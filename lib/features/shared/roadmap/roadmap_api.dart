// lib/features/shared/roadmap/roadmap_api.dart
//
// The course roadmap and "Recommended for you" (D-120): pure models, the editor's draft and the API. Personal
// accounts on personal courses only — the server answers 403 individual_only / org_course / feature_off and every
// part of the app then draws nothing ([RoadmapHidden]).
//
//   GET  /api/v1/roadmap/courses/{id}              Roadmap (previous · course · next with prerequisites)
//   PUT  /api/v1/roadmap/courses/{id}              owner: {next_course_ids, prerequisite_ids, level, tags}
//   GET  /api/v1/roadmap/courses/{id}/candidates   owner: the courses that may be picked
//   GET  /api/v1/me/journey                        Journey with every step (null = no clear field)
//   GET  /api/v1/me/recommendations?skip&limit     RecPage
//   POST /api/v1/me/recommendations/{id}/dismiss   "Not interested" (DELETE = undo)
//   POST /api/v1/me/recommendations/events         shown / opened reports (RecEventLog batches them)
//   GET  /api/v1/admin/recommendations/stats       super admin: numbers per reason + weights · PUT …/settings
//   GET  /api/v1/me/learning-prefs · PUT           LearningPrefs
//   GET  /api/v1/categories                        the interests picker's fields
//
// The home's card reads `journey` from /me/home (MeHome.journey), never a call of its own.
// Server: ../back/routers/learning_router.py, services/learning/.
library;

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../../../core/app_mode.dart';
import '../../admin/admin_common.dart' show t;
import '../../student/models.dart' show AppCurrency, AppCurrencyX;

const kRoadmapKey = 'roadmap';
const kRoadmapPathKey = 'roadmap.path';
const kRoadmapTeacherPicksKey = 'roadmap.teacher_picks';
const kRoadmapRecsKey = 'roadmap.recommendations';
const kRoadmapJourneyKey = 'roadmap.journey';
const kRoadmapEnrollKey = 'course.enroll_roadmap';
const kRecsAdminKey = 'admin.recommendations';

/// The course page's tab id.
const kRoadmapTab = 'path';

const roadmapLevels = ['beginner', 'intermediate', 'advanced'];

/// A roadmap kill switch is off: the key itself or the whole `roadmap`.
bool roadmapOff(String key) => AppConfig.disableList.contains(kRoadmapKey) || AppConfig.disableList.contains(key);

/// The account works in an organization (an org-admin / org-staff login, or a live membership while organizations
/// are on): it gets no roadmap and no recommendations. The server decides too; this only spares the calls.
bool roadmapOrgAccount(String? role) =>
    role == 'org-admin' || role == 'org-staff' || AppModeController.instance.available;

String roadmapLevelLabel(String? level) => switch (level) {
  'beginner' => t('مبتدئ', 'Beginner'),
  'intermediate' => t('متوسط', 'Intermediate'),
  'advanced' => t('متقدم', 'Advanced'),
  _ => t('بدون مستوى', 'No level'),
};

int _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
double _dbl(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String? _str(dynamic v) => v == null ? null : '$v';
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

String _pick(String? ar, String? en) {
  final a = (ar ?? '').trim(), e = (en ?? '').trim();
  return AppConfig.lang == 'ar' ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
}

/// A category (a "field").
class RmField {
  const RmField({required this.id, this.nameAr, this.nameEn, this.parentId});

  final int id;
  final String? nameAr, nameEn;

  /// A sub-field's parent (the interests picker groups by it); null for a top field.
  final int? parentId;

  String get name => _pick(nameAr, nameEn);

  static RmField? fromJson(dynamic j) {
    final m = _map(j);
    if (m.isEmpty) return null;
    return RmField(
      id: _int(m['id']),
      nameAr: _str(m['name_ar']),
      nameEn: _str(m['name_en']),
      parentId: m['parent_id'] == null ? null : _int(m['parent_id']),
    );
  }
}

/// A prerequisite of a next course (`done` only for a student).
class RmPrereq {
  const RmPrereq({required this.id, this.nameAr, this.nameEn, this.done});

  final int id;
  final String? nameAr, nameEn;
  final bool? done;

  String get name => _pick(nameAr, nameEn);

  factory RmPrereq.fromJson(Map<String, dynamic> m) => RmPrereq(
    id: _int(m['id']),
    nameAr: _str(m['name_ar']),
    nameEn: _str(m['name_en']),
    done: m['done'] is bool ? m['done'] as bool : null,
  );
}

/// The viewer's state of a course: completed · in_progress · not_started; null for the teacher.
enum RmState { completed, inProgress, notStarted }

RmState? _state(dynamic v) => switch (v) {
  'completed' => RmState.completed,
  'in_progress' => RmState.inProgress,
  'not_started' => RmState.notStarted,
  _ => null,
};

class RmCourse {
  const RmCourse({
    required this.id,
    this.nameAr,
    this.nameEn,
    this.imageUrl,
    this.level,
    this.tags = const [],
    this.field,
    this.teacherName,
    this.isPublished = true,
    this.isPrivate = false,
    this.isFree = false,
    this.finalPrice = 0,
    this.currency = AppCurrency.egp,
    this.state,
    this.progress = 0,
    this.order,
    this.prerequisites = const [],
    this.prereqsMet,
    this.current = false,
    this.kind,
  });

  final int id;
  final String? nameAr, nameEn, imageUrl, level, teacherName;
  final List<String> tags;
  final RmField? field;
  final bool isPublished, isPrivate, isFree;
  final double finalPrice;
  final AppCurrency currency;
  final RmState? state;
  final double progress;
  final int? order;
  final List<RmPrereq> prerequisites;
  final bool? prereqsMet;

  /// Journey steps: the next step of the path.
  final bool current;

  /// Journey's next step: continue (enrolled) · start.
  final String? kind;

  String get name => _pick(nameAr, nameEn);
  bool get done => state == RmState.completed;

  factory RmCourse.fromJson(Map<String, dynamic> m) => RmCourse(
    id: _int(m['id']),
    nameAr: _str(m['name_ar']),
    nameEn: _str(m['name_en']),
    imageUrl: (_str(m['image_url']) ?? '').isEmpty ? null : _str(m['image_url']),
    level: _str(m['level']),
    tags: [for (final x in (m['tags'] is List ? m['tags'] as List : const [])) '$x'],
    field: RmField.fromJson(m['category']),
    teacherName: _str(_map(m['teacher'])['name']),
    isPublished: m['is_published'] != false,
    isPrivate: m['is_private'] == true,
    isFree: m['is_free'] == true,
    finalPrice: _dbl(m['final_price']),
    currency: AppCurrencyX.fromCode(_str(m['currency'])),
    state: _state(m['state']),
    progress: _dbl(m['progress']),
    order: m['order'] == null ? null : _int(m['order']),
    prerequisites: [for (final p in _maps(m['prerequisites'])) RmPrereq.fromJson(p)],
    prereqsMet: m['prereqs_met'] is bool ? m['prereqs_met'] as bool : null,
    current: m['current'] == true,
    kind: _str(m['kind']),
  );
}

class Roadmap {
  const Roadmap({required this.course, this.previous = const [], this.next = const [], this.prerequisites = const [], this.canEdit = false});

  final RmCourse course;
  final List<RmCourse> previous, next;
  final List<RmPrereq> prerequisites;
  final bool canEdit;

  bool get isEmpty => previous.isEmpty && next.isEmpty;

  /// A next course the student has not taken yet (the "Enroll in the whole path" button needs one).
  bool get hasNotTaken => next.any((n) => n.state == RmState.notStarted);

  factory Roadmap.fromJson(dynamic j) {
    final m = _map(j);
    return Roadmap(
      course: RmCourse.fromJson(_map(m['course'])),
      previous: [for (final c in _maps(m['previous'])) RmCourse.fromJson(c)],
      next: [for (final c in _maps(m['next'])) RmCourse.fromJson(c)],
      prerequisites: [for (final p in _maps(m['prerequisites'])) RmPrereq.fromJson(p)],
      canEdit: m['can_edit'] == true,
    );
  }
}

/// "Continue your journey in …": the home card (no steps) and the journey page (with steps).
class Journey {
  const Journey({required this.source, required this.next, this.anchorCourseId, this.field, this.done = 0, this.total = 0, this.steps = const []});

  final String source; // roadmap | interest
  final int? anchorCourseId;
  final RmField? field;
  final RmCourse next;
  final int done, total;
  final List<RmCourse> steps;

  double get fraction => total <= 0 ? 0 : (done / total).clamp(0, 1).toDouble();

  static Journey? fromJson(dynamic j) {
    final m = _map(j);
    final next = _map(m['next']);
    if (m.isEmpty || next.isEmpty) return null;
    return Journey(
      source: _str(m['source']) ?? 'roadmap',
      anchorCourseId: m['anchor_course_id'] == null ? null : _int(m['anchor_course_id']),
      field: RmField.fromJson(m['field']),
      next: RmCourse.fromJson(next),
      done: _int(m['done']),
      total: _int(m['total']),
      steps: [for (final s in _maps(m['steps'])) RmCourse.fromJson(s)],
    );
  }

  /// "Continue your journey in Python" / "Continue your journey".
  String get title {
    final f = field?.name ?? '';
    return f.isEmpty ? t('واصل رحلتك', 'Continue your journey') : t('واصل رحلتك في $f', 'Continue your journey in $f');
  }

  /// "Next: Python 2" / "Continue: Python 2".
  String get nextLine => next.kind == 'continue' ? t('أكمل: ${next.name}', 'Continue: ${next.name}') : t('التالي: ${next.name}', 'Next: ${next.name}');

  /// "2 of 3 done".
  String get doneLine => t('$done من $total مكتملة', '$done of $total done');
}

class RecItem {
  const RecItem({required this.course, required this.reason, this.reasonAr, this.reasonEn});

  final RmCourse course;
  final String reason;
  final String? reasonAr, reasonEn;

  /// The server's sentence, else a generic one per code.
  String get reasonText {
    final s = _pick(reasonAr, reasonEn);
    if (s.isNotEmpty) return s;
    return switch (reason) {
      'similar_students' => t('طلاب مثلك درسوه', 'Students like you took this'),
      'same_teacher' => t('من نفس المدرّس', 'From the same instructor'),
      'because_completed' || 'because_taking' || 'similar_topics' => t('قريب مما تدرسه', 'Close to what you study'),
      'matches_interest' || 'popular_in_field' => t('رائج في مجالك', 'Popular in your field'),
      'explore_field' => t('رائج في مجال جديد عليك', 'Popular in a field new to you'),
      _ => t('رائج على المنصة', 'Popular on the platform'),
    };
  }

  factory RecItem.fromJson(Map<String, dynamic> m) => RecItem(
    course: RmCourse.fromJson(_map(m['course'])),
    reason: _str(m['reason']) ?? 'popular',
    reasonAr: _str(m['reason_ar']),
    reasonEn: _str(m['reason_en']),
  );
}

class RecPage {
  const RecPage({this.items = const [], this.total = 0, this.hidden = false});

  final List<RecItem> items;
  final int total;
  final bool hidden;

  factory RecPage.fromJson(dynamic j) {
    final m = _map(j);
    return RecPage(
      items: [for (final i in _maps(m['items'])) RecItem.fromJson(i)],
      total: _int(m['total']),
      hidden: m['hidden'] == true,
    );
  }
}

class LearningPrefs {
  const LearningPrefs({
    this.hide = false,
    this.chosen = false,
    this.interests = const [],
    this.inferred = const [],
    this.dismissed = 0,
    this.choices = const [],
  });

  final bool hide, chosen;
  final List<RmField> interests, inferred;
  final int dismissed;

  /// Every field the student may pick, sub-fields with their parent (empty from an older server).
  final List<RmField> choices;

  factory LearningPrefs.fromJson(dynamic j) {
    final m = _map(j);
    List<RmField> fields(dynamic v) => [for (final f in _maps(v)) ?RmField.fromJson(f)];
    return LearningPrefs(
      hide: m['hide_recommendations'] == true,
      chosen: m['chosen'] == true,
      interests: fields(m['interests']),
      inferred: fields(m['inferred']),
      dismissed: _int(m['dismissed']),
      choices: fields(m['choices']),
    );
  }
}

/// The picker's groups: each top field with its sub-fields, in the server's order; a sub-field whose parent is not
/// listed stands as a group of its own.
List<(RmField, List<RmField>)> interestGroups(List<RmField> fields) {
  final tops = [for (final f in fields) if (f.parentId == null) f];
  final topIds = {for (final f in tops) f.id};
  final kids = <int, List<RmField>>{};
  final orphans = <RmField>[];
  for (final f in fields) {
    final p = f.parentId;
    if (p == null) continue;
    if (topIds.contains(p)) {
      (kids[p] ??= []).add(f);
    } else {
      orphans.add(f);
    }
  }
  return [for (final t in tops) (t, kids[t.id] ?? const <RmField>[]), for (final o in orphans) (o, const <RmField>[])];
}

/// One reason's numbers for the super admin.
class RecReasonStat {
  const RecReasonStat({required this.reason, this.shown = 0, this.opened = 0, this.dismissed = 0, this.enrolled = 0, this.openRate = 0, this.enrollRate = 0});

  final String reason;
  final int shown, opened, dismissed, enrolled;
  final double openRate, enrollRate;

  factory RecReasonStat.fromJson(Map<String, dynamic> m) => RecReasonStat(
    reason: _str(m['reason']) ?? 'popular',
    shown: _int(m['shown']),
    opened: _int(m['opened']),
    dismissed: _int(m['dismissed']),
    enrolled: _int(m['enrolled']),
    openRate: _dbl(m['open_rate']),
    enrollRate: _dbl(m['enroll_rate']),
  );
}

/// GET /api/v1/admin/recommendations/stats.
class RecStats {
  const RecStats({this.days = 30, this.students = 0, this.total = const RecReasonStat(reason: 'total'), this.byReason = const [], this.weights = const {}, this.defaults = const {}, this.countsAt});

  final int days, students;
  final RecReasonStat total;
  final List<RecReasonStat> byReason;
  final Map<String, double> weights, defaults;
  final String? countsAt;

  factory RecStats.fromJson(dynamic j) {
    final m = _map(j);
    Map<String, double> w(dynamic v) => {for (final e in _map(v).entries) e.key: _dbl(e.value)};
    final t = _map(m['total']);
    return RecStats(
      days: _int(m['days']),
      students: _int(m['students']),
      total: RecReasonStat.fromJson({...t, 'reason': 'total'}),
      byReason: [for (final r in _maps(m['by_reason'])) RecReasonStat.fromJson(r)],
      weights: w(m['weights']),
      defaults: w(m['defaults']),
      countsAt: _str(m['counts_at']),
    );
  }
}

/// The four signals the super admin weighs, in display order.
const recWeightKeys = ['similar_students', 'content', 'same_teacher', 'popularity'];

String recWeightLabel(String key) => switch (key) {
  'similar_students' => t('طلاب مشابهون', 'Similar students'),
  'content' => t('المجال والمواضيع والمستوى', 'Field, topics and level'),
  'same_teacher' => t('نفس المدرّس', 'Same instructor'),
  _ => t('الرواج', 'Popularity'),
};

String recReasonLabel(String reason) => switch (reason) {
  'because_completed' => t('لأنك أكملت…', 'Because you completed…'),
  'because_taking' => t('لأنك تدرس…', 'Because you’re taking…'),
  'matches_interest' => t('ضمن اهتماماتك', 'Matches your interest'),
  'similar_topics' => t('مواضيع قريبة', 'Close topics'),
  'similar_students' => t('طلاب مثلك', 'Students like you'),
  'same_teacher' => t('نفس المدرّس', 'Same instructor'),
  'popular_in_field' => t('رائج في المجال', 'Popular in the field'),
  'explore_field' => t('مجال جديد عليك', 'A field new to you'),
  _ => t('رائج على المنصة', 'Popular on the platform'),
};

/// Collects `shown` / `opened` reports and sends them in batches (once per course per kind and session); never
/// fails the screen. [send] defaults to the API (a test passes its own).
class RecEventLog {
  RecEventLog({Future<void> Function(List<Map<String, dynamic>> items)? send}) : _send = send ?? const RoadmapApi().logEvents;

  static final RecEventLog instance = RecEventLog();

  final Future<void> Function(List<Map<String, dynamic>> items) _send;
  final Set<String> _seen = {};
  final List<Map<String, dynamic>> _pending = [];
  bool _scheduled = false;

  void shown(Iterable<int> courseIds) {
    for (final id in courseIds) {
      _add(id, 'shown');
    }
  }

  void opened(int courseId) => _add(courseId, 'opened');

  void _add(int id, String kind) {
    if (!_seen.add('$kind:$id')) return;
    _pending.add({'course_id': id, 'kind': kind});
    if (_scheduled) return;
    _scheduled = true;
    Future<void>.delayed(const Duration(seconds: 2), flush);
  }

  /// Sends what is pending (a batch at most 50); a failure drops it quietly (these are numbers, not data).
  Future<void> flush() async {
    _scheduled = false;
    if (_pending.isEmpty) return;
    final batch = _pending.take(50).toList();
    _pending.removeRange(0, batch.length);
    try {
      await _send(batch);
    } catch (_) {}
    if (_pending.isNotEmpty) await flush();
  }
}

/// The teacher's edit of a roadmap (pure: the editor sheet only draws it).
class RoadmapDraft {
  RoadmapDraft({List<RmCourse> next = const [], List<RmCourse> prereqs = const [], this.level, List<String> tags = const []})
    : next = [...next],
      prereqs = [...prereqs],
      tags = [...tags];

  factory RoadmapDraft.of(Roadmap r, List<RmCourse> candidates) {
    final byId = {for (final c in candidates) c.id: c};
    return RoadmapDraft(
      next: r.next,
      prereqs: [for (final p in r.prerequisites) byId[p.id] ?? RmCourse(id: p.id, nameAr: p.nameAr, nameEn: p.nameEn)],
      level: r.course.level,
      tags: r.course.tags,
    );
  }

  static const maxCourses = 8;
  static const maxTags = 8;
  static const tagLength = 24;

  final List<RmCourse> next;
  final List<RmCourse> prereqs;
  String? level;
  final List<String> tags;

  Set<int> get usedIds => {...next.map((c) => c.id), ...prereqs.map((c) => c.id)};

  /// Courses a picker may still offer (not already a next course nor a prerequisite).
  List<RmCourse> available(List<RmCourse> candidates) => [for (final c in candidates) if (!usedIds.contains(c.id)) c];

  bool addNext(RmCourse c) {
    if (next.length >= maxCourses || usedIds.contains(c.id)) return false;
    next.add(c);
    return true;
  }

  bool addPrereq(RmCourse c) {
    if (prereqs.length >= maxCourses || usedIds.contains(c.id)) return false;
    prereqs.add(c);
    return true;
  }

  /// Moves the next course at [from] to the position [to] (ReorderableListView.onReorderItem's indices).
  void moveNext(int from, int to) {
    if (from < 0 || from >= next.length) return;
    final item = next.removeAt(from);
    next.insert(to.clamp(0, next.length), item);
  }

  /// Adds a topic word (trimmed, collapsed spaces, case-insensitive unique). False when nothing was added.
  bool addTag(String raw) {
    var s = raw.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
    if (s.length > tagLength) s = s.substring(0, tagLength);
    if (s.isEmpty || tags.length >= maxTags || tags.any((x) => x.toLowerCase() == s.toLowerCase())) return false;
    tags.add(s);
    return true;
  }

  Map<String, dynamic> toJson() => {
    'next_course_ids': [for (final c in next) c.id],
    'prerequisite_ids': [for (final c in prereqs) c.id],
    'level': level,
    'tags': tags,
  };
}

/// The server said this part is not for this account / course / switched off: draw nothing.
bool roadmapHiddenError(Object e) {
  final x = ApiException.from(e);
  return x.statusCode == 403 && const {'individual_only', 'org_course', 'feature_off', 'students_only'}.contains(x.code);
}

class RoadmapApi {
  const RoadmapApi();

  static const _timeout = Duration(seconds: 20);

  ApiClient get _api => ApiClient();

  Future<Roadmap> roadmap(int courseId) async => Roadmap.fromJson(await _api.get('/api/v1/roadmap/courses/$courseId').timeout(_timeout));

  Future<Roadmap> save(int courseId, RoadmapDraft d) async =>
      Roadmap.fromJson(await _api.put('/api/v1/roadmap/courses/$courseId', body: d.toJson()).timeout(_timeout));

  Future<List<RmCourse>> candidates(int courseId) async {
    final r = await _api.get('/api/v1/roadmap/courses/$courseId/candidates').timeout(_timeout);
    return [for (final c in _maps(_map(r)['items'])) RmCourse.fromJson(c)];
  }

  Future<Journey?> journey() async => Journey.fromJson(_map(await _api.get('/api/v1/me/journey').timeout(_timeout))['journey']);

  Future<RecPage> recommendations({int skip = 0, int limit = 10}) async =>
      RecPage.fromJson(await _api.get('/api/v1/me/recommendations', queryParams: {'skip': skip, 'limit': limit}).timeout(_timeout));

  Future<void> dismiss(int courseId) async => _api.post('/api/v1/me/recommendations/$courseId/dismiss').timeout(_timeout);

  /// Undo "Not interested".
  Future<void> restore(int courseId) async => _api.delete('/api/v1/me/recommendations/$courseId/dismiss').timeout(_timeout);

  Future<void> logEvents(List<Map<String, dynamic>> items) async =>
      _api.post('/api/v1/me/recommendations/events', body: {'items': items}).timeout(_timeout);

  Future<RecStats> stats({int days = 30}) async =>
      RecStats.fromJson(await _api.get('/api/v1/admin/recommendations/stats', queryParams: {'days': days}).timeout(_timeout));

  Future<Map<String, double>> saveWeights(Map<String, double> weights) async {
    final r = _map(await _api.put('/api/v1/admin/recommendations/settings', body: {'weights': weights}).timeout(_timeout));
    return {for (final e in _map(r['weights']).entries) e.key: _dbl(e.value)};
  }

  /// The platform's top categories (the interests picker's choices).
  Future<List<RmField>> categories() async {
    final r = await _api.get('/api/v1/categories').timeout(_timeout);
    return [for (final c in _maps(r is Map ? r['items'] : r)) ?RmField.fromJson(c)];
  }

  Future<LearningPrefs> prefs() async => LearningPrefs.fromJson(await _api.get('/api/v1/me/learning-prefs').timeout(_timeout));

  Future<LearningPrefs> savePrefs({bool? hide, List<int>? interestIds, bool reset = false, bool clearDismissed = false}) async =>
      LearningPrefs.fromJson(
        await _api
            .put('/api/v1/me/learning-prefs', body: {
              'hide_recommendations': ?hide,
              'interest_ids': ?interestIds,
              if (reset) 'reset_interests': true,
              if (clearDismissed) 'clear_dismissed': true,
            })
            .timeout(_timeout),
      );
}
