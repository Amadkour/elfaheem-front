package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// ScreenCaptureService — Standard MediaProjection recording pipeline
//
// DESIGN:
//   Uses Android's MediaProjection API (the standard approach) to record
//   the device screen. A system dialog is shown once when the teacher starts
//   the session; after approval the service records continuously in 5-second
//   MP4 chunks and uploads each chunk to the server.
//
// RECORDING PIPELINE:
//   MediaProjection → VirtualDisplay → MediaRecorder → .mp4 chunk → upload
//   MIC audio is captured by MediaRecorder directly (AudioSource.MIC).
//
// PERMISSIONS REQUIRED (in AndroidManifest.xml):
//   RECORD_AUDIO, FOREGROUND_SERVICE, FOREGROUND_SERVICE_MICROPHONE,
//   FOREGROUND_SERVICE_MEDIA_PROJECTION (Android 14+)
//   Service foregroundServiceType: mediaProjection|microphone
//
// CHUNK FLOW:
//   1. Dart calls startMicRecording (ACTION_START_MIC_ONLY) with session info.
//   2. MainActivity shows the MediaProjection permission dialog.
//   3. On user approval, onActivityResult stores the projection intent and
//      fires ACTION_STORE_PROJECTION to this service.
//   4. Service starts recording and emits "screenLoopStarted" to Dart.
//   5. Every chunkSeconds the current MediaRecorder is stopped, its file
//      uploaded, and a new MediaRecorder starts for the next chunk.
//   6. On ACTION_STOP the final chunk is finalized and uploaded with isFinal=true.
// ─────────────────────────────────────────────────────────────────────────────

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioFormat
import android.media.AudioRecord
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
import java.util.concurrent.atomic.AtomicBoolean

class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID      = "screen_capture_channel"
        const val CHANNEL_NAME    = "Screen Capture"
        const val NOTIFICATION_ID = 1001

        const val ACTION_STOP             = "com.example.flutter_education_app.STOP_SCREEN_CAPTURE"
        const val ACTION_START_MIC_ONLY   = "com.example.flutter_education_app.START_MIC_ONLY"
        const val ACTION_STORE_PROJECTION = "com.example.flutter_education_app.STORE_PROJECTION"
        // Screen-share lifecycle signals (no-ops here; flutter_webrtc owns its projection)
        const val ACTION_UPGRADE_TO_SCREEN          = "com.example.flutter_education_app.UPGRADE_TO_SCREEN"
        const val ACTION_DOWNGRADE_TO_MIC_FOR_SHARE = "com.example.flutter_education_app.DOWNGRADE_TO_MIC_FOR_SHARE"
        const val ACTION_DOWNGRADE_TO_MIC           = "com.example.flutter_education_app.DOWNGRADE_TO_MIC"
        const val ACTION_PROMOTE_FOR_SHARE          = "com.example.flutter_education_app.PROMOTE_FOR_SHARE"

        const val EXTRA_RESULT_CODE  = "resultCode"
        const val EXTRA_DATA         = "data"
        const val EXTRA_SESSION_ID   = "sessionId"
        const val EXTRA_UPLOAD_URL   = "uploadUrl"
        const val EXTRA_AUTH_TOKEN   = "authToken"
        const val EXTRA_CHUNK_SECS   = "chunkSeconds"
        const val EXTRA_IS_FINAL     = "isFinal"
        const val EXTRA_CHUNK_INDEX  = "chunkIndex"

        private const val TAG         = "ScreenCaptureService"
        private const val VIDEO_WIDTH = 1280
        private const val VIDEO_BPS   = 2_000_000
        private const val VIDEO_FPS   = 15
        private const val AUDIO_BPS   = 128_000

        @Volatile var eventSink: EventChannel.EventSink? = null
        @Volatile var isRunning: Boolean = false
        @Volatile var currentChunkIndex: Int = 0
        @Volatile var onProjectionGrantStored: (() -> Unit)? = null
        @Volatile var onFgsPromoted: (() -> Unit)? = null

        // Tracks in-flight uploadChunkAsync threads so recordLoop() keeps the
        // FGS alive until every chunk has been uploaded before calling stopSelf().
        val pendingUploads = java.util.concurrent.atomic.AtomicInteger(0)
    }

    // ── Instance state ────────────────────────────────────────────────────────

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection:   MediaProjection? = null
    private var virtualDisplay:    VirtualDisplay? = null
    private var mediaRecorder:     MediaRecorder? = null

    private val recording  = AtomicBoolean(false)
    private val stopping   = AtomicBoolean(false)

    private var sessionId  = 0
    private var uploadUrl  = ""
    private var authToken  = ""
    private var chunkSecs  = 5
    private var chunkIndex = 0

    private var screenWidth  = VIDEO_WIDTH
    private var screenHeight = 720
    private var screenDpi    = 320

    private val mainHandler = Handler(Looper.getMainLooper())

    // Stored projection grant from onActivityResult
    private var pendingResultCode = 0
    private var pendingData: Intent? = null

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopRecordingClean()
        isRunning = false
        super.onDestroy()
    }

    // ── onStartCommand ────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {

            ACTION_START_MIC_ONLY -> {
                // Called by Dart to configure the session and start the FGS.
                // Actual recording begins after the projection dialog is approved
                // and ACTION_STORE_PROJECTION arrives.
                sessionId  = intent.getIntExtra(EXTRA_SESSION_ID, 0)
                uploadUrl  = intent.getStringExtra(EXTRA_UPLOAD_URL) ?: ""
                authToken  = intent.getStringExtra(EXTRA_AUTH_TOKEN) ?: ""
                chunkSecs  = intent.getIntExtra(EXTRA_CHUNK_SECS, 5)
                chunkIndex = intent.getIntExtra(EXTRA_CHUNK_INDEX, 0)
                Log.d(TAG, "ACTION_START_MIC_ONLY: session=$sessionId chunkSecs=$chunkSecs")
                resolveScreenMetrics()
                startForegroundMicOnly()
                isRunning = true
            }

            ACTION_STORE_PROJECTION -> {
                // Receives the approved MediaProjection result from MainActivity.
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data       = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                else
                    @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)

                Log.d(TAG, "ACTION_STORE_PROJECTION: resultCode=$resultCode uploadUrl=$uploadUrl")
                // Promote FGS type to include MEDIA_PROJECTION — must happen
                // after dialog approval and before getMediaProjection().
                promoteForegroundToProjection()
                isRunning = true

                if (resultCode != 0 && data != null && !recording.get()) {
                    if (uploadUrl.isEmpty()) {
                        Log.e(TAG, "ACTION_STORE_PROJECTION: uploadUrl empty — session params missing")
                        mainHandler.post {
                            emitError("Projection received before session params")
                            onProjectionGrantStored?.invoke()
                            onProjectionGrantStored = null
                        }
                        return START_STICKY
                    }
                    pendingResultCode = resultCode
                    pendingData       = data
                    recording.set(true)
                    stopping.set(false)
                    Thread({ recordLoop() }, "ScreenRecorder").start()
                }

                // Unblock Dart AFTER recordLoop() is launched so upgradeToScreenRecording()
                // waits for the real screenLoopStarted, not a fake one.
                mainHandler.post {
                    onProjectionGrantStored?.invoke()
                    onProjectionGrantStored = null
                }
            }

            ACTION_STOP -> {
                Log.d(TAG, "ACTION_STOP: finalising recording")
                stopping.set(true)
                // Recording loop will detect this and finalise the last chunk.
            }

            // ── Screen-share lifecycle signals ─────────────────────────────────
            // flutter_webrtc manages its own projection token.  We just unblock
            // the Dart completers so the share flow isn't stuck waiting.

            ACTION_UPGRADE_TO_SCREEN -> {
                Log.d(TAG, "ACTION_UPGRADE_TO_SCREEN: emitting screenLoopStarted")
                mainHandler.post { emitScreenLoopStarted() }
            }

            ACTION_DOWNGRADE_TO_MIC_FOR_SHARE -> {
                Log.d(TAG, "ACTION_DOWNGRADE_TO_MIC_FOR_SHARE: recording continues; emitting micReadyForShare")
                mainHandler.post { emitMicReadyForShare() }
            }

            ACTION_DOWNGRADE_TO_MIC -> {
                Log.d(TAG, "ACTION_DOWNGRADE_TO_MIC: share ended; emitting micLoopStarted")
                mainHandler.post { emitMicLoopStarted() }
            }

            ACTION_PROMOTE_FOR_SHARE -> {
                Log.d(TAG, "ACTION_PROMOTE_FOR_SHARE: no-op; unblocking Dart")
                mainHandler.post {
                    onFgsPromoted?.invoke()
                    onFgsPromoted = null
                }
            }

            else -> {
                startForegroundMicOnly()
                isRunning = true
            }
        }
        return START_STICKY
    }

    // ── FGS notification ──────────────────────────────────────────────────────

    /**
     * Phase 1 — called during ACTION_START_MIC_ONLY, before the projection
     * dialog.  Declares ONLY microphone type.  Android 14 rejects mediaProjection
     * type here because the user hasn't approved the dialog yet.
     */
    private fun startForegroundMicOnly() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID, buildNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    /**
     * Phase 2 — called during ACTION_STORE_PROJECTION, after dialog approval.
     * Promotes the running FGS to include MEDIA_PROJECTION type by calling
     * startForeground() again with the wider OR'd type set.
     *
     * IMPORTANT: Do NOT call stopForeground() here.  Stopping the foreground
     * state even briefly causes flutter_webrtc's FlutterRTCMediaProjectionService
     * to lose its own FGS type, crashing the app when the teacher tries to share
     * their screen.  Simply re-calling startForeground() with an expanded type
     * set is the correct Android 14 promotion pattern for an already-running FGS.
     */
    private fun promoteForegroundToProjection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                    NOTIFICATION_ID, buildNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                            android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                    NOTIFICATION_ID, buildNotification(),
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    // ── Screen metrics ────────────────────────────────────────────────────────

    private fun resolveScreenMetrics() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            var w = b.width()
            var h = b.height()
            if (w > VIDEO_WIDTH) {
                val scale = VIDEO_WIDTH.toDouble() / w
                w = VIDEO_WIDTH
                h = (h * scale).toInt() and 0xFFFE
            }
            screenWidth  = w
            screenHeight = h
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getMetrics(dm)
            var w = dm.widthPixels
            var h = dm.heightPixels
            if (w > VIDEO_WIDTH) {
                val scale = VIDEO_WIDTH.toDouble() / w
                w = VIDEO_WIDTH
                h = (h * scale).toInt() and 0xFFFE
            }
            screenWidth  = w
            screenHeight = h
            screenDpi    = dm.densityDpi
        }
        Log.d(TAG, "Screen metrics: ${screenWidth}x${screenHeight} dpi=$screenDpi")
    }

    // ── Main recording loop ───────────────────────────────────────────────────

    private fun recordLoop() {
        // Obtain the MediaProjection from the stored grant.
        mediaProjection = projectionManager!!.getMediaProjection(pendingResultCode, pendingData!!)
        if (mediaProjection == null) {
            Log.e(TAG, "getMediaProjection returned null — aborting")
            mainHandler.post { emitError("MediaProjection grant invalid") }
            return
        }

        Log.d(TAG, "recordLoop started: chunkSecs=$chunkSecs")

        // Notify Dart that video recording is live.
        mainHandler.post { emitScreenLoopStarted() }

        var firstChunk = true
        while (recording.get() && !stopping.get()) {
            val outFile = File(cacheDir, "chunk_${chunkIndex.toString().padStart(6, '0')}.mp4")
            Log.d(TAG, "CHUNK #$chunkIndex → ${outFile.name}")
            try {
                recordChunk(outFile, chunkSecs * 1_000L, firstChunk)
                firstChunk = false
            } catch (e: Exception) {
                Log.e(TAG, "recordChunk error: ${e.message}", e)
                mainHandler.post { emitError("recordChunk: ${e.message}") }
                break
            }
            val isFinal = !recording.get() || stopping.get()
            if (outFile.exists() && outFile.length() > 0) {
                uploadChunkAsync(outFile, chunkIndex, isFinal)
            }
            chunkIndex++
            currentChunkIndex = chunkIndex

            if (isFinal) break
        }

        // Handle the final chunk if stopping was requested mid-loop.
        cleanupRecorder()
        mediaProjection?.stop()
        mediaProjection = null
        virtualDisplay?.release()
        virtualDisplay = null

        // Keep the FGS alive until every uploadChunkAsync thread finishes.
        // Without this, Android may kill the process while chunks are still
        // being POSTed when stopSelf() is called.
        val drainDeadline = System.currentTimeMillis() + 120_000L
        while (pendingUploads.get() > 0 && System.currentTimeMillis() < drainDeadline) {
            Thread.sleep(200)
        }
        if (pendingUploads.get() > 0) {
            Log.w(TAG, "recordLoop: ${pendingUploads.get()} upload(s) still in-flight after 120s — giving up")
        }

        isRunning = false
        stopSelf()
        Log.d(TAG, "recordLoop ended — all uploads drained, service stopping")
    }

    // ── Record one chunk ──────────────────────────────────────────────────────

    private fun recordChunk(outFile: File, durationMs: Long, isFirst: Boolean) {
        val recorder = MediaRecorder(this).also { mediaRecorder = it }

        recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
        recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
        recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        recorder.setAudioEncodingBitRate(AUDIO_BPS)
        recorder.setAudioSamplingRate(44100)
        recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
        recorder.setVideoEncodingBitRate(VIDEO_BPS)
        recorder.setVideoFrameRate(VIDEO_FPS)
        recorder.setVideoSize(screenWidth, screenHeight)
        recorder.setOutputFile(outFile.absolutePath)
        recorder.prepare()

        // Attach (or reattach) the VirtualDisplay to the recorder's surface.
        val surface = recorder.surface
        if (virtualDisplay == null) {
            // Android 14 requires a callback to be registered before createVirtualDisplay().
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        Log.d(TAG, "MediaProjection.onStop — releasing virtual display")
                        virtualDisplay?.release()
                        virtualDisplay = null
                    }
                }, mainHandler)
            }
            virtualDisplay = mediaProjection!!.createVirtualDisplay(
                    "ScreenCapture",
                    screenWidth, screenHeight, screenDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    surface, null, null
            )
        } else {
            virtualDisplay!!.surface = surface
        }

        recorder.start()
        Log.d(TAG, "MediaRecorder started for chunk #$chunkIndex")

        // Wait for the chunk duration (or until stop is requested).
        val t0 = System.currentTimeMillis()
        while (System.currentTimeMillis() - t0 < durationMs) {
            if (stopping.get() || !recording.get()) break
            Thread.sleep(100)
        }

        // Stop the recorder cleanly.
        try {
            recorder.stop()
        } catch (e: Exception) {
            Log.w(TAG, "recorder.stop() exception (chunk may be incomplete): ${e.message}")
        }
        recorder.release()
        mediaRecorder = null
    }

    private fun cleanupRecorder() {
        try { mediaRecorder?.stop() } catch (_: Exception) {}
        mediaRecorder?.release()
        mediaRecorder = null
    }

    // ── Chunk upload ──────────────────────────────────────────────────────────

    private fun uploadChunkAsync(file: File, index: Int, isFinal: Boolean) {
        val size = file.length()
        pendingUploads.incrementAndGet()
        Thread({
            var attempt = 0
            while (attempt <= 3) {
                try {
                    uploadChunk(file, index, isFinal)
                    file.delete()
                    pendingUploads.decrementAndGet()
                    mainHandler.post { emitChunkUploaded(index, size, isFinal) }
                    return@Thread
                } catch (e: Exception) {
                    Log.e(TAG, "Upload #$index attempt ${attempt + 1}: ${e.message}")
                    attempt++
                    if (attempt <= 3) Thread.sleep(1000L * (1 shl attempt))
                }
            }
            file.delete()
            pendingUploads.decrementAndGet()
            mainHandler.post { emitError("chunk #$index upload permanently failed") }
        }, "ChunkUpload-$index").start()
    }

    private fun uploadChunk(file: File, index: Int, isFinal: Boolean) {
        val boundary = "----ElFaheemBoundary${System.currentTimeMillis()}"
        val conn = java.net.URL(uploadUrl).openConnection() as java.net.HttpURLConnection
        conn.requestMethod  = "POST"
        conn.doOutput       = true
        conn.connectTimeout = 15_000
        conn.readTimeout    = 120_000
        conn.setRequestProperty("Authorization", authToken)
        conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        conn.outputStream.use { out ->
            fun w(s: String) = out.write(s.toByteArray(Charsets.UTF_8))
            w("--$boundary\r\nContent-Disposition: form-data; name=\"chunk_index\"\r\n\r\n$index\r\n")
            w("--$boundary\r\nContent-Disposition: form-data; name=\"is_final\"\r\n\r\n${if (isFinal) "1" else "0"}\r\n")
            w("--$boundary\r\nContent-Disposition: form-data; name=\"chunk\"; ")
            w("filename=\"chunk_${index.toString().padStart(6, '0')}.mp4\"\r\nContent-Type: video/mp4\r\n\r\n")
            file.inputStream().use { it.copyTo(out) }
            w("\r\n--$boundary--\r\n")
        }
        val code = conn.responseCode
        if (code !in 200..299) {
            val body = try { conn.errorStream?.bufferedReader()?.readText() } catch (_: Exception) { "" }
            throw Exception("HTTP $code: $body")
        }
        conn.disconnect()
    }

    private fun stopRecordingClean() {
        recording.set(false)
        stopping.set(true)
        cleanupRecorder()
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
    }

    // ── EventChannel helpers ──────────────────────────────────────────────────

    private fun emitScreenLoopStarted() {
        Log.d(TAG, "emitScreenLoopStarted")
        eventSink?.success(mapOf("event" to "screenLoopStarted"))
    }
    private fun emitMicReadyForShare() {
        eventSink?.success(mapOf("event" to "micReadyForShare"))
    }
    private fun emitMicLoopStarted() {
        eventSink?.success(mapOf("event" to "micLoopStarted"))
    }
    private fun emitChunkUploaded(index: Int, bytes: Long, isFinal: Boolean) {
        eventSink?.success(mapOf(
                "event"      to "chunkUploaded",
                "chunkIndex" to index,
                "bytes"      to bytes,
                "isFinal"    to isFinal,
        ))
    }
    private fun emitError(msg: String) {
        eventSink?.error("REC_ERROR", msg, null)
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active while session is being recorded"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("Recording session")
                    .setContentText("Session recording in progress")
                    .setSmallIcon(android.R.drawable.ic_menu_camera)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setOngoing(true)
                    .build()
}