target format 1920x1080, targetFps: 0, selected format: 1920x1080, selected fps 0
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
Stop video capturer, trackID 70F70B72-CA39-4A5E-9CE3-EFF037E432A2
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:569) - (err=-17281)
video capturer stopped, trackID = 70F70B72-CA39-4A5E-9CE3-EFF037E432A2
[LiveKit] Configuring category:  AVAudioSessionCategoryPlayAndRecord
[LiveKit] Configuring categoryOptions:  ["allowBluetooth", "allowBluetoothA2DP", "allowAirPlay"]
[LiveKit] Configuring mode:  AVAudioSessionModeVideoChat
[LiveKit] RTCAudioSession Configure success
[REC] startMicRecording: session=26 chunkSecs=5
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] beginChunkWriter: chunk #0 720×1564
[REC] chunk timer scheduled: 5s for chunk #0
[REC] RPScreenRecorder started — chunk #0
[REC] writer session started at 8759.956632625s
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[REC] AVAudioSession: delayed re-arm applied
[REC] AVAudioSession: playAndRecord / videoRecording / mixWithOthers — active (broadcast share, non-ducking mode)
[SHARE] Darwin listeners registered
[REC] background task started id=182
[SHARE] picker: recording paused before system overlay
[SHARE] showBroadcastPicker — extension: com.softkour.alfaheem.BroadcastUploadExtension
[REC] finalised chunk #0 (250008B isFinal=false audioSeen=204 audioAppended=204 sysAudioSeen=0 sysAudioAppended=0 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[SHARE] picker: paused chunk rotated at #1
[REC] chunk #0 HTTP 201 isFinal=false size=250008B
[REC] chunk #0 uploaded OK (250008B isFinal=false)
[REC] background task ended
[SHARE] first broadcast frame — switching recording source
[REC] beginChunkWriter: chunk #1 720×1562
[REC] chunk timer scheduled: 5s for chunk #1
[SHARE] recording resumed from picker-pause — broadcast chunk #1
[REC] writer session (broadcast) started at 8768.398s
[REC] writer session (broadcast) started at 8773.357s
[REC] finalised chunk #1 (512799B isFinal=false audioSeen=502 audioAppended=502 sysAudioSeen=221 sysAudioAppended=221 sysAudioPeak=0.99982 sysAudioRms=0.02804)
[REC] beginChunkWriter: chunk #2 720×1562
[REC] chunk timer scheduled: 5s for chunk #2
[REC] writer session (broadcast) started at 8773.39s
[REC] background task started id=201
[REC] writer session (broadcast) started at 8778.649s
[REC] system-audio dropped — systemAudioInput is nil
[REC] system-audio dropped — systemAudioInput is nil
[REC] system-audio dropped — systemAudioInput is nil
[REC] system-audio dropped — systemAudioInput is nil
[REC] system-audio dropped — systemAudioInput is nil
[REC] system-audio dropped — systemAudioInput is nil
[REC] finalised chunk #2 (1126378B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=231 sysAudioAppended=229 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[REC] beginChunkWriter: chunk #3 720×1562
[REC] chunk timer scheduled: 5s for chunk #3
[REC] writer session (broadcast) started at 8778.707s
[REC] chunk #1 HTTP 201 isFinal=false size=512799B
[REC] chunk #1 uploaded OK (512799B isFinal=false)
[REC] writer session (broadcast) started at 8783.857s
[REC] finalised chunk #3 (930015B isFinal=false audioSeen=500 audioAppended=500 sysAudioSeen=240 sysAudioAppended=235 sysAudioPeak=1.00003 sysAudioRms=0.55384)
[REC] beginChunkWriter: chunk #4 720×1562
[REC] chunk timer scheduled: 5s for chunk #4
[REC] writer session (broadcast) started at 8783.891s
[REC] writer session (broadcast) started at 8788.85s
[REC] finalised chunk #4 (1097080B isFinal=false audioSeen=498 audioAppended=498 sysAudioSeen=229 sysAudioAppended=228 sysAudioPeak=1.00003 sysAudioRms=0.50876)
[REC] beginChunkWriter: chunk #5 720×1562
[REC] chunk timer scheduled: 5s for chunk #5
[REC] writer session (broadcast) started at 8788.883s
[REC] background task ended
[REC] chunk #2 HTTP 201 isFinal=false size=1126378B
[REC] chunk #2 uploaded OK (1126378B isFinal=false)
[REC] stopRecording: isFinal=true isBroadcasting=true
[SHARE] Darwin listeners removed
[REC] writer session (broadcast) started at 8791.558s
[REC] finalised chunk #5 (602555B isFinal=true audioSeen=270 audioAppended=270 sysAudioSeen=126 sysAudioAppended=125 sysAudioPeak=0.00000 sysAudioRms=0.00000)
[REC] mic recordPermission=granted isInputAvailable=true
[REC] AVAudioSession: playAndRecord / videoChat / mixWithOthers — active
[ERROR] -[RPScreenRecorder stopCaptureWithHandler:]:564 failed to stop in app capture because we're not recording
[REC] stopCapture: Failed due to attempting to stop a recording that wasn’t in recording state
[REC] stopCapture done — queuing finalize ping
[REC] chunk #3 HTTP 201 isFinal=false size=930015B
[REC] chunk #3 uploaded OK (930015B isFinal=false)
[REC] chunk #4 HTTP 201 isFinal=false size=1097080B
[REC] chunk #4 uploaded OK (1097080B isFinal=false)
[REC] chunk #5 HTTP 201 isFinal=true size=602555B
[REC] chunk #5 uploaded OK (602555B isFinal=true)
[REC] finalize ping HTTP 201
RTC AudioSession deactive is successful
[LiveKit] Configuring category:  AVAudioSessionCategorySoloAmbient
[LiveKit] Configuring categoryOptions:  []
[LiveKit] Configuring mode:  AVAudioSessionModeDefault
[LiveKit] RTCAudioSession Configure success
