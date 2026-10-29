package com.example.flutter_education_app

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.hardware.input.InputManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The whole-screen annotation overlay (D-079): a transparent full-screen canvas and a small floating
 * toolbar drawn over every app while the presenter shares the WHOLE Android screen. MediaProjection
 * captures overlay windows, so the strokes are burned into the shared video and every recording; the
 * app does not also send them as vectors.
 *
 * Two windows (TYPE_APPLICATION_OVERLAY, "Display over other apps"):
 *  - the canvas, MATCH_PARENT. Drawing on: it takes the touches. Drawing off ("use apps"):
 *    FLAG_NOT_TOUCHABLE and, on Android 12+, a window alpha at most the system's
 *    maximumObscuringOpacityForTouch (0.8): the untrusted-touch rule then lets the touches reach the
 *    app below, so the presenter keeps using other apps with the drawings still on screen.
 *  - the toolbar, WRAP_CONTENT, draggable by its grip, collapsible to one button. Pen, highlighter,
 *    eraser (stroke eraser), laser (fades), use apps, undo, clear, colour, thickness, collapse, close.
 *
 * Stylus pressure comes from MotionEvent.getPressure; a finger draws at 0.5. Palm-safe: one pointer draws;
 * while a stylus is down (or just lifted) fingers are ignored, and the stylus's eraser end erases.
 * Labels / colours come from Dart (android_overlay.dart), so the overlay speaks the app language.
 */
class AnnotationOverlay(context: Context, private val onClosed: () -> Unit) {

    companion object {
        private const val TAG = "AnnotationOverlay"
        private val PEN_WIDTHS = floatArrayOf(0.002f, 0.004f, 0.008f)
        private val HIGHLIGHTER_WIDTHS = floatArrayOf(0.012f, 0.02f, 0.032f)
        const val LASER_TTL_MS = 1500L
        private const val PALM_GUARD_MS = 500L
    }

    enum class Tool { PEN, HIGHLIGHTER, ERASER, LASER }

    private val ctx: Context =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                context.applicationContext.createWindowContext(overlayType(), null)
            else context.applicationContext
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var canvasView: CanvasView? = null
    private var toolbar: Toolbar? = null
    private var canvasParams: WindowManager.LayoutParams? = null
    private var toolbarParams: WindowManager.LayoutParams? = null

    // State shared by the canvas and the toolbar.
    var tool = Tool.PEN
    var drawing = true
    var colors: IntArray = intArrayOf(0xFFE53935.toInt(), 0xFFFFB300.toInt(), 0xFF43A047.toInt(),
            0xFF1E88E5.toInt(), 0xFF8E24AA.toInt(), Color.WHITE, 0xFF212121.toInt())
    var color: Int = colors[0]
    var thickness = 1
    var labels: Map<String, String> = emptyMap()
    var surface: Int = 0xF0182030.toInt()
    var accent: Int = 0xFF4FC3F7.toInt()
    var rtl = false

    val isShowing: Boolean get() = canvasView != null

    fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback

    fun dp(v: Float): Float = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)

    @Suppress("DEPRECATION")
    private fun overlayType(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE

    /** Adds both windows. False when the system refused them (no permission, a bad token…). */
    fun show(): Boolean {
        if (isShowing) {
            toolbar?.refresh()
            return true
        }
        return try {
            val cv = CanvasView(ctx)
            val cp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.MATCH_PARENT,
                    overlayType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                }
                title = "Annotation canvas"
            }
            wm.addView(cv, cp)
            canvasView = cv
            canvasParams = cp

            val tb = Toolbar(ctx)
            val tp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    overlayType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = dp(12f).toInt()
                y = dp(96f).toInt()
                title = "Annotation toolbar"
            }
            wm.addView(tb, tp)
            toolbar = tb
            toolbarParams = tp
            applyTouchMode()
            Log.d(TAG, "overlay shown")
            true
        } catch (e: Exception) {
            Log.w(TAG, "overlay could not be shown: ${e.message}")
            hide()
            false
        }
    }

    fun hide() {
        toolbar?.let { runCatching { wm.removeViewImmediate(it) } }
        canvasView?.let { runCatching { wm.removeViewImmediate(it) } }
        toolbar = null
        canvasView = null
        toolbarParams = null
        canvasParams = null
    }

    /** Drawing on: the canvas takes touches. Off: touches pass through to the app below. */
    fun setDrawingMode(on: Boolean) {
        drawing = on
        applyTouchMode()
        toolbar?.refresh()
    }

    private fun applyTouchMode() {
        val cv = canvasView ?: return
        val p = canvasParams ?: return
        if (drawing) {
            p.flags = p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
            p.alpha = 1f
        } else {
            p.flags = p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            p.alpha = passThroughAlpha()
        }
        runCatching { wm.updateViewLayout(cv, p) }
    }

    private fun passThroughAlpha(): Float {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 1f
        val im = ctx.getSystemService(Context.INPUT_SERVICE) as? InputManager
        val maxOpacity = im?.maximumObscuringOpacityForTouch ?: 0.8f
        return min(0.8f, maxOpacity)
    }

    fun undo() = canvasView?.undo()
    fun clear() = canvasView?.clear()
    fun close() {
        hide()
        onClosed()
    }

    fun widthFraction(t: Tool): Float =
            if (t == Tool.HIGHLIGHTER) HIGHLIGHTER_WIDTHS[thickness] else PEN_WIDTHS[thickness]

    // ── Toolbar dragging ────────────────────────────────────────────────────────

    fun moveToolbarBy(dx: Float, dy: Float) {
        val tb = toolbar ?: return
        val p = toolbarParams ?: return
        val dm = ctx.resources.displayMetrics
        p.x = (p.x + dx.toInt()).coerceIn(0, max(0, dm.widthPixels - tb.width))
        p.y = (p.y + dy.toInt()).coerceIn(0, max(0, dm.heightPixels - tb.height))
        runCatching { wm.updateViewLayout(tb, p) }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Canvas
    // ─────────────────────────────────────────────────────────────────────────────

    private class Stroke(val highlighter: Boolean, val color: Int, val widthPx: Float) {
        val xs = ArrayList<Float>()
        val ys = ArrayList<Float>()
        val ps = ArrayList<Float>()
        var path: Path? = null
        var pathCount = 0

        fun add(x: Float, y: Float, p: Float) {
            if (xs.isNotEmpty() && xs.last() == x && ys.last() == y) return
            xs.add(x); ys.add(y); ps.add(p)
        }

        val size get() = xs.size
        val pressured get() = !highlighter && ps.any { abs(it - 0.5f) > 0.02f }

        fun smoothPath(): Path {
            path?.let { if (pathCount == size) return it }
            val p = Path()
            if (size > 0) {
                p.moveTo(xs[0], ys[0])
                if (size == 2) p.lineTo(xs[1], ys[1])
                else if (size > 2) {
                    for (i in 1 until size - 1) {
                        p.quadTo(xs[i], ys[i], (xs[i] + xs[i + 1]) / 2f, (ys[i] + ys[i + 1]) / 2f)
                    }
                    p.lineTo(xs[size - 1], ys[size - 1])
                }
            }
            path = p
            pathCount = size
            return p
        }

        fun distanceTo(x: Float, y: Float): Float {
            if (size == 1) return hypot(x - xs[0], y - ys[0])
            var best = Float.MAX_VALUE
            for (i in 1 until size) best = min(best, segDist(x, y, xs[i - 1], ys[i - 1], xs[i], ys[i]))
            return best
        }

        private fun segDist(px: Float, py: Float, ax: Float, ay: Float, bx: Float, by: Float): Float {
            val dx = bx - ax
            val dy = by - ay
            val l2 = dx * dx + dy * dy
            if (l2 == 0f) return hypot(px - ax, py - ay)
            val t = (((px - ax) * dx + (py - ay) * dy) / l2).coerceIn(0f, 1f)
            return hypot(px - (ax + dx * t), py - (ay + dy * t))
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class CanvasView(context: Context) : View(context) {
        private val strokes = ArrayList<Stroke>()
        private var current: Stroke? = null
        private var activePointer = -1
        private var activeTool: Tool? = null
        private var stylusDown = false
        private var stylusUpAt = 0L
        private var laserX = 0f
        private var laserY = 0f
        private var laserAt = 0L

        private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
        }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
        private val glow = Paint(Paint.ANTI_ALIAS_FLAG)

        init {
            // BlurMaskFilter needs software rendering on some devices; the canvas layer is small work.
            setLayerType(LAYER_TYPE_SOFTWARE, null)
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        fun undo() {
            if (strokes.isNotEmpty()) strokes.removeAt(strokes.size - 1)
            invalidate()
        }

        fun clear() {
            strokes.clear()
            current = null
            invalidate()
        }

        private fun isStylus(tt: Int) = tt == MotionEvent.TOOL_TYPE_STYLUS || tt == MotionEvent.TOOL_TYPE_ERASER

        private fun pressure(ev: MotionEvent, idx: Int, h: Int = -1): Float {
            if (!isStylus(ev.getToolType(idx))) return 0.5f
            val p = if (h >= 0) ev.getHistoricalPressure(idx, h) else ev.getPressure(idx)
            return p.coerceIn(0f, 1f)
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(ev: MotionEvent): Boolean {
            if (!drawing) return false
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                    val idx = ev.actionIndex
                    val tt = ev.getToolType(idx)
                    val stylus = isStylus(tt)
                    if (stylus) stylusDown = true
                    val palmWindow = SystemClock.uptimeMillis() - stylusUpAt < PALM_GUARD_MS
                    if (!stylus && (stylusDown || palmWindow)) return true
                    if (activePointer != -1) {
                        // A stylus wins over a finger that is drawing (the palm): that stroke goes away.
                        val activeIdx = ev.findPointerIndex(activePointer)
                        val activeIsFinger = activeIdx >= 0 && !isStylus(ev.getToolType(activeIdx))
                        if (stylus && activeIsFinger) {
                            current?.let { strokes.remove(it) }
                            current = null
                            activePointer = -1
                        } else return true
                    }
                    activePointer = ev.getPointerId(idx)
                    activeTool = if (tt == MotionEvent.TOOL_TYPE_ERASER) Tool.ERASER else tool
                    begin(ev.getX(idx), ev.getY(idx), pressure(ev, idx))
                }
                MotionEvent.ACTION_MOVE -> {
                    val idx = ev.findPointerIndex(activePointer)
                    if (idx < 0) return true
                    for (h in 0 until ev.historySize) {
                        moveTo(ev.getHistoricalX(idx, h), ev.getHistoricalY(idx, h), pressure(ev, idx, h))
                    }
                    moveTo(ev.getX(idx), ev.getY(idx), pressure(ev, idx))
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                    val idx = ev.actionIndex
                    if (isStylus(ev.getToolType(idx))) {
                        stylusDown = false
                        stylusUpAt = SystemClock.uptimeMillis()
                    }
                    if (ev.actionMasked == MotionEvent.ACTION_CANCEL || ev.getPointerId(idx) == activePointer) {
                        current = null
                        activePointer = -1
                        activeTool = null
                    }
                }
            }
            return true
        }

        private fun begin(x: Float, y: Float, p: Float) {
            val t = activeTool ?: return
            when (t) {
                Tool.PEN, Tool.HIGHLIGHTER -> {
                    val hl = t == Tool.HIGHLIGHTER
                    val c = if (hl) (color and 0x00FFFFFF) or (0x60 shl 24) else color
                    val s = Stroke(hl, c, max(1f, widthFraction(t) * width))
                    s.add(x, y, p)
                    strokes.add(s)
                    current = s
                }
                Tool.ERASER -> eraseAt(x, y)
                Tool.LASER -> laser(x, y)
            }
            invalidate()
        }

        private fun moveTo(x: Float, y: Float, p: Float) {
            when (activeTool) {
                Tool.PEN, Tool.HIGHLIGHTER -> current?.add(x, y, p)
                Tool.ERASER -> eraseAt(x, y)
                Tool.LASER -> laser(x, y)
                null -> {}
            }
            invalidate()
        }

        private fun eraseAt(x: Float, y: Float) {
            val tol = dp(10f)
            strokes.removeAll { it.distanceTo(x, y) <= tol + it.widthPx / 2f }
        }

        private fun laser(x: Float, y: Float) {
            laserX = x
            laserY = y
            laserAt = SystemClock.uptimeMillis()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            for (s in strokes) drawStroke(canvas, s)
            drawLaser(canvas)
        }

        private fun drawStroke(canvas: Canvas, s: Stroke) {
            if (s.size == 0) return
            paint.color = s.color
            paint.strokeCap = if (s.highlighter) Paint.Cap.BUTT else Paint.Cap.ROUND
            if (s.size == 1) {
                fill.color = s.color
                val w = if (s.highlighter) s.widthPx else s.widthPx * (0.5f + s.ps[0])
                if (s.highlighter) canvas.drawRect(RectF(s.xs[0] - w / 4, s.ys[0] - w / 2, s.xs[0] + w / 4, s.ys[0] + w / 2), fill)
                else canvas.drawCircle(s.xs[0], s.ys[0], w / 2, fill)
                return
            }
            if (!s.pressured) {
                paint.strokeWidth = s.widthPx
                canvas.drawPath(s.smoothPath(), paint)
                return
            }
            // Variable width: one quadratic piece per sample (midpoint → sample → next midpoint).
            var fx = s.xs[0]
            var fy = s.ys[0]
            val seg = Path()
            for (i in 1 until s.size) {
                val last = i == s.size - 1
                val tx = if (last) s.xs[i] else (s.xs[i] + s.xs[i + 1]) / 2f
                val ty = if (last) s.ys[i] else (s.ys[i] + s.ys[i + 1]) / 2f
                paint.strokeWidth = s.widthPx * (0.5f + s.ps[i])
                seg.reset()
                seg.moveTo(fx, fy)
                seg.quadTo(s.xs[i], s.ys[i], tx, ty)
                canvas.drawPath(seg, paint)
                fx = tx
                fy = ty
            }
        }

        private fun drawLaser(canvas: Canvas) {
            if (laserAt == 0L) return
            val age = (SystemClock.uptimeMillis() - laserAt).toFloat() / LASER_TTL_MS
            if (age >= 1f) {
                laserAt = 0L
                return
            }
            val a = if (age <= 0.6f) 1f else (1f - (age - 0.6f) / 0.4f).coerceIn(0f, 1f)
            val r = max(dp(5f), width * 0.007f)
            val laserColor = colors.firstOrNull() ?: Color.RED
            glow.color = withAlpha(laserColor, 0.35f * a)
            glow.maskFilter = BlurMaskFilter(r * 1.4f, BlurMaskFilter.Blur.NORMAL)
            canvas.drawCircle(laserX, laserY, r * 2.2f, glow)
            fill.color = withAlpha(laserColor, a)
            canvas.drawCircle(laserX, laserY, r, fill)
            fill.color = withAlpha(Color.WHITE, 0.85f * a)
            canvas.drawCircle(laserX, laserY, r * 0.4f, fill)
            postInvalidateOnAnimation()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Toolbar
    // ─────────────────────────────────────────────────────────────────────────────

    enum class Glyph { MOVE, PEN, HIGHLIGHTER, ERASER, LASER, INTERACT, UNDO, CLEAR, COLOR, THICKNESS, COLLAPSE, EXPAND, CLOSE, SWATCH }

    @SuppressLint("ViewConstructor")
    private inner class ToolButton(context: Context, val glyph: Glyph, val swatch: Int = 0) : View(context) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        var isOn = false

        init {
            val s = dp(44f).toInt()
            layoutParams = LinearLayout.LayoutParams(s, s)
            isClickable = true
            isFocusable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val s = if (glyph == Glyph.SWATCH) dp(40f).toInt() else dp(48f).toInt()
            setMeasuredDimension(s, s)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val w = width.toFloat()
            val h = height.toFloat()
            val cx = w / 2f
            val cy = h / 2f
            val u = min(w, h) / 48f
            if (isOn) {
                p.style = Paint.Style.FILL
                p.color = withAlpha(accent, 0.30f)
                canvas.drawRoundRect(RectF(4 * u, 4 * u, w - 4 * u, h - 4 * u), 12 * u, 12 * u, p)
            }
            val ink = if (isOn) Color.WHITE else withAlpha(Color.WHITE, 0.75f)
            p.color = ink
            p.style = Paint.Style.STROKE
            p.strokeWidth = 2.4f * u
            p.strokeCap = Paint.Cap.ROUND
            p.strokeJoin = Paint.Join.ROUND
            when (glyph) {
                Glyph.MOVE -> {
                    p.style = Paint.Style.FILL
                    for (dx in intArrayOf(-1, 1)) for (dy in intArrayOf(-1, 0, 1)) {
                        canvas.drawCircle(cx + dx * 4 * u, cy + dy * 6 * u, 2f * u, p)
                    }
                }
                Glyph.PEN -> {
                    canvas.drawLine(cx - 8 * u, cy + 8 * u, cx + 7 * u, cy - 7 * u, p)
                    p.style = Paint.Style.FILL
                    canvas.drawCircle(cx - 9 * u, cy + 9 * u, 2.2f * u, p)
                }
                Glyph.HIGHLIGHTER -> {
                    p.strokeWidth = 7 * u
                    p.strokeCap = Paint.Cap.BUTT
                    p.color = withAlpha(color, 0.6f)
                    canvas.drawLine(cx - 9 * u, cy + 6 * u, cx + 9 * u, cy - 6 * u, p)
                }
                Glyph.ERASER -> {
                    canvas.save()
                    canvas.rotate(-35f, cx, cy)
                    val r = RectF(cx - 10 * u, cy - 5 * u, cx + 10 * u, cy + 5 * u)
                    canvas.drawRoundRect(r, 2.5f * u, 2.5f * u, p)
                    p.style = Paint.Style.FILL
                    canvas.drawRoundRect(RectF(r.left, r.top, cx - 1 * u, r.bottom), 2.5f * u, 2.5f * u, p)
                    canvas.restore()
                }
                Glyph.LASER -> {
                    canvas.drawCircle(cx, cy, 8 * u, p)
                    p.style = Paint.Style.FILL
                    p.color = colors.firstOrNull() ?: Color.RED
                    canvas.drawCircle(cx, cy, 4 * u, p)
                }
                Glyph.INTERACT -> {
                    // An arrow cursor: drawing off, the apps below get the touches.
                    val path = Path().apply {
                        moveTo(cx - 6 * u, cy - 10 * u)
                        lineTo(cx - 6 * u, cy + 8 * u)
                        lineTo(cx - 1 * u, cy + 3 * u)
                        lineTo(cx + 3 * u, cy + 11 * u)
                        lineTo(cx + 6 * u, cy + 9.5f * u)
                        lineTo(cx + 2 * u, cy + 1.5f * u)
                        lineTo(cx + 8 * u, cy + 1.5f * u)
                        close()
                    }
                    canvas.drawPath(path, p)
                }
                Glyph.UNDO -> {
                    canvas.save()
                    if (rtl) canvas.scale(-1f, 1f, cx, cy) // undo points against the reading direction
                    val arc = RectF(cx - 8 * u, cy - 6 * u, cx + 8 * u, cy + 10 * u)
                    canvas.drawArc(arc, 200f, 230f, false, p)
                    canvas.drawLine(cx - 9 * u, cy - 3 * u, cx - 9 * u, cy - 10 * u, p)
                    canvas.drawLine(cx - 9 * u, cy - 3 * u, cx - 2 * u, cy - 3 * u, p)
                    canvas.restore()
                }
                Glyph.CLEAR -> {
                    p.color = 0xFFEF5350.toInt()
                    canvas.drawRoundRect(RectF(cx - 7 * u, cy - 6 * u, cx + 7 * u, cy + 10 * u), 2 * u, 2 * u, p)
                    canvas.drawLine(cx - 10 * u, cy - 9 * u, cx + 10 * u, cy - 9 * u, p)
                    canvas.drawLine(cx - 3 * u, cy - 12 * u, cx + 3 * u, cy - 12 * u, p)
                }
                Glyph.COLOR -> {
                    p.style = Paint.Style.FILL
                    p.color = color
                    canvas.drawCircle(cx, cy, 10 * u, p)
                    p.style = Paint.Style.STROKE
                    p.color = Color.WHITE
                    canvas.drawCircle(cx, cy, 10 * u, p)
                }
                Glyph.THICKNESS -> {
                    p.style = Paint.Style.FILL
                    canvas.drawCircle(cx, cy, (3f + thickness * 3f) * u, p)
                }
                Glyph.COLLAPSE -> canvas.drawLine(cx - 8 * u, cy, cx + 8 * u, cy, p)
                Glyph.EXPAND -> {
                    canvas.drawLine(cx - 8 * u, cy + 8 * u, cx + 7 * u, cy - 7 * u, p)
                    p.style = Paint.Style.FILL
                    p.color = color
                    canvas.drawCircle(cx - 9 * u, cy + 9 * u, 3f * u, p)
                }
                Glyph.CLOSE -> {
                    canvas.drawLine(cx - 7 * u, cy - 7 * u, cx + 7 * u, cy + 7 * u, p)
                    canvas.drawLine(cx + 7 * u, cy - 7 * u, cx - 7 * u, cy + 7 * u, p)
                }
                Glyph.SWATCH -> {
                    p.style = Paint.Style.FILL
                    p.color = swatch
                    val r = if (swatch == color) 11 * u else 9 * u
                    canvas.drawCircle(cx, cy, r, p)
                    p.style = Paint.Style.STROKE
                    p.color = if (swatch == color) Color.WHITE else withAlpha(Color.WHITE, 0.3f)
                    canvas.drawCircle(cx, cy, r, p)
                }
            }
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class Toolbar(context: Context) : LinearLayout(context) {
        private var collapsed = false
        private var swatchesOpen = false
        private val buttons = ArrayList<ToolButton>()

        init {
            orientation = VERTICAL
            val pad = dp(4f).toInt()
            setPadding(pad, pad, pad, pad)
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(18f)
                setColor(surface)
                setStroke(dp(1f).toInt(), withAlpha(Color.WHITE, 0.19f))
            }
            elevation = dp(8f)
            layoutDirection = if (rtl) LAYOUT_DIRECTION_RTL else LAYOUT_DIRECTION_LTR
            build()
        }

        fun refresh() {
            (background as? android.graphics.drawable.GradientDrawable)?.setColor(surface)
            layoutDirection = if (rtl) LAYOUT_DIRECTION_RTL else LAYOUT_DIRECTION_LTR
            build()
        }

        private fun row(): LinearLayout = LinearLayout(context).apply { orientation = HORIZONTAL }

        @SuppressLint("ClickableViewAccessibility")
        private fun build() {
            removeAllViews()
            buttons.clear()
            if (collapsed) {
                val r = row()
                r.addView(grip())
                r.addView(button(Glyph.EXPAND, label("expand", "Show drawing tools")) {
                    collapsed = false
                    build()
                })
                addView(r)
                post { requestLayoutWindow() }
                return
            }
            val r1 = row()
            r1.addView(grip())
            r1.addView(toolButton(Glyph.PEN, Tool.PEN, label("pen", "Pen")))
            r1.addView(toolButton(Glyph.HIGHLIGHTER, Tool.HIGHLIGHTER, label("highlighter", "Highlighter")))
            r1.addView(toolButton(Glyph.ERASER, Tool.ERASER, label("eraser", "Eraser")))
            r1.addView(toolButton(Glyph.LASER, Tool.LASER, label("laser", "Laser pointer")))
            r1.addView(button(Glyph.INTERACT, label("interact", "Use apps (drawing off)"), selected = !drawing) {
                setDrawingMode(false)
            })
            addView(r1)

            val r2 = row()
            r2.addView(button(Glyph.UNDO, label("undo", "Undo")) { undo() })
            r2.addView(button(Glyph.CLEAR, label("clear", "Clear all")) { clear() })
            r2.addView(button(Glyph.COLOR, label("color", "Colour"), selected = swatchesOpen) {
                swatchesOpen = !swatchesOpen
                build()
            })
            r2.addView(button(Glyph.THICKNESS, "${label("thickness", "Thickness")} ${thickness + 1}/3") {
                thickness = (thickness + 1) % 3
                build()
            })
            r2.addView(button(Glyph.COLLAPSE, label("collapse", "Collapse toolbar")) {
                collapsed = true
                swatchesOpen = false
                build()
            })
            r2.addView(button(Glyph.CLOSE, label("close", "Close annotation")) { close() })
            addView(r2)

            if (swatchesOpen) {
                val r3 = row()
                for ((i, c) in colors.withIndex()) {
                    r3.addView(ToolButton(context, Glyph.SWATCH, c).apply {
                        contentDescription = "${label("color", "Colour")} ${i + 1}"
                        isOn = c == color
                        setOnClickListener {
                            color = c
                            swatchesOpen = false
                            if (tool == Tool.ERASER || tool == Tool.LASER) tool = Tool.PEN
                            setDrawingMode(true)
                            build()
                        }
                    })
                }
                addView(r3)
            }
            post { requestLayoutWindow() }
        }

        private fun requestLayoutWindow() {
            val tp = toolbarParams ?: return
            runCatching { wm.updateViewLayout(this, tp) }
        }

        private fun button(g: Glyph, desc: String, selected: Boolean = false, onTap: () -> Unit): ToolButton =
                ToolButton(context, g).apply {
                    contentDescription = desc
                    isOn = selected
                    setOnClickListener { onTap() }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tooltipText = desc
                    buttons.add(this)
                }

        private fun toolButton(g: Glyph, t: Tool, desc: String): ToolButton =
                button(g, desc, selected = drawing && tool == t) {
                    tool = t
                    setDrawingMode(true)
                    build()
                }

        @SuppressLint("ClickableViewAccessibility")
        private fun grip(): ToolButton = ToolButton(context, Glyph.MOVE).apply {
            contentDescription = label("move", "Drag to move the toolbar")
            var lastX = 0f
            var lastY = 0f
            setOnTouchListener { _, ev ->
                when (ev.actionMasked) {
                    MotionEvent.ACTION_DOWN -> {
                        lastX = ev.rawX
                        lastY = ev.rawY
                    }
                    MotionEvent.ACTION_MOVE -> {
                        moveToolbarBy(ev.rawX - lastX, ev.rawY - lastY)
                        lastX = ev.rawX
                        lastY = ev.rawY
                    }
                }
                true
            }
        }
    }
}

private fun withAlpha(c: Int, a: Float): Int = (c and 0x00FFFFFF) or ((a.coerceIn(0f, 1f) * 255).toInt() shl 24)
