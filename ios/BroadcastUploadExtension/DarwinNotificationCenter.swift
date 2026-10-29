// DarwinNotificationCenter.swift
// BroadcastUploadExtension target
//
// UNTESTED (written on Windows, 2026-10-29) — see docs/live/ios_test_plan.md.
//
// Darwin notifications are the only signal that crosses the app ↔ extension
// process boundary without extra entitlements. Names:
//
//   iOS_BroadcastStarted / iOS_BroadcastStopped / iOS_BroadcastRequestStop
//     MUST match livekit_client 2.13.1 (ios/livekit_client/Sources/
//     livekit_client/DarwinNotificationCenter.swift). LiveKit's BroadcastManager
//     turns Started / Stopped into BroadcastManager().isBroadcasting, which
//     publishes / unpublishes the screen-share track; BroadcastManager().
//     requestStop() (and AppDelegate's "requestBroadcastStop") posts
//     RequestStop, which this extension answers with finishBroadcastWithError.
//
//   com.example.flutter_education_app.*  — this app's own recording IPC
//     (frame / audioframe / stop, plus wants_changed); must match
//     AppDelegate.swift.

import Foundation

enum DarwinNotification: String {
    case broadcastStarted     = "iOS_BroadcastStarted"
    case broadcastStopped     = "iOS_BroadcastStopped"
    case broadcastRequestStop = "iOS_BroadcastRequestStop"
    // App recording IPC (AppDelegate.swift kDarwin* constants).
    case recordingFrame       = "com.example.flutter_education_app.frame"
    case recordingAudio       = "com.example.flutter_education_app.audioframe"
    case recordingStop        = "com.example.flutter_education_app.stop"
    /// Posted by the app after it changed one of the ext_wants_* marker files.
    case wantsChanged         = "com.example.flutter_education_app.wants_changed"
}

final class DarwinNotificationCenter {
    static let shared = DarwinNotificationCenter()

    private let center = CFNotificationCenterGetDarwinNotifyCenter()
    private let lock = NSLock()
    private var handlers: [String: () -> Void] = [:]

    func post(_ name: DarwinNotification) {
        CFNotificationCenterPostNotification(
            center, CFNotificationName(rawValue: name.rawValue as CFString), nil, nil, true)
    }

    /// One handler per name (a later call replaces it). The handler runs on
    /// whatever thread the Darwin center delivers on; keep it short.
    func observe(_ name: DarwinNotification, _ handler: @escaping () -> Void) {
        lock.lock()
        let isNew = handlers[name.rawValue] == nil
        handlers[name.rawValue] = handler
        lock.unlock()
        guard isNew else { return }
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, cfName, _, _ in
                guard let observer = observer, let cfName = cfName else { return }
                let me = Unmanaged<DarwinNotificationCenter>.fromOpaque(observer).takeUnretainedValue()
                me.dispatch(cfName.rawValue as String)
            },
            name.rawValue as CFString, nil, .deliverImmediately)
    }

    func removeAll() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    private func dispatch(_ name: String) {
        lock.lock()
        let handler = handlers[name]
        lock.unlock()
        handler?()
    }
}
