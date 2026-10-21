package com.swock.vpn.swock.hotspot

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import com.swock.vpn.swock.MyVpnService
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket

/** Creates a Wi-Fi Direct access point and shares the active VPN through a local HTTP proxy. */
class HotspotService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var proxy: HttpProxyServer? = null
    private var session = 0
    private var requestedSsid = ""
    private var requestedPassword = ""
    private var requestedPort = DEFAULT_PORT

    companion object {
        const val ACTION_START = "com.swock.vpn.swock.hotspot.START"
        const val ACTION_STOP = "com.swock.vpn.swock.hotspot.STOP"
        const val EXTRA_NAME = "name"
        const val EXTRA_PASSWORD = "password"
        const val EXTRA_PORT = "port"
        const val DEFAULT_PORT = 8080
        private const val NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "swock_hotshare"
        private const val SSID_PREFIX = "DIRECT-sw-"

        @Volatile private var current: Map<String, Any?> = stopped("Hotshare is off")

        fun status(): Map<String, Any?> = current

        private fun stopped(message: String, state: String = "stopped") = mapOf(
            "state" to state,
            "message" to message,
            "ssid" to "",
            "password" to "",
            "host" to "",
            "port" to DEFAULT_PORT,
            "clients" to 0,
            "bytes" to 0L,
        )
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown("Hotshare is off")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START) {
            stopSelf()
            return START_NOT_STICKY
        }
        createNotificationChannel()
        val notification = buildNotification("Starting Hotshare")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        teardown(null)
        requestedSsid = intent.getStringExtra(EXTRA_NAME).orEmpty()
        requestedPassword = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
        requestedPort = intent.getIntExtra(EXTRA_PORT, DEFAULT_PORT)
        begin()
        return START_NOT_STICKY
    }

    private fun begin() {
        val failure = validate()
        if (failure != null) return fail(failure)
        val ssid = SSID_PREFIX + requestedSsid
        publish("starting", "Creating Wi-Fi network…", ssid = ssid, password = requestedPassword)
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) return fail("Turn Wi-Fi on, then start Hotshare again.")
        val p2p = getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            ?: return fail("This device does not support Wi-Fi Direct hotspots.")
        val p2pChannel = p2p.initialize(this, Looper.getMainLooper(), null)
            ?: return fail("Could not open the Wi-Fi Direct service.")
        manager = p2p
        channel = p2pChannel
        val mySession = ++session
        // A previous group (for example from a killed process) blocks creating a new one.
        p2p.removeGroup(p2pChannel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = createGroup(mySession, ssid)
            override fun onFailure(reason: Int) = createGroup(mySession, ssid)
        })
    }

    private fun validate(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "Hotshare requires Android 10 or newer."
        if (requestedSsid.isBlank() || (SSID_PREFIX + requestedSsid).toByteArray().size > 32) {
            return "Hotspot name must be 1-22 characters."
        }
        if (requestedPassword.length !in 8..63) return "Password must be 8-63 characters."
        if (requestedPort !in 1024..65535) return "Port must be between 1024 and 65535."
        if (MyVpnService.status()["state"] != "connected") return "Connect the VPN before starting Hotshare."
        return null
    }

    @SuppressLint("MissingPermission")
    private fun createGroup(mySession: Int, ssid: String) {
        if (mySession != session) return
        val p2p = manager ?: return
        val p2pChannel = channel ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return fail("Hotshare requires Android 10 or newer.")
        try {
            val config = WifiP2pConfig.Builder()
                .setNetworkName(ssid)
                .setPassphrase(requestedPassword)
                .enablePersistentMode(false)
                .setGroupOperatingBand(WifiP2pConfig.GROUP_OWNER_BAND_2GHZ)
                .build()
            p2p.createGroup(p2pChannel, config, object : WifiP2pManager.ActionListener {
                override fun onSuccess() = waitForGroup(mySession, 0)
                override fun onFailure(reason: Int) {
                    if (mySession != session) return
                    fail(
                        when (reason) {
                            WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct is not supported on this device."
                            WifiP2pManager.BUSY -> "Wi-Fi is busy. Turn off any active hotspot or Wi-Fi Direct session and try again."
                            else -> "Could not create the hotspot (code $reason)."
                        },
                    )
                }
            })
        } catch (error: SecurityException) {
            fail("Nearby devices permission is required to create the hotspot.")
        } catch (error: IllegalArgumentException) {
            fail("Hotspot name or password was rejected by Android.")
        }
    }

    @SuppressLint("MissingPermission")
    private fun waitForGroup(mySession: Int, attempt: Int) {
        if (mySession != session) return
        val p2p = manager ?: return
        val p2pChannel = channel ?: return
        try {
            p2p.requestConnectionInfo(p2pChannel) { info ->
                if (mySession != session) return@requestConnectionInfo
                val address = info?.groupOwnerAddress
                if (info != null && info.groupFormed && info.isGroupOwner && address != null) {
                    startProxy(mySession, address)
                } else if (attempt >= 30) {
                    fail("The hotspot did not start. Try again.")
                } else {
                    handler.postDelayed({ waitForGroup(mySession, attempt + 1) }, 500)
                }
            }
        } catch (error: SecurityException) {
            fail("Nearby devices permission is required to create the hotspot.")
        }
    }

    @SuppressLint("MissingPermission")
    private fun startProxy(mySession: Int, address: InetAddress) {
        val server = HttpProxyServer(address, requestedPort, ::connectThroughVpn) { MyVpnService.recordVpnEvent("Hotshare: $it") }
        try {
            server.start()
        } catch (error: IOException) {
            return fail("Proxy port $requestedPort is unavailable: ${error.message}")
        }
        proxy = server
        MyVpnService.recordVpnEvent("Hotshare proxy listening on ${address.hostAddress}:$requestedPort")
        val p2p = manager
        val p2pChannel = channel
        var ssid = SSID_PREFIX + requestedSsid
        var password = requestedPassword
        publish("running", "Hotshare is on", ssid, password, address.hostAddress.orEmpty())
        updateNotification("Sharing VPN on ${address.hostAddress}:$requestedPort")
        if (p2p != null && p2pChannel != null) {
            try {
                p2p.requestGroupInfo(p2pChannel) { group ->
                    if (mySession == session && group != null) {
                        ssid = group.networkName ?: ssid
                        password = group.passphrase ?: password
                        publish("running", "Hotshare is on", ssid, password, address.hostAddress.orEmpty())
                    }
                }
            } catch (_: SecurityException) { }
        }
        handler.postDelayed({ monitor(mySession) }, 2000)
    }

    @SuppressLint("MissingPermission")
    private fun monitor(mySession: Int) {
        if (mySession != session) return
        val vpnState = MyVpnService.status()["state"]
        if (vpnState == "disconnected") {
            MyVpnService.recordVpnEvent("Hotshare stopped because the VPN disconnected")
            stopWithMessage("Hotshare stopped because the VPN disconnected.")
            return
        }
        val p2p = manager
        val p2pChannel = channel
        if (p2p != null && p2pChannel != null) {
            try {
                p2p.requestGroupInfo(p2pChannel) { group ->
                    if (mySession != session) return@requestGroupInfo
                    if (group == null) {
                        stopWithMessage("The hotspot was closed by Android.")
                        return@requestGroupInfo
                    }
                    val previous = current
                    current = previous + mapOf(
                        "clients" to group.clientList.size,
                        "bytes" to (proxy?.bytesTransferred ?: 0L),
                        "message" to if (vpnState == "connected") "Hotshare is on" else "VPN reconnecting; proxy paused",
                    )
                }
            } catch (_: SecurityException) { }
        }
        handler.postDelayed({ monitor(mySession) }, 2000)
    }

    private fun stopWithMessage(message: String) {
        teardown(message, "stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun connectThroughVpn(host: String, port: Int): Socket {
        if (MyVpnService.status()["state"] != "connected") throw IOException("VPN is not connected")
        val connectivity = getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION")
        val vpn = (listOfNotNull(connectivity.activeNetwork) + connectivity.allNetworks.toList())
            .firstOrNull { connectivity.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }
            ?: throw IOException("VPN network is unavailable")
        val address = vpn.getAllByName(host).filterIsInstance<Inet4Address>().firstOrNull()
            ?: throw IOException("No IPv4 address for $host")
        if (address.isAnyLocalAddress || address.isLoopbackAddress || address.isLinkLocalAddress ||
            address.isMulticastAddress || NetworkInterface.getByInetAddress(address) != null
        ) {
            throw IOException("Destination is not allowed")
        }
        val socket = vpn.socketFactory.createSocket()
        try {
            socket.connect(InetSocketAddress(address, port), 15_000)
        } catch (error: IOException) {
            try { socket.close() } catch (_: IOException) { }
            throw error
        }
        return socket
    }

    private fun fail(message: String) {
        MyVpnService.recordVpnEvent("Hotshare: $message")
        teardown(message, "error")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun teardown(message: String?, state: String = "stopped") {
        session++
        handler.removeCallbacksAndMessages(null)
        proxy?.stop()
        proxy = null
        val p2p = manager
        val p2pChannel = channel
        if (p2p != null && p2pChannel != null) {
            try { p2p.removeGroup(p2pChannel, null) } catch (_: SecurityException) { }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) p2pChannel.close()
        }
        manager = null
        channel = null
        if (message != null) current = stopped(message, state)
    }

    private fun publish(
        state: String,
        message: String,
        ssid: String = "",
        password: String = "",
        host: String = "",
    ) {
        current = mapOf(
            "state" to state,
            "message" to message,
            "ssid" to ssid,
            "password" to password,
            "host" to host,
            "port" to requestedPort,
            "clients" to 0,
            "bytes" to 0L,
        )
    }

    override fun onDestroy() {
        teardown(null)
        if (current["state"] == "running" || current["state"] == "starting") current = stopped("Hotshare is off")
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(CHANNEL_ID, "Swock Hotshare", NotificationManager.IMPORTANCE_LOW)
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(message: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(this, 1, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stopIntent = PendingIntent.getService(
            this, 2,
            Intent(this, HotspotService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Swock Hotshare")
            .setContentText(message)
            .setContentIntent(contentIntent)
            .addAction(0, "Stop", stopIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(message: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(message))
    }
}
