// The Android share sheet (share_options_sheet.dart): both modes and the device-audio switch on
// Android 10+, the "microphone only" note below it, the Android 14+ device-audio scope note (L7) —
// every size, both languages, text 1.3x — and the choices it hands back.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/widgets/android_share.dart'
    show shareDeviceAudioScopeNote;
import 'package:flutter_education_app/features/live/room/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/live/room/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('layout: device audio offered / not supported, both modes', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
          ShareOptionsLayout(
            quality: ShareQuality.detail,
            deviceAudio: true,
            deviceAudioSupported: true,
            onQuality: (_) {},
            onDeviceAudio: (_) {},
            onStart: () {},
          ),
          const ShareOptionsLayout(quality: ShareQuality.motion, deviceAudio: false, deviceAudioSupported: false),
          ShareOptionsLayout(
            quality: ShareQuality.detail,
            deviceAudio: true,
            deviceAudioSupported: true,
            deviceAudioNote: shareDeviceAudioScopeNote(arabic: AppConfig.lang == 'ar'),
          ),
        ])));
  });

  testWidgets('Android 14+: the scope note under the device-audio switch, only when given', (t) async {
    await t.pumpWidget(layoutHost(ShareOptionsLayout(
        quality: ShareQuality.detail,
        deviceAudio: true,
        deviceAudioSupported: true,
        deviceAudioNote: shareDeviceAudioScopeNote(arabic: false))));
    expect(find.byKey(const ValueKey('share.device_audio.scope')), findsOneWidget);
    expect(find.text(shareDeviceAudioScopeNote(arabic: false)), findsOneWidget);
    await t.pumpWidget(layoutHost(const ShareOptionsLayout(
        quality: ShareQuality.detail, deviceAudio: true, deviceAudioSupported: true)));
    expect(find.byKey(const ValueKey('share.device_audio.scope')), findsNothing);
  });

  testWidgets('no switch below Android 10, the note instead', (t) async {
    await t.pumpWidget(layoutHost(const ShareOptionsLayout(
        quality: ShareQuality.detail, deviceAudio: false, deviceAudioSupported: false)));
    expect(find.byKey(const ValueKey('share.device_audio')), findsNothing);
    expect(find.byKey(const ValueKey('share.no_device_audio')), findsOneWidget);
  });

  testWidgets('the sheet returns the picked mode and device audio', (t) async {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    ShareChoice? picked;
    await t.pumpWidget(layoutHost(Builder(
      builder: (context) => TextButton(
        onPressed: () async => picked = await showShareOptionsSheet(context, deviceAudioSupported: true),
        child: const Text('open'),
      ),
    ), scale: 1));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('share.mode.motion')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('share.device_audio')));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('share.start')));
    await t.pumpAndSettle();
    expect(picked?.quality, ShareQuality.motion);
    expect(picked?.deviceAudio, isFalse);
  });
}
