// SampleUploader.swift
// BroadcastUploadExtension target
//
// UNTESTED (written on Windows, 2026-10-29) — see docs/live/ios_test_plan.md.
//
// FrameEncoder: ReplayKit video sample → downscaled JPEG (ONE CIContext for
// the whole broadcast). SampleUploader: sends one encoded frame at a time to
// flutter_webrtc over SocketConnection, framed exactly like the reference
// extension shipped with livekit_client 2.13.1 (example/ios/LiveKit Broadcast
// Extension/SampleUploader.swift):
//
//     HTTP/1.1 200 OK                       ← CFHTTPMessageCreateResponse(200)
//     Content-Length: <jpeg bytes>
//     Buffer-Width: <jpeg width>
//     Buffer-Height: <jpeg height>
//     Buffer-Orientation: <RPVideoSampleOrientationKey, CGImagePropertyOrientation>
//     <blank line>
//     <JPEG>
//
// flutter_webrtc's FlutterSocketConnectionFrameReader (fork, ios/flutter_webrtc/
// Sources/flutter_webrtc/Broadcast/FlutterSocketConnectionFrameReader.m) parses
// that with CFHTTPMessageAppendBytes, creates a BGRA CVPixelBuffer of exactly
// Buffer-Width × Buffer-Height, renders the JPEG into it with its own CIContext
// and turns Buffer-Orientation into the RTCVideoFrame rotation. So the width /
// height headers MUST be the JPEG's real pixel size — that is why the scaled
// image is cropped to integer dimensions below.
//
// Differences from the reference (all on purpose):
//   • the header is serialised WITHOUT the body and the JPEG is streamed
//     after it, so the JPEG is never copied into a second "whole message"
//     Data (the bytes on the wire are identical);
//   • the frame is downscaled (reference: full resolution, quality 1.0 —
//     several MB per frame on a modern iPhone, the main jetsam risk, I4);
//   • the pending message is assigned on the serial queue (the reference
//     wrote `dataToSend` from ReplayKit's thread while the queue read it).
//
// ── Memory budget (broadcast upload extensions are killed at ~50 MB) ──────
//   Per frame, worst case, 1280 px long side (detail mode 1920):
//     ReplayKit's own NV12 buffer          ~4.5 MB  (owned by ReplayKit, reused)
//     CI render target, BGRA 590×1280       ~3.0 MB  (886×1920: ~6.8 MB)
//     JPEG, q 0.70 / 0.80                  ~0.1–0.4 MB
//     HTTP header                           <1 KB
//     recording record (file write)        streamed, no copy (see writeFrameFile)
//   Steady state ≈ 8–15 MB for the whole extension (Swift runtime, ReplayKit,
//   CoreImage caches with cacheIntermediates off). Measure with the
//   "Allocations" + "VM Tracker" instruments on the extension process (test
//   plan §5). At most ONE frame is encoded / in flight at a time: while the
//   socket is still sending the previous one, new frames are skipped.

import Foundation
import ReplayKit
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO

/// One encoded frame. `jpeg` is shared by the live socket and the recording file.
struct EncodedFrame {
    let jpeg: Data
    let width: Int
    let height: Int
    /// CGImagePropertyOrientation raw value from RPVideoSampleOrientationKey.
    let orientation: UInt32
    /// Presentation time of the ReplayKit sample, nanoseconds (host clock).
    let ptsNs: UInt64
}

final class FrameEncoder {
    // Creating a CIContext is expensive and it keeps GPU resources; one per
    // broadcast (I4). Intermediates are not cached: every frame is new.
    private let context = CIContext(options: [
        .cacheIntermediates: false,
    ])
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// Long side of the encoded frame. 1280 keeps text readable on a
    /// phone screen share and fits WebRTC's 1080p15 screen-share preset.
    static let normalLongSide = 1280
    /// "Detail" mode (small text, spreadsheets): ~2.3× the pixels.
    static let detailLongSide = 1920

    func encode(_ sample: CMSampleBuffer, detail: Bool) -> EncodedFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let srcW = CVPixelBufferGetWidth(pixelBuffer)
        let srcH = CVPixelBufferGetHeight(pixelBuffer)
        guard srcW > 0, srcH > 0 else { return nil }

        let maxLong = detail ? Self.detailLongSide : Self.normalLongSide
        let longSide = max(srcW, srcH)
        let scale = longSide > maxLong ? Double(maxLong) / Double(longSide) : 1.0
        // Even, integer output size: the header must equal the JPEG's size,
        // and I420 (what flutter_webrtc converts to) wants even dimensions.
        let dstW = max(2, (Int(Double(srcW) * scale) / 2) * 2)
        let dstH = max(2, (Int(Double(srcH) * scale) / 2) * 2)

        let orientation = (CMGetAttachment(
            sample, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil
        ) as? NSNumber)?.uint32Value ?? 0

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let seconds = CMTIME_IS_VALID(pts) ? CMTimeGetSeconds(pts) : 0
        let ptsNs = UInt64(max(0, seconds * 1_000_000_000))

        return autoreleasepool { () -> EncodedFrame? in
            let sx = CGFloat(dstW) / CGFloat(srcW)
            let sy = CGFloat(dstH) / CGFloat(srcH)
            let image = CIImage(cvPixelBuffer: pixelBuffer)
                .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                .cropped(to: CGRect(x: 0, y: 0, width: dstW, height: dstH))
            let quality: Float = detail ? 0.80 : 0.70
            let options: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
            ]
            guard let jpeg = context.jpegRepresentation(
                of: image, colorSpace: image.colorSpace ?? sRGB, options: options
            ) else { return nil }
            return EncodedFrame(jpeg: jpeg, width: dstW, height: dstH,
                                orientation: orientation, ptsNs: ptsNs)
        }
    }
}

final class SampleUploader {
    private static let bufferMaxLength = 10_240   // same chunk size as the reference

    private let connection: SocketConnection
    private let serialQueue = DispatchQueue(label: "broadcast.sampleUploader")

    // Ready = socket open and no message in flight. Read on ReplayKit's
    // thread, written on the network / serial queues.
    private let readyLock = NSLock()
    private var _isReady = false
    var isReady: Bool {
        readyLock.lock(); defer { readyLock.unlock() }
        return _isReady
    }
    private func setReady(_ value: Bool) {
        readyLock.lock(); _isReady = value; readyLock.unlock()
    }

    // In-flight message: header, then the JPEG. Touched on serialQueue only.
    private var segments: [Data] = []
    private var segmentIndex = 0
    private var byteIndex = 0

    init(connection: SocketConnection) {
        self.connection = connection
        connection.didOpen = { [weak self] in self?.setReady(true) }
        connection.streamHasSpaceAvailable = { [weak self] in
            self?.serialQueue.async {
                guard let self = self else { return }
                // Same state machine as the reference: when nothing is left
                // to write on a "space available" event, we are ready for
                // the next frame (no further events come until we write).
                if !self.sendDataChunk() { self.setReady(true) }
            }
        }
    }

    /// Queues one frame if the previous one has been fully written.
    /// Returns false (frame skipped) while a frame is still in flight.
    @discardableResult
    func send(_ frame: EncodedFrame) -> Bool {
        readyLock.lock()
        guard _isReady else { readyLock.unlock(); return false }
        _isReady = false
        readyLock.unlock()

        guard let header = Self.header(for: frame) else {
            setReady(true)
            return false
        }
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            self.segments = [header, frame.jpeg]
            self.segmentIndex = 0
            self.byteIndex = 0
            self.sendDataChunk()
        }
        return true
    }

    /// Writes at most one chunk. Returns false when nothing was pending.
    @discardableResult
    private func sendDataChunk() -> Bool {
        guard segmentIndex < segments.count else {
            segments = []
            return false
        }
        let data = segments[segmentIndex]
        let bytesLeft = data.count - byteIndex
        let length = min(bytesLeft, Self.bufferMaxLength)
        let written: Int = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return connection.writeToStream(buffer: base.advanced(by: byteIndex), maxLength: length)
        }
        if written > 0 {
            byteIndex += written
            if byteIndex >= data.count {
                segmentIndex += 1
                byteIndex = 0
                if segmentIndex >= segments.count { segments = [] ; segmentIndex = 0 }
            }
        } else {
            NSLog("[SampleUploader] write failed (\(written))")
        }
        return true
    }

    /// The reference's header block (status line + the four fields + blank
    /// line), written by hand instead of CFHTTPMessageCopySerializedMessage on a
    /// body-less message, so nothing can rewrite Content-Length. The reader
    /// only needs a complete header (CFHTTPMessageIsHeaderComplete) and these
    /// four fields (CFHTTPMessageCopyHeaderFieldValue); field order is free.
    private static func header(for frame: EncodedFrame) -> Data? {
        let text = "HTTP/1.1 200 OK\r\n"
            + "Content-Length: \(frame.jpeg.count)\r\n"
            + "Buffer-Width: \(frame.width)\r\n"
            + "Buffer-Height: \(frame.height)\r\n"
            + "Buffer-Orientation: \(frame.orientation)\r\n"
            + "\r\n"
        return text.data(using: .ascii)
    }
}
