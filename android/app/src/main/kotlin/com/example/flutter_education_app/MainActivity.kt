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
//
// A share no longer needs a recording: without one the service runs in
// share-only mode (projection + renderer, no MediaRecorder). A projection
// kept from an earlier share (a recording runs, below API 34) is reused with
// ACTION_START_SHARE, no dialog. Share / audio events reach Dart on
// CH_LIVE_EVENTS (shareStarted, shareStopped, shareResized, audioInterruption).
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
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.cloudwebrtc.webrtc.ElFaheemBridge

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"

        private const val CH_SCREEN_SHARE  = "com.example.flutter_education_app/screen_share"
        private const val CH_RECORDER      = "com.example.flutter_education_app/native_recorder"
        private const val CH_NOTIFICATIONS = "com.example.flutter_education_app/notifications"
        private const val CH_REC_EVENTS    = "com.example.flutter_education_app/rec_events"
        private const val CH_RADIOS        = "com.example.flutter_education_app/radios"   // attendance: switch radios on
        private const val CH_LIVE_EVENTS   = "com.example.flutter_education_app/live_events" // share + phone-call events

        // 1001: the one and only MediaProjection grant → ACTION_STORE_PROJECTION
        private const val REQUEST_MEDIA_PROJECTION = 1001
    }

    private var projectionManager: MediaProjectionManager? = null

    private var onRecorderProjectionApproved: ((Map<String, Any?>) -> Unit)? = null // 1001
    // The share preset of the pending request (forwarded with STORE_PROJECTION).
    private var pendingShareExtras: Intent.() -> Unit = {}
    private var audioInterruptions: LiveAudioInterruptions? = null
    // ScreenCaptureService was put in the foreground (microphone) before the consent dialog (M4).
    private var preparedForShare = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
    }

    // Back in front: a live-call service the background refused to start comes back now.
    override fun onResume() {
        super.onResume()
        LiveCallService.sync(this)
    }

    // The live-call notification's "Leave" (the app is in front again; Dart may confirm).
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getStringExtra(LiveCallService.EXTRA_LIVE_CALL_ACTION) == LiveCallService.LIVE_CALL_LEAVE) {
            intent.removeExtra(LiveCallService.EXTRA_LIVE_CALL_ACTION)
            LiveCallService.leaveRequested()
        }
    }

    /** D-090: the reused direct buffer of the whiteboard's recording frames ("pushBoardFrame"). */
    private var boardFrameBuffer: java.nio.ByteBuffer? = null

    /** D-108: the room's frames for the device recording, copied from Flutter's surface ("startRoomCapture"). */
    private var roomGrabber: RoomFrameGrabber? = null

    private fun roomRect(call: io.flutter.plugin.common.MethodCall): android.graphics.Rect? {
        val l = call.argument<Int>("left") ?: return null
        val t = call.argument<Int>("top") ?: return null
        val w = call.argument<Int>("width") ?: return null
        val h = call.argument<Int>("height") ?: return null
        if (w <= 0 || h <= 0) return null
        return android.graphics.Rect(l, t, l + w, t + h)
    }

    // L6: the audio-focus listener is static in ElFaheemBridge and its lambda holds the watcher; the
    // EventChannel's onCancel does not run when the Activity is destroyed with its engine. The room
    // goes with the engine, so the live-call service stops too.
    override fun onDestroy() {
        roomGrabber?.release()
        roomGrabber = null
        audioInterruptions?.stop()
        audioInterruptions = null
        LiveCallService.release(this)
        super.onDestroy()
    }

    /** M4: the consent did not lead to a share — the prepared (idle) capture service stops again. */
    private fun unprepareShare() {
        if (!preparedForShare) return
        preparedForShare = false
        if (ScreenCaptureService.isRunning || ScreenCaptureService.isSharing || ScreenCaptureService.isProjectionGranted) return
        try {
            stopService(Intent(this, ScreenCaptureService::class.java))
        } catch (e: Exception) {
            Log.w(TAG, "unprepareShare: ${e.message}")
        }
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
                    ScreenCaptureService.onProjectionGrantStored = { outcome ->
                        onRecorderProjectionApproved?.invoke(outcome)
                        onRecorderProjectionApproved = null
                    }

                    val i = Intent(this, ScreenCaptureService::class.java).apply {
                        action = ScreenCaptureService.ACTION_STORE_PROJECTION
                        putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                        putExtra(ScreenCaptureService.EXTRA_DATA, data)
                        pendingShareExtras()
                    }
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                            startForegroundService(i) else startService(i)
                        preparedForShare = false // the service owns its state from here
                    } catch (e: Exception) {
                        // e.g. ForegroundServiceStartNotAllowedException (12+): Dart must not wait forever.
                        Log.e(TAG, "onActivityResult(1001): could not start the service: ${e.message}", e)
                        ScreenCaptureService.onProjectionGrantStored = null
                        onRecorderProjectionApproved?.invoke(mapOf("ok" to false, "error" to (e.message ?: "service start failed")))
                        onRecorderProjectionApproved = null
                        unprepareShare()
                    }

                } else {
                    Log.w(TAG, "onActivityResult(1001): recorder projection denied (resultCode=$resultCode)")
                    onRecorderProjectionApproved?.invoke(mapOf("ok" to false, "denied" to true))
                    onRecorderProjectionApproved = null
                    unprepareShare() // STORE_PROJECTION is never sent
                }
            }
            // REQUEST_SCREEN_SHARE (1002) removed — was a second, redundant
            // MediaProjection dialog. ACTION_STORE_PROJECTION (triggered by
            // the 1001 grant above) already calls promoteForegroundToProjection()
            // itself, so there was nothing left for this second dialog to do.
            // See ScreenCaptureService.kt for the single remaining grant path.
        }
    }

    /**
     * M4: before the consent dialog, while this activity is in front, ScreenCaptureService goes into
     * the foreground with the microphone type (when no recording already holds it and RECORD_AUDIO is
     * granted). The STORE_PROJECTION that follows the consent then reaches a foreground service (no
     * background-start refusal) and the presenter's voice keeps going in other apps on 14+.
     */
    private fun prepareShare() {
        preparedForShare = false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        if (ScreenCaptureService.isRunning || ScreenCaptureService.isSharing || ScreenCaptureService.isProjectionGranted) return
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED) return
        try {
            startService(Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_PREPARE_SHARE
            })
            preparedForShare = true
        } catch (e: Exception) {
            Log.w(TAG, "prepareShare: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Flutter engine — method + event channels
    // ─────────────────────────────────────────────────────────────────────────

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AnnotationOverlayChannel.register(this, flutterEngine.dartExecutor.binaryMessenger) // D-079 whole-screen annotation
        LiveCallService.register(this, flutterEngine.dartExecutor.binaryMessenger) // the room's mic in the background

        // ── 1. Screen-share channel ───────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CH_SCREEN_SHARE)
                .setMethodCallHandler { call, result ->
                    when (call.method) {

                        // Starts a live share with the preset from Dart
                        // ({maxLongSide, fps, deviceAudio}) and answers
                        // {ok, denied?, error?, width, height, deviceAudio}
                        // once the share runs (or failed). With or without a
                        // recording; a projection kept from an earlier share
                        // is reused (no dialog), otherwise grant 1001 is asked.
                        "startScreenCaptureService" -> {
                            val maxLong = call.argument<Int>("maxLongSide") ?: 1280
                            val shortSide = call.argument<Int>("shortSide") ?: 0
                            val maxPixels = call.argument<Int>("maxPixels") ?: 0
                            val fps = call.argument<Int>("fps") ?: 15
                            val deviceAudio = call.argument<Boolean>("deviceAudio") ?: false
                            val extras: Intent.() -> Unit = {
                                putExtra(ScreenCaptureService.EXTRA_SHARE_MAX_LONG, maxLong)
                                putExtra(ScreenCaptureService.EXTRA_SHARE_SHORT, shortSide)
                                putExtra(ScreenCaptureService.EXTRA_SHARE_PIXELS, maxPixels)
                                putExtra(ScreenCaptureService.EXTRA_SHARE_FPS, fps)
                                putExtra(ScreenCaptureService.EXTRA_SHARE_AUDIO, deviceAudio)
                            }
                            if (ScreenCaptureService.isSharing) {
                                Log.d(TAG, "startScreenCaptureService: already sharing")
                                result.success(mapOf("ok" to true, "already" to true,
                                        "deviceAudio" to ElFaheemBridge.screenAudioState()))
                                return@setMethodCallHandler
                            }
                            if (ScreenCaptureService.isProjectionGranted) {
                                Log.d(TAG, "startScreenCaptureService: reusing the kept projection")
                                ScreenCaptureService.onProjectionGrantStored = { outcome -> result.success(outcome) }
                                try {
                                    startService(Intent(this, ScreenCaptureService::class.java).apply {
                                        action = ScreenCaptureService.ACTION_START_SHARE
                                        extras()
                                    })
                                } catch (e: Exception) {
                                    ScreenCaptureService.onProjectionGrantStored = null
                                    result.success(mapOf("ok" to false, "error" to e.message))
                                }
                                return@setMethodCallHandler
                            }
                            pendingShareExtras = extras
                            onRecorderProjectionApproved = { outcome -> result.success(outcome) }
                            prepareShare()
                            try {
                                @Suppress("DEPRECATION")
                                startActivityForResult(
                                        projectionManager!!.createScreenCaptureIntent(),
                                        REQUEST_MEDIA_PROJECTION,
                                )
                            } catch (e: Exception) {
                                Log.e(TAG, "startScreenCaptureService: ${e.message}", e)
                                onRecorderProjectionApproved = null
                                unprepareShare()
                                result.error("START_ERROR", e.message, null)
                            }
                        }

                        // Share off: releases the VirtualDisplay (and the projection unless a
                        // recording keeps it, below API 34). Idempotent.
                        "stopScreenShare", "stopScreenCaptureService" -> {
                            if (ScreenCaptureService.isSharing || ScreenCaptureService.isProjectionGranted) {
                                try {
                                    startService(Intent(this, ScreenCaptureService::class.java).apply {
                                        action = ScreenCaptureService.ACTION_STOP_SHARE
                                    })
                                } catch (e: Exception) {
                                    Log.e(TAG, "stopScreenShare: ${e.message}", e)
                                }
                            }
                            ElFaheemBridge.setMicSoftMute(false)
                            result.success(null)
                        }

                        // D-090: one frame of the presented whiteboard (RGBA, top-left origin) for its
                        // slow recording track (an ElFaheemFrameCapturer track Dart made with
                        // getDisplayMedia useElFaheemCapturer). No projection, no service: the frame goes
                        // straight to the active capturer. Never while a screen share runs (it owns it).
                        "pushBoardFrame" -> {
                            val bytes = call.argument<ByteArray>("rgba")
                            val w = call.argument<Int>("width") ?: 0
                            val h = call.argument<Int>("height") ?: 0
                            if (ScreenCaptureService.isSharing || bytes == null || w <= 0 || h <= 0 ||
                                    bytes.size < w * h * 4 || !ElFaheemBridge.hasCapturer()) {
                                result.success(false)
                            } else {
                                val buf = boardFrameBuffer?.takeIf { it.capacity() >= bytes.size }
                                        ?: java.nio.ByteBuffer.allocateDirect(bytes.size).also { boardFrameBuffer = it }
                                buf.clear()
                                buf.put(bytes, 0, w * h * 4)
                                buf.position(0)
                                ElFaheemBridge.pushFrame(buf, w, h, System.nanoTime())
                                result.success(true)
                            }
                        }

                        // What this device can do in the share flow.
                        "shareCapabilities" -> result.success(mapOf(
                                "deviceAudio" to ElFaheemBridge.screenAudioSupported(),
                                "sdk" to Build.VERSION.SDK_INT,
                                "keepsGrant" to (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE),
                        ))

                        "shareState" -> result.success(mapOf(
                                "sharing" to ScreenCaptureService.isSharing,
                                "projection" to ScreenCaptureService.isProjectionGranted,
                                "deviceAudio" to ElFaheemBridge.screenAudioState(),
                                "micSoftMuted" to ElFaheemBridge.isMicSoftMuted(),
                        ))

                        // The mic "soft mute" during a share with device audio: the mic's
                        // samples are zeroed, the track (carrying the shared audio) keeps going.
                        "setMicSoftMute" -> {
                            ElFaheemBridge.setMicSoftMute(call.argument<Boolean>("muted") ?: false)
                            result.success(null)
                        }

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
                            // The recorder start's id (native_epoch.md): sent with every chunk as `epoch`.
                            val epoch     = call.argument<Any>("epoch")?.toString() ?: ""
                            // Meeting recordings: the picked quality (absent for course sessions → 0 = defaults).
                            val videoBps  = call.argument<Int>("videoBitrate") ?: 0
                            val maxHeight = call.argument<Int>("maxHeight")    ?: 0
                            // Audio-only: an AAC MediaRecorder with no video source (see ScreenCaptureService).
                            val audioOnly = call.argument<Boolean>("audioOnly") ?: false
                            // Android 14+: the service's startForeground(MICROPHONE) throws without
                            // RECORD_AUDIO, and a startForegroundService() that never reaches
                            // startForeground crashes the app — refuse here, Dart reports the error.
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
                                    checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) !=
                                    android.content.pm.PackageManager.PERMISSION_GRANTED) {
                                Log.e(TAG, "startMicRecording: RECORD_AUDIO not granted")
                                result.error("MIC_PERMISSION", "Microphone permission is required to record", null)
                                return@setMethodCallHandler
                            }
                            try {
                                val i = Intent(this, ScreenCaptureService::class.java).apply {
                                    action = ScreenCaptureService.ACTION_START_MIC_ONLY
                                    putExtra(ScreenCaptureService.EXTRA_SESSION_ID,  sessionId)
                                    putExtra(ScreenCaptureService.EXTRA_UPLOAD_URL,  uploadUrl)
                                    putExtra(ScreenCaptureService.EXTRA_AUTH_TOKEN,  authToken)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_SECS,  chunkSecs)
                                    putExtra(ScreenCaptureService.EXTRA_CHUNK_INDEX, chunkIdx)
                                    putExtra(ScreenCaptureService.EXTRA_EPOCH,       epoch)
                                    putExtra(ScreenCaptureService.EXTRA_VIDEO_BPS,   videoBps)
                                    putExtra(ScreenCaptureService.EXTRA_MAX_HEIGHT,  maxHeight)
                                    putExtra(ScreenCaptureService.EXTRA_AUDIO_ONLY,  audioOnly)
                                }
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                                    startForegroundService(i) else startService(i)
                                Log.d(TAG, "startMicRecording: session=$sessionId  chunkSecs=$chunkSecs  audioOnly=$audioOnly")
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e(TAG, "startMicRecording: ${e.message}", e)
                                result.error("MIC_START_ERROR", e.message, null)
                            }
                        }

                        "getChunkIndex" -> result.success(ScreenCaptureService.currentChunkIndex)

                        // D-108: the room's frames copied natively from Flutter's surface at 30 fps (RoomFrameGrabber).
                        // Answers whether a first copy worked; false → Dart keeps sending its own frames.
                        "startRoomCapture" -> {
                            val rect = roomRect(call)
                            if (rect == null) {
                                result.error("BAD_ARGS", "left / top / width / height missing", null)
                                return@setMethodCallHandler
                            }
                            val renderer = ScreenCaptureService.placeholderRenderer
                            if (renderer == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val grabber = roomGrabber ?: RoomFrameGrabber(this).also { roomGrabber = it }
                            val answered = java.util.concurrent.atomic.AtomicBoolean(false)
                            val main = android.os.Handler(mainLooper)
                            val answer = { ok: Boolean ->
                                if (answered.compareAndSet(false, true)) main.post { result.success(ok) }
                            }
                            grabber.start(rect, renderer.encoderLongSide, answer)
                            // A copy that never answers (no frame on the surface yet) must not hold Dart.
                            main.postDelayed({
                                if (!answered.get()) { grabber.stop(); answer(false) }
                            }, 2_500)
                        }

                        "updateRoomCapture" -> {
                            roomGrabber?.update(roomRect(call), call.argument<Boolean>("active") ?: true)
                            result.success(null)
                        }

                        "stopRoomCapture" -> {
                            roomGrabber?.stop()
                            result.success(null)
                        }

                        // D-103: a raw RGBA frame of the room (~12 fps) — the recording's camera moves in real time.
                        "setPlaceholderFrame" -> {
                            val bytes = call.argument<ByteArray>("rgba")
                            val w = call.argument<Int>("width") ?: 0
                            val h = call.argument<Int>("height") ?: 0
                            if (bytes == null || w <= 0 || h <= 0) {
                                result.error("BAD_ARGS", "rgba / width / height missing", null)
                                return@setMethodCallHandler
                            }
                            ScreenCaptureService.placeholderRenderer?.setPlaceholderFrame(bytes, w, h)
                            result.success(null)
                        }

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

        // ── 3c. Share / phone-call events (room_screen_share.dart) ───────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, CH_LIVE_EVENTS)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                        Log.d(TAG, "live events: Dart is listening")
                        ScreenCaptureService.liveEventSink = sink
                        audioInterruptions?.stop()
                        audioInterruptions = LiveAudioInterruptions(this@MainActivity) { event ->
                            ScreenCaptureService.liveEventSink?.success(event)
                        }.also { it.start() }
                    }
                    override fun onCancel(args: Any?) {
                        Log.d(TAG, "live events: Dart cancelled")
                        ScreenCaptureService.liveEventSink = null
                        audioInterruptions?.stop()
                        audioInterruptions = null
                    }
                })

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