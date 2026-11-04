import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/course_trash/trash_models.dart';
import 'package:flutter_education_app/features/admin/course_trash/trash_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'اسم طويل جداً جداً لكورس يختبر التفاف النص في كل الأحجام Introduction to Advanced Quantum Field Theory and Applications';

TrashItem _item({bool legacy = false}) => TrashItem.fromJson({
      'course_id': 1234567, 'name_ar': _long, 'name_en': _long, 'teacher': {'id': 3, 'name': _long, 'role': 'teacher'}, 'legacy': legacy,
      'via': legacy ? 'legacy' : 'teacher', 'deleted_at': '2026-11-01T10:00:00', 'deleted_by': {'id': 3, 'name': _long, 'role': 'super-admin'},
      'reason': _long * 3, 'was_published': true, 'students': 123456, 'paid_students': 99999, 'sessions': 3000, 'payments': 8000,
    });

TrashPurgePlan _plan(String mode) => TrashPurgePlan.fromJson({
      'mode': mode,
      'removed': {'sessions': 120, 'materials': 40, 'a_really_long_unknown_table_name_for_layout_testing_purposes': 3},
      'kept': mode == 'purged' ? {'payments': 12, 'certificates': 4, 'earnings': 9} : {},
      'detached': {'favorites': 2},
      'rows_removed': 163,
      'blocked_by': mode == 'blocked' ? ['a_long_blocking_reason_name_here'] : null,
    });

List<TrashHistoryEntry> _history() => [
      for (var i = 0; i < 3; i++)
        TrashHistoryEntry.fromJson({
          'id': i, 'state': i == 0 ? 'purged' : 'restored', 'via': 'admin',
          'deleted_at': '2026-11-01T10:00:00', 'deleted_by': {'id': 1, 'name': _long, 'role': 'admin'}, 'delete_reason': _long,
          'restored_at': i == 0 ? null : '2026-11-02T10:00:00', 'restored_by': {'id': 1, 'name': _long, 'role': 'super-admin'}, 'restore_reason': _long,
          'purged_at': i == 0 ? '2026-11-03T10:00:00' : null, 'purged_by': {'id': 1, 'name': _long, 'role': 'super-admin'}, 'purge_reason': _long,
        }),
    ];

void main() {
  for (final legacy in [false, true]) {
    testWidgets('trash card legacy=$legacy', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: [TrashCourseCard(item: _item(legacy: legacy), onTap: () {})]));
    });
  }

  testWidgets('trash card with nothing optional', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [TrashCourseCard(item: TrashItem.fromJson({'course_id': 1}), onTap: () {})]));
  });

  testWidgets('purged cards', (tester) async {
    final items = [
      for (final s in ['erased', 'purged'])
        PurgedItem.fromJson({
          'course_id': 5, 'name_ar': _long, 'name_en': _long, 'teacher': {'id': 1, 'name': _long}, 'state': s,
          'deleted_at': '2026-11-01T10:00:00', 'deleted_by': {'id': 1, 'name': _long, 'role': 'teacher'}, 'delete_reason': _long,
          'purged_at': '2026-11-03T10:00:00', 'purged_by': {'id': 1, 'name': _long, 'role': 'super-admin'}, 'purge_reason': _long,
          'purge_summary': {'mode': s, 'rows_removed': 12345},
        }),
    ];
    await expectNoLayoutErrors(tester, () => ListView(children: [for (final p in items) TrashPurgedCard(item: p)]));
  });

  for (final mode in ['erased', 'purged', 'blocked']) {
    testWidgets('purge plan $mode', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: [TrashPurgePlanView(_plan(mode))]), act: (t) async {
        final more = find.byIcon(Icons.expand_more_rounded);
        if (more.evaluate().isNotEmpty) await t.tap(more);
      });
    });
  }

  testWidgets('history timeline', (tester) async {
    await expectNoLayoutErrors(tester, () => ListView(children: [TrashHistoryTimeline(_history()), const TrashHistoryTimeline([])]));
  });

  for (final legacy in [false, true]) {
    testWidgets('detail body legacy=$legacy', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(children: [TrashDetailBody(detail: TrashDetail(item: _item(legacy: legacy), history: _history(), plan: _plan('purged')), onRestore: () {}, onPurge: () {})]),
      );
    });
  }

  testWidgets('restore and purge forms', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        TrashRestoreForm(item: _item(legacy: true), onCancel: () {}, onConfirm: (_) {}),
        TrashPurgeForm(courseId: 1234567, plan: _plan('erased'), onCancel: () {}, onConfirm: (_) {}),
        TrashPurgeForm(courseId: 1234567, plan: _plan('blocked'), onCancel: () {}, onConfirm: (_) {}),
      ]),
    );
  });

  testWidgets('purge button needs a reason and the typed id', (tester) async {
    await tester.pumpWidget(layoutHost(TrashPurgeForm(courseId: 42, plan: _plan('erased'), onCancel: () {}, onConfirm: (_) {})));
    bool enabled() => tester.widget<AppButton>(find.byType(AppButton)).onPressed != null;

    expect(enabled(), isFalse);
    await tester.enterText(find.byType(TextField).at(0), 'cleanup now');
    await tester.pump();
    expect(enabled(), isFalse);
    await tester.enterText(find.byType(TextField).at(1), '42');
    await tester.pump();
    expect(enabled(), isTrue);
  });
}
