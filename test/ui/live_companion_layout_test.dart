import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/live/companion/companion_core.dart';
import 'package:flutter_education_app/features/shared/live/companion/companion_link.dart' show CompanionStage;
import 'package:flutter_education_app/features/shared/live/companion/companion_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _all = {CompanionSource.camera, CompanionSource.microphone, CompanionSource.speaker};

void main() {
  CompanionChooserBody chooser(CompanionStage stage, Set<CompanionSource> sources, {String? qr, bool noPhone = false, String? error}) =>
      CompanionChooserBody(
        stage: stage,
        sources: sources,
        onToggle: (_) {},
        onAsk: () {},
        onCancel: () {},
        onStop: () {},
        qrUrl: qr,
        showQr: qr != null,
        noPhone: noPhone,
        error: error,
      );

  Widget scrollable(Widget w) => SingleChildScrollView(child: w);

  testWidgets('the chooser in every stage fits', (tester) async {
    await expectNoLayoutErrors(tester, () => scrollable(chooser(CompanionStage.idle, {CompanionSource.microphone})));
    await expectNoLayoutErrors(tester, () => scrollable(chooser(CompanionStage.ringing, _all, qr: 'https://nextbrain.site/s/companion/abcdefgh')));
    await expectNoLayoutErrors(tester, () => scrollable(chooser(CompanionStage.ringing, _all, noPhone: true, qr: 'https://nextbrain.site/s/companion/abcdefgh')));
    await expectNoLayoutErrors(tester, () => scrollable(chooser(CompanionStage.active, _all, error: 'That did not work.')));
  });

  testWidgets('the phone prompt fits', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => CompanionIncomingLayout(
        sources: _all,
        secondsLeft: 118,
        originLabel: 'Chrome on Windows',
        roomTitle: 'A long meeting title that wraps on a small phone screen and keeps going',
        note: 'Your phone will ask to use its camera or microphone.',
        onAccept: () {},
        onDecline: () {},
      ),
    );
  });

  testWidgets('the phone screen fits, connecting, connected, camera off', (tester) async {
    for (final state in CompanionPhoneState.values) {
      await expectNoLayoutErrors(
        tester,
        () => CompanionPhoneLayout(
          state: state,
          originLabel: 'Chrome on Windows',
          sources: _all,
          micOn: state != CompanionPhoneState.connecting,
          camOn: state == CompanionPhoneState.connected,
          speakerOn: true,
          preview: const ColoredBox(color: Colors.black),
          notice: state == CompanionPhoneState.reconnecting ? 'Camera paused: the app is in the background.' : null,
          onLeave: () {},
          onToggleMic: () {},
          onToggleCam: () {},
          onFlip: () {},
          onToggleSpeaker: () {},
        ),
      );
    }
  });

  testWidgets('the pre-join row fits with and without a choice', (tester) async {
    await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.topCenter, child: PreJoinPhoneRow(selected: const {}, onTap: () {})));
    await expectNoLayoutErrors(tester, () => Align(alignment: Alignment.topCenter, child: PreJoinPhoneRow(selected: _all, onTap: () {})));
  });
}
