package com.example.flutter_education_app

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer

/**
 * D-103: the course recording as ONE continuous encode, cut into ~5 s MP4 chunks without ever stopping an encoder.
 *
 * The old recorder stopped one MediaRecorder and started the next every chunk ("ping-pong"). Every boundary then
 * lost time: the renderer moved to the next recorder's surface before the old one stopped (its video ended early),
 * the next encoder needed a key frame and ~100 ms to start, both recorders captured the mic for a moment (a sliver
 * of sound twice), and every file began with a fresh AAC encoder's priming silence — a jump and a click every 5 s.
 *
 * Here one H.264 encoder (input surface, fed by ScreenPlaceholderRenderer) and one AAC encoder (fed by an AudioRecord
 * whose timestamps follow its sample count) run for the whole recording. Their output is merged in timestamp order
 * and written by a MediaMuxer that is swapped for a new file at the first video key frame ≥ ~5 s into the chunk
 * (a sync frame is requested just before): every video frame and every AAC frame lands in exactly one chunk, the
 * chunks join with no gap and no overlap, and each file still plays on its own (it starts with a key frame and the
 * codec config). The server (local_recorder.py) joins them with `-c copy` on the audio clock (`seamless=1`).
 *
 * Timestamps are CLOCK_MONOTONIC microseconds (the renderer stamps each frame with System.nanoTime(), the audio
 * comes from AudioRecord.getTimestamp), so motion in the file is exactly real time.
 *
 * Threads: the AudioRecord reader, one drain thread per encoder; the muxer is only touched under [lock].
 * [start] throws if an encoder / the mic cannot be set up — the caller then falls back to MediaRecorder.
 */
class SegmentedRecorder(
        private val audioOnly: Boolean,
        private val width: Int,
        private val height: Int,
        private val videoBps: Int,
        private val fps: Int,
        private val audioBps: Int,
        private val segmentSecs: Int,
        firstIndex: Int,
        /** Where chunk [index] is written while it is open (renamed by [onSegment]). */
        private val tmpFileFor: (index: Int) -> File,
        /** A chunk file is complete. [last] = closed by [finish] (the recording stops / pauses). */
        private val onSegment: (tmp: File, index: Int, last: Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "SegmentedRecorder"
        private const val SAMPLE_RATE = 44_100
        private const val I_FRAME_SECS = 2
        /** A key frame this close to the chunk length already ends the chunk. */
        private const val CUT_EARLY_US = 250_000L
        /** The sync frame is asked this long before the chunk is due. */
        private const val SYNC_LEAD_US = 400_000L
        /** A track that produced nothing for this long no longer holds the other one back. */
        private const val STALL_US = 1_000_000L
        private const val DRAIN_TIMEOUT_US = 10_000L
    }

    private class Sample(val data: ByteArray, val ptsUs: Long, val flags: Int, val video: Boolean) {
        val key get() = (flags and MediaCodec.BUFFER_FLAG_KEY_FRAME) != 0
    }

    /** The video encoder's input: ScreenPlaceholderRenderer draws into it. Null for an audio-only recording. */
    var inputSurface: Surface? = null
        private set

    private var videoCodec: MediaCodec? = null
    private var audioCodec: MediaCodec? = null
    private var audioRecord: AudioRecord? = null
    private val threads = mutableListOf<Thread>()
    @Volatile private var capturing = false

    // ── muxing state (under lock) ──
    private val lock = Object()
    private var videoFormat: MediaFormat? = null
    private var audioFormat: MediaFormat? = null
    private val vq = ArrayDeque<Sample>()
    private val aq = ArrayDeque<Sample>()
    private var vLast = Long.MIN_VALUE
    private var aLast = Long.MIN_VALUE
    private var vDone = false
    private var aDone = false
    private var muxer: MediaMuxer? = null
    private var vTrack = -1
    private var aTrack = -1
    private var segIndex = firstIndex
    private var segStartUs = -1L
    private var segTmp: File? = null
    private var segSamples = 0
    private var syncAsked = false
    private var startedAnyVideo = false
    private val segmentUs = segmentSecs.coerceAtLeast(1) * 1_000_000L

    /** The index the NEXT chunk will get (after [finish]: where a resumed recorder continues). */
    val nextIndex: Int get() = synchronized(lock) { if (muxer != null) segIndex + 1 else segIndex }

    // ── lifecycle ─────────────────────────────────────────────────────────────

    @SuppressLint("MissingPermission") // RECORD_AUDIO is checked by ScreenCaptureService before any recording
    fun start() {
        try {
            if (!audioOnly) {
                val f = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                    setInteger(MediaFormat.KEY_BIT_RATE, videoBps)
                    setInteger(MediaFormat.KEY_FRAME_RATE, fps)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, I_FRAME_SECS)
                    // No B-frames: the cut and the server's timing assume presentation order = decode order.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
                }
                val vc = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                videoCodec = vc
                vc.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                inputSurface = vc.createInputSurface()
            }
            val af = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, audioBps)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16 * 1024)
            }
            val ac = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
            audioCodec = ac
            ac.configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)

            val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT)
            if (minBuf <= 0) throw IllegalStateException("AudioRecord.getMinBufferSize=$minBuf")
            // The same source MediaRecorder used (MIC): the recording hears what it heard before.
            val ar = AudioRecord(MediaRecorder.AudioSource.MIC, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf * 4, SAMPLE_RATE / 2 * 2))
            audioRecord = ar
            if (ar.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("AudioRecord not initialized")

            videoCodec?.start()
            ac.start()
            ar.startRecording()
            capturing = true
            threads += Thread({ audioLoop(ar, ac) }, "SegRecAudioIn")
            threads += Thread({ drainLoop(ac, video = false) }, "SegRecAudioOut")
            videoCodec?.let { vc -> threads += Thread({ drainLoop(vc, video = true) }, "SegRecVideoOut") }
            if (audioOnly) vDone = true
            threads.forEach { it.start() }
            Log.d(TAG, "started ${if (audioOnly) "audio-only" else "${width}x$height@$fps ${videoBps / 1000}kbps"} " +
                    "chunk≈${segmentSecs}s from #$segIndex")
        } catch (e: Exception) {
            releaseAll()
            throw e
        }
    }

    /**
     * Stops capturing, drains both encoders and closes the open chunk ([onSegment] with last = true). Blocks
     * (bounded). The renderer must already have stopped drawing into [inputSurface].
     */
    fun finish() {
        capturing = false
        try { videoCodec?.signalEndOfInputStream() } catch (e: Exception) { Log.w(TAG, "EOS video: ${e.message}") }
        for (t in threads) {
            try { t.join(3_000) } catch (_: InterruptedException) {}
            if (t.isAlive) Log.w(TAG, "${t.name} did not end in time")
        }
        synchronized(lock) {
            vDone = true
            aDone = true
            drain(force = true)
            closeSegment(last = true)
        }
        releaseAll()
    }

    private fun releaseAll() {
        capturing = false
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        for (c in listOfNotNull(videoCodec, audioCodec)) {
            try { c.stop() } catch (_: Exception) {}
            try { c.release() } catch (_: Exception) {}
        }
        videoCodec = null
        audioCodec = null
        try { inputSurface?.release() } catch (_: Exception) {}
        inputSurface = null
        synchronized(lock) {
            muxer?.let { m ->
                try { m.release() } catch (_: Exception) {}
            }
            muxer = null
        }
    }

    // ── capture ───────────────────────────────────────────────────────────────

    /** PCM → AAC encoder, stamped from the sample count on the AudioRecord's own monotonic clock. */
    private fun audioLoop(ar: AudioRecord, codec: MediaCodec) {
        var samples = 0L
        var anchorNs = -1L
        val ts = AudioTimestamp()
        try {
            while (capturing) {
                val idx = codec.dequeueInputBuffer(DRAIN_TIMEOUT_US)
                if (idx < 0) continue
                val buf = codec.getInputBuffer(idx)
                if (buf == null) {
                    codec.queueInputBuffer(idx, 0, 0, ptsFor(anchorNs, samples), 0)
                    continue
                }
                val want = minOf(buf.capacity(), 2048 * 2) and 1.inv()
                var n = 0
                while (capturing && n <= 0) {      // keep this input buffer until there is sound for it
                    buf.clear()
                    n = ar.read(buf, want)
                    if (n < 0) Thread.sleep(5)
                }
                if (n <= 0) {                        // stopped while waiting: this buffer carries the end
                    codec.queueInputBuffer(idx, 0, 0, ptsFor(anchorNs, samples), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    return
                }
                if (anchorNs < 0) {
                    // Frame 0's capture time: the AudioRecord's own timestamp when it has one, else "now" minus
                    // what was just read. Fixed for the whole run, so the timeline never jumps.
                    anchorNs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                            ar.getTimestamp(ts, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
                        ts.nanoTime - ts.framePosition * 1_000_000_000L / SAMPLE_RATE
                    } else {
                        System.nanoTime() - (n / 2) * 1_000_000_000L / SAMPLE_RATE
                    }
                }
                codec.queueInputBuffer(idx, 0, n, ptsFor(anchorNs, samples), 0)
                samples += n / 2
            }
            // End of stream.
            for (attempt in 0 until 50) {
                val idx = codec.dequeueInputBuffer(DRAIN_TIMEOUT_US)
                if (idx >= 0) {
                    codec.queueInputBuffer(idx, 0, 0, ptsFor(anchorNs, samples), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                    break
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "audio input stopped: ${e.message}", e)
        }
    }

    private fun ptsFor(anchorNs: Long, samples: Long): Long {
        val base = if (anchorNs < 0) System.nanoTime() else anchorNs
        return (base + samples * 1_000_000_000L / SAMPLE_RATE) / 1_000
    }

    private fun drainLoop(codec: MediaCodec, video: Boolean) {
        val info = MediaCodec.BufferInfo()
        try {
            while (true) {
                val idx = codec.dequeueOutputBuffer(info, DRAIN_TIMEOUT_US)
                when {
                    idx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> synchronized(lock) {
                        if (video) videoFormat = codec.outputFormat else audioFormat = codec.outputFormat
                    }
                    idx >= 0 -> {
                        val eos = (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                        val config = (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                        if (!config && info.size > 0) {
                            val out = codec.getOutputBuffer(idx)
                            if (out != null) {
                                val bytes = ByteArray(info.size)
                                out.position(info.offset)
                                out.limit(info.offset + info.size)
                                out.get(bytes)
                                push(Sample(bytes, info.presentationTimeUs, info.flags, video))
                            }
                        }
                        codec.releaseOutputBuffer(idx, false)
                        if (eos) break
                    }
                    !capturing && idx == MediaCodec.INFO_TRY_AGAIN_LATER && stalledAfterStop() -> break
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "${if (video) "video" else "audio"} drain ended: ${e.message}")
        }
        synchronized(lock) {
            if (video) vDone = true else aDone = true
            drain(force = false)
        }
    }

    @Volatile private var stopSeenAtNs = 0L
    /** After [finish] asked for the end, an encoder that never sends EOS is given up after 2 s. */
    private fun stalledAfterStop(): Boolean {
        val now = System.nanoTime()
        if (stopSeenAtNs == 0L) stopSeenAtNs = now
        return now - stopSeenAtNs > 2_000_000_000L
    }

    // ── merge + cut (under lock) ──────────────────────────────────────────────

    private fun push(s: Sample) = synchronized(lock) {
        if (s.video) { vq.addLast(s); vLast = s.ptsUs } else { aq.addLast(s); aLast = s.ptsUs }
        drain(force = false)
    }

    /**
     * Writes queued samples in timestamp order. A sample goes out only once the other track has passed its time
     * (each track's timestamps only grow), so the chunk a sample lands in is decided by its own timestamp.
     */
    private fun drain(force: Boolean) {
        while (true) {
            val v = vq.firstOrNull()
            val a = aq.firstOrNull()
            val s = when {
                v != null && (a == null || v.ptsUs <= a.ptsUs) -> v
                a != null -> a
                else -> return
            }
            if (!force) {
                val otherLast = if (s.video) aLast else vLast
                val otherDone = if (s.video) aDone else vDone
                val newest = maxOf(vLast, aLast)
                if (!otherDone && otherLast < s.ptsUs && newest - s.ptsUs < STALL_US) return
            }
            if (s.video) vq.removeFirst() else aq.removeFirst()
            write(s)
        }
    }

    private fun write(s: Sample) {
        if (s.video) {
            if (muxer == null || (s.key && s.ptsUs - segStartUs >= segmentUs - CUT_EARLY_US)) {
                if (!s.key) return                    // never start a chunk without a key frame
                if (muxer != null) closeSegment(last = false)
                if (!openSegment(s.ptsUs)) return
            }
            if (!syncAsked && s.ptsUs - segStartUs >= segmentUs - SYNC_LEAD_US) requestSyncFrame()
            writeSample(vTrack, s)
            startedAnyVideo = true
        } else {
            if (audioOnly) {
                if (muxer == null || s.ptsUs - segStartUs >= segmentUs) {
                    if (muxer != null) closeSegment(last = false)
                    if (!openSegment(s.ptsUs)) return
                }
            } else if (muxer == null || !startedAnyVideo) {
                return                                // audio before the run's first key frame is dropped
            }
            if (aTrack >= 0) writeSample(aTrack, s)
        }
    }

    private fun requestSyncFrame() {
        syncAsked = true
        try {
            videoCodec?.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
        } catch (e: Exception) {
            Log.w(TAG, "sync frame request failed: ${e.message}")
        }
    }

    private fun openSegment(startUs: Long): Boolean {
        val vf = videoFormat
        val af = audioFormat
        if (!audioOnly && vf == null) return false
        val tmp = tmpFileFor(segIndex).also { it.delete() }
        return try {
            val m = MediaMuxer(tmp.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            vTrack = if (!audioOnly && vf != null) m.addTrack(vf) else -1
            aTrack = if (af != null) m.addTrack(af) else -1
            if (aTrack < 0) Log.w(TAG, "chunk #$segIndex opened without audio (no AAC output yet)")
            if (vTrack < 0 && aTrack < 0) { m.release(); return false }
            m.start()
            muxer = m
            segTmp = tmp
            segStartUs = startUs
            segSamples = 0
            syncAsked = false
            true
        } catch (e: Exception) {
            Log.e(TAG, "chunk #$segIndex could not be opened: ${e.message}", e)
            false
        }
    }

    private fun writeSample(track: Int, s: Sample) {
        val m = muxer ?: return
        val info = MediaCodec.BufferInfo().apply {
            set(0, s.data.size, s.ptsUs, s.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM.inv())
        }
        try {
            m.writeSampleData(track, ByteBuffer.wrap(s.data), info)
            segSamples++
        } catch (e: Exception) {
            Log.w(TAG, "sample dropped (chunk #$segIndex): ${e.message}")
        }
    }

    private fun closeSegment(last: Boolean) {
        val m = muxer ?: return
        val tmp = segTmp
        val index = segIndex
        muxer = null
        segTmp = null
        var ok = segSamples > 0
        try { m.stop() } catch (e: Exception) { ok = false; Log.w(TAG, "chunk #$index stop failed: ${e.message}") }
        try { m.release() } catch (_: Exception) {}
        segIndex++
        if (tmp != null) {
            if (ok) onSegment(tmp, index, last) else tmp.delete()
        }
    }
}
