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
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity
//
// DESIGN: ONE MediaProjection grant for everything.
//
// Android only allows ONE active MediaProjection per app at a time.
// We own the grant inside ScreenCaptureService. flutter_webrtc (LiveKit)
// does NOT get its own grant — it reuses the running FGS.
//
// flutter_webrtc on Android skips its own MediaProjection dialog when:
//   1. A foreground service with FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION is running.
//   2. That service was started before setScreenShareEnabled(true) is called.
//
// We guarantee both conditions in _toggleScreenShareAndroid():
//   1. Call startScreenCaptureService()       → dialog fires ONCE → grant stored
//      → service calls back onProjectionGrantStored AFTER startForeground()
//        and getMediaProjection() have both completed
//      → Dart awaits this call returning before proceeding
//   2. Call upgradeToScreenRecording()        → service creates VirtualDisplay,
//      emits screenLoopStarted → Dart unblocks
//   3. Call releaseVirtualDisplay()           → service releases its VirtualDisplay
//      so flutter_webrtc can create its own without conflict
//   4. Call setScreenShareEnabled(true)       → flutter_webrtc sees running
//      MEDIA_PROJECTION FGS → NO second dialog → one VirtualDisplay at a time
// ─────────────────────────────────────────────────────────────────────────────
class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"

        private const val CHANNEL_SCREEN_SHARE  = "com.example.flutter_education_app/screen_share"
        private const val CHANNEL_RECORDER      = "com.example.flutter_education_app/native_recorder"
        private const val CHANNEL_NOTIFICATIONS = "com.example.flutter_education_app/notifications"
        private const val CHANNEL_REC_EVENTS    = "com.example.flutter_education_app/rec_events"

        private const val REQUEST_MEDIA_PROJECTION = 1001

        // FIX 1: The service calls this lambda AFTER startForeground(MEDIA_PROJECTION)
        // and getMediaProjection() have both completed, guaranteeing hasProjectionGrant=true
        // before we reply success to Dart. Previously we used Handler.post which returned
        // to Dart before the service had actually obtained the grant.
        @Volatile var onProjectionGrantStored: (() -> Unit)? = null
    }

    private var mediaProjectionManager: MediaProjectionManager? = null

    private enum class PendingKind { SCREEN_SHARE }
    private var pendingKind:   PendingKind?          = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaProjectionManager =
                getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // ── 1. Screen-share channel ───────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SCREEN_SHARE)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startScreenCaptureService" -> {
                            if (ScreenCaptureService.isRunning && ScreenCaptureService.hasProjectionGrant) {
                                Log.d(TAG, "startScreenCaptureService: grant already held, skip dialog")
                                result.success(true)
                                return@setMethodCallHandler
                            }
                            if (pendingResult != null) {
                                result.error("BUSY", "Permission dialog already open", null)
                                return@setMethodCallHandler
                            }
                            pendingKind   = PendingKind.SCREEN_SHARE
                            pendingResult = result
                            startActivityForResult(
                                    mediaProjectionManager!!.createScreenCaptureIntent(),
                                    REQUEST_MEDIA_PROJECTION
                            )
                        }
                        "stopScreenCaptureService" -> {
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }

        // ── 2. Native recorder channel ────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_RECORDER)
                .setMethodCallHandler { call, result ->
                    when (call.method) {

                        // Phase 1: mic-only (no dialog, no MediaProjection)
                        "startMicRecording" -> {
                            val sessionId  = call.argument<Int>("sessionId")    ?: 0
                            val uploadUrl  = call.argument<String>("uploadUrl") ?: ""
                            val authToken  = call.argument<String>("authToken") ?: ""
                            val chunkSecs  = call.argument<Int>("chunkSeconds") ?: 30
                            val chunkIndex = call.argument<Int>("chunkIndex")   ?: 0
                            try {
                                val intent = Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_START_MIC_ONLY
                                    putExtra(ScreenCaptureService.EXTRA_SESSION_ID,  sessionId)
                                    putExtra(ScreenCaptureService.EXTRA_UPLOAD_URL,  uploadUrl)
                                    putExtra(ScreenCaptureService.EXTRA_AUTH_TOKEN,  authToken)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_SECS,  chunkSecs)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_INDEX, chunkIndex)
                                }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                    startForegroundService(intent)
                                else
                                    startService(intent)
                                Handler(Looper.getMainLooper()).post { result.success(true) }
                                Log.d(TAG, "startMicRecording: sent chunkIndex=$chunkIndex")
                            } catch (e: Exception) {
                                Log.e(TAG, "startMicRecording failed: ${e.message}", e)
                                result.error("MIC_START_ERROR", e.message, null)
                            }
                        }

                        "getChunkIndex" -> {
                            result.success(ScreenCaptureService.currentChunkIndex)
                        }

                        // Phase 2: upgrade mic-only → screen+audio (NO dialog).
                        "upgradeToScreenRecording" -> {
                            if (!ScreenCaptureService.isRunning) {
                                Log.w(TAG, "upgradeToScreenRecording: service not running")
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            if (!ScreenCaptureService.hasProjectionGrant) {
                                Log.w(TAG, "upgradeToScreenRecording: no projection grant yet")
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_UPGRADE_TO_SCREEN
                                })
                                Handler(Looper.getMainLooper()).post { result.success(true) }
                                Log.d(TAG, "upgradeToScreenRecording: ACTION_UPGRADE_TO_SCREEN sent")
                            } catch (e: Exception) {
                                Log.e(TAG, "upgradeToScreenRecording: ${e.message}", e)
                                result.error("UPGRADE_ERROR", e.message, null)
                            }
                        }

                        // Downgrade screen+audio → mic-only specifically because LiveKit
                        // screen share is about to start. This cleanly stops the screen
                        // recording loop so mediaProjection has no active VirtualDisplay
                        // when flutter_webrtc calls createVirtualDisplay(). The service
                        // emits "micReadyForShare" when the mic loop is running and it
                        // is safe to call setScreenShareEnabled(true).
                        "downgradeToMicForShare" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_DOWNGRADE_TO_MIC_FOR_SHARE
                                })
                                Log.d(TAG, "downgradeToMicForShare: ACTION_DOWNGRADE_TO_MIC_FOR_SHARE sent")
                            } catch (e: Exception) {
                                Log.e(TAG, "downgradeToMicForShare: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        // Downgrade screen+audio → mic-only (screen share stopped by teacher).
                        "stopScreenCapture" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_DOWNGRADE_TO_MIC
                                })
                                Log.d(TAG, "stopScreenCapture: ACTION_DOWNGRADE_TO_MIC sent")
                            } catch (e: Exception) {
                                Log.e(TAG, "stopScreenCapture: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        // Stop everything and seal the final chunk.
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NOTIFICATIONS)
                .setMethodCallHandler { call, result ->
                    if (call.method == "createNotificationChannel") {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val id         = call.argument<String>("channelId") ?: return@setMethodCallHandler result.error("MISSING_ARG", "channelId required", null)
                            val name       = call.argument<String>("channelName") ?: ""
                            val importance = call.argument<Int>("importance") ?: NotificationManager.IMPORTANCE_DEFAULT
                            val ch = NotificationChannel(id, name, importance)
                            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
                        }
                        result.success(null)
                    } else {
                        result.notImplemented()
                    }
                }

        // ── 4. EventChannel: native → Dart chunk/error events ─────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_REC_EVENTS)
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

    // ── onActivityResult: OUR MediaProjection dialog only ────────────────────
    //
    // FIX 1: We no longer call result.success(true) here with a Handler.post.
    // Instead we store the result and set onProjectionGrantStored — the service
    // calls this lambda back from its main-thread handler AFTER startForeground()
    // and getMediaProjection() have both completed. This guarantees
    // hasProjectionGrant=true before Dart ever sees the success reply.

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_MEDIA_PROJECTION) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val kind   = pendingKind
        val result = pendingResult
        pendingKind   = null
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.d(TAG, "MediaProjection denied (kind=$kind)")
            result?.error("USER_DENIED", "Permission denied", null)
            return
        }

        Log.d(TAG, "MediaProjection granted — sending ACTION_STORE_PROJECTION")
        try {
            // Register callback BEFORE starting the service so we cannot miss it
            // even if the service processes the intent before we return here.
            onProjectionGrantStored = {
                Log.d(TAG, "onProjectionGrantStored: replying success to Dart")
                result?.success(true)
            }

            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_STORE_PROJECTION
                putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                putExtra(ScreenCaptureService.EXTRA_DATA, data)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else
                startService(intent)

            // Do NOT reply here — wait for service callback via onProjectionGrantStored.
        } catch (e: Exception) {
            onProjectionGrantStored = null
            Log.e(TAG, "ACTION_STORE_PROJECTION failed: ${e.message}", e)
            result?.error("FGS_ERROR", e.message, null)
        }
        // Do NOT call super.
    }
}