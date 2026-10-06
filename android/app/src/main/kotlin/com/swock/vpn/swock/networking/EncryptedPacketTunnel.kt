package com.swock.vpn.swock.networking

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class EncryptedPacketTunnel(
    private val transport: Closeable,
    inputStream: InputStream,
    outputStream: OutputStream,
    private val tunDescriptor: java.io.FileDescriptor,
    private val sessionKeyHex: String,
    private val onFailure: (String) -> Unit,
) {
    private val cipher = ChaCha20Cipher()
    private val input = DataInputStream(inputStream)
    private val output = DataOutputStream(outputStream)
    private val tunInput = FileInputStream(tunDescriptor)
    private val tunOutput = FileOutputStream(tunDescriptor)
    @Volatile private var stopped = false
    private var txCounter = 0L
    private var rxCounter = 0L
    private val writeLock = Any()
    private val failureReported = AtomicBoolean(false)
    private val uploadedBytes = AtomicLong(0)
    private val downloadedBytes = AtomicLong(0)

    fun uploadedBytes(): Long = uploadedBytes.get()
    fun downloadedBytes(): Long = downloadedBytes.get()

    fun start() {
        Thread(::readFromTun, "swock-tun-to-server").start()
        Thread(::readFromServer, "swock-server-to-tun").start()
    }

    fun stop() {
        stopped = true
        try { transport.close() } catch (_: Exception) { }
        try { tunInput.close() } catch (_: Exception) { }
        try { tunOutput.close() } catch (_: Exception) { }
    }

    private fun readFromTun() {
        val packet = ByteArray(65535)
        try {
            while (!stopped) {
                val count = tunInput.read(packet)
                if (count > 0) {
                    sendFrame(packet.copyOf(count), txCounter++)
                    uploadedBytes.addAndGet(count.toLong())
                }
            }
        } catch (error: Exception) {
            reportFailure(error)
        }
    }

    private fun readFromServer() {
        try {
            while (!stopped) {
                val length = input.readInt()
                require(length in 17..(65535 + 16)) { "Invalid tunnel frame length" }
                val frame = ByteArray(length)
                input.readFully(frame)
                val packet = cipher.decrypt(frame, sessionKeyHex, nonce(rxCounter++))
                tunOutput.write(packet)
                tunOutput.flush()
                downloadedBytes.addAndGet(packet.size.toLong())
            }
        } catch (error: Exception) {
            reportFailure(error)
        }
    }

    private fun reportFailure(error: Exception) {
        if (!stopped && failureReported.compareAndSet(false, true)) {
            onFailure(error.message ?: "Tunnel transport closed")
            stop()
        }
    }

    private fun sendFrame(packet: ByteArray, counter: Long) {
        val encrypted = cipher.encrypt(packet, sessionKeyHex, nonce(counter))
        synchronized(writeLock) {
            output.writeInt(encrypted.size)
            output.write(encrypted)
            output.flush()
        }
    }

    private fun nonce(counter: Long): ByteArray {
        return ByteBuffer.allocate(12)
            .order(ByteOrder.BIG_ENDIAN)
            .putInt(0)
            .putLong(counter)
            .array()
    }
}
