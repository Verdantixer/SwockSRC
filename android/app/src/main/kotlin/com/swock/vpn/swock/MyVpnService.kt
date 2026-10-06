package com.swock.vpn.swock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import com.swock.vpn.swock.networking.ShadowsocksEngine
import org.json.JSONObject

class MyVpnService : VpnService() {
    @Volatile private var shouldRun = false
    @Volatile private var vpnInterface: ParcelFileDescriptor? = null
    @Volatile private var worker: Thread? = null
    private val retryMonitor = Object()
    private val connectivityManager by lazy { getSystemService(ConnectivityManager::class.java) }
    private val engine by lazy {
        ShadowsocksEngine(this) { state, message ->
            currentStatus = mapOf("state" to state, "connected" to (state == "connected"), "message" to message)
            recordVpnEvent(message)
        }
    }
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            synchronized(retryMonitor) { retryMonitor.notifyAll() }
        }

        override fun onLost(network: Network) {
            if (shouldRun) {
                recordVpnEvent("Network lost; reconnecting tunnel")
                engine.forceReconnect("Network changed; reconnecting")
            }
        }
    }

    companion object {
        const val EXTRA_PROFILE = "profile"
        const val EXTRA_STOP = "stop"
        private const val PREFS = "swock_vpn_service"
        private const val PROFILE_KEY = "desired_profile"
        @Volatile private var currentStatus: Map<String, Any?> = mapOf("state" to "disconnected", "connected" to false, "message" to "Disconnected")
        @Volatile private var currentStatistics: Map<String, Any?> = mapOf("downloadBytes" to 0L, "uploadBytes" to 0L, "durationMs" to 0L)
        private val vpnEvents = ArrayDeque<Map<String, Any?>>()

        fun recordVpnEvent(message: String) {
            synchronized(vpnEvents) {
                vpnEvents.addLast(mapOf("timestamp" to System.currentTimeMillis(), "message" to message))
                while (vpnEvents.size > 500) vpnEvents.removeFirst()
            }
        }

        fun updateStatus(state: String, message: String) {
            currentStatus = mapOf(
                "state" to state,
                "connected" to (state == "connected"),
                "message" to message,
            )
            recordVpnEvent(message)
        }

        fun drainVpnEvents(): List<Map<String, Any?>> = synchronized(vpnEvents) {
            buildList {
                while (vpnEvents.isNotEmpty()) add(vpnEvents.removeFirst())
            }
        }

        fun clearVpnEvents() = synchronized(vpnEvents) { vpnEvents.clear() }

        fun status(): Map<String, Any?> = currentStatus
        fun statistics(): Map<String, Any?> = currentStatistics
        fun testConnection(profileJson: String): Boolean = try {
            val profile = JSONObject(profileJson)
            profile.optString("server").isNotBlank() && profile.optInt("port") in 1..65535
        } catch (_: Exception) {
            false
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        try {
            connectivityManager.registerNetworkCallback(NetworkRequest.Builder().build(), networkCallback)
        } catch (_: Exception) { }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.getBooleanExtra(EXTRA_STOP, false) == true) {
            stopRequestedByUser()
            return START_NOT_STICKY
        }
        val stored = getSharedPreferences(PREFS, MODE_PRIVATE)
        val profileJson = intent?.getStringExtra(EXTRA_PROFILE) ?: stored.getString(PROFILE_KEY, null)
        if (profileJson.isNullOrBlank()) {
            currentStatus = mapOf("state" to "disconnected", "connected" to false, "message" to "Disconnected")
            stopSelf()
            return START_NOT_STICKY
        }
        stored.edit().putString(PROFILE_KEY, profileJson).apply()
        shouldRun = true
        recordVpnEvent("VPN service started")
        startForeground(1, buildNotification("Starting secure tunnel"))
        if (worker?.isAlive != true) {
            worker = Thread({ runConnectionLoop(profileJson) }, "swock-vpn-reconnect").also { it.start() }
        } else if (intent?.hasExtra(EXTRA_PROFILE) == true) {
            engine.forceReconnect("Profile changed; reconnecting")
        }
        return START_STICKY
    }

    private fun runConnectionLoop(profileJson: String) {
        var retries = 0
        while (shouldRun) {
            try {
                currentStatus = mapOf(
                    "state" to if (retries == 0) "connecting" else "reconnecting",
                    "connected" to false,
                    "message" to if (retries == 0) "Preparing VPN interface" else "Retry attempt $retries",
                    "attempt" to retries,
                )
                recordVpnEvent(currentStatus["message"].toString())
                closeVpnInterface()
                val profile = JSONObject(profileJson)
                val builder = Builder()
                    .setSession("Swock")
                    .addAddress("10.8.0.2", 32)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0)
                val dns = profile.optJSONObject("dns")
                if (dns?.optBoolean("enabled", false) == true) {
                    listOf("primary", "secondary", "tertiary")
                        .map { dns.optString(it).trim() }
                        .filter { it.isNotEmpty() }
                        .forEach(builder::addDnsServer)
                }
                vpnInterface = builder.establish()
                requireNotNull(vpnInterface) { "Unable to establish VPN interface" }
                recordVpnEvent("VPN interface established")
                engine.start(profileJson, vpnInterface!!)
                retries = 0
                currentStatus = engine.getStatus()
                while (shouldRun && engine.getStatus()["state"] == "connected") {
                    currentStatus = engine.getStatus()
                    currentStatistics = engine.getStatistics()
                    try {
                        startForeground(1, buildNotification("Secure tunnel connected"))
                        Thread.sleep(500)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        break
                    }
                }
                if (!shouldRun) break
                val failure = engine.getStatus()["message"]?.toString() ?: "Tunnel connection lost"
                throw IllegalStateException(failure)
            } catch (error: Exception) {
                if (!shouldRun) break
                Log.e("SwockVpnService", "VPN connection attempt failed", error)
                engine.stop()
                closeVpnInterface()
                retries++
                val delaySeconds = minOf(30, 1 shl minOf(retries - 1, 5))
                currentStatus = mapOf(
                    "state" to "reconnecting",
                    "connected" to false,
                    "message" to "${error.message ?: "Connection failed"}. Retrying in ${delaySeconds}s",
                    "attempt" to retries,
                )
                recordVpnEvent(currentStatus["message"].toString())
                currentStatistics = engine.getStatistics()
                startForeground(1, buildNotification("Reconnecting · attempt $retries"))
                synchronized(retryMonitor) {
                    try { retryMonitor.wait(delaySeconds * 1000L) } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                    }
                }
            }
        }
        engine.stop()
        closeVpnInterface()
        if (!shouldRun) {
            currentStatus = mapOf("state" to "disconnected", "connected" to false, "message" to "Disconnected")
            recordVpnEvent("VPN disconnected")
            currentStatistics = mapOf("downloadBytes" to 0L, "uploadBytes" to 0L, "durationMs" to 0L)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun stopRequestedByUser() {
        shouldRun = false
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().remove(PROFILE_KEY).apply()
        currentStatus = mapOf("state" to "disconnecting", "connected" to false, "message" to "Disconnecting tunnel")
        recordVpnEvent("User requested VPN stop")
        engine.stop()
        if (worker?.isAlive == true) {
            currentStatus = mapOf("state" to "disconnecting", "connected" to false, "message" to "Disconnecting tunnel")
        }
        synchronized(retryMonitor) { retryMonitor.notifyAll() }
        closeVpnInterface()
        if (worker?.isAlive != true) {
            currentStatus = mapOf("state" to "disconnected", "connected" to false, "message" to "Disconnected")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun closeVpnInterface() {
        try { vpnInterface?.close() } catch (_: Exception) { }
        vpnInterface = null
    }

    override fun onRevoke() {
        stopRequestedByUser()
        super.onRevoke()
    }

    override fun onDestroy() {
        shouldRun = false
        try { connectivityManager.unregisterNetworkCallback(networkCallback) } catch (_: Exception) { }
        synchronized(retryMonitor) { retryMonitor.notifyAll() }
        engine.stop()
        closeVpnInterface()
        if (currentStatus["state"] != "disconnecting") {
            currentStatus = mapOf("state" to "disconnected", "connected" to false, "message" to "Disconnected")
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel("swock_vpn", "Swock VPN", NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(message: String): android.app.Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, "swock_vpn")
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Swock")
            .setContentText(message)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}