package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// MainActivity — single MediaProjection grant
//
// HISTORY: this used to request two independent MediaProjection grants —
// one for the recorder, one for flutter_webrtc's own screen capture — on
// the theory that Android allows multiple concurrent projections as long
// as each has separate user consent. Testing showed that theory was wrong:
// the second grant still silently killed the first's VirtualDisplay, so
// live share still stopped local recording, just one dialog later than
// before, plus the second grant was itself two dialogs (a redundant FGS-
// promotion step and flutter_webrtc's own consent) for zero benefit.
//
// CURRENT DESIGN: exactly one MediaProjection grant for the whole session,
// requested only when Share is first tapped (not at session start):
//
//   REQUEST_MEDIA_PROJECTION = 1001  →  the only grant
//     startScreenCaptureService  →  dialog  →  onActivityResult(1001)
//       →  ACTION_STORE_PROJECTION  →  ScreenCaptureService.recordLoop()
//          (this already promotes the FGS to
//          FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION itself — nothing else
//          needs to request or promote anything further)
//
// flutter_webrtc never calls MediaProjectionManager itself on this path —
// see ElFaheemFrameCapturer.java / GetUserMediaImpl.java's
// useElFaheemCapturer branch, which reads frames from the SAME
// VirtualDisplay above instead of requesting its own.
// ─────────────────────────────────────────────────────────────────────────────

import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Intent
import android.provider.Settings
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
        private const val CH_RADIOS        = "com.example.flutter_education_app/radios"   // attendance: switch radios on

        // 1001: the one and only MediaProjection grant → ACTION_STORE_PROJECTION
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var projectionManager: MediaProjectionManager? = null

    private var onRecorderProjectionApproved: (() -> Unit)? = null // 1001

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
            // REQUEST_SCREEN_SHARE (1002) removed — was a second, redundant
            // MediaProjection dialog. ACTION_STORE_PROJECTION (triggered by
            // the 1001 grant above) already calls promoteForegroundToProjection()
            // itself, so there was nothing left for this second dialog to do.
            // See ScreenCaptureService.kt for the single remaining grant path.
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
                        // Called once, the first time Share is tapped — NOT at
                        // session start (recording itself starts earlier, at
                        // ACTION_START_MIC_ONLY, showing a placeholder; this
                        // grant only upgrades that already-running recording
                        // to real screen content — see ScreenCaptureService.kt's
                        // activateLiveProjection()).
                        "startScreenCaptureService" -> {
                            // Guard on isProjectionGranted, NOT isRunning.
                            // isRunning is true from session start (placeholder
                            // recording via ACTION_START_MIC_ONLY already running).
                            // We must still show the projection dialog (grant 1001)
                            // so ACTION_STORE_PROJECTION can fire and
                            // activateLiveProjection() can upgrade to live content.
                            // Only skip if the grant was already stored.
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

                        "setPlaceholderImage" -> {
                            val bytes = call.argument<ByteArray>("png")
                            if (bytes == null) {
                                result.error("BAD_ARGS", "png bytes missing", null)
                                return@setMethodCallHandler
                            }
                            val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                            if (bitmap == null) {
                                Log.w(TAG, "setPlaceholderImage: could not decode PNG (${bytes.size} bytes)")
                                result.error("DECODE_FAILED", "could not decode PNG", null)
                                return@setMethodCallHandler
                            }
                            // placeholderRenderer may not exist yet if this call races
                            // session start — setPlaceholderBitmap itself has no queue
                            // for "renderer doesn't exist at all" (only for "renderer
                            // exists but hasn't finished start()"), so this is a
                            // best-effort — Dart already logs+swallows failures here.
                            val renderer = ScreenCaptureService.placeholderRenderer
                            if (renderer == null) {
                                Log.w(TAG, "setPlaceholderImage: no active renderer yet")
                                result.success(null)
                                return@setMethodCallHandler
                            }
                            renderer.setPlaceholderBitmap(bitmap)
                            result.success(null)
                        }

                        // "upgradeToScreenRecording" removed — dialog #2 and
                        // REQUEST_SCREEN_SHARE (1002) are gone. Any Dart-side
                        // caller of this action now hits MissingPluginException
                        // by design (see recorder_native_shared.dart, which
                        // treats that as expected on Android and continues
                        // waiting for screenLoopStarted from the 1001 grant).

                        "promoteForShare" -> {
                            ScreenCaptureService.onFgsPromoted?.invoke()
                            ScreenCaptureService.onFgsPromoted = null
                            result.success(null)
                        }

                        "revertToPlaceholder" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_REVERT_TO_PLACEHOLDER
                                })
                                result.success(null)
                            } catch (e: Exception) {
                                Log.e(TAG, "revertToPlaceholder: ${e.message}", e)
                                result.error("REVERT_ERROR", e.message, null)
                            }
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

                        // ── NEW: pauseRecording ───────────────────────────────
                        // Signals the chunk loop to finish the current chunk,
                        // upload it, then park until resumeRecording arrives.
                        // Safe to call even if already paused (no-op in that case).
                        "pauseRecording" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_PAUSE_RECORDING
                                })
                                Log.d(TAG, "pauseRecording sent")
                            } catch (e: Exception) {
                                Log.e(TAG, "pauseRecording: ${e.message}", e)
                            }
                            result.success(null)
                        }

                        // ── NEW: resumeRecording ──────────────────────────────
                        // Clears the pause flag and wakes the parked loop.
                        // Safe to call even if not paused (no-op in that case).
                        "resumeRecording" -> {
                            try {
                                startService(Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_RESUME_RECORDING
                                })
                                Log.d(TAG, "resumeRecording sent")
                            } catch (e: Exception) {
                                Log.e(TAG, "resumeRecording: ${e.message}", e)
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

        // ── 3b. Radios: the attendance sheet's "Turn on Bluetooth / Wi-Fi" buttons ──
        // Apps may not switch radios themselves; these open the SYSTEM dialog / panel for the person.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_RADIOS)
                .setMethodCallHandler { call, result ->
                    try {
                        when (call.method) {
                            "requestBluetoothOn" -> {
                                val adapter = getSystemService(BluetoothManager::class.java)?.adapter
                                if (adapter == null) { result.success(false); return@setMethodCallHandler }
                                if (adapter.isEnabled) { result.success(true); return@setMethodCallHandler }
                                // "Allow <app> to turn on Bluetooth?" — needs BLUETOOTH_CONNECT on Android 12+
                                startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            }
                            "openBluetoothSettings" -> {
                                startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            }
                            "openWifiPanel" -> {
                                val action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                                    Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
                                startActivity(Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(true)
                            }
                            else -> result.notImplemented()
                        }
                    } catch (e: Exception) {          // SecurityException (permission not granted yet) …
                        Log.w(TAG, "radios.${call.method} failed: ${e.message}")
                        result.success(false)        // … Dart falls back to the settings screen / a hint
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