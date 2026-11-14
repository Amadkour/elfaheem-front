// Course profile: pure helpers + the page at 320x640 / 1400x900, Arabic + English, textScaler 1.3 (no network:
// the payload is passed in `initial`).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_actions.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_models.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_parts.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'مقدمة في هندسة البرمجيات وتصميم الأنظمة الموزعة والحوسبة السحابية المتقدمة';
const longEn = 'Introduction to Software Engineering, Distributed Systems Design and Advanced Cloud Computing';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> session(int id, String track, {int days = -3, bool done = false, int mats = 2}) => {
      'id': id,
      'name': '$longAr $id',
      'description': longEn,
      'track': track,
      'type': 'live',
      'scheduled_at': iso(DateTime.now().add(Duration(days: days))),
      'duration_minutes': 90,
      'group_no': track == 'section' ? 2 : null,
      'from_timetable': true,
      'live_now': id == 1,
      'upcoming': days > 0,
      'materials_count': mats,
      'materials': [
        for (var i = 0; i < mats; i++)
          {
            'id': id * 10 + i,
            'session_id': id,
            'name': '$longEn material $i',
            'type': i == 0 ? 'video' : 'pdf',
            'order': i,
            'created_at': iso(DateTime.now()),
            'completed': done,
            'duration_seconds': i == 0 ? 3725 : null,
            if (i == 0) 'requires_play': true else 'url': 'https://f.test/$id.pdf',
          }
      ],
      'done': done,
      'attended': done,
      'watched': false,
    };

Map<String, dynamic> payload(String role, {bool closed = false, String archiveState = 'locked', bool past = false}) {
  final staff = role == 'instructor' || role == 'admin';
  final team = staff || role == 'ta';
  final now = !closed && !past;
  return {
    'course': {
      'id': 7,
      'name_ar': longAr,
      'name_en': longEn,
      'description_ar': longAr,
      'description_en': longEn,
      'kind': 'org',
      'org': {'id': 3, 'name_ar': longAr, 'name_en': longEn},
      'code': 'CS101',
      'credit_hours': 3,
      'teacher': {'id': 1, 'name': longAr},
      'term': {'id': 1, 'year_label': '2026/2027', 'kind': 'term1', 'start_date': '2026-09-20', 'end_date': '2027-01-20'},
      'run': {'id': 1, 'status': closed ? 'archived' : 'open'},
    },
    'role': role,
    'caps': {
      'view_material': !closed || archiveState == 'granted' || staff,
      'manage_lecture': staff,
      'manage_section': staff || role == 'ta',
      'attend_lecture': staff && !closed,
      'attend_section': (staff || role == 'ta') && !closed,
      'view_attendance': true,
      'view_all_attendance': staff,
      'manage_staff': staff,
      'manage_certificates': staff,
      'manage_archive': staff,
      'approve_archive': false,
      'live': !closed,
      'announce': (staff || role == 'ta') && !closed,
      'view_versions': team,
      'archive_course': role == 'admin' && now,
      'course_settings': staff && !past,
    },
    'version': {'run_id': past ? 1 : 2, 'past': past},
    'versions': team
        ? [
            {'id': 2, 'status': 'open', 'current': true, 'students': 0, 'passed': 0,
              'term': {'id': 2, 'year_label': '2026/2027', 'kind': 'term2'}},
            {'id': 1, 'status': 'archived', 'current': false, 'students': 128, 'passed': 120,
              'term': {'id': 1, 'year_label': '2026/2027', 'kind': 'term1'}},
          ]
        : null,
    'attendance_target': team && now ? {'id': 2, 'name': '$longAr 2', 'track': 'lecture', 'live_now': false} : null,
    'announcements': role == 'ta'
        ? []
        : [
            {'id': 1, 'track': 'all', 'title': longAr, 'body': '$longEn $longAr', 'pinned': true,
              'created_at': iso(DateTime.now()), 'author': {'id': 1, 'name': longAr}, 'can_delete': staff},
            {'id': 2, 'track': 'section', 'title': longEn, 'body': null, 'pinned': false,
              'created_at': iso(DateTime.now()), 'author': {'id': 2, 'name': longEn}, 'can_delete': false},
          ],
    'closed': closed,
    'read_only': (closed && role == 'student') || past,
    'grant': role == 'ta' ? {'lecture_edit': false, 'lecture_attendance': true} : null,
    'archive': closed && role == 'student'
        ? {'closed': true, 'state': archiveState, 'mode': 'code', 'effective_mode': 'code', 'took_it': true, 'until': null}
        : null,
    'archive_policy': staff ? {'mode': 'code', 'days': 180, 'code': 'AB12CD', 'open_access': false} : null,
    'tracks': {
      'lecture': [session(1, 'lecture', done: true), session(2, 'lecture'), session(3, 'lecture', days: 4, mats: 0)],
      'section': [session(4, 'section'), session(5, 'section', days: 2)],
    },
    'staff': {
      'instructor': {'id': 1, 'name': longAr},
      'assistants': [
        {'user': {'id': 2, 'name': longEn}, 'lecture_edit': false, 'lecture_attendance': true},
      ],
    },
    'certificates': staff
        ? [
            {'id': 1, 'title': longEn, 'scope': 'lecture', 'auto_send': true, 'issued_count': 12},
          ]
        : role != 'student'
            ? []
            : [
            {'id': 1, 'title': longEn, 'scope': 'both', 'auto_send': true, 'progress': 62.5, 'issued': false},
            {'id': 2, 'title': longAr, 'scope': 'lecture', 'issued': true, 'url': 'https://f/c.png', 'url_ar': 'https://f/a.png'},
          ],
    'analytics': staff
        ? {'lectures': 3, 'sections': 2, 'students': 128, 'avg_progress': 64.2, 'completed': 9, 'attendance_rate': 81.0,
            'at_risk': 4, 'held': 10, 'missed_by_staff': 2,
            'next_session': {'id': 3, 'name': longAr, 'track': 'lecture', 'scheduled_at': iso(DateTime.now().add(const Duration(days: 4)))}}
        : {'lectures': 3, 'sections': 2, 'progress': {'overall': 50.0, 'lecture': 100.0, 'section': 0.0},
            'attended': 7, 'expected': 9, 'absence_pct': 22.2, 'grade': {'percent': 87.5, 'letter': 'B+', 'denied': false}},
  };
}

Map<String, dynamic> attendance(bool staff) => {
      'sessions': [
        for (var i = 0; i < 4; i++)
          {
            'id': i,
            'name': '$longAr $i',
            'track': i.isEven ? 'lecture' : 'section',
            'scheduled_at': iso(DateTime.now().subtract(Duration(days: i))),
            'expected': 40,
            'present': 31,
            'absent': 9,
            'held': i != 2,
            'missed_by_staff': i == 2,
            'staff': {'id': 2, 'name': longEn},
            if (!staff) 'me': ['present', 'absent', 'not_held', 'present'][i],
          }
      ],
      'students': [
        {'user': {'id': 5, 'name': longAr}, 'attended': 3, 'expected': 4, 'absent': 1, 'absence_pct': 25.0},
        {'user': {'id': 6, 'name': longEn}, 'attended': 4, 'expected': 4, 'absent': 0, 'absence_pct': 0.0},
      ],
      'held': 3,
      'missed_by_staff': staff ? 1 : 0,
    };

void main() {
  test('tabs follow the role', () {
    expect(cpTabs(CourseProfile(payload('instructor'))),
        ['overview', 'lecture', 'section', 'attendance', 'announcements', 'certificates', 'team', 'archive']);
    expect(cpTabs(CourseProfile(payload('student'))),
        ['overview', 'lecture', 'section', 'attendance', 'announcements', 'certificates']);
    // closed: read-only — no attendance tab, archive tab instead; old announcements stay readable
    expect(cpTabs(CourseProfile(payload('student', closed: true))),
        ['overview', 'lecture', 'section', 'announcements', 'certificates', 'archive']);
    // a TA can always announce (to sections & labs) and sees the course's versions
    expect(cpTabs(CourseProfile(payload('ta'))),
        ['overview', 'lecture', 'section', 'attendance', 'announcements', 'team', 'archive']);
    // an earlier version: review only
    expect(cpTabs(CourseProfile(payload('ta', past: true))), ['overview', 'lecture', 'section', 'attendance']);
    expect(cpTabs(CourseProfile(payload('instructor', past: true))),
        ['overview', 'lecture', 'section', 'announcements', 'attendance']);
  });

  test('versions · attendance target · markable sessions', () {
    final p = CourseProfile(payload('instructor'));
    expect(p.versions.map((v) => (v.id, v.current, v.archived)).toList(), [(2, true, false), (1, false, true)]);
    expect(cpTermLabel(p.versions.last.term, false), 'Term 1 · 2026/2027');
    expect(p.attendanceTarget!.id, 2);
    expect(p.pastVersion, isFalse);
    expect(CourseProfile(payload('instructor', past: true)).pastVersion, isTrue);
    expect(CourseProfile(payload('instructor', past: true)).attendanceTarget, isNull);
    expect(CourseProfile(payload('student')).grade!['letter'], 'B+');
    // TA: sections only (no lecture attendance in this payload)
    expect(CourseProfile(payload('ta')).attendableSessions.map((s) => s.id).toList(), [4, 5]);
    // markable = started (or within the hour), newest first: lectures 1, 2 (3 is in 4 days)
    final ids = cpMarkableSessions(p).map((s) => s.id).toSet();
    expect(ids.containsAll({1, 2, 4}) && !ids.contains(3) && !ids.contains(5), isTrue);
  });

  test('status pill', () {
    expect(cpStatus(CourseProfile(payload('student', closed: true))), 'archived');
    expect(cpStatus(CourseProfile(payload('student'))), 'live');           // session 1 is live
    final up = payload('student');
    (up['tracks'] as Map)['lecture'] = [session(9, 'lecture', days: 3)];
    (up['tracks'] as Map)['section'] = <Map<String, dynamic>>[];
    expect(cpStatus(CourseProfile(up)), 'upcoming');
    expect(cpAudienceLabel('section').$2, 'Sections & labs');
  });

  test('continue / stats / attendance helpers', () {
    final p = CourseProfile(payload('student'));
    expect(cpContinue(p)!.id, 2);                           // first session with unfinished material
    final s = cpMaterialStats(p);
    expect((s.materials, s.videos, s.done), (8, 4, 2));
    final a = CpAttendance(attendance(true));
    expect(a.byRisk.first['absence_pct'], 25.0);
    expect(a.filtered('section').length, 2);
    expect(cpErrorText('bad_code'), isNotNull);
    expect(cpScopeLabel('section').$2, 'Sections & labs');
  });

  for (final role in ['instructor', 'admin', 'student', 'ta']) {
    for (final tab in ['overview', 'lecture', 'section', 'announcements', 'certificates', 'team']) {
      if ((role == 'ta' || role == 'admin') && tab == 'certificates') continue;
      if (role == 'student' && tab == 'team') continue;
      testWidgets('course profile $role / $tab', (tester) async {
        await expectNoLayoutErrors(
            tester, () => CourseProfileScreen(courseId: 7, initial: payload(role), initialTab: tab), scaffold: false);
      });
    }
  }

  testWidgets('expanded session card with material', (tester) async {
    await expectNoLayoutErrors(tester,
        () => CourseProfileScreen(courseId: 7, initial: payload('student'), initialTab: 'lecture'),
        scaffold: false, act: (t) async {
      final f = find.byIcon(Icons.expand_more_rounded);
      if (f.evaluate().isNotEmpty) await t.tap(f.first, warnIfMissed: false);
    });
  });

  testWidgets('earlier version (instructor) overview + attendance', (tester) async {
    for (final tab in ['overview', 'lecture']) {
      await expectNoLayoutErrors(tester,
          () => CourseProfileScreen(courseId: 7, initial: payload('instructor', past: true), initialTab: tab), scaffold: false);
    }
  });

  testWidgets('versions in the archive tab (TA)', (tester) async {
    await expectNoLayoutErrors(tester,
        () => CourseProfileScreen(courseId: 7, initial: payload('ta'), initialTab: 'archive'), scaffold: false);
  });

  testWidgets('manual attendance sheet', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => CpManualAttendanceSheet(courseId: 7, sessionId: 2, initial: {
              'session': {'id': 2, 'name': '$longAr 2', 'track': 'lecture', 'scheduled_at': iso(DateTime.now())},
              'students': [
                for (var i = 0; i < 6; i++)
                  {'user': {'id': i, 'name': i.isEven ? longAr : longEn}, 'present': i < 3, 'manual': i == 1},
              ],
              'present': 3,
            }));
  });

  testWidgets('archive: closed course (student, code) and staff policy', (tester) async {
    await expectNoLayoutErrors(tester,
        () => CourseProfileScreen(courseId: 7, initial: payload('student', closed: true), initialTab: 'archive'), scaffold: false);
    await expectNoLayoutErrors(tester,
        () => CourseProfileScreen(courseId: 7, initial: payload('instructor'), initialTab: 'archive'), scaffold: false);
  });

  for (final staff in [true, false]) {
    testWidgets('attendance tab (staff: $staff)', (tester) async {
      final p = CourseProfile(payload(staff ? 'instructor' : 'student'));
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: CpAttendanceTab(profile: p, initial: attendance(staff))));
    });
  }
}
