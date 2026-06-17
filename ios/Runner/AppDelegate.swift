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
    private var rpRunning     = false  // true once RPScreenRecorder.startCapture succeeds

    // ── Upload URLSession ─────────────────────────────────────────────────────
    //
    // URLSession.shared is cancelled by LiveKit's WebRTC stack when it tears
    // down its network connections on room disconnect.
    //
    // Fix: a DEDICATED default-configuration URLSession that is completely
    // independent from URLSession.shared and from LiveKit's internal sessions.
    //
    // We do NOT use URLSessionConfiguration.background because:
    //   • background sessions forbid completion-handler–based tasks entirely
    //     (crashes with "Completion handler blocks are not supported in
    //     background sessions. Use a delegate instead.")
    //   • Our retry logic lives in the completion handler.
    //
    // A fresh .default session with waitsForConnectivity=true is sufficient:
    //   • It is not shared with any other consumer, so LiveKit cannot cancel it.
    //   • waitsForConnectivity queues tasks instead of failing when the network
    //     is momentarily lost during LiveKit's socket teardown.
    //   • httpMaximumConnectionsPerHost=1 serialises requests to the Cloudflare
    //     tunnel (avoids per-IP connection-limit resets from trycloudflare.com).
    private lazy var uploadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity          = true
        cfg.timeoutIntervalForRequest     = 120
        cfg.timeoutIntervalForResource    = 300
        cfg.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: cfg)
    }()

    // ── Broadcast source control ──────────────────────────────────────────────
    // When isBroadcasting = true, frames from RPScreenRecorder are suppressed
    // and frames from the broadcast extension are written instead.
    private var isBroadcasting      = false

    // Tracks the previous broadcast frame's presentation timestamp so we can
    // compute each frame's REAL duration (extension frame arrival is not a
    // fixed cadence — JPEG encode + file write + Darwin notify round-trip
    // introduces jitter). nil until the first broadcast frame is written.
    private var lastBroadcastPts:   CMTime?

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
    //      Add group ID:  group.com.example.flutterEducationApp
    //   2. Select the BroadcastUploadExtension target → same steps → same ID
    //   Both targets must share the EXACT same group string.
    //
    //   NOTE: this must match BroadcastUploadExtension.entitlements AND the
    //   kAppGroup constant in SampleHandler.swift EXACTLY (character-for-
    //   character). A previous version of this file used the snake_case
    //   variant "group.com.example.flutter_education_app", which silently
    //   mismatched the entitlements file (camelCase) — that mismatch makes
    //   containerURL(forSecurityApplicationGroupIdentifier:) return nil in
    //   BOTH processes, breaking the IPC with no obvious error at the call
    //   site. If you ever rename the App Group, grep the whole project for
    //   the old string and update every occurrence in the same commit.
    //   If your bundle ID differs, update kAppGroup in BOTH this file and
    //   SampleHandler.swift — they must be identical.
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
        // Re-arm audio session whenever LiveKit resets it to SoloAmbient.
        // LiveKit posts AVAudioSession.routeChangeNotification and
        // AVAudioSession.interruptionNotification after each reconfigure.
        // Observing these and re-applying playAndRecord+videoChat+mixWithOthers
        // keeps the mic active for RPScreenRecorder throughout the session.
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioSessionRouteChanged),
            name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification, object: nil)

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

    /// Re-arm audio session after LiveKit changes the route (e.g. speaker/BT switch).
    /// LiveKit's RTCAudioSession reconfigures to SoloAmbient on certain route changes,
    /// dropping mic input for RPScreenRecorder and producing silent/empty chunks.
    @objc private func audioSessionRouteChanged(_ notification: Notification) {
        guard recording, !stopping else { return }
        let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
            .flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
        NSLog("[REC] AVAudioSession route changed (reason=\(reason?.rawValue ?? 99)) — re-arming")
        // Small delay so LiveKit finishes its own reconfigure before we override.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.recording, !self.stopping else { return }
            self.configureAudioSessionForRecording()
        }
    }

    /// Re-arm audio session after an interruption ends (e.g. phone call, Siri).
    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard recording, !stopping else { return }
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.ended.rawValue else { return }
        NSLog("[REC] AVAudioSession interruption ended — re-arming")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.recording, !self.stopping else { return }
            self.configureAudioSessionForRecording()
        }
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
                // Guard on rpRunning (not recording) — recording=true is set
                // in Phase 1 (startMicRecording) to start the chunk timer early.
                // We still need to call startRPScreenRecorder for the actual
                // RPScreenRecorder.startCapture() that brings video frames.
                guard !self.rpRunning else { result(true); return }
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
                // ── Single-call recording start ───────────────────────────────
                // startMicRecording now starts BOTH the chunk loop AND
                // RPScreenRecorder in one call. The old two-phase design
                // (Phase1=store params, Phase2=startScreenCaptureService) created
                // gaps: Phase-1 chunks had no video frames (dropped as too small
                // or rejected by server), and the async gap between phases let
                // LiveKit reset AVAudioSession to SoloAmbient, silencing the mic.
                //
                // Dart side still calls startScreenCaptureService separately for
                // the iOS permission dialog flow; we use rpRunning to make that
                // a cheap no-op once we are already capturing.
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                    return
                }
                guard !self.recording else {
                    // Already recording — just confirm so Dart resolves.
                    self.emitEvent(["event": "screenLoopStarted"])
                    result(true)
                    return
                }
                self.sessionId  = args["sessionId"]    as? Int    ?? 0
                self.uploadUrl  = args["uploadUrl"]    as? String ?? ""
                self.authToken  = args["authToken"]    as? String ?? ""
                self.chunkSecs  = args["chunkSeconds"] as? Int    ?? 5
                // chunkIndex is monotonically increasing across the whole
                // session — never reset to 0 so a reconnect doesn't overwrite
                // already-uploaded chunks on the server.
                let startIdx    = args["chunkIndex"]   as? Int    ?? 0
                if startIdx > self.chunkIndex { self.chunkIndex = startIdx }
                NSLog("[REC] startMicRecording: session=\(self.sessionId) chunk=\(self.chunkIndex) secs=\(self.chunkSecs)")
                self.recording   = true
                self.stopping    = false
                self.paused      = false
                self.videoWidth  = 0
                self.videoHeight = 0
                self.sweepStaleChunks()
                // Emit before startRPScreenRecorder so Dart's _startCompleter
                // resolves immediately regardless of how long permission dialog takes.
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)
                // Start RPScreenRecorder (permission dialog + red-pill).
                // This is async; the chunk timer inside beginChunkWriter()
                // is scheduled here and frames start flowing once the dialog
                // is approved — no gap between param-store and first frame.
                self.startRPScreenRecorder(result: { _ in })

            case "upgradeToScreenRecording":
                if self.recording {
                    // Emit a DISTINCT event so Dart's _upgradeCompleter resolves
                    // without accidentally triggering Phase-1 logic or resetting
                    // the chunk timer again via another beginChunkWriter() call.
                    self.emitEvent(["event": "videoChunksActive"])
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

        // recording/paused/stopping/videoWidth/videoHeight were already
        // set in startMicRecording (Phase 1). Don't reset them here.
        rpRunning = true
        configureAudioSessionForRecording()
        rp.isMicrophoneEnabled = true
        // beginChunkWriter() was already called in Phase 1.
        // scheduleChunkTimer()'s guard (chunkTimer == nil) makes this a no-op
        // if the timer is already running, so it's safe to call again just in
        // case Phase 1 didn't complete for some reason.
        if assetWriter == nil { beginChunkWriter() }

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
                    // RPScreenRecorder failed — mark rpRunning=false.
                    // recording stays true: the Phase-1 chunk loop is still running
                    // (audio-only chunks). The session can still be stopped cleanly.
                    self.rpRunning = false
                    self.releaseAudioSessionLock()
                    result(FlutterError(code: "RP_START_ERROR",
                                        message: e.localizedDescription, details: nil))
                    return
                }
                // ── Re-arm audio session AFTER startCapture completes ────────
                // LiveKit's RTCAudioSession may have reconfigured the session
                // during the async gap (visible in logs as "SoloAmbient").
                // Re-applying here ensures mic input is active when frames arrive.
                self.configureAudioSessionForRecording()

                // Schedule a delayed re-arm to catch any LiveKit reset that
                // fires after the completion handler (observed in practice).
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.recording else { return }
                    self.configureAudioSessionForRecording()
                    NSLog("[REC] AVAudioSession: delayed re-arm applied")
                }

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

            // Real per-frame duration = delta from the previous broadcast
            // frame's PTS. Extension frame cadence is not fixed (JPEG encode +
            // shared-file write + Darwin notify round-trip jitters), so a
            // hardcoded 1/30s duration would be wrong on most frames even
            // though the PTS itself is accurate. Clamp to a sane range so a
            // single dropped/delayed notification (or the first frame, which
            // has no prior PTS to diff against) can't produce a zero-length
            // or absurdly long sample.
            let fallbackDuration = CMTime(value: 1, timescale: 30)
            var duration = fallbackDuration
            if let last = self.lastBroadcastPts {
                let delta = CMTimeSubtract(pts, last)
                let deltaSeconds = CMTimeGetSeconds(delta)
                if deltaSeconds.isFinite, deltaSeconds > 0.005, deltaSeconds < 1.0 {
                    duration = delta
                }
                // else: out-of-range delta (clock jump, dropped notification,
                // or out-of-order frame) — keep fallbackDuration rather than
                // writing a degenerate sample.
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
        // beginChunkWriter creates an AVAssetWriter and schedules a Timer.
        // Both must happen on the main thread:
        //   • Timer.scheduledTimer requires the main RunLoop
        //   • AVAssetWriter init is not thread-safe
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
        // New chunk = new writer = new timeline, so the previous chunk's last
        // broadcast-frame PTS is no longer a valid baseline for a duration
        // delta. Reset it so the first broadcast frame of this chunk falls
        // back to fallbackDuration instead of computing a (likely huge,
        // cross-chunk) delta.
        lastBroadcastPts = nil

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) \(w)×\(h)")
        scheduleChunkTimer()
    }

    private func scheduleChunkTimer() {
        // MUST run on main thread — Timer.scheduledTimer requires a RunLoop.
        // Background DispatchQueues (writerQueue, ipcReadQueue) have NO RunLoop,
        // so a Timer created there is never added to any run loop and never fires.
        // Result: chunks are never rotated → only the first chunk is ever saved.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleChunkTimer() }
            return
        }
        // Guard: if a timer is already running, don't reset it.
        // beginChunkWriter() can be called multiple times (e.g. from 3 rapid
        // screenLoopStarted events) and each call previously reset the timer
        // back to zero — the 5-second chunk never completed.
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
        guard recording, !stopping, !paused else { return }
        // Nil the timer here so scheduleChunkTimer() inside the next
        // beginChunkWriter() call sees nil and creates a fresh one.
        chunkTimer?.invalidate()
        chunkTimer = nil
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
        stopping = true; recording = false; rpRunning = false
        chunkTimer?.invalidate(); chunkTimer = nil
        isBroadcasting = false
        removeDarwinListeners()
        endBgTask()

        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error { NSLog("[REC] stopCapture: \(e.localizedDescription)") }
            // ── Drain the writer queue before finalising ───────────────────
            // stopCapture's completion fires before all queued
            // processSampleFromRecorder calls finish executing on writerQueue.
            // Without this barrier, finishWriting races with in-flight
            // appends → the last 1-3 seconds of the session are truncated.
            // writerQueue.async{} after the barrier runs only after all
            // prior writerQueue work is done, then we hop to main to finalise.
            self?.writerQueue.async {
                DispatchQueue.main.async {
                    self?.finaliseChunk(isFinal: isFinal) {
                        self?.stopping = false
                        result(nil)
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk finalisation & upload
    // ─────────────────────────────────────────────────────────────────────────

    private func finaliseChunk(isFinal: Bool, completion: @escaping () -> Void) {
        // Capture into locals and nil immediately — prevents double-finishWriting crash.
        // "Cannot call finishWritingWithCompletionHandler when status is 2" happens
        // when this is called twice on the same writer (e.g. stopBroadcastShare then
        // stopRecording). Nilling first means the second call hits the guard below.
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
        assetWriter = nil; videoInput = nil; audioInput = nil
        currentFile = nil; writerSessionStarted = false
        let idx = chunkIndex
        writerQueue.async { [weak self] in
            vi.markAsFinished()
            ai.markAsFinished()
            writer.finishWriting {
                if writer.status == .failed {
                    NSLog("[REC] writer failed chunk #\(idx): \(writer.error?.localizedDescription ?? "unknown")")
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
            return
        }

        // ── Read file size BEFORE touching the file ───────────────────────────
        // resourceValues returns nil once the file is deleted, so we must
        // capture the size now, not after removeItem.
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard fileSize > 0 else {
            NSLog("[REC] chunk #\(index) file missing or empty — skipping")
            return
        }

        // ── Build multipart body with a temp file ─────────────────────────────
        // Using request.httpBody = Data(contentsOf:) loads the entire video
        // chunk into RAM and URLSession may silently drop large bodies.
        // Instead we write the multipart envelope to a temp file and use
        // uploadTask(with:fromFile:) which streams directly from disk —
        // the correct approach for large binary payloads.
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

        // Write header + video bytes + footer into a single temp file.
        guard let videoData = try? Data(contentsOf: fileURL) else {
            NSLog("[REC] chunk #\(index) could not read video file")
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
            return
        }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken,                                      forHTTPHeaderField: "Authorization")
        request.setValue("\(multipart.count)",                          forHTTPHeaderField: "Content-Length")
        request.timeoutInterval = 120

        // uploadTask(with:fromFile:) streams the temp file — no RAM spike.
        // Use the dedicated background URLSession so this upload survives
        // LiveKit disconnect / app backgrounding (URLSession.shared is cancelled
        // by the WebRTC stack teardown, causing "network connection was lost").
        uploadSession.uploadTask(with: request, fromFile: tmpURL) { [weak self] _, response, error in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: tmpURL)   // clean temp file

            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[REC] chunk #\(index) HTTP \(code) isFinal=\(isFinal) size=\(fileSize)B")

            if error != nil || code < 200 || code > 299 {
                let reason = error?.localizedDescription ?? "HTTP \(code)"
                NSLog("[REC] chunk #\(index) attempt \(attempt+1) failed: \(reason)")
                if attempt < 4 {
                    // Back-off: 3s, 6s, 12s, 24s — longer than before because
                    // waitsForConnectivity means the network may need time to
                    // fully re-establish after LiveKit tears down its sockets.
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(3 * (1 << attempt))) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index,
                                              isFinal: isFinal, attempt: attempt + 1)
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.emitError("chunk #\(index) failed after 4 retries: \(reason)")
                }
                return
            }

            // Success — delete the original chunk file and notify Dart.
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[REC] chunk #\(index) uploaded OK (\(fileSize)B isFinal=\(isFinal))")
            DispatchQueue.main.async {
                self.emitEvent(["event": "chunkUploaded", "chunkIndex": index,
                                "bytes": fileSize, "isFinal": isFinal])
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
        // Only remove chunk files that are more than 1 hour old.
        // Deleting recent files risks wiping chunks that a background URLSession
        // task is currently uploading from a previous session launch.
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

            // Pre-start background task before picker appears — teacher may
            // switch apps immediately after confirming.
            self.appDidEnterBackground()

            // ── Do NOT pause recording during the picker overlay ─────────
            // The previous approach paused (finalisedChunk + stopped writing)
            // here, creating a deliberate gap of 5–30 seconds while the user
            // looks at the system picker. For continuous recording we keep
            // RPScreenRecorder writing app-screen frames throughout.
            //
            // AVAudioSession interruptions from the system sheet are handled
            // by our audioSessionRouteChanged / audioSessionInterrupted
            // observers which re-arm playAndRecord+videoChat+mixWithOthers
            // automatically after iOS resumes the app.
            //
            // When the first Darwin frame notification arrives (broadcast confirmed),
            // handleBroadcastData sets isBroadcasting=true which suppresses
            // RPScreenRecorder frames in favour of the extension frames —
            // the transition is seamless with no gap.
            NSLog("[SHARE] picker: recording continues uninterrupted during overlay")

            // Register Darwin notification listeners BEFORE the picker appears
            // so we are ready the instant the extension's broadcastStarted() fires.
            self.registerDarwinListeners()

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
        // Recording was never paused during the picker; just rotate the chunk
        // so the transition from broadcast back to RPScreenRecorder is seamless.
        if recording && !stopping && !paused {
            finaliseChunk(isFinal: false) { [weak self] in
                guard let self = self, self.recording, !self.stopping, !self.paused else { return }
                self.chunkIndex += 1
                self.beginChunkWriter()
                NSLog("[SHARE] broadcast chunk rotated — RPScreenRecorder resuming at chunk #\(self.chunkIndex)")
            }
        }
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
        // Broadcast ended — rotate chunk and resume RPScreenRecorder frames.
        // (Recording was never paused during the picker, so no paused-state
        // branch is needed here.)
        if recording && !stopping && !paused {
            finaliseChunk(isFinal: false) { [weak self] in
                guard let self = self, self.recording, !self.stopping, !self.paused else { return }
                self.chunkIndex += 1
                self.beginChunkWriter()
                NSLog("[SHARE] Darwin stop: chunk rotated at #\(self.chunkIndex)")
            }
        }
    }

    /// Parse a frame blob and route it to the writer.
    /// Wire format: [4B typeId BE][8B ptsNs BE][4B payloadSize BE][payload]
    /// typeId: 0 = video (JPEG), 1 = audioMic (PCM), 2 = audioApp (PCM)
    private func handleBroadcastData(_ data: Data) {
        guard data.count >= 16 else { return }

        // NOTE: do NOT use withUnsafeBytes { $0.load(as:) } here.
        // load(as:) requires the pointer to be aligned to the loaded type's
        // size (8 bytes for UInt64, 4 for UInt32). Data.dropFirst(n) returns
        // a slice whose base address is `originalBase + n` — Data/Foundation
        // makes no alignment guarantee for that address, so loading a UInt64
        // from an offset-4 slice (as the old ptsNs line did) crashes roughly
        // half the time with "Fatal error: load from misaligned raw pointer"
        // depending on where the OS happened to place the backing buffer.
        // Decoding byte-by-byte below is alignment-safe by construction since
        // UInt8 has no alignment requirement greater than 1.
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
            // Video frame (JPEG) — write into the active AVAssetWriter chunk.
            if !isBroadcasting {
                isBroadcasting = true
                // Fresh broadcast session — any previous PTS baseline is from
                // a prior (now-stopped) broadcast and would produce a bogus
                // duration delta on the first frame of this one.
                lastBroadcastPts = nil
                NSLog("[SHARE] first broadcast frame — switching recording source")
                // Recording is continuous — no paused state to resume from.
                // isBroadcasting=true is enough to route subsequent frames
                // through processSampleFromBroadcast instead of RPScreenRecorder.
                NSLog("[SHARE] broadcast active — switching frame source at chunk #\(chunkIndex)")
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