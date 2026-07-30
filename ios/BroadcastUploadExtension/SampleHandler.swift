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
//      first sample then goes silent for the rest of the share". So each
//      audio sample instead gets its OWN sequentially-numbered file under
//      a queue directory:
//        <AppGroup>/broadcast_audio_queue/aud_0000000001.bin
//        <AppGroup>/broadcast_audio_queue/aud_0000000002.bin  ...
//      Nothing is ever overwritten, so there is nothing to race — the host
//      just drains the directory in filename order on each notification
//      (see AppDelegate's drainAudioQueueDirectory).
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

    // ── DIRECT-CAPTURE DIAGNOSTIC (2026-07-30) ──────────────────────────────
    // Teams/Zoom-style architecture: encode the ORIGINAL ReplayKit
    // CMSampleBuffer directly, inside the extension, at the point of
    // capture — zero custom serialization, zero host-side reconstruction.
    // If audio recorded this way is STILL corrupted, the bug is genuinely
    // upstream of all custom code (ReplayKit/OS level). If it's clean,
    // this proves the existing serialize→queue→reconstruct pipeline is
    // where the corruption is introduced, and this becomes the
    // replacement architecture rather than just a diagnostic.
    private var directAudioWriter: AVAssetWriter?
    private var directAudioInput: AVAssetWriterInput?
    private var directAudioSessionStarted = false
    private let directAudioQueue = DispatchQueue(label: "com.softkour.alfaheem.directaudio")

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

        // ── DIRECT-CAPTURE DIAGNOSTIC: initialize the writer ────────────────
        let directAudioURL = container.appendingPathComponent("direct_system_audio.m4a")
        try? FileManager.default.removeItem(at: directAudioURL) // overwrite each broadcast
        if let writer = try? AVAssetWriter(outputURL: directAudioURL, fileType: .m4a) {
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                directAudioWriter = writer
                directAudioInput = input
                directAudioSessionStarted = false
                NSLog("[DIRECT-AUDIO] writer initialized → \(directAudioURL.lastPathComponent)")
            } else {
                NSLog("[DIRECT-AUDIO] canAdd(input) returned false — writer not usable")
            }
        } else {
            NSLog("[DIRECT-AUDIO] failed to create AVAssetWriter")
        }

        NSLog("[SampleHandler] started — container: \(container.path)")
        NSLog("[SampleHandler] BUILD-CHECK-\(Date()) started")
    }

    override func broadcastPaused()  {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        notify(kDarwinStopNotif)
        audioListBuffer?.deallocate()
        audioListBuffer = nil
        audioListBufferSize = 0
        audioSeq = 0

        // ── DIRECT-CAPTURE DIAGNOSTIC: finalize ─────────────────────────────
        // Synchronous on purpose — broadcastFinished() is the extension's
        // last chance to run any code at all before the process is torn
        // down, so this can't be fire-and-forget the way the main pipeline
        // is elsewhere.
        directAudioQueue.sync {
            guard let writer = directAudioWriter else { return }
            directAudioInput?.markAsFinished()
            let sem = DispatchSemaphore(value: 0)
            writer.finishWriting { sem.signal() }
            _ = sem.wait(timeout: .now() + 5)
            NSLog("[DIRECT-AUDIO] finalized, status=\(writer.status.rawValue) "
                  + "error=\(String(describing: writer.error))")
        }

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
                return
            }
            guard let data = serialiseAudio(sampleBuffer) else { return }
            writeAudioSample(data)

            // ── DIRECT-CAPTURE DIAGNOSTIC ────────────────────────────────────
            // Append the ORIGINAL sampleBuffer directly — no serialization,
            // no host-side reconstruction. Isolated on its own dispatch
            // queue so any issue here can never affect the main pipeline
            // above.
            appendDirectAudio(sampleBuffer)

        case .audioMic:
            // Still intentionally dropped: this extension has no mic
            // permission of its own in this app's configuration, and the
            // teacher's mic is already covered by the LiveKit tap.
            return

        @unknown default:
            return
        }
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

        // Reuse the cached buffer across calls — only (re)allocate if it
        // doesn't exist yet or this frame genuinely needs more room than
        // what's cached (channel count/format is stable for the life of a
        // session, so growth here should be rare to never in practice).
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

    // ── DIRECT-CAPTURE DIAGNOSTIC ────────────────────────────────────────────
    //
    // Appends the ORIGINAL CMSampleBuffer straight from ReplayKit into an
    // AVAssetWriterInput running inside THIS process (the extension) —
    // exactly the CMSampleBuffer, untouched, that ReplayKit itself handed
    // us. There is no serialization, no IPC, no manual ASBD/CMBlockBuffer
    // reconstruction anywhere in this path. If the resulting file is
    // clean, every bug we've chased in the serialize→queue→reconstruct
    // pipeline becomes moot — this becomes the real fix, not just a test.
    private func appendDirectAudio(_ sampleBuffer: CMSampleBuffer) {
        directAudioQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.directAudioWriter,
                  let input = self.directAudioInput
            else { return }

            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.directAudioSessionStarted = true
                NSLog("[DIRECT-AUDIO] session started")
            }
            guard self.directAudioSessionStarted, writer.status == .writing else { return }
            guard input.isReadyForMoreMediaData else { return }
            if !input.append(sampleBuffer) {
                NSLog("[DIRECT-AUDIO] append FAILED — status=\(writer.status.rawValue) "
                      + "error=\(String(describing: writer.error))")
            }
        }
    }

    private func write(_ data: Data, to url: URL?, notif: String) {
        guard let url = url else { return }
        // Write atomically so the host app never reads a partial file.
        try? data.write(to: url, options: .atomic)
        notify(notif)
    }

    /// Writes ONE audio sample to its own file in the queue directory and
    /// posts the audio Darwin notification. Deliberately never reuses a
    /// filename — each call gets the next sequence number, so there is
    /// nothing for a fast producer / slower consumer to race over (unlike
    /// the old single fixed-file design, which could get overwritten
    /// before the host read it, or read twice yielding a duplicate
    /// timestamp — see this file's header comment for why that silenced
    /// audio after the very first sample).
    private func writeAudioSample(_ data: Data) {
        guard let dir = audioQueueDirURL else { return }
        let seq = audioSeq
        audioSeq += 1
        let fileURL = dir.appendingPathComponent("aud_\(paddedSeq(seq)).bin")
        try? data.write(to: fileURL, options: .atomic)
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