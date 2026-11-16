// Institutions v2, phase 6 (docs/institutions/V2_PLAN.md item 6, D-998 – D-999): the manager's Institution health.
// GET …/institution/health parses defensively (severities, a missing score derived, ids), groups block → warn → info,
// every check's Fix goes to its wizard step or the filtered governance list (none when governance is off or the
// action is unknown); the `org_institution_health` link opens only for a manager; the Home slot shows the score and
// the top issue after the launch (an older server: the roadmap card); every new widget lays out at 320×640 and
// 1400×900 in Arabic and English with text scale 1.3 and passes the a11y guidelines.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/org/org_institution_health.dart';
import 'package:flutter_education_app/features/org/org_institution_wizard.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/a11y_guidelines_test.dart' show expectA11y;
import '../ui/layout_harness.dart';

const _inst = '/api/v1/org/orgs/5/institution';

Map<String, dynamic> _health({int? score = 62}) => {
      'ok': false,
      'score': ?score,
      'generated_at': '2026-11-15T09:00:00',
      'checks': [
        {'key': 'stale_requests', 'severity': 'warn', 'count': 4, 'text_ar': '4 طلبات متأخرة', 'text_en': '4 requests are past their deadline', 'action': 'items', 'ids': [11, 12, 0, 'x']},
        {'key': 'heads_missing', 'severity': 'block', 'count': 2, 'text_ar': 'وحدتان بلا رئيس', 'text_en': '2 units have no head', 'action': 'heads', 'ids': [3, 4]},
        {'key': 'council_no_chair', 'severity': 'block', 'count': 1, 'text_en': 'A council has no chair, said in a sentence long enough to wrap on a phone', 'action': 'councils'},
        {'key': 'headless_repaired', 'severity': 'info', 'count': 1, 'text_ar': 'أصلحنا وحدة بلا رئيس', 'text_en': 'We made the manager acting head of 1 unit', 'action': 'heads'},
        {'key': 'orphan_items', 'severity': 'warn', 'count': 1, 'text_en': 'A request has no unit to answer it', 'action': 'items'},
        {'key': 'mystery', 'severity': 'weird', 'text_en': 'Something else', 'action': 'nowhere'},
        {'severity': 'block', 'text_en': 'no key: dropped'},
      ],
    };

Map<String, dynamic> _wizard() => {
      'step': 'review',
      'done': ['basics', 'departments', 'heads', 'councils', 'optional', 'review'],
      'launched_at': '2026-11-10T10:00:00',
      'applicable': true,
      'readiness': {
        'ok': false,
        'items': [
          {'key': 'heads_acting', 'severity': 'warn', 'count': 1, 'text_en': 'A unit has an acting head', 'action': 'heads'},
        ],
      },
    };

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

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
    AppConfig.orgsEnabled = true;
  });

  group('parse and group', () {
    test('severities, ids, score clamp, a missing score derived, the top issue', () {
      final h = InstitutionHealth.fromJson(_health());
      expect(h.ok, isFalse);
      expect(h.score, 62);
      expect(h.generatedAt!.toUtc(), DateTime.utc(2026, 11, 15, 9));
      expect(h.checks.length, 6, reason: 'a check without a key is dropped');
      expect(h.checks.first.ids, [11, 12]);
      expect(h.checks.firstWhere((c) => c.key == 'mystery').severity, 'warn', reason: 'an unknown severity reads as warn');
      expect(h.grouped.keys.toList(), ['block', 'warn', 'info']);
      expect([for (final c in h.grouped['block']!) c.key], ['heads_missing', 'council_no_chair']);
      expect([for (final c in h.grouped['warn']!) c.key], ['stale_requests', 'orphan_items', 'mystery']);
      expect(h.issueCount, 5, reason: 'info never counts');
      expect(h.top!.key, 'heads_missing');
      expect(h.calm, isFalse);
      expect(InstitutionHealth.fromJson({'score': 140}).score, 100);
      expect(InstitutionHealth.fromJson({'score': -3}).score, 0);
      // no score: 100 − 20 per block − 5 per warn
      expect(InstitutionHealth.fromJson(_health(score: null)).score, 100 - 2 * 20 - 3 * 5);
      final calm = InstitutionHealth.fromJson({'ok': true, 'score': 100, 'checks': [{'key': 'headless_repaired', 'severity': 'info'}]});
      expect(calm.calm, isTrue);
      expect(calm.top, isNull);
      // garbage in → empty, never a throw
      final g = InstitutionHealth.fromJson({'checks': 'x', 'generated_at': 3});
      expect(g.checks, isEmpty);
      expect(g.ok, isTrue);
      expect(g.generatedAt, isNull);
      // Arabic text with the English fallback
      AppConfig.lang = 'ar';
      expect(h.checks.firstWhere((c) => c.key == 'council_no_chair').text, startsWith('A council has no chair'));
      expect(h.top!.text, 'وحدتان بلا رئيس');
    });

    test('verdict words and group titles count', () {
      expect(institutionHealthVerdict(90), 'Healthy');
      expect(institutionHealthVerdict(62), 'Needs care');
      expect(institutionHealthVerdict(20), 'At risk');
      expect(institutionHealthGroupTitle('block', 2), '2 things to fix');
      expect(institutionHealthGroupTitle('warn', 1), '1 thing worth a look');
      expect(institutionHealthGroupTitle('info', 3), '3 notes for you');
      AppConfig.lang = 'ar';
      expect(institutionHealthGroupTitle('block', 2), 'أمران يجب إصلاحهما');
      expect(institutionHealthGroupTitle('warn', 11), '11 ملاحظة تستحق النظر');
    });
  });

  group('fix actions', () {
    InstitutionHealthFix fix(String key, String action, {bool governance = true}) =>
        institutionHealthFixOf(InstitutionHealthCheck(key: key, action: action), governance: governance);

    test('wizard steps, stale / orphan → the filtered governance list, unknown → none', () {
      expect(fix('heads_missing', 'heads'), const InstitutionHealthFix(InstitutionHealthFixKind.wizard, step: 'heads'));
      expect(fix('council_no_chair', 'councils'), const InstitutionHealthFix(InstitutionHealthFixKind.wizard, step: 'councils'));
      expect(fix('study_system', 'basics').step, 'basics');
      expect(fix('x', 'launch'), const InstitutionHealthFix(InstitutionHealthFixKind.wizard, step: 'review'));
      expect(fix('stale_requests', 'items'), const InstitutionHealthFix(InstitutionHealthFixKind.items, tile: 'overdue'));
      expect(fix('requests_overdue', ''), const InstitutionHealthFix(InstitutionHealthFixKind.items, tile: 'overdue'));
      expect(fix('orphan_items', 'items'), const InstitutionHealthFix(InstitutionHealthFixKind.items, tile: 'pending'));
      expect(fix('unassigned', 'governance'), const InstitutionHealthFix(InstitutionHealthFixKind.items, tile: 'pending'));
      expect(fix('something', 'governance'), const InstitutionHealthFix(InstitutionHealthFixKind.items, tile: 'all'));
      expect(fix('stale_requests', 'items', governance: false).kind, InstitutionHealthFixKind.none);
      expect(fix('heads_missing', 'heads', governance: false).kind, InstitutionHealthFixKind.wizard, reason: 'the wizard does not need governance');
      expect(fix('mystery', 'nowhere').kind, InstitutionHealthFixKind.none);
      expect(institutionHealthFixPlace(fix('heads_missing', 'heads')), 'Heads');
      expect(institutionHealthFixPlace(fix('stale_requests', 'items')), 'Requests');
      expect(institutionHealthFixPlace(fix('mystery', 'nowhere')), isNull);
    });

    test('the notification link: managers only, organizations and the institution feature on', () {
      bool ok({int? org = 5, bool on = true, List<String> off = const [], bool manages = true}) =>
          institutionHealthLinkAllowed(orgId: org, orgsEnabled: on, disabled: off, manages: manages);
      expect(ok(), isTrue);
      expect(ok(org: null), isFalse);
      expect(ok(on: false), isFalse);
      expect(ok(off: const ['org.institution']), isFalse);
      expect(ok(manages: false), isFalse);
    });

    testWidgets('view: groups in order, each Fix reports its target, unknown has no button', (tester) async {
      final h = InstitutionHealth.fromJson(_health());
      final fixed = <String>[];
      await _pump(tester, _scroll(InstitutionHealthView(health: h, onFix: (c, f) => fixed.add('${c.key}:${f.kind.name}:${f.step ?? f.tile}'))));
      expect(find.text('Needs care'), findsOneWidget);
      expect(find.text('62%'), findsOneWidget);
      final y = [for (final s in ['block', 'warn', 'info']) tester.getTopLeft(find.byKey(ValueKey('health.group.$s'))).dy];
      expect(y, orderedEquals([...y]..sort()));
      expect(find.text('2 things to fix'), findsOneWidget);
      expect(find.byKey(const ValueKey('health.fix.mystery')), findsNothing);
      for (final k in ['heads_missing', 'council_no_chair', 'stale_requests', 'orphan_items', 'headless_repaired']) {
        await tester.ensureVisible(find.byKey(ValueKey('health.fix.$k')));
        await tester.tap(find.byKey(ValueKey('health.fix.$k')));
      }
      expect(fixed, ['heads_missing:wizard:heads', 'council_no_chair:wizard:councils', 'stale_requests:items:overdue', 'orphan_items:items:pending', 'headless_repaired:wizard:heads']);
      // an info check says Open, the rest Fix
      expect(find.descendant(of: find.byKey(const ValueKey('health.fix.headless_repaired')), matching: find.text('Open')), findsOneWidget);
      // governance off: the request checks lose their button
      await _pump(tester, _scroll(InstitutionHealthView(health: h, onFix: (_, _) {}, governance: false)));
      expect(find.byKey(const ValueKey('health.fix.stale_requests')), findsNothing);
      expect(find.byKey(const ValueKey('health.fix.heads_missing')), findsOneWidget);
    });

    testWidgets('view: nothing to look at → the calm empty state', (tester) async {
      await _pump(tester, _scroll(InstitutionHealthView(health: InstitutionHealth.fromJson({'ok': true, 'score': 100}))));
      expect(find.byKey(const ValueKey('inst.health.empty')), findsOneWidget);
      expect(find.text('Healthy'), findsOneWidget);
    });

    testWidgets('home card: the score, the top issue and how many more; a tap opens the page', (tester) async {
      var opened = 0;
      await _pump(tester, _scroll(InstitutionHealthCard(health: InstitutionHealth.fromJson(_health()), onOpen: () => opened++)));
      expect(find.text('Institution health'), findsOneWidget);
      expect(find.text('2 units have no head · 4 more'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('inst.health.open')));
      expect(opened, 1);
    });
  });

  group('home slot', () {
    late FakeApi api;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      await StorageService.getInstance();
    });
    tearDown(() => api.uninstall());

    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(600, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider<OrgSession>(
        create: (_) => OrgSession()..currentId = 5,
        child: ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          child: MaterialApp(
              navigatorKey: navigatorKey,
              home: Scaffold(body: SingleChildScrollView(child: OrgInstitutionSetupCard(orgId: 5, onOpen: () async {})))),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('launched: the health card; an older server (404) → the roadmap card', (tester) async {
      api = FakeApi({'GET $_inst/wizard': (_) => _wizard(), 'GET $_inst/health': (_) => _health()}, latency: const Duration(milliseconds: 10))..install();
      await open(tester);
      expect(find.byKey(const ValueKey('inst.health.card')), findsOneWidget);
      expect(find.byKey(const ValueKey('inst.roadmap.card')), findsNothing);
      api.uninstall();
      await tester.pumpWidget(const SizedBox());
      api = FakeApi({'GET $_inst/wizard': (_) => _wizard()}, latency: const Duration(milliseconds: 10))..install();
      await open(tester);
      expect(find.byKey(const ValueKey('inst.health.card')), findsNothing);
      expect(find.byKey(const ValueKey('inst.roadmap.card')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('launched and calm: nothing on the Home', (tester) async {
      api = FakeApi({'GET $_inst/wizard': (_) => _wizard(), 'GET $_inst/health': (_) => {'ok': true, 'score': 100, 'checks': []}},
          latency: const Duration(milliseconds: 10))
        ..install();
      await open(tester);
      expect(find.byKey(const ValueKey('inst.health.card')), findsNothing);
      expect(find.byKey(const ValueKey('inst.roadmap.card')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('layout and a11y', () {
    final h = InstitutionHealth.fromJson(_health());
    testWidgets('page view, empty view, home card', (tester) async {
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionHealthView(health: h, onFix: (_, _) {})));
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionHealthView(health: InstitutionHealth.fromJson({'ok': true, 'score': 100}))));
      await expectNoLayoutErrors(tester, () => _scroll(InstitutionHealthCard(health: h, onOpen: () {})));
    });

    testWidgets('a11y: page view and home card', (tester) async {
      await expectA11y(tester, 'p6.health', () => _scroll(InstitutionHealthView(health: h, onFix: (_, _) {})));
      await expectA11y(tester, 'p6.health.card', () => _scroll(InstitutionHealthCard(health: h, onOpen: () {})));
    });
  });
}
