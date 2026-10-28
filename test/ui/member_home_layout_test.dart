// Organization member home (Track B.4): OrgMemberHomeBody at 320x640 and 1400x900, Arabic + English,
// textScaler 1.3 — a teacher-admin with everything (today, inbox rows, decisions, departments, grouped quick
// actions + the "More" sheet), a plain student with an empty day, an older server (fallback slots), no organization.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا';
const longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research, Faculty of Engineering';

final now = DateTime.utc(2026, 10, 28, 9, 0);

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> event(String id, Duration from, Duration to, {String source = 'timetable', String? kind}) => {
      'id': id,
      'source': source,
      'title': '$longAr $longEn',
      'subtitle': longEn,
      'starts_at': iso(now.add(from)),
      'ends_at': iso(now.add(to)),
      'org_id': 4,
      'org': {'id': 4, 'name_ar': longAr, 'name_en': longEn},
      'kind': kind,
      'location': 'Room 12',
    };

Map<String, dynamic> inboxRow(String key, {String segment = 'todo'}) => {
      'key': key,
      'kind': 'form',
      'segment': segment,
      'title': '$longAr $longEn',
      'subtitle': longEn,
      'org_id': 4,
      'organization': {'id': 4, 'name_ar': longAr, 'name_en': longEn},
      'due_at': iso(now.add(const Duration(hours: 30))),
      'created_at': iso(now.subtract(const Duration(hours: 1))),
      'mandatory': true,
    };

final org = {'id': 4, 'status': 'approved', 'type': 'university', 'name_ar': longAr, 'name_en': longEn, 'color': '#3366CC'};

Map<String, dynamic> teacherAdmin() => {
      'organization': org,
      'roles': ['student', 'teacher', 'teacher_assistant'],
      'manage': {
        'is_admin': true,
        'permissions': {},
        'departments': [
          {'id': 1, 'name_ar': longAr, 'name_en': longEn, 'via': 'dept', 'modules': {'forms': ['view', 'approve'], 'complaints': ['view']}},
          {'id': 2, 'name_ar': 'ق', 'name_en': 'D', 'via': 'dept', 'modules': {}},
        ],
        'sub_orgs': [
          {'id': 5, 'type': 'faculty', 'status': 'approved', 'name_ar': longAr, 'name_en': longEn},
          {'id': 6, 'type': 'faculty', 'status': 'pending', 'name_ar': 'ك', 'name_en': 'F'},
        ],
      },
      'todo': {'total': 1234, 'overdue': 3, 'due_soon': 40},
      'approvals': {'total': 56, 'form_responses': 20, 'complaints': 30, 'overdue_complaints': 2, 'assigned_to_me': 5, 'join_requests': 4, 'unit_requests': 2},
      'news': 7890,
    };

Map<String, dynamic> student() => {
      'organization': {...org, 'status': 'pending'},
      'roles': ['student'],
      'manage': null,
      'todo': {'total': 0},
      'approvals': {'total': 0},
      'news': 0,
    };

List<Map<String, dynamic>> today() => [
      event('a', const Duration(hours: -3), const Duration(hours: -2)),
      event('b', const Duration(minutes: -10), const Duration(minutes: 50), kind: 'lab'),
      event('c', const Duration(hours: 3), const Duration(hours: 4), source: 'exam'),
    ];

Widget body(OrgMemberHomeBody b) => SingleChildScrollView(child: b);

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.orgsEnabled = true;
    AppModeController.applyContext = (_) {};
  });

  testWidgets('member home: teacher-admin with everything, and the "More" sheet of a quick-action group', (tester) async {
    final me = MeHome.fromJson({'today': today(), 'inbox_preview': [inboxRow('f1'), inboxRow('f2'), inboxRow('n1', segment: 'news')]});
    Finder more() => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('quick.more.'));
    await expectNoLayoutErrors(
      tester,
      () => body(OrgMemberHomeBody(
        entry: teacherAdmin(),
        showPicker: true,
        today: me.todayOf(4),
        inbox: me.inboxPreviewOf(4),
        now: now,
        onPick: () {},
        onOpenEvent: (_) {},
        onOpenInboxItem: (_) {},
      )),
      act: (t) async {
        expect(more(), findsWidgets, reason: 'My studies has more than 6 actions for a student-teacher');
        await t.ensureVisible(more().first);
        await t.tap(more().first);
      },
    );
  });

  testWidgets('member home: a student with an empty day, under review; an older server keeps the fallback slots', (tester) async {
    await expectNoLayoutErrors(tester, () => body(OrgMemberHomeBody(entry: student(), today: const [], inbox: const [], now: now)));
    // today / inbox unknown (no /me/home) → the fallback widgets take the slots (here placeholders)
    await expectNoLayoutErrors(
      tester,
      () => body(OrgMemberHomeBody(
        entry: student(),
        now: now,
        todayFallback: const SizedBox(height: 80),
        inboxFallback: const SizedBox(height: 80),
        news: const SizedBox(height: 60),
      )),
    );
  });

  testWidgets('member home: no organization', (tester) async {
    AppModeController.instance.debugSet({'items': []}, mode: AppMode.organization);
    await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: OrgMemberHome()));
  });

  testWidgets('quick actions are grouped, at most 6 pills a group, the rest behind "More"', (tester) async {
    late List<OrgQuickGroup> groups;
    await tester.pumpWidget(layoutHost(Builder(builder: (context) {
      groups = orgQuickGroups(context, teacherAdmin());
      return const SizedBox();
    })));
    expect(groups.length, 4);
    expect(groups.map((g) => g.actions.length).reduce((a, b) => a > b ? a : b), greaterThan(orgQuickPillsMax));
    // a plain student has no "Manage" group
    await tester.pumpWidget(layoutHost(Builder(builder: (context) {
      groups = orgQuickGroups(context, student());
      return const SizedBox();
    })));
    expect(groups.length, 3);
    expect(groups.every((g) => g.actions.isNotEmpty), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
