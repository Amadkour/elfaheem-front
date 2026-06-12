import Flutter
import UIKit
import Firebase
import ReplayKit
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
// AppDelegate — iOS recording pipeline mirroring the Android two-channel model.
//
// CHANNEL ARCHITECTURE (matches Android exactly):
//
//   com.example.flutter_education_app/screen_share   (MethodChannel)
//     startScreenCaptureService  → requests mic permission, starts RPScreenRecorder,
//                                  begins chunk loop, emits "screenLoopStarted"
//     startMicRecording          → stores session params (service config phase)
//     upgradeToScreenRecording   → no-op on iOS (RPScreenRecorder captures both
//                                  mic + screen in one go); returns true immediately
//     stopScreenCapture          → emits "micLoopStarted" (share ended, back to
//                                  audio-only equivalent)
//     downgradeToMicForShare     → emits "micReadyForShare" (share about to start)
//     promoteForShare            → no-op; unblocks any Dart waiter
//     stopRecording              → stops chunk loop and RPScreenRecorder
//     pauseRecording             → pauses chunk rotation, emits "recordingPaused"
//     resumeRecording            → resumes chunk rotation, emits "recordingResumed"
//     getChunkIndex              → returns current chunk index
//
//   com.example.flutter_education_app/rec_events   (EventChannel)
//     screenLoopStarted          → RPScreenRecorder is capturing and chunk loop running
//     micReadyForShare           → downgradeToMicForShare acknowledged
//     micLoopStarted             → stopScreenCapture acknowledged
//     chunkUploaded              → { chunkIndex, bytes, isFinal }
//     recordingPaused            → chunk loop is parked
//     recordingResumed           → chunk loop is running again
//     REC_ERROR                  → error string
//
// LIFECYCLE (mirrors Android):
//   Phase 1 — startMicRecording  : store session/upload params (mic-only on Android).
//                                   On iOS RPScreenRecorder does both, so we just save
//                                   params here and delay the permission dialog.
//   Phase 2 — startScreenCaptureService : request mic permission → start RPScreenRecorder
//                                   → begin chunk loop → emit "screenLoopStarted".
//   Phase 3 — upgradeToScreenRecording  : on Android this shows a second system dialog
//                                   for flutter_webrtc. On iOS flutter_webrtc handles
//                                   its own broadcast extension, so we return true
//                                   immediately and emit "screenLoopStarted" again
//                                   so Dart's completer resolves.
//
// PAUSE / RESUME:
//   pauseRecording  → invalidate chunkTimer, finish current chunk (isFinal=false),
//                     upload it, park — emit "recordingPaused".
//   resumeRecording → restart chunk loop from next index — emit "recordingResumed".
//
// SCREEN-SHARE COORDINATION:
//   downgradeToMicForShare → emits "micReadyForShare" so Dart waits for a clean
//                             chunk boundary before flutter_webrtc starts sharing.
//   stopScreenCapture      → emits "micLoopStarted" so Dart knows share ended and
//                             re-upgrade can proceed.
// ─────────────────────────────────────────────────────────────────────────────

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    // ── Channel names (must match Android / Dart exactly) ─────────────────────
    private let kScreenShareChannel = "com.example.flutter_education_app/screen_share"
    private let kRecEventChannel    = "com.example.flutter_education_app/rec_events"

    // ── EventChannel sink ─────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── AVAssetWriter state ───────────────────────────────────────────────────
    private var assetWriter:  AVAssetWriter?
    private var videoInput:   AVAssetWriterInput?
    private var audioInput:   AVAssetWriterInput?

    // ── Session params (stored by startMicRecording, used by startScreenCaptureService)
    private var sessionId:  Int    = 0
    private var uploadUrl:  String = ""
    private var authToken:  String = ""
    private var chunkSecs:  Int    = 5

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:  Int   = 0
    private var chunkTimer:  Timer?
    private var currentFile: URL?
    private var recording    = false
    private var paused       = false
    private var stopping     = false

    // ── App lifecycle ─────────────────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        setupChannels(registry: engineBridge.pluginRegistry)
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }

    // ── Channel setup ─────────────────────────────────────────────────────────

    private func setupChannels(registry: FlutterPluginRegistry) {
        let messenger: FlutterBinaryMessenger
        if let registrar = registry.registrar(forPlugin: "NativeRecorder"),
           let m = (registrar as? FlutterPluginRegistrar)?.messenger() {
            messenger = m
        } else if let vc = window?.rootViewController as? FlutterViewController {
            messenger = vc.binaryMessenger
        } else {
            return
        }
        registerScreenShareChannel(messenger: messenger)
        registerEventChannel(messenger: messenger)
    }

    // ── screen_share MethodChannel ────────────────────────────────────────────

    private func registerScreenShareChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: kScreenShareChannel, binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {

            // ── Phase 1: store session params (mic-only phase on Android).
            //    On iOS we just save the params; RPScreenRecorder starts in Phase 2.
            case "startMicRecording":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                    return
                }
                self.sessionId = args["sessionId"]    as? Int    ?? 0
                self.uploadUrl = args["uploadUrl"]    as? String ?? ""
                self.authToken = args["authToken"]    as? String ?? ""
                self.chunkSecs = args["chunkSeconds"] as? Int    ?? 5
                self.chunkIndex = args["chunkIndex"]  as? Int    ?? 0
                NSLog("[REC] startMicRecording: session=\(self.sessionId) chunkSecs=\(self.chunkSecs)")
                result(true)

            // ── Phase 2: show permission dialog, start RPScreenRecorder, begin chunk loop.
            //    Mirrors Android's onActivityResult(1001) → ACTION_STORE_PROJECTION.
            case "startScreenCaptureService":
                // Guard: skip if projection is already granted (recording active).
                guard !self.recording else {
                    NSLog("[REC] startScreenCaptureService: already recording — skipping")
                    result(nil)
                    return
                }
                guard !self.uploadUrl.isEmpty else {
                    self.emitError("uploadUrl not set — call startMicRecording first")
                    result(FlutterError(code: "NOT_CONFIGURED", message: "Call startMicRecording first", details: nil))
                    return
                }
                self.startScreenCaptureService(result: result)

            // ── Phase 3: flutter_webrtc screen-share grant.
            //    On Android this fires a second system dialog (grant 1002) and promotes
            //    the FGS type.  On iOS RPScreenRecorder already captures everything, so
            //    we simply acknowledge and re-emit "screenLoopStarted" so Dart's
            //    _screenLoopCompleter resolves.
            case "upgradeToScreenRecording":
                guard self.recording else {
                    NSLog("[REC] upgradeToScreenRecording: service not running")
                    result(false)
                    return
                }
                // Re-emit so Dart's completer in upgradeToScreenRecording() resolves.
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)

            // ── Acknowledge that share is about to start (clean chunk boundary).
            //    Mirrors ACTION_DOWNGRADE_TO_MIC_FOR_SHARE → emits "micReadyForShare".
            case "downgradeToMicForShare":
                NSLog("[REC] downgradeToMicForShare")
                self.emitEvent(["event": "micReadyForShare"])
                result(nil)

            // ── Acknowledge that share has ended.
            //    Mirrors ACTION_DOWNGRADE_TO_MIC → emits "micLoopStarted".
            case "stopScreenCapture":
                NSLog("[REC] stopScreenCapture")
                self.emitEvent(["event": "micLoopStarted"])
                result(nil)

            // ── No-op: unblocks any Dart waiter on onFgsPromoted.
            case "promoteForShare":
                NSLog("[REC] promoteForShare (no-op on iOS)")
                result(nil)

            // ── Returns current chunk index (mirrors getChunkIndex on Android).
            case "getChunkIndex":
                result(self.chunkIndex)

            // ── Pause: finish current chunk, upload it (isFinal=false), park loop.
            case "pauseRecording":
                self.pauseRecording(result: result)

            // ── Resume: restart chunk loop from next index.
            case "resumeRecording":
                self.resumeRecording(result: result)

            // ── Stop recording entirely.
            case "stopRecording":
                let isFinal = (call.arguments as? [String: Any])?["isFinal"] as? Bool ?? true
                self.stopRecording(isFinal: isFinal, result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // ── EventChannel ──────────────────────────────────────────────────────────

    private func registerEventChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterEventChannel(name: kRecEventChannel, binaryMessenger: messenger)
        ch.setStreamHandler(RecEventStreamHandler { [weak self] sink in
            self?.eventSink = sink
        } onCancel: { [weak self] in
            self?.eventSink = nil
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Phase 2: Start screen capture service
    // ─────────────────────────────────────────────────────────────────────────

    private func startScreenCaptureService(result: @escaping FlutterResult) {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard granted else {
                    result(FlutterError(code: "NO_MIC", message: "Microphone permission denied", details: nil))
                    return
                }
                self.recording  = false  // reset so beginNextChunk guard passes
                self.paused     = false
                self.stopping   = false
                // Clean up stale temp files from previous sessions.
                self.sweepStaleChunks()
                self.beginNextChunk()
                result(nil)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk loop
    // ─────────────────────────────────────────────────────────────────────────

    private func beginNextChunk() {
        guard !stopping else { return }

        let fileName = String(format: "rec_chunk_%06d.mp4", chunkIndex)
        let fileURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        currentFile = fileURL

        // Set up AVAssetWriter for this chunk.
        guard let writer = try? AVAssetWriter(outputURL: fileURL, fileType: .mp4) else {
            emitError("AVAssetWriter init failed for chunk #\(chunkIndex)")
            return
        }
        assetWriter = writer

        let scale = UIScreen.main.scale
        let w = UIScreen.main.bounds.width  * scale
        let h = UIScreen.main.bounds.height * scale

        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:      8_000_000,  // matches Android VIDEO_BPS
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey:        AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vi.expectsMediaDataInRealTime = true
        videoInput = vi

        let aSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey:   192_000,             // matches Android AUDIO_BPS
        ]
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        ai.expectsMediaDataInRealTime = true
        audioInput = ai

        writer.add(vi)
        writer.add(ai)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Start RPScreenRecorder on the very first chunk only; keep it running
        // across chunk boundaries (mirrors Android VirtualDisplay surface-swap).
        let rp = RPScreenRecorder.shared()
        if !rp.isRecording {
            rp.isMicrophoneEnabled = true
            rp.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
                guard let self = self, self.recording, !self.stopping else { return }
                if let e = error { self.emitError(e.localizedDescription); return }
                self.processSample(sampleBuffer, type: bufferType)
            }) { [weak self] error in
                if let e = error {
                    self?.emitError("RPScreenRecorder start: \(e.localizedDescription)")
                }
            }
        }

        recording = true
        paused    = false

        // Emit "screenLoopStarted" once RPScreenRecorder is capturing.
        // (Mirrors Android's emitScreenLoopStarted() called from recordLoop().)
        emitEvent(["event": "screenLoopStarted"])
        NSLog("[REC] beginNextChunk: chunk #\(chunkIndex) started")

        // Schedule automatic chunk rotation.
        scheduleChunkTimer()
    }

    private func scheduleChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: Double(chunkSecs), repeats: false) { [weak self] _ in
            self?.rotateChunk()
        }
    }

    private func rotateChunk() {
        guard recording, !stopping, !paused else { return }
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self, self.recording, !self.stopping, !self.paused else { return }
            self.chunkIndex += 1
            self.beginNextChunk()
        }
    }

    private func processSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard let writer = assetWriter, writer.status == .writing else { return }
        switch type {
        case .video:
            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }
        case .audioMic, .audioApp:
            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Pause / Resume  (mirrors Android ACTION_PAUSE/RESUME_RECORDING)
    // ─────────────────────────────────────────────────────────────────────────

    private func pauseRecording(result: @escaping FlutterResult) {
        guard recording, !stopping else {
            NSLog("[REC] pauseRecording: not recording — ignored")
            result(nil)
            return
        }
        guard !paused else {
            NSLog("[REC] pauseRecording: already paused — ignored")
            result(nil)
            return
        }
        NSLog("[REC] pauseRecording: finishing current chunk then parking")

        // Stop the timer so no automatic rotation fires.
        chunkTimer?.invalidate()
        chunkTimer = nil
        paused = true

        // Finish the in-progress chunk (isFinal=false), then park.
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self else { return }
            self.chunkIndex += 1
            // Release the current writer so a new one can start on resume.
            self.assetWriter = nil
            self.videoInput  = nil
            self.audioInput  = nil
            self.emitEvent(["event": "recordingPaused"])
            NSLog("[REC] recordingPaused at chunk #\(self.chunkIndex)")
            result(nil)
        }
    }

    private func resumeRecording(result: @escaping FlutterResult) {
        guard recording, paused, !stopping else {
            NSLog("[REC] resumeRecording: not in a pauseable state — ignored")
            result(nil)
            return
        }
        NSLog("[REC] resumeRecording: restarting chunk loop at chunk #\(chunkIndex)")
        paused = false
        // Start a fresh AVAssetWriter for the resumed segment.
        beginNextChunk()
        emitEvent(["event": "recordingResumed"])
        result(nil)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Stop recording  (mirrors Android ACTION_STOP)
    // ─────────────────────────────────────────────────────────────────────────

    private func stopRecording(isFinal: Bool, result: @escaping FlutterResult) {
        guard recording else { result(nil); return }
        NSLog("[REC] stopRecording: isFinal=\(isFinal)")
        stopping = true
        recording = false
        chunkTimer?.invalidate()
        chunkTimer = nil

        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error {
                NSLog("[REC] RPScreenRecorder stop error: \(e.localizedDescription)")
            }
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
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { completion(); return }
            DispatchQueue.global(qos: .utility).async {
                self.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal)
                DispatchQueue.main.async { completion() }
            }
        }
    }

    /// Retry-aware upload — mirrors Android's uploadChunkAsync (3 retries, exp back-off).
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
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let fname = String(format: "chunk_%06d.mp4", index)
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
                NSLog("[REC] chunk #\(index) attempt \(attempt + 1) failed: \(reason)")
                if attempt < 3 {
                    let delay = Double(1 << (attempt + 1))
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index, isFinal: isFinal, attempt: attempt + 1)
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.emitError("chunk #\(index) upload permanently failed after 3 retries: \(reason)")
                }
                return
            }
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try? FileManager.default.removeItem(at: fileURL)
            NSLog("[REC] chunk #\(index) uploaded OK (\(size)B isFinal=\(isFinal))")
            DispatchQueue.main.async {
                self.emitEvent([
                    "event":      "chunkUploaded",
                    "chunkIndex": index,
                    "bytes":      size,
                    "isFinal":    isFinal,
                ])
            }
        }.resume()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────────────────────────────────────

    /// Emit a success event on the EventChannel (must be called on main thread).
    private func emitEvent(_ payload: [String: Any]) {
        DispatchQueue.main.async { self.eventSink?(payload) }
    }

    /// Emit an error event on the EventChannel (must be called on main thread).
    private func emitError(_ msg: String) {
        NSLog("[REC] emitError: \(msg)")
        DispatchQueue.main.async {
            self.eventSink?(FlutterError(code: "REC_ERROR", message: msg, details: nil))
        }
    }

    /// Remove temp chunk files from previous sessions to avoid storage build-up.
    private func sweepStaleChunks() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil
        ) else { return }
        for url in items where url.lastPathComponent.hasPrefix("rec_chunk_") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// ── Simple StreamHandler helper ───────────────────────────────────────────────
private class RecEventStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    private let onCancel: () -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void, onCancel: @escaping () -> Void) {
        self.onListen = onListen; self.onCancel = onCancel
    }
    func onListen(withArguments args: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        onListen(eventSink); return nil
    }
    func onCancel(withArguments args: Any?) -> FlutterError? {
        onCancel(); return nil
    }
}