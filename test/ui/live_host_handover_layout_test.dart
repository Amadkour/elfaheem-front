// D-310: a meeting host's End sheet (End for everyone / Leave), the handover sheet after Leave, and the meeting's
// recording indicator as everyone else sees it (the top row with a remote recording: REC + time / Paused, no menu)
// at 320×640 and 1400×900, Arabic and English, text scale 1.3 — no overflow, the right texts and keys.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/live/live_host_handover.dart';
import 'package:flutter_education_app/features/shared/live/live_rec_signal.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_top_row.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _people = [
  LiveHandoverCandidate(userId: 7, identity: 'meet_7', name: 'Mona Abdelrahman El-Sayed Mahmoud'),
  LiveHandoverCandidate(userId: 9, identity: 'meet_9', name: 'أحمد'),
  LiveHandoverCandidate(userId: 12, identity: 'meet_12', name: 'Omar'),
];

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('End sheet: both choices + Cancel, recording line, every size and language', (t) async {
    final picked = <LiveEndChoice>[];
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(children: [
          LiveEndChoiceBody(recording: true, others: 3, onChoose: picked.add, onCancel: () {}),
          const LiveEndChoiceBody(canEndForAll: false, onChoose: _ignore, onCancel: _noop),
        ]),
      ),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.byKey(const ValueKey('live_end.end_all')), findsOneWidget);
        expect(find.byKey(const ValueKey('live_end.leave')), findsNWidgets(2));
        expect(find.byKey(const ValueKey('live_end.cancel')), findsNWidgets(2));
        expect(find.text(ar ? 'إنهاء الاجتماع للجميع' : 'End meeting for everyone'), findsOneWidget);
        expect(find.textContaining(ar ? 'يُحفظ التسجيل' : 'The recording is saved'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('live_end.end_all')));
        await t.tap(find.byKey(const ValueKey('live_end.leave')).first);
      },
    );
    expect(picked.take(2), [LiveEndChoice.endForAll, LiveEndChoice.leave]);
  });

  testWidgets('Handover sheet: people, none / one picked, busy, an error', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(children: [
          LiveHandoverBody(people: _people, onSelect: (_) {}, onConfirm: () {}, onJustLeave: () {}),
          LiveHandoverBody(people: _people, selectedId: 9, onSelect: (_) {}, onConfirm: () {}, onJustLeave: () {}),
          LiveHandoverBody(
            people: _people.take(1).toList(),
            selectedId: 7,
            busy: true,
            error: 'This person is no longer in the meeting. Pick someone else.',
            onSelect: (_) {},
            onConfirm: () {},
            onJustLeave: () {},
          ),
        ]),
      ),
      act: (t) async {
        final ar = AppConfig.lang == 'ar';
        expect(find.text(ar ? 'اجعله المضيف وغادر' : 'Make host and leave'), findsNWidgets(3));
        expect(find.text(ar ? 'لا، غادر فقط' : 'No, just leave'), findsNWidgets(3));
        final buttons = t.widgetList<FilledButton>(find.byType(FilledButton)).toList();
        expect(buttons[0].onPressed, isNull, reason: 'nobody picked yet');
        expect(buttons[1].onPressed, isNotNull);
        expect(buttons[2].onPressed, isNull, reason: 'busy');
      },
    );
  });

  testWidgets('everyone else sees the meeting recording: REC + time, Paused with the pause glyph, no menu', (t) async {
    Widget row(LiveRemoteRecState s) => ColoredBox(
          color: const Color(0xFF0B1020),
          child: LiveTopRow(
            onInfo: () {},
            liveFor: const Duration(minutes: 12),
            recording: LiveTopRecording(
              phase: liveRecPhase(remote: s, offer: true),
              elapsed: const Duration(minutes: 4, seconds: 5),
            ),
          ),
        );
    await expectNoLayoutErrors(
      t,
      () => Column(children: [row(LiveRemoteRecState.recording), row(LiveRemoteRecState.paused)]),
      act: (t) async {
        expect(find.byKey(const ValueKey('live_room.rec_control')), findsWidgets); // the row also lays out a fallback
        expect(find.byKey(const ValueKey('live_room.record')), findsNothing, reason: 'a recording beats the offer');
        expect(find.byIcon(Icons.pause_rounded), findsWidgets);
        expect(find.byIcon(Icons.expand_more_rounded), findsNothing, reason: 'no menu for a viewer');
        if (t.view.physicalSize.width / t.view.devicePixelRatio >= kLiveTopRowCompactWidth) {
          final ar = AppConfig.lang == 'ar';
          expect(find.text(ar ? 'متوقف مؤقتًا' : 'Paused'), findsWidgets);
          expect(find.text(ar ? 'يُسجَّل' : 'REC'), findsWidgets);
        }
      },
    );
  });
}

void _noop() {}
void _ignore(LiveEndChoice _) {}
