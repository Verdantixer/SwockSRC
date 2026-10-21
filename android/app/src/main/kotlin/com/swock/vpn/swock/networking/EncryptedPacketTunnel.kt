package com.swock.vpn.swock.networking

import android.os.Process
import java.io.Closeable
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.SecureRandom
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class EncryptedPacketTunnel(
    private val transport: Closeable,
    inputStream: InputStream,
    outputStream: OutputStream,
    private val tunDescriptor: java.io.FileDescriptor,
    private val txKeyHex: String,
    private val rxKeyHex: String,
    initialTxCounter: Long = 0L,
    initialRxCounter: Long = 0L,
    private val urgentThreads: Boolean = false,
    private val stealthObfuscation: Boolean = false,
    private val onFailure: (String) -> Unit,
) {
    private val cipher = ChaCha20Cipher()
    private val random = SecureRandom()
    private val input = DataInputStream(inputStream)
    private val output = DataOutputStream(outputStream)
    private val tunInput = FileInputStream(tunDescriptor)
    private val tunOutput = FileOutputStream(tunDescriptor)
    @Volatile private var stopped = false
    @Volatile var linkMonitor: LinkMonitor? = null
    private var txCounter = initialTxCounter
    private var rxCounter = initialRxCounter
    private val writeLock = Any()
    private val failureReported = AtomicBoolean(false)
    private val uploadedBytes = AtomicLong(0)
    private val downloadedBytes = AtomicLong(0)

    fun uploadedBytes(): Long = uploadedBytes.get()
    fun downloadedBytes(): Long = downloadedBytes.get()

    fun start() {
        launch("swock-tun-to-server", ::readFromTun)
        launch("swock-server-to-tun", ::readFromServer)
    }

    fun stop() {
        stopped = true
        linkMonitor?.stop()
        try { transport.close() } catch (_: Exception) { }
        try { tunInput.close() } catch (_: Exception) { }
        try { tunOutput.close() } catch (_: Exception) { }
    }

    /** Sends a tunnel-internal packet (such as a link probe) that does not come from the TUN device. */
    fun sendInternalPacket(packet: ByteArray) {
        try {
            sendFrame(packet)
        } catch (error: Exception) {
            reportFailure(error)
        }
    }

    private fun launch(name: String, body: () -> Unit) {
        Thread({
            if (urgentThreads) {
                try { Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO) } catch (_: Exception) { }
            }
            body()
        }, name).start()
    }

    private fun readFromTun() {
        val packet = ByteArray(65535)
        try {
            while (!stopped) {
                val count = tunInput.read(packet)
                if (count > 0) {
                    sendFrame(packet.copyOf(count))
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
                var packet = cipher.decrypt(frame, rxKeyHex, nonce(rxCounter++))
                if (stealthObfuscation && packet.size >= 2) {
                    // Check if packet contains stealth padding header (0xFE magic byte)
                    if (packet[0] == 0xFE.toByte()) {
                        val paddingLen = packet[1].toInt() and 0xFF
                        if (packet.size >= 2 + paddingLen) {
                            packet = packet.copyOfRange(2 + paddingLen, packet.size)
                        }
                    }
                }
                if (linkMonitor?.consume(packet) == true) continue
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

    // The counter is taken under the write lock so frames are numbered in the order they are written.
    private fun sendFrame(rawPacket: ByteArray) {
        synchronized(writeLock) {
            val payload = if (stealthObfuscation && rawPacket.size < 512) {
                // Randomize small packet size signatures with dynamic 4..32 byte padding
                val padLen = 4 + random.nextInt(29)
                val padded = ByteArray(2 + padLen + rawPacket.size)
                padded[0] = 0xFE.toByte() // Stealth magic
                padded[1] = padLen.toByte()
                random.nextBytes(ByteArray(padLen).also { System.arraycopy(it, 0, padded, 2, padLen) })
                System.arraycopy(rawPacket, 0, padded, 2 + padLen, rawPacket.size)
                padded
            } else {
                rawPacket
            }

            val encrypted = cipher.encrypt(payload, txKeyHex, nonce(txCounter++))
            val frame = ByteArray(4 + encrypted.size)
            ByteBuffer.wrap(frame).putInt(encrypted.size)
            System.arraycopy(encrypted, 0, frame, 4, encrypted.size)
            output.write(frame)
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
