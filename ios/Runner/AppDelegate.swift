import Flutter
import UIKit
import Firebase
import ReplayKit
import AVFoundation

// ─────────────────────────────────────────────────────────────────────────────
// AppDelegate
// ─────────────────────────────────────────────────────────────────────────────
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    // ── Channels ──────────────────────────────────────────────────────────────
    private let kRecorderChannel  = "com.example.flutter_education_app/native_recorder"
    private let kRecEventChannel  = "com.example.flutter_education_app/rec_events"

    // ── Recorder state ────────────────────────────────────────────────────────
    private var eventSink:   FlutterEventSink?
    private var assetWriter: AVAssetWriter?
    private var videoInput:  AVAssetWriterInput?
    private var audioInput:  AVAssetWriterInput?

    private var sessionId:   Int    = 0
    private var uploadUrl:   String = ""
    private var authToken:   String = ""
    private var chunkSecs:   Int    = 30
    private var chunkIndex:  Int    = 0
    private var chunkTimer:  Timer?
    private var currentFile: URL?
    private var recording    = false

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
        guard let registrar = registry.registrar(forPlugin: "NativeRecorder"),
              let messenger = (registrar as? FlutterPluginRegistrar)?.messenger() else {
            // Fallback: grab messenger from the main FlutterViewController
            guard let vc = window?.rootViewController as? FlutterViewController else { return }
            let m = vc.binaryMessenger
            registerMethodChannel(messenger: m)
            registerEventChannel(messenger: m)
            return
        }
        registerMethodChannel(messenger: messenger)
        registerEventChannel(messenger: messenger)
    }

    private func registerMethodChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: kRecorderChannel, binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            switch call.method {
            case "startRecording":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                    return
                }
                self.sessionId  = args["sessionId"]    as? Int    ?? 0
                self.uploadUrl  = args["uploadUrl"]    as? String ?? ""
                self.authToken  = args["authToken"]    as? String ?? ""
                self.chunkSecs  = args["chunkSeconds"] as? Int    ?? 30
                self.startRecording(result: result)
            case "stopRecording":
                self.stopRecording(result: result)
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

    // ── Start recording ───────────────────────────────────────────────────────

    private func startRecording(result: @escaping FlutterResult) {
        guard !recording else {
            result(FlutterError(code: "BUSY", message: "Already recording", details: nil))
            return
        }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else {
                    result(FlutterError(code: "NO_MIC", message: "Microphone permission denied", details: nil))
                    return
                }
                self.chunkIndex = 0
                self.recording  = true
                self.beginNextChunk()
                result(true)
            }
        }
    }

    // ── Chunk management ──────────────────────────────────────────────────────

    private func beginNextChunk() {
        guard recording else { return }

        let fileName = String(format: "rec_chunk_%06d.mp4", chunkIndex)
        let fileURL  = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
        currentFile  = fileURL

        // Set up AVAssetWriter
        guard let writer = try? AVAssetWriter(outputURL: fileURL, fileType: .mp4) else {
            emitError("AVAssetWriter init failed"); return
        }
        assetWriter = writer

        // Video: RPScreenRecorder delivers CVPixelBuffers at native resolution
        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  UIScreen.main.bounds.width  * UIScreen.main.scale,
            AVVideoHeightKey: UIScreen.main.bounds.height * UIScreen.main.scale,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:       4_000_000,
                AVVideoMaxKeyFrameIntervalKey:  60,
                AVVideoProfileLevelKey:         AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vi.expectsMediaDataInRealTime = true
        videoInput = vi

        // Audio: mic + app audio mixed by ReplayKit
        let aSettings: [String: Any] = [
            AVFormatIDKey:            kAudioFormatMPEG4AAC,
            AVSampleRateKey:          44100,
            AVNumberOfChannelsKey:    2,
            AVEncoderBitRateKey:      192_000,
        ]
        let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
        ai.expectsMediaDataInRealTime = true
        audioInput = ai

        writer.add(vi)
        writer.add(ai)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Start/continue RPScreenRecorder
        let rp = RPScreenRecorder.shared()
        if !rp.isRecording {
            rp.isMicrophoneEnabled = true
            rp.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
                guard let self = self, self.recording else { return }
                if let e = error { self.emitError(e.localizedDescription); return }
                self.processSample(sampleBuffer, type: bufferType)
            }) { [weak self] error in
                if let e = error {
                    self?.emitError("RPScreenRecorder start: \(e.localizedDescription)")
                }
            }
        }

        // Schedule chunk rotation
        chunkTimer?.invalidate()
        chunkTimer = Timer.scheduledTimer(withTimeInterval: Double(chunkSecs), repeats: false) { [weak self] _ in
            self?.rotateChunk()
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

    private func rotateChunk() {
        guard recording else { return }
        finaliseChunk(isFinal: false) { [weak self] in
            guard let self = self, self.recording else { return }
            self.chunkIndex += 1
            self.beginNextChunk()
        }
    }

    // ── Stop recording ────────────────────────────────────────────────────────

    private func stopRecording(result: @escaping FlutterResult) {
        guard recording else { result(nil); return }
        recording = false
        chunkTimer?.invalidate()
        chunkTimer = nil

        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error {
                NSLog("[REC] RPScreenRecorder stop error: \(e.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.finaliseChunk(isFinal: true) { result(nil) }
            }
        }
    }

    private func finaliseChunk(isFinal: Bool, completion: @escaping () -> Void) {
        guard let writer = assetWriter, let fileURL = currentFile else {
            completion(); return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            guard let self = self else { completion(); return }
            let idx = self.chunkIndex
            DispatchQueue.global(qos: .utility).async {
                self.uploadChunk(fileURL: fileURL, index: idx, isFinal: isFinal)
                DispatchQueue.main.async { completion() }
            }
        }
    }

    // ── Upload ────────────────────────────────────────────────────────────────

    private func uploadChunk(fileURL: URL, index: Int, isFinal: Bool, attempt: Int = 0) {
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
        appendField("is_final",    "\(isFinal)")
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
                NSLog("[REC] chunk #\(index) upload attempt \(attempt + 1) failed: \(error?.localizedDescription ?? "HTTP \(code)")")
                if attempt < 3 {
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(1 << (attempt + 1))) {
                        self.uploadChunk(fileURL: fileURL, index: index, isFinal: isFinal, attempt: attempt + 1)
                    }
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                    self.emitError("chunk #\(index) upload permanently failed")
                }
                return
            }
            try? FileManager.default.removeItem(at: fileURL)
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            DispatchQueue.main.async {
                self.eventSink?(["event": "chunkUploaded", "chunkIndex": index,
                                 "bytes": size, "isFinal": isFinal])
            }
        }.resume()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func emitError(_ msg: String) {
        DispatchQueue.main.async {
            self.eventSink?(FlutterError(code: "REC_ERROR", message: msg, details: nil))
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