package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// LiveCallService — the live room's microphone in the background
//
// Android 14+ cuts the microphone of an app in the background unless a
// foreground service of type "microphone" runs. ScreenCaptureService is one
// while a recording or a share runs; this service covers everyone else in a
// room (a student, a teacher who neither records nor shares): a small
// low-priority notification "In a live session" whose tap and "Leave" action
// only bring the app to the front (the room is never closed from here; "Leave"
// also tells Dart, which may ask the person to confirm).
//
// Dart (widgets/live_call_service.dart) says start / stop on CH_LIVE_CALL;
// whether it really runs follows ScreenCaptureService: while that one holds
// the microphone type (onCaptureForeground) this one stops, and comes back
// when it goes away. Started with startService (never startForegroundService)
// while the app is in front, so a refused startForeground just stops it, no
// "did not call startForeground" crash. A start refused in the background
// (the capture service ended while the person was in another app) is retried
// by MainActivity.onResume (sync).
// ─────────────────────────────────────────────────────────────────────────────

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class LiveCallService : Service() {

    companion object {
        private const val TAG = "LiveCallService"

        const val CH_LIVE_CALL = "com.example.flutter_education_app/live_call"
        private const val CHANNEL_ID = "live_call_channel"
        private const val NOTIFICATION_ID = 1002 // 1001 = ScreenCaptureService

        /** Extra on the activity intent of the notification's "Leave" action. */
        const val EXTRA_LIVE_CALL_ACTION = "liveCallAction"
        const val LIVE_CALL_LEAVE = "leave"

        /** Dart: the person is in a room with a microphone they may publish. */
        @Volatile var wanted = false
        /** ScreenCaptureService is in the foreground with the microphone type. */
        @Volatile private var captureHoldsMic = false
        /** startService was sent and no stop since. */
        @Volatile private var started = false
        /** startForeground succeeded. */
        @Volatile var isForeground = false
            private set

        // The notification's texts, in the app language (from Dart).
        @Volatile private var title = "In a live session"
        @Volatile private var text = "Your microphone keeps working in the background"
        @Volatile private var leaveLabel = "Leave"
        @Volatile private var channelName = "Live sessions"

        private var channel: MethodChannel? = null

        fun register(activity: Activity, messenger: BinaryMessenger) {
            channel = MethodChannel(messenger, CH_LIVE_CALL).also {
                it.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "start" -> {
                            call.argument<String>("title")?.let { v -> title = v }
                            call.argument<String>("text")?.let { v -> text = v }
                            call.argument<String>("leave")?.let { v -> leaveLabel = v }
                            call.argument<String>("channelName")?.let { v -> channelName = v }
                            wanted = true
                            result.success(sync(activity))
                        }
                        "stop" -> {
                            wanted = false
                            sync(activity)
                            result.success(null)
                        }
                        "isRunning" -> result.success(isForeground || captureHoldsMic)
                        else -> result.notImplemented()
                    }
                }
            }
        }

        /** ScreenCaptureService went foreground with the microphone type (true) or was destroyed (false). */
        fun onCaptureForeground(context: Context, holdsMic: Boolean) {
            if (captureHoldsMic == holdsMic) return
            captureHoldsMic = holdsMic
            sync(context)
        }

        /** The notification's "Leave": the app is in front again, Dart decides (a confirmation). */
        fun leaveRequested() {
            try {
                channel?.invokeMethod("leaveRequested", null)
            } catch (e: Exception) {
                Log.w(TAG, "leaveRequested not delivered: ${e.message}")
            }
        }

        /** The Activity is going away with its engine: no room can be left behind. */
        fun release(context: Context) {
            wanted = false
            sync(context)
        }

        /**
         * Brings the service to what is wanted. True when the room's mic is covered in the background
         * (this service or ScreenCaptureService), false when it could not start (no RECORD_AUDIO, the
         * app is in the background).
         */
        fun sync(context: Context): Boolean {
            val app = context.applicationContext
            val run = wanted && !captureHoldsMic
            if (!run) {
                if (started) {
                    started = false
                    try {
                        app.stopService(Intent(app, LiveCallService::class.java))
                    } catch (e: Exception) {
                        Log.w(TAG, "stop: ${e.message}")
                    }
                }
                return wanted && captureHoldsMic
            }
            if (app.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "RECORD_AUDIO not granted — no live-call service")
                return false
            }
            if (started && isForeground) return true
            return try {
                app.startService(Intent(app, LiveCallService::class.java))
                started = true
                true
            } catch (e: Exception) {
                // IllegalStateException: the app is in the background; MainActivity.onResume retries.
                Log.w(TAG, "start refused: ${e.message}")
                started = false
                false
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!wanted || captureHoldsMic) {
            Log.d(TAG, "not needed (wanted=$wanted, capture holds the mic=$captureHoldsMic)")
            started = false
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createNotificationChannel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                startForeground(NOTIFICATION_ID, buildNotification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            else
                startForeground(NOTIFICATION_ID, buildNotification())
            isForeground = true
            Log.d(TAG, "in the foreground (microphone)")
        } catch (e: Exception) {
            // While-in-use refused (started from the background) or no permission: nothing to keep.
            Log.w(TAG, "startForeground(microphone) refused: ${e.message}")
            isForeground = false
            started = false
            stopSelf()
        }
        // Not sticky: a restart after the process died has no room to serve.
        return START_NOT_STICKY
    }

    // The app was swiped away: the room goes with the engine.
    override fun onTaskRemoved(rootIntent: Intent?) {
        wanted = false
        started = false
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        isForeground = false
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            getSystemService(NotificationManager::class.java)
                    .createNotificationChannel(NotificationChannel(
                            CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_LOW).apply {
                        setShowBadge(false)
                    })
    }

    /** The app's task to the front (MainActivity is singleTop: the running room, no new instance). */
    private fun openApp(requestCode: Int, leave: Boolean): PendingIntent {
        val i = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (leave) putExtra(EXTRA_LIVE_CALL_ACTION, LIVE_CALL_LEAVE)
        }
        return PendingIntent.getActivity(this, requestCode, i,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun buildNotification(): Notification =
            NotificationCompat.Builder(this, CHANNEL_ID)
                    .setContentTitle(title)
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                    .setPriority(NotificationCompat.PRIORITY_LOW)
                    .setCategory(NotificationCompat.CATEGORY_CALL)
                    .setOngoing(true)
                    .setContentIntent(openApp(0, leave = false))
                    .addAction(0, leaveLabel, openApp(1, leave = true))
                    .build()
}
