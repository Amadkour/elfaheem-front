package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity — Standard MediaProjection recording pipeline
//
// KEY RESPONSIBILITIES:
//   • startScreenCaptureService: shows the system MediaProjection permission
//     dialog. On user approval, stores the result and starts ScreenCaptureService
//     with ACTION_STORE_PROJECTION so recording can begin.
//   • All recorder method channel handlers are identical to before — Dart
//     code (room_recorder.dart) is unchanged.
//   • onActivityResult handles REQUEST_MEDIA_PROJECTION and forwards the
//     approved intent to ScreenCaptureService.
// ─────────────────────────────────────────────────────────────────────────────

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"

        private const val CH_SCREEN_SHARE  = "com.example.flutter_education_app/screen_share"
        private const val CH_RECORDER      = "com.example.flutter_education_app/native_recorder"
        private const val CH_NOTIFICATIONS = "com.example.flutter_education_app/notifications"
        private const val CH_REC_EVENTS    = "com.example.flutter_education_app/rec_events"

        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var projectionManager: MediaProjectionManager? = null

    // Callback to fire once the user approves the projection dialog.
    private var onProjectionApproved: (() -> Unit)? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    // ── MediaProjection dialog result ─────────────────────────────────────────

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_MEDIA_PROJECTION) return

        if (resultCode == RESULT_OK && data != null) {
            Log.d(TAG, "onActivityResult: projection approved")

            // Wire the callback through the service so Dart is unblocked only
            // AFTER onStartCommand(ACTION_STORE_PROJECTION) has run and recordLoop()
            // has been launched.  If we called onProjectionApproved here directly
            // (before the service processes the intent), Dart would send
            // ACTION_UPGRADE_TO_SCREEN and get a fake screenLoopStarted while the
            // real recordLoop hadn't started yet, resulting in zero chunks recorded.
            ScreenCaptureService.onProjectionGrantStored = {
                onProjectionApproved?.invoke()
                onProjectionApproved = null
            }

            // Pass the grant to ScreenCaptureService — it will promote FGS type
            // to MEDIA_PROJECTION and launch recordLoop().
            val i = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_STORE_PROJECTION
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_DATA, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(i) else startService(i)
        } else {
            Log.w(TAG, "onActivityResult: projection denied (resultCode=$resultCode)")
            onProjectionApproved = null
        }
    }

    // ── FlutterEngine channel setup ───────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. Screen-share channel ───────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_SCREEN_SHARE)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startScreenCaptureService" -> {
                            if (ScreenCaptureService.isRunning) {
                                Log.d(TAG, "startScreenCaptureService: already running")
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            // Store the callback so onActivityResult can resolve the Dart Future.
                            onProjectionApproved = { result.success(true) }
                            try {
                                // Show the standard "Allow screen capture?" system dialog.
                                val intent = projectionManager!!.createScreenCaptureIntent()
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, REQUEST_MEDIA_PROJECTION)
                            } catch (e: Exception) {
                                Log.e(TAG, "startScreenCaptureService: ${e.message}", e)
                                onProjectionApproved = null
                                result.error("START_ERROR", e.message, null)
                            }
                        }
                        "stopScreenCaptureService" -> result.success(null)
                        else -> result.notImplemented()
                    }
                }

        // ── 2. Recorder method channel ────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_RECORDER)
                .setMethodCallHandler { call, result ->
                    when (call.method) {

                        "startMicRecording" -> {
                            val sessionId = call.argument<Int>("sessionId")    ?: 0
                            val uploadUrl = call.argument<String>("uploadUrl") ?: ""
                            val authToken = call.argument<String>("authToken") ?: ""
                            val chunkSecs = call.argument<Int>("chunkSeconds") ?: 5
                            val chunkIdx  = call.argument<Int>("chunkIndex")   ?: 0
                            try {
                                val i = Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_START_MIC_ONLY
                                    putExtra(ScreenCaptureService.EXTRA_SESSION_ID,  sessionId)
                                    putExtra(ScreenCaptureService.EXTRA_UPLOAD_URL,  uploadUrl)
                                    putExtra(ScreenCaptureService.EXTRA_AUTH_TOKEN,  authToken)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_SECS,  chunkSecs)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_INDEX, chunkIdx)
                                }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                    startForegroundService(i) else startService(i)
                                Log.d(TAG, "startMicRecording: service configured chunkSecs=$chunkSecs")
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e(TAG, "startMicRecording: ${e.message}", e)
                                result.error("MIC_START_ERROR", e.message, null)
                            }
                        }

                        "getChunkIndex" -> result.success(ScreenCaptureService.currentChunkIndex)

                        "upgradeToScreenRecording" -> {
                            // Called after the projection dialog is approved.
                            // ScreenCaptureService is already recording; just emit screenLoopStarted.
                            if (!ScreenCaptureService.isRunning) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_UPGRADE_TO_SCREEN
                                })
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e(TAG, "upgradeToScreenRecording: ${e.message}", e)
                                result.error("UPGRADE_ERROR", e.message, null)
                            }
                        }

                        "promoteForShare" -> {
                            ScreenCaptureService.onFgsPromoted?.invoke()
                            ScreenCaptureService.onFgsPromoted = null
                            result.success(null)
                        }

                        "downgradeToMicForShare" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_DOWNGRADE_TO_MIC_FOR_SHARE
                                })
                            } catch (e: Exception) {
                                Log.e(TAG, "downgradeToMicForShare: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        "stopScreenCapture" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_DOWNGRADE_TO_MIC
                                })
                            } catch (e: Exception) {
                                Log.e(TAG, "stopScreenCapture: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        "stopRecording" -> {
                            val isFinal = call.argument<Boolean>("isFinal") ?: true
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_STOP
                                    putExtra(ScreenCaptureService.EXTRA_IS_FINAL, isFinal)
                                })
                                Log.d(TAG, "stopRecording: isFinal=$isFinal")
                            } catch (e: Exception) {
                                Log.e(TAG, "stopRecording: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                }

        // ── 3. Notifications channel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_NOTIFICATIONS)
                .setMethodCallHandler { call, result ->
                    if (call.method == "createNotificationChannel") {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val id   = call.argument<String>("channelId")   ?: return@setMethodCallHandler result.error("MISSING", "channelId required", null)
                            val name = call.argument<String>("channelName") ?: ""
                            val imp  = call.argument<Int>("importance")     ?: NotificationManager.IMPORTANCE_DEFAULT
                            getSystemService(NotificationManager::class.java)
                                    .createNotificationChannel(NotificationChannel(id, name, imp))
                        }
                        result.success(null)
                    } else result.notImplemented()
                }

        // ── 4. EventChannel: native → Dart ────────────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CH_REC_EVENTS)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                        Log.d(TAG, "EventChannel: Dart listening")
                        ScreenCaptureService.eventSink = sink
                    }
                    override fun onCancel(args: Any?) {
                        Log.d(TAG, "EventChannel: Dart cancelled")
                        ScreenCaptureService.eventSink = null
                    }
                })
    }
}