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
//   1. SampleHandler serialises each video frame into a binary blob.
//   2. Writes it atomically to the App Group shared container:
//        <AppGroup>/broadcast_frame.bin
//   3. Posts a Darwin notification:  "…flutter_education_app.frame"
//   4. AppDelegate receives the notification (Darwin center crosses the
//      sandbox boundary safely), reads the file, decodes, and writes to
//      the AVAssetWriter recording chunk.
//   5. On broadcast end, posts "…flutter_education_app.stop".
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

private let kAppGroup         = "group.com.example.flutterEducationApp"
private let kDarwinFrameNotif = "com.example.flutter_education_app.frame"
private let kDarwinStopNotif  = "com.example.flutter_education_app.stop"
private let kFrameFileName    = "broadcast_frame.bin"

class SampleHandler: RPBroadcastSampleHandler {

    // Resolved once in broadcastStarted() and reused for every frame.
    private var frameFileURL: URL?

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
        // Only forward video frames. Audio is captured cleanly by
        // RPScreenRecorder in the host app (with LiveKit AEC/NS applied),
        // so sending extension audio would produce duplicates.
        guard sampleBufferType == .video,
              CMSampleBufferIsValid(sampleBuffer) else { return }

        guard let data = serialise(sampleBuffer) else { return }
        write(data)
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

    // ── File write + Darwin notification ──────────────────────────────────────

    private func write(_ data: Data) {
        guard let url = frameFileURL else { return }
        // Write atomically so the host app never reads a partial file.
        try? data.write(to: url, options: .atomic)
        notify(kDarwinFrameNotif)
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