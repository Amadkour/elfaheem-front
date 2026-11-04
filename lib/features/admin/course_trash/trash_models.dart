// lib/features/admin/course_trash/trash_models.dart
//
// Models and server error texts of the Super Admin's "Deleted courses" console (D-260):
// GET/POST /api/v1/admin/course-trash/... Plain Dart, tolerant of missing keys (an older server) and unknown values.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/course_students/cs_models.dart' show csInt, csList, csMap, csStr, csTime;

/// Someone named in the log (who deleted, restored, purged).
class TrashPerson {
  const TrashPerson({this.id, this.name = '', this.role = ''});
  final int? id;
  final String name;
  final String role;

  static TrashPerson? tryParse(Object? v) {
    if (v is! Map) return null;
    final m = csMap(v);
    final name = csStr(m['name']) ?? '';
    final id = m['id'] is num ? (m['id'] as num).toInt() : int.tryParse('${m['id'] ?? ''}');
    if (name.isEmpty && id == null) return null;
    return TrashPerson(id: id, name: name.isEmpty ? '#$id' : name, role: csStr(m['role']) ?? '');
  }
}

/// A role as words.
String trashRoleLabel(String role) => switch (role) {
      'teacher' => t('مدرّس', 'Teacher'),
      'admin' => t('مشرف', 'Admin'),
      'super-admin' || 'super_admin' => t('مشرف عام', 'Super admin'),
      'developer' => t('مطوّر', 'Developer'),
      'org-admin' => t('مدير مؤسسة', 'Org admin'),
      '' => '',
      _ => role,
    };

/// "Name · Role".
String trashPersonText(TrashPerson? p) {
  if (p == null) return '-';
  final r = trashRoleLabel(p.role);
  return r.isEmpty ? p.name : '${p.name} · $r';
}

/// How a course got into the trash.
String trashViaLabel(String via) => switch (via) {
      'teacher' => t('حذفه المدرّس', 'Deleted by the teacher'),
      'admin' => t('حذفه مشرف', 'Deleted by an admin'),
      'legacy' => t('حُذف قبل وجود سلة المحذوفات', 'Deleted before the trash existed'),
      _ => '',
    };

String _bilingual(String? ar, String? en, int id) {
  final a = (ar ?? '').trim();
  final e = (en ?? '').trim();
  final first = AppConfig.lang == 'ar' ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
  return first.isEmpty ? '#$id' : first;
}

/// One course in the trash (`state=trash`).
class TrashItem {
  const TrashItem({
    required this.courseId,
    this.nameAr = '',
    this.nameEn = '',
    this.imageUrl,
    this.teacher,
    this.legacy = false,
    this.via = '',
    this.deletedAt,
    this.deletedBy,
    this.reason,
    this.wasPublished = false,
    this.students = 0,
    this.paidStudents = 0,
    this.sessions = 0,
    this.payments = 0,
  });

  final int courseId;
  final String nameAr;
  final String nameEn;
  final String? imageUrl;
  final TrashPerson? teacher;
  final bool legacy;
  final String via;
  final DateTime? deletedAt;
  final TrashPerson? deletedBy;
  final String? reason;
  final bool wasPublished;
  final int students;
  final int paidStudents;
  final int sessions;
  final int payments;

  String get name => _bilingual(nameAr, nameEn, courseId);

  factory TrashItem.fromJson(Object? j) {
    final m = csMap(j);
    return TrashItem(
      courseId: csInt(m['course_id'] ?? m['id']),
      nameAr: csStr(m['name_ar']) ?? '',
      nameEn: csStr(m['name_en']) ?? '',
      imageUrl: csStr(m['image_url']),
      teacher: TrashPerson.tryParse(m['teacher']),
      legacy: m['legacy'] == true,
      via: csStr(m['via']) ?? '',
      deletedAt: csTime(m['deleted_at']),
      deletedBy: TrashPerson.tryParse(m['deleted_by']),
      reason: csStr(m['reason']),
      wasPublished: m['was_published'] == true,
      students: csInt(m['students']),
      paidStudents: csInt(m['paid_students']),
      sessions: csInt(m['sessions']),
      payments: csInt(m['payments']),
    );
  }
}

/// What a permanent delete removed / kept / detached, per table.
class TrashCounts {
  const TrashCounts([this.byTable = const {}]);
  final Map<String, int> byTable;

  int get total => byTable.values.fold(0, (a, b) => a + b);
  bool get isEmpty => byTable.isEmpty;

  factory TrashCounts.fromJson(Object? j) {
    final m = csMap(j);
    return TrashCounts({for (final e in m.entries) e.key: csInt(e.value)});
  }
}

/// The result summary of a purge (also stored in the history).
class TrashPurgeSummary {
  const TrashPurgeSummary({this.mode = '', this.removed = const TrashCounts(), this.kept = const TrashCounts(), this.detached = const TrashCounts(), this.rowsRemoved = 0, this.files = 0});
  final String mode;
  final TrashCounts removed;
  final TrashCounts kept;
  final TrashCounts detached;
  final int rowsRemoved;
  final int files;

  factory TrashPurgeSummary.fromJson(Object? j) {
    final m = csMap(j);
    final removed = TrashCounts.fromJson(m['removed']);
    return TrashPurgeSummary(
      mode: csStr(m['mode']) ?? '',
      removed: removed,
      kept: TrashCounts.fromJson(m['kept']),
      detached: TrashCounts.fromJson(m['detached']),
      rowsRemoved: m['rows_removed'] == null ? removed.total : csInt(m['rows_removed']),
      files: csInt(m['files'] ?? m['files_deleted']),
    );
  }
}

/// One entry of the permanently-deleted list (`state=purged`).
class PurgedItem {
  const PurgedItem({
    required this.courseId,
    this.nameAr = '',
    this.nameEn = '',
    this.teacher,
    this.state = '',
    this.via = '',
    this.deletedAt,
    this.deletedBy,
    this.deleteReason,
    this.purgedAt,
    this.purgedBy,
    this.purgeReason,
    this.summary = const TrashPurgeSummary(),
  });

  final int courseId;
  final String nameAr;
  final String nameEn;
  final TrashPerson? teacher;

  /// `purged` (the row stays as a financial record) or `erased` (gone completely).
  final String state;
  final String via;
  final DateTime? deletedAt;
  final TrashPerson? deletedBy;
  final String? deleteReason;
  final DateTime? purgedAt;
  final TrashPerson? purgedBy;
  final String? purgeReason;
  final TrashPurgeSummary summary;

  String get name => _bilingual(nameAr, nameEn, courseId);
  bool get erased => state == 'erased';

  factory PurgedItem.fromJson(Object? j) {
    final m = csMap(j);
    return PurgedItem(
      courseId: csInt(m['course_id']),
      nameAr: csStr(m['name_ar']) ?? '',
      nameEn: csStr(m['name_en']) ?? '',
      teacher: TrashPerson.tryParse(m['teacher']),
      state: csStr(m['state']) ?? '',
      via: csStr(m['via']) ?? '',
      deletedAt: csTime(m['deleted_at']),
      deletedBy: TrashPerson.tryParse(m['deleted_by']),
      deleteReason: csStr(m['delete_reason']),
      purgedAt: csTime(m['purged_at']),
      purgedBy: TrashPerson.tryParse(m['purged_by']),
      purgeReason: csStr(m['purge_reason']),
      summary: TrashPurgeSummary.fromJson(m['purge_summary']),
    );
  }
}

/// A page of either list.
class TrashPage<T> {
  const TrashPage({this.items = const [], this.total = 0, this.page = 1, this.size = 20});
  final List<T> items;
  final int total;
  final int page;
  final int size;

  int get pages => size <= 0 ? 1 : ((total + size - 1) ~/ size).clamp(1, 1 << 30);

  static TrashPage<T> parse<T>(Object? j, T Function(Object?) item) {
    final m = csMap(j);
    return TrashPage<T>(
      items: [for (final e in csList(m['items'])) item(e)],
      total: csInt(m['total']),
      page: csInt(m['page'], 1),
      size: csInt(m['size'], 20),
    );
  }
}

/// One line of a course's life: deleted -> restored / purged.
class TrashHistoryEntry {
  const TrashHistoryEntry({this.id = 0, this.state = '', this.via = '', this.deletedAt, this.deletedBy, this.deleteReason, this.restoredAt, this.restoredBy, this.restoreReason, this.purgedAt, this.purgedBy, this.purgeReason, this.summary});
  final int id;
  final String state;
  final String via;
  final DateTime? deletedAt;
  final TrashPerson? deletedBy;
  final String? deleteReason;
  final DateTime? restoredAt;
  final TrashPerson? restoredBy;
  final String? restoreReason;
  final DateTime? purgedAt;
  final TrashPerson? purgedBy;
  final String? purgeReason;
  final TrashPurgeSummary? summary;

  factory TrashHistoryEntry.fromJson(Object? j) {
    final m = csMap(j);
    return TrashHistoryEntry(
      id: csInt(m['id']),
      state: csStr(m['state']) ?? '',
      via: csStr(m['via']) ?? '',
      deletedAt: csTime(m['deleted_at']),
      deletedBy: TrashPerson.tryParse(m['deleted_by']),
      deleteReason: csStr(m['delete_reason']),
      restoredAt: csTime(m['restored_at']),
      restoredBy: TrashPerson.tryParse(m['restored_by']),
      restoreReason: csStr(m['restore_reason']),
      purgedAt: csTime(m['purged_at']),
      purgedBy: TrashPerson.tryParse(m['purged_by']),
      purgeReason: csStr(m['purge_reason']),
      summary: m['purge_summary'] is Map ? TrashPurgeSummary.fromJson(m['purge_summary']) : null,
    );
  }
}

/// What a permanent delete would do: `erased` | `purged` | `blocked` (anything else is treated as blocked).
class TrashPurgePlan {
  const TrashPurgePlan({this.mode = 'blocked', this.removed = const TrashCounts(), this.kept = const TrashCounts(), this.detached = const TrashCounts(), this.rowsRemoved = 0, this.blockedBy});
  final String mode;
  final TrashCounts removed;
  final TrashCounts kept;
  final TrashCounts detached;
  final int rowsRemoved;
  final String? blockedBy;

  bool get erased => mode == 'erased';
  bool get purged => mode == 'purged';
  bool get blocked => !erased && !purged;

  factory TrashPurgePlan.fromJson(Object? j) {
    final m = csMap(j);
    final removed = TrashCounts.fromJson(m['removed']);
    final by = m['blocked_by'];
    return TrashPurgePlan(
      mode: csStr(m['mode']) ?? 'blocked',
      removed: removed,
      kept: TrashCounts.fromJson(m['kept']),
      detached: TrashCounts.fromJson(m['detached']),
      rowsRemoved: m['rows_removed'] == null ? removed.total : csInt(m['rows_removed']),
      blockedBy: by is List ? by.map((e) => '$e').join(', ') : csStr(by),
    );
  }
}

/// `GET /admin/course-trash/{id}`: the item, its history and the purge plan.
class TrashDetail {
  const TrashDetail({required this.item, this.history = const [], this.plan = const TrashPurgePlan()});
  final TrashItem item;
  final List<TrashHistoryEntry> history;
  final TrashPurgePlan plan;

  factory TrashDetail.fromJson(Object? j) {
    final m = csMap(j);
    return TrashDetail(
      item: TrashItem.fromJson(m),
      history: [for (final e in csList(m['history'])) TrashHistoryEntry.fromJson(e)],
      plan: TrashPurgePlan.fromJson(m['purge_plan']),
    );
  }
}

class TrashRestoreResult {
  const TrashRestoreResult({this.legacy = false, this.published = false, this.studentsRestored = 0, this.expiredMeanwhile = 0, this.studentsSkipped = 0, this.favoritesRestored = 0});
  final bool legacy;
  final bool published;
  final int studentsRestored;
  final int expiredMeanwhile;
  final int studentsSkipped;
  final int favoritesRestored;

  factory TrashRestoreResult.fromJson(Object? j) {
    final m = csMap(j);
    return TrashRestoreResult(
      legacy: m['legacy'] == true,
      published: m['published'] == true,
      studentsRestored: csInt(m['students_restored']),
      expiredMeanwhile: csInt(m['expired_meanwhile']),
      studentsSkipped: csInt(m['students_skipped']),
      favoritesRestored: csInt(m['favorites_restored']),
    );
  }
}

/// Text of the table names a purge reports (unknown tables show as they are).
String trashTableLabel(String table) => switch (table) {
      'sessions' => t('الجلسات', 'Sessions'),
      'enrollments' || 'enrolments' => t('الاشتراكات', 'Enrollments'),
      'payments' => t('المدفوعات', 'Payments'),
      'certificates' => t('الشهادات', 'Certificates'),
      'earnings' || 'teacher_earnings' => t('الأرباح', 'Earnings'),
      'materials' => t('المواد', 'Materials'),
      'exams' => t('الاختبارات', 'Exams'),
      'favorites' => t('المفضلة', 'Favorites'),
      _ => table,
    };

/// Bilingual text of the trash's server error codes; anything else keeps the server's own message.
String trashErrorText(String? code, String fallback) => switch (code) {
      'course_not_found' => t('الكورس غير موجود', 'Course not found'),
      'not_in_trash' => t('هذا الكورس ليس في سلة المحذوفات', 'This course is not in the trash'),
      'course_purged' => t('حُذف هذا الكورس نهائياً ولا يمكن استرجاعه', 'This course was permanently deleted and cannot be restored'),
      'course_erased' => t('مُسح هذا الكورس بالكامل', 'This course was erased completely'),
      'purge_blocked' => t('لا يمكن حذف هذا الكورس نهائياً الآن', 'This course cannot be permanently deleted right now'),
      'reason_required' => t('اكتب سبباً لا يقل عن 5 أحرف', 'Write a reason of at least 5 characters'),
      'confirm_mismatch' => t('رقم الكورس المكتوب غير مطابق', 'The course id you typed does not match'),
      'super_admin_required' || 'forbidden' => t('هذه الصفحة للمشرف العام فقط', 'This page is for the super admin only'),
      _ => fallback,
    };
