// The lifecycle settings, "Who decides what", the timeline's undo row and the file header's "Change status" never
// overflow (contract §14 phase 2, F2): StudentSettingsView with the usual values, read only, struggling off and long
// custom reminder days; StudentMatrixView editable / read only with changed rows; DecisionRuleEditorView for an
// auto-ok key, a dangerous key decided directly, and a flag; StudentTimelineRow with Undo and with who undid it;
// StudentFileView with "Change status".
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/students/student_file_models.dart';
import 'package:flutter_education_app/features/org/students/student_file_page.dart';
import 'package:flutter_education_app/features/org/students/student_matrix_page.dart';
import 'package:flutter_education_app/features/org/students/student_settings_page.dart';
import 'package:flutter_education_app/features/org/students/student_status_models.dart';
import 'package:flutter_education_app/features/org/students/student_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/student_file_models_test.dart' show sampleFileJson;
import 'layout_harness.dart';

Map<String, dynamic> _m(String decide, String? body, bool no) => {'decide': decide, 'body': body, 'decision_no': no};

/// The server's DEFAULTS (features/org/students/settings.py).
Map<String, dynamic> usualLifecycle() => {
      'decision_matrix': {
        'suspend': _m('approve', 'faculty_council', true),
        'suspend_extend': _m('approve', 'university_council', true),
        'postpone': _m('approve', 'faculty_council', true),
        'resume': _m('update', 'student_affairs', false),
        'disc_suspend': _m('approve', 'dean', true),
        'outside': _m('approve', 'faculty_council', true),
        'dismiss_academic': _m('approve', 'faculty_council', true),
        'dismiss_disciplinary': _m('approve', 'disciplinary_board', true),
        'withdraw': _m('update', 'student_affairs', false),
        'cancel': _m('approve', 'faculty_council', true),
        'transfer_out': _m('approve', 'university_president', true),
        'reenrol': _m('approve', 'faculty_council', true),
        'graduate_undo': _m('approve', 'faculty_council', true),
        'deceased': _m('update', 'student_affairs', false),
        'standing_override': _m('approve', 'faculty_council', false),
        'final_chance': _m('approve', 'faculty_council', true),
        'flag.struggling': _m('update', null, false),
        'flag.special_case': _m('update', null, false),
        'flag.conscripted': _m('update', 'student_affairs', false),
        'flag.excuse_open': _m('approve', 'faculty_council', false),
        'flag.disciplinary_record': _m('approve', 'dean', true),
      },
      'struggling_rule': {'auto': true, 'standings': ['warning', 'final_chance'], 'repeat_same_level_times': 2},
      'side_effects': {'block_registration': true, 'ask_drop_current': true, 'access_after_leaving_days': 90},
      'student_sees': {'status': true, 'reason': true, 'decision_no': true},
      'reminders': {'incomplete_every_days': 7, 'incomplete_max': 4, 'ask_before_days': [3, 1], 'suspension_ending_days': 14},
      'file_log': {'window_minutes': 30, 'tell_staff': true},
      'sibling_duplicate': 'warn',
    };

void main() {
  final usual = LifecycleSettings.fromJson(usualLifecycle());
  final changed = usual
      .withRule('dismiss_academic', const DecisionRule(decide: 'auto', body: 'faculty_council', decisionNo: true))
      .withRule('withdraw', const DecisionRule(decide: 'update', body: 'education_committee'))
      .withSection('struggling_rule', {'auto': false})
      .withSection('student_sees', {'status': false})
      .withSection('reminders', {'ask_before_days': [365, 120, 45, 3, 1, 0], 'incomplete_every_days': 365});

  testWidgets('StudentSettingsView · the usual values, editable', (tester) async {
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: StudentSettingsView(settings: usual, onChanged: (_) {}, onOpenMatrix: () {})));
  });

  testWidgets('StudentSettingsView · read only, changed values, custom reminder days', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentSettingsView(settings: changed, onOpenMatrix: () {})));
  });

  testWidgets('StudentSettingsView · an empty object (an old server) still draws', (tester) async {
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: StudentSettingsView(settings: LifecycleSettings({}))));
  });

  testWidgets('StudentSettingsView · a switch edits its section and keeps the rest', (tester) async {
    LifecycleSettings? got;
    final prev = AppConfig.lang;
    addTearDown(() => AppConfig.lang = prev);
    AppConfig.lang = 'en';
    await tester.pumpWidget(layoutHost(SingleChildScrollView(child: StudentSettingsView(settings: usual, onChanged: (s) => got = s))));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Stop registration for new courses'));
    await tester.pump();
    expect(got, isNotNull);
    expect((got!.raw['side_effects'] as Map)['block_registration'], isFalse);
    expect((got!.raw['side_effects'] as Map)['access_after_leaving_days'], 90);
    expect(got!.raw.keys.toSet(), usual.raw.keys.toSet());
  });

  testWidgets('StudentMatrixView · editable with changed rows, and read only', (tester) async {
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentMatrixView(settings: changed, defaults: usual, onEdit: (_) {})));
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: StudentMatrixView(settings: usual)));
  });

  testWidgets('DecisionRuleEditorView · auto allowed, a dangerous key decided directly, a flag', (tester) async {
    for (final (k, r) in [
      ('dismiss_academic', const DecisionRule(decide: 'auto', body: 'faculty_council', decisionNo: true)),
      ('dismiss_disciplinary', const DecisionRule(decide: 'update', body: 'disciplinary_board')),
      ('flag.struggling', const DecisionRule(decide: 'update')),
    ]) {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: DecisionRuleEditorView(decision: k, rule: r, usual: usual.rule(k), onChanged: (_) {})));
    }
  });

  test('auto is offered only where the contract allows it; the summary counts every key', () {
    expect(decideChoices('dismiss_academic'), contains('auto'));
    expect(decideChoices('final_chance'), contains('auto'));
    expect(decideChoices('suspend'), isNot(contains('auto')));
    final (d, a, auto) = matrixCounts(usual);
    expect(d + a + auto, decisionKeys.length);
    expect(auto, 0);
  });

  testWidgets('StudentTimelineRow · Undo, and an undone change with who undid it', (tester) async {
    final item = TimelineItem.fromJson({
      'id': 'status:41',
      'kind': 'status',
      'at': '2026-11-20T10:00:00',
      'actor': {'id': 4, 'name': 'منى السيد عبد الحميد المصري'},
      'title_ar': 'القيد: مقيد ← موقوف القيد لمدة فصل دراسي كامل بناءً على طلب الطالب',
      'title_en': 'Enrolment: enrolled → suspended for a full term at the student\'s own request',
      'reason': 'شهادة مرضية معتمدة من مستشفى الجامعة',
      'decision_no': 'م ك 12/2026',
      'can_undo': true,
      'undone': false,
    });
    final undone = TimelineItem.fromJson({
      'id': 'status:40',
      'kind': 'status',
      'at': '2026-11-19T10:00:00',
      'title_ar': 'علامة متعثر',
      'title_en': 'Flag struggling',
      'undone': true,
    });
    expect(statusEventIdOf(item), 41);
    await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(
              child: StudentTimelineView(
                items: [item, undone],
                onUndo: (_) {},
                undoneBy: {
                  'status:40': UndoneBy(
                      who: 'عبد الرحمن محمد عبد الرحيم عبد العزيز السيد الشناوي', at: DateTime.utc(2026, 11, 20, 9), reason: 'وُضعت العلامة على الطالب الخطأ'),
                },
              ),
            ),
        act: (tester) async => expect(find.byIcon(Icons.undo_rounded), findsWidgets));
  });

  testWidgets('StudentFileView · "Change status" in the header', (tester) async {
    final f = StudentFile.fromJson(sampleFileJson());
    await expectNoLayoutErrors(
        tester,
        () => StudentFileView(
              file: f,
              tab: StudentFileTab.overview,
              onTab: (_) {},
              onChangeStatus: () {},
            ),
        act: (tester) async => expect(find.byKey(const ValueKey('student-file-change-status')), findsOneWidget));
  });
}
