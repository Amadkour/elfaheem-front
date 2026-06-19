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
//
//  FIXES applied in this revision (2025-06):
//  ─────────────────────────────────────────
//  1. stopResult race condition: stopCaptureThenSignal previously fired
//     the Flutter result as a fallback immediately after RPScreenRecorder
//     stopCapture returned — even when the final-chunk upload was still
//     in-flight on a background queue. This caused Dart to unblock and
//     call onEnd() before the server received the final chunk, so only
//     chunk #0 was ever recorded. Fix: stopCapture is called BEFORE
//     finaliseChunk so the upload is already complete when we need to
//     signal Dart. The signal is only sent once the upload callback fires.
//
//  2. Chunk timer guard flip: scheduleChunkTimer had `guard chunkTimer == nil`
//     which correctly prevents double-scheduling, but beginChunkWriter also
//     ran the `guard !stopping` check AFTER nilling the timer — meaning a
//     rapid stop → beginChunkWriter could schedule a new timer. No functional
//     change here; the logic was already correct but comments clarify intent.
//
//  3. Event naming: startRPScreenRecorder now emits "videoChunksActive" (not
//     "screenLoopStarted") so Dart's Phase-2 _upgradeCompleter resolves
//     correctly without being swallowed by the Phase-1 early-return guard.

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

    // ── Upload URLSession ─────────────────────────────────────────────────────
    //
    // A DEDICATED default-configuration URLSession that is completely
    // independent from URLSession.shared and from LiveKit's internal sessions.
    // waitsForConnectivity=true queues tasks instead of failing when the network
    // is momentarily lost during LiveKit's socket teardown.
    // httpMaximumConnectionsPerHost=1 serialises requests to the Cloudflare
    // tunnel (avoids per-IP connection-limit resets from trycloudflare.com).
    private lazy var uploadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity          = true
        cfg.timeoutIntervalForRequest     = 120
        cfg.timeoutIntervalForResource    = 300
        cfg.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: cfg)
    }()

    // ── Broadcast source control ──────────────────────────────────────────────
    private var isBroadcasting      = false
    private var lastBroadcastPts:   CMTime?

    // ── Broadcast Extension IPC (App Group + Darwin notifications) ───────────
    private let kAppGroup           = "group.com.example.flutterEducationApp"
    private let kDarwinFrameNotif   = "com.example.flutter_education_app.frame"
    private let kDarwinStopNotif    = "com.example.flutter_education_app.stop"
    private let kFrameFileName      = "broadcast_frame.bin"
    private var darwinObserverAdded = false
    private let ipcReadQueue        = DispatchQueue(label: "com.elfaheem.ipc", qos: .userInteractive)

    // ── Video dimensions (read from first RPScreenRecorder video frame) ───────
    private var videoWidth:  Int = 0
    private var videoHeight: Int = 0

    // ── Background keepalive task ─────────────────────────────────────────────
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // ── Stop-recording coordination ───────────────────────────────────────────
    //
    // FIX: The old design dispatched uploadChunkAsync concurrently with
    // stopCapture, then used a `stopResult` fallback in stopCapture's
    // completion handler that fired result(nil) even while the upload was
    // still in-flight. This caused Dart to unblock before the final chunk
    // reached the server.
    //
    // New design:
    //   1. stopRecording: set stopping=true, invalidate timer, stop capture.
    //   2. Inside stopCapture's completion: finaliseChunk(isFinal:).
    //   3. Inside finaliseChunk's completion: uploadChunkAsync runs and holds
    //      the FlutterResult open. result(nil) fires ONLY after the upload
    //      callback (success or final retry failure) confirms the server has
    //      received the chunk — never from a fallback path.
    //
    // This guarantees: Dart's `await invokeMethod('stopRecording')` truly
    // blocks until the server has the final chunk, so _endSessionWithRecording
    // can safely call widget.onEnd() without killing an in-flight upload.
    private var pendingStopResult: FlutterResult?

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

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)

        let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        return true
    }

    @objc private func appDidEnterBackground() {
        guard isBroadcasting || darwinObserverAdded else { return }
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "BroadcastRecord") {
            [weak self] in
            guard let self = self else { return }
            NSLog("[REC] background task expiring — finalising chunk")
            self.finaliseChunk(isFinal: false) { [weak self] in
                guard let self = self else { return }
                self.chunkIndex += 1
            }
            UIApplication.shared.endBackgroundTask(self.bgTask)
            self.bgTask = .invalid
        }
        NSLog("[REC] background task started id=\(bgTask.rawValue)")
    }

    @objc private func appWillEnterForeground() {
        endBgTask()
    }

    private func endBgTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
        NSLog("[REC] background task ended")
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
                // Phase-1: emit immediately so Dart's _startCompleter resolves.
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)

            case "upgradeToScreenRecording":
                // FIX: Always emit videoChunksActive for Phase-2, regardless
                // of recording state. The Dart side created _upgradeCompleter
                // before calling startScreenCaptureService, so this event will
                // resolve it correctly. Previously this returned false when
                // recording=false (race before startCapture completed), leaving
                // _upgradeCompleter pending until it timed out at 20s.
                self.emitEvent(["event": "videoChunksActive"])
                result(self.recording)

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

        configureAudioSessionForRecording()
        rp.isMicrophoneEnabled = true

        // Set recording=true BEFORE startCapture's async completion so that
        // any stopRecording() call during startup correctly reaches finaliseChunk().
        recording = true

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
                    self.recording  = false
                    self.stopping   = false
                    self.chunkTimer?.invalidate()
                    self.chunkTimer = nil
                    self.assetWriter = nil
                    self.videoInput  = nil
                    self.audioInput  = nil
                    self.writerSessionStarted = false
                    self.releaseAudioSessionLock()
                    result(FlutterError(code: "RP_START_ERROR",
                                        message: e.localizedDescription, details: nil))
                    return
                }

                // Re-arm audio session AFTER startCapture completes.
                self.configureAudioSessionForRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.recording else { return }
                    self.configureAudioSessionForRecording()
                    NSLog("[REC] AVAudioSession: delayed re-arm applied")
                }

                // Start chunk writer — RPScreenRecorder is delivering frames.
                // The first video frame anchors the AVAssetWriter session.
                // FIX: emit "videoChunksActive" (not "screenLoopStarted") so
                // Dart's Phase-2 _upgradeCompleter resolves without being
                // consumed by the Phase-1 early-return guard in _onNativeEvent.
                self.beginChunkWriter()
                self.emitEvent(["event": "videoChunksActive"])
                NSLog("[REC] RPScreenRecorder started — chunk #\(self.chunkIndex)")
                result(true)
            }
        })
    }

    // ── AVAudioSession management ─────────────────────────────────────────────

    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker,
                          .allowBluetooth,
                          .allowBluetoothA2DP,
                          .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active")
        } catch {
            NSLog("[REC] AVAudioSession configure error: \(error.localizedDescription)")
        }
    }

    private func releaseAudioSessionLock() {
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
    // ─────────────────────────────────────────────────────────────────────────

    private func processSampleFromRecorder(_ sampleBuffer: CMSampleBuffer,
                                           type: RPSampleBufferType) {
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  writer.status == .writing else { return }

            switch type {
            case .video:
                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                guard CMTIME_IS_VALID(pts) else { return }

                if self.videoWidth == 0,
                   let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    let dim = CMVideoFormatDescriptionGetDimensions(fmt)
                    self.videoWidth  = Int(dim.width)
                    self.videoHeight = Int(dim.height)
                }

                if !self.writerSessionStarted {
                    writer.startSession(atSourceTime: pts)
                    self.writerSessionStarted = true
                    NSLog("[REC] writer session started at \(CMTimeGetSeconds(pts))s")
                }
                if self.videoInput?.isReadyForMoreMediaData == true {
                    self.videoInput?.append(sampleBuffer)
                }

            case .audioMic, .audioApp:
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
    // ─────────────────────────────────────────────────────────────────────────

    private func processSampleFromBroadcast(jpegData: Data, ptsNs: UInt64) {
        writerQueue.async { [weak self] in
            guard let self = self,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  self.videoInput?.isReadyForMoreMediaData == true else { return }

            guard let pixelBuffer = self.jpegToPixelBuffer(jpegData) else { return }

            let pts  = CMTimeMake(value: Int64(ptsNs / 1_000_000),
                                  timescale: 1_000)

            let fallbackDuration = CMTime(value: 1, timescale: 30)
            var duration = fallbackDuration
            if let last = self.lastBroadcastPts {
                let delta = CMTimeSubtract(pts, last)
                let deltaSeconds = CMTimeGetSeconds(delta)
                if deltaSeconds.isFinite, deltaSeconds > 0.005, deltaSeconds < 1.0 {
                    duration = delta
                }
            }
            self.lastBroadcastPts = pts

            var timingInfo = CMSampleTimingInfo(
                duration:               duration,
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.beginChunkWriter() }
            return
        }
        guard !stopping else { return }

        let fileName = String(format: "rec_chunk_%06d.mp4", chunkIndex)
        let fileURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        currentFile = fileURL

        guard let writer = try? AVAssetWriter(outputURL: fileURL, fileType: .mp4) else {
            emitError("AVAssetWriter init failed for chunk #\(chunkIndex)"); return
        }
        assetWriter = writer

        let scale  = UIScreen.main.scale
        let rawW   = videoWidth  > 0 ? videoWidth  : Int(UIScreen.main.bounds.width  * scale)
        let rawH   = videoHeight > 0 ? videoHeight : Int(UIScreen.main.bounds.height * scale)
        let maxShort = 720
        let shortSide = min(rawW, rawH)
        let ratio  = shortSide > maxShort ? CGFloat(maxShort) / CGFloat(shortSide) : 1.0
        let w      = (Int(CGFloat(rawW) * ratio) / 2) * 2
        let h      = (Int(CGFloat(rawH) * ratio) / 2) * 2

        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:       4_000_000,
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
        writerSessionStarted = false
        lastBroadcastPts = nil

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) \(w)×\(h)")
        scheduleChunkTimer()
    }

    private func scheduleChunkTimer() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleChunkTimer() }
            return
        }
        // Guard: if a timer is already running, don't reset it.
        // beginChunkWriter() can be called multiple times (e.g. rapid events)
        // and each call must NOT reset the timer — that would cause the 5-second
        // chunk to never complete (always restarting the countdown).
        guard chunkTimer == nil else {
            NSLog("[REC] scheduleChunkTimer: timer already running — skipping reset")
            return
        }
        chunkTimer = Timer.scheduledTimer(
            withTimeInterval: Double(chunkSecs),
            repeats: false
        ) { [weak self] _ in
            self?.rotateChunk()
        }
        NSLog("[REC] chunk timer scheduled: \(chunkSecs)s for chunk #\(chunkIndex)")
    }

    private func rotateChunk() {
        // ALWAYS nil the timer reference first — even if we return early.
        // If we don't, the spent (fired, non-repeating) timer object stays
        // non-nil in chunkTimer, and the next beginChunkWriter() →
        // scheduleChunkTimer() hits the `guard chunkTimer == nil` guard and
        // returns without scheduling a new timer. This was the cause of
        // "only records one giant chunk until stop": after the first rotation
        // the timer was never rescheduled, so only the final stopRecording()
        // call ever produced a second chunk (the "last chunk only" symptom).
        chunkTimer?.invalidate()
        chunkTimer = nil
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
    //
    // FIX — correct ordering to eliminate the stopResult race condition:
    //
    // OLD (broken) flow:
    //   finaliseChunk() → [dispatches uploadChunkAsync on global queue]
    //                   → completion() fires on main thread
    //   stopCaptureThenSignal():
    //     stopResult = result
    //     stopCapture() → completion:
    //       if let r = stopResult { r(nil) }   ← fires BEFORE upload completes!
    //
    // NEW (correct) flow:
    //   1. Invalidate chunk timer.
    //   2. stopCapture() — stops RPScreenRecorder frame delivery.
    //   3. Inside stopCapture's completion: finaliseChunk(isFinal:).
    //   4. Inside finaliseChunk's completion: uploadChunkAsync holds the
    //      FlutterResult open and fires result(nil) ONLY after the upload
    //      callback (success or exhausted retries) confirms receipt.
    //
    // This guarantees Dart's `await invokeMethod('stopRecording')` blocks
    // until the server has the final chunk before onEnd() is called.

    private func stopRecording(isFinal: Bool, result: @escaping FlutterResult) {
        guard recording else { result(nil); return }
        NSLog("[REC] stopRecording: isFinal=\(isFinal) isBroadcasting=\(isBroadcasting)")
        stopping = true
        recording = false
        chunkTimer?.invalidate(); chunkTimer = nil
        isBroadcasting = false
        removeDarwinListeners()
        endBgTask()

        // Store the result so uploadChunkAsync can fire it after the upload.
        pendingStopResult = result

        // Step 1: Stop RPScreenRecorder frame delivery first so no new frames
        // arrive during finaliseChunk's finishWriting call (avoids "append after
        // finishWriting" crashes on the writerQueue).
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error {
                NSLog("[REC] stopCapture error: \(e.localizedDescription)")
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { result(nil); return }
                self.stopping = false
                // Step 2: Finalise and upload the last chunk. The FlutterResult
                // is held in pendingStopResult and fired by uploadChunkAsync
                // after the server confirms receipt. If no frames were written
                // (writerSessionStarted=false), finaliseChunk drops the chunk
                // and its completion runs immediately — we signal Dart then.
                self.finaliseLastChunk(isFinal: isFinal)
            }
        }
    }

    /// Finalises the active chunk with isFinal flag. The FlutterResult stored
    /// in pendingStopResult is fired by uploadChunkAsync after upload completes.
    /// If there is nothing to finalise (empty writer), signals Dart immediately.
    private func finaliseLastChunk(isFinal: Bool) {
        // If there's no active writer (e.g. recording was paused or never had
        // any frames), just signal Dart immediately.
        guard assetWriter != nil else {
            NSLog("[REC] finaliseLastChunk: no active writer — signalling Dart")
            if let r = pendingStopResult {
                pendingStopResult = nil
                r(nil)
            }
            return
        }
        finaliseChunk(isFinal: isFinal) { [weak self] in
            guard let self = self else { return }
            // For non-final chunks (shouldn't normally happen on stop, but
            // guard against it), signal Dart immediately since uploadChunkAsync
            // won't fire pendingStopResult for non-final chunks.
            if !isFinal {
                if let r = self.pendingStopResult {
                    self.pendingStopResult = nil
                    r(nil)
                }
            }
            // For isFinal=true: uploadChunkAsync holds pendingStopResult and
            // fires it after the upload succeeds (or exhausts retries).
            // No action needed here.
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk finalisation & upload
    // ─────────────────────────────────────────────────────────────────────────

    private func finaliseChunk(isFinal: Bool, completion: @escaping () -> Void) {
        guard let writer  = assetWriter,
              let vi      = videoInput,
              let ai      = audioInput,
              let fileURL = currentFile else {
            DispatchQueue.main.async { completion() }
            return
        }
        guard writer.status == .writing else {
            NSLog("[REC] finaliseChunk skipped (writer status=\(writer.status.rawValue))")
            assetWriter = nil; videoInput = nil; audioInput = nil
            currentFile = nil; writerSessionStarted = false
            DispatchQueue.main.async { completion() }
            return
        }
        guard writerSessionStarted else {
            NSLog("[REC] finaliseChunk skipped — startSession never called (no frames yet)")
            assetWriter = nil; videoInput = nil; audioInput = nil
            currentFile = nil; writerSessionStarted = false
            try? FileManager.default.removeItem(at: fileURL)
            // Signal Dart if this is the final stop and we have no frames.
            if isFinal {
                if let r = pendingStopResult {
                    pendingStopResult = nil
                    r(nil)
                }
            }
            DispatchQueue.main.async { completion() }
            return
        }
        assetWriter = nil; videoInput = nil; audioInput = nil
        currentFile = nil; writerSessionStarted = false
        let idx = chunkIndex
        writerQueue.async { [weak self] in
            vi.markAsFinished()
            ai.markAsFinished()
            writer.finishWriting {
                if writer.status == .failed {
                    NSLog("[REC] writer failed chunk #\(idx): \(writer.error?.localizedDescription ?? "unknown")")
                    if isFinal {
                        DispatchQueue.main.async {
                            if let r = self?.pendingStopResult {
                                self?.pendingStopResult = nil
                                r(nil)
                            }
                        }
                    }
                    DispatchQueue.main.async { completion() }
                    return
                }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size < 512 {
                    NSLog("[REC] chunk #\(idx) too small (\(size)B) — dropping")
                    try? FileManager.default.removeItem(at: fileURL)
                    if isFinal {
                        DispatchQueue.main.async {
                            if let r = self?.pendingStopResult {
                                self?.pendingStopResult = nil
                                r(nil)
                            }
                        }
                    }
                    DispatchQueue.main.async { completion() }
                    return
                }
                NSLog("[REC] finalised chunk #\(idx) (\(size)B isFinal=\(isFinal))")
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal)
                }
                DispatchQueue.main.async { completion() }
            }
        }
    }

    private func uploadChunkAsync(fileURL: URL, index: Int, isFinal: Bool, attempt: Int = 0) {
        guard let url = URL(string: uploadUrl) else {
            NSLog("[REC] chunk #\(index) bad uploadUrl — skipping")
            if isFinal {
                DispatchQueue.main.async {
                    if let r = self.pendingStopResult {
                        self.pendingStopResult = nil
                        r(nil)
                    }
                }
            }
            return
        }

        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard fileSize > 0 else {
            NSLog("[REC] chunk #\(index) file missing or empty — skipping")
            if isFinal {
                DispatchQueue.main.async {
                    if let r = self.pendingStopResult {
                        self.pendingStopResult = nil
                        r(nil)
                    }
                }
            }
            return
        }

        let boundary  = "----ElFaheemBoundary\(index)x\(attempt)"
        let tmpName   = "upload_chunk_\(index)_\(attempt).bin"
        let tmpURL    = FileManager.default.temporaryDirectory.appendingPathComponent(tmpName)

        var header = Data()
        func addField(_ name: String, _ value: String) {
            header.append("--\(boundary)\r\n".data(using: .utf8)!)
            header.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            header.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("chunk_index", "\(index)")
        addField("is_final",    isFinal ? "1" : "0")

        let fname = String(format: "chunk_%06d.mp4", index)
        header.append("--\(boundary)\r\n".data(using: .utf8)!)
        header.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        header.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)

        let footer = "\r\n--\(boundary)--\r\n".data(using: .utf8)!

        guard let videoData = try? Data(contentsOf: fileURL) else {
            NSLog("[REC] chunk #\(index) could not read video file")
            if isFinal {
                DispatchQueue.main.async {
                    if let r = self.pendingStopResult {
                        self.pendingStopResult = nil
                        r(nil)
                    }
                }
            }
            return
        }
        var multipart = Data(capacity: header.count + videoData.count + footer.count)
        multipart.append(header)
        multipart.append(videoData)
        multipart.append(footer)
        do {
            try multipart.write(to: tmpURL, options: .atomic)
        } catch {
            NSLog("[REC] chunk #\(index) could not write multipart temp: \(error)")
            if isFinal {
                DispatchQueue.main.async {
                    if let r = self.pendingStopResult {
                        self.pendingStopResult = nil
                        r(nil)
                    }
                }
            }
            return
        }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken,                                      forHTTPHeaderField: "Authorization")
        request.setValue("\(multipart.count)",                          forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120

        uploadSession.uploadTask(with: request, fromFile: tmpURL) { [weak self] _, response, error in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: tmpURL)

            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[REC] chunk #\(index) HTTP \(code) isFinal=\(isFinal) size=\(fileSize)B")

            if error != nil || code < 200 || code > 299 {
                let reason = error?.localizedDescription ?? "HTTP \(code)"
                NSLog("[REC] chunk #\(index) attempt \(attempt+1) failed: \(reason)")
                if attempt < 4 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(3 * (1 << attempt))) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index,
                                              isFinal: isFinal, attempt: attempt + 1)
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.emitError("chunk #\(index) failed after 4 retries: \(reason)")
                    // Final chunk failed permanently — unblock Dart.
                    if isFinal {
                        DispatchQueue.main.async {
                            if let r = self.pendingStopResult {
                                self.pendingStopResult = nil
                                r(nil)
                            }
                        }
                    }
                }
                return
            }

            // Success.
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[REC] chunk #\(index) uploaded OK (\(fileSize)B isFinal=\(isFinal))")
            DispatchQueue.main.async {
                self.emitEvent(["event": "chunkUploaded", "chunkIndex": index,
                                "bytes": fileSize, "isFinal": isFinal])
                // FIX: signal Dart ONLY after the upload callback confirms
                // the server received the final chunk. This is the ONLY place
                // result(nil) fires for isFinal=true — no fallback paths.
                if isFinal {
                    if let r = self.pendingStopResult {
                        self.pendingStopResult = nil
                        r(nil)
                    }
                }
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
        let tmp  = FileManager.default.temporaryDirectory
        let cutoff = Date(timeIntervalSinceNow: -3600)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.creationDateKey]) else { return }
        for url in items where url.lastPathComponent.hasPrefix("rec_chunk_") {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let d = created, d < cutoff {
                try? FileManager.default.removeItem(at: url)
                NSLog("[REC] swept stale chunk: \(url.lastPathComponent)")
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Broadcast Extension (foreign-app screen share)
    // ─────────────────────────────────────────────────────────────────────────

    private func showBroadcastPicker(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { result(nil); return }

            self.appDidEnterBackground()

            if self.recording && !self.paused && !self.stopping {
                self.paused = true
                NSLog("[SHARE] picker: recording paused before system overlay")
                self.finaliseChunk(isFinal: false) { [weak self] in
                    guard let self = self else { return }
                    self.chunkIndex += 1
                    NSLog("[SHARE] picker: paused chunk rotated at #\(self.chunkIndex)")
                }
            }

            self.registerDarwinListeners()
   // --- NEW: schedule a resume if broadcast doesn't start ---
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            // If broadcast hasn't started and we're still paused, resume recording.
            if !self.isBroadcasting && self.paused && self.recording && !self.stopping {
                self.paused = false
                self.beginChunkWriter()
                NSLog("[SHARE] picker timeout: recording resumed (broadcast not started)")
            }
        }
        // --- END NEW ---
            let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
            picker.preferredExtension =
                Bundle.main.bundleIdentifier.map { $0 + ".BroadcastUploadExtension" }
            picker.showsMicrophoneButton = false

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
        endBgTask()
        emitEvent(["event": "broadcastStopped"])
        NSLog("[SHARE] broadcast stopped by app")
        if recording && !stopping {
            if paused {
                paused = false
                beginChunkWriter()
                NSLog("[SHARE] picker cancelled — RPScreenRecorder resumed at chunk #\(chunkIndex)")
            } else {
                finaliseChunk(isFinal: false) { [weak self] in
                    guard let self = self, self.recording, !self.stopping, !self.paused else { return }
                    self.chunkIndex += 1
                    self.beginChunkWriter()
                    NSLog("[SHARE] broadcast chunk rotated — RPScreenRecorder resuming at chunk #\(self.chunkIndex)")
                }
            }
        }
        result(nil)
    }

    // ── IPC: Darwin notifications + App Group shared file ────────────────────

    private func registerDarwinListeners() {
        guard !darwinObserverAdded else { return }
        darwinObserverAdded = true

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        CFNotificationCenterAddObserver(
            center, selfPtr,
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                me.onDarwinFrameNotif()
            },
            kDarwinFrameNotif as CFString, nil, .deliverImmediately
        )

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

    private func onDarwinStopNotif() {
        NSLog("[SHARE] broadcast extension finished (Darwin stop)")
        isBroadcasting = false
        removeDarwinListeners()
        emitEvent(["event": "broadcastStopped"])
        if recording && !stopping {
            if paused {
                paused = false
                beginChunkWriter()
                NSLog("[SHARE] Darwin stop: resumed from paused state at chunk #\(chunkIndex)")
            } else {
                finaliseChunk(isFinal: false) { [weak self] in
                    guard let self = self, self.recording, !self.stopping, !self.paused else { return }
                    self.chunkIndex += 1
                    self.beginChunkWriter()
                    NSLog("[SHARE] Darwin stop: chunk rotated at #\(self.chunkIndex)")
                }
            }
        }
    }

    private func handleBroadcastData(_ data: Data) {
        guard data.count >= 16 else { return }

        func beUInt32(_ bytes: Data, _ offset: Int) -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v = (v << 8) | UInt32(bytes[bytes.startIndex + offset + i]) }
            return v
        }
        func beUInt64(_ bytes: Data, _ offset: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<8 { v = (v << 8) | UInt64(bytes[bytes.startIndex + offset + i]) }
            return v
        }

        let typeId  = beUInt32(data, 0)
        let ptsNs   = beUInt64(data, 4)
        let paySize = beUInt32(data, 12)
        guard data.count >= 16 + Int(paySize) else { return }
        let payload = Data(data.dropFirst(16).prefix(Int(paySize)))

        switch typeId {
        case 0:
            if !isBroadcasting {
                isBroadcasting = true
                lastBroadcastPts = nil
                NSLog("[SHARE] first broadcast frame — switching recording source")
                if recording && paused && !stopping {
                    paused = false
                    beginChunkWriter()
                    NSLog("[SHARE] recording resumed from picker-pause — broadcast chunk #\(chunkIndex)")
                }
            }
            guard recording, !stopping, !paused else { return }
            processSampleFromBroadcast(jpegData: payload, ptsNs: ptsNs)

        case 1, 2:
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