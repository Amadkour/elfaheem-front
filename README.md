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
fopen failed for data file: errno = 2 (No such file or directory)
fopen failed for data file: errno = 2 (No such file or directory)
12.15.0 - [FirebaseCore][I-COR000008] The project's Bundle ID is inconsistent with either the Bundle ID in 'GoogleService-Info.plist', or the Bundle ID in the options if you are using a customized options. To ensure that everything can be configured correctly, you may need to make the Bundle IDs consistent. To continue with this plist file, you may change your app's bundle identifier to 'com.example.flutterEducationApp'. Or you can download a new configuration file that matches your bundle identifier from https://console.firebase.google.com/ and replace the current one.
[Firebase/Crashlytics] Version 12.15.0
12.15.0 - [FirebaseRemoteConfig][I-RCN000072] New config database created. Resetting user defaults.
flutter: The Dart VM service is listening on http://127.0.0.1:50424/UhpXln1HGkY=/
12.15.0 - [FirebaseMessaging][I-FCM001000] FIRMessaging Remote Notifications proxy enabled, will swizzle remote notification receiver handlers. If you'd prefer to manually integrate Firebase Messaging, add "FirebaseAppDelegateProxyEnabled" to your Info.plist, and set it to NO. Follow the instructions at:
https://firebase.google.com/docs/cloud-messaging/ios/client#method_swizzling_in_firebase_messaging
to ensure proper integration.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
no valid “aps-environment” entitlement string found for application
no valid “aps-environment” entitlement string found for application
12.15.0 - [FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application
Reading from public effective user settings.
flutter: [FCM] registerWithBackend error: [firebase_messaging/apns-token-not-set] APNS token has not been received on the device yet. Please ensure the APNS token is available before calling `getAPNSToken()`.
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
Stop video capturer, trackID AAEDF97A-26A9-4223-BA7C-182433455D26
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = AAEDF97A-26A9-4223-BA7C-182433455D26
[LiveKit] Configuring category:  AVAudioSessionCategoryPlayAndRecord
[LiveKit] Configuring categoryOptions:  ["allowBluetooth", "allowBluetoothA2DP", "allowAirPlay"]
[LiveKit] Configuring mode:  AVAudioSessionModeVideoChat
[LiveKit] RTCAudioSession Configure success
[REC] startMicRecording: session=26 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 4192.627284291s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[SHARE] Darwin listeners registered
[REC] background task started id=24
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (149835B isFinal=false audioSeen=138 audioAppended=138 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[SHARE] picker: paused chunk rotated at #1
[REC] chunk #0 HTTP 201 isFinal=false size=149835B
[REC] chunk #0 uploaded OK (149835B isFinal=false)
[REC] background task ended
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] writer session (broadcast) started at 4198.918s
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] writer session (broadcast) started at 4204.076s
[REC] finalised chunk #1 (452393B isFinal=false audioSeen=484 audioAppended=484 sysAudioSeen=226 sysAudioAppended=217 sysAudioPeak=0.99991 sysAudioRms=0.05312)
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 4204.11s
[REC] background task started id=38
[REC] writer session (broadcast) started at 4209.102s
[REC] finalised chunk #2 (1170433B isFinal=false audioSeen=479 audioAppended=479 sysAudioSeen=228 sysAudioAppended=228 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 4209.185s
[REC] chunk #1 HTTP 201 isFinal=false size=452393B
[REC] chunk #1 uploaded OK (452393B isFinal=false)
[REC] writer session (broadcast) started at 4214.252s
[REC] finalised chunk #3 (1280264B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=224 sysAudioAppended=224 sysAudioPeak=1.00003 sysAudioRms=0.19546)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 4214.269s
[REC] writer session (broadcast) started at 4219.336s
[REC] finalised chunk #4 (972137B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=233 sysAudioAppended=233 sysAudioPeak=1.00003 sysAudioRms=0.56213)
[REC] beginChunkWriter: chunk #5 720×1562
[REC] chunk timer scheduled: 5s for chunk #5
[REC] writer session (broadcast) started at 4219.369s
[REC] chunk #2 HTTP 201 isFinal=false size=1170433B
[REC] chunk #2 uploaded OK (1170433B isFinal=false)
[REC] writer session (broadcast) started at 4224.353s
[REC] finalised chunk #5 (893434B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=230 sysAudioAppended=230 sysAudioPeak=1.00003 sysAudioRms=0.56252)
[REC] beginChunkWriter: chunk #6 720×1562
[REC] chunk timer scheduled: 5s for chunk #6
[REC] writer session (broadcast) started at 4224.403s
[REC] writer session (broadcast) started at 4229.37s
[REC] finalised chunk #6 (930832B isFinal=false audioSeen=496 audioAppended=496 sysAudioSeen=232 sysAudioAppended=231 sysAudioPeak=1.00003 sysAudioRms=0.56532)
[REC] beginChunkWriter: chunk #7 720×1562
[REC] chunk timer scheduled: 5s for chunk #7
[REC] writer session (broadcast) started at 4229.387s
[REC] finalised chunk #7 (993213B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=230 sysAudioAppended=230 sysAudioPeak=1.00003 sysAudioRms=0.53976)
[REC] beginChunkWriter: chunk #8 720×1562
[REC] chunk timer scheduled: 5s for chunk #8
[REC] writer session (broadcast) started at 4234.421s
[REC] background task ended
[REC] chunk #3 HTTP 201 isFinal=false size=1280264B
[REC] chunk #3 uploaded OK (1280264B isFinal=false)
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] finalised chunk #8 (893138B isFinal=true audioSeen=400 audioAppended=400 sysAudioSeen=178 sysAudioAppended=178 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
[REC] chunk #4 HTTP 201 isFinal=false size=972137B
[REC] chunk #4 uploaded OK (972137B isFinal=false)
[REC] chunk #5 HTTP 201 isFinal=false size=893434B
[REC] chunk #5 uploaded OK (893434B isFinal=false)
[REC] chunk #6 HTTP 201 isFinal=false size=930832B
[REC] chunk #6 uploaded OK (930832B isFinal=false)
[REC] chunk #7 HTTP 201 isFinal=false size=993213B
[REC] chunk #7 uploaded OK (993213B isFinal=false)
[REC] chunk #8 HTTP 201 isFinal=true size=893138B
[REC] chunk #8 uploaded OK (893138B isFinal=true)
[REC] finalize ping HTTP 201
RTC AudioSession deactive is successful
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success