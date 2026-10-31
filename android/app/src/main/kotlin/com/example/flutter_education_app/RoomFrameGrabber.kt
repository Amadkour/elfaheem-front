package com.example.flutter_education_app

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Log
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import java.lang.ref.WeakReference

/**
 * D-110: the room's picture for the device recording, copied natively from Flutter's own surface at 30 fps.
 *
 * Before a share the Android recording draws the room as the teacher sees it. Until now Dart sent it
 * (RepaintBoundary.toImage → rawRgba → platform channel → GL upload, D-103): ~55 ms per frame on the S24, so the
 * room reached the encoder ~9 times a second and the camera moved in visible jumps ("slow motion"). Here the
 * already-composited frame (camera texture included) is read from the FlutterSurfaceView with PixelCopy — scaled
 * to the recording's size by the GPU on the way, no Dart work, no channel copy — straight into one reused Bitmap
 * that ScreenPlaceholderRenderer uploads and hands to the encoder at once, stamped with the copy's time.
 *
 * One copy is in flight at a time and the next starts at most every 1/[FPS] s after the previous one STARTED
 * (deadline based, so the rate does not sag by the copy's own time). A copy that fails (the app in the background,
 * the surface gone) is skipped; the renderer's keep-alive clock repeats the last picture meanwhile. Dart tells the
 * grabber where the room is on screen ([update], physical pixels) and when it is not visible (minimized: inactive).
 *
 * [start] answers through [onProbe] whether a first copy worked; when it does not (a Flutter build whose surface
 * PixelCopy cannot read), Dart keeps its own frames (live_frame_pacing.dart).
 */
class RoomFrameGrabber(activity: Activity) {
    companion object {
        private const val TAG = "RoomFrameGrabber"
        const val FPS = 30
        private const val PERIOD_MS = 1000L / FPS
        /** Nothing to do (inactive, no encoder, no surface): look again this often. */
        private const val IDLE_MS = 100L
        private const val FLUTTER_SURFACE_VIEW = "io.flutter.embedding.android.FlutterSurfaceView"
    }

    private val activityRef = WeakReference(activity)
    private val thread = HandlerThread("RoomFrameGrabber").also { it.start() }
    private val handler = Handler(thread.looper)

    @Volatile private var srcRect: Rect? = null
    @Volatile private var active = true
    @Volatile private var running = false
    @Volatile private var maxLongSide = 1280
    private var viewRef: WeakReference<SurfaceView>? = null
    private var bitmap: Bitmap? = null
    private var probe: ((Boolean) -> Unit)? = null
    private var generation = 0
    private var copied = 0L
    private var failed = 0L
    private var statsAt = 0L

    /**
     * Starts the loop. Call on the main thread (the view tree is walked here). [onProbe] gets the first copy's
     * outcome, on the grabber's thread.
     */
    fun start(rect: Rect, maxLong: Int, onProbe: (Boolean) -> Unit) {
        val view = findFlutterSurface()
        handler.post {
            viewRef = view?.let { WeakReference(it) }
            srcRect = rect
            maxLongSide = maxLong.coerceIn(320, 3840)
            active = true
            running = true
            probe = onProbe
            val gen = ++generation
            loop(gen)
        }
    }

    /** Where the room is on screen (physical px of the Flutter view) and whether it is visible at all. */
    fun update(rect: Rect?, isActive: Boolean) {
        if (rect != null && !rect.isEmpty) srcRect = rect
        active = isActive
    }

    fun stop() {
        handler.post {
            running = false
            generation++
            probe?.invoke(false)
            probe = null
            Log.d(TAG, "stopped (copied=$copied failed=$failed)")
        }
    }

    fun release() {
        stop()
        handler.post {
            bitmap?.recycle()
            bitmap = null
            thread.quitSafely()
        }
    }

    private fun loop(gen: Int) {
        if (!running || gen != generation) return
        val startedAt = SystemClock.uptimeMillis()
        val renderer = ScreenCaptureService.placeholderRenderer
        val view = if (active || probe != null) surfaceView() else null
        val rect = srcRect?.let { clip(it, view) }
        if (view == null || rect == null || renderer == null || (probe == null && !renderer.wantsRoomFrames) ||
                !view.holder.surface.isValid) {
            if (probe != null && view == null) finishProbe(false)
            handler.postDelayed({ loop(gen) }, IDLE_MS)
            return
        }
        val bmp = bitmapFor(rect)
        val captureNs = System.nanoTime()
        try {
            PixelCopy.request(view, rect, bmp, { res ->
                if (gen != generation) return@request
                if (res == PixelCopy.SUCCESS) {
                    copied++
                    finishProbe(true)
                    renderer.pushRoomBitmap(bmp, captureNs) {
                        handler.post { next(gen, startedAt) }
                    }
                } else {
                    failed++
                    if (probe != null) finishProbe(false)
                    handler.postDelayed({ loop(gen) }, IDLE_MS)
                }
                logStats()
            }, handler)
        } catch (e: Exception) {
            failed++
            Log.w(TAG, "copy request failed: ${e.message}")
            if (probe != null) finishProbe(false)
            handler.postDelayed({ loop(gen) }, IDLE_MS)
        }
    }

    private fun next(gen: Int, startedAt: Long) {
        val due = startedAt + PERIOD_MS
        val now = SystemClock.uptimeMillis()
        if (due <= now) loop(gen) else handler.postAtTime({ loop(gen) }, due)
    }

    private fun finishProbe(ok: Boolean) {
        val p = probe ?: return
        probe = null
        Log.d(TAG, "probe ${if (ok) "ok" else "FAILED"} — ${if (ok) "native room frames at $FPS fps" else "Dart frames stay"}")
        if (!ok) {
            running = false
            generation++
        }
        p(ok)
    }

    private fun logStats() {
        val now = SystemClock.uptimeMillis()
        if (statsAt == 0L) statsAt = now
        if (now - statsAt >= 10_000L) {
            Log.d(TAG, "copied=$copied failed=$failed (${bitmap?.width}x${bitmap?.height})")
            statsAt = now
        }
    }

    /** The source rectangle inside the view, or null when nothing of it is on the view. */
    private fun clip(r: Rect, view: SurfaceView?): Rect? {
        val v = view ?: return null
        val out = Rect(r)
        if (!out.intersect(0, 0, v.width, v.height) || out.width() < 16 || out.height() < 16) return null
        return out
    }

    /** One reused ARGB bitmap at the source's aspect, its longer side at most [maxLongSide] (even sizes). */
    private fun bitmapFor(r: Rect): Bitmap {
        val longer = maxOf(r.width(), r.height())
        val scale = if (longer > maxLongSide) maxLongSide.toDouble() / longer else 1.0
        fun even(v: Double) = (Math.round(v).toInt() and 1.inv()).coerceAtLeast(16)
        val w = even(r.width() * scale)
        val h = even(r.height() * scale)
        val b = bitmap
        if (b != null && b.width == w && b.height == h && !b.isRecycled) return b
        // The previous bitmap may still be read by the GL thread for this frame: let the GC take it.
        return Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also {
            bitmap = it
            Log.d(TAG, "frames ${w}x$h from ${r.width()}x${r.height()}")
        }
    }

    private fun surfaceView(): SurfaceView? = viewRef?.get()?.takeIf { it.isAttachedToWindow }

    /** Main thread. */
    private fun findFlutterSurface(): SurfaceView? {
        val root = activityRef.get()?.window?.decorView ?: return null
        return find(root).also { if (it == null) Log.w(TAG, "no FlutterSurfaceView in the window") }
    }

    /** The largest FlutterSurfaceView (Flutter's own surface, not a platform view's). */
    private fun find(v: View): SurfaceView? {
        var best: SurfaceView? = null
        fun walk(x: View) {
            if (x is SurfaceView && x.javaClass.name == FLUTTER_SURFACE_VIEW) {
                val b = best
                if (b == null || x.width * x.height > b.width * b.height) best = x
            }
            if (x is ViewGroup) for (i in 0 until x.childCount) walk(x.getChildAt(i))
        }
        walk(v)
        return best
    }
}
