// lib/core/entities/entity_models.dart — the shapes of `/api/v1/entities/...` (D-290, ../back/docs/master_detail/
// CONTRACT.md) as plain parsers. Every key is optional: an older server that lacks a block gives an empty / null
// value and the panel simply draws less. Times are the server's naive UTC, read as UTC instants ([entityTime]).
//
//   EntitySummary.fromJson(GET /students/{id})          header · stats · badges · sections · can
//   EntityPage.fromJson(json, (j) => EntityItem.parse(kind, section, j))   one page of a sub-list
//   EntityListQuery(search:, sort:, filter: {'state': 'withdrawn'}, page:, size:).toParams()
library;

import 'entity_ref.dart';

// ── Value readers (tolerant) ─────────────────────────────────────────────────

/// The server's naive-UTC (or zoned) ISO time as the UTC instant it means; null for anything else.
DateTime? entityTime(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final plainDate = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : (plainDate ? '${s}T00:00:00Z' : '${s}Z'))?.toUtc();
}

Map<String, dynamic>? entityMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> entityMaps(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

int entityInt(Object? v, [int fallback = 0]) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);

int? entityIntOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? entityDouble(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

String? entityString(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

// ── Mini objects (`student_ref`, `teacher_ref`, `course_ref`, `category_ref`) ──

/// A `student_ref` / `teacher_ref` (`{id, name, username, image_url}`) as a ref; null without an id.
EntityRef? personRefFrom(EntityKind kind, Object? json) {
  final j = entityMap(json);
  final id = entityIntOrNull(j?['id']);
  if (j == null || id == null) return null;
  return EntityRef(kind, id, label: entityString(j['name']), imageUrl: entityString(j['image_url']));
}

/// A `category_ref` (`{id, name_ar, name_en}`) as a ref.
EntityRef? categoryRefFrom(Object? json) {
  final j = entityMap(json);
  final id = entityIntOrNull(j?['id']);
  if (j == null || id == null) return null;
  return EntityRef(EntityKind.category, id, label: entityString(j['name_ar']), labelEn: entityString(j['name_en']));
}

/// The @username of a person ref / header, without the "@".
String? usernameOf(Object? json) => entityString(entityMap(json)?['username']);

/// A `course_ref`: the course with its category and teacher.
class EntityCourse {
  const EntityCourse(this.ref, {this.category, this.teacher});

  final EntityRef ref;
  final EntityRef? category;
  final EntityRef? teacher;

  static EntityCourse? fromJson(Object? json) {
    final j = entityMap(json);
    final id = entityIntOrNull(j?['id']);
    if (j == null || id == null) return null;
    return EntityCourse(
      EntityRef(EntityKind.course, id,
          label: entityString(j['name_ar']), labelEn: entityString(j['name_en']), imageUrl: entityString(j['image_url'])),
      category: categoryRefFrom(j['category']),
      teacher: personRefFrom(EntityKind.teacher, j['teacher']),
    );
  }
}

/// An amount of money in one currency (`{amount, currency}`).
class EntityMoney {
  const EntityMoney(this.amount, this.currency);

  final double amount;
  final String currency;

  static EntityMoney? fromJson(Object? json) {
    final j = entityMap(json);
    final a = entityDouble(j?['amount']);
    if (j == null || a == null) return null;
    return EntityMoney(a, entityString(j['currency']) ?? '');
  }

  /// A course's `{amount, currency}` or a teacher's `[{currency, amount}]`, as a list.
  static List<EntityMoney> listFrom(Object? v) {
    if (v is List) return [for (final x in v) ?EntityMoney.fromJson(x)];
    final one = EntityMoney.fromJson(v);
    return one == null ? const [] : [one];
  }
}

// ── Summary ──────────────────────────────────────────────────────────────────

/// A computed fact the app words itself (`code` + `level` + an optional number).
class EntityBadge {
  const EntityBadge(this.code, this.level, this.value);

  final String code;

  /// warn · info · good · bad
  final String level;
  final num? value;

  static EntityBadge? fromJson(Object? json) {
    final j = entityMap(json);
    final code = entityString(j?['code']);
    if (j == null || code == null) return null;
    final v = j['value'];
    return EntityBadge(code, entityString(j['level']) ?? 'info', v is num ? v : null);
  }
}

/// What this viewer may do on the entity.
class EntityCan {
  const EntityCan({this.manage = false, this.message = false, this.seeMoney = false});

  final bool manage;
  final bool message;
  final bool seeMoney;

  static EntityCan fromJson(Object? json) {
    final j = entityMap(json) ?? const {};
    return EntityCan(manage: j['manage'] == true, message: j['message'] == true, seeMoney: j['see_money'] == true);
  }
}

class EntityRating {
  const EntityRating(this.value, this.review, this.at);

  final int value;
  final String? review;
  final DateTime? at;

  static EntityRating? fromJson(Object? json) {
    final j = entityMap(json);
    if (j == null) return null;
    return EntityRating(entityInt(j['value']), entityString(j['review']), entityTime(j['at']));
  }
}

class EntityExams {
  const EntityExams(this.count, this.avgPercentage, this.passed);

  final int count;
  final double? avgPercentage;
  final int passed;

  static EntityExams? fromJson(Object? json) {
    final j = entityMap(json);
    if (j == null) return null;
    return EntityExams(entityInt(j['count']), entityDouble(j['avg_percentage']), entityInt(j['passed']));
  }
}

/// The states of an enrollment row, in the order the filters list them.
const entityEnrollmentStates = ['in_progress', 'completed', 'withdrawn', 'expired', 'pending'];

/// One enrollment (`enrollment` in the contract): a student in a course.
class EntityEnrollment {
  const EntityEnrollment({
    required this.enrollmentId,
    required this.state,
    this.enrolledAt,
    this.expectedEndAt,
    this.progress,
    this.firstActivityAt,
    this.lastActivityAt,
    this.completedAt,
    this.withdrawnAt,
    this.withdrawalReasonCode,
    this.withdrawalReason,
    this.favorited = false,
    this.rating,
    this.exams,
  });

  final int enrollmentId;

  /// pending · in_progress · completed · withdrawn · expired
  final String state;
  final DateTime? enrolledAt;
  final DateTime? expectedEndAt;
  final double? progress;
  final DateTime? firstActivityAt;
  final DateTime? lastActivityAt;
  final DateTime? completedAt;
  final DateTime? withdrawnAt;
  final String? withdrawalReasonCode;

  /// The free text (admins only).
  final String? withdrawalReason;
  final bool favorited;
  final EntityRating? rating;
  final EntityExams? exams;

  static EntityEnrollment fromJson(Map<String, dynamic> j) => EntityEnrollment(
        enrollmentId: entityInt(j['enrollment_id']),
        state: entityString(j['state']) ?? 'in_progress',
        enrolledAt: entityTime(j['enrolled_at']),
        expectedEndAt: entityTime(j['expected_end_at']),
        progress: entityDouble(j['progress']),
        firstActivityAt: entityTime(j['first_activity_at']),
        lastActivityAt: entityTime(j['last_activity_at']),
        completedAt: entityTime(j['completed_at']),
        withdrawnAt: entityTime(j['withdrawn_at']),
        withdrawalReasonCode: entityString(j['withdrawal_reason_code']),
        withdrawalReason: entityString(j['withdrawal_reason']),
        favorited: j['favorited'] == true,
        rating: EntityRating.fromJson(j['rating']),
        exams: EntityExams.fromJson(j['exams']),
      );
}

/// One week of a course's `trend` (new enrollments).
class EntityTrendPoint {
  const EntityTrendPoint(this.weekStart, this.count);

  final DateTime? weekStart;
  final int count;
}

/// The summary of one entity (`GET /api/v1/entities/<plural>/<id>`).
class EntitySummary {
  const EntitySummary({
    required this.kind,
    required this.id,
    this.header = const {},
    this.stats = const {},
    this.badges = const [],
    this.sections = const [],
    this.can = const EntityCan(),
  });

  final EntityKind kind;
  final int id;
  final Map<String, dynamic> header;
  final Map<String, dynamic> stats;
  final List<EntityBadge> badges;

  /// The sub-lists and blocks THIS viewer may open, in display order: the app shows nothing else.
  final List<String> sections;
  final EntityCan can;

  static EntitySummary fromJson(Map<String, dynamic> j, {EntityKind? kind, int? id}) {
    final k = EntityKind.tryParse(entityString(j['kind'])) ?? kind ?? EntityKind.student;
    return EntitySummary(
      kind: k,
      id: entityIntOrNull(j['id']) ?? id ?? 0,
      header: entityMap(j['header']) ?? const {},
      stats: entityMap(j['stats']) ?? const {},
      badges: [for (final b in (j['badges'] is List ? j['badges'] as List : const [])) ?EntityBadge.fromJson(b)],
      sections: [for (final s in (j['sections'] is List ? j['sections'] as List : const [])) if (s is String) s],
      can: EntityCan.fromJson(j['can']),
    );
  }

  /// The entity as a ref (name, image) from its header.
  EntityRef get ref => kind == EntityKind.course || kind == EntityKind.category
      ? EntityRef(kind, id,
          label: entityString(header['name_ar']),
          labelEn: entityString(header['name_en']),
          imageUrl: entityString(header['image_url']))
      : EntityRef(kind, id, label: entityString(header['name']), imageUrl: entityString(header['image_url']));

  String? text(String key) => entityString(header[key]);
  DateTime? time(String key) => entityTime(header[key]);
  bool? flag(String key) => header[key] is bool ? header[key] as bool : null;

  /// A figure of `stats` (null when the server did not send it: the tile is left out).
  num? stat(String key) => stats[key] is num ? stats[key] as num : null;
  DateTime? statTime(String key) => entityTime(stats[key]);

  // course
  EntityRef? get category => categoryRefFrom(header['category']);
  EntityRef? get teacher => personRefFrom(EntityKind.teacher, header['teacher']);
  Map<String, dynamic>? get price => entityMap(header['price']);

  List<EntityTrendPoint> get trend => [
        for (final p in entityMaps(stats['trend'])) EntityTrendPoint(entityTime(p['week_start']), entityInt(p['count'])),
      ];

  List<(String code, int count)> get withdrawalReasons => [
        for (final r in entityMaps(stats['withdrawal_reasons']))
          if (entityString(r['code']) != null) (entityString(r['code'])!, entityInt(r['count'])),
      ];

  /// A learner's own enrollment in this course (`stats.mine`); null when not enrolled or not a learner view.
  EntityEnrollment? get mine {
    final m = entityMap(stats['mine']);
    return m == null ? null : EntityEnrollment.fromJson(m);
  }

  bool get isLearnerView => stats.containsKey('mine');

  /// Whose enrollment [mine] is (a parent's child; the student themselves).
  int? get learnerId => stat('student_id')?.toInt();

  /// A course's or a teacher's revenue (money viewers only), one entry per currency.
  List<EntityMoney> get revenue => EntityMoney.listFrom(stats['revenue']);

  // teacher
  EntityRef? get specialization => categoryRefFrom(header['specialization']);

  // category
  EntityRef? get parent => categoryRefFrom(header['parent']);
  List<EntityRef> get children => [
        for (final c in (header['children'] is List ? header['children'] as List : const [])) ?categoryRefFrom(c),
      ];

  List<(EntityCourse course, int students)> get topCourses => [
        for (final t in entityMaps(stats['top_courses']))
          if (EntityCourse.fromJson(t['course']) case final c?) (c, entityInt(t['students'])),
      ];
}

// ── Sub-lists ────────────────────────────────────────────────────────────────

/// One page of a sub-list (`{items, total, page, size, pages}`).
class EntityPage<T> {
  const EntityPage({this.items = const [], this.total = 0, this.page = 1, this.size = 20, this.pages = 1});

  final List<T> items;
  final int total;
  final int page;
  final int size;
  final int pages;

  bool get hasMore => page < pages;

  static EntityPage<T> fromJson<T>(Object? json, T Function(Map<String, dynamic> j) item) {
    final j = entityMap(json) ?? const {};
    final items = [for (final x in entityMaps(j['items'])) item(x)];
    final size = entityInt(j['size'], items.length);
    final total = entityInt(j['total'], items.length);
    return EntityPage<T>(
      items: items,
      total: total,
      page: entityInt(j['page'], 1),
      size: size,
      pages: entityInt(j['pages'], size > 0 ? ((total + size - 1) ~/ size).clamp(1, 1 << 30) : 1),
    );
  }
}

/// What a sub-list asks for. [filter] holds the contract's filter (`state` or `status`).
class EntityListQuery {
  const EntityListQuery({this.search = '', this.sort, this.filter = const {}, this.page = 1, this.size = 20});

  final String search;
  final String? sort;
  final Map<String, String> filter;
  final int page;
  final int size;

  EntityListQuery copyWith({String? search, String? sort, Map<String, String>? filter, int? page, int? size}) =>
      EntityListQuery(
        search: search ?? this.search,
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        page: page ?? this.page,
        size: size ?? this.size,
      );

  Map<String, dynamic> toParams() => {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (sort != null && sort!.isNotEmpty) 'sort': sort,
        for (final e in filter.entries)
          if (e.value.isNotEmpty) e.key: e.value,
        'page': page,
        'size': size,
      };
}

/// One row of a sub-list, by what it is.
sealed class EntityItem {
  const EntityItem(this.json);

  /// The row as the server sent it.
  final Map<String, dynamic> json;

  /// The row of [section] of a [kind] entity.
  static EntityItem parse(EntityKind kind, String section, Map<String, dynamic> j) => switch ((kind, section)) {
        (EntityKind.student, 'courses') => EnrollmentRow.fromJson(j, EntityKind.course),
        (EntityKind.course, 'students') => EnrollmentRow.fromJson(j, EntityKind.student),
        (EntityKind.teacher || EntityKind.category, 'courses') => CourseRow.fromJson(j),
        (EntityKind.teacher || EntityKind.category, 'students') => PersonRow.fromJson(j, EntityKind.student),
        (EntityKind.category, 'teachers') => PersonRow.fromJson(j, EntityKind.teacher),
        (EntityKind.student, 'payments') => PaymentRow.fromJson(j),
        (EntityKind.student, 'subscriptions') => SubscriptionRow.fromJson(j),
        (EntityKind.student || EntityKind.course, 'grades') || (EntityKind.teacher, 'submissions') => GradeRow.fromJson(j),
        (EntityKind.course, 'lessons') => LessonRow.fromJson(j),
        (EntityKind.course, 'deadlines') => DeadlineRow.fromJson(j),
        (EntityKind.course || EntityKind.teacher, 'reviews') => ReviewRow.fromJson(j),
        _ => RawRow(j),
      };
}

/// A student's course (`{course, ...enrollment}`) or a course's student (`{student, ...enrollment}`).
class EnrollmentRow extends EntityItem {
  const EnrollmentRow(super.json, {required this.subject, this.course, required this.enrollment});

  /// The course (a student's row) or the student (a course's row).
  final EntityRef subject;

  /// The course with its category and teacher (a student's row only).
  final EntityCourse? course;
  final EntityEnrollment enrollment;

  static EnrollmentRow fromJson(Map<String, dynamic> j, EntityKind subjectKind) {
    final course = subjectKind == EntityKind.course ? EntityCourse.fromJson(j['course']) : null;
    final subject = course?.ref ??
        personRefFrom(subjectKind, j[subjectKind.name]) ??
        EntityRef(subjectKind, 0);
    return EnrollmentRow(j, subject: subject, course: course, enrollment: EntityEnrollment.fromJson(j));
  }
}

/// A course of a teacher or a category (`{course, status, is_published, students, completion_rate, rating_avg,
/// revenue}`).
class CourseRow extends EntityItem {
  const CourseRow(super.json,
      {required this.course,
      this.status,
      this.isPublished = false,
      this.archivedAt,
      this.students = 0,
      this.completionRate,
      this.ratingAvg,
      this.revenue});

  final EntityCourse course;
  final String? status;
  final bool isPublished;
  final DateTime? archivedAt;
  final int students;
  final double? completionRate;
  final double? ratingAvg;
  final EntityMoney? revenue;

  static CourseRow fromJson(Map<String, dynamic> j) => CourseRow(
        j,
        course: EntityCourse.fromJson(j['course']) ?? const EntityCourse(EntityRef(EntityKind.course, 0)),
        status: entityString(j['status']),
        isPublished: j['is_published'] == true,
        archivedAt: entityTime(j['archived_at']),
        students: entityInt(j['students']),
        completionRate: entityDouble(j['completion_rate']),
        ratingAvg: entityDouble(j['rating_avg']),
        revenue: EntityMoney.fromJson(j['revenue']),
      );
}

/// A student or teacher with their figures across a teacher's / category's courses.
class PersonRow extends EntityItem {
  const PersonRow(super.json,
      {required this.person,
      this.username,
      this.courses = 0,
      this.students,
      this.avgProgress,
      this.lastActivityAt,
      this.attention = false});

  final EntityRef person;
  final String? username;
  final int courses;

  /// A category's teacher: their students there.
  final int? students;
  final double? avgProgress;
  final DateTime? lastActivityAt;

  /// Quiet for two weeks, or still under 20 % a month in.
  final bool attention;

  static PersonRow fromJson(Map<String, dynamic> j, EntityKind kind) => PersonRow(
        j,
        person: personRefFrom(kind, j[kind.name]) ?? EntityRef(kind, 0),
        username: usernameOf(j[kind.name]),
        courses: entityInt(j['courses']),
        students: entityIntOrNull(j['students']),
        avgProgress: entityDouble(j['avg_progress']),
        lastActivityAt: entityTime(j['last_activity_at']),
        attention: j['attention'] == true,
      );
}

/// One assessment: a legacy exam, an Exam Engine result or an assignment (`source`). A held result reaches a student
/// or parent with `held` and no figures.
class GradeRow extends EntityItem {
  const GradeRow(super.json,
      {required this.id,
      required this.source,
      this.title = '',
      this.course,
      this.student,
      this.at,
      this.percentage,
      this.score,
      this.maxScore,
      this.passed,
      this.held = false,
      this.needsReview = false});

  final int id;
  final String source;
  final String title;
  final EntityCourse? course;
  final EntityRef? student;
  final DateTime? at;
  final double? percentage;
  final double? score;
  final double? maxScore;
  final bool? passed;
  final bool held;
  final bool needsReview;

  static GradeRow fromJson(Map<String, dynamic> j) => GradeRow(
        j,
        id: entityInt(j['id']),
        source: entityString(j['source']) ?? 'exam',
        title: entityString(j['title']) ?? '',
        course: EntityCourse.fromJson(j['course']),
        student: personRefFrom(EntityKind.student, j['student']),
        at: entityTime(j['at']),
        percentage: entityDouble(j['percentage']),
        score: entityDouble(j['score']),
        maxScore: entityDouble(j['max_score']),
        passed: j['passed'] is bool ? j['passed'] as bool : null,
        held: j['held'] == true,
        needsReview: j['needs_review'] == true,
      );
}

/// One session of a learner's course: `done` · `in_progress` · `upcoming` · `open`.
class LessonRow extends EntityItem {
  const LessonRow(super.json,
      {required this.id,
      this.name = '',
      this.scheduledAt,
      this.materials = 0,
      this.completed = 0,
      this.attended = false,
      this.state = 'open'});

  final int id;
  final String name;
  final DateTime? scheduledAt;
  final int materials;
  final int completed;
  final bool attended;
  final String state;

  static LessonRow fromJson(Map<String, dynamic> j) => LessonRow(
        j,
        id: entityInt(j['id']),
        name: entityString(j['name']) ?? '',
        scheduledAt: entityTime(j['scheduled_at']),
        materials: entityInt(j['materials']),
        completed: entityInt(j['completed']),
        attended: j['attended'] == true,
        state: entityString(j['state']) ?? 'open',
      );
}

/// What is due next in a learner's course: `exam` · `assignment` · `session` · `access_end`.
class DeadlineRow extends EntityItem {
  const DeadlineRow(super.json, {required this.type, required this.id, this.title = '', this.at, this.opensAt});

  final String type;
  final int id;
  final String title;
  final DateTime? at;
  final DateTime? opensAt;

  static DeadlineRow fromJson(Map<String, dynamic> j) => DeadlineRow(
        j,
        type: entityString(j['type']) ?? 'session',
        id: entityInt(j['id']),
        title: entityString(j['title']) ?? '',
        at: entityTime(j['at']),
        opensAt: entityTime(j['opens_at']),
      );
}

/// A course's rating with its text.
class ReviewRow extends EntityItem {
  const ReviewRow(super.json, {required this.id, this.value = 0, this.review, this.at, this.course, this.student});

  final int id;
  final int value;
  final String? review;
  final DateTime? at;
  final EntityCourse? course;
  final EntityRef? student;

  static ReviewRow fromJson(Map<String, dynamic> j) => ReviewRow(
        j,
        id: entityInt(j['id']),
        value: entityInt(j['value']),
        review: entityString(j['review']),
        at: entityTime(j['at']),
        course: EntityCourse.fromJson(j['course']),
        student: personRefFrom(EntityKind.student, j['student']),
      );
}

/// A course or teacher a notification (or any server text) mentions: a chip, a link only when [canOpen].
class EntityMention {
  const EntityMention(this.ref, {this.canOpen = true});

  final EntityRef ref;
  final bool canOpen;

  static List<EntityMention> listFrom(Object? json) {
    if (json is! List) return const [];
    final out = <EntityMention>[];
    for (final raw in json) {
      final j = entityMap(raw);
      final kind = EntityKind.tryParse(entityString(j?['kind']));
      final id = entityIntOrNull(j?['id']);
      if (j == null || kind == null || id == null) continue;
      out.add(EntityMention(
        EntityRef(kind, id,
            label: entityString(j['name']) ?? entityString(j['name_ar']),
            labelEn: entityString(j['name_en']),
            imageUrl: entityString(j['image_url'])),
        canOpen: j['can_open'] != false,
      ));
    }
    return out;
  }
}

/// A student's payment (admins).
class PaymentRow extends EntityItem {
  const PaymentRow(super.json,
      {required this.id,
      this.course,
      this.amount,
      this.currency = '',
      this.status,
      this.method,
      this.paidAt,
      this.refundedAt,
      this.createdAt});

  final int id;
  final EntityCourse? course;
  final double? amount;
  final String currency;
  final String? status;
  final String? method;
  final DateTime? paidAt;
  final DateTime? refundedAt;
  final DateTime? createdAt;

  static PaymentRow fromJson(Map<String, dynamic> j) => PaymentRow(
        j,
        id: entityInt(j['id']),
        course: EntityCourse.fromJson(j['course']),
        amount: entityDouble(j['amount']),
        currency: entityString(j['currency']) ?? '',
        status: entityString(j['status']),
        method: entityString(j['method']) ?? entityString(j['provider']),
        paidAt: entityTime(j['paid_at']),
        refundedAt: entityTime(j['refunded_at']),
        createdAt: entityTime(j['created_at']),
      );
}

/// A student's subscription event (admins).
class SubscriptionRow extends EntityItem {
  const SubscriptionRow(super.json,
      {required this.id, required this.type, this.actorType, this.reason, this.course, this.occurredAt});

  final int id;
  final String type;
  final String? actorType;
  final String? reason;
  final EntityCourse? course;
  final DateTime? occurredAt;

  static SubscriptionRow fromJson(Map<String, dynamic> j) => SubscriptionRow(
        j,
        id: entityInt(j['id']),
        type: entityString(j['type']) ?? '',
        actorType: entityString(j['actor_type']),
        reason: entityString(j['reason']),
        course: EntityCourse.fromJson(j['course']),
        occurredAt: entityTime(j['occurred_at']),
      );
}

/// A row of a section this app version does not know (drawn as nothing special).
class RawRow extends EntityItem {
  const RawRow(super.json);
}

/// One event of a student's history in one course (`{at, type, data}`), newest first.
class EntityTimelineEvent {
  const EntityTimelineEvent(this.at, this.type, this.data);

  final DateTime? at;

  /// enrolled · first_visit · material_completed · live_attended · exam_submitted · favorited · rated · completed ·
  /// withdrawn · subscription
  final String type;
  final Map<String, dynamic> data;

  static EntityTimelineEvent fromJson(Map<String, dynamic> j) =>
      EntityTimelineEvent(entityTime(j['at']), entityString(j['type']) ?? '', entityMap(j['data']) ?? const {});
}
