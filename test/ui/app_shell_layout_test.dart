// The role shells (lib/design/app_shell.dart): WideShell · RailShell · MobileShell at 320x640 and 1400x900,
// Arabic + English, textScaler 1.3; AppShell picks by width; a tab's count = badge + the attention feed, drawn at
// the leaf (the feed's tick repaints the badge without rebuilding the shell); tabs are built on their first visit
// and kept afterwards (LazyTabStack, D-077), and an unbuilt tab still shows its count. D-1340: the phone bar draws
// at most five slots (groups, then "More"), a group slot opens its sheet and a row switches the tab.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_contrast.dart';
import 'package:flutter_education_app/design/app_gradients.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const longAr = 'إدارة شؤون الطلاب والدراسات العليا';

void main() {
  late StorageService storage;
  final feed = ValueNotifier<int>(3);
  var shellBuilds = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'ar';
    ShellBadge.source = () => feed;
    ShellBadge.countOf = (key, orgId) => key == AttentionTabs.home ? feed.value : 0;
    shellBuilds = 0;
  });

  List<DashboardItem> items() => [
        DashboardItem(Icons.home_outlined, Icons.home_rounded, 'home', () async {},
            Builder(builder: (_) {
              shellBuilds++;
              return const Center(child: Text('home page'));
            }),
            attentionKeys: const [AttentionTabs.home]),
        DashboardItem(Icons.book_outlined, Icons.book_rounded, 'my_courses', null, const Text('courses'), badge: 2),
        DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, longAr, null, const Text('schedule')),
        DashboardItem(Icons.analytics_outlined, Icons.analytics, 'analysis', null, const Text('analysis'), badge: 120),
        DashboardItem(Icons.person_outline, Icons.person, 'my_profile', null, const Text('profile'),
            badge: 1, attentionKeys: const [AttentionTabs.profile]),
      ];

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ],
        child: child,
      );

  testWidgets('three shells × harness: no overflow, a badge count renders', (tester) async {
    await expectNoLayoutErrors(tester,
        () => host(WideShell(currentIndex: 0, onTap: (_) {}, dashboardItems: items(), unreadCount: 120)),
        scaffold: false);
    await expectNoLayoutErrors(tester,
        () => host(RailShell(currentIndex: 2, onTap: (_) {}, dashboardItems: items(), unreadCount: 5)),
        scaffold: false);
    await expectNoLayoutErrors(tester, () => host(MobileShell(currentIndex: 4, onTap: (_) {}, dashboardItems: items())),
        scaffold: false);
  });

  testWidgets('AppShell picks the shell by width; the leaf badge follows the feed without a shell rebuild',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    var taps = <int>[];
    Widget shell(double w) => host(AppShell(width: w, currentIndex: 0, onTap: taps.add, items: items(), unreadCount: 2));

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpWidget(layoutHost(shell(1400), scaffold: false));
    await tester.pump();
    expect(find.byType(WideShell), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'home = feed 3');
    expect(find.text('99+'), findsWidgets, reason: 'analysis 120 → 99+');
    final builds = shellBuilds;
    feed.value = 7;
    await tester.pump();
    expect(find.text('7'), findsOneWidget, reason: 'the leaf repainted');
    expect(shellBuilds, builds, reason: 'the shell (and its pages) did not rebuild on the attention tick');
    await tester.tap(find.text('my_courses'.tr).first);
    expect(taps, [1]);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpWidget(layoutHost(shell(800), scaffold: false));
    await tester.pump();
    expect(find.byType(RailShell), findsOneWidget);

    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpWidget(layoutHost(shell(320), scaffold: false));
    await tester.pump();
    expect(find.byType(MobileShell), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lazy tabs: only the open tab is built; a visited tab keeps its state; badges need no build',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final created = <String>[];
    var index = 0;
    late StateSetter set;
    DashboardItem tab(String label, {int badge = 0}) => DashboardItem(Icons.circle_outlined, Icons.circle, label, null,
        _Probe(name: label, created: created), badge: badge);
    final tabs = [tab('home'), tab('my_courses', badge: 2), tab('analysis')];
    Widget shell(double w) => host(StatefulBuilder(builder: (context, s) {
          set = s;
          return AppShell(width: w, currentIndex: index, onTap: (i) => s(() => index = i), items: tabs);
        }));

    for (final w in const [320.0, 1400.0]) {
      created.clear();
      index = 0;
      tester.view.physicalSize = Size(w, 900);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(layoutHost(shell(w), scaffold: false));
      await tester.pump();
      expect(created, ['home'], reason: '$w: only the open tab is built');
      expect(find.text('2'), findsOneWidget, reason: '$w: the unbuilt tab shows its badge');

      await tester.tap(find.text('my_courses'.tr).first); // onTap
      await tester.pump();
      expect(created, ['home', 'my_courses']);
      set(() => index = 2); // a deep link changing currentIndex
      await tester.pump();
      set(() => index = 0);
      await tester.pump();
      set(() => index = 1);
      await tester.pump();
      expect(created, ['home', 'my_courses', 'analysis'], reason: '$w: a visited tab is kept, never re-created');
      expect(find.text('my_courses #1', skipOffstage: false), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the desktop shell is in the semantics tree: tabs and top-bar actions are labelled buttons (H12)',
      (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(
        host(WideShell(currentIndex: 0, onTap: (_) {}, dashboardItems: items(), unreadCount: 4)),
        scaffold: false));
    await tester.pump();
    for (final label in ['home', 'my_courses', 'analysis']) {
      expect(
        find.bySemanticsLabel(RegExp(label)),
        findsWidgets,
        reason: 'sidebar tab "$label" must be reachable',
      );
    }
    final home = tester.getSemantics(find.bySemanticsLabel(RegExp('^home')).first);
    expect(home, containsSemantics(isButton: true, isSelected: true, isFocusable: true, hasTapAction: true));
    final bell = tester.getSemantics(find.bySemanticsLabel(RegExp('^notifications, 4')));
    expect(bell, containsSemantics(isButton: true, hasTapAction: true), reason: 'the bell is a labelled button with its count');
    expect(find.bySemanticsLabel(RegExp('my_calendar')), findsOneWidget);
    handle.dispose();
  });

  // D-650 r3: the sidebar is the 60 / 40 panel (green held to 60 %, then the blend to the cream, top → bottom) and
  // each item picks its ink from the colour under it (AppBrandInk). Every tab label, the wordmark, the group labels
  // and the person box are checked at the place they are drawn, with the colour they are drawn in, over the panel's
  // colour there (BrandLayer.sideAt) and the item's plate if it has one, plain, hovered and on the open tab's glass;
  // both modes, Arabic and English, on the production palette, at a short and a tall window.
  testWidgets('sidebar inks keep 4.5:1 where the items sit (the cream part included)', (tester) async {
    final prod = jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;
    final prevLang = AppConfig.lang;
    addTearDown(() {
      AppConfig.lang = prevLang;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    var low = 21.0;
    for (final height in const [900.0, 560.0]) {
    tester.view.physicalSize = Size(1440, height);
    for (final dark in const [false, true]) {
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        final t = ThemeConfigProvider(api: ApiClient())..debugUseColors(prod);
        t.isDark = dark;
        final rtl = lang == 'ar';
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(ThemeConfigScope(
          provider: t,
          child: MaterialApp(
            theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
            home: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: host(WideShell(currentIndex: 0, onTap: (_) {}, dashboardItems: items(), unreadCount: 4)),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump();
        final l = BrandLayer.of(t);
        final card = find.byWidgetPredicate((w) =>
            w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).gradient is RadialGradient &&
            ((w.decoration as BoxDecoration).gradient! as RadialGradient).colors.first == l.sideRadial.first);
        expect(card, findsOneWidget);
        final box = tester.getRect(card);
        final texts = find.descendant(of: card, matching: find.byType(Text));
        var checked = 0;
        for (final e in texts.evaluate()) {
          final w = e.widget as Text;
          final ink = w.style?.color;
          if (ink == null || ink.a < 1) continue;
          if (RegExp(r'^[0-9+]+$').hasMatch(w.data ?? '')) continue; // the red count pills
          final r = tester.getRect(find.byWidget(w));
          final region = find.ancestor(of: find.byWidget(w), matching: find.byType(AppBrandInk));
          final k = region.evaluate().isEmpty
              ? AppBrandLayer.inkFor(l, l.sideSpots)
              : tester.state<AppBrandInkState>(region.first).ink;
          for (final p in [r.topLeft, r.topRight, r.center, r.bottomLeft, r.bottomRight]) {
            final local = Offset(rtl ? box.right - p.dx : p.dx - box.left, p.dy - box.top);
            final bare = l.sideAt(box.size, local);
            final under = k.plate == null ? bare : Color.alphaBlend(k.plate!, bare);
            final surfaces = ink == k.activeInk && ink != k.item
                ? [Color.alphaBlend(k.activeFill, under)]
                : [
                    under,
                    Color.alphaBlend(k.hover, under),
                    if (ink == k.ink || ink == k.muted) Color.alphaBlend(k.glass, under),
                  ];
            for (final s in surfaces) {
              final ratio = contrastRatio(ink, s);
              if (ratio < low) low = ratio;
              expect(ratio, greaterThanOrEqualTo(4.5), reason: '"${w.data}" at $local (${dark ? 'dark' : 'light'} $lang $height)');
            }
          }
          checked++;
        }
        expect(checked, greaterThanOrEqualTo(5), reason: 'the tab labels and the wordmark were checked');
      }
    }
    }
    // ignore: avoid_print
    print('lowest sidebar contrast at the items: ${low.toStringAsFixed(2)}');
  });

  testWidgets('editorial shell: 48 px tabs on the bar, the rail and the sidebar; a reward count renders', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final tabs = [
      ...items(),
      DashboardItem(Icons.star_outline_rounded, Icons.star_rounded, 'points', null, const Text('points'),
          badge: 4, badgeTone: ShellBadgeTone.reward),
    ];

    tester.view.physicalSize = const Size(320, 640);
    // five tabs: one slot each (six would fold the last two into More, D-1340)
    final phoneTabs = [for (final t in tabs) if (t.label != 'analysis') t];
    await tester.pumpWidget(layoutHost(host(MobileShell(currentIndex: 0, onTap: (_) {}, dashboardItems: phoneTabs)), scaffold: false));
    await tester.pump();
    for (final label in ['my_courses', 'points']) {
      final tab = find.ancestor(of: find.text(label.tr), matching: find.byType(ConstrainedBox)).first;
      expect(tester.getSize(tab).height, greaterThanOrEqualTo(48), reason: 'bottom tab "$label" is a 48 px target');
      expect(tester.getSize(tab).width, greaterThanOrEqualTo(48));
    }
    expect(find.text('4'), findsOneWidget, reason: 'the reward (gold) count renders');
    expect(BottomNavMetrics.heightFor(tester.element(find.byType(MobileShell))), greaterThanOrEqualTo(48));

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpWidget(layoutHost(host(RailShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs, unreadCount: 0)), scaffold: false));
    await tester.pump();
    final rail = tester.getSize(find.ancestor(of: find.byIcon(Icons.star_outline_rounded), matching: find.byType(InkWell)).first);
    expect(rail.height, greaterThanOrEqualTo(48));
    expect(rail.width, greaterThanOrEqualTo(48));

    tester.view.physicalSize = const Size(1400, 900);
    await tester.pumpWidget(layoutHost(host(WideShell(currentIndex: 1, onTap: (_) {}, dashboardItems: tabs, unreadCount: 0)), scaffold: false));
    await tester.pump();
    final tile = find.ancestor(of: find.text('points'.tr), matching: find.byType(AnimatedContainer)).first;
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48), reason: 'a sidebar tab is a 48 px row');
    await tester.pumpWidget(const SizedBox());
  });

  d1340Tests(host);
}

const _learn = ShellMobileGroup('learn', Icons.school_outlined, Icons.school_rounded, 'learn_hub');

/// The student's nine tabs (D-1340): five carry the Learn group.
List<DashboardItem> studentTabs({Set<String> off = const {}}) {
  DashboardItem it(String label, IconData icon, {bool learn = false, int badge = 0}) => DashboardItem(
      icon, icon, label, null, Text('$label page'),
      badge: badge, mobileGroup: learn ? _learn : null, hint: learn ? 'learn_hint_$label' : null);
  return [
    it('home', Icons.home_outlined),
    it('my_courses', Icons.book_outlined),
    it('store', Icons.local_mall_outlined, learn: true, badge: 2),
    it('games', Icons.extension_outlined, learn: true),
    it('quran', Icons.menu_book_outlined, learn: true, badge: 3),
    it('nahw', Icons.translate_outlined, learn: true),
    it('analysis', Icons.analytics_outlined, learn: true),
    it('my_schedule', Icons.calendar_month_outlined),
    it('my_profile', Icons.person_outline),
  ].where((e) => !off.contains(e.label)).toList();
}

class _Bar extends StatefulWidget {
  const _Bar({required this.items});

  final List<DashboardItem> items;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  int index = 0;

  @override
  Widget build(BuildContext context) =>
      MobileShell(currentIndex: index, onTap: (i) => setState(() => index = i), dashboardItems: widget.items);
}

void d1340Tests(Widget Function(Widget) host) {
  group('D-1340 phone bar', () {
    test('slots: nine student tabs → Home · My courses · Learn · Schedule · Profile', () {
      final slots = shellNavSlots(studentTabs());
      expect(slots.length, 5);
      expect(slots[2].group, _learn);
      expect(slots[2].members, [2, 3, 4, 5, 6]);
      expect([for (final s in slots) if (!s.isGroup) s.members.single], [0, 1, 7, 8]);
    });

    test('slots: four items draw no group; one visible member draws the tab itself; the More fallback', () {
      final four = studentTabs(off: {'store', 'games', 'quran', 'nahw', 'analysis'});
      expect(four.length, 4);
      expect(shellNavSlots(four).any((s) => s.isGroup), isFalse);

      final one = studentTabs(off: {'store', 'games', 'quran', 'nahw'});
      final slots = shellNavSlots(one);
      expect(slots.length, 5);
      expect(slots.any((s) => s.isGroup), isFalse, reason: 'analysis alone draws its own tab');

      final plain = [
        for (var i = 0; i < 8; i++) DashboardItem(Icons.circle_outlined, Icons.circle, 't$i', null, const SizedBox()),
      ];
      final more = shellNavSlots(plain);
      expect(more.length, 5);
      expect(more.last.group, ShellMobileGroup.more);
      expect(more.last.members, [4, 5, 6, 7]);
    });

    testWidgets('nine items at 320×640 (ar/en, text 1.3): five slots, no overflow', (tester) async {
      await expectNoLayoutErrors(tester, () => host(MobileShell(currentIndex: 4, onTap: (_) {}, dashboardItems: studentTabs())),
          scaffold: false);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(layoutHost(host(MobileShell(currentIndex: 0, onTap: (_) {}, dashboardItems: studentTabs())), scaffold: false));
      await tester.pump();
      expect(find.byKey(const ValueKey('shell.group.learn')), findsOneWidget);
      expect(find.text('store'.tr), findsNothing, reason: 'the store folds into Learn');
      expect(find.text('5'), findsOneWidget, reason: 'the Learn slot sums its members (2 + 3)');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a tap on Learn opens the sheet; a row switches the tab and marks the slot active', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 780);
      addTearDown(tester.view.resetPhysicalSize);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(layoutHost(host(_Bar(items: studentTabs())), scaffold: false));
      await tester.pump();
      final slot = find.byKey(const ValueKey('shell.group.learn'));
      expect(tester.getSemantics(slot), isNot(containsSemantics(isSelected: true)));
      await tester.tap(slot);
      await tester.pumpAndSettle();
      expect(find.byType(ShellGroupSheet), findsOneWidget);
      for (final l in ['store', 'games', 'quran', 'nahw', 'analysis']) {
        final row = find.byKey(ValueKey('shell.group.row.$l'));
        expect(row, findsOneWidget);
        expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byKey(const ValueKey('shell.group.row.quran')));
      await tester.pumpAndSettle();
      expect(find.byType(ShellGroupSheet), findsNothing);
      expect(tester.state<_BarState>(find.byType(_Bar)).index, 4);
      expect(tester.getSemantics(slot), containsSemantics(isSelected: true));
      // the sheet marks the open tab
      await tester.tap(slot);
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.descendant(of: find.byKey(const ValueKey('shell.group.row.quran')), matching: find.byType(Semantics)).first),
          containsSemantics(isSelected: true));
      handle.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the group sheet: no overflow at 320×640 and 1400×900, ar/en, text 1.3', (tester) async {
      final tabs = studentTabs();
      await expectNoLayoutErrors(
          tester,
          () => host(SingleChildScrollView(
              child: ShellGroupSheet(title: 'learn_hub'.tr, items: tabs, members: const [2, 3, 4, 5, 6], current: 4, onPick: (_) {}))));
    });
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.name, required this.created});

  final String name;
  final List<String> created;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.name);
  }

  @override
  Widget build(BuildContext context) =>
      Text('${widget.name} #${widget.created.where((n) => n == widget.name).length}');
}
