package com.swock.vpn.swock

import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.widget.TextView
import com.swock.vpn.swock.hotspot.HotspotService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.swock.vpn/channel"
    private val hotspotPermissionRequest = 7
    private val vpnNotificationPermissionRequest = 8
    private var pendingProfileJson: String? = null
    private var pendingImportUri: String? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var integrityVerified = false

    private val hotspotWifiPermission: String
        get() = if (Build.VERSION.SDK_INT >= 33) android.Manifest.permission.NEARBY_WIFI_DEVICES
        else android.Manifest.permission.ACCESS_FINE_LOCATION

    override fun onCreate(savedInstanceState: Bundle?) {
        integrityVerified = AppIntegrity.isTrusted(this)
        super.onCreate(savedInstanceState)
        if (!integrityVerified) {
            setContentView(TextView(this).apply {
                text = "This is not an official Swock release. Install the signed release build."
                textSize = 16f
                setPadding(48, 96, 48, 48)
            })
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!integrityVerified) return
        pendingImportUri = intent?.dataString

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> {
                    val profileJson = call.argument<String>("profile")
                    if (profileJson.isNullOrBlank()) {
                        result.error("INVALID_PROFILE", "A profile is required", null)
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (pendingNotificationPermissionResult != null) {
                            result.error("BUSY", "A permission request is already open", null)
                        } else {
                            pendingProfileJson = profileJson
                            pendingNotificationPermissionResult = result
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), vpnNotificationPermissionRequest)
                        }
                    } else {
                        beginVpnPermissionFlow(profileJson, result)
                    }
                }
                "disconnect" -> {
                    pendingProfileJson = null
                    val stopIntent = Intent(this, MyVpnService::class.java)
                        .putExtra(MyVpnService.EXTRA_STOP, true)
                    startService(stopIntent)
                    result.success(true)
                }
                "getStatus" -> result.success(MyVpnService.status())
                "getStatistics" -> result.success(MyVpnService.statistics())
                "drainVpnLogs" -> result.success(MyVpnService.drainVpnEvents())
                "clearVpnLogs" -> {
                    MyVpnService.clearVpnEvents()
                    result.success(true)
                }
                "testConnection" -> result.success(call.argument<String>("profile")?.let(MyVpnService::testConnection) == true)
                "getNetworkInfo" -> result.success(mapOf("connected" to true))
                "hotspotRequestPermissions" -> {
                    val needed = buildList {
                        if (checkSelfPermission(hotspotWifiPermission) != PackageManager.PERMISSION_GRANTED) add(hotspotWifiPermission)
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            add(android.Manifest.permission.POST_NOTIFICATIONS)
                        }
                    }
                    if (needed.isEmpty()) {
                        result.success(true)
                    } else if (pendingPermissionResult != null) {
                        result.error("BUSY", "A permission request is already open", null)
                    } else {
                        pendingPermissionResult = result
                        requestPermissions(needed.toTypedArray(), hotspotPermissionRequest)
                    }
                }
                "hotspotStart" -> {
                    val intent = Intent(this, HotspotService::class.java)
                        .setAction(HotspotService.ACTION_START)
                        .putExtra(HotspotService.EXTRA_NAME, call.argument<String>("name"))
                        .putExtra(HotspotService.EXTRA_PASSWORD, call.argument<String>("password"))
                        .putExtra(HotspotService.EXTRA_PORT, call.argument<Int>("port") ?: HotspotService.DEFAULT_PORT)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                    result.success(true)
                }
                "hotspotStop" -> {
                    startService(Intent(this, HotspotService::class.java).setAction(HotspotService.ACTION_STOP))
                    result.success(true)
                }
                "hotspotStatus" -> result.success(HotspotService.status())
                "getImportUri" -> {
                    result.success(pendingImportUri)
                    pendingImportUri = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingImportUri = intent.dataString
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == hotspotPermissionRequest) {
            val index = permissions.indexOf(hotspotWifiPermission)
            val granted = index >= 0 && grantResults.getOrNull(index) == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        } else if (requestCode == vpnNotificationPermissionRequest) {
            val profile = pendingProfileJson
            val result = pendingNotificationPermissionResult
            pendingProfileJson = null
            pendingNotificationPermissionResult = null
            if (profile != null && result != null) {
                // Notification permission is optional for the tunnel itself. Continue
                // connection even if the user declines, then let Android suppress alerts.
                beginVpnPermissionFlow(profile, result)
            }
        }
    }

    private fun beginVpnPermissionFlow(profileJson: String, result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingProfileJson = profileJson
            startActivityForResult(intent, 0)
            result.success(true)
        } else {
            startVpnService(profileJson)
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0) {
            val profile = pendingProfileJson
            pendingProfileJson = null
            if (resultCode == RESULT_OK && profile != null) {
                startVpnService(profile)
            } else if (resultCode != RESULT_OK) {
                MyVpnService.updateStatus("disconnected", "VPN permission was not granted")
            }
        }
    }

    private fun startVpnService(profileJson: String) {
        val intent = Intent(this, MyVpnService::class.java)
            .putExtra(MyVpnService.EXTRA_PROFILE, profileJson)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
