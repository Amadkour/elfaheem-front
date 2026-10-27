package com.example.flutter_education_app

import com.cloudwebrtc.webrtc.ElFaheemBridge
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
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
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID      = "screen_capture_channel"
        const val CHANNEL_NAME    = "Screen Capture"
        const val NOTIFICATION_ID = 1001

        const val ACTION_START_MIC_ONLY             = "com.example.flutter_education_app.START_MIC_ONLY"
        const val ACTION_STORE_PROJECTION           = "com.example.flutter_education_app.STORE_PROJECTION"
        const val ACTION_STOP                       = "com.example.flutter_education_app.STOP_SCREEN_CAPTURE"
        const val ACTION_REVERT_TO_PLACEHOLDER      = "com.example.flutter_education_app.REVERT_TO_PLACEHOLDER"
        const val ACTION_DOWNGRADE_TO_MIC_FOR_SHARE = "com.example.flutter_education_app.DOWNGRADE_TO_MIC_FOR_SHARE"
        const val ACTION_DOWNGRADE_TO_MIC           = "com.example.flutter_education_app.DOWNGRADE_TO_MIC"
        const val ACTION_PROMOTE_FOR_SHARE          = "com.example.flutter_education_app.PROMOTE_FOR_SHARE"

        // ── NEW: pause / resume recording ────────────────────────────────────
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
        // Meeting recordings (docs/backend/live-rooms-spec.md §5): the picked quality. 0 = the defaults below.
        const val EXTRA_VIDEO_BPS   = "videoBitrate"
        const val EXTRA_MAX_HEIGHT  = "maxHeight"
        // Audio-only (quality "audio"): MediaRecorder captures the mic alone — AAC in an MP4 container
        // (.m4a chunks), no video source / encoder surface, no MediaProjection needed for the recording.
        const val EXTRA_AUDIO_ONLY  = "audioOnly"

        private const val TAG       = "ScreenCaptureService"
        private const val VIDEO_BPS = 8_000_000
        private const val VIDEO_FPS = 15
        private const val AUDIO_BPS = 192_000   // raised from 128k for cleaner chunk boundaries

        @Volatile var isRunning:               Boolean                 = false
        @Volatile var isProjectionGranted:     Boolean                 = false
        @Volatile var isPaused:                Boolean                 = false   // NEW
        @Volatile var currentChunkIndex:       Int                     = 0
        @Volatile var eventSink:               EventChannel.EventSink? = null
        @Volatile var onProjectionGrantStored: (() -> Unit)?           = null
        @Volatile var onFgsPromoted:           (() -> Unit)?           = null
        @Volatile var placeholderRenderer:     ScreenPlaceholderRenderer? = null

        val pendingUploads = AtomicInteger(0)

        // Single-threaded executor — chunks always reach the server in order.
        val uploadExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "ChunkUploader").also { it.isDaemon = true }
        }
    }

    // ── recording state ───────────────────────────────────────────────────────
    private val shouldRecord      = AtomicBoolean(false)
    private val shouldStop        = AtomicBoolean(false)
    private val shouldPause       = AtomicBoolean(false)   // NEW
    private val projectionRevoked = AtomicBoolean(false)

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection:   MediaProjection?        = null
    private var virtualDisplay:    VirtualDisplay?         = null

    // Active recorder for the current chunk (may be swapped during ping-pong).
    private var mediaRecorder: MediaRecorder? = null

    private var sessionId  = 0
    private var uploadUrl  = ""
    private var authToken  = ""
    private var chunkSecs  = 5
    private var chunkIndex = 0
    private var videoBps   = VIDEO_BPS   // EXTRA_VIDEO_BPS when > 0
    private var maxHeight  = 0           // EXTRA_MAX_HEIGHT: cap on the longer side (0 = none)
    private var audioOnly  = false       // EXTRA_AUDIO_ONLY: see prepareRecorder()

    private var screenWidth  = 1080
    private var screenHeight = 1920
    private var screenDpi    = 420

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        shouldStop.set(true)
        shouldRecord.set(false)
        shouldPause.set(false)
        safeReleaseMedia()
        isRunning = false
        isProjectionGranted = false
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
                chunkSecs  = intent.getIntExtra(EXTRA_CHUNK_SECS,   5)
                chunkIndex = intent.getIntExtra(EXTRA_CHUNK_INDEX,  0)
                videoBps   = intent.getIntExtra(EXTRA_VIDEO_BPS, 0).let { if (it > 0) it else VIDEO_BPS }
                maxHeight  = intent.getIntExtra(EXTRA_MAX_HEIGHT, 0)
                audioOnly  = intent.getBooleanExtra(EXTRA_AUDIO_ONLY, false)
                pendingUploads.set(0)
                Log.d(TAG, "ACTION_START_MIC_ONLY session=$sessionId chunkSecs=$chunkSecs audioOnly=$audioOnly")
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
                startForegroundMicOnly()
                isRunning = true

                // Single-MediaProjection architecture: recording (with a
                // placeholder in place of real screen content) starts here,
                // immediately, with no dialog — ScreenPlaceholderRenderer
                // draws a placeholder frame into the encoder until Share is
                // tapped and ACTION_STORE_PROJECTION below activates live
                // content. See ScreenPlaceholderRenderer.kt.
                if (uploadUrl.isEmpty()) {
                    Log.e(TAG, "uploadUrl empty — cannot start placeholder recording")
                } else if (shouldRecord.get()) {
                    Log.w(TAG, "already recording — ignoring duplicate START_MIC_ONLY")
                } else {
                    placeholderRenderer = ScreenPlaceholderRenderer(
                            onLiveFrameForCapturer = { w, h, rgba ->
                                ElFaheemBridge.pushFrame(rgba, w, h, System.nanoTime())
                            },
                    ).also {
                        it.start(screenWidth, screenHeight)
                        // Audio-only: the recorder never gets an encoder surface
                        // (prepareRecorder skips attachEncoderSurface), but the
                        // renderer stays alive drawing into an offscreen buffer so
                        // a later Share still works the same single-projection way
                        // (ACTION_STORE_PROJECTION → VirtualDisplay → inputSurface →
                        // onLiveFrameForCapturer); only nothing of it is recorded.
                        if (audioOnly) it.attachOffscreenOutput(screenWidth, screenHeight)
                    }

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

                Log.d(TAG, "ACTION_STORE_PROJECTION resultCode=$resultCode")

                if (resultCode == 0 || data == null) {
                    Log.e(TAG, "invalid grant — aborting")
                    mainHandler.post {
                        emitError("MediaProjection grant invalid")
                        onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
                    }
                    return START_STICKY
                }
                if (!shouldRecord.get() || placeholderRenderer == null) {
                    // Placeholder recording never started (e.g. uploadUrl was
                    // empty at session start) — nothing to activate live.
                    Log.e(TAG, "no active placeholder recording — cannot activate live projection")
                    mainHandler.post {
                        emitError("Recording not active — cannot start live sharing")
                        onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
                    }
                    return START_STICKY
                }
                if (isProjectionGranted) {
                    Log.w(TAG, "projection already active — ignoring duplicate STORE_PROJECTION")
                    mainHandler.post { onProjectionGrantStored?.invoke(); onProjectionGrantStored = null }
                    return START_STICKY
                }

                promoteForegroundToProjection()
                activateLiveProjection(resultCode, data)
            }

            ACTION_REVERT_TO_PLACEHOLDER -> {
                Log.d(TAG, "ACTION_REVERT_TO_PLACEHOLDER")
                // Share turned off: keep the MediaProjection grant + recording
                // alive (no new dialog needed if Share is tapped again), just
                // stop drawing live frames into the encoder/live capturer —
                // revert to the placeholder until Share is re-tapped.
                placeholderRenderer?.switchToPlaceholder()
            }

            ACTION_STOP -> {
                Log.d(TAG, "ACTION_STOP — signalling chunk loop")
                shouldStop.set(true)
                shouldRecord.set(false)
                shouldPause.set(false)
                // If currently paused, wake the park-loop so it can exit cleanly.
                synchronized(this) { (this as Object).notifyAll() }
            }

            // ACTION_UPGRADE_TO_SCREEN removed — was a no-op duplicate of what
            // ACTION_STORE_PROJECTION already does (promoteForegroundToProjection()
            // + emitScreenLoopStarted()) when the single MediaProjection grant
            // (1001) is confirmed. See MainActivity.kt for the single-grant flow.

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

            // ── NEW: PAUSE ────────────────────────────────────────────────────
            // Signals the chunk loop to finish the current chunk, upload it with
            // isFinal=false, then park (sleep) until RESUME or STOP arrives.
            ACTION_PAUSE_RECORDING -> {
                if (!shouldRecord.get() || shouldStop.get()) {
                    Log.w(TAG, "PAUSE ignored — not recording")
                    return START_STICKY
                }
                if (shouldPause.get()) {
                    Log.w(TAG, "PAUSE ignored — already paused")
                    return START_STICKY
                }
                Log.d(TAG, "ACTION_PAUSE_RECORDING")
                shouldPause.set(true)
                // The chunk loop's 50 ms tick loop will see shouldPause and
                // break out of the current chunk early, finishing it cleanly.
            }

            // ── NEW: RESUME ───────────────────────────────────────────────────
            // Clears the pause flag and wakes the parked chunk loop.
            ACTION_RESUME_RECORDING -> {
                if (!isProjectionGranted || shouldStop.get()) {
                    Log.w(TAG, "RESUME ignored — not in a pauseable state")
                    return START_STICKY
                }
                if (!shouldPause.get()) {
                    Log.w(TAG, "RESUME ignored — not paused")
                    return START_STICKY
                }
                Log.d(TAG, "ACTION_RESUME_RECORDING")
                shouldRecord.set(true)
                shouldPause.set(false)
                isPaused = false
                // Wake the park-loop in recordLoop().
                synchronized(this) { (this as Object).notifyAll() }
            }

            else -> {
                startForegroundMicOnly()
                isRunning = true
            }
        }
        return START_STICKY
    }

    // ── FGS helpers ───────────────────────────────────────────────────────────

    private fun startForegroundMicOnly() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            startForeground(NOTIFICATION_ID, buildNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        else
            startForeground(NOTIFICATION_ID, buildNotification())
    }

    private fun promoteForegroundToProjection() {
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                startForeground(NOTIFICATION_ID, buildNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                startForeground(NOTIFICATION_ID, buildNotification(),
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else ->
                startForeground(NOTIFICATION_ID, buildNotification())
        }
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
    //   the MediaRecorder but keep the VirtualDisplay/Projection alive so RESUME
    //   can re-enter without a second system dialog.
    //
    // On RESUME: re-enter the while-loop; a fresh MediaRecorder is prepared and
    //   recording continues from the next chunk index.

    private fun recordLoop() {
        Log.d(TAG, "recordLoop started (placeholder) — ${screenWidth}x${screenHeight} chunkSecs=$chunkSecs")

        val sessionDir = File(cacheDir, "session_$sessionId").also { it.mkdirs() }
        val chunkDurationMs = chunkSecs * 1_000L

        // Prepare the very first recorder before signalling Dart, so that
        // emitScreenLoopStarted() fires only when audio is truly capturing.
        var currentRecorder = prepareRecorder(sessionDir, chunkIndex)
        currentRecorder.start()
        Log.d(TAG, "MediaRecorder.start() chunk #$chunkIndex (first)")
        mainHandler.post { emitScreenLoopStarted() }

        // ── 3. chunk loop ─────────────────────────────────────────────────────
        outer@ while (true) {

            // ── 3a. chunk timing window ───────────────────────────────────────
            val t0 = System.currentTimeMillis()
            while (System.currentTimeMillis() - t0 < chunkDurationMs) {
                when {
                    shouldStop.get()  -> break
                    projectionRevoked.get() -> break
                    shouldPause.get() -> break   // exit timing window early on pause
                }
                Thread.sleep(50)
            }

            val outFile = chunkFile(sessionDir, chunkIndex)
            val tmpFile = tmpFile(sessionDir, chunkIndex)

            // Determine final BEFORE ping-pong so we pick up any stop/pause
            // signal that arrived during the timing window.
            val stopping = shouldStop.get() || projectionRevoked.get()
            val pausing  = shouldPause.get() && !stopping
            val isFinal  = stopping   // isFinal=true only on hard stop

            // ── 3b. ping-pong: start next recorder BEFORE stopping current ────
            var nextRecorder: MediaRecorder? = null
            if (!stopping && !pausing) {
                // Seamless transition — prepare next chunk recorder while
                // current is still encoding (zero-gap swap).
                try {
                    nextRecorder = prepareRecorder(sessionDir, chunkIndex + 1)
                    nextRecorder.start()
                    Log.d(TAG, "MediaRecorder.start() chunk #${chunkIndex + 1} (next)")
                    // NOTE: no virtualDisplay.surface swap here — prepareRecorder()
                    // above already re-pointed placeholderRenderer's output at
                    // nextRecorder.surface. virtualDisplay (when live) always
                    // targets the renderer's STABLE input surface and must never
                    // be touched per-chunk — only prepareRecorder's encoder-side
                    // attach changes.
                } catch (e: Exception) {
                    Log.e(TAG, "ping-pong prepare failed: ${e.message} — will stop after this chunk")
                    nextRecorder?.release()
                    nextRecorder = null
                }
            }

            // ── 3c. stop and finalise the current chunk ───────────────────────
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

            // ── 3d. decide what comes next ────────────────────────────────────
            when {
                stopping -> {
                    // Hard stop — exit loop, drain, quit.
                    nextRecorder?.release()
                    break@outer
                }
                pausing -> {
                    // Soft pause — park this thread until RESUME or STOP.
                    //
                    // Re-point the renderer's output at a safe, persistent
                    // pbuffer BEFORE parking: currentRecorder.release() just
                    // above already invalidated the Surface
                    // placeholderRenderer was drawing into (attachEncoderSurface
                    // for the next chunk is deliberately skipped while
                    // pausing — there's no next chunk yet). Left unhandled,
                    // eglMakeCurrent against that dead surface fails on every
                    // tick for the whole pause duration, silently no-opping
                    // drawLiveFrame() — which is also what feeds the live
                    // share via onLiveFrameForCapturer. Pausing the local
                    // recording must never freeze what viewers see.
                    placeholderRenderer?.detachEncoderSurfaceForPause()
                    isPaused = true
                    mainHandler.post { emitRecordingPaused() }
                    Log.d(TAG, "recording PAUSED at chunk #$chunkIndex")

                    synchronized(this) {
                        while (shouldPause.get() && !shouldStop.get() && !projectionRevoked.get()) {
                            try { (this as Object).wait(1_000) }
                            catch (_: InterruptedException) { break }
                        }
                    }

                    if (shouldStop.get() || projectionRevoked.get()) {
                        Log.d(TAG, "exiting from paused state — stop/revoke received")
                        break@outer
                    }

                    // RESUME received — re-enter the chunk loop.
                    Log.d(TAG, "recording RESUMED at chunk #$chunkIndex")
                    mainHandler.post { emitRecordingResumed() }

                    // Prepare the first recorder of the new recording segment.
                    try {
                        currentRecorder = prepareRecorder(sessionDir, chunkIndex)
                        currentRecorder.start()
                        Log.d(TAG, "MediaRecorder.start() chunk #$chunkIndex (resumed)")
                    } catch (e: Exception) {
                        Log.e(TAG, "resume: prepareRecorder failed: ${e.message}")
                        mainHandler.post { emitError("Resume failed: ${e.message}") }
                        break@outer
                    }
                    // Continue outer loop — surface swap handled by prepareRecorder.
                }
                nextRecorder != null -> {
                    // Seamless continuation — swap to the next recorder that is
                    // already running.
                    currentRecorder = nextRecorder
                }
                else -> {
                    // ping-pong prepare failed earlier; exit gracefully.
                    break@outer
                }
            }
        }

        // ── 4. release media objects ──────────────────────────────────────────
        safeReleaseMedia()

        // ── 5. drain pending uploads (max 120 s) ──────────────────────────────
        Log.d(TAG, "all chunks recorded — waiting for ${pendingUploads.get()} upload(s)…")
        val deadline = System.currentTimeMillis() + 120_000L
        while (pendingUploads.get() > 0 && System.currentTimeMillis() < deadline) {
            Thread.sleep(200)
        }
        if (pendingUploads.get() > 0)
            Log.w(TAG, "${pendingUploads.get()} upload(s) unfinished after 120 s")

        isRunning = false
        isProjectionGranted = false
        isPaused = false
        stopSelf()
        Log.d(TAG, "recordLoop done")
    }

    // ── Activate live projection (called once, when Share is first tapped) ────
    //
    // recordLoop()'s ping-pong chunk recording is ALREADY running (started
    // from ACTION_START_MIC_ONLY, feeding on a placeholder). This does not
    // touch that loop at all — it only obtains the real MediaProjection and
    // points a real VirtualDisplay at placeholderRenderer's stable input
    // surface, then flips the renderer to live mode. From the next drawn
    // frame on, both the encoder (recording) and the live capturer
    // (ElFaheemFrameCapturer, via the renderer's onLiveFrameForCapturer
    // callback) receive real screen content — no new MediaRecorder, no new
    // VirtualDisplay target on the encoder side, no gap in the recording.
    private fun activateLiveProjection(resultCode: Int, data: Intent) {
        val projection = try {
            projectionManager!!.getMediaProjection(resultCode, data)
        } catch (e: Exception) {
            Log.e(TAG, "getMediaProjection failed: ${e.message}", e); null
        }
        if (projection == null) {
            Log.e(TAG, "null MediaProjection — cannot activate live sharing")
            mainHandler.post {
                emitError("Could not obtain MediaProjection")
                onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
            }
            return
        }
        mediaProjection = projection

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            projection.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    // System revoked the grant (e.g. user dismissed the
                    // "stop sharing" system notification). Recording itself
                    // is NOT stopped — only the live path reverts, same as
                    // ACTION_REVERT_TO_PLACEHOLDER. Re-tapping Share will
                    // show a fresh dialog and re-activate.
                    Log.w(TAG, "MediaProjection revoked by system")
                    projectionRevoked.set(true)
                    isProjectionGranted = false
                    placeholderRenderer?.switchToPlaceholder()
                    try { virtualDisplay?.release() } catch (_: Exception) {}
                    virtualDisplay = null
                }
            }, mainHandler)
        }

        try {
            virtualDisplay = projection.createVirtualDisplay(
                    "ScreenCapture",
                    screenWidth, screenHeight, screenDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    placeholderRenderer!!.inputSurface, null, null,
            )
            Log.d(TAG, "VirtualDisplay created (live) ${screenWidth}x${screenHeight}@${screenDpi}dpi")
        } catch (e: Exception) {
            Log.e(TAG, "createVirtualDisplay failed: ${e.message}", e)
            mainHandler.post {
                emitError("Could not start live screen capture")
                onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
            }
            return
        }

        projectionRevoked.set(false)
        isProjectionGranted = true
        placeholderRenderer!!.switchToLive()

        mainHandler.post {
            // Re-using the same event name Dart already waits on via
            // upgradeToScreenRecording()'s completer — see room_screen_share.dart.
            emitScreenLoopStarted()
            onProjectionGrantStored?.invoke()
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

    /** The screen size, scaled down so the longer side is at most [maxHeight] (when set), 16-aligned. */
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

        val recorder = MediaRecorder(this).also { mediaRecorder = it }
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

    private fun uploadChunkAsync(file: File, index: Int, isFinal: Boolean) {
        val size = file.length()
        pendingUploads.incrementAndGet()
        uploadExecutor.execute {
            var attempt = 0
            var lastErr = "unknown"
            while (attempt <= 3) {
                try {
                    uploadChunk(file, index, isFinal)
                    file.delete()
                    pendingUploads.decrementAndGet()
                    mainHandler.post { emitChunkUploaded(index, size, isFinal) }
                    Log.d(TAG, "chunk #$index uploaded OK (attempt ${attempt + 1})")
                    return@execute
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

    private fun uploadChunk(file: File, index: Int, isFinal: Boolean) {
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
            out.write(("--$boundary\r\nContent-Disposition: form-data; name=\"chunk\";" +
                    " filename=\"chunk_${index.toString().padStart(6,'0')}.${chunkExt()}\"\r\n" +
                    "Content-Type: ${if (audioOnly) "audio/mp4" else "video/mp4"}\r\n\r\n").toByteArray())
            file.inputStream().use { it.copyTo(out) }
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }
        val code = conn.responseCode
        conn.disconnect()
        if (code !in 200..299) throw Exception("HTTP $code")
    }

    // ── teardown ──────────────────────────────────────────────────────────────

    private fun safeReleaseMedia() {
        try { mediaRecorder?.stop()    } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { mediaProjection?.stop()   } catch (_: Exception) {}
        mediaProjection = null
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

    // NEW events ──────────────────────────────────────────────────────────────
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
                        description = "Active while session is being recorded"
                        setShowBadge(false)
                    })
    }

    private fun buildNotification(): Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("Recording session")
                    .setContentText(
                            when {
                                isPaused  -> "Recording paused"
                                audioOnly -> "Audio recording in progress"
                                else      -> "Session recording in progress"
                            }
                    )
                    .setSmallIcon(android.R.drawable.ic_menu_camera)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setOngoing(true)
                    .build()
}