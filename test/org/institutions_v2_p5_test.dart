// Institutions v2, phase 5 (docs/institutions/V2_PLAN.md item 5, D-994 – D-997): the roadmap UX. AppRoadmap /
// AppStatusPath draw every state with a word (never colour alone) and read "Step 2 of 5, …"; the journey parses
// defensively (the server's help keys, capped lists + counts), orders by urgency then date, folds "Can wait", and a
// contact's Message targets its unit; the attention flow shows its sections, opens rows and has a calm empty state;
// the admin roadmap comes from the wizard's stages (or derives them) and opens the wizard at a stage; every new
// widget lays out at 320×640 and 1400×900 in Arabic and English with text scale 1.3, and passes the a11y guidelines.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/org/org_attention_flow.dart';
import 'package:flutter_education_app/features/org/org_institution_roadmap.dart';
import 'package:flutter_education_app/features/org/org_institution_wizard.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart' show OrgMemberHomeBody;
import 'package:flutter_education_app/features/org/org_my_journey.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/a11y_guidelines_test.dart' show expectA11y;
import '../ui/layout_harness.dart';

Map<String, dynamic> _step(String key, {String severity = 'normal', String? due, String module = 'work_item', int? target = 7}) => {
      'key': key,
      'title_ar': 'خطوة $key',
      'title_en': 'Step $key with a title long enough to wrap on a small phone',
      'why_ar': 'لماذا $key',
      'why_en': 'Why $key matters, said in one calm sentence.',
      'action': {'module': module, 'target_id': ?target},
      'due_at': due,
      'severity': severity,
    };

Map<String, dynamic> _journey() => {
      'now': [
        _step('reply:1', due: '2026-11-20T10:00:00'),
        _step('ack:2', severity: 'urgent', due: '2026-11-25T10:00:00', module: 'message'),
        _step('form:3', severity: 'urgent', due: '2026-11-18T10:00:00', module: 'form'),
      ],
      'important': [_step('register', module: 'registrar', target: 4)],
      'later': [_step('meeting:5', module: 'advising_appointment'), _step('x:6', module: 'mystery')],
      'counts': {'now': 3, 'important': 1, 'later': 9},
      'requests': [
        {
          'id': 41,
          'ref': 'REQ-0041',
          'title': 'Enrolment letter for the embassy',
          'type': 'request',
          'status': 'in_review',
          'stage': 'reviewed',
          'stages': [
            {'key': 'submitted', 'at': '2026-11-10T09:00:00'},
            {'key': 'reviewed', 'at': '2026-11-12T09:00:00'},
            {'key': 'decided', 'at': null},
          ],
          'updated_at': '2026-11-12T09:00:00',
        },
        {'id': 0, 'title': 'dropped: no id'},
        {'id': 42, 'title': 'Old complaint', 'type': 'complaint', 'stage': 'decided', 'stages': []},
      ],
      'register': {'open': true, 'window': 'registration', 'window_ends_at': '2026-11-30', 'registered': false, 'term_id': 4, 'reason': null, 'action': {'module': 'registrar', 'target_id': 4}},
      'contacts': [
        {'kind': 'advisor', 'id': 90, 'name': 'Dr. Mona Adel', 'dept_id': null, 'can_message': false, 'action': {'module': 'advisor', 'target_id': 90}},
        {
          'kind': 'department',
          'id': 12,
          'name': 'شئون الطلاب',
          'name_en': 'Student Affairs',
          'core': true,
          'dept_id': 12,
          'can_message': true,
          'action': {'module': 'unit_message', 'target_id': 12, 'route': '/api/v1/org/public/governance/5/units/12/message'},
        },
        {'kind': 'head', 'id': 55, 'name': 'Prof. Hany', 'dept_id': 3, 'acting': true, 'can_message': false, 'action': {'module': 'unit', 'target_id': 3}},
        {'kind': 'department', 'name': ''},
      ],
      'help': {
        'file_request': {'module': 'new_request', 'route': '/api/v1/org/public/governance/5/items'},
        'file_complaint': {'module': 'new_complaint', 'route': '/api/v1/org/public/governance/5/items'},
      },
    };

Map<String, dynamic> _flow() => {
      'new_requests': [
        {'id': 11, 'ref': 'REQ-11', 'title': 'Transcript request', 'type': 'request', 'status': 'open', 'dept': {'id': 3, 'name_ar': 'الحاسب', 'name_en': 'Computer Science'}, 'due_at': '2026-11-20T10:00:00', 'overdue': false},
      ],
      'votes_waiting': [
        {'session_id': 8, 'agenda_item_id': 81, 'council': {'id': 2, 'name_ar': 'مجلس القسم', 'name_en': 'Department council'}, 'item_id': 11, 'title': 'Approve the new elective', 'deadline': '2026-11-19T12:00:00', 'action': {'module': 'council_vote', 'target_id': 8}},
        {'session_id': 0},
      ],
      'overdue': [
        {'id': 12, 'ref': 'REQ-12', 'title': 'Late complaint', 'dept': null, 'due_at': '2026-11-01T10:00:00', 'overdue': true},
      ],
      'assigned_to_me': <Map<String, dynamic>>[],
      'acting_units': [
        {'id': 3, 'name': 'قسم الحاسب', 'name_en': 'Computer Science', 'action': {'module': 'assign_head', 'target_id': 3}},
      ],
      'counts': {'new_requests': 14, 'votes_waiting': 1, 'overdue': 1, 'assigned_to_me': 0, 'acting_units': 1},
      'total': 17,
    };

Map<String, dynamic> _wizard({List<Map<String, dynamic>>? stages, String? launchedAt, String step = 'heads', List<String> done = const ['basics', 'departments']}) => {
      'step': step,
      'done': done,
      'launched_at': launchedAt,
      'applicable': true,
      'readiness': {
        'ok': false,
        'blocking': 1,
        'items': [
          {'key': 'heads_missing', 'severity': 'block', 'count': 2, 'text_en': '2 units have no head', 'text_ar': 'وحدتان بلا رئيس', 'action': 'heads'},
          {'key': 'council_no_secretary', 'severity': 'warn', 'count': 1, 'text_en': 'A council has no secretary', 'action': 'councils'},
        ],
      },
      'stages': ?stages,
    };

List<Map<String, dynamic>> _stages() => [
      {'key': 'basics', 'state': 'done', 'count_warn': 0, 'blocking': 0},
      {'key': 'departments', 'state': 'done', 'count_warn': 0, 'blocking': 0},
      {'key': 'heads', 'state': 'current', 'count_warn': 2, 'blocking': 1},
      {'key': 'councils', 'state': 'warn', 'count_warn': 1, 'blocking': 0},
      {'key': 'launch', 'state': 'todo', 'count_warn': 0, 'blocking': 0},
      {'key': 'bogus', 'state': 'done'},
    ];

Widget _scroll(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(AppSpace.md), child: child);

Future<void> _pump(WidgetTester tester, Widget child, {Size size = const Size(390, 2400)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(layoutHost(child, scale: 1));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _nodes = [
  AppRoadmapNode(id: 'a', title: 'Basics', state: AppRoadmapState.done),
  AppRoadmapNode(id: 'b', title: 'Departments', state: AppRoadmapState.warn, subtitle: '1 thing worth a look'),
  AppRoadmapNode(id: 'c', title: 'Heads', state: AppRoadmapState.current, subtitle: 'A head for every unit', actionLabel: 'Open this step'),
  AppRoadmapNode(id: 'd', title: 'Councils'),
  AppRoadmapNode(id: 'e', title: 'Launch'),
];

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    OrgJourneyStore.instance.reset();
    AttentionFlowStore.instance.reset();
  });

  group('AppRoadmap / AppStatusPath', () {
    test('next node, direction, labels', () {
      expect(appRoadmapNextIndex(_nodes), 2); // current wins over the earlier warn
      expect(appRoadmapNextIndex(const [AppRoadmapNode(title: 'x', state: AppRoadmapState.done), AppRoadmapNode(title: 'y', state: AppRoadmapState.warn)]), 1);
      expect(appRoadmapNextIndex(const [AppRoadmapNode(title: 'x', state: AppRoadmapState.done)]), isNull);
      expect(appRoadmapHorizontal(1000, 5), isTrue);
      expect(appRoadmapHorizontal(1000, 7), isFalse);
      expect(appRoadmapHorizontal(400, 5), isFalse);
      expect(appRoadmapNodeLabel(_nodes[0], 0, 5), 'Step 1 of 5, Basics, Done');
      expect(appRoadmapNodeLabel(_nodes[2], 2, 5, next: true), 'Step 3 of 5, Heads, In progress, Next step, A head for every unit');
      expect(appRoadmapStateLabel(AppRoadmapState.warn), 'Needs attention');
      AppConfig.lang = 'ar';
      expect(appRoadmapNodeLabel(_nodes[0], 0, 5), 'الخطوة 1 من 5، Basics، مكتمل');
      AppConfig.lang = 'en';
      final stops = const [AppStatusStop('Submitted', at: '10 Nov'), AppStatusStop('Reviewed'), AppStatusStop('Decided')];
      expect(appStatusPathLabel(stops, 0), 'Status: Submitted, 1 of 3, 10 Nov');
      expect(appStatusPathLabel(stops, 5), 'Status: Decided, 3 of 3');
      expect(appStatusPathLabel(stops, -1), 'Status: not started');
    });

    testWidgets('every state has its word; semantics read the step; the next node has the button', (tester) async {
      final handle = tester.ensureSemantics();
      var acted = 0;
      final nodes = [..._nodes];
      nodes[2] = AppRoadmapNode(id: 'c', title: 'Heads', state: AppRoadmapState.current, actionLabel: 'Open this step', onAction: () => acted++);
      await _pump(tester, _scroll(AppRoadmap(nodes: nodes)));
      for (final w in ['Done', 'Needs attention', 'In progress', 'To do']) {
        expect(find.text(w), findsWidgets, reason: w);
      }
      expect(find.text('Next'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Step 1 of 5, Basics, Done$')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Step 2 of 5, Departments, Needs attention')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('roadmap.action.c')));
      expect(acted, 1);
      // wide: one row, the next node's block below it
      await _pump(tester, _scroll(AppRoadmap(nodes: nodes)), size: const Size(1400, 900));
      final a = tester.getTopLeft(find.byKey(const ValueKey('roadmap.node.a')));
      final e = tester.getTopLeft(find.byKey(const ValueKey('roadmap.node.e')));
      expect(a.dy, e.dy);
      expect(find.byKey(const ValueKey('roadmap.action.c')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('status path: the request semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _scroll(AppStatusPath.request(reached: 1, times: const ['10 Nov', '12 Nov', null], semanticPrefix: 'Letter')));
      expect(find.bySemanticsLabel('Letter, Status: Reviewed, 2 of 3, 12 Nov'), findsOneWidget);
      expect(find.text('Decided'), findsOneWidget);
      handle.dispose();
    });
  });

  group('journey', () {
    test('parse: ordering by urgency then date, counts, help keys, contacts, register', () {
      final j = MyJourney.fromJson(_journey());
      expect([for (final s in j.now) s.key], ['form:3', 'ack:2', 'reply:1']);
      expect(j.top!.key, 'form:3');
      expect([for (final s in j.importantRows) s.key], ['ack:2', 'reply:1', 'register']);
      expect(j.laterCount, 9);
      expect(j.importantCount, 3);
      expect([for (final r in j.requests) r.id], [41, 42]);
      expect(j.requests.first.reached, 1);
      expect(j.requests.last.reached, 2);
      expect(j.registerOpen, isTrue);
      expect(j.registerEndsAt, isNotNull);
      expect(j.fileRequest!.module, 'new_request');
      expect(j.fileComplaint!.module, 'new_complaint');
      expect(j.contacts.length, 3);
      final dept = j.contacts[1];
      expect(dept.messageable, isTrue);
      expect(dept.messageDeptId, 12);
      expect(dept.displayName, 'Student Affairs');
      expect(j.contacts[0].messageable, isFalse); // advisor: can_message false
      expect(j.contacts[2].messageable, isFalse); // action unit
      expect(j.contacts[2].kindLabel, 'Acting head of department');
      // a closed window or one I can't use → no Register tile
      expect(MyJourney.fromJson({'register': {'open': true, 'reason': 'not_self_service'}}).registerOpen, isFalse);
      // garbage in → empty, never a throw
      final empty = MyJourney.fromJson({'now': 'x', 'requests': 3, 'contacts': [1], 'help': 'no'});
      expect(empty.isEmpty, isTrue);
      expect(empty.top, isNull);
    });

    test('action targets: every server module, unknown → the safe fallback', () {
      JourneyTarget of(String m, [int? id = 1]) => journeyTargetOf(JourneyAction(module: m, targetId: id));
      expect(of('work_item'), JourneyTarget.workItem);
      expect(of('work_item', null), JourneyTarget.none);
      expect(of('complaint'), JourneyTarget.complaint);
      expect(of('message'), JourneyTarget.message);
      expect(of('registrar'), JourneyTarget.registrar);
      expect(of('advising_appointment'), JourneyTarget.meeting);
      expect(of('form'), JourneyTarget.form);
      expect(of('new_request'), JourneyTarget.newRequest);
      expect(of('new_complaint'), JourneyTarget.newComplaint);
      expect(of('unit_message'), JourneyTarget.unitMessage);
      expect(of('org_council'), JourneyTarget.notification);
      expect(of('mystery'), JourneyTarget.none);
      expect(journeyTargetOf(null), JourneyTarget.none);
    });

    testWidgets('view: hero, Important, Can wait folded then open, shortcuts and requests', (tester) async {
      final j = MyJourney.fromJson(_journey());
      final acted = <String>[];
      final filed = <String>[];
      JourneyRequest? opened;
      await _pump(
          tester,
          _scroll(OrgMyJourneyView(
            journey: j,
            onAction: (s) => acted.add(s.key),
            onFile: filed.add,
            onRegister: () => filed.add('register'),
            onContacts: () {},
            onOpenRequest: (r) => opened = r,
          )));
      expect(find.text('What should I do now?'), findsOneWidget);
      expect(find.text(j.top!.title), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('journey.hero.action')));
      expect(acted, ['form:3']);
      expect(find.byKey(const ValueKey('journey.important')), findsOneWidget);
      expect(find.text('Important · 3'), findsOneWidget);
      // Can wait: folded, with the full count
      expect(find.byKey(const ValueKey('journey.later')), findsNothing);
      expect(find.text('Can wait · 9'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('journey.later.toggle')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('journey.later')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('journey.register')));
      await tester.ensureVisible(find.byKey(const ValueKey('journey.file.complaint')));
      await tester.tap(find.byKey(const ValueKey('journey.file.complaint')));
      expect(filed, ['register', 'complaint']);
      await tester.ensureVisible(find.byKey(const ValueKey('journey.request.41')));
      await tester.tap(find.byKey(const ValueKey('journey.request.41')));
      expect(opened?.id, 41);
      expect(find.byType(AppStatusPath), findsNWidgets(2));
    });

    testWidgets('nothing now → the calm hero, no button', (tester) async {
      await _pump(tester, _scroll(OrgMyJourneyView(journey: const MyJourney(), onAction: (_) {})));
      expect(find.text('Nothing needs you right now'), findsOneWidget);
      expect(find.byKey(const ValueKey('journey.hero.action')), findsNothing);
      expect(find.byKey(const ValueKey('journey.register')), findsNothing);
    });

    testWidgets('contacts: Message only where the server allows it, and it targets the unit', (tester) async {
      final j = MyJourney.fromJson(_journey());
      final sent = <int?>[];
      await _pump(tester, _scroll(JourneyContactsList(contacts: j.contacts, onMessage: (c) => sent.add(c.messageDeptId))));
      expect(find.byKey(const ValueKey('journey.contact.message.12')), findsOneWidget);
      expect(find.byKey(const ValueKey('journey.contact.message.90')), findsNothing);
      expect(find.byKey(const ValueKey('journey.contact.message.55')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('journey.contact.message.12')));
      expect(sent, [12]);
    });

    testWidgets('member home: the journey leads, the rest folds under More', (tester) async {
      final entry = {
        'organization': {'id': 5, 'name_en': 'Faculty of Science', 'name_ar': 'كلية العلوم', 'status': 'approved', 'type': 'faculty'},
        'roles': ['student'],
        'todo': {'total': 2},
        'approvals': {},
        'news': 1,
      };
      await _pump(
          tester,
          SingleChildScrollView(
              child: OrgMemberHomeBody(
                  entry: entry,
                  today: const [],
                  inbox: const [],
                  news: const SizedBox(key: ValueKey('news.probe'), height: 40),
                  journey: OrgMyJourneyView(journey: MyJourney.fromJson(_journey())))));
      expect(find.text('My journey'), findsOneWidget);
      expect(find.byKey(const ValueKey('member.more')), findsOneWidget);
      expect(find.byKey(const ValueKey('news.probe')), findsNothing); // folded: nothing under More is built
      final journeyY = tester.getTopLeft(find.text('My journey')).dy;
      final moreY = tester.getTopLeft(find.byKey(const ValueKey('member.more'))).dy;
      expect(journeyY, lessThan(moreY));
    });
  });

  group('attention flow', () {
    test('parse: sections, capped lists with full counts, names', () {
      final f = AttentionFlow.fromJson(_flow());
      expect(f.newRequests.single.unit, 'Computer Science');
      expect(f.newCount, 14);
      expect(f.votesWaiting.single.agendaItemId, 81);
      expect(f.votesWaiting.single.council, 'Department council');
      expect(f.overdue.single.late, isTrue);
      expect(f.actingUnits.single.name, 'Computer Science');
      expect(f.total, 17);
      expect(attentionFlowSummary(f), '14 new · 1 vote · 1 overdue · 1 unit without a head');
      final derived = AttentionFlow.fromJson({'overdue': [{'id': 1}], 'votes_waiting': 'x'});
      expect(derived.total, 1);
      expect(AttentionFlow.fromJson(const {}).isEmpty, isTrue);
    });

    testWidgets('view: sections in order, rows open, Assign a head, empty state', (tester) async {
      final f = AttentionFlow.fromJson(_flow());
      final opened = <String>[];
      await _pump(
          tester,
          _scroll(AttentionFlowView(
            flow: f,
            onOpenItem: (x) => opened.add('item ${x.id}'),
            onOpenVote: (v) => opened.add('vote ${v.sessionId}'),
            onAssignHead: (u) => opened.add('unit ${u.id}'),
          )));
      final y = [for (final k in ['overdue', 'new', 'votes', 'acting']) tester.getTopLeft(find.byKey(ValueKey('flow.section.$k'))).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.byKey(const ValueKey('flow.section.assigned')), findsNothing);
      expect(find.text('and 13 more'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('flow.item.12')));
      await tester.tap(find.byKey(const ValueKey('flow.item.11')));
      await tester.ensureVisible(find.byKey(const ValueKey('flow.vote.8.81')));
      await tester.tap(find.byKey(const ValueKey('flow.vote.8.81')));
      await tester.ensureVisible(find.byKey(const ValueKey('flow.unit.3')));
      await tester.tap(find.byKey(const ValueKey('flow.unit.3')));
      expect(opened, ['item 12', 'item 11', 'vote 8', 'unit 3']);
      await _pump(tester, _scroll(const AttentionFlowView(flow: AttentionFlow())));
      expect(find.byKey(const ValueKey('flow.empty')), findsOneWidget);
    });
  });

  group('admin roadmap', () {
    test('stages: the server\'s (unknown keys dropped), else derived from step / done / readiness', () {
      final w = InstitutionWizardState.fromJson(_wizard(stages: _stages()));
      expect([for (final s in w.stages) s.key], institutionStageKeys);
      expect(w.stages[2].blocking, 1);
      expect(institutionStagesOf(w)[3].state, 'warn');
      expect(institutionStagesOf(w)[4].wizardStep, 'review');
      final d = institutionStagesOf(InstitutionWizardState.fromJson(_wizard()));
      expect([for (final s in d) s.state], ['done', 'done', 'current', 'todo', 'todo']);
      expect(d[2].blocking, 1);
      final launched = institutionStagesOf(InstitutionWizardState.fromJson(_wizard(
          launchedAt: '2026-11-15T10:00:00', step: 'review', done: ['basics', 'departments', 'heads', 'councils', 'optional', 'review'])));
      expect([for (final s in launched) s.state], ['done', 'done', 'warn', 'warn', 'done']);
      expect(institutionHealthy(launched), isFalse);
      expect(institutionHealthy([for (final k in institutionStageKeys) InstitutionStage(key: k, state: 'done')]), isTrue);
    });

    testWidgets('page view: the next node opens the wizard at its step; warnings open theirs', (tester) async {
      final steps = <String>[];
      final w = InstitutionWizardState.fromJson(_wizard(stages: _stages()));
      await _pump(tester, _scroll(InstitutionRoadmapView(state: w, onOpenStep: steps.add)));
      expect(find.text('Next'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('roadmap.action.inst.heads')));
      await tester.ensureVisible(find.text('A council has no secretary'));
      expect(steps, ['heads']);
      expect(find.text('2 units have no head'), findsOneWidget);
    });

    testWidgets('home card: health after launch opens a stage', (tester) async {
      final opened = <String>[];
      final w = InstitutionWizardState.fromJson(_wizard(stages: _stages(), launchedAt: '2026-11-15T10:00:00'));
      await _pump(tester, _scroll(InstitutionRoadmapCard(state: w, onOpenStage: (s) => opened.add(s.key), onOpenPage: () => opened.add('page'))));
      expect(find.text('Institution health'), findsOneWidget);
      expect(find.text('3 warnings'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inst.roadmap.open')));
      expect(opened, ['page']);
    });
  });

  group('layout', () {
    final j = MyJourney.fromJson(_journey());
    final f = AttentionFlow.fromJson(_flow());
    final w = InstitutionWizardState.fromJson(_wizard(stages: _stages()));

    testWidgets('AppRoadmap (both directions, dense) and AppStatusPath', (tester) async {
      await expectNoLayoutErrors(tester, () => _scroll(AppRoadmap(nodes: [for (final n in _nodes) AppRoadmapNode(id: n.id, title: n.title, state: n.state, subtitle: n.subtitle, actionLabel: n.actionLabel, onAction: n.actionLabel == null ? null : () {}, onTap: () {})])));
      await expectNoLayoutErrors(tester, () => _scroll(const AppRoadmap(nodes: _nodes, dense: true)));
      await expectNoLayoutErrors(tester, () => _scroll(const AppRoadmap(nodes: _nodes, axis: Axis.horizontal)));
      await expectNoLayoutErrors(tester, () => _scroll(AppStatusPath.request(reached: 2, times: const ['10 Nov', '12 Nov', '14 Nov'])));
    });

    testWidgets('journey: view (Can wait open), contacts, empty', (tester) async {
      await expectNoLayoutErrors(tester, () => _scroll(OrgMyJourneyView(journey: j, onAction: (_) {}, onFile: (_) {}, onRegister: () {}, onContacts: () {}, onOpenRequest: (_) {}, onAllRequests: () {})),
          act: (tester) async {
        await tester.ensureVisible(find.byKey(const ValueKey('journey.later.toggle')));
        await tester.tap(find.byKey(const ValueKey('journey.later.toggle')));
      });
      await expectNoLayoutErrors(tester, () => _scroll(JourneyContactsList(contacts: j.contacts, onMessage: (_) {})));
      await expectNoLayoutErrors(tester, () => _scroll(OrgMyJourneyView(journey: const MyJourney())));
    });

    testWidgets('attention flow and the admin roadmap', (tester) async {
      await expectNoLayoutErrors(tester, () => _scroll(AttentionFlowView(flow: f, onOpenItem: (_) {}, onOpenVote: (_) {}, onAssignHead: (_) {})));
      await expectNoLayoutErrors(tester, () => _scroll(const AttentionFlowView(flow: AttentionFlow())));
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionRoadmapView(state: w, onOpenStep: (_) {})));
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionRoadmapCard(state: w, onOpenStage: (_) {}, onOpenPage: () {})));
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionSetupCard(state: w, onContinue: () {}, onRoadmap: () {})));
    });
  });

  group('a11y', () {
    final j = MyJourney.fromJson(_journey());
    testWidgets('journey', (tester) async {
      await expectA11y(tester, 'p5.journey', () => _scroll(OrgMyJourneyView(journey: j, onAction: (_) {}, onFile: (_) {}, onRegister: () {}, onContacts: () {}, onOpenRequest: (_) {}, onAllRequests: () {})));
      await expectA11y(tester, 'p5.contacts', () => _scroll(JourneyContactsList(contacts: j.contacts, onMessage: (_) {})));
    });
    testWidgets('attention flow and roadmap', (tester) async {
      await expectA11y(tester, 'p5.flow', () => _scroll(AttentionFlowView(flow: AttentionFlow.fromJson(_flow()), onOpenItem: (_) {}, onOpenVote: (_) {}, onAssignHead: (_) {})));
      final w = InstitutionWizardState.fromJson(_wizard(stages: _stages()));
      await expectA11y(tester, 'p5.roadmap', () => _scroll(InstitutionRoadmapView(state: w, onOpenStep: (_) {})));
    });
  });
}
