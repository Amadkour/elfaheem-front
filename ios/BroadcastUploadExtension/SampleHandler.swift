// SampleHandler.swift
// BroadcastUploadExtension target
//
// This runs in a separate Apple process when the user taps "Start Broadcast"
// from the iOS system picker.  It receives every screen frame + mic/app audio
// sample buffer from ReplayKit, serialises them, and writes them into a shared
// CFMessagePort so the main Runner app can read and publish them via LiveKit.
//
// Architecture:
//   Extension process  →  CFMessagePort (local)  →  Main app process
//
// The main app registers a CFMessagePortCreateLocal receiver in AppDelegate.
// The extension writes each sample buffer as:
//   [4-byte type][8-byte pts_ns][4-byte size][<size>-byte data]
//
// Buffer types (match AppDelegate constants):
//   0 = video, 1 = audioMic, 2 = audioApp, 99 = stop signal

import ReplayKit
import CoreMedia
import CoreVideo

private let kPortName = "com.example.flutter_education_app.broadcast"

class SampleHandler: RPBroadcastSampleHandler {

    private var port: CFMessagePort?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        // Open the port the main app registered.
        // The main app calls registerBroadcastPort() before showing the picker,
        // so the port should exist by the time broadcastStarted() fires.
        // We retry once after a short delay to handle any tiny race window.
        port = CFMessagePortCreateRemote(nil, kPortName as CFString)
        if port == nil {
            // Give the main app one extra moment then retry.
            Thread.sleep(forTimeInterval: 0.5)
            port = CFMessagePortCreateRemote(nil, kPortName as CFString)
        }
        if port == nil {
            let err = NSError(domain: "BroadcastError", code: 0,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Could not connect to the main app. " +
                                "Make sure the app is open and try again."])
            finishBroadcastWithError(err)
            return
        }
        NSLog("[SampleHandler] connected to main app port")
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        sendStop()
        if let p = port { CFMessagePortInvalidate(p); port = nil }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        let typeId: UInt32
        switch sampleBufferType {
        case .video:    typeId = 0
        case .audioMic: typeId = 1
        case .audioApp: typeId = 2
        @unknown default: return
        }

        guard let data = serialise(sampleBuffer, type: typeId) else { return }
        send(data)
    }

    // ─── Serialisation ────────────────────────────────────────────────────────

    private func serialise(_ sb: CMSampleBuffer, type: UInt32) -> Data? {
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        let ptsNs = UInt64(CMTimeGetSeconds(pts) * 1_000_000_000)

        // For video: encode as JPEG to keep IPC payload small.
        // For audio: copy raw PCM bytes from the block buffer.
        let payload: Data
        if type == 0 {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sb) else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext()
            guard let jpegData = context.jpegRepresentation(of: ciImage,
                                                             colorSpace: CGColorSpaceCreateDeviceRGB(),
                                                             options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.6]) else { return nil }
            payload = jpegData
        } else {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sb) else { return nil }
            var length = 0
            var dataPtr: UnsafeMutablePointer<Int8>? = nil
            guard CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                              lengthAtOffsetOut: nil,
                                              totalLengthOut: &length,
                                              dataPointerOut: &dataPtr) == noErr,
                  let ptr = dataPtr else { return nil }
            payload = Data(bytes: ptr, count: length)
        }

        var out = Data(capacity: 4 + 8 + 4 + payload.count)
        var t = type.bigEndian
        var p = ptsNs.bigEndian
        var s = UInt32(payload.count).bigEndian
        out.append(Data(bytes: &t, count: 4))
        out.append(Data(bytes: &p, count: 8))
        out.append(Data(bytes: &s, count: 4))
        out.append(payload)
        return out
    }

    private func send(_ data: Data) {
        guard let port = port else { return }
        let cfData = data as CFData
        CFMessagePortSendRequest(port, 0, cfData, 0, 0, nil, nil)
    }

    private func sendStop() {
        var typeId = UInt32(99).bigEndian
        var zero8  = UInt64(0).bigEndian
        var zero4  = UInt32(0).bigEndian
        var data = Data(capacity: 16)
        data.append(Data(bytes: &typeId, count: 4))
        data.append(Data(bytes: &zero8,  count: 8))
        data.append(Data(bytes: &zero4,  count: 4))
        send(data)
    }
}