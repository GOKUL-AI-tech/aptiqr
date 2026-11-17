package com.example.aptiqr

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FLAG_SECURE: blocks screenshots, screen recording and the
        // recent-apps thumbnail while a test is on screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aptiqr/secure")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        runOnUiThread { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                        result.success(null)
                    }
                    "disable" -> {
                        runOnUiThread { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
