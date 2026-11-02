package com.example.flutter_education_app

// ─────────────────────────────────────────────────────────────────────────────
// VodMediaService — a course lecture playing as sound (the listen bar, D-104)
//
// The lecture plays in video_player's ExoPlayer (allowBackgroundPlayback, audio focus handled there). Without a
// foreground service Android treats the app as idle once it is in the background: Doze / App Standby cut its
// network after a while (the stream stalls with the screen off) and Samsung's battery manager may kill it. This
// service is the "mediaPlayback" foreground service for the whole listen session (playing or paused):
//   * a media notification (Notification.MediaStyle + a framework MediaSession, no extra library) with
//     −10 s · play / pause · +10 s · close, a seek line, title — also on the lock screen and in quick settings;
//   * a partial wake lock + a Wi-Fi lock while the sound plays, so the stream keeps loading with the screen off;
//   * headset / Bluetooth buttons and the notification's actions come back to Dart as "command" on CH_VOD_MEDIA.
// Dart (vod_media_controls.dart) says start / update / stop. Started with startService while the app is in front
// (the bar always starts from the player page), so a refused startForeground just stops it.
// ─────────────────────────────────────────────────────────────────────────────

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class VodMediaService : Service() {

    companion object {
        private const val TAG = "VodMediaService"

        const val CH_VOD_MEDIA = "com.example.flutter_education_app/vod_media"
        private const val CHANNEL_ID = "vod_listen_channel"
        private const val NOTIFICATION_ID = 1003 // 1001 ScreenCaptureService, 1002 LiveCallService

        private const val ACTION_CMD = "com.example.flutter_education_app.VOD_CMD"
        private const val EXTRA_CMD = "cmd"

        // What Dart last said (read by the service on every refresh).
        @Volatile private var wanted = false
        @Volatile private var title = ""
        @Volatile private var subtitle = ""
        @Volatile private var playing = false
        @Volatile private var positionMs = 0L
        @Volatile private var durationMs = 0L
        @Volatile private var speed = 1.0f
        @Volatile private var channelName = "Lectures"
        @Volatile private var labels = mapOf(
                "play" to "Play", "pause" to "Pause", "back" to "Back 10 s", "forward" to "Forward 10 s", "close" to "Close")

        @Volatile private var instance: VodMediaService? = null
        private var channel: MethodChannel? = null
        private val main = Handler(Looper.getMainLooper())

        fun register(context: Context, messenger: BinaryMessenger) {
            val app = context.applicationContext
            channel = MethodChannel(messenger, CH_VOD_MEDIA).also {
                it.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "start", "update" -> {
                            call.argument<String>("title")?.let { v -> title = v }
                            call.argument<String>("subtitle")?.let { v -> subtitle = v }
                            call.argument<Boolean>("playing")?.let { v -> playing = v }
                            call.argument<Number>("position")?.let { v -> positionMs = v.toLong() }
                            call.argument<Number>("duration")?.let { v -> durationMs = v.toLong() }
                            call.argument<Number>("speed")?.let { v -> speed = v.toFloat() }
                            call.argument<String>("channelName")?.let { v -> channelName = v }
                            call.argument<Map<String, String>>("labels")?.let { v -> labels = labels + v }
                            if (call.method == "start") {
                                wanted = true
                                result.success(startService(app))
                            } else {
                                instance?.refresh()
                                result.success(instance != null)
                            }
                        }
                        "stop" -> {
                            stop(app)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        }

        private fun startService(app: Context): Boolean {
            instance?.let {
                it.refresh()
                return true
            }
            return try {
                app.startService(Intent(app, VodMediaService::class.java))
                true
            } catch (e: Exception) {
                // IllegalStateException: started from the background — the sound still plays, without the service.
                Log.w(TAG, "start refused: ${e.message}")
                false
            }
        }

        /** The listen session ended (closed, back to the video, signed out) or the Activity went away. */
        fun stop(context: Context) {
            wanted = false
            try {
                context.applicationContext.stopService(Intent(context.applicationContext, VodMediaService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stop: ${e.message}")
            }
        }

        private fun send(cmd: String, arg: Long? = null) {
            main.post {
                try {
                    channel?.invokeMethod("command", if (arg == null) mapOf("cmd" to cmd) else mapOf("cmd" to cmd, "ms" to arg))
                } catch (e: Exception) {
                    Log.w(TAG, "command $cmd not delivered: ${e.message}")
                }
            }
        }
    }

    private var session: MediaSession? = null
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        session = MediaSession(this, "vod_listen").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() = send("play")
                override fun onPause() = send("pause")
                override fun onStop() = send("stop")
                override fun onSeekTo(pos: Long) = send("seek", pos)
                override fun onFastForward() = send("forward")
                override fun onRewind() = send("back")
                override fun onSkipToNext() = send("forward")
                override fun onSkipToPrevious() = send("back")
            })
            setSessionActivity(openApp())
            isActive = true
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CMD) {
            when (val cmd = intent.getStringExtra(EXTRA_CMD)) {
                "toggle" -> send(if (playing) "pause" else "play")
                null -> {}
                else -> send(cmd)
            }
            return START_NOT_STICKY
        }
        if (!wanted) {
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            createNotificationChannel()
            val n = buildNotification()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else
                startForeground(NOTIFICATION_ID, n)
            Log.d(TAG, "in the foreground (mediaPlayback)")
            refresh()
        } catch (e: Exception) {
            Log.w(TAG, "startForeground(mediaPlayback) refused: ${e.message}")
            stopSelf()
        }
        // Not sticky: after the process died there is no lecture to serve.
        return START_NOT_STICKY
    }

    /** Session state, notification and locks from what Dart last said. */
    fun refresh() {
        main.post {
            val s = session ?: return@post
            s.setMetadata(MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
                    .build())
            s.setPlaybackState(PlaybackState.Builder()
                    .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
                            PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND or
                            PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
                            PlaybackState.ACTION_STOP)
                    .setState(if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                            positionMs, if (playing) speed else 0f, SystemClock.elapsedRealtime())
                    .build())
            try {
                getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification())
            } catch (e: Exception) {
                Log.w(TAG, "notify: ${e.message}")
            }
            holdLocks(playing)
        }
    }

    @SuppressLint("WakelockTimeout")
    private fun holdLocks(on: Boolean) {
        if (on) {
            if (wake == null) {
                wake = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "elfaheem:vod_listen").apply {
                            setReferenceCounted(false)
                        }
            }
            if (wake?.isHeld == false) wake?.acquire()
            if (wifi == null) {
                @Suppress("DEPRECATION")
                val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                    WifiManager.WIFI_MODE_FULL_LOW_LATENCY else WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifi = (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                        .createWifiLock(mode, "elfaheem:vod_listen").apply { setReferenceCounted(false) }
            }
            if (wifi?.isHeld == false) wifi?.acquire()
        } else {
            if (wake?.isHeld == true) wake?.release()
            if (wifi?.isHeld == true) wifi?.release()
        }
    }

    // The app was swiped away: the lecture goes with the engine.
    override fun onTaskRemoved(rootIntent: Intent?) {
        wanted = false
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        instance = null
        holdLocks(false)
        session?.isActive = false
        session?.release()
        session = null
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
                        setSound(null, null)
                    })
    }

    private fun openApp(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun command(cmd: String, requestCode: Int): PendingIntent {
        val i = Intent(this, VodMediaService::class.java).apply {
            action = ACTION_CMD
            putExtra(EXTRA_CMD, cmd)
        }
        return PendingIntent.getService(this, requestCode, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun action(icon: Int, label: String, cmd: String, requestCode: Int): Notification.Action =
            Notification.Action.Builder(Icon.createWithResource(this, icon), label, command(cmd, requestCode)).build()

    private fun buildNotification(): Notification {
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val style = Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2)
        session?.let { style.setMediaSession(it.sessionToken) }
        return b.setContentTitle(title)
                .setContentText(subtitle)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentIntent(openApp())
                .setDeleteIntent(command("stop", 9))
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOngoing(playing)
                .setShowWhen(false)
                .setStyle(style)
                .addAction(action(android.R.drawable.ic_media_rew, labels["back"] ?: "", "back", 1))
                .addAction(if (playing) action(android.R.drawable.ic_media_pause, labels["pause"] ?: "", "toggle", 2)
                           else action(android.R.drawable.ic_media_play, labels["play"] ?: "", "toggle", 2))
                .addAction(action(android.R.drawable.ic_media_ff, labels["forward"] ?: "", "forward", 3))
                .addAction(action(android.R.drawable.ic_menu_close_clear_cancel, labels["close"] ?: "", "stop", 4))
                .build()
    }
}
