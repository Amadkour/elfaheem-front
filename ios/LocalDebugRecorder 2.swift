import AVFoundation
import Photos
import UIKit

/// TEMP DIAGNOSTIC TOOL (2026-07-29) — NOT part of the production pipeline.
///
/// Runs a SEPARATE, single, non-rotating AVAssetWriter session in parallel
/// to the normal chunked recorder, and saves the result directly to the
/// Photos gallery when stopped. This is deliberately NOT another 5-second
/// rotating chunk writer — the whole point is to remove chunk-boundary
/// timing and the upload/backend pipeline from the picture entirely, so
/// you can watch the exact same captured audio on-device, immediately,
/// with nothing else in between.
///
/// USAGE:
///   1. Call `LocalDebugRecorder.shared.start()` at the same point your
///      normal recording starts (e.g. right after `beginChunkWriter` for
///      chunk #0).
///   2. In the SAME functions where you append to the main pipeline's
///      videoInput / audioInput / systemAudioInput, ALSO call the
///      matching LocalDebugRecorder.shared.appendVideo/appendMic/
///      appendSystemAudio with the exact same sampleBuffer. See the
///      call-site notes below each function.
///   3. Call `LocalDebugRecorder.shared.stopAndSaveToPhotos()` when the
///      session ends. It finalizes the file and saves it to Photos; you
///      can then play it directly from the Photos app on the device.
///
/// REQUIRES: add this key to Info.plist (host app target, not the
/// broadcast extension) if not already present:
///   NSPhotoLibraryAddUsageDescription
///     "Used temporarily to save a diagnostic copy of screen-share
///      recordings for debugging audio issues."
final class LocalDebugRecorder {

    static let shared = LocalDebugRecorder()
    private init() {}

    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var sysInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?

    private let queue = DispatchQueue(label: "com.softkour.alfaheem.localdebugrecorder")

    // MARK: - Start

    /// Call once, at the same point the main pipeline starts its first
    /// chunk writer. videoSize should match what beginChunkWriter uses.
    func start(videoWidth: Int, videoHeight: Int) {
        queue.async {
            guard self.writer == nil else {
                NSLog("[LOCAL-DEBUG] start() called but a session is already active — ignoring")
                return
            }

            let tempDir = FileManager.default.temporaryDirectory
            let url = tempDir.appendingPathComponent("local_debug_\(UUID().uuidString).mp4")
            self.outputURL = url

            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
                NSLog("[LOCAL-DEBUG] Failed to create AVAssetWriter")
                return
            }

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: videoWidth,
                AVVideoHeightKey: videoHeight,
            ]
            let vi = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vi.expectsMediaDataInRealTime = true
            if writer.canAdd(vi) { writer.add(vi) }
            self.videoInput = vi

            // Mic: mono, matches main pipeline's aSettings.
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000,
            ]
            let mi = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            mi.expectsMediaDataInRealTime = true
            if writer.canAdd(mi) { writer.add(mi) }
            self.micInput = mi

            // System audio: STEREO — matches the hypothesis fix applied to
            // the main pipeline's systemAudioInput. Change to mono here too
            // if you revert that change, so this stays a fair comparison.
            let sysSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ]
            let si = AVAssetWriterInput(mediaType: .audio, outputSettings: sysSettings)
            si.expectsMediaDataInRealTime = true
            if writer.canAdd(si) { writer.add(si) }
            self.sysInput = si

            self.writer = writer
            self.sessionStarted = false
            NSLog("[LOCAL-DEBUG] Recorder initialized → \(url.lastPathComponent)")
        }
    }

    // MARK: - Append (call alongside the main pipeline's own append calls)

    /// Call this in the SAME place the main pipeline appends to its own
    /// videoInput (search for `videoInput?.append(` in AppDelegate.swift —
    /// call this right after, passing the identical sampleBuffer).
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard let writer = self.writer, let vi = self.videoInput else { return }
            if writer.status == .unknown {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                self.sessionStarted = true
                NSLog("[LOCAL-DEBUG] Writer session started")
            }
            guard self.sessionStarted, vi.isReadyForMoreMediaData else { return }
            if !vi.append(sampleBuffer) {
                NSLog("[LOCAL-DEBUG] video append FAILED — status=\(writer.status.rawValue) error=\(String(describing: writer.error))")
            }
        }
    }

    /// Call alongside the main pipeline's audioInput (mic) append.
    func appendMic(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard self.sessionStarted, let mi = self.micInput, mi.isReadyForMoreMediaData else { return }
            if !mi.append(sampleBuffer) {
                NSLog("[LOCAL-DEBUG] mic append FAILED")
            }
        }
    }

    /// Call alongside the main pipeline's systemAudioInput (shared-app
    /// audio) append — same sampleBuffer, right after the main pipeline's
    /// own `systemAudioInput?.append(sampleBuffer)` call in
    /// appendSystemAudioSample.
    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        queue.async {
            guard self.sessionStarted, let si = self.sysInput, si.isReadyForMoreMediaData else { return }
            if !si.append(sampleBuffer) {
                NSLog("[LOCAL-DEBUG] system-audio append FAILED")
            }
        }
    }

    // MARK: - Stop + save to Photos

    /// Call when the recording session ends. Finalizes the local file and
    /// saves it directly to the Photos library. Requires Photos
    /// "add-only" permission (NSPhotoLibraryAddUsageDescription) — iOS
    /// will prompt automatically on first call if not yet granted.
    func stopAndSaveToPhotos(completion: ((Bool, Error?) -> Void)? = nil) {
        queue.async {
            guard let writer = self.writer, let url = self.outputURL else {
                completion?(false, nil)
                return
            }
            self.videoInput?.markAsFinished()
            self.micInput?.markAsFinished()
            self.sysInput?.markAsFinished()

            writer.finishWriting {
                NSLog("[LOCAL-DEBUG] Finalized: \(url.path) size="
                      + "\((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) ?? "?")")

                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        NSLog("[LOCAL-DEBUG] Photos permission not granted (status=\(status.rawValue))")
                        completion?(false, nil)
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }) { success, error in
                        if success {
                            NSLog("[LOCAL-DEBUG] ✅ Saved to Photos gallery")
                        } else {
                            NSLog("[LOCAL-DEBUG] ❌ Failed to save to Photos: \(String(describing: error))")
                        }
                        // Clean up the temp file either way.
                        try? FileManager.default.removeItem(at: url)
                        self.writer = nil
                        self.videoInput = nil
                        self.micInput = nil
                        self.sysInput = nil
                        self.sessionStarted = false
                        self.outputURL = nil
                        completion?(success, error)
                    }
                }
            }
        }
    }
}
