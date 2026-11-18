// Pins and colour boxes in the role shells (lib/design/shell_pins.dart, D-1170): the stored state (add, unpin with
// its colour, reorder, colours, JSON, the 8-pin cap), which routes rebuild after a restart, the pin button on a page
// opened inside a tab, a pin as its own sidebar entry the dashboard's index never sees, a pinned page that closes
// itself going to Home, the phone's Home strip, and the strip / Customize sheet under the layout harness.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/design/shell_pins.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _scope = '0|t';

void main() {
  late StorageService storage;

  Future<void> seed([ShellPinState state = const ShellPinState()]) async {
    SharedPreferences.setMockInitialValues({'ui.shell_tabs.v1.$_scope': jsonEncode(state.toJson())});
    storage = await StorageService.getInstance();
    ShellPins.debugReset();
  }

  setUp(() async {
    AppConfig.lang = 'en';
    await seed();
  });

  group('ShellPinState', () {
    const a = ShellPin(id: 'a', title: 'Rooms', route: '/calendar');
    const b = ShellPin(id: 'b', title: 'Grades');

    test('add gives each pin the next ring colour; remove drops its colour too', () {
      final s = const ShellPinState().add(a).add(b);
      expect(s.pins.map((p) => p.id), ['a', 'b']);
      expect(s.colorOf('pin_a'), ShellTabColor.coral);
      expect(s.colorOf('pin_b'), ShellTabColor.sky);
      final r = s.remove('a');
      expect(r.pins.map((p) => p.id), ['b']);
      expect(r.colorOf('pin_a'), isNull);
    });

    test('move clamps; colours: a role tab goes back to none, a pin to its ring colour', () {
      var s = const ShellPinState().add(a).add(b);
      expect(s.move('a', 5).pins.map((p) => p.id), ['b', 'a']);
      expect(s.move('a', -1).pins.map((p) => p.id), ['a', 'b']);
      s = s.withColor('home', ShellTabColor.amber).withColor('pin_a', ShellTabColor.slate);
      expect(s.colorOf('home'), ShellTabColor.amber);
      expect(s.withColor('home', null).colorOf('home'), isNull);
      expect(s.withColor('pin_a', null).colorOf('pin_a'), ShellTabColor.coral);
      final reset = s.resetColors();
      expect(reset.colorOf('home'), isNull);
      expect(reset.colorOf('pin_a'), ShellTabColor.coral);
    });

    test('JSON round trip; bad rows, duplicates and pins past the cap are dropped', () {
      final s = const ShellPinState().add(a).add(b).withColor('home', ShellTabColor.indigo);
      expect(ShellPinState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>).toJson(), s.toJson());
      final many = {
        'pins': [
          for (var i = 0; i < kShellPinMax + 3; i++) {'id': 'p$i', 'title': 'T$i'},
          {'id': 'p0', 'title': 'dup'},
          {'title': 'no id'},
          'junk',
        ],
        'colors': {'home': 'nope', 'x': 'amber'},
      };
      final parsed = ShellPinState.fromJson(many);
      expect(parsed.pins.length, kShellPinMax);
      expect(parsed.colors, {'x': ShellTabColor.amber});
      var full = parsed;
      full = full.add(const ShellPin(id: 'new', title: 'New'));
      expect(full.pins.length, kShellPinMax, reason: 'no ninth pin');
    });

    test('restorable routes: named, plain arguments, not a root-only route', () {
      MaterialPageRoute<void> r(String? name, [Object? args]) =>
          MaterialPageRoute(settings: RouteSettings(name: name, arguments: args), builder: (_) => const SizedBox());
      expect(shellRestorableRoute(r('/calendar'))?.name, '/calendar');
      expect(shellRestorableRoute(r('/course-profile', 7))?.args, 7);
      expect(shellRestorableRoute(r(null)), isNull);
      expect(shellRestorableRoute(r('/course-detail', Object())), isNull, reason: 'an in-memory object');
      expect(shellRestorableRoute(r('/login')), isNull, reason: 'never inside a tab');
      expect(shellPageBuilderOf(r('/x')), isNotNull);
    });

    test('the box ink is the one that reads on its fill', () {
      const light = Color(0xFFFFFFFF), dark = Color(0xFF111111);
      expect(shellInkOn(const Color(0xFF0B3D2E), light: light, dark: dark), light);
      expect(shellInkOn(const Color(0xFFF6E7C4), light: light, dark: dark), dark);
    });
  });

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ],
        child: child,
      );

  /// A page with the kit's header, as a tab's pushed page draws it.
  Widget roomsPage() => const Scaffold(
        appBar: AppHeader(title: 'Rooms'),
        body: Center(child: Text('rooms body')),
      );

  List<DashboardItem> items() => [
        DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', null, Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => roomsPage())),
              child: const Text('open rooms'),
            ),
          ),
        )),
        DashboardItem(Icons.book_outlined, Icons.book_rounded, 'my_courses', null, const Text('courses')),
      ];

  testWidgets('desktop: pin a page from its header; it becomes a sidebar entry the dashboard index never sees',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    final taps = <int>[];
    await tester.pumpWidget(layoutHost(
        host(AppShell(width: 1400, currentIndex: 0, onTap: taps.add, items: items(), pinScope: 't')),
        scaffold: false));
    await tester.pump();

    expect(find.byKey(const ValueKey('shell.pin')), findsNothing, reason: 'a tab first page is a tab already');
    await tester.tap(find.text('open rooms'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('shell.pin')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('shell.pin')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final scope = ShellPins.scope(_scope);
    expect(scope.pins.map((p) => p.title), ['Rooms']);
    expect(find.text('shell_group_pinned'.tr.toUpperCase()), findsOneWidget, reason: 'the Pinned group label');

    // the pin's own entry: its page, without touching the dashboard's index
    await tester.tap(find.text('Rooms').first);
    await tester.pumpAndSettle();
    expect(taps, isEmpty);
    expect(find.text('rooms body'), findsWidgets);

    // the pinned page closes itself (a save that pops): Home, not out of the dashboard
    final ctx = tester.element(find.text('rooms body').last);
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    expect(taps, [0]);
    expect(find.byType(AppShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a pin that cannot be rebuilt after a restart says so and offers Unpin', (tester) async {
    await seed(const ShellPinState().add(const ShellPin(id: 'z', title: 'Old page')));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(
        host(AppShell(width: 1400, currentIndex: 0, onTap: (_) {}, items: items(), pinScope: 't')),
        scaffold: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Old page').first);
    await tester.pumpAndSettle();
    expect(find.text('shell_pin_reconnect_body'.tr), findsOneWidget);
    await tester.tap(find.text('shell_unpin'.tr).last);
    await tester.pumpAndSettle();
    expect(ShellPins.scope(_scope).pins, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone: the bar keeps the role tabs; pins are a strip on Home that opens the page inside Home',
      (tester) async {
    await seed(const ShellPinState().add(const ShellPin(id: 'c', title: 'Calendar', route: '/cal')));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ThemeConfigScope(
      provider: ThemeConfigProvider(api: ApiClient()),
      child: MaterialApp(
        onGenerateRoute: (s) => s.name == '/cal'
            ? MaterialPageRoute<void>(settings: s, builder: (_) => const Scaffold(body: Text('calendar body')))
            : null,
        home: host(AppShell(width: 320, currentIndex: 0, onTap: (_) {}, items: items(), pinScope: 't')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ShellPinStrip), findsOneWidget);
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('calendar body'), findsOneWidget, reason: 'rebuilt from its route');
    expect(find.byType(ShellPinStrip), findsNothing, reason: 'only on Home first page');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('strip and Customize sheet: no overflow at 320 / 1400, ar / en, scale 1.3', (tester) async {
    final scope = ShellPinScope('h')
      ..debugSet(const ShellPinState()
          .add(const ShellPin(id: 'a', title: 'إدارة شؤون الطلاب والدراسات العليا والقبول'))
          .add(const ShellPin(id: 'b', title: 'Grades and transcripts of every program'))
          .withColor('home', ShellTabColor.amber));
    await expectNoLayoutErrors(tester, () => ShellPinStrip(
          pins: scope.pins,
          colors: scope.state.colors,
          onOpen: (_) {},
          onCustomize: () {},
        ));
    // bounded like the app's sheet: the sheet must scroll its own rows
    await expectNoLayoutErrors(tester, () => Padding(
            padding: const EdgeInsets.all(16),
            child: ShellTabsSheet(scope: scope, tabs: const [
              ShellTabEntry(tabId: 'home', label: 'الرئيسية والملخص اليومي للأعمال', icon: Icons.home_rounded),
              ShellTabEntry(tabId: 'courses', label: 'My courses', icon: Icons.book_rounded),
              ShellTabEntry(tabId: 'sched', label: 'Schedule', icon: Icons.calendar_month_rounded),
              ShellTabEntry(tabId: 'an', label: 'Analysis', icon: Icons.analytics),
              ShellTabEntry(tabId: 'me', label: 'Profile', icon: Icons.person),
            ]),
        ));
  });
}
