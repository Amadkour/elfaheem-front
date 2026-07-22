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
12.15.0 - [FirebaseCore][I-COR000008] The project's Bundle ID is inconsistent with either the Bundle ID in 'GoogleService-Info.plist', or the Bundle ID in the options if you are using a customized options. To ensure that everything can be configured correctly, you may need to make the Bundle IDs consistent. To continue with this plist file, you may change your app's bundle identifier to 'com.example.flutterEducationApp'. Or you can download a new configuration file that matches your bundle identifier from https://console.firebase.google.com/ and replace the current one.
flutter: The Dart VM service is listening on http://127.0.0.1:51238/S02-HTQSpgE=/
[Firebase/Crashlytics] Version 12.15.0
12.15.0 - [FirebaseMessaging][I-FCM001000] FIRMessaging Remote Notifications proxy enabled, will swizzle remote notification receiver handlers. If you'd prefer to manually integrate Firebase Messaging, add "FirebaseAppDelegateProxyEnabled" to your Info.plist, and set it to NO. Follow the instructions at:
https://firebase.google.com/docs/cloud-messaging/ios/client#method_swizzling_in_firebase_messaging
to ensure proper integration.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
no valid “aps-environment” entitlement string found for application
no valid “aps-environment” entitlement string found for application
12.15.0 - [FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application

The OS has terminated the Flutter debug connection for being inactive in the background for too long.

There are no errors with your Flutter application.

To reconnect, launch your application again via 'flutter run'
Reading from public effective user settings.
nw_path_necp_check_for_updates Failed to copy updated result (22)
flutter: [FCM] registerWithBackend error: [firebase_messaging/apns-token-not-set] APNS token has not been received on the device yet. Please ensure the APNS token is available before calling `getAPNSToken()`.
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
Reporter disconnected. { function=sendMessage, reporterID=3951369912322 }
The variant selector cell index number could not be found.
The variant selector cell index number could not be found.
The variant selector cell index number could not be found.
The variant selector cell index number could not be found.
The variant selector cell index number could not be found.
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
[LiveKit] Configuring category:  AVAudioSessionCategoryPlayAndRecord
[LiveKit] Configuring categoryOptions:  ["allowBluetooth", "allowBluetoothA2DP", "allowAirPlay"]
[LiveKit] Configuring mode:  AVAudioSessionModeVideoChat
[LiveKit] RTCAudioSession Configure success
codec video/VP8
codec video/H264
codec video/rtx
codec video/H264
codec video/H265
codec video/VP9
codec video/AV1
codec video/red
codec video/ulpfec
codec video/flexfec-03
[REC] startMicRecording: session=22 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 14259.001102166s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[SHARE] Darwin listeners registered
[REC] background task started id=36
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (725724B isFinal=false audioSeen=232 audioAppended=232 sysAudioSeen=0 sysAudioAppended=0)
[SHARE] picker: paused chunk rotated at #1
[REC] upgradeToScreenRecording: still paused after wait — reporting not-yet-active
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] writer session (broadcast) started at 14268.018s
[REC] chunk #0 HTTP 201 isFinal=false size=725724B
[REC] chunk #0 uploaded OK (725724B isFinal=false)
[REC] background task ended
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
-[RTIInputSystemClient remoteTextInputSessionWithID:performInputOperation:]  perform input operation requires a valid sessionID. inputModality = Keyboard, inputOperation = dismissAutoFillPanel, customInfoType = UIUserInteractionRemoteInputOperations
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
[REC] background task started id=50
Snapshotting a view (0x140ec3400, UIKeyboardImpl) that is not in a visible window requires afterScreenUpdates:YES.
[REC] writer session (broadcast) started at 14273.094s
[REC] finalised chunk #1 (1178355B isFinal=false audioSeen=490 audioAppended=490 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 14273.177s
Reporter disconnected or already stopped. { func=stop, reporterID=3951369912322 }
[REC] writer session (broadcast) started at 14278.194s
[REC] finalised chunk #2 (1030939B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 14278.244s
[REC] background task ended
[REC] writer session (broadcast) started at 14283.136s
[REC] finalised chunk #3 (1093921B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 14283.186s
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] writer session (broadcast) started at 14283.569s
[REC] finalised chunk #4 (49518B isFinal=true audioSeen=40 audioAppended=40 sysAudioSeen=0 sysAudioAppended=0)
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
[REC] chunk #1 HTTP 201 isFinal=false size=1178355B
[REC] chunk #1 uploaded OK (1178355B isFinal=false)
[REC] chunk #2 HTTP 201 isFinal=false size=1030939B
[REC] chunk #2 uploaded OK (1030939B isFinal=false)
[REC] chunk #3 HTTP 201 isFinal=false size=1093921B
[REC] chunk #3 uploaded OK (1093921B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=true size=49518B
[REC] chunk #4 uploaded OK (49518B isFinal=true)
[REC] finalize ping HTTP 201
Stop video capturer, trackID 18DC141E-33F1-4FEE-8661-6AB027B844CA
RTC AudioSession deactive is successful
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = 18DC141E-33F1-4FEE-8661-6AB027B844CA
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success