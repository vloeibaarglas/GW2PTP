package com.vloeibaarglas.gw2tp

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.vloeibaarglas.gw2tp/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBatteryOptimizationDisabled" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        val disabled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else {
                            true
                        }
                        result.success(disabled)
                    }
                    "showDisableBatteryOptimizationSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "isBackgroundRestricted" -> {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                        val restricted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            am.isBackgroundRestricted
                        } else {
                            false
                        }
                        result.success(restricted)
                    }
                    "showAppBatterySettings" -> {
                        // App info page: one tap from the per-app Battery
                        // screen (Unrestricted / Optimized / Restricted).
                        // This is the only way back ON — Android offers no API
                        // to re-enable battery optimization programmatically.
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
