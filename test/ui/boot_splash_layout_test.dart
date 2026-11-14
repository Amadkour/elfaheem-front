// The splash screen: no overflow at any size / language / text scale, in every phase (first frame, words
// shown, offline, hand-off), plus the pure pacing and text helpers.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/boot_splash.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

SplashState _state({double at = 3, bool offline = false, int stage = 0, String user = 'Ahmed Hamdy Madkour'}) {
  final s = SplashState()
    ..clockOffset = at
    ..stage = stage
    ..steps = 4
    ..expected = 10
    ..step = 'offlineVideos'
    ..offline = offline
    ..tagline = 'Learn anywhere, any time, with the people who care about every single student of yours'
    ..version = '3.4.0'
    ..setFooter(text: 'Powered by Double Y — with a partner line long enough to need an ellipsis', logoUrl: 'https://x.test/l.png')
    ..setUser({'name': user});
  return s;
}

void main() {
  testWidgets('first frame: only the mark', (tester) async {
    await expectNoLayoutErrors(tester, () => BootSplash(state: _state(at: 0)), scaffold: false);
  });

  testWidgets('words shown, long tagline + greeting', (tester) async {
    await expectNoLayoutErrors(tester, () => BootSplash(state: _state()), scaffold: false, frames: 6);
  });

  testWidgets('offline, no user, no identity', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => BootSplash(state: _state(offline: true, user: '')..tagline = ''..version = ''..setFooter(text: '', logoUrl: '')),
        scaffold: false);
  });

  testWidgets('footer with cached logo bytes', (tester) async {
    // 1×1 transparent PNG
    const png = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0,
      31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 156, 99, 248, 255, 255, 63, 0, 5, 254, 2, 254, 167, 53,
      129, 132, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];
    await expectNoLayoutErrors(
        tester,
        () => BootSplash(state: _state()..setFooter(text: 'Powered by Double Y', logoBytes: Uint8List.fromList(png))),
        scaffold: false);
  });

  testWidgets('hand-off overlay dissolves over the app', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const SplashHandOff(child: ColoredBox(color: Colors.white)),
      scaffold: false,
      frames: 10,
    );
  });

  group('SplashPacing.target', () {
    test('follows steps when the usual boot time is unknown', () {
      expect(SplashPacing.target(stage: 0, steps: 0, expected: 10, elapsed: 0, usual: 0), closeTo(0.06, 1e-9));
      expect(SplashPacing.target(stage: 0, steps: 10, expected: 10, elapsed: 0, usual: 0), closeTo(0.68, 1e-9));
    });
    test('elapsed time keeps the bar moving inside a slow step, capped below done', () {
      final slowStep = SplashPacing.target(stage: 0, steps: 1, expected: 10, elapsed: 2, usual: 2.5);
      expect(slowStep, greaterThan(0.5));
      expect(SplashPacing.target(stage: 0, steps: 1, expected: 10, elapsed: 30, usual: 2.5), 0.78);
    });
    test('stages', () {
      expect(SplashPacing.target(stage: 1, steps: 0, expected: 10, elapsed: 0, usual: 0), 0.82);
      expect(SplashPacing.target(stage: 2, steps: 0, expected: 10, elapsed: 0, usual: 0), 1);
    });
  });

  group('SplashTexts', () {
    test('greeting by time of day, with the first name', () {
      expect(SplashTexts.greeting(name: 'Ahmed', en: true, now: DateTime(2026, 1, 1, 9)), 'Good morning, Ahmed');
      expect(SplashTexts.greeting(name: 'أحمد', en: false, now: DateTime(2026, 1, 1, 20)), 'مساء الخير، أحمد');
      expect(SplashTexts.greeting(name: '', en: true, now: DateTime(2026, 1, 1, 9)), 'Welcome');
    });
    test('status says what runs now; offline and slow win', () {
      expect(SplashTexts.status(step: 'firebase', stage: 0, offline: false, elapsed: 1, en: true),
          'Connecting securely…');
      expect(SplashTexts.status(step: 'firebase', stage: 0, offline: true, elapsed: 1, en: false),
          'لا يوجد اتصال — نفتح تنزيلاتك');
      expect(SplashTexts.status(step: 'firebase', stage: 0, offline: false, elapsed: 12, en: true),
          'Taking a little longer than usual…');
      expect(SplashTexts.status(step: '', stage: 1, offline: false, elapsed: 1, en: true), 'Applying your theme…');
    });
  });

  test('SplashState.firstName skips titles and trims', () {
    expect(SplashState.firstName('Dr. Ahmed Hamdy'), 'Ahmed');
    expect(SplashState.firstName('د. أحمد حمدي'), 'أحمد');
    expect(SplashState.firstName('  '), '');
    expect(SplashState.firstName('Abcdefghijklmnopqrstuvwxyz'), 'Abcdefghijklmno…');
  });
}
