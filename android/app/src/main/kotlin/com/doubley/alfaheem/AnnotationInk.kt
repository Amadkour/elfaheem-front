package com.doubley.alfaheem

import android.graphics.Path
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The ink of the whole-screen overlay: the same rules as lib/.../annotation/annotation_ink.dart (D-083),
 * so a stroke drawn over other apps looks like one drawn in the room. Keep the two in step.
 *
 *  - [Filter]: a 2-D One Euro filter (one speed for both axes) on the pen's position, the pressure through
 *    an exponential average with a step limit, samples closer than minDistance dropped, the real last
 *    position added when the pen lifts.
 *  - [Stroke]: the centre line is the chain of quadratic pieces through the midpoints; a pressure stroke is
 *    ONE filled shape (circles + bands along the densely sampled centre line, all clockwise, non-zero
 *    fill) with causally averaged radii and tapered ends; finished pieces are cached and only the tail is
 *    rebuilt while the stroke grows. A stroke without pressure / the highlighter is one stroked path.
 */
object AnnotationInk {
    const val MIN_CUTOFF = 1.0
    const val BETA = 0.025
    const val D_CUTOFF = 1.0
    const val PRESSURE_ALPHA = 0.35f
    const val MAX_PRESSURE_STEP = 0.08f
    const val RADIUS_ALPHA = 0.45f
    const val TAPER_WIDTHS = 2.5f
    const val TAPER_MIN = 0.3f
    const val MAX_POINTS = 20000

    fun pressureFactor(p: Float): Float = 0.55f + 0.9f * p.coerceIn(0f, 1f)

    private fun alpha(cutoff: Double, dt: Double): Double {
        val tau = 1.0 / (2 * PI * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    class Sample(val x: Float, val y: Float, val p: Float)

    /** One stroke's input filter (px, seconds, pressure 0..1). */
    class Filter(private val minDistance: Float, private val pressure: Boolean) {
        private var fx = 0.0
        private var fy = 0.0
        private var ft = 0.0
        private var speed = 0.0
        private var p = 0.5f
        private var last: Sample? = null
        private var started = false

        fun start(x: Float, y: Float, t: Double, rawP: Float): Sample {
            fx = x.toDouble(); fy = y.toDouble(); ft = t; speed = 0.0
            p = if (pressure) rawP.coerceIn(0f, 1f) else 0.5f
            started = true
            return Sample(x, y, p).also { last = it }
        }

        fun add(x: Float, y: Float, t: Double, rawP: Float): Sample? {
            if (!started) return start(x, y, t, rawP)
            var dt = t - ft
            if (!(dt > 0) || dt > 1) dt = 1.0 / 120
            val v = hypot(x - fx, y - fy) / dt
            speed += alpha(D_CUTOFF, dt) * (v - speed)
            val a = alpha(MIN_CUTOFF + BETA * speed, dt)
            fx += a * (x - fx)
            fy += a * (y - fy)
            ft = t
            if (pressure) {
                val target = p + PRESSURE_ALPHA * (rawP.coerceIn(0f, 1f) - p)
                p += (target - p).coerceIn(-MAX_PRESSURE_STEP, MAX_PRESSURE_STEP)
            }
            val l = last ?: return null
            if (hypot(l.x - fx, l.y - fy) < minDistance) return null
            return Sample(fx.toFloat(), fy.toFloat(), p).also { last = it }
        }

        fun finish(x: Float, y: Float): Sample? {
            val l = last ?: return null
            if (hypot(l.x - x, l.y - y) < max(minDistance, 0.5f)) return null
            return Sample(x, y, p).also { last = it }
        }
    }

    class Stroke(val highlighter: Boolean, val color: Int, val widthPx: Float, val pressured: Boolean) {
        val xs = ArrayList<Float>()
        val ys = ArrayList<Float>()
        val ps = ArrayList<Float>()
        private val radii = ArrayList<Float>()
        var open = true

        // Caches.
        private var stroked: Path? = null
        private var strokedCount = -1
        private var committed = Path()
        private var pieces = 0
        private var arc = 0f
        var tail: Path? = null
            private set
        private var builtCount = -1
        private var builtOpen = true

        val size get() = xs.size

        fun add(s: Sample) {
            if (xs.size >= MAX_POINTS) return
            if (xs.isNotEmpty() && xs.last() == s.x && ys.last() == s.y) return
            xs.add(s.x); ys.add(s.y); ps.add(s.p)
            val target = widthPx / 2f * pressureFactor(s.p)
            radii.add(if (radii.isEmpty()) target else radii.last() + RADIUS_ALPHA * (target - radii.last()))
        }

        /** Constant width: the midpoint chain to stroke. */
        fun strokedPath(): Path {
            stroked?.let { if (strokedCount == size) return it }
            val p = Path()
            if (size > 0) {
                p.moveTo(xs[0], ys[0])
                if (size == 2) p.lineTo(xs[1], ys[1])
                else if (size > 2) {
                    for (i in 1 until size - 1) p.quadTo(xs[i], ys[i], (xs[i] + xs[i + 1]) / 2f, (ys[i] + ys[i + 1]) / 2f)
                    p.lineTo(xs[size - 1], ys[size - 1])
                }
            }
            stroked = p
            strokedCount = size
            return p
        }

        /** Pressure: the shape (the finished pieces; [tail] holds the last piece while open). */
        fun shape(): Path {
            if (builtCount == size && builtOpen == open) return committed
            val n = size
            val spacing = (widthPx * 0.3f).coerceIn(0.5f, 3f)
            if (!open) {
                val nodes = centerline(spacing, 1, n - 1)
                taper(nodes, 0f, true)
                committed = Path()
                append(committed, nodes)
                tail = null
            } else {
                val finalPieces = n - 2
                if (finalPieces > pieces) {
                    val nodes = centerline(spacing, pieces + 1, finalPieces)
                    val startArc = arc
                    arc += arcOf(nodes)
                    taper(nodes, startArc, false)
                    append(committed, nodes)
                    pieces = finalPieces
                }
                val tn = centerline(spacing, max(1, n - 1), n - 1)
                taper(tn, arc, false)
                tail = Path().also { append(it, tn) }
            }
            builtCount = n
            builtOpen = open
            return committed
        }

        // Nodes as a flat list x, y, r.
        private fun centerline(spacing: Float, fromPiece: Int, toPiece: Int): FloatArrayList {
            val n = size
            val out = FloatArrayList()
            if (n == 0) return out
            if (n == 1) { out.add(xs[0], ys[0], radii[0]); return out }
            val from = max(1, fromPiece)
            val to = min(toPiece, n - 1)
            for (i in from..to) {
                val ax = if (i == 1) xs[0] else (xs[i - 1] + xs[i]) / 2f
                val ay = if (i == 1) ys[0] else (ys[i - 1] + ys[i]) / 2f
                val ra = if (i == 1) radii[0] else (radii[i - 1] + radii[i]) / 2f
                val bx = if (i == n - 1) xs[n - 1] else (xs[i] + xs[i + 1]) / 2f
                val by = if (i == n - 1) ys[n - 1] else (ys[i] + ys[i + 1]) / 2f
                val rb = if (i == n - 1) radii[n - 1] else (radii[i] + radii[i + 1]) / 2f
                val cx = if (n == 2) (ax + bx) / 2f else xs[i]
                val cy = if (n == 2) (ay + by) / 2f else ys[i]
                val len = hypot(cx - ax, cy - ay) + hypot(bx - cx, by - cy)
                val steps = max(1, ceil(len / max(0.25f, spacing)).toInt())
                for (k in (if (i == from) 0 else 1)..steps) {
                    val t = k.toFloat() / steps
                    val u = 1 - t
                    out.add(u * u * ax + 2 * u * t * cx + t * t * bx, u * u * ay + 2 * u * t * cy + t * t * by, ra + (rb - ra) * t)
                }
            }
            return out
        }

        private fun arcOf(nodes: FloatArrayList): Float {
            var s = 0f
            for (i in 1 until nodes.count) s += hypot(nodes.x(i) - nodes.x(i - 1), nodes.y(i) - nodes.y(i - 1))
            return s
        }

        private fun taperAt(s: Float): Float {
            val len = max(1f, widthPx * TAPER_WIDTHS)
            if (s >= len) return 1f
            val t = (s / len).coerceIn(0f, 1f)
            val e = 1 - (1 - t) * (1 - t)
            return TAPER_MIN + (1 - TAPER_MIN) * e
        }

        private fun taper(nodes: FloatArrayList, startArc: Float, end: Boolean) {
            if (nodes.count == 0) return
            val arcs = FloatArray(nodes.count)
            var s = startArc
            for (i in 0 until nodes.count) {
                if (i > 0) s += hypot(nodes.x(i) - nodes.x(i - 1), nodes.y(i) - nodes.y(i - 1))
                arcs[i] = s
            }
            for (i in 0 until nodes.count) {
                nodes.setR(i, nodes.r(i) * taperAt(arcs[i]) * (if (end) taperAt(s - arcs[i]) else 1f))
            }
        }

        private fun append(path: Path, nodes: FloatArrayList) {
            for (i in 0 until nodes.count) {
                val bx = nodes.x(i); val by = nodes.y(i); val br = nodes.r(i)
                if (br <= 0f) continue
                path.addCircle(bx, by, br, Path.Direction.CW)
                if (i == 0) continue
                val ax = nodes.x(i - 1); val ay = nodes.y(i - 1); val ar = nodes.r(i - 1)
                val dx = bx - ax; val dy = by - ay
                val len = hypot(dx, dy)
                if (len < 1e-4f) continue
                val nx = -dy / len; val ny = dx / len
                // The band between the two circles, clockwise as seen (y down) like the circles.
                val x0 = ax + nx * ar; val y0 = ay + ny * ar
                val x1 = bx + nx * br; val y1 = by + ny * br
                val x2 = bx - nx * br; val y2 = by - ny * br
                val x3 = ax - nx * ar; val y3 = ay - ny * ar
                val area = (x0 * y1 - x1 * y0) + (x1 * y2 - x2 * y1) + (x2 * y3 - x3 * y2) + (x3 * y0 - x0 * y3)
                if (area >= 0) {
                    path.moveTo(x0, y0); path.lineTo(x1, y1); path.lineTo(x2, y2); path.lineTo(x3, y3)
                } else {
                    path.moveTo(x3, y3); path.lineTo(x2, y2); path.lineTo(x1, y1); path.lineTo(x0, y0)
                }
                path.close()
            }
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

        /** Width of a one-point stroke (a dot). */
        fun dotRadius(): Float = if (pressured) widthPx / 2f * pressureFactor(ps[0]) else widthPx / 2f

        val hasPressureVariation get() = pressured && ps.any { abs(it - 0.5f) > 0.02f }
    }

    /** A growable list of (x, y, r) triples without boxing. */
    class FloatArrayList {
        private var a = FloatArray(96)
        var count = 0
            private set

        fun add(x: Float, y: Float, r: Float) {
            if ((count + 1) * 3 > a.size) a = a.copyOf(a.size * 2)
            a[count * 3] = x; a[count * 3 + 1] = y; a[count * 3 + 2] = r
            count++
        }

        fun x(i: Int) = a[i * 3]
        fun y(i: Int) = a[i * 3 + 1]
        fun r(i: Int) = a[i * 3 + 2]
        fun setR(i: Int, r: Float) { a[i * 3 + 2] = r }
    }
}
