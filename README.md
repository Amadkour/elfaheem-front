# elfaheem-flutter



// Student                 Flutter App            Backend             Moyasar
// │                         │                       │                    │
// │  ─── اضغط "اشترك" ───►  │                       │                    │
// │                         │  GET /fees/preview    │                    │
// │  ◄── تفاصيل الرسوم ───  │ ◄──────────────────── │                    │
// │                         │                       │                    │
// │  ─── اختر مدى ────────► │                       │                    │
// │                         │  POST /payments       │                    │
// │                         │ ──────────────────────►                    │
// │                         │                       │  POST /v1/payments │
// │                         │                       │ ───────────────────►
// │                         │                       │  ◄── checkout_url ─┤
// │                         │ ◄── {checkout_url} ── │                    │
// │                         │                       │                    │
// │  ◄── فتح صفحة Moyasar ─ │                       │                    │
// │  ─── إدخال بيانات ────► │ (browser/webview)     │                    │
// │                         │                       │  ◄── webhook paid ─┤
// │                         │                       │  تفعيل الكورس      │
// │  ◄── إشعار التفعيل ──── │ ◄── notification ──── │                    │

// ---------------------------------[Bank transfer]-----------------------------

// Student           Flutter App           Backend           Admin
// │                     │                    │                │
// │  ─── اضغط "تحويل" ► │                    │                │
// │                     │  POST /bank-transfer                │
// │                     │ ─────────────────► │                │
// │  ◄── بيانات الحساب ─│ ◄── {iban, ref} ── │                │
// │                     │                    │                │
// │  ─── يحوّل من بنكه ► │ (خارج التطبيق)     │                │
// │                     │                    │                │
// │                     │                    │ ◄── يتحقق ──── │
// │                     │                    │  POST /confirm │
// │                     │                    │  تفعيل الكورس  │
// │  ◄── إشعار التفعيل ─────────────────────── notification ─ │


-- LLDB integration loaded --
`UIScene` lifecycle will soon be required. Failure to adopt will result in an assert in the future.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
Dart execution mode: JIT
flutter: The Dart VM service is listening on http://127.0.0.1:60208/D-t14PjdlfU=/
12.15.0 - [FirebaseCore][I-COR000008] The project's Bundle ID is inconsistent with either the Bundle ID in 'GoogleService-Info.plist', or the Bundle ID in the options if you are using a customized options. To ensure that everything can be configured correctly, you may need to make the Bundle IDs consistent. To continue with this plist file, you may change your app's bundle identifier to 'com.example.flutterEducationApp'. Or you can download a new configuration file that matches your bundle identifier from https://console.firebase.google.com/ and replace the current one.
[Firebase/Crashlytics] Version 12.15.0
12.15.0 - [FirebaseMessaging][I-FCM001000] FIRMessaging Remote Notifications proxy enabled, will swizzle remote notification receiver handlers. If you'd prefer to manually integrate Firebase Messaging, add "FirebaseAppDelegateProxyEnabled" to your Info.plist, and set it to NO. Follow the instructions at:
https://firebase.google.com/docs/cloud-messaging/ios/client#method_swizzling_in_firebase_messaging
to ensure proper integration.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
no valid “aps-environment” entitlement string found for application
no valid “aps-environment” entitlement string found for application
12.15.0 - [FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application
Reading from public effective user settings.
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
Stop video capturer, trackID 3742CFB4-8CFB-45BA-8FC9-5A9085A1F628
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = 3742CFB4-8CFB-45BA-8FC9-5A9085A1F628
[LiveKit] Configuring category:  AVAudioSessionCategoryPlayAndRecord
[LiveKit] Configuring categoryOptions:  ["allowBluetooth", "allowBluetoothA2DP", "allowAirPlay"]
[LiveKit] Configuring mode:  AVAudioSessionModeVideoChat
[LiveKit] RTCAudioSession Configure success
[REC] startMicRecording: session=25 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 56173.99569225s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[SHARE] Darwin listeners registered
[REC] background task started id=11
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (95184B isFinal=false audioSeen=124 audioAppended=124 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[SHARE] picker: paused chunk rotated at #1
[REC] chunk #0 HTTP 201 isFinal=false size=95184B
[REC] chunk #0 uploaded OK (95184B isFinal=false)
[REC] background task ended
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] writer session (broadcast) started at 56180.328s
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] background task started id=30
[REC] writer session (broadcast) started at 56185.412s
[REC] finalised chunk #1 (1305744B isFinal=false audioSeen=480 audioAppended=480 sysAudioSeen=215 sysAudioAppended=211 sysAudioPeak=0.99991)
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 56185.445s
[REC] writer session (broadcast) started at 56190.429s
[REC] system-audio dropped — systemAudioInput not ready (nil=true)
[REC] finalised chunk #2 (791139B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=231 sysAudioAppended=230 sysAudioPeak=1.00003)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 56190.462s
[REC] writer session (broadcast) started at 56195.463s
[REC] finalised chunk #3 (792044B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=231 sysAudioAppended=230 sysAudioPeak=1.00003)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 56195.496s
[REC] background task ended
[REC] chunk #1 HTTP 201 isFinal=false size=1305744B
[REC] chunk #1 uploaded OK (1305744B isFinal=false)
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] finalised chunk #4 (1033901B isFinal=true audioSeen=448 audioAppended=448 sysAudioSeen=199 sysAudioAppended=199 sysAudioPeak=1.00003)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping