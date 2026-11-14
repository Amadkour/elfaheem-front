// SocketConnection.swift
// BroadcastUploadExtension target
//
// UNTESTED (written on Windows, 2026-10-29) — see docs/live/ios_test_plan.md.
//
// Client side of flutter_webrtc's screen-share socket. The app process
// (flutter_webrtc FlutterBroadcastScreenCapturer → FlutterSocketConnection)
// binds and listens on a Unix domain socket at
//     <App Group container>/rtc_SSFD
// as soon as LiveKit creates the screen-share track (deviceId
// "broadcast-manual"). This class connects to it and exposes a write
// stream; SampleUploader pushes framed JPEG messages through it.
//
// Adapted from the reference broadcast extension shipped with
// livekit_client 2.13.1 (example/ios/LiveKit Broadcast Extension/
// SocketConnection.swift, originally Jitsi / 8x8), with two deliberate
// changes:
//   1. The streams are scheduled on ONE dedicated thread with its own run
//      loop (like flutter_webrtc's server side, FlutterSocketConnection.m).
//      The reference scheduled them on a global-queue thread and later
//      "unscheduled" them from whatever thread called close(), i.e. from a
//      different run loop than the one they were on.
//   2. open() creates a FRESH socket for every attempt and closes it when
//      connect() fails. The reference kept retrying connect() on the same
//      descriptor; after a failed connect() the state of a socket is
//      unspecified by POSIX, and a stale rtc_SSFD file left by an earlier
//      session makes the first attempts fail.

import Foundation

final class SocketConnection: NSObject {
    /// Called on the network thread once the write stream is open.
    var didOpen: (() -> Void)?
    /// Called on the network thread when the server closed the socket
    /// (error == nil) or the stream failed (error != nil). Called once.
    var didClose: ((Error?) -> Void)?
    /// Called on the network thread when the write stream can take bytes.
    var streamHasSpaceAvailable: (() -> Void)?

    private let filePath: String
    private var socketHandle: Int32 = -1

    private var inputStream: InputStream?
    private var outputStream: OutputStream?

    private var networkThread: Thread?
    private let stateLock = NSLock()
    private var closed = false

    init(filePath path: String) {
        filePath = path
        super.init()
    }

    /// One connection attempt. Returns true when connect() succeeded and the
    /// streams were scheduled. Safe to call repeatedly until it succeeds.
    func open() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !closed, inputStream == nil else { return false }

        // flutter_webrtc creates the file when it binds; nothing to connect to
        // before that (the track does not exist yet).
        guard FileManager.default.fileExists(atPath: filePath) else { return false }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(filePath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else {
            NSLog("[SocketConnection] socket path too long (\(pathBytes.count) >= \(capacity))")
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in pathBytes.enumerated() { raw[i] = b }
            raw[pathBytes.count] = 0
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("[SocketConnection] socket() failed errno=\(errno)")
            return false
        }
        // A write to a socket whose peer went away must not kill the
        // extension with SIGPIPE; the stream reports an error instead.
        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe,
                       socklen_t(MemoryLayout<Int32>.size))

        let status = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else {
            // ENOENT / ECONNREFUSED while the app has not started listening yet.
            Darwin.close(fd)
            return false
        }
        socketHandle = fd

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocket(kCFAllocatorDefault, fd, &readStream, &writeStream)
        guard let rs = readStream?.takeRetainedValue(),
              let ws = writeStream?.takeRetainedValue() else {
            Darwin.close(fd)
            socketHandle = -1
            return false
        }
        let input = rs as InputStream     // toll-free bridged
        let output = ws as OutputStream
        // The streams own the descriptor from here on.
        let closeNative = Stream.PropertyKey(kCFStreamPropertyShouldCloseNativeSocket as String)
        input.setProperty(kCFBooleanTrue, forKey: closeNative)
        output.setProperty(kCFBooleanTrue, forKey: closeNative)
        input.delegate = self
        output.delegate = self
        inputStream = input
        outputStream = output

        let thread = Thread {
            // A port keeps run(mode:before:) blocking (instead of returning at
            // once and spinning) before the streams are scheduled and after
            // they are removed. The loop ends when close() cancels the thread.
            RunLoop.current.add(NSMachPort(), forMode: .default)
            while !Thread.current.isCancelled {
                autoreleasepool {
                    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.5))
                }
            }
        }
        thread.name = "broadcast.socket"
        thread.qualityOfService = .userInitiated
        networkThread = thread
        thread.start()
        perform(#selector(scheduleStreams), on: thread, with: nil, waitUntilDone: true)
        input.open()
        output.open()
        return true
    }

    /// Idempotent. Never calls didClose (the caller asked for it).
    func close() {
        stateLock.lock()
        let alreadyClosed = closed
        closed = true
        let thread = networkThread
        stateLock.unlock()
        guard !alreadyClosed else { return }
        tearDown(on: thread)
    }

    /// Writes up to `length` bytes. Returns the number written, 0 or -1.
    func writeToStream(buffer: UnsafePointer<UInt8>, maxLength length: Int) -> Int {
        outputStream?.write(buffer, maxLength: length) ?? -1
    }

    // MARK: - Private

    private func tearDown(on thread: Thread?) {
        if let thread = thread, thread.isExecuting {
            perform(#selector(unscheduleStreams), on: thread, with: nil, waitUntilDone: true)
            thread.cancel()
        }
        inputStream?.delegate = nil
        outputStream?.delegate = nil
        inputStream?.close()
        outputStream?.close()
        inputStream = nil
        outputStream = nil
        socketHandle = -1
        networkThread = nil
    }

    @objc private func scheduleStreams() {
        inputStream?.schedule(in: .current, forMode: .common)
        outputStream?.schedule(in: .current, forMode: .common)
    }

    @objc private func unscheduleStreams() {
        inputStream?.remove(from: .current, forMode: .common)
        outputStream?.remove(from: .current, forMode: .common)
    }

    /// Runs on the network thread. Closes once and reports it.
    private func remoteClosed(_ error: Error?) {
        stateLock.lock()
        let alreadyClosed = closed
        closed = true
        stateLock.unlock()
        guard !alreadyClosed else { return }
        // We are ON the network thread: unschedule directly instead of
        // performSelector-waiting on ourselves.
        unscheduleStreams()
        networkThread?.cancel()
        tearDown(on: nil)
        didClose?(error)
    }
}

extension SocketConnection: StreamDelegate {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            if aStream === outputStream { didOpen?() }
        case .hasBytesAvailable:
            // flutter_webrtc never sends anything; bytes here only mean EOF
            // bookkeeping. read() == 0 at end of stream = server closed.
            if aStream === inputStream {
                var byte: UInt8 = 0
                let n = inputStream?.read(&byte, maxLength: 1) ?? 0
                if n == 0 && aStream.streamStatus == .atEnd {
                    remoteClosed(nil)
                }
            }
        case .hasSpaceAvailable:
            if aStream === outputStream { streamHasSpaceAvailable?() }
        case .endEncountered:
            remoteClosed(nil)
        case .errorOccurred:
            NSLog("[SocketConnection] stream error: \(String(describing: aStream.streamError))")
            remoteClosed(aStream.streamError)
        default:
            break
        }
    }
}
