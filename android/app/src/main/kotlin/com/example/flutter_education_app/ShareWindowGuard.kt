package com.example.flutter_education_app

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

/**
 * The presenter's own window while they share the WHOLE screen (D-081, lib/core/screen_security.dart).
 *
 * MediaProjection leaves out (draws black) every window that is FLAG_SECURE — on Android 15+ also every
 * window whose content is marked sensitive (View.setContentSensitivity). The app sets FLAG_SECURE for the
 * course video player and the exam screens (screen_protector); one left on, or one under the room, made
 * the app's own area black in the share while other apps showed. While a share runs this guard:
 *   - clears FLAG_SECURE when Dart says no protected screen is open (`clearSecure`), and
 *   - marks the Flutter view NOT_SENSITIVE (API 35+),
 * and on [end] puts back exactly what it changed (a FLAG_SECURE that something set again meanwhile — a
 * protected screen opened during the share — is left alone: protection wins).
 *
 * `com.example.flutter_education_app/share_window`:
 *   begin {clearSecure} → {wasSecure, sensitivity}   ·   end → null   ·   state → {secure, active}
 * Registered by AnnotationOverlayChannel.register (no MainActivity change). ScreenCaptureService calls
 * [onShareStopped] too, so the window is restored even when Dart is not running.
 */
class ShareWindowGuard private constructor(activity: Activity, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "ShareWindowGuard"
        const val CHANNEL = "com.example.flutter_education_app/share_window"

        @Volatile private var instance: ShareWindowGuard? = null

        fun register(activity: Activity, messenger: BinaryMessenger) {
            instance = ShareWindowGuard(activity, messenger)
        }

        /** The share ended natively (system Stop, task removed): restore the window. Any thread. */
        fun onShareStopped() {
            val g = instance ?: return
            g.main.post { g.end("share stopped") }
        }
    }

    private val activityRef = WeakReference(activity)
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, CHANNEL)

    private var active = false
    private var clearedSecure = false
    private var savedSensitivity: Int? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> result.success(begin(call.argument<Boolean>("clearSecure") ?: true))
                "end" -> {
                    end("dart")
                    result.success(null)
                }
                "state" -> result.success(mapOf("secure" to isSecure(), "active" to active))
                else -> result.notImplemented()
            }
        }
    }

    private fun isSecure(): Boolean {
        val w = activityRef.get()?.window ?: return false
        return (w.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0
    }

    private fun begin(clearSecure: Boolean): Map<String, Any?> {
        val a = activityRef.get() ?: return mapOf("ok" to false)
        val w = a.window
        val wasSecure = isSecure()
        if (!active) {
            active = true
            clearedSecure = false
            savedSensitivity = null
        }
        if (wasSecure && clearSecure) {
            w.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            clearedSecure = true
        }
        var sensitivity: Int? = null
        if (Build.VERSION.SDK_INT >= 35) {
            val v = flutterView(a)
            if (v != null) {
                sensitivity = v.contentSensitivity
                if (savedSensitivity == null) savedSensitivity = sensitivity
                if (sensitivity != View.CONTENT_SENSITIVITY_NOT_SENSITIVE) {
                    v.contentSensitivity = View.CONTENT_SENSITIVITY_NOT_SENSITIVE
                }
            }
        }
        // The evidence for a black app area in the share: was the window secure / sensitive when it began?
        Log.i(TAG, "share window: FLAG_SECURE was $wasSecure (cleared ${wasSecure && clearSecure}), " +
                "content sensitivity was $sensitivity")
        return mapOf("ok" to true, "wasSecure" to wasSecure, "sensitivity" to sensitivity)
    }

    private fun end(why: String) {
        if (!active) return
        active = false
        val a = activityRef.get()
        if (a != null) {
            if (clearedSecure && !isSecure()) {
                a.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
            }
            val s = savedSensitivity
            if (s != null && Build.VERSION.SDK_INT >= 35) {
                flutterView(a)?.let { if (it.contentSensitivity != s) it.contentSensitivity = s }
            }
        }
        Log.i(TAG, "share window restored ($why): FLAG_SECURE ${if (clearedSecure) "back on" else "unchanged"}")
        clearedSecure = false
        savedSensitivity = null
    }

    /** The FlutterView (the engine's SensitiveContent plugin sets ITS sensitivity), else the content root. */
    private fun flutterView(a: Activity): View? {
        val root = a.findViewById<View>(android.R.id.content) ?: return null
        return findFlutterView(root) ?: root
    }

    private fun findFlutterView(v: View): View? {
        if (v is io.flutter.embedding.android.FlutterView) return v
        if (v is android.view.ViewGroup) {
            for (i in 0 until v.childCount) findFlutterView(v.getChildAt(i))?.let { return it }
        }
        return null
    }
}
