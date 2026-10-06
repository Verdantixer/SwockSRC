package com.swock.vpn.swock.networking

interface TransportEngine {
    fun connect(profile: Map<String, Any?>): Boolean
    fun disconnect()
    fun isConnected(): Boolean
}
