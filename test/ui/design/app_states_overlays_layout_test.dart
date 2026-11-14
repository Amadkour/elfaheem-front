// AppErrorState / AppLoadingState / AppStateView and the overlays (dialog, drawer, unsaved guard).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_blocks.dart';
import 'package:flutter_education_app/design/app_buttons.dart';
import 'package:flutter_education_app/design/app_overlays.dart';
import 'package:flutter_education_app/design/app_states.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _longAr = 'هذا عنوان طويل جدا لنافذة تحتوي على كثير من الكلمات العربية لاختبار عدم حدوث أي تجاوز في الشاشة';

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  testWidgets('error states', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        SizedBox(height: 300, child: AppErrorState(message: _longAr, onRetry: () {})),
        AppErrorState(compact: true, message: _longAr, onRetry: () {}),
        const AppErrorState(compact: true),
      ]),
    );
  });

  testWidgets('empty states: plate, headline, one action', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppEmpty(icon: Icons.menu_book_rounded, title: _longAr, message: _longAr, actionLabel: _longAr, onAction: () {}),
        const AppEmpty(icon: Icons.inbox_rounded, title: 'Nothing here yet'),
        const AppEmpty(icon: Icons.event_busy_rounded, title: 'No sessions', message: 'm', tone: AppBlockTone.sky),
        // an action label without a handler shows no button
        const AppEmpty(icon: Icons.inbox_rounded, title: 'x', actionLabel: 'Add'),
        const SizedBox(height: 120, child: AppStatePlate(icon: Icons.school_rounded, size: 80)),
      ]),
    );
  });

  testWidgets('loading states, every shape', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        for (final s in AppLoadingShape.values) AppLoadingState(shape: s, items: 5),
      ]),
    );
  });

  testWidgets('state view: data, empty, loading, error', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppStateView<List<int>>(loading: false, data: const [1, 2], builder: (_, d) => Text('n=${d.length}')),
        AppStateView<List<int>>(
            loading: false, data: const [], isEmpty: (d) => d.isEmpty, builder: (_, d) => Text('n=${d.length}')),
        AppStateView<List<int>>(loading: true, builder: (_, d) => Text('n=${d.length}')),
        AppStateView<List<int>>(
            loading: false, error: Exception('x'), data: const [1], builder: (_, d) => Text('n=${d.length}'), onRetry: () {}),
      ]),
    );
  });

  testWidgets('dialog', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
          builder: (context) => TextButton(
              onPressed: () => showAppDialog<void>(context,
                  title: _longAr,
                  icon: Icons.warning_amber_rounded,
                  danger: true,
                  body: const Text(_longAr),
                  actions: [TextButton(onPressed: () {}, child: const Text('Cancel')), FilledButton(onPressed: () {}, child: const Text('Delete'))]),
              child: const Text('open'))),
      act: (tester) async {
        await tester.tap(find.text('open'));
      },
    );
  });

  testWidgets('drawer (side sheet wide, bottom sheet on phones)', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Builder(
          builder: (context) => TextButton(
              onPressed: () => showAppDrawer<void>(context,
                  title: _longAr,
                  builder: (_) => Column(children: [for (var i = 0; i < 40; i++) Text('row $i')]),
                  actions: [FilledButton(onPressed: () {}, child: const Text('Save'))]),
              child: const Text('open'))),
      act: (tester) async {
        await tester.tap(find.text('open'));
      },
    );
  });

  group('behaviour', () {
    testWidgets('AppStateView keeps stale data and shows a banner when a refresh fails', (tester) async {
      await tester.pumpWidget(layoutHost(AppStateView<String>(
        loading: false,
        error: const ApiException(statusCode: 500, message: 'Server said no'),
        data: 'GOOD DATA',
        builder: (_, d) => Text(d),
        onRetry: () {},
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('GOOD DATA'), findsOneWidget);
      expect(find.text('Server said no'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('AppStateView shows the skeleton only while there is no data', (tester) async {
      await tester.pumpWidget(layoutHost(AppStateView<String>(loading: true, builder: (_, d) => Text(d))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(AppLoadingState), findsOneWidget);
      await tester.pumpWidget(layoutHost(AppStateView<String>(loading: true, data: 'DATA', builder: (_, d) => Text(d))));
      // the skeleton crossfades out (D-582, 260 ms)
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppLoadingState), findsNothing);
      expect(find.text('DATA'), findsOneWidget);
    });

    testWidgets('AppEmpty shows its one action only with a handler, and the action fires', (tester) async {
      var fired = 0;
      await tester.pumpWidget(layoutHost(AppEmpty(icon: Icons.inbox_rounded, title: 'T', actionLabel: 'Go', onAction: () => fired++)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppButton), findsOneWidget);
      await tester.tap(find.text('Go'));
      expect(fired, 1);
      await tester.pumpWidget(layoutHost(const AppEmpty(icon: Icons.inbox_rounded, title: 'T', actionLabel: 'Go')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('a plain exception never leaks its text', (tester) async {
      await tester.pumpWidget(layoutHost(AppStateView<String>(
        loading: false,
        error: Exception('SECRET-STACK-TRACE'),
        builder: (_, d) => Text(d),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.text('Check your connection and try again.'), findsOneWidget);

      await tester.pumpWidget(layoutHost(AppStateView<String>(
        loading: false,
        error: const ApiException(statusCode: 403, message: 'Not allowed here'),
        builder: (_, d) => Text(d),
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Not allowed here'), findsOneWidget);
    });

    Future<double> panelLeft(WidgetTester tester, String lang) async {
      AppConfig.lang = lang;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(layoutHost(Builder(
          builder: (context) => TextButton(
              onPressed: () => showAppDrawer<void>(context, title: 'T', builder: (_) => const Text('body')),
              child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final box = find.byKey(const ValueKey('app.drawer.panel'));
      expect(box, findsOneWidget);
      return tester.getTopLeft(box).dx;
    }

    testWidgets('the drawer opens from the end edge: right in LTR, left in RTL', (tester) async {
      final ltr = await panelLeft(tester, 'en');
      expect(ltr, greaterThan(700)); // 1400 - 480
      await tester.pumpWidget(const SizedBox());
      final rtl = await panelLeft(tester, 'ar');
      expect(rtl, 12); // D-360: a floating panel, one margin off the edge
    });

    testWidgets('Esc closes the drawer', (tester) async {
      await panelLeft(tester, 'en');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('app.drawer.panel')), findsNothing);
    });

    testWidgets('AppUnsavedGuard asks when dirty and pops when clean', (tester) async {
      AppConfig.lang = 'en';
      Future<void> open(WidgetTester tester, bool dirty) async {
        await tester.pumpWidget(layoutHost(Builder(
            builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => AppUnsavedGuard(dirty: dirty, child: const Scaffold(body: Text('FORM'))))),
                child: const Text('go')))));
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('FORM'), findsOneWidget);
      }

      await open(tester, true);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FORM'), findsOneWidget);
      await nav.maybePop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FORM'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await open(tester, false);
      await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FORM'), findsNothing);
      expect(find.text('Discard your changes?'), findsNothing);
    });
  });
}
