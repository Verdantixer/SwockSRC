package com.swock.vpn.swock.networking

interface VpnEngine {
    fun start(profileJson: String, tun: android.os.ParcelFileDescriptor)
    fun stop()
    fun getStatus(): Map<String, Any?>
    fun getStatistics(): Map<String, Any?>
    fun testConnection(profileJson: String): Boolean
}
