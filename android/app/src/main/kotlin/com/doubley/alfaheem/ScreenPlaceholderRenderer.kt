package com.doubley.alfaheem

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Sits between the frame source and the MediaRecorder's encoder surface.
 *
 * PLACEHOLDER MODE (default, from session start): draws a solid color into
 * the encoder surface on a timer. No MediaProjection involved.
 *
 * LIVE MODE (from the moment Share is granted): owns a stable SurfaceTexture
 * that the real VirtualDisplay targets. On each new frame, draws it into the
 * encoder surface AND forwards it to a live-frame sink (ElFaheemFrameCapturer)
 * so local recording and the live share see the identical content.
 *
 * The encoder-facing output surface changes every chunk (ping-pong recorder
 * swap) — call attachEncoderSurface() on every chunk boundary, exactly where
 * ScreenCaptureService used to do `virtualDisplay.surface = recorder.surface`.
 * The input side (placeholder timer, or the VirtualDisplay's target surface)
 * stays constant across chunk boundaries — only the output re-points.
 *
 * All EGL/GL work happens on a single dedicated GL thread — every public
 * method hops onto it via the Handler; none of this is safe to call from
 * arbitrary threads directly.
 *
 * The live share's readback (A6): the frame is drawn a second time into a
 * small offscreen framebuffer — scaled to [configureCapture]'s caps (short
 * side 720 "motion" / 1080 "detail", a pixel ceiling, a long-side cap), aspect
 * kept, flipped to top-left origin — and read with glReadPixels into ONE
 * reused direct buffer, only when a new screen frame arrived (or every
 * 500 ms on a static screen) and never faster than the share's fps. Nothing
 * is handed to the capturer before the first real frame, nor in placeholder
 * mode. With no encoder attached (share without a recording, audio-only
 * recording, a paused recording) the encoder pass is skipped entirely.
 */
class ScreenPlaceholderRenderer(
        private val onLiveFrameForCapturer: ((widthPx: Int, heightPx: Int, rgbaBytes: ByteBuffer) -> Unit)?,
) {
    companion object {
        private const val TAG = "ScreenPlaceholderRenderer"
        private const val FPS_PLACEHOLDER = 15
        /** D-110: the recording's frame rate (SegmentedRecorder encodes at it; a share is drawn into it at it). */
        const val RECORD_FPS = 30
        private const val DEFAULT_ROOM_LONG = 1280
        /** Placeholder mode: the clock repeats the picture only when no frame was drawn for this long. */
        private const val KEEPALIVE_GAP_NS = 45_000_000L
        // Placeholder color: dark slate, distinguishable from a real black
        // screen so it's obviously "not yet sharing" on playback.
        private const val PLACEHOLDER_R = 0.10f
        private const val PLACEHOLDER_G = 0.12f
        private const val PLACEHOLDER_B = 0.16f
        /** A static screen is re-sent this often, so the encoder can refine it. */
        private const val STATIC_RESEND_MS = 500L
        private const val LATCH_TIMEOUT_MS = 3_000L
    }

    private val thread = HandlerThread("ScreenPlaceholderRendererGL").also { it.start() }
    private val glHandler = Handler(thread.looper)

    // EGL
    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext = EGL14.EGL_NO_CONTEXT
    private var eglConfig: EGLConfig? = null
    private var outputSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var outputWidth = 0
    private var outputHeight = 0

    // Input (live mode): external OES texture fed by VirtualDisplay via SurfaceTexture.
    private var oesTextureId = 0
    private var inputSurfaceTexture: SurfaceTexture? = null

    /** Stable Surface the real VirtualDisplay targets once Share is granted. Valid after start(). */
    var inputSurface: Surface? = null
        private set

    @Volatile private var liveMode = false
    @Volatile private var running = false

    // No encoder surface (share-only, audio-only, paused): only the capture pass runs.
    @Volatile private var offscreen = false

    // Size of the VirtualDisplay's frames (= the SurfaceTexture's buffer size).
    private var inputWidth = 0
    private var inputHeight = 0

    // Live-share capture: scaled offscreen framebuffer + one reused readback buffer.
    @Volatile private var captureMaxLongSide = 1280
    // D-090: 0 = off (the long side alone decides, as before).
    @Volatile private var captureShortSide = 0
    @Volatile private var captureMaxPixels = 0
    @Volatile private var captureFps = 15
    private var captureFbo = 0
    private var captureTexture = 0
    private var captureWidth = 0
    private var captureHeight = 0
    private var captureBuffer: ByteBuffer? = null
    private var lastCaptureMs = 0L
    @Volatile private var newFrameSinceCapture = false
    private var flippedVertexBuffer: FloatBuffer? = null
    private var fitVertexBuffer: FloatBuffer? = null
    private var fitFor = ""
    private var capturedFrames = 0L

    // GL program handles used by the live textured-quad path (OES external texture).
    private var program = 0
    private var aPositionLoc = 0
    private var aTexCoordLoc = 0
    private var uTexMatrixLoc = 0
    private var vertexBuffer: FloatBuffer? = null
    private val texMatrix = FloatArray(16)
    private val identityMatrix = FloatArray(16).also { android.opengl.Matrix.setIdentityM(it, 0) }

    // Second program for the placeholder bitmap (plain GL_TEXTURE_2D, not OES).
    private var bitmapProgram = 0
    private var bmpPositionLoc = 0
    private var bmpTexCoordLoc = 0
    private var bmpTexMatrixLoc = 0
    private var placeholderTextureId = 0
    @Volatile private var hasPlaceholderImage = false
    private var placeholderAspect = 1f // width/height of the uploaded bitmap
    private var pendingBitmap: Bitmap? = null

    /**
     * Sets (or replaces) the placeholder image — call from Dart via a method
     * channel any time the session-info card should update (e.g. once at
     * session start; again if displayed info changes). Decode PNG bytes to
     * a Bitmap on the Dart/platform-channel thread before calling this;
     * upload itself happens on the GL thread. Safe to call before start()
     * finishes — the upload is queued and applied once GL is ready.
     */
    fun setPlaceholderBitmap(bitmap: Bitmap) {
        glHandler.post {
            if (!running) {
                pendingBitmap = bitmap
                return@post
            }
            uploadPlaceholderBitmap(bitmap)
        }
    }

    private fun uploadPlaceholderBitmap(bitmap: Bitmap) {
        if (!makeCurrentAny()) return
        if (placeholderTextureId == 0) {
            val tex = IntArray(1)
            GLES20.glGenTextures(1, tex, 0)
            placeholderTextureId = tex[0]
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, placeholderTextureId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        texW = -1 // a raw room frame re-specifies the texture next time
        placeholderAspect = bitmap.width.toFloat() / bitmap.height.toFloat()
        hasPlaceholderImage = true
        Log.d(TAG, "placeholder bitmap uploaded ${bitmap.width}x${bitmap.height}")
    }

    /** True/current-EGL-context helper for uploads that may race attachEncoderSurface. */
    private fun makeCurrentAny(): Boolean {
        // Uploading a texture just needs SOME current context/surface, not
        // necessarily the encoder's output surface — reuse output if it
        // exists yet, otherwise this will simply be retried on next draw
        // (uploadPlaceholderBitmap is safe to call again).
        if (outputSurface != EGL14.EGL_NO_SURFACE) return makeCurrentOutput()
        return false
    }


    fun start(width: Int, height: Int) {
        val latch = java.util.concurrent.CountDownLatch(1)
        glHandler.post {
            try {
                initEgl()
                inputWidth = width
                inputHeight = height
                initTexture(width, height)
                initProgram()
                running = true
            } catch (e: Exception) {
                Log.e(TAG, "start() failed: ${e.message}", e)
            } finally {
                latch.countDown()
            }
        }
        await(latch, "start")
    }

    /** Waits for a GL-thread task, but never forever (the thread may have quit: A21). */
    private fun await(latch: java.util.concurrent.CountDownLatch, what: String) {
        if (!latch.await(LATCH_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)) {
            Log.w(TAG, "$what: GL thread did not answer in $LATCH_TIMEOUT_MS ms")
        }
    }

    /**
     * The live share's capture size and rate: longer side at most [maxLongSide]
     * (aspect kept), at most [fps] frames per second. Also speeds the draw
     * clock up to [fps] while live.
     */
    fun configureCapture(maxLongSide: Int, fps: Int, shortSide: Int = 0, maxPixels: Int = 0) {
        captureMaxLongSide = maxLongSide.coerceIn(320, 3840)
        captureShortSide = shortSide
        captureMaxPixels = maxPixels
        captureFps = fps.coerceIn(1, 30)
        Log.d(TAG, "capture short≤${captureShortSide} px≤${captureMaxPixels} long≤${captureMaxLongSide}px @${captureFps}fps")
    }

    /**
     * The VirtualDisplay was resized (rotation, Android 14 single-app share):
     * the SurfaceTexture's buffer follows, and the capture size with it.
     */
    fun setInputSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        val latch = java.util.concurrent.CountDownLatch(1)
        glHandler.post {
            try {
                inputWidth = width
                inputHeight = height
                inputSurfaceTexture?.setDefaultBufferSize(width, height)
                Log.d(TAG, "input size ${width}x$height")
            } finally {
                latch.countDown()
            }
        }
        await(latch, "setInputSize")
    }

    /**
     * Call right before releasing the current chunk's MediaRecorder when
     * PAUSING (not stopping) — see ScreenCaptureService.kt's recordLoop(),
     * which deliberately skips calling attachEncoderSurface() again during
     * a pause (there's no new chunk to write into yet). Left unhandled,
     * that meant outputSurface stayed pointed at a Surface whose
     * MediaRecorder had just been released: eglMakeCurrent against it then
     * fails, makeCurrentOutput() returns false, and drawLiveFrame() silently
     * no-ops for the ENTIRE pause window — meaning onLiveFrameForCapturer
     * never fires and the live share students see freezes for as long as
     * recording stays paused, even though pausing the local recording was
     * never supposed to affect the live share at all.
     *
     * This re-points outputSurface at a persistent pbuffer sized to match
     * the current output resolution instead: eglMakeCurrent keeps
     * succeeding, the shared draw tick keeps running, and live frames keep
     * reaching onLiveFrameForCapturer uninterrupted — only the
     * MediaRecorder-side chunk file writing is what's actually paused.
     * attachEncoderSurface() on resume destroys this pbuffer and re-points
     * outputSurface at the fresh real chunk's surface, same as any other
     * chunk boundary.
     */
    fun detachEncoderSurfaceForPause() {
        val latch = java.util.concurrent.CountDownLatch(1)
        glHandler.post {
            try {
                if (outputSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, outputSurface)
                }
                // Nothing is drawn into it while paused: a tiny pbuffer keeps a
                // current context for the live share's capture pass.
                val attribs = intArrayOf(EGL14.EGL_WIDTH, 16, EGL14.EGL_HEIGHT, 16, EGL14.EGL_NONE)
                outputSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, attribs, 0)
                offscreen = true
                // outputWidth/outputHeight deliberately left unchanged —
                // dimensions must stay consistent for onLiveFrameForCapturer
                // (a resolution change mid-stream could disrupt the live
                // WebRTC track on viewers' side); only the destination
                // surface changes.
                scheduleNextTick()
            } catch (e: Exception) {
                Log.e(TAG, "detachEncoderSurfaceForPause failed: ${e.message}", e)
            } finally {
                latch.countDown()
            }
        }
        await(latch, "surface change")
    }

    /**
     * Audio-only recording (ScreenCaptureService's EXTRA_AUDIO_ONLY): there is
     * never an encoder surface, so the draw clock runs against an offscreen
     * pbuffer of the given size instead. Nothing of it is recorded; it only
     * keeps the live path (switchToLive → drawLiveFrame → onLiveFrameForCapturer)
     * working should the person share the screen during an audio recording.
     * Same mechanics as detachEncoderSurfaceForPause(), with the size set here
     * because no attachEncoderSurface() ever ran. Blocks until applied.
     */
    fun attachOffscreenOutput(width: Int, height: Int) {
        val latch = java.util.concurrent.CountDownLatch(1)
        glHandler.post {
            try {
                if (outputSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, outputSurface)
                }
                outputWidth = width
                outputHeight = height
                // Nothing is drawn into it (no encoder): a tiny pbuffer is
                // enough to keep a current context for the capture pass.
                val attribs = intArrayOf(EGL14.EGL_WIDTH, 16, EGL14.EGL_HEIGHT, 16, EGL14.EGL_NONE)
                outputSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, attribs, 0)
                offscreen = true
                scheduleNextTick()
            } catch (e: Exception) {
                Log.e(TAG, "attachOffscreenOutput failed: ${e.message}", e)
            } finally {
                latch.countDown()
            }
        }
        await(latch, "surface change")
    }

    /** Call on EVERY chunk boundary (first chunk + every ping-pong swap). Blocks until applied. */
    fun attachEncoderSurface(surface: Surface, width: Int, height: Int) {
        val latch = java.util.concurrent.CountDownLatch(1)
        glHandler.post {
            try {
                if (outputSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, outputSurface)
                }
                outputSurface = EGL14.eglCreateWindowSurface(
                        eglDisplay, eglConfig, surface, intArrayOf(EGL14.EGL_NONE), 0)
                outputWidth = width
                outputHeight = height
                offscreen = false
                pendingBitmap?.let { uploadPlaceholderBitmap(it); pendingBitmap = null }
                // Always (re)start the draw clock here, in both modes — it
                // drives placeholder AND live drawing now (see "Draw clock"
                // section below), not just placeholder.
                scheduleNextTick()
            } catch (e: Exception) {
                Log.e(TAG, "attachEncoderSurface failed: ${e.message}", e)
            } finally {
                latch.countDown()
            }
        }
        await(latch, "surface change")
    }

    /**
     * Flips to live mode: from now on, the steady draw clock draws whatever
     * is currently in the OES texture fed by inputSurface (the real
     * VirtualDisplay's target) instead of the placeholder, and forwards
     * each drawn frame to onLiveFrameForCapturer. Call AFTER creating the
     * real VirtualDisplay against inputSurface.
     */
    fun switchToLive() {
        glHandler.post {
            liveMode = true
            haveLiveFrame = false // no real frame drawn into the texture yet
            newFrameSinceCapture = false
            lastCaptureMs = 0L
            Log.d(TAG, "switched to LIVE mode")
            scheduleNextTick() // restart the clock under the new mode, in case it isn't already running
        }
    }

    /** Share turned off: the recording shows the placeholder again and nothing more reaches the capturer. */
    fun switchToPlaceholder() {
        glHandler.post {
            liveMode = false
            haveLiveFrame = false
            Log.d(TAG, "switched to PLACEHOLDER mode")
            scheduleNextTick()
        }
    }

    fun release() {
        running = false
        glHandler.post {
            try {
                if (captureFbo != 0) GLES20.glDeleteFramebuffers(1, intArrayOf(captureFbo), 0)
                if (captureTexture != 0) GLES20.glDeleteTextures(1, intArrayOf(captureTexture), 0)
                captureFbo = 0
                captureTexture = 0
                captureBuffer = null
                inputSurface?.release()
                inputSurfaceTexture?.release()
                if (placeholderTextureId != 0) {
                    GLES20.glDeleteTextures(1, intArrayOf(placeholderTextureId), 0)
                    placeholderTextureId = 0
                }
                if (outputSurface != EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, outputSurface)
                }
                if (eglContext != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglMakeCurrent(
                            eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                    EGL14.eglDestroyContext(eglDisplay, eglContext)
                }
                EGL14.eglTerminate(eglDisplay)
            } catch (e: Exception) {
                Log.w(TAG, "release() cleanup error: ${e.message}")
            }
        }
        thread.quitSafely()
    }

    // ── EGL / GL setup ──────────────────────────────────────────────────────

    private fun initEgl() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) throw RuntimeException("eglGetDisplay failed")
        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
            throw RuntimeException("eglInitialize failed")
        }
        val attribs = intArrayOf(
                EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, attribs, 0, configs, 0, 1, numConfigs, 0)) {
            throw RuntimeException("eglChooseConfig failed")
        }
        eglConfig = configs[0]
        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
        if (eglContext == EGL14.EGL_NO_CONTEXT) throw RuntimeException("eglCreateContext failed")
    }

    private fun initTexture(width: Int, height: Int) {
        val tex = IntArray(1)
        GLES20.glGenTextures(1, tex, 0)
        oesTextureId = tex[0]
        // SurfaceTexture requires a current EGL context to bind — use a tiny
        // 1x1 pbuffer surface transiently just to make the context current.
        val pbufferAttribs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
        val pbuffer = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, pbufferAttribs, 0)
        EGL14.eglMakeCurrent(eglDisplay, pbuffer, pbuffer, eglContext)
        inputSurfaceTexture = SurfaceTexture(oesTextureId).apply {
            // Without this, the consumer side defaults to a 1x1 buffer,
            // which can silently break the handshake with a producer
            // (the VirtualDisplay) that's writing much larger frames.
            setDefaultBufferSize(width, height)
            setOnFrameAvailableListener({ onFrameAvailable() }, glHandler)
        }
        inputSurface = Surface(inputSurfaceTexture)
        EGL14.eglDestroySurface(eglDisplay, pbuffer)
    }

    private fun initProgram() {
        val vertexSrc = """
            attribute vec4 aPosition;
            attribute vec4 aTexCoord;
            uniform mat4 uTexMatrix;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = (uTexMatrix * aTexCoord).xy;
            }
        """.trimIndent()
        val fragmentSrc = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTexCoord;
            uniform samplerExternalOES sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """.trimIndent()
        program = linkProgram(vertexSrc, fragmentSrc)
        aPositionLoc = GLES20.glGetAttribLocation(program, "aPosition")
        aTexCoordLoc = GLES20.glGetAttribLocation(program, "aTexCoord")
        uTexMatrixLoc = GLES20.glGetUniformLocation(program, "uTexMatrix")

        // Second program: identical vertex stage, but a plain (non-OES)
        // sampler2D fragment stage for the placeholder bitmap texture.
        val bitmapFragmentSrc = """
            precision mediump float;
            varying vec2 vTexCoord;
            uniform sampler2D sTexture;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """.trimIndent()
        bitmapProgram = linkProgram(vertexSrc, bitmapFragmentSrc)
        bmpPositionLoc = GLES20.glGetAttribLocation(bitmapProgram, "aPosition")
        bmpTexCoordLoc = GLES20.glGetAttribLocation(bitmapProgram, "aTexCoord")
        bmpTexMatrixLoc = GLES20.glGetUniformLocation(bitmapProgram, "uTexMatrix")

        // Full-screen quad: x, y, u, v
        val verts = floatArrayOf(
                -1f, -1f, 0f, 0f,
                1f, -1f, 1f, 0f,
                -1f, 1f, 0f, 1f,
                1f, 1f, 1f, 1f,
        )
        vertexBuffer = floatBuffer(verts)
        // Same quad upside down: drawn into the capture framebuffer, glReadPixels
        // (bottom-left origin) then returns the rows top-down, as the capturer expects.
        flippedVertexBuffer = floatBuffer(floatArrayOf(
                -1f, 1f, 0f, 0f,
                1f, 1f, 1f, 0f,
                -1f, -1f, 0f, 1f,
                1f, -1f, 1f, 1f,
        ))
    }

    private fun floatBuffer(values: FloatArray): FloatBuffer =
            ByteBuffer.allocateDirect(values.size * 4)
                    .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(values); position(0) }

    private fun linkProgram(vertexSrc: String, fragmentSrc: String): Int {
        val vs = compileShader(GLES20.GL_VERTEX_SHADER, vertexSrc)
        val fs = compileShader(GLES20.GL_FRAGMENT_SHADER, fragmentSrc)
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, vs)
        GLES20.glAttachShader(p, fs)
        GLES20.glLinkProgram(p)
        val status = IntArray(1)
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetProgramInfoLog(p)
            GLES20.glDeleteProgram(p)
            throw RuntimeException("Program link failed: $log")
        }
        return p
    }

    private fun compileShader(type: Int, src: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, src)
        GLES20.glCompileShader(s)
        val status = IntArray(1)
        GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] == 0) {
            val log = GLES20.glGetShaderInfoLog(s)
            GLES20.glDeleteShader(s)
            throw RuntimeException("Shader compile failed: $log")
        }
        return s
    }

    // ── Placeholder path ────────────────────────────────────────────────────

    // ── Draw clock ──────────────────────────────────────────────────────────
    //
    // ONE steady-rate draw loop drives BOTH modes — this replaced an earlier
    // design where live mode was driven entirely by onFrameAvailable()
    // (i.e., by the VirtualDisplay actually producing new frames). That
    // works fine when the screen is visibly changing, but Android's
    // VirtualDisplay/SurfaceTexture only fires new frames on actual content
    // changes — a static screen (very normal during a real lesson: reading,
    // pausing, etc.) produced ZERO frames for whole chunk windows, and
    // MediaRecorder.stop() failed with -1007 (no video samples ever
    // written) for that chunk. Now onFrameAvailable() only keeps the OES
    // texture up to date; the steady clock re-draws whatever's currently in
    // that texture (fresh or repeated) every tick, in both modes.
    //
    // Bumped every time a new draw chain starts (attachEncoderSurface on
    // every chunk boundary, switchToLive, or switchToPlaceholder). A
    // running chain checks its captured generation against the current one
    // on each tick and stops silently if it's stale — without this, every
    // chunk boundary spawned an ADDITIONAL concurrent recursive postDelayed
    // chain that never stopped, so after N chunks there were N chains all
    // fighting over the same outputSurface/EGL state on one thread. That
    // contention was very likely why most chunks' MediaRecorder.stop()
    // failed with -1007 before this fix, too.
    private var drawGeneration = 0
    @Volatile private var haveLiveFrame = false

    private fun scheduleNextTick() {
        val myGeneration = ++drawGeneration
        scheduleNextTickInner(myGeneration)
    }

    /**
     * The clock's period. Live (a share): the recording's [RECORD_FPS] while an encoder is attached (the share's own
     * capture pass is throttled separately to [captureFps]), else the share's rate. Placeholder: [FPS_PLACEHOLDER] —
     * only a keep-alive while room frames are pushed ([pushRoomBitmap] draws each one itself, D-110).
     */
    private fun tickPeriodMs(): Long {
        val fps = if (liveMode) {
            if (offscreen) maxOf(FPS_PLACEHOLDER, captureFps) else maxOf(RECORD_FPS, captureFps)
        } else FPS_PLACEHOLDER
        return 1000L / fps
    }

    private var nextTickAt = 0L

    private fun scheduleNextTickInner(myGeneration: Int) {
        // Deadline based (D-110): the draw's own time no longer stretches the period (a 33 ms clock that drew for
        // 8 ms used to tick every 41 ms).
        val now = android.os.SystemClock.uptimeMillis()
        val period = tickPeriodMs()
        nextTickAt = if (nextTickAt + period <= now || nextTickAt > now + period) now + period else nextTickAt + period
        glHandler.postAtTime({
            if (!running || outputSurface == EGL14.EGL_NO_SURFACE) return@postAtTime
            if (myGeneration != drawGeneration) return@postAtTime // a newer chain took over
            // try/catch is load-bearing, not defensive decoration: this
            // runnable reschedules itself on the line AFTER the draw call,
            // so an uncaught exception from drawLiveFrame()/
            // drawPlaceholderFrame() (e.g. eglSwapBuffers against a surface
            // whose underlying MediaRecorder was just released) previously
            // killed the entire recurring chain permanently — no more
            // ticks, ever, for BOTH the local recording AND the live share
            // (onLiveFrameForCapturer runs on this same chain). One bad
            // frame must never be able to do that.
            try {
                if (liveMode) {
                    drawLiveFrame()
                } else if (System.nanoTime() - lastSwapNs >= KEEPALIVE_GAP_NS) {
                    // Pushed room frames draw themselves; the clock only repeats the picture when they stop
                    // (app in the background, Dart frames at their own pace).
                    drawPlaceholderFrame()
                }
            } catch (e: Exception) {
                Log.e(TAG, "draw tick failed, continuing: ${e.message}", e)
            }
            scheduleNextTickInner(myGeneration)
        }, nextTickAt)
    }

    // Under the GL thread only.
    private var lastStampNs = 0L
    @Volatile private var lastSwapNs = 0L

    /**
     * Hands the drawn frame to the encoder stamped with the monotonic clock (D-135): the frame's time in the
     * recording is the moment it was captured ([stampNs], default: now), on the same clock as the recorder's audio —
     * real-time motion, A/V in sync. Stamps never go backwards (an encoder input must only move forward).
     */
    private fun swapToEncoder(stampNs: Long = System.nanoTime()) {
        val stamp = if (stampNs <= lastStampNs) lastStampNs + 1_000_000L else stampNs
        lastStampNs = stamp
        EGLExt.eglPresentationTimeANDROID(eglDisplay, outputSurface, stamp)
        EGL14.eglSwapBuffers(eglDisplay, outputSurface)
        lastSwapNs = System.nanoTime()
    }

    /** True while a room frame would reach an encoder (recording, not paused, no share): [RoomFrameGrabber]. */
    val wantsRoomFrames: Boolean get() = running && !liveMode && !offscreen

    /** The encoder's longer side (0 before one is attached): the room frames are copied at most this large. */
    val encoderLongSide: Int get() = if (offscreen) DEFAULT_ROOM_LONG else maxOf(outputWidth, outputHeight)

    /**
     * D-110: a room frame copied natively ([RoomFrameGrabber], PixelCopy of Flutter's surface): uploaded and drawn
     * into the encoder at once, stamped with its capture time. [done] runs on the GL thread when the bitmap may be
     * reused. A share or a pause in the meantime: nothing is drawn.
     */
    fun pushRoomBitmap(bitmap: Bitmap, captureNs: Long, done: () -> Unit) {
        glHandler.post {
            try {
                if (wantsRoomFrames && !bitmap.isRecycled && makeCurrentOutput()) {
                    uploadRoomBitmap(bitmap)
                    drawPlaceholderContents()
                    swapToEncoder(captureNs)
                }
            } catch (e: Exception) {
                Log.w(TAG, "room frame dropped: ${e.message}")
            } finally {
                done()
            }
        }
    }

    private fun uploadRoomBitmap(bitmap: Bitmap) {
        if (placeholderTextureId == 0) {
            val tex = IntArray(1)
            GLES20.glGenTextures(1, tex, 0)
            placeholderTextureId = tex[0]
            texW = -1
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, placeholderTextureId)
        if (bitmap.width != texW || bitmap.height != texH) {
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
            texW = bitmap.width
            texH = bitmap.height
        } else {
            GLUtils.texSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, bitmap)
        }
        synchronized(frameLock) { frameDirty = false } // a Dart frame queued before is older than this one
        placeholderAspect = bitmap.width.toFloat() / bitmap.height.toFloat()
        hasPlaceholderImage = true
    }

    // ── Live room frames (D-135) ────────────────────────────────────────────
    //
    // Before a share, the recording shows the room as Dart sees it. It used to arrive as a PNG twice a second
    // (setPlaceholderBitmap): the camera in the recording moved in ~2 fps jumps — what the owner saw as "slow
    // motion". Dart now sends raw RGBA frames ~12 times a second; the latest one is copied into ONE reused direct
    // buffer (any thread) and uploaded to the placeholder texture by the next draw tick (GL thread).
    private val frameLock = Any()
    private var frameBuf: ByteBuffer? = null
    private var frameW = 0
    private var frameH = 0
    private var frameDirty = false
    private var texW = -1
    private var texH = -1

    /** The latest room frame, [rgba] = width × height × 4 bytes, rows top-down (Flutter's rawRgba). */
    fun setPlaceholderFrame(rgba: ByteArray, width: Int, height: Int) {
        val n = width * height * 4
        if (width <= 0 || height <= 0 || rgba.size < n) return
        synchronized(frameLock) {
            var b = frameBuf
            if (b == null || b.capacity() < n) b = ByteBuffer.allocateDirect(n).order(ByteOrder.nativeOrder())
            b!!.clear()
            b.put(rgba, 0, n)
            b.flip()
            frameBuf = b
            frameW = width
            frameH = height
            frameDirty = true
        }
    }

    /** GL thread, a context current: the pending room frame into the placeholder texture. */
    private fun uploadPendingFrame() {
        synchronized(frameLock) {
            if (!frameDirty) return
            val b = frameBuf ?: return
            if (placeholderTextureId == 0) {
                val tex = IntArray(1)
                GLES20.glGenTextures(1, tex, 0)
                placeholderTextureId = tex[0]
                texW = -1
            }
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, placeholderTextureId)
            GLES20.glPixelStorei(GLES20.GL_UNPACK_ALIGNMENT, 4)
            b.position(0)
            if (frameW != texW || frameH != texH) {
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
                GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, frameW, frameH, 0,
                        GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, b)
                texW = frameW
                texH = frameH
            } else {
                GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, frameW, frameH,
                        GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, b)
            }
            placeholderAspect = frameW.toFloat() / frameH.toFloat()
            hasPlaceholderImage = true
            frameDirty = false
        }
    }

    private fun drawPlaceholderFrame() {
        if (offscreen) return // nothing consumes it
        if (!makeCurrentOutput()) return
        uploadPendingFrame()
        drawPlaceholderContents()
        swapToEncoder()
    }

    private fun drawPlaceholderContents() {
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(PLACEHOLDER_R, PLACEHOLDER_G, PLACEHOLDER_B, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (hasPlaceholderImage && placeholderTextureId != 0) {
            drawPlaceholderBitmapAspectFit()
        }
    }

    /**
     * Draws the placeholder bitmap centered, scaled to fit inside the output
     * frame while preserving its own aspect ratio (letterboxed on the solid
     * background already cleared above) — the captured session-info widget
     * keeps its real proportions instead of being stretched to fill a
     * differently-shaped video frame.
     */
    private fun drawPlaceholderBitmapAspectFit() {
        val outputAspect = outputWidth.toFloat() / outputHeight.toFloat()
        var scaleX = 1f
        var scaleY = 1f
        if (placeholderAspect > outputAspect) {
            // Bitmap relatively wider than the frame: fit width, letterbox top/bottom.
            scaleY = outputAspect / placeholderAspect
        } else {
            // Bitmap relatively taller than the frame: fit height, pillarbox left/right.
            scaleX = placeholderAspect / outputAspect
        }
        val verts = floatArrayOf(
                -scaleX, -scaleY, 0f, 1f, // note: V flipped (bitmap origin is top-left, GL is bottom-left)
                scaleX, -scaleY, 1f, 1f,
                -scaleX, scaleY, 0f, 0f,
                scaleX, scaleY, 1f, 0f,
        )
        val fitBuffer = ByteBuffer.allocateDirect(verts.size * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(verts); position(0) }

        GLES20.glUseProgram(bitmapProgram)
        fitBuffer.position(0)
        GLES20.glVertexAttribPointer(bmpPositionLoc, 2, GLES20.GL_FLOAT, false, 16, fitBuffer)
        GLES20.glEnableVertexAttribArray(bmpPositionLoc)
        fitBuffer.position(2)
        GLES20.glVertexAttribPointer(bmpTexCoordLoc, 2, GLES20.GL_FLOAT, false, 16, fitBuffer)
        GLES20.glEnableVertexAttribArray(bmpTexCoordLoc)
        GLES20.glUniformMatrix4fv(bmpTexMatrixLoc, 1, false, identityMatrix, 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, placeholderTextureId)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    // ── Live path ────────────────────────────────────────────────────────────

    /**
     * SurfaceTexture.OnFrameAvailableListener callback — fires only when the
     * VirtualDisplay actually produces a new frame (i.e. the screen visibly
     * changed). Deliberately lightweight: just consumes the buffer so the
     * producer never blocks. The actual draw/encode/readback work happens
     * on the steady clock (scheduleNextTickInner → drawLiveFrame), which
     * redraws whatever's currently bound to the texture regardless of
     * whether THIS tick brought a new frame or not.
     */
    private fun onFrameAvailable() {
        try {
            inputSurfaceTexture?.updateTexImage()
            haveLiveFrame = true
            newFrameSinceCapture = true
        } catch (_: Exception) {}
    }

    private fun drawLiveFrame() {
        if (!makeCurrentOutput()) return
        if (haveLiveFrame) inputSurfaceTexture?.getTransformMatrix(texMatrix)

        // 1. The live share: a scaled, flipped copy into the capture framebuffer.
        if (haveLiveFrame) onLiveFrameForCapturer?.let { captureForShare(it) }

        // 2. The recording's encoder (skipped without one).
        if (offscreen) return
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        // No real frame yet (right after switchToLive): the black clear still
        // goes to the encoder, so it keeps getting frames every tick.
        if (haveLiveFrame) drawInputQuad(fitVertexBuffer())
        swapToEncoder()
    }

    /** The OES input texture over [verts] (x, y, u, v) into whatever framebuffer is bound. */
    private fun drawInputQuad(verts: FloatBuffer) {
        GLES20.glUseProgram(program)
        verts.position(0)
        GLES20.glVertexAttribPointer(aPositionLoc, 2, GLES20.GL_FLOAT, false, 16, verts)
        GLES20.glEnableVertexAttribArray(aPositionLoc)
        verts.position(2)
        GLES20.glVertexAttribPointer(aTexCoordLoc, 2, GLES20.GL_FLOAT, false, 16, verts)
        GLES20.glEnableVertexAttribArray(aTexCoordLoc)
        GLES20.glUniformMatrix4fv(uTexMatrixLoc, 1, false, texMatrix, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    /**
     * The screen aspect-fitted into the encoder frame (a landscape screen after
     * a rotation is letterboxed into the portrait recording, not stretched).
     */
    private fun fitVertexBuffer(): FloatBuffer {
        val key = "${inputWidth}x$inputHeight>${outputWidth}x$outputHeight"
        fitVertexBuffer?.let { if (key == fitFor) return it }
        var sx = 1f
        var sy = 1f
        if (inputWidth > 0 && inputHeight > 0 && outputWidth > 0 && outputHeight > 0) {
            val inAspect = inputWidth.toFloat() / inputHeight
            val outAspect = outputWidth.toFloat() / outputHeight
            if (inAspect > outAspect) sy = outAspect / inAspect else sx = inAspect / outAspect
        }
        val buf = floatBuffer(floatArrayOf(
                -sx, -sy, 0f, 0f,
                sx, -sy, 1f, 0f,
                -sx, sy, 0f, 1f,
                sx, sy, 1f, 1f,
        ))
        fitVertexBuffer = buf
        fitFor = key
        return buf
    }

    private fun captureForShare(sink: (Int, Int, ByteBuffer) -> Unit) {
        val now = android.os.SystemClock.uptimeMillis()
        val minGap = 1000L / captureFps - 2
        if (now - lastCaptureMs < minGap) return
        if (!newFrameSinceCapture && now - lastCaptureMs < STATIC_RESEND_MS) return
        if (!ensureCaptureTarget()) return

        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, captureFbo)
        GLES20.glViewport(0, 0, captureWidth, captureHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        drawInputQuad(flippedVertexBuffer!!)
        val buf = captureBuffer!!
        buf.position(0)
        GLES20.glReadPixels(0, 0, captureWidth, captureHeight, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        buf.position(0)
        lastCaptureMs = now
        newFrameSinceCapture = false
        // The capturer converts synchronously (RGBA → I420 into its own
        // buffers), so this one buffer is free again when the sink returns.
        sink(captureWidth, captureHeight, buf)
        if (++capturedFrames % 300 == 0L) {
            Log.d(TAG, "share: $capturedFrames frames read back at ${captureWidth}x$captureHeight")
        }
    }

    /** (Re)creates the capture framebuffer + readback buffer for the current input size. */
    private fun ensureCaptureTarget(): Boolean {
        if (inputWidth <= 0 || inputHeight <= 0) return false
        val (w, h) = scaledSize(inputWidth, inputHeight, captureMaxLongSide, captureShortSide, captureMaxPixels)
        if (captureFbo != 0 && w == captureWidth && h == captureHeight) return true
        if (captureTexture == 0) {
            val t = IntArray(1)
            GLES20.glGenTextures(1, t, 0)
            captureTexture = t[0]
        }
        if (captureFbo == 0) {
            val f = IntArray(1)
            GLES20.glGenFramebuffers(1, f, 0)
            captureFbo = f[0]
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, captureTexture)
        GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, GLES20.GL_RGBA, w, h, 0,
                GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, null)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, captureFbo)
        GLES20.glFramebufferTexture2D(GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0,
                GLES20.GL_TEXTURE_2D, captureTexture, 0)
        val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        if (status != GLES20.GL_FRAMEBUFFER_COMPLETE) {
            Log.e(TAG, "capture framebuffer incomplete: $status")
            return false
        }
        captureWidth = w
        captureHeight = h
        captureBuffer = ByteBuffer.allocateDirect(w * h * 4).order(ByteOrder.nativeOrder())
        Log.d(TAG, "share capture target ${w}x$h (input ${inputWidth}x$inputHeight, max $captureMaxLongSide)")
        return true
    }

    /**
     * [w]x[h] scaled so the longer side is at most [maxLong], the shorter at most [shortSide] and the area at most
     * [maxPixels] (0 = that cap is off); aspect kept, never upscaled, both even. Same rule as SharePreset.sizeFor
     * (D-090: a 1440x3120 phone shares 1080x2340 Detail / 720x1560 Motion, not 886x1920 / 590x1280).
     */
    private fun scaledSize(w: Int, h: Int, maxLong: Int, shortSide: Int = 0, maxPixels: Int = 0): Pair<Int, Int> {
        val longer = maxOf(w, h)
        val shorter = minOf(w, h)
        var scale = if (longer > maxLong) maxLong.toDouble() / longer else 1.0
        if (shortSide > 0 && shorter > shortSide) scale = minOf(scale, shortSide.toDouble() / shorter)
        if (maxPixels > 0 && w.toLong() * h > maxPixels) scale = minOf(scale, Math.sqrt(maxPixels.toDouble() / (w.toDouble() * h)))
        fun even(v: Double) = (Math.round(v).toInt() and 1.inv()).coerceAtLeast(2)
        return even(w * scale) to even(h * scale)
    }

    private fun makeCurrentOutput(): Boolean {
        if (outputSurface == EGL14.EGL_NO_SURFACE) return false
        return EGL14.eglMakeCurrent(eglDisplay, outputSurface, outputSurface, eglContext)
    }
}