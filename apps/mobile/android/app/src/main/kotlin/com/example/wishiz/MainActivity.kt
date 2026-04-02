package com.example.wishiz

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "wishiz/share_intake/methods"
    private val eventChannelName = "wishiz/share_intake/events"
    private var eventSink: EventChannel.EventSink? = null
    private var latestSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        latestSharedText = extractSharedText(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "getInitialSharedText" -> result.success(latestSharedText)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(
                object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                        eventSink = events
                    }

                    override fun onCancel(arguments: Any?) {
                        eventSink = null
                    }
                }
            )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val sharedText = extractSharedText(intent)
        latestSharedText = sharedText
        if (!sharedText.isNullOrBlank()) {
            eventSink?.success(sharedText)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) {
            return null
        }

        val pieces = listOfNotNull(
            intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim(),
            intent.getStringExtra(Intent.EXTRA_TEXT)?.trim(),
        ).filter { it.isNotEmpty() }

        if (pieces.isEmpty()) {
            return null
        }

        return pieces.joinToString(separator = "\n")
    }
}
