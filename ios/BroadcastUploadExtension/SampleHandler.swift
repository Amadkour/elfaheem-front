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
//   2. Writes it to the App Group shared container:
//        <AppGroup>/broadcast_frame.bin              (video — single
//                                                       "mailbox" file,
//                                                       overwritten each
//                                                       frame; fine because
//                                                       video arrives slowly,
//                                                       every ~33-100ms)
//        <AppGroup>/broadcast_audio_queue/aud_NNNNNNNNNN.bin   (system/app
//                                                       audio — see note
//                                                       below for why this
//                                                       one is a QUEUE, not
//                                                       a single file)
//   3. Posts a Darwin notification per type: "…flutter_education_app.frame"
//      / "…flutter_education_app.audioframe".
//   4. AppDelegate receives the notification (Darwin center crosses the
//      sandbox boundary safely), reads the corresponding file(s), decodes,
//      and writes to the AVAssetWriter recording chunk.
//   5. On broadcast end, posts "…flutter_education_app.stop".
//
//   WHY AUDIO USES A QUEUE DIRECTORY INSTEAD OF ONE FILE (unlike video):
//   .audioApp buffers arrive every ~10-25ms — much faster than video frames,
//   on the same order as the cross-process notify→read→decode round trip.
//   A single "last write wins" file for something arriving that fast causes
//   two failure modes at once: (a) this handler overwrites the file with
//   buffer N+1 before the host has read buffer N, silently losing N; and
//   (b) since Darwin notifications carry no payload and aren't guaranteed
//   1:1 with posts, the host's serialized read tasks can fire twice before
//   this handler writes anything new, so it reads the SAME file content
//   twice — which decodes to the exact same timestamp and gets rejected as
//   "non-monotonic" on the host side. In practice that dropped the large
//   majority of shared-app audio for the ENTIRE broadcast (not just at the
//   edges), which is what actually made screen-share recordings come out
//   with no shared-app sound. Giving every buffer its own sequentially
//   numbered file turns the Darwin notification into a plain "there's new
//   work, go look" wake-up instead of a fragile 1-buffer mailbox — the host
//   drains whatever has piled up, in order, and nothing is silently
//   clobbered or double-read.
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

private let kAppGroup          = "group.com.softkour.alfaheem"
private let kDarwinFrameNotif  = "com.example.flutter_education_app.frame"
// NEW: system/app audio (the audio OF the app being shared — e.g. a video
// or game playing on the shared screen). Deliberately its own Darwin
// notification, separate from the video frame notification — but note this
// is now backed by a QUEUE DIRECTORY, not a single file (see header comment
// above for why: .audioApp buffers arrive far too fast for a 1-slot mailbox
// to keep up with, which was silently eating almost all of this audio).
private let kDarwinAudioNotif  = "com.example.flutter_education_app.audioframe"
private let kDarwinStopNotif   = "com.example.flutter_education_app.stop"
private let kFrameFileName     = "broadcast_frame.bin"
private let kAudioQueueDirName = "broadcast_audio_queue"
// Filenames are zero-padded so lexicographic directory listing order is
// also numeric/chronological order — the host just needs to sort the
// directory listing, no need to parse/compare anything.
private let kAudioSeqPad = 10

class SampleHandler: RPBroadcastSampleHandler {

    // Resolved once in broadcastStarted() and reused for every frame.
    private var frameFileURL: URL?
    private var audioQueueDirURL: URL?
    // Monotonically increasing per-broadcast sequence number, one per
    // .audioApp buffer written. Encoded into the filename so the host can
    // drain the directory in the exact order buffers were produced.
    private var audioSeq: UInt64 = 0
    // Soft cap on how many not-yet-consumed audio files can pile up in the
    // queue directory. Under normal conditions the host drains this almost
    // as fast as it's written; this only protects against runaway disk
    // usage in the App Group container in the pathological case where the
    // host stops reading entirely (e.g. suspended) for an extended period.
    // ~1200 files at a ~15ms buffer interval is ~18s of buffered audio.
    private let kAudioQueueSoftCap = 1200

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

        let queueDir = container.appendingPathComponent(kAudioQueueDirName)
        // Clear out anything left over from a previous broadcast (e.g. one
        // that crashed or was force-stopped before the host finished
        // draining it) so stale audio never leaks into a new recording.
        try? FileManager.default.removeItem(at: queueDir)
        try? FileManager.default.createDirectory(
            at: queueDir, withIntermediateDirectories: true
        )
        audioQueueDirURL = queueDir
        audioSeq = 0

        NSLog("[SampleHandler] started — container: \(container.path)")
    }

    override func broadcastPaused()  {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        notify(kDarwinStopNotif)
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
            // This is the audio OF THE SHARED APP/SCREEN (e.g. a video or
            // game playing on the foreign app being broadcast) — genuinely
            // different content from the teacher's own mic, which is
            // already forwarded separately in the host app via the LiveKit
            // audio tap (see room.dart's _startLiveKitAudioTap). Forwarding
            // this too lets the recording include both.
            //
            // Queued write (own file per buffer), NOT the single-mailbox
            // `write()` used for video — see the header comment for why.
            guard let data = serialiseAudio(sampleBuffer) else { return }
            writeQueuedAudio(data)

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

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr,
              let buffer = audioBufferList.mBuffers.mData,
              audioBufferList.mBuffers.mDataByteSize > 0 else { return nil }

        let pcmData = Data(bytes: buffer, count: Int(audioBufferList.mBuffers.mDataByteSize))
        let sampleRate = UInt32(asbd.mSampleRate)
        let channels   = asbd.mChannelsPerFrame
        let isFloat: UInt32 = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0 ? 1 : 0

        var payload = Data(capacity: 9 + pcmData.count)
        var sr = sampleRate.bigEndian
        var ch = channels.bigEndian
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
    }

    // ── File write + Darwin notification ──────────────────────────────────────

    /// Single-"mailbox"-file write, used only for video frames. Video
    /// arrives slowly enough (~33-100ms apart) that overwrite-and-notify is
    /// fine — occasionally losing a frame to the race is imperceptible.
    /// Do NOT use this for .audioApp; see writeQueuedAudio below.
    private func write(_ data: Data, to url: URL?, notif: String) {
        guard let url = url else { return }
        // Write atomically so the host app never reads a partial file.
        try? data.write(to: url, options: .atomic)
        notify(notif)
    }

    /// Queued write for .audioApp buffers: each buffer gets its OWN file
    /// (sequence-numbered) instead of overwriting a shared one. This is
    /// the actual fix for shared-app audio going missing from recordings —
    /// see the header comment for the full explanation of why a single
    /// mailbox file can't keep up with ~10-25ms audio buffer intervals.
    /// The Darwin notification here is just a "go check the directory"
    /// wake-up; it's fine (and expected) if several of these coalesce into
    /// fewer deliveries, since the host always drains everything present.
    private func writeQueuedAudio(_ data: Data) {
        guard let dir = audioQueueDirURL else { return }

        audioSeq += 1
        // Manual zero-padding rather than String(format: "%d", …) — %d
        // expects Int32 in Swift's C-variadic bridging, which is not a
        // reliable match for UInt64 on every platform/architecture.
        let seqStr = String(audioSeq)
        let padded = String(repeating: "0", count: max(0, kAudioSeqPad - seqStr.count)) + seqStr
        let name   = "aud_\(padded).bin"
        let url    = dir.appendingPathComponent(name)

        // Soft cap: if the host has stopped draining (e.g. suspended) for
        // long enough that a large backlog has built up, drop new buffers
        // rather than growing the App Group container without bound. This
        // only ever engages in a pathological stall — under normal
        // operation the host drains this directory continuously.
        if audioSeq % 100 == 0 {
            let pending = (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            ).count) ?? 0
            if pending > kAudioQueueSoftCap {
                NSLog("[SampleHandler] audio queue backlog (\(pending)) exceeds cap — dropping buffer")
                return
            }
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[SampleHandler] audio queue write failed: \(error)")
            return
        }
        notify(kDarwinAudioNotif)
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