package com.swock.vpn.swock

import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.swock.vpn/channel"
    private var pendingProfileJson: String? = null
    private var pendingImportUri: String? = null
    private var integrityVerified = false

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
                    pendingProfileJson = profileJson
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                    } else {
                        startVpnService(profileJson)
                    }
                    result.success(true)
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
