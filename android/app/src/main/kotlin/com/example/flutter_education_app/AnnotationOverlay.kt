package com.example.flutter_education_app

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.ComponentCallbacks
import android.content.Context
import android.content.res.Configuration
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.hardware.input.InputManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.widget.LinearLayout
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The whole-screen annotation overlay (D-079, D-081): while the presenter shares the WHOLE Android screen
 * and has LEFT the app, a small floating "annotate" bubble stays over every app. Tapping it opens a compact
 * toolbar and a transparent full-screen canvas over the app below; MediaProjection captures overlay
 * windows, so the strokes are burned into the shared video (and every recording) and are NOT also sent as
 * vectors (no double drawing on the viewers).
 *
 * Windows (TYPE_APPLICATION_OVERLAY, "Display over other apps"), present only while armed AND the app is
 * not in front (AnnotationOverlayChannel tells us):
 *  - bubble: 56 dp, draggable, snaps to the nearest side; tap → the tools.
 *  - toolbar: pen · highlighter · eraser · laser · use apps (drawing off) / colour · thickness · undo · clear ·
 *    hide tools (back to the bubble, drawings stay) · close (back to the bubble, drawings cleared).
 *  - canvas: MATCH_PARENT. Drawing: it takes the touches. Otherwise FLAG_NOT_TOUCHABLE and, on Android 12+,
 *    a window alpha at most the system's maximumObscuringOpacityForTouch: the untrusted-touch rule then
 *    lets the touches through to the app below while the drawings stay on screen.
 * Back in the app every window is removed; the strokes are kept and come back when the presenter leaves the
 * app again (they belong to that screen). A rotation clears them (the content they marked moved). The share
 * ending disarms and clears everything.
 *
 * Ink: AnnotationInk (the room's annotation_ink.dart rules). Stylus pressure from MotionEvent (historical
 * samples included); a finger draws a constant width. Palm-safe: one pointer draws; while a stylus is down
 * (or just lifted) fingers are ignored, and the stylus's eraser end erases.
 */
class AnnotationOverlay(context: Context, private val onClosed: () -> Unit) {

    companion object {
        private const val TAG = "AnnotationOverlay"
        private val PEN_WIDTHS = floatArrayOf(0.002f, 0.004f, 0.008f)
        private val HIGHLIGHTER_WIDTHS = floatArrayOf(0.012f, 0.02f, 0.032f)
        const val LASER_TTL_MS = 1500L
        private const val PALM_GUARD_MS = 500L
        private const val MAX_STROKES = 400
    }

    enum class Tool { PEN, HIGHLIGHTER, ERASER, LASER }
    private enum class Mode { BUBBLE, TOOLS }

    private val ctx: Context =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                context.applicationContext.createWindowContext(overlayType(), null)
            else context.applicationContext
    private val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    private var bubble: BubbleView? = null
    private var toolbar: Toolbar? = null
    private var canvasView: CanvasView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var toolbarParams: WindowManager.LayoutParams? = null
    private var canvasParams: WindowManager.LayoutParams? = null

    // Set by Dart (AnnotationOverlayChannel "show").
    var colors: IntArray = intArrayOf(0xFFE53935.toInt(), 0xFFFFB300.toInt(), 0xFF43A047.toInt(),
            0xFF1E88E5.toInt(), 0xFF8E24AA.toInt(), Color.WHITE, 0xFF212121.toInt())
    var color: Int = colors[0]
    var thickness = 1
    var labels: Map<String, String> = emptyMap()
    var surface: Int = 0xF0182030.toInt()
    var accent: Int = 0xFF4FC3F7.toInt()
    var rtl = false

    // State.
    private var armed = false
    private var appInFront = true
    private var mode = Mode.BUBBLE
    var tool = Tool.PEN
        private set
    /** Tools open, but the touches go to the apps below (the drawings stay). */
    private var passThrough = false
    private var swatchesOpen = false

    /** The strokes live here, not in the canvas view: they survive the canvas window being removed. */
    private val strokes = ArrayList<AnnotationInk.Stroke>()
    private var strokesW = 0
    private var strokesH = 0

    // Where the bubble sits (px from the top-left corner of the screen); remembered across shows.
    private var bubbleX = -1
    private var bubbleY = -1
    private var configCallbacks: ComponentCallbacks? = null

    /** Armed for the running share (what Dart's isShowing means). */
    val isShowing: Boolean get() = armed

    fun label(key: String, fallback: String) = labels[key]?.takeIf { it.isNotBlank() } ?: fallback

    fun dp(v: Float): Float = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)

    @Suppress("DEPRECATION")
    private fun overlayType(): Int =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE

    private fun reduceMotion(): Boolean =
            runCatching { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
                    .getOrDefault(false)

    // ── Lifecycle ───────────────────────────────────────────────────────────────

    /** Arms the overlay for this share. Windows appear once the presenter leaves the app. */
    fun show(): Boolean {
        if (!armed) {
            armed = true
            mode = Mode.BUBBLE
            passThrough = false
            registerConfig()
            Log.d(TAG, "armed (shown outside the app)")
        }
        toolbar?.rebuild()
        bubble?.invalidate()
        return sync()
    }

    /** Disarms: every window goes, the drawings are cleared. */
    fun hide() {
        val was = armed
        armed = false
        mode = Mode.BUBBLE
        swatchesOpen = false
        strokes.clear()
        removeAll()
        unregisterConfig()
        if (was) Log.d(TAG, "disarmed")
    }

    fun setAppInFront(front: Boolean) {
        if (front == appInFront) return
        appInFront = front
        if (front) {
            // Back in the app: the tools close (the drawings are kept for when the presenter leaves again).
            mode = Mode.BUBBLE
            swatchesOpen = false
        }
        sync()
    }

    /** Adds / removes windows for the current state. False when the system refused a window. */
    private fun sync(): Boolean {
        if (!armed || appInFront) {
            removeAll()
            return true
        }
        return try {
            when (mode) {
                Mode.BUBBLE -> {
                    removeToolbar()
                    if (strokes.isEmpty()) removeCanvas() else ensureCanvas()
                    ensureBubble()
                }
                Mode.TOOLS -> {
                    removeBubble()
                    ensureCanvas()
                    ensureToolbar()
                }
            }
            applyTouchMode()
            true
        } catch (e: Exception) {
            // "Display over other apps" taken away while sharing, a bad token…: the room falls back to in-app.
            Log.w(TAG, "overlay window refused: ${e.message}")
            armed = false
            strokes.clear()
            removeAll()
            unregisterConfig()
            onClosed()
            false
        }
    }

    private fun removeAll() {
        removeToolbar()
        removeBubble()
        removeCanvas()
    }

    // LEFT, not START: a START window measures x from the right under an Arabic system locale.
    @SuppressLint("RtlHardcoded")
    private fun baseParams(w: Int, h: Int, flags: Int) = WindowManager.LayoutParams(
            w, h, overlayType(),
            flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
    ).apply { gravity = Gravity.TOP or Gravity.LEFT }

    private fun ensureCanvas() {
        if (canvasView != null) return
        val cv = CanvasView(ctx)
        val p = baseParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        ).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
            title = "Annotation canvas"
        }
        wm.addView(cv, p)
        canvasView = cv
        canvasParams = p
    }

    private fun removeCanvas() {
        canvasView?.let { runCatching { wm.removeViewImmediate(it) } }
        canvasView = null
        canvasParams = null
    }

    private fun ensureBubble() {
        if (bubble != null) return
        val dm = ctx.resources.displayMetrics
        val size = dp(56f).toInt()
        if (bubbleX < 0 || bubbleY < 0) {
            // First time: the reading-end side, a third down.
            bubbleX = if (rtl) dp(12f).toInt() else dm.widthPixels - size - dp(12f).toInt()
            bubbleY = dm.heightPixels / 3
        }
        val b = BubbleView(ctx)
        val p = baseParams(size + dp(12f).toInt(), size + dp(12f).toInt(), WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS).apply {
            x = bubbleX
            y = bubbleY
            title = "Annotation bubble"
        }
        wm.addView(b, p)
        bubble = b
        bubbleParams = p
        b.appear()
    }

    private fun removeBubble() {
        bubble?.let {
            it.cancelAnimations()
            runCatching { wm.removeViewImmediate(it) }
        }
        bubble = null
        bubbleParams = null
    }

    private fun ensureToolbar() {
        if (toolbar != null) return
        val tb = Toolbar(ctx)
        val p = baseParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        ).apply {
            // Opens where the bubble was, on its side of the screen.
            val dm = ctx.resources.displayMetrics
            x = if (bubbleX > dm.widthPixels / 2) dm.widthPixels else 0
            y = max(0, bubbleY)
            title = "Annotation toolbar"
        }
        wm.addView(tb, p)
        toolbar = tb
        toolbarParams = p
        tb.post { clampToolbar() }
    }

    private fun removeToolbar() {
        toolbar?.let { runCatching { wm.removeViewImmediate(it) } }
        toolbar = null
        toolbarParams = null
    }

    private fun registerConfig() {
        if (configCallbacks != null) return
        val cb = object : ComponentCallbacks {
            override fun onConfigurationChanged(newConfig: Configuration) {
                // Rotation / screen size: keep the bubble and the toolbar on screen.
                canvasView?.post { clampBubble(animate = false); clampToolbar() }
                    ?: bubble?.post { clampBubble(animate = false); clampToolbar() }
            }
            override fun onLowMemory() {}
        }
        ctx.registerComponentCallbacks(cb)
        configCallbacks = cb
    }

    private fun unregisterConfig() {
        configCallbacks?.let { runCatching { ctx.unregisterComponentCallbacks(it) } }
        configCallbacks = null
    }

    private fun clampBubble(animate: Boolean) {
        val b = bubble ?: return
        val p = bubbleParams ?: return
        val dm = ctx.resources.displayMetrics
        val w = if (b.width > 0) b.width else p.width
        val h = if (b.height > 0) b.height else p.height
        val margin = dp(6f).toInt()
        // Snap to the nearest side.
        val targetX = if (p.x + w / 2 < dm.widthPixels / 2) margin else dm.widthPixels - w - margin
        val targetY = p.y.coerceIn(dp(24f).toInt(), max(dp(24f).toInt(), dm.heightPixels - h - dp(48f).toInt()))
        if (!animate || reduceMotion()) {
            p.x = targetX
            p.y = targetY
            bubbleX = p.x
            bubbleY = p.y
            runCatching { wm.updateViewLayout(b, p) }
            return
        }
        val fromX = p.x
        val fromY = p.y
        b.animateTo { f ->
            if (bubble !== b) return@animateTo
            p.x = (fromX + (targetX - fromX) * f).toInt()
            p.y = (fromY + (targetY - fromY) * f).toInt()
            bubbleX = p.x
            bubbleY = p.y
            runCatching { wm.updateViewLayout(b, p) }
        }
    }

    private fun clampToolbar() {
        val tb = toolbar ?: return
        val p = toolbarParams ?: return
        val dm = ctx.resources.displayMetrics
        val m = dp(8f).toInt()
        p.x = p.x.coerceIn(m, max(m, dm.widthPixels - tb.width - m))
        p.y = p.y.coerceIn(dp(24f).toInt(), max(dp(24f).toInt(), dm.heightPixels - tb.height - dp(24f).toInt()))
        runCatching { wm.updateViewLayout(tb, p) }
    }

    fun moveToolbarBy(dx: Float, dy: Float) {
        val tb = toolbar ?: return
        val p = toolbarParams ?: return
        val dm = ctx.resources.displayMetrics
        p.x = (p.x + dx.toInt()).coerceIn(0, max(0, dm.widthPixels - tb.width))
        p.y = (p.y + dy.toInt()).coerceIn(0, max(0, dm.heightPixels - tb.height))
        runCatching { wm.updateViewLayout(tb, p) }
    }

    // ── Modes and tools ─────────────────────────────────────────────────────────

    private val drawing: Boolean get() = armed && !appInFront && mode == Mode.TOOLS && !passThrough

    private fun openTools() {
        mode = Mode.TOOLS
        passThrough = false
        sync()
    }

    /** Back to the bubble; the drawings stay on screen (touches go to the apps). */
    private fun hideTools() {
        mode = Mode.BUBBLE
        swatchesOpen = false
        sync()
    }

    /** Close: the drawings are cleared and the bubble comes back. */
    private fun closeTools() {
        strokes.clear()
        canvasView?.invalidate()
        hideTools()
    }

    private fun selectTool(t: Tool) {
        tool = t
        passThrough = false
        applyTouchMode()
        toolbar?.rebuild()
    }

    private fun setPassThrough(on: Boolean) {
        passThrough = on
        applyTouchMode()
        toolbar?.rebuild()
    }

    private fun applyTouchMode() {
        val cv = canvasView ?: return
        val p = canvasParams ?: return
        val touch = drawing
        val flags = if (touch) p.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE.inv()
                    else p.flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        val alpha = if (touch) 1f else passThroughAlpha()
        if (flags == p.flags && alpha == p.alpha) return
        p.flags = flags
        p.alpha = alpha
        runCatching { wm.updateViewLayout(cv, p) }
    }

    private fun passThroughAlpha(): Float {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 1f
        val im = ctx.getSystemService(Context.INPUT_SERVICE) as? InputManager
        val maxOpacity = im?.maximumObscuringOpacityForTouch ?: 0.8f
        return min(0.8f, maxOpacity)
    }

    private fun undo() {
        if (strokes.isNotEmpty()) strokes.removeAt(strokes.size - 1)
        canvasView?.invalidate()
        toolbar?.rebuild()
    }

    private fun clear() {
        strokes.clear()
        canvasView?.invalidate()
        toolbar?.rebuild()
    }

    fun widthFraction(t: Tool): Float =
            if (t == Tool.HIGHLIGHTER) HIGHLIGHTER_WIDTHS[thickness] else PEN_WIDTHS[thickness]

    // ─────────────────────────────────────────────────────────────────────────────
    // Canvas
    // ─────────────────────────────────────────────────────────────────────────────

    @SuppressLint("ViewConstructor")
    private inner class CanvasView(context: Context) : View(context) {
        private var current: AnnotationInk.Stroke? = null
        private var filter: AnnotationInk.Filter? = null
        private var activePointer = -1
        private var activeTool: Tool? = null
        private var stylusDown = false
        private var stylusUpAt = 0L
        private var laserX = 0f
        private var laserY = 0f
        private var laserAt = 0L

        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeJoin = Paint.Join.ROUND
        }
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
        private val glow = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
            super.onSizeChanged(w, h, oldw, oldh)
            // A rotation (now, or while the canvas was gone): the drawings marked content that moved.
            if (strokesW != 0 && (w != strokesW || h != strokesH) && strokes.isNotEmpty()) {
                strokes.clear()
                current = null
                activePointer = -1
                Log.d(TAG, "screen size changed ${strokesW}x$strokesH → ${w}x$h: drawings cleared")
            }
            strokesW = w
            strokesH = h
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
                    begin(ev.getX(idx), ev.getY(idx), ev.eventTime / 1000.0, pressure(ev, idx), stylus)
                }
                MotionEvent.ACTION_MOVE -> {
                    val idx = ev.findPointerIndex(activePointer)
                    if (idx < 0) return true
                    for (h in 0 until ev.historySize) {
                        moveTo(ev.getHistoricalX(idx, h), ev.getHistoricalY(idx, h),
                                ev.getHistoricalEventTime(h) / 1000.0, pressure(ev, idx, h))
                    }
                    moveTo(ev.getX(idx), ev.getY(idx), ev.eventTime / 1000.0, pressure(ev, idx))
                    invalidate()
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                    val idx = ev.actionIndex
                    if (isStylus(ev.getToolType(idx))) {
                        stylusDown = false
                        stylusUpAt = SystemClock.uptimeMillis()
                    }
                    if (ev.actionMasked == MotionEvent.ACTION_CANCEL || ev.getPointerId(idx) == activePointer) {
                        if (ev.actionMasked != MotionEvent.ACTION_CANCEL) {
                            filter?.finish(ev.getX(idx), ev.getY(idx))?.let { current?.add(it) }
                        }
                        current?.open = false
                        current = null
                        filter = null
                        activePointer = -1
                        activeTool = null
                        invalidate()
                        toolbar?.rebuild()
                    }
                }
            }
            return true
        }

        private fun begin(x: Float, y: Float, t: Double, p: Float, stylus: Boolean) {
            val tl = activeTool ?: return
            when (tl) {
                Tool.PEN, Tool.HIGHLIGHTER -> {
                    if (strokes.size >= MAX_STROKES) return
                    val hl = tl == Tool.HIGHLIGHTER
                    val c = if (hl) (color and 0x00FFFFFF) or (0x61 shl 24) else (color or (0xFF shl 24))
                    val pressured = stylus && !hl
                    val f = AnnotationInk.Filter(dp(0.8f), pressured)
                    val s = AnnotationInk.Stroke(hl, c, max(1f, widthFraction(tl) * width), pressured)
                    s.add(f.start(x, y, t, p))
                    strokes.add(s)
                    current = s
                    filter = f
                }
                Tool.ERASER -> eraseAt(x, y)
                Tool.LASER -> laser(x, y)
            }
            invalidate()
        }

        private fun moveTo(x: Float, y: Float, t: Double, p: Float) {
            when (activeTool) {
                Tool.PEN, Tool.HIGHLIGHTER -> filter?.add(x, y, t, p)?.let { current?.add(it) }
                Tool.ERASER -> eraseAt(x, y)
                Tool.LASER -> laser(x, y)
                null -> {}
            }
        }

        private fun eraseAt(x: Float, y: Float) {
            val tol = dp(10f)
            if (strokes.removeAll { it.distanceTo(x, y) <= tol + it.widthPx / 2f }) toolbar?.rebuild()
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

        private fun drawStroke(canvas: Canvas, s: AnnotationInk.Stroke) {
            if (s.size == 0) return
            if (s.size == 1) {
                fill.color = s.color
                if (s.highlighter) {
                    val w = s.widthPx
                    canvas.drawRect(RectF(s.xs[0] - w / 4, s.ys[0] - w / 2, s.xs[0] + w / 4, s.ys[0] + w / 2), fill)
                } else canvas.drawCircle(s.xs[0], s.ys[0], s.dotRadius(), fill)
                return
            }
            if (s.highlighter || !s.pressured) {
                strokePaint.color = s.color
                strokePaint.strokeWidth = s.widthPx
                strokePaint.strokeCap = if (s.highlighter) Paint.Cap.BUTT else Paint.Cap.ROUND
                canvas.drawPath(s.strokedPath(), strokePaint)
                return
            }
            fill.color = s.color
            canvas.drawPath(s.shape(), fill)
            s.tail?.let { canvas.drawPath(it, fill) }
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
            // A radial glow (hardware friendly, no blur mask).
            glow.shader = RadialGradient(laserX, laserY, r * 2.4f,
                    intArrayOf(withAlpha(laserColor, 0.45f * a), withAlpha(laserColor, 0f)), null, Shader.TileMode.CLAMP)
            canvas.drawCircle(laserX, laserY, r * 2.4f, glow)
            fill.color = withAlpha(laserColor, a)
            canvas.drawCircle(laserX, laserY, r, fill)
            fill.color = withAlpha(Color.WHITE, 0.85f * a)
            canvas.drawCircle(laserX, laserY, r * 0.4f, fill)
            postInvalidateOnAnimation()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Bubble
    // ─────────────────────────────────────────────────────────────────────────────

    @SuppressLint("ViewConstructor", "ClickableViewAccessibility")
    private inner class BubbleView(context: Context) : View(context) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var downRawX = 0f
        private var downRawY = 0f
        private var startX = 0
        private var startY = 0
        private var dragging = false
        private var pressed = false
        private var animator: ValueAnimator? = null
        private var scale = 1f

        init {
            contentDescription = label("annotate", "Annotate")
            isClickable = true
            isFocusable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tooltipText = label("annotate", "Annotate")
            // A soft shadow under the disc (the window is a little larger than the disc for it).
            elevation = dp(6f)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    val d = dp(56f)
                    val l = (view.width - d) / 2f
                    val t = (view.height - d) / 2f
                    outline.setOval(l.toInt(), t.toInt(), (l + d).toInt(), (t + d).toInt())
                }
            }
            setOnClickListener { openTools() }
        }

        fun appear() {
            if (reduceMotion()) return
            scale = 0.6f
            alpha = 0f
            animate().alpha(1f).setDuration(180).start()
            animateScale(1f, 220)
        }

        private fun animateScale(to: Float, ms: Long) {
            val from = scale
            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = ms
                interpolator = DecelerateInterpolator()
                addUpdateListener {
                    scale = from + (to - from) * (it.animatedValue as Float)
                    invalidate()
                }
                start()
            }
        }

        fun animateTo(step: (Float) -> Unit) {
            animator?.cancel()
            animator = ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 220
                interpolator = DecelerateInterpolator()
                addUpdateListener { step(it.animatedValue as Float) }
                start()
            }
        }

        fun cancelAnimations() {
            animator?.cancel()
            animator = null
            animate().cancel()
        }

        override fun onTouchEvent(ev: MotionEvent): Boolean {
            val bp = bubbleParams ?: return false
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    animator?.cancel()
                    downRawX = ev.rawX
                    downRawY = ev.rawY
                    startX = bp.x
                    startY = bp.y
                    dragging = false
                    pressed = true
                    if (!reduceMotion()) animateScale(0.92f, 90) else invalidate()
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = ev.rawX - downRawX
                    val dy = ev.rawY - downRawY
                    if (!dragging && hypot(dx, dy) > slop) dragging = true
                    if (dragging) {
                        bp.x = (startX + dx).toInt()
                        bp.y = (startY + dy).toInt()
                        bubbleX = bp.x
                        bubbleY = bp.y
                        runCatching { wm.updateViewLayout(this, bp) }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    pressed = false
                    if (!reduceMotion()) animateScale(1f, 120) else invalidate()
                    if (dragging) clampBubble(animate = true)
                    else if (ev.actionMasked == MotionEvent.ACTION_UP) performClick()
                    dragging = false
                }
            }
            return true
        }

        override fun performClick(): Boolean {
            super.performClick()
            return true
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val r = dp(28f) * scale
            // Disc.
            p.style = Paint.Style.FILL
            p.color = surface or (0xFF shl 24)
            canvas.drawCircle(cx, cy, r, p)
            // Accent ring (thicker while pressed).
            p.style = Paint.Style.STROKE
            p.strokeWidth = dp(if (pressed) 3f else 2f)
            p.color = withAlpha(accent, 0.9f)
            canvas.drawCircle(cx, cy, r - p.strokeWidth / 2f, p)
            // Pen glyph in the current ink colour.
            val u = r / 28f
            canvas.save()
            canvas.rotate(-45f, cx, cy)
            p.style = Paint.Style.FILL
            p.color = withAlpha(Color.WHITE, 0.95f)
            val body = RectF(cx - 3.2f * u, cy - 11f * u, cx + 3.2f * u, cy + 6f * u)
            canvas.drawRoundRect(body, 1.6f * u, 1.6f * u, p)
            val tip = Path().apply {
                moveTo(cx - 3.2f * u, cy + 6.5f * u)
                lineTo(cx + 3.2f * u, cy + 6.5f * u)
                lineTo(cx, cy + 11.5f * u)
                close()
            }
            p.color = color or (0xFF shl 24)
            canvas.drawPath(tip, p)
            canvas.restore()
            // The ink colour's dot.
            p.color = color or (0xFF shl 24)
            canvas.drawCircle(cx + 9f * u, cy + 9f * u, 3.4f * u, p)
            p.style = Paint.Style.STROKE
            p.strokeWidth = 1.5f * u
            p.color = surface or (0xFF shl 24)
            canvas.drawCircle(cx + 9f * u, cy + 9f * u, 3.4f * u, p)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Toolbar
    // ─────────────────────────────────────────────────────────────────────────────

    enum class Glyph { MOVE, PEN, HIGHLIGHTER, ERASER, LASER, INTERACT, UNDO, CLEAR, COLOR, THICKNESS, MINIMIZE, CLOSE, SWATCH }

    @SuppressLint("ViewConstructor")
    private inner class ToolButton(context: Context, val glyph: Glyph, val swatch: Int = 0) : View(context) {
        private val p = Paint(Paint.ANTI_ALIAS_FLAG)
        var isOn = false
        var enabledLook = true

        init {
            val s = dp(48f).toInt()
            layoutParams = LinearLayout.LayoutParams(s, s)
            isClickable = true
            isFocusable = false
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }

        override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
            val s = dp(48f).toInt()
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
                p.color = withAlpha(accent, 0.28f)
                canvas.drawRoundRect(RectF(4 * u, 4 * u, w - 4 * u, h - 4 * u), 12 * u, 12 * u, p)
            }
            val ink = when {
                !enabledLook -> withAlpha(Color.WHITE, 0.35f)
                isOn -> Color.WHITE
                else -> withAlpha(Color.WHITE, 0.78f)
            }
            p.color = ink
            p.style = Paint.Style.STROKE
            p.strokeWidth = 2.2f * u
            p.strokeCap = Paint.Cap.ROUND
            p.strokeJoin = Paint.Join.ROUND
            when (glyph) {
                Glyph.MOVE -> {
                    p.style = Paint.Style.FILL
                    for (dx in intArrayOf(-1, 1)) for (dy in intArrayOf(-1, 0, 1)) {
                        canvas.drawCircle(cx + dx * 4 * u, cy + dy * 6 * u, 1.8f * u, p)
                    }
                }
                Glyph.PEN -> {
                    canvas.save()
                    canvas.rotate(-45f, cx, cy)
                    canvas.drawRoundRect(RectF(cx - 3 * u, cy - 10 * u, cx + 3 * u, cy + 5 * u), 1.5f * u, 1.5f * u, p)
                    val tip = Path().apply { moveTo(cx - 3 * u, cy + 5 * u); lineTo(cx, cy + 10 * u); lineTo(cx + 3 * u, cy + 5 * u) }
                    canvas.drawPath(tip, p)
                    canvas.restore()
                }
                Glyph.HIGHLIGHTER -> {
                    p.strokeWidth = 7 * u
                    p.strokeCap = Paint.Cap.BUTT
                    p.color = withAlpha(color, 0.55f)
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
                    canvas.drawRoundRect(RectF(cx - 7 * u, cy - 6 * u, cx + 7 * u, cy + 10 * u), 2 * u, 2 * u, p)
                    canvas.drawLine(cx - 10 * u, cy - 9 * u, cx + 10 * u, cy - 9 * u, p)
                    canvas.drawLine(cx - 3 * u, cy - 12 * u, cx + 3 * u, cy - 12 * u, p)
                    canvas.drawLine(cx - 2.5f * u, cy - 2 * u, cx - 2.5f * u, cy + 6 * u, p)
                    canvas.drawLine(cx + 2.5f * u, cy - 2 * u, cx + 2.5f * u, cy + 6 * u, p)
                }
                Glyph.COLOR -> {
                    p.style = Paint.Style.FILL
                    p.color = color or (0xFF shl 24)
                    canvas.drawCircle(cx, cy, 9 * u, p)
                    p.style = Paint.Style.STROKE
                    p.color = withAlpha(Color.WHITE, 0.9f)
                    canvas.drawCircle(cx, cy, 10.5f * u, p)
                }
                Glyph.THICKNESS -> {
                    p.style = Paint.Style.FILL
                    canvas.drawCircle(cx, cy, (2.5f + thickness * 2.8f) * u, p)
                }
                Glyph.MINIMIZE -> {
                    // Into the bubble: a small circle with a down-right arrow.
                    canvas.drawCircle(cx + 4 * u, cy + 4 * u, 5 * u, p)
                    canvas.drawLine(cx - 9 * u, cy - 9 * u, cx - 1 * u, cy - 1 * u, p)
                    canvas.drawLine(cx - 1 * u, cy - 1 * u, cx - 6 * u, cy - 1 * u, p)
                    canvas.drawLine(cx - 1 * u, cy - 1 * u, cx - 1 * u, cy - 6 * u, p)
                }
                Glyph.CLOSE -> {
                    canvas.drawLine(cx - 7 * u, cy - 7 * u, cx + 7 * u, cy + 7 * u, p)
                    canvas.drawLine(cx + 7 * u, cy - 7 * u, cx - 7 * u, cy + 7 * u, p)
                }
                Glyph.SWATCH -> {
                    p.style = Paint.Style.FILL
                    p.color = swatch or (0xFF shl 24)
                    val sel = swatch == color
                    val r = if (sel) 10 * u else 9 * u
                    canvas.drawCircle(cx, cy, r, p)
                    p.style = Paint.Style.STROKE
                    p.strokeWidth = (if (sel) 2.4f else 1.2f) * u
                    p.color = if (sel) Color.WHITE else withAlpha(Color.WHITE, 0.3f)
                    canvas.drawCircle(cx, cy, r + (if (sel) 2.5f else 0f) * u, p)
                }
            }
        }
    }

    @SuppressLint("ViewConstructor")
    private inner class Toolbar(context: Context) : LinearLayout(context) {
        init {
            orientation = VERTICAL
            val pad = dp(6f).toInt()
            setPadding(pad, pad, pad, pad)
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(20f)
                setColor(surface or (0xF2 shl 24))
                setStroke(dp(1f).toInt(), withAlpha(Color.WHITE, 0.14f))
            }
            elevation = dp(10f)
            layoutDirection = if (rtl) LAYOUT_DIRECTION_RTL else LAYOUT_DIRECTION_LTR
            rebuild()
            if (!reduceMotion()) {
                alpha = 0f
                scaleX = 0.94f
                scaleY = 0.94f
                animate().alpha(1f).scaleX(1f).scaleY(1f).setDuration(160).setInterpolator(DecelerateInterpolator()).start()
            }
        }

        private fun row(): LinearLayout = LinearLayout(context).apply { orientation = HORIZONTAL }

        private fun divider(): View = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(dp(1f).toInt(), dp(28f).toInt()).apply {
                gravity = Gravity.CENTER_VERTICAL
                marginStart = dp(4f).toInt()
                marginEnd = dp(4f).toInt()
            }
            setBackgroundColor(withAlpha(Color.WHITE, 0.14f))
        }

        @SuppressLint("ClickableViewAccessibility")
        fun rebuild() {
            removeAllViews()
            background?.let { (it as? android.graphics.drawable.GradientDrawable)?.setColor(surface or (0xF2 shl 24)) }
            layoutDirection = if (rtl) LAYOUT_DIRECTION_RTL else LAYOUT_DIRECTION_LTR

            val r1 = row()
            r1.addView(grip())
            r1.addView(toolButton(Glyph.PEN, Tool.PEN, label("pen", "Pen")))
            r1.addView(toolButton(Glyph.HIGHLIGHTER, Tool.HIGHLIGHTER, label("highlighter", "Highlighter")))
            r1.addView(toolButton(Glyph.ERASER, Tool.ERASER, label("eraser", "Eraser")))
            r1.addView(toolButton(Glyph.LASER, Tool.LASER, label("laser", "Laser pointer")))
            r1.addView(button(Glyph.INTERACT, label("interact", "Use apps (drawing off)"), selected = passThrough) {
                setPassThrough(!passThrough)
            })
            addView(r1)

            val r2 = row()
            r2.addView(button(Glyph.COLOR, label("color", "Colour"), selected = swatchesOpen) {
                swatchesOpen = !swatchesOpen
                rebuild()
                post { clampToolbar() }
            })
            r2.addView(button(Glyph.THICKNESS, "${label("thickness", "Thickness")} ${thickness + 1}/3") {
                thickness = (thickness + 1) % 3
                rebuild()
            })
            r2.addView(button(Glyph.UNDO, label("undo", "Undo"), enabled = strokes.isNotEmpty()) { undo() })
            r2.addView(button(Glyph.CLEAR, label("clear", "Clear all"), enabled = strokes.isNotEmpty()) { clear() })
            r2.addView(divider())
            r2.addView(button(Glyph.MINIMIZE, label("minimize", "Hide tools")) { hideTools() })
            r2.addView(button(Glyph.CLOSE, label("close", "Stop drawing and clear")) { closeTools() })
            addView(r2)

            if (swatchesOpen) {
                val r3 = row()
                for ((i, c) in colors.withIndex()) {
                    r3.addView(ToolButton(context, Glyph.SWATCH, c).apply {
                        contentDescription = "${label("color", "Colour")} ${i + 1}"
                        isOn = false
                        setOnClickListener {
                            color = c
                            swatchesOpen = false
                            if (tool == Tool.ERASER || tool == Tool.LASER) tool = Tool.PEN
                            selectTool(tool)
                            bubble?.invalidate()
                        }
                    })
                }
                addView(r3)
            }
        }

        private fun button(g: Glyph, desc: String, selected: Boolean = false, enabled: Boolean = true,
                           onTap: () -> Unit): ToolButton =
                ToolButton(context, g).apply {
                    contentDescription = desc
                    isOn = selected
                    enabledLook = enabled
                    isEnabled = enabled
                    setOnClickListener { onTap() }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) tooltipText = desc
                }

        private fun toolButton(g: Glyph, t: Tool, desc: String): ToolButton =
                button(g, desc, selected = !passThrough && tool == t) { selectTool(t) }

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
