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
//     This app uses livekit_client (Flutter) → flutter_webrtc → Google's
//     native WebRTC framework — there is NO client-sdk-swift/AudioManager
//     in this dependency tree, only WebRTC's own RTCAudioSession. By
//     default RTCAudioSession configures/activates AVAudioSession
//     automatically in response to its OWN audio engine lifecycle events
//     (mic publish/unpublish, track subscribe, internal reconnects) —
//     independently of anything this file does, and without necessarily
//     posting a routeChangeNotification we could observe.
//
//     THIS WAS THE ROOT CAUSE of "shared video sound is fine for a
//     fraction of a second, then goes quiet for the rest of the share":
//     configureAudioSessionForBroadcastShare() below would set the
//     non-ducking .videoRecording mode, then RTCAudioSession's own
//     automatic handling would silently stomp it back to .videoChat
//     (which force-ducks the shared app's audio) on its next internal
//     trigger — often under a second later, well before our old 0.5s
//     poll timer even got a chance to look.
//
//     FIX: RTCAudioSession.sharedInstance().useManualAudio = true is set
//     once at launch (see application(_:didFinishLaunchingWithOptions:)).
//     This tells WebRTC's audio engine to stop reconfiguring
//     AVAudioSession on its own — WE now own every transition, funneled
//     through lockForConfiguration()/unlockForConfiguration() so WebRTC's
//     engine and our AVAudioSession calls never race each other. The
//     reassert timer stays as a defensive fallback only (interval
//     shortened — see startAudioSessionObserver), it should now rarely if
//     ever need to actually do anything.
//
//  LIVE SCREEN SHARE (2026-10-29, audit docs/live/audit/ios_web.md I1–I14;
//  UNTESTED — written on Windows, see docs/live/ios_test_plan.md):
//     Viewers get the shared screen through flutter_webrtc's broadcast
//     capturer: the extension sends JPEG frames over the Unix socket
//     <App Group>/rtc_SSFD (Info.plist RTCAppGroupIdentifier /
//     RTCScreenSharingExtension) and posts iOS_BroadcastStarted / Stopped,
//     which livekit_client turns into publishing / unpublishing the
//     screen-share track (Dart: ScreenShareCaptureOptions(
//     useiOSBroadcastExtension: true), docs/live/ios_share_wiring.md).
//     This file observes the same two notifications (onLkBroadcastStarted /
//     Stopped) to arm the in-app recorder (path B above, unchanged wire
//     format, now only while the ext_wants_* marker files ask for it), to
//     report the share state to Dart ("…/broadcast_state" EventChannel) and
//     to mix the shared app's sound into the live microphone
//     (ShareAppAudioMixer at the bottom, flutter_webrtc AudioManager's
//     capture post-processing hook). "requestBroadcastStop" / "stopBroadcast"
//     post iOS_BroadcastRequestStop so the extension really ends (I2).
//     During a share the session stays playAndRecord + videoChat (I5: echo
//     cancellation kept; the old .videoRecording switch is gone).
//
//  ════════════════════════════════════════════════════════════════════

import Flutter
import UIKit
import Firebase
import ReplayKit
import AVFoundation
import MediaPlayer  // the listen bar's lock-screen controls (VodNowPlaying, D-104)
import CoreMedia
import CoreVideo
import WebRTC
import flutter_webrtc   // AudioManager / ExternalAudioProcessingDelegate (ShareAppAudioMixer)
import os

@main
@objc class AppDelegate: FlutterAppDelegate {

    // ── Channel names ─────────────────────────────────────────────────────────
    private let kScreenShareChannel = "com.doubley.alfaheem/screen_share"
    private let kRecorderChannel    = "com.doubley.alfaheem/native_recorder"
    private let kRecEventChannel    = "com.doubley.alfaheem/rec_events"

    // ── EventChannel sink ─────────────────────────────────────────────────────
    private var eventSink: FlutterEventSink?

    // ── Flutter engine ────────────────────────────────────────────────────────
    private var flutterEngine: FlutterEngine?

    // ── AVAssetWriter — one instance, reused across chunks ───────────────────
    private var assetWriter:        AVAssetWriter?
    private var videoInput:         AVAssetWriterInput?
    private var audioInput:         AVAssetWriterInput?
    // Second audio track for the SHARED APP's own audio (e.g. a video/game
    // playing on the screen being broadcast) — see SampleHandler.swift's
    // .audioApp forwarding. Deliberately a SEPARATE AVAssetWriterInput
    // rather than mixed into `audioInput`: putting two independently-clocked
    // PCM streams (mic + system audio) into one track hits the exact
    // "strictly increasing PTS per track" problem documented on lastAudioPts
    // below — a second track sidesteps that entirely, at the cost of the
    // two tracks needing to be mixed down (e.g. ffmpeg `amix`) server-side
    // during the existing post-transcode step, since most players only play
    // one audio track at a time by default.
    private var systemAudioInput:   AVAssetWriterInput?
    private var lastSystemAudioPts: CMTime?
    // Small holding buffer for system-audio samples that arrive in the brief
    // window right after a new chunk's writer is created but before its
    // session has actually started (started by the first broadcast VIDEO
    // frame — see processSampleFromBroadcast). Previously these were just
    // dropped ("writer not active"/"session not started"), which bit at
    // every chunk rotation during a screen share. Buffered here (in arrival
    // order) and flushed once the session goes live — see
    // flushPendingSystemAudioFrames(). Only ever touched on systemAudioQueue.
    private var pendingSystemAudioFrames:
        [(sampleRate: UInt32, channels: UInt32, isFloat: Bool, pcm: Data, ptsNs: UInt64)] = []
    // ~1-1.5s of audio at a 10-25ms buffer interval — comfortably covers
    // the chunk-rotation gap without buffering unbounded amounts if
    // something is genuinely stuck.
    private let kPendingSystemAudioCap = 60
    // Guards against scheduling overlapping retries when several samples in
    // a row hit "systemAudioInput not ready" — only one retry needs to be in
    // flight at a time since it drains the whole queue when it fires.
    private var notReadyRetryScheduled = false
    // True while a not-ready sample is queued and waiting for its retry —
    // see processSystemAudioFromBroadcast's guard and appendSystemAudioSample's
    // not-ready branch. Keeps ordering strict: newly-arriving samples queue
    // up behind the retry instead of appending directly and landing ahead
    // of it.
    private var systemAudioBackpressured = false
    // FIX (2026-08-01) — investigating a "system audio plays as noise/
    // static" report. systemAudioInput's internal audio converter/encoder
    // is configured from whatever format the FIRST sample buffer appended
    // to it this chunk has — it isn't built to silently re-negotiate for
    // a differently-shaped buffer arriving mid-stream. makeAudioSampleBuffer
    // rebuilds the ASBD fresh from EVERY packet's own reported sampleRate/
    // channels/isFloat (see processSystemAudioFromBroadcast) without
    // checking it matches what systemAudioInput already locked onto — if
    // ReplayKit ever reports a different shape mid-chunk (e.g. the shared
    // app briefly switching mono/stereo, or a route change altering the
    // tap's reported format), that later buffer gets forced through a
    // converter set up for the earlier format. That mismatch is a classic
    // cause of exactly this symptom (audible static, not silence and not
    // just "loud") since samples get reinterpreted at the wrong stride/
    // rate. This tracks the format actually locked in per chunk so a
    // later mismatch can be caught and dropped-with-a-log instead of
    // silently corrupting the track. Reset to nil in beginChunkWriter.
    private var systemAudioLockedFormat: (sampleRate: UInt32, channels: UInt32, isFloat: Bool)?
    // Pixel buffer adaptor for the broadcast-extension path. Broadcast frames
    // arrive as decoded JPEGs (see jpegToPixelBuffer), and MUST be appended
    // through an AVAssetWriterInputPixelBufferAdaptor rather than by manually
    // constructing a CMSampleBuffer and calling videoInput.append(_:) — see
    // the long comment in jpegToPixelBuffer() for why the manual-CMSampleBuffer
    // approach silently poisoned the writer for the rest of the session.
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    // Last successfully-appended broadcast-frame PTS for the CURRENT chunk —
    // guards against non-monotonic timestamps the same way lastAudioPts does.
    private var lastBroadcastVideoPts: CMTime?
    // Exact width/height the CURRENT chunk's pixelBufferAdaptor pool was
    // configured with (set in beginChunkWriter). Every broadcast frame MUST
    // be drawn into a buffer of exactly this size — see jpegToPixelBuffer.
    private var chunkVideoWidth:  Int = 0
    private var chunkVideoHeight: Int = 0
    private var writerSessionStarted = false    // true once startSession() called
    // Last successfully-appended audio PTS for the CURRENT chunk's audioInput.
    // See processSampleFromRecorder's .audioMic/.audioApp case for why this
    // is required — it's the fix for audio silently disappearing from
    // recordings. Reset to nil every time a new chunk/writer is created.
    private var lastAudioPts: CMTime?
    // Per-chunk counters, purely for diagnostics: logged in finaliseChunk's
    // "finalised chunk #N" line so we can tell, from the log alone, whether
    // RPScreenRecorder is delivering ANY audio samples at all (audioSamplesSeen
    // stays 0 the whole session ⇒ capture/permission problem, look upstream of
    // the writer) versus samples arriving but something downstream dropping
    // them (audioSamplesSeen > 0 but audioSamplesAppended is much lower, or
    // the final assembled video still has no sound despite both being > 0,
    // which would point at the server's ffmpeg step instead).
    private var audioSamplesSeenThisChunk: Int = 0
    private var audioSamplesAppendedThisChunk: Int = 0
    private var sysAudioSamplesSeenThisChunk: Int = 0
    private var sysAudioSamplesAppendedThisChunk: Int = 0
    // Peak absolute sample value (normalized 0.0–1.0) seen in system-audio
    // payloads THIS CHUNK. This is the key diagnostic for "shared audio is
    // very quiet/absent": sysAudioSeen>0 with sysAudioPeak sitting at
    // (or extremely near) 0.0 for the WHOLE recording proves ReplayKit is
    // handing us literal silence/zeroed-out buffers for the specific app
    // being shared — a documented, longstanding ReplayKit limitation for
    // certain apps (Apple has open radars on this; it is NOT something
    // fixable from gain/ducking/loudnorm on our side, since there is no
    // real signal to amplify). A non-trivial peak (say > 0.02) means real
    // signal IS arriving and any remaining quietness is a mixing/gain
    // question further down the pipeline, not a capture problem.
    private var sysAudioPeakThisChunk: Float = 0.0
    // Running sum-of-squares + sample count for an RMS (average loudness)
    // reading per chunk, alongside the existing peak-only diagnostic. Peak
    // alone was insufficient to catch the ducking-oscillation bug: a single
    // loud sample landing during a brief un-ducked window makes the peak
    // look healthy (~1.0) even while the audio was ducked/near-silent for
    // the rest of the chunk. RMS surfaces that gap — a chunk that's mostly
    // ducked will show a high peak but a low RMS, whereas one that's
    // genuinely clear throughout will show both high.
    private var sysAudioSquareSumThisChunk: Double = 0.0
    private var sysAudioRmsSampleCountThisChunk: Int = 0
    // Mirrors audioSeen/audioAppended above, but for broadcast VIDEO frames
    // (processSampleFromBroadcast) instead of audio. There was previously no
    // numeric visibility into whether broadcast video frames were even
    // reaching that function, being silently rejected by one of its guards
    // (writer/adaptor/pool/isReadyForMoreMediaData/chunkVideoWidth/Height),
    // or reaching adaptor.append() and failing there — any of which would
    // produce the same symptom (audio present, shared screen video absent)
    // with nothing in the log to distinguish which stage was actually at
    // fault. videoBroadcastSeen=0 for a chunk known to be broadcast-sourced
    // ⇒ frames aren't reaching this function at all (IPC/routing problem
    // upstream, e.g. handleBroadcastData not dispatching typeId=0). Seen>0
    // but Appended==0 ⇒ one of the guards at the top of
    // processSampleFromBroadcast is rejecting every frame. Both > 0 ⇒
    // frames are genuinely being written into the chunk's video track, and
    // an all-black or missing appearance in the ASSEMBLED file points
    // downstream (jpegToPixelBuffer's letterbox math, or the server's
    // ffmpeg step) instead.
    private var videoBroadcastSeenThisChunk: Int = 0
    private var videoBroadcastAppendedThisChunk: Int = 0
    private var writerQueue = DispatchQueue(label: "com.doubley.alfaheem.writer", qos: .userInitiated)
    // Same reasoning as audioIpcReadQueue above, one level further down the
    // pipeline: writerQueue does video JPEG decode + append (expensive) AND
    // mic-audio append. Appending system audio there too means a slow video
    // decode can stall system-audio appends behind it — its own queue keeps
    // that append path independent. AVAssetWriterInput.append() is safe to
    // call from a different thread per input; it's only unsafe to call
    // concurrently on the SAME input from multiple threads, which this
    // doesn't do (systemAudioInput is only ever touched from this queue).
    private var systemAudioQueue = DispatchQueue(label: "com.doubley.alfaheem.writer.systemAudio", qos: .userInteractive)

    // ── Session params ────────────────────────────────────────────────────────
    private var sessionId:  Int    = 0
    private var uploadUrl:  String = ""
    private var authToken:  String = ""
    // The recorder start's id (ms, a new one per start; docs/live/native_epoch.md): sent as the chunk field
    // `epoch`, so the server orders assembly by (epoch, index). Empty from an older Dart side.
    private var epoch:      String = ""
    // 409 recording_assembled / a dead upload token: this run takes no more chunks (reset on every start).
    private var uploadsClosed: Bool = false
    private var chunkSecs:  Int    = 5
    // Meeting recordings (docs/backend/live-rooms-spec.md §5): the picked quality; 0 = the defaults below.
    private var videoBitrate: Int  = 0
    private var maxHeight:    Int  = 0
    // Audio-only (quality "audio"): no RPScreenRecorder at all — the AVAssetWriter chunk loop runs with
    // audio tracks only from startMicRecording on (see startAudioOnlyRecording), each chunk's session is
    // anchored by its first audio sample (handleIncomingAudioFrame), and chunks upload as .m4a / audio/mp4.
    private var audioOnly:    Bool = false

    // ── Chunk loop state ──────────────────────────────────────────────────────
    private var chunkIndex:   Int   = 0
    private var chunkTimer:   Timer?
    private var currentFile:  URL?
    private var recording     = false
    private var paused        = false
    private var stopping      = false
    private var audioSessionObserver: NSObjectProtocol?
    // NEW: separate observer for AVAudioSession.interruptionNotification.
    // See startAudioSessionObserver's doc comment for why routeChange alone
    // was an incomplete fix — category/mode survive an interruption but the
    // session's ACTIVE state does not, and alreadyCorrect only checks
    // category/mode, so a route-change-only observer could leave the
    // session silently inactive (and the shared app ducked) with nothing
    // logged to explain it.
    private var audioInterruptionObserver: NSObjectProtocol?
    // See startAudioSessionObserver's doc comment — this is what actually
    // keeps the shared app's audio un-ducked for the WHOLE share, not just
    // the first second of it.
    private var audioSessionReassertTimer: Timer?
    // Diagnostics: how many times THIS broadcast actually reconfigured the
    // session (as opposed to alreadyCorrect short-circuiting). A healthy
    // share should show this stay very low (ideally 1 — the initial
    // pre-picker call) after the first ~second. If this climbs steadily for
    // the whole share, something is repeatedly kicking the session out of
    // non-ducking mode and the reassert timer is fighting it the entire
    // time — worth knowing, since that repeated setActive/setCategory
    // churn is itself audible as clicking/static on the shared app's audio.
    private var audioReconfigCount = 0
    private var audioReconfigCountAtShareStart = 0

    private func startAudioSessionObserver() {
        // Idempotent: this is now called both pre-emptively from
        // showBroadcastPicker() and again (defensively) from
        // handleBroadcastData() on the first broadcast frame. Without this
        // guard, the second call would stack a duplicate route-change
        // observer (each future route change would then re-apply the
        // broadcast-share config twice) and restart the 0.15s reassert timer
        // from zero for no reason.
        guard audioSessionObserver == nil else { return }

        audioReconfigCount = 0
        audioReconfigCountAtShareStart = 0

        audioSessionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            // NOTE: (isBroadcasting || broadcastShareArmed) — a route change
            // (the user switching to the app they're about to share) is
            // exactly what can happen BEFORE isBroadcasting flips true. See
            // broadcastShareArmed's doc comment.
            guard let self = self, self.isBroadcasting || self.broadcastShareArmed else { return }
            // Re-assert non-ducking mode every time the session changes
            // while a broadcast is active (or about to be). Cheap no-op if
            // already correct.
            self.configureAudioSessionForBroadcastShare()
            NSLog("[REC] Audio session observer: re-applied broadcast-share mode after route change")
        }

        // NEW — the gap routeChangeNotification alone doesn't cover:
        // an interruption (Siri, a phone call, another app's transient
        // audio session, even certain background-task edge cases) can
        // deactivate our session WITHOUT changing category/mode. Since
        // configureAudioSessionForBroadcastShare()'s alreadyCorrect guard
        // only inspects category/mode/options — not whether the session is
        // actually active — a route-change-only observer can miss this
        // entirely: the guard reads "already correct", skips reactivating,
        // and the session stays silently inactive/ducked with nothing in
        // the log to explain it. This observer forces a real reconfigure
        // (bypassing the cheap early-return) specifically on interruption
        // end, since that's the one case where category/mode alone aren't
        // enough evidence that the session is actually live.
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isBroadcasting || self.broadcastShareArmed else { return }
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue)
            else { return }

            switch type {
            case .began:
                NSLog("[REC] Audio session interruption BEGAN during broadcast — "
                      + "session likely deactivated by the system")
            case .ended:
                // Force a real reconfigure — do NOT rely on alreadyCorrect
                // here, since category/mode can still read "correct" while
                // the session itself is inactive. forceReconfigureAudioSessionForBroadcastShare()
                // bypasses the early-return specifically for this case.
                NSLog("[REC] Audio session interruption ENDED during broadcast — "
                      + "forcing reactivation (bypassing alreadyCorrect)")
                self.forceReconfigureAudioSessionForBroadcastShare()
            @unknown default:
                break
            }
        }

        // WHY KEEP A TIMER AT ALL, GIVEN useManualAudio=true:
        // Setting RTCAudioSession.sharedInstance().useManualAudio = true at
        // launch (see didFinishLaunchingWithOptions) stops WebRTC's engine
        // from auto-reconfiguring AVAudioSession on its own internal
        // triggers — that was the actual root cause of "shared audio is
        // fine for about a second, then goes quiet for the rest of the
        // share", and is now fixed at the source. This timer is kept only
        // as a defensive fallback for anything else that could still drift
        // the session (e.g. another plugin, a Bluetooth reconnect edge
        // case) — it should now rarely if ever find `alreadyCorrect ==
        // false` in configureAudioSessionForBroadcastShare(). Interval
        // shortened from the old 0.5s to 0.15s: 0.5s was long enough for a
        // human to perceive as "briefly clear, then muted" if anything did
        // slip through; 0.15s keeps any residual drift below the threshold
        // of being audible as a distinct dropout. configureAudioSessionForBroadcastShare()
        // is a cheap no-op when the session is already correctly
        // configured, so polling this often is safe.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioSessionReassertTimer?.invalidate()
            self.audioSessionReassertTimer = Timer.scheduledTimer(
                withTimeInterval: 0.15, repeats: true
            ) { [weak self] _ in
                guard let self = self, self.isBroadcasting || self.broadcastShareArmed else { return }
                self.configureAudioSessionForBroadcastShare()
            }
        }
    }

    private func stopAudioSessionObserver() {
        if let observer = audioSessionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioSessionObserver = nil
        }
        if let observer = audioInterruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioInterruptionObserver = nil
        }
        // Diagnostic summary: how many times THIS share actually
        // reconfigured the session vs. the initial pre-picker call. A
        // healthy share should show this at or near 1. Anything
        // meaningfully higher means something kept knocking the session
        // out of non-ducking mode for the whole share — check for
        // repeated "[REC] AVAudioSession:" reconfigure lines in this same
        // log window to see what triggered each one (route change vs.
        // interruption vs. timer).
        let deltaThisShare = audioReconfigCount - audioReconfigCountAtShareStart
        NSLog("[REC] Audio session diagnostic: reconfigured \(deltaThisShare) time(s) "
              + "during this share (total since app launch: \(audioReconfigCount))")
        DispatchQueue.main.async { [weak self] in
            self?.audioSessionReassertTimer?.invalidate()
            self?.audioSessionReassertTimer = nil
        }
    }
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
    //   • httpMaximumConnectionsPerHost=1, and — more importantly — the
    //     explicit serial queue below (enqueueUpload/uploadFinished), keep
    //     chunk uploads strictly one-at-a-time. This used to be set to 4 to
    //     let the last few chunks upload in parallel during the stop-
    //     recording wait window, but on a constrained connection (e.g. the
    //     Cloudflare quick tunnels used in testing) that let several chunks
    //     compete for bandwidth simultaneously: EARLIER chunks would time
    //     out and exhaust their retries (each attempt permanently deletes
    //     the chunk file on final failure — see uploadChunkAsync) while a
    //     LATER chunk, uploaded once the earlier ones had already failed
    //     and cleared out of the way, sailed through uncontested. That's
    //     exactly why only the last of several chunks was ever reaching the
    //     server — not corruption, not a dropped chunk, just several large
    //     uploads fighting over one slow tunnel at once. Serial upload
    //     removes the contention entirely; see the queue below for the
    //     actual ordering guarantee (the connection-count setting alone
    //     isn't sufficient, since a chunk sleeping in its retry backoff
    //     isn't holding a connection, so the next chunk could still start
    //     early even with this set to 1).
    private lazy var uploadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity          = true
        cfg.timeoutIntervalForRequest     = 120
        cfg.timeoutIntervalForResource    = 300
        cfg.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: cfg)
    }()

    // ── Serial upload queue ─────────────────────────────────────────────────
    // Guarantees chunk uploads happen strictly one at a time, IN ORDER,
    // including every retry — the next chunk's first attempt never starts
    // until the current chunk's entire attempt sequence (success, or all
    // retries exhausted) has concluded. uploadChunkAsync's recursive retry
    // calls do NOT go through this queue (they're a continuation of the
    // same in-flight chunk, not a new one) — only the top-level call from
    // finaliseChunk does.
    private var uploadQueue: [() -> Void] = []
    private var uploadInFlight = false

    private func enqueueUpload(_ work: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uploadQueue.append(work)
            self.drainUploadQueueIfIdle()
        }
    }

    private func drainUploadQueueIfIdle() {
        guard !uploadInFlight, !uploadQueue.isEmpty else { return }
        uploadInFlight = true
        beginUploadBgTask()   // I9: its own task, ended when the queue is empty
        let next = uploadQueue.removeFirst()
        next()
    }

    /// Call exactly once per chunk, at whichever point its upload attempt
    /// sequence truly concludes — success, or retries exhausted. NOT called
    /// between individual retries, since those are the same chunk continuing.
    private func uploadFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.uploadInFlight = false
            self.drainUploadQueueIfIdle()
            // Once nothing is running AND nothing is queued behind it, the
            // upload's own background task is released. I9: this used to end
            // the shared "BroadcastRecord" bgTask, i.e. mid-broadcast after
            // every chunk upload, leaving the share unprotected in background.
            if !self.uploadInFlight, self.uploadQueue.isEmpty {
                self.endUploadBgTask()
            }
        }
    }

    // ── Broadcast source control ──────────────────────────────────────────────
    // When isBroadcasting = true, frames from RPScreenRecorder are suppressed
    // and frames from the broadcast extension are written instead.
    private var isBroadcasting      = false

    // FIX (2026-08-01) — covers the "still very quiet for the WHOLE share"
    // reports even after configureAudioSessionForBroadcastShare() was moved
    // to run pre-emptively in showBroadcastPicker(). isBroadcasting only
    // flips true once the FIRST broadcast video frame arrives, which is
    // 1-3+ seconds after the user taps "Start Broadcast" (they still have
    // to manually switch to the target app). All three reassertion
    // mechanisms in startAudioSessionObserver — the route-change observer,
    // the interruption-end observer, and the 0.15s timer — were gated on
    // isBroadcasting alone, so NONE of them were watching the session
    // during that gap. And that gap is precisely when a route change is
    // most likely (the user switching apps IS a route/foreground change).
    // If the session gets ducked in that window, it isn't corrected until
    // first-frame flips isBroadcasting true — by which point, per the
    // documented slow multi-second duck-release curve, the duck has
    // already latched for the rest of the share. broadcastShareArmed
    // closes that gap: it's set true the moment the picker is shown
    // (before isBroadcasting can possibly be true) and cleared on every
    // path that also clears/never-sets isBroadcasting for this share
    // attempt (cancelled picker, watchdog timeout, normal stop).
    private var broadcastShareArmed = false

    // NOTE: per-frame duration for broadcast frames used to be hand-computed
    // here from a tracked "previous PTS" because the old code appended raw
    // CMSampleBuffers. Now that processSampleFromBroadcast appends through
    // AVAssetWriterInputPixelBufferAdaptor, the adaptor derives each frame's
    // duration itself from the delta between consecutive presentation times,
    // so no extra state is needed here.

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
    //      Add group ID:  group.com.doubley.alfaheem
    //   2. Select the BroadcastUploadExtension target → same steps → same ID
    //   Both targets must share the EXACT same group string.
    //
    //   NOTE: this must match BroadcastUploadExtension.entitlements AND the
    //   kAppGroup constant in SampleHandler.swift EXACTLY (character-for-
    //   character). A previous version of this file used the snake_case
    //   variant of the group id ("group.<bundle id in snake_case>"), which silently
    //   mismatched the entitlements file (camelCase) — that mismatch makes
    //   containerURL(forSecurityApplicationGroupIdentifier:) return nil in
    //   BOTH processes, breaking the IPC with no obvious error at the call
    //   site. If you ever rename the App Group, grep the whole project for
    //   the old string and update every occurrence in the same commit.
    //   If your bundle ID differs, update kAppGroup in BOTH this file and
    //   SampleHandler.swift — they must be identical.
    private let kAppGroup           = "group.com.doubley.alfaheem"
    private let kDarwinFrameNotif   = "com.doubley.alfaheem.frame"
    // NEW: shared app's own audio (e.g. sound from a video/game on the
    // shared screen) — see SampleHandler.swift's .audioApp case. This is
    // backed by a QUEUE DIRECTORY (kAudioQueueDirName), not a single file
    // like video — see SampleHandler.swift's header comment for why a
    // single-file "mailbox" silently drops the large majority of this
    // audio (it arrives every ~10-25ms, too fast for overwrite-and-notify
    // to keep up with reliably).
    private let kDarwinAudioNotif   = "com.doubley.alfaheem.audioframe"
    private let kDarwinStopNotif    = "com.doubley.alfaheem.stop"
    private let kFrameFileName      = "broadcast_frame.bin"
    private let kAudioQueueDirName  = "broadcast_audio_queue"
    private var darwinObserverAdded = false
    private let ipcReadQueue        = DispatchQueue(label: "com.doubley.alfaheem.ipc", qos: .userInteractive)
    // Audio buffers (from LiveKit's mic tap AND the broadcast's .audioApp)
    // arrive far more often than video frames (every ~10-25ms vs every
    // ~33-100ms), and reading the video frame file involves decoding a full
    // JPEG. Sharing one serial queue between the two means a slow video
    // read can back up behind it every audio notification that fires while
    // it's working — and once that backlog exists it never drains, since
    // more audio keeps arriving faster than the queue can process it. A
    // dedicated queue means video work can never delay audio work or vice
    // versa.
    private let audioIpcReadQueue   = DispatchQueue(label: "com.doubley.alfaheem.ipc.audio", qos: .userInteractive)

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
    // I9: uploads draining after a stop get their OWN task, so finishing an
    // upload can never end the "BroadcastRecord" task above mid-broadcast.
    private var uploadBgTask: UIBackgroundTaskIdentifier = .invalid

    // ── Live screen share via the broadcast extension (I1–I3) ────────────────
    // Darwin names shared with livekit_client 2.13.1 (DarwinNotificationCenter.
    // swift) and the extension (BroadcastUploadExtension/DarwinNotificationCenter.swift).
    private let kLkBroadcastStarted     = "iOS_BroadcastStarted"
    private let kLkBroadcastStopped     = "iOS_BroadcastStopped"
    private let kLkBroadcastRequestStop = "iOS_BroadcastRequestStop"
    private let kDarwinWantsChanged     = "com.doubley.alfaheem.wants_changed"
    // Marker files in the App Group the extension polls (SampleHandler Wants).
    private let kWantsVideoFile  = "ext_wants_video_file"
    private let kWantsAudioQueue = "ext_wants_audio_queue"
    private let kWantsDetail     = "ext_detail_mode"
    private let kBroadcastStateChannel = "com.doubley.alfaheem/broadcast_state"
    /// True between iOS_BroadcastStarted and iOS_BroadcastStopped. Main thread.
    private var extensionBroadcastLive = false
    private var broadcastStateSink: FlutterEventSink?
    private var lkObserversAdded = false
    /// Mix the shared app's sound into the published microphone (Dart
    /// "setShareAppAudio"). On by default while a share is live.
    private var shareAppAudioEnabled = true
    private var shareDetailMode = false
    private let appAudioMixer = ShareAppAudioMixer()
    /// Audio-queue Darwin observer, registered either by the recorder
    /// (registerDarwinListeners) or by the mixer. Main thread.
    private var audioQueueObserverAdded = false

    // ── In-app recorder robustness (I7, I11, I12, I14) ───────────────────────
    private var recordingAudioObservers: [NSObjectProtocol] = []
    private var lastForcedRotation: CFAbsoluteTime = 0
    // Mic sample clock (I14), writerQueue only: PTS = anchor + samples / rate,
    // re-anchored on a format change or when it drifts > 0.3 s from arrival.
    private var micClockAnchor: CMTime?
    private var micClockSamples: Int64 = 0
    private var micClockRate: Int = 0
    // Mic format the CURRENT writer's audio input locked onto (I12),
    // writerQueue only. A different format means a new chunk.
    private var micLockedFormat: (writer: ObjectIdentifier, sampleRate: Int, channels: Int, format: String)?

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - App lifecycle
    // ─────────────────────────────────────────────────────────────────────────

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()

        // Take over AVAudioSession ownership from WebRTC's automatic
        // engine-lifecycle handling. Must be set exactly once, as early as
        // possible, before livekit_client/flutter_webrtc ever touches the
        // session — see the Audio section of the architecture comment at
        // the top of this file for why this is required.
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = true

        let engine = FlutterEngine(name: "main_engine")
        engine.run()
        flutterEngine = engine

        GeneratedPluginRegistrant.register(with: engine)
        registerScreenShareChannel(messenger: engine.binaryMessenger)
        registerRecorderChannel(messenger: engine.binaryMessenger)
        registerEventChannel(messenger: engine.binaryMessenger)
        registerBroadcastStateChannel(messenger: engine.binaryMessenger)
        VodNowPlaying.shared.register(messenger: engine.binaryMessenger) // a lecture as sound (D-104)

        // Live share: follow the extension's Started / Stopped for the whole
        // app lifetime, and start from a clean App Group (no stale markers or
        // audio files from a previous run that ended abruptly).
        clearExtensionMarkers()
        resetAudioQueueDirectory()
        registerLiveKitBroadcastObservers()

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
        // The app going away must not leave the extension capturing (I2).
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification, object: nil)

        // Downloaded (encrypted) videos must never go to iCloud / iTunes backups.
        excludeOfflineFolderFromBackup()

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
            // I8: the old handler finalised the chunk and bumped chunkIndex
            // but never opened a new writer, so nothing was recorded until
            // the share stopped. Rotate instead: the next writer opens before
            // the current one closes (finaliseChunk openNext). While the call
            // keeps the audio session active the "audio" background mode
            // keeps the process running, so recording simply continues.
            NSLog("[REC] background task expiring — rotating chunk")
            if self.recording, !self.stopping, !self.paused, self.writerSessionStarted {
                self.chunkTimer?.invalidate()
                self.chunkTimer = nil
                self.finaliseChunk(isFinal: false, openNext: true) { _ in }
            }
            self.endBgTask()
        }
        NSLog("[REC] background task started id=\(bgTask.rawValue)")
    }

    @objc private func appWillEnterForeground() {
        endBgTask()
    }

    @objc private func appWillTerminate() {
        if extensionBroadcastLive { postDarwin(kLkBroadcastRequestStop) }
        clearExtensionMarkers()
    }

    /// Keeps <Application Support>/offline (the encrypted downloads written by
    /// OfflineVideoService) out of iCloud / iTunes backups.
    private func excludeOfflineFolderFromBackup() {
        guard var dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        dir.appendPathComponent("offline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
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
                // Shows the system "Start Broadcast" sheet for OUR extension
                // (installed in the window — see showBroadcastPicker) and arms
                // the in-app recorder. When the user starts, the extension
                // posts iOS_BroadcastStarted and LiveKit publishes the share
                // (ScreenShareCaptureOptions(useiOSBroadcastExtension: true)).
                // {"present": false} arms the recorder without a sheet (for a
                // flow where LiveKit's requestActivation shows it).
                let present = (call.arguments as? [String: Any])?["present"] as? Bool ?? true
                self.showBroadcastPicker(present: present, result: result)

            case "stopBroadcast":
                self.stopBroadcastShare(result: result)

            case "requestBroadcastStop":
                // I2: ask the extension to end the broadcast (it answers with
                // finishBroadcastWithError + iOS_BroadcastStopped). Same
                // notification as livekit_client's BroadcastManager().requestStop().
                self.postDarwin(self.kLkBroadcastRequestStop)
                result(self.extensionBroadcastLive)

            case "isBroadcastActive":
                result(self.extensionBroadcastLive)

            case "setShareAppAudio":
                let on = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? true
                self.shareAppAudioEnabled = on
                if on { self.startAppAudioMixIfWanted() } else { self.stopAppAudioMix() }
                result(self.appAudioMixer.isActive)

            case "setShareDetailMode":
                let on = (call.arguments as? [String: Any])?["enabled"] as? Bool ?? false
                self.shareDetailMode = on
                self.updateExtensionWants()
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
                if let e = args["epoch"] as? String {
                    self.epoch = e
                } else if let n = args["epoch"] as? NSNumber {
                    self.epoch = n.stringValue
                } else {
                    self.epoch = ""
                }
                self.uploadsClosed = false
                self.chunkSecs  = args["chunkSeconds"] as? Int    ?? 5
                self.chunkIndex = args["chunkIndex"]   as? Int    ?? 0
                self.videoBitrate = args["videoBitrate"] as? Int  ?? 0
                self.maxHeight    = args["maxHeight"]    as? Int  ?? 0
                self.audioOnly    = args["audioOnly"]    as? Bool ?? false
                NSLog("[REC] startMicRecording: session=\(self.sessionId) chunkSecs=\(self.chunkSecs) audioOnly=\(self.audioOnly)")
                // I11: chunks that failed in an earlier run are retried now,
                // with this (fresh) token, ahead of this session's chunks.
                self.retryPendingChunks(authToken: self.authToken)
                // Audio-only: the whole recording starts right here (no Phase 2,
                // no screen capture, no red pill) — see startAudioOnlyRecording.
                if self.audioOnly { self.startAudioOnlyRecording() }
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

            // (startLocalDebugSave / stopLocalDebugSave — the TEMP Photos
            // mirror, audit I6 — were removed with LocalDebugRecorder.swift.
            // An old Dart build calling them gets FlutterMethodNotImplemented.)

            case "retryPendingUploads":
                // I11: optional — Dart may call this once signed in (app
                // start) so chunks kept from a failed upload go out without
                // waiting for the next recording.
                let token = (call.arguments as? [String: Any])?["authToken"] as? String ?? ""
                if !token.isEmpty { self.retryPendingChunks(authToken: token) }
                result(nil)

            case "sendAudioFrame":
                // Raw PCM audio frames forwarded from Dart via
                // LocalAudioTrack.addAudioRenderer() (see room.dart) — this
                // replaces RPScreenRecorder's own .audioMic/.audioApp capture,
                // which never delivers a single sample while a LiveKit call
                // is simultaneously active (confirmed via audioSeen=0 in
                // testing regardless of permission/timing/session count —
                // RPScreenRecorder's internal mic tap can't get access to
                // hardware LiveKit's WebRTC audio engine already owns).
                guard let args = call.arguments as? [String: Any],
                      let typedData = args["data"] as? FlutterStandardTypedData,
                      let sampleRate = args["sampleRate"] as? Int,
                      let channels = args["channels"] as? Int else {
                    result(nil)   // fire-and-forget from Dart's side regardless
                    return
                }
                let format = (args["format"] as? String) ?? "int16"
                self.handleIncomingAudioFrame(
                    data: typedData.data, sampleRate: sampleRate,
                    channels: channels, format: format
                )
                // Acknowledge immediately — the actual writer append happens
                // asynchronously on writerQueue. Dart doesn't need (and
                // shouldn't wait for) this to block the audio callback.
                result(nil)

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
    // MARK: - Audio-only recording (meeting recordings, quality "audio")
    // ─────────────────────────────────────────────────────────────────────────

    /// Starts the AVAssetWriter chunk loop with audio tracks only, without
    /// RPScreenRecorder: no screen-capture permission, no red pill. The mic
    /// PCM arrives through "sendAudioFrame" (LiveKit's own audio tap, see
    /// room.dart's _startLiveKitAudioTap) and anchors each chunk's session in
    /// handleIncomingAudioFrame. `recording` is true from here on, so a later
    /// startScreenCaptureService (a Share tap) answers true at once and the
    /// broadcast's video frames are simply dropped (no video input / adaptor).
    private func startAudioOnlyRecording() {
        guard !recording else { return }
        paused      = false
        stopping    = false
        videoWidth  = 0
        videoHeight = 0
        sweepStaleChunks()
        configureAudioSessionForRecording()
        recording = true
        startRecordingAudioObservers()
        updateExtensionWants()
        beginChunkWriter()
        armIfBroadcastAlreadyLive()
        NSLog("[REC] audio-only recording started — chunk #\(chunkIndex)")
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
        startRecordingAudioObservers()
        updateExtensionWants()

        rp.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self = self, self.recording, !self.stopping else { return }
            if let e = error { self.emitError(e.localizedDescription); return }
            // NOTE: do NOT gate this whole call on !isBroadcasting — audio
            // must keep flowing here even while a broadcast is active (see
            // processSampleFromRecorder's .video case for where video
            // actually gets suppressed during a broadcast).
            self.processSampleFromRecorder(sampleBuffer, type: bufferType)
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
                    // Synchronized for consistency with the other teardown
                    // sites — see beginChunkWriter's matching .sync.
                    self.systemAudioQueue.sync { self.systemAudioInput = nil }
                    self.pixelBufferAdaptor = nil
                    self.writerSessionStarted = false
                    self.stopRecordingAudioObservers()
                    self.updateExtensionWants()
                    self.releaseAudioSessionLock()
                    result(FlutterError(code: "RP_START_ERROR",
                                        message: e.localizedDescription, details: nil))
                    return
                }
                // ── Re-arm audio session AFTER startCapture completes ────────
                // GUARDED on !isBroadcasting — this is the actual root cause
                // of "shared video sound is fine for ~0.5s then very very
                // quiet": this 1-second one-shot timer is armed the moment
                // RPScreenRecorder starts, completely independent of when
                // screen sharing begins. The Flutter share flow
                // (room_screen_share.dart) taps "Share Screen" only ~300ms
                // after recording starts, so by the time this timer fires,
                // a broadcast is very often ALREADY LIVE and
                // configureAudioSessionForBroadcastShare() has already put
                // the session in non-ducking .videoRecording mode for it.
                // Without this guard, this call would unconditionally stomp
                // that back to the auto-ducking .videoChat mode mid-share.
                // The 0.15s reassert timer (startAudioSessionObserver) DOES
                // correct the category back afterward, but that's not
                // enough: iOS engages .duckOthers on the shared app's
                // rendered audio almost instantly, then only RELEASES the
                // duck over its own slow, multi-second fade envelope (see
                // configureAudioSessionForBroadcastShare's doc comment) —
                // so even one instant of the wrong mode, corrected 150ms
                // later, is enough to duck the shared audio and leave it
                // crawling back up for the rest of the chunk. That's
                // exactly "clear for a fraction of a second, then very
                // quiet." Never touch the session here while a broadcast is
                // active — the broadcast-share reassert timer alone owns
                // the session for the duration of the share.
                // FIX (2026-10-29): this used to be `guard !isBroadcasting
                // else { return }`, which also skipped beginChunkWriter() and
                // result(true) below — a recording started while a share was
                // already live never wrote a chunk and Dart's call never
                // returned. Only the session re-arm is skipped now.
                if !self.isBroadcasting {
                    self.configureAudioSessionForRecording()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self = self, self.recording, !self.isBroadcasting else { return }
                        self.configureAudioSessionForRecording()
                        NSLog("[REC] AVAudioSession: delayed re-arm applied")
                    }
                }

                // ── Start chunk writer NOW — RPScreenRecorder is delivering ──
                // The first video frame will anchor the AVAssetWriter session,
                // and the 5-second timer starts from this moment, not from
                // before startCapture was called.
                self.beginChunkWriter()
                self.armIfBroadcastAlreadyLive()
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
        // Cheap, one-line way to rule out "mic permission was never actually
        // granted" as the cause of audioSeen staying 0 — if permission is
        // .denied, RPScreenRecorder will happily keep recording video and
        // just never deliver .audioMic samples, with no error anywhere.
        let permissionStr: String
        switch session.recordPermission {
        case .granted:      permissionStr = "granted"
        case .denied:       permissionStr = "denied"
        case .undetermined: permissionStr = "undetermined"
        @unknown default:   permissionStr = "unknown"
        }
        NSLog("[REC] mic recordPermission=\(permissionStr) isInputAvailable=\(session.isInputAvailable)")

        // Go through RTCAudioSession's lock (not AVAudioSession directly) —
        // now that useManualAudio=true, this is how WebRTC's engine finds
        // out about our change instead of fighting it later. See the Audio
        // section of the top-of-file comment.
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        defer { rtcSession.unlockForConfiguration() }
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
            rtcSession.isAudioEnabled = true
            NSLog("[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active")
        } catch {
            NSLog("[REC] AVAudioSession configure error: \(error.localizedDescription)")
        }
    }

    // ── AVAudioSession management — screen-share/broadcast override ──────────
    //
    // ROOT CAUSE of "shared video sound is very quiet even after server-side
    // volume balancing": AVAudioSession.Mode .videoChat (like .voiceChat)
    // makes iOS AUTOMATICALLY apply its .duckOthers behavior to every OTHER
    // app's audio output — silently, regardless of whether .duckOthers is
    // in OUR OWN options array. This is a documented iOS quirk, not a bug in
    // our code: Apple's system audio mixer attenuates the shared app's
    // actual rendered output (e.g. a video playing in Safari) BEFORE
    // ReplayKit's broadcast extension ever captures it via .audioApp — so
    // no amount of server-side gain/loudnorm can fully recover it, because
    // the samples we receive are already quiet at the source, not just
    // quiet in the mix.
    //
    // Fix (same approach Teams/Zoom/Meet use): while a broadcast (screen
    // share) is actually active, switch the audio session to
    // .videoRecording mode instead of .videoChat. .videoRecording keeps
    // .playAndRecord + mixWithOthers + defaultToSpeaker + Bluetooth working
    // exactly the same, but — unlike .videoChat/.voiceChat — does NOT
    // implicitly force .duckOthers, so the shared app's audio plays (and
    // gets captured) at its natural, un-ducked volume.
    //
    // Trade-off: .videoRecording does not get the same hardware-assisted
    // acoustic echo cancellation / noise suppression tuning as .videoChat,
    // so mic pickup during a share may pick up slightly more room echo if
    // the teacher is near a speaker. This is the same trade-off Teams/Zoom/
    // Meet accept for "share sound" — avoiding it would mean the shared
    // content's audio stays silently ducked, which is strictly worse for a
    // recording where the shared content IS the primary audio.
    //
    // Called from handleBroadcastData (broadcast confirmed live → switch
    // to this) and from every broadcast-stop path (→ configureAudioSessionForRecording()
    // switches back to .videoChat for normal call-quality mic audio).

    private func configureAudioSessionForBroadcastShare() {
        let session = AVAudioSession.sharedInstance()

        // IMPORTANT: setCategory/setActive interrupt the underlying Core
        // Audio I/O even when the values being set are IDENTICAL to what's
        // already active — mic capture and the shared-app audio capture
        // both briefly glitch. That's fine for a one-off call, but this
        // function is now also polled every 0.5s by the reassert timer in
        // startAudioSessionObserver() to fight LiveKit's own internal
        // session management — polling that blindly reconfigured a LIVE
        // session constantly, which is what turned into audible clicking/
        // noise/static instead of clean audio. So: read the current state
        // first and only actually touch the session if it's genuinely
        // drifted away from non-ducking mode. Most polls should hit this
        // early return and do nothing.
        //
        // CAVEAT (see forceReconfigureAudioSessionForBroadcastShare below):
        // this check only looks at category/mode/options. It says nothing
        // about whether the session is actually ACTIVE. An interruption
        // (Siri, a call, another app's transient session) can deactivate
        // the session while leaving category/mode untouched — this guard
        // would then say "already correct" and skip reactivating, leaving
        // the shared app silently ducked. That path is handled separately
        // by the interruption observer calling the force variant below.
        // I5 (2026-10-29): voiceChat (LiveKit's earpiece preset) and
        // videoChat (its speaker preset, and ours) both keep the platform
        // echo canceller; anything else is drift worth correcting.
        // mixWithOthers stays required: without it, activating our session
        // would interrupt the app being shared (its video would pause).
        let alreadyCorrect =
            session.category == .playAndRecord &&
            (session.mode == .videoChat || session.mode == .voiceChat) &&
            session.categoryOptions.contains(.mixWithOthers)
        guard !alreadyCorrect else { return }
        applyBroadcastShareAudioSessionConfig(reason: "reassert/route-change")
    }

    /// Bypasses the alreadyCorrect early-return entirely. Only call this
    /// from a point where you have independent evidence (not just
    /// category/mode) that the session actually needs reactivating — e.g.
    /// AVAudioSession.interruptionNotification's .ended case, where
    /// category/mode can read "correct" even though the session itself
    /// went inactive. Calling this from the 0.15s poll timer would
    /// reintroduce the "audible clicking/static from constant reconfigure"
    /// regression the alreadyCorrect guard exists to prevent — don't wire
    /// it up there.
    private func forceReconfigureAudioSessionForBroadcastShare() {
        applyBroadcastShareAudioSessionConfig(reason: "interruption-ended (forced)")
    }

    private func applyBroadcastShareAudioSessionConfig(reason: String) {
        let session = AVAudioSession.sharedInstance()

        // Go through RTCAudioSession's lock, same as
        // configureAudioSessionForRecording(). With useManualAudio=true set
        // at launch, WebRTC's engine no longer reconfigures the session on
        // its own lifecycle events, so this switch to non-ducking mode
        // actually STAYS non-ducking for the rest of the share instead of
        // being silently reverted within roughly a second — which was the
        // actual root cause of "shared audio clear at first, then muted".
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        defer { rtcSession.unlockForConfiguration() }
        do {
            // I5 (2026-10-29): was .videoRecording, chosen so iOS would not
            // duck the shared app's sound. .videoRecording has no voice
            // processing, so together with the share-time echoCancellation:
            // false on the Dart side the students heard the teacher's speaker
            // through the mic (echo). Echo-free speech wins: keep .videoChat.
            // The shared app may now be ducked a little on the teacher's
            // speaker; viewers get its sound from ShareAppAudioMixer (mixed
            // in digitally, after the echo canceller), not through the air.
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,                          // keeps AEC + NS
                options: [.defaultToSpeaker,
                          .allowBluetooth,
                          .allowBluetoothA2DP,
                          .mixWithOthers]                  // coexist with the shared app's audio
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            rtcSession.isAudioEnabled = true
            audioReconfigCount += 1
            NSLog("[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers "
                  + "— active (broadcast share, echo cancellation kept) [reason: \(reason), "
                  + "count=\(audioReconfigCount)]")
        } catch {
            NSLog("[REC] AVAudioSession broadcast-share configure error "
                  + "[reason: \(reason)]: \(error.localizedDescription)")
        }
    }

    private func releaseAudioSessionLock() {
        // Called only on RPScreenRecorder stop or start failure.
        // Restore the session to LiveKit's preferred state so the live call
        // continues to work normally after recording ends.
        let session = AVAudioSession.sharedInstance()
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()
        defer { rtcSession.unlockForConfiguration() }
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker, .allowBluetooth,
                          .allowBluetoothA2DP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            rtcSession.isAudioEnabled = true
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
                // While a broadcast extension is active, VIDEO comes from
                // SampleHandler/processSampleFromBroadcast instead (it can
                // capture the whole device screen, not just this app's own
                // content) — suppress RPScreenRecorder's own video here to
                // avoid writing two competing video streams into the same
                // chunk. Audio is NOT suppressed here — see the .audioMic/
                // .audioApp case below, which intentionally has no such
                // guard, since SampleHandler never forwards audio at all
                // (see its header comment) and relies entirely on this path
                // continuing to supply it during a broadcast.
                guard !self.isBroadcasting else { return }

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
                    // Normally nothing is pending here (system audio only
                    // exists while isBroadcasting, and this path only runs
                    // when !isBroadcasting) — flushing is just a safety net
                    // for the downgrade-mid-chunk edge case.
                    self.systemAudioQueue.async { [weak self] in
                        self?.flushPendingSystemAudioFrames()
                    }
                }
                if self.videoInput?.isReadyForMoreMediaData == true {
                    self.videoInput?.append(sampleBuffer)
                }

            case .audioMic, .audioApp:
                // Counted BEFORE any guard below, on purpose — this tells us
                // definitively whether RPScreenRecorder is calling us with
                // audio at all, independent of whether writerSessionStarted
                // or the ordering guard below end up dropping it.
                self.audioSamplesSeenThisChunk += 1

                // Deliberately NOT gated on isBroadcasting — this is the
                // ONLY source of audio while a broadcast is active, since
                // SampleHandler.swift only ever forwards video. Suppressing
                // this during a broadcast (as a previous version of the
                // capture-handler guard used to do, by skipping
                // processSampleFromRecorder entirely) silently produced
                // video-only chunks with no audio track at all.
                //
                // I7 (2026-10-29): the first sample of ANY type starts the
                // chunk's session (it used to wait for a video frame, and
                // ReplayKit only sends video when the screen changes, so a
                // static screen lost seconds of audio at every chunk start).
                let firstPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                if !self.writerSessionStarted {
                    guard CMTIME_IS_VALID(firstPts) else { return }
                    writer.startSession(atSourceTime: firstPts)
                    self.writerSessionStarted = true
                    NSLog("[REC] writer session started (RP audio) at \(CMTimeGetSeconds(firstPts))s")
                    self.systemAudioQueue.async { [weak self] in
                        self?.flushPendingSystemAudioFrames()
                    }
                }

                // ── Why audio could disappear entirely ──────────────────
                // .audioMic and .audioApp are TWO INDEPENDENTLY-CLOCKED
                // sample streams, both funnelled into the SAME
                // AVAssetWriterInput track. AVAssetWriter requires strictly
                // increasing presentation timestamps per track — if a
                // sample from one stream arrives with a PTS at or before
                // the last sample WE appended (which may have come from the
                // OTHER stream), the writer silently rejects it. Because the
                // append() return value was never checked, that rejection
                // was invisible — and once it starts happening, most/all
                // subsequent samples on that track can be rejected the same
                // way, which is exactly what "no audio in the recording"
                // looks like with zero errors in the log.
                //
                // This guard makes the ordering explicit: skip (don't even
                // attempt to append) any sample that wouldn't be strictly
                // increasing, and log real append failures so any remaining
                // issue is visible instead of silent.
                let audioPts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                guard CMTIME_IS_VALID(audioPts) else { return }
                if let last = self.lastAudioPts, CMTimeCompare(audioPts, last) <= 0 {
                    return
                }
                self.lastAudioPts = audioPts

                if self.audioInput?.isReadyForMoreMediaData == true {
                    if self.audioInput?.append(sampleBuffer) == false {
                        NSLog("[REC] audio append FAILED (\(type == .audioMic ? "mic" : "app")) "
                              + "— writer status=\(writer.status.rawValue) error=\(String(describing: writer.error))")
                    } else {
                        self.audioSamplesAppendedThisChunk += 1
                    }
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

    // ── LiveKit PCM audio path ──────────────────────────────────────────────
    //
    // Replaces reliance on RPScreenRecorder's .audioMic/.audioApp, which
    // never fires while a LiveKit call is active (see the sendAudioFrame
    // case's comment). Frames arrive from Dart via LocalAudioTrack's
    // addAudioRenderer(), with no per-frame timestamp of their own — LiveKit's
    // PCMAudioFrame only carries {data, format, channels, sampleRate}. We
    // timestamp on arrival using the same host-time clock domain the video
    // writer's session already runs on (CMClockGetHostTimeClock()), which is
    // shared across processes/threads on the device. Method-channel dispatch
    // latency is small enough (single-digit ms) that "time of arrival" is a
    // fine proxy for true capture time — audio/video sync doesn't need
    // frame-perfect alignment, just consistent monotonic ordering, which the
    // existing lastAudioPts guard already enforces.
    //
    // I14 (2026-10-29): arrival time is NOT used per frame any more. After a
    // Dart round trip per 10 ms frame, arrival jitter made neighbouring frames
    // non-monotonic (dropped by the guard) or overlapping. The PTS now comes
    // from a sample clock: anchor (host time of the first frame) + samples
    // written / sample rate. It re-anchors on a format change or when it drifts
    // more than 0.3 s from arrival time (frames lost on the Dart side). The
    // clock is continuous across chunks, so chunk N+1 starts exactly where N
    // ended. Larger frames are fine (frame count comes from the byte count):
    // see docs/live/ios_share_wiring.md for batching ~100 ms per call in Dart.
    // I7: the first mic frame may start the chunk's session in every mode.
    // I12: a format change mid-chunk asks for a new chunk instead of feeding
    // a mismatched buffer to an input that locked onto the old format.
    private func handleIncomingAudioFrame(data: Data, sampleRate: Int, channels: Int, format: String) {
        let arrival = CMClockGetTime(CMClockGetHostTimeClock())
        writerQueue.async { [weak self] in
            guard let self = self,
                  sampleRate > 0, channels > 0,
                  let writer = self.assetWriter,
                  writer.status == .writing,
                  self.audioInput?.isReadyForMoreMediaData == true else { return }

            self.audioSamplesSeenThisChunk += 1

            // I12: one mic format per writer.
            let writerId = ObjectIdentifier(writer)
            if let locked = self.micLockedFormat, locked.writer == writerId {
                if locked.sampleRate != sampleRate || locked.channels != channels || locked.format != format {
                    NSLog("[REC] mic format changed mid-chunk (\(locked.sampleRate)/\(locked.channels)/\(locked.format) "
                          + "→ \(sampleRate)/\(channels)/\(format)) — rotating chunk")
                    DispatchQueue.main.async { [weak self] in
                        self?.requestChunkRotation(reason: "mic format change", evenIfEmpty: true)
                    }
                    return
                }
            } else {
                self.micLockedFormat = (writerId, sampleRate, channels, format)
            }

            // I14: sample clock.
            let bytesPerFrame = (format == "float32" ? 4 : 2) * channels
            let frameCount = Int64(data.count / max(1, bytesPerFrame))
            guard frameCount > 0 else { return }
            var pts: CMTime
            if let anchor = self.micClockAnchor, self.micClockRate == sampleRate {
                pts = CMTimeAdd(anchor, CMTimeMake(value: self.micClockSamples, timescale: Int32(sampleRate)))
                let drift = abs(CMTimeGetSeconds(CMTimeSubtract(arrival, pts)))
                if drift > 0.3 {
                    self.micClockAnchor = arrival
                    self.micClockSamples = 0
                    pts = arrival
                }
            } else {
                self.micClockAnchor = arrival
                self.micClockRate = sampleRate
                self.micClockSamples = 0
                pts = arrival
            }

            guard let sampleBuffer = self.makeAudioSampleBuffer(
                data: data, sampleRate: sampleRate, channels: channels, format: format,
                presentationTime: pts
            ) else { return }
            self.micClockSamples += frameCount

            if !self.writerSessionStarted {
                // First sample of the chunk (any mode) anchors the session —
                // never .zero, see processSampleFromRecorder.
                writer.startSession(atSourceTime: pts)
                self.writerSessionStarted = true
                NSLog("[REC] writer session started (mic) at \(CMTimeGetSeconds(pts))s")
                self.systemAudioQueue.async { [weak self] in
                    self?.flushPendingSystemAudioFrames()
                }
            }
            // Same monotonic-ordering guard as the RPScreenRecorder audio
            // path — protects against this new source and any residual
            // RPScreenRecorder audio (should there ever be any) racing.
            if let last = self.lastAudioPts, CMTimeCompare(pts, last) <= 0 { return }
            self.lastAudioPts = pts

            if self.audioInput?.append(sampleBuffer) == false {
                NSLog("[REC] audio append FAILED (livekit) — writer status=\(writer.status.rawValue) "
                      + "error=\(String(describing: writer.error))")
            } else {
                self.audioSamplesAppendedThisChunk += 1
            }
        }
    }

    /// Builds a CMSampleBuffer of raw interleaved PCM from the bytes LiveKit's
    /// PCMAudioFrame hands us over the method channel. `format` is "int16" or
    /// "float32" (matches AVAudioPCMBuffer.serializeAsBytes()'s "commonFormat"
    /// on the plugin's own native side).
    private func makeAudioSampleBuffer(
        data: Data, sampleRate: Int, channels: Int, format: String, ptsNs: UInt64? = nil,
        presentationTime: CMTime? = nil
    ) -> CMSampleBuffer? {
        let isFloat = (format == "float32")
        let bytesPerSample = isFloat ? 4 : 2
        let bytesPerFrame  = bytesPerSample * channels
        guard bytesPerFrame > 0 else { return nil }
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else { return nil }

        var asbd = AudioStreamBasicDescription(
            mSampleRate:       Float64(sampleRate),
            mFormatID:         kAudioFormatLinearPCM,
            mFormatFlags:      isFloat
                ? (kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked)
                : (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked),
            mBytesPerPacket:   UInt32(bytesPerFrame),
            mFramesPerPacket:  1,
            mBytesPerFrame:    UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel:   UInt32(bytesPerSample * 8),
            mReserved:         0
        )

        var formatDesc: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &formatDesc
        ) == noErr, let fmt = formatDesc else { return nil }

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: data.count, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0,
            dataLength: data.count, flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let bb = blockBuffer else { return nil }

        let copyStatus = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OSStatus in
            guard let base = raw.baseAddress else { return kCMBlockBufferBlockAllocationFailedErr }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: bb, offsetIntoDestination: 0, dataLength: data.count
            )
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        // LiveKit mic frames (ptsNs == nil) have no per-frame timestamp of
        // their own — timestamp on arrival using the host clock (see the
        // header comment above). Broadcast system-audio frames DO carry a
        // real ptsNs from the extension's own CMSampleBufferGetPresentationTimeStamp
        // (same host-time clock domain, shared across processes on-device),
        // matching how processSampleFromBroadcast times its video frames —
        // using arrival time for these instead would drift out of sync with
        // the broadcast video track over a multi-second chunk.
        let pts: CMTime
        if let given = presentationTime {
            // Mic frames: the sample clock of handleIncomingAudioFrame (I14).
            pts = given
        } else if let ns = ptsNs {
            // Microsecond precision, not millisecond: audio buffers can
            // arrive every ~10-25ms, so rounding to whole milliseconds
            // risks two consecutive buffers landing on the identical
            // timestamp — which the strictly-increasing-PTS guard in
            // processSystemAudioFromBroadcast would then treat as a
            // duplicate and silently drop, forever, since it never
            // increases again relative to a "last" that was rounded the
            // same way. Video frames (using this same helper's PTS via
            // processSampleFromBroadcast) don't share this risk since they
            // arrive far less often, so this only needed tightening here.
            pts = CMTimeMake(value: Int64(ns / 1_000), timescale: 1_000_000)
        } else {
            pts = CMClockGetTime(CMClockGetHostTimeClock())
        }
        // With ONE timing entry for many samples CoreMedia applies `duration`
        // to EACH sample, so it is one PCM frame (it used to be the whole
        // buffer's length, i.e. frameCount times too long).
        var timing = CMSampleTimingInfo(
            duration: CMTimeMake(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleSize = bytesPerFrame

        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: bb, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: fmt,
            sampleCount: CMItemCount(frameCount), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }

        return sampleBuffer
    }

    private func processSampleFromBroadcast(jpegData: Data, ptsNs: UInt64) {
        writerQueue.async { [weak self] in
            guard let self = self else { return }
            // Counted BEFORE the guards below so the log can distinguish
            // "frames never reached this function" (seen stays 0) from
            // "frames arrived but got rejected by a guard here" (seen>0,
            // appended stays 0) — see the property's doc comment.
            self.videoBroadcastSeenThisChunk += 1

            guard let writer = self.assetWriter,
                  writer.status == .writing,
                  let adaptor = self.pixelBufferAdaptor,
                  let pool = adaptor.pixelBufferPool,
                  self.videoInput?.isReadyForMoreMediaData == true else { return }

            // Always draw into a buffer pulled from the adaptor's OWN pool,
            // sized to this chunk's fixed geometry — see jpegToPixelBuffer's
            // header comment for why this (not the JPEG's own dimensions)
            // is what eliminates the intermittent append failures that were
            // silently dropping whole chunks (e.g. chunk #3 in the logs).
            guard self.chunkVideoWidth > 0, self.chunkVideoHeight > 0,
                  let pixelBuffer = self.jpegToPixelBuffer(
                      jpegData, pool: pool,
                      targetWidth: self.chunkVideoWidth,
                      targetHeight: self.chunkVideoHeight
                  ) else { return }

            let pts = CMTimeMake(value: Int64(ptsNs / 1_000_000),
                                  timescale: 1_000)   // millisecond timescale

            if !self.writerSessionStarted {
                writer.startSession(atSourceTime: pts)
                self.writerSessionStarted = true
                NSLog("[REC] writer session (broadcast) started at \(CMTimeGetSeconds(pts))s")
                // Replay anything system-audio that arrived just before the
                // session went live (see processSystemAudioFromBroadcast).
                self.systemAudioQueue.async { [weak self] in
                    self?.flushPendingSystemAudioFrames()
                }
            }

            // Same monotonic-PTS protection as audio (see lastAudioPts) —
            // guards against a stray out-of-order broadcast frame being
            // silently rejected by the writer.
            if let last = self.lastBroadcastVideoPts, CMTimeCompare(pts, last) <= 0 {
                return
            }
            self.lastBroadcastVideoPts = pts

            // append(_:withPresentationTime:) is the adaptor-based API and is
            // the only supported way to feed decoded CVPixelBuffers into an
            // AVAssetWriterInput — see jpegToPixelBuffer's header comment for
            // why the old approach (manually building a CMSampleBuffer and
            // calling videoInput.append(sampleBuffer) directly) permanently
            // failed the writer as soon as broadcast frames started arriving.
            // The adaptor also derives each frame's duration itself from the
            // delta between consecutive presentation times, so there's no
            // need to hand-compute a duration/CMSampleTimingInfo here.
            if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                NSLog("[REC] broadcast frame append FAILED — writer status=\(writer.status.rawValue) error=\(String(describing: writer.error))")
            } else {
                self.videoBroadcastAppendedThisChunk += 1
            }
        }
    }

    /// Decode a JPEG Data into a CVPixelBuffer suitable for the broadcast
    /// pixel-buffer adaptor.
    //
    // ROOT CAUSE #1 (fixed) OF "records fine, then dies silently the moment
    // Share Screen starts": this buffer used to be created with plain
    // CVPixelBufferCreate + kCVPixelFormatType_32ARGB and NO
    // kCVPixelBufferIOSurfacePropertiesKey. That produces a pixel buffer
    // that is NOT IOSurface-backed.
    //
    // AVAssetWriter's H.264 encode session runs out-of-process (mediaserverd)
    // and can only accept pixel buffers across that XPC boundary if they are
    // IOSurface-backed — a plain malloc'd CVPixelBuffer cannot be shared that
    // way. Handing one to the writer doesn't fail loudly; the encoder XPC
    // call fails deep inside CoreMedia, which is exactly the
    // "FigSampleBufferSerialization ... err=-19642" seen in the logs, and
    // that failure flips the WHOLE AVAssetWriter to .failed.
    //
    // ROOT CAUSE #2 (fixed here) OF "an occasional chunk (e.g. #3) just
    // disappears, and it's always around a camera-open-while-sharing
    // moment": this function used to size the CVPixelBuffer to whatever the
    // JPEG's OWN width/height happened to be, frame by frame. But the
    // AVAssetWriterInputPixelBufferAdaptor created in beginChunkWriter is
    // configured with a FIXED pool geometry (kCVPixelBufferWidthKey/
    // HeightKey = the chunk's w×h). The moment ReplayKit's broadcast frame
    // briefly reports different pixel dimensions than that fixed pool size
    // — which is exactly what can happen for a frame or two when a camera
    // overlay/PiP appears on top of the shared screen, or on a rotation —
    // adaptor.append() fails with an intermittent
    // "AVFoundationErrorDomain -11800 / NSOSStatusErrorDomain -16364" error,
    // which (same as root cause #1) flips the writer to .failed and the
    // whole in-flight chunk is lost.
    //
    // Fix: ALWAYS allocate the pixel buffer from the adaptor's own
    // `pixelBufferPool` (guaranteeing the exact pool geometry + IOSurface
    // backing every time, regardless of what's on screen) and aspect-fit
    // the decoded JPEG into that fixed canvas (letterboxed with black bars
    // if the source frame's aspect ratio doesn't match) instead of ever
    // creating a differently-sized buffer.
    private func jpegToPixelBuffer(
        _ data: Data,
        pool: CVPixelBufferPool,
        targetWidth: Int,
        targetHeight: Int
    ) -> CVPixelBuffer? {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else { return nil }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
                == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let ctx = CGContext(
            data:             CVPixelBufferGetBaseAddress(pb),
            width:            targetWidth,
            height:           targetHeight,
            bitsPerComponent: 8,
            bytesPerRow:      CVPixelBufferGetBytesPerRow(pb),
            space:            CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Clear to black first — if the source aspect ratio doesn't exactly
        // match the fixed canvas we'll letterbox rather than stretch, and
        // the letterbox bars must not be leftover pool-buffer garbage.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        // Aspect-fit + center the decoded frame into the fixed canvas so the
        // OUTPUT pixel buffer is always exactly targetWidth×targetHeight —
        // the pool's fixed geometry — no matter what size ReplayKit's frame
        // (or the camera overlay on top of it) actually was.
        let srcW = CGFloat(cgImage.width)
        let srcH = CGFloat(cgImage.height)
        if srcW > 0, srcH > 0 {
            let scale  = min(CGFloat(targetWidth) / srcW, CGFloat(targetHeight) / srcH)
            let drawW  = srcW * scale
            let drawH  = srcH * scale
            let originX = (CGFloat(targetWidth)  - drawW) / 2
            let originY = (CGFloat(targetHeight) - drawH) / 2
            ctx.draw(cgImage, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
        }

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
        // Clamp to 720p on the short side to keep files manageable — or to the
        // picked quality of a meeting recording (maxHeight is its longer side).
        let maxShort = maxHeight > 0 ? max(144, min(maxHeight * 9 / 16, 2160)) : 720
        let shortSide = min(rawW, rawH)
        let ratio  = shortSide > maxShort ? CGFloat(maxShort) / CGFloat(shortSide) : 1.0
        let w      = (Int(CGFloat(rawW) * ratio) / 2) * 2   // must be even
        let h      = (Int(CGFloat(rawH) * ratio) / 2) * 2

        // ── Bitrate ────────────────────────────────────────────────────────────
        // Broadcast-sourced chunks (Share Screen, especially with a camera
        // overlay on top of it) come from JPEG-decoded frames that are
        // already lossy — re-encoding them at the same 4 Mbps used for
        // RPScreenRecorder's own crisp, native-resolution frames spends a
        // lot of bits re-compressing JPEG blocking artifacts for no real
        // quality gain, which is why these chunks were coming out 5-6×
        // larger (e.g. ~2.6 MB per 5 s vs ~400 KB) than the in-app-only
        // chunks. Use a meaningfully lower bitrate whenever the chunk being
        // created is (or will be) a broadcast chunk.
        let isBroadcastChunk = isBroadcasting
        let defaultBitrate = isBroadcastChunk ? 1_800_000 : 4_000_000   // bps
        let bitrate = videoBitrate > 0 ? min(videoBitrate, defaultBitrate) : defaultBitrate

        // Audio-only: no video track at all — the chunk holds the two audio
        // tracks below and its session is anchored by the first audio sample
        // (handleIncomingAudioFrame). videoInput / pixelBufferAdaptor stay nil,
        // which is what makes every video append path drop its frames.
        var vi: AVAssetWriterInput? = nil
        if audioOnly {
            pixelBufferAdaptor = nil
        } else {
            let vSettings: [String: Any] = [
                AVVideoCodecKey:  AVVideoCodecType.h264,
                AVVideoWidthKey:  w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey:       bitrate,
                    AVVideoMaxKeyFrameIntervalKey:  60,
                    AVVideoProfileLevelKey:         AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoAllowFrameReorderingKey: false,
                ],
            ]
            let v = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
            v.expectsMediaDataInRealTime = true
            vi = v

            // Adaptor used by the broadcast-extension path (processSampleFromBroadcast)
            // to feed decoded JPEG frames in as CVPixelBuffers. Must be created here,
            // once per chunk/writer, same as videoInput — see jpegToPixelBuffer's
            // header comment for why appending through this adaptor (vs. manually
            // building a CMSampleBuffer) is required for the writer to survive a
            // Share Screen broadcast.
            let sourcePixelAttrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String:   kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String:              w,
                kCVPixelBufferHeightKey as String:             h,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            ]
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput:            v,
                sourcePixelBufferAttributes: sourcePixelAttrs
            )
        }
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

        // Second, independent audio track for the shared app's own audio —
        // only ever populated while isBroadcasting is true, but always
        // created so a broadcast that starts mid-chunk (rotating in) never
        // races the writer's `.add()` calls, which must all happen before
        // startWriting() below.
        // ── UNVERIFIED HYPOTHESIS FIX (2026-07-29) ──────────────────────────
        // System audio (.audioApp) is very often genuine stereo from
        // ReplayKit, but was previously forced through the same mono
        // `aSettings` as the mic track. This declares systemAudioInput's
        // output as stereo instead, in case an implicit stereo→mono
        // downmix during AVAssetWriter's internal conversion was producing
        // the static/noise reported in the 2026-07-29 investigation.
        // NOT CONFIRMED as the root cause — the raw pre-mix .audioApp
        // track was already noisy when extracted directly from the
        // AVAssetWriter chunk, which was never isolated further down to
        // capture vs. reconstruction before this was applied. If this
        // does not resolve the issue, revert to reusing `aSettings` and
        // continue the raw-PCM bisection (see writeAudioSample's TEMP
        // DEBUG block in SampleHandler.swift) instead of guessing further.
        let saiSettings: [String: Any] = [
            AVFormatIDKey:         kAudioFormatMPEG4AAC,
            AVSampleRateKey:       44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey:   128_000,
        ]
        let sai = AVAssetWriterInput(mediaType: .audio, outputSettings: saiSettings)
        sai.expectsMediaDataInRealTime = true
        // Publish through systemAudioQueue rather than assigning directly
        // here on the main thread. systemAudioInput is read/appended-to
        // exclusively on systemAudioQueue (see its declaration comment),
        // but until this fix beginChunkWriter (main thread) and
        // finaliseChunk (also not systemAudioQueue) both mutated it with
        // zero synchronization against that queue — a genuine data race,
        // not just a logical timing gap. That race is the actual cause of
        // "system-audio dropped — systemAudioInput is nil" firing WHILE
        // the previous chunk's writer/session were still reported live:
        // processSystemAudioFromBroadcast's guard reads self.assetWriter/
        // writerSessionStarted, decides the old chunk is still active, and
        // calls appendSystemAudioSample — which can then observe a
        // just-nilled systemAudioInput if finaliseChunk's teardown lands
        // on the main thread in between, since nothing serialized the two.
        // Using .sync here keeps ordering identical to before (this still
        // completes before writer.add(sai)/startWriting() below run) while
        // guaranteeing systemAudioQueue never observes a torn/mid-write
        // reference.
        systemAudioQueue.sync { self.systemAudioInput = sai }
        systemAudioQueue.sync { self.systemAudioLockedFormat = nil }

        if let vi = vi { writer.add(vi) }
        writer.add(ai)
        writer.add(sai)
        writer.startWriting()
        // ── Do NOT call startSession here ─────────────────────────────────────
        // Session is started in processSampleFromRecorder/Broadcast on the
        // first video frame using its actual PTS.  Starting at .zero causes
        // every subsequent real frame (which has pts > 0) to be treated as
        // "before the session" and silently dropped → black video track.
        writerSessionStarted = false
        // Fresh chunk = fresh writer/track = fresh timeline. The previous
        // chunk's last audio PTS is not a valid baseline for this one.
        lastAudioPts = nil
        lastSystemAudioPts = nil
        // Fresh chunk = fresh broadcast video timeline too.
        lastBroadcastVideoPts = nil
        // Anything still buffered from the previous chunk belongs to that
        // chunk's (now-finalising) writer/session, not this new one — its
        // timestamps would fall before this chunk's session start and just
        // fail to append anyway. Drop it rather than let it leak forward.
        systemAudioQueue.async { [weak self] in
            self?.pendingSystemAudioFrames.removeAll()
            self?.systemAudioBackpressured = false
        }
        // Record the exact geometry this chunk's pixelBufferAdaptor pool was
        // configured with, so processSampleFromBroadcast can always draw
        // decoded JPEG frames into a buffer of this exact size (see
        // jpegToPixelBuffer's header comment).
        chunkVideoWidth  = audioOnly ? 0 : w
        chunkVideoHeight = audioOnly ? 0 : h

        NSLog("[REC] beginChunkWriter: chunk #\(chunkIndex) \(audioOnly ? "audio-only" : "\(w)×\(h)")")
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

        // ── Why chunk #0 was always the one that went missing ──────────────────
        // The chunk timer's 5s countdown starts the instant beginChunkWriter()
        // runs — NOT from whenever the first real frame actually arrives (see
        // beginChunkWriter's own comment on why startSession can't just use
        // .zero). At the very start of a session, RPScreenRecorder and
        // LiveKit's own camera capture are handing the capture pipeline back
        // and forth (this is exactly what the "FigCaptureSourceRemote ...
        // err=-17281" / "Stop video capturer" lines at the very top of every
        // session's log are — a normal but non-instant handoff). If that
        // handoff isn't done by the time this 5s timer fires, chunk #0's
        // writer never received a single frame — writerSessionStarted is
        // still false — and finaliseChunk's own "no frames yet" guard
        // silently DELETES it and reports nothing to upload. Because this
        // code used to rotate unconditionally, chunkIndex still advanced to
        // 1 and a brand-new chunk began right as real frames were *finally*
        // about to start flowing — so the first ~5 real seconds of the
        // session were thrown away every single time, deterministically.
        //
        // Fix: if this chunk never got its first real frame, DON'T finalize/
        // rotate it away — keep the SAME writer open and just give it more
        // time. There is nothing to lose by waiting (an unstarted writer has
        // no content to lose), and this is what actually preserves those
        // first few seconds once real frames do arrive.
        guard writerSessionStarted else {
            NSLog("[REC] rotateChunk: chunk #\(chunkIndex) has received no frames yet "
                  + "— extending its window instead of rotating")
            scheduleChunkTimer()
            return
        }

        // I7: double-buffered — finaliseChunk opens writer N+1 synchronously
        // (right after detaching writer N), then finishes N in the
        // background. Before, N+1 was only created after N's finishWriting
        // and upload hand-off, and every sample of that gap was dropped.
        finaliseChunk(isFinal: false, openNext: true) { _ in }
    }

    /// Starts a new chunk now (I8 / I12: audio interruption ended, input
    /// route or mic format changed, media services reset). Debounced to one
    /// per second. `evenIfEmpty`: also replace a writer that has no session
    /// yet (it may be bound to the old format / dead media services).
    private func requestChunkRotation(reason: String, evenIfEmpty: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.requestChunkRotation(reason: reason, evenIfEmpty: evenIfEmpty)
            }
            return
        }
        guard recording, !stopping, !paused, assetWriter != nil else { return }
        guard writerSessionStarted || evenIfEmpty else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastForcedRotation >= 1.0 else { return }
        lastForcedRotation = now
        NSLog("[REC] forced chunk rotation: \(reason)")
        chunkTimer?.invalidate()
        chunkTimer = nil
        finaliseChunk(isFinal: false, openNext: true) { _ in }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Pause / Resume
    // ─────────────────────────────────────────────────────────────────────────

    private func pauseRecording(result: @escaping FlutterResult) {
        guard recording, !stopping, !paused else { result(nil); return }
        NSLog("[REC] pauseRecording: finalising chunk #\(chunkIndex)")
        chunkTimer?.invalidate(); chunkTimer = nil
        paused = true
        // finaliseChunk detaches the writer synchronously. The index is
        // advanced right away too (2026-10-29): advancing it — and nil-ing
        // the writer again — in the completion could hit the NEXT writer when
        // resumeRecording came first (same index → its file deleted, or the
        // new writer dropped).
        finaliseChunk(isFinal: false) { [weak self] _ in
            self?.emitEvent(["event": "recordingPaused"])
            result(nil)
        }
        chunkIndex += 1
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
        // NOTE: isBroadcasting is deliberately NOT cleared here — see the
        // same reasoning in stopBroadcastShare above. It's cleared inside
        // finaliseChunk's completion callback below instead, strictly after
        // the (possibly still-broadcast-sourced) writer has actually been
        // nil'd out, so RPScreenRecorder's video can't resume writing into
        // it first. This matters here too: ending the session WHILE a share
        // is still active goes through this exact path.
        removeDarwinListeners()       // also clears the ext_wants_* markers
        stopRecordingAudioObservers()
        endBgTask()

        // ── Why we hold result open until the upload completes ────────────────
        // On iOS there is no ForegroundService — once result(nil) fires, Dart
        // calls widget.onEnd() which tears down the room, backgrounds the app,
        // and may suspend the process. Any in-flight URLSession.default task
        // is killed silently on suspension. So we must NOT call result(nil)
        // until the final chunk has actually landed on the server.
        //
        // ── Why THIS chunk's own isFinal flag is not trusted alone ─────────────
        // If stopRecording() lands at almost the same instant as a chunk-timer
        // rotation (rotateChunk), finaliseChunk() here can find assetWriter/
        // videoInput/audioInput already nil — rotateChunk's own finaliseChunk
        // call nils them synchronously the moment IT runs, well before its
        // async finishWriting/upload chain completes. In that case THIS call
        // has nothing to finalize, so `uploadQueued` comes back false and the
        // actual last content-bearing chunk ends up uploaded by the ROTATION
        // with isFinal=false instead of true. No recorded content is lost —
        // but nothing ever tells the server "that was the last one", so
        // assembly would otherwise sit waiting on the server's slow idle
        // watchdog (up to CHUNK_IDLE_TIMEOUT) instead of running immediately,
        // and could even lose the race against the app being backgrounded/
        // suspended right after this call returns.
        //
        // Fix: regardless of which branch fires, ALWAYS follow up with an
        // explicit "finalize ping" (see uploadFinalizePingAsync) once
        // RPScreenRecorder has actually stopped. It's enqueued through the
        // same serial upload queue as every real chunk, so it's guaranteed
        // to run strictly after any chunk from an in-flight rotation has
        // fully finished uploading — the server already has every byte on
        // disk by the time the ping tells it to assemble.
        finaliseChunk(isFinal: isFinal) { [weak self] _ in
            guard let self = self else { result(nil); return }
            self.isBroadcasting = false
            // If the whole session ends while a broadcast was still active,
            // don't leave the audio session parked in the non-ducking
            // .videoRecording mode for the rest of the app's lifetime — see
            // configureAudioSessionForBroadcastShare's doc comment.
            self.configureAudioSessionForRecording()
            self.stopCaptureThenSignal(result: result)
        }
    }

    /// Called after finaliseChunk completes. Stops RPScreenRecorder, then
    /// ALWAYS enqueues an explicit finalize ping and waits for it (see
    /// uploadFinalizePingAsync) before firing `result`.
    private var stopResult: FlutterResult?

    private func stopCaptureThenSignal(result: @escaping FlutterResult) {
        stopResult = result
        if audioOnly {
            // No RPScreenRecorder was ever started — straight to the ping.
            stopping = false
            NSLog("[REC] audio-only stop — queuing finalize ping")
            enqueueUpload { [weak self] in self?.uploadFinalizePingAsync() }
            return
        }
        RPScreenRecorder.shared().stopCapture { [weak self] error in
            if let e = error { NSLog("[REC] stopCapture: \(e.localizedDescription)") }
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.stopping = false
                NSLog("[REC] stopCapture done — queuing finalize ping")
                // Enqueued (not called directly) so it strictly follows any
                // real chunk upload already ahead of it in the queue.
                self.enqueueUpload { self.uploadFinalizePingAsync() }
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Chunk finalisation & upload
    // ─────────────────────────────────────────────────────────────────────────

    /// `openNext` (I7): open the NEXT chunk's writer right after this one is
    /// detached and before it is finished, so no sample falls into a gap.
    /// Main thread. Only when still recording, not stopping and not paused.
    private func finaliseChunk(isFinal: Bool, openNext: Bool = false,
                               completion: @escaping (_ uploadQueued: Bool) -> Void) {
        // Opens a replacement writer; `advance` = this chunk produced a file.
        func openNextWriter(advance: Bool) {
            guard openNext, recording, !stopping, !paused else { return }
            if advance { chunkIndex += 1 }
            beginChunkWriter()
        }
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
        // videoInput is nil for an audio-only recording (beginChunkWriter) —
        // optional here, same as systemAudioInput below.
        let vi = videoInput
        guard let writer  = assetWriter,
              let ai      = audioInput,
              let fileURL = currentFile else {
            DispatchQueue.main.async { [weak self] in
                // No writer — fire stopResult if this is the stop path.
                if let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                completion(false)
            }
            return
        }
        // Captured as a local separately from the guard above (not required)
        // — systemAudioInput is always created in beginChunkWriter alongside
        // audioInput, but treating it as non-critical here means a future
        // code path that skips creating it can never break chunk finalisation.
        let sai = systemAudioInput
        guard writer.status == .writing else {
            NSLog("[REC] finaliseChunk skipped (writer status=\(writer.status.rawValue))")
            assetWriter = nil; videoInput = nil; audioInput = nil
            // See beginChunkWriter's matching .sync — this teardown path
            // must publish through systemAudioQueue too, or systemAudioQueue
            // can observe a torn/racing reference against a concurrent
            // append.
            systemAudioQueue.sync { self.systemAudioInput = nil }
            pixelBufferAdaptor = nil
            currentFile = nil; writerSessionStarted = false
            // A failed writer (e.g. media services reset) is replaced under
            // the same index — its partial file is not uploadable.
            openNextWriter(advance: false)
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
            // See beginChunkWriter's matching .sync — same reasoning.
            systemAudioQueue.sync { self.systemAudioInput = nil }
            pixelBufferAdaptor = nil
            currentFile = nil; writerSessionStarted = false
            try? FileManager.default.removeItem(at: fileURL)
            openNextWriter(advance: false)
            DispatchQueue.main.async { [weak self] in
                if let r = self?.stopResult { self?.stopResult = nil; r(nil) }
                completion(false)
            }
            return
        }
        assetWriter = nil; videoInput = nil; audioInput = nil
        // Publish through systemAudioQueue — this is the hot-path teardown
        // that runs on EVERY chunk rotation during a screen share (unlike
        // the two early-return branches above, which only fire on error
        // paths). It's this specific assignment racing against
        // processSystemAudioFromBroadcast's guard-then-append on
        // systemAudioQueue that produced "system-audio dropped —
        // systemAudioInput is nil" while the previous chunk's writer was
        // still reported as live. See beginChunkWriter's matching .sync
        // for the other half of this fix.
        systemAudioQueue.sync { self.systemAudioInput = nil }
        pixelBufferAdaptor = nil
        currentFile = nil; writerSessionStarted = false
        let idx = chunkIndex
        // Snapshot then reset — see the properties' declaration for why these
        // exist. Must be captured now (not read later) since the NEXT
        // chunk's beginChunkWriter can start incrementing them again before
        // this async block below even runs.
        let audioSeen     = audioSamplesSeenThisChunk
        let audioAppended = audioSamplesAppendedThisChunk
        let sysAudioSeen     = sysAudioSamplesSeenThisChunk
        let sysAudioAppended = sysAudioSamplesAppendedThisChunk
        let sysAudioPeak     = sysAudioPeakThisChunk
        let sysAudioRms: Float = sysAudioRmsSampleCountThisChunk > 0
            ? Float(sqrt(sysAudioSquareSumThisChunk / Double(sysAudioRmsSampleCountThisChunk)))
            : 0.0
        let videoBroadcastSeen     = videoBroadcastSeenThisChunk
        let videoBroadcastAppended = videoBroadcastAppendedThisChunk
        audioSamplesSeenThisChunk     = 0
        audioSamplesAppendedThisChunk = 0
        sysAudioSamplesSeenThisChunk     = 0
        sysAudioSamplesAppendedThisChunk = 0
        sysAudioPeakThisChunk = 0.0
        sysAudioSquareSumThisChunk = 0.0
        sysAudioRmsSampleCountThisChunk = 0
        videoBroadcastSeenThisChunk     = 0
        videoBroadcastAppendedThisChunk = 0
        // Where this chunk goes, captured now (a pending retry may outlive
        // the session's settings).
        let target = UploadTarget(url: uploadUrl, token: authToken, audioOnly: audioOnly, epoch: epoch)
        // I7: writer N+1 exists before writer N is finished below.
        openNextWriter(advance: true)
        writerQueue.async { [weak self] in
            vi?.markAsFinished()
            ai.markAsFinished()
            sai?.markAsFinished()
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
                // audioSeen=0 for every chunk in a session ⇒ RPScreenRecorder
                // isn't delivering audio samples at all (permission/session
                // issue upstream of the writer). audioSeen>0 but
                // audioAppended much lower ⇒ samples are arriving but being
                // dropped by the ordering guard above. Both > 0 but the
                // final assembled video still has no sound ⇒ look at the
                // server's ffmpeg concat/transcode step instead.
                //
                // sysAudioPeak is the critical one for "shared video sound
                // is very quiet/missing": sysAudioSeen>0 with sysAudioPeak
                // ≈ 0.0000 for the WHOLE recording means ReplayKit handed
                // us real sample-count but literally silent/zeroed PCM for
                // this specific shared app — a ReplayKit-level limitation,
                // not fixable via audio-session/gain changes. A non-trivial
                // sysAudioPeak (> ~0.02) proves real signal IS arriving.
                //
                // sysAudioRms catches what peak alone can't: ducking
                // oscillation. A chunk that's mostly ducked but briefly
                // un-ducked (e.g. right when our config wins a race against
                // WebRTC's own session handling) can still show a healthy
                // peak from that one brief window, while the RMS stays low
                // because most of the chunk really was quiet. peak high +
                // rms low ⇒ suspect ducking is still slipping through
                // somewhere; peak and rms both high ⇒ genuinely clear audio
                // for the whole chunk.
                NSLog("[REC] finalised chunk #\(idx) (\(size)B isFinal=\(isFinal) "
                      + "audioSeen=\(audioSeen) audioAppended=\(audioAppended) "
                      + "sysAudioSeen=\(sysAudioSeen) sysAudioAppended=\(sysAudioAppended) "
                      + "sysAudioPeak=\(String(format: "%.5f", sysAudioPeak)) "
                      + "sysAudioRms=\(String(format: "%.5f", sysAudioRms)) "
                      + "videoBroadcastSeen=\(videoBroadcastSeen) "
                      + "videoBroadcastAppended=\(videoBroadcastAppended))")
                self?.enqueueUpload {
                    self?.uploadChunkAsync(fileURL: fileURL, index: idx, isFinal: isFinal, target: target)
                }
                DispatchQueue.main.async { completion(true) }
            }
        }
    }

    /// Sends an explicit "finalize ping" — an empty-body chunk request with
    /// is_final=1 — which the server's receive_recording_chunk already treats
    /// as "all data already uploaded, assemble now" (see its
    /// `if not contents:` branch). This is the guaranteed trigger stopRecording
    /// falls back on so assembly never depends on exactly which chunk upload
    /// happened to carry isFinal=true (see stopCaptureThenSignal's comment).
    /// Always terminates: on success OR after retries are exhausted, it calls
    /// uploadFinished() and fires stopResult so Dart is never left hanging.
    private func uploadFinalizePingAsync(attempt: Int = 0) {
        func finish() {
            uploadFinished()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if let r = self.stopResult { self.stopResult = nil; r(nil) }
            }
        }

        guard let url = URL(string: uploadUrl) else {
            NSLog("[REC] finalize ping: bad uploadUrl — skipping")
            finish()
            return
        }

        let boundary = "----AlfaheemPingBoundary\(attempt)"
        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("chunk_index", "\(chunkIndex)")
        addField("is_final", "1")
        if !epoch.isEmpty { addField("epoch", epoch) }
        // Empty file part — zero bytes read server-side triggers the
        // "finalize ping" branch instead of trying to save a chunk.
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"ping.mp4\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        // REQUIRED \r\n terminating the (empty) file part's content before the
        // closing boundary delimiter — every multipart body part, even an
        // empty one, must end with CRLF before "--boundary--". Missing this
        // is exactly what caused the "finalize ping HTTP 422" seen in the
        // logs: the server's multipart parser saw a malformed body and
        // FastAPI rejected it before ever reaching the route handler.
        // Compare uploadChunkAsync's `footer`, which already has this.
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(authToken,                                      forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        uploadSession.uploadTask(with: request, from: body) { [weak self] _, response, error in
            guard let self = self else { return }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[REC] finalize ping HTTP \(code)")
            // Only no answer / 408 / 429 / 5xx is worth another try (409 recording_assembled: already done; a
            // dead upload token or another 4xx will not get better).
            let retryable = error != nil || code == 0 || code == 408 || code == 429 || code >= 500
            if retryable, attempt < 3 {
                NSLog("[REC] finalize ping attempt \(attempt + 1) failed: "
                      + "\(error?.localizedDescription ?? "HTTP \(code)") — retrying")
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(3 * (1 << attempt))) {
                    self.uploadFinalizePingAsync(attempt: attempt + 1)
                }
                return
            }
            if error != nil || code < 200 || code > 299 {
                NSLog("[REC] finalize ping failed permanently — server will fall back to its idle watchdog")
            }
            finish()
        }.resume()
    }

    /// `target`: url / token / container kind of the chunk (captured when it
    /// was finalised, or from a pending sidecar on a retry). `pending`: the
    /// sidecar of a chunk kept from an earlier failure (I11) — on success
    /// both files go, on failure the sidecar's attempt count is bumped.
    private func uploadChunkAsync(fileURL: URL, index: Int, isFinal: Bool,
                                  target: UploadTarget, pending: URL? = nil, attempt: Int = 0) {
        let audioOnly = target.audioOnly
        let authToken = target.token
        if pending == nil && uploadsClosed {
            // The run takes no more chunks (assembled / its token is dead): nothing to send, the recorder is done.
            NSLog("[REC] chunk #\(index) skipped — uploads closed for this run")
            try? FileManager.default.removeItem(at: fileURL)
            uploadFinished()
            if isFinal { resolveStopResult() }
            return
        }
        guard let url = URL(string: target.url) else {
            NSLog("[REC] chunk #\(index) bad uploadUrl — skipping")
            uploadFinished()
            return
        }

        // ── Read file size BEFORE touching the file ───────────────────────────
        // resourceValues returns nil once the file is deleted, so we must
        // capture the size now, not after removeItem.
        let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard fileSize > 0 else {
            NSLog("[REC] chunk #\(index) file missing or empty — skipping")
            uploadFinished()
            return
        }

        // ── Build multipart body with a temp file ─────────────────────────────
        // Using request.httpBody = Data(contentsOf:) loads the entire video
        // chunk into RAM and URLSession may silently drop large bodies.
        // Instead we write the multipart envelope to a temp file and use
        // uploadTask(with:fromFile:) which streams directly from disk —
        // the correct approach for large binary payloads.
        let boundary  = "----AlfaheemBoundary\(index)x\(attempt)"
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
        if !target.epoch.isEmpty { addField("epoch", target.epoch) }

        // Audio-only chunks are the same MP4 container with audio tracks only —
        // named .m4a / audio/mp4 so the server assembles one .m4a from them.
        let fname = String(format: audioOnly ? "chunk_%06d.m4a" : "chunk_%06d.mp4", index)
        header.append("--\(boundary)\r\n".data(using: .utf8)!)
        header.append("Content-Disposition: form-data; name=\"chunk\"; filename=\"\(fname)\"\r\n".data(using: .utf8)!)
        header.append("Content-Type: \(audioOnly ? "audio/mp4" : "video/mp4")\r\n\r\n".data(using: .utf8)!)

        let footer = "\r\n--\(boundary)--\r\n".data(using: .utf8)!

        // Write header + video bytes + footer into a single temp file.
        guard let videoData = try? Data(contentsOf: fileURL) else {
            NSLog("[REC] chunk #\(index) could not read video file")
            uploadFinished()
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
            uploadFinished()
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
        uploadSession.uploadTask(with: request, fromFile: tmpURL) { [weak self] data, response, error in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: tmpURL)   // clean temp file

            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[REC] chunk #\(index) HTTP \(code) isFinal=\(isFinal) size=\(fileSize)B")
            let errCode: String? = (error == nil && (code < 200 || code > 299)) ? recChunkErrorCode(data) : nil

            if error == nil && code == 409 && errCode == "recording_assembled" {
                // The run's recording is assembled: stop uploading for it, drop what is left of it.
                NSLog("[REC] chunk #\(index): recording already assembled — uploads stopped")
                try? FileManager.default.removeItem(at: fileURL)
                if let sidecar = pending { try? FileManager.default.removeItem(at: sidecar) }
                self.uploadFinished()
                guard pending == nil else { return }
                self.uploadsClosed = true
                self.dropKeptChunks(forUrl: target.url)
                self.emitEvent(["event": "uploadsStopped", "reason": "recording_assembled"])
                if isFinal { self.resolveStopResult() }
                return
            }
            if error == nil && code == 409 && errCode == "recording_assembling" {
                // Being assembled right now: keep the chunk (never delete footage), no retry in this run.
                NSLog("[REC] chunk #\(index): recording being assembled — kept")
                if pending == nil {
                    self.keepFailedChunk(fileURL: fileURL, index: index, isFinal: isFinal, target: target)
                }
                self.uploadFinished()
                guard pending == nil else { return }
                if isFinal { self.resolveStopResult() }
                return
            }

            if error != nil || code < 200 || code > 299 {
                // 401 upload_token_expired / _invalid / _revoked, 403 upload_token_scope: this token can no
                // longer upload to the run — permanent (below), and the rest of the run is not sent either.
                if pending == nil, let c = errCode, c.hasPrefix("upload_token_") { self.uploadsClosed = true }
                let reason = error?.localizedDescription ?? "HTTP \(code)"
                NSLog("[REC] chunk #\(index) attempt \(attempt+1) failed: \(reason)")
                // A 4xx (other than timeout / rate limit) will not get better
                // by retrying (session gone, token for another user, …).
                let permanent = error == nil && (400...499).contains(code) && code != 408 && code != 429
                // A kept chunk retried from a later run gets one extra try per run.
                let maxAttempts = pending == nil ? 4 : 1
                if !permanent && attempt < maxAttempts {
                    // Back-off: 3s, 6s, 12s, 24s — longer than before because
                    // waitsForConnectivity means the network may need time to
                    // fully re-establish after LiveKit tears down its sockets.
                    DispatchQueue.global().asyncAfter(deadline: .now() + Double(3 * (1 << attempt))) {
                        self.uploadChunkAsync(fileURL: fileURL, index: index, isFinal: isFinal,
                                              target: target, pending: pending, attempt: attempt + 1)
                    }
                } else {
                    if let sidecar = pending {
                        self.pendingChunkFailed(sidecar: sidecar, file: fileURL, dropNow: permanent)
                    } else if permanent {
                        try? FileManager.default.removeItem(at: fileURL)
                    } else {
                        // I11: keep it (Application Support, survives tmp
                        // purges) and retry on the next startMicRecording /
                        // retryPendingUploads instead of deleting it.
                        self.keepFailedChunk(fileURL: fileURL, index: index, isFinal: isFinal, target: target)
                    }
                    self.uploadFinished()
                    guard pending == nil else { return }
                    self.emitError("chunk #\(index) failed after \(attempt + 1) attempts: \(reason)"
                                   + (permanent ? "" : " — kept for a later retry"))
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
            if let sidecar = pending { try? FileManager.default.removeItem(at: sidecar) }
            NSLog("[REC] chunk #\(index) uploaded OK (\(fileSize)B isFinal=\(isFinal) kept=\(pending != nil))")
            self.uploadFinished()
            // A kept chunk from an earlier run is not part of the current
            // recording: no event, and it never resolves this run's stop.
            guard pending == nil else { return }
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

    /// Unblocks Dart's `await stopRecording` (once).
    private func resolveStopResult() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let r = self.stopResult else { return }
            self.stopResult = nil
            r(nil)
        }
    }

    /// Deletes the kept chunks (I11) that were going to `url` (the run is assembled: they can never land).
    private func dropKeptChunks(forUrl url: String) {
        guard let dir = pendingChunksDir(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return }
        for sidecar in entries where sidecar.pathExtension == "json" {
            guard let data = try? Data(contentsOf: sidecar),
                  let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (meta["url"] as? String) == url else { continue }
            if let file = meta["file"] as? String {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
            try? FileManager.default.removeItem(at: sidecar)
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
        // I11: the multipart temp copies (upload_chunk_*) are swept too —
        // they used to stay forever when the app died mid-upload.
        for url in items where url.lastPathComponent.hasPrefix("rec_chunk_")
                            || url.lastPathComponent.hasPrefix("upload_chunk_") {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let d = created, d < cutoff {
                try? FileManager.default.removeItem(at: url)
                NSLog("[REC] swept stale chunk: \(url.lastPathComponent)")
            }
        }
        // Kept chunks (I11) give up after 72 h.
        guard let dir = pendingChunksDir(),
              let kept = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let keptCutoff = Date(timeIntervalSinceNow: -72 * 3600)
        for url in kept {
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
            if let d = created, d < keptCutoff {
                try? FileManager.default.removeItem(at: url)
                NSLog("[REC] swept kept chunk: \(url.lastPathComponent)")
            }
        }
    }

    // ── I11: chunks kept after a failed upload ───────────────────────────────
    //
    // <Application Support>/rec_pending/<name>.mp4|.m4a + <name>.json
    // (sidecar: url, index, isFinal, audioOnly, attempts). The auth token is
    // NOT stored: a retry uses the token of the run that retries it
    // (startMicRecording or Dart's "retryPendingUploads"). Retried in creation
    // order through the same serial upload queue; dropped after a 4xx, after
    // 10 attempts across runs, or after 72 h (sweepStaleChunks).
    // OPEN QUESTION for the server: a chunk that arrives after its recording
    // was assembled (finalize ping / idle watchdog) — see the test plan.

    private func pendingChunksDir() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("rec_pending", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDir = dir
        try? mutableDir.setResourceValues(values)
        return dir
    }

    private func keepFailedChunk(fileURL: URL, index: Int, isFinal: Bool, target: UploadTarget) {
        guard let dir = pendingChunksDir() else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let name = String(format: "p_%013d_%06d", stamp, index)
        let dest = dir.appendingPathComponent(name + (target.audioOnly ? ".m4a" : ".mp4"))
        do {
            try FileManager.default.moveItem(at: fileURL, to: dest)
        } catch {
            NSLog("[REC] could not keep chunk #\(index): \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let meta: [String: Any] = [
            "url": target.url, "index": index, "isFinal": isFinal,
            "audioOnly": target.audioOnly, "attempts": 1, "epoch": target.epoch,
            "file": dest.lastPathComponent,
        ]
        if let json = try? JSONSerialization.data(withJSONObject: meta) {
            try? json.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic)
        }
        NSLog("[REC] chunk #\(index) kept for a later retry: \(dest.lastPathComponent)")
    }

    /// Queues every kept chunk (oldest first) for upload with `authToken`.
    private func retryPendingChunks(authToken token: String) {
        guard !token.isEmpty, let dir = pendingChunksDir(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { return }
        let sidecars = entries.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for sidecar in sidecars {
            guard let data = try? Data(contentsOf: sidecar),
                  let meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let url = meta["url"] as? String,
                  let index = meta["index"] as? Int,
                  let file = meta["file"] as? String else {
                try? FileManager.default.removeItem(at: sidecar)
                continue
            }
            let fileURL = dir.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                try? FileManager.default.removeItem(at: sidecar)
                continue
            }
            let isFinal = meta["isFinal"] as? Bool ?? false
            let target = UploadTarget(url: url, token: token,
                                      audioOnly: meta["audioOnly"] as? Bool ?? false,
                                      epoch: meta["epoch"] as? String ?? "")
            NSLog("[REC] retrying kept chunk #\(index) (\(file))")
            enqueueUpload { [weak self] in
                self?.uploadChunkAsync(fileURL: fileURL, index: index, isFinal: isFinal,
                                       target: target, pending: sidecar)
            }
        }
    }

    private func pendingChunkFailed(sidecar: URL, file: URL, dropNow: Bool) {
        var attempts = 10
        if let data = try? Data(contentsOf: sidecar),
           var meta = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            attempts = (meta["attempts"] as? Int ?? 1) + 1
            meta["attempts"] = attempts
            if let json = try? JSONSerialization.data(withJSONObject: meta) {
                try? json.write(to: sidecar, options: .atomic)
            }
        }
        if dropNow || attempts >= 10 {
            NSLog("[REC] dropping kept chunk \(file.lastPathComponent) (attempts=\(attempts) permanent=\(dropNow))")
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    // ── I9: background time for the upload queue, separate from bgTask ───────
    private func beginUploadBgTask() {
        guard uploadBgTask == .invalid else { return }
        uploadBgTask = UIApplication.shared.beginBackgroundTask(withName: "RecordingUpload") {
            [weak self] in self?.endUploadBgTask()
        }
    }

    private func endUploadBgTask() {
        guard uploadBgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(uploadBgTask)
        uploadBgTask = .invalid
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Broadcast Extension (foreign-app screen share)
    // ─────────────────────────────────────────────────────────────────────────

    private func showBroadcastPicker(present: Bool, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { result(nil); return }
            self.armBroadcastRecording(reason: present ? "picker" : "arm-only")
            if present { self.presentBroadcastPicker() }
            result(nil)
        }
    }

    /// Prepares the in-app recorder (and the audio session) for a broadcast:
    /// Darwin listeners for the extension's frames / audio / stop, the
    /// background task, a clean chunk boundary (recording paused until the
    /// first broadcast frame) and the no-show watchdog. Idempotent enough to
    /// run from the picker AND again from onLkBroadcastStarted. Main thread.
    private func armBroadcastRecording(reason: String) {

            // NOTE (I5, 2026-10-29): the "broadcast share" session config is
            // now playAndRecord + videoChat (echo cancellation kept), so the
            // non-ducking history below no longer applies; the call is kept
            // so the reassert observers still guard against drift.
            // ── Switch to non-ducking mode BEFORE the picker even appears ──
            // Previously this only happened reactively, in handleBroadcastData,
            // on the FIRST BROADCAST VIDEO FRAME. That is too late: the user
            // still has to (1) confirm "Start Broadcast" in the system sheet,
            // then (2) manually switch to the app they want to share, then
            // (3) that app has to actually be showing something before its
            // first frame reaches us — commonly 1-3+ seconds, during which our
            // session was STILL in .videoChat (auto-duck) mode from normal
            // mic recording. If the shared app started playing its audio
            // anywhere in that window, iOS ducked it right then — and that
            // duck does NOT lift the instant we switch modes afterward, it
            // releases on iOS's own multi-second fade envelope. That slow
            // fade-back-up is exactly what a "clear for a fraction of a
            // second, then very quiet for the next 15-20s" recording looks
            // like (see sysAudioRms climbing chunk over chunk in the logs:
            // 0.053 → 0.0 → 0.195 → 0.562 → 0.562 → 0.565 → 0.540 — a slow
            // release curve, not a step change).
            // Configuring non-ducking mode here instead means the shared
            // app's audio is never ducked in the first place — there is
            // nothing left to release/fade back from.
            //
            // Safe even if the user cancels the picker: stopBroadcastShare's
            // `paused == true` branch already reverts to .videoChat via
            // configureAudioSessionForRecording() for exactly that case.
            self.broadcastShareArmed = true
            self.configureAudioSessionForBroadcastShare()
            self.startAudioSessionObserver()

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

            // Audio-only recordings have no video source to switch (and the
            // extension sends them no frames: ext_wants_video_file is off),
            // so they keep recording straight through the share.
            if self.recording && !self.paused && !self.stopping && !self.audioOnly {
                self.paused = true
                // Without this, the pre-share chunk's still-pending 5s timer
                // survives the pause untouched. If the whole picker-confirm→
                // extension-launch→first-frame sequence finishes before that
                // stale timer happens to fire (easily 1-2s, well within its
                // remaining life), scheduleChunkTimer() for the broadcast's
                // first chunk sees chunkTimer != nil and skips scheduling a
                // proper new one — leaving chunk rotation for the broadcast
                // riding on a leftover timer with the wrong fire time instead
                // of a clean 5s cadence from when the broadcast actually
                // started. pauseRecording() (the explicit pause handler)
                // already does this; this path was the one inconsistent case
                // that didn't.
                self.chunkTimer?.invalidate()
                self.chunkTimer = nil
                NSLog("[SHARE] arm (\(reason)): recording paused until the first broadcast frame")
                // Index advanced NOW, not in the completion: the first
                // broadcast frame can reopen a writer before this chunk's
                // finishWriting returns, and must not reuse (and delete) its file.
                self.finaliseChunk(isFinal: false) { _ in }
                self.chunkIndex += 1
                NSLog("[SHARE] arm: paused chunk rotated, next #\(self.chunkIndex)")
            }

            // ── Watchdog: resume if the broadcast never actually starts ──────
            // Covers: sheet failed to present, user dismissed it without going
            // through "Start Broadcast", or the extension failed to launch
            // (signing/App-Group misconfiguration etc). Cancelled as soon as
            // a real broadcast frame arrives (handleBroadcastData), the user
            // explicitly cancels (stopBroadcastShare), or the extension itself
            // reports it stopped (onDarwinStopNotif). A broadcast confirmed
            // after it fired re-arms through onLkBroadcastStarted.
            self.pickerWatchdog?.invalidate()
            self.pickerWatchdog = Timer.scheduledTimer(
                withTimeInterval: self.pickerWatchdogSecs, repeats: false
            ) { [weak self] _ in
                guard let self = self else { return }
                self.pickerWatchdog = nil
                guard self.recording, self.paused, !self.isBroadcasting, !self.stopping else { return }
                NSLog("[SHARE] picker watchdog: no broadcast frame after " +
                      "\(self.pickerWatchdogSecs)s — resuming RPScreenRecorder")
                self.broadcastShareArmed = false
                self.paused = false
                self.beginChunkWriter()
            }
    }

    /// Shows the system "Start Broadcast" sheet for our extension. Main thread.
    private func presentBroadcastPicker() {

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
            // Same key flutter_webrtc and livekit_client read (Info.plist).
            picker.preferredExtension =
                (Bundle.main.object(forInfoDictionaryKey: "RTCScreenSharingExtension") as? String)
                ?? Bundle.main.bundleIdentifier.map { $0 + ".BroadcastUploadExtension" }
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
    }

    private func stopBroadcastShare(result: @escaping FlutterResult) {
        // I2: actually end the extension (it used to keep capturing — red
        // pill — after "Stop sharing" / leaving the room). It answers with
        // finishBroadcastWithError + iOS_BroadcastStopped.
        if extensionBroadcastLive || broadcastShareArmed || isBroadcasting {
            postDarwin(kLkBroadcastRequestStop)
        }
        // NOTE: isBroadcasting is deliberately NOT set to false here at the
        // top — see below for why. Everything else that's safe to clean up
        // immediately (Darwin listeners, background task, watchdog, picker
        // view) still happens right away.
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
                // Broadcast was never confirmed (user cancelled picker) — no
                // active broadcast writer exists yet, so there's no race to
                // protect against. Safe to flip isBroadcasting immediately.
                isBroadcasting = false
                broadcastShareArmed = false
                // Harmless no-op if configureAudioSessionForBroadcastShare()
                // was never actually applied (picker cancelled before the
                // first broadcast frame) — still correct to re-assert
                // .videoChat here in case it was.
                configureAudioSessionForRecording()
                paused = false
                beginChunkWriter()
                NSLog("[SHARE] picker cancelled — RPScreenRecorder resumed at chunk #\(chunkIndex)")
            } else {
                // Broadcast was active: finalise the broadcast chunk BEFORE
                // letting RPScreenRecorder's video resume writing anywhere.
                //
                // RPScreenRecorder's capture handler keeps running the ENTIRE
                // time a broadcast is active (audio must keep flowing through
                // it — see processSampleFromRecorder's .audioMic/.audioApp
                // case), with only its VIDEO gated on `!isBroadcasting`. If
                // isBroadcasting flipped false here, at the top of this
                // function, the very next RPScreenRecorder video frame —
                // which could arrive within milliseconds, well before
                // finaliseChunk below has actually nil'd out and closed the
                // broadcast's writer — would pass that guard and get
                // appended to the SAME, still-open AVAssetWriter the
                // broadcast was just using. That mixes two independent frame
                // sources with incompatible timelines into one track, which
                // AVAssetWriter enforces strictly increasing timestamps for;
                // the append can be silently rejected or the writer can end
                // up in a bad state, and finishWriting() either fails or
                // produces something unusable — with nothing logged anywhere
                // to explain it. That's exactly how the LAST broadcast chunk
                // could vanish with no trace: not lost in upload, never
                // successfully finalized in the first place.
                //
                // Keeping isBroadcasting true until INSIDE this completion
                // handler — i.e. strictly after finaliseChunk's synchronous
                // nil-ing of assetWriter/videoInput/audioInput has already
                // happened — closes that window completely.
                finaliseChunk(isFinal: false) { [weak self] _ in
                    guard let self = self else { return }
                    self.isBroadcasting = false
                    self.broadcastShareArmed = false
                    // Restore .videoChat mode now that the shared app's
                    // audio no longer needs un-ducked capture — see
                    // configureAudioSessionForBroadcastShare's doc comment.
                    self.configureAudioSessionForRecording()
                    guard self.recording, !self.stopping, !self.paused else { return }
                    self.chunkIndex += 1
                    self.beginChunkWriter()
                    NSLog("[SHARE] broadcast chunk rotated — RPScreenRecorder resuming at chunk #\(self.chunkIndex)")
                }
            }
        } else {
            isBroadcasting = false
            broadcastShareArmed = false
            stopAudioSessionObserver()  // ← NEW
            configureAudioSessionForRecording()

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

        // Wipe any audio-queue files left over from a previous broadcast
        // (e.g. one that ended abruptly before the host finished draining
        // it) before this new broadcast's frames start arriving.
        // (Not while the app-audio mixer is already draining it.)
        if !audioQueueObserverAdded { resetAudioQueueDirectory() }

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

        // System/app audio notification (shared app's own audio) — shared
        // with ShareAppAudioMixer, so registered once for both.
        registerAudioQueueListener()

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
        updateExtensionWants()
    }

    private func removeDarwinListeners() {
        guard darwinObserverAdded else { updateExtensionWants(); return }
        darwinObserverAdded = false
        let center  = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveObserver(center, selfPtr,
            CFNotificationName(kDarwinFrameNotif as CFString), nil)
        CFNotificationCenterRemoveObserver(center, selfPtr,
            CFNotificationName(kDarwinStopNotif  as CFString), nil)
        // The audio queue stays observed while the mixer still uses it.
        if !appAudioMixer.isActive { removeAudioQueueListener() }
        NSLog("[SHARE] Darwin listeners removed")
        updateExtensionWants()
    }

    private func registerAudioQueueListener() {
        guard !audioQueueObserverAdded else { return }
        audioQueueObserverAdded = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                me.onDarwinAudioFrameNotif()
            },
            kDarwinAudioNotif as CFString, nil, .deliverImmediately
        )
    }

    private func removeAudioQueueListener() {
        guard audioQueueObserverAdded else { return }
        audioQueueObserverAdded = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(kDarwinAudioNotif as CFString), nil)
        // Whatever the extension still had queued is nobody's now.
        audioIpcReadQueue.async { [weak self] in self?.resetAudioQueueDirectory() }
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

    /// Called on the main thread when the extension posted a system-audio
    /// frame notification (SampleHandler's .audioApp path).
    ///
    /// IMPORTANT: unlike onDarwinFrameNotif (video), this does NOT read one
    /// fixed file. .audioApp buffers are written by SampleHandler into their
    /// own sequentially-numbered files under kAudioQueueDirName (a queue,
    /// not a 1-slot mailbox) precisely because they arrive too fast
    /// (~10-25ms apart) for overwrite-and-notify to keep up with — that
    /// single-file design was the actual cause of shared-app audio going
    /// missing from screen-share recordings (buffers overwritten before
    /// being read, or the same file read twice yielding a duplicate/
    /// non-monotonic timestamp that the writer then rejected). A Darwin
    /// notification here just means "there may be new files" — it's fine,
    /// and expected, for several writes to coalesce into one notification;
    /// draining the whole directory every time covers that.
    private func onDarwinAudioFrameNotif() {
        audioIpcReadQueue.async { [weak self] in
            self?.drainAudioQueueDirectory()
        }
    }

    /// Reads and deletes every currently-pending file in the audio queue
    /// directory, in ascending (i.e. chronological) filename order, and
    /// feeds each one to handleBatchedAudioData (which may unpack several
    /// batched records per file — see its doc comment) in that order.
    /// Must only be called on audioIpcReadQueue (serial) so two drains
    /// never overlap.
    private func drainAudioQueueDirectory() {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) else { return }
        let dir = container.appendingPathComponent(kAudioQueueDirName)

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        // Filenames are zero-padded (see SampleHandler's kAudioSeqPad), so
        // a plain string sort is also the correct chronological order.
        let ordered = entries
            .filter { $0.lastPathComponent.hasPrefix("aud_") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in ordered {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            // Delete first: if handleBroadcastData is slow/re-entrant, we
            // never want a second drain pass to double-process this file.
            try? FileManager.default.removeItem(at: fileURL)
            guard data.count >= 16 else { continue }
            handleBatchedAudioData(data)
        }
    }

    /// Each file in the audio queue directory may contain several audio
    /// records concatenated back-to-back (SampleHandler batches up to
    /// kAudioBatchSize samples per file-write instead of writing one file
    /// per sample — see SampleHandler.swift's 2026-07-30 header comment
    /// for why). Each record is still the same self-describing
    /// [4B typeId][8B ptsNs][4B size][payload] format handleBroadcastData
    /// already knows how to parse, so this just walks the buffer and hands
    /// each record to handleBroadcastData in order, one at a time, instead
    /// of assuming the whole file is a single record.
    private func handleBatchedAudioData(_ data: Data) {
        var offset = data.startIndex
        while data.distance(from: offset, to: data.endIndex) >= 16 {
            let remaining = Data(data[offset...])
            func beUInt32At(_ o: Int) -> UInt32 {
                var v: UInt32 = 0
                for i in 0..<4 { v = (v << 8) | UInt32(remaining[remaining.startIndex + o + i]) }
                return v
            }
            let paySize = Int(beUInt32At(12))
            let recordLen = 16 + paySize
            guard remaining.count >= recordLen else {
                // Truncated trailing record (shouldn't happen — writes are
                // atomic — but bail out defensively rather than parsing
                // garbage as a header).
                break
            }
            handleBroadcastData(Data(remaining.prefix(recordLen)))
            offset = data.index(offset, offsetBy: recordLen)
        }
    }

    /// Clears any leftover audio-queue files from a previous broadcast
    /// before a new one starts, so stale audio can never leak into a new
    /// recording. Called from registerDarwinListeners(), which runs once
    /// per Share Screen start (see showBroadcastPicker).
    private func resetAudioQueueDirectory() {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) else { return }
        let dir = container.appendingPathComponent(kAudioQueueDirName)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Called on the main thread when the extension posted a stop notification.
    private func onDarwinStopNotif() {
        // Reached twice per broadcast end (the extension posts both its own
        // "…stop" and iOS_BroadcastStopped → onLkBroadcastStopped): once is enough.
        guard darwinObserverAdded || isBroadcasting || broadcastShareArmed else { return }
        NSLog("[SHARE] broadcast extension finished (Darwin stop)")
        isBroadcasting = false
        broadcastShareArmed = false
        // Restore .videoChat mode (AEC/NS for the live call) now that the
        // shared app's audio no longer needs to be captured un-ducked —
        // see configureAudioSessionForBroadcastShare's doc comment.
        stopAudioSessionObserver()  // ← NEW
        configureAudioSessionForRecording()
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
        stopAudioSessionObserver()
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
                // Switch OFF the auto-ducking .videoChat mode NOW, before any
                // real system audio from the shared app has a chance to be
                // rendered (and silently attenuated) under the old mode —
                // see configureAudioSessionForBroadcastShare's doc comment.
                configureAudioSessionForBroadcastShare()
                NSLog("[SHARE] first broadcast frame — switching recording source")
                startAudioSessionObserver()

                // If recording was paused by showBroadcastPicker (to protect
                // against the iOS overlay suspension window), resume it now.
                // The extension is running, iOS has fully resumed, it's safe to write.
                if recording && paused && !stopping {
                    paused = false
                    // IMPORTANT: beginChunkWriter() detects it isn't on the main
                    // thread (we're on ipcReadQueue here) and re-dispatches
                    // itself there — but returns immediately without waiting.
                    // processSampleFromBroadcast (below) reads self.assetWriter
                    // via its own separate writerQueue dispatch, with no
                    // ordering guarantee against beginChunkWriter's pending
                    // main-thread work. Calling it right after beginChunkWriter()
                    // here could easily see assetWriter still nil and silently
                    // drop this — and potentially several more — broadcast
                    // frames with nothing logged anywhere. Dispatching both
                    // calls together onto the main thread makes them run in
                    // that exact order: the writer is guaranteed to exist
                    // before this first frame is processed.
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.beginChunkWriter()
                        NSLog("[SHARE] recording resumed from picker-pause — broadcast chunk #\(self.chunkIndex)")
                        self.processSampleFromBroadcast(jpegData: payload, ptsNs: ptsNs)
                    }
                    return
                }
            }
            guard recording, !stopping, !paused else { return }
            processSampleFromBroadcast(jpegData: payload, ptsNs: ptsNs)

        case 1:
            // Extension mic audio — still intentionally dropped. The
            // teacher's mic is already forwarded via the LiveKit audio tap
            // (see handleIncomingAudioFrame / room.dart's
            // _startLiveKitAudioTap), so this would just be a duplicate.
            break

        case 2:
            // Shared app's own audio (e.g. sound from a video/game on the
            // screen being broadcast) — genuinely different content from
            // the mic, NOT a duplicate. Written into the second, independent
            // systemAudioInput track (see its declaration for why it's a
            // separate track rather than mixed into the mic track).
            //
            // Live: also mixed into the published microphone (ShareAppAudioMixer).
            if appAudioMixer.isActive { appAudioMixer.push(payload: payload) }
            guard recording, !stopping, !paused else { return }
            // While the mixer is really mixing, the recording's mic track (the
            // LiveKit audio tap reads the capture post-processing output, i.e.
            // AFTER the mix) already carries this sound; writing it to the
            // system-audio track as well would play it twice after the
            // server's amix. If the mic is muted / its engine stopped, the
            // mixer is not called back and the system-audio track takes over.
            if appAudioMixer.isMixingLive { return }
            processSystemAudioFromBroadcast(payload, ptsNs: ptsNs)

        default:
            break
        }
    }

    /// Decodes a [sampleRate:4B BE][channels:4B BE][isFloat:4B BE][raw PCM]
    /// payload (see SampleHandler.swift's serialiseAudio) and appends it to
    /// systemAudioInput, anchored to the SAME ptsNs clock domain the
    /// broadcast video frames use (both come from CMSampleBufferGetPresentationTimeStamp
    /// inside the extension process, on the shared host-time clock).
    private func processSystemAudioFromBroadcast(_ payload: Data, ptsNs: UInt64) {
        guard payload.count > 12 else { return }
        func beUInt32(_ bytes: Data, _ offset: Int) -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v = (v << 8) | UInt32(bytes[bytes.startIndex + offset + i]) }
            return v
        }
        let sampleRate = beUInt32(payload, 0)
        let channels   = beUInt32(payload, 4)
        let isFloat    = beUInt32(payload, 8) != 0
        let pcm        = Data(payload.dropFirst(12))
        guard sampleRate > 0, channels > 0, !pcm.isEmpty else { return }

        systemAudioQueue.async { [weak self] in
            guard let self = self else { return }
            self.sysAudioSamplesSeenThisChunk += 1
            let stats = Self.peakAndRms(pcm, isFloat: isFloat)
            self.sysAudioPeakThisChunk = max(self.sysAudioPeakThisChunk, stats.peak)
            self.sysAudioSquareSumThisChunk += stats.squareSum
            self.sysAudioRmsSampleCountThisChunk += stats.count

            guard let writer = self.assetWriter, writer.status == .writing,
                  self.writerSessionStarted,
                  // Also route through the pending queue while a not-ready
                  // retry is outstanding (see appendSystemAudioSample) —
                  // otherwise this NEWER sample would append directly and
                  // land ahead of the OLDER one still waiting to retry,
                  // which then gets rejected as non-monotonic once the
                  // retry finally runs. Queuing everything behind it keeps
                  // strict arrival order.
                  !self.systemAudioBackpressured
            else {
                // Writer/session not live yet — this is expected for a brief
                // window right at the start of each chunk during a screen
                // share (the session only starts once the first broadcast
                // VIDEO frame arrives). Buffer instead of dropping; replayed
                // in order by flushPendingSystemAudioFrames() as soon as the
                // session actually starts.
                if self.pendingSystemAudioFrames.count >= self.kPendingSystemAudioCap {
                    self.pendingSystemAudioFrames.removeFirst()
                }
                self.pendingSystemAudioFrames.append(
                    (sampleRate, channels, isFloat, pcm, ptsNs)
                )
                return
            }

            self.appendSystemAudioSample(
                sampleRate: sampleRate, channels: channels, isFloat: isFloat,
                pcm: pcm, ptsNs: ptsNs
            )
        }
    }

    /// Actually appends one system-audio sample to systemAudioInput. Must
    /// only be called on systemAudioQueue, and only once the writer/session
    /// are confirmed live (either directly from processSystemAudioFromBroadcast,
    /// or via flushPendingSystemAudioFrames once they become live).
    private func appendSystemAudioSample(
        sampleRate: UInt32, channels: UInt32, isFloat: Bool, pcm: Data, ptsNs: UInt64
    ) {
        guard self.systemAudioInput?.isReadyForMoreMediaData == true else {
            // Genuinely nil input (no active chunk) — nothing to retry.
            guard self.systemAudioInput != nil else {
                NSLog("[REC] system-audio dropped — systemAudioInput is nil")
                return
            }
            // Input exists but is momentarily busy (e.g. right after a new
            // chunk's writer session starts, competing with the video track
            // for encoder throughput — this is exactly the burst of drops
            // seen at the start of chunk #1 in the logs). Re-queue instead
            // of dropping outright and retry shortly; the encoder catches up
            // within a few milliseconds in practice, and losing this window
            // every chunk read as an audible stutter/brief mute right after
            // the "clear" opening moment. Same bounded queue/cap used for
            // "session not live yet" — the ordering guarantee (FIFO, drained
            // in appendSystemAudioSample calls) is the same either way.
            if self.pendingSystemAudioFrames.count >= self.kPendingSystemAudioCap {
                self.pendingSystemAudioFrames.removeFirst()
            }
            self.pendingSystemAudioFrames.append(
                (sampleRate, channels, isFloat, pcm, ptsNs)
            )
            self.systemAudioBackpressured = true
            if !self.notReadyRetryScheduled {
                self.notReadyRetryScheduled = true
                self.systemAudioQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                    guard let self = self else { return }
                    self.notReadyRetryScheduled = false
                    // Clear optimistically before draining — if the writer
                    // is still busy, appendSystemAudioSample's not-ready
                    // branch below will just set this back to true and
                    // schedule another retry, same as the first time.
                    self.systemAudioBackpressured = false
                    self.flushPendingSystemAudioFrames()
                }
            }
            return
        }

        let pcmWithHeadroom = Self.applyHeadroomGain(
            pcm, isFloat: isFloat, gain: Self.kSystemAudioHeadroomGain
        )
        guard let sampleBuffer = self.makeAudioSampleBuffer(
            data: pcmWithHeadroom, sampleRate: Int(sampleRate), channels: Int(channels),
            format: isFloat ? "float32" : "int16", ptsNs: ptsNs
        ) else {
            NSLog("[REC] system-audio dropped — makeAudioSampleBuffer failed "
                  + "(sr=\(sampleRate) ch=\(channels) bytes=\(pcm.count))")
            return
        }

        // FIX (2026-08-01) — see systemAudioLockedFormat's doc comment.
        // Lock to whichever format the FIRST sample of this chunk actually
        // had, and refuse (rather than silently feed through) any later
        // packet reporting a different shape — that mismatch is the likely
        // cause of "system audio plays as noise/static" reports.
        if let locked = self.systemAudioLockedFormat {
            guard locked.sampleRate == sampleRate, locked.channels == channels,
                  locked.isFloat == isFloat
            else {
                NSLog("[REC] system-audio dropped — format changed mid-chunk "
                      + "(locked sr=\(locked.sampleRate) ch=\(locked.channels) "
                      + "float=\(locked.isFloat) vs this packet sr=\(sampleRate) "
                      + "ch=\(channels) float=\(isFloat)) — would otherwise feed "
                      + "a mismatched buffer through the already-configured "
                      + "audio converter and produce audible static")
                return
            }
        } else {
            self.systemAudioLockedFormat = (sampleRate, channels, isFloat)
            let branchName = isFloat ? "float" : "int16"
            NSLog("[REC] system-audio format locked for this chunk: "
                  + "sr=\(sampleRate) ch=\(channels) isFloat=\(isFloat) "
                  + "(headroom-gain will use the \(branchName) branch)")
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let last = self.lastSystemAudioPts, CMTimeCompare(pts, last) <= 0 {
            NSLog("[REC] system-audio dropped — non-monotonic pts "
                  + "(\(CMTimeGetSeconds(pts))s <= \(CMTimeGetSeconds(last))s)")
            return
        }
        self.lastSystemAudioPts = pts

        if self.systemAudioInput?.append(sampleBuffer) == true {
            self.sysAudioSamplesAppendedThisChunk += 1
        } else {
            NSLog("[REC] system-audio append FAILED — writer status="
                  + "\(String(describing: self.assetWriter?.status.rawValue)) "
                  + "error=\(String(describing: self.assetWriter?.error))")
        }
    }

    /// Replays anything buffered by processSystemAudioFromBroadcast while
    /// the writer/session weren't live yet, now that they are. Called (via
    /// systemAudioQueue.async) right after processSampleFromBroadcast starts
    /// a new writer session. Order-preserving: the buffer is FIFO and this
    /// drains it front-to-back before anything newly-arriving is processed,
    /// since it all runs serially on systemAudioQueue.
    private func flushPendingSystemAudioFrames() {
        guard !pendingSystemAudioFrames.isEmpty else { return }
        let queued = pendingSystemAudioFrames
        pendingSystemAudioFrames.removeAll()
        for frame in queued {
            appendSystemAudioSample(
                sampleRate: frame.sampleRate, channels: frame.channels,
                isFloat: frame.isFloat, pcm: frame.pcm, ptsNs: frame.ptsNs
            )
        }
    }

    /// Cheap peak + sum-of-squares scan (normalized 0.0–1.0 samples) of a
    /// raw PCM buffer. Feeds both the sysAudioPeak diagnostic (real-but-
    /// quiet vs. literally silent/zeroed samples from ReplayKit — see
    /// sysAudioPeakThisChunk's doc comment) and the sysAudioRms diagnostic
    /// (catches ducking-oscillation: peak alone can look healthy off a
    /// single loud sample even when most of the chunk was ducked — see
    /// sysAudioSquareSumThisChunk's doc comment). Sampling every 8th value
    /// is deliberate: this runs on every system-audio packet and only needs
    /// a representative reading, not full-buffer precision.
    private static func peakAndRms(
        _ pcm: Data, isFloat: Bool
    ) -> (peak: Float, squareSum: Double, count: Int) {
        var peak: Float = 0.0
        var squareSum: Double = 0.0
        var count = 0
        pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if isFloat {
                let total = raw.count / MemoryLayout<Float>.size
                guard total > 0 else { return }
                let floats = raw.bindMemory(to: Float.self)
                var i = 0
                while i < total {
                    let sample = abs(floats[i])
                    peak = max(peak, sample)
                    squareSum += Double(sample) * Double(sample)
                    count += 1
                    i += 8
                }
            } else {
                let total = raw.count / MemoryLayout<Int16>.size
                guard total > 0 else { return }
                let ints = raw.bindMemory(to: Int16.self)
                var i = 0
                while i < total {
                    let sample = abs(Float(ints[i]) / Float(Int16.max))
                    peak = max(peak, sample)
                    squareSum += Double(sample) * Double(sample)
                    count += 1
                    i += 8
                }
            }
        }
        return (peak, squareSum, count)
    }

    // FIX (2026-08-01) — "system audio plays as noise/static" investigation.
    // sysAudioPeak has measured essentially exactly 1.0 (occasionally
    // fractionally OVER 1.0) in every chunk across multiple test sessions
    // — never comfortably under it. That's consistent with the signal
    // already riding at/past the clipping ceiling before it reaches this
    // pipeline at all, which leaves zero headroom for AAC encoding here
    // and the server's amix/alimiter afterward — processing an
    // already-at-ceiling signal further tends to compound audible harsh
    // distortion ("noise") rather than fix it. Backing the gain off
    // slightly before encoding can only help: if the source truly is
    // already clipped, this at least stops this pipeline from adding
    // further clipping on top of it; if it's not actually clipped and
    // this was a red herring, a ~2dB reduction is inaudible as a level
    // change and won't affect diagnosing whatever the real cause turns
    // out to be. NOT applied to sysAudioPeak/Rms measurement itself
    // (measured pre-gain, in processSystemAudioFromBroadcast) so those
    // diagnostics keep reflecting the true as-captured level for
    // comparison across builds.
    private static let kSystemAudioHeadroomGain: Float = 0.8   // ≈ -2dB

    // DIAGNOSTIC (2026-08-02) — the float clamp added last round should have
    // made it mathematically impossible for output to exceed ±1.0, yet the
    // next test still measured 1.88 in the final file — nearly unchanged
    // from before the clamp existed (1.85). That can only mean one of two
    // things: (a) that build didn't actually contain this code, or (b) the
    // out-of-range values are being introduced AFTER this point — inside
    // AVAssetWriterInput's own AAC encoder, which is an Apple black box we
    // can't edit or clamp. This counter proves which: if it logs a
    // meaningful clamp-hit rate, we KNOW this code is running and the
    // overshoot really is happening downstream in the encoder (a different
    // problem requiring a different fix — e.g. checking what the encoder
    // does to already-near-full-scale input). If it logs ~0 hits while the
    // exported file still shows values over 1.0, the build under test
    // didn't include this fix and we need to confirm the rebuild actually
    // took before investigating further.
    private static var headroomClampHitCount: Int = 0
    private static var headroomClampSampleCount: Int = 0
    private static var lastHeadroomClampLogTime: CFAbsoluteTime = 0

    private static func applyHeadroomGain(_ pcm: Data, isFloat: Bool, gain: Float) -> Data {
        var out = pcm
        out.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            if isFloat {
                let total = raw.count / MemoryLayout<Float>.size
                guard total > 0 else { return }
                let floats = raw.bindMemory(to: Float.self)
                // FIX (2026-08-01, follow-up) — this branch multiplied by
                // gain but never clamped afterward, unlike the int16 branch
                // below. Direct measurement of a captured system-audio
                // track found real samples up to 1.85 — genuinely,
                // sometimes drastically outside the valid ±1.0 range for
                // float PCM. Even after this fix's own 0.8x gain reduction,
                // 1.85 × 0.8 = 1.48 — STILL out of range, so those samples
                // were still being handed to the AAC encoder unclamped.
                // Depending on how the encoder's internal fixed-point
                // conversion handles an out-of-range float, that can
                // produce wraparound artifacts rather than a clean clip —
                // audible as static, not just "loud". Hard-clamping here
                // guarantees nothing downstream of this point ever sees an
                // out-of-range sample, regardless of how hot the source
                // audio genuinely is.
                for i in 0..<total {
                    let scaled = floats[i] * gain
                    let clamped = max(Float(-1.0), min(Float(1.0), scaled))
                    if scaled != clamped { Self.headroomClampHitCount += 1 }
                    floats[i] = clamped
                }
                Self.headroomClampSampleCount += total
                let now = CFAbsoluteTimeGetCurrent()
                if now - Self.lastHeadroomClampLogTime >= 1.0 {
                    Self.lastHeadroomClampLogTime = now
                    let pct = Self.headroomClampSampleCount > 0
                        ? Double(Self.headroomClampHitCount) / Double(Self.headroomClampSampleCount) * 100
                        : 0
                    NSLog("[REC] headroom clamp: \(Self.headroomClampHitCount)/"
                          + "\(Self.headroomClampSampleCount) samples clamped so far "
                          + "(\(String(format: "%.3f", pct))%)")
                }
            } else {
                let total = raw.count / MemoryLayout<Int16>.size
                guard total > 0 else { return }
                let ints = raw.bindMemory(to: Int16.self)
                var hits = 0
                for i in 0..<total {
                    let scaled = Float(ints[i]) * gain
                    let clampedF = max(Float(Int16.min), min(Float(Int16.max), scaled))
                    if scaled != clampedF { hits += 1 }
                    ints[i] = Int16(clampedF)
                }
                // DIAGNOSTIC (2026-08-02) — the previous round's clamp-hit
                // logging only existed in the isFloat branch above. If
                // system audio on this device/OS is actually delivered as
                // Int16 (not Float32) — both are valid ReplayKit formats —
                // that log would never fire even on a correct, freshly
                // built binary, which is exactly what was observed despite
                // a confirmed clean rebuild with the right file. This
                // mirrors that logging here so whichever branch is
                // actually active, we get proof either way.
                Self.headroomClampHitCount += hits
                Self.headroomClampSampleCount += total
                let now = CFAbsoluteTimeGetCurrent()
                if now - Self.lastHeadroomClampLogTime >= 1.0 {
                    Self.lastHeadroomClampLogTime = now
                    let pct = Self.headroomClampSampleCount > 0
                        ? Double(Self.headroomClampHitCount) / Double(Self.headroomClampSampleCount) * 100
                        : 0
                    NSLog("[REC] headroom clamp (int16 path): \(Self.headroomClampHitCount)/"
                          + "\(Self.headroomClampSampleCount) samples clamped so far "
                          + "(\(String(format: "%.3f", pct))%)")
                }
            }
        }
        return out
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Live share state (I1–I3), extension markers, app audio
    // UNTESTED (2026-10-29) — docs/live/ios_test_plan.md
    // ─────────────────────────────────────────────────────────────────────────

    /// "…/broadcast_state": {"active": Bool} on every Started / Stopped, and
    /// the current value as soon as Dart listens (ios_share.dart). Its own
    /// channel: rec_events allows one listener only (ClientRecorder's).
    private func registerBroadcastStateChannel(messenger: FlutterBinaryMessenger) {
        let ch = FlutterEventChannel(name: kBroadcastStateChannel, binaryMessenger: messenger)
        ch.setStreamHandler(RecEventStreamHandler(
            onListen: { [weak self] sink in
                guard let self = self else { return }
                self.broadcastStateSink = sink
                sink?(["active": self.extensionBroadcastLive])
            },
            onCancel: { [weak self] in self?.broadcastStateSink = nil }
        ))
    }

    private func emitBroadcastState(_ active: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.broadcastStateSink?(["active": active])
        }
    }

    private func postDarwin(_ name: String) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString), nil, nil, true)
    }

    /// iOS_BroadcastStarted / Stopped (posted by the extension), observed
    /// for the app's whole lifetime. livekit_client observes the same names
    /// independently (publish / unpublish); this side does recording, state
    /// and app audio.
    private func registerLiveKitBroadcastObservers() {
        guard !lkObserversAdded else { return }
        lkObserversAdded = true
        let center  = CFNotificationCenterGetDarwinNotifyCenter()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, selfPtr,
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                DispatchQueue.main.async { me.onLkBroadcastStarted() }
            },
            kLkBroadcastStarted as CFString, nil, .deliverImmediately)
        CFNotificationCenterAddObserver(
            center, selfPtr,
            { _, selfPtr, _, _, _ in
                guard let selfPtr = selfPtr else { return }
                let me = Unmanaged<AppDelegate>.fromOpaque(selfPtr).takeUnretainedValue()
                DispatchQueue.main.async { me.onLkBroadcastStopped() }
            },
            kLkBroadcastStopped as CFString, nil, .deliverImmediately)
    }

    private func onLkBroadcastStarted() {
        guard !extensionBroadcastLive else { return }
        extensionBroadcastLive = true
        NSLog("[SHARE] iOS_BroadcastStarted — extension live")
        emitBroadcastState(true)
        // A share started from LiveKit's own picker (or confirmed after the
        // picker watchdog gave up) still needs the recorder armed.
        if recording && !stopping { armBroadcastRecording(reason: "broadcast started") }
        startAppAudioMixIfWanted()
        updateExtensionWants()
    }

    private func onLkBroadcastStopped() {
        NSLog("[SHARE] iOS_BroadcastStopped — extension ended")
        extensionBroadcastLive = false
        stopAppAudioMix()
        emitBroadcastState(false)
        onDarwinStopNotif()          // recorder side; no-op when not armed
        updateExtensionWants()
    }

    /// A recording that starts while a share is already live arms itself.
    private func armIfBroadcastAlreadyLive() {
        guard extensionBroadcastLive, recording, !stopping else { return }
        armBroadcastRecording(reason: "recording started during a share")
    }

    // ── Marker files the extension polls (SampleHandler.refreshWants) ────────

    /// Writes what the extension should produce right now, then pokes it
    /// (it also re-reads every second). Nothing is written to the App Group
    /// unless someone here drains it (I2: no audio files piling up).
    private func updateExtensionWants() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.updateExtensionWants() }
            return
        }
        let wantsVideo = recording && !audioOnly && darwinObserverAdded
        let wantsAudio = (recording && darwinObserverAdded) || appAudioMixer.isActive
        setExtensionMarker(kWantsVideoFile, on: wantsVideo)
        setExtensionMarker(kWantsAudioQueue, on: wantsAudio)
        setExtensionMarker(kWantsDetail, on: shareDetailMode)
        postDarwin(kDarwinWantsChanged)
    }

    private func clearExtensionMarkers() {
        setExtensionMarker(kWantsVideoFile, on: false)
        setExtensionMarker(kWantsAudioQueue, on: false)
        setExtensionMarker(kWantsDetail, on: false)
    }

    private func setExtensionMarker(_ name: String, on: Bool) {
        guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: kAppGroup) else { return }
        let path = container.appendingPathComponent(name).path
        let fm = FileManager.default
        if on {
            if !fm.fileExists(atPath: path) { _ = fm.createFile(atPath: path, contents: nil) }
        } else if fm.fileExists(atPath: path) {
            try? fm.removeItem(atPath: path)
        }
    }

    // ── App audio into the live microphone ───────────────────────────────────

    private func startAppAudioMixIfWanted() {
        guard shareAppAudioEnabled, extensionBroadcastLive, !appAudioMixer.isActive else { return }
        appAudioMixer.start()
        registerAudioQueueListener()
        updateExtensionWants()
        NSLog("[SHARE] app audio mixing into the microphone: on")
    }

    private func stopAppAudioMix() {
        guard appAudioMixer.isActive else { return }
        appAudioMixer.stop()
        if !darwinObserverAdded { removeAudioQueueListener() }
        updateExtensionWants()
        NSLog("[SHARE] app audio mixing into the microphone: off")
    }

    // ── I12: audio-session events for the WHOLE recording ────────────────────
    //
    // startAudioSessionObserver() only watches while a share is armed. A
    // phone call, a headset / Bluetooth route change or a media-services
    // reset during a plain recording could leave the session inactive or
    // change the mic format under a writer locked onto the old one. Each of
    // these now starts a fresh chunk (requestChunkRotation, debounced).

    private func startRecordingAudioObservers() {
        guard recordingAudioObservers.isEmpty else { return }
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        recordingAudioObservers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                NSLog("[REC] audio interruption began (recording)")
            case .ended:
                // During a share startAudioSessionObserver forces the
                // reactivation itself; otherwise do it here.
                if !(self.isBroadcasting || self.broadcastShareArmed) {
                    self.configureAudioSessionForRecording()
                }
                self.requestChunkRotation(reason: "audio interruption ended", evenIfEmpty: true)
            @unknown default:
                break
            }
        })

        recordingAudioObservers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            // Only real device changes; .categoryChange fires on our own
            // (and LiveKit's) reconfigurations.
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                self.requestChunkRotation(reason: "audio route changed (\(raw))")
            default:
                break
            }
        })

        recordingAudioObservers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            NSLog("[REC] media services were reset — reconfiguring and replacing the writer")
            self.configureAudioSessionForRecording()
            self.requestChunkRotation(reason: "media services reset", evenIfEmpty: true)
        })
    }

    private func stopRecordingAudioObservers() {
        for observer in recordingAudioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        recordingAudioObservers.removeAll()
    }
}

/// Where a chunk is uploaded (captured when it is finalised; I11).
private struct UploadTarget {
    let url: String
    let token: String
    let audioOnly: Bool
    /// The recorder start the chunk was recorded in (the `epoch` form field; "" from an older Dart side).
    let epoch: String
}

/// `detail.code` of a FastAPI error body (`{"detail": {"code": …}}`), else nil.
private func recChunkErrorCode(_ data: Data?) -> String? {
    guard let data = data,
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let detail = json["detail"] as? [String: Any],
          let code = detail["code"] as? String, !code.isEmpty else { return nil }
    return code
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ShareAppAudioMixer — the shared app's sound into the live mic
//
// UNTESTED (2026-10-29). flutter_webrtc (fork nextbrain/1.6.2-hotfix.4)
// builds its RTCPeerConnectionFactory with AudioManager.sharedInstance's
// RTCDefaultAudioProcessingModule; that module's capturePostProcessingDelegate
// is AudioManager.capturePostProcessingAdapter, which calls every registered
// ExternalAudioProcessingDelegate with each 10 ms capture buffer AFTER the
// echo canceller / noise suppressor and BEFORE it is encoded and sent
// (common/darwin/Classes/AudioManager.m, AudioProcessingAdapter.m). Adding
// samples there puts them into the published microphone track:
//   • viewers hear the shared app (a video, a lesson app) clean, with no
//     acoustic path and no echo-canceller interference (it runs before us);
//   • it is only heard while the teacher's microphone track is published
//     and capturing (muted mic → no capture callbacks → no app audio). That
//     limitation is documented in docs/live/ios_share_wiring.md.
//
// Data path: extension .audioApp → App Group audio queue (batches of ~6
// buffers, ≈ 60–150 ms) → AppDelegate drain (audioIpcReadQueue) → push():
// decode (16-bit int or 32-bit float, native endian — the extension already
// byte-swaps big-endian, I13), down-mix to mono, linear resampling to the
// capture rate (frames × 100, typically 48 kHz), into a ring buffer. The
// audio thread pulls `frames` samples per callback with a 0.7 gain and
// clamps to the int16 range RTCAudioBuffer uses (float samples, ±32768).
// Jitter: playback starts once 80 ms are buffered (again after an
// underrun); more than 400 ms buffered drops the oldest down to 200 ms, so
// the added latency stays ≈ 100–300 ms (the extension's batching dominates).
// ─────────────────────────────────────────────────────────────────────────────

final class ShareAppAudioMixer: NSObject, ExternalAudioProcessingDelegate {
    private let lock: UnsafeMutablePointer<os_unfair_lock>
    // Ring buffer (mono, capture rate, int16-scale floats). Guarded by lock.
    private var ring = [Float](repeating: 0, count: 48_000)   // 1 s at 48 kHz
    private var readIndex = 0
    private var writeIndex = 0
    private var count = 0
    private var priming = true
    private var targetRate: Double = 48_000
    private var lastProcessTime: CFAbsoluteTime = 0
    private var active = false
    // Resampler state — push() only (audioIpcReadQueue, serial).
    private var resampleSourceRate: Double = 0
    private var resampleTargetRate: Double = 0
    private var resamplePos: Double = 0
    private var resamplePrev: Float = 0

    private let gain: Float = 0.7

    override init() {
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        super.init()
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var isActive: Bool {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return active
    }

    /// True while WebRTC is calling us back (mic capturing), i.e. the app
    /// audio really reaches the published track.
    var isMixingLive: Bool {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return active && CFAbsoluteTimeGetCurrent() - lastProcessTime < 0.5
    }

    func start() {
        os_unfair_lock_lock(lock)
        let wasActive = active
        active = true
        resetRingLocked()
        os_unfair_lock_unlock(lock)
        guard !wasActive else { return }
        AudioManager.sharedInstance().capturePostProcessingAdapter.addProcessing(self)
    }

    func stop() {
        os_unfair_lock_lock(lock)
        let wasActive = active
        active = false
        resetRingLocked()
        os_unfair_lock_unlock(lock)
        guard wasActive else { return }
        AudioManager.sharedInstance().capturePostProcessingAdapter.removeProcessing(self)
    }

    private func resetRingLocked() {
        readIndex = 0; writeIndex = 0; count = 0; priming = true
    }

    /// One audio record payload from the extension:
    /// [4B sampleRate BE][4B channels BE][4B isFloat BE][interleaved PCM].
    /// audioIpcReadQueue only.
    func push(payload: Data) {
        guard payload.count > 12 else { return }
        func be32(_ o: Int) -> UInt32 {
            var v: UInt32 = 0
            for i in 0..<4 { v = (v << 8) | UInt32(payload[payload.startIndex + o + i]) }
            return v
        }
        let srcRate = Double(be32(0))
        let channels = Int(be32(4))
        let isFloat = be32(8) != 0
        guard srcRate > 0, channels > 0 else { return }

        // Decode + down-mix to mono, int16 scale.
        var mono: [Float] = []
        payload.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let pcm = UnsafeRawBufferPointer(rebasing: raw[12...])
            let width = isFloat ? 4 : 2
            let frames = pcm.count / (width * channels)
            guard frames > 0 else { return }
            mono.reserveCapacity(frames)
            let inv = 1 / Float(channels)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels {
                    let offset = (f * channels + c) * width
                    if isFloat {
                        let bits = pcm.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                        sum += Float(bitPattern: bits) * 32767
                    } else {
                        let bits = pcm.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
                        sum += Float(Int16(bitPattern: bits))
                    }
                }
                mono.append(sum * inv)
            }
        }
        guard !mono.isEmpty else { return }

        os_unfair_lock_lock(lock)
        let dstRate = targetRate
        let isOn = active
        os_unfair_lock_unlock(lock)
        guard isOn else { return }

        // Streaming linear resampler (state carried across pushes).
        if resampleSourceRate != srcRate || resampleTargetRate != dstRate {
            resampleSourceRate = srcRate
            resampleTargetRate = dstRate
            resamplePos = 0
            resamplePrev = mono[0]
        }
        let step = srcRate / dstRate          // source samples per output sample
        let n = mono.count
        var out: [Float] = []
        out.reserveCapacity(Int(Double(n) / step) + 2)
        var pos = resamplePos                 // -1 ≤ pos: index -1 = resamplePrev
        while pos <= Double(n - 1) {
            let i = Int(pos.rounded(.down))
            let frac = Float(pos - Double(i))
            let a = i < 0 ? resamplePrev : mono[i]
            let b = (i + 1 < n) ? mono[i + 1] : mono[n - 1]
            out.append(a + (b - a) * frac)
            pos += step
        }
        resamplePos = pos - Double(n)
        resamplePrev = mono[n - 1]

        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard active, targetRate == dstRate else { return }   // rate changed meanwhile
        let cap = ring.count
        for s in out {
            if count == cap {                 // full: drop the oldest
                readIndex = (readIndex + 1) % cap
                count -= 1
            }
            ring[writeIndex] = s
            writeIndex = (writeIndex + 1) % cap
            count += 1
        }
        // Latency cap: > 400 ms buffered → keep the newest 200 ms.
        let high = Int(dstRate * 0.4), keep = Int(dstRate * 0.2)
        if count > high {
            let drop = count - keep
            readIndex = (readIndex + drop) % cap
            count = keep
        }
    }

    // MARK: ExternalAudioProcessingDelegate (WebRTC audio thread)

    func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {
        os_unfair_lock_lock(lock)
        if sampleRateHz > 0 { setTargetRateLocked(Double(sampleRateHz)) }
        os_unfair_lock_unlock(lock)
    }

    func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
        let frames = audioBuffer.frames
        let channels = audioBuffer.channels
        guard frames > 0, channels > 0 else { return }

        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        guard active else { return }
        lastProcessTime = CFAbsoluteTimeGetCurrent()
        // RTCAudioBuffer holds 10 ms: its rate is frames × 100.
        let rate = Double(frames * 100)
        if rate != targetRate { setTargetRateLocked(rate); return }

        let prebuffer = Int(targetRate * 0.08)
        if priming {
            guard count >= prebuffer else { return }
            priming = false
        }
        let n = min(frames, count)
        let cap = ring.count
        for f in 0..<n {
            let s = ring[readIndex] * gain
            readIndex = (readIndex + 1) % cap
            for c in 0..<channels {
                let ptr = audioBuffer.rawBuffer(forChannel: c)
                ptr[f] = max(-32768, min(32767, ptr[f] + s))
            }
        }
        count -= n
        if n < frames { priming = true }      // underrun: buffer up again
    }

    func audioProcessingRelease() {}

    private func setTargetRateLocked(_ rate: Double) {
        guard rate != targetRate else { return }
        targetRate = rate
        let needed = Int(rate)                // 1 s of ring
        if ring.count != needed { ring = [Float](repeating: 0, count: needed) }
        resetRingLocked()
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

// ─────────────────────────────────────────────────────────────────────────────
// VodNowPlaying — the listen bar's lecture on the lock screen / Control Center (D-104)
//
// The sound itself is video_player's AVPlayer (allowBackgroundPlayback + UIBackgroundModes audio). This only
// publishes the title / position / rate to MPNowPlayingInfoCenter and sends the remote commands (play, pause,
// ±10 s, scrub) back to Dart as "command" on the vod_media channel — the same protocol as Android's
// VodMediaService.
// ─────────────────────────────────────────────────────────────────────────────
final class VodNowPlaying {
    static let shared = VodNowPlaying()
    private var channel: FlutterMethodChannel?
    private var targets: [(MPRemoteCommand, Any)] = []
    private var title = ""
    private var subtitle = ""
    private var playing = false
    private var position = 0.0
    private var duration = 0.0
    private var speed = 1.0

    func register(messenger: FlutterBinaryMessenger) {
        let ch = FlutterMethodChannel(name: "com.doubley.alfaheem/vod_media", binaryMessenger: messenger)
        ch.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            let a = call.arguments as? [String: Any] ?? [:]
            switch call.method {
            case "start", "update":
                if let v = a["title"] as? String { self.title = v }
                if let v = a["subtitle"] as? String { self.subtitle = v }
                if let v = a["playing"] as? Bool { self.playing = v }
                if let v = a["position"] as? NSNumber { self.position = v.doubleValue / 1000 }
                if let v = a["duration"] as? NSNumber { self.duration = v.doubleValue / 1000 }
                if let v = a["speed"] as? NSNumber { self.speed = v.doubleValue }
                if call.method == "start" { self.attach() }
                self.publish()
                result(true)
            case "stop":
                self.detach()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        channel = ch
    }

    private func send(_ cmd: String, ms: Int? = nil) {
        var args: [String: Any] = ["cmd": cmd]
        if let ms = ms { args["ms"] = ms }
        channel?.invokeMethod("command", arguments: args)
    }

    private func attach() {
        guard targets.isEmpty else { return }
        let c = MPRemoteCommandCenter.shared()
        targets.append((c.playCommand, c.playCommand.addTarget { [weak self] _ in self?.send("play"); return .success }))
        targets.append((c.pauseCommand, c.pauseCommand.addTarget { [weak self] _ in self?.send("pause"); return .success }))
        targets.append((c.togglePlayPauseCommand, c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.send(self.playing ? "pause" : "play"); return .success }))
        c.skipBackwardCommand.preferredIntervals = [10]
        c.skipForwardCommand.preferredIntervals = [10]
        targets.append((c.skipBackwardCommand, c.skipBackwardCommand.addTarget { [weak self] _ in self?.send("back"); return .success }))
        targets.append((c.skipForwardCommand, c.skipForwardCommand.addTarget { [weak self] _ in self?.send("forward"); return .success }))
        targets.append((c.changePlaybackPositionCommand, c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.send("seek", ms: Int(e.positionTime * 1000)); return .success }))
        for (cmd, _) in targets { cmd.isEnabled = true }
    }

    private func detach() {
        for (cmd, target) in targets { cmd.removeTarget(target) }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func publish() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
