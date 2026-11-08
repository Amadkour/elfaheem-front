// "All exams" (D-300): every Exam Engine exam the person manages, across courses and the organizations they work in,
// on one page. This file is the pure part (models, filters, counts, the loader); `exam_all_screen.dart` draws it.
//
//   GET /api/v1/exam/exams/mine?org_ids=&course_ids=   one call (back: exam_engine/routers/exams.py `list_my_exams`)
//   GET /api/v1/my-courses?scope=all&limit=100          the teacher's courses: names, and the ids sent above
//   GET /api/v1/org/orgs/{id}/courses?size=100          names of an organization's courses the teacher does not teach
//                                                       (only for organizations with such exams, in parallel)
//
// An older engine without /exams/mine answers 422 (the path reads as /exams/{id}) or a bare 404: the loader falls back
// to the per-space lists (`GET /exams` personal + `?org_id=` per organization).
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'exam_authoring.dart';

/// The page's kill switch.
const kAllExamsFeatureKey = 'exam.all_exams';

/// How students sit the exam, as the list shows it.
enum AllExamType { online, paper, file }

String allExamTypeLabel(AllExamType k) => switch (k) {
      AllExamType.online => t('إلكتروني', 'Online'),
      AllExamType.paper => t('ورقي', 'Paper'),
      AllExamType.file => t('ملف امتحان', 'Exam file'),
    };

/// One exam of the list (an item of GET /exams/mine or GET /exams).
class AllExam {
  AllExam(this.raw)
      : id = asInt(raw['id']),
        orgId = raw['org_id'] == null ? null : asInt(raw['org_id']),
        courseId = raw['course_id'] == null ? null : asInt(raw['course_id']),
        title = '${raw['title'] ?? ''}'.trim(),
        status = '${raw['status'] ?? 'draft'}',
        startsAt = parseEngineUtc(raw['starts_at']),
        endsAt = parseEngineUtc(raw['ends_at']),
        createdAt = parseEngineUtc(raw['created_at']),
        questionCount = asInt(raw['question_count']),
        attempts = asInt(asMap(raw['attempts'])['total']),
        durationMinutes = raw['duration_minutes'] == null ? null : asInt(raw['duration_minutes']);

  final Map<String, dynamic> raw;
  final int id;
  final int? orgId, courseId;
  final String title, status;
  final DateTime? startsAt, endsAt, createdAt;
  final int questionCount, attempts;
  final int? durationMinutes;

  Map<String, dynamic> get _settings => asMap(raw['settings']);

  AllExamType get type {
    if (_settings['paper_file'] is Map) return AllExamType.file;
    if ('${_settings['mode'] ?? ''}' == 'offline') return AllExamType.paper;
    return AllExamType.online;
  }

  bool get draft => status == 'draft';
  bool get published => status == 'published';
  bool get resultsPublished => raw['results_published_at'] != null;
  String get displayTitle => title.isEmpty ? t('اختبار بلا عنوان', 'Untitled exam') : title;

  /// The instant the list sorts and shows: the start when there is one, else when it was made.
  DateTime? get when => startsAt ?? createdAt;
}

/// The status tabs: null = everything but the archive.
const allExamStatuses = <String?>[null, 'draft', 'published', 'closed', 'archived'];

String allExamStatusTab(String? s) => s == null ? t('الكل', 'All') : examStatusLabel(s);

/// What the person narrowed the list to.
class AllExamsFilter {
  const AllExamsFilter({this.query = '', this.status, this.courseId, this.type});

  final String query;
  final String? status;

  /// null = every course; [noCourse] = the exams without a course.
  final int? courseId;
  final AllExamType? type;

  static const noCourse = -1;

  AllExamsFilter copyWith({String? query, Object? status = _keep, Object? courseId = _keep, Object? type = _keep}) => AllExamsFilter(
        query: query ?? this.query,
        status: identical(status, _keep) ? this.status : status as String?,
        courseId: identical(courseId, _keep) ? this.courseId : courseId as int?,
        type: identical(type, _keep) ? this.type : type as AllExamType?,
      );

  /// Course or type narrowed (the "Clear filters" link shows).
  bool get narrowed => courseId != null || type != null || query.trim().isNotEmpty;
}

const _keep = Object();

/// Every loaded exam, the names to show with them, and where they came from.
class AllExamsData {
  const AllExamsData({required this.exams, this.courseNames = const {}, this.courseOrgs = const {}, this.orgNames = const {}, this.fallback = false});

  final List<AllExam> exams;
  final Map<int, String> courseNames;

  /// course id → its organization (null = personal), for "New exam" in that course.
  final Map<int, int?> courseOrgs;
  final Map<int, String> orgNames;

  /// Read from the per-space lists (an older engine): exams of courses taught in an organization without
  /// organization-wide rights may be missing.
  final bool fallback;

  String? courseName(AllExam e) => e.courseId == null ? null : courseNames[e.courseId!];
  String? orgName(AllExam e) => e.orgId == null ? null : orgNames[e.orgId!];

  /// The courses that have exams, by name, for the course filter.
  List<(int, String)> get coursesWithExams {
    final ids = {for (final e in exams) if (e.courseId != null) e.courseId!};
    final out = [for (final id in ids) (id, courseNames[id] ?? t('مقرر #$id', 'Course #$id'))];
    out.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    return out;
  }

  bool get anyWithoutCourse => exams.any((e) => e.courseId == null);
}

/// [exams] narrowed by [f] (status, course, type, then the words of the query over title, course and organization),
/// newest first.
List<AllExam> filterAllExams(AllExamsData data, AllExamsFilter f) {
  final words = f.query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final out = data.exams.where((e) {
    if (f.status == null ? e.status == 'archived' : e.status != f.status) return false;
    if (f.courseId == AllExamsFilter.noCourse ? e.courseId != null : (f.courseId != null && e.courseId != f.courseId)) return false;
    if (f.type != null && e.type != f.type) return false;
    if (words.isEmpty) return true;
    final hay = '${e.title} ${data.courseName(e) ?? ''} ${data.orgName(e) ?? ''}'.toLowerCase();
    return words.every(hay.contains);
  }).toList();
  out.sort((a, b) {
    final wa = a.when, wb = b.when;
    if (wa != null && wb != null && wa != wb) return wb.compareTo(wa);
    return b.id.compareTo(a.id);
  });
  return out;
}

/// How many exams each status tab holds (with the course / type / query narrowing applied, status left out).
Map<String?, int> allExamCounts(AllExamsData data, AllExamsFilter f) => {
      for (final s in allExamStatuses) s: filterAllExams(data, f.copyWith(status: s)).length,
    };

String _pickName(Map<String, dynamic> m) {
  final ar = '${m['name_ar'] ?? ''}'.trim(), en = '${m['name_en'] ?? ''}'.trim();
  final plain = '${m['title'] ?? m['name'] ?? ''}'.trim();
  final s = AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  return s.isNotEmpty ? s : plain;
}

/// Loads the page. [orgs] = the organizations the person works in (id → name), from the app's organization overview.
Future<AllExamsData> loadAllExams({required Map<int, String> orgs, ApiClient? api, ExamAuthoringApi? engine}) async {
  final client = api ?? ApiClient();
  final eng = engine ?? ExamAuthoringApi(client);
  final courseNames = <int, String>{};
  final courseOrgs = <int, int?>{};
  try {
    final r = asMap(await client.get('/api/v1/my-courses', queryParams: {'scope': 'all', 'skip': 0, 'limit': 100}));
    for (final c in asMapList(r['items'])) {
      final id = asInt(c['id']);
      final name = _pickName(c);
      if (name.isNotEmpty) courseNames[id] = name;
      final org = asMap(c['org']);
      courseOrgs[id] = org['id'] == null ? null : asInt(org['id']);
    }
  } catch (_) {
    // not a teacher (an organization's staff), or the list failed: the exams still load, names come below
  }
  final orgIds = orgs.keys.toList()..sort();
  var fallback = false;
  final items = <Map<String, dynamic>>[];
  final mine = await eng.myExams(orgIds: orgIds, courseIds: courseOrgs.keys.toList()..sort());
  if (mine.ok) {
    items.addAll(asMapList(mine.map['items']));
  } else if (mine.unavailable || mine.status == 422) {
    fallback = true;
    final lists = await Future.wait([eng.exams(), for (final o in orgIds) eng.exams(orgId: o)]);
    if (lists.every((r) => !r.ok)) throw ApiException(statusCode: lists.first.status, message: authoringError(lists.first));
    final seen = <int>{};
    for (final r in lists) {
      for (final x in asMapList(r.map['items'])) {
        if (seen.add(asInt(x['id']))) items.add(x);
      }
    }
  } else {
    throw ApiException(statusCode: mine.status, message: authoringError(mine), code: mine.code);
  }
  final exams = [for (final x in items) AllExam(x)];
  // names of organization courses this person does not teach: one page of each such organization, in parallel
  final missing = <int>{for (final e in exams) if (e.orgId != null && e.courseId != null && !courseNames.containsKey(e.courseId)) e.orgId!};
  await Future.wait([
    for (final o in missing)
      () async {
        try {
          final r = asMap(await client.get('/api/v1/org/orgs/$o/courses', queryParams: {'page': 1, 'size': 100}));
          for (final c in asMapList(r['items'])) {
            final id = asInt(c['id']);
            final name = _pickName(c);
            if (name.isNotEmpty) courseNames.putIfAbsent(id, () => name);
            courseOrgs.putIfAbsent(id, () => o);
          }
        } catch (_) {
          // no right to the organization's course list: the card shows the organization instead
        }
      }(),
  ]);
  for (final e in exams) {
    if (e.courseId != null) courseOrgs.putIfAbsent(e.courseId!, () => e.orgId);
  }
  return AllExamsData(exams: exams, courseNames: courseNames, courseOrgs: courseOrgs, orgNames: orgs, fallback: fallback);
}

/// A course the creator can start a new exam in: id (null = no course), organization, name.
typedef NewExamPlace = ({int? courseId, int? orgId, String name});

/// The places "New exam" offers: the courses the person teaches or has exams in, by name, then "Without a course".
List<NewExamPlace> newExamPlaces(AllExamsData data) {
  final out = <NewExamPlace>[
    for (final id in data.courseOrgs.keys)
      if (data.courseNames[id] != null) (courseId: id, orgId: data.courseOrgs[id], name: data.courseNames[id]!),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  out.add((courseId: null, orgId: null, name: t('بدون مقرر (اختبار شخصي)', 'Without a course (personal exam)')));
  return out;
}
