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
    private val pendingSharedTexts = ArrayDeque<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        extractSharedText(intent)?.let { pendingSharedTexts.addLast(it) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                when (call.method) {
                    "consumePendingSharedTexts" -> {
                        val drained = ArrayList(pendingSharedTexts)
                        pendingSharedTexts.clear()
                        result.success(drained)
                    }
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
        if (!sharedText.isNullOrBlank()) {
            if (eventSink != null) {
                eventSink?.success(sharedText)
            } else {
                pendingSharedTexts.addLast(sharedText)
            }
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null) {
            return null
        }

        return WishizIncomingLinkParser.extractPendingValue(
            action = intent.action,
            dataString = intent.dataString,
            subject = intent.getStringExtra(Intent.EXTRA_SUBJECT),
            text = intent.getStringExtra(Intent.EXTRA_TEXT),
        )
    }
}
