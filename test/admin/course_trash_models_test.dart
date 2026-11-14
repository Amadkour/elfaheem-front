import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/course_access.dart';
import 'package:flutter_education_app/features/courses/admin/course_trash/trash_models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> trashJson() => {
      'course_id': 7, 'name_ar': 'كورس', 'name_en': 'Course', 'image_url': 'https://x/y.png',
      'teacher': {'id': 3, 'name': 'Sara', 'role': 'teacher'}, 'legacy': false, 'via': 'teacher',
      'deleted_at': '2026-11-01T10:00:00', 'deleted_by': {'id': 3, 'name': 'Sara', 'role': 'teacher'},
      'reason': 'old', 'was_published': true, 'students': 12, 'paid_students': 5, 'sessions': 30, 'payments': 6,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('a trash item parses, time is UTC', () {
    final it = TrashItem.fromJson(trashJson());
    expect(it.courseId, 7);
    expect(it.name, 'Course');
    expect(it.deletedAt, DateTime.utc(2026, 11, 1, 10));
    expect(it.deletedBy!.role, 'teacher');
    expect((it.students, it.paidStudents, it.sessions, it.payments), (12, 5, 30, 6));
    expect(it.legacy, isFalse);
    AppConfig.lang = 'ar';
    expect(it.name, 'كورس');
  });

  test('a legacy item with nothing but an id does not throw', () {
    final it = TrashItem.fromJson({'course_id': 9, 'legacy': true, 'teacher': null, 'deleted_by': null, 'deleted_at': null});
    expect(it.legacy, isTrue);
    expect(it.name, '#9');
    expect(it.teacher, isNull);
    expect(it.deletedAt, isNull);
    expect(trashPersonText(it.deletedBy), '-');
    expect(TrashItem.fromJson(null).courseId, 0);
  });

  test('a purged item parses both states and the summary', () {
    final p = PurgedItem.fromJson({
      'course_id': 4, 'name_ar': 'أ', 'name_en': 'A', 'state': 'purged', 'via': 'admin',
      'purged_at': '2026-11-02T00:00:00Z', 'purged_by': {'id': 1, 'name': 'Root', 'role': 'super-admin'}, 'purge_reason': 'cleanup',
      'purge_summary': {'mode': 'purged', 'removed': {'sessions': 5, 'materials': 2}, 'kept': {'payments': 3}, 'detached': {}, 'rows_removed': 7, 'files': 4},
    });
    expect(p.erased, isFalse);
    expect(p.summary.rowsRemoved, 7);
    expect(p.summary.kept.byTable['payments'], 3);
    expect(p.purgedBy!.name, 'Root');
    expect(PurgedItem.fromJson({'course_id': 5, 'state': 'erased'}).erased, isTrue);
    final bare = PurgedItem.fromJson({'course_id': 6});
    expect(bare.summary.rowsRemoved, 0);
    expect(bare.purgedAt, isNull);
  });

  test('rows_removed falls back to the sum of removed', () {
    final s = TrashPurgeSummary.fromJson({'removed': {'a': 2, 'b': 3}});
    expect(s.rowsRemoved, 5);
  });

  test('purge plan modes', () {
    expect(TrashPurgePlan.fromJson({'mode': 'erased', 'removed': {'sessions': 2}, 'rows_removed': 2}).erased, isTrue);
    final purged = TrashPurgePlan.fromJson({'mode': 'purged', 'kept': {'payments': 1}});
    expect(purged.purged, isTrue);
    expect(purged.blocked, isFalse);
    final blocked = TrashPurgePlan.fromJson({'mode': 'blocked', 'blocked_by': ['exam_attempts', 'x']});
    expect(blocked.blocked, isTrue);
    expect(blocked.blockedBy, 'exam_attempts, x');
    expect(TrashPurgePlan.fromJson(null).blocked, isTrue);
    expect(TrashPurgePlan.fromJson({'mode': 'something_new'}).blocked, isTrue);
  });

  test('detail has history newest first and tolerates an older server', () {
    final d = TrashDetail.fromJson({
      ...trashJson(),
      'history': [
        {'id': 2, 'state': 'trash', 'via': 'teacher', 'deleted_at': '2026-11-01T10:00:00', 'restored_at': null},
        {'id': 1, 'state': 'restored', 'restored_at': '2026-10-01T10:00:00', 'restored_by': {'id': 1, 'name': 'Root', 'role': 'super-admin'}},
      ],
      'purge_plan': {'mode': 'erased'},
    });
    expect(d.history.map((e) => e.id), [2, 1]);
    expect(d.history[1].restoredBy!.name, 'Root');
    expect(d.plan.erased, isTrue);
    final old = TrashDetail.fromJson(trashJson());
    expect(old.history, isEmpty);
    expect(old.plan.blocked, isTrue);
  });

  test('page parsing and page count', () {
    final p = TrashPage.parse({'items': [trashJson(), trashJson()], 'total': 41, 'page': 2, 'size': 20}, TrashItem.fromJson);
    expect(p.items.length, 2);
    expect(p.pages, 3);
    expect(TrashPage.parse(null, TrashItem.fromJson).items, isEmpty);
  });

  test('restore result parses with defaults', () {
    final r = TrashRestoreResult.fromJson({'restored': true, 'students_restored': 8, 'expired_meanwhile': 2});
    expect((r.studentsRestored, r.expiredMeanwhile, r.legacy), (8, 2, false));
    expect(TrashRestoreResult.fromJson(null).studentsRestored, 0);
  });

  test('error codes have bilingual text, unknown keeps the server message', () {
    for (final code in ['course_not_found', 'not_in_trash', 'course_purged', 'course_erased', 'purge_blocked', 'reason_required', 'confirm_mismatch']) {
      AppConfig.lang = 'en';
      final en = trashErrorText(code, 'srv');
      AppConfig.lang = 'ar';
      final ar = trashErrorText(code, 'srv');
      expect(en, isNot('srv'));
      expect(ar, isNot(en));
    }
    expect(trashErrorText('other', 'srv'), 'srv');
    expect(trashErrorText(null, 'srv'), 'srv');
  });

  test('course_deleted has an access reason text', () {
    AppConfig.lang = 'en';
    expect(accessReasonTextFor('course_deleted'), contains('deleted'));
    expect(kOfflineBlockingReasons, contains('course_deleted'));
  });
}
