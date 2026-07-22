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
flutter: The Dart VM service is listening on http://127.0.0.1:54187/nBXemsY8iBQ=/
[Firebase/Crashlytics] Version 12.15.0
12.15.0 - [FirebaseMessaging][I-FCM001000] FIRMessaging Remote Notifications proxy enabled, will swizzle remote notification receiver handlers. If you'd prefer to manually integrate Firebase Messaging, add "FirebaseAppDelegateProxyEnabled" to your Info.plist, and set it to NO. Follow the instructions at:
https://firebase.google.com/docs/cloud-messaging/ios/client#method_swizzling_in_firebase_messaging
to ensure proper integration.
FlutterView implements focusItemsInRect: - caching for linear focus movement is limited as long as this view is on screen.
no valid “aps-environment” entitlement string found for application
no valid “aps-environment” entitlement string found for application
12.15.0 - [FirebaseMessaging][I-FCM012002] Error in application:didFailToRegisterForRemoteNotificationsWithError: no valid “aps-environment” entitlement string found for application
nw_connection_copy_protocol_metadata_internal_block_invoke [C5] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_protocol_metadata_internal_block_invoke [C5] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_protocol_metadata_internal_block_invoke [C5] Client called nw_connection_copy_protocol_metadata_internal on unconnected nw_connection
nw_connection_copy_connected_local_endpoint_block_invoke [C5] Client called nw_connection_copy_connected_local_endpoint on unconnected nw_connection
nw_connection_copy_connected_remote_endpoint_block_invoke [C5] Client called nw_connection_copy_connected_remote_endpoint on unconnected nw_connection
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
Reading from public effective user settings.
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
(Fig) signalled err=-12710 at <>:601
target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
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
[REC] startMicRecording: session=23 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
<<<< FigApplicationStateMonitor >>>> signalled err=-19431 at <>:474
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 31780.126950958s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
[SHARE] Darwin listeners registered
[REC] background task started id=11
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (1770067B isFinal=false audioSeen=366 audioAppended=366 sysAudioSeen=0 sysAudioAppended=0)
[SHARE] picker: paused chunk rotated at #1
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1564
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] writer session (broadcast) started at 31787.668s
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
[REC] finalised chunk #1 (1146364B isFinal=false audioSeen=496 audioAppended=496 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #2 720×1564
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 31792.785s
[REC] finalised chunk #2 (1029805B isFinal=false audioSeen=494 audioAppended=494 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #3 720×1564
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 31797.753s
[REC] background task ended
[REC] finalised chunk #3 (1155082B isFinal=false audioSeen=490 audioAppended=489 sysAudioSeen=0 sysAudioAppended=0)
[REC] beginChunkWriter: chunk #4 720×1564
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 31802.67s
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] finalised chunk #4 (483978B isFinal=true audioSeen=206 audioAppended=207 sysAudioSeen=0 sysAudioAppended=0)
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
[REC] chunk #0 HTTP 201 isFinal=false size=1770067B
[REC] chunk #0 uploaded OK (1770067B isFinal=false)
[REC] chunk #1 HTTP 201 isFinal=false size=1146364B
[REC] chunk #1 uploaded OK (1146364B isFinal=false)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
[REC] chunk #2 HTTP 201 isFinal=false size=1029805B
[REC] chunk #2 uploaded OK (1029805B isFinal=false)
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
[REC] chunk #3 HTTP 201 isFinal=false size=1155082B
[REC] chunk #3 uploaded OK (1155082B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=true size=483978B
[REC] chunk #4 uploaded OK (483978B isFinal=true)
Stop video capturer, trackID 68AF1C6C-E83B-4D4A-B001-F77DBEC21629
[REC] finalize ping HTTP 201
RTC AudioSession deactive is successful
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = 68AF1C6C-E83B-4D4A-B001-F77DBEC21629
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp
nw_protocol_instance_set_output_handler Not calling remove_input_handler on 0x132532800:udp