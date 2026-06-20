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
        // Allow up to 4 concurrent connections so chunks upload in parallel.
        // Previously set to 1 (serial) to avoid Cloudflare tunnel connection-
        // limit resets — but serial uploads mean chunk N+1 sits on disk waiting
        // for chunk N to finish, so on a slow tunnel only 1 chunk uploads per
        // session interval. With 4 parallel connections, the last few chunks
        // can all upload simultaneously during the stop-recording wait window.
        // trycloudflare.com doesn't enforce a strict per-IP connection limit
        // in practice; if you see resets in production, lower this to 2.
        cfg.httpMaximumConnectionsPerHost = 4
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

    // ── Broadcast-picker watchdog ─────────────────────────────────────────────
    // showBroadcastPicker() pauses RPScreenRecorder and waits for the extension
    // to deliver its first frame before recording resumes. If the system sheet
    // never actually appears (e.g. the simulated button tap on the picker view
    // fails on a given iOS version) or the user backs out without the normal
    // cancel path firing, nothing would ever resume recording and only the
    // pre-share chunk(s) would ever reach the server. This timer is a safety
    // net: if no broadcast frame has arrived within pickerWatchdogSecs of
    // showing the picker, we assume the broadcast never started and resume
    // RPScreenRecorder ourselves.
    private var pickerWatchdog: Timer?
    private let pickerWatchdogSecs: TimeInterval = 10
    // Kept alive only so the picker view (which must be in the window/view
    // hierarchy for its button to reliably trigger the system sheet) isn't
    // deallocated before iOS has had a chance to act on the simulated tap.
    private var activeBroadcastPicker: RPSystemBroadcastPickerView?

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
            self.finaliseChunk(isFinal: false) { [weak self] _ in
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
                // FIX: previously this checked only `self.recording`, which
                // stays true the entire time we are `paused` waiting for a
                // broadcast extension's first frame (see showBroadcastPicker).
                // That meant calling this right after showing the broadcast
                // picker reported "Phase-2 confirmed" / emitted
                // 'videoChunksActive' INSTANTLY and unconditionally — even
                // though nothing was actually being captured yet, because the
                // picker's system sheet hadn't even been confirmed by the
                // user. Dart would then believe screen-share recording was
                // live while in reality the recorder was still paused with no
                // writer, so when the session ended shortly after, there was
                // nothing left to finalise but the one chunk recorded before
                // the share tap. confirmRecordingActive() now actually waits
                // for `paused` to clear (i.e. a real frame arrived, or the
                // watchdog/cancel path resumed RPScreenRecorder) before
                // reporting success.
                self.confirmRecordingActive(result: result)

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

    /// Confirms recording is genuinely live (frames currently being written —
    /// either by RPScreenRecorder or by an active broadcast) before telling
    /// Dart that Phase-2 / screen-share upgrade succeeded.
    ///
    /// Critically, while `paused` is true (e.g. between showBroadcastPicker
    /// pausing RPScreenRecorder and the extension's first frame actually
    /// arriving), we must NOT report success yet. The old implementation
    /// fired the "videoChunksActive" event immediately whenever `recording`
    /// was true, which stayed true throughout the paused window — a false
    /// positive that told Dart broadcast chunks were flowing when nothing
    /// was being captured at all.
    ///
    /// We poll briefly instead of failing immediately, because `paused`
    /// legitimately flips back to false very soon after this is called in
    /// the normal flows (RPScreenRecorder's own Phase-2 upgrade, or a
    /// broadcast frame arriving a moment after the user confirms the system
    /// sheet). 20 attempts * 0.25s = 5s, comfortably inside Dart's own 20s
    /// timeout for this call so a genuine failure is still reported promptly
    /// rather than silently falling back to Dart's "assume live" timeout path.
    private func confirmRecordingActive(result: @escaping FlutterResult, attemptsLeft: Int = 20) {
        guard recording, !stopping else { result(false); return }
        guard paused else {
            // Genuinely writing frames right now.
            emitEvent(["event": "videoChunksActive"])
            result(true)
            return
        }
        guard attemptsLeft > 0 else {
            NSLog("[REC] upgradeToScreenRecording: still paused after wait — reporting not-yet-active")
            result(false)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.confirmRecordingActive(result: result, attemptsLeft: attemptsLeft - 1)
        }
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
        // LiveKit resets AVAudioSession to SoloAmbient (output-only) after
        // RPScreenRecorder starts, killing mic input and causing silent/noisy
        // audio in recordings.
        //
        // Strategy:
        //   1. Configure playAndRecord+videoChat+mixWithOthers BEFORE startCapture.
        //   2. Set recording=true BEFORE the async completion handler fires, so
        //      stopRecording() called during startup still reaches finaliseChunk().
        //   3. After startCapture's completion fires, re-apply the audio config
        //      because LiveKit may have reset it during the async gap.
        //   4. Schedule a one-shot re-arm 1 s later to catch any delayed reset.
        configureAudioSessionForRecording()

        rp.isMicrophoneEnabled = true

        // ── Set recording=true BEFORE startCapture's async completion ────────
        // Without this, if stopRecording() is called while startCapture is still
        // in flight (e.g. user taps End Session quickly), the guard
        // `guard recording else { return }` in stopRecording() exits immediately
        // without calling finaliseChunk(), producing 0 uploaded chunks.
        recording = true
        // NOTE: do NOT call beginChunkWriter() here.
        // beginChunkWriter() starts the 5-second chunk timer. If we start it
        // before startCapture's completionHandler fires (which takes 1-3s on
        // device), the timer fires into a writer that has never had startSession
        // called — finishWriting on an un-started AVAssetWriter produces a
        // corrupt/empty file that gets dropped. Worse, that race means chunk #0
        // is silently dropped and chunkIndex increments to 1 before any real
        // media is captured. The timer is started in completionHandler below,
        // after RPScreenRecorder confirms it is actually delivering frames.

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
                    // Undo the optimistic recording=true so we stay consistent.
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
                // ── Re-arm audio session AFTER startCapture completes ────────
                self.configureAudioSessionForRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, self.recording else { return }
                    self.configureAudioSessionForRecording()
                    NSLog("[REC] AVAudioSession: delayed re-arm applied")
                }

                // ── Start chunk writer NOW — RPScreenRecorder is delivering ──
                // The first video frame will anchor the AVAssetWriter session,
                // and the 5-second timer starts from this moment, not from
                // before startCapture was called.
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
        // ALWAYS nil the timer reference first, unconditionally — even if we're
        // about to return early due to paused/stopping/not-recording.
        // If we don't, the spent (fired, non-repeating) timer object sits in
        // chunkTimer non-nil, and the next beginChunkWriter() → scheduleChunkTimer()
        // call hits `guard chunkTimer == nil` and returns without scheduling a new
        // timer — so chunks never rotate again for the rest of the session.
        // This was the cause of "only records chunks before sharing": showBroadcastPicker
        // sets paused=true, the 5-second timer fires, rotateChunk() returns early
        // (paused guard), chunkTimer stays non-nil with the spent timer, then when
        // the first broadcast frame arrives and calls beginChunkWriter(), no new
        // timer is ever scheduled. One giant broadcast chunk accumulates until
        // stopRecording() flushes it — instead of 5-second rotations.
        chunkTimer?.invalidate()
        chunkTimer = nil
        guard recording, !stopping, !paused else { return }
        finaliseChunk(isFinal: false) { [weak self] _ in
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
        finaliseChunk(isFinal: false) { [weak self] _ in
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
        NSLog("[REC] stopRecording: isFinal=\(isFinal) isBroadcasting=\(isBroadcasting)")
        stopping = true; recording = false
        chunkTimer?.invalidate(); chunkTimer = nil
        pickerWatchdog?.invalidate(); pickerWatchdog = nil
        activeBroadcastPicker?.removeFromSuperview()
        activeBroadcastPicker = nil
        isBroadcasting = false
        removeDarwinListeners()
        endBgTask()

        // ── Why we hold result open until the upload completes ────────────────
        // On iOS there is no ForegroundService — once result(nil) fires, Dart
        // calls widget.onEnd() which tears down the room, backgrounds the app,
        // and may suspend the process. Any in-flight URLSession.default task
        // is killed silently on suspension. So we must NOT call result(nil)
        // until the final chunk has actually landed on the server.
        //
        // Flow:
        //   finaliseChunk → finishWriting → uploadChunkAsync(isFinal:true)
        //     success/final-failure → stopCapture → result(nil)   ← Dart unblocks
        //
        // This means Dart's `await invokeMethod('stopRecording')` truly waits
        // for the upload, so _endSessionWithRecording's `await stopRecordingOnly()`
        // blocks until the server has the final chunk before onEnd() is called.
        //
        // BUT: if finaliseChunk had nothing to finalise — e.g. the user ended
        // the session while still `paused` waiting on a broadcast picker that
        // never actually started, so no AVAssetWriter/frames ever existed for
        // this "chunk" — no upload will EVER be queued, and waiting on
        // stopResult would hang until Dart's own 90s timeout. uploadQueued
        // tells us which case we're in.
        finaliseChunk(isFinal: isFinal) { [weak self] uploadQueued in
            guard let self = self else { result(nil); return }
            // Pass result into uploadChunkAsync — it will call result(nil) once
            // the upload succeeds or exhausts its retries. If the chunk is
            // not-final or there's nothing to upload, uploadChunkAsync calls
            // result(nil) immediately after the final attempt.
            self.stopCaptureThenSignal(result: result, expectFinalUpload: uploadQueued)
        }
    }

    /// Called after finaliseChunk completes. Stops RPScreenRecorder and waits
    /// for uploadChunkAsync to fire stopResult when the final upload lands.
    /// IMPORTANT: stopCapture's completion must NOT call result(nil) — on a
    /// slow network (Cloudflare tunnel) stopCapture completes in <1s but the
    /// upload takes much longer. Firing result here would unblock Dart before
    /// the chunk reaches the server, causing onEnd() to kill the upload.
    ///
    /// `expectFinalUpload` must be false when finaliseChunk produced nothing
    /// to upload (e.g. stop was called mid-pause with no frames captured) —
    /// in that case nothing will ever call uploadChunkAsync's isFinal path,
    /// so we must fire result(nil) right here instead of waiting forever.
    private var stopResult: FlutterResult?

    private func stopCaptureThenSignal(result: @escaping FlutterResult, expectFinalUpload: Bool) {
        if expectFinalUpload {
            stopResult = result
        }
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error { NSLog("[REC] stopCapture: \(e.localizedDescription)") }
            DispatchQueue.main.async {
                self?.stopping = false
                if expectFinalUpload {
                    // Do NOT fire result(nil) here — uploadChunkAsync holds
                    // stopResult and fires it when the server confirms the
                    // final chunk (or after all retries fail). Firing here
                    // would unblock Dart before the upload completes, killing
                    // the in-flight URLSession task when onEnd() backgrounds
                    // the app.
                    NSLog("[REC] stopCapture done — waiting for final chunk upload to confirm")
                } else {
                    // Nothing was queued to upload — there is nothing left to
                    // wait for, so unblock Dart now instead of stalling for
                    // 90s until its own timeout gives up.
                    NSLog("[REC] stopCapture done — no final chunk was produced, unblocking Dart now")
                    result(nil)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk finalisation & upload
    // ─────────────────────────────────────────────────────────────────────────

    private func finaliseChunk(isFinal: Bool, completion: @escaping (_ uploadQueued: Bool) -> Void) {
        // Capture into locals and nil immediately — prevents double-finishWriting crash.
        // "Cannot call finishWritingWithCompletionHandler when status is 2" happens
        // when this is called twice on the same writer (e.g. stopBroadcastShare then
        // stopRecording). Nilling first means the second call hits the guard below.
        //
        // `uploadQueued` tells the caller whether an upload was actually handed
        // off to uploadChunkAsync(). This matters for the stop path: if there is
        // nothing to upload (e.g. we were paused waiting on a broadcast picker
        // that never actually started, so no frames were ever written), the
        // caller must NOT block waiting for an isFinal upload completion that
        // will never happen — that was the cause of stopRecording hanging for
        // the full 90s Dart timeout with only the pre-share chunk ever landing.
        guard let writer  = assetWriter,
              let vi      = videoInput,
              let ai      = audioInput,
              let fileURL = currentFile else {
            DispatchQueue.main.async { [weak self] in
                // No writer — fire stopResult if this is the stop path.
                if let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                completion(false)
            }
            return
        }
        guard writer.status == .writing else {
            NSLog("[REC] finaliseChunk skipped (writer status=\(writer.status.rawValue))")
            assetWriter = nil; videoInput = nil; audioInput = nil
            currentFile = nil; writerSessionStarted = false
            DispatchQueue.main.async { [weak self] in
                if let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                completion(false)
            }
            return
        }
        // Guard: if startSession was never called (no frames arrived yet),
        // calling finishWriting produces a corrupt/empty container. Drop it.
        guard writerSessionStarted else {
            NSLog("[REC] finaliseChunk skipped — startSession never called (no frames yet)")
            assetWriter = nil; videoInput = nil; audioInput = nil
            currentFile = nil; writerSessionStarted = false
            try? FileManager.default.removeItem(at: fileURL)
            DispatchQueue.main.async { [weak self] in
                if let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                completion(false)
            }
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
                    DispatchQueue.main.async { [weak self] in
                        if isFinal, let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                        completion(false)
                    }
                    return
                }
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                if size < 512 {
                    NSLog("[REC] chunk #\(idx) too small (\(size)B) — dropping")
                    try? FileManager.default.removeItem(at: fileURL)
                    DispatchQueue.main.async { [weak self] in
                        if isFinal, let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                        completion(false)
                    }
                    return
                }
                NSLog("[REC] finalised chunk #\(idx) (\(size)B isFinal=\(isFinal))")
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal)
                }
                DispatchQueue.main.async { completion(true) }
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
                    // Final chunk failed permanently — still unblock Dart so the
                    // session can close. The idle watchdog on the server will
                    // assemble whatever chunks landed successfully.
                    if isFinal {
                        DispatchQueue.main.async {
                            if let r = self.stopResult {
                                self.stopResult = nil
                                r(nil)
                            }
                        }
                    }
                }
                return
            }

            // Success — delete the original chunk file and notify Dart.
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[REC] chunk #\(index) uploaded OK (\(fileSize)B isFinal=\(isFinal))")
            DispatchQueue.main.async {
                self.emitEvent(["event": "chunkUploaded", "chunkIndex": index,
                                "bytes": fileSize, "isFinal": isFinal])
                // Final chunk confirmed by server — now safe to unblock Dart.
                // Dart's await invokeMethod('stopRecording') resolves here,
                // allowing _endSessionWithRecording to call widget.onEnd().
                if isFinal {
                    if let r = self.stopResult {
                        self.stopResult = nil
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

            // ── ORDER MATTERS ────────────────────────────────────────────
            // registerDarwinListeners() MUST run before appDidEnterBackground().
            // appDidEnterBackground()'s very first line is:
            //     guard isBroadcasting || darwinObserverAdded else { return }
            // At this point isBroadcasting is still false (the extension
            // hasn't sent its first frame yet), so that guard only passes if
            // darwinObserverAdded is already true. Calling
            // appDidEnterBackground() first meant the guard always failed,
            // beginBackgroundTask() was never started, and a few seconds
            // later — exactly when the teacher switches away to the app they
            // want to share — iOS suspends the host process with no
            // background task protecting it. The chunk timer and upload
            // callbacks then freeze until the user returns to the app, which
            // is what looked like "recording stops the moment you open
            // another app to share". Registering the Darwin listeners first
            // makes the guard pass and the background task actually start.
            self.registerDarwinListeners()
            self.appDidEnterBackground()

            if self.recording && !self.paused && !self.stopping {
                self.paused = true
                NSLog("[SHARE] picker: recording paused before system overlay")
                self.finaliseChunk(isFinal: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.chunkIndex += 1
                    NSLog("[SHARE] picker: paused chunk rotated at #\(self.chunkIndex)")
                }
            }

            // ── preferredExtension = OUR extension (not nil) ─────────────────
            //
            // IMPORTANT — why NOT nil:
            //   Setting preferredExtension = nil shows a generic "Choose a
            //   broadcast app" picker listing every broadcast extension on the
            //   device. Our extension still appears, but:
            //     a) The user must manually pick it (bad UX).
            //     b) If the user picks a different extension (e.g. a third-party
            //        streaming app), our SampleHandler never runs, we never get
            //        Darwin notifications, and the recording hangs forever.
            //
            // Setting preferredExtension = our bundle makes iOS show a direct
            // one-tap confirmation sheet for OUR extension and immediately starts
            // SampleHandler, which receives the FULL DEVICE SCREEN COMPOSITOR —
            // including any app the user navigates to after confirming.
            //
            // ── Why some apps (Facebook, Netflix) show "share not available" ──
            //
            //   These apps call UIScreen.main.isCaptured and actively block
            //   screen recording using AVCaptureSession / DRM enforcement.
            //   This is enforced by the APP being recorded, not by iOS or our
            //   extension. It cannot be bypassed — Apple's own QuickTime, AirPlay
            //   mirroring, and every other screen recorder hits the same block.
            //   Whiteboards, browsers, document cameras, PDF viewers, and most
            //   educational apps work fine.
            //
            // ── How to share any app's screen ────────────────────────────────
            //
            //   1. Teacher taps "Share Screen" → this picker appears.
            //   2. Teacher taps "Start Broadcast" → SampleHandler starts.
            //   3. Teacher SWITCHES to the app they want to share (home button
            //      or swipe up → tap the other app). SampleHandler keeps
            //      receiving frames of whatever is on screen.
            //   4. The recording captures everything the teacher shows —
            //      across any non-DRM app.
            //
            let picker = RPSystemBroadcastPickerView(
                frame: CGRect(x: 0, y: 0, width: 60, height: 60))
            picker.preferredExtension =
                Bundle.main.bundleIdentifier.map { $0 + ".BroadcastUploadExtension" }
            picker.showsMicrophoneButton = false

            // ── CRITICAL: the picker must be part of a live window ───────────
            // RPSystemBroadcastPickerView's internal button only reliably
            // presents the system "Start Broadcast" sheet when the view is
            // actually installed in a window. Previously this view was never
            // added to any superview — the simulated tap below had nothing
            // to act on, so on affected iOS versions the sheet silently never
            // appeared, the extension never launched, `paused` stayed true
            // forever, and only the chunk(s) recorded before this tap ever
            // reached the server. We keep it nearly invisible (not literally
            // hidden — UIKit does not forward control events to hidden views)
            // and behind everything else, then remove it shortly after.
            guard let hostWindow = self.window else {
                NSLog("[SHARE] showBroadcastPicker: no window available")
                result(nil)
                return
            }
            picker.alpha = 0.01
            hostWindow.addSubview(picker)
            hostWindow.sendSubviewToBack(picker)
            self.activeBroadcastPicker = picker

            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }
            NSLog("[SHARE] showBroadcastPicker — extension: \(picker.preferredExtension ?? "nil")")

            // Remove the picker view shortly after — it has done its job of
            // hosting the tap that opens the system sheet. The sheet itself
            // is presented by iOS in its own process and doesn't need this
            // view to remain in the hierarchy.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                picker.removeFromSuperview()
                if self?.activeBroadcastPicker === picker {
                    self?.activeBroadcastPicker = nil
                }
            }

            // ── Watchdog: resume if the broadcast never actually starts ──────
            // Covers: sheet failed to present, user dismissed it without going
            // through "Start Broadcast", or the extension failed to launch
            // (signing/App-Group misconfiguration etc). Cancelled as soon as
            // a real broadcast frame arrives (handleBroadcastData), the user
            // explicitly cancels (stopBroadcastShare), or the extension itself
            // reports it stopped (onDarwinStopNotif).
            self.pickerWatchdog?.invalidate()
            self.pickerWatchdog = Timer.scheduledTimer(
                withTimeInterval: self.pickerWatchdogSecs, repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                self.pickerWatchdog = nil
                guard self.recording, self.paused, !self.isBroadcasting, !self.stopping else { return }
                NSLog("[SHARE] picker watchdog: no broadcast frame after " +
                      "\(self.pickerWatchdogSecs)s — resuming RPScreenRecorder")
                self.paused = false
                self.beginChunkWriter()
            }

            result(nil)
        }
    }

    private func stopBroadcastShare(result: @escaping FlutterResult) {
        isBroadcasting = false
        removeDarwinListeners()
        endBgTask()
        pickerWatchdog?.invalidate()
        pickerWatchdog = nil
        activeBroadcastPicker?.removeFromSuperview()
        activeBroadcastPicker = nil
        emitEvent(["event": "broadcastStopped"])
        NSLog("[SHARE] broadcast stopped by app")
        if recording && !stopping {
            if paused {
                // Broadcast was never confirmed (user cancelled picker).
                // Resume RPScreenRecorder which was paused by showBroadcastPicker.
                paused = false
                beginChunkWriter()
                NSLog("[SHARE] picker cancelled — RPScreenRecorder resumed at chunk #\(chunkIndex)")
            } else {
                // Broadcast was active: finalise the broadcast chunk and start
                // a fresh RPScreenRecorder chunk.
                finaliseChunk(isFinal: false) { [weak self] _ in
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
        pickerWatchdog?.invalidate()
        pickerWatchdog = nil
        activeBroadcastPicker?.removeFromSuperview()
        activeBroadcastPicker = nil
        emitEvent(["event": "broadcastStopped"])
        if recording && !stopping {
            if paused {
                // Extension stopped before we got the first frame (race).
                paused = false
                beginChunkWriter()
                NSLog("[SHARE] Darwin stop: resumed from paused state at chunk #\(chunkIndex)")
            } else {
                finaliseChunk(isFinal: false) { [weak self] _ in
                    guard let self = self, self.recording, !self.stopping, !self.paused else { return }
                    self.chunkIndex += 1
                    self.beginChunkWriter()
                    NSLog("[SHARE] Darwin stop: chunk rotated at #\(self.chunkIndex)")
                }
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
                // Broadcast is confirmed live — the watchdog that would have
                // resumed RPScreenRecorder on a no-show is no longer needed.
                pickerWatchdog?.invalidate()
                pickerWatchdog = nil
                // Fresh broadcast session — any previous PTS baseline is from
                // a prior (now-stopped) broadcast and would produce a bogus
                // duration delta on the first frame of this one.
                lastBroadcastPts = nil
                NSLog("[SHARE] first broadcast frame — switching recording source")
                // If recording was paused by showBroadcastPicker (to protect
                // against the iOS overlay suspension window), resume it now.
                // The extension is running, iOS has fully resumed, it's safe to write.
                if recording && paused && !stopping {
                    paused = false
                    beginChunkWriter()
                    NSLog("[SHARE] recording resumed from picker-pause — broadcast chunk #\(chunkIndex)")
                }
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