// UX v3 phase 6 (polish):
//   • the org fix actions: open_members · open_agenda · setup_councils decided (orgFixOf), registered app-wide (an
//     AppErrorBox carrying one gets the button), a screen's own AppFixScope wins (the archive sheet's pick_reassign)
//   • the archive view: the refusal as an AppErrorBox with "Choose the unit" / "Open the council's agenda"
//   • heads and deans: "Needs my action" opens the action inbox, their flow page stays under More
//   • the wizard's heads step finds an off-screen refused row (headsFirstErrorFraction)
//   • semantics: the action banner and the error box announce once; an inbox row is one button with its words
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/notif_link.dart';
import 'package:flutter_education_app/design/action_banner.dart';
import 'package:flutter_education_app/design/app_errors.dart';
import 'package:flutter_education_app/features/org/home/org_home_persona.dart';
import 'package:flutter_education_app/features/org/needs_my_action_page.dart';
import 'package:flutter_education_app/features/org/org_fix_actions.dart';
import 'package:flutter_education_app/features/org/org_institution_wizard.dart' show HeadUnit, headsFirstErrorFraction;
import 'package:flutter_education_app/features/org/org_unit_rules.dart' show DeptArchiveView, DeptImpact;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

ApiException _err(int status, String code, {String? action, Map<String, dynamic> extra = const {}}) => ApiException(
      statusCode: status,
      message: code,
      type: status == 409 ? ApiErrorType.conflict : ApiErrorType.validation,
      code: code,
      body: {
        'detail': {'code': code, 'message': code, 'message_en': code, 'fix_action': ?action, ...extra},
      },
    );

Future<void> _pump(WidgetTester tester, Widget w) async {
  await tester.pumpWidget(layoutHost(SingleChildScrollView(child: w)));
  await tester.pump();
}

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('org fix actions', () {
    test('orgFixOf: where each fix goes', () {
      expect(orgFixOf(_err(422, 'head_invalid', action: 'open_members')), (fix: OrgFix.members, councilId: null));
      expect(orgFixOf(_err(422, 'not_staff_member', action: 'open_members', extra: {'council_id': 9})), (fix: OrgFix.councilRoster, councilId: 9));
      expect(
          orgFixOf(_err(409, 'council_has_open_agenda', action: 'open_agenda', extra: {
            'councils': [
              {'id': 12, 'name': 'Faculty council', 'open_agenda_items': 2},
            ],
          })),
          (fix: OrgFix.councilAgenda, councilId: 12));
      expect(orgFixOf(_err(409, 'council_has_open_agenda', action: 'open_agenda', extra: {'open_agenda_items': 3})),
          (fix: OrgFix.councilsList, councilId: null));
      expect(orgFixOf(_err(422, 'no_council', action: 'setup_councils')), (fix: OrgFix.councilsSetup, councilId: null));
      expect(orgFixOf(_err(409, 'dept_has_open_items', action: 'pick_reassign')), isNull, reason: 'screen-local only');
      expect(orgFixOf(_err(422, 'x')), isNull);
    });

    test('registered app-wide (idempotent); labels in both languages', () {
      registerOrgFixActions();
      registerOrgFixActions();
      for (final a in orgFixActions) {
        expect(AppFixActions.has(a), isTrue, reason: a);
      }
      expect(AppFixActions.has(orgPickReassignAction), isFalse);
      expect(appSharedFix(_err(422, 'head_invalid', action: 'open_members'))?.$2, 'Open Members');
      expect(appSharedFix(_err(422, 'no_council', action: 'setup_councils'))?.$2, 'Open the councils setup');
      AppConfig.lang = 'ar';
      expect(orgFixLabel(OrgFix.councilAgenda), 'افتح جدول أعمال المجلس');
      AppConfig.lang = 'en';
      expect(appSharedFix(_err(422, 'x', action: 'unknown_action')), isNull);
    });

    testWidgets('an AppErrorBox with a registered fix_action draws its button', (tester) async {
      registerOrgFixActions();
      await _pump(tester, AppErrorBox(error: _err(422, 'not_staff_member', action: 'open_members', extra: {'council_id': 4})));
      expect(find.byKey(const ValueKey('app_error_fix')), findsOneWidget);
      expect(find.text('Open the council members'), findsOneWidget);
    });

    testWidgets("a screen's AppFixScope wins over the app-wide fix", (tester) async {
      var local = 0;
      await _pump(
          tester,
          AppFixScope(
            fixes: {'open_agenda': (() => local++, 'Mine')},
            child: AppErrorBox(error: _err(409, 'council_has_open_agenda', action: 'open_agenda')),
          ));
      expect(find.text('Mine'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app_error_fix')));
      expect(local, 1);
    });
  });

  group('archive view', () {
    testWidgets('pick_reassign: the refusal offers "Choose the unit"; a blocked unit opens its agenda', (tester) async {
      var picks = 0, agendas = 0;
      final key = GlobalKey();
      Widget view(DeptImpact i, ApiException? e) => DeptArchiveView(
            name: 'Student Affairs',
            impact: i,
            targets: const [
              {'id': 4, 'name_en': 'Exams Control', 'name_ar': 'الكنترول'},
            ],
            reassignTo: null,
            onReassign: (_) {},
            onArchive: () {},
            apiError: e,
            error: e == null ? null : 'The unit has open requests',
            reassignKey: key,
            onPickReassign: () => picks++,
            onOpenAgenda: () => agendas++,
          );
      await _pump(tester, view(const DeptImpact(openItems: 2), _err(409, 'dept_has_open_items', action: 'pick_reassign')));
      expect(find.byKey(const ValueKey('dept.archive.error')), findsOneWidget);
      expect(find.text('Choose the unit'), findsOneWidget);
      expect(key.currentContext, isNotNull, reason: 'the picker carries the key the fix scrolls to');
      await tester.tap(find.byKey(const ValueKey('app_error_fix')));
      expect(picks, 1);

      await _pump(tester, view(const DeptImpact(openAgendaItems: 2), null));
      expect(find.byKey(const ValueKey('dept.archive.blocked')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dept.archive.open_agenda')));
      expect(agendas, 1);
    });

    testWidgets('no layout errors with the refusal box', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
                child: DeptArchiveView(
                  name: 'Student Affairs with a very long name that must wrap on a phone',
                  impact: const DeptImpact(openItems: 2, courses: 3, members: 12),
                  targets: const [
                    {'id': 4, 'name_en': 'Exams Control', 'name_ar': 'الكنترول'},
                  ],
                  reassignTo: null,
                  onReassign: (_) {},
                  onArchive: () {},
                  apiError: _err(409, 'dept_has_open_items', action: 'pick_reassign'),
                  error: 'The unit has open requests; choose a unit to move them to',
                  onPickReassign: () {},
                ),
              ));
    });
  });

  group('heads and deans', () {
    test('the entry row opens the action inbox; the flow page stays under More', () {
      expect([for (final p in OrgPersona.values) if (orgPersonaEntryOpensActionInbox(p)) p],
          [OrgPersona.dean, OrgPersona.head, OrgPersona.staff, OrgPersona.teacher]);
      // D-1081 moved the councils / votes links from the home into More, ahead of the flow page
      expect(orgPersonaMore(OrgPersona.head).first, 'needs_action');
      expect(orgPersonaMore(OrgPersona.head), contains('attention_flow'));
      // D-1081 moved the councils / votes links from the home into More, ahead of the flow page
      expect(orgPersonaMore(OrgPersona.dean).first, 'needs_action');
      expect(orgPersonaMore(OrgPersona.dean), contains('attention_flow'));
      expect(orgPersonaMore(OrgPersona.staff), isNot(contains('attention_flow')));
    });

    test('the wizard finds the first refused row in drawn order', () {
      const rows = [
        HeadUnit(id: 1, name: 'Service A'),
        HeadUnit(id: 2, name: 'Academic A', kind: 'academic'),
        HeadUnit(id: 3, name: 'Academic B', kind: 'academic'),
      ];
      expect(headsFirstErrorFraction(rows, {}), isNull);
      expect(headsFirstErrorFraction(rows, {2}), 0, reason: 'academic rows are drawn first');
      expect(headsFirstErrorFraction(rows, {1}), 1, reason: 'the service row is drawn last');
      expect(headsFirstErrorFraction(rows, {3, 1}), 0.5);
    });
  });

  group('semantics', () {
    testWidgets('the action banner announces what is asked, why, and its button', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester, ActionBanner(action: NotifAction.edit, reason: 'The date is missing', onAction: () {}));
      final node = tester.getSemantics(find.byKey(const ValueKey('action_banner')));
      expect(node.label, startsWith('Needs your edit. The date is missing'));
      expect(node.label, endsWith('Edit now'), reason: 'the headline, why, then the button once');
      expect('Edit now'.allMatches(node.label).length, 1);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      h.dispose();
    });

    testWidgets('the error box announces once, Fix before Retry', (tester) async {
      final h = tester.ensureSemantics();
      final e = ApiException(statusCode: 0, message: 'offline', type: ApiErrorType.network);
      await _pump(tester, AppErrorBox(error: e, onRetry: () {}, onFix: () {}, fixLabel: 'Fix it now'));
      final node = tester.getSemantics(find.byKey(const ValueKey('app_error_box')));
      expect(node.label, startsWith('No connection'));
      final fix = tester.getTopLeft(find.byKey(const ValueKey('app_error_fix')));
      final retry = tester.getTopLeft(find.byKey(const ValueKey('app_error_retry')));
      expect(fix.dx < retry.dx || fix.dy < retry.dy, isTrue);
      h.dispose();
    });

    testWidgets('an inbox row is one button with its words', (tester) async {
      final h = tester.ensureSemantics();
      var opened = 0;
      const x = ActionInboxItem(key: 'org_work:1', action: NotifAction.approve, title: 'Leave request', reasonEn: 'Waiting for you', overdue: true);
      await _pump(tester, NeedsMyActionRow(item: x, onOpen: (_) => opened++));
      expect(actionInboxRowSemantics(x), 'Leave request. Awaiting your approval: Waiting for you. Overdue');
      final node = tester.getSemantics(find.bySemanticsLabel(actionInboxRowSemantics(x)));
      expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
      await tester.tap(find.byKey(const ValueKey('action_inbox.org_work:1')));
      expect(opened, 1);
      h.dispose();
    });
  });
}
