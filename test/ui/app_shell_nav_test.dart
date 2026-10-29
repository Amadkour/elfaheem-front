// Per-tab back stacks of the role shells (lib/design/app_shell_nav.dart, D-081): the pure decisions (what goes to
// the root navigator, what back and a tab tap do), and the shell itself — a page pushed from a tab keeps the tab
// bar, each tab keeps its own stack, a tap on the current tab and the system back pop that stack, dialogs / sheets /
// sign-out still land on the root navigator, a deep link through navigatorKey still lands, topRouteObserver sees
// the page inside the tab, and a full-screen page hides the chrome.
import 'package:flutter/cupertino.dart' show CupertinoModalPopupRoute;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/design/app_shell_nav.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:flutter_education_app/utils/top_route_observer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

Route<void> _page(String? name, {bool fullscreenDialog = false}) => MaterialPageRoute<void>(
    settings: RouteSettings(name: name), fullscreenDialog: fullscreenDialog, builder: (_) => const SizedBox());

void main() {
  group('pure decisions', () {
    test('what a push from inside a tab hands to the root navigator', () {
      expect(shellRouteGoesToRoot(_page('/notifications')), isFalse, reason: 'an ordinary page stays in the tab');
      expect(shellRouteGoesToRoot(_page(null)), isFalse);
      expect(shellRouteGoesToRoot(_page('/course-detail')), isFalse);
      for (final n in ['/login', '/dashboard', '/org_dashboard', '/org_member', '/teacher_dashboard', '/attendance-live']) {
        expect(shellRouteGoesToRoot(_page(n)), isTrue, reason: '$n is a root route');
      }
      expect(shellRouteGoesToRoot(_page('/live/abc')), isTrue, reason: 'guest live link');
      expect(shellRouteGoesToRoot(_page(null, fullscreenDialog: true)), isTrue, reason: 'cropper, forms');
      expect(shellRouteGoesToRoot(RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox())), isTrue, reason: 'dialogs');
      expect(
          shellRouteGoesToRoot(ModalBottomSheetRoute<void>(builder: (_) => const SizedBox(), isScrollControlled: false)),
          isTrue);
      expect(shellRouteGoesToRoot(CupertinoModalPopupRoute<void>(builder: (_) => const SizedBox())), isTrue);
    });

    test('back: the tab first, then the home tab, then out', () {
      expect(shellBackAction(tabCanPop: true, index: 2), ShellBack.popTab);
      expect(shellBackAction(tabCanPop: true, index: 0), ShellBack.popTab);
      expect(shellBackAction(tabCanPop: false, index: 2), ShellBack.homeTab);
      expect(shellBackAction(tabCanPop: false, index: 0), ShellBack.leave);
    });

    test('a tap: another tab switches, the current tab with pages goes back to its root', () {
      expect(shellTapAction(tapped: 1, current: 0, tabCanPop: true), ShellTap.switchTab);
      expect(shellTapAction(tapped: 1, current: 1, tabCanPop: true), ShellTap.popToRoot);
      expect(shellTapAction(tapped: 1, current: 1, tabCanPop: false), ShellTap.none);
    });
  });

  group('the shell', () {
    late StorageService storage;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = await StorageService.getInstance();
      AppConfig.lang = 'en';
    });

    late StateSetter setIndex;
    var index = 0;

    Widget app(double width) {
      index = 0;
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ],
        child: ThemeConfigScope(
          provider: ThemeConfigProvider(api: ApiClient()),
          child: MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [topRouteObserver],
            onGenerateRoute: (s) => switch (s.name) {
              '/' => MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/dashboard'),
                  builder: (_) => StatefulBuilder(builder: (context, set) {
                        setIndex = set;
                        return LayoutBuilder(builder: (context, box) => AppShell(
                          width: box.maxWidth,
                          currentIndex: index,
                          onTap: (i) => set(() => index = i),
                          items: [
                            DashboardItem(Icons.home_outlined, Icons.home, 'Home', null, const _HomeTab()),
                            DashboardItem(Icons.book_outlined, Icons.book, 'Courses', null, const Center(child: Text('courses root'))),
                            DashboardItem(Icons.person_outline, Icons.person, 'Profile', null, const _ProfileTab()),
                          ],
                        ));
                      })),
              '/details' => MaterialPageRoute<void>(settings: s, builder: (_) => const _Details()),
              '/login' => MaterialPageRoute<void>(settings: s, builder: (_) => const Scaffold(body: Text('login page'))),
              '/video' => MaterialPageRoute<void>(
                  settings: s,
                  builder: (context) {
                    AppShellNav.markFullScreen(context);
                    return const Scaffold(body: Text('video page'));
                  }),
              _ => null,
            },
          ),
        ),
      );
    }

    Future<void> pumpApp(WidgetTester tester, double width) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(width));
      await tester.pumpAndSettle();
    }

    Future<void> tearDownApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('phone: a page pushed from a tab keeps the bar; each tab keeps its stack; tap and back pop it',
        (tester) async {
      await pumpApp(tester, 390);
      expect(find.byType(MobileShell), findsOneWidget);
      await tester.tap(find.text('open details'));
      await tester.pumpAndSettle();
      expect(find.text('details page'), findsOneWidget);
      expect(find.text('Courses'), findsOneWidget, reason: 'the bottom bar is still there');
      expect(topRouteObserver.currentRoute?.settings.name, '/details', reason: 'the observer sees the page in the tab');
      expect(topRouteObserver.rootRoute?.settings.name, '/dashboard');

      // another tab, then back: the details page is still on the home tab
      await tester.tap(find.text('Courses'));
      await tester.pumpAndSettle();
      expect(find.text('courses root'), findsOneWidget);
      expect(find.text('details page'), findsNothing);
      expect(topRouteObserver.currentRoute?.settings.name, '/dashboard', reason: 'a tab on its root reports the shell');
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('details page'), findsOneWidget, reason: 'per-tab back stack');

      // a tap on the current tab goes back to its root
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('details page'), findsNothing);
      expect(find.text('open details'), findsOneWidget);

      // system back: the tab's page first, then the home tab, then out
      await tester.tap(find.text('open details'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('open details'), findsOneWidget, reason: 'back popped the tab, not the dashboard');
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      expect(index, 2);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(index, 0, reason: 'back on a non-home tab root goes to the home tab');
      expect(find.text('open details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tearDownApp(tester);
    });

    testWidgets('dialogs, sheets and sign-out go to the root navigator; named pages stay in the tab', (tester) async {
      await pumpApp(tester, 390);
      // a sheet opened inside the tab covers the bar (root navigator)
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsOneWidget);
      expect(navigatorKey.currentState!.canPop(), isTrue, reason: 'the sheet is on the root navigator');
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();

      // sign-out from a tab page: replaces the whole app stack, the shell is gone
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('sign out'));
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tearDownApp(tester);
    });

    testWidgets('deep links: the visible tab through AppShellNav, the root through navigatorKey', (tester) async {
      await pumpApp(tester, 1440);
      expect(find.byType(WideShell), findsOneWidget);
      // AppNavigator pushes into the visible tab: the sidebar stays
      expect(AppShellNav.pushTarget(), isNotNull);
      AppShellNav.pushTarget()!.pushNamed('/details');
      await tester.pumpAndSettle();
      expect(find.text('details page'), findsOneWidget);
      expect(find.text('Courses'), findsOneWidget, reason: 'the sidebar is still there');
      // the root navigator (navigatorKey) still works: a full-screen page above the shell
      navigatorKey.currentState!.pushNamed('/login');
      await tester.pumpAndSettle();
      expect(find.text('login page'), findsOneWidget);
      expect(AppShellNav.pushTarget(), isNull, reason: 'a root page covers the shell');
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('details page'), findsOneWidget);
      // a role home pushed from inside a tab goes to the root navigator, never into the tab
      AppShellNav.pushTarget()!.pushNamed('/login');
      await tester.pumpAndSettle();
      expect(topRouteObserver.rootRoute?.settings.name, '/login');
      expect(tester.takeException(), isNull);
      await tearDownApp(tester);
    });

    testWidgets('a full-screen page inside a tab hides the chrome; leaving brings it back', (tester) async {
      await pumpApp(tester, 390);
      AppShellNav.pushTarget()!.pushNamed('/video');
      await tester.pumpAndSettle();
      expect(find.text('video page'), findsOneWidget);
      expect(find.text('Courses'), findsNothing, reason: 'no bottom bar over the player');
      expect(AppShellNav.bottomBarHeight(), 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Courses'), findsOneWidget);
      expect(AppShellNav.bottomBarHeight(), greaterThan(40));
      expect(tester.takeException(), isNull);
      await tearDownApp(tester);
    });

    testWidgets('rotation across breakpoints keeps the tab stacks', (tester) async {
      await pumpApp(tester, 390);
      await tester.tap(find.text('open details'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(find.byType(RailShell), findsOneWidget);
      expect(find.text('details page'), findsOneWidget, reason: 'the GlobalKey moved the stack into the rail shell');
      expect(tester.takeException(), isNull);
      setIndex(() {});
      await tearDownApp(tester);
    });
  });

  testWidgets('layout: the shells with a pushed page, both languages, phone and desktop', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.getInstance();
    await expectNoLayoutErrors(
      tester,
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
        ],
        child: LayoutBuilder(
          builder: (context, c) => AppShell(width: c.maxWidth, currentIndex: 0, onTap: (_) {}, items: [
            DashboardItem(Icons.home_outlined, Icons.home, 'home', () async {}, const _HomeTab()),
            DashboardItem(Icons.person_outline, Icons.person, 'my_profile', null, const _ProfileTab(), badge: 3),
          ]),
        ),
      ),
      scaffold: false,
      act: (tester) async {
        AppShellNav.pushTarget()?.push(MaterialPageRoute<void>(builder: (_) => const _Details()));
      },
    );
  });
}

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextButton(onPressed: () => Navigator.of(context).pushNamed('/details'), child: const Text('open details')),
            TextButton(
              onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const Text('sheet body')),
              child: const Text('open sheet'),
            ),
          ]),
        ),
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('login page'))), (_) => false),
            child: const Text('sign out'),
          ),
        ),
      );
}

class _Details extends StatelessWidget {
  const _Details();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Details')),
        body: const Center(child: Text('details page')),
      );
}
