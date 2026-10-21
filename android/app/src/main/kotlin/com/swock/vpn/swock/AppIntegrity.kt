package com.swock.vpn.swock

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/** Rejects debuggable and re-signed packages before the VPN UI or service can run. */
object AppIntegrity {
    private const val expectedPackageName = "com.swock.vpn.swock"
    private const val releaseCertificateSha256 =
        "0481B224FCFA7A4A8B7943748F1AD6DFD313AD940652D44544BDD088753955B3"

    @Suppress("DEPRECATION")
    fun isTrusted(context: Context): Boolean {
        if (context.packageName != expectedPackageName ||
            BuildConfig.APPLICATION_ID != expectedPackageName
        ) {
            return false
        }

        if (BuildConfig.DEBUG ||
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        ) {
            return false
        }

        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
        } else {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNATURES,
            )
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners.orEmpty()
        } else {
            packageInfo.signatures.orEmpty()
        }
        return signatures.any { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02X".format(byte) } == releaseCertificateSha256
        }
    }
}
