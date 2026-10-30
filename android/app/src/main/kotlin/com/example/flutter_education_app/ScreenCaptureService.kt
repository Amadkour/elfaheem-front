package com.example.flutter_education_app

import com.cloudwebrtc.webrtc.ElFaheemBridge
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.Display
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * The one MediaProjection of a live session, and the client-side recording.
 *
 * Two independent jobs share it:
 * - RECORDING (ACTION_START_MIC_ONLY … ACTION_STOP): one continuous encode
 *   (SegmentedRecorder, D-103) cut into ~5 s MP4 chunks at key frames, fed by
 *   ScreenPlaceholderRenderer (the room's frames until a share starts, the
 *   live screen while it runs), uploaded one by one with `seamless=1`; the
 *   old ping-pong MediaRecorder chunks remain only as the fallback.
 * - SCREEN SHARE (ACTION_STORE_PROJECTION / ACTION_START_SHARE …
 *   ACTION_STOP_SHARE): the projection's VirtualDisplay draws into the
 *   renderer, which hands scaled frames to the fork's ElFaheemFrameCapturer
 *   (the published LiveKit track) and, from API 29, the device audio to the
 *   mic mixer. Works with or without a recording.
 *
 * Share lifecycle:
 * - every share start switches the renderer to live (a second share works);
 * - share stop releases the VirtualDisplay; the projection itself is kept
 *   only while a recording runs AND below API 34 (a 34+ projection can make
 *   one VirtualDisplay only, so a later share asks again) — otherwise it is
 *   stopped, which also turns the system's privacy indicator off;
 * - the person stopping it from the system UI (chip, notification, cast
 *   tile) arrives in MediaProjection.Callback.onStop: the share is torn down
 *   and Dart gets `shareStopped` (reason "system") on CH_LIVE_EVENTS so it
 *   unpublishes the track; a running recording just continues on the
 *   placeholder;
 * - rotation (below 34: a DisplayListener) and Android 14's single-app
 *   share (onCapturedContentResize) resize the VirtualDisplay and the
 *   renderer's buffers (A12).
 */
class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID      = "screen_capture_channel"
        const val CHANNEL_NAME    = "Screen Capture"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_MIC_ONLY             = "com.example.flutter_education_app.START_MIC_ONLY"
        const val ACTION_STORE_PROJECTION           = "com.example.flutter_education_app.STORE_PROJECTION"
        const val ACTION_START_SHARE                = "com.example.flutter_education_app.START_SHARE"
        const val ACTION_STOP_SHARE                 = "com.example.flutter_education_app.STOP_SHARE"
        const val ACTION_STOP                       = "com.example.flutter_education_app.STOP_SCREEN_CAPTURE"
        const val ACTION_REVERT_TO_PLACEHOLDER      = "com.example.flutter_education_app.REVERT_TO_PLACEHOLDER"
        const val ACTION_DOWNGRADE_TO_MIC_FOR_SHARE = "com.example.flutter_education_app.DOWNGRADE_TO_MIC_FOR_SHARE"
        const val ACTION_DOWNGRADE_TO_MIC           = "com.example.flutter_education_app.DOWNGRADE_TO_MIC"
        const val ACTION_PROMOTE_FOR_SHARE          = "com.example.flutter_education_app.PROMOTE_FOR_SHARE"
        // MainActivity, right before the consent dialog (M4): a microphone-typed foreground start while the
        // activity is in front, so the STORE_PROJECTION that follows is never a background start.
        const val ACTION_PREPARE_SHARE              = "com.example.flutter_education_app.PREPARE_SHARE"

        // ── pause / resume recording ─────────────────────────────────────────
        // PAUSE  → finish current chunk (isFinal=false), stop encoding,
        //          park the projection, emit "recordingPaused".
        // RESUME → re-enter the chunk loop from where we left off,
        //          emit "recordingResumed".
        const val ACTION_PAUSE_RECORDING  = "com.example.flutter_education_app.PAUSE_RECORDING"
        const val ACTION_RESUME_RECORDING = "com.example.flutter_education_app.RESUME_RECORDING"

        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA        = "data"
        const val EXTRA_SESSION_ID  = "sessionId"
        const val EXTRA_UPLOAD_URL  = "uploadUrl"
        const val EXTRA_AUTH_TOKEN  = "authToken"
        const val EXTRA_CHUNK_SECS  = "chunkSeconds"
        const val EXTRA_IS_FINAL    = "isFinal"
        const val EXTRA_CHUNK_INDEX = "chunkIndex"
        /** The recorder start's id (ms, a new one per start): sent as the chunk field `epoch` (native_epoch.md). */
        const val EXTRA_EPOCH       = "epoch"
        // Meeting recordings (docs/backend/live-rooms-spec.md §5): the picked quality. 0 = the defaults below.
        const val EXTRA_VIDEO_BPS   = "videoBitrate"
        const val EXTRA_MAX_HEIGHT  = "maxHeight"
        // Audio-only (quality "audio"): MediaRecorder captures the mic alone — AAC in an MP4 container
        // (.m4a chunks), no video source / encoder surface, no MediaProjection needed for the recording.
        const val EXTRA_AUDIO_ONLY  = "audioOnly"
        // The share's preset (room_screen_share.dart → SharePreset): capture size cap, fps, device audio.
        const val EXTRA_SHARE_MAX_LONG = "shareMaxLongSide"
        // D-090: the share's size class is its SHORT side (1080 Detail / 720 Motion) + a pixel ceiling.
        const val EXTRA_SHARE_SHORT    = "shareShortSide"
        const val EXTRA_SHARE_PIXELS   = "shareMaxPixels"
        const val EXTRA_SHARE_FPS      = "shareFps"
        const val EXTRA_SHARE_AUDIO    = "shareAudio"

        private const val TAG       = "ScreenCaptureService"
        // A13: the course recording is 720p (longer side 1280) at ~2 Mbps unless the
        // meeting-recording quality says otherwise — it uploads on top of the live uplink.
        private const val VIDEO_BPS = 2_000_000
        private const val DEFAULT_MAX_LONG = 1280
        private const val VIDEO_FPS = 15
        private const val AUDIO_BPS = 192_000   // raised from 128k for cleaner chunk boundaries

        @Volatile var isRunning:               Boolean                 = false   // a recording runs
        @Volatile var isProjectionGranted:     Boolean                 = false   // a MediaProjection is held
        @Volatile var isSharing:               Boolean                 = false   // a VirtualDisplay feeds the share
        @Volatile var isPaused:                Boolean                 = false
        @Volatile var currentChunkIndex:       Int                     = 0
        @Volatile var eventSink:               EventChannel.EventSink? = null    // recorder events (rec_events)
        @Volatile var liveEventSink:           EventChannel.EventSink? = null    // share / audio events (live_events)
        /** Called once per share request with its outcome (MainActivity answers Dart with it). */
        @Volatile var onProjectionGrantStored: ((Map<String, Any?>) -> Unit)? = null
        @Volatile var onFgsPromoted:           (() -> Unit)?           = null
        @Volatile var placeholderRenderer:     ScreenPlaceholderRenderer? = null

        val pendingUploads = AtomicInteger(0)

        // Single-threaded executor — chunks always reach the server in order.
        val uploadExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "ChunkUploader").also { it.isDaemon = true }
        }

        /** A phone call took / gave back the mic (LiveAudioInterruptions): a marker in the recording's log. */
        fun markAudioInterruption(active: Boolean) {
            if (!isRunning) return
            if (active) Log.w(TAG, "REC MARKER: audio interrupted (phone call) at chunk #$currentChunkIndex — " +
                    "the recording's audio is silent until it ends")
            else Log.w(TAG, "REC MARKER: audio back at chunk #$currentChunkIndex")
        }

        private val mainHandler = Handler(Looper.getMainLooper())

        /** Sends a share / audio event to Dart (CH_LIVE_EVENTS); main thread. */
        fun emitLive(event: String, extra: Map<String, Any?> = emptyMap()) {
            mainHandler.post {
                try {
                    liveEventSink?.success(mapOf("event" to event) + extra)
                } catch (e: Exception) {
                    Log.w(TAG, "live event $event not delivered: ${e.message}")
                }
            }
        }
    }

    // ── recording state ───────────────────────────────────────────────────────
    private val shouldRecord      = AtomicBoolean(false)
    private val shouldStop        = AtomicBoolean(false)
    private val shouldPause       = AtomicBoolean(false)

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection:   MediaProjection?        = null
    private var virtualDisplay:    VirtualDisplay?         = null
    private var vdWidth  = 0
    private var vdHeight = 0
    /** Set right before WE stop the projection, so its onStop is not taken for the person's. */
    private var stoppingProjection = false
    private var displayListener: DisplayManager.DisplayListener? = null

    // Active recorder for the current chunk (may be swapped during ping-pong).
    private var mediaRecorder: MediaRecorder? = null

    private var sessionId  = 0
    private var uploadUrl  = ""
    private var authToken  = ""
    private var epoch      = ""          // EXTRA_EPOCH: the server orders assembly by (epoch, index)
    // 409 recording_assembled / a dead upload token: this run takes no more chunks (reset on every start).
    private val uploadsClosed = java.util.concurrent.atomic.AtomicBoolean(false)
    private var chunkSecs  = 5
    private var chunkIndex = 0
    private var videoBps   = VIDEO_BPS   // EXTRA_VIDEO_BPS when > 0
    private var maxHeight  = DEFAULT_MAX_LONG // EXTRA_MAX_HEIGHT: cap on the longer side
    private var audioOnly  = false       // EXTRA_AUDIO_ONLY: see prepareRecorder()

    // The share's preset (EXTRA_SHARE_*).
    private var shareMaxLong = 1280
    private var shareShort   = 0   // 0 = no short-side cap (an older Dart side)
    private var sharePixels  = 0   // 0 = no pixel ceiling
    private var shareFps     = 15
    private var shareAudio   = false

    private var screenWidth  = 1080
    private var screenHeight = 1920
    private var screenDpi    = 420

    // ── lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // The app was swiped away from recents: the same teardown as ACTION_STOP
    // (the chunk loop flags the last chunk is_final, drains the uploads and
    // stops the service), and the share ends — never a projection left
    // running for an engine that no longer exists.
    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.d(TAG, "onTaskRemoved — stopping the share and the recording")
        if (isSharing || mediaProjection != null) stopShare(reason = "task_removed", keepGrantIfRecording = false)
        requestStop()
        // The engine goes with the task: the process-static soft mute must not outlive it.
        ElFaheemBridge.setMicSoftMute(false)
        if (!isRunning) stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        LiveCallService.onCaptureForeground(this, false) // the live-call service takes the mic back
        shouldStop.set(true)
        shouldRecord.set(false)
        shouldPause.set(false)
        ElFaheemBridge.stopScreenAudio()
        // No room listens any more (its LiveMicGate clears it after a real mute otherwise, and a
        // new audio device module clears it too): never leave the next session's mic zeroed.
        if (liveEventSink == null) ElFaheemBridge.setMicSoftMute(false)
        unregisterDisplayListener()
        safeReleaseMedia()
        isRunning = false
        isProjectionGranted = false
        isSharing = false
        isPaused = false
        super.onDestroy()
    }

    // ── onStartCommand ────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {

            ACTION_START_MIC_ONLY -> {
                sessionId  = intent.getIntExtra(EXTRA_SESSION_ID,  0)
                uploadUrl  = intent.getStringExtra(EXTRA_UPLOAD_URL) ?: ""
                authToken  = intent.getStringExtra(EXTRA_AUTH_TOKEN) ?: ""
                epoch      = intent.getStringExtra(EXTRA_EPOCH) ?: ""
                uploadsClosed.set(false)
                chunkSecs  = intent.getIntExtra(EXTRA_CHUNK_SECS,   5)
                chunkIndex = intent.getIntExtra(EXTRA_CHUNK_INDEX,  0)
                videoBps   = intent.getIntExtra(EXTRA_VIDEO_BPS, 0).let { if (it > 0) it else VIDEO_BPS }
                maxHeight  = intent.getIntExtra(EXTRA_MAX_HEIGHT, 0).let { if (it > 0) it else DEFAULT_MAX_LONG }
                audioOnly  = intent.getBooleanExtra(EXTRA_AUDIO_ONLY, false)
                pendingUploads.set(0)
                Log.d(TAG, "ACTION_START_MIC_ONLY session=$sessionId chunkSecs=$chunkSecs audioOnly=$audioOnly " +
                        "video=${videoBps / 1000}kbps ≤${maxHeight}px")
                try {
                    cacheDir.listFiles()?.forEach { f ->
                        if (f.isDirectory && f.name.startsWith("session_") &&
                                f.name != "session_$sessionId") {
                            f.deleteRecursively()
                            Log.d(TAG, "swept stale dir: ${f.name}")
                        }
                    }
                } catch (_: Exception) {}
                resolveScreenMetrics()
                if (!startForegroundMicOnly()) {
                    // No microphone foreground service (Android 14+ without
                    // RECORD_AUDIO): Dart got the error event, nothing records.
                    if (!isRunning && !isSharing) {
                        foregroundBeforeStop()
                        stopSelf()
                    }
                    return START_NOT_STICKY
                }
                isRunning = true

                // Single-MediaProjection architecture: recording (with a
                // placeholder in place of real screen content) starts here,
                // immediately, with no dialog. A share already running
                // (shared before the recording started) keeps its renderer:
                // the recording then shows the live screen from chunk 0.
                if (uploadUrl.isEmpty()) {
                    Log.e(TAG, "uploadUrl empty — cannot start placeholder recording")
                } else if (shouldRecord.get()) {
                    Log.w(TAG, "already recording — ignoring duplicate START_MIC_ONLY")
                } else {
                    val renderer = ensureRenderer()
                    // Audio-only: the recorder never gets an encoder surface
                    // (prepareRecorder skips attachEncoderSurface); the renderer
                    // keeps an offscreen output so a share still works.
                    if (audioOnly) renderer.attachOffscreenOutput(screenWidth, screenHeight)

                    shouldStop.set(false)
                    shouldPause.set(false)
                    shouldRecord.set(true)
                    isPaused = false

                    Thread({ recordLoop() }, "ScreenRecorder").start()
                }
            }

            ACTION_STORE_PROJECTION -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data: Intent? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                        else
                            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)
                readShareExtras(intent)
                Log.d(TAG, "ACTION_STORE_PROJECTION resultCode=$resultCode recording=$isRunning " +
                        "preset=≤${shareMaxLong}px@${shareFps}fps audio=$shareAudio")

                if (resultCode == 0 || data == null) {
                    Log.e(TAG, "invalid grant — aborting")
                    answerShare(false, "MediaProjection grant invalid")
                    answerForegroundStart()
                    return START_NOT_STICKY
                }
                if (mediaProjection != null) {
                    // A projection is still held (kept for a running recording below
                    // API 34): this new grant is not needed — reuse the old one.
                    Log.w(TAG, "projection already held — reusing it for this share")
                    answerForegroundStart()
                    startLiveShare()
                    return START_NOT_STICKY
                }

                try {
                    promoteForegroundToProjection()
                } catch (e: Exception) {
                    Log.e(TAG, "promoteForegroundToProjection failed: ${e.message}", e)
                    answerShare(false, "Could not start screen capture: ${e.message}")
                    if (!isRunning && !isSharing) {
                        foregroundBeforeStop()
                        stopSelf()
                    }
                    return START_NOT_STICKY
                }
                activateLiveProjection(resultCode, data)
            }

            ACTION_PREPARE_SHARE -> {
                // Sent with startService (the activity is in front) and only while nothing runs here:
                // a refused start just stops the service again.
                if (isRunning || isSharing || mediaProjection != null) return START_NOT_STICKY
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        startForegroundTyped(ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
                    Log.d(TAG, "ACTION_PREPARE_SHARE — in the foreground (microphone) before the consent")
                } catch (e: Exception) {
                    Log.w(TAG, "ACTION_PREPARE_SHARE refused: ${e.message}")
                    stopSelf()
                }
            }

            ACTION_START_SHARE -> {
                // Share again on the projection kept from an earlier share (no dialog).
                readShareExtras(intent)
                Log.d(TAG, "ACTION_START_SHARE (kept projection) preset=≤${shareMaxLong}px@${shareFps}fps audio=$shareAudio")
                if (mediaProjection == null) {
                    answerShare(false, "No screen capture permission is held")
                } else {
                    startLiveShare()
                }
            }

            ACTION_STOP_SHARE, ACTION_REVERT_TO_PLACEHOLDER -> {
                Log.d(TAG, "${intent.action} — share off")
                stopShare(reason = "user", keepGrantIfRecording = true)
            }

            ACTION_STOP -> {
                Log.d(TAG, "ACTION_STOP — signalling chunk loop")
                requestStop()
            }

            ACTION_DOWNGRADE_TO_MIC_FOR_SHARE -> {
                Log.d(TAG, "ACTION_DOWNGRADE_TO_MIC_FOR_SHARE")
                mainHandler.post { emitMicReadyForShare() }
            }

            ACTION_DOWNGRADE_TO_MIC -> {
                Log.d(TAG, "ACTION_DOWNGRADE_TO_MIC")
                mainHandler.post { emitMicLoopStarted() }
            }

            ACTION_PROMOTE_FOR_SHARE -> {
                Log.d(TAG, "ACTION_PROMOTE_FOR_SHARE")
                mainHandler.post { onFgsPromoted?.invoke(); onFgsPromoted = null }
            }

            // Signals the chunk loop to finish the current chunk, upload it with
            // isFinal=false, then park (sleep) until RESUME or STOP arrives.
            ACTION_PAUSE_RECORDING -> {
                if (!shouldRecord.get() || shouldStop.get()) {
                    Log.w(TAG, "PAUSE ignored — not recording")
                    return START_NOT_STICKY
                }
                if (shouldPause.get()) {
                    Log.w(TAG, "PAUSE ignored — already paused")
                    return START_NOT_STICKY
                }
                Log.d(TAG, "ACTION_PAUSE_RECORDING")
                shouldPause.set(true)
            }

            // Clears the pause flag and wakes the parked chunk loop.
            ACTION_RESUME_RECORDING -> {
                // Gated on the recorder, not on the screen grant: a recording
                // paused before the first share (or an audio-only meeting)
                // has no projection and must still resume.
                if (!isRunning || !shouldRecord.get() || shouldStop.get()) {
                    Log.w(TAG, "RESUME ignored — not in a pauseable state")
                    return START_NOT_STICKY
                }
                if (!shouldPause.get()) {
                    Log.w(TAG, "RESUME ignored — not paused")
                    return START_NOT_STICKY
                }
                Log.d(TAG, "ACTION_RESUME_RECORDING")
                shouldRecord.set(true)
                shouldPause.set(false)
                isPaused = false
                synchronized(this) { (this as Object).notifyAll() }
            }

            else -> {
                // Unknown / null action: satisfy a startForegroundService()
                // call, but never pretend a recording runs.
                answerForegroundStart()
            }
        }
        // Not sticky: a restart after the process died would come back with
        // a null intent and no session to record (a zombie foreground service).
        return START_NOT_STICKY
    }

    private fun readShareExtras(intent: Intent) {
        shareMaxLong = intent.getIntExtra(EXTRA_SHARE_MAX_LONG, 1280).coerceIn(320, 3840)
        shareShort   = intent.getIntExtra(EXTRA_SHARE_SHORT, 0).let { if (it <= 0) 0 else it.coerceIn(180, 2160) }
        sharePixels  = intent.getIntExtra(EXTRA_SHARE_PIXELS, 0).let { if (it <= 0) 0 else it.coerceIn(100_000, 8_294_400) }
        shareFps     = intent.getIntExtra(EXTRA_SHARE_FPS, 15).coerceIn(1, 30)
        shareAudio   = intent.getBooleanExtra(EXTRA_SHARE_AUDIO, false)
    }

    /** The renderer both jobs draw through; created by whichever comes first. */
    private fun ensureRenderer(): ScreenPlaceholderRenderer {
        placeholderRenderer?.let { return it }
        return ScreenPlaceholderRenderer(
                onLiveFrameForCapturer = { w, h, rgba ->
                    ElFaheemBridge.pushFrame(rgba, w, h, System.nanoTime())
                },
        ).also {
            it.start(screenWidth, screenHeight)
            // No encoder yet: an offscreen output keeps the draw clock (and the
            // share's capture pass) running; the recording attaches its encoder.
            it.attachOffscreenOutput(screenWidth, screenHeight)
            placeholderRenderer = it
        }
    }

    // ── FGS helpers ───────────────────────────────────────────────────────────

    private fun hasRecordAudio(): Boolean =
            checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    private fun hasCamera(): Boolean =
            checkSelfPermission(android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    /**
     * The foreground-service type for the current state: mediaProjection while
     * a projection is held (API 29+), microphone (API 30+, with RECORD_AUDIO)
     * while recording or sharing — WebRTC's mic and the device-audio capture
     * keep working while the person is in another app.
     *
     * D-094: camera too (API 30+, with CAMERA) while a projection is held. The
     * room keeps the camera on while the screen is shared (LiveBackgroundCamera),
     * but from Android 11 a background app may use the camera only through a
     * foreground service of type camera that was started while the app was in
     * front — without it the presenter's camera froze for everyone the moment
     * they left the app to show another one. The type only keeps access; the
     * camera itself is still opened (or not) by the room.
     */
    private fun foregroundType(withProjection: Boolean): Int {
        var type = 0
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && withProjection)
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && hasRecordAudio())
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && withProjection && hasCamera())
            type = type or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
        return type
    }

    private fun startForegroundTyped(type: Int) {
        val camera = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                (type and ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA) != 0
        if (camera) {
            try {
                startForeground(NOTIFICATION_ID, buildNotification(), type)
                afterForeground(type)
                return
            } catch (e: Exception) {
                // The camera type can be refused (while-in-use rules: the app is not in front): the same call
                // without it — the share and the microphone matter more than the camera.
                Log.w(TAG, "startForeground with the camera type refused: ${e.message} — without it")
            }
            startForegroundTyped(type and ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA.inv())
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && type != 0)
            startForeground(NOTIFICATION_ID, buildNotification(), type)
        else
            startForeground(NOTIFICATION_ID, buildNotification())
        afterForeground(type)
    }

    private fun afterForeground(type: Int) {
        // This service now holds the microphone type: the live-call service steps aside.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && (type and ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE) != 0)
            LiveCallService.onCaptureForeground(this, true)
    }

    /**
     * The recording's foreground service. Returns false, with the error event
     * sent to Dart, when it cannot start: Android 14+ throws on
     * startForeground(MICROPHONE) without RECORD_AUDIO, which crashed the app.
     */
    private fun startForegroundMicOnly(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE && !hasRecordAudio()) {
            Log.e(TAG, "RECORD_AUDIO not granted — no microphone foreground service")
            mainHandler.post { emitError("Microphone permission is required to record") }
            return false
        }
        return try {
            startForegroundTyped(foregroundType(withProjection = mediaProjection != null))
            true
        } catch (e: Exception) {
            Log.e(TAG, "startForeground(microphone) failed: ${e.message}", e)
            mainHandler.post { emitError("Could not start the recording service: ${e.message}") }
            false
        }
    }

    /**
     * MediaProjection needs a mediaProjection-typed foreground service from
     * API 29 (MediaProjection.start() throws on 10–13 otherwise), BEFORE
     * getMediaProjection(). Called right after the consent dialog, with the
     * activity in front, so the microphone type may be added too.
     */
    private fun promoteForegroundToProjection() {
        try {
            startForegroundTyped(foregroundType(withProjection = true))
        } catch (e: Exception) {
            // The microphone type can be refused (while-in-use rules): projection alone.
            Log.w(TAG, "startForeground(projection+mic) refused: ${e.message} — projection only")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            else
                startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    /** The state changed (share on / off, recording ended): same notification, current type. */
    private fun refreshForeground() {
        if (!isRunning && !isSharing && mediaProjection == null) return
        try {
            startForegroundTyped(foregroundType(withProjection = mediaProjection != null))
        } catch (e: Exception) {
            Log.w(TAG, "refreshForeground: ${e.message}")
        }
    }

    /**
     * STORE_PROJECTION (and an unknown action) arrives through
     * startForegroundService(): every branch must call startForeground, also
     * the ones that give up — stopping without it crashes the app
     * ("did not then call Service.startForeground"). Stops the service again
     * when nothing records or shares.
     */
    private fun answerForegroundStart() {
        val ok = try {
            when {
                mediaProjection != null || isRunning -> startForegroundTyped(foregroundType(mediaProjection != null))
                // Idle service: the user has just granted the projection
                // (MainActivity sends STORE_PROJECTION on RESULT_OK only), so
                // the mediaProjection type is allowed; no microphone needed.
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    startForeground(NOTIFICATION_ID, buildNotification(),
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                else -> startForeground(NOTIFICATION_ID, buildNotification())
            }
            true
        } catch (e: Exception) {
            Log.e(TAG, "answerForegroundStart: ${e.message}", e)
            false
        }
        if (!isRunning && !isSharing && mediaProjection == null) {
            if (!ok) foregroundBeforeStop()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /**
     * Before a stopSelf() that follows a startForegroundService() whose
     * startForeground threw: a service that stops without ever having been
     * in the foreground crashes the app. The first type accepted wins: the
     * projection type (valid right after the consent), the microphone type
     * (with RECORD_AUDIO), then the plain call (the manifest's types; always
     * accepted below Android 14). Stopping follows at once.
     */
    private fun foregroundBeforeStop() {
        val types = mutableListOf<Int>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            types += ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && hasRecordAudio())
            types += ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        types += 0 // startForegroundTyped(0) = the plain call
        for (type in types) {
            try {
                startForegroundTyped(type)
                Log.d(TAG, "foregroundBeforeStop: foreground with type $type, stopping")
                return
            } catch (e: Exception) {
                Log.w(TAG, "foregroundBeforeStop: type $type refused: ${e.message}")
            }
        }
        Log.e(TAG, "foregroundBeforeStop: no foreground type accepted")
    }

    /** ACTION_STOP / onTaskRemoved: the chunk loop finishes the current chunk (is_final), drains and stops. */
    private fun requestStop() {
        shouldStop.set(true)
        shouldRecord.set(false)
        shouldPause.set(false)
        // If currently paused, wake the park-loop so it can exit cleanly.
        synchronized(this) { (this as Object).notifyAll() }
    }

    // ── screen metrics ────────────────────────────────────────────────────────

    private fun resolveScreenMetrics() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val rawW: Int; val rawH: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            rawW = b.width(); rawH = b.height()
            screenDpi = resources.displayMetrics.densityDpi
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getMetrics(dm)
            rawW = dm.widthPixels; rawH = dm.heightPixels; screenDpi = dm.densityDpi
        }
        fun align16(v: Int) = (v and 0xFFF0).coerceAtLeast(16)
        screenWidth  = align16(rawW)
        screenHeight = align16(rawH)
        Log.d(TAG, "screen: raw=${rawW}x${rawH} → ${screenWidth}x${screenHeight} dpi=$screenDpi")
    }

    /** The default display's real size in its CURRENT rotation (what the VirtualDisplay mirrors). */
    private fun currentDisplaySize(): Pair<Int, Int> {
        return try {
            val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
            val display = dm.getDisplay(Display.DEFAULT_DISPLAY)
            val metrics = DisplayMetrics()
            @Suppress("DEPRECATION") display.getRealMetrics(metrics)
            screenDpi = metrics.densityDpi
            metrics.widthPixels to metrics.heightPixels
        } catch (e: Exception) {
            screenWidth to screenHeight
        }
    }

    // ── main recording loop ───────────────────────────────────────────────────
    //
    // Uses a PING-PONG (dual-buffer) MediaRecorder strategy to eliminate the
    // audio gap between chunks:
    //
    //   1. Prepare recorder N+1 WHILE recorder N is still encoding.
    //   2. Call recorderNext.start() first (audio capture begins immediately).
    //   3. Re-point ScreenPlaceholderRenderer's output at the new recorder's surface.
    //   4. Only then call recorderCurrent.stop() — the gap is now microseconds.
    //
    // On PAUSE: finish the in-progress chunk, upload it (isFinal=false), release
    //   the MediaRecorder but keep the renderer (and any share) alive so RESUME
    //   can re-enter without a second system dialog.
    //
    // On RESUME: re-enter the while-loop; a fresh MediaRecorder is prepared and
    //   recording continues from the next chunk index.
    //
    // The person stopping the share from the system UI does NOT end the
    // recording any more (it used to: projectionRevoked broke this loop).

    private fun recordLoop() {
        Log.d(TAG, "recordLoop started (placeholder) — ${screenWidth}x${screenHeight} chunkSecs=$chunkSecs")
        val sessionDir = File(cacheDir, "session_$sessionId").also { it.mkdirs() }
        // D-103: one continuous encode cut into chunks (gapless). MediaRecorder ping-pong only where the device's
        // encoders / mic cannot be driven directly.
        if (recordLoopSegmented(sessionDir)) return
        Log.w(TAG, "continuous recorder unavailable — falling back to MediaRecorder chunks")
        recordLoopLegacy(sessionDir)
    }

    /**
     * D-103: [SegmentedRecorder] runs ONE H.264 + ONE AAC encoder for the whole recording (until a pause) and only
     * switches the MP4 file at a key frame every ~[chunkSecs]: no frame or sample is lost or doubled at a chunk
     * boundary, and each chunk is uploaded with `seamless=1` so the server joins them with a stream copy on the audio
     * clock. Returns false (nothing recorded yet) when the recorder cannot start — the caller falls back.
     */
    private fun recordLoopSegmented(sessionDir: File): Boolean {
        var finishingAsFinal = false
        var finalSent = false

        fun newRecorder(): SegmentedRecorder {
            val (encW, encH) = encoderSize()
            return SegmentedRecorder(
                    audioOnly = audioOnly,
                    width = encW, height = encH,
                    videoBps = videoBps, fps = VIDEO_FPS, audioBps = AUDIO_BPS,
                    segmentSecs = chunkSecs,
                    firstIndex = chunkIndex,
                    tmpFileFor = { tmpFile(sessionDir, it) },
                    onSegment = onSegment@{ tmp, index, last ->
                        val out = chunkFile(sessionDir, index)
                        out.delete()
                        if (!tmp.renameTo(out)) {
                            Log.w(TAG, "chunk #$index could not be finalised — dropped")
                            tmp.delete()
                            return@onSegment
                        }
                        val isFinal = last && finishingAsFinal
                        if (isFinal) finalSent = true
                        currentChunkIndex = index + 1
                        Log.d(TAG, "chunk #$index ready (${out.length()}B) final=$isFinal — queuing upload")
                        uploadChunkAsync(out, index, isFinal, seamless = true)
                    },
            )
        }

        fun startOne(): SegmentedRecorder? {
            val r = newRecorder()
            return try {
                r.start()
                r.inputSurface?.let { s ->
                    val (encW, encH) = encoderSize()
                    placeholderRenderer!!.attachEncoderSurface(s, encW, encH)
                }
                r
            } catch (e: Exception) {
                Log.e(TAG, "continuous recorder could not start: ${e.message}", e)
                null
            }
        }

        var rec = startOne() ?: return false
        Log.d(TAG, "continuous recorder started at chunk #$chunkIndex")
        mainHandler.post { emitScreenLoopStarted() }

        while (true) {
            while (!shouldStop.get() && !shouldPause.get()) Thread.sleep(50)
            val stopping = shouldStop.get()
            // The renderer stops drawing into the encoder before the encoder goes away (a share keeps running).
            if (!audioOnly) placeholderRenderer?.detachEncoderSurfaceForPause()
            finishingAsFinal = stopping
            rec.finish()
            chunkIndex = rec.nextIndex
            currentChunkIndex = chunkIndex
            if (stopping) break

            isPaused = true
            mainHandler.post { emitRecordingPaused() }
            Log.d(TAG, "recording PAUSED at chunk #$chunkIndex")
            synchronized(this) {
                while (shouldPause.get() && !shouldStop.get()) {
                    try { (this as Object).wait(1_000) } catch (_: InterruptedException) { break }
                }
            }
            if (shouldStop.get()) {
                Log.d(TAG, "exiting from paused state — stop received")
                break
            }
            Log.d(TAG, "recording RESUMED at chunk #$chunkIndex")
            mainHandler.post { emitRecordingResumed() }
            rec = startOne() ?: run {
                mainHandler.post { emitError("Resume failed") }
                null
            } ?: break
        }

        // The last chunk went up non-final (stopped while paused, or the last file could not be written): an empty
        // final chunk tells the server to assemble now (the same finalize ping iOS sends).
        if (!finalSent) {
            val ping = File(sessionDir, "final_ping_${chunkIndex}.${chunkExt()}")
            try {
                ping.writeBytes(ByteArray(0))
                uploadChunkAsync(ping, chunkIndex, true, seamless = true)
            } catch (e: Exception) {
                Log.w(TAG, "finalize ping not queued: ${e.message}")
            }
        }

        Log.d(TAG, "all chunks recorded — waiting for ${pendingUploads.get()} upload(s)…")
        val deadline = System.currentTimeMillis() + 120_000L
        while (pendingUploads.get() > 0 && System.currentTimeMillis() < deadline) Thread.sleep(200)
        if (pendingUploads.get() > 0) Log.w(TAG, "${pendingUploads.get()} upload(s) unfinished after 120 s")
        mainHandler.post { onRecordingFinished() }
        Log.d(TAG, "recordLoop done")
        return true
    }

    /** The pre-D-103 MediaRecorder ping-pong (one recorder per chunk): the fallback only. */
    private fun recordLoopLegacy(sessionDir: File) {
        val chunkDurationMs = chunkSecs * 1_000L

        // Prepare the very first recorder before signalling Dart, so that
        // emitScreenLoopStarted() fires only when audio is truly capturing.
        // Wrapped: an exception here, on this thread, used to kill the whole
        // process. Now Dart gets the error event and the recording stops.
        var currentRecorder = try {
            prepareRecorder(sessionDir, chunkIndex).also { it.start() }
        } catch (e: Exception) {
            Log.e(TAG, "first MediaRecorder prepare/start failed: ${e.message}", e)
            mainHandler.post { emitError("Recording could not start: ${e.message}") }
            shouldRecord.set(false)
            shouldStop.set(true)
            releaseRecorder()
            mainHandler.post { onRecordingFinished() }
            return
        }
        Log.d(TAG, "MediaRecorder.start() chunk #$chunkIndex (first)")
        mainHandler.post { emitScreenLoopStarted() }

        outer@ while (true) {

            val t0 = System.currentTimeMillis()
            while (System.currentTimeMillis() - t0 < chunkDurationMs) {
                when {
                    shouldStop.get()  -> break
                    shouldPause.get() -> break   // exit timing window early on pause
                }
                Thread.sleep(50)
            }

            val outFile = chunkFile(sessionDir, chunkIndex)
            val tmpFile = tmpFile(sessionDir, chunkIndex)

            // Determine final BEFORE ping-pong so we pick up any stop/pause
            // signal that arrived during the timing window.
            val stopping = shouldStop.get()
            val pausing  = shouldPause.get() && !stopping
            val isFinal  = stopping   // isFinal=true only on hard stop

            var nextRecorder: MediaRecorder? = null
            if (!stopping && !pausing) {
                // Seamless transition — prepare next chunk recorder while
                // current is still encoding (zero-gap swap). prepareRecorder()
                // re-points the renderer's encoder output; the VirtualDisplay
                // always targets the renderer's stable input surface.
                try {
                    nextRecorder = prepareRecorder(sessionDir, chunkIndex + 1)
                    nextRecorder.start()
                    Log.d(TAG, "MediaRecorder.start() chunk #${chunkIndex + 1} (next)")
                } catch (e: Exception) {
                    Log.e(TAG, "ping-pong prepare failed: ${e.message} — will stop after this chunk")
                    nextRecorder?.release()
                    nextRecorder = null
                }
            }

            var stopOk = false
            try {
                currentRecorder.stop()
                stopOk = true
                Log.d(TAG, "MediaRecorder.stop() chunk #$chunkIndex (${tmpFile.length()}B)")
            } catch (e: Exception) {
                Log.w(TAG, "recorder.stop() chunk #$chunkIndex failed: ${e.message} — discarding")
            } finally {
                currentRecorder.release()
                mediaRecorder = null
            }

            if (stopOk && tmpFile.exists() && tmpFile.length() > 0L) {
                tmpFile.renameTo(outFile)
                Log.d(TAG, "chunk #$chunkIndex finalised → ${outFile.name} (${outFile.length()}B)")
            } else {
                tmpFile.delete()
            }

            if (outFile.exists() && outFile.length() > 0L) {
                Log.d(TAG, "queuing upload chunk #$chunkIndex isFinal=$isFinal pausing=$pausing")
                uploadChunkAsync(outFile, chunkIndex, isFinal)
            } else {
                Log.w(TAG, "chunk #$chunkIndex is empty — skipping upload")
            }

            chunkIndex++
            currentChunkIndex = chunkIndex

            when {
                stopping -> {
                    nextRecorder?.release()
                    break@outer
                }
                pausing -> {
                    // Re-point the renderer's output at an offscreen pbuffer
                    // BEFORE parking: the released recorder's surface is dead.
                    // Pausing the local recording must never freeze what
                    // viewers of a share see.
                    placeholderRenderer?.detachEncoderSurfaceForPause()
                    isPaused = true
                    mainHandler.post { emitRecordingPaused() }
                    Log.d(TAG, "recording PAUSED at chunk #$chunkIndex")

                    synchronized(this) {
                        while (shouldPause.get() && !shouldStop.get()) {
                            try { (this as Object).wait(1_000) }
                            catch (_: InterruptedException) { break }
                        }
                    }

                    if (shouldStop.get()) {
                        Log.d(TAG, "exiting from paused state — stop received")
                        break@outer
                    }

                    Log.d(TAG, "recording RESUMED at chunk #$chunkIndex")
                    mainHandler.post { emitRecordingResumed() }

                    try {
                        currentRecorder = prepareRecorder(sessionDir, chunkIndex)
                        currentRecorder.start()
                        Log.d(TAG, "MediaRecorder.start() chunk #$chunkIndex (resumed)")
                    } catch (e: Exception) {
                        Log.e(TAG, "resume: prepareRecorder failed: ${e.message}")
                        mainHandler.post { emitError("Resume failed: ${e.message}") }
                        break@outer
                    }
                }
                nextRecorder != null -> {
                    currentRecorder = nextRecorder
                }
                else -> {
                    break@outer
                }
            }
        }

        releaseRecorder()

        // Drain pending uploads (max 120 s).
        Log.d(TAG, "all chunks recorded — waiting for ${pendingUploads.get()} upload(s)…")
        val deadline = System.currentTimeMillis() + 120_000L
        while (pendingUploads.get() > 0 && System.currentTimeMillis() < deadline) {
            Thread.sleep(200)
        }
        if (pendingUploads.get() > 0)
            Log.w(TAG, "${pendingUploads.get()} upload(s) unfinished after 120 s")

        mainHandler.post { onRecordingFinished() }
        Log.d(TAG, "recordLoop done")
    }

    /**
     * Main thread, after the chunk loop ended: a share still running keeps
     * the service (and the renderer, offscreen again); otherwise everything
     * is released and the service stops.
     */
    private fun onRecordingFinished() {
        isRunning = false
        isPaused = false
        if (isSharing) {
            Log.d(TAG, "recording finished — the share continues")
            placeholderRenderer?.attachOffscreenOutput(screenWidth, screenHeight)
            refreshForeground()
            return
        }
        safeReleaseMedia()
        isProjectionGranted = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    // ── screen share ──────────────────────────────────────────────────────────

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            if (stoppingProjection) {
                stoppingProjection = false
                Log.d(TAG, "MediaProjection stopped (by us)")
                return
            }
            // The person stopped it from the system UI (status-bar chip,
            // notification, cast tile) or the system revoked it. The share
            // ends; a recording continues on the placeholder.
            Log.w(TAG, "MediaProjection stopped by the system / the person")
            mediaProjection = null
            isProjectionGranted = false
            stopShare(reason = "system", keepGrantIfRecording = false)
        }

        override fun onCapturedContentResize(width: Int, height: Int) {
            // API 34+: the captured area changed (rotation, or the single app
            // the person picked was resized).
            Log.d(TAG, "onCapturedContentResize ${width}x$height")
            resizeShare(width, height)
        }

        override fun onCapturedContentVisibilityChanged(isVisible: Boolean) {
            Log.d(TAG, "captured content visible=$isVisible")
            emitLive("shareContentVisible", mapOf("visible" to isVisible))
        }
    }

    // Called once per grant: obtains the projection, then starts the share on it.
    private fun activateLiveProjection(resultCode: Int, data: Intent) {
        val projection = try {
            projectionManager!!.getMediaProjection(resultCode, data)
        } catch (e: Exception) {
            Log.e(TAG, "getMediaProjection failed: ${e.message}", e); null
        }
        if (projection == null) {
            Log.e(TAG, "null MediaProjection — cannot share")
            answerShare(false, "Could not obtain MediaProjection")
            if (!isRunning) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
            return
        }
        // Registered on every API level, before createVirtualDisplay (required on 34+).
        projection.registerCallback(projectionCallback, mainHandler)
        mediaProjection = projection
        isProjectionGranted = true
        startLiveShare()
    }

    /** A VirtualDisplay on the held projection → the renderer → the share track (+ device audio). */
    private fun startLiveShare() {
        val projection = mediaProjection ?: return answerShare(false, "No MediaProjection")
        if (screenWidth <= 0) resolveScreenMetrics()
        val renderer = ensureRenderer()
        renderer.configureCapture(shareMaxLong, shareFps, shareShort, sharePixels)

        if (virtualDisplay == null) {
            val (w, h) = currentDisplaySize()
            renderer.setInputSize(w, h)
            try {
                virtualDisplay = projection.createVirtualDisplay(
                        "ScreenCapture",
                        w, h, screenDpi,
                        DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                        renderer.inputSurface, null, null,
                )
                vdWidth = w
                vdHeight = h
                Log.d(TAG, "VirtualDisplay created (live) ${w}x${h}@${screenDpi}dpi")
            } catch (e: Exception) {
                // e.g. API 34+: a projection makes ONE VirtualDisplay; a kept one cannot share again.
                Log.e(TAG, "createVirtualDisplay failed: ${e.message}", e)
                releaseProjection()
                answerShare(false, "Could not start live screen capture")
                if (!isRunning) { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
                return
            }
        }
        isSharing = true
        renderer.switchToLive()
        registerDisplayListener()

        val audioState = when {
            !shareAudio -> "off"
            !ElFaheemBridge.screenAudioSupported() -> "unsupported"
            !hasRecordAudio() -> "no_permission"
            else -> ElFaheemBridge.startScreenAudio(projection)
        }
        Log.i(TAG, "share started ${vdWidth}x$vdHeight short≤$shareShort px≤$sharePixels long≤${shareMaxLong}px" +
                "@${shareFps}fps device audio: $audioState")
        refreshForeground()

        if (isRunning) mainHandler.post { emitScreenLoopStarted() } // the recorder's Phase-2 wait
        answerShare(true, null, mapOf("width" to vdWidth, "height" to vdHeight, "deviceAudio" to audioState))
        emitLive("shareStarted", mapOf("width" to vdWidth, "height" to vdHeight, "deviceAudio" to audioState))
    }

    /**
     * Share off. [reason]: "user" (Dart), "system" (projection stopped from
     * the system UI), "task_removed". The projection is kept only when a
     * recording runs, below API 34 and [keepGrantIfRecording].
     */
    private fun stopShare(reason: String, keepGrantIfRecording: Boolean) {
        val wasSharing = isSharing || virtualDisplay != null
        ElFaheemBridge.stopScreenAudio()
        unregisterDisplayListener()
        placeholderRenderer?.switchToPlaceholder()
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        isSharing = false
        shareEndedForOverlays() // D-083: the annotate bubble and the window guard go with the share

        val keep = keepGrantIfRecording && isRunning && Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE
        if (!keep) releaseProjection()
        Log.i(TAG, "share stopped ($reason) — projection ${if (keep) "kept for the recording" else "released"}")
        if (wasSharing || reason == "system") emitLive("shareStopped", mapOf("reason" to reason))

        if (!isRunning) {
            // No recording: nothing left for this service to do.
            try { placeholderRenderer?.release() } catch (_: Exception) {}
            placeholderRenderer = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        } else {
            refreshForeground()
        }
    }

    /** D-083: whatever ends the share, the annotation bubble is hidden and the presenter's window restored. */
    private fun shareEndedForOverlays() {
        AnnotationOverlayChannel.onShareStopped()
        ShareWindowGuard.onShareStopped()
    }

    private fun releaseProjection() {
        val p = mediaProjection ?: return
        mediaProjection = null
        isProjectionGranted = false
        stoppingProjection = true
        try { p.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        try { p.stop() } catch (_: Exception) {}
        stoppingProjection = false
    }

    /** Rotation / single-app resize: the VirtualDisplay and the renderer's buffers follow (A12). */
    private fun resizeShare(width: Int, height: Int) {
        val vd = virtualDisplay ?: return
        if (width <= 0 || height <= 0 || (width == vdWidth && height == vdHeight)) return
        try {
            placeholderRenderer?.setInputSize(width, height)
            vd.resize(width, height, screenDpi)
            vdWidth = width
            vdHeight = height
            Log.d(TAG, "share resized to ${width}x$height")
            emitLive("shareResized", mapOf("width" to width, "height" to height))
        } catch (e: Exception) {
            Log.w(TAG, "VirtualDisplay resize failed: ${e.message}")
        }
    }

    private fun registerDisplayListener() {
        // API 34+ reports the captured area itself (onCapturedContentResize).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE || displayListener != null) return
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val l = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) {}
            override fun onDisplayRemoved(displayId: Int) {}
            override fun onDisplayChanged(displayId: Int) {
                if (displayId != Display.DEFAULT_DISPLAY || virtualDisplay == null) return
                val (w, h) = currentDisplaySize()
                resizeShare(w, h)
            }
        }
        dm.registerDisplayListener(l, mainHandler)
        displayListener = l
    }

    private fun unregisterDisplayListener() {
        val l = displayListener ?: return
        displayListener = null
        try { (getSystemService(Context.DISPLAY_SERVICE) as DisplayManager).unregisterDisplayListener(l) } catch (_: Exception) {}
    }

    /** The answer to the pending share request (MainActivity → Dart's startScreenCaptureService). */
    private fun answerShare(ok: Boolean, error: String?, extra: Map<String, Any?> = emptyMap()) {
        mainHandler.post {
            onProjectionGrantStored?.invoke(mapOf("ok" to ok, "error" to error) + extra)
            onProjectionGrantStored = null
        }
    }

    // ── Prepare a fresh MediaRecorder for one chunk ───────────────────────────
    //
    // Always writes to a .tmp file; the caller renames it to the final .mp4
    // only after recorder.stop() succeeds (guarantees a valid moov atom).
    //
    // The encoder-facing surface is owned by ScreenPlaceholderRenderer, not
    // directly by a VirtualDisplay — attachEncoderSurface() re-points the
    // renderer's EGL output to this chunk's recorder.surface, whether the
    // renderer is currently drawing a placeholder or real live frames.

    /** The screen size, scaled down so the longer side is at most [maxHeight], 16-aligned. */
    private fun encoderSize(): Pair<Int, Int> {
        val longer = maxOf(screenWidth, screenHeight)
        if (maxHeight <= 0 || longer <= maxHeight) return screenWidth to screenHeight
        val ratio = maxHeight.toDouble() / longer
        fun align16(v: Int) = (v and 0xFFF0).coerceAtLeast(16)
        return align16((screenWidth * ratio).toInt()) to align16((screenHeight * ratio).toInt())
    }

    private fun prepareRecorder(sessionDir: File, index: Int): MediaRecorder {
        val tmp = tmpFile(sessionDir, index)
        tmp.delete()

        // MediaRecorder(Context) is API 31+; minSdk is 24.
        val recorder = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this)
                        else @Suppress("DEPRECATION") MediaRecorder()).also { mediaRecorder = it }
        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        if (audioOnly) {
            // Audio-only: AAC in an MP4 container (an .m4a chunk) — no video
            // source, no encoder surface, same chunk rotation / upload path.
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioEncodingBitRate(AUDIO_BPS)
            recorder.setAudioSamplingRate(44100)
            recorder.setOutputFile(tmp.absolutePath)
            recorder.prepare()
            return recorder
        }
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setAudioEncodingBitRate(AUDIO_BPS)
        recorder.setAudioSamplingRate(44100)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        recorder.setVideoEncodingBitRate(videoBps)
        recorder.setVideoFrameRate(VIDEO_FPS)
        val (encW, encH) = encoderSize()
        recorder.setVideoSize(encW, encH)
        recorder.setOutputFile(tmp.absolutePath)
        recorder.prepare()

        placeholderRenderer!!.attachEncoderSurface(recorder.surface, encW, encH)

        return recorder
    }

    // ── File path helpers ─────────────────────────────────────────────────────

    /** `.m4a` for an audio-only recording (AAC in MP4), `.mp4` otherwise — also the uploaded name / type. */
    private fun chunkExt() = if (audioOnly) "m4a" else "mp4"

    private fun chunkFile(dir: File, index: Int) =
            File(dir, "chunk_${index.toString().padStart(6, '0')}.${chunkExt()}")

    private fun tmpFile(dir: File, index: Int) =
            File(dir, "chunk_${index.toString().padStart(6, '0')}.${chunkExt()}.tmp")

    // ── upload ────────────────────────────────────────────────────────────────

    /**
     * What the server's answer means for a chunk — the same rule as recordingChunkVerdict
     * (lib/.../widgets/record/recording_upload_token.dart): 2xx uploaded; 409 recording_assembled = the run is
     * assembled, stop uploading; 409 recording_assembling = keep the file; no answer / 408 / 429 / 5xx = retry;
     * every other 4xx (401 upload_token_expired / _invalid / _revoked, 403 upload_token_scope, …) = permanent.
     */
    private enum class ChunkVerdict { UPLOADED, ASSEMBLED, KEEP, DROP, RETRY }

    private class ChunkUploadException(val verdict: ChunkVerdict, val code: String?, message: String) :
            Exception(message)

    private fun chunkVerdict(status: Int, code: String?): ChunkVerdict = when {
        status in 200..299 -> ChunkVerdict.UPLOADED
        status == 409 && code == "recording_assembled" -> ChunkVerdict.ASSEMBLED
        status == 409 && code == "recording_assembling" -> ChunkVerdict.KEEP
        status == 0 || status == 408 || status == 429 || status >= 500 -> ChunkVerdict.RETRY
        else -> ChunkVerdict.DROP
    }

    /** `detail.code` of a FastAPI error body (`{"detail": {"code": …}}`), else null. */
    private fun errorCode(body: String?): String? = try {
        if (body.isNullOrBlank()) null
        else org.json.JSONObject(body).optJSONObject("detail")?.optString("code")?.takeIf { it.isNotEmpty() }
    } catch (_: Exception) { null }

    private fun uploadChunkAsync(file: File, index: Int, isFinal: Boolean, seamless: Boolean = false) {
        val size = file.length()
        pendingUploads.incrementAndGet()
        uploadExecutor.execute {
            if (uploadsClosed.get()) {
                // The run takes no more chunks (assembled / token dead): nothing to send, the recorder is done.
                file.delete()
                pendingUploads.decrementAndGet()
                if (isFinal) mainHandler.post { emitChunkUploaded(index, 0, true) }
                Log.d(TAG, "chunk #$index skipped — uploads closed for this run")
                return@execute
            }
            var attempt = 0
            var lastErr = "unknown"
            while (attempt <= 3) {
                try {
                    uploadChunk(file, index, isFinal, seamless)
                    file.delete()
                    pendingUploads.decrementAndGet()
                    mainHandler.post { emitChunkUploaded(index, size, isFinal) }
                    Log.d(TAG, "chunk #$index uploaded OK (attempt ${attempt + 1})")
                    return@execute
                } catch (e: ChunkUploadException) {
                    lastErr = e.message ?: "unknown"
                    when (e.verdict) {
                        ChunkVerdict.ASSEMBLED -> {
                            // The recording is assembled: stop uploading for this run, drop what is left.
                            uploadsClosed.set(true)
                            file.delete()
                            file.parentFile?.listFiles()?.forEach { f -> if (f.name.startsWith("chunk_")) f.delete() }
                            pendingUploads.decrementAndGet()
                            mainHandler.post {
                                eventSink?.success(mapOf("event" to "uploadsStopped", "reason" to (e.code ?: "")))
                                if (isFinal) emitChunkUploaded(index, 0, true)
                            }
                            Log.w(TAG, "chunk #$index: the recording is already assembled — uploads stopped")
                            return@execute
                        }
                        ChunkVerdict.KEEP -> {
                            // Being assembled right now: keep the file (never delete footage), do not retry.
                            pendingUploads.decrementAndGet()
                            Log.w(TAG, "chunk #$index: recording being assembled — kept at ${file.name}")
                            return@execute
                        }
                        ChunkVerdict.DROP -> {
                            // Permanent (a dead / foreign upload token, a refused chunk): never retried.
                            if (e.code?.startsWith("upload_token_") == true) uploadsClosed.set(true)
                            file.delete()
                            pendingUploads.decrementAndGet()
                            mainHandler.post {
                                if (uploadsClosed.get()) {
                                    eventSink?.success(mapOf("event" to "uploadsStopped", "reason" to (e.code ?: "")))
                                }
                                emitError("chunk #$index refused: $lastErr")
                            }
                            Log.e(TAG, "chunk #$index refused permanently: $lastErr")
                            return@execute
                        }
                        else -> {
                            Log.e(TAG, "chunk #$index attempt ${attempt + 1} failed: $lastErr")
                            attempt++
                            if (attempt <= 3) Thread.sleep(1_000L * (1 shl attempt))
                        }
                    }
                } catch (e: Exception) {
                    lastErr = e.message ?: "unknown"
                    Log.e(TAG, "chunk #$index attempt ${attempt + 1} failed: $lastErr")
                    attempt++
                    if (attempt <= 3) Thread.sleep(1_000L * (1 shl attempt))
                }
            }
            Log.e(TAG, "chunk #$index permanently failed: $lastErr")
            file.delete()
            pendingUploads.decrementAndGet()
            mainHandler.post { emitError("chunk #$index failed after 3 retries: $lastErr") }
        }
    }

    private fun uploadChunk(file: File, index: Int, isFinal: Boolean, seamless: Boolean) {
        val boundary = "----ElFaheemBoundary${System.currentTimeMillis()}"
        val conn = (java.net.URL(uploadUrl).openConnection() as java.net.HttpURLConnection).apply {
            requestMethod  = "POST"
            doOutput       = true
            connectTimeout = 15_000
            readTimeout    = 120_000
            setRequestProperty("Authorization", authToken)
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }
        conn.outputStream.use { out ->
            fun field(name: String, value: String) =
                    out.write("--$boundary\r\nContent-Disposition: form-data; name=\"$name\"\r\n\r\n$value\r\n".toByteArray())
            field("chunk_index", index.toString())
            field("is_final",    if (isFinal) "1" else "0")
            if (epoch.isNotEmpty()) field("epoch", epoch)
            // D-103: one slice of a continuous encode — the server joins these with a stream copy (older servers
            // ignore the field and re-encode as before).
            if (seamless) field("seamless", "1")
            out.write(("--$boundary\r\nContent-Disposition: form-data; name=\"chunk\";" +
                    " filename=\"chunk_${index.toString().padStart(6,'0')}.${chunkExt()}\"\r\n" +
                    "Content-Type: ${if (audioOnly) "audio/mp4" else "video/mp4"}\r\n\r\n").toByteArray())
            file.inputStream().use { it.copyTo(out) }
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }
        val code = conn.responseCode
        if (code in 200..299) {
            conn.disconnect()
            return
        }
        val body = try { conn.errorStream?.bufferedReader()?.use { it.readText() } } catch (_: Exception) { null }
        conn.disconnect()
        val errCode = errorCode(body)
        throw ChunkUploadException(chunkVerdict(code, errCode), errCode, "HTTP $code${errCode?.let { " $it" } ?: ""}")
    }

    // ── teardown ──────────────────────────────────────────────────────────────

    /** The recorder only (the share, if any, keeps running). */
    private fun releaseRecorder() {
        try { mediaRecorder?.stop()    } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
    }

    private fun safeReleaseMedia() {
        releaseRecorder()
        ElFaheemBridge.stopScreenAudio()
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        if (isSharing) shareEndedForOverlays()
        isSharing = false
        releaseProjection()
        try { placeholderRenderer?.release() } catch (_: Exception) {}
        placeholderRenderer = null
    }

    // ── EventChannel ──────────────────────────────────────────────────────────

    private fun emitScreenLoopStarted() {
        Log.d(TAG, "emit screenLoopStarted")
        eventSink?.success(mapOf("event" to "screenLoopStarted"))
    }
    private fun emitMicReadyForShare()  = eventSink?.success(mapOf("event" to "micReadyForShare"))
    private fun emitMicLoopStarted()    = eventSink?.success(mapOf("event" to "micLoopStarted"))
    private fun emitChunkUploaded(index: Int, bytes: Long, isFinal: Boolean) =
            eventSink?.success(mapOf("event" to "chunkUploaded", "chunkIndex" to index,
                    "bytes" to bytes, "isFinal" to isFinal))

    private fun emitRecordingPaused()  {
        Log.d(TAG, "emit recordingPaused")
        eventSink?.success(mapOf("event" to "recordingPaused"))
    }
    private fun emitRecordingResumed() {
        Log.d(TAG, "emit recordingResumed")
        eventSink?.success(mapOf("event" to "recordingResumed"))
    }

    private fun emitError(msg: String) = eventSink?.error("REC_ERROR", msg, null)

    // ── notification ─────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(NotificationChannel(
                            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW).apply {
                        description = "Active while a session is recorded or the screen is shared"
                        setShowBadge(false)
                    })
    }

    private fun buildNotification(): Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle(if (isRunning) "Recording session" else "Sharing your screen")
                    .setContentText(
                            when {
                                !isRunning -> "Your screen is shown in the live session"
                                isPaused   -> "Recording paused"
                                audioOnly  -> "Audio recording in progress"
                                else       -> "Session recording in progress"
                            }
                    )
                    .setSmallIcon(android.R.drawable.ic_menu_camera)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setOngoing(true)
                    .build()
}
