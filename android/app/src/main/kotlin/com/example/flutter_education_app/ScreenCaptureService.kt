package com.example.flutter_education_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
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

// ─────────────────────────────────────────────────────────────────────────────
// ScreenCaptureService — Option B: synchronous upgrade with EventChannel callback
//
// UPGRADE FLOW (mic-only → screen+audio → LiveKit screen share):
//
//   1. ACTION_START_MIC_ONLY  → mic-only loop starts, no MediaProjection needed
//   2. ACTION_STORE_PROJECTION → dialog grant stored, FGS upgraded to
//      MEDIA_PROJECTION, onProjectionGrantStored callback fires to Dart
//      (FIX 1: callback fires AFTER getMediaProjection() completes, not before)
//   3. ACTION_UPGRADE_TO_SCREEN → mic loop drains, screen loop starts,
//      createVirtualDisplay() called, "screenLoopStarted" event emitted
//   4. ACTION_RELEASE_VIRTUAL_DISPLAY → service releases its VirtualDisplay
//      (FIX 3: prevents dual-VirtualDisplay conflict with flutter_webrtc)
//   5. Dart calls setScreenShareEnabled(true) → flutter_webrtc creates its own
//      VirtualDisplay safely, no second dialog, no conflict
//   6. ACTION_DOWNGRADE_TO_MIC → screen loop drains, mic loop restarts,
//      "micLoopStarted" event emitted
//   7. ACTION_STOP → stopping flag set, loops drain cleanly, resources released
//      (FIX 2: recording flag NOT force-cleared; loops drain and release properly)
// ─────────────────────────────────────────────────────────────────────────────
class ScreenCaptureService : Service() {

    companion object {
        const val CHANNEL_ID              = "screen_capture_channel"
        const val CHANNEL_NAME            = "Screen Capture"
        const val NOTIFICATION_ID         = 1001
        const val ACTION_STOP                    = "com.example.flutter_education_app.STOP_SCREEN_CAPTURE"
        const val ACTION_START_MIC_ONLY          = "com.example.flutter_education_app.START_MIC_ONLY"
        const val ACTION_STORE_PROJECTION        = "com.example.flutter_education_app.STORE_PROJECTION"
        const val ACTION_UPGRADE_TO_SCREEN       = "com.example.flutter_education_app.UPGRADE_TO_SCREEN"
        const val ACTION_DOWNGRADE_TO_MIC        = "com.example.flutter_education_app.DOWNGRADE_TO_MIC"
        // FIX 3: new action — releases service VirtualDisplay before flutter_webrtc
        // creates its own, preventing the dual-VirtualDisplay crash/blackout.
        const val ACTION_RELEASE_VIRTUAL_DISPLAY = "com.example.flutter_education_app.RELEASE_VIRTUAL_DISPLAY"
        const val EXTRA_RESULT_CODE       = "resultCode"
        const val EXTRA_DATA              = "data"
        const val EXTRA_SESSION_ID        = "sessionId"
        const val EXTRA_UPLOAD_URL        = "uploadUrl"
        const val EXTRA_AUTH_TOKEN        = "authToken"
        const val EXTRA_CHUNK_SECS        = "chunkSeconds"
        const val EXTRA_IS_FINAL          = "isFinal"
        const val EXTRA_CHUNK_INDEX       = "chunkIndex"

        private const val TAG = "ScreenCaptureService"

        private enum class RecMode { NONE, MIC_ONLY, SCREEN_AUDIO }
        @Volatile private var recMode = RecMode.NONE

        @Volatile var eventSink: EventChannel.EventSink? = null

        @Volatile var isRunning: Boolean         = false
        @Volatile var hasProjectionGrant: Boolean = false
        @Volatile var currentChunkIndex: Int      = 0

        @Volatile private var isUpgrading = false
    }

    // ── Instance state ────────────────────────────────────────────────────────
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay:  VirtualDisplay?  = null

    private var videoCodec:  MediaCodec?  = null
    private var audioCodec:  MediaCodec?  = null
    private var audioRecord: AudioRecord? = null
    private var muxer:       MediaMuxer?  = null

    private var videoTrackIndex = -1
    private var audioTrackIndex = -1
    private var muxerStarted    = false

    private val recording = AtomicBoolean(false)
    private val stopping  = AtomicBoolean(false)

    private var sessionId  = 0
    private var uploadUrl  = ""
    private var authToken  = ""
    private var chunkSecs  = 5
    private var chunkIndex = 0

    private var screenWidth  = 1280
    private var screenHeight = 720
    private var screenDpi    = 160

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {

            // ── FIX 2: Stop everything cleanly ───────────────────────────────
            // Previously this force-cleared recording=false, which races with the
            // loop threads still writing/uploading. Now we only set stopping=true
            // and let the loops exit naturally and call release themselves.
            // isUpgrading=false ensures the loops know this is a real stop
            // (not a mode switch) and will call releaseAllResources()/stopSelf().
            ACTION_STOP -> {
                val isFinal = intent.getBooleanExtra(EXTRA_IS_FINAL, true)
                Log.d(TAG, "ACTION_STOP isFinal=$isFinal")
                isUpgrading = false   // not a mode switch — loops must fully release
                stopping.set(true)
                // Do NOT set recording=false here. The active loop checks stopping
                // on its next iteration, finalises the current chunk, uploads it,
                // calls release*Resources(), and then stopSelf(). Force-clearing
                // recording here races with the muxer still writing sample data.
                return START_NOT_STICKY
            }

            // ── Phase 1: mic-only ─────────────────────────────────────────────
            ACTION_START_MIC_ONLY -> {
                sessionId  = intent.getIntExtra(EXTRA_SESSION_ID, 0)
                uploadUrl  = intent.getStringExtra(EXTRA_UPLOAD_URL) ?: ""
                authToken  = intent.getStringExtra(EXTRA_AUTH_TOKEN) ?: ""
                chunkSecs  = intent.getIntExtra(EXTRA_CHUNK_SECS, 5)
                chunkIndex = intent.getIntExtra(EXTRA_CHUNK_INDEX, 0)

                Log.d(TAG, "ACTION_START_MIC_ONLY session=$sessionId chunkSecs=$chunkSecs")
                startForegroundNotification(isMicOnly = true)
                isRunning = true

                if (!recording.get()) {
                    recording.set(true)
                    stopping.set(false)
                    recMode = RecMode.MIC_ONLY
                    Thread({ micOnlyLoop() }, "MicOnlyRecorder").start()
                }
            }

            // ── Store MediaProjection grant ───────────────────────────────────
            // FIX 1: We now call MainActivity.onProjectionGrantStored AFTER both
            // startForeground(MEDIA_PROJECTION) and getMediaProjection() have
            // completed. Previously MainActivity used Handler.post to reply to Dart
            // after only a single looper tick, which could return before
            // onStartCommand ran, meaning hasProjectionGrant was still false when
            // Dart called upgradeToScreenRecording().
            ACTION_STORE_PROJECTION -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
                val data: Intent? = if (Build.VERSION.SDK_INT >= 33)
                    intent.getParcelableExtra(EXTRA_DATA, Intent::class.java)
                else
                    @Suppress("DEPRECATION") intent.getParcelableExtra(EXTRA_DATA)

                // Step 1: upgrade FGS type BEFORE obtaining the grant (Android 14 requirement).
                startForegroundNotification(isMicOnly = false)
                isRunning = true

                // Step 2: obtain the MediaProjection grant.
                if (data != null && mediaProjection == null) {
                    val mpm = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                    mediaProjection = mpm.getMediaProjection(resultCode, data)
                    mediaProjection!!.registerCallback(object : MediaProjection.Callback() {
                        override fun onStop() {
                            Log.d(TAG, "MediaProjection stopped externally")
                            stopping.set(true)
                            recording.set(false)
                            hasProjectionGrant = false
                        }
                    }, mainHandler)
                    hasProjectionGrant = true
                    Log.d(TAG, "STORE_PROJECTION: grant stored, FGS=MEDIA_PROJECTION")
                }

                // Step 3: NOW reply to Dart. Both startForeground() and
                // getMediaProjection() are done — hasProjectionGrant is true.
                mainHandler.post {
                    MainActivity.onProjectionGrantStored?.invoke()
                    MainActivity.onProjectionGrantStored = null
                }
                return START_STICKY
            }

            // ── Upgrade mic-only → screen+audio ──────────────────────────────
            ACTION_UPGRADE_TO_SCREEN -> {
                Log.d(TAG, "ACTION_UPGRADE_TO_SCREEN recMode=$recMode")
                when (recMode) {
                    RecMode.SCREEN_AUDIO -> {
                        Log.d(TAG, "Already SCREEN_AUDIO — emitting screenLoopStarted")
                        mainHandler.post { emitScreenLoopStarted() }
                    }
                    RecMode.MIC_ONLY -> {
                        if (mediaProjection == null) {
                            Log.e(TAG, "UPGRADE_TO_SCREEN: no projection grant — emitting error")
                            mainHandler.post { emitError("upgradeToScreen: no MediaProjection grant") }
                            return START_STICKY
                        }
                        startForegroundNotification(isMicOnly = false)

                        isUpgrading = true
                        stopping.set(true)

                        Thread {
                            val deadline = System.currentTimeMillis() + (chunkSecs + 2) * 1000L
                            while (recording.get() && System.currentTimeMillis() < deadline) {
                                Thread.sleep(30)
                            }
                            if (recording.get()) {
                                Log.w(TAG, "Mic loop deadline exceeded, forcing upgrade")
                                recording.set(false)
                            }

                            resolveScreenMetrics()
                            recording.set(true)
                            stopping.set(false)
                            recMode = RecMode.SCREEN_AUDIO
                            isUpgrading = false
                            Thread({ recordLoop() }, "ScreenRecorder").start()
                            Log.d(TAG, "Screen+audio loop launched from chunk #$chunkIndex")
                        }.start()
                    }
                    RecMode.NONE -> {
                        if (mediaProjection == null) {
                            Log.e(TAG, "UPGRADE_TO_SCREEN (NONE): no projection grant")
                            mainHandler.post { emitError("upgradeToScreen: no MediaProjection grant") }
                            return START_STICKY
                        }
                        startForegroundNotification(isMicOnly = false)
                        resolveScreenMetrics()
                        recording.set(true)
                        stopping.set(false)
                        recMode = RecMode.SCREEN_AUDIO
                        Thread({ recordLoop() }, "ScreenRecorder").start()
                        Log.d(TAG, "Screen+audio loop launched (from NONE) chunk #$chunkIndex")
                    }
                }
                return START_STICKY
            }

            // ── FIX 3: Release VirtualDisplay before flutter_webrtc creates its own ──
            // Android allows only one active VirtualDisplay per MediaProjection on
            // most devices. If our service holds a VirtualDisplay when
            // setScreenShareEnabled(true) is called, flutter_webrtc's VirtualDisplay
            // creation either fails silently (black recording) or crashes.
            // Dart calls this AFTER upgradeToScreenRecording() and BEFORE
            // setScreenShareEnabled(true).
            //
            // The screen+audio loop continues to run after the VirtualDisplay is
            // released — it will produce chunks with audio only until the next chunk
            // boundary, then the loop will exit on the next stopping.set(true) from
            // ACTION_DOWNGRADE_TO_MIC when screen share stops. This is acceptable:
            // the primary recording source during screen share is the LiveKit egress
            // or the client capture from the track, not the VirtualDisplay.
            //
            // If you want to keep recording screen during the share phase, see the
            // comment on ACTION_DOWNGRADE_TO_MIC below — you can re-create the
            // VirtualDisplay from the same mediaProjection after LiveKit releases its
            // own, but that requires knowing when LiveKit has released it.
            ACTION_RELEASE_VIRTUAL_DISPLAY -> {
                Log.d(TAG, "ACTION_RELEASE_VIRTUAL_DISPLAY — releasing service VirtualDisplay")
                virtualDisplay?.release()
                virtualDisplay = null
                // No change to recording/recMode — audio loop continues.
                return START_STICKY
            }

            // ── Downgrade screen+audio → mic-only ────────────────────────────
            ACTION_DOWNGRADE_TO_MIC -> {
                Log.d(TAG, "ACTION_DOWNGRADE_TO_MIC recMode=$recMode")
                if (recMode == RecMode.SCREEN_AUDIO && recording.get()) {
                    isUpgrading = true
                    stopping.set(true)

                    Thread {
                        val deadline = System.currentTimeMillis() + (chunkSecs + 2) * 1000L
                        while (recording.get() && System.currentTimeMillis() < deadline) {
                            Thread.sleep(30)
                        }
                        if (recording.get()) {
                            recording.set(false)
                            Log.w(TAG, "Screen loop deadline exceeded, forcing downgrade")
                        }
                        mainHandler.post { startForegroundNotification(isMicOnly = true) }
                        recording.set(true)
                        stopping.set(false)
                        recMode = RecMode.MIC_ONLY
                        isUpgrading = false
                        Thread({ micOnlyLoop() }, "MicOnlyRecorder").start()
                        mainHandler.post { emitMicLoopStarted() }
                        Log.d(TAG, "Downgraded to mic-only from chunk #$chunkIndex")
                    }.start()
                } else {
                    mainHandler.post { emitMicLoopStarted() }
                }
                return START_STICKY
            }

            else -> {
                startForegroundNotification(isMicOnly = true)
                isRunning = true
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopping.set(true)
        recording.set(false)
        super.onDestroy()
    }

    // ── FGS notification ──────────────────────────────────────────────────────

    private fun startForegroundNotification(isMicOnly: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = if (isMicOnly) {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            startForeground(NOTIFICATION_ID, buildNotification(), serviceType)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    // ── Screen metrics ────────────────────────────────────────────────────────

    private fun resolveScreenMetrics() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = wm.currentWindowMetrics.bounds
            screenWidth  = b.width()
            screenHeight = b.height()
        } else {
            val dm = DisplayMetrics()
            @Suppress("DEPRECATION") wm.defaultDisplay.getMetrics(dm)
            screenWidth  = dm.widthPixels
            screenHeight = dm.heightPixels
            screenDpi    = dm.densityDpi
        }
        if (screenWidth > 1920) {
            val scale = 1920.0 / screenWidth
            screenWidth  = 1920
            screenHeight = (screenHeight * scale).toInt() and 0xFFFE
        }
        screenDpi = resources.displayMetrics.densityDpi
        Log.d(TAG, "Screen metrics: ${screenWidth}x${screenHeight}@${screenDpi}dpi")
    }

    // ── Mic-only loop ─────────────────────────────────────────────────────────

    private fun micOnlyLoop() {
        while (recording.get() && !stopping.get()) {
            val outFile = File(cacheDir, "chunk_${chunkIndex.toString().padStart(6,'0')}.mp4")
            Log.d(TAG, "MIC chunk #$chunkIndex → ${outFile.name}")
            try {
                recordMicChunk(outFile, chunkSecs * 1_000L)
            } catch (e: Exception) {
                Log.e(TAG, "recordMicChunk error: ${e.message}", e)
                mainHandler.post { emitError("recordMicChunk: ${e.message}") }
                recording.set(false)
                break
            }
            if (outFile.exists() && outFile.length() > 0) {
                // FIX: isUpgrading=true means this is a mode-switch drain chunk,
                // NOT the final chunk of the recording. Marking it isFinal=true
                // would cause Dart to cancel its EventChannel subscription and
                // enter RecState.done mid-session, silently dropping all subsequent
                // chunk events. Only set isFinal=true when we are truly stopping.
                val isFinal = (!recording.get() || stopping.get()) && !isUpgrading
                uploadChunkAsync(outFile, chunkIndex, isFinal)
            }
            chunkIndex++
            currentChunkIndex = chunkIndex
        }

        if (isUpgrading) {
            Log.d(TAG, "micOnlyLoop: exiting for mode switch")
            recording.set(false)
            return
        }

        releaseMicResources()
        isRunning = false
        recMode = RecMode.NONE
        stopSelf()
    }

    // ── Screen+audio loop ─────────────────────────────────────────────────────

    private fun recordLoop() {
        var firstChunk = true
        while (recording.get() && !stopping.get()) {
            val outFile = File(cacheDir, "chunk_${chunkIndex.toString().padStart(6,'0')}.mp4")
            Log.d(TAG, "SCREEN chunk #$chunkIndex → ${outFile.name}")
            try {
                recordChunk(outFile, chunkSecs * 1_000L, notifyStarted = firstChunk)
                firstChunk = false
            } catch (e: Exception) {
                Log.e(TAG, "recordChunk error: ${e.message}", e)
                mainHandler.post { emitError("recordChunk: ${e.message}") }
                recording.set(false)
                break
            }
            if (outFile.exists() && outFile.length() > 0) {
                // FIX: isUpgrading=true means this is a mode-switch drain chunk
                // (downgrade screen→mic), not the true end of recording.
                val isFinal = (!recording.get() || stopping.get()) && !isUpgrading
                uploadChunkAsync(outFile, chunkIndex, isFinal)
            }
            chunkIndex++
            currentChunkIndex = chunkIndex
        }

        if (isUpgrading) {
            Log.d(TAG, "recordLoop: exiting for downgrade")
            releaseScreenResources()
            recording.set(false)
            return
        }

        releaseAllResources()
        hasProjectionGrant = false
        isRunning = false
        recMode = RecMode.NONE
        stopSelf()
    }

    // ── Record one mic-only chunk ─────────────────────────────────────────────

    private fun recordMicChunk(outFile: File, durationMs: Long) {
        val sampleRate  = 44100
        val channelMask = AudioFormat.CHANNEL_IN_MONO
        val audioFmt    = AudioFormat.ENCODING_PCM_16BIT
        val minBuf      = AudioRecord.getMinBufferSize(sampleRate, channelMask, audioFmt)

        val ar = AudioRecord(
                android.media.MediaRecorder.AudioSource.MIC,
                sampleRate, channelMask, audioFmt, minBuf * 4
        )
        if (ar.state != AudioRecord.STATE_INITIALIZED) {
            ar.release()
            throw IllegalStateException("AudioRecord (mic) failed to init")
        }

        val aFmt = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 1
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 128_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, minBuf)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also {
            it.configure(aFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            it.start()
        }
        ar.startRecording()

        val mux      = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var trackIdx = -1
        var muxOk    = false
        val info     = MediaCodec.BufferInfo()
        val startMs  = System.currentTimeMillis()

        try {
            while (true) {
                val elapsed   = System.currentTimeMillis() - startMs
                val shouldEnd = elapsed >= durationMs || stopping.get() || !recording.get()

                val ibIdx = codec.dequeueInputBuffer(0)
                if (ibIdx >= 0) {
                    val ib   = codec.getInputBuffer(ibIdx)!!
                    ib.clear()
                    val read = ar.read(ib, ib.capacity())
                    if (read > 0) {
                        codec.queueInputBuffer(ibIdx, 0, read, elapsed * 1000,
                                if (shouldEnd) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    } else {
                        codec.queueInputBuffer(ibIdx, 0, 0, 0, 0)
                    }
                }

                var eos   = false
                val obIdx = codec.dequeueOutputBuffer(info, 10_000L)
                when {
                    obIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        trackIdx = mux.addTrack(codec.outputFormat)
                        mux.start(); muxOk = true
                    }
                    obIdx >= 0 -> {
                        val buf = codec.getOutputBuffer(obIdx)
                        if (muxOk && buf != null &&
                                (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0)
                            mux.writeSampleData(trackIdx, buf, info)
                        eos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        codec.releaseOutputBuffer(obIdx, false)
                    }
                }
                if (shouldEnd && eos) break
                if (elapsed > durationMs * 2) break
            }
        } finally {
            try { ar.stop() } catch (_: Exception) {}
            ar.release()
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            if (muxOk) try { mux.stop() } catch (_: Exception) {}
            mux.release()
        }
    }

    // ── Record one screen+audio chunk ─────────────────────────────────────────
    //
    // notifyStarted=true → emits "screenLoopStarted" after createVirtualDisplay().
    // This unblocks Dart's upgradeToScreenRecording() Completer, after which Dart
    // calls releaseVirtualDisplay() then setScreenShareEnabled(true).

    private fun recordChunk(outFile: File, durationMs: Long, notifyStarted: Boolean = false) {
        // ── Video codec ───────────────────────────────────────────────────────
        val vFmt = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC, screenWidth, screenHeight
        ).apply {
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, 30)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            setInteger(MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        }
        videoCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also {
            it.configure(vFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
        val inputSurface = videoCodec!!.createInputSurface()

        // ── VirtualDisplay ────────────────────────────────────────────────────
        // Creates the display capture surface. This will be released shortly after
        // via ACTION_RELEASE_VIRTUAL_DISPLAY so flutter_webrtc can create its own.
        virtualDisplay = mediaProjection!!.createVirtualDisplay(
                "ElFaheemCapture",
                screenWidth, screenHeight, screenDpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                inputSurface, null, null
        )
        videoCodec!!.start()

        // ── Notify Dart that VirtualDisplay is live ───────────────────────────
        // Dart's Completer unblocks, then Dart calls releaseVirtualDisplay()
        // and only then calls setScreenShareEnabled(true).
        if (notifyStarted) {
            mainHandler.post { emitScreenLoopStarted() }
        }

        // ── Audio codec + AudioRecord ─────────────────────────────────────────
        val sampleRate  = 44100
        val channelMask = AudioFormat.CHANNEL_IN_STEREO
        val audioFmt    = AudioFormat.ENCODING_PCM_16BIT
        val minBuf      = AudioRecord.getMinBufferSize(sampleRate, channelMask, audioFmt)

        val audioCapture = buildAudioRecord(sampleRate, channelMask, audioFmt, minBuf)
        val aFmt = MediaFormat.createAudioFormat(
                MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, 2
        ).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE,
                    MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 192_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, minBuf)
        }
        audioCodec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also {
            it.configure(aFmt, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            it.start()
        }
        audioRecord = audioCapture
        audioCapture?.startRecording()

        // ── Muxer ─────────────────────────────────────────────────────────────
        muxer           = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        videoTrackIndex = -1
        audioTrackIndex = -1
        muxerStarted    = false

        val startTime  = System.currentTimeMillis()
        val videoInfo  = MediaCodec.BufferInfo()
        val audioInfo  = MediaCodec.BufferInfo()
        val TIMEOUT_US = 10_000L

        while (true) {
            val elapsed   = System.currentTimeMillis() - startTime
            val shouldEnd = elapsed >= durationMs || stopping.get() || !recording.get()

            // Feed PCM → audio codec
            if (audioCapture != null &&
                    audioCapture.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val ibIdx = audioCodec!!.dequeueInputBuffer(0)
                if (ibIdx >= 0) {
                    val ib   = audioCodec!!.getInputBuffer(ibIdx)!!
                    ib.clear()
                    val read = audioCapture.read(ib, ib.capacity())
                    if (read > 0) {
                        audioCodec!!.queueInputBuffer(ibIdx, 0, read, elapsed * 1000,
                                if (shouldEnd) MediaCodec.BUFFER_FLAG_END_OF_STREAM else 0)
                    } else {
                        audioCodec!!.queueInputBuffer(ibIdx, 0, 0, 0, 0)
                    }
                }
            }

            if (shouldEnd) {
                try { videoCodec!!.signalEndOfInputStream() } catch (_: Exception) {}
            }

            // Drain video
            var videoEos = false
            val vIdx = videoCodec!!.dequeueOutputBuffer(videoInfo, TIMEOUT_US)
            when {
                vIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        videoTrackIndex = muxer!!.addTrack(videoCodec!!.outputFormat)
                        if (audioTrackIndex >= 0) { muxer!!.start(); muxerStarted = true }
                    }
                }
                vIdx >= 0 -> {
                    val buf = videoCodec!!.getOutputBuffer(vIdx)
                    if (muxerStarted && buf != null &&
                            (videoInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0)
                        muxer!!.writeSampleData(videoTrackIndex, buf, videoInfo)
                    videoEos = (videoInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    videoCodec!!.releaseOutputBuffer(vIdx, false)
                }
            }

            // Drain audio
            var audioEos = false
            val aIdx = audioCodec!!.dequeueOutputBuffer(audioInfo, TIMEOUT_US)
            when {
                aIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        audioTrackIndex = muxer!!.addTrack(audioCodec!!.outputFormat)
                        if (videoTrackIndex >= 0) { muxer!!.start(); muxerStarted = true }
                    }
                }
                aIdx >= 0 -> {
                    val buf = audioCodec!!.getOutputBuffer(aIdx)
                    if (muxerStarted && buf != null &&
                            (audioInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0)
                        muxer!!.writeSampleData(audioTrackIndex, buf, audioInfo)
                    audioEos = (audioInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                    audioCodec!!.releaseOutputBuffer(aIdx, false)
                }
            }

            if (shouldEnd && videoEos && audioEos) break
            if (elapsed > durationMs * 2) break
        }

        // Release per-chunk resources
        audioCapture?.stop(); audioCapture?.release(); audioRecord = null
        try { videoCodec?.stop() } catch (_: Exception) {}
        videoCodec?.release(); videoCodec = null
        try { audioCodec?.stop() } catch (_: Exception) {}
        audioCodec?.release(); audioCodec = null
        // NOTE: virtualDisplay may already be null if ACTION_RELEASE_VIRTUAL_DISPLAY
        // fired during this chunk. The null-safe release here is intentional.
        virtualDisplay?.release(); virtualDisplay = null
        if (muxerStarted) try { muxer?.stop() } catch (_: Exception) {}
        muxer?.release(); muxer = null; muxerStarted = false
    }

    // ── AudioRecord builder ───────────────────────────────────────────────────

    private fun buildAudioRecord(
            sampleRate: Int, channelMask: Int, audioFmt: Int, bufSize: Int
    ): AudioRecord? {
        for (src in listOf(
                android.media.MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                android.media.MediaRecorder.AudioSource.MIC
        )) {
            try {
                val ar = AudioRecord(src, sampleRate, channelMask, audioFmt, bufSize * 4)
                if (ar.state == AudioRecord.STATE_INITIALIZED) {
                    Log.d(TAG, "AudioRecord source=$src OK")
                    return ar
                }
                ar.release()
            } catch (e: Exception) {
                Log.w(TAG, "AudioRecord source=$src failed: ${e.message}")
            }
        }
        Log.e(TAG, "buildAudioRecord: all sources failed")
        return null
    }

    // ── Release helpers ───────────────────────────────────────────────────────

    private fun releaseScreenResources() {
        try { audioRecord?.stop(); audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        try { videoCodec?.stop(); videoCodec?.release() } catch (_: Exception) {}
        videoCodec = null
        try { audioCodec?.stop(); audioCodec?.release() } catch (_: Exception) {}
        audioCodec = null
        virtualDisplay?.release(); virtualDisplay = null
        if (muxerStarted) try { muxer?.stop() } catch (_: Exception) {}
        muxer?.release(); muxer = null; muxerStarted = false
    }

    private fun releaseMicResources() {
        try { audioRecord?.stop(); audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        try { audioCodec?.stop(); audioCodec?.release() } catch (_: Exception) {}
        audioCodec = null
        if (muxerStarted) try { muxer?.stop() } catch (_: Exception) {}
        muxer?.release(); muxer = null; muxerStarted = false
    }

    private fun releaseAllResources() {
        releaseScreenResources()
        mediaProjection?.stop(); mediaProjection = null
    }

    // ── Upload ────────────────────────────────────────────────────────────────

    private fun uploadChunkAsync(file: File, index: Int, isFinal: Boolean) {
        val fileSize = file.length()
        Thread({
            var attempt = 0
            while (attempt <= 3) {
                try {
                    uploadChunk(file, index, isFinal)
                    file.delete()
                    mainHandler.post { emitChunkUploaded(index, fileSize, isFinal) }
                    return@Thread
                } catch (e: Exception) {
                    Log.e(TAG, "Upload #$index attempt ${attempt+1}: ${e.message}")
                    attempt++
                    if (attempt <= 3) Thread.sleep(1000L * (1 shl attempt))
                }
            }
            file.delete()
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

        val out = conn.outputStream
        fun w(s: String) = out.write(s.toByteArray(Charsets.UTF_8))
        w("--$boundary\r\nContent-Disposition: form-data; name=\"chunk_index\"\r\n\r\n$index\r\n")
        w("--$boundary\r\nContent-Disposition: form-data; name=\"is_final\"\r\n\r\n${if (isFinal) "1" else "0"}\r\n")
        w("--$boundary\r\nContent-Disposition: form-data; name=\"chunk\"; ")
        w("filename=\"chunk_${index.toString().padStart(6,'0')}.mp4\"\r\nContent-Type: video/mp4\r\n\r\n")
        file.inputStream().use { it.copyTo(out) }
        w("\r\n--$boundary--\r\n")
        out.flush(); out.close()

        val code = conn.responseCode
        if (code !in 200..299) {
            val body = try { conn.errorStream?.bufferedReader()?.readText() } catch (_: Exception) { "" }
            throw Exception("HTTP $code: $body")
        }
        conn.disconnect()
    }

    // ── EventChannel helpers ──────────────────────────────────────────────────

    private fun emitScreenLoopStarted() {
        Log.d(TAG, "emitScreenLoopStarted — Dart may now call releaseVirtualDisplay + setScreenShareEnabled")
        eventSink?.success(mapOf("event" to "screenLoopStarted"))
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
            ).apply { description = "Active while session is being recorded"; setShowBadge(false) }
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle("Recording session")
                    .setContentText("Audio + screen recording in progress")
                    .setSmallIcon(android.R.drawable.ic_menu_camera)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setOngoing(true)
                    .build()
}