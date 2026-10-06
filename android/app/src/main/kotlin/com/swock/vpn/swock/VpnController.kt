package com.swock.vpn.swock

import android.content.Context
import android.net.VpnService
import com.swock.vpn.swock.networking.VpnEngine

class VpnController(
    private val context: Context,
    private val engine: VpnEngine,
) {
    fun connect(profileJson: String, tun: android.os.ParcelFileDescriptor) {
        val service = VpnService.prepare(context)
        if (service != null) {
            return
        }
        engine.start(profileJson, tun)
    }

    fun disconnect() {
        engine.stop()
    }

    fun status(): Map<String, Any?> = engine.getStatus()

    fun statistics(): Map<String, Any?> = engine.getStatistics()
}
