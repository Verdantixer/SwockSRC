package com.swock.vpn.swock.networking

import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.security.SecureRandom

class WebSocketStreams(
    private val input: InputStream,
    private val output: OutputStream,
) {
    private val random = SecureRandom()
    val inputStream: InputStream = WebSocketInputStream()
    val outputStream: OutputStream = WebSocketOutputStream()

    private fun writeFrame(opcode: Int, payload: ByteArray) {
        output.write(0x80 or opcode)
        when {
            payload.size < 126 -> output.write(0x80 or payload.size)
            payload.size <= 0xffff -> {
                output.write(0x80 or 126)
                output.write(payload.size ushr 8)
                output.write(payload.size and 0xff)
            }
            else -> {
                output.write(0x80 or 127)
                repeat(4) { output.write(0) }
                repeat(4) { shift -> output.write(payload.size ushr ((3 - shift) * 8) and 0xff) }
            }
        }
        val mask = ByteArray(4).also(random::nextBytes)
        output.write(mask)
        val masked = ByteArray(payload.size) { index ->
            (payload[index].toInt() xor mask[index % 4].toInt()).toByte()
        }
        output.write(masked)
        output.flush()
    }

    private inner class WebSocketInputStream : InputStream() {
        private var payload = ByteArray(0)
        private var offset = 0
        private var ended = false

        override fun read(): Int {
            val one = ByteArray(1)
            return if (read(one, 0, 1) < 0) -1 else one[0].toInt() and 0xff
        }

        override fun read(buffer: ByteArray, byteOffset: Int, byteCount: Int): Int {
            if (byteCount == 0) return 0
            while (offset >= payload.size) {
                if (ended) return -1
                readFrame()
            }
            val count = minOf(byteCount, payload.size - offset)
            payload.copyInto(buffer, byteOffset, offset, offset + count)
            offset += count
            return count
        }

        private fun readFrame() {
            while (true) {
                val first = input.read()
                if (first < 0) throw EOFException("WebSocket closed")
                val second = input.read()
                if (second < 0) throw EOFException("Incomplete WebSocket frame")
                val opcode = first and 0x0f
                val masked = second and 0x80 != 0
                var length = (second and 0x7f).toLong()
                if (length == 126L) {
                    length = (readByte() shl 8 or readByte()).toLong()
                } else if (length == 127L) {
                    length = 0
                    repeat(8) { length = (length shl 8) or readByte().toLong() }
                }
                require(length in 0..1_048_576) { "WebSocket frame exceeds the allowed size" }
                val mask = if (masked) ByteArray(4).also(input::readFully) else null
                val frame = ByteArray(length.toInt())
                input.readFully(frame)
                if (mask != null) {
                    frame.indices.forEach { index -> frame[index] = (frame[index].toInt() xor mask[index % 4].toInt()).toByte() }
                }
                when (opcode) {
                    0x0, 0x2 -> {
                        payload = frame
                        offset = 0
                        if (frame.isNotEmpty()) return
                    }
                    0x8 -> {
                        ended = true
                        return
                    }
                    0x9 -> synchronized(output) { writeFrame(0xA, frame) }
                    0xA -> Unit
                    else -> throw IllegalStateException("Unsupported WebSocket opcode: $opcode")
                }
            }
        }

        private fun readByte(): Int {
            val value = input.read()
            if (value < 0) throw EOFException("Incomplete WebSocket frame length")
            return value
        }
    }

    private inner class WebSocketOutputStream : OutputStream() {
        override fun write(value: Int) = write(byteArrayOf(value.toByte()), 0, 1)

        override fun write(buffer: ByteArray, byteOffset: Int, byteCount: Int) {
            if (byteCount == 0) return
            val payload = buffer.copyOfRange(byteOffset, byteOffset + byteCount)
            synchronized(output) { writeFrame(0x2, payload) }
        }
    }
}

private fun InputStream.readFully(target: ByteArray) {
    var offset = 0
    while (offset < target.size) {
        val count = read(target, offset, target.size - offset)
        if (count < 0) throw EOFException("Incomplete WebSocket frame")
        offset += count
    }
}