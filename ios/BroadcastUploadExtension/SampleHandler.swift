// SampleHandler.swift
// BroadcastUploadExtension target
//
// Receives every screen frame + audio sample buffer from ReplayKit and
// forwards them to the main Runner app using the ONLY IPC mechanism that
// actually works across the iOS process sandbox for Broadcast Upload
// Extensions on iOS 14+:
//
//   App Group shared file  +  Darwin notifications
//
// WHY NOT CFMessagePort?
//   CFMessagePortCreateRemote() always returns nil when called from a
//   Broadcast Upload Extension trying to connect to the host app process.
//   Apple's iOS sandbox blocks it — this is not a configuration issue,
//   it is a platform restriction introduced in iOS 14.
//
// ⚠️  2026-07-30 FIX — SYSTEM/APP AUDIO WAS NOT REACHING THE RECORDING:
//   A prior change ("DIRECT-CAPTURE DIAGNOSTIC") redirected every
//   .audioApp sample into a standalone AVAssetWriter that encoded straight
//   to <AppGroup>/direct_system_audio.m4a, entirely inside this extension
//   process, and removed the call that fed audio into the real IPC path
//   below. That diagnostic file was never read by anything — AppDelegate's
//   actual recording pipeline (systemAudioInput, the chunked AVAssetWriter,
//   progressive chunk upload) only ever consumes samples that arrive via
//   the queue-directory + Darwin-notification mechanism described below.
//   So system/app audio was captured correctly, but into a file with no
//   connection to the session recording — it just silently never showed
//   up in what got saved/uploaded. It also can't be fixed by muxing that
//   file in afterward: the app records and uploads in live chunks (see
//   RecState.uploading in recorder_types.dart), and a file only finalised
//   in broadcastFinished() isn't available until the whole broadcast ends,
//   which is incompatible with that chunked/progressive design.
//
//   The diagnostic did teach us something real, though: per-sample file
//   writes (one file create+write syscall every ~10-25ms) were expensive
//   enough that ReplayKit's non-buffering delivery model started silently
//   dropping .audioApp samples after a short burst — exactly the shape of
//   bug this was chasing. The fix below keeps that lesson without
//   abandoning the working pipeline: audio records are now BATCHED in
//   memory and flushed to a single queue file every few samples instead
//   of one file per sample, cutting the syscall rate by ~kAudioBatchSize
//   while still feeding the real recording path. See writeAudioSample.
//
// HOW THIS WORKS:
//   1. SampleHandler serialises each video frame (and each .audioApp — the
//      SHARED APP'S OWN audio, e.g. a video/game playing on the shared
//      screen) into a binary blob.
//   2. VIDEO is written atomically to a single fixed file:
//        <AppGroup>/broadcast_frame.bin
//      This is fine for video — frames arrive only a few times a second,
//      slow enough that "last write wins" never loses one before the host
//      reads it.
//      AUDIO is DIFFERENT: .audioApp buffers arrive every ~10-25ms, which
//      is fast enough that a single fixed filename becomes a race — the
//      extension can overwrite the file again before the host's Darwin
//      callback gets around to reading it, or the host can read the exact
//      same (not-yet-overwritten) file twice. That second case is the
//      dangerous one: the host feeds the same audio blob to the writer
//      twice, gets a duplicate/non-monotonic timestamp, and the writer's
//      strictly-increasing-PTS guard then silently rejects it and every
//      write after it — which looks exactly like "audio works for the
//      first sample then goes silent for the rest of the share". So audio
//      is written under its own sequentially-numbered file under a queue
//      directory:
//        <AppGroup>/broadcast_audio_queue/aud_0000000001.bin
//        <AppGroup>/broadcast_audio_queue/aud_0000000002.bin  ...
//      Nothing is ever overwritten, so there is nothing to race — the host
//      just drains the directory in filename order on each notification
//      (see AppDelegate's drainAudioQueueDirectory). To keep the syscall
//      rate down (see the 2026-07-30 fix note above), each file is now a
//      BATCH of up to kAudioBatchSize samples concatenated back-to-back
//      (still each in the same self-describing [typeId][pts][size][payload]
//      wire format), rather than exactly one sample per file. AppDelegate's
//      drain loop walks each file record-by-record, so batching is
//      transparent to it beyond that loop.
//   3. Posts a Darwin notification per type: "…flutter_education_app.frame"
//      / "…flutter_education_app.audioframe".
//   4. AppDelegate receives the notification (Darwin center crosses the
//      sandbox boundary safely), reads the corresponding file(s), decodes,
//      and writes to the AVAssetWriter recording chunk.
//   5. On broadcast end, posts "…flutter_education_app.stop".
//
//   NOTE: the teacher's own MIC audio is NOT sent from here — it is
//   forwarded separately from the host app via room.dart's
//   _startLiveKitAudioTap()/AppDelegate's "sendAudioFrame" (RPScreenRecorder's
//   own .audioMic/.audioApp capture never delivers samples while a LiveKit
//   call is active, extension or not — see AppDelegate.swift's comments).
//   So a recording made during a screen share has THREE independent audio
//   sources feeding the SAME chunk: mic (LiveKit tap) + shared-app audio
//   (this extension's .audioApp) — see AppDelegate's systemAudioInput track.
//
// ⚠️  REQUIRED XCODE SETUP — must match AppDelegate.swift:
//   Runner target:                  Signing & Capabilities → App Groups
//     → group.com.example.flutter_education_app
//   BroadcastUploadExtension target: same capability → same group ID
//
//   If your bundle ID is different, change kAppGroup below AND in
//   AppDelegate.swift (they must be identical strings).

import ReplayKit
import CoreMedia
import CoreVideo
import CoreAudio
import AudioToolbox
import AVFoundation

private let kAppGroup         = "group.com.softkour.alfaheem"
private let kDarwinFrameNotif = "com.example.flutter_education_app.frame"
// System/app audio (the audio OF the app being shared — e.g. a video or
// game playing on the shared screen). Posted once per audio sample, same
// as the video notification, but the payload lives in a QUEUE DIRECTORY
// of numbered files rather than one fixed filename — see the header
// comment above for why a single overwritten file silently muted audio
// after the first sample.
private let kDarwinAudioNotif   = "com.example.flutter_education_app.audioframe"
private let kDarwinStopNotif    = "com.example.flutter_education_app.stop"
private let kFrameFileName      = "broadcast_frame.bin"
// Must match AppDelegate's kAudioQueueDirName exactly.
private let kAudioQueueDirName  = "broadcast_audio_queue"
// Width of the zero-padded sequence number in each audio filename
// (e.g. "aud_0000000001.bin"). Fixed width is required so AppDelegate's
// drainAudioQueueDirectory can rely on a plain string sort to recover
// chronological order — must match what AppDelegate assumes.
private let kAudioSeqPad        = 10

class SampleHandler: RPBroadcastSampleHandler {

    // Resolved once in broadcastStarted() and reused for every frame.
    private var frameFileURL: URL?
    // Directory each audio sample gets its own numbered file under —
    // see kAudioQueueDirName's doc comment for why this replaced a single
    // fixed audio file.
    private var audioQueueDirURL: URL?
    // Monotonically increasing per-broadcast counter used to name each
    // audio sample's file (aud_0000000001.bin, aud_0000000002.bin, ...).
    // Only ever touched from processSampleBuffer's .audioApp case, which
    // ReplayKit calls serially, so no locking is needed.
    private var audioSeq: UInt64 = 0

    // DIAGNOSTIC (2026-08-01) — see processSampleBuffer's .audioApp case.
    // Measures raw .audioApp loudness AT THE POINT REPLAYKIT HANDS IT TO
    // US, before any of our own serialisation/batching/writing touches it.
    // This extension runs as a completely separate OS process from the
    // host app — it does not share the host app's AVAudioSession, so none
    // of AppDelegate's category/mode/duckOthers configuration can affect
    // what ReplayKit captures here. All prior fixes targeted the host
    // app's session. This log answers the question those fixes couldn't:
    // is ReplayKit itself already handing this extension quiet samples
    // (root cause is upstream, at the OS audio-routing level, outside any
    // app's control), or is it giving us good levels that get squashed
    // somewhere downstream in the host app's mixing/writing (in which
    // case a host-app-side fix is still viable)?
    private var lastAudioAppRmsLogTime: CFAbsoluteTime = 0
    private var audioAppRmsSquareSum: Double = 0
    private var audioAppRmsSampleCount: Int = 0
    private var audioAppRmsPeak: Float = 0

    // Reused across every audio callback rather than allocated+freed per
    // frame. Broadcast extensions have a very tight CPU/memory budget, and
    // audio callbacks can fire every ~10-25ms — allocating and
    // deallocating raw memory on every single one of those was enough
    // overhead that ReplayKit started dropping/muting audio buffers after
    // a short initial burst (they don't queue if the extension doesn't
    // keep up; they just get skipped). The channel count/format is stable
    // for the life of a broadcast session, so the buffer only needs to be
    // sized once and can be reused indefinitely after that.
    private var audioListBuffer: UnsafeMutableRawPointer?
    private var audioListBufferSize: Int = 0
    // Guards audioListBuffer against aliasing by two overlapping calls —
    // see the FIX comment where this is used in serialiseAudio for why.
    private let audioBufferLock = NSLock()

    // ── Audio batching buffer ────────────────────────────────────────────
    // See the 2026-07-30 header comment: writing one file per .audioApp
    // sample (~every 10-25ms) was expensive enough that ReplayKit stopped
    // delivering audio after a short burst. Records are accumulated here
    // in memory and flushed to a single queue file every kAudioBatchSize
    // samples, cutting the per-callback file-write rate by that factor.
    // Only ever touched from processSampleBuffer's .audioApp case, which
    // ReplayKit calls serially, so no locking is needed.
    private var pendingAudioRecords: [Data] = []
    // Flush after this many buffered samples. .audioApp fires every
    // ~10-25ms, so 6 keeps added latency to roughly 60-150ms — comfortably
    // inside what a chunked recording can tolerate — while cutting file
    // writes to about 1/6th of the original per-sample rate.
    private let kAudioBatchSize = 6

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Resolve the shared container URL.
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) else {
            let err = NSError(
                domain: "BroadcastError", code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "App Group '\(kAppGroup)' not found. " +
                    "Add the App Groups capability (same group ID) to both " +
                    "the Runner target and the BroadcastUploadExtension target in Xcode."])
            finishBroadcastWithError(err)
            return
        }
        frameFileURL = container.appendingPathComponent(kFrameFileName)

        let audioDir = container.appendingPathComponent(kAudioQueueDirName)
        // AppDelegate's registerDarwinListeners() already wipes+recreates
        // this directory right before the broadcast picker is shown, but
        // create it defensively here too in case the extension is ever
        // launched without that having run first — writing into a
        // directory that doesn't exist yet would silently no-op every
        // audio sample for the whole broadcast.
        try? FileManager.default.createDirectory(
            at: audioDir, withIntermediateDirectories: true
        )
        audioQueueDirURL = audioDir
        audioSeq = 0
        pendingAudioRecords.removeAll()

        NSLog("[SampleHandler] started — container: \(container.path)")
        NSLog("[SampleHandler] BUILD-CHECK-\(Date()) started")
    }

    override func broadcastPaused()  { flushPendingAudio() }
    override func broadcastResumed() {}

    override func broadcastFinished() {
        // Flush whatever's still buffered so the tail end of the share's
        // audio (up to kAudioBatchSize-1 samples) isn't lost just because
        // the batch never filled up before the broadcast ended.
        flushPendingAudio()
        notify(kDarwinStopNotif)
        audioListBuffer?.deallocate()
        audioListBuffer = nil
        audioListBufferSize = 0
        audioSeq = 0
        NSLog("[SampleHandler] finished — stop notification posted")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        switch sampleBufferType {
        case .video:
            guard let data = serialise(sampleBuffer) else { return }
            write(data, to: frameFileURL, notif: kDarwinFrameNotif)

        case .audioApp:
            guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
                  asbd.pointee.mFormatID == kAudioFormatLinearPCM
            else {
                // Non-PCM (e.g. AAC from DRM-protected apps) — skip, can't forward
                NSLog("[SampleHandler][diag] .audioApp buffer is NOT LinearPCM "
                      + "(likely DRM-protected content) — dropped, cannot forward")
                return
            }

            // DIAGNOSTIC (2026-08-01) — measure the RAW samples ReplayKit
            // just handed us, before serialiseAudio/batching/writing touch
            // them. Accumulated per-buffer, logged once/sec so this doesn't
            // add per-callback overhead (see the 2026-07-30 header comment
            // on why extra per-callback cost silently starves .audioApp
            // delivery). isFloat vs int16 handled since either can show up
            // depending on the shared app's own output format.
            measureAudioAppRms(sampleBuffer, asbd: asbd.pointee)

            // Serialise into the wire-format record AppDelegate expects,
            // then buffer it rather than writing a file per sample — see
            // the 2026-07-30 header comment for why one file per ~10-25ms
            // callback made ReplayKit silently stop delivering .audioApp
            // samples after a short burst. writeAudioSample only actually
            // touches disk once every kAudioBatchSize samples.
            guard let record = serialiseAudio(sampleBuffer) else { return }
            writeAudioSample(record)

        case .audioMic:
            // Still intentionally dropped: this extension has no mic
            // permission of its own in this app's configuration, and the
            // teacher's mic is already covered by the LiveKit tap.
            return

        @unknown default:
            return
        }
    }

    // ── DIAGNOSTIC (2026-08-01): raw .audioApp loudness at the source ────────
    // Reads straight from the CMBlockBuffer — no dependency on
    // serialiseAudio's own extraction path, so a bug in serialisation can't
    // mask (or fake) what's measured here.
    private func measureAudioAppRms(_ sb: CMSampleBuffer, asbd: AudioStreamBasicDescription) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sb) else { return }
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength, dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer, totalLength > 0 else {
            NSLog("[SampleHandler][diag] .audioApp: could not read raw block buffer (status=\(status))")
            return
        }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel) / 8
        guard bytesPerSample > 0 else { return }
        let sampleCount = totalLength / bytesPerSample

        var sumSquares: Double = 0
        var peak: Float = 0
        dataPointer.withMemoryRebound(to: UInt8.self, capacity: totalLength) { raw in
            if isFloat && bytesPerSample == 4 {
                raw.withMemoryRebound(to: Float32.self, capacity: sampleCount) { samples in
                    for i in 0..<sampleCount {
                        let v = samples[i]
                        sumSquares += Double(v * v)
                        peak = max(peak, abs(v))
                    }
                }
            } else if !isFloat && bytesPerSample == 2 {
                raw.withMemoryRebound(to: Int16.self, capacity: sampleCount) { samples in
                    for i in 0..<sampleCount {
                        let v = Float(samples[i]) / 32768.0
                        sumSquares += Double(v * v)
                        peak = max(peak, abs(v))
                    }
                }
            }
            // Other bit depths (e.g. 8/24/32-bit int) aren't sampled here —
            // rare for ReplayKit's .audioApp in practice, and this is a
            // diagnostic, not the forwarding path (serialiseAudio still
            // forwards the buffer exactly as before regardless).
        }

        audioAppRmsSquareSum += sumSquares
        audioAppRmsSampleCount += sampleCount
        audioAppRmsPeak = max(audioAppRmsPeak, peak)

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAudioAppRmsLogTime >= 1.0 else { return }
        lastAudioAppRmsLogTime = now
        let rms: Float = audioAppRmsSampleCount > 0
            ? Float(sqrt(audioAppRmsSquareSum / Double(audioAppRmsSampleCount)))
            : 0
        NSLog("[SampleHandler][diag] RAW .audioApp @source rms=\(String(format: "%.5f", rms)) "
              + "peak=\(String(format: "%.5f", audioAppRmsPeak)) "
              + "sampleRate=\(asbd.mSampleRate) channels=\(asbd.mChannelsPerFrame) "
              + "bits=\(asbd.mBitsPerChannel) isFloat=\(isFloat)")
        audioAppRmsSquareSum = 0
        audioAppRmsSampleCount = 0
        audioAppRmsPeak = 0
    }

    // ── Serialisation ─────────────────────────────────────────────────────────
    //
    // Wire format (same as AppDelegate expects):
    //   [4B  typeId  uint32 BE]  — 0 = video
    //   [8B  ptsNs   uint64 BE]  — presentation timestamp in nanoseconds
    //   [4B  size    uint32 BE]  — byte length of payload
    //   [<size> bytes payload]   — JPEG-encoded frame

    private func serialise(_ sb: CMSampleBuffer) -> Data? {
        let pts   = CMSampleBufferGetPresentationTimeStamp(sb)
        let ptsNs = UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000_000))

        // Encode the pixel buffer as JPEG to keep the shared file small.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let ciImage  = CIImage(cvPixelBuffer: pixelBuffer)
        let context  = CIContext()
        guard let jpegData = context.jpegRepresentation(
            of:         ciImage,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options:    [kCGImageDestinationLossyCompressionQuality
                         as CIImageRepresentationOption: 0.6]
        ) else { return nil }

        var typeId = UInt32(0).bigEndian
        var pts8   = ptsNs.bigEndian
        var size4  = UInt32(jpegData.count).bigEndian

        var out = Data(capacity: 16 + jpegData.count)
        out.append(Data(bytes: &typeId, count: 4))
        out.append(Data(bytes: &pts8,   count: 8))
        out.append(Data(bytes: &size4,  count: 4))
        out.append(jpegData)
        return out
    }

    // ── Audio serialisation (.audioApp) ─────────────────────────────────────
    //
    // Wire format (typeId = 2, matches AppDelegate's handleBroadcastData):
    //   [4B  typeId  uint32 BE]  — 2 = system/app audio
    //   [8B  ptsNs   uint64 BE]  — presentation timestamp in nanoseconds
    //   [4B  size    uint32 BE]  — byte length of payload
    //   [<size> bytes payload]   — [4B sampleRate BE][4B channels BE][4B isFloat BE][raw PCM]
    //
    // ReplayKit hands .audioApp buffers to us as PCM already (no need to
    // JPEG-encode like video), so we just copy the raw interleaved samples
    // out of the CMSampleBuffer's AudioBufferList alongside the format the
    // host needs to reconstruct it (sample rate + channel count).

    private func serialiseAudio(_ sb: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sb),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }
        let asbd = asbdPtr.pointee

        let pts   = CMSampleBufferGetPresentationTimeStamp(sb)
        let ptsNs = UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000_000))

        let channels = Int(asbd.mChannelsPerFrame)
        guard channels > 0 else { return nil }

        // Two-call pattern (the correct, documented way to do this — no
        // guessing at struct sizes): first ask CoreMedia exactly how many
        // bytes an AudioBufferList big enough for this sample buffer needs,
        // then allocate precisely that much. A previous version tried to
        // hand-compute this size instead (MemoryLayout<AudioBufferList>.size
        // + (channels-1)*MemoryLayout<AudioBuffer>.size); if that computed
        // size didn't exactly match what this specific CMSampleBuffer
        // needed, the call below would fail and this function would return
        // nil for every single frame — total silence, not just wrong
        // channel data. Querying the real size up front removes that risk
        // entirely, regardless of whether the source turns out to be
        // interleaved or non-interleaved (planar) underneath.
        var sizeNeeded = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
            bufferListSize: 0, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard sizeStatus == noErr, sizeNeeded > 0 else { return nil }

        // FIX (2026-08-01) — investigating "system audio plays as noise".
        // Direct measurement of a captured system-audio track showed 3.26%
        // of ALL samples exceeding the valid ±1.0 float range (up to 1.31),
        // plus 39% of samples at exact zero — a pattern that only makes
        // sense as reads from memory whose lifetime/ownership was violated
        // (freed/reclaimed pages often read back as zero; pages reused by
        // something else read back as garbage). This file already has one
        // documented fix for exactly that class of bug (withExtendedLifetime
        // on blockBuffer, below) — audioListBuffer is a SECOND instance of
        // the same risk: cached, mutable, INSTANCE-level memory reused
        // across every call. If this method is ever re-entered before a
        // prior call's read through it has finished — RPBroadcastSampleHandler
        // doesn't publicly document a strict serial-delivery guarantee
        // within one sample type — both calls would alias the SAME memory,
        // and one call's in-flight read gets silently corrupted by the
        // other's write.
        //
        // IMPORTANT: do NOT "fix" this by just allocating fresh memory
        // every call instead of reusing the cache — that was tried and
        // reverted. The cache exists because per-callback alloc/dealloc
        // previously caused ReplayKit to drop/mute audio buffers after a
        // short burst (see this property's declaration comment) — a real,
        // previously-confirmed cost, not a hypothetical one. Losing that
        // fix to gain this one would trade one production bug for another.
        // audioBufferLock keeps the reuse (and its performance win) while
        // making the buffer's use section exclusive, so no two calls can
        // ever be in it at once.
        audioBufferLock.lock()
        defer { audioBufferLock.unlock() }

        if audioListBuffer == nil || audioListBufferSize < sizeNeeded {
            audioListBuffer?.deallocate()
            audioListBuffer = UnsafeMutableRawPointer.allocate(
                byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment
            )
            audioListBufferSize = sizeNeeded
        }
        let listPtr = audioListBuffer!.assumingMemoryBound(to: AudioBufferList.self)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: nil,
            bufferListOut: listPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        // ── BUG FIX (2026-07-29) ────────────────────────────────────────────
        // `blockBuffer` backs the memory that `listPointer`'s `mData`
        // pointers point into, but it is never read again after the call
        // above — only written to as an out-parameter. Swift's ARC keeps a
        // variable alive only until its LAST USE; with no later use, the
        // optimizer is free (especially in a Release/optimized build) to
        // release `blockBuffer` immediately after this call returns —
        // potentially BEFORE the code below finishes reading through
        // `mData`. That reads freed/reused memory, producing garbage bytes
        // — audible as static/noise, not silence or a clean failure, and
        // easy to miss in Debug builds where deallocation timing differs.
        // withExtendedLifetime forces `blockBuffer` to stay alive for the
        // full duration of the closure, guaranteeing every `mData` read
        // below happens against still-valid memory.
        return withExtendedLifetime(blockBuffer) { () -> Data? in
        let listPointer = UnsafeMutableAudioBufferListPointer(listPtr)
        let isFloat: UInt32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 ? 1 : 0
        let bytesPerSample  = isFloat == 1 ? 4 : 2
        let numBuffers      = listPointer.count

        var pcmData: Data
        if numBuffers <= 1 {
            // Interleaved: one buffer already holds every channel in
            // L,R,L,R... order — use it as-is.
            guard let buffer = listPointer[0].mData,
                  listPointer[0].mDataByteSize > 0 else { return nil }
            pcmData = Data(bytes: buffer, count: Int(listPointer[0].mDataByteSize))
        } else {
            // Non-interleaved (planar): one buffer per channel, each
            // holding that channel's samples back-to-back in mono. Manually
            // interleave them sample-by-sample into one combined buffer so
            // the wire format (and the decoder on the other end) can keep
            // assuming "interleaved" universally rather than needing to
            // carry a layout flag through the whole pipeline.
            guard listPointer[0].mData != nil, listPointer[0].mDataByteSize > 0
            else { return nil }
            let frameCount = Int(listPointer[0].mDataByteSize) / bytesPerSample
            var interleaved = Data(count: frameCount * bytesPerSample * numBuffers)
            let channelPtrs: [UnsafeMutableRawPointer?] = (0..<numBuffers).map { listPointer[$0].mData }
            guard channelPtrs.allSatisfy({ $0 != nil }) else { return nil }

            interleaved.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                for frame in 0..<frameCount {
                    for ch in 0..<numBuffers {
                        let srcOffset = frame * bytesPerSample
                        let dstOffset = (frame * numBuffers + ch) * bytesPerSample
                        let src = channelPtrs[ch]!.advanced(by: srcOffset)
                        dst.baseAddress!.advanced(by: dstOffset)
                            .copyMemory(from: src, byteCount: bytesPerSample)
                    }
                }
            }
            pcmData = interleaved
        }

        let sampleRate = UInt32(asbd.mSampleRate)

        var payload = Data(capacity: 9 + pcmData.count)
        var sr = sampleRate.bigEndian
        var ch = UInt32(channels).bigEndian
        var fl = isFloat.bigEndian
        payload.append(Data(bytes: &sr, count: 4))
        payload.append(Data(bytes: &ch, count: 4))
        payload.append(Data(bytes: &fl, count: 4))
        payload.append(pcmData)

        var typeId = UInt32(2).bigEndian
        var pts8   = ptsNs.bigEndian
        var size4  = UInt32(payload.count).bigEndian

        var out = Data(capacity: 16 + payload.count)
        out.append(Data(bytes: &typeId, count: 4))
        out.append(Data(bytes: &pts8,   count: 8))
        out.append(Data(bytes: &size4,  count: 4))
        out.append(payload)
        return out
        } // end withExtendedLifetime(blockBuffer)
    }

    // ── File write + Darwin notification ──────────────────────────────────────

    private func write(_ data: Data, to url: URL?, notif: String) {
        guard let url = url else { return }
        // Write atomically so the host app never reads a partial file.
        try? data.write(to: url, options: .atomic)
        notify(notif)
    }

    /// Buffers one already-serialised audio record (from serialiseAudio)
    /// and flushes the batch to disk once kAudioBatchSize records have
    /// accumulated. This is the call site that used to write a brand new
    /// file per sample; batching is what fixes ReplayKit silently halting
    /// .audioApp delivery under that per-callback I/O cost (see the
    /// 2026-07-30 header comment) while still feeding the exact same
    /// queue-directory pipeline AppDelegate already knows how to drain.
    private func writeAudioSample(_ data: Data) {
        pendingAudioRecords.append(data)
        if pendingAudioRecords.count >= kAudioBatchSize {
            flushPendingAudio()
        }
    }

    /// Concatenates every currently-buffered audio record into ONE file
    /// under the queue directory and posts a single Darwin notification
    /// for the whole batch. Deliberately never reuses a filename — each
    /// flush gets the next sequence number, so there is nothing for a fast
    /// producer / slower consumer to race over (unlike the old single
    /// fixed-file design, which could get overwritten before the host read
    /// it, or read twice yielding a duplicate timestamp — see this file's
    /// header comment for why that silenced audio after the very first
    /// sample). Safe to call with an empty buffer (no-op).
    private func flushPendingAudio() {
        guard !pendingAudioRecords.isEmpty else { return }
        guard let dir = audioQueueDirURL else {
            pendingAudioRecords.removeAll()
            return
        }
        var batch = Data()
        for record in pendingAudioRecords { batch.append(record) }
        pendingAudioRecords.removeAll()

        let seq = audioSeq
        audioSeq += 1
        let fileURL = dir.appendingPathComponent("aud_\(paddedSeq(seq)).bin")
        try? batch.write(to: fileURL, options: .atomic)
        notify(kDarwinAudioNotif)
    }

    /// Zero-pads `n` to kAudioSeqPad digits (e.g. 42 → "0000000042") so a
    /// plain string sort on the host side is also chronological order.
    private func paddedSeq(_ n: UInt64) -> String {
        let s = String(n)
        guard s.count < kAudioSeqPad else { return s }
        return String(repeating: "0", count: kAudioSeqPad - s.count) + s
    }

    private func notify(_ name: String) {
        // CFNotificationCenterPostNotification on the Darwin center is the
        // only notification mechanism that crosses the iOS extension sandbox.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}