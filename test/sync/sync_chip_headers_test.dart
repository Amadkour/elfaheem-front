// The offline / waiting-writes chip (D-1351) on every header that carries tools (QA_PHASE7 W-7): ScreenAppBar
// (AppHeader's tools, no shell top bar), OrgPageHeader on a phone and on a wide screen. Offline with writes
// waiting draws the chip; online and quiet draws nothing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/offline/sync/sync_status.dart';
import 'package:flutter_education_app/features/org/org_page_header.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import '../ui/org_home_v3_layout_test.dart' show wrapProviders;

const _chip = ValueKey('sync.status.chip');

Future<void> _show(WidgetTester tester, Widget w, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(layoutHost(w, scale: 1));
  await tester.pump(const Duration(milliseconds: 400));
}

void _offlineWithWrites() {
  SyncStatus.instance.setOnline(false);
  SyncStatus.instance.report(SyncStatus.outbox, 2);
}

void _quiet() {
  SyncStatus.instance.setOnline(true);
  SyncStatus.instance.report(SyncStatus.outbox, 0);
}

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');
  tearDown(_quiet);

  final headers = <String, (Widget Function(), Size)>{
    'ScreenAppBar': (() => const ScreenAppBar(title: 'Courses'), const Size(390, 800)),
    'OrgPageHeader, phone': (() => wrapProviders(const OrgPageHeader(title: 'Members')), const Size(390, 800)),
    'OrgPageHeader, wide': (() => wrapProviders(const OrgPageHeader(title: 'Members')), const Size(1400, 900)),
  };

  for (final e in headers.entries) {
    testWidgets('${e.key}: the chip while offline with writes waiting, nothing while quiet', (tester) async {
      final (build, size) = e.value;
      _quiet();
      await _show(tester, build(), size);
      expect(find.byKey(_chip), findsNothing);

      _offlineWithWrites();
      await tester.pump();
      expect(find.byKey(_chip), findsOneWidget);
    });
  }
}
