package com.swock.vpn.swock.networking

import org.json.JSONObject

/** The endpoint configured by the imported Swock profile. */
data class TunnelRoute(val label: String, val port: Int, val tls: Boolean, val webSocket: Boolean) {
    /** Bytes added around each tunneled IP packet: TCP/IP + timestamps, SWK frame, TLS record, WebSocket header. */
    val overheadBytes: Int
        get() = 72 + (if (tls) 29 else 0) + (if (webSocket) 14 else 0)

    companion object {
        fun primary(profile: JSONObject): TunnelRoute {
            val tlsConfig = profile.optJSONObject("tls") ?: JSONObject()
            val webSocketConfig = profile.optJSONObject("webSocket") ?: JSONObject()
            val legacy = profile.optString("transport", "auto")
            val tls = tlsConfig.optBoolean("enabled", legacy == "websocketTls")
            val webSocket = webSocketConfig.optBoolean("enabled", legacy == "websocket" || legacy == "websocketTls")
            val port = profile.optInt("port")
            return TunnelRoute("port $port", port, tls, webSocket)
        }

        /** Never guess listener ports; only a route encoded in the profile can be used. */
        fun candidates(profile: JSONObject): List<TunnelRoute> = listOf(primary(profile))
    }
}
