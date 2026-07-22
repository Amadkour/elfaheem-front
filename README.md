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
flutter: The Dart VM service is listening on http://127.0.0.1:55515/i6iLE25t1fA=/
12.15.0 - [FirebaseRemoteConfig][I-RCN000072] New config database created. Resetting user defaults.
12.15.0 - [FirebaseMessaging][I-FCM001000] FIRMessaging Remote Notifications proxy enabled, will swizzle remote notification receiver handlers. If you'd prefer to manually integrate Firebase Messaging, add "FirebaseAppDelegateProxyEnabled" to your Info.plist, and set it to NO. Follow the instructions at:
https://firebase.google.com/docs/cloud-messaging/ios/client#method_swizzling_in_firebase_messaging
to ensure proper integration.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
no valid “aps-environment” entitlement string found for application
no valid “aps-environment” entitlement string found for application
12.15.0 - [FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
Reading from public effective user settings.
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
flutter: [FCM] registerWithBackend error: [firebase_messaging/apns-token-not-set] APNS token has not been received on the device yet. Please ensure the APNS token is available before calling `getAPNSToken()`.
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
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
[REC] startMicRecording: session=24 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 36563.375073125s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[SHARE] Darwin listeners registered
[REC] background task started id=29
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (1509101B isFinal=false audioSeen=336 audioAppended=336 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[SHARE] picker: paused chunk rotated at #1
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] writer session (broadcast) started at 36570.515s
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] writer session (broadcast) started at 36575.607s
[REC] finalised chunk #1 (1228682B isFinal=false audioSeen=492 audioAppended=492 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 36575.624s
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] writer session (broadcast) started at 36580.716s
[REC] finalised chunk #2 (1277634B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 36580.75s
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] chunk #0 HTTP 201 isFinal=false size=1509101B
[REC] chunk #0 uploaded OK (1509101B isFinal=false)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] writer session (broadcast) started at 36585.708s
[REC] finalised chunk #3 (1167584B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 36585.725s
[REC] background task ended
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] finalised chunk #4 (1012815B isFinal=true audioSeen=402 audioAppended=402 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x1073d9900:udp
[REC] chunk #1 HTTP 201 isFinal=false size=1228682B
[REC] chunk #1 uploaded OK (1228682B isFinal=false)
[REC] chunk #2 HTTP 201 isFinal=false size=1277634B
[REC] chunk #2 uploaded OK (1277634B isFinal=false)
[REC] chunk #3 HTTP 201 isFinal=false size=1167584B
[REC] chunk #3 uploaded OK (1167584B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=true size=1012815B
[REC] chunk #4 uploaded OK (1012815B isFinal=true)
[REC] finalize ping HTTP 201
Stop video capturer, trackID FFD54BD2-DCDA-4321-8C3F-33BC159527D7
RTC AudioSession deactive is successful
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success
video capturer stopped, trackID = FFD54BD2-DCDA-4321-8C3F-33BC159527D7