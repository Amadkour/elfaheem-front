package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity — two independent MediaProjection grants
//
// WHY TWO REQUEST CODES:
//   Android allows only ONE active projection per process.  If the same grant
//   is handed to both the recorder and flutter_webrtc, the second call to
//   getMediaProjection() silently revokes the first — the recorder then dies
//   after chunk #0.
//
//   Solution: show the system permission dialog TWICE, once per consumer.
//
//   REQUEST_MEDIA_PROJECTION = 1001  →  recorder-exclusive grant
//     startScreenCaptureService  →  dialog  →  onActivityResult(1001)
//       →  ACTION_STORE_PROJECTION  →  ScreenCaptureService.recordLoop()
//
//   REQUEST_SCREEN_SHARE = 1002  →  flutter_webrtc grant
//     upgradeToScreenRecording   →  dialog  →  onActivityResult(1002)
//       →  ACTION_UPGRADE_TO_SCREEN (promotes FGS type, unblocks Dart)
//       →  flutter_webrtc calls getMediaProjection() with THIS grant
//
//   The two tokens are completely independent — flutter_webrtc can never
//   invalidate the recorder's projection, and the recorder keeps chunking
//   through the entire screen-share lifecycle.
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

        // 1001: recorder grant  → ACTION_STORE_PROJECTION
        private const val REQUEST_MEDIA_PROJECTION = 1001
        // 1002: flutter_webrtc screen-share grant  → ACTION_UPGRADE_TO_SCREEN
        private const val REQUEST_SCREEN_SHARE     = 1002
    }

    private var projectionManager: MediaProjectionManager? = null

    // Each grant has its own pending callback so they never cross-resolve.
    private var onRecorderProjectionApproved:  (() -> Unit)? = null   // 1001
    private var onScreenShareProjectionResult: ((Boolean) -> Unit)? = null // 1002

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    // ─────────────────────────────────────────────────────────────────────────
    // onActivityResult — dispatch by request code
    // ─────────────────────────────────────────────────────────────────────────

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {

            // ── Recorder grant ────────────────────────────────────────────────
            REQUEST_MEDIA_PROJECTION -> {
                if (resultCode == RESULT_OK && data != null) {
                    Log.d(TAG, "onActivityResult(1001): recorder projection approved")

                    // Wire the callback through the service so Dart is unblocked
                    // only AFTER ACTION_STORE_PROJECTION has run and recordLoop()
                    // has been launched. Calling the callback here directly would
                    // let Dart race ahead before recording starts.
                    ScreenCaptureService.onProjectionGrantStored = {
                        onRecorderProjectionApproved?.invoke()
                        onRecorderProjectionApproved = null
                    }

                    val i = Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_STORE_PROJECTION
                        putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ScreenCaptureService.EXTRA_DATA, data)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        startForegroundService(i) else startService(i)

                } else {
                    Log.w(TAG, "onActivityResult(1001): recorder projection denied (resultCode=$resultCode)")
                    onRecorderProjectionApproved?.invoke()
                    onRecorderProjectionApproved = null
                }
            }

            // ── flutter_webrtc screen-share grant ─────────────────────────────
            REQUEST_SCREEN_SHARE -> {
                if (resultCode == RESULT_OK && data != null) {
                    Log.d(TAG, "onActivityResult(1002): screen-share projection approved")

                    // Promote the FGS type so flutter_webrtc can legally call
                    // getMediaProjection() on Android 14+.
                    startService(Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_UPGRADE_TO_SCREEN
                    })

                    onScreenShareProjectionResult?.invoke(true)
                    onScreenShareProjectionResult = null

                } else {
                    Log.w(TAG, "onActivityResult(1002): screen-share denied (resultCode=$resultCode)")
                    onScreenShareProjectionResult?.invoke(false)
                    onScreenShareProjectionResult = null
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flutter engine — method + event channels
    // ─────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── 1. Screen-share channel ───────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_SCREEN_SHARE)
                .setMethodCallHandler { call, result ->
                    when (call.method) {

                        // Shows the projection dialog for the RECORDER (grant 1001).
                        // Called once at session start before recording begins.
                        "startScreenCaptureService" -> {
                            // Guard on isProjectionGranted, NOT isRunning.
                            // isRunning is true as soon as startMicRecording starts the
                            // service (mic-only mode).  We must still show the projection
                            // dialog (grant 1001) so ACTION_STORE_PROJECTION can fire and
                            // recordLoop() can start.  Only skip if the grant was already
                            // stored and recording is genuinely active.
                            if (ScreenCaptureService.isProjectionGranted) {
                                Log.d(TAG, "startScreenCaptureService: projection already granted")
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            onRecorderProjectionApproved = { result.success(true) }
                            try {
                                @Suppress("DEPRECATION")
                                startActivityForResult(
                                        projectionManager!!.createScreenCaptureIntent(),
                                        REQUEST_MEDIA_PROJECTION,
                                )
                            } catch (e: Exception) {
                                Log.e(TAG, "startScreenCaptureService: ${e.message}", e)
                                onRecorderProjectionApproved = null
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

                        // Configure session params and start the foreground service.
                        // Recording starts after the projection dialog is approved.
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
                                Log.d(TAG, "startMicRecording: session=$sessionId  chunkSecs=$chunkSecs")
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e(TAG, "startMicRecording: ${e.message}", e)
                                result.error("MIC_START_ERROR", e.message, null)
                            }
                        }

                        "getChunkIndex" -> result.success(ScreenCaptureService.currentChunkIndex)

                        // Shows the projection dialog for flutter_webrtc (grant 1002).
                        // The recorder's grant (1001) is NOT touched.
                        "upgradeToScreenRecording" -> {
                            if (!ScreenCaptureService.isRunning) {
                                Log.w(TAG, "upgradeToScreenRecording: service not running")
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            onScreenShareProjectionResult = { approved ->
                                result.success(approved)
                            }
                            try {
                                @Suppress("DEPRECATION")
                                startActivityForResult(
                                        projectionManager!!.createScreenCaptureIntent(),
                                        REQUEST_SCREEN_SHARE,
                                )
                            } catch (e: Exception) {
                                Log.e(TAG, "upgradeToScreenRecording: ${e.message}", e)
                                onScreenShareProjectionResult = null
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
                            val id   = call.argument<String>("channelId")
                                    ?: return@setMethodCallHandler result.error("MISSING", "channelId required", null)
                            val name = call.argument<String>("channelName") ?: ""
                            val imp  = call.argument<Int>("importance") ?: NotificationManager.IMPORTANCE_DEFAULT
                            getSystemService(NotificationManager::class.java)
                                    .createNotificationChannel(NotificationChannel(id, name, imp))
                        }
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }

        // ── 4. EventChannel: native → Dart events ─────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CH_REC_EVENTS)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                        Log.d(TAG, "EventChannel: Dart is listening")
                        ScreenCaptureService.eventSink = sink
                    }
                    override fun onCancel(args: Any?) {
                        Log.d(TAG, "EventChannel: Dart cancelled")
                        ScreenCaptureService.eventSink = null
                    }
                })
    }
}