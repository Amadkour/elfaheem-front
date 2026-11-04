// DeferredPage (lib/core/routing/deferred_screens.dart): a blank page for the first 150 ms, then the skeleton, then
// the screen once the part is loaded; a failed download shows a retry; a part that is loaded builds at once.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() {
    resetDeferredLoads();
    AppConfig.lang = 'en';
  });

  Widget page(String id, Future<void> Function() load, {DeferredLook look = DeferredLook.page}) =>
      layoutHost(DeferredPage(id: id, load: load, look: look, builder: (_) => const Text('loaded screen')), scaffold: false);

  testWidgets('placeholder (quiet, then skeleton) -> the screen', (tester) async {
    final gate = Completer<void>();
    await tester.pumpWidget(page('a', () => gate.future));
    expect(find.byType(AppListSkeleton), findsNothing); // quiet for the first 150 ms
    expect(find.text('loaded screen'), findsNothing);
    await tester.pump(kDeferredQuietTime + const Duration(milliseconds: 10));
    expect(find.byType(AppListSkeleton), findsOneWidget);
    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('loaded screen'), findsOneWidget);
    expect(find.byType(AppListSkeleton), findsNothing);
  });

  testWidgets('a fast load never shows the skeleton', (tester) async {
    await tester.pumpWidget(page('b', () async {}));
    await tester.pump();
    expect(find.text('loaded screen'), findsOneWidget);
    expect(find.byType(AppListSkeleton), findsNothing);
    await tester.pump(const Duration(seconds: 1)); // the quiet timer was cancelled
  });

  testWidgets('a failed load shows a retry; retrying loads the screen', (tester) async {
    var calls = 0;
    Future<void> load() async {
      calls++;
      if (calls == 1) throw StateError('offline');
    }

    await tester.pumpWidget(page('c', load));
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('loaded screen'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.text('loaded screen'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('a part that is already loaded builds in the first frame and is not loaded twice', (tester) async {
    var calls = 0;
    Future<void> load() async => calls++;
    await tester.pumpWidget(page('d', load));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page('d', load));
    expect(find.text('loaded screen'), findsOneWidget); // no pump in between
    expect(calls, 1);
  });

  testWidgets('concurrent pages share one download', (tester) async {
    var calls = 0;
    final gate = Completer<void>();
    Future<void> load() {
      calls++;
      return gate.future;
    }

    final a = loadDeferred('e', load), b = loadDeferred('e', load);
    expect(calls, 1);
    gate.complete();
    await Future.wait([a, b]);
  });
}
