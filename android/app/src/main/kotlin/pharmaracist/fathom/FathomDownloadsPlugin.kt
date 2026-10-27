package pharmaracist.fathom

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FathomDownloadsPlugin(private var activity: Activity?) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "pharmaracist.fathom/downloads"
        private const val PERMISSION_REQUEST = 4711
        private const val NOTIFICATION_PERMISSION_REQUEST = 4712
        private const val SUBDIR = "Fathom"
        private const val NOTIFICATION_CHANNEL_ID = "fathom_downloads"
        private const val NOTIFICATION_CHANNEL_NAME = "Downloads"
        private const val NOTIFICATION_ID_BASE = 200000

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
    private var heldPermissionResult: MethodChannel.Result? = null
    private val activeNotifications = mutableMapOf<String, Int>()

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Download progress notifications"
            }
            val manager = context().getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveAudio" -> saveAudio(call, result)
            "startDownloadNotification" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val title = call.argument<String>("title") ?: ""
                startDownloadNotification(videoId, title)
                result.success(null)
            }
            "updateDownloadProgress" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val title = call.argument<String>("title") ?: ""
                val progress = call.argument<Int>("progress") ?: 0
                updateDownloadProgress(videoId, title, progress)
                result.success(null)
            }
            "completeDownloadNotification" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                val title = call.argument<String>("title") ?: ""
                completeDownloadNotification(videoId, title)
                result.success(null)
            }
            "cancelDownloadNotification" -> {
                val videoId = call.argument<String>("videoId") ?: ""
                cancelDownloadNotification(videoId)
                result.success(null)
            }
            "requestNotificationPermission" -> requestNotificationPermission(call, result)
            else -> result.notImplemented()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == PERMISSION_REQUEST) {
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
            return
        }

        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            val res = heldPermissionResult
            heldPermissionResult = null
            res?.success(granted)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            val res = heldPermissionResult
            heldPermissionResult = null
            res?.success(granted)
            return
        }
        onRequestPermissionsResult(requestCode, emptyArray(), grantResults)
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

    /**
     * Files a finished download.
     *
     * The transfer already happened on a Dart isolate; what is left is a read
     * and write of the whole audio (tagging plus the MediaStore copy), so it
     * runs on a worker instead of the platform channel's main thread. The
     * result is posted back on the main looper.
     */
    private fun copyToMediaStore(call: MethodCall, result: MethodChannel.Result) {
        val source = call.argument<String>("path")?.let { File(it) }
        val artworkPath = call.argument<String>("artworkPath")?.let { File(it) }
        val title = call.argument<String>("title").orEmpty()
        val artist = call.argument<String>("artist").orEmpty()
        val album = call.argument<String>("album").orEmpty().ifBlank { "Fathom" }
        val durationMs = call.argument<Number>("durationMs")?.toLong() ?: 0L

        if (source == null || !source.exists()) {
            result.error("missing", "The downloaded file is gone", null)
            return
        }

        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                val id = fileDownload(source, artworkPath, title, artist, album, durationMs)
                main.post { result.success(id) }
            } catch (e: Exception) {
                source.delete()
                main.post {
                    result.error("save", e.message ?: "Could not file the audio", null)
                }
            }
        }.apply {
            name = "fathom-save"
            isDaemon = true
        }.start()
    }

    private fun fileDownload(
        source: File,
        artworkPath: File?,
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
    ): Long {
        // Cover art is a nicety: a file that cannot be read or tagged with it
        // must still be saved, so a failed read falls back to no cover. The
        // bytes are normalised once here, so the tag and the album-art row are
        // written from the same JPEG rather than a WebP that the tagger would
        // have to mislabel or the album-art provider might refuse.
        val cover = try {
            Mp4Tagger.coverJpeg(
                artworkPath?.takeIf { it.exists() }?.readBytes(),
            )
        } catch (_: Exception) {
            null
        }
        val id = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveViaMediaStore(source, title, artist, album, durationMs, cover)
        } else {
            saveLegacy(source, title, artist, album, durationMs, cover)
        }
        // An image that would not decode is not written anywhere: the tag is
        // skipped and the album-art row with it.
        if (id >= 0 && cover != null) {
            attachArtwork(id, cover)
        }
        source.delete()
        return id
    }

    /**
     * The store-facing description of the file.
     *
     * MediaStore treats these audio columns as a view of the file's own tags:
     * when a pending item is published the provider scans the new file, and a
     * file it cannot read tags from is described by its display name. The same
     * values are therefore written on insert, on publish, and once more after
     * the publish scan, so a row cannot be left saying "song.m4a".
     */
    private fun metadataFor(
        source: File,
        title: String,
        artist: String,
        album: String,
    ): ContentValues = ContentValues().apply {
        put(MediaStore.Audio.Media.TITLE, title.ifBlank { source.nameWithoutExtension })
        put(MediaStore.Audio.Media.ARTIST, artist.ifBlank { "Unknown Artist" })
        put(MediaStore.Audio.Media.ALBUM_ARTIST, artist.ifBlank { "Unknown Artist" })
        put(MediaStore.Audio.Media.ALBUM, album.ifBlank { "Fathom" })
    }

    private fun saveViaMediaStore(
        source: File,
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        cover: ByteArray?,
    ): Long {
        val resolver = context().contentResolver

        val values = metadataFor(source, title, artist, album).apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, displayNameFor(source, title))
            put(MediaStore.Audio.Media.MIME_TYPE, mimeFor(source.name))
            put(
                MediaStore.Audio.Media.RELATIVE_PATH,
                Environment.DIRECTORY_MUSIC + File.separator + SUBDIR,
            )
            put(MediaStore.Audio.Media.IS_PENDING, 1)
            if (durationMs > 0) put(MediaStore.Audio.Media.DURATION, durationMs)
        }

        val collection = MediaStore.Audio.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY,
        )
        val item = resolver.insert(collection, values)
            ?: throw IllegalStateException("MediaStore refused the entry")

        try {
            // The tag pass writes into the same output stream as the copy, so
            // the audio is written once and no tagged temporary is produced.
            // A null plan means this writer cannot tag the container (webm, or
            // an mp4 with an absolute fragment index); the bytes are still
            // saved untouched and the row carries the description above.
            val plan = if (isMp4(source)) {
                Mp4Tagger.plan(source, title, artist, album, cover)
            } else {
                null
            }
            resolver.openOutputStream(item)?.use { out ->
                if (plan != null) {
                    plan.writeTo(out)
                } else {
                    source.inputStream().use { it.copyTo(out) }
                }
            } ?: throw IllegalStateException("MediaStore refused the file")
        } catch (e: Exception) {
            resolver.delete(item, null, null)
            throw e
        }

        val publish = metadataFor(source, title, artist, album).apply {
            put(MediaStore.Audio.Media.IS_PENDING, 0)
            if (durationMs > 0) put(MediaStore.Audio.Media.DURATION, durationMs)
        }
        resolver.update(item, publish, null, null)
        // Publishing is what makes MediaProvider scan the file. Write the
        // description once more after it: the scan may have replaced the
        // columns with what it could read, and this row must not regress to
        // the file name when the tag writer had to be skipped.
        resolver.update(item, metadataFor(source, title, artist, album), null, null)

        return ContentUris.parseId(item)
    }

    private fun saveLegacy(
        source: File,
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        cover: ByteArray?,
    ): Long {
        val root = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_MUSIC,
        )
        val dir = File(root, SUBDIR)
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create ${dir.path}")
        }

        val target = File(dir, displayNameFor(source, title))
        // The same rewrite as the MediaStore path: below API 29 the row holds
        // the columns, but the file itself is what survives a rescan, so it
        // carries the tags too.
        val plan = if (isMp4(source)) {
            Mp4Tagger.plan(source, title, artist, album, cover)
        } else {
            null
        }
        try {
            if (plan != null) {
                target.outputStream().buffered().use { plan.writeTo(it) }
            } else {
                source.copyTo(target, overwrite = true)
            }
        } catch (e: Exception) {
            target.delete()
            throw e
        }

        // Below API 29 there is no pending row to publish, so the row itself is
        // the only description of the file. Inserting it directly writes the
        // equivalent columns; scanning alone would leave title and artist to
        // the scanner, which fills them from the file name when it finds no
        // tags.
        val values = metadataFor(source, title, artist, album).apply {
            put(MediaStore.Audio.Media.DATA, target.path)
            put(MediaStore.Audio.Media.DISPLAY_NAME, target.name)
            put(MediaStore.Audio.Media.MIME_TYPE, mimeFor(target.name))
            put(MediaStore.Audio.Media.SIZE, target.length())
            if (durationMs > 0) put(MediaStore.Audio.Media.DURATION, durationMs)
        }
        val uri = try {
            context().contentResolver.insert(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                values,
            )
        } catch (_: Exception) {
            null
        }
        if (uri != null) return ContentUris.parseId(uri)

        // An older provider can refuse a row without a scan; a scanned row is
        // still better than no record at all.
        MediaScannerConnection.scanFile(
            context(),
            arrayOf(target.path),
            arrayOf(mimeFor(target.name)),
            null,
        )
        return -1L
    }

    private fun isMp4(file: File): Boolean {
        val extension = file.extension.lowercase()
        return extension == "m4a" || extension == "mp4"
    }

    private fun attachArtwork(audioId: Long, artwork: ByteArray) {
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
                out.write(artwork)
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

    private fun getNotificationManager(): NotificationManager {
        val ctx = context()
        return ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    }

    private fun getNotificationId(videoId: String): Int {
        val id = activeNotifications.getOrPut(videoId) {
            (NOTIFICATION_ID_BASE + Math.abs(videoId.hashCode().toLong())).toInt() % 100000 + NOTIFICATION_ID_BASE
        }
        return id
    }

    private fun startDownloadNotification(videoId: String, title: String) {
        createNotificationChannel()
        val ctx = context()
        val notificationId = getNotificationId(videoId)

        val builder = NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title.ifEmpty { "Downloading" })
            .setContentText("Downloading...")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, 0, true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)

        getNotificationManager().notify(notificationId, builder.build())
    }

    private fun updateDownloadProgress(videoId: String, title: String, progress: Int) {
        createNotificationChannel()
        val ctx = context()
        val notificationId = getNotificationId(videoId)
        val clamped = progress.coerceIn(0, 100)

        val builder = NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title.ifEmpty { "Downloading" })
            .setContentText("$clamped%")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, clamped, false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)

        getNotificationManager().notify(notificationId, builder.build())
    }

    private fun completeDownloadNotification(videoId: String, title: String) {
        createNotificationChannel()
        val ctx = context()
        val notificationId = getNotificationId(videoId)

        val builder = NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title.ifEmpty { "Download complete" })
            .setContentText("Download complete")
            .setOngoing(false)
            .setAutoCancel(true)
            .setProgress(0, 0, false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_STATUS)

        getNotificationManager().notify(notificationId, builder.build())
        activeNotifications.remove(videoId)
    }

    private fun cancelDownloadNotification(videoId: String) {
        val notificationId = activeNotifications.remove(videoId) ?: ((NOTIFICATION_ID_BASE + Math.abs(videoId.hashCode().toLong())).toInt() % 100000 + NOTIFICATION_ID_BASE)
        getNotificationManager().cancel(notificationId)
    }

    private fun requestNotificationPermission(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (heldPermissionResult != null) {
            result.error("busy", "Another permission request is running", null)
            return
        }
        if (ContextCompat.checkSelfPermission(
                context(),
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        heldPermissionResult = result
        activity?.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        ) ?: run {
            heldPermissionResult = null
            result.success(false)
        }
    }
}
