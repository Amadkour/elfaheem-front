import Flutter
import UIKit
import Firebase
import ReplayKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {

    // ── Channel names ─────────────────────────────────────────────────────────
    private let kScreenShareChannel = "com.example.flutter_education_app/screen_share"
    private let kRecorderChannel    = "com.example.flutter_education_app/native_recorder"
    private let kRecEventChannel    = "com.example.flutter_education_app/rec_events"

    // ── EventChannel sink ─────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── Flutter engine (owned here so it outlives the VC) ────────────────────
    private var flutterEngine: FlutterEngine?

    // ── AVAssetWriter (one per chunk) ─────────────────────────────────────────
    private var assetWriter: AVAssetWriter?
    private var videoInput:  AVAssetWriterInput?
    private var audioInput:  AVAssetWriterInput?

    // ── Session params ────────────────────────────────────────────────────────
    private var sessionId: Int    = 0
    private var uploadUrl: String = ""
    private var authToken: String = ""
    private var chunkSecs: Int    = 5

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:  Int   = 0
    private var chunkTimer:  Timer?
    private var currentFile: URL?
    private var recording    = false
    private var paused       = false
    private var stopping     = false

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - App lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()

        // 1. Create and run the Flutter engine explicitly.
        //    This gives us a messenger that is guaranteed ready — no window
        //    lookup needed, no timing race with rootViewController assignment.
        let engine = FlutterEngine(name: "main_engine")
        engine.run()
        flutterEngine = engine

        // 2. Register all Flutter plugins (shared_preferences, etc.) against
        //    this engine BEFORE the FlutterViewController is presented.
        //    This is the correct place — matches what the default AppDelegate
        //    template does when it calls super.application(...).
        GeneratedPluginRegistrant.register(with: engine)

        // 3. Register our custom channels against the same engine messenger.
        //    The messenger is live the moment engine.run() returns.
        registerScreenShareChannel(messenger: engine.binaryMessenger)
        registerRecorderChannel(messenger: engine.binaryMessenger)
        registerEventChannel(messenger: engine.binaryMessenger)

        // 4. Create the root view controller from our running engine and
        //    attach it to the window — exactly as Flutter's template does.
        let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()

        return true
        // Note: we do NOT call super.application(...) here because super's
        // implementation creates its own engine and its own VC, which would
        // conflict with ours. Returning true directly is correct when you
        // own the engine lifecycle yourself.
    }

    override func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
        super.application(application,
                           didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
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
                guard !self.recording else {
                    NSLog("[REC] startScreenCaptureService: already recording — skip")
                    result(true); return
                }
                guard !self.uploadUrl.isEmpty else {
                    result(FlutterError(code: "NOT_CONFIGURED",
                                        message: "Call startMicRecording first", details: nil))
                    return
                }
                self.startScreenCaptureService(result: result)

            case "stopScreenCaptureService":
                result(nil)

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
                // On iOS, RPScreenRecorder is the only recording path.
                // Start capture immediately here so that the subsequent
                // startScreenCaptureService call from Dart is idempotent
                // (caught by the "already recording" guard) and avoids
                // the timing race where startScreenCaptureService fires
                // before uploadUrl is stored.
                guard !self.recording else {
                    result(true); return
                }
                self.startScreenCaptureService(result: result)

            case "upgradeToScreenRecording":
                guard self.recording else {
                    NSLog("[REC] upgradeToScreenRecording: not recording")
                    result(false); return
                }
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)

            case "downgradeToMicForShare":
                NSLog("[REC] downgradeToMicForShare")
                self.emitEvent(["event": "micReadyForShare"])
                result(nil)

            case "stopScreenCapture":
                NSLog("[REC] stopScreenCapture")
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
        ch.setStreamHandler(RecEventStreamHandler { [weak self] sink in
            self?.eventSink = sink
        } onCancel: { [weak self] in
            self?.eventSink = nil
        })
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Phase 2: startScreenCaptureService
    // ─────────────────────────────────────────────────────────────────────────

    private func startScreenCaptureService(result: @escaping FlutterResult) {
        configureAudioSessionForRecording()

        let rp = RPScreenRecorder.shared()
        guard rp.isAvailable else {
            result(FlutterError(code: "RP_UNAVAILABLE",
                                message: "RPScreenRecorder is not available on this device",
                                details: nil))
            return
        }

        paused   = false
        stopping = false
        sweepStaleChunks()
        rp.isMicrophoneEnabled = true

        rp.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self = self, self.recording, !self.stopping else { return }
            if let e = error { self.emitError(e.localizedDescription); return }
            self.processSample(sampleBuffer, type: bufferType)
        }) { [weak self] error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let e = error {
                    NSLog("[REC] RPScreenRecorder startCapture error: \(e.localizedDescription)")
                    result(FlutterError(code: "RP_START_ERROR",
                                        message: e.localizedDescription, details: nil))
                    return
                }
                self.recording = true
                self.beginChunkWriter()
                self.emitEvent(["event": "screenLoopStarted"])
                NSLog("[REC] capture started at chunk #\(self.chunkIndex)")
                result(true)
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - AVAudioSession helpers
    // ─────────────────────────────────────────────────────────────────────────

    private func configureAudioSessionForRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth,
                                              .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[REC] AVAudioSession configured for recording")
        } catch {
            NSLog("[REC] AVAudioSession config error: \(error.localizedDescription)")
        }
    }

    private func restoreAudioSessionForLiveKit() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .videoChat,
                                    options: [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            NSLog("[REC] AVAudioSession restored for LiveKit")
        } catch {
            NSLog("[REC] AVAudioSession restore error: \(error.localizedDescription)")
        }
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

        let scale = UIScreen.main.scale
        let w = Int(UIScreen.main.bounds.width  * scale)
        let h = Int(UIScreen.main.bounds.height * scale)

        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:      8_000_000,
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
            AVEncoderBitRateKey:   192_000,
        ]
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        ai.expectsMediaDataInRealTime = true
        audioInput = ai

        writer.add(vi)
        writer.add(ai)
        writer.startWriting()
        writer.startSession(atSourceTime: CMClockGetTime(CMClockGetHostTimeClock()))

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) ready")
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

    private func processSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard let writer = assetWriter, writer.status == .writing else { return }
        switch type {
        case .video:
            if videoInput?.isReadyForMoreMediaData == true { videoInput?.append(sampleBuffer) }
        case .audioMic, .audioApp:
            if audioInput?.isReadyForMoreMediaData == true { audioInput?.append(sampleBuffer) }
        @unknown default: break
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Pause / Resume
    // ─────────────────────────────────────────────────────────────────────────

    private func pauseRecording(result: @escaping FlutterResult) {
        guard recording, !stopping else {
            NSLog("[REC] pauseRecording: not recording — ignored"); result(nil); return
        }
        guard !paused else {
            NSLog("[REC] pauseRecording: already paused — ignored"); result(nil); return
        }
        NSLog("[REC] pauseRecording: finishing chunk #\(chunkIndex) then parking")
        chunkTimer?.invalidate(); chunkTimer = nil
        paused = true
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self else { return }
            self.chunkIndex += 1
            self.assetWriter = nil; self.videoInput = nil; self.audioInput = nil
            self.emitEvent(["event": "recordingPaused"])
            NSLog("[REC] recordingPaused at chunk #\(self.chunkIndex)")
            result(nil)
        }
    }

    private func resumeRecording(result: @escaping FlutterResult) {
        guard recording, paused, !stopping else {
            NSLog("[REC] resumeRecording: not in pauseable state — ignored")
            result(nil); return
        }
        NSLog("[REC] resumeRecording: restarting at chunk #\(chunkIndex)")
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

        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error { NSLog("[REC] stopCapture error: \(e.localizedDescription)") }
            DispatchQueue.main.async {
                self?.restoreAudioSessionForLiveKit()
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
            if writer.status == .failed {
                NSLog("[REC] writer failed chunk #\(idx): \(writer.error?.localizedDescription ?? "")")
                completion(); return
            }
            DispatchQueue.global(qos: .utility).async {
                self.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal)
                DispatchQueue.main.async { completion() }
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
                NSLog("[REC] chunk #\(index) attempt \(attempt + 1) failed: \(reason)")
                if attempt < 3 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(1 << (attempt + 1))) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index,
                                              isFinal: isFinal, attempt: attempt + 1)
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
        NSLog("[REC] emitError: \(msg)")
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
}

// ── Simple StreamHandler helper ───────────────────────────────────────────────
private class RecEventStreamHandler: NSObject, FlutterStreamHandler {
    private let onListen: (FlutterEventSink?) -> Void
    private let onCancel: () -> Void
    init(onListen: @escaping (FlutterEventSink?) -> Void,
         onCancel: @escaping () -> Void) {
        self.onListen = onListen; self.onCancel = onCancel
    }
    func onListen(withArguments args: Any?,
                  eventSink: @escaping FlutterEventSink) -> FlutterError? {
        onListen(eventSink); return nil
    }
    func onCancel(withArguments args: Any?) -> FlutterError? {
        onCancel(); return nil
    }
}