package pharmaracist.fathom

import android.Manifest
import android.app.Activity
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FathomDownloadsPlugin(private var activity: Activity?) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "pharmaracist.fathom/downloads"
        private const val PERMISSION_REQUEST = 4711
        private const val SUBDIR = "Fathom"

        private val MIME_BY_EXT = mapOf(
            "m4a" to "audio/mp4",
            "mp4" to "audio/mp4",
            "webm" to "audio/webm",
            "opus" to "audio/opus",
            "ogg" to "audio/ogg",
        )
    }

    private var heldCall: MethodCall? = null
    private var heldResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveAudio" -> saveAudio(call, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return

        val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        val call = heldCall
        val result = heldResult
        heldCall = null
        heldResult = null

        if (call == null || result == null) return
        if (granted) {
            copyToMediaStore(call, result)
        } else {
            result.error(
                "permission",
                "Storage access is needed to save music on this device",
                null,
            )
        }
    }

    private fun saveAudio(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("path")?.let { File(it) }
        if (source == null || !source.exists()) {
            result.error("missing", "The downloaded file is gone", null)
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            hasWritePermission()
        ) {
            copyToMediaStore(call, result)
            return
        }

        if (heldResult != null) {
            source.delete()
            result.error("busy", "Another save is still running", null)
            return
        }

        heldCall = call
        heldResult = result
        activity?.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            PERMISSION_REQUEST,
        ) ?: run {
            heldCall = null
            heldResult = null
            source.delete()
            result.error("permission", "No activity to ask for storage access", null)
        }
    }

    private fun copyToMediaStore(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("path")?.let { File(it) }
        val artworkPath = call.argument<String>("artworkPath")?.let { File(it) }
        val title = call.argument<String>("title").orEmpty()
        val artist = call.argument<String>("artist").orEmpty()

        if (source == null || !source.exists()) {
            result.error("missing", "The downloaded file is gone", null)
            return
        }

        try {
            val id = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveViaMediaStore(source, artworkPath, title, artist)
            } else {
                saveLegacy(source, artworkPath, title, artist)
            }
            source.delete()
            result.success(id)
        } catch (e: Exception) {
            source.delete()
            result.error("save", e.message ?: "Could not file the audio", null)
        }
    }

    private fun saveViaMediaStore(
        source: File,
        artworkPath: File?,
        title: String,
        artist: String
    ): Long {
        val resolver = context().contentResolver

        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayNameFor(source, title))
            put(MediaStore.Audio.Media.MIME_TYPE, mimeFor(source.name))
            put(MediaStore.Audio.Media.TITLE, title.ifBlank { source.nameWithoutExtension })
            put(MediaStore.Audio.Media.ARTIST, artist.ifBlank { "Unknown Artist" })
            put(MediaStore.Audio.Media.ALBUM, "Fathom")
            put(
                MediaStore.Audio.Media.RELATIVE_PATH,
                Environment.DIRECTORY_MUSIC + File.separator + SUBDIR,
            )
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }

        val collection = MediaStore.Audio.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val item = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused the entry")

        try {
            resolver.openOutputStream(item)?.use { out ->
                source.inputStream().use { it.copyTo(out) }
            }
        } catch (e: Exception) {
            resolver.delete(item, null, null)
            throw e
        }

        val publish = ContentValues().apply {
            put(MediaStore.Audio.Media.IS_PENDING, 0)
            put(MediaStore.Audio.Media.TITLE, title.ifBlank { source.nameWithoutExtension })
            put(MediaStore.Audio.Media.ARTIST, artist.ifBlank { "Unknown Artist" })
            put(MediaStore.Audio.Media.ALBUM, "Fathom")
        }
        resolver.update(item, publish, null, null)

        val id = ContentUris.parseId(item)

        if (artworkPath != null && artworkPath.exists()) {
            attachArtwork(id, artworkPath)
        }

        return id
    }

    private fun saveLegacy(
        source: File,
        artworkPath: File?,
        title: String,
        artist: String
    ): Long {
        val root = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_MUSIC,
        )
        val dir = File(root, SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create ${dir.absolutePath}")
        }

        val target = File(dir, displayNameFor(source, title))
        source.copyTo(target, overwrite = true)

        MediaScannerConnection.scanFile(
            context(),
            arrayOf(target.absolutePath),
            arrayOf(mimeFor(target.name)),
            null,
        )

        return -1L
    }

    private fun attachArtwork(audioId: Long, artworkPath: File) {
        try {
            val resolver = context().contentResolver
            val albumId = getAlbumId(audioId) ?: return
            val artworkUri = Uri.parse("content://media/external/audio/albumart")

            resolver.delete(ContentUris.withAppendedId(artworkUri, albumId), null, null)

            val values = ContentValues().apply {
                put("album_id", albumId)
            }

            val insertedUri = resolver.insert(artworkUri, values) ?: return
            resolver.openOutputStream(insertedUri)?.use { out ->
                artworkPath.inputStream().use { it.copyTo(out) }
            }
        } catch (_: Exception) {
        }
    }

    private fun getAlbumId(audioId: Long): Long? {
        val resolver = context().contentResolver
        val uri = ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            audioId
        )
        val projection = arrayOf(MediaStore.Audio.Media.ALBUM_ID)
        resolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
                if (index != -1) return cursor.getLong(index)
            }
        }
        return null
    }

    private fun displayNameFor(source: File, title: String): String {
        val ext = source.name.substringAfterLast('.', "m4a")
        val base = title.ifBlank { source.nameWithoutExtension }
            .replace(Regex("""[\\/:*?"<>|]"""), " ")
            .trim()
            .take(120)
        return if (base.isEmpty()) "fathom.$ext" else "$base.$ext"
    }

    private fun mimeFor(name: String): String =
        MIME_BY_EXT[name.substringAfterLast('.', "").lowercase()] ?: "audio/mp4"

    private fun context(): Context =
        checkNotNull(activity) { "FathomDownloadsPlugin has no activity" }

    private fun hasWritePermission(): Boolean {
        val ctx = activity ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            ctx.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                    PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }
}
