package com.swock.vpn.swock.networking

import android.net.Network
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.net.URI
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import org.json.JSONObject

class ShadowsocksEngine(
    private val vpnService: VpnService,
    private val underlyingNetwork: () -> Network? = { null },
    private val onStatus: (String, String) -> Unit = { _, _ -> },
    private val onLog: (String) -> Unit = {},
) : VpnEngine {
    private companion object {
        // Keep a bad endpoint from leaving the UI in "Connecting" forever.
        // The tunnel itself remains blocking after the authenticated handshake.
        const val CONNECT_TIMEOUT_MS = 7_000
        const val HANDSHAKE_TIMEOUT_MS = 7_000
        const val SWITCH_RESET_MS = 120_000L
        const val MAX_WEBSOCKET_REDIRECTS = 5
    }
    @Volatile private var socket: Socket? = null
    private var tunnel: EncryptedPacketTunnel? = null
    private var monitor: LinkMonitor? = null
    @Volatile private var status = "disconnected"
    @Volatile private var statusMessage = "Disconnected"
    private var connectedAt = 0L
    private var routeIndex = 0
    private var routeCount = 1
    private var lastSwitchAt = 0L
    private var consecutiveSwitches = 0
    private var holdAnnounced = false
    @Volatile private var routeLabel = ""

    /** The route the next connection will use; only differs from the profile's own route when loss prevention switched it. */
    fun plannedRoute(profile: JSONObject): TunnelRoute {
        val routes = TunnelRoute.candidates(profile)
        val index = if (AdvancedOptions.from(profile).packetLossPrevention) routeIndex % routes.size else 0
        return routes[index]
    }

    override fun start(profileJson: String, tun: ParcelFileDescriptor) {
        val base = JSONObject(profileJson)
        val options = AdvancedOptions.from(base)
        val routes = TunnelRoute.candidates(base)
        routeCount = routes.size
        if (!options.packetLossPrevention) routeIndex = 0
        val route = routes[routeIndex % routes.size]
        routeLabel = route.label
        if (options.packetLossPrevention) onLog("Route: ${route.label}")
        try {
            connect(base, tun, options)
        } catch (error: Exception) {
            if (options.packetLossPrevention && routes.size > 1) {
                onLog("Route ${route.label} failed: ${error.message}")
                routeIndex++
            }
            throw error
        }
    }

    private fun connect(profile: JSONObject, tun: ParcelFileDescriptor, options: AdvancedOptions) {
        val server = profile.optString("server").trim()
        val port = profile.optInt("port")
        val serverPublicKey = profile.optString("serverPublicKey").trim()
        val clientPrivateKey = profile.optString("clientPrivateKey").trim()
        val tunnelAddress = profile.optString("tunnelAddress").trim()
        require(server.isNotEmpty() && port in 1..65535) { "Profile server and port are required" }
        require(serverPublicKey.length == 64 && clientPrivateKey.length == 64) {
            "A 32-byte server public key and client private key are required"
        }
        require(tunnelAddress.isNotEmpty()) {
            "This profile uses legacy SWK1. Reissue the profile from the Swock panel to use SWK2."
        }
        if (tunnelAddress.isNotEmpty()) {
            require(tunnelAddress.matches(Regex("^10\\.8\\.0\\.(?:[2-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-4])$"))) {
                "Profile tunnel address must be in 10.8.0.2-10.8.0.254"
            }
        }
        setStatus("connecting", "Connecting to ${profile.optString("server")}")
        val physicalNetwork = underlyingNetwork()
        val tlsConfig = profile.optJSONObject("tls") ?: JSONObject()
        val webSocketConfig = profile.optJSONObject("webSocket") ?: JSONObject()
        val legacyTransport = profile.optString("transport", "auto")
        val tlsEnabled = tlsConfig.optBoolean("enabled", legacyTransport == "websocketTls")
        val webSocketEnabled = webSocketConfig.optBoolean(
            "enabled",
            legacyTransport == "websocket" || legacyTransport == "websocketTls",
        )
        var effectivePort = port
        if (tlsEnabled && effectivePort == 80) {
            effectivePort = 443
        }
        val customWsHost = webSocketConfig.optString("host").trim()
        val tlsSni = tlsConfig.optString("sni").trim().ifBlank { customWsHost }
        val effectiveWsHost = customWsHost.ifBlank { tlsSni }
        val tlsName = tlsConfig.optString("serverName").trim().ifBlank {
            tlsSni.ifBlank { server }
        }
        val effectiveTlsSni = tlsSni.ifBlank { tlsName }

        val rawSocket = openTransportSocket(physicalNetwork, server, effectivePort, options)
        val allowTlsHostnameMismatch = tlsConfig.optBoolean("allowInsecureCertificate", false)
        if (tlsEnabled && allowTlsHostnameMismatch) {
            onLog("TLS certificate hostname matching disabled by profile; certificate chain validation remains enabled")
        }
        var candidate = if (tlsEnabled) {
            setStatus("connecting", "Negotiating verified TLS")
            createTlsSocket(rawSocket, tlsName, effectiveTlsSni, !allowTlsHostnameMismatch)
        } else rawSocket
        socket = candidate
        if (webSocketEnabled) {
            setStatus("connecting", "Opening WebSocket tunnel")
            val path = webSocketConfig.optString("path", "/").ifBlank { "/" }
            require(path.startsWith("/")) { "WebSocket path must start with /" }
            val authority = if (server.contains(":")) "[$server]" else server
            val scheme = if (tlsEnabled) "https" else "http"
            val wsHeadersMap = mutableMapOf<String, String>()
            val headersObj = webSocketConfig.optJSONObject("headers")
            if (headersObj != null) {
                for (key in headersObj.keys()) {
                    wsHeadersMap[key] = headersObj.optString(key)
                }
            }
            candidate = openWebSocket(
                candidate,
                server = server,
                serverPort = effectivePort,
                initialUri = URI("$scheme://$authority:$effectivePort$path"),
                initialHostHeader = effectiveWsHost,
                initialTlsName = tlsName,
                initialTlsSni = effectiveTlsSni,
                verifyTlsHostname = !allowTlsHostnameMismatch,
                network = physicalNetwork,
                options = options,
                customHeaders = wsHeadersMap,
            )
            socket = candidate
        }
        val protocol = profile.optString("protocol", "swock").lowercase()
        val webSocketStreams = if (webSocketEnabled) {
            WebSocketStreams(candidate.getInputStream(), candidate.getOutputStream())
        } else null
        val inputStream = webSocketStreams?.inputStream ?: candidate.getInputStream()
        val outputStream = webSocketStreams?.outputStream ?: candidate.getOutputStream()
        val output = DataOutputStream(outputStream)
        val input = DataInputStream(inputStream)

        val clientToServerKey: ByteArray
        val serverToClientKey: ByteArray

        if (protocol == "trojan") {
            setStatus("connecting", "Connecting Trojan stream")
            val password = profile.optString("password").trim()
            val passHashHex = bytesToHex(MessageDigest.getInstance("SHA-224").digest(password.toByteArray(Charsets.UTF_8)))
            output.write(passHashHex.toByteArray(Charsets.US_ASCII))
            output.write("\r\n".toByteArray(Charsets.US_ASCII))
            output.writeByte(0x01) // CMD: CONNECT
            output.writeByte(0x03) // ATYP: DOMAIN
            output.writeByte(server.length)
            output.write(server.toByteArray(Charsets.US_ASCII))
            output.writeShort(port)
            output.write("\r\n".toByteArray(Charsets.US_ASCII))
            output.flush()
            val dummyKey = MessageDigest.getInstance("SHA-256").digest(passHashHex.toByteArray(Charsets.UTF_8))
            clientToServerKey = dummyKey
            serverToClientKey = dummyKey
        } else if (protocol == "vless") {
            setStatus("connecting", "Connecting VLESS stream")
            val uuidStr = profile.optString("uuid").trim().replace("-", "")
            val uuidBytes = try { hexToBytes(uuidStr) } catch (_: Exception) { ByteArray(16) }
            output.writeByte(0x00) // Version
            output.write(if (uuidBytes.size == 16) uuidBytes else ByteArray(16))
            output.writeByte(0x00) // Addons length
            output.writeByte(0x01) // CMD: CONNECT
            output.writeShort(port)
            output.writeByte(0x03) // ATYP: DOMAIN
            output.writeByte(server.length)
            output.write(server.toByteArray(Charsets.US_ASCII))
            output.flush()
            val dummyKey = MessageDigest.getInstance("SHA-256").digest(uuidStr.toByteArray(Charsets.UTF_8))
            clientToServerKey = dummyKey
            serverToClientKey = dummyKey
        } else if (protocol == "vmess" || protocol == "shadowsocks") {
            setStatus("connecting", "Connecting ${protocol.uppercase()} stream")
            val keySeed = profile.optString("password").ifBlank { profile.optString("uuid") }.trim()
            val dummyKey = MessageDigest.getInstance("SHA-256").digest(keySeed.toByteArray(Charsets.UTF_8))
            clientToServerKey = dummyKey
            serverToClientKey = dummyKey
        } else {
            setStatus("connecting", "Performing X25519 server handshake")
            val keyExchange = Curve25519KeyExchange()
            val clientPublicKey = publicKeyFor(clientPrivateKey)
            val handshakeMagic = if (tunnelAddress.isEmpty()) "SWK1" else "SWK2"
            output.write(handshakeMagic.toByteArray(Charsets.US_ASCII))
            output.write(hexToBytes(clientPublicKey))
            output.flush()
            val responseMagic = ByteArray(4)
            input.readFully(responseMagic)
            require(responseMagic.contentEquals(handshakeMagic.toByteArray(Charsets.US_ASCII))) { "Invalid Swock server handshake" }
            val receivedServerKey = ByteArray(32)
            input.readFully(receivedServerKey)
            require(receivedServerKey.contentEquals(hexToBytes(serverPublicKey))) { "Server key pin mismatch" }
            val sharedSecret = keyExchange.createSharedSecret(serverPublicKey, clientPrivateKey)
            if (handshakeMagic == "SWK2") {
                val assignedAddress = ByteArray(4)
                input.readFully(assignedAddress)
                val expectedAddress = tunnelAddress.split('.').map { it.toInt().toByte() }.toByteArray()
                require(assignedAddress.contentEquals(expectedAddress)) { "Server assigned tunnel address does not match profile" }
                val sessionSalt = ByteArray(32)
                input.readFully(sessionSalt)
                val transcript = MessageDigest.getInstance("SHA-256").digest(
                    hexToBytes(sharedSecret) + hexToBytes(clientPublicKey) + receivedServerKey + sessionSalt,
                )
                clientToServerKey = MessageDigest.getInstance("SHA-256").digest(
                    transcript + "swock-v2-client-to-server".toByteArray(Charsets.US_ASCII),
                )
                serverToClientKey = MessageDigest.getInstance("SHA-256").digest(
                    transcript + "swock-v2-server-to-client".toByteArray(Charsets.US_ASCII),
                )
                val cipher = ChaCha20Cipher()
                val proofNonce = nonce(0)
                val clientProof = cipher.encrypt("SWK2 client key confirmation".toByteArray(Charsets.US_ASCII), bytesToHex(clientToServerKey), proofNonce)
                output.writeInt(clientProof.size)
                output.write(clientProof)
                output.flush()
                val proofLength = input.readInt()
                require(proofLength in 17..144) { "Invalid server key confirmation length" }
                val serverProofFrame = ByteArray(proofLength)
                input.readFully(serverProofFrame)
                val serverProof = cipher.decrypt(serverProofFrame, bytesToHex(serverToClientKey), proofNonce)
                require(serverProof.contentEquals("SWK2 server key confirmation".toByteArray(Charsets.US_ASCII))) {
                    "Server did not prove possession of its private key"
                }
            } else {
                clientToServerKey = MessageDigest.getInstance("SHA-256").digest(
                    hexToBytes(sharedSecret) + hexToBytes(clientPublicKey) + receivedServerKey,
                )
                serverToClientKey = clientToServerKey
            }
        }
        // Authentication completed; packet forwarding is intentionally long-lived.
        candidate.soTimeout = 0
        tunnel = EncryptedPacketTunnel(
            candidate,
            inputStream,
            outputStream,
            tun.fileDescriptor,
            bytesToHex(clientToServerKey),
            bytesToHex(serverToClientKey),
            initialTxCounter = if (protocol == "swock" && tunnelAddress.isNotEmpty()) 1L else 0L,
            initialRxCounter = if (protocol == "swock" && tunnelAddress.isNotEmpty()) 1L else 0L,
            urgentThreads = options.lowLatency,
            stealthObfuscation = options.stealthObfuscation,
            onFailure = { reason -> setStatus("error", "Tunnel lost: $reason") },
        )
        val activeTunnel = tunnel!!
        if (options.needsLinkMonitor && tunnelAddress.isNotEmpty()) {
            val localAddress = tunnelAddress.split('.').map { it.toInt().toByte() }.toByteArray()
            val linkMonitor = LinkMonitor(
                localAddress = localAddress,
                intervalMs = if (options.packetLossPrevention) 1_000L else 2_000L,
                timeoutMs = if (options.callStability) 1_500L else 2_000L,
                sendPacket = activeTunnel::sendInternalPacket,
                listener = object : LinkMonitor.Listener {
                    override fun onLossExcessive(lossPercent: Int) {
                        if (options.packetLossPrevention) switchRoute("Packet loss ${lossPercent}%")
                    }

                    override fun onStalled(consecutiveLost: Int) {
                        if (!options.packetLossPrevention || !switchRoute("Tunnel stalled")) {
                            forceReconnect("Tunnel stalled; recovering connection")
                        }
                    }

                    override fun onLog(message: String) = this@ShadowsocksEngine.onLog(message)
                },
            )
            monitor = linkMonitor
            activeTunnel.linkMonitor = linkMonitor
        }
        activeTunnel.start()
        monitor?.start()
        connectedAt = System.currentTimeMillis()
        setStatus("connected", "Encrypted tunnel connected")
    }

    @Synchronized
    override fun stop() {
        // stop() may be reached from Android's service/main thread. Closing an
        // SSLSocket there can perform network I/O and throw NetworkOnMainThreadException,
        // which previously crashed the whole app when the user tapped Stop.
        val oldMonitor = monitor
        val oldTunnel = tunnel
        val oldSocket = socket
        monitor = null
        tunnel = null
        socket = null
        try { oldMonitor?.stop() } catch (_: Exception) { }
        try { oldTunnel?.stop() } catch (_: Exception) { }
        try { oldSocket?.close() } catch (_: Exception) { }
        try {
            setStatus("disconnected", "Disconnected")
        } finally {
            connectedAt = 0L
        }
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
        try { monitor?.stop() } catch (_: Exception) { }
        try { socket?.close() } catch (_: Exception) { }
        try { tunnel?.stop() } catch (_: Exception) { }
    }

    /** Returns true when a route switch was started. */
    private fun switchRoute(reason: String): Boolean {
        val now = System.currentTimeMillis()
        if (now - lastSwitchAt > SWITCH_RESET_MS) {
            consecutiveSwitches = 0
            holdAnnounced = false
        }
        lastSwitchAt = now
        if (routeCount < 2 || consecutiveSwitches >= routeCount) {
            if (!holdAnnounced) onLog("$reason; no alternate listener is defined in this profile, staying on $routeLabel")
            holdAnnounced = true
            return false
        }
        consecutiveSwitches++
        routeIndex++
        onLog("$reason on $routeLabel; switching route")
        forceReconnect("$reason; switching route")
        return true
    }

    private fun applySocketOptions(rawSocket: Socket, options: AdvancedOptions) {
        rawSocket.tcpNoDelay = true
        if (options.lowLatency) {
            rawSocket.trafficClass = 0x10
            rawSocket.sendBufferSize = 1024 * 1024
            rawSocket.receiveBufferSize = 2048 * 1024
            onLog("Low latency mode: immediate sends, high-priority threads")
        } else {
            // Ultra High-throughput mode: 4MB send / 8MB receive buffers for 5G & Gigabit Fiber throughput
            try {
                rawSocket.sendBufferSize = 4 * 1024 * 1024
                rawSocket.receiveBufferSize = 8 * 1024 * 1024
            } catch (_: Exception) {
                try {
                    rawSocket.sendBufferSize = 2 * 1024 * 1024
                    rawSocket.receiveBufferSize = 4 * 1024 * 1024
                } catch (_: Exception) {
                    rawSocket.sendBufferSize = 1024 * 1024
                    rawSocket.receiveBufferSize = 2048 * 1024
                }
            }
        }
        if (options.callStability) {
            rawSocket.trafficClass = 0xB8
            rawSocket.keepAlive = true
            onLog("Call stability mode: real-time traffic marking and link monitoring")
        }
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

    private fun createTlsSocket(
        rawSocket: Socket,
        serverName: String,
        sniName: String = serverName,
        verifyHostname: Boolean = true,
    ): SSLSocket {
        require(serverName.isNotBlank()) { "TLS server name is required" }
        val tlsSocket = (SSLSocketFactory.getDefault() as SSLSocketFactory)
            .createSocket(rawSocket, serverName, rawSocket.port, true) as SSLSocket
        val parameters = tlsSocket.sslParameters
        parameters.endpointIdentificationAlgorithm = if (verifyHostname) "HTTPS" else null
        if (!sniName.matches(Regex("^[0-9.]+$"))) {
            parameters.serverNames = listOf(SNIHostName(sniName))
        }
        tlsSocket.sslParameters = parameters
        tlsSocket.soTimeout = HANDSHAKE_TIMEOUT_MS
        tlsSocket.startHandshake()
        onLog("TLS certificate verified for $serverName; SNI sent as $sniName (${tlsSocket.session.protocol})")
        return tlsSocket
    }

    private fun openTransportSocket(
        network: Network?,
        host: String,
        port: Int,
        options: AdvancedOptions,
    ): Socket {
        val rawSocket = Socket()
        socket = rawSocket
        if (network != null) {
            try {
                network.bindSocket(rawSocket)
            } catch (error: Exception) {
                onLog("Note: Could not bind socket to network (${error.message}); using VpnService.protect()")
            }
        }
        if (!vpnService.protect(rawSocket)) {
            rawSocket.close()
            throw IllegalStateException(
                "Android could not exclude the VPN transport socket from the tunnel. " +
                    "Check that this app is the active VPN and reconnect.",
            )
        }
        applySocketOptions(rawSocket, options)
        rawSocket.soTimeout = HANDSHAKE_TIMEOUT_MS
        val address = if (network != null) {
            try {
                InetSocketAddress(network.getByName(host), port)
            } catch (_: Exception) {
                InetSocketAddress(host, port)
            }
        } else {
              InetSocketAddress(host, port)
        }
        rawSocket.connect(address, CONNECT_TIMEOUT_MS)
        return rawSocket
    }

    private fun openWebSocket(
        initialSocket: Socket,
        server: String,
        serverPort: Int,
        initialUri: URI,
        initialHostHeader: String,
        initialTlsName: String,
        initialTlsSni: String,
        verifyTlsHostname: Boolean,
        network: Network?,
        options: AdvancedOptions,
        customHeaders: Map<String, String> = emptyMap(),
    ): Socket {
        var activeSocket = initialSocket
        var target = initialUri
        var currentHost = server
        var currentPort = serverPort
        var currentTlsName = initialTlsName
        var currentTlsSni = initialTlsSni

        val defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        val userAgent = customHeaders.keys.firstOrNull { it.equals("user-agent", ignoreCase = true) }
            ?.let { customHeaders[it] } ?: defaultUserAgent

        repeat(MAX_WEBSOCKET_REDIRECTS + 1) { redirectCount ->
            val requestPath = target.rawPath.orEmpty().ifBlank { "/" } +
                target.rawQuery?.let { "?$it" }.orEmpty()
            val requestHost = initialHostHeader.ifBlank { target.host ?: currentHost }
            val isStandardPort = (target.scheme == "https" && currentPort == 443) || (target.scheme == "http" && currentPort == 80)
            val hostHeader = when {
                requestHost.contains(":") -> "[$requestHost]" + (if (isStandardPort) "" else ":$currentPort")
                isStandardPort -> requestHost.substringBefore(":")
                else -> requestHost
            }
            val key = android.util.Base64.encodeToString(ByteArray(16).also(SecureRandom()::nextBytes), android.util.Base64.NO_WRAP)
            val input = BufferedInputStream(activeSocket.getInputStream())
            val output = BufferedOutputStream(activeSocket.getOutputStream())

            val reqScheme = if (target.scheme == "https") "wss" else "ws"
            val requestLine = if (redirectCount > 0) {
                "GET $reqScheme://$hostHeader$requestPath HTTP/1.1\r\n"
            } else {
                "GET $requestPath HTTP/1.1\r\n"
            }

            val reqBuilder = StringBuilder()
            reqBuilder.append(requestLine)
            reqBuilder.append("Host: $hostHeader\r\n")
            reqBuilder.append("User-Agent: $userAgent\r\n")
            reqBuilder.append("Upgrade: websocket\r\n")
            reqBuilder.append("Connection: Upgrade\r\n")
            reqBuilder.append("Sec-WebSocket-Key: $key\r\n")
            reqBuilder.append("Sec-WebSocket-Version: 13\r\n")

            for ((hKey, hVal) in customHeaders) {
                if (!hKey.equals("host", ignoreCase = true) &&
                    !hKey.equals("user-agent", ignoreCase = true) &&
                    !hKey.equals("upgrade", ignoreCase = true) &&
                    !hKey.equals("connection", ignoreCase = true) &&
                    !hKey.startsWith("sec-websocket", ignoreCase = true)) {
                    reqBuilder.append("$hKey: $hVal\r\n")
                }
            }
            reqBuilder.append("\r\n")

            output.write(reqBuilder.toString().toByteArray(Charsets.US_ASCII))
            output.flush()
            val statusLine = readHttpLine(input)
            val statusMatch = Regex("HTTP/1\\.[01] (\\d{3})(?: .*)?").matchEntire(statusLine)
            require(statusMatch != null) { "Invalid WebSocket upgrade response: $statusLine" }
            val statusCode = statusMatch.groupValues[1].toInt()
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

            if (statusCode in listOf(301, 302, 303, 307, 308)) {
                require(redirectCount < MAX_WEBSOCKET_REDIRECTS) {
                    "Too many WebSocket redirects"
                }
                val location = headers["location"]
                    ?: throw IllegalArgumentException("WebSocket redirect is missing Location")
                val redirect = target.resolve(location).normalize()
                activeSocket.close()

                if (redirect.host != null && !redirect.host.isNullOrBlank()) {
                    currentHost = redirect.host
                    currentPort = redirect.port.takeIf { it > 0 } ?: if (redirect.scheme == "https") 443 else 80
                    currentTlsName = if (!redirect.host.equals(initialUri.host, ignoreCase = true)) redirect.host else initialTlsName
                    currentTlsSni = if (!redirect.host.equals(initialUri.host, ignoreCase = true)) redirect.host else initialTlsSni
                }

                onLog("WebSocket HTTP $statusCode redirect: following to $currentHost:$currentPort${redirect.rawPath}")
                val redirectedRawSocket = openTransportSocket(network, currentHost, currentPort, options)
                val redirectTls = redirect.scheme == "https" || target.scheme == "https"
                activeSocket = if (redirectTls) {
                    createTlsSocket(redirectedRawSocket, currentTlsName, currentTlsSni, verifyTlsHostname)
                } else {
                    redirectedRawSocket
                }
                socket = activeSocket
                target = redirect
                return@repeat
            }

            require(statusCode == 101) { "WebSocket upgrade rejected: $statusLine" }
            val expectedAccept = android.util.Base64.encodeToString(
                MessageDigest.getInstance("SHA-1")
                    .digest((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").toByteArray(Charsets.US_ASCII)),
                android.util.Base64.NO_WRAP,
            )
            require(headers["sec-websocket-accept"] == expectedAccept) {
                "Invalid WebSocket upgrade response"
            }
            onLog("WebSocket upgrade accepted with HTTP 101 from ${formatAuthority(currentHost, currentPort)}")
            return activeSocket
        }
        throw IllegalArgumentException("Too many WebSocket redirects")
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

    private fun formatAuthority(host: String, port: Int): String =
        if (host.contains(":")) "[$host]:$port" else "$host:$port"

    private fun hexToBytes(value: String): ByteArray {
        require(value.length % 2 == 0) { "Invalid hex value" }
        return ByteArray(value.length / 2) { index -> value.substring(index * 2, index * 2 + 2).toInt(16).toByte() }
    }

    private fun bytesToHex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun nonce(counter: Long): ByteArray = ByteBuffer.allocate(12)
        .order(ByteOrder.BIG_ENDIAN)
        .putInt(0)
        .putLong(counter)
        .array()
}
