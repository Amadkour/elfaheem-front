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
[REC] startMicRecording: session=25 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 57651.03023325s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
Stop video capturer, trackID D851332D-B40E-4B4C-80ED-CD6A32DADB5E
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = D851332D-B40E-4B4C-80ED-CD6A32DADB5E
[REC] finalised chunk #0 (828508B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[REC] writer session started at 57656.065826583s
[SHARE] Darwin listeners registered
[REC] background task started id=302
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #1 (52058B isFinal=false audioSeen=36 audioAppended=36 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[SHARE] picker: paused chunk rotated at #2
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[SHARE] recording resumed from picker-pause — broadcast chunk #2
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] writer session (broadcast) started at 57662.314s
[REC] chunk #0 HTTP 201 isFinal=false size=828508B
[REC] chunk #0 uploaded OK (828508B isFinal=false)
[REC] chunk #1 HTTP 201 isFinal=false size=52058B
[REC] chunk #1 uploaded OK (52058B isFinal=false)
[REC] background task ended
[REC] writer session (broadcast) started at 57667.389s
[REC] finalised chunk #2 (1119672B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=227 sysAudioAppended=227 sysAudioPeak=0.98431)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 57667.423s
[REC] background task started id=316
[REC] writer session (broadcast) started at 57672.457s
[REC] finalised chunk #3 (1171919B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=229 sysAudioAppended=228 sysAudioPeak=1.00000)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 57672.49s
[REC] writer session (broadcast) started at 57677.49s
[REC] system-audio dropped — systemAudioInput not ready (nil=true)
[REC] finalised chunk #4 (800096B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=230 sysAudioAppended=230 sysAudioPeak=1.00003)
[REC] beginChunkWriter: chunk #5 720×1562
[REC] chunk timer scheduled: 5s for chunk #5
[REC] writer session (broadcast) started at 57677.524s
[REC] chunk #2 HTTP 201 isFinal=false size=1119672B
[REC] chunk #2 uploaded OK (1119672B isFinal=false)
[REC] writer session (broadcast) started at 57682.508s
[REC] finalised chunk #5 (1097074B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=230 sysAudioAppended=229 sysAudioPeak=1.00003)
[REC] beginChunkWriter: chunk #6 720×1562
[REC] chunk timer scheduled: 5s for chunk #6
[REC] writer session (broadcast) started at 57682.541s
[REC] background task ended
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] writer session (broadcast) started at 57685.049s
[REC] finalised chunk #6 (538046B isFinal=true audioSeen=256 audioAppended=256 sysAudioSeen=114 sysAudioAppended=114 sysAudioPeak=0.00000)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
[REC] chunk #3 HTTP 201 isFinal=false size=1171919B
[REC] chunk #3 uploaded OK (1171919B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=false size=800096B
[REC] chunk #4 uploaded OK (800096B isFinal=false)
[REC] chunk #5 HTTP 201 isFinal=false size=1097074B
[REC] chunk #5 uploaded OK (1097074B isFinal=false)
[REC] chunk #6 HTTP 201 isFinal=true size=538046B
[REC] chunk #6 uploaded OK (538046B isFinal=true)
[REC] finalize ping HTTP 201
RTC AudioSession deactive is successful
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success