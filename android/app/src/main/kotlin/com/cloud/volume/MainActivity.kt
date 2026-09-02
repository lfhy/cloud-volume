package com.cloud.volume

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// Android host wiring for handing cached remote files to system storage/apps.
class MainActivity : FlutterActivity() {
    private val externalFileOpener by lazy { AndroidExternalFileOpener(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXTERNAL_FILE_OPENER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openFile" -> externalFileOpener.openWithSystem(
                    call.argument<String>("path"),
                    result,
                )
                else -> result.notImplemented()
            }
        }
    }

    private companion object {
        const val EXTERNAL_FILE_OPENER_CHANNEL = "cloud_volume/external_file_opener"
    }
}
