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
//   2. Writes it atomically to the App Group shared container:
//        <AppGroup>/broadcast_frame.bin   (video)
//        <AppGroup>/broadcast_audio.bin   (system/app audio)
//   3. Posts a Darwin notification per type: "…flutter_education_app.frame"
//      / "…flutter_education_app.audioframe".
//   4. AppDelegate receives the notification (Darwin center crosses the
//      sandbox boundary safely), reads the corresponding file, decodes,
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

private let kAppGroup         = "group.com.softkour.alfaheem"
private let kDarwinFrameNotif = "com.example.flutter_education_app.frame"
// NEW: system/app audio (the audio OF the app being shared — e.g. a video
// or game playing on the shared screen). This is a SEPARATE file+notification
// pair from the video frame, deliberately — video and audio buffers arrive
// concurrently from ReplayKit on independent internal queues, and reusing a
// single "last write wins" file for both would silently drop whichever one
// lost the race, exactly like the original single-file design would if we
// crammed both types through it.
private let kDarwinAudioNotif = "com.example.flutter_education_app.audioframe"
private let kDarwinStopNotif  = "com.example.flutter_education_app.stop"
private let kFrameFileName    = "broadcast_frame.bin"
private let kAudioFileName    = "broadcast_audio.bin"

class SampleHandler: RPBroadcastSampleHandler {

    // Resolved once in broadcastStarted() and reused for every frame.
    private var frameFileURL: URL?
    private var audioFileURL: URL?

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
        audioFileURL = container.appendingPathComponent(kAudioFileName)
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
            guard let data = serialiseAudio(sampleBuffer) else { return }
            write(data, to: audioFileURL, notif: kDarwinAudioNotif)

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

    private func write(_ data: Data, to url: URL?, notif: String) {
        guard let url = url else { return }
        // Write atomically so the host app never reads a partial file.
        try? data.write(to: url, options: .atomic)
        notify(notif)
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