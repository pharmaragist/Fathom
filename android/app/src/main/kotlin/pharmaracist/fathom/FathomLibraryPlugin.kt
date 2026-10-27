package pharmaracist.fathom

import android.app.Activity
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Deletes audio files from the shared media store.
 *
 * The MediaStore owns the rows, so a delete is a request to the provider rather
 * than a file operation Fathom performs itself. On Android 11 and later a file
 * the app does not own needs the system's own delete confirmation; that dialog
 * is launched from here and its answer is held with the Dart call, so Dart sees
 * one completed operation rather than a permission request it would have to
 * track.
 */
class FathomLibraryPlugin(private var activity: Activity?) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "pharmaracist.fathom/library"
        private const val DELETE_REQUEST = 4811
        private val COLLECTION: Uri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
    }

    private var heldResult: MethodChannel.Result? = null
    private var heldUris: List<Uri> = emptyList()
    private var deletedBeforeDialog: MutableSet<Int> = mutableSetOf()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deleteTracks" -> deleteTracks(call, result)
            else -> result.notImplemented()
        }
    }

    private fun deleteTracks(call: MethodCall, result: MethodChannel.Result) {
        if (heldResult != null) {
            result.error("busy", "Another delete is still running", null)
            return
        }

        val ids = call.argument<List<Int>>("ids").orEmpty()
            .filter { it >= 0 }
            .distinct()
        if (ids.isEmpty()) {
            result.success(emptyList<Int>())
            return
        }

        val uris = ids.map { ContentUris.withAppendedId(COLLECTION, it.toLong()) }
        val (deleted, failed) = deleteNow(uris)
        if (failed.isEmpty()) {
            result.success(deleted.toList())
            return
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // Below Android 11 there is no batch delete confirmation to show.
            // Report what was actually removed instead of pretending the rest
            // succeeded; the caller leaves those rows selected.
            result.success(deleted.toList())
            return
        }

        val currentActivity = activity
        if (currentActivity == null) {
            result.error("delete", "No activity to ask for delete access", null)
            return
        }

        heldResult = result
        heldUris = failed
        deletedBeforeDialog = deleted

        try {
            val request = MediaStore.createDeleteRequest(
                currentActivity.contentResolver,
                failed,
            )
            currentActivity.startIntentSenderForResult(
                request.intentSender,
                DELETE_REQUEST,
                null,
                0,
                0,
                0,
            )
        } catch (e: Exception) {
            clearHeld()
            result.error("delete", e.message ?: "Could not ask to delete", null)
        }
    }

    /**
     * Deletes [uris] and returns the ids that are now gone.
     *
     * A provider can refuse some rows for ownership reasons; those are what the
     * system confirmation is for. A row whose delete reports zero rows may
     * already have been removed by the confirmation dialog, so [isGone] is the
     * authority after the dialog rather than the delete count alone.
     */
    private fun deleteNow(uris: List<Uri>): Pair<MutableSet<Int>, List<Uri>> {
        val deleted = mutableSetOf<Int>()
        val failed = mutableListOf<Uri>()
        val resolver = activity?.contentResolver ?: return deleted to uris

        for (uri in uris) {
            val id = uri.lastPathSegment?.toIntOrNull()
            try {
                val rows = resolver.delete(uri, null, null)
                if (rows > 0 && id != null) {
                    deleted.add(id)
                } else {
                    failed.add(uri)
                }
            } catch (_: SecurityException) {
                failed.add(uri)
            } catch (_: Exception) {
                failed.add(uri)
            }
        }
        return deleted to failed
    }

    private fun goneAfterDialog(uris: List<Uri>): Set<Int> {
        val resolver = activity?.contentResolver
        val gone = mutableSetOf<Int>()
        if (resolver == null) return gone

        for (uri in uris) {
            val id = uri.lastPathSegment?.toIntOrNull() ?: continue
            try {
                resolver.query(uri, arrayOf(MediaStore.Audio.Media._ID), null, null, null)
                    ?.use { cursor ->
                        if (!cursor.moveToFirst()) gone.add(id)
                    }
            } catch (_: Exception) {
                // A provider that cannot be queried is not proof the row is
                // gone, so it is left out of the success list.
            }
        }
        return gone
    }

    /**
     * Forwards the system delete dialog's answer.
     *
     * MainActivity calls this from its own `onActivityResult`; returning true
     * means the result belonged to this plugin.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != DELETE_REQUEST) return false

        val result = heldResult
        val uris = heldUris
        val before = deletedBeforeDialog
        clearHeld()
        if (result == null) return true

        if (resultCode == Activity.RESULT_OK) {
            val (deleted, _) = deleteNow(uris)
            before.addAll(deleted)
            // The confirmation may have removed the rows before the retry.
            before.addAll(goneAfterDialog(uris))
        }

        result.success(before.toList())
        return true
    }

    private fun clearHeld() {
        heldResult = null
        heldUris = emptyList()
        deletedBeforeDialog = mutableSetOf()
    }
}
