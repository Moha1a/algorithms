package com.company.manfathak

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.Locale

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "manfathak/android_auth")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "diagnostics" -> result.success(androidAuthDiagnostics())
                    else -> result.notImplemented()
                }
            }
    }

    private fun androidAuthDiagnostics(): Map<String, Any?> {
        val signatures = signingCertificates()
        val firstSignature = signatures.firstOrNull()
        return mapOf(
            "packageName" to packageName,
            "installerPackageName" to installerPackageName(),
            "androidSdkInt" to Build.VERSION.SDK_INT,
            "deviceManufacturer" to Build.MANUFACTURER,
            "deviceModel" to Build.MODEL,
            "signingCertificateCount" to signatures.size,
            "signingSha1" to firstSignature?.let { fingerprint(it, "SHA-1") }.orEmpty(),
            "signingSha256" to firstSignature?.let { fingerprint(it, "SHA-256") }.orEmpty(),
            "signingSha1List" to signatures.map { fingerprint(it, "SHA-1") },
            "signingSha256List" to signatures.map { fingerprint(it, "SHA-256") },
        )
    }

    private fun installerPackageName(): String {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                packageManager.getInstallSourceInfo(packageName).installingPackageName.orEmpty()
            } else {
                @Suppress("DEPRECATION")
                packageManager.getInstallerPackageName(packageName).orEmpty()
            }
        } catch (_: Exception) {
            ""
        }
    }

    private fun signingCertificates(): List<ByteArray> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNING_CERTIFICATES
                )
                val signingInfo = packageInfo.signingInfo ?: return emptyList()
                val signers = if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                } ?: return emptyList()
                signers.map { it.toByteArray() }
            } else {
                @Suppress("DEPRECATION")
                val packageInfo = packageManager.getPackageInfo(
                    packageName,
                    PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                packageInfo.signatures?.map { it.toByteArray() } ?: emptyList()
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun fingerprint(certificateBytes: ByteArray, algorithm: String): String {
        val digest = MessageDigest.getInstance(algorithm).digest(certificateBytes)
        return digest.joinToString(":") { byte ->
            "%02X".format(Locale.US, byte)
        }
    }
}
