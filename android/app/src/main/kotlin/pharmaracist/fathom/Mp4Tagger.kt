package pharmaracist.fathom

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer

object Mp4Tagger {

    private class Box(val type: String, val start: Long, val size: Long, val header: Int)

    private val containers = setOf("trak", "mdia", "minf", "stbl")

    fun tag(
        source: File,
        target: File,
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): Boolean {
        return try {
            val done = write(source, target, title, artist, album, cover)
            if (!done) target.delete()
            done
        } catch (e: Exception) {
            target.delete()
            false
        }
    }

    private fun write(
        source: File,
        target: File,
        title: String,
        artist: String,
        album: String,
        cover: ByteArray?,
    ): Boolean {
        RandomAccessFile(source, "r").use { input ->
            val length = input.length()
            val top = readBoxes(input, 0, length)
            if (top.any { it.type == "mfra" }) return false

            val moov = top.firstOrNull { it.type == "moov" } ?: return false
            if (moov.header != 8) return false

            val moovChildren = readBoxes(input, moov.start + 8, moov.start + moov.size)
            if (moovChildren.any { it.type == "udta" }) return false

            val udta = buildUdta(title, artist, album, cover)
            val delta = udta.size.toLong()

            val bodyBase = moov.start + 8
            val body = ByteArray((moov.size - 8).toInt())
            input.seek(bodyBase)
            input.readFully(body)

            val mdatAfter = top.any { it.type == "mdat" && it.start > moov.start }
            if (mdatAfter) {
                val tables = ArrayList<Box>()
                collectChunkTables(input, moovChildren, tables)
                for (table in tables) {
                    if (!shift(body, (table.start + table.header - bodyBase).toInt(), table.type, delta)) {
                        return false
                    }
                }
            }

            target.outputStream().buffered().use { out ->
                copyRange(input, 0, moov.start, out)
                out.write(int32(moov.size + delta))
                out.write("moov".toByteArray(Charsets.ISO_8859_1))
                out.write(body)
                out.write(udta)
                copyRange(input, moov.start + moov.size, length, out)
            }
        }
        return true
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

    private fun collectChunkTables(
        input: RandomAccessFile,
        boxes: List<Box>,
        into: MutableList<Box>,
    ) {
        for (box in boxes) {
            when {
                box.type == "stco" || box.type == "co64" -> into.add(box)
                box.type in containers -> collectChunkTables(
                    input,
                    readBoxes(input, box.start + box.header, box.start + box.size),
                    into,
                )
            }
        }
    }

    private fun shift(body: ByteArray, payload: Int, type: String, delta: Long): Boolean {
        val buffer = ByteBuffer.wrap(body)
        val count = buffer.getInt(payload + 4)
        var at = payload + 8
        for (i in 0 until count) {
            if (type == "stco") {
                val value = (buffer.getInt(at).toLong() and 0xFFFFFFFFL) + delta
                if (value > 0xFFFFFFFFL) return false
                buffer.putInt(at, value.toInt())
                at += 4
            } else {
                buffer.putLong(at, buffer.getLong(at) + delta)
                at += 8
            }
        }
        return true
    }

    private fun copyRange(input: RandomAccessFile, from: Long, to: Long, out: java.io.OutputStream) {
        input.seek(from)
        val chunk = ByteArray(64 * 1024)
        var remaining = to - from
        while (remaining > 0) {
            val read = input.read(chunk, 0, minOf(chunk.size.toLong(), remaining).toInt())
            if (read < 0) break
            out.write(chunk, 0, read)
            remaining -= read
        }
    }

    private fun buildUdta(title: String, artist: String, album: String, cover: ByteArray?): ByteArray {
        val items = java.io.ByteArrayOutputStream()
        if (title.isNotBlank()) items.write(textItem("\u00A9nam", title))
        if (artist.isNotBlank()) {
            items.write(textItem("\u00A9ART", artist))
            items.write(textItem("aART", artist))
        }
        if (album.isNotBlank()) items.write(textItem("\u00A9alb", album))
        if (cover != null && cover.isNotEmpty()) {
            val png = cover.size > 4 && cover[0] == 0x89.toByte() && cover[1] == 'P'.code.toByte()
            items.write(
                box("covr", dataAtom(if (png) 14 else 13, cover)),
            )
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
}
