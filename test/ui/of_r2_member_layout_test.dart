// Agent r2: no overflow on any size / language / text scale for the redesigned member screens — the shared pieces
// (MemberRow · MemberNote · MemberSlotTile · MemberStatusBadge), the member home without its hero (standalone page),
// the member space tabs (departments · requests · complaints, over a fake server) and the "My organization" tab.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_education_app/features/org/org_member_parts.dart';
import 'package:flutter_education_app/features/org/org_member_space.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';
import 'member_home_layout_test.dart' as home;

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة والتكنولوجيا — Office of Student Affairs, Graduate Studies and Scientific Research';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.lang = 'en';
    AppConfig.orgsEnabled = true;
    AppModeController.applyContext = (_) {};
  });

  test('memberStatusTone maps the status codes', () {
    expect(memberStatusTone('approved'), AppTone.success);
    expect(memberStatusTone('submitted'), AppTone.warning);
    expect(memberStatusTone('rejected'), AppTone.danger);
    expect(memberStatusTone('in_progress'), AppTone.info);
    expect(memberStatusTone('whatever'), AppTone.neutral);
  });

  testWidgets('MemberRow variants', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          const MemberRow(icon: Icons.fact_check_rounded, title: _long, subtitle: _long, count: 1234, onTap: _noop),
          const MemberRow(icon: Icons.fact_check_rounded, title: 'Short'),
          MemberRow(icon: Icons.receipt_long_rounded, title: _long, subtitle: 'REQ-1\n$_long', trailing: const MemberStatusBadge('approved', label: _long)),
        ]),
      ),
    );
  });

  testWidgets('MemberNote and MemberSlotTile', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: Column(children: [
          const MemberNote(_long),
          MemberSlotTile(start: '10:00 AM', end: '11:30 AM', title: _long, where: _long, tags: [
            AppStatusBadge(label: _long, tone: AppTone.warning, dense: true),
            const AppStatusBadge(label: 'Lab', dense: true),
          ]),
          const MemberSlotTile(start: '9:00 AM', end: '', title: 'Cancelled', cancelled: true),
        ]),
      ),
    );
  });

  testWidgets('member home without the hero (standalone page)', (tester) async {
    final me = MeHome.fromJson({'today': home.today(), 'inbox_preview': [home.inboxRow('f1'), home.inboxRow('f2'), home.inboxRow('n1', segment: 'news')]});
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: OrgMemberHomeBody(
          entry: home.teacherAdmin(),
          showHero: false,
          today: me.todayOf(4),
          inbox: me.inboxPreviewOf(4),
          now: home.now,
          onOpenEvent: (_) {},
        ),
      ),
    );
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: OrgMemberHomeBody(entry: home.student(), showHero: false, today: const [], inbox: const [], now: home.now)));
  });

  group('over a fake server', () {
    late FakeApi fake;
    setUp(() {
      mockRequestPlugins();
      fake = FakeApi({
        'GET /api/v1/home/mix': (_) => {
              'org_weight': 70,
              'organizations': [home.org],
              'required': [
                {'kind': 'form', 'id': 9, 'org_id': 4, 'title': _long}
              ],
            },
        'GET /api/v1/org/public/schedule/me': (_) => {
              'items': [
                {
                  'items': [
                    {'slot_id': 1, 'day': 'monday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 2, 'day': 'tuesday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 3, 'day': 'wednesday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 4, 'day': 'thursday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 5, 'day': 'friday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 6, 'day': 'saturday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long},
                    {'slot_id': 7, 'day': 'sunday', 'start_time': '09:00', 'end_time': '10:30', 'course': _long, 'room': _long, 'kind': 'lab'},
                  ],
                  'extras': [],
                }
              ]
            },
        'GET /api/v1/org/public/4/departments': (_) => {
              'items': [
                {'id': 1, 'name_ar': _long, 'name_en': _long, 'description': _long, 'location': _long, 'office_hours': _long, 'email': 'a@b.c', 'phone': '+20', 'accepts_complaints': true, 'features': ['forms', 'complaints']},
              ]
            },
        'GET /api/v1/org/public/me/forms': (_) => {
              'items': [
                {'id': 1, 'title': _long, 'can_answer': true, 'closes_at': '2026-11-30T00:00:00', 'department': {'name_ar': _long, 'name_en': _long}},
                {'id': 2, 'title': _long, 'can_answer': false},
              ]
            },
        'GET /api/v1/org/public/me/form-responses': (_) => {
              'items': [
                {'org_id': 4, 'form_title': _long, 'ref': 'REQ-1', 'status': 'rejected', 'created_at': '2026-11-02T08:00:00', 'reviewer_note': _long},
              ]
            },
        'GET /api/v1/org/public/me/complaints': (_) => {
              'items': [
                {'id': 1, 'org_id': 4, 'subject': _long, 'ref': 'CMP-7', 'status': 'in_progress', 'unread': true, 'updated_at': '2026-11-03T08:00:00'},
              ]
            },
      }, latency: Duration.zero, fallback: (_) => {'items': const [], 'total': 0});
      fake.install();
    });
    tearDown(() => fake.uninstall());

    Future<void> more(WidgetTester t) async {
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    for (final (tab, name) in [(0, 'news'), (1, 'departments'), (2, 'requests'), (3, 'complaints'), (4, 'regulations')]) {
      testWidgets('member space: $name', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession(), child: OrgMemberSpace(org: home.org, initialTab: tab)),
          scaffold: false,
          act: more,
        );
      });
    }

    testWidgets('the My organization tab', (tester) async {
      await expectNoLayoutErrors(tester, () => const SingleChildScrollView(child: OrgHomeTab()), act: more);
    });
  });
}

void _noop() {}
