// The app's hand-written parsers against REAL server responses (test/fixtures/payloads/, written by
// ../back/tests/contract/dump_payloads.py from the backend's own e2e harnesses — regenerate after a payload change).
//
// The path contract test (api_paths_test.dart) proves every called route exists; this proves the parsers read what
// those routes return: every key a parser reads must be IN the real payload (a field the server sends under another
// name fails here instead of silently defaulting), and every parsed value must equal the JSON — counts, nested
// lists, UTC instants, nullables. Each parser also runs on an "older server" variant (the new blocks removed) to
// confirm the screens hide them instead of breaking.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/live/live_events_client.dart' show SseParser;
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
import 'package:flutter_education_app/features/org/advising/adv_appt_models.dart' show AdvMemberHub;
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/parent/parent_overview.dart';
import 'package:flutter_education_app/features/shared/calendar/calendar_models.dart' show CalEvent;
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/shared/rag/rag_admin_console.dart';
import 'package:flutter_education_app/features/shared/rag/rag_chat.dart';
import 'package:flutter_education_app/features/shared/rag/rag_qa_admin.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/payloads';

Map<String, dynamic> fixture(String name) {
  final f = File('$_dir/$name.json');
  expect(f.existsSync(), isTrue, reason: '$name.json missing: run ../back/tests/contract/dump_payloads.py');
  return Map<String, dynamic>.from(jsonDecode(f.readAsStringSync())['payload'] as Map);
}

Map<String, dynamic> m(dynamic v) => Map<String, dynamic>.from(v as Map);
List<Map<String, dynamic>> ms(dynamic v) => [for (final x in v as List) m(x)];

/// The parser reads these keys: the real payload must carry every one of them.
void hasKeys(Map<String, dynamic> j, Iterable<String> keys, String where) {
  for (final k in keys) {
    expect(j.containsKey(k), isTrue, reason: '$where: the server sends no "$k" (renamed or dropped?) — keys: ${j.keys}');
  }
}

/// The server's naive-UTC (or zoned) ISO time as the UTC instant it means.
DateTime? utc(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final plainDate = RegExp(r'^\d{4}-\d\d-\d\d$').hasMatch(s); // a date column (`start_date`) has no time of day
  return DateTime.parse(zoned ? s : (plainDate ? '${s}T00:00:00Z' : '${s}Z')).toUtc();
}

int? asIntOrNull(dynamic v) => v == null ? null : (v as num).toInt();
double? asDoubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();

/// One calendar row (`today[]`, `upcoming[]`, `teaching_today[]`) against its JSON.
void sameEvent(CalEvent e, Map<String, dynamic> j) {
  hasKeys(j, const ['id', 'source', 'title', 'subtitle', 'starts_at', 'ends_at', 'org_id', 'course_id', 'meeting_id',
      'location', 'mode', 'my_status', 'kind', 'color'], 'calendar event');
  expect(e.id, '${j['id']}');
  expect(e.source, j['source']);
  expect(e.title, j['title']);
  expect(e.subtitle, j['subtitle']);
  expect(e.start, utc(j['starts_at']));
  expect(e.end, utc(j['ends_at']));
  expect(e.orgId, j['org_id']);
  expect(e.courseId, j['course_id']);
  expect(e.meetingId, j['meeting_id']);
  expect(e.location, j['location']);
  expect(e.mode, j['mode']);
  expect(e.myStatus, j['my_status']);
  expect(e.kind, j['kind']);
  expect(e.color, j['color']);
}

void sameEvents(List<CalEvent> parsed, dynamic rows) {
  final js = ms(rows)..sort((a, b) => utc(a['starts_at'])!.compareTo(utc(b['starts_at'])!));
  expect(parsed.map((e) => e.id).toList(), js.map((j) => '${j['id']}').toList());
  for (var i = 0; i < js.length; i++) {
    sameEvent(parsed[i], js[i]);
  }
}

void main() {
  if (!Directory(_dir).existsSync()) {
    test('payload shapes', () {}, skip: '$_dir missing: run ../back/tests/contract/dump_payloads.py');
    return;
  }
  setUp(() => AppConfig.lang = 'en');

  // ── GET /api/v1/me/home ────────────────────────────────────────────────────
  group('GET /me/home → MeHome', () {
    void common(Map<String, dynamic> j, MeHome h) {
      hasKeys(j, const ['now', 'today_date', 'timezone', 'role', 'orgs_enabled', 'today', 'upcoming', 'attention',
          'inbox_preview', 'inbox_counts', 'notifications_unread', 'org_overview'], 'me/home');
      expect(h.legacy, isFalse);
      expect(h.now, utc(j['now']));
      expect(h.todayDate, j['today_date']);
      expect(h.timezone, j['timezone']);
      expect(h.role, j['role']);
      expect(h.orgsEnabled, j['orgs_enabled']);
      sameEvents(h.today, j['today']);
      sameEvents(h.upcoming, j['upcoming']);
      expect(h.attention, j['attention']);
      hasKeys(m(j['attention']), const ['counts', 'total', 'items'], 'me/home attention');
      expect(h.attentionTotal, j['attention']['total']);
      expect(h.attentionItems, j['attention']['items']);
      expect(h.inboxPreview, j['inbox_preview']);
      expect(h.inboxCounts, m(j['inbox_counts']));
      hasKeys(m(j['inbox_counts']), const ['todo', 'overdue', 'due_soon'], 'me/home inbox_counts');
      expect(h.notificationsUnread, j['notifications_unread']);
      if (j['org_overview'] == null) {
        expect(h.orgOverview, isNull);
        expect(h.orgEntries, isEmpty);
      } else {
        expect(h.orgOverview, j['org_overview']);
        final items = ms(j['org_overview']['items']);
        expect(h.orgEntries.length, items.length);
        for (final it in items) {
          final id = it['organization']['id'] as int;
          expect(h.orgEntry(id), it, reason: 'orgEntry($id) must find the overview row by organization.id');
          expect(h.todayOf(id).length, ms(j['today']).where((e) => e['org_id'] == id).length);
        }
      }
    }

    test('student with an organization membership', () {
      final j = fixture('me_home_student');
      final h = MeHome.fromJson(j);
      common(j, h);
      expect(h.today, isNotEmpty, reason: 'the harness seeds a session today');
      expect(h.teacher, isNull);
      final cp = ms(j['courses_progress']);
      expect(h.coursesProgress.length, cp.length);
      expect(cp, isNotEmpty);
      for (var i = 0; i < cp.length; i++) {
        final c = h.coursesProgress[i], r = cp[i];
        hasKeys(r, const ['course_id', 'name_ar', 'name_en', 'image_url', 'progress', 'plan', 'expires_at', 'next_lecture'],
            'courses_progress');
        expect(c.courseId, r['course_id']);
        expect(c.nameAr, r['name_ar']);
        expect(c.nameEn, r['name_en']);
        expect(c.imageUrl, r['image_url']);
        expect(c.progress, (r['progress'] as num).toDouble());
        expect(c.plan, r['plan']);
        expect(c.expiresAt, utc(r['expires_at']));
        if (r['next_lecture'] == null) {
          expect(c.nextLecture, isNull);
        } else {
          final n = m(r['next_lecture']);
          hasKeys(n, const ['id', 'name', 'scheduled_at', 'duration_minutes', 'track'], 'next_lecture');
          expect(c.nextLecture!.id, n['id']);
          expect(c.nextLecture!.name, n['name']);
          expect(c.nextLecture!.scheduledAt, utc(n['scheduled_at']));
          expect(c.nextLecture!.durationMinutes, n['duration_minutes']);
          expect(c.nextLecture!.track, n['track']);
        }
      }
    });

    // academic advising (D-289 Phase 9): the membership's `advising` block feeds the "My academic advisor" card;
    // an older server (or a student without an advisor) leaves the key out and the card asks the member status
    test('student membership: the advising block of the overview item', () {
      final j = fixture('me_home_student');
      final item = ms(j['org_overview']['items']).first;
      hasKeys(m(item['advising']), const ['hub', 'unread', 'appointments_today', 'surveys_pending'], 'org_overview advising');
      final h = MeHome.fromJson(j);
      final hub = AdvMemberHub.fromOverview(h.orgEntry(item['organization']['id'] as int)!['advising'])!;
      final b = m(item['advising']);
      expect(hub.hub, b['hub']);
      expect(hub.counts.threadsUnread, b['unread']);
      expect(hub.counts.appointmentsToday, b['appointments_today']);
      expect(hub.counts.surveysPending, b['surveys_pending']);
      expect(hub.counts.total, (b['unread'] as int) + (b['appointments_today'] as int) + (b['surveys_pending'] as int));
      // older server: the key is absent
      final old = Map<String, dynamic>.of(item)..remove('advising');
      expect(AdvMemberHub.fromOverview(old['advising']), isNull);
    });

    test('student without a membership: org_overview null, no courses', () {
      final j = fixture('me_home_student_no_org');
      final h = MeHome.fromJson(j);
      common(j, h);
      expect(h.orgOverview, isNull);
      expect(h.coursesProgress, isEmpty);
      expect(h.studyPrompt, j['study_prompt'] == true, reason: 'the study card flag (D-793)');
    });

    test('teacher block', () {
      final j = fixture('me_home_teacher');
      hasKeys(j, const ['teaching_today', 'pending', 'teaching_courses', 'earnings'], 'me/home teacher');
      final h = MeHome.fromJson(j);
      common(j, h);
      final t = h.teacher!;
      sameEvents(t.teachingToday, j['teaching_today']);
      expect(t.teachingToday, isNotEmpty);
      expect(t.pending, m(j['pending']));
      hasKeys(m(j['pending']), const ['attendance_missing', 'materials_missing', 'grading', 'enrollment_requests'], 'pending');
      expect(t.teachingCourses, j['teaching_courses']);
      hasKeys(m(j['earnings']), const ['month', 'pending_payout'], 'earnings');
      expect(t.earningsMonth, (j['earnings']['month'] as num).toDouble());
      expect(t.pendingPayout, (j['earnings']['pending_payout'] as num).toDouble());
      expect(h.coursesProgress, isEmpty);
    });

    test('older server: no org_overview / courses / teacher blocks → hidden', () {
      final j = fixture('me_home_teacher')
        ..remove('org_overview')
        ..remove('orgs_enabled')
        ..remove('teaching_today')
        ..remove('pending')
        ..remove('earnings')
        ..remove('teaching_courses')
        ..remove('courses_progress');
      final h = MeHome.fromJson(j);
      expect(h.orgOverview, isNull);
      expect(h.teacher, isNull);
      expect(h.coursesProgress, isEmpty);
      expect(h.orgsEnabled, isTrue);
      expect(h.today.length, (j['today'] as List).length);
    });
  });

  // ── GET /api/v1/admin/overview ─────────────────────────────────────────────
  group('GET /admin/overview → AdminHomeData', () {
    test('every block read from the real payload', () {
      final j = fixture('admin_overview');
      hasKeys(j, const ['students', 'teachers', 'courses', 'published_courses', 'active_enrollments', 'pending_transfers',
          'pending_subscriptions', 'active_subscriptions', 'subscription_required', 'income_by_currency',
          'collected_by_currency', 'organizations', 'series', 'alerts', 'realtime'], 'admin/overview');
      final d = AdminHomeData.fromOverview(j);
      expect(d.students, j['students']);
      expect(d.teachers, j['teachers']);
      expect(d.courses, j['courses']);
      expect(d.publishedCourses, j['published_courses']);
      expect(d.activeEnrollments, j['active_enrollments']);
      expect(d.pendingTransfers, j['pending_transfers']);
      expect(d.pendingSubscriptions, j['pending_subscriptions']);
      expect(d.activeSubscriptions, j['active_subscriptions']);
      expect(d.subscriptionRequired, j['subscription_required']);
      Map<String, double> money(dynamic v) => {for (final e in m(v).entries) e.key: (e.value as num).toDouble()};
      expect(d.incomeByCurrency, money(j['income_by_currency']));
      expect(d.collectedByCurrency, money(j['collected_by_currency']));
      expect(d.collectedByCurrency, isNotEmpty);

      final o = m(j['organizations']);
      hasKeys(o, const ['total', 'active', 'pending_approval', 'by_type'], 'organizations');
      expect(d.hasOrganizations, isTrue);
      expect(d.orgTotal, o['total']);
      expect(d.orgActive, o['active']);
      expect(d.orgPendingApproval, o['pending_approval']);
      expect(d.orgByType, m(o['by_type']));

      final series = ms(j['series']);
      expect(series.length, 30);
      expect(d.series.length, 30);
      for (var i = 0; i < 30; i++) {
        final p = d.series[i], r = series[i];
        hasKeys(r, const ['date', 'signups', 'enrollments', 'revenue', 'live_sessions', 'complaints'], 'series row');
        expect(p.date, r['date']);
        expect(p.signups, r['signups']);
        expect(p.enrollments, r['enrollments']);
        expect(p.revenue, money(r['revenue']));
        expect(p.liveSessions, r['live_sessions']);
        expect(p.complaints, r['complaints']);
      }
      expect(d.signups30, series.fold<int>(0, (s, r) => s + (r['signups'] as int)));
      expect(d.hasActivity, isTrue);

      final alerts = ms(j['alerts']);
      expect(alerts, isNotEmpty);
      expect(d.hasAlerts, isTrue);
      expect(d.alerts.length, alerts.length);
      for (var i = 0; i < alerts.length; i++) {
        final a = d.alerts[i], r = alerts[i];
        hasKeys(r, const ['key', 'severity', 'count', 'deep_link'], 'alert');
        expect(a.key, r['key']);
        expect(a.severity, r['severity']);
        expect(a.count, r['count']);
        expect(a.deepLink, r['deep_link']);
        expect(a.byKind, r.containsKey('by_kind') ? m(r['by_kind']) : isEmpty);
        expect(a.days, r['days']);
      }
      expect(d.jobsFailed24h, alerts.firstWhere((r) => r['key'] == 'jobs_failed_24h')['count']);

      expect(d.hasRealtime, isTrue);
      hasKeys(m(j['realtime']), const ['events_24h'], 'realtime');
      expect(d.eventsLast24h, j['realtime']['events_24h']);
    });

    test('older server: organizations / series / alerts / realtime missing → hidden, legacy figures kept', () {
      final j = fixture('admin_overview');
      final full = AdminHomeData.fromOverview(j);
      for (final k in ['organizations', 'series', 'alerts', 'realtime']) {
        j.remove(k);
      }
      final d = AdminHomeData.fromOverview(j);
      expect(d.hasOrganizations, isFalse);
      expect(d.hasSeries, isFalse);
      expect(d.hasAlerts, isFalse);
      expect(d.hasRealtime, isFalse);
      expect(d.eventsLast24h, isNull);
      expect(d.students, full.students);
      expect(d.collectedByCurrency, full.collectedByCurrency);
      expect(d.queueTotal(0), d.pendingSubscriptions + d.pendingTransfers);
    });
  });

  // ── GET /api/v1/rag/admin/monitoring/summary ───────────────────────────────
  group('GET /rag/admin/monitoring/summary → AdminAssistantHealth', () {
    test('real payload', () {
      final j = fixture('rag_monitoring_summary');
      hasKeys(j, const ['days', 'questions', 'no_answer_rate', 'cache_hit_rate', 'latency_ms', 'by_day'], 'monitoring/summary');
      final h = AdminAssistantHealth.fromJson(j);
      expect(h.days, j['days']);
      expect(h.questions, j['questions']);
      expect(h.questions, greaterThan(0));
      expect(h.noAnswerRate, asDoubleOrNull(j['no_answer_rate']));
      expect(h.cacheHitRate, asDoubleOrNull(j['cache_hit_rate']));
      hasKeys(m(j['latency_ms']), const ['p50'], 'monitoring/summary latency_ms');
      expect(h.p50Ms, asIntOrNull(j['latency_ms']['p50']));
      final days = ms(j['by_day']);
      expect(days.length, j['days']);
      for (final r in days) {
        hasKeys(r, const ['day', 'questions'], 'monitoring/summary by_day');
      }
      expect(h.daily, [for (final r in days) r['questions']]);
    });

    test('older payload without latency / by_day → dashes, no spark', () {
      final j = fixture('rag_monitoring_summary')
        ..remove('latency_ms')
        ..remove('by_day')
        ..remove('cache_hit_rate');
      final h = AdminAssistantHealth.fromJson(j);
      expect(h.p50Ms, isNull);
      expect(h.p50Text, '—');
      expect(h.cacheHitRate, isNull);
      expect(h.daily, isEmpty);
    });
  });

  // ── GET /api/v1/org/orgs/{id}/dashboard ────────────────────────────────────
  group('GET /org/orgs/{id}/dashboard → OrgHomeData', () {
    test('real payload', () {
      final j = fixture('org_dashboard');
      hasKeys(j, const ['organization', 'my_role', 'kpis', 'members', 'pending_total', 'attention', 'attention_total',
          'series', 'departments', 'programs', 'recent_activity', 'generated_at'], 'org dashboard');
      final d = OrgHomeData.fromJson(j)!;
      expect(d.organization, j['organization']);
      expect(d.myRole, j['my_role']);
      expect(d.kpis, m(j['kpis']));
      final mem = m(j['members']);
      hasKeys(mem, const ['students', 'teachers', 'staff', 'pending_join'], 'members');
      expect(d.members!.students, mem['students']);
      expect(d.members!.teachers, mem['teachers']);
      expect(d.members!.staff, mem['staff']);
      expect(d.members!.pendingJoin, mem['pending_join']);
      expect(d.figures, (mem['students'], mem['teachers'], mem['staff'], mem['pending_join']));
      expect(d.pendingTotal, j['pending_total']);
      final att = ms(j['attention']);
      expect(att, isNotEmpty);
      expect(d.attention.length, att.length);
      for (var i = 0; i < att.length; i++) {
        hasKeys(att[i], const ['key', 'count', 'severity'], 'attention');
        expect(d.attention[i].key, att[i]['key']);
        expect(d.attention[i].count, att[i]['count']);
        expect(d.attention[i].severity, att[i]['severity']);
        expect(orgAttentionText(d.attention[i]), isNotNull, reason: 'attention key ${att[i]['key']} has no text');
      }
      final series = ms(j['series']);
      expect(series.length, 30);
      expect(d.series!.length, 30);
      for (var i = 0; i < 30; i++) {
        expect(d.series![i].date, series[i]['date']);
        expect(d.series![i].values, {for (final e in series[i].entries) if (e.key != 'date') e.key: e.value});
      }
      for (final k in OrgHomeData.trendKeys) {
        expect(series.first.containsKey(k), isTrue, reason: 'trend key $k is not in the series');
        final daily = [for (final r in series) r[k] as int];
        expect(d.trend(k)!.value, daily.sublist(23).fold<int>(0, (a, b) => a + b));
        expect(d.trend(k)!.spark.length, 30);
      }
      expect(d.departments, j['departments']);
      expect(d.programs, j['programs']);
      expect(d.recentActivity, j['recent_activity']);
      expect(d.recentActivity, isNotEmpty);
      expect(d.generatedAt, utc(j['generated_at']));
      expect(d.generatedAt!.isUtc, isTrue);
    });

    test('older server: no members / series / pending_total → kpis figures, no trends', () {
      final j = fixture('org_dashboard')
        ..remove('members')
        ..remove('series')
        ..remove('pending_total');
      final d = OrgHomeData.fromJson(j)!;
      expect(d.members, isNull);
      expect(d.hasTrends, isFalse);
      expect(d.trends, isEmpty);
      expect(d.pendingTotal, j['attention_total']);
      expect(d.figures, (j['kpis']['students'], j['kpis']['teachers'], j['kpis']['staff'], null));
    });
  });

  // ── GET /api/v1/parent/overview ────────────────────────────────────────────
  group('GET /parent/overview → ParentOverviewData', () {
    test('real payload', () {
      final j = fixture('parent_overview');
      hasKeys(j, const ['now', 'today_date', 'timezone', 'children', 'alerts_total', 'requests', 'link_config'], 'parent/overview');
      final d = ParentOverviewData.fromJson(j);
      expect(d.now, utc(j['now']));
      expect(d.todayDate, j['today_date']);
      expect(d.timezone, j['timezone']);
      expect(d.alertsTotal, j['alerts_total']);
      expect(d.requests, j['requests']);
      expect(d.linkConfig, j['link_config']);
      final kids = ms(j['children']);
      expect(kids.length, 2);
      expect(d.children.length, kids.length);
      for (var i = 0; i < kids.length; i++) {
        final c = d.children[i], r = kids[i];
        hasKeys(r, const ['child', 'today_sessions', 'attendance_pct_30d', 'latest_marks', 'open_alerts', 'next_exam', 'courses'],
            'parent child');
        final ch = m(r['child']);
        hasKeys(ch, const ['id', 'name', 'image_url', 'is_active', 'linked_at'], 'parent child.child');
        expect(c.id, ch['id']);
        expect(c.name, ch['name']);
        expect(c.imageUrl, ch['image_url'] ?? '');
        expect(c.isActive, ch['is_active']);
        expect(c.linkedAt, utc(ch['linked_at']));
        expect(c.child, ch);
        expect(c.attendancePct30d, r['attendance_pct_30d']);
        expect(c.openAlerts, r['open_alerts']);
        expect(c.courses, r['courses']);
        final sess = ms(r['today_sessions'])..sort((a, b) => utc(a['starts_at'])!.compareTo(utc(b['starts_at'])!));
        expect(c.todaySessions.length, sess.length);
        for (var k = 0; k < sess.length; k++) {
          final e = c.todaySessions[k], s = sess[k];
          hasKeys(s, const ['id', 'source', 'title', 'subtitle', 'starts_at', 'ends_at', 'course_id', 'kind', 'mode', 'location'],
              'parent today_sessions');
          expect(e.id, '${s['id']}', reason: 'a calendar row id is a string ("session:3")');
          expect(e.source, s['source']);
          expect(e.title, s['title']);
          expect(e.subtitle, s['subtitle'] ?? '');
          expect(e.startsAt, utc(s['starts_at']));
          expect(e.endsAt, utc(s['ends_at']));
          expect(e.courseId, s['course_id']);
          expect(e.kind, s['kind'] ?? '');
          expect(e.mode, s['mode'] ?? '');
          expect(e.location, s['location'] ?? '');
        }
        final marks = ms(r['latest_marks']);
        expect(c.latestMarks.length, marks.length);
        for (var k = 0; k < marks.length; k++) {
          final x = c.latestMarks[k], s = marks[k];
          hasKeys(s, const ['exam_id', 'exam', 'course_id', 'course_ar', 'course_en', 'percentage', 'passed', 'submitted_at'],
              'latest_marks');
          expect(x.examId, s['exam_id']);
          expect(x.exam, s['exam']);
          expect(x.courseId, s['course_id']);
          expect(x.courseAr, s['course_ar']);
          expect(x.courseEn, s['course_en']);
          expect(x.percentage, asDoubleOrNull(s['percentage']));
          expect(x.passed, s['passed']);
          expect(x.submittedAt, utc(s['submitted_at']));
        }
        if (r['next_exam'] == null) {
          expect(c.nextExam, isNull);
        } else {
          final n = m(r['next_exam']);
          hasKeys(n, const ['id', 'name', 'course_id', 'starts_at', 'ends_at', 'source'], 'next_exam');
          expect(c.nextExam!.id, n['id']);
          expect(c.nextExam!.name, n['name']);
          expect(c.nextExam!.courseId, n['course_id']);
          expect(c.nextExam!.startsAt, utc(n['starts_at']));
          expect(c.nextExam!.endsAt, utc(n['ends_at']));
          expect(c.nextExam!.source, n['source']);
        }
      }
      expect(d.children.first.todaySessions, isNotEmpty);
      expect(d.children.first.latestMarks, isNotEmpty);
      expect(d.children.first.nextExam, isNotNull);
      expect(d.children.last.attendancePct30d, isNull);
      expect(d.sessionsToday, kids.fold<int>(0, (n, r) => n + (r['today_sessions'] as List).length));
      // D-305: the pulse ("how is my child doing")
      for (var i = 0; i < kids.length; i++) {
        final r = m(m(kids[i])['pulse']), p = d.children[i].pulse!;
        hasKeys(r, const ['status', 'week', 'missed_sessions', 'attendance_trend', 'grades', 'subjects', 'upcoming', 'roadmap',
            'insights', 'teachers'], 'pulse');
        expect(p.status.wire, r['status']);
        final w = m(r['week']);
        hasKeys(w, const ['scheduled', 'attended', 'missed', 'rate', 'homework_due', 'homework_missing', 'homework_due_soon',
            'active_days', 'last_active_days'], 'pulse.week');
        expect((p.week.scheduled, p.week.attended, p.week.missed, p.week.rate), (w['scheduled'], w['attended'], w['missed'], w['rate']));
        expect((p.week.homeworkMissing, p.week.activeDays, p.week.lastActiveDays), (w['homework_missing'], w['active_days'], w['last_active_days']));
        expect(p.attendanceTrend, [for (final t in ms(r['attendance_trend'])) t['rate']]);
        for (final x in ms(r['missed_sessions'])) {
          hasKeys(x, const ['session', 'course_id', 'course_ar', 'course_en', 'at'], 'pulse.missed_sessions');
        }
        expect(p.missedSessions.length, (r['missed_sessions'] as List).length);
        if (r['grades'] != null) {
          final g = m(r['grades']);
          hasKeys(g, const ['avg', 'prev_avg', 'class_avg', 'mine_vs_class', 'count', 'failed', 'trend'], 'pulse.grades');
          expect((p.grades!.avg, p.grades!.count, p.grades!.failed), (asDoubleOrNull(g['avg']), g['count'], g['failed']));
          expect(p.grades!.trend, [for (final t in ms(g['trend'])) asDoubleOrNull(t['avg'])]);
        }
        final subj = ms(r['subjects']);
        expect(p.subjects.length, subj.length);
        for (var k = 0; k < subj.length; k++) {
          hasKeys(subj[k], const ['course_id', 'name_ar', 'name_en', 'progress', 'avg', 'class_avg', 'missed', 'weak_open', 'tone',
              'teacher'], 'pulse.subjects');
          expect((p.subjects[k].courseId, p.subjects[k].tone, p.subjects[k].teacher?.id),
              (subj[k]['course_id'], subj[k]['tone'], (subj[k]['teacher'] as Map?)?['id']));
        }
        expect(p.upcoming.length, (r['upcoming'] as List).length);
        for (final t in ms(r['teachers'])) {
          hasKeys(t, const ['id', 'name', 'image_url', 'course_id', 'course_ar', 'course_en'], 'pulse.teachers');
        }
        expect(p.teachers.length, (r['teachers'] as List).length);
        for (final x in ms(r['insights'])) {
          hasKeys(x, const ['code', 'level', 'params', 'action'], 'pulse.insights');
        }
        expect(p.insights.length, (r['insights'] as List).length);
      }
      expect(d.children.first.pulse!.subjects, isNotEmpty);
      expect(d.children.first.pulse!.week.scheduled, greaterThan(0));
    });

    test('older payload: a child row with only `child` → empty blocks', () {
      final j = fixture('parent_overview');
      j['children'] = [for (final r in ms(j['children'])) {'child': r['child']}];
      j.remove('link_config');
      final d = ParentOverviewData.fromJson(j);
      expect(d.children.length, 2);
      expect(d.children.first.todaySessions, isEmpty);
      expect(d.children.first.nextExam, isNull);
      expect(d.children.first.attendancePct30d, isNull);
      expect(d.linkConfig, isEmpty);
      expect(d.children.first.pulse, isNull, reason: 'an older server sends no pulse');
    });
  });

  // ── RAG: conversations + messages ──────────────────────────────────────────
  group('RAG conversations → RagConversation / RagAnswer', () {
    test('GET /rag/conversations', () {
      final j = fixture('rag_conversations');
      hasKeys(j, const ['items', 'retention_days'], 'rag/conversations');
      final r = EngineResult.ok(j);
      expect(RagApi.retentionDays(r), j['retention_days']);
      final items = ms(j['items']);
      expect(items, isNotEmpty);
      final parsed = RagApi.conversationItems(r);
      expect(parsed.length, items.length);
      for (var i = 0; i < items.length; i++) {
        final c = parsed[i], x = items[i];
        hasKeys(x, const ['id', 'title', 'scope', 'created_at', 'last_at', 'turns'], 'conversation');
        final sc = m(x['scope']);
        hasKeys(sc, const ['app', 'org_id', 'course_id'], 'conversation scope');
        expect(c.id, x['id']);
        expect(c.title, '${x['title'] ?? ''}'.trim());
        expect(c.app, sc['app']);
        expect(c.orgId, sc['org_id']);
        expect(c.courseId, sc['course_id']);
        expect(c.createdAt, utc(x['created_at']));
        expect(c.lastAt, utc(x['last_at'] ?? x['created_at']));
        expect(c.turns, x['turns']);
      }
    });

    void sameAnswer(RagAnswer a, Map<String, dynamic> x) {
      hasKeys(x, const ['id', 'state', 'question', 'found', 'answer', 'citations', 'error', 'helpful', 'follow_ups', 'stage',
          'generator', 'app', 'org_id', 'conversation_id'], 'query row');
      expect(a.id, x['id']);
      expect(a.state, x['state']);
      expect(a.question, x['question']);
      expect(a.found, x['found']);
      expect(a.answer, x['answer'] ?? '');
      expect(a.error, x['error']);
      expect(a.helpful, x['helpful']);
      expect(a.followUps, [for (final f in x['follow_ups'] as List) '$f'.trim()]..removeWhere((f) => f.isEmpty));
      expect(a.stage, x['stage']);
      expect(a.generator, x['generator'] ?? '');
      expect(a.app, x['app']);
      expect(a.orgId, x['org_id']);
      expect(a.conversationId, x['conversation_id']);
      final cits = ms(x['citations']);
      expect(a.citations.length, cits.length);
      for (var k = 0; k < cits.length; k++) {
        final c = a.citations[k], y = cits[k];
        hasKeys(y, const ['n', 'document_id', 'title', 'section', 'page_from', 'page_to', 'quote'], 'citation');
        expect(c.n, y['n']);
        // REPORTED (rag_chat.dart is not ours to edit): a curated-answer citation (`kind: qa`) has
        // `document_id: null`; RagCitation.documentId is a non-null int and reads it as 0.
        expect(c.documentId, y['document_id'] ?? 0);
        expect(c.kind, y['kind'] ?? '');
        expect(c.deepLink, y['deep_link']);
        expect(c.title, y['title'] ?? '');
        expect(c.section, y['section'] ?? '');
        expect(c.pageFrom, y['page_from']);
        expect(c.pageTo, y['page_to']);
        expect(c.quote, y['quote'] ?? '');
      }
    }

    test('GET /rag/conversations/{id}/messages (full + a page)', () {
      for (final name in ['rag_messages', 'rag_messages_page']) {
        final j = fixture(name);
        hasKeys(j, const ['items', 'has_more'], name);
        final r = EngineResult.ok(j);
        expect(RagApi.hasMore(r), j['has_more']);
        final items = ms(j['items']);
        expect(items, isNotEmpty);
        final parsed = RagApi.items(r);
        expect(parsed.length, items.length);
        for (var i = 0; i < items.length; i++) {
          sameAnswer(parsed[i], items[i]);
          expect(parsed[i].conversationId, isNotNull);
        }
      }
      expect(fixture('rag_messages_page')['has_more'], isTrue);
      expect(ms(fixture('rag_messages')['items']).any((x) => (x['citations'] as List).isNotEmpty), isTrue);
    });
  });

  // ── RAG: curated Q&A ───────────────────────────────────────────────────────
  test('GET /rag/qa → QaLibrary', () {
    final j = fixture('rag_qa');
    hasKeys(j, const ['items', 'scope', 'org_id', 'manager', 'embedder', 'thresholds', 'usage'], 'rag/qa');
    final lib = QaLibrary.fromJson(j);
    expect(lib.scope, j['scope']);
    expect(lib.orgId, j['org_id']);
    expect(lib.manager, j['manager']);
    expect(lib.embedder, j['embedder']);
    hasKeys(m(j['thresholds']), const ['direct', 'example'], 'rag/qa thresholds');
    expect(lib.directThreshold, asDoubleOrNull(j['thresholds']['direct']));
    expect(lib.exampleThreshold, asDoubleOrNull(j['thresholds']['example']));
    hasKeys(m(j['usage']), const ['pairs', 'enabled', 'direct'], 'rag/qa usage');
    expect(lib.pairs, j['usage']['pairs']);
    expect(lib.enabledCount, j['usage']['enabled']);
    expect(lib.direct, j['usage']['direct']);
    final items = ms(j['items']);
    expect(items, isNotEmpty);
    expect(lib.items.length, items.length);
    for (var i = 0; i < items.length; i++) {
      final p = lib.items[i], x = items[i];
      hasKeys(x, const ['id', 'scope', 'org_id', 'question', 'variants', 'answer', 'lang', 'deep_link', 'enabled', 'created_by',
          'usage_count', 'last_used_at', 'version', 'created_at', 'updated_at', 'stale'], 'qa pair');
      expect(p.id, x['id']);
      expect(p.scope, x['scope']);
      expect(p.orgId, x['org_id']);
      expect(p.question, '${x['question']}'.trim());
      expect(p.variants, x['variants']);
      expect(p.answer, x['answer']);
      expect(p.lang, x['lang']);
      expect(p.deepLink, x['deep_link']);
      expect(p.enabled, x['enabled']);
      expect(p.createdBy, x['created_by']);
      expect(p.usageCount, x['usage_count']);
      expect(p.lastUsedAt, x['last_used_at']);
      expect(p.version, x['version']);
      expect(p.createdAt, x['created_at']);
      expect(p.updatedAt, x['updated_at']);
      expect(p.stale, x['stale']);
    }
  });

  // ── RAG: admin overview + monitoring ───────────────────────────────────────
  group('GET /rag/admin/overview → RagOverview / RagMonitoring', () {
    test('real payload', () {
      final j = fixture('rag_admin_overview');
      hasKeys(j, const ['days', 'totals', 'latency_ms', 'by_day', 'contexts', 'generators', 'not_found', 'unhelpful', 'documents',
          'queue', 'exam_drafts', 'qa', 'monitoring'], 'rag/admin/overview');
      final o = RagOverview.fromJson(j);
      final tot = m(j['totals']);
      hasKeys(tot, const ['asked', 'answered', 'found', 'failed', 'pending', 'rated', 'helpful', 'askers'], 'totals');
      expect(o.days, j['days']);
      expect([o.asked, o.answered, o.found, o.failed, o.pending, o.rated, o.helpful, o.askers],
          [tot['asked'], tot['answered'], tot['found'], tot['failed'], tot['pending'], tot['rated'], tot['helpful'], tot['askers']]);
      expect(o.p50, asIntOrNull(j['latency_ms']['p50']));
      expect(o.p90, asIntOrNull(j['latency_ms']['p90']));
      expect(o.byDay, j['by_day']);
      expect(o.notFound, j['not_found']);
      expect(o.unhelpful, j['unhelpful']);
      expect(o.documents, j['documents']);
      expect(o.contexts, {for (final e in m(j['contexts']).entries) e.key: Map<String, int>.from(e.value as Map)});
      expect(o.generators, Map<String, int>.from(j['generators'] as Map));
      expect(o.queueWaiting, j['queue']['waiting']);
      expect([o.drafts, o.draftQuestions, o.draftsLlm],
          [j['exam_drafts']['total'], j['exam_drafts']['questions'], j['exam_drafts']['llm']]);
      final qa = m(j['qa']);
      hasKeys(qa, const ['pairs', 'enabled', 'direct', 'example'], 'qa');
      expect([o.qaPairs, o.qaEnabled, o.qaDirect, o.qaExample], [qa['pairs'], qa['enabled'], qa['direct'], qa['example']]);

      final mj = m(j['monitoring']);
      hasKeys(mj, const ['days', 'questions', 'latency_ms', 'cache_hit_rate', 'qa_direct_rate', 'qa_example_rate',
          'no_answer_rate', 'fallback_rate', 'helpful_rate', 'by_day'], 'monitoring');
      final mo = o.monitoring!;
      expect(mo.days, mj['days']);
      expect(mo.questions, mj['questions']);
      expect(mo.hasActivity, isTrue);
      final lat = m(mj['latency_ms']);
      expect(mo.p50, asIntOrNull(lat['p50']));
      expect(mo.p95, asIntOrNull(lat['p95']));
      final bp = m(lat['by_path']);
      expect(bp.keys.toSet(), ragPaths.toSet(), reason: 'by_path keys = the app\'s ragPaths');
      for (final p in ragPaths) {
        final x = m(bp[p]);
        hasKeys(x, const ['questions', 'count', 'p50', 'p95'], 'by_path.$p');
        expect(mo.byPath[p]!.questions, x['questions']);
        expect(mo.byPath[p]!.count, x['count']);
        expect(mo.byPath[p]!.p50, asIntOrNull(x['p50']));
        expect(mo.byPath[p]!.p95, asIntOrNull(x['p95']));
      }
      expect(mo.cacheHitRate, asDoubleOrNull(mj['cache_hit_rate']));
      expect(mo.qaDirectRate, asDoubleOrNull(mj['qa_direct_rate']));
      expect(mo.qaExampleRate, asDoubleOrNull(mj['qa_example_rate']));
      expect(mo.noAnswerRate, asDoubleOrNull(mj['no_answer_rate']));
      expect(mo.fallbackRate, asDoubleOrNull(mj['fallback_rate']));
      expect(mo.helpfulRate, asDoubleOrNull(mj['helpful_rate']));
      final days = ms(mj['by_day']);
      expect(days.length, mj['days']);
      expect(mo.byDay.length, days.length);
      for (var i = 0; i < days.length; i++) {
        hasKeys(days[i], const ['day', 'questions', 'no_answer', 'cache_hits', 'qa_direct', 'p50_ms'], 'monitoring by_day');
        expect(mo.byDay[i].day, days[i]['day']);
        expect(mo.byDay[i].questions, days[i]['questions']);
        expect(mo.byDay[i].noAnswer, days[i]['no_answer']);
        expect(mo.byDay[i].cacheHits, days[i]['cache_hits']);
        expect(mo.byDay[i].qaDirect, days[i]['qa_direct']);
        expect(mo.byDay[i].p50Ms, asIntOrNull(days[i]['p50_ms']));
      }
    });

    test('older server: no monitoring / qa → the block hides', () {
      final j = fixture('rag_admin_overview')
        ..remove('monitoring')
        ..remove('qa');
      final o = RagOverview.fromJson(j);
      expect(o.monitoring, isNull);
      expect(o.qaPairs, 0);
      expect(o.asked, j['totals']['asked']);
    });
  });

  // ── the SSE stream (GET /api/v1/me/events) → LiveEvent getters ─────────────
  group('live events: the server\'s SSE frames → LiveEvent', () {
    Future<void> check(String file) async {
      final f = File('$_dir/$file');
      expect(f.existsSync(), isTrue, reason: '$file missing: run ../back/tests/contract/dump_payloads.py');
      final frames = SseParser().feed(f.readAsStringSync());
      expect(frames, isNotEmpty);
      final got = <LiveEvent>[];
      final sub = LiveEvents.instance.listen({for (final x in frames) x.name}, got.add);
      addTearDown(sub.cancel);
      for (final x in frames) {
        LiveEvents.instance.emit(x.name, x.json); // exactly what LiveEventsClient._deliver does
      }
      await Future<void>.delayed(Duration.zero);
      {
        expect(got.length, frames.length);
        for (var i = 0; i < frames.length; i++) {
          final env = frames[i].json, e = got[i];
          expect(env['event'], frames[i].name);
          expect(env['id'], frames[i].id, reason: 'the frame id is the envelope id (Last-Event-ID / dedupe)');
          final d = m(env['data']);
          expect(e.data, d, reason: '${e.type}: listeners get the event fields, not the envelope');
          int? n(String k) => d[k] == null ? null : int.parse('${d[k]}');
          String? s(String k) => d[k]?.toString();
          expect(e.complaintId, n('complaint_id'));
          expect(e.paymentId, n('payment_id'));
          expect(e.action, d['action']);
          expect(e.tab, s('tab'));
          expect(e.orgId, n('org_id'));
          expect(e.kind, s('kind'));
          expect(e.id, s('id'));
          expect(e.status, s('status'));
          expect(e.stage, s('stage'));
          expect(e.sessionId, n('session_id'));
          expect(e.courseId, n('course_id'));
          expect(e.examId, n('exam_id'));
          expect(e.requestId, n('request_id'));
          expect(e.withdrawalId, n('withdrawal_id'));
          expect(e.state, s('state'));
          expect(e.relatedType, s('related_type'));
          expect(e.relatedId, n('related_id'));
          if (!LiveEvents.serverTypes.contains(e.type)) fail('the server emits "${e.type}", unknown to LiveEvents.serverTypes');
        }
      }
    }

    test('one frame of every event shape the harnesses emitted', () => check('live_events.sse'));
    test('a real GET /me/events body', () => check('live_events_stream.sse'));

    test('a silent push (flat fields + event_id) is passed through as-is', () async {
      final got = <LiveEvent>[];
      final sub = LiveEvents.instance.listen({LiveEvents.jobUpdated}, got.add);
      LiveEvents.instance.emit(LiveEvents.jobUpdated, {'kind': 'export', 'id': 'e1', 'status': 'ready', 'event_id': 'u'});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(got.single.id, 'e1');
      expect(got.single.kind, 'export');
    });
  });

  // ── GET /api/v1/entities/... (D-290) ───────────────────────────────────────
  group('GET /api/v1/entities/* → entity models', () {
    const enrollmentKeys = ['enrollment_id', 'state', 'enrolled_at', 'expected_end_at', 'progress', 'first_activity_at',
        'last_activity_at', 'completed_at', 'withdrawn_at', 'withdrawal_reason_code', 'withdrawal_reason', 'favorited',
        'rating', 'exams'];

    void samePerson(EntityRef? r, dynamic j, EntityKind kind, String where) {
      hasKeys(m(j), const ['id', 'name', 'username', 'image_url'], where);
      expect(r, EntityRef(kind, j['id'] as int));
      expect(r!.label, j['name']);
      expect(r.imageUrl, j['image_url']);
    }

    void sameCategory(EntityRef? r, dynamic j, String where) {
      if (j == null) return expect(r, isNull);
      hasKeys(m(j), const ['id', 'name_ar', 'name_en'], where);
      expect(r, EntityRef(EntityKind.category, j['id'] as int));
      expect(r!.label, j['name_ar']);
      expect(r.labelEn, j['name_en']);
    }

    void sameCourse(EntityCourse? c, dynamic j, String where) {
      hasKeys(m(j), const ['id', 'name_ar', 'name_en', 'image_url', 'category', 'teacher'], where);
      expect(c!.ref, EntityRef(EntityKind.course, j['id'] as int));
      expect(c.ref.label, j['name_ar']);
      expect(c.ref.labelEn, j['name_en']);
      sameCategory(c.category, j['category'], '$where.category');
      if (j['teacher'] != null) samePerson(c.teacher, j['teacher'], EntityKind.teacher, '$where.teacher');
    }

    void sameEnrollment(EntityEnrollment e, Map<String, dynamic> j, String where) {
      hasKeys(j, enrollmentKeys, where);
      expect(e.enrollmentId, j['enrollment_id']);
      expect(e.state, j['state']);
      expect(entityEnrollmentStates, contains(e.state));
      expect(e.enrolledAt, utc(j['enrolled_at']));
      expect(e.expectedEndAt, utc(j['expected_end_at']));
      expect(e.progress, asDoubleOrNull(j['progress']));
      expect(e.firstActivityAt, utc(j['first_activity_at']));
      expect(e.lastActivityAt, utc(j['last_activity_at']));
      expect(e.completedAt, utc(j['completed_at']));
      expect(e.withdrawnAt, utc(j['withdrawn_at']));
      expect(e.withdrawalReasonCode, j['withdrawal_reason_code']);
      expect(e.withdrawalReason, j['withdrawal_reason']);
      expect(e.favorited, j['favorited']);
      if (j['rating'] == null) {
        expect(e.rating, isNull);
      } else {
        hasKeys(m(j['rating']), const ['value', 'review', 'at'], '$where.rating');
        expect(e.rating!.value, j['rating']['value']);
        expect(e.rating!.review, j['rating']['review']);
        expect(e.rating!.at, utc(j['rating']['at']));
      }
      hasKeys(m(j['exams']), const ['count', 'avg_percentage', 'passed'], '$where.exams');
      expect(e.exams!.count, j['exams']['count']);
      expect(e.exams!.avgPercentage, asDoubleOrNull(j['exams']['avg_percentage']));
      expect(e.exams!.passed, j['exams']['passed']);
    }

    void sameSummary(EntitySummary s, Map<String, dynamic> j, String where) {
      hasKeys(j, const ['kind', 'id', 'header', 'stats', 'badges', 'sections', 'can'], where);
      expect(s.kind.name, j['kind']);
      expect(s.id, j['id']);
      expect(s.header, j['header']);
      expect(s.stats, j['stats']);
      expect(s.sections, j['sections']);
      expect(s.badges.length, (j['badges'] as List).length);
      for (var i = 0; i < s.badges.length; i++) {
        final b = m(j['badges'][i]);
        hasKeys(b, const ['code', 'level', 'value'], '$where.badges');
        expect(s.badges[i].code, b['code']);
        expect(s.badges[i].level, b['level']);
        expect(s.badges[i].value, b['value']);
      }
      hasKeys(m(j['can']), const ['manage', 'message', 'see_money'], '$where.can');
      expect(s.can.manage, j['can']['manage']);
      expect(s.can.message, j['can']['message']);
      expect(s.can.seeMoney, j['can']['see_money']);
    }

    test('a student (admin view)', () {
      final j = fixture('entity_student');
      final s = EntitySummary.fromJson(j);
      sameSummary(s, j, 'student');
      hasKeys(m(j['header']), const ['id', 'name', 'username', 'image_url', 'country', 'is_active', 'created_at',
          'last_login', 'email', 'phone', 'study'], 'student.header');
      hasKeys(m(j['stats']), const ['enrolled', 'in_progress', 'completed', 'withdrawn', 'expired', 'pending',
          'avg_progress', 'last_activity_at'], 'student.stats');
      expect(s.ref.name, j['header']['name']);
      expect(s.time('created_at'), utc(j['header']['created_at']));
      expect(s.statTime('last_activity_at'), utc(j['stats']['last_activity_at']));
      expect(s.sections, containsAll(['courses', 'timeline']));
    });

    test('a course (staff view, money) and a learner\'s view of it (stats.mine)', () {
      final j = fixture('entity_course');
      final s = EntitySummary.fromJson(j);
      sameSummary(s, j, 'course');
      final h = m(j['header']);
      hasKeys(h, const ['id', 'name_ar', 'name_en', 'image_url', 'category', 'teacher', 'status', 'is_published',
          'is_private', 'price', 'start_date', 'end_date', 'created_at', 'archived_at'], 'course.header');
      hasKeys(m(h['price']), const ['fees', 'monthly', 'six_months', 'currency'], 'course.header.price');
      sameCategory(s.category, h['category'], 'course.header.category');
      samePerson(s.teacher, h['teacher'], EntityKind.teacher, 'course.header.teacher');
      final st = m(j['stats']);
      hasKeys(st, const ['enrolled', 'in_progress', 'completed', 'withdrawn', 'expired', 'pending', 'completion_rate',
          'avg_progress', 'rating_avg', 'rating_count', 'favorites', 'sessions', 'materials', 'withdrawal_reasons', 'trend',
          'revenue'], 'course.stats');
      final trend = ms(st['trend']);
      expect(s.trend.length, trend.length);
      for (var i = 0; i < trend.length; i++) {
        hasKeys(trend[i], const ['week_start', 'count'], 'course.stats.trend');
        expect(s.trend[i].weekStart, utc(trend[i]['week_start']));
        expect(s.trend[i].count, trend[i]['count']);
      }
      final reasons = ms(st['withdrawal_reasons']);
      expect(s.withdrawalReasons, [for (final r in reasons) (r['code'], r['count'])]);
      hasKeys(m(st['revenue']), const ['amount', 'currency'], 'course.stats.revenue');
      expect(s.revenue.single.amount, asDoubleOrNull(st['revenue']['amount']));
      expect(s.revenue.single.currency, st['revenue']['currency']);
      expect(s.isLearnerView, isFalse);

      final lj = fixture('entity_course_learner');
      final l = EntitySummary.fromJson(lj);
      sameSummary(l, lj, 'course (learner)');
      hasKeys(m(lj['stats']), const ['rating_avg', 'rating_count', 'enrolled', 'sessions', 'materials', 'mine'],
          'course.stats (learner)');
      expect(l.isLearnerView, isTrue);
      sameEnrollment(l.mine!, m(lj['stats']['mine']), 'course.stats.mine');
      expect(l.revenue, isEmpty, reason: 'no money for a learner');
    });

    test('a teacher (revenue per currency) and a category (top courses)', () {
      final j = fixture('entity_teacher');
      final s = EntitySummary.fromJson(j);
      sameSummary(s, j, 'teacher');
      hasKeys(m(j['header']), const ['id', 'name', 'username', 'image_url', 'bio', 'is_active', 'specialization',
          'created_at'], 'teacher.header');
      sameCategory(s.specialization, j['header']['specialization'], 'teacher.header.specialization');
      final st = m(j['stats']);
      hasKeys(st, const ['courses', 'published_courses', 'students', 'active_students_30d', 'rating_avg',
          'teacher_rating_avg', 'completion_rate', 'revenue'], 'teacher.stats');
      final rev = ms(st['revenue']);
      expect(s.revenue.length, rev.length);
      for (var i = 0; i < rev.length; i++) {
        hasKeys(rev[i], const ['currency', 'amount'], 'teacher.stats.revenue');
        expect(s.revenue[i].amount, asDoubleOrNull(rev[i]['amount']));
        expect(s.revenue[i].currency, rev[i]['currency']);
      }

      final cj = fixture('entity_category');
      final c = EntitySummary.fromJson(cj);
      sameSummary(c, cj, 'category');
      hasKeys(m(cj['header']), const ['id', 'name_ar', 'name_en', 'description', 'image_url', 'parent', 'children'],
          'category.header');
      sameCategory(c.parent, cj['header']['parent'], 'category.header.parent');
      expect(c.children.length, (cj['header']['children'] as List).length);
      final cs = m(cj['stats']);
      hasKeys(cs, const ['courses', 'teachers', 'students', 'completion_rate', 'top_courses'], 'category.stats');
      final top = ms(cs['top_courses']);
      expect(c.topCourses.length, top.length);
      for (var i = 0; i < top.length; i++) {
        hasKeys(top[i], const ['course', 'students'], 'category.stats.top_courses');
        sameCourse(c.topCourses[i].$1, top[i]['course'], 'category.stats.top_courses.course');
        expect(c.topCourses[i].$2, top[i]['students']);
      }
    });

    EntityPage<EntityItem> pageOf(EntityKind kind, String section, Map<String, dynamic> j) {
      hasKeys(j, const ['items', 'total', 'page', 'size', 'pages'], '$kind/$section');
      final p = EntityPage.fromJson<EntityItem>(j, (x) => EntityItem.parse(kind, section, x));
      expect(p.total, j['total']);
      expect(p.page, j['page']);
      expect(p.size, j['size']);
      expect(p.pages, j['pages']);
      expect(p.items.length, (j['items'] as List).length);
      expect(p.items, isNotEmpty, reason: '$kind/$section: the harness seeds rows');
      return p;
    }

    test('enrollment rows: a student\'s courses, a course\'s students', () {
      final sc = fixture('entity_student_courses');
      final p1 = pageOf(EntityKind.student, 'courses', sc);
      for (var i = 0; i < p1.items.length; i++) {
        final r = p1.items[i] as EnrollmentRow, j = m(sc['items'][i]);
        sameCourse(r.course, j['course'], 'student.courses.course');
        expect(r.subject, r.course!.ref);
        sameEnrollment(r.enrollment, j, 'student.courses');
      }
      final cs = fixture('entity_course_students');
      final p2 = pageOf(EntityKind.course, 'students', cs);
      for (var i = 0; i < p2.items.length; i++) {
        final r = p2.items[i] as EnrollmentRow, j = m(cs['items'][i]);
        samePerson(r.subject, j['student'], EntityKind.student, 'course.students.student');
        sameEnrollment(r.enrollment, j, 'course.students');
      }
    });

    test('course rows of a teacher / a category', () {
      for (final (kind, name) in [(EntityKind.teacher, 'entity_teacher_courses'), (EntityKind.category, 'entity_category_courses')]) {
        final j = fixture(name);
        final p = pageOf(kind, 'courses', j);
        for (var i = 0; i < p.items.length; i++) {
          final r = p.items[i] as CourseRow, x = m(j['items'][i]);
          hasKeys(x, const ['course', 'status', 'is_published', 'archived_at', 'students', 'completion_rate', 'rating_avg',
              'revenue'], name);
          sameCourse(r.course, x['course'], '$name.course');
          expect(r.status, x['status']);
          expect(r.isPublished, x['is_published']);
          expect(r.archivedAt, utc(x['archived_at']));
          expect(r.students, x['students']);
          expect(r.completionRate, asDoubleOrNull(x['completion_rate']));
          expect(r.ratingAvg, asDoubleOrNull(x['rating_avg']));
          expect(r.revenue?.amount, asDoubleOrNull(x['revenue']?['amount']));
        }
      }
    });

    test('people rows: a teacher\'s / category\'s students, a category\'s teachers', () {
      for (final (kind, section, name, person) in [
        (EntityKind.teacher, 'students', 'entity_teacher_students', EntityKind.student),
        (EntityKind.category, 'students', 'entity_category_students', EntityKind.student),
        (EntityKind.category, 'teachers', 'entity_category_teachers', EntityKind.teacher),
      ]) {
        final j = fixture(name);
        final p = pageOf(kind, section, j);
        for (var i = 0; i < p.items.length; i++) {
          final r = p.items[i] as PersonRow, x = m(j['items'][i]);
          samePerson(r.person, x[person.name], person, '$name.${person.name}');
          expect(r.username, x[person.name]['username']);
          expect(r.courses, x['courses']);
          if (person == EntityKind.student) {
            hasKeys(x, const ['courses', 'avg_progress', 'last_activity_at'], name);
            expect(r.avgProgress, asDoubleOrNull(x['avg_progress']));
            expect(r.lastActivityAt, utc(x['last_activity_at']));
          } else {
            hasKeys(x, const ['courses', 'students'], name);
            expect(r.students, x['students']);
          }
        }
      }
    });

    test('a student\'s payments and subscription events (admins)', () {
      final pj = fixture('entity_student_payments');
      final p = pageOf(EntityKind.student, 'payments', pj);
      for (var i = 0; i < p.items.length; i++) {
        final r = p.items[i] as PaymentRow, x = m(pj['items'][i]);
        hasKeys(x, const ['id', 'course', 'amount', 'currency', 'status', 'method', 'provider', 'paid_at', 'refunded_at',
            'created_at'], 'payments');
        sameCourse(r.course, x['course'], 'payments.course');
        expect(r.id, x['id']);
        expect(r.amount, asDoubleOrNull(x['amount']));
        expect(r.currency, x['currency']);
        expect(r.status, x['status']);
        expect(r.method, x['method'] ?? x['provider']);
        expect(r.paidAt, utc(x['paid_at']));
        expect(r.refundedAt, utc(x['refunded_at']));
      }
      final sj = fixture('entity_student_subscriptions');
      final s = pageOf(EntityKind.student, 'subscriptions', sj);
      for (var i = 0; i < s.items.length; i++) {
        final r = s.items[i] as SubscriptionRow, x = m(sj['items'][i]);
        hasKeys(x, const ['id', 'type', 'actor_type', 'reason', 'course', 'occurred_at'], 'subscriptions');
        sameCourse(r.course, x['course'], 'subscriptions.course');
        expect(r.id, x['id']);
        expect(r.type, x['type']);
        expect(r.actorType, x['actor_type']);
        expect(r.reason, x['reason']);
        expect(r.occurredAt, utc(x['occurred_at']));
      }
    });

    test('a student\'s timeline in one course: every event with the data the app reads', () {
      final j = fixture('entity_timeline');
      hasKeys(j, const ['items', 'total', 'page', 'size', 'pages'], 'timeline');
      final p = EntityPage.fromJson(j, EntityTimelineEvent.fromJson);
      const dataKeys = {
        'material_completed': ['title'],
        'live_attended': ['title'],
        'exam_submitted': ['title', 'percentage', 'passed'],
        'rated': ['value', 'review'],
        'subscription': ['event', 'actor'],
        'withdrawn': ['reason_code'],
      };
      for (var i = 0; i < p.items.length; i++) {
        final e = p.items[i], x = m(j['items'][i]);
        hasKeys(x, const ['at', 'type', 'data'], 'timeline item');
        expect(e.at, utc(x['at']));
        expect(e.type, x['type']);
        expect(e.data, x['data']);
        hasKeys(m(x['data']), dataKeys[e.type] ?? const [], 'timeline ${e.type}.data');
      }
    });

    test('older server: no badges / sections / can / the new stats, rows without the 0051 history → drawn less', () {
      final j = fixture('entity_student')
        ..remove('badges')
        ..remove('sections')
        ..remove('can');
      (j['stats'] as Map).remove('last_activity_at');
      final s = EntitySummary.fromJson(j);
      expect(s.badges, isEmpty);
      expect(s.sections, isEmpty, reason: 'the panel opens nothing it was not told about');
      expect(s.can.manage, isFalse);
      expect(s.statTime('last_activity_at'), isNull);
      final c = fixture('entity_course');
      (c['stats'] as Map)
        ..remove('trend')
        ..remove('withdrawal_reasons')
        ..remove('revenue');
      final cs = EntitySummary.fromJson(c);
      expect(cs.trend, isEmpty);
      expect(cs.withdrawalReasons, isEmpty);
      expect(cs.revenue, isEmpty);
      final row = m(fixture('entity_student_courses')['items'][0])
        ..removeWhere((k, _) => const ['first_activity_at', 'last_activity_at', 'completed_at', 'withdrawn_at',
            'withdrawal_reason_code', 'withdrawal_reason', 'favorited', 'rating', 'exams', 'expected_end_at'].contains(k));
      final r = EntityItem.parse(EntityKind.student, 'courses', row) as EnrollmentRow;
      expect(r.enrollment.lastActivityAt, isNull);
      expect(r.enrollment.withdrawalReasonCode, isNull);
      expect(r.enrollment.exams, isNull);
      expect(r.enrollment.state, row['state']);
    });
  });
}
