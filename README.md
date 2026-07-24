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


AVAudioSessionModeVideoChat
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
[REC] writer session started at 56956.087423041s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[REC] finalised chunk #0 (1016087B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[REC] writer session started at 56961.114300416s
Stop video capturer, trackID D60C599D-6229-48A2-A367-918C52B13D24
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = D60C599D-6229-48A2-A367-918C52B13D24
[SHARE] Darwin listeners registered
[REC] background task started id=176
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #1 (302893B isFinal=false audioSeen=220 audioAppended=220 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000)
[SHARE] picker: paused chunk rotated at #2
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[SHARE] recording resumed from picker-pause — broadcast chunk #2
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] Audio session observer: re-applied broadcast-share mode after route change
[REC] writer session (broadcast) started at 56967.513s
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] system-audio dropped — systemAudioInput not ready (nil=false)
[REC] chunk #0 HTTP 201 isFinal=false size=1016087B
[REC] chunk #0 uploaded OK (1016087B isFinal=false)
[REC] finalised chunk #2 (1156364B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=222 sysAudioAppended=220 sysAudioPeak=0.99997)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 56972.605s
[REC] chunk #1 HTTP 201 isFinal=false size=302893B
[REC] chunk #1 uploaded OK (302893B isFinal=false)
[REC] writer session (broadcast) started at 56977.605s
[REC] system-audio dropped — systemAudioInput not ready (nil=true)
[REC] finalised chunk #3 (784770B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=230 sysAudioAppended=230 sysAudioPeak=1.00003)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 56977.639s
[REC] background task ended
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] finalised chunk #4 (1062372B isFinal=true audioSeen=470 audioAppended=470 sysAudioSeen=211 sysAudioAppended=210 sysAudioPeak=1.00003)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
[REC] chunk #2 HTTP 201 isFinal=false size=1156364B
[REC] chunk #2 uploaded OK (1156364B isFinal=false)
[REC] chunk #3 HTTP 201 isFinal=false size=784770B
[REC] chunk #3 uploaded OK (784770B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=true size=1062372B
[REC] chunk #4 uploaded OK (1062372B isFinal=true)
[REC] finalize ping HTTP 201
RTC AudioSession deactive is successful
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success