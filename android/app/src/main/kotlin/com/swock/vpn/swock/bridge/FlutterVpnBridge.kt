package com.swock.vpn.swock.bridge

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class FlutterVpnBridge(
    private val context: Context,
    private val flutterEngine: FlutterEngine,
) {
    private val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.swock.vpn/channel")

    fun connect(profileJson: String) {
        channel.invokeMethod("connect", profileJson)
    }

    fun disconnect() {
        channel.invokeMethod("disconnect", null)
    }

    fun getStatus() {
        channel.invokeMethod("getStatus", null)
    }

    fun getStatistics() {
        channel.invokeMethod("getStatistics", null)
    }

    fun testConnection(profileJson: String) {
        channel.invokeMethod("testConnection", profileJson)
    }

    fun getNetworkInfo() {
        channel.invokeMethod("getNetworkInfo", null)
    }
}
