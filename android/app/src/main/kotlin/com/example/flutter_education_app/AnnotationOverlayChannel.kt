package com.example.flutter_education_app

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
 * `com.example.flutter_education_app/annotation_overlay` (android_overlay.dart): show / hide the
 * whole-screen annotation overlay ([AnnotationOverlay]) and its "Display over other apps" permission.
 *
 *   isPermitted        → Settings.canDrawOverlays
 *   requestPermission  → opens Settings.ACTION_MANAGE_OVERLAY_PERMISSION for this app; answers when the
 *                        person comes back to the activity (re-checked twice: on some Android 8 builds the
 *                        app-op lands a moment after the return)
 *   show {colors, color, thickness, labels, surface?, accent?, rtl?}  → adds the windows
 *   hide · isShowing
 *   native → Dart: `closed` (the overlay's own close button)
 *
 * MainActivity registers it with ONE line in configureFlutterEngine. It hides the overlay when the
 * activity is finally destroyed, so a window never outlives the app.
 */
class AnnotationOverlayChannel private constructor(private val activity: Activity, messenger: BinaryMessenger) {

    companion object {
        private const val TAG = "AnnotationOverlay"
        const val CHANNEL = "com.example.flutter_education_app/annotation_overlay"

        fun register(activity: Activity, messenger: BinaryMessenger): AnnotationOverlayChannel =
                AnnotationOverlayChannel(activity, messenger)
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private var overlay: AnnotationOverlay? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var awaitingReturn = false

    private val lifecycle = object : Application.ActivityLifecycleCallbacks {
        override fun onActivityResumed(a: Activity) {
            if (a !== activity || !awaitingReturn) return
            awaitingReturn = false
            checkPermissionSoon(0)
        }
        override fun onActivityDestroyed(a: Activity) {
            if (a !== activity) return
            if (a.isFinishing) {
                overlay?.hide()
                overlay = null
            }
            replyPermission(permitted())
            a.application.unregisterActivityLifecycleCallbacks(this)
        }
        override fun onActivityCreated(a: Activity, b: Bundle?) {}
        override fun onActivityStarted(a: Activity) {}
        override fun onActivityPaused(a: Activity) {}
        override fun onActivityStopped(a: Activity) {}
        override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
    }

    init {
        activity.application.registerActivityLifecycleCallbacks(lifecycle)
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "isPermitted" -> result.success(permitted())
                    "requestPermission" -> requestPermission(result)
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

    private fun permitted(): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(activity)

    private fun requestPermission(result: MethodChannel.Result) {
        if (permitted()) {
            result.success(true)
            return
        }
        // A second request while the first waits: the first gets its answer now, from the same check.
        replyPermission(false)
        pendingPermission = result
        try {
            val i = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${activity.packageName}"))
            awaitingReturn = true
            activity.startActivity(i)
        } catch (e: Exception) {
            Log.w(TAG, "overlay settings page: ${e.message}")
            awaitingReturn = false
            try {
                // Some builds have no per-app page: the list of every app.
                awaitingReturn = true
                activity.startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION))
            } catch (e2: Exception) {
                awaitingReturn = false
                replyPermission(false)
            }
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
