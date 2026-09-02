package com.example.flutter_education_app

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLDisplay
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
 */
class ScreenPlaceholderRenderer(
        private val onLiveFrameForCapturer: ((widthPx: Int, heightPx: Int, rgbaBytes: ByteBuffer) -> Unit)?,
) {
    companion object {
        private const val TAG = "ScreenPlaceholderRenderer"
        private const val FPS_PLACEHOLDER = 15
        // Placeholder color: dark slate, distinguishable from a real black
        // screen so it's obviously "not yet sharing" on playback.
        private const val PLACEHOLDER_R = 0.10f
        private const val PLACEHOLDER_G = 0.12f
        private const val PLACEHOLDER_B = 0.16f
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
                initTexture(width, height)
                initProgram()
                running = true
            } catch (e: Exception) {
                Log.e(TAG, "start() failed: ${e.message}", e)
            } finally {
                latch.countDown()
            }
        }
        latch.await()
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
                val attribs = intArrayOf(
                        EGL14.EGL_WIDTH, outputWidth, EGL14.EGL_HEIGHT, outputHeight,
                        EGL14.EGL_NONE)
                outputSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglConfig, attribs, 0)
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
        latch.await()
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
        latch.await()
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
            Log.d(TAG, "switched to LIVE mode")
            scheduleNextTick() // restart the clock under the new mode, in case it isn't already running
        }
    }

    /** Optional: revert to placeholder (e.g. if you want recording to show a
     *  placeholder again after Share is turned off, rather than a frozen
     *  last frame). Not called by default — see ScreenCaptureService wiring. */
    fun switchToPlaceholder() {
        glHandler.post {
            liveMode = false
            Log.d(TAG, "switched to PLACEHOLDER mode")
            scheduleNextTick()
        }
    }

    fun release() {
        running = false
        glHandler.post {
            try {
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
        vertexBuffer = ByteBuffer.allocateDirect(verts.size * 4)
                .order(ByteOrder.nativeOrder()).asFloatBuffer().apply { put(verts); position(0) }
    }

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

    private fun scheduleNextTickInner(myGeneration: Int) {
        glHandler.postDelayed({
            if (!running || outputSurface == EGL14.EGL_NO_SURFACE) return@postDelayed
            if (myGeneration != drawGeneration) return@postDelayed // a newer chain took over
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
                if (liveMode) drawLiveFrame() else drawPlaceholderFrame()
            } catch (e: Exception) {
                Log.e(TAG, "draw tick failed, continuing: ${e.message}", e)
            }
            scheduleNextTickInner(myGeneration)
        }, 1000L / FPS_PLACEHOLDER)
    }

    private fun drawPlaceholderFrame() {
        if (!makeCurrentOutput()) return
        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(PLACEHOLDER_R, PLACEHOLDER_G, PLACEHOLDER_B, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (hasPlaceholderImage && placeholderTextureId != 0) {
            drawPlaceholderBitmapAspectFit()
        }

        EGL14.eglSwapBuffers(eglDisplay, outputSurface)
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
        } catch (_: Exception) {}
    }

    private fun drawLiveFrame() {
        if (!makeCurrentOutput()) return

        GLES20.glViewport(0, 0, outputWidth, outputHeight)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        if (haveLiveFrame) {
            // Real content available — draw the OES texture (fresh or
            // repeated from the last onFrameAvailable(), doesn't matter).
            inputSurfaceTexture?.getTransformMatrix(texMatrix)
            GLES20.glUseProgram(program)
            vertexBuffer!!.position(0)
            GLES20.glVertexAttribPointer(aPositionLoc, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            GLES20.glEnableVertexAttribArray(aPositionLoc)
            vertexBuffer!!.position(2)
            GLES20.glVertexAttribPointer(aTexCoordLoc, 2, GLES20.GL_FLOAT, false, 16, vertexBuffer)
            GLES20.glEnableVertexAttribArray(aTexCoordLoc)
            GLES20.glUniformMatrix4fv(uTexMatrixLoc, 1, false, texMatrix, 0)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        }
        // else: no real frame has arrived yet (brief window right after
        // switchToLive(), before the first actual screen change) — still
        // draw+swap+readback the plain black clear above instead of doing
        // nothing, so the encoder keeps getting frames every tick
        // regardless. Once onFrameAvailable() fires, subsequent ticks draw
        // the real texture as above.

        // CRITICAL ORDERING: glReadPixels MUST happen before eglSwapBuffers.
        // Swapping makes the buffer we just drew into the FRONT buffer and
        // hands back an undefined (often white, on this Adreno driver) back
        // buffer for the next frame — reading pixels after swap reads that
        // undefined buffer, not the frame we actually rendered. This was
        // the cause of the live share showing a solid white screen.
        //
        // NOTE: reading pixels back via glReadPixels every frame is real CPU
        // cost at 15fps; this is the simplest-to-verify approach for a first
        // working version, not the most efficient one. If frame rate or CPU
        // usage becomes a problem, this is the place to optimize (e.g. a
        // second EGL output surface backed by the capturer's own
        // SurfaceTexture, avoiding the CPU round-trip entirely).
        onLiveFrameForCapturer?.let { sink ->
            val buf = ByteBuffer.allocateDirect(outputWidth * outputHeight * 4)
                    .order(ByteOrder.nativeOrder())
            GLES20.glReadPixels(
                    0, 0, outputWidth, outputHeight,
                    GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, buf)
            buf.position(0)
            sink(outputWidth, outputHeight, buf)
        }

        EGL14.eglSwapBuffers(eglDisplay, outputSurface)
    }

    private fun makeCurrentOutput(): Boolean {
        if (outputSurface == EGL14.EGL_NO_SURFACE) return false
        return EGL14.eglMakeCurrent(eglDisplay, outputSurface, outputSurface, eglContext)
    }
}