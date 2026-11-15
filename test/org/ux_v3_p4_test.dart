// UX v3 phase 4: role-based homes (lib/features/org/home/org_home_persona.dart + org_dashboard_home.dart).
//   • orgHomePersona: the decision table (admin · dean · head · staff · teacher · student, several at once)
//   • OrgPersonaStore: the default (highest responsibility) and the remembered choice per user + organization
//   • orgPersonaSections / orgPersonaMore / orgFlowPicks: each persona's blocks, More, the preview rows
//   • every persona's home (OrgHomeBody with its blocks) and the switcher through expectNoLayoutErrors
//   • the quick-reply sheet posts the canned text as a comment (FakeApi)
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/org/home/org_home_persona.dart';
import 'package:flutter_education_app/features/org/home/org_home_tasks.dart';
import 'package:flutter_education_app/features/org/org_attention_flow.dart';
import 'package:flutter_education_app/features/org/org_dashboard_home.dart';
import 'package:flutter_education_app/features/org/org_dashboard_model.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';
import '../ui/org_home_v3_layout_test.dart' show adminPayload, memberPayload, wrapProviders;

AttentionFlow _flow() => AttentionFlow.fromJson({
      'new_requests': [
        {'id': 31, 'ref': 'REQ-31', 'title': 'Room change for section 4', 'status': 'open', 'unit': 'Student affairs'},
      ],
      'votes_waiting': [
        {'session_id': 9, 'council': 'Department council', 'item_id': 70, 'title': 'Approve the new elective', 'deadline': null},
      ],
      'overdue': [
        {'id': 12, 'ref': 'REQ-12', 'title': 'Transcript for a transfer', 'status': 'open', 'unit': 'Registrar', 'overdue': true},
      ],
      'assigned_to_me': [
        {'id': 12, 'ref': 'REQ-12', 'title': 'Transcript for a transfer', 'status': 'open', 'unit': 'Registrar', 'overdue': true},
        {'id': 15, 'ref': 'REQ-15', 'title': 'Enrollment certificate', 'status': 'open', 'unit': 'Registrar'},
      ],
      'acting_units': const [],
    });

List<OrgAttentionSpec> _links(int n) => [
      for (var i = 0; i < n; i++)
        orgLinkRow(Icons.apartment_rounded, AppConfig.lang == 'ar' ? 'رابط رقم $i بعنوان طويل نوعاً ما' : 'A link number $i with a rather long title', () {},
            subtitle: AppConfig.lang == 'ar' ? 'سطر يشرح الوجهة' : 'A line that says where it goes', count: i == 1 ? 3 : 0),
    ];

/// The persona's home the way OrgHomePage composes it, with plain values.
Widget _home(OrgPersona p, {List<OrgPersona>? held}) {
  final admin = p == OrgPersona.admin;
  final d = OrgHomeData.fromJson(admin ? adminPayload() : memberPayload())!;
  final all = held ?? [p];
  return wrapProviders(
    OrgHomeBody(
      data: d,
      persona: p,
      header: OrgPageHeader(title: AppConfig.lang == 'ar' ? 'الرئيسية' : 'Home', subtitle: orgPersonaLabel(p)),
      switcher: all.length < 2 ? null : OrgPersonaSwitcher(held: all, current: p, onChanged: (_) {}),
      alerts: [for (final a in d.alerts) ?OrgAttentionSpec.of(a, () {})],
      live: p == OrgPersona.staff || p == OrgPersona.teacher
          ? OrgRowsCard(margin: EdgeInsets.zero, children: [
              for (final x in orgFlowPicks(_flow(), p))
                OrgAlertRow(
                  spec: OrgAttentionSpec(
                    icon: Icons.assignment_ind_rounded,
                    severity: x.late ? 'warning' : 'info',
                    title: x.title,
                    subtitle: x.place,
                    action: 'Open',
                    onTap: () {},
                    trailing: x.replyable ? IconButton(tooltip: 'Quick reply', icon: const Icon(Icons.quickreply_outlined), onPressed: () {}) : null,
                  ),
                ),
            ])
          : null,
      onTaskAction: (_, _) {},
      onOpenTask: (_) {},
      onSeeAllTasks: () {},
      onOpenUnit: (_) {},
      setup: admin ? const SizedBox(height: 120, child: Placeholder()) : null,
      faculty: p == OrgPersona.dean ? const SizedBox(height: 96, child: Placeholder()) : null,
      blocks: {
        if (p == OrgPersona.dean || p == OrgPersona.head)
          OrgHomeBlock.councils: OrgHomeLinksSection(id: 't.councils', title: 'Councils', links: _links(3)),
        if (p == OrgPersona.teacher) OrgHomeBlock.myCourses: OrgHomeLinksSection(id: 't.courses', title: 'My teaching', links: _links(2)),
        OrgHomeBlock.more: OrgHomeLinksSection(id: 't.more', title: 'More', links: _links(6), max: 4),
      },
    ),
    admin: admin,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    OrgPersonaStore.instance.reset();
  });

  group('orgHomePersona: the decision table', () {
    test('admin by access or by my_role; teaching on top of it', () {
      final a = orgHomePersona(access: 'admin');
      expect(a.primary, OrgPersona.admin);
      expect(a.held, [OrgPersona.admin]);
      final b = orgHomePersona(myRole: 'org_admin', memberRole: 'teacher');
      expect(b.primary, OrgPersona.admin);
      expect(b.held, [OrgPersona.admin, OrgPersona.teacher]);
      expect(orgHomePersona(myRole: 'platform_admin').primary, OrgPersona.admin);
    });

    test('dean = the faculty overview without admin; an admin never holds dean', () {
      final d = orgHomePersona(access: 'staff', myRole: 'teacher', memberRole: 'teacher', facultyOverview: true);
      expect(d.primary, OrgPersona.dean);
      expect(d.held, [OrgPersona.dean, OrgPersona.teacher]);
      expect(orgHomePersona(access: 'admin', facultyOverview: true).held, [OrgPersona.admin]);
    });

    test('head: the server list wins over the approve right; a head who teaches holds both', () {
      final h = orgHomePersona(access: 'staff', memberRole: 'teacher', deptApprover: true);
      expect(h.primary, OrgPersona.head);
      expect(h.held, [OrgPersona.head, OrgPersona.teacher]);
      expect(orgHomePersona(access: 'staff', memberRole: 'teacher', headUnitIds: const [], deptApprover: true).held, [OrgPersona.teacher]);
      expect(orgHomePersona(access: 'member', memberRole: 'teacher', headUnitIds: const [3]).primary, OrgPersona.head);
    });

    test('staff, teacher, student and the fallback', () {
      expect(orgHomePersona(access: 'staff', memberRole: 'admin_assistant').held, [OrgPersona.staff]);
      expect(orgHomePersona(access: 'member', memberRole: 'teacher_assistant').held, [OrgPersona.teacher]);
      expect(orgHomePersona(access: 'member', memberRole: 'student').held, [OrgPersona.student]);
      // a member without a role or rights: the calm staff home
      expect(orgHomePersona(access: 'member').held, [OrgPersona.staff]);
      expect(orgHomePersona().primary, OrgPersona.staff);
    });

    test('the signals: department approve rights, the head units the server may send', () {
      expect(orgDeptApprover(null), isFalse);
      expect(orgDeptApprover({'3': {'team': ['view']}}), isFalse);
      expect(orgDeptApprover({'3': {'workflow': ['view', 'approve']}}), isTrue);
      expect(orgHeadUnitIds(null), isNull);
      expect(orgHeadUnitIds({'x': 1}), isNull);
      expect(orgHeadUnitIds({'head_unit_ids': [3, '4', 0]}), [3, 4]);
      expect(orgHeadUnitIds({'head_units': [{'id': 5}, {'id': null}]}), [5]);
      expect(orgIsInstitutionItem({'type': 'faculty'}), isTrue);
      expect(orgIsInstitutionItem({'type': 'school'}), isFalse);
      expect(orgIsInstitutionItem({'type': 'center', 'study_system': 'credit_hours'}), isTrue);
    });
  });

  group('the switcher: default and remembered choice', () {
    test('default = the highest responsibility; a stored persona no longer held falls back', () {
      expect(orgPersonaDefault([OrgPersona.head, OrgPersona.teacher], null), OrgPersona.head);
      expect(orgPersonaDefault([OrgPersona.head, OrgPersona.teacher], 'teacher'), OrgPersona.teacher);
      expect(orgPersonaDefault([OrgPersona.teacher], 'head'), OrgPersona.teacher);
      expect(orgPersonaDefault(const [], null), OrgPersona.staff);
    });

    test('remembered per user + organization, and read back after a restart', () async {
      final s = OrgPersonaStore.instance;
      const held = [OrgPersona.head, OrgPersona.teacher];
      await s.ensureLoaded();
      expect(s.pick(7, 4, held), OrgPersona.head);
      await s.choose(7, 4, OrgPersona.teacher);
      expect(s.pick(7, 4, held), OrgPersona.teacher);
      expect(s.pick(7, 5, held), OrgPersona.head, reason: 'another organization keeps its default');
      expect(s.pick(8, 4, held), OrgPersona.head, reason: 'another user keeps the default');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(OrgPersonaStore.keyFor(7, 4)), 'teacher');
      s.reset();
      await s.ensureLoaded();
      expect(s.pick(7, 4, held), OrgPersona.teacher);
    });
  });

  group('each persona\'s home', () {
    test('sections: what needs me first, More last, at most four', () {
      for (final p in OrgPersona.values) {
        final x = orgPersonaSections(p);
        expect(x.length, lessThanOrEqualTo(4), reason: '$p');
        expect(x.last, OrgHomeBlock.more, reason: '$p');
      }
      expect(orgPersonaSections(OrgPersona.admin), [OrgHomeBlock.needsMe, OrgHomeBlock.setup, OrgHomeBlock.insights, OrgHomeBlock.more]);
      expect(orgPersonaSections(OrgPersona.dean), [OrgHomeBlock.needsMe, OrgHomeBlock.faculty, OrgHomeBlock.councils, OrgHomeBlock.more]);
      expect(orgPersonaSections(OrgPersona.head), [OrgHomeBlock.needsMe, OrgHomeBlock.team, OrgHomeBlock.councils, OrgHomeBlock.more]);
      expect(orgPersonaSections(OrgPersona.staff), [OrgHomeBlock.needsMe, OrgHomeBlock.queue, OrgHomeBlock.more]);
      expect(orgPersonaSections(OrgPersona.teacher), [OrgHomeBlock.needsMe, OrgHomeBlock.myCourses, OrgHomeBlock.more]);
      expect(orgPersonaSections(OrgPersona.student).first, OrgHomeBlock.journey);
    });

    test('More: Needs my action for every staff persona; figures only for admin and dean', () {
      for (final p in OrgPersona.values.where((p) => p != OrgPersona.student)) {
        expect(orgPersonaMore(p).first, 'needs_action', reason: '$p');
        expect(orgPersonaMore(p), contains('settings'), reason: '$p');
      }
      expect(orgPersonaMore(OrgPersona.admin), containsAll(['departments', 'members', 'health', 'wizard']));
      expect([for (final p in OrgPersona.values) if (orgPersonaShowsFigures(p)) p], [OrgPersona.admin, OrgPersona.dean]);
      expect([for (final p in OrgPersona.values) if (orgPersonaOpensActionInbox(p)) p], [OrgPersona.staff, OrgPersona.teacher]);
    });

    test('preview rows: a teacher\'s votes first; staff get assigned, overdue, new, each once', () {
      final f = _flow();
      final teacher = orgFlowPicks(f, OrgPersona.teacher);
      expect([for (final x in teacher) (x.vote, x.id)], [(true, 9), (false, 12), (false, 15)]);
      expect(teacher.first.replyable, isFalse);
      final staff = orgFlowPicks(f, OrgPersona.staff, max: 5);
      expect([for (final x in staff) x.id], [12, 15, 31]);
      expect(staff.first.late, isTrue);
      expect(orgFlowPicks(f, OrgPersona.head), isEmpty);
      expect(orgFlowPicks(null, OrgPersona.staff), isEmpty);
    });
  });

  group('layout', () {
    for (final p in OrgPersona.values.where((p) => p != OrgPersona.student)) {
      testWidgets('the ${p.name} home', (tester) async {
        await expectNoLayoutErrors(tester, () => _home(p, held: p == OrgPersona.head ? const [OrgPersona.head, OrgPersona.teacher] : null), frames: 4);
      });
    }

    testWidgets('the switcher: chips for each persona, nothing for one', (tester) async {
      OrgPersona? chosen;
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: OrgPersonaSwitcher(
                  held: const [OrgPersona.admin, OrgPersona.dean, OrgPersona.head, OrgPersona.teacher], current: OrgPersona.dean, onChanged: (p) => chosen = p)),
          act: (t) async {
        expect(find.byKey(const ValueKey('org.persona.head')), findsOneWidget);
      });
      AppConfig.lang = 'en';
      await tester.pumpWidget(layoutHost(OrgPersonaSwitcher(held: const [OrgPersona.head, OrgPersona.teacher], current: OrgPersona.head, onChanged: (p) => chosen = p)));
      await tester.tap(find.byKey(const ValueKey('org.persona.teacher')));
      expect(chosen, OrgPersona.teacher);
      await tester.pumpWidget(layoutHost(OrgPersonaSwitcher(held: const [OrgPersona.teacher], current: OrgPersona.teacher, onChanged: (_) {})));
      expect(find.byType(Wrap), findsNothing);
    });

    testWidgets('quick reply: the canned text goes out as a comment', (tester) async {
      Object? sent;
      final api = FakeApi({
        'POST /api/v1/org/orgs/4/governance/items/15/comments': (o) {
          sent = o.data;
          return {'id': 1};
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(api.uninstall);
      AppConfig.lang = 'en';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      bool? ok;
      await tester.pumpWidget(layoutHost(Builder(
          builder: (context) => TextButton(onPressed: () async => ok = await showOrgQuickReply(context, orgId: 4, itemId: 15), child: const Text('reply')))));
      await tester.tap(find.text('reply'));
      await tester.pumpAndSettle();
      expect(find.text('Quick reply'), findsOneWidget);
      await tester.tap(find.text(orgQuickReplies.first.$2));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ok, isTrue);
      expect('$sent', contains(orgQuickReplies.first.$2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
