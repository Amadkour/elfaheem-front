// AppDelegate.swift
//
// Recording architecture — two-phase:
//
//   Phase 1 · startMicRecording (called on room connect)
//     ▸ Configures session params (uploadUrl, authToken, chunkSecs)
//     ▸ Returns immediately (result: true)
//     ▸ Does NOT start RPScreenRecorder yet — no dialog, no red pill
//     ▸ Emits nothing — Dart will call startScreenCaptureService next
//
//   Phase 2 · startScreenCaptureService (called right after Phase 1)
//     ▸ Calls RPScreenRecorder.startCapture(...)
//     ▸ iOS shows the microphone-permission dialog HERE (first use only)
//       and the red-pill indicator — this is expected and correct
//     ▸ On success: begins AVAssetWriter chunk loop, emits "screenLoopStarted"
//     ▸ Chunks are full MP4 (H.264 video + AAC audio) — no black screen
//
//   Screen share (separate concern):
//     ▸ showBroadcastPicker → RPSystemBroadcastPickerView for LiveKit share
//     ▸ Recording continues uninterrupted (RPScreenRecorder keeps running)
//     ▸ SampleHandler sends frames to LiveKit via CFMessagePort IPC
//
// WHY NOT AVAudioEngine:
//   AVAudioEngine captures mic audio only — produces audio-only .caf files
//   with no video track, causing the black-screen symptom. RPScreenRecorder
//   is the correct iOS API for screen+audio recording.
//
// PERMISSION TIMING:
//   The microphone permission dialog appears the FIRST TIME startCapture()
//   is called. On subsequent launches it does not appear. The red-pill
//   "screen recording" indicator appears whenever RPScreenRecorder is
//   actively capturing — this is an iOS system requirement and cannot be
//   suppressed for recording. For screen-share-only (not recording), the
//   broadcast extension approach avoids the red pill.

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

    // ── AVAssetWriter (one per chunk) ─────────────────────────────────────────
    private var assetWriter: AVAssetWriter?
    private var videoInput:  AVAssetWriterInput?
    private var audioInput:  AVAssetWriterInput?

    // ── Session params (set by startMicRecording, used by startScreenCaptureService) ──
    private var sessionId: Int    = 0
    private var uploadUrl: String = ""
    private var authToken: String = ""
    private var chunkSecs: Int    = 5

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:  Int   = 0
    private var chunkTimer:  Timer?
    private var currentFile: URL?
    private var recording    = false   // true while RPScreenRecorder is capturing
    private var paused       = false
    private var stopping     = false

    // ── First video sample flag ───────────────────────────────────────────────
    // RPScreenRecorder may deliver a few audio samples before the first video
    // frame. We must not start the AVAssetWriter session until we have a valid
    // video timestamp, otherwise the writer fails with "sample out of order".
    private var writerSessionStarted = false
    private var firstVideoTimestamp: CMTime = .invalid

    // ── iOS Broadcast Extension IPC ───────────────────────────────────────────
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
                // Phase 2: start RPScreenRecorder.
                // Called from room.dart immediately after the room connects
                // and startMicRecording has configured session params.
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

            case "showBroadcastPicker":
                // Called when teacher taps "Share Screen".
                // RPScreenRecorder keeps recording; we just open the
                // broadcast picker for the LiveKit screen-share stream.
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
                // Phase 1: store session params. No RPScreenRecorder yet.
                // Returns immediately so room.dart can proceed to show the
                // room UI and then call startScreenCaptureService.
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(code: "BAD_ARGS", message: "Expected map", details: nil))
                    return
                }
                self.sessionId  = args["sessionId"]    as? Int    ?? 0
                self.uploadUrl  = args["uploadUrl"]    as? String ?? ""
                self.authToken  = args["authToken"]    as? String ?? ""
                self.chunkSecs  = args["chunkSeconds"] as? Int    ?? 5
                self.chunkIndex = args["chunkIndex"]   as? Int    ?? 0
                NSLog("[REC] startMicRecording: session=\(self.sessionId) configured — waiting for startScreenCaptureService")
                // Emit screenLoopStarted immediately so Dart's _startRecording()
                // completer resolves without waiting for Phase 2.
                // The actual recording loop starts in startScreenCaptureService.
                self.emitEvent(["event": "screenLoopStarted"])
                result(true)

            case "upgradeToScreenRecording":
                // Called from room.dart after startScreenCaptureService returns.
                // On iOS, recording is already running at this point.
                if self.recording {
                    self.emitEvent(["event": "screenLoopStarted"])
                    result(true)
                } else {
                    // startScreenCaptureService not done yet — emit when it finishes.
                    // Safe: room.dart waits on the event, not this return value.
                    result(true)
                }

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
    // MARK: - Phase 2: RPScreenRecorder capture
    //
    // This is the correct iOS API for recording screen + mic audio together
    // into a proper MP4 with both video and audio tracks.
    //
    // The system microphone permission dialog (if not yet granted) and the
    // red-pill recording indicator appear here — this is iOS-enforced and
    // cannot be avoided when using RPScreenRecorder. The dialog is shown
    // at the right time: after the room is connected and the teacher is
    // already in the session, not at app launch.
    // ─────────────────────────────────────────────────────────────────────────

    private func startScreenCaptureService(result: @escaping FlutterResult) {
        configureAudioSessionForRecording()

        let rp = RPScreenRecorder.shared()
        guard rp.isAvailable else {
            result(FlutterError(code: "RP_UNAVAILABLE",
                                message: "RPScreenRecorder not available", details: nil))
            return
        }

        paused               = false
        stopping             = false
        writerSessionStarted = false
        firstVideoTimestamp  = .invalid
        sweepStaleChunks()

        // Enable mic capture. The iOS permission dialog appears here on
        // first call if mic permission has not been granted before.
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
                // Re-emit screenLoopStarted now that the capture loop is
                // actually running. The Dart side may already have resolved
                // its completer from the Phase 1 emit; emitting again is safe
                // and ensures upgradeToScreenRecording() also gets it.
                self.emitEvent(["event": "screenLoopStarted"])
                NSLog("[REC] RPScreenRecorder capture started — chunk #\(self.chunkIndex)")
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
            // .playAndRecord with .mixWithOthers lets LiveKit's audio and
            // RPScreenRecorder's mic capture coexist without session conflicts.
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
    // MARK: - Chunk writer (AVAssetWriter — H.264 video + AAC audio)
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

        // ── Video settings ────────────────────────────────────────────────────
        // Use screen native resolution scaled to a sensible recording size.
        // 720p is a good balance between quality and file size for education.
        let scale   = UIScreen.main.scale
        let nativeW = Int(UIScreen.main.bounds.width  * scale)
        let nativeH = Int(UIScreen.main.bounds.height * scale)
        // Clamp to 720p max (1280 on the shorter side) to avoid huge files.
        let maxShort = 720
        let shortSide = min(nativeW, nativeH)
        let ratio  = shortSide > maxShort ? CGFloat(maxShort) / CGFloat(shortSide) : 1.0
        let recW   = Int(CGFloat(nativeW) * ratio) & ~1  // must be even for H.264
        let recH   = Int(CGFloat(nativeH) * ratio) & ~1

        let vSettings: [String: Any] = [
            AVVideoCodecKey:  AVVideoCodecType.h264,
            AVVideoWidthKey:  recW,
            AVVideoHeightKey: recH,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:      4_000_000,   // 4 Mbps — clear screen content
                AVVideoMaxKeyFrameIntervalKey: 60,
                AVVideoProfileLevelKey:        AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,      // low-latency encoding
            ],
        ]
        let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vi.expectsMediaDataInRealTime = true
        videoInput = vi

        // ── Audio settings ────────────────────────────────────────────────────
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
        // IMPORTANT: do NOT call startSession(atSourceTime:) here.
        // We start the session on the FIRST video sample so the timestamp
        // is correct. Starting at .zero causes "sample out of order" failures
        // when the first real video frame has a non-zero PTS.
        writerSessionStarted = false
        firstVideoTimestamp  = .invalid

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) \(recW)×\(recH)")
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
    // MARK: - Sample processing
    //
    // RPScreenRecorder delivers three buffer types:
    //   .video    — CVPixelBuffer frames (the actual screen content)
    //   .audioMic — PCM audio from the device microphone
    //   .audioApp — PCM audio from apps (system sounds, etc.)
    //
    // We write video frames to the video track and mic audio to the audio
    // track. App audio is mixed in as well for a complete recording.
    //
    // CRITICAL: the AVAssetWriter session must be started with the PTS of
    // the FIRST VIDEO FRAME. Audio samples before that PTS are dropped.
    // Starting at .zero causes the writer to fail silently (black video).
    // ─────────────────────────────────────────────────────────────────────────

    private func processSample(_ sampleBuffer: CMSampleBuffer, type: RPSampleBufferType) {
        guard CMSampleBufferIsValid(sampleBuffer),
              let writer = assetWriter,
              writer.status == .writing else { return }

        switch type {
        case .video:
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard CMTIME_IS_VALID(pts) else { return }

            if !writerSessionStarted {
                // Start the session on the very first video frame.
                // This anchors the timeline correctly so video and audio are in sync.
                writer.startSession(atSourceTime: pts)
                firstVideoTimestamp  = pts
                writerSessionStarted = true
                NSLog("[REC] writer session started at PTS \(CMTimeGetSeconds(pts))s")
            }

            if videoInput?.isReadyForMoreMediaData == true {
                videoInput?.append(sampleBuffer)
            }

        case .audioMic, .audioApp:
            // Drop audio samples that arrive before the first video frame —
            // they would be out-of-order relative to the session start time.
            guard writerSessionStarted else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard CMTIME_IS_VALID(pts),
                  CMTimeCompare(pts, firstVideoTimestamp) >= 0 else { return }

            if audioInput?.isReadyForMoreMediaData == true {
                audioInput?.append(sampleBuffer)
            }

        @unknown default:
            break
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
            self.writerSessionStarted = false
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
        writerSessionStarted = false
        firstVideoTimestamp  = .invalid
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
                NSLog("[REC] writer failed chunk #\(idx): \(writer.error?.localizedDescription ?? "unknown")")
                // Still call completion so the chunk loop continues.
                DispatchQueue.main.async { completion() }
                return
            }

            // Verify the file is non-empty before uploading.
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size < 1024 {
                NSLog("[REC] chunk #\(idx) suspiciously small (\(size)B) — dropping")
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

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - iOS Broadcast Extension share (showBroadcastPicker)
    //
    // Completely separate from the recording pipeline.
    // RPScreenRecorder continues its chunk recording uninterrupted while
    // the broadcast extension streams to LiveKit participants.
    // ─────────────────────────────────────────────────────────────────────────

    private func showBroadcastPicker(result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { result(nil); return }

            self.registerBroadcastPort()

            let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
            let bundleId = Bundle.main.bundleIdentifier ?? ""
            picker.preferredExtension = "\(bundleId).BroadcastUploadExtension"
            picker.showsMicrophoneButton = false

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