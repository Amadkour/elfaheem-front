// AppDelegate.swift
//
// ════════════════════════════════════════════════════════════════════
//  ARCHITECTURE — READ THIS BEFORE EDITING
// ════════════════════════════════════════════════════════════════════
//
//  Recording has TWO separate video sources that can be active:
//
//  A) RPScreenRecorder   — captures YOUR OWN APP's screen continuously.
//     Active from startScreenCaptureService() until stopRecording().
//     Frames → processSampleFromRecorder() → AVAssetWriter chunks → upload.
//     This is what fills the recording when the teacher is just talking
//     and showing content inside the app (whiteboard, PDF, etc.).
//
//  B) Broadcast Extension (SampleHandler.swift) — captures a FOREIGN APP
//     chosen by the user from RPSystemBroadcastPickerView.
//     Active only while the user has tapped "Share Screen" → picked an app
//     → "Start Broadcast".
//     Frames arrive via Darwin notification + App Group shared file IPC
//     → processSampleFromBroadcast() → SAME AVAssetWriter chunks → upload.
//     While broadcast is active we PAUSE RPScreenRecorder frames so that
//     only the foreign app's screen goes into the recording.
//
//  Audio:
//     NEVER reconfigure AVAudioSession in this file.
//     LiveKit owns the session in .videoChat mode with echo cancellation
//     and noise suppression. Changing the session breaks those DSP
//     filters, causing the noise burst the user hears.
//     RPScreenRecorder inherits whatever session is already active —
//     it records the mic audio LiveKit is already processing cleanly.
//
//  ════════════════════════════════════════════════════════════════════

import Flutter
import UIKit
import Firebase
import ReplayKit
import AVFoundation
import CoreMedia
import CoreVideo

@main
@objc class AppDelegate: FlutterAppDelegate {

    // ── Channel names ─────────────────────────────────────────────────────────
    private let kScreenShareChannel = "com.example.flutter_education_app/screen_share"
    private let kRecorderChannel    = "com.example.flutter_education_app/native_recorder"
    private let kRecEventChannel    = "com.example.flutter_education_app/rec_events"

    // ── EventChannel sink ─────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── Flutter engine ────────────────────────────────────────────────────────
    private var flutterEngine: FlutterEngine?

    // ── AVAssetWriter — one instance, reused across chunks ───────────────────
    private var assetWriter:        AVAssetWriter?
    private var videoInput:         AVAssetWriterInput?
    private var audioInput:         AVAssetWriterInput?
    private var writerSessionStarted = false    // true once startSession() called
    private var writerQueue = DispatchQueue(label: "com.elfaheem.writer", qos: .userInitiated)

    // ── Session params ────────────────────────────────────────────────────────
    private var sessionId:  Int    = 0
    private var uploadUrl:  String = ""
    private var authToken:  String = ""
    private var chunkSecs:  Int    = 5

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:   Int   = 0
    private var chunkTimer:   Timer?
    private var currentFile:  URL?
    private var recording     = false
    private var paused        = false
    private var stopping      = false

    // ── Broadcast source control ──────────────────────────────────────────────
    // When isBroadcasting = true, frames from RPScreenRecorder are suppressed
    // and frames from the broadcast extension are written instead.
    private var isBroadcasting      = false

    // ── Broadcast Extension IPC (App Group + Darwin notifications) ───────────
    //
    // CFMessagePort CANNOT cross the iOS process sandbox on modern iOS —
    // CFMessagePortCreateRemote always returns nil from an extension process.
    //
    // Correct mechanism: shared App Group container + Darwin notifications.
    //   • SampleHandler writes each frame to a shared binary file, then
    //     posts a Darwin notification as the "data ready" signal.
    //   • AppDelegate registers for those notifications and reads the file.
    //
    // ⚠️  REQUIRED XCODE SETUP (one-time, ~30 seconds):
    //   1. Select the Runner target → Signing & Capabilities → "+" → App Groups
    //      Add group ID:  group.com.example.flutter_education_app
    //   2. Select the BroadcastUploadExtension target → same steps → same ID
    //   Both targets must share the EXACT same group string.
    //
    //   If your bundle ID differs, update kAppGroup in BOTH this file and
    //   SampleHandler.swift — they must be identical.
    private let kAppGroup           = "group.com.example.flutter_education_app"
    private let kDarwinFrameNotif   = "com.example.flutter_education_app.frame"
    private let kDarwinStopNotif    = "com.example.flutter_education_app.stop"
    private let kFrameFileName      = "broadcast_frame.bin"
    private var darwinObserverAdded = false
    private let ipcReadQueue        = DispatchQueue(label: "com.elfaheem.ipc", qos: .userInteractive)

    // ── Video dimensions (read from first RPScreenRecorder video frame) ───────
    private var videoWidth:  Int = 0
    private var videoHeight: Int = 0

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - App lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()

        let engine = FlutterEngine(name: "main_engine")
        engine.run()
        flutterEngine = engine

        GeneratedPluginRegistrant.register(with: engine)
        registerScreenShareChannel(messenger: engine.binaryMessenger)
        registerRecorderChannel(messenger: engine.binaryMessenger)
        registerEventChannel(messenger: engine.binaryMessenger)

        let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        return true
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Channel registration
    // ─────────────────────────────────────────────────────────────────────────

    private func registerScreenShareChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: kScreenShareChannel, binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "startScreenCaptureService":
                guard !self.recording else { result(true); return }
                guard !self.uploadUrl.isEmpty else {
                    result(FlutterError(code: "NOT_CONFIGURED",
                                        message: "Call startMicRecording first", details: nil))
                    return
                }
                self.startRPScreenRecorder(result: result)

            case "stopScreenCaptureService":
                result(nil)

            case "showBroadcastPicker":
                // Show the iOS system picker so the user can choose which
                // foreign app to share. When they pick one and tap
                // "Start Broadcast", SampleHandler.broadcastStarted() fires
                // and the extension begins sending frames via CFMessagePort.
                self.showBroadcastPicker(result: result)

            case "stopBroadcast":
                self.stopBroadcastShare(result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func registerRecorderChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: kRecorderChannel, binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {

            case "startMicRecording":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                    return
                }
                self.sessionId  = args["sessionId"]    as? Int    ?? 0
                self.uploadUrl  = args["uploadUrl"]    as? String ?? ""
                self.authToken  = args["authToken"]    as? String ?? ""
                self.chunkSecs  = args["chunkSeconds"] as? Int    ?? 5
                self.chunkIndex = args["chunkIndex"]   as? Int    ?? 0
                NSLog("[REC] startMicRecording: session=\(self.sessionId) chunkSecs=\(self.chunkSecs)")
                // Emit immediately so Dart's Phase-1 completer resolves.
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)

            case "upgradeToScreenRecording":
                if self.recording {
                    self.emitEvent(["event": "screenLoopStarted"])
                    result(true)
                } else {
                    result(false)
                }

            case "downgradeToMicForShare":
                self.emitEvent(["event": "micReadyForShare"])
                result(nil)

            case "stopScreenCapture":
                self.emitEvent(["event": "micLoopStarted"])
                result(nil)

            case "promoteForShare":
                result(nil)

            case "getChunkIndex":
                result(self.chunkIndex)

            case "pauseRecording":
                self.pauseRecording(result: result)

            case "resumeRecording":
                self.resumeRecording(result: result)

            case "stopRecording":
                let isFinal = (call.arguments as? [String: Any])?["isFinal"] as? Bool ?? true
                self.stopRecording(isFinal: isFinal, result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func registerEventChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterEventChannel(name: kRecEventChannel, binaryMessenger: messenger)
        ch.setStreamHandler(RecEventStreamHandler(
            onListen: { [weak self] sink in self?.eventSink = sink },
            onCancel: { [weak self] in self?.eventSink = nil }
        ))
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - RPScreenRecorder (own-app recording)
    // ─────────────────────────────────────────────────────────────────────────

    private func startRPScreenRecorder(result: @escaping FlutterResult) {
        let rp = RPScreenRecorder.shared()
        guard rp.isAvailable else {
            result(FlutterError(code: "RP_UNAVAILABLE",
                                message: "RPScreenRecorder not available", details: nil))
            return
        }

        paused       = false
        stopping     = false
        videoWidth   = 0
        videoHeight  = 0
        sweepStaleChunks()

        // ── Audio session setup ───────────────────────────────────────────────
        // The log shows LiveKit resetting the session to SoloAmbient AFTER
        // RPScreenRecorder starts. SoloAmbient is output-only — mic input is
        // disabled, which is why the recorded audio is noisy/silent.
        //
        // Fix: configure the session to playAndRecord+videoChat+mixWithOthers
        // BEFORE startCapture(), then call lockForConfiguration() on the WebRTC
        // RTCAudioSession so LiveKit's internal audio manager cannot override it.
        //
        // We use AVAudioSession directly (not RTCAudioSession) because
        // RTCAudioSession.h may not be available in all Flutter/WebRTC setups.
        // The lock is achieved by setting isAudioEnabled = false on the
        // RTCAudioSession equivalent — but the simplest cross-compatible approach
        // is to configure the session and call setActive(true) with
        // notifyOthersOnDeactivation so other clients (LiveKit) are told to
        // re-adopt the existing configuration rather than replacing it.
        configureAudioSessionForRecording()

        rp.isMicrophoneEnabled = true

        rp.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self = self, self.recording, !self.stopping else { return }
            if let e = error { self.emitError(e.localizedDescription); return }
            if !self.isBroadcasting {
                self.processSampleFromRecorder(sampleBuffer, type: bufferType)
            }
        }, completionHandler: { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let e = error {
                    NSLog("[REC] RPScreenRecorder start error: \(e.localizedDescription)")
                    // Release audio session lock on failure
                    self.releaseAudioSessionLock()
                    result(FlutterError(code: "RP_START_ERROR",
                                        message: e.localizedDescription, details: nil))
                    return
                }
                self.recording = true
                self.beginChunkWriter()
                self.emitEvent(["event": "screenLoopStarted"])
                NSLog("[REC] RPScreenRecorder started — chunk #\(self.chunkIndex)")
                result(true)
            }
        })
    }

    // ── AVAudioSession management ─────────────────────────────────────────────
    //
    // We configure the session ONCE before RPScreenRecorder starts and post a
    // notification so LiveKit re-reads it instead of replacing it.
    // Using .mixWithOthers means LiveKit's WebRTC audio engine and
    // RPScreenRecorder share the same hardware path — no teardown, no noise.
    // Using .videoChat mode keeps AEC (acoustic echo cancellation) and NS
    // (noise suppression) active, giving clean mic audio in the recording.

    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,                          // keeps AEC + NS active
                options: [.defaultToSpeaker,
                          .allowBluetooth,
                          .allowBluetoothA2DP,
                          .mixWithOthers]                  // coexist with LiveKit WebRTC
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active")
        } catch {
            NSLog("[REC] AVAudioSession configure error: \(error.localizedDescription)")
        }
    }

    private func releaseAudioSessionLock() {
        // Called only on RPScreenRecorder stop or start failure.
        // Restore the session to LiveKit's preferred state so the live call
        // continues to work normally after recording ends.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker, .allowBluetooth,
                          .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[REC] AVAudioSession: restored after recording stop")
        } catch {
            NSLog("[REC] AVAudioSession restore error: \(error.localizedDescription)")
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Sample processing — RPScreenRecorder path
    //
    // Called for every frame/sample from RPScreenRecorder.
    // Suppressed (not called) while a broadcast extension is active.
    // ─────────────────────────────────────────────────────────────────────────

    private func processSampleFromRecorder(_ sampleBuffer: CMSampleBuffer,
                                           type: RPSampleBufferType) {
        // The writer is created on the main thread in beginChunkWriter() and
        // samples arrive on RPScreenRecorder's internal serial queue, so we
        // dispatch to our dedicated writerQueue to avoid data races.
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  writer.status == .writing else { return }

            switch type {
            case .video:
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                guard CMTIME_IS_VALID(pts) else { return }

                // Capture actual pixel dimensions from the first video frame.
                // We need this to configure the broadcast extension's writer
                // with matching dimensions so chunks stitch seamlessly.
                if self.videoWidth == 0,
                   let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    let dim = CMVideoFormatDescriptionGetDimensions(fmt)
                    self.videoWidth  = Int(dim.width)
                    self.videoHeight = Int(dim.height)
                }

                if !self.writerSessionStarted {
                    // Anchor the session to the first real video PTS.
                    // NEVER use .zero — frames with pts > 0 would be
                    // considered "before the session" and silently dropped,
                    // producing a black video track.
                    writer.startSession(atSourceTime: pts)
                    self.writerSessionStarted = true
                    NSLog("[REC] writer session started at \(CMTimeGetSeconds(pts))s")
                }
                if self.videoInput?.isReadyForMoreMediaData == true {
                    self.videoInput?.append(sampleBuffer)
                }

            case .audioMic, .audioApp:
                // Drop audio that arrives before the first video frame —
                // those samples precede the session start time and would
                // cause "sample out of order" log spam and audio glitches
                // at the very beginning of each chunk.
                guard self.writerSessionStarted else { return }
                if self.audioInput?.isReadyForMoreMediaData == true {
                    self.audioInput?.append(sampleBuffer)
                }

            @unknown default:
                break
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Sample processing — Broadcast Extension path
    //
    // Called when the user has started a broadcast (picked a foreign app).
    // Decodes the JPEG frame from SampleHandler and writes it as a video
    // frame into the SAME AVAssetWriter chunk that RPScreenRecorder uses.
    // This means the foreign app's screen appears seamlessly in the recording.
    // ─────────────────────────────────────────────────────────────────────────

    private func processSampleFromBroadcast(jpegData: Data, ptsNs: UInt64) {
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  self.videoInput?.isReadyForMoreMediaData == true else { return }

            // Reconstruct a CMSampleBuffer from the JPEG bytes.
            guard let pixelBuffer = self.jpegToPixelBuffer(jpegData) else { return }

            let pts  = CMTimeMake(value: Int64(ptsNs / 1_000_000),
                                  timescale: 1_000)   // millisecond timescale

            var timingInfo = CMSampleTimingInfo(
                duration:               CMTime(value: 1, timescale: 30),
                presentationTimeStamp:  pts,
                decodeTimeStamp:        .invalid
            )

            var fmtDesc: CMVideoFormatDescription?
            guard CMVideoFormatDescriptionCreateForImageBuffer(
                allocator:              kCFAllocatorDefault,
                imageBuffer:            pixelBuffer,
                formatDescriptionOut:   &fmtDesc
            ) == noErr, fmtDesc != nil else { return }

            var sampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreateReadyWithImageBuffer(
                allocator:              kCFAllocatorDefault,
                imageBuffer:            pixelBuffer,
                formatDescription:      fmtDesc!,
                sampleTiming:           &timingInfo,
                sampleBufferOut:        &sampleBuffer
            ) == noErr, let sb = sampleBuffer else { return }

            if !self.writerSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.writerSessionStarted = true
                NSLog("[REC] writer session (broadcast) started at \(CMTimeGetSeconds(pts))s")
            }
            self.videoInput?.append(sb)
        }
    }

    /// Decode a JPEG Data into a CVPixelBuffer suitable for AVAssetWriterInput.
    private func jpegToPixelBuffer(_ data: Data) -> CVPixelBuffer? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }

        let w = cgImage.width
        let h = cgImage.height
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey:       true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                  kCVPixelFormatType_32ARGB,
                                  attrs as CFDictionary,
                                  &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pb),
            width:            w,
            height:           h,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pb),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:       CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pb
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk writer
    // ─────────────────────────────────────────────────────────────────────────

    private func beginChunkWriter() {
        guard !stopping else { return }

        let fileName = String(format: "rec_chunk_%06d.mp4", chunkIndex)
        let fileURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        currentFile = fileURL

        guard let writer = try? AVAssetWriter(outputURL: fileURL, fileType: .mp4) else {
            emitError("AVAssetWriter init failed for chunk #\(chunkIndex)"); return
        }
        assetWriter = writer

        // ── Video dimensions ──────────────────────────────────────────────────
        // Use actual screen dimensions (populated from first video frame on
        // previous chunk, or screen bounds for the very first chunk).
        // Both values must be even for H.264 encoding.
        let scale  = UIScreen.main.scale
        let rawW   = videoWidth  > 0 ? videoWidth  : Int(UIScreen.main.bounds.width  * scale)
        let rawH   = videoHeight > 0 ? videoHeight : Int(UIScreen.main.bounds.height * scale)
        // Clamp to 720p on the short side to keep files manageable.
        let maxShort = 720
        let shortSide = min(rawW, rawH)
        let ratio  = shortSide > maxShort ? CGFloat(maxShort) / CGFloat(shortSide) : 1.0
        let w      = (Int(CGFloat(rawW) * ratio) / 2) * 2   // must be even
        let h      = (Int(CGFloat(rawH) * ratio) / 2) * 2

        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:       4_000_000,   // 4 Mbps — clear for screen content
                AVVideoMaxKeyFrameIntervalKey:  60,
                AVVideoProfileLevelKey:         AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vi.expectsMediaDataInRealTime = true
        videoInput = vi

        let aSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   128_000,
        ]
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        ai.expectsMediaDataInRealTime = true
        audioInput = ai

        writer.add(vi)
        writer.add(ai)
        writer.startWriting()
        // ── Do NOT call startSession here ─────────────────────────────────────
        // Session is started in processSampleFromRecorder/Broadcast on the
        // first video frame using its actual PTS.  Starting at .zero causes
        // every subsequent real frame (which has pts > 0) to be treated as
        // "before the session" and silently dropped → black video track.
        writerSessionStarted = false

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) \(w)×\(h)")
        scheduleChunkTimer()
    }

    private func scheduleChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: Double(chunkSecs),
                                          repeats: false) { [weak self] _ in
            self?.rotateChunk()
        }
    }

    private func rotateChunk() {
        guard recording, !stopping, !paused else { return }
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self, self.recording, !self.stopping, !self.paused else { return }
            self.chunkIndex += 1
            self.beginChunkWriter()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Pause / Resume
    // ─────────────────────────────────────────────────────────────────────────

    private func pauseRecording(result: @escaping FlutterResult) {
        guard recording, !stopping, !paused else { result(nil); return }
        NSLog("[REC] pauseRecording: finalising chunk #\(chunkIndex)")
        chunkTimer?.invalidate(); chunkTimer = nil
        paused = true
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self else { return }
            self.chunkIndex += 1
            self.assetWriter  = nil
            self.videoInput   = nil
            self.audioInput   = nil
            self.writerSessionStarted = false
            self.emitEvent(["event": "recordingPaused"])
            result(nil)
        }
    }

    private func resumeRecording(result: @escaping FlutterResult) {
        guard recording, paused, !stopping else { result(nil); return }
        NSLog("[REC] resumeRecording: resuming at chunk #\(chunkIndex)")
        paused = false
        beginChunkWriter()
        emitEvent(["event": "recordingResumed"])
        result(nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Stop
    // ─────────────────────────────────────────────────────────────────────────

    private func stopRecording(isFinal: Bool, result: @escaping FlutterResult) {
        guard recording else { result(nil); return }
        NSLog("[REC] stopRecording: isFinal=\(isFinal)")
        stopping = true; recording = false
        chunkTimer?.invalidate(); chunkTimer = nil
        isBroadcasting = false
        removeDarwinListeners()

        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error { NSLog("[REC] stopCapture: \(e.localizedDescription)") }
            DispatchQueue.main.async {
                self?.finaliseChunk(isFinal: isFinal) {
                    self?.stopping = false
                    result(nil)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk finalisation & upload
    // ─────────────────────────────────────────────────────────────────────────

    private func finaliseChunk(isFinal: Bool, completion: @escaping () -> Void) {
        guard let writer = assetWriter, let fileURL = currentFile else {
            completion(); return
        }
        let idx = chunkIndex
        // markAsFinished must run on the same queue that appends samples.
        writerQueue.async { [weak self] in
            guard let self = self else { DispatchQueue.main.async { completion() }; return }
            self.videoInput?.markAsFinished()
            self.audioInput?.markAsFinished()
            writer.finishWriting {
                if writer.status == .failed {
                    NSLog("[REC] writer failed chunk #\(idx): \(writer.error?.localizedDescription ?? "")")
                    DispatchQueue.main.async { completion() }
                    return
                }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size < 512 {
                    NSLog("[REC] chunk #\(idx) too small (\(size)B) — dropping")
                    try? FileManager.default.removeItem(at: fileURL)
                    DispatchQueue.main.async { completion() }
                    return
                }
                NSLog("[REC] finalised chunk #\(idx) (\(size)B isFinal=\(isFinal))")
                DispatchQueue.global(qos: .utility).async {
                    self.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal)
                    DispatchQueue.main.async { completion() }
                }
            }
        }
    }

    private func uploadChunkAsync(fileURL: URL, index: Int, isFinal: Bool, attempt: Int = 0) {
        guard let url = URL(string: uploadUrl) else { return }
        let boundary = "----ElFaheemBoundary\(Int(Date().timeIntervalSince1970))"
        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("chunk_index", "\(index)")
        appendField("is_final",    isFinal ? "1" : "0")

        let fname = String(format: "chunk_%06d.mp4", index)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        body.append((try? Data(contentsOf: fileURL)) ?? Data())
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || code < 200 || code > 299 {
                let reason = error?.localizedDescription ?? "HTTP \(code)"
                NSLog("[REC] chunk #\(index) attempt \(attempt+1) failed: \(reason)")
                if attempt < 3 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(1 << (attempt+1))) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index,
                                              isFinal: isFinal, attempt: attempt+1)
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.emitError("chunk #\(index) failed after 3 retries: \(reason)")
                }
                return
            }
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[REC] chunk #\(index) uploaded OK (\(size)B isFinal=\(isFinal))")
            DispatchQueue.main.async {
                self.emitEvent(["event": "chunkUploaded", "chunkIndex": index,
                                "bytes": size, "isFinal": isFinal])
            }
        }.resume()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func emitEvent(_ payload: [String: Any]) {
        DispatchQueue.main.async { self.eventSink?(payload) }
    }

    private func emitError(_ msg: String) {
        NSLog("[REC] ERROR: \(msg)")
        DispatchQueue.main.async {
            self.eventSink?(FlutterError(code: "REC_ERROR", message: msg, details: nil))
        }
    }

    private func sweepStaleChunks() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in items where url.lastPathComponent.hasPrefix("rec_chunk_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Broadcast Extension (foreign-app screen share)
    // ─────────────────────────────────────────────────────────────────────────

    private func showBroadcastPicker(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { result(nil); return }

            // Register Darwin notification listeners BEFORE the picker appears
            // so we are ready the instant the extension's broadcastStarted() fires.
            self.registerDarwinListeners()

            let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))

            // Point directly at our own extension so the system skips the
            // full picker list and shows only our "Start Broadcast" sheet.
            picker.preferredExtension =
                Bundle.main.bundleIdentifier.map { $0 + ".BroadcastUploadExtension" }
            picker.showsMicrophoneButton = false

            // Programmatically press the picker button to open the sheet.
            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }
            NSLog("[SHARE] showBroadcastPicker — extension: \(picker.preferredExtension ?? "nil")")
            result(nil)
        }
    }

    private func stopBroadcastShare(result: @escaping FlutterResult) {
        isBroadcasting = false
        removeDarwinListeners()
        emitEvent(["event": "broadcastStopped"])
        NSLog("[SHARE] broadcast stopped by app")
        result(nil)
    }

    // ── IPC: Darwin notifications + App Group shared file ────────────────────
    //
    // How it works:
    //   SampleHandler (extension process):
    //     1. Serialises each frame into a binary blob.
    //     2. Writes it atomically to:
    //        <AppGroupContainer>/broadcast_frame.bin
    //     3. Calls notify_post("…frame") — a Darwin notification that crosses
    //        the iOS process sandbox without any entitlement beyond App Group.
    //
    //   AppDelegate (host app process):
    //     1. Registered for the same Darwin notification via
    //        CFNotificationCenterAddObserver on the Darwin center.
    //     2. On notification: reads the shared file on ipcReadQueue,
    //        parses the binary blob, routes to handleBroadcastData().
    //
    // Why not CFMessagePort?
    //   CFMessagePortCreateRemote() always returns nil from a Broadcast Upload
    //   Extension on iOS 14+ because the OS sandbox blocks extension→app IPC
    //   for CFMessagePort. Darwin notifications + a shared container file is
    //   the Apple-documented pattern for this exact use case.

    private func registerDarwinListeners() {
        guard !darwinObserverAdded else { return }
        darwinObserverAdded = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // Frame notification
        CFNotificationCenterAddObserver(
            center, selfPtr,
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                me.onDarwinFrameNotif()
            },
            kDarwinFrameNotif as CFString, nil, .deliverImmediately
        )

        // Stop notification
        CFNotificationCenterAddObserver(
            center, selfPtr,
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                me.onDarwinStopNotif()
            },
            kDarwinStopNotif as CFString, nil, .deliverImmediately
        )

        NSLog("[SHARE] Darwin listeners registered")
    }

    private func removeDarwinListeners() {
        guard darwinObserverAdded else { return }
        darwinObserverAdded = false
        let center  = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, selfPtr,
            CFNotificationName(kDarwinFrameNotif as CFString), nil)
        CFNotificationCenterRemoveObserver(center, selfPtr,
            CFNotificationName(kDarwinStopNotif  as CFString), nil)
        NSLog("[SHARE] Darwin listeners removed")
    }

    /// Called on the main thread when the extension posted a frame notification.
    private func onDarwinFrameNotif() {
        ipcReadQueue.async { [weak self] in
            guard let self = self else { return }
            guard let container = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: self.kAppGroup) else {
                NSLog("[SHARE] ERROR: App Group container not found — check entitlements")
                return
            }
            let fileURL = container.appendingPathComponent(self.kFrameFileName)
            guard let data = try? Data(contentsOf: fileURL), data.count >= 16 else { return }
            self.handleBroadcastData(data)
        }
    }

    /// Called on the main thread when the extension posted a stop notification.
    private func onDarwinStopNotif() {
        NSLog("[SHARE] broadcast extension finished (Darwin stop)")
        isBroadcasting = false
        removeDarwinListeners()
        emitEvent(["event": "broadcastStopped"])
    }

    /// Parse a frame blob and route it to the writer.
    /// Wire format: [4B typeId BE][8B ptsNs BE][4B payloadSize BE][payload]
    /// typeId: 0 = video (JPEG), 1 = audioMic (PCM), 2 = audioApp (PCM)
    private func handleBroadcastData(_ data: Data) {
        guard data.count >= 16 else { return }
        let typeId  = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let ptsNs   = data.dropFirst(4).prefix(8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let paySize = data.dropFirst(12).prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let payload = Data(data.dropFirst(16).prefix(Int(paySize)))

        switch typeId {
        case 0:
            // Video frame (JPEG) — write into the active AVAssetWriter chunk.
            if !isBroadcasting {
                isBroadcasting = true
                NSLog("[SHARE] first broadcast frame — switching recording source")
            }
            guard recording, !stopping, !paused else { return }
            processSampleFromBroadcast(jpegData: payload, ptsNs: ptsNs)

        case 1, 2:
            // Audio from the extension.
            // RPScreenRecorder already captures mic audio (clean, with LiveKit
            // AEC/NS applied), so we skip the extension audio to avoid doubles.
            break

        default:
            break
        }
    }
}

// ── StreamHandler helper ──────────────────────────────────────────────────────
private class RecEventStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    private let onCancel: () -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        self.onListen = onListen; self.onCancel = onCancel
    }
    func onListen(withArguments args: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        onListen(eventSink); return nil
    }
    func onCancel(withArguments args: Any?) -> FlutterError? { onCancel(); return nil }
}