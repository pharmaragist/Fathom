package pharmaracist.fathom

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.OutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer

/**
 * Rewrites the `moov` box of an MP4/M4A file so it carries the track's title,
 * artist, album and cover art, without touching the audio.
 *
 * This is a box rewrite, not a remux and not a re-encode: the sample data is
 * copied byte for byte and only `moov/udta/meta/ilst` is replaced, plus the
 * offset tables that describe where the copied data landed. That matters for
 * two reasons. The file stays the same codec/container, so no decoder or
 * muxer is involved, and a downloaded AAC track keeps the container it was
 * written in.
 *
 * [plan] does the whole analysis first and returns null when the file cannot
 * be rewritten safely. A plan that is returned already knows the new byte
 * positions, so [Plan.writeTo] only copies. The download plugin uses that to
 * write the tagged file straight into the MediaStore output stream: one pass
 * over the audio instead of a tagged temporary followed by a second copy.
 *
 * Files with a `mfra` index are refused. Its `tfra` entries store absolute
 * `moof` offsets that this writer does not patch, and a wrong index is worse
 * than a file without tags — the audio still plays and MediaStore still has
 * the row's columns.
 */
object Mp4Tagger {

    /**
     * Matches the cap on the movie box the writer keeps in memory. A `moov`
     * this large carries sample tables, not audio, and is far beyond anything
     * a music file produces; refusing it keeps a malformed file from taking
     * the download worker down with an allocation failure.
     */
    private const val MAX_MOOV_BYTES = 32L * 1024 * 1024

    private const val COPY_BUFFER_BYTES = 256 * 1024

    /**
     * `traf` is here so the same walker can patch fragment headers; the chunk
     * table walk simply finds nothing inside it.
     */
    private val containers = setOf("trak", "mdia", "minf", "stbl", "traf")

    private class Box(val type: String, val start: Long, val size: Long, val header: Int)

    private class Child(
        val type: String,
        val start: Int,
        val header: Int,
        val size: Int,
    ) {
        val payload: Int get() = start + header
        val end: Int get() = start + size
    }

    /** The analysed rewrite: everything [writeTo] needs, and nothing to decide. */
    class Plan internal constructor(
        private val source: File,
        private val moovStart: Long,
        private val moovEnd: Long,
        private val newMoov: ByteArray,
        private val delta: Int,
    ) {
        /**
         * Copies the file to [out] with the new `moov` in place.
         *
         * [delta] is how much the movie box grew (or shrank). When it is not
         * zero the tail has moved, so each `moof` is read and its absolute
         * `tfhd` base offsets — when the file uses them — are adjusted before
         * being written. Fragments that address their data relative to the
         * `moof` need no adjustment, and moving the whole tail together keeps
         * `sidx` and `trun` offsets valid.
         */
        fun writeTo(out: OutputStream) {
            RandomAccessFile(source, "r").use { input ->
                copyRange(input, 0, moovStart, out)
                out.write(newMoov)

                val length = input.length()
                if (delta == 0) {
                    copyRange(input, moovEnd, length, out)
                    return
                }

                var position = moovEnd
                while (position + 8 <= length) {
                    input.seek(position)
                    val head = ByteArray(8)
                    input.readFully(head)
                    val buffer = ByteBuffer.wrap(head)
                    var size = buffer.int.toLong() and 0xFFFFFFFFL
                    val type = String(head, 4, 4, Charsets.ISO_8859_1)
                    var header = 8
                    if (size == 1L) {
                        size = input.readLong()
                        header = 16
                    } else if (size == 0L) {
                        size = length - position
                    }
                    if (size < header || position + size > length) {
                        // The layout stopped making sense. Copy what is left
                        // unchanged: a missing offset patch is a player bug,
                        // while dropping bytes would be a broken file.
                        copyRange(input, position, length, out)
                        return
                    }

                    if (type == "moof") {
                        if (size > Int.MAX_VALUE) {
                            copyRange(input, position, length, out)
                            return
                        }
                        val moof = ByteArray(size.toInt())
                        input.seek(position)
                        input.readFully(moof)
                        patchFragmentOffsets(moof, header, delta)
                        out.write(moof)
                    } else {
                        copyRange(input, position, position + size, out)
                    }
                    position += size
                }
                if (position < length) copyRange(input, position, length, out)
            }
        }
    }

    /**
     * Prepares a tagged rewrite of [source], or returns null when the file is
     * not an MP4 whose movie box can be rewritten safely.
     *
     * Nothing is written here, so a caller can fall back to a plain copy after
     * a null without having polluted the output.
     */
    fun plan(
        source: File,
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): Plan? = try {
        analyse(source, title, artist, album, cover)
    } catch (_: Exception) {
        null
    }

    /** Tagged copy of [source] at [target], kept for callers that want a file. */
    fun tag(
        source: File,
        target: File,
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): Boolean {
        val plan = plan(source, title, artist, album, cover) ?: return false
        return try {
            target.outputStream().buffered().use { plan.writeTo(it) }
            true
        } catch (_: Exception) {
            target.delete()
            false
        }
    }

    private fun analyse(
        source: File,
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): Plan? {
        RandomAccessFile(source, "r").use { input ->
            val length = input.length()
            val top = readBoxes(input, 0, length)

            // A fragment index stores absolute moof offsets. This writer does
            // not patch tfra, so leave the file alone rather than hand a player
            // an index that points into the middle of a box.
            if (top.any { it.type == "mfra" }) return null

            val moov = top.firstOrNull { it.type == "moov" } ?: return null
            if (moov.header != 8 || moov.size <= 8 || moov.size > MAX_MOOV_BYTES) {
                return null
            }

            val body = ByteArray((moov.size - 8).toInt())
            input.seek(moov.start + 8)
            input.readFully(body)

            val children = readBoxes(body, 0, body.size)
            // YouTube's own m4a already has moov/udta/meta/ilst (it carries
            // the encoder tag). The old writer refused that shape and filed
            // every download untagged, which is why MediaStore fell back to
            // the filename. The existing box is replaced, not duplicated:
            // two udta boxes leave players free to read the stale one.
            val existing = children.firstOrNull { it.type == "udta" }
            val udta = buildUdta(title, artist, album, cover)
            val newBody = ByteArray(body.size - (existing?.size ?: 0) + udta.size)

            var at = 0
            for (child in children) {
                if (existing != null && child.start == existing.start) continue
                System.arraycopy(body, child.start, newBody, at, child.size)
                at += child.size
            }
            System.arraycopy(udta, 0, newBody, at, udta.size)

            val delta = newBody.size - body.size
            val mediaAfterMoov = top.any {
                (it.type == "mdat" || it.type == "moof") && it.start > moov.start
            }
            if (delta != 0 && mediaAfterMoov) {
                if (!shiftChunkOffsets(newBody, delta)) return null
            }

            val newSize = newBody.size + 8L
            if (newSize > 0xFFFFFFFFL) return null

            val newMoov =
                int32(newSize) + "moov".toByteArray(Charsets.ISO_8859_1) + newBody
            return Plan(source, moov.start, moov.start + moov.size, newMoov, delta)
        }
    }

    private fun readBoxes(input: RandomAccessFile, from: Long, to: Long): List<Box> {
        val boxes = ArrayList<Box>()
        var position = from
        val head = ByteArray(8)
        while (position + 8 <= to) {
            input.seek(position)
            input.readFully(head)
            val buffer = ByteBuffer.wrap(head)
            var size = buffer.int.toLong() and 0xFFFFFFFFL
            val type = String(head, 4, 4, Charsets.ISO_8859_1)
            var header = 8
            if (size == 1L) {
                size = input.readLong()
                header = 16
            } else if (size == 0L) {
                size = to - position
            }
            if (size < header || position + size > to) break
            boxes.add(Box(type, position, size, header))
            position += size
        }
        return boxes
    }

    private fun readBoxes(data: ByteArray, from: Int, to: Int): List<Child> {
        val boxes = ArrayList<Child>()
        var position = from
        while (position + 8 <= to) {
            var size = (intAt(data, position).toLong() and 0xFFFFFFFFL)
            val type = String(data, position + 4, 4, Charsets.ISO_8859_1)
            var header = 8
            if (size == 1L) {
                if (position + 16 > to) break
                size = longAt(data, position + 8)
                header = 16
            } else if (size == 0L) {
                size = (to - position).toLong()
            }
            if (size < header || position + size > to) break
            boxes.add(Child(type, position, header, size.toInt()))
            position += size.toInt()
        }
        return boxes
    }

    private fun walk(data: ByteArray, from: Int, to: Int, visit: (Child) -> Unit) {
        for (child in readBoxes(data, from, to)) {
            visit(child)
            if (child.type in containers) {
                walk(data, child.payload, child.end, visit)
            }
        }
    }

    /**
     * Adds [delta] to every absolute chunk offset inside [body].
     *
     * These tables live in `stbl` and point at `mdat`. They only need moving
     * when the media data sits after the movie box, which the caller checks.
     * A table that no longer fits in 32 bits means the rewrite would corrupt
     * the file, so the whole plan is refused.
     */
    private fun shiftChunkOffsets(body: ByteArray, delta: Int): Boolean {
        var valid = true
        walk(body, 0, body.size) { child ->
            if (valid && (child.type == "stco" || child.type == "co64")) {
                valid = shiftTable(body, child, delta)
            }
        }
        return valid
    }

    private fun shiftTable(body: ByteArray, child: Child, delta: Int): Boolean {
        val count = intAt(body, child.payload + 4)
        if (count < 0) return false
        var at = child.payload + 8
        for (i in 0 until count) {
            if (child.type == "stco") {
                if (at + 4 > child.end) return false
                val value = (intAt(body, at).toLong() and 0xFFFFFFFFL) + delta
                if (value < 0 || value > 0xFFFFFFFFL) return false
                putInt(body, at, value.toInt())
                at += 4
            } else {
                if (at + 8 > child.end) return false
                val value = longAt(body, at) + delta
                if (value < 0) return false
                putLong(body, at, value)
                at += 8
            }
        }
        return true
    }

    /**
     * Adjusts `tfhd` base-data-offset values in one fragment.
     *
     * Most DASH audio uses `default-base-is-moof` (0x020000) and stores no
     * absolute base, so this is a no-op for it. When the flag is absent the
     * eight-byte base after `track_ID` is absolute, and growing `moov` moves
     * it by [delta].
     */
    private fun patchFragmentOffsets(moof: ByteArray, header: Int, delta: Int) {
        if (moof.size < header) return
        walk(moof, header, moof.size) { child ->
            if (child.type == "tfhd") {
                val flags = intAt(moof, child.payload) and 0xFFFFFF
                if (flags and 0x1 != 0) {
                    val at = child.payload + 8
                    if (at + 8 <= child.end) {
                        val value = longAt(moof, at) + delta
                        if (value >= 0) putLong(moof, at, value)
                    }
                }
            }
        }
    }

    private fun copyRange(
        input: RandomAccessFile,
        from: Long,
        to: Long,
        out: OutputStream,
    ) {
        input.seek(from)
        val chunk = ByteArray(COPY_BUFFER_BYTES)
        var remaining = to - from
        while (remaining > 0) {
            val read = input.read(chunk, 0, minOf(chunk.size.toLong(), remaining).toInt())
            if (read < 0) break
            out.write(chunk, 0, read)
            remaining -= read
        }
    }

    /**
     * Re-encodes [cover] as JPEG, or returns null when it is not an image.
     *
     * A `covr` data atom names its format in the flags, and players trust that
     * flag over the bytes. The old writer labelled everything that was not PNG
     * as JPEG, so a WebP thumbnail — which is what a ytimg `webp` URL serves —
     * was embedded as "JPEG": readers reported no image at all and the cover
     * showed as broken. Decoding and re-encoding makes the flag true, and bytes
     * that cannot be decoded are dropped rather than mislabelled.
     *
     * The caller runs on the download worker thread, so a full-size cover is
     * decoded and compressed off the main thread.
     */
    fun coverJpeg(cover: ByteArray?): ByteArray? {
        if (cover == null || cover.isEmpty()) return null
        val bitmap = try {
            BitmapFactory.decodeByteArray(cover, 0, cover.size)
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        } ?: return null

        return try {
            val out = ByteArrayOutputStream()
            if (bitmap.compress(Bitmap.CompressFormat.JPEG, 92, out)) {
                out.toByteArray().takeIf { it.isNotEmpty() }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        } catch (_: OutOfMemoryError) {
            null
        } finally {
            bitmap.recycle()
        }
    }

    private fun buildUdta(
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): ByteArray {
        val items = java.io.ByteArrayOutputStream()
        if (title.isNotBlank()) items.write(textItem("\u00A9nam", title))
        if (artist.isNotBlank()) {
            items.write(textItem("\u00A9ART", artist))
            items.write(textItem("aART", artist))
        }
        if (album.isNotBlank()) items.write(textItem("\u00A9alb", album))
        // No cover at all is better than one whose declared type is a lie: a
        // reader that cannot decode the bytes shows a broken square, and every
        // later copy keeps the same wrong flag.
        val jpeg = coverJpeg(cover)
        if (jpeg != null) {
            items.write(box("covr", dataAtom(13, jpeg)))
        }

        val hdlr = box(
            "hdlr",
            byteArrayOf(0, 0, 0, 0) +
                    byteArrayOf(0, 0, 0, 0) +
                    "mdir".toByteArray(Charsets.ISO_8859_1) +
                    "appl".toByteArray(Charsets.ISO_8859_1) +
                    ByteArray(8) +
                    byteArrayOf(0),
        )
        val ilst = box("ilst", items.toByteArray())
        val meta = box("meta", byteArrayOf(0, 0, 0, 0) + hdlr + ilst)
        return box("udta", meta)
    }

    private fun textItem(type: String, value: String): ByteArray =
        box(type, dataAtom(1, value.toByteArray(Charsets.UTF_8)))

    private fun dataAtom(flags: Int, payload: ByteArray): ByteArray =
        box("data", int32(flags.toLong()) + ByteArray(4) + payload)

    private fun box(type: String, payload: ByteArray): ByteArray =
        int32(8L + payload.size) + type.toByteArray(Charsets.ISO_8859_1) + payload

    private fun int32(value: Long): ByteArray =
        ByteBuffer.allocate(4).putInt(value.toInt()).array()

    private fun intAt(data: ByteArray, at: Int): Int =
        ((data[at].toInt() and 0xFF) shl 24) or
                ((data[at + 1].toInt() and 0xFF) shl 16) or
                ((data[at + 2].toInt() and 0xFF) shl 8) or
                (data[at + 3].toInt() and 0xFF)

    private fun longAt(data: ByteArray, at: Int): Long =
        (intAt(data, at).toLong() shl 32) or
                (intAt(data, at + 4).toLong() and 0xFFFFFFFFL)

    private fun putInt(data: ByteArray, at: Int, value: Int) {
        data[at] = (value ushr 24).toByte()
        data[at + 1] = (value ushr 16).toByte()
        data[at + 2] = (value ushr 8).toByte()
        data[at + 3] = value.toByte()
    }

    private fun putLong(data: ByteArray, at: Int, value: Long) {
        putInt(data, at, (value ushr 32).toInt())
        putInt(data, at + 4, value.toInt())
    }
}
