// The role shells (lib/design/app_shell.dart): WideShell · RailShell · MobileShell at 320x640 and 1400x900,
// Arabic + English, textScaler 1.3; AppShell picks by width; a tab's count = badge + the attention feed, drawn at
// the leaf (the feed's tick repaints the badge without rebuilding the shell); tabs are built on their first visit
// and kept afterwards (LazyTabStack, D-077), and an unbuilt tab still shows its count.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
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
