package com.doubley.alfaheem

import android.util.Log
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * D-306: the other people's voices in the device recording.
 *
 * The recorder (SegmentedRecorder) hears the microphone only, so a meeting recorded on a phone with earphones had
 * nobody but its host in it, and on the loudspeaker the others came in as room echo. WebRTC's audio device module
 * hands every block it plays (~10 ms, the mix of every remote participant, before it reaches the speaker) to the
 * fork's PlaybackSamplesReadyCallbackAdapter; this object registers itself there for the length of a recording,
 * turns each block into 44.1 kHz mono 16-bit PCM and keeps up to [MAX_BACKLOG] of it in a ring, and the recorder's
 * audio loop adds what is due into every microphone block it encodes ([mixInto], saturating).
 *
 * The plugin keeps org.webrtc off the app's compile classpath (the fork's `implementation` dependency) and its
 * method-call handler private, so both are reached by reflection: the callback interface is implemented with a
 * java.lang.reflect.Proxy and the samples are read through cached Methods. Anything missing (an older fork, a
 * renamed field) makes [attach] return false and the recording stays microphone-only, exactly as before.
 *
 * Timing: playout runs on its own clock, the microphone on its own; both are real time, so the ring only drifts by
 * the two clocks' difference. Over [MAX_BACKLOG] the oldest samples are dropped down to [TARGET_BACKLOG] (the voices
 * never lag behind the host's by more than ~0.25 s); an empty ring adds silence.
 *
 * Not measured on a device yet (D-306). On the loudspeaker the microphone also hears the voices from the room, a
 * few tens of milliseconds later than the mixed copy (a slight doubling); with earphones the mixed copy is the only
 * one.
 */
object RemoteAudioMix {
    private const val TAG = "RemoteAudioMix"
    private const val RATE = 44_100
    private const val CAP = RATE // one second of mono samples
    private const val MAX_BACKLOG = RATE / 2
    private const val TARGET_BACKLOG = RATE / 10

    private val ring = ShortArray(CAP)
    private var readPos = 0
    private var size = 0
    private val lock = Any()

    /** Resampler state: the position (in input frames) of the next output sample within the incoming stream. */
    private var phase = 0.0
    private var lastIn = 0
    private var inRate = 0

    @Volatile private var attached: Any? = null // the proxy
    private var adapter: Any? = null
    private var removeMethod: Method? = null
    private var getData: Method? = null
    private var getRate: Method? = null
    private var getChannels: Method? = null

    /** Starts receiving the played-out audio. True when the hook is in place. */
    @Synchronized
    fun attach(): Boolean {
        if (attached != null) return true
        return try {
            val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
            val plugin = pluginClass.getField("sharedSingleton").get(null) ?: return false
            val handlerField = pluginClass.getDeclaredField("methodCallHandler").apply { isAccessible = true }
            val handler = handlerField.get(plugin) ?: return false
            val adapterObj = handler.javaClass.getField("playbackSamplesReadyCallbackAdapter").get(handler) ?: return false
            val cbClass = Class.forName("org.webrtc.audio.JavaAudioDeviceModule\$PlaybackSamplesReadyCallback")
            val samplesClass = Class.forName("org.webrtc.audio.JavaAudioDeviceModule\$AudioSamples")
            getData = samplesClass.getMethod("getData")
            getRate = samplesClass.getMethod("getSampleRate")
            getChannels = samplesClass.getMethod("getChannelCount")
            val proxy = Proxy.newProxyInstance(cbClass.classLoader, arrayOf(cbClass)) { self, method, args ->
                when (method.name) {
                    "onWebRtcAudioTrackSamplesReady" -> { args?.firstOrNull()?.let { onSamples(it) }; null }
                    "hashCode" -> System.identityHashCode(self)
                    "equals" -> self === args?.firstOrNull()
                    "toString" -> "RemoteAudioMix"
                    else -> null
                }
            }
            adapterObj.javaClass.getMethod("addCallback", cbClass).invoke(adapterObj, proxy)
            removeMethod = adapterObj.javaClass.getMethod("removeCallback", cbClass)
            adapter = adapterObj
            reset()
            attached = proxy
            Log.d(TAG, "attached")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "playback hook unavailable — the recording keeps the microphone only: $e")
            false
        }
    }

    @Synchronized
    fun detach() {
        val proxy = attached ?: return
        attached = null
        try {
            removeMethod?.invoke(adapter, proxy)
        } catch (e: Throwable) {
            Log.w(TAG, "detach: $e")
        }
        adapter = null
        removeMethod = null
        reset()
    }

    private fun reset() = synchronized(lock) {
        readPos = 0
        size = 0
        phase = 0.0
        lastIn = 0
        inRate = 0
    }

    /** One played block (16-bit PCM, interleaved): down to mono, resampled to [RATE], into the ring. */
    private fun onSamples(samples: Any) {
        if (attached == null) return
        try {
            val data = getData?.invoke(samples) as? ByteArray ?: return
            val rate = (getRate?.invoke(samples) as? Int) ?: return
            val ch = ((getChannels?.invoke(samples) as? Int) ?: 1).coerceAtLeast(1)
            if (rate <= 0) return
            val bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN)
            val frames = data.size / 2 / ch
            synchronized(lock) {
                if (rate != inRate) {
                    inRate = rate
                    phase = 0.0
                }
                val step = rate.toDouble() / RATE // input frames per output sample
                // Linear interpolation between the previous block's last frame (index -1) and this block.
                fun frame(i: Int): Int {
                    if (i < 0) return lastIn
                    var sum = 0
                    for (c in 0 until ch) sum += bb.getShort((i * ch + c) * 2).toInt()
                    return sum / ch
                }
                // phase lies in [-1, frames - 1]: frame -1 is the previous block's last one.
                while (phase <= frames - 1) {
                    val i = Math.floor(phase).toInt()
                    val f = phase - i
                    val a = frame(i)
                    val b = if (i + 1 < frames) frame(i + 1) else a
                    val s = (a + (b - a) * f).toInt()
                    push(s.coerceIn(-32768, 32767).toShort())
                    phase += step
                }
                phase -= frames
                if (frames > 0) lastIn = frame(frames - 1)
                if (size > MAX_BACKLOG) drop(size - TARGET_BACKLOG)
            }
        } catch (e: Throwable) {
            Log.w(TAG, "samples: $e")
        }
    }

    private fun push(v: Short) {
        if (size == CAP) drop(1)
        ring[(readPos + size) % CAP] = v
        size++
    }

    private fun drop(n: Int) {
        val k = minOf(n, size)
        readPos = (readPos + k) % CAP
        size -= k
    }

    /**
     * Adds the voices that are due into [bytes] bytes of the microphone's 16-bit mono PCM at the start of [buf]
     * (44.1 kHz, native order; the buffer's position and limit are not touched). A no-op while not attached.
     */
    fun mixInto(buf: ByteBuffer, bytes: Int) {
        if (attached == null || bytes < 2) return
        val pcm = buf.duplicate().order(ByteOrder.nativeOrder())
        val n = bytes / 2
        synchronized(lock) {
            val take = minOf(n, size)
            for (i in 0 until take) {
                val mic = pcm.getShort(i * 2).toInt()
                val v = ring[(readPos + i) % CAP].toInt()
                pcm.putShort(i * 2, (mic + v).coerceIn(-32768, 32767).toShort())
            }
            drop(take)
        }
    }
}
