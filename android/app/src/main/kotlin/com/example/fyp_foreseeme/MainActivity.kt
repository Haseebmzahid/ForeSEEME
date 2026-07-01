package com.example.fyp_foreseeme

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val configChannel = "fyp_foreseeme/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, configChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Expose the Maps/Places key already injected into the manifest
                    // (from local.properties) so the Dart Places REST call can reuse
                    // it — no separate --dart-define needed.
                    "getMapsApiKey" -> {
                        try {
                            val appInfo = packageManager.getApplicationInfo(
                                packageName,
                                PackageManager.GET_META_DATA,
                            )
                            val key = appInfo.metaData
                                ?.getString("com.google.android.geo.API_KEY")
                                ?: ""
                            result.success(key)
                        } catch (e: Exception) {
                            result.success("")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
