// PreJoinLayout (the pre-join screen without LiveKit) at 320x640 and 1400x900, ar + en, textScaler 1.3:
// with and without devices, camera on/off, busy, teacher/student, permission issue, and the device sheet open.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/live/room/prejoin_layout.dart';
import 'package:flutter_education_app/features/live/room/prejoin_mic_meter_stub.dart' show micLevelFromBands;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _mics = <PreJoinDevice>[
  ('m1', 'Default - Microphone Array (Realtek(R) Audio) with a very long device label'),
  ('m2', 'ميكروفون سماعة الرأس اللاسلكية'),
  ('m3', 'USB Microphone'),
];
const _cams = <PreJoinDevice>[
  ('c1', 'Integrated Camera (04f2:b6d0) front facing'),
  ('c2', 'كاميرا خارجية'),
];

Widget _layout({
  List<PreJoinDevice> mics = _mics,
  List<PreJoinDevice> cams = _cams,
  Widget? preview,
  bool micOn = true,
  bool camOn = true,
  bool busy = false,
  bool isTeacher = true,
  PreJoinIssue? issue,
  String? title,
  String userName = 'أحمد حمدي مدكور',
  double? micLevel,
  bool cameraOffHint = false,
}) =>
    PreJoinLayout(
      title: title ?? 'Live session: Advanced Algorithms — week 7 (a long session name to wrap)',
      isTeacher: isTeacher,
      userName: userName,
      preview: preview,
      micOn: micOn,
      camOn: camOn,
      micLevel: micLevel,
      onToggleMic: mics.isEmpty ? null : () {},
      onToggleCam: cams.isEmpty ? null : () {},
      mics: mics,
      cams: cams,
      selectedMic: mics.isEmpty ? null : mics.first.$1,
      selectedCam: cams.isEmpty ? null : cams.first.$1,
      onMicChanged: (_) {},
      onCamChanged: (_) {},
      busy: busy,
      onJoin: () {},
      onBack: () {},
      issue: issue,
      onRetry: issue == null ? null : () {},
      cameraOffHint: cameraOffHint,
    );

void main() {
  testWidgets('camera on with a live preview, devices present (teacher)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(preview: const ColoredBox(color: Colors.blueGrey)),
      act: (t) async {
        expect(find.byKey(const ValueKey('prejoin.join')), findsOneWidget);
        expect(find.byKey(const ValueKey('prejoin.issue')), findsNothing);
      },
    );
  });

  testWidgets('camera off: avatar state, mic muted, student recording note', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false, micOn: false, isTeacher: false, userName: 'Student Name'),
    );
  });

  testWidgets('a student whose camera starts off by the admin default sees why, with Turn on (D-090)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false, isTeacher: false, userName: 'Student Name', cameraOffHint: true),
      act: (t) async {
        expect(find.byKey(const ValueKey('prejoin.camera_off_hint')), findsOneWidget);
        expect(find.byKey(const ValueKey('prejoin.camera_off_hint.turn_on')), findsOneWidget);
      },
    );
    // Once the camera is on, the hint goes.
    await expectNoLayoutErrors(
      tester,
      () => _layout(isTeacher: false, cameraOffHint: true),
      act: (t) async => expect(find.byKey(const ValueKey('prejoin.camera_off_hint')), findsNothing),
    );
  });

  testWidgets('camera starting (on, no preview yet) + busy join', (tester) async {
    await expectNoLayoutErrors(tester, () => _layout(busy: true));
  });

  testWidgets('no devices at all + retry banner', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(mics: const [], cams: const [], camOn: false, micOn: false, issue: PreJoinIssue.noDevices),
      act: (t) async {
        expect(find.byKey(const ValueKey('prejoin.issue')), findsOneWidget);
        expect(find.byKey(const ValueKey('prejoin.retry')), findsOneWidget);
      },
    );
  });

  testWidgets('permission denied with a short title', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false, micOn: false, issue: PreJoinIssue.permissionDenied, title: 'Math', userName: 'A'),
    );
  });

  testWidgets('microphone picker sheet opens without overflow', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false),
      act: (t) async {
        await t.ensureVisible(find.byKey(const ValueKey('prejoin.mic')));
        await t.tap(find.byKey(const ValueKey('prejoin.mic')));
      },
    );
  });

  testWidgets('mic level meter under the mic pill: quiet, speaking, clipping', (tester) async {
    for (final level in [0.0, 0.5, 1.0]) {
      await expectNoLayoutErrors(
        tester,
        () => _layout(camOn: false, micLevel: level),
        act: (t) async {
          expect(find.byKey(const ValueKey('prejoin.mic.meter')), findsOneWidget);
        },
      );
    }
  });

  testWidgets('mic level meter is hidden while the mic is off, and without a level', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false, micOn: false, micLevel: 0.7),
      act: (t) async {
        expect(find.byKey(const ValueKey('prejoin.mic.meter')), findsNothing);
      },
    );
    await expectNoLayoutErrors(
      tester,
      () => _layout(camOn: false, micOn: true, micLevel: null),
      act: (t) async {
        expect(find.byKey(const ValueKey('prejoin.mic.meter')), findsNothing);
      },
    );
  });

  group('micLevelFromBands (native visualizer frame → meter level)', () {
    test('loudest band, clamped to 0–1', () {
      expect(micLevelFromBands(const [0.1, 0.4, 0.25]), 0.4);
      expect(micLevelFromBands(const [0.0, 0.0]), 0.0);
      expect(micLevelFromBands(const [1.7, 0.2]), 1.0);
      expect(micLevelFromBands(const [-0.3]), 0.0);
    });

    test('empty frame and non-numbers count as silence', () {
      expect(micLevelFromBands(const []), 0.0);
      expect(micLevelFromBands(const ['x', null, 0.3]), 0.3);
      expect(micLevelFromBands([double.nan, 0.2]), 0.2);
    });
  });

  testWidgets('preview card alone fits a narrow 16:9 box', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const Center(
        child: SizedBox(
          width: 200,
          child: PreJoinPreviewCard(preview: null, camOn: false, micOn: false, hasCamera: true, userName: 'Ahmed Hamdy'),
        ),
      ),
    );
  });
}
