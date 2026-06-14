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

    // ── Flutter engine ────────────────────────────────────────────────────────
    private var flutterEngine: FlutterEngine?

    // ── AVAssetWriter — mic-only writer (Phase 1) ─────────────────────────────
    // On iOS we record mic audio via AVAudioEngine instead of RPScreenRecorder
    // so the red-pill "recording" indicator never appears during normal teaching.
    // RPScreenRecorder is only used when the teacher taps "Share Screen".
    private var audioEngine:   AVAudioEngine?
    private var audioFile:     AVAudioFile?

    // ── AVAssetWriter — full MP4 writer (used when RPScreenRecorder is active) ──
    private var assetWriter: AVAssetWriter?
    private var videoInput:  AVAssetWriterInput?
    private var audioInput:  AVAssetWriterInput?

    // ── Session params ────────────────────────────────────────────────────────
    private var sessionId:  Int    = 0
    private var uploadUrl:  String = ""
    private var authToken:  String = ""
    private var chunkSecs:  Int    = 5

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:  Int   = 0
    private var chunkTimer:  Timer?
    private var currentFile: URL?
    private var recording    = false   // true while mic-only audio engine is running
    private var screenActive = false   // true while RPScreenRecorder is active
    private var paused       = false
    private var stopping     = false

    // ── Mic-only chunk state ──────────────────────────────────────────────────
    private var micChunkTimer: Timer?
    private var micChunkIndex: Int = 0
    private var micCurrentFile: URL?

    // ── iOS Broadcast Extension share state ───────────────────────────────────
    private let kBroadcastPortName = "com.example.flutter_education_app.broadcast"
    private var broadcastPort: CFMessagePort?
    private var isBroadcasting = false

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
                // On iOS this is a no-op — mic recording already started in
                // startMicRecording. Screen capture starts only on showBroadcastPicker.
                NSLog("[REC] startScreenCaptureService: iOS mic-only mode — no-op")
                result(true)

            case "stopScreenCaptureService":
                result(nil)

            case "showBroadcastPicker":
                // Teacher tapped "Share Screen" — start RPSystemBroadcastPickerView.
                // Mic-only recording continues uninterrupted in the background.
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
                // ── Phase 1: start mic-only audio recording ───────────────────
                // This is called immediately when the room connects.
                // NO red pill, NO system dialog — just silent AVAudioEngine recording.
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

                // Start mic-only recording via AVAudioEngine (no red pill).
                self.startMicOnlyRecording { success in
                    if success {
                        // Emit screenLoopStarted so Dart's completer resolves.
                        self.emitEvent(["event": "screenLoopStarted"])
                        result(true)
                    } else {
                        result(FlutterError(code: "MIC_START_FAILED",
                                            message: "AVAudioEngine failed to start", details: nil))
                    }
                }

            case "upgradeToScreenRecording":
                // Screen share is active — re-confirm recording is live.
                // On iOS the mic-only recorder is still running; we just acknowledge.
                NSLog("[REC] upgradeToScreenRecording: iOS — mic-only recording confirmed")
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
                self.pauseMicRecording(result: result)

            case "resumeRecording":
                self.resumeMicRecording(result: result)

            case "stopRecording":
                let isFinal = (call.arguments as? [String: Any])?["isFinal"] as? Bool ?? true
                self.stopMicRecording(isFinal: isFinal, result: result)

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
    // MARK: - Phase 1: Mic-only recording via AVAudioEngine
    //
    // Uses AVAudioEngine to tap the microphone input and write raw AAC chunks.
    // This produces ZERO system UI — no red pill, no permission dialog (the
    // microphone permission was already requested by Flutter's permission_handler
    // before this is called).
    //
    // Each chunk is a self-contained M4A file uploaded to the backend.
    // ─────────────────────────────────────────────────────────────────────────

    private func startMicOnlyRecording(completion: @escaping (Bool) -> Void) {
        // Configure the audio session for recording BEFORE starting the engine.
        // Use .record category so LiveKit's playAndRecord doesn't fight us.
        // We restore it after mic recording stops.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth,
                                              .allowBluetoothA2DP, .mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            NSLog("[REC] AVAudioSession config error: \(error.localizedDescription)")
            completion(false)
            return
        }

        stopAudioEngine() // clean up any previous instance

        let engine  = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let inputFmt  = inputNode.outputFormat(forBus: 0)

        guard inputFmt.sampleRate > 0 else {
            NSLog("[REC] AVAudioEngine: invalid input format — mic permission may be missing")
            completion(false)
            return
        }

        micChunkIndex = chunkIndex
        recording     = true
        paused        = false
        stopping      = false
        sweepStaleChunks()

        // Open the first chunk file.
        guard openMicChunkFile(index: micChunkIndex, format: inputFmt) else {
            completion(false)
            return
        }

        // Install a tap on the input node to write PCM frames.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFmt) { [weak self] buffer, _ in
            guard let self = self, self.recording, !self.stopping, !self.paused else { return }
            do {
                try self.audioFile?.write(from: buffer)
            } catch {
                NSLog("[REC] audioFile write error: \(error.localizedDescription)")
            }
        }

        do {
            try engine.start()
        } catch {
            NSLog("[REC] AVAudioEngine start error: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            audioEngine = nil
            completion(false)
            return
        }

        NSLog("[REC] AVAudioEngine started — mic-only recording at chunk #\(micChunkIndex)")
        scheduleMicChunkTimer(format: inputFmt)
        completion(true)
    }

    private func openMicChunkFile(index: Int, format: AVAudioFormat) -> Bool {
        let fileName = String(format: "mic_chunk_%06d.caf", index)
        let fileURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        micCurrentFile = fileURL
        do {
            // Write as Core Audio Format (CAF) — AVAudioFile handles the container.
            // We convert to AAC in uploadMicChunk for server compatibility.
            audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            return true
        } catch {
            NSLog("[REC] openMicChunkFile failed: \(error.localizedDescription)")
            return false
        }
    }

    private func scheduleMicChunkTimer(format: AVAudioFormat) {
        micChunkTimer?.invalidate()
        micChunkTimer = Timer.scheduledTimer(withTimeInterval: Double(chunkSecs),
                                             repeats: false) { [weak self] _ in
            self?.rotateMicChunk(format: format)
        }
    }

    private func rotateMicChunk(format: AVAudioFormat) {
        guard recording, !stopping, !paused else { return }
        let idx      = micChunkIndex
        let fileURL  = micCurrentFile
        micChunkIndex += 1
        chunkIndex    = micChunkIndex // keep global index in sync

        guard openMicChunkFile(index: micChunkIndex, format: format) else { return }
        scheduleMicChunkTimer(format: format)

        // Upload the just-finished chunk in the background.
        if let url = fileURL {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.uploadChunkAsync(fileURL: url, index: idx, isFinal: false)
            }
        }
    }

    private func pauseMicRecording(result: @escaping FlutterResult) {
        guard recording, !stopping, !paused else { result(nil); return }
        NSLog("[REC] pauseMicRecording at chunk #\(micChunkIndex)")
        micChunkTimer?.invalidate(); micChunkTimer = nil
        paused = true

        let idx     = micChunkIndex
        let fileURL = micCurrentFile
        micChunkIndex += 1
        chunkIndex    = micChunkIndex
        audioFile     = nil // close the current file

        if let url = fileURL {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.uploadChunkAsync(fileURL: url, index: idx, isFinal: false)
                DispatchQueue.main.async {
                    self?.emitEvent(["event": "recordingPaused"])
                    result(nil)
                }
            }
        } else {
            emitEvent(["event": "recordingPaused"])
            result(nil)
        }
    }

    private func resumeMicRecording(result: @escaping FlutterResult) {
        guard recording, paused, !stopping else { result(nil); return }
        NSLog("[REC] resumeMicRecording at chunk #\(micChunkIndex)")
        paused = false

        guard let engine = audioEngine else { result(nil); return }
        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        guard openMicChunkFile(index: micChunkIndex, format: inputFmt) else {
            result(nil); return
        }
        scheduleMicChunkTimer(format: inputFmt)
        emitEvent(["event": "recordingResumed"])
        result(nil)
    }

    private func stopMicRecording(isFinal: Bool, result: @escaping FlutterResult) {
        guard recording else { result(nil); return }
        NSLog("[REC] stopMicRecording: isFinal=\(isFinal)")
        stopping = true; recording = false
        micChunkTimer?.invalidate(); micChunkTimer = nil

        let idx     = micChunkIndex
        let fileURL = micCurrentFile
        audioFile   = nil // close the file before uploading

        stopAudioEngine()
        restoreAudioSessionForLiveKit()

        if let url = fileURL {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.uploadChunkAsync(fileURL: url, index: idx, isFinal: isFinal)
                DispatchQueue.main.async {
                    self?.stopping = false
                    result(nil)
                }
            }
        } else {
            stopping = false
            result(nil)
        }
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile   = nil
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - AVAudioSession helpers
    // ─────────────────────────────────────────────────────────────────────────

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
    // MARK: - Chunk upload
    // ─────────────────────────────────────────────────────────────────────────

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

        // Accept both .caf (mic-only) and .mp4 (screen+audio) chunk files.
        let ext   = fileURL.pathExtension.lowercased()
        let mime  = ext == "mp4" ? "video/mp4" : "audio/x-caf"
        let fname = String(format: "chunk_%06d.\(ext)", index)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
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
        for url in items where url.lastPathComponent.hasPrefix("mic_chunk_")
                                  || url.lastPathComponent.hasPrefix("rec_chunk_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - iOS Broadcast Extension share (showBroadcastPicker)
    //
    // Called ONLY when the teacher taps the "Share Screen" button.
    // The mic-only AVAudioEngine recording continues in parallel — we do NOT
    // stop it. The broadcast extension sends video frames via CFMessagePort
    // which are forwarded to LiveKit. Audio from the broadcast extension is
    // handled separately (the extension captures mic + app audio).
    // ─────────────────────────────────────────────────────────────────────────

    private func showBroadcastPicker(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { result(nil); return }

            // Register the CFMessagePort so the extension can connect
            // the moment broadcastStarted() fires in SampleHandler.
            self.registerBroadcastPort()

            let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            picker.preferredExtension = "\(bundleId).BroadcastUploadExtension"
            picker.showsMicrophoneButton = false // mic is handled by our AVAudioEngine

            // Programmatically trigger the picker button.
            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }

            self.isBroadcasting = true
            NSLog("[SHARE] showBroadcastPicker: picker triggered")
            result(nil)
        }
    }

    private func stopBroadcastShare(result: @escaping FlutterResult) {
        isBroadcasting = false
        invalidateBroadcastPort()
        emitEvent(["event": "broadcastStopped"])
        NSLog("[SHARE] stopBroadcastShare: IPC port closed")
        result(nil)
    }

    // ── CFMessagePort IPC receiver ────────────────────────────────────────────

    private func registerBroadcastPort() {
        invalidateBroadcastPort()

        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )

        broadcastPort = CFMessagePortCreateLocal(
            nil,
            kBroadcastPortName as CFString,
            { _, _, data, info -> Unmanaged<CFData>? in
                guard let info = info else { return nil }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(info).takeUnretainedValue()
                if let data = data { delegate.handleBroadcastData(data as Data) }
                return nil
            },
            &context,
            nil
        )

        if let port = broadcastPort {
            let runLoopSource = CFMessagePortCreateRunLoopSource(nil, port, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            NSLog("[SHARE] CFMessagePort registered: \(kBroadcastPortName)")
        } else {
            NSLog("[SHARE] CFMessagePort registration FAILED")
        }
    }

    private func invalidateBroadcastPort() {
        if let port = broadcastPort {
            CFMessagePortInvalidate(port)
            broadcastPort = nil
        }
    }

    /// Deserialise the wire format from SampleHandler.
    /// Wire: [4B type][8B pts_ns][4B payload_size][payload]
    /// Type 99 = stop signal.
    private func handleBroadcastData(_ data: Data) {
        guard data.count >= 16 else { return }

        let typeId  = data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let ptsNs   = data.dropFirst(4).prefix(8).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let paySize = data.dropFirst(12).prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let payload = data.dropFirst(16).prefix(Int(paySize))

        if typeId == 99 {
            NSLog("[SHARE] Extension broadcast finished")
            isBroadcasting = false
            invalidateBroadcastPort()
            emitEvent(["event": "broadcastStopped"])
            return
        }

        // Forward video frames to Flutter/LiveKit via event channel.
        // Audio (types 1,2) from the extension is captured separately by
        // LiveKit's own audio session handling — we don't relay it here.
        if typeId == 0 {
            let base64 = payload.base64EncodedString()
            emitEvent([
                "event":   "broadcastFrame",
                "type":    Int(typeId),
                "ptsNs":   Int64(bitPattern: ptsNs),
                "payload": base64,
            ])
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