package com.example.flutter_education_app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.cloudwebrtc.webrtc.ElFaheemBridge

/**
 * Phone calls during a live session (A19). While a cellular / system call
 * rings or runs, Android hands the microphone to the call: the room's mic
 * would go silent with no signal, and the recording would record silence.
 *
 * Signals: the room's audio-focus listener (flutter_webrtc's
 * AudioSwitchManager, forwarded by the fork's ElFaheemBridge — it was a
 * no-op) and, from API 31, the audio-mode listener. Only a CALL mode
 * (ringtone / in call / call screening / redirect) counts: focus lost to
 * a media app (the presenter plays a video in another app during a share)
 * leaves the mic alone. Telecom asks for focus BEFORE it sets the ringtone
 * mode, so a focus loss is re-checked shortly after.
 *
 * [emit] gets `audioInterruption {active, reason}` once per change (main
 * thread); Dart mutes / restores the mic and shows a notice. The recording
 * gets a marker line in its log (ScreenCaptureService.markAudioInterruption).
 */
class LiveAudioInterruptions(
        context: Context,
        private val emit: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "LiveAudioInterruptions"
    }

    // The application context's AudioManager: ElFaheemBridge.audioFocusListener is static and
    // the mode listener is registered on it, so neither may hold the Activity.
    private val appContext = context.applicationContext
    private val audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())
    private var interrupted = false
    private var modeListener: Any? = null
    private var started = false

    fun start() {
        if (started) return
        started = true
        ElFaheemBridge.audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
            main.post { onFocusChange(change) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val l = AudioManager.OnModeChangedListener { mode -> main.post { onMode(mode) } }
            try {
                audioManager.addOnModeChangedListener(appContext.mainExecutor, l)
                modeListener = l
            } catch (e: Exception) {
                Log.w(TAG, "mode listener unavailable: ${e.message}")
            }
        }
        Log.d(TAG, "watching for phone calls")
    }

    /** Also MainActivity.onDestroy: the static focus listener must not outlive the Activity. */
    fun stop() {
        if (!started) return
        started = false
        ElFaheemBridge.audioFocusListener = null
        main.removeCallbacksAndMessages(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (modeListener as? AudioManager.OnModeChangedListener)?.let {
                try { audioManager.removeOnModeChangedListener(it) } catch (_: Exception) {}
            }
        }
        modeListener = null
        interrupted = false
    }

    private fun isCallMode(mode: Int): Boolean {
        if (mode == AudioManager.MODE_RINGTONE || mode == AudioManager.MODE_IN_CALL) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && mode == AudioManager.MODE_CALL_SCREENING) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && mode == AudioManager.MODE_CALL_REDIRECT) return true
        return false
    }

    private fun onFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                Log.d(TAG, "audio focus lost ($change), mode ${audioManager.mode}")
                checkMode()
                // Telecom requests focus first and sets MODE_RINGTONE right after.
                main.postDelayed({ checkMode() }, 300)
                main.postDelayed({ checkMode() }, 1_200)
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                Log.d(TAG, "audio focus back, mode ${audioManager.mode}")
                checkMode()
            }
        }
    }

    private fun onMode(mode: Int) {
        Log.d(TAG, "audio mode $mode")
        set(isCallMode(mode))
    }

    private fun checkMode() = set(isCallMode(audioManager.mode))

    private fun set(active: Boolean) {
        if (!started || active == interrupted) return
        interrupted = active
        Log.i(TAG, if (active) "phone call: the mic is interrupted" else "phone call ended")
        ScreenCaptureService.markAudioInterruption(active)
        emit(mapOf("event" to "audioInterruption", "active" to active, "reason" to "call"))
    }
}
