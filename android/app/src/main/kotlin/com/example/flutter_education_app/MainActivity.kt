package com.example.flutter_education_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.flutter_education_app/notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Create the screen-share notification channel immediately on launch.
        // This is safe to call multiple times — Android ignores duplicates.
        createScreenShareChannel()

        MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createNotificationChannel" -> {
                    val channelId          = call.argument<String>("channelId") ?: "livekit_screen_share"
                    val channelName        = call.argument<String>("channelName") ?: "Screen Share"
                    val channelDescription = call.argument<String>("channelDescription") ?: ""
                    val importance         = call.argument<Int>("importance") ?: NotificationManager.IMPORTANCE_DEFAULT
                    createChannel(channelId, channelName, channelDescription, importance)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Called eagerly so the channel exists before any service tries to use it.
    private fun createScreenShareChannel() {
        createChannel(
                channelId          = "livekit_screen_share",
                channelName        = "Screen Share",
                channelDescription = "Used while screen sharing is active",
                importance         = NotificationManager.IMPORTANCE_DEFAULT
        )
    }

    private fun createChannel(
            channelId: String,
            channelName: String,
            channelDescription: String,
            importance: Int
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }
}