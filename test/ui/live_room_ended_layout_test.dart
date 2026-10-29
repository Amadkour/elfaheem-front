// The room's "connection lost / removed / another device" card (widgets/live_room_ended.dart, D9) at every size,
// both languages, text 1.3x; Rejoin only for a lost connection that can join again; the web share sheet's texts
// (share_options_sheet.dart, web: true).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_room_ended.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/share_options_sheet.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/share_presets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('layout: every kind, with and without Rejoin', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
          LiveRoomEndedCard(kind: LiveEndedKind.lost, onRejoin: () {}, onClose: () {}),
          LiveRoomEndedCard(kind: LiveEndedKind.lost, onClose: () {}),
          LiveRoomEndedCard(kind: LiveEndedKind.removed, onRejoin: () {}, onClose: () {}),
          LiveRoomEndedCard(kind: LiveEndedKind.otherDevice, onClose: () {}),
        ])));
  });

  testWidgets('Rejoin only for a lost connection; the buttons answer', (t) async {
    var rejoined = 0, closed = 0;
    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: LiveRoomEndedCard(kind: LiveEndedKind.lost, onRejoin: () => rejoined++, onClose: () => closed++),
    )));
    expect(find.text('Rejoin'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('live_room.rejoin')));
    await t.tap(find.byKey(const ValueKey('live_room.ended_close')));
    expect((rejoined, closed), (1, 1));

    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: LiveRoomEndedCard(kind: LiveEndedKind.otherDevice, onRejoin: () => rejoined++, onClose: () => closed++),
    )));
    expect(find.byKey(const ValueKey('live_room.rejoin')), findsNothing, reason: 'another device never rejoins');
    expect(find.text('This account joined from another device'), findsOneWidget);

    await t.pumpWidget(layoutHost(SingleChildScrollView(
      child: LiveRoomEndedCard(kind: LiveEndedKind.removed, onRejoin: () => rejoined++, onClose: () => closed++),
    )));
    expect(find.byKey(const ValueKey('live_room.rejoin')), findsNothing);
    expect(find.text('You were removed by the host'), findsOneWidget);
  });

  testWidgets('web share sheet: tab audio where the browser can, the note where it cannot', (t) async {
    await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
          ShareOptionsLayout(
            quality: ShareQuality.detail,
            deviceAudio: true,
            deviceAudioSupported: true,
            web: true,
            onQuality: (_) {},
            onDeviceAudio: (_) {},
            onStart: () {},
          ),
          const ShareOptionsLayout(
              quality: ShareQuality.motion, deviceAudio: false, deviceAudioSupported: false, web: true),
        ])));
    await t.pumpWidget(layoutHost(const SingleChildScrollView(
      child: ShareOptionsLayout(quality: ShareQuality.detail, deviceAudio: false, deviceAudioSupported: false, web: true),
    )));
    expect(find.byKey(const ValueKey('share.no_device_audio')), findsOneWidget);
    expect(find.textContaining('Chrome or Edge'), findsOneWidget);
    expect(find.textContaining('Android'), findsNothing);
  });
}
