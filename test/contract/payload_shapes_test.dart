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
import 'package:flutter_education_app/core/live/live_events_client.dart' show SseParser;
import 'package:flutter_education_app/features/admin/admin_home_data.dart';
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
  return DateTime.parse(zoned ? s : '${s}Z').toUtc();
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

    test('student without a membership: org_overview null, no courses', () {
      final j = fixture('me_home_student_no_org');
      final h = MeHome.fromJson(j);
      common(j, h);
      expect(h.orgOverview, isNull);
      expect(h.coursesProgress, isEmpty);
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
        expect(c.documentId, y['document_id']);
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
}
