package com.doubley.alfaheem

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * `com.doubley.alfaheem/annotation_overlay` (android_overlay.dart): arm / disarm the
 * whole-screen annotation overlay ([AnnotationOverlay]) and its "Display over other apps" permission.
 *
 *   isPermitted        → Settings.canDrawOverlays
 *   requestPermission  → opens Settings.ACTION_MANAGE_OVERLAY_PERMISSION for this app; answers when the
 *                        person comes back to the activity (re-checked twice: on some Android 8 builds the
 *                        app-op lands a moment after the return)
 *   openSettings       → the same page, without waiting (the in-app "Allow" banner)
 *   show {colors, color, thickness, labels, surface?, accent?, rtl?}  → arms the overlay for this share
 *   hide · isShowing (armed)
 *   native → Dart: `closed` (the overlay could not be shown any more, e.g. the permission was revoked)
 *
 * D-083: an armed overlay is visible only while the app is NOT in front (stopped, or in picture-in-
 * picture): a floating "annotate" bubble over the other apps. In the app nothing is drawn over it. The
 * activity's start / stop tell the overlay. It is disarmed when the share stops — by Dart, and natively by
 * ScreenCaptureService ([onShareStopped]) — and when the activity is finally destroyed.
 *
 * MainActivity registers it with ONE line in configureFlutterEngine; it also registers ShareWindowGuard
 * (the presenter's window while sharing).
 */
class AnnotationOverlayChannel private constructor(private val activity: Activity, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "AnnotationOverlay"
        const val CHANNEL = "com.doubley.alfaheem/annotation_overlay"

        @Volatile private var instance: AnnotationOverlayChannel? = null

        fun register(activity: Activity, messenger: BinaryMessenger): AnnotationOverlayChannel {
            ShareWindowGuard.register(activity, messenger)
            return AnnotationOverlayChannel(activity, messenger).also { instance = it }
        }

        /** The share ended natively (system Stop, task removed): the bubble goes with it. Any thread. */
        fun onShareStopped() {
            val c = instance ?: return
            c.main.post { c.overlay?.hide() }
        }
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private var overlay: AnnotationOverlay? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var awaitingReturn = false

    // The activity is started (visible): the configureFlutterEngine that registers us runs in onCreate,
    // before the first onStart, so "started" is the right default.
    private var started = true

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityStarted(a: Activity) {
            if (a !== activity) return
            started = true
            syncFront()
        }
        override fun onActivityStopped(a: Activity) {
            if (a !== activity) return
            started = false
            syncFront()
        }
        override fun onActivityResumed(a: Activity) {
            if (a !== activity) return
            syncFront() // leaving picture-in-picture
            if (!awaitingReturn) return
            awaitingReturn = false
            checkPermissionSoon(0)
        }
        override fun onActivityPaused(a: Activity) {
            if (a === activity) syncFront() // entering picture-in-picture
        }
        override fun onActivityDestroyed(a: Activity) {
            if (a !== activity) return
            if (a.isFinishing) {
                overlay?.hide()
                overlay = null
            }
            replyPermission(permitted())
            a.application.unregisterActivityLifecycleCallbacks(this)
            if (instance === this@AnnotationOverlayChannel) instance = null
        }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
    }

    init {
        activity.application.registerActivityLifecycleCallbacks(lifecycle)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isPermitted" -> result.success(permitted())
                    "requestPermission" -> requestPermission(result)
                    "openSettings" -> result.success(openSettings())
                    "isShowing" -> result.success(overlay?.isShowing == true)
                    "show" -> {
                        if (!permitted()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val o = overlay ?: AnnotationOverlay(activity) {
                            channel.invokeMethod("closed", null)
                        }.also { overlay = it }
                        call.argument<List<Number>>("colors")?.takeIf { it.isNotEmpty() }?.let { list ->
                            o.colors = IntArray(list.size) { list[it].toLong().toInt() }
                        }
                        call.argument<Number>("color")?.let { o.color = it.toLong().toInt() }
                        call.argument<Int>("thickness")?.let { o.thickness = it.coerceIn(0, 2) }
                        call.argument<Number>("surface")?.let { o.surface = it.toLong().toInt() }
                        call.argument<Number>("accent")?.let { o.accent = it.toLong().toInt() }
                        call.argument<Boolean>("rtl")?.let { o.rtl = it }
                        call.argument<Map<String, String>>("labels")?.let { o.labels = it }
                        o.setAppInFront(inFront())
                        result.success(o.show())
                    }
                    "hide" -> {
                        overlay?.hide()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.w(TAG, "${call.method} failed: ${e.message}")
                result.success(false)
            }
        }
    }

    private fun inFront(): Boolean {
        val pip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && activity.isInPictureInPictureMode
        return started && !pip
    }

    private fun syncFront() {
        overlay?.setAppInFront(inFront())
    }

    private fun permitted(): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(activity)

    private fun openSettings(): Boolean {
        return try {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}")))
            true
        } catch (e: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
                true
            } catch (e2: Exception) {
                Log.w(TAG, "overlay settings page: ${e2.message}")
                false
            }
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (permitted()) {
            result.success(true)
            return
        }
        // A second request while the first waits: the first gets its answer now, from the same check.
        replyPermission(false)
        pendingPermission = result
        awaitingReturn = true
        if (!openSettings()) {
            awaitingReturn = false
            replyPermission(false)
        }
    }

    private fun checkPermissionSoon(attempt: Int) {
        if (permitted() || attempt >= 2) {
            replyPermission(permitted())
            return
        }
        main.postDelayed({ checkPermissionSoon(attempt + 1) }, if (attempt == 0) 300L else 1000L)
    }

    private fun replyPermission(ok: Boolean) {
        val r = pendingPermission ?: return
        pendingPermission = null
        runCatching { r.success(ok) }
    }
}
