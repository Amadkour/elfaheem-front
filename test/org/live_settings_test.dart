// The super admin's Live performance settings (D-089): the tolerant JSON model, the PUT body (only what changed),
// the admin payload and the bandwidth preview's arithmetic.
import 'package:flutter_education_app/features/admin/live_settings/live_settings_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson reads every field; a missing or unknown value is the fallback', () {
    final d = LiveSettingsDraft.fromJson({
      'video_codec': 'H264',
      'weak_network': 'audio_first',
      'camera_max_host': '540p',
      'camera_max_participant': '180p',
      'camera_fps': 30.0,
      'screen_fps_max': 10,
      'screen_bitrate_kbps': 4000,
      'audio_dtx': false,
      'audio_red': true,
      'participants_camera_default_off': false,
      'pause_hidden_video': true,
      'recording_mode': 'client',
      'server_recording_engine': 'media',
      'server_recording_tiers': 'all',
    });
    expect(d.videoCodec, 'h264');
    expect(d.weakNetwork, 'audio_first');
    expect(d.cameraMaxHost, '540p');
    expect(d.cameraMaxParticipant, '180p');
    expect(d.cameraFps, 30);
    expect(d.screenFpsMax, 10);
    expect(d.screenBitrateKbps, 4000);
    expect(d.audioDtx, isFalse);
    expect(d.participantsCameraDefaultOff, isFalse);
    expect(d.recordingMode, 'client');
    expect(d.serverRecordingEngine, 'media');
    expect(d.serverRecordingTiers, 'all');

    final bad = LiveSettingsDraft.fromJson({
      'video_codec': 'av1',
      'camera_fps': 20,
      'screen_fps_max': 99,
      'screen_bitrate_kbps': 2500.5,
      'audio_dtx': 'yes',
      'recording_mode': null,
    });
    expect(bad, LiveSettingsDraft.recommended);
    expect(LiveSettingsDraft.fromJson(null), LiveSettingsDraft.recommended);
  });

  test('toJson round-trips; changesFrom is the PUT body', () {
    const r = LiveSettingsDraft.recommended;
    expect(LiveSettingsDraft.fromJson(r.toJson()), r);
    expect(r.toJson().keys, containsAll(['video_codec', 'server_recording_tiers', 'pause_hidden_video']));
    final d = r.copyWith(videoCodec: 'vp9', screenFpsMax: 8, audioRed: false);
    expect(d.changesFrom(r), {'video_codec': 'vp9', 'screen_fps_max': 8, 'audio_red': false});
    expect(d.differencesFrom(r), 3);
    expect(r.changesFrom(r), isEmpty);
    expect(d == r, isFalse);
    expect(d.copyWith(videoCodec: 'vp8', screenFpsMax: 15, audioRed: true), r);
  });

  test('the admin payload: settings over the server recommended set, stored fields, env', () {
    final info = LiveSettingsInfo.fromJson({
      'settings': {'video_codec': 'h264', 'recording_mode': 'client', 'server_recording_tiers': 'all'},
      'recommended': LiveSettingsDraft.recommended.toJson(),
      'stored': ['video_codec'],
      'env': {'recording_mode': 'client', 'server_recording_tiers': 'all'},
      'updated_at': '2026-10-29T10:00:00',
    });
    expect(info.settings.videoCodec, 'h264');
    expect(info.settings.recordingMode, 'client');
    expect(info.settings.cameraFps, 24, reason: 'a field the payload lacks reads as the recommended value');
    expect(info.stored, {'video_codec'});
    expect(info.envRecordingMode, 'client');
    expect(info.envRecordingTiers, 'all');
    expect(info.updatedAt, DateTime(2026, 10, 29, 10));
    expect(LiveSettingsInfo.fromJson(const {}).settings, LiveSettingsDraft.recommended);
  });

  test('bandwidth: layers, codec and fps scale, the recommended set', () {
    expect(simulcastLayers('720p'), ['720p', '360p', '180p']);
    expect(simulcastLayers('540p'), ['540p', '360p', '180p']);
    expect(simulcastLayers('360p'), ['360p', '180p']);
    expect(simulcastLayers('180p'), ['180p']);
    expect(layerKbps('720p', 30, 'vp8'), 1700);
    expect(layerKbps('720p', 30, 'vp9'), 1190);
    expect(layerKbps('720p', 15, 'vp8'), lessThan(1100));
    const r = LiveSettingsDraft.recommended;
    final b = estimateBandwidth(r);
    expect(b.teacherCameraKbps, layerKbps('720p', 24, 'vp8'));
    expect(b.screenKbps, 2500);
    expect(b.camerasOn, kPreviewCamerasWhenDefaultOff);
    expect(b.studentTiles, 2);
    expect(b.perViewerWithShareKbps, b.perViewerKbps + 2500);
    expect(b.teacherUploadKbps,
        layerKbps('720p', 24, 'vp8') + layerKbps('360p', 24, 'vp8') + layerKbps('180p', 24, 'vp8') + 2500);
    expect(b.perViewerHourMb, (b.perViewerWithShareKbps * 3600 / 8 / 1000).round());
  });

  test('bandwidth: what each switch saves', () {
    const r = LiveSettingsDraft.recommended;
    final base = estimateBandwidth(r);
    final camerasOn = estimateBandwidth(r.copyWith(participantsCameraDefaultOff: false));
    expect(camerasOn.camerasOn, kPreviewStudents);
    expect(camerasOn.studentTiles, kPreviewVisibleTiles, reason: 'hidden tiles are paused');
    final noPause = estimateBandwidth(r.copyWith(participantsCameraDefaultOff: false, pauseHiddenVideo: false));
    expect(noPause.studentTiles, kPreviewStudents);
    expect(noPause.studentTilesKbps, greaterThan(camerasOn.studentTilesKbps));
    expect(estimateBandwidth(r.copyWith(audioRed: false)).audioKbps, lessThan(base.audioKbps));
    expect(estimateBandwidth(r.copyWith(audioDtx: false)).audioKbps, greaterThan(base.audioKbps));
    expect(estimateBandwidth(r.copyWith(videoCodec: 'vp9')).perViewerKbps, lessThan(base.perViewerKbps));
    expect(estimateBandwidth(r.copyWith(cameraMaxHost: '360p')).teacherCameraKbps, lessThan(base.teacherCameraKbps));
    expect(estimateBandwidth(r.copyWith(weakNetwork: 'audio_first')).weakNetworkFloorKbps, 350);
  });

  test('mbps formatting', () {
    expect(mbps(450), '0.45');
    expect(mbps(1700), '1.7');
    expect(mbps(12500), '13');
  });
}
