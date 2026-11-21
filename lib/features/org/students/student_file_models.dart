// lib/features/org/students/student_file_models.dart — the unified student file, pure (D-1400, phase 1).
//
//   StudentFile.fromJson(GET …/students/{uid}/file)   header facts, academic summary, intake, journey, open items, can
//   StudentCan                                         what the caller may see (each tab and section hides without it)
//   JourneyNode → AppRoadmapNode                       the journey rail (applied → accepted → year 1 … → graduation)
//   TimelineItem / TimelinePage                        GET …/timeline (append-only, newest first, paged with `before`)
//   groupTimelineByYear                                academic-year blocks (September to August), days inside them
//   timelineKindText · timelineIcon · timelineTone     the words, icon and tone of a timeline kind
//   StudentFileTab · studentFileTabs(can)              the tabs the caller sees, in order
//
// Contract: docs/student-lifecycle/CONTRACT.md §3.4, §4.2, §4.3, §4.5, §5. Tests: test/org/student_file_models_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;
import 'package:flutter_education_app/design/app_roadmap.dart';

import '../../admin/admin_common.dart' show t;
import '../org_v3.dart' show orgParseUtc;
import 'students_models.dart' show StudentRow, enrolFinal, enrolLabel, enrolPaused;

Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<dynamic> _list(dynamic v) => v is List ? v : const [];
String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
double? _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
bool _bool(dynamic v) => v == true;

/// [ar] or [en] by the app language; the other one when the chosen one is empty.
String _pick(String? ar, String? en) {
  final a = (ar ?? '').trim(), e = (en ?? '').trim();
  if (AppConfig.lang == 'ar') return a.isNotEmpty ? a : e;
  return e.isNotEmpty ? e : a;
}

// ═════════════════════════════════════════════════════════════════════════════
//  The file
// ═════════════════════════════════════════════════════════════════════════════

/// What the caller may see on the file (`can` of §4.2). `statusChange`, `ask` and `meeting` are always false in
/// phase 1.
class StudentCan {
  const StudentCan({
    this.academic = false,
    this.documents = false,
    this.kase = false,
    this.requests = false,
    this.complaints = false,
    this.advising = false,
    this.accessLog = false,
    this.statusView = false,
    this.statusChange = false,
    this.ask = false,
    this.meeting = false,
  });

  factory StudentCan.fromJson(dynamic v) {
    final m = _map(v);
    return StudentCan(
      academic: _bool(m['academic']),
      documents: _bool(m['documents']),
      kase: _bool(m['case']),
      requests: _bool(m['requests']),
      complaints: _bool(m['complaints']),
      advising: _bool(m['advising']),
      accessLog: _bool(m['access_log']),
      statusView: _bool(m['status_view']),
      statusChange: _bool(m['status_change']),
      ask: _bool(m['ask']),
      meeting: _bool(m['meeting']),
    );
  }

  final bool academic, documents, kase, requests, complaints, advising, accessLog, statusView, statusChange, ask, meeting;
}

/// One stop of the journey rail.
class JourneyNode {
  const JourneyNode({required this.key, required this.labelAr, required this.labelEn, required this.state, this.at});

  factory JourneyNode.fromJson(dynamic v) {
    final m = _map(v);
    return JourneyNode(
      key: _str(m['key']) ?? '',
      labelAr: _str(m['label_ar']) ?? '',
      labelEn: _str(m['label_en']) ?? '',
      state: journeyState(_str(m['state'])),
      at: orgParseUtc(m['at']),
    );
  }

  final String key, labelAr, labelEn;
  final AppRoadmapState state;
  final DateTime? at;

  String get label => _pick(labelAr, labelEn);

  AppRoadmapNode toRoadmapNode() => AppRoadmapNode(
        id: key,
        title: label,
        state: state,
        caption: at == null || state == AppRoadmapState.todo ? null : AppTime.date(at!.toUtc()),
      );
}

/// The journey as the rail draws it, told by the enrolment: a student who LEFT (withdrawn, dismissed, graduated …)
/// has no "in progress" stop and no "next" one — the stop they reached reads the final state (graduated: done,
/// otherwise stopped there, `warn`); a PAUSED student (suspended, postponed) keeps the stop but reads the pause and
/// has no "next" either. [next] is AppRoadmap's `next` (-1: none; null: the rail's own pick).
({List<AppRoadmapNode> nodes, int? next}) studentJourney(List<JourneyNode> journey, String enrolStatus) {
  final nodes = [for (final n in journey) n.toRoadmapNode()];
  final ended = enrolFinal.contains(enrolStatus), paused = enrolPaused.contains(enrolStatus);
  if (!ended && !paused) return (nodes: nodes, next: null);
  var at = nodes.indexWhere((n) => n.state == AppRoadmapState.current || n.state == AppRoadmapState.warn);
  // a graduate's last stop is the graduation itself when the server left nothing in progress
  if (at < 0 && enrolStatus == 'graduated' && nodes.isNotEmpty) at = nodes.lastIndexWhere((n) => n.state != AppRoadmapState.done);
  if (at >= 0) {
    final n = nodes[at];
    final state = !ended
        ? n.state
        : enrolStatus == 'graduated'
            ? AppRoadmapState.done
            : AppRoadmapState.warn;
    nodes[at] = AppRoadmapNode(id: n.id, title: n.title, state: state, caption: enrolLabel(enrolStatus));
  }
  return (nodes: nodes, next: -1);
}

/// `done | current | todo | warn` → the roadmap state (an unknown word reads as "to do").
AppRoadmapState journeyState(String? s) => switch (s) {
      'done' => AppRoadmapState.done,
      'current' => AppRoadmapState.current,
      'warn' => AppRoadmapState.warn,
      _ => AppRoadmapState.todo,
    };

/// The academic summary (`academic` of §4.2).
class StudentAcademic {
  const StudentAcademic({
    this.stage,
    this.cgpa,
    this.earnedCredits,
    this.attemptedCredits,
    this.legacyStanding,
    this.probations = 0,
    this.studySystem,
    this.advisorId,
    this.advisorName,
    this.graduatedAt,
  });

  factory StudentAcademic.fromJson(dynamic v) {
    final m = _map(v);
    final adv = _map(m['advisor']);
    return StudentAcademic(
      stage: _str(m['stage']),
      cgpa: _num(m['cgpa']),
      earnedCredits: _num(m['earned_credits']),
      attemptedCredits: _num(m['attempted_credits']),
      legacyStanding: _str(m['legacy_standing']),
      probations: _int(m['probations']) ?? 0,
      studySystem: _str(m['study_system']),
      advisorId: _int(adv['id']),
      advisorName: _str(adv['name']),
      graduatedAt: orgParseUtc(m['graduated_at']),
    );
  }

  final String? stage, legacyStanding, studySystem, advisorName;
  final double? cgpa, earnedCredits, attemptedCredits;
  final int probations;
  final int? advisorId;
  final DateTime? graduatedAt;
}

/// The admission / appointment case behind the student (`intake` of §4.2).
class FileIntake {
  const FileIntake({
    this.caseId,
    this.typeKey,
    this.typeLabelAr,
    this.typeLabelEn,
    this.status,
    this.label,
    this.conditional = false,
    this.dueAt,
    this.missingCount,
    this.activatedAt,
  });

  factory FileIntake.fromJson(dynamic v) {
    final m = _map(v);
    return FileIntake(
      caseId: _int(m['case_id']),
      typeKey: _str(m['type_key']),
      typeLabelAr: _str(m['type_label_ar']),
      typeLabelEn: _str(m['type_label_en']),
      status: _str(m['status']),
      label: _str(m['label']),
      conditional: _bool(m['conditional']),
      dueAt: orgParseUtc(m['due_at']),
      missingCount: _int(m['missing_count']),
      activatedAt: orgParseUtc(m['activated_at']),
    );
  }

  final int? caseId;
  final String? typeKey, typeLabelAr, typeLabelEn, status, label;
  final bool conditional;
  final DateTime? dueAt, activatedAt;
  final int? missingCount;

  String get typeLabel => _pick(typeLabelAr, typeLabelEn);
}

/// The next meeting held for this student (`open.next_meeting`).
class StudentMeeting {
  const StudentMeeting({required this.id, this.startsAt, this.mode, this.title});

  static StudentMeeting? fromJson(dynamic v) {
    final m = _map(v);
    final id = _int(m['id']);
    if (id == null) return null;
    return StudentMeeting(id: id, startsAt: orgParseUtc(m['starts_at']), mode: _str(m['mode']), title: _str(m['title']));
  }

  final int id;
  final DateTime? startsAt;
  final String? mode, title;
}

/// What is still open around the student. [complaints] is null without the complaints right (the line is hidden).
/// One open lifecycle request of the file (`open.lifecycle_requests[]`, newest first): [id] is the Governance work
/// item id (the request detail opens it). The labels are the server's in the app's language ('' on an older server).
class StudentOpenRequest {
  const StudentOpenRequest({required this.id, this.ref = '', this.request = '', this.label = '', this.status = '', this.statusLabel = '', this.stage = '', this.origin = '', this.createdAt});

  /// null when the entry has no id (nothing to open).
  static StudentOpenRequest? fromJson(dynamic v) {
    final m = _map(v);
    final id = _int(m['id']);
    if (id == null || id <= 0) return null;
    String pick(String k) => _pick(_str(m['${k}_ar']), _str(m['${k}_en']));

    return StudentOpenRequest(
      id: id,
      ref: _str(m['ref']) ?? '',
      request: _str(m['request']) ?? '',
      label: pick('label'),
      status: _str(m['status']) ?? '',
      statusLabel: pick('status_label'),
      stage: _str(m['stage']) ?? '',
      origin: _str(m['origin']) ?? '',
      createdAt: orgParseUtc(m['created_at']),
    );
  }

  final int id;
  final String ref, request, label, status, statusLabel, stage, origin;
  final DateTime? createdAt;
}

class StudentOpen {
  const StudentOpen({this.asks = 0, this.requests = 0, this.complaints, this.nextMeeting, this.lifecycleRequests = const []});

  factory StudentOpen.fromJson(dynamic v) {
    final m = _map(v);
    return StudentOpen(
      asks: _int(m['asks']) ?? 0,
      requests: _int(m['requests']) ?? 0,
      complaints: _int(m['complaints']),
      nextMeeting: StudentMeeting.fromJson(m['next_meeting']),
      lifecycleRequests: [
        for (final x in _list(m['lifecycle_requests'])) ?StudentOpenRequest.fromJson(x),
      ],
    );
  }

  final int asks, requests;
  final int? complaints;
  final StudentMeeting? nextMeeting;

  /// The open lifecycle requests, newest first (empty on an older server: only the [requests] count).
  final List<StudentOpenRequest> lifecycleRequests;
}

/// `GET …/students/{uid}/file`: the student's row ([row], parsed by students_models.dart) plus the file's own parts.
class StudentFile {
  const StudentFile({
    required this.row,
    this.email,
    this.phone,
    this.joinedAt,
    this.birthDate,
    this.gender,
    this.nationality,
    this.nationalityLabelAr,
    this.nationalityLabelEn,
    this.academic,
    this.intake,
    this.journey = const [],
    this.open = const StudentOpen(),
    this.can = const StudentCan(),
    this.logged = false,
  });

  factory StudentFile.fromJson(Map<String, dynamic> j) {
    final s = _map(j['student']);
    final intake = j['intake'] is Map ? j['intake'] : s['intake'];
    return StudentFile(
      row: StudentRow.fromJson(s),
      email: _str(s['email']),
      phone: _str(s['phone']),
      joinedAt: orgParseUtc(s['joined_at']),
      birthDate: orgParseUtc(s['birth_date']),
      gender: _str(s['gender']),
      nationality: _str(s['nationality']),
      nationalityLabelAr: _str(s['nationality_label_ar']),
      nationalityLabelEn: _str(s['nationality_label_en']),
      academic: j['academic'] is Map ? StudentAcademic.fromJson(j['academic']) : null,
      intake: intake is Map ? FileIntake.fromJson(intake) : null,
      journey: [for (final n in _list(j['journey'])) JourneyNode.fromJson(n)],
      open: StudentOpen.fromJson(j['open']),
      can: StudentCan.fromJson(j['can']),
      logged: _bool(j['logged']),
    );
  }

  final StudentRow row;

  /// null without the case type's `view` right (the line is hidden).
  final String? email, phone, gender, nationality;

  /// The nationality's name from the server (`nationality_label_ar` / `_en`); null on an older server.
  final String? nationalityLabelAr, nationalityLabelEn;

  /// The nationality in the app language: its name (the other language's when this one is missing), else the code.
  String? get nationalityText {
    if (nationality == null) return null;
    final ar = nationalityLabelAr, en = nationalityLabelEn;
    final pick = AppConfig.lang == 'ar' ? (ar ?? en) : (en ?? ar);
    return pick ?? nationality;
  }
  final DateTime? joinedAt, birthDate;
  final StudentAcademic? academic;
  final FileIntake? intake;
  final List<JourneyNode> journey;
  final StudentOpen open;
  final StudentCan can;
  final bool logged;

  int get userId => row.user.id;

  /// The name in the app language (the other one when it is empty).
  String get displayName => row.name.trim().isEmpty ? t('طالب', 'Student') : row.name.trim();

  /// The name in the other language, when it differs.
  String? get otherName {
    final other = (AppConfig.lang == 'ar' ? row.user.nameEn : row.user.name).trim();
    return other.isEmpty || other == displayName ? null : other;
  }

  /// "Computer Science · Year 2" (either part may be missing).
  String? get programLine {
    final program = row.program?.label;
    final parts = [if (program != null && program.isNotEmpty) program, if (row.level != null) studentLevelText(row.level!)];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  bool get hasMissing => row.hasMissing;
}

/// A level code as words: "1" → "Level 1" (the list, the file and the report say the same word); any other code is shown as sent.
String studentLevelText(String level) {
  final n = int.tryParse(level);
  if (n == null) return level;
  return t('المستوى $n', 'Level $n');
}

/// `m` / `f` as words; an unknown code as sent.
String genderText(String g) => switch (g) {
      'm' || 'male' => t('ذكر', 'Male'),
      'f' || 'female' => t('أنثى', 'Female'),
      _ => g,
    };

/// The study system of the academic summary.
String studySystemText(String s) => switch (s) {
      'credit_hours' => t('الساعات المعتمدة', 'Credit hours'),
      'traditional' => t('النظام التقليدي (السنوي)', 'Traditional (yearly)'),
      _ => s,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Tabs
// ═════════════════════════════════════════════════════════════════════════════

enum StudentFileTab { overview, timeline, academic, documents, requests, advising, accessLog }

/// The tabs [can] lets the caller see, in the file's order. Overview and Timeline need only `students:view` (the
/// file itself); every other tab hides without its right.
List<StudentFileTab> studentFileTabs(StudentCan can) => [
      StudentFileTab.overview,
      StudentFileTab.timeline,
      if (can.academic) StudentFileTab.academic,
      if (can.kase || can.documents) StudentFileTab.documents,
      if (can.requests || can.complaints) StudentFileTab.requests,
      if (can.advising) StudentFileTab.advising,
      if (can.accessLog) StudentFileTab.accessLog,
    ];

String studentFileTabText(StudentFileTab tab) => switch (tab) {
      StudentFileTab.overview => t('نظرة عامة', 'Overview'),
      StudentFileTab.timeline => t('السجل الزمني', 'Timeline'),
      StudentFileTab.academic => t('الأكاديمي', 'Academic'),
      StudentFileTab.documents => t('الملف والمستندات', 'File & documents'),
      StudentFileTab.requests => t('الطلبات والشكاوى', 'Requests & complaints'),
      StudentFileTab.advising => t('الإرشاد', 'Advising'),
      StudentFileTab.accessLog => t('سجل الاطلاع', 'Access log'),
    };

IconData studentFileTabIcon(StudentFileTab tab) => switch (tab) {
      StudentFileTab.overview => Icons.dashboard_outlined,
      StudentFileTab.timeline => Icons.timeline_rounded,
      StudentFileTab.academic => Icons.school_outlined,
      StudentFileTab.documents => Icons.folder_open_rounded,
      StudentFileTab.requests => Icons.forum_outlined,
      StudentFileTab.advising => Icons.support_agent_rounded,
      StudentFileTab.accessLog => Icons.visibility_outlined,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Timeline
// ═════════════════════════════════════════════════════════════════════════════

/// Every kind of the timeline (`TIMELINE_KINDS`).
const kTimelineKinds = <String>[
  'status', 'intake', 'documents', 'level', 'results', 'registration', 'requests', 'meetings', 'complaints', 'asks',
  'record',
];

/// The kinds offered as filter chips (`asks` is also where the file's "asks waiting" line lands).
const kTimelineFilterKinds = <String>[
  'status', 'asks', 'requests', 'results', 'registration', 'level', 'meetings', 'complaints', 'intake', 'documents', 'record',
];

/// One line of the student's history (§3.4). Read only: nothing on it can be edited.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.kind,
    this.at,
    this.actorId,
    this.actorName,
    this.titleAr,
    this.titleEn,
    this.detailAr,
    this.detailEn,
    this.reason,
    this.decisionNo,
    this.sourceType,
    this.sourceId,
    this.canUndo = false,
    this.undone = false,
  });

  factory TimelineItem.fromJson(dynamic v) {
    final m = _map(v);
    final actor = _map(m['actor']);
    final src = _map(m['source']);
    return TimelineItem(
      id: _str(m['id']) ?? '',
      kind: _str(m['kind']) ?? 'record',
      at: orgParseUtc(m['at']),
      actorId: _int(actor['id']),
      actorName: _str(actor['name']),
      titleAr: _str(m['title_ar']),
      titleEn: _str(m['title_en']),
      detailAr: _str(m['detail_ar']),
      detailEn: _str(m['detail_en']),
      reason: _str(m['reason']),
      decisionNo: _str(m['decision_no']),
      sourceType: _str(src['type']),
      sourceId: _int(src['id']),
      canUndo: _bool(m['can_undo']),
      undone: _bool(m['undone']),
    );
  }

  final String id, kind;
  final DateTime? at;
  final int? actorId;

  /// null = the system did it.
  final String? actorName;
  final String? titleAr, titleEn, detailAr, detailEn, reason, decisionNo, sourceType;
  final int? sourceId;
  final bool canUndo, undone;

  String get title {
    final s = _pick(titleAr, titleEn);
    return s.isEmpty ? timelineKindText(kind) : s;
  }

  String? get detail {
    final s = _pick(detailAr, detailEn);
    return s.isEmpty ? null : s;
  }

  String get actor => actorName ?? t('النظام', 'System');
}

/// One page of `GET …/timeline`. [nextBefore] is sent back as is for the next page (null = the end).
class TimelinePage {
  const TimelinePage({this.items = const [], this.nextBefore, this.hiddenKinds = const []});

  factory TimelinePage.fromJson(dynamic v) {
    final m = _map(v);
    return TimelinePage(
      items: [for (final i in _list(m['items'])) TimelineItem.fromJson(i)],
      nextBefore: _str(m['next_before']),
      hiddenKinds: [for (final k in _list(m['hidden_kinds'])) ?_str(k)],
    );
  }

  final List<TimelineItem> items;
  final String? nextBefore;
  final List<String> hiddenKinds;
}

/// [prev] followed by [next] without the items it already holds (a page boundary on a tie repeats nothing).
List<TimelineItem> mergeTimeline(List<TimelineItem> prev, List<TimelineItem> next) {
  final seen = {for (final i in prev) i.id};
  return [...prev, for (final i in next) if (seen.add(i.id)) i];
}

/// The words of a timeline kind.
String timelineKindText(String kind) => switch (kind) {
      'status' => t('الحالة', 'Status'),
      'intake' => t('الالتحاق', 'Admission'),
      'documents' => t('المستندات', 'Documents'),
      'level' => t('الفرقة', 'Level'),
      'results' => t('النتائج', 'Results'),
      'registration' => t('التسجيل', 'Registration'),
      'requests' => t('الطلبات', 'Requests'),
      'meetings' => t('الاجتماعات', 'Meetings'),
      'complaints' => t('الشكاوى', 'Complaints'),
      'asks' => t('طلبات من الطالب', 'Asks'),
      'record' => t('تعديلات السجل', 'Record changes'),
      _ => kind,
    };

IconData timelineIcon(String kind) => switch (kind) {
      'status' => Icons.flag_outlined,
      'intake' => Icons.how_to_reg_rounded,
      'documents' => Icons.description_outlined,
      'level' => Icons.trending_up_rounded,
      'results' => Icons.grading_rounded,
      'registration' => Icons.playlist_add_check_rounded,
      'requests' => Icons.assignment_outlined,
      'meetings' => Icons.event_outlined,
      'complaints' => Icons.report_outlined,
      'asks' => Icons.help_outline_rounded,
      'record' => Icons.edit_note_rounded,
      _ => Icons.circle_outlined,
    };

AppTone timelineTone(String kind) => switch (kind) {
      'status' => AppTone.brand,
      'intake' || 'level' => AppTone.success,
      'results' => AppTone.gold,
      'complaints' => AppTone.warning,
      'meetings' || 'registration' || 'requests' || 'asks' => AppTone.info,
      _ => AppTone.neutral,
    };

/// The items of one day.
class TimelineDay {
  const TimelineDay(this.day, this.items);

  /// Midnight of the day in the platform / organization timezone; null = items without a time.
  final DateTime? day;
  final List<TimelineItem> items;
}

/// One academic year (September to August) of the timeline, its days newest first.
class TimelineGroup {
  const TimelineGroup(this.startYear, this.days);

  /// The year the academic year starts in (2026 = 2026/2027); null = items without a time.
  final int? startYear;
  final List<TimelineDay> days;

  int get count => days.fold(0, (n, d) => n + d.items.length);

  String get label => startYear == null
      ? t('بلا تاريخ', 'No date')
      : t('العام الدراسي $startYear/${startYear! + 1}', 'Academic year $startYear/${startYear! + 1}');
}

/// The academic year an instant falls in (September starts a new one).
int academicYearOf(DateTime wall) => wall.month >= 9 ? wall.year : wall.year - 1;

/// [items] (newest first, as the server sends them) in academic-year blocks with their days inside. [wallOf] turns
/// an instant into its wall clock (default: the platform / organization timezone). Items without a time come last.
List<TimelineGroup> groupTimelineByYear(List<TimelineItem> items, {DateTime Function(DateTime utc)? wallOf}) {
  final wall = wallOf ?? (DateTime utc) => AppTime.toZone(utc.toUtc());
  final groups = <TimelineGroup>[];
  final undated = <TimelineItem>[];
  for (final i in items) {
    if (i.at == null) {
      undated.add(i);
      continue;
    }
    final w = wall(i.at!);
    final day = DateTime(w.year, w.month, w.day);
    final year = academicYearOf(w);
    final g = groups.isNotEmpty && groups.last.startYear == year ? groups.last : null;
    if (g == null) {
      groups.add(TimelineGroup(year, [
        TimelineDay(day, [i])
      ]));
      continue;
    }
    final last = g.days.last;
    if (last.day == day) {
      last.items.add(i);
    } else {
      g.days.add(TimelineDay(day, [i]));
    }
  }
  if (undated.isNotEmpty) {
    groups.add(TimelineGroup(null, [TimelineDay(null, undated)]));
  }
  return groups;
}

