package com.swock.vpn.swock.networking

import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.InetSocketAddress
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import org.json.JSONObject

class ShadowsocksEngine(
    private val vpnService: VpnService,
    private val onStatus: (String, String) -> Unit = { _, _ -> },
) : VpnEngine {
    private companion object {
        // Keep a bad endpoint from leaving the UI in "Connecting" forever.
        // The tunnel itself remains blocking after the authenticated handshake.
        const val CONNECT_TIMEOUT_MS = 7_000
        const val HANDSHAKE_TIMEOUT_MS = 7_000
    }
    @Volatile private var socket: Socket? = null
    private var tunnel: EncryptedPacketTunnel? = null
    @Volatile private var status = "disconnected"
    @Volatile private var statusMessage = "Disconnected"
    private var connectedAt = 0L

    override fun start(profileJson: String, tun: ParcelFileDescriptor) {
        val profile = JSONObject(profileJson)
        val server = profile.optString("server").trim()
        val port = profile.optInt("port")
        val serverPublicKey = profile.optString("serverPublicKey").trim()
        val clientPrivateKey = profile.optString("clientPrivateKey").trim()
        require(server.isNotEmpty() && port in 1..65535) { "Profile server and port are required" }
        require(serverPublicKey.length == 64 && clientPrivateKey.length == 64) {
            "A 32-byte server public key and client private key are required"
        }
        setStatus("connecting", "Connecting to ${profile.optString("server")}")
        val rawSocket = Socket()
        socket = rawSocket
        check(vpnService.protect(rawSocket)) { "Unable to protect VPN transport socket" }
        rawSocket.soTimeout = HANDSHAKE_TIMEOUT_MS
        rawSocket.connect(InetSocketAddress(server, port), CONNECT_TIMEOUT_MS)
        val tlsConfig = profile.optJSONObject("tls") ?: JSONObject()
        val webSocketConfig = profile.optJSONObject("webSocket") ?: JSONObject()
        val legacyTransport = profile.optString("transport", "auto")
        val tlsEnabled = tlsConfig.optBoolean("enabled", legacyTransport == "websocketTls")
        val webSocketEnabled = webSocketConfig.optBoolean(
            "enabled",
            legacyTransport == "websocket" || legacyTransport == "websocketTls",
        )
        val tlsName = tlsConfig.optString("sni").ifBlank {
            tlsConfig.optString("serverName").ifBlank { server }
        }
        val candidate = if (tlsEnabled) {
            setStatus("connecting", "Negotiating verified TLS")
            createTlsSocket(rawSocket, tlsName)
        } else rawSocket
        socket = candidate
        if (webSocketEnabled) {
            setStatus("connecting", "Opening WebSocket tunnel")
            openWebSocket(candidate, server, port, webSocketConfig)
        }
        setStatus("connecting", "Performing X25519 server handshake")
        val keyExchange = Curve25519KeyExchange()
        val clientPublicKey = publicKeyFor(clientPrivateKey)
        val webSocketStreams = if (webSocketEnabled) {
            WebSocketStreams(candidate.getInputStream(), candidate.getOutputStream())
        } else null
        val inputStream = webSocketStreams?.inputStream ?: candidate.getInputStream()
        val outputStream = webSocketStreams?.outputStream ?: candidate.getOutputStream()
        val output = DataOutputStream(outputStream)
        val input = DataInputStream(inputStream)
        output.write("SWK1".toByteArray(Charsets.US_ASCII))
        output.write(hexToBytes(clientPublicKey))
        output.flush()
        val responseMagic = ByteArray(4)
        input.readFully(responseMagic)
        require(responseMagic.contentEquals("SWK1".toByteArray(Charsets.US_ASCII))) { "Invalid Swock server handshake" }
        val receivedServerKey = ByteArray(32)
        input.readFully(receivedServerKey)
        require(receivedServerKey.contentEquals(hexToBytes(serverPublicKey))) { "Server key pin mismatch" }
        val sharedSecret = keyExchange.createSharedSecret(serverPublicKey, clientPrivateKey)
        val sessionKey = MessageDigest.getInstance("SHA-256").digest(
            hexToBytes(sharedSecret) + hexToBytes(clientPublicKey) + receivedServerKey,
        )
        // Authentication completed; packet forwarding is intentionally long-lived.
        candidate.soTimeout = 0
        tunnel = EncryptedPacketTunnel(
            candidate,
            inputStream,
            outputStream,
            tun.fileDescriptor,
            bytesToHex(sessionKey),
            { reason -> setStatus("error", "Tunnel lost: $reason") },
        )
        tunnel?.start()
        connectedAt = System.currentTimeMillis()
        setStatus("connected", "Encrypted tunnel connected")
    }

    override fun stop() {
        tunnel?.stop()
        tunnel = null
        socket?.close()
        socket = null
        setStatus("disconnected", "Disconnected")
        connectedAt = 0L
    }

    override fun getStatus(): Map<String, Any?> = mapOf(
        "state" to status,
        "connected" to (status == "connected"),
        "message" to statusMessage,
    )

    override fun getStatistics(): Map<String, Any?> = mapOf(
        "downloadBytes" to (tunnel?.downloadedBytes() ?: 0L),
        "uploadBytes" to (tunnel?.uploadedBytes() ?: 0L),
        "durationMs" to if (connectedAt == 0L) 0L else System.currentTimeMillis() - connectedAt,
    )

    private fun setStatus(next: String, message: String) {
        status = next
        statusMessage = message
        onStatus(next, message)
    }

    fun forceReconnect(reason: String) {
        setStatus("error", reason)
        try { socket?.close() } catch (_: Exception) { }
        try { tunnel?.stop() } catch (_: Exception) { }
    }

    override fun testConnection(profileJson: String): Boolean {
        return try {
            val profile = JSONObject(profileJson)
            profile.optString("server").isNotBlank() && profile.optInt("port") in 1..65535
        } catch (_: Exception) {
            false
        }
    }

    private fun publicKeyFor(privateKeyHex: String): String {
        val privateKey = org.bouncycastle.crypto.params.X25519PrivateKeyParameters(hexToBytes(privateKeyHex), 0)
        return bytesToHex(privateKey.generatePublicKey().encoded)
    }

    private fun createTlsSocket(rawSocket: Socket, serverName: String): SSLSocket {
        require(serverName.isNotBlank()) { "TLS server name is required" }
        val tlsSocket = (SSLSocketFactory.getDefault() as SSLSocketFactory)
            .createSocket(rawSocket, serverName, rawSocket.port, true) as SSLSocket
        val parameters = tlsSocket.sslParameters
        parameters.endpointIdentificationAlgorithm = "HTTPS"
        if (!serverName.matches(Regex("^[0-9.]+$"))) {
            parameters.serverNames = listOf(SNIHostName(serverName))
        }
        tlsSocket.sslParameters = parameters
        tlsSocket.soTimeout = HANDSHAKE_TIMEOUT_MS
        tlsSocket.startHandshake()
        return tlsSocket
    }

    private fun openWebSocket(
        socket: Socket,
        server: String,
        port: Int,
        config: JSONObject,
    ) {
        val path = config.optString("path", "/").ifBlank { "/" }
        require(path.startsWith("/")) { "WebSocket path must start with /" }
        val host = config.optString("host").ifBlank { server }
        val key = Base64.getEncoder().encodeToString(ByteArray(16).also(SecureRandom()::nextBytes))
        val input = BufferedInputStream(socket.getInputStream())
        val output = BufferedOutputStream(socket.getOutputStream())
        val hostHeader = if (host.contains(":")) "[$host]:$port" else "$host:$port"
        output.write(
            ("GET $path HTTP/1.1\r\n" +
                "Host: $hostHeader\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                "Sec-WebSocket-Key: $key\r\n" +
                "Sec-WebSocket-Version: 13\r\n\r\n").toByteArray(Charsets.US_ASCII),
        )
        output.flush()
        val statusLine = readHttpLine(input)
        require(statusLine.matches(Regex("HTTP/1\\.[01] 101(?: .*)?"))) {
            "WebSocket upgrade rejected: $statusLine"
        }
        val headers = mutableMapOf<String, String>()
        while (true) {
            val line = readHttpLine(input)
            if (line.isEmpty()) break
            val separator = line.indexOf(':')
            if (separator > 0) {
                headers[line.substring(0, separator).trim().lowercase()] =
                    line.substring(separator + 1).trim()
            }
        }
        val expectedAccept = Base64.getEncoder().encodeToString(
            MessageDigest.getInstance("SHA-1")
                .digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray(Charsets.US_ASCII)),
        )
        require(headers["sec-websocket-accept"] == expectedAccept) {
            "Invalid WebSocket upgrade response"
        }
    }

    private fun readHttpLine(input: BufferedInputStream): String {
        val line = StringBuilder()
        while (line.length < 8192) {
            val next = input.read()
            if (next < 0) throw EOFException("Connection closed during WebSocket upgrade")
            if (next == '\n'.code) return line.toString().trimEnd('\r')
            line.append(next.toChar())
        }
        throw IllegalArgumentException("WebSocket header line is too long")
    }

    private fun hexToBytes(value: String): ByteArray {
        require(value.length % 2 == 0) { "Invalid hex value" }
        return ByteArray(value.length / 2) { index -> value.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    }

    private fun bytesToHex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
}
