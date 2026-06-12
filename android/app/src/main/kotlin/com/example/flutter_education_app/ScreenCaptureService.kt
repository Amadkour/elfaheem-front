package com.example.flutter_education_app

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
        const val ACTION_UPGRADE_TO_SCREEN          = "com.example.flutter_education_app.UPGRADE_TO_SCREEN"
        const val ACTION_DOWNGRADE_TO_MIC_FOR_SHARE = "com.example.flutter_education_app.DOWNGRADE_TO_MIC_FOR_SHARE"
        const val ACTION_DOWNGRADE_TO_MIC           = "com.example.flutter_education_app.DOWNGRADE_TO_MIC"
        const val ACTION_PROMOTE_FOR_SHARE          = "com.example.flutter_education_app.PROMOTE_FOR_SHARE"

        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_DATA        = "data"
        const val EXTRA_SESSION_ID  = "sessionId"
        const val EXTRA_UPLOAD_URL  = "uploadUrl"
        const val EXTRA_AUTH_TOKEN  = "authToken"
        const val EXTRA_CHUNK_SECS  = "chunkSeconds"
        const val EXTRA_IS_FINAL    = "isFinal"
        const val EXTRA_CHUNK_INDEX = "chunkIndex"

        private const val TAG       = "ScreenCaptureService"
        private const val VIDEO_BPS = 8_000_000
        private const val VIDEO_FPS = 15
        private const val AUDIO_BPS = 128_000

        @Volatile var isRunning:               Boolean                 = false
        // Set to true only after ACTION_STORE_PROJECTION successfully starts
        // recordLoop().  Used by MainActivity to distinguish a mic-only service
        // (isRunning=true, isProjectionGranted=false) from a fully-recording one.
        @Volatile var isProjectionGranted:     Boolean                 = false
        @Volatile var currentChunkIndex:       Int                     = 0
        @Volatile var eventSink:               EventChannel.EventSink? = null
        @Volatile var onProjectionGrantStored: (() -> Unit)?           = null
        @Volatile var onFgsPromoted:           (() -> Unit)?           = null

        val pendingUploads = AtomicInteger(0)

        // Single-threaded executor for chunk uploads.
        // Chunks are enqueued in order and uploaded one-at-a-time so chunk N
        // always reaches the server BEFORE chunk N+1.  Without this, a large
        // chunk 0 and a tiny chunk 1 (is_final) race — chunk 1 can arrive first
        // and trigger server-side assembly before chunk 0 is saved to disk.
        val uploadExecutor = Executors.newSingleThreadExecutor { r ->
            Thread(r, "ChunkUploader").also { it.isDaemon = true }
        }
    }

    // ── recording state ───────────────────────────────────────────────────────
    // shouldRecord: set true when recording starts, false only by ACTION_STOP or onDestroy.
    //               The chunk loop checks this to know when to emit isFinal=true.
    // shouldStop:   set true only by ACTION_STOP or onDestroy — never by the loop itself.
    // projectionRevoked: set by MediaProjection.Callback.onStop().
    private val shouldRecord       = AtomicBoolean(false)
    private val shouldStop         = AtomicBoolean(false)
    private val projectionRevoked  = AtomicBoolean(false)

    private var projectionManager: MediaProjectionManager? = null
    private var mediaProjection:   MediaProjection?        = null
    private var virtualDisplay:    VirtualDisplay?         = null
    private var mediaRecorder:     MediaRecorder?          = null

    private var sessionId  = 0
    private var uploadUrl  = ""
    private var authToken  = ""
    private var chunkSecs  = 5
    private var chunkIndex = 0

    private var screenWidth  = 1080
    private var screenHeight = 1920
    private var screenDpi    = 420

    private var pendingResultCode = 0
    private var pendingData: Intent? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        // Signal the chunk loop to stop at the next 100 ms tick.
        shouldStop.set(true)
        shouldRecord.set(false)
        // Release media objects immediately — the loop will see null refs
        // and exit gracefully on its next iteration.
        safeReleaseMedia()
        isRunning = false
        isProjectionGranted = false
        // Do NOT delete the session directory here.  uploadChunkAsync deletes
        // each chunk file individually after upload (success or permanent failure).
        // Calling deleteRecursively() here races with in-flight upload tasks on
        // the uploadExecutor thread — chunks that are still queued will have their
        // files deleted before the upload attempt, causing ENOENT on every retry
        // and silently losing those chunks.  Stale dirs from crashed previous
        // sessions are swept at the start of ACTION_START_MIC_ONLY instead.
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
                // Reset the static upload counter so a stale value from a previous
                // session (which may still be draining) does not confuse this one.
                pendingUploads.set(0)
                Log.d(TAG, "ACTION_START_MIC_ONLY session=$sessionId chunkSecs=$chunkSecs")
                // Sweep leftover session dirs from any previously-crashed sessions.
                // We deliberately skip the current sessionId so that a service restart
                // mid-session (e.g. process death + START_STICKY re-delivery) does not
                // delete chunks that are still being uploaded on a surviving executor thread.
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
            }

            ACTION_STORE_PROJECTION -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data: Intent? =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                            intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                        else
                            @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)

                Log.d(TAG, "ACTION_STORE_PROJECTION resultCode=$resultCode")
                promoteForegroundToProjection()
                isRunning = true

                if (resultCode == 0 || data == null) {
                    Log.e(TAG, "invalid grant — aborting")
                    mainHandler.post {
                        emitError("MediaProjection grant invalid")
                        onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
                    }
                    return START_STICKY
                }
                if (uploadUrl.isEmpty()) {
                    Log.e(TAG, "uploadUrl empty — aborting")
                    mainHandler.post {
                        emitError("uploadUrl not set")
                        onProjectionGrantStored?.invoke(); onProjectionGrantStored = null
                    }
                    return START_STICKY
                }
                if (shouldRecord.get()) {
                    Log.w(TAG, "already recording — ignoring duplicate STORE_PROJECTION")
                    mainHandler.post { onProjectionGrantStored?.invoke(); onProjectionGrantStored = null }
                    return START_STICKY
                }

                pendingResultCode = resultCode
                pendingData       = data
                projectionRevoked.set(false)
                shouldStop.set(false)
                shouldRecord.set(true)
                isProjectionGranted = true

                Thread({ recordLoop() }, "ScreenRecorder").start()

                // Unblock Dart AFTER the thread is started so screenLoopStarted
                // is guaranteed to arrive before Dart sends any follow-up commands.
                mainHandler.post {
                    onProjectionGrantStored?.invoke()
                    onProjectionGrantStored = null
                }
            }

            ACTION_STOP -> {
                Log.d(TAG, "ACTION_STOP — signalling chunk loop")
                // Only set the flags — never touch media objects here.
                // The chunk loop will finish the current chunk, upload it as
                // isFinal=true, drain all uploads, then call stopSelf().
                shouldStop.set(true)
                shouldRecord.set(false)
            }

            ACTION_UPGRADE_TO_SCREEN -> {
                Log.d(TAG, "ACTION_UPGRADE_TO_SCREEN")
                promoteForegroundToProjection()
                mainHandler.post { emitScreenLoopStarted() }
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

    private fun recordLoop() {
        // ── 1. obtain projection ──────────────────────────────────────────────
        mediaProjection = try {
            projectionManager!!.getMediaProjection(pendingResultCode, pendingData!!)
        } catch (e: Exception) {
            Log.e(TAG, "getMediaProjection failed: ${e.message}", e); null
        }

        if (mediaProjection == null) {
            Log.e(TAG, "null MediaProjection — aborting")
            mainHandler.post { emitError("Could not obtain MediaProjection") }
            shouldRecord.set(false)
            isRunning = false
            stopSelf()
            return
        }

        // ── 2. register revocation callback once ──────────────────────────────
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {
                    Log.w(TAG, "MediaProjection revoked by system")
                    projectionRevoked.set(true)
                    shouldStop.set(true)
                    shouldRecord.set(false)
                }
            }, mainHandler)
        }

        Log.d(TAG, "recordLoop started — ${screenWidth}x${screenHeight} chunkSecs=$chunkSecs")
        mainHandler.post { emitScreenLoopStarted() }

        // ── 3. chunk loop ─────────────────────────────────────────────────────
        //
        // Loop invariant: shouldRecord=true AND shouldStop=false means keep going.
        // Only ACTION_STOP / onDestroy / projectionRevoked flip these flags.
        // The loop itself NEVER touches shouldRecord or shouldStop.
        //
        // Session-scoped chunk directory prevents files from one session overwriting
        // a concurrent upload from the previous session (cacheDir is app-global).
        val sessionDir = File(cacheDir, "session_$sessionId").also { it.mkdirs() }

        while (shouldRecord.get() && !shouldStop.get()) {
            val outFile = File(sessionDir, "chunk_${chunkIndex.toString().padStart(6, '0')}.mp4")
            Log.d(TAG, "recording chunk #$chunkIndex → ${outFile.absolutePath}")

            val recordOk = runCatching { recordChunk(outFile, chunkSecs * 1_000L) }

            if (recordOk.isFailure) {
                val msg = recordOk.exceptionOrNull()?.message ?: "unknown"
                Log.e(TAG, "recordChunk #$chunkIndex exception: $msg")
                if (!shouldStop.get()) mainHandler.post { emitError("chunk #$chunkIndex failed: $msg") }
                // Salvage partial file if anything was written.
                if (outFile.exists() && outFile.length() > 0L) {
                    uploadChunkAsync(outFile, chunkIndex, isFinal = true)
                    chunkIndex++; currentChunkIndex = chunkIndex
                }
                break   // exit loop — do not attempt further chunks
            }

            // Determine isFinal AFTER recordChunk returns so we pick up any
            // stop signal that arrived during the recording window.
            val isFinal = !shouldRecord.get() || shouldStop.get()

            if (outFile.exists() && outFile.length() > 0L) {
                Log.d(TAG, "chunk #$chunkIndex ready: ${outFile.length()}B isFinal=$isFinal — queuing upload")
                uploadChunkAsync(outFile, chunkIndex, isFinal)
            } else {
                Log.w(TAG, "chunk #$chunkIndex is 0 bytes — skipping upload")
            }

            chunkIndex++
            currentChunkIndex = chunkIndex

            if (isFinal) break
            // continue → next iteration creates chunk #(chunkIndex) immediately
        }

        // ── 4. release media objects ──────────────────────────────────────────
        // Do this BEFORE draining uploads so the projection / display are freed
        // as soon as recording ends, not held for up to 120 s.
        safeReleaseMedia()

        // ── 5. drain pending uploads (keep FGS alive, max 120 s) ─────────────
        Log.d(TAG, "all chunks recorded — waiting for ${pendingUploads.get()} upload(s)…")
        val deadline = System.currentTimeMillis() + 120_000L
        while (pendingUploads.get() > 0 && System.currentTimeMillis() < deadline) {
            Thread.sleep(200)
        }
        if (pendingUploads.get() > 0)
            Log.w(TAG, "${pendingUploads.get()} upload(s) unfinished after 120 s")

        isRunning = false
        stopSelf()
        Log.d(TAG, "recordLoop done")
    }

    // ── record one chunk ──────────────────────────────────────────────────────

    private fun recordChunk(outFile: File, durationMs: Long) {
        // Write to a .tmp file first; rename to outFile only after stop() succeeds.
        // This guarantees outFile is always a complete, moov-finalised MP4.
        // If stop() throws (e.g. < 100 ms of frames), the .tmp is deleted and
        // outFile never appears — the chunk loop sees outFile.exists()==false and
        // skips the upload rather than sending a corrupt file to the server.
        val tmpFile = File(outFile.parent, "${outFile.name}.tmp")
        tmpFile.delete() // clean up any stale .tmp from a previous crash

        // Fresh MediaRecorder for every chunk — reusing a stopped recorder
        // causes IllegalStateException on Android 12+.
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
        recorder.setOutputFile(tmpFile.absolutePath)  // write to .tmp
        recorder.prepare()

        val surface = recorder.surface

        // VirtualDisplay is created ONCE per session (first chunk) and then
        // only its surface is swapped.  Re-creating it every chunk causes
        // Android 14+ to produce a silent 0-byte file on the second chunk.
        if (virtualDisplay == null) {
            virtualDisplay = mediaProjection!!.createVirtualDisplay(
                    "ScreenCapture",
                    screenWidth, screenHeight, screenDpi,
                    DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                    surface, null, null,
            )
            Log.d(TAG, "VirtualDisplay created ${screenWidth}x${screenHeight}@${screenDpi}dpi")
        } else {
            // Swap surface on existing VirtualDisplay — do NOT release/recreate it.
            virtualDisplay!!.surface = surface
        }

        recorder.start()
        Log.d(TAG, "MediaRecorder.start() chunk #$chunkIndex")

        // Wait for chunk duration in short ticks so we catch stop signals fast.
        val t0 = System.currentTimeMillis()
        while (System.currentTimeMillis() - t0 < durationMs) {
            if (shouldStop.get() || !shouldRecord.get() || projectionRevoked.get()) break
            Thread.sleep(50)
        }

        var stopOk = false
        try {
            recorder.stop()
            stopOk = true
            Log.d(TAG, "MediaRecorder.stop() chunk #$chunkIndex size=${tmpFile.length()}B")
        } catch (e: Exception) {
            // stop() throws RuntimeException when no frames were encoded yet
            // (recording was shorter than ~100 ms, or the surface had no frames).
            // This means the tmp file has no valid moov atom — discard it.
            Log.w(TAG, "recorder.stop() failed on chunk #$chunkIndex (${e.message}) — discarding")
        } finally {
            recorder.release()
            mediaRecorder = null
        }

        if (stopOk && tmpFile.length() > 0L) {
            // Atomic rename: outFile now exists and is a complete, valid MP4.
            tmpFile.renameTo(outFile)
            Log.d(TAG, "chunk #$chunkIndex finalised → ${outFile.name} (${outFile.length()}B)")
        } else {
            tmpFile.delete()
            // Leave outFile absent — the chunk loop's outFile.exists() check skips upload.
        }
    }

    // ── upload ────────────────────────────────────────────────────────────────

    private fun uploadChunkAsync(file: File, index: Int, isFinal: Boolean) {
        // Enqueue into the single-threaded executor so uploads are sent in
        // strict chunk-index order.  A raw Thread.start() per chunk lets large
        // chunks (chunk 0) lose the race to small final chunks (chunk 1),
        // causing the server to assemble with only the final chunk and discard
        // all earlier data.
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
                    if (attempt <= 3) Thread.sleep(1_000L * (1 shl attempt)) // 2 s, 4 s, 8 s
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
                    " filename=\"chunk_${index.toString().padStart(6,'0')}.mp4\"\r\n" +
                    "Content-Type: video/mp4\r\n\r\n").toByteArray())
            file.inputStream().use { it.copyTo(out) }
            out.write("\r\n--$boundary--\r\n".toByteArray())
        }
        val code = conn.responseCode
        conn.disconnect()
        if (code !in 200..299) throw Exception("HTTP $code")
    }

    // ── teardown ──────────────────────────────────────────────────────────────

    /** Releases recorder / virtualDisplay / mediaProjection without touching
     *  shouldRecord / shouldStop flags — safe to call from any context. */
    private fun safeReleaseMedia() {
        try { mediaRecorder?.stop()    } catch (_: Exception) {}
        try { mediaRecorder?.release() } catch (_: Exception) {}
        mediaRecorder = null
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { mediaProjection?.stop()   } catch (_: Exception) {}
        mediaProjection = null
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
                    .setContentText("Session recording in progress")
                    .setSmallIcon(android.R.drawable.ic_menu_camera)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setOngoing(true)
                    .build()
}