// SampleHandler.swift
// BroadcastUploadExtension target
//
// UNTESTED (written on Windows, 2026-10-29; nothing here has run on a
// device yet) — see docs/live/ios_test_plan.md before shipping.
//
// What this extension does while the teacher shares the iPhone / iPad screen:
//
//  1. LIVE (audit I1/I3) — every video sample is downscaled and JPEG-encoded
//     (FrameEncoder, ONE CIContext) and sent over the Unix socket
//     <App Group>/rtc_SSFD to flutter_webrtc's FlutterBroadcastScreenCapturer
//     in the app, framed exactly like the reference extension of
//     livekit_client 2.13.1 (SampleUploader.swift). That capturer feeds the
//     LiveKit screen-share track, so viewers see the screen.
//     The app side needs, in Runner/Info.plist,
//       RTCAppGroupIdentifier     = group.com.doubley.nextbrain
//       RTCScreenSharingExtension = com.doubley.nextbrain.BroadcastUploadExtension
//     and the Dart side ScreenShareCaptureOptions(useiOSBroadcastExtension:
//     true) (docs/live/ios_share_wiring.md).
//
//  2. BROADCAST STATE — posts the Darwin notifications livekit_client listens
//     for: iOS_BroadcastStarted when the broadcast starts (LiveKit then
//     publishes the screen-share track) and iOS_BroadcastStopped when it
//     ends (LiveKit unpublishes it; AppDelegate resets the share UI).
//
//  3. STOP FROM THE APP (I2) — observes iOS_BroadcastRequestStop (posted by
//     LiveKit's BroadcastManager().requestStop() and by AppDelegate's
//     "requestBroadcastStop" / "stopBroadcast") and ends the broadcast with
//     finishBroadcastWithError and a readable message. It also ends itself
//     when the app closes the socket (the screen-share track was unpublished,
//     the room was left or the app died), like the reference does.
//
//  4. RECORDING / APP AUDIO IPC (unchanged wire format) — only when the app
//     asks for it through marker files in the App Group (see Wants below):
//       • ext_wants_video_file → each encoded JPEG is also written to
//         <App Group>/broadcast_frame.bin as [4B typeId=0][8B ptsNs][4B size]
//         [JPEG] + Darwin "…nextbrain.frame" (AppDelegate's
//         in-app recorder). The SAME JPEG bytes are used for the socket and
//         the file: one encode per frame, no second copy (I1 trade-off: the
//         recording keeps its existing path without doubling memory).
//       • ext_wants_audio_queue → .audioApp PCM is batched into
//         <App Group>/broadcast_audio_queue/aud_NNNNNNNNNN.bin as
//         [4B typeId=2][8B ptsNs][4B size][4B sampleRate][4B channels]
//         [4B isFloat][interleaved native-endian PCM] + Darwin
//         "…nextbrain.audioframe". AppDelegate uses it for the
//         recording's system-audio track and for mixing the shared app's
//         sound into the live microphone (ShareAppAudioMixer).
//     Without the markers nothing is written, so no audio files pile up in
//     the App Group when nobody drains them (I2).
//
//  The teacher's microphone is NOT captured here (.audioMic is dropped): the
//  live mic is LiveKit's own track, and the recording gets it from the
//  LiveKit audio tap (AppDelegate "sendAudioFrame").
//
//  Memory: see the budget in SampleUploader.swift. At most one ReplayKit
//  video sample is retained (the newest, until the next encode slot) plus
//  the last encoded JPEG (re-sent once a second while the screen is static
//  so a viewer who joins late, or a WebRTC key-frame request, gets a
//  picture).

import ReplayKit
import CoreMedia
import CoreVideo
import CoreAudio
import AudioToolbox
import AVFoundation

private let kAppGroup          = "group.com.doubley.nextbrain"
/// flutter_webrtc: FlutterBroadcastScreenCapturer.m kRTCScreensharingSocketFD.
private let kSocketFileName    = "rtc_SSFD"
private let kFrameFileName     = "broadcast_frame.bin"
// Must match AppDelegate's kAudioQueueDirName exactly.
private let kAudioQueueDirName = "broadcast_audio_queue"
// Width of the zero-padded sequence number in each audio filename
// (e.g. "aud_0000000001.bin"); AppDelegate sorts the names as strings.
private let kAudioSeqPad       = 10
// Marker files written by AppDelegate (updateExtensionWants) — must match.
private let kWantsVideoFile    = "ext_wants_video_file"
private let kWantsAudioQueue   = "ext_wants_audio_queue"
private let kWantsDetail       = "ext_detail_mode"

class SampleHandler: RPBroadcastSampleHandler {

    // ── Live (flutter_webrtc socket) ─────────────────────────────────────
    private var connection: SocketConnection?
    private var uploader: SampleUploader?
    private let encoder = FrameEncoder()
    private var connectTimer: DispatchSourceTimer?
    private var keepAliveTimer: DispatchSourceTimer?
    private let liveLock = NSLock()
    private var _liveOpen = false
    private var liveOpen: Bool {
        liveLock.lock(); defer { liveLock.unlock() }
        return _liveOpen
    }

    // ── Video pipeline (all on videoQueue) ───────────────────────────────
    private let videoQueue = DispatchQueue(label: "broadcast.video", qos: .userInitiated)
    // Newest sample waiting for the next encode slot ("latest wins"), so the
    // LAST frame of a scroll is never lost to the frame-rate cap.
    private let slotLock = NSLock()
    private var latestVideo: CMSampleBuffer?
    private var drainScheduled = false
    private var lastEncodeTime: CFAbsoluteTime = 0
    private var lastSendTime: CFAbsoluteTime = 0
    private var lastFrame: EncodedFrame?
    /// 15 fps while someone consumes frames — the LiveKit screen-share preset
    /// in prejoin.dart is 1080p15, more would only cost CPU / memory.
    private let activeFrameInterval: CFAbsoluteTime = 1.0 / 15.0
    /// Before the socket is connected and when not recording: keep a fresh
    /// lastFrame (sent as soon as the socket opens) at 2 fps.
    private let idleFrameInterval: CFAbsoluteTime = 0.5

    // ── Wants (marker files from the app) ────────────────────────────────
    private struct Wants { var videoFile = false; var audioQueue = false; var detail = false }
    private let wantsLock = NSLock()
    private var wants = Wants()
    private var wantsCheckedAt: CFAbsoluteTime = 0
    private var wantsDirty = true
    private var containerURL: URL?

    // ── Recording IPC ─────────────────────────────────────────────────────
    private var frameFileURL: URL?
    private var audioQueueDirURL: URL?
    // Only touched from processSampleBuffer's .audioApp case (serial).
    private var audioSeq: UInt64 = 0
    private var pendingAudioRecords: [Data] = []
    // .audioApp fires every ~10-25 ms; 6 per file keeps added latency at
    // roughly 60-150 ms and file writes at ~1/6 of the callback rate (writing
    // one file per sample made ReplayKit stop delivering .audioApp).
    private let kAudioBatchSize = 6
    // Reused AudioBufferList storage (per-callback alloc/free also starved
    // .audioApp delivery); the lock prevents two overlapping calls aliasing it.
    private var audioListBuffer: UnsafeMutableRawPointer?
    private var audioListBufferSize: Int = 0
    private let audioBufferLock = NSLock()

    // ── End-of-broadcast bookkeeping ─────────────────────────────────────
    private let endLock = NSLock()
    private var stoppedPosted = false
    private var finishing = false

    #if DEBUG
    private var lastAudioAppRmsLogTime: CFAbsoluteTime = 0
    #endif

    // MARK: - RPBroadcastSampleHandler

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) else {
            let err = NSError(
                domain: RPRecordingErrorDomain, code: 10002,
                userInfo: [NSLocalizedDescriptionKey:
                    "App Group '\(kAppGroup)' not found. Add the App Groups capability "
                    + "(same group) to the Runner and BroadcastUploadExtension targets."])
            finishBroadcastWithError(err)
            return
        }
        containerURL = container
        frameFileURL = container.appendingPathComponent(kFrameFileName)
        let audioDir = container.appendingPathComponent(kAudioQueueDirName)
        try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        audioQueueDirURL = audioDir
        audioSeq = 0
        pendingAudioRecords.removeAll()
        refreshWants(force: true)

        let darwin = DarwinNotificationCenter.shared
        darwin.observe(.broadcastRequestStop) { [weak self] in
            NSLog("[SampleHandler] stop requested by the app")
            self?.endBroadcast(error: nil)
        }
        darwin.observe(.wantsChanged) { [weak self] in
            guard let self = self else { return }
            self.wantsLock.lock(); self.wantsDirty = true; self.wantsLock.unlock()
        }

        setUpLiveConnection(container: container)
        startKeepAlive()

        // LiveKit publishes the screen-share track on this (BroadcastManager);
        // AppDelegate arms the recording / app-audio paths on it.
        darwin.post(.broadcastStarted)
        NSLog("[SampleHandler] started — container: \(container.path)")
    }

    override func broadcastPaused()  { flushPendingAudio() }
    override func broadcastResumed() {}

    override func broadcastFinished() {
        // Stopped from Control Center / the red status pill, or after
        // finishBroadcastWithError.
        endLock.lock(); finishing = true; endLock.unlock()
        flushPendingAudio()
        postStoppedOnce()
        tearDownLive()
        DarwinNotificationCenter.shared.removeAll()
        audioBufferLock.lock()
        audioListBuffer?.deallocate()
        audioListBuffer = nil
        audioListBufferSize = 0
        audioBufferLock.unlock()
        NSLog("[SampleHandler] finished")
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }

        switch sampleBufferType {
        case .video:
            enqueueVideo(sampleBuffer)

        case .audioApp:
            refreshWantsIfNeeded()
            guard currentWants().audioQueue else {
                if !pendingAudioRecords.isEmpty { pendingAudioRecords.removeAll() }
                return
            }
            #if DEBUG
            logAudioFormatOncePerSecond(sampleBuffer)
            #endif
            guard let record = serialiseAudio(sampleBuffer) else { return }
            writeAudioSample(record)

        case .audioMic:
            // Intentionally dropped: the live mic is LiveKit's own track and
            // the recording gets it from the LiveKit audio tap.
            return

        @unknown default:
            return
        }
    }

    // MARK: - Ending the broadcast

    /// Ends the broadcast from inside the extension (app asked, or the app
    /// closed the share socket). `error == nil` → the friendly default text,
    /// which iOS shows in its "Screen Broadcast stopped" alert.
    private func endBroadcast(error: Error?) {
        endLock.lock()
        let already = finishing
        finishing = true
        endLock.unlock()
        guard !already else { return }

        flushPendingAudio()
        postStoppedOnce()
        tearDownLive()
        let shown: NSError = error.map { $0 as NSError } ?? NSError(
            domain: RPRecordingErrorDomain, code: 10001,   // reference: JMScreenSharingStopped
            userInfo: [NSLocalizedDescriptionKey: Self.stoppedMessage()])
        finishBroadcastWithError(shown)
    }

    /// iOS_BroadcastStopped (LiveKit) + the app's own recording stop. Once.
    private func postStoppedOnce() {
        endLock.lock()
        let already = stoppedPosted
        stoppedPosted = true
        endLock.unlock()
        guard !already else { return }
        DarwinNotificationCenter.shared.post(.broadcastStopped)
        DarwinNotificationCenter.shared.post(.recordingStop)
    }

    private static func stoppedMessage() -> String {
        let lang = Locale.preferredLanguages.first ?? "en"
        return lang.hasPrefix("ar") ? "تم إيقاف مشاركة الشاشة" : "Screen sharing stopped"
    }

    // MARK: - Live connection

    private func setUpLiveConnection(container: URL) {
        let path = container.appendingPathComponent(kSocketFileName).path
        let conn = SocketConnection(filePath: path)
        let up = SampleUploader(connection: conn)   // sets didOpen / hasSpace
        conn.didClose = { [weak self] error in
            guard let self = self else { return }
            self.liveLock.lock(); self._liveOpen = false; self.liveLock.unlock()
            // The app unpublished the screen-share track (share stopped, room
            // left) or the app went away: end the broadcast like the reference.
            NSLog("[SampleHandler] live socket closed by the app (\(String(describing: error)))")
            self.endBroadcast(error: nil)
        }
        connection = conn
        uploader = up

        // flutter_webrtc only listens once LiveKit created the track, which
        // happens after iOS_BroadcastStarted reaches the app: retry until then.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "broadcast.connect"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(100))
        // Strong capture of `timer` (as in the reference); the cycle ends with
        // cancel() here or in tearDownLive().
        timer.setEventHandler { [weak self] in
            guard let self = self else { timer.cancel(); return }
            guard conn.open() else { return }
            self.liveLock.lock(); self._liveOpen = true; self.liveLock.unlock()
            NSLog("[SampleHandler] live socket connected")
            timer.cancel()
        }
        connectTimer = timer
        timer.resume()
    }

    private func tearDownLive() {
        connectTimer?.cancel()
        connectTimer = nil
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        liveLock.lock(); _liveOpen = false; liveLock.unlock()
        connection?.close()
    }

    /// Re-sends the last JPEG once a second while nothing new was sent
    /// (static screen, or the socket just opened). Costs no encode.
    private func startKeepAlive() {
        let timer = DispatchSource.makeTimerSource(queue: videoQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: .milliseconds(250), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self = self, let frame = self.lastFrame,
                  let up = self.uploader, up.isReady else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastSendTime >= 1.0 else { return }
            if up.send(frame) { self.lastSendTime = now }
        }
        keepAliveTimer = timer
        timer.resume()
    }

    // MARK: - Video

    private func enqueueVideo(_ sample: CMSampleBuffer) {
        slotLock.lock()
        latestVideo = sample          // releases the previous waiting sample
        let schedule = !drainScheduled
        drainScheduled = true
        slotLock.unlock()
        if schedule { videoQueue.async { [weak self] in self?.drainVideo() } }
    }

    /// videoQueue only.
    private func drainVideo() {
        refreshWantsIfNeeded()
        let w = currentWants()
        let open = liveOpen
        let liveReady = uploader?.isReady ?? false
        let consuming = open || w.videoFile
        let interval = consuming ? activeFrameInterval : idleFrameInterval
        let now = CFAbsoluteTimeGetCurrent()

        let wait = interval - (now - lastEncodeTime)
        if wait > 0 {
            videoQueue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.drainVideo() }
            return
        }
        // Live is the only consumer and the previous frame is still being
        // written: keep the newest sample and look again shortly.
        if open && !liveReady && !w.videoFile {
            videoQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in self?.drainVideo() }
            return
        }

        slotLock.lock()
        let sample = latestVideo
        latestVideo = nil
        drainScheduled = false
        slotLock.unlock()
        guard let sb = sample else { return }

        guard let frame = encoder.encode(sb, detail: w.detail) else { return }
        lastEncodeTime = now
        lastFrame = frame
        if liveReady, let up = uploader, up.send(frame) { lastSendTime = now }
        if w.videoFile { writeFrameFile(frame) }
    }

    /// Recording IPC: [4B typeId=0 BE][8B ptsNs BE][4B size BE][JPEG], written
    /// to a temp file and renamed over broadcast_frame.bin (atomic for the
    /// reader) without building a second header+JPEG Data.
    private func writeFrameFile(_ frame: EncodedFrame) {
        guard let url = frameFileURL else { return }
        var header = Data(capacity: 16)
        var typeId = UInt32(0).bigEndian
        var pts8   = frame.ptsNs.bigEndian
        var size4  = UInt32(frame.jpeg.count).bigEndian
        withUnsafeBytes(of: &typeId) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &pts8)   { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &size4)  { header.append(contentsOf: $0) }

        let tmpPath = url.path + ".tmp"
        guard FileManager.default.createFile(atPath: tmpPath, contents: header) else { return }
        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: tmpPath))
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: frame.jpeg)
        } catch {
            return
        }
        guard Darwin.rename(tmpPath, url.path) == 0 else { return }
        DarwinNotificationCenter.shared.post(.recordingFrame)
    }

    // MARK: - Wants

    private func currentWants() -> Wants {
        wantsLock.lock(); defer { wantsLock.unlock() }
        return wants
    }

    private func refreshWantsIfNeeded() {
        wantsLock.lock()
        let due = wantsDirty || CFAbsoluteTimeGetCurrent() - wantsCheckedAt >= 1.0
        wantsLock.unlock()
        if due { refreshWants(force: true) }
    }

    private func refreshWants(force: Bool) {
        guard let c = containerURL else { return }
        let fm = FileManager.default
        var w = Wants()
        w.videoFile  = fm.fileExists(atPath: c.appendingPathComponent(kWantsVideoFile).path)
        w.audioQueue = fm.fileExists(atPath: c.appendingPathComponent(kWantsAudioQueue).path)
        w.detail     = fm.fileExists(atPath: c.appendingPathComponent(kWantsDetail).path)
        wantsLock.lock()
        wants = w
        wantsDirty = false
        wantsCheckedAt = CFAbsoluteTimeGetCurrent()
        wantsLock.unlock()
    }

    // MARK: - Audio (.audioApp) serialisation
    //
    // Record (typeId = 2, AppDelegate.handleBroadcastData):
    //   [4B typeId BE][8B ptsNs BE][4B size BE]
    //   payload: [4B sampleRate BE][4B channels BE][4B isFloat BE][PCM]
    // PCM is interleaved and NATIVE (little) endian: ReplayKit's .audioApp is
    // commonly signed 16-bit BIG-endian (kAudioFormatFlagIsBigEndian), and the
    // host treated it as little-endian → loud noise (I13). Byte-swapped here.
    // Only 16-bit integer and 32-bit float are forwarded.

    private func serialiseAudio(_ sb: CMSampleBuffer) -> Data? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sb),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return nil }
        let asbd = asbdPtr.pointee
        // Non-PCM (e.g. DRM-protected content) cannot be forwarded.
        guard asbd.mFormatID == kAudioFormatLinearPCM else { return nil }

        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isBigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
        let bytesPerSample = Int(asbd.mBitsPerChannel) / 8
        guard (isFloat && bytesPerSample == 4) || (!isFloat && bytesPerSample == 2) else {
            return nil
        }
        let channels = Int(asbd.mChannelsPerFrame)
        guard channels > 0 else { return nil }

        let pts   = CMSampleBufferGetPresentationTimeStamp(sb)
        let ptsNs = UInt64(max(0, CMTimeGetSeconds(pts) * 1_000_000_000))

        var sizeNeeded = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb, bufferListSizeNeededOut: &sizeNeeded, bufferListOut: nil,
            bufferListSize: 0, blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil
        )
        guard sizeStatus == noErr, sizeNeeded > 0 else { return nil }

        audioBufferLock.lock()
        defer { audioBufferLock.unlock() }

        if audioListBuffer == nil || audioListBufferSize < sizeNeeded {
            audioListBuffer?.deallocate()
            audioListBuffer = UnsafeMutableRawPointer.allocate(
                byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment
            )
            audioListBufferSize = sizeNeeded
        }
        guard let rawList = audioListBuffer else { return nil }
        let listPtr = rawList.assumingMemoryBound(to: AudioBufferList.self)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sb,
            bufferListSizeNeededOut: nil,
            bufferListOut: listPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        // blockBuffer backs every mData pointer below; keep it alive until
        // the bytes are copied (an optimised build may release it early).
        return withExtendedLifetime(blockBuffer) { () -> Data? in
            let list = UnsafeMutableAudioBufferListPointer(listPtr)
            let numBuffers = list.count
            guard numBuffers > 0 else { return nil }

            var pcmData: Data
            if numBuffers == 1 {
                guard let buffer = list[0].mData, list[0].mDataByteSize > 0 else { return nil }
                pcmData = Data(bytes: buffer, count: Int(list[0].mDataByteSize))
            } else {
                // Planar → interleave so the wire format stays "interleaved".
                guard list[0].mDataByteSize > 0 else { return nil }
                let frameCount = Int(list[0].mDataByteSize) / bytesPerSample
                let channelPtrs: [UnsafeMutableRawPointer?] = (0..<numBuffers).map { list[$0].mData }
                guard channelPtrs.allSatisfy({ $0 != nil }) else { return nil }
                pcmData = Data(count: frameCount * bytesPerSample * numBuffers)
                pcmData.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
                    guard let dstBase = dst.baseAddress else { return }
                    for frame in 0..<frameCount {
                        for ch in 0..<numBuffers {
                            let src = channelPtrs[ch]!.advanced(by: frame * bytesPerSample)
                            dstBase.advanced(by: (frame * numBuffers + ch) * bytesPerSample)
                                .copyMemory(from: src, byteCount: bytesPerSample)
                        }
                    }
                }
            }
            if isBigEndian { Self.swapBytesInPlace(&pcmData, width: bytesPerSample) }

            var payload = Data(capacity: 12 + pcmData.count)
            var sr = UInt32(asbd.mSampleRate).bigEndian
            var ch = UInt32(numBuffers > 1 ? numBuffers : channels).bigEndian
            var fl = UInt32(isFloat ? 1 : 0).bigEndian
            withUnsafeBytes(of: &sr) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: &ch) { payload.append(contentsOf: $0) }
            withUnsafeBytes(of: &fl) { payload.append(contentsOf: $0) }
            payload.append(pcmData)

            var out = Data(capacity: 16 + payload.count)
            var typeId = UInt32(2).bigEndian
            var pts8   = ptsNs.bigEndian
            var size4  = UInt32(payload.count).bigEndian
            withUnsafeBytes(of: &typeId) { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &pts8)   { out.append(contentsOf: $0) }
            withUnsafeBytes(of: &size4)  { out.append(contentsOf: $0) }
            out.append(payload)
            return out
        }
    }

    /// Big-endian → native for 2- or 4-byte samples.
    private static func swapBytesInPlace(_ data: inout Data, width: Int) {
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            let count = raw.count / width
            if width == 2 {
                let p = raw.bindMemory(to: UInt16.self)
                for i in 0..<count { p[i] = p[i].byteSwapped }
            } else if width == 4 {
                let p = raw.bindMemory(to: UInt32.self)
                for i in 0..<count { p[i] = p[i].byteSwapped }
            }
        }
    }

    #if DEBUG
    /// Debug builds only: the shared app's audio format, once a second.
    private func logAudioFormatOncePerSecond(_ sb: CMSampleBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAudioAppRmsLogTime >= 1.0,
              let fd = CMSampleBufferGetFormatDescription(sb),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee else { return }
        lastAudioAppRmsLogTime = now
        NSLog("[SampleHandler][diag] .audioApp sr=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame) "
              + "bits=\(asbd.mBitsPerChannel) flags=0x\(String(asbd.mFormatFlags, radix: 16))")
    }
    #endif

    // MARK: - Audio queue files

    private func writeAudioSample(_ data: Data) {
        pendingAudioRecords.append(data)
        if pendingAudioRecords.count >= kAudioBatchSize { flushPendingAudio() }
    }

    /// One file per batch, never reusing a name (no overwrite race with the
    /// app's drain), one Darwin notification per batch.
    private func flushPendingAudio() {
        guard !pendingAudioRecords.isEmpty else { return }
        guard let dir = audioQueueDirURL, currentWants().audioQueue else {
            pendingAudioRecords.removeAll()
            return
        }
        var batch = Data(capacity: pendingAudioRecords.reduce(0) { $0 + $1.count })
        for record in pendingAudioRecords { batch.append(record) }
        pendingAudioRecords.removeAll()

        let seq = audioSeq
        audioSeq += 1
        let fileURL = dir.appendingPathComponent("aud_\(paddedSeq(seq)).bin")
        try? batch.write(to: fileURL, options: .atomic)
        DarwinNotificationCenter.shared.post(.recordingAudio)
    }

    private func paddedSeq(_ n: UInt64) -> String {
        let s = String(n)
        guard s.count < kAudioSeqPad else { return s }
        return String(repeating: "0", count: kAudioSeqPad - s.count) + s
    }
}
