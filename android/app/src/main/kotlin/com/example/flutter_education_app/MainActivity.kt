package com.example.flutter_education_app

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.example.flutter_education_app/screen_share"
        private const val CHANNEL_NOTIFICATIONS = "com.example.flutter_education_app/notifications"
        private const val REQUEST_CODE = 1001
    }

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager =
            getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // ── Screen share channel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "startScreenCaptureService" -> {
                        if (pendingResult != null) {
                            result.error("BUSY", "Screen share already pending", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = mediaProjectionManager!!.createScreenCaptureIntent()
                        startActivityForResult(intent, REQUEST_CODE)
                    }

                    "stopScreenCaptureService" -> {
                        stopScreenCaptureService()
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        // ── Notifications channel ─────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NOTIFICATIONS)
            .setMethodCallHandler { call, result ->
                if (call.method == "createNotificationChannel") {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val id = call.argument<String>("channelId")
                            ?: return@setMethodCallHandler result.error(
                                "MISSING_ARG", "channelId is required", null)
                        val name = call.argument<String>("channelName") ?: ""
                        val importance = call.argument<Int>("importance")
                            ?: NotificationManager.IMPORTANCE_DEFAULT
                        val ch = NotificationChannel(id, name, importance)
                        getSystemService(NotificationManager::class.java)
                            .createNotificationChannel(ch)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                Log.d(TAG, "Screen capture permission granted — starting FGS")
                try {
                    val serviceIntent = Intent(this, ScreenCaptureService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    // The service's onStartCommand runs on the next Looper iteration.
                    // We post our reply AFTER it, so ScreenCaptureService.startForeground()
                    // has been called before Dart proceeds to setScreenShareEnabled().
                    // This guarantees the FGS is fully registered when flutter_webrtc
                    // calls MediaProjection.start() inside setScreenShareEnabled().
                    Handler(Looper.getMainLooper()).post {
                        Log.d(TAG, "FGS onStartCommand dispatched — notifying Dart")
                        pendingResult?.success(true)
                        pendingResult = null
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "FGS start failed: ${e.message}", e)
                    pendingResult?.error("FGS_ERROR", e.message, null)
                    pendingResult = null
                }
            } else {
                Log.d(TAG, "Screen capture permission denied")
                pendingResult?.error("USER_DENIED", "Permission denied", null)
                pendingResult = null
            }
            // Do NOT call super — flutter_webrtc must not see our result.
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun stopScreenCaptureService() {
        try {
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_STOP
            }
            startService(intent)
            Log.d(TAG, "ScreenCaptureService stop requested")
        } catch (e: Exception) {
            Log.e(TAG, "stopScreenCaptureService failed: ${e.message}", e)
        }
    }
}