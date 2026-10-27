// PreJoinLayout (the pre-join screen without LiveKit) at 320x640 and 1400x900, ar + en, textScaler 1.3:
// with and without devices, camera on/off, busy, teacher/student, permission issue, and the device sheet open.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/prejoin_layout.dart';
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
}) =>
    PreJoinLayout(
      title: title ?? 'Live session: Advanced Algorithms — week 7 (a long session name to wrap)',
      isTeacher: isTeacher,
      userName: userName,
      preview: preview,
      micOn: micOn,
      camOn: camOn,
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
