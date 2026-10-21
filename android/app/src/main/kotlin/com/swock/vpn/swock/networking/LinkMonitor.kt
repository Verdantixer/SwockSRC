package com.swock.vpn.swock.networking

import java.security.SecureRandom

/**
 * Measures tunnel health by pinging the server's tunnel address (10.8.0.1) through the tunnel.
 * Replies are consumed here and never reach the TUN device.
 */
class LinkMonitor(
    private val localAddress: ByteArray,
    private val intervalMs: Long,
    private val timeoutMs: Long,
    private val sendPacket: (ByteArray) -> Unit,
    private val listener: Listener,
) {
    interface Listener {
        fun onLossExcessive(lossPercent: Int)
        fun onStalled(consecutiveLost: Int)
        fun onLog(message: String)
    }

    private companion object {
        const val WINDOW = 20
        const val MIN_SAMPLES = 10
        const val LOSS_THRESHOLD_PERCENT = 30
        const val STALL_PROBES = 4
        const val UNSUPPORTED_AFTER_PROBES = 8
    }

    private val gateway = byteArrayOf(10, 8, 0, 1)
    private val random = SecureRandom()
    private val identifier = random.nextInt(0xFFFF)
    private val lock = Any()
    private val pending = LinkedHashMap<Int, Long>()
    private val outcomes = ArrayDeque<Boolean>()
    private var sequence = 0
    private var probesSent = 0
    private var everReplied = false
    private var consecutiveLost = 0
    private var smoothedRttMs = -1.0
    @Volatile private var stopped = false
    private var worker: Thread? = null

    fun start() {
        worker = Thread(::run, "swock-link-monitor").also {
            it.isDaemon = true
            it.start()
        }
    }

    fun stop() {
        stopped = true
        worker?.interrupt()
    }

    fun rttMs(): Int = synchronized(lock) { smoothedRttMs.toInt() }

    fun lossPercent(): Int = synchronized(lock) {
        if (outcomes.isEmpty()) 0 else outcomes.count { !it } * 100 / outcomes.size
    }

    /** Returns true when the packet was a reply to one of our probes. */
    fun consume(packet: ByteArray): Boolean {
        if (packet.size < 28 || (packet[0].toInt() ushr 4) != 4 || packet[9].toInt() != 1) return false
        val headerLength = (packet[0].toInt() and 0x0F) * 4
        if (packet.size < headerLength + 8 || packet[headerLength].toInt() != 0) return false
        if (!packet.copyOfRange(12, 16).contentEquals(gateway) || !packet.copyOfRange(16, 20).contentEquals(localAddress)) {
            return false
        }
        val replyId = ((packet[headerLength + 4].toInt() and 0xFF) shl 8) or (packet[headerLength + 5].toInt() and 0xFF)
        if (replyId != identifier) return false
        val replySequence = ((packet[headerLength + 6].toInt() and 0xFF) shl 8) or (packet[headerLength + 7].toInt() and 0xFF)
        synchronized(lock) {
            val sentAt = pending.remove(replySequence) ?: return true
            val rtt = (System.nanoTime() - sentAt) / 1_000_000.0
            smoothedRttMs = if (smoothedRttMs < 0) rtt else smoothedRttMs * 0.8 + rtt * 0.2
            if (!everReplied) {
                everReplied = true
                listener.onLog("Link monitor active (round trip ${rtt.toInt()} ms)")
            }
            consecutiveLost = 0
            record(true)
        }
        return true
    }

    private fun run() {
        while (!stopped) {
            try {
                Thread.sleep(intervalMs)
                if (stopped) return
                expireOldProbes()
                send()
                if (!evaluate()) return
            } catch (_: InterruptedException) {
                return
            } catch (_: Exception) {
                return
            }
        }
    }

    private fun send() {
        val seq: Int
        synchronized(lock) {
            seq = sequence++ and 0xFFFF
            pending[seq] = System.nanoTime()
            probesSent++
        }
        sendPacket(buildEchoRequest(seq))
    }

    private fun expireOldProbes() {
        synchronized(lock) {
            val deadline = System.nanoTime() - timeoutMs * 1_000_000
            val iterator = pending.entries.iterator()
            while (iterator.hasNext()) {
                val entry = iterator.next()
                if (entry.value > deadline) break
                iterator.remove()
                consecutiveLost++
                record(false)
            }
        }
    }

    /** Returns false when monitoring should end. */
    private fun evaluate(): Boolean {
        var excessiveLoss = -1
        var stalled = 0
        synchronized(lock) {
            if (!everReplied) {
                if (probesSent >= UNSUPPORTED_AFTER_PROBES && pending.size + consecutiveLost >= UNSUPPORTED_AFTER_PROBES - 2) {
                    listener.onLog("Server does not answer link probes; automatic recovery paused")
                    return false
                }
                return true
            }
            if (consecutiveLost >= STALL_PROBES) {
                stalled = consecutiveLost
                consecutiveLost = 0
                outcomes.clear()
            } else if (outcomes.size >= MIN_SAMPLES) {
                val loss = outcomes.count { !it } * 100 / outcomes.size
                if (loss >= LOSS_THRESHOLD_PERCENT) {
                    excessiveLoss = loss
                    outcomes.clear()
                }
            }
        }
        if (stalled > 0) listener.onStalled(stalled)
        else if (excessiveLoss >= 0) listener.onLossExcessive(excessiveLoss)
        return true
    }

    private fun record(success: Boolean) {
        outcomes.addLast(success)
        while (outcomes.size > WINDOW) outcomes.removeFirst()
    }

    private fun buildEchoRequest(sequenceNumber: Int): ByteArray {
        val payloadLength = 16
        val total = 20 + 8 + payloadLength
        val packet = ByteArray(total)
        packet[0] = 0x45
        packet[2] = (total ushr 8).toByte()
        packet[3] = total.toByte()
        val ipId = random.nextInt(0xFFFF)
        packet[4] = (ipId ushr 8).toByte()
        packet[5] = ipId.toByte()
        packet[6] = 0x40
        packet[8] = 64
        packet[9] = 1
        System.arraycopy(localAddress, 0, packet, 12, 4)
        System.arraycopy(gateway, 0, packet, 16, 4)
        val ipChecksum = checksum(packet, 0, 20)
        packet[10] = (ipChecksum ushr 8).toByte()
        packet[11] = ipChecksum.toByte()
        packet[20] = 8
        packet[24] = (identifier ushr 8).toByte()
        packet[25] = identifier.toByte()
        packet[26] = (sequenceNumber ushr 8).toByte()
        packet[27] = sequenceNumber.toByte()
        val payload = ByteArray(payloadLength).also(random::nextBytes)
        System.arraycopy(payload, 0, packet, 28, payloadLength)
        val icmpChecksum = checksum(packet, 20, total - 20)
        packet[22] = (icmpChecksum ushr 8).toByte()
        packet[23] = icmpChecksum.toByte()
        return packet
    }

    private fun checksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var index = offset
        val end = offset + length
        while (index + 1 < end) {
            sum += ((data[index].toInt() and 0xFF) shl 8) or (data[index + 1].toInt() and 0xFF)
            index += 2
        }
        if (index < end) sum += (data[index].toInt() and 0xFF) shl 8
        while (sum ushr 16 != 0) sum = (sum and 0xFFFF) + (sum ushr 16)
        return sum.inv() and 0xFFFF
    }
}
