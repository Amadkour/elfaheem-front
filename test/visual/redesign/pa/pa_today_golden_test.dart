// Review renders of the parent's Today tab (Pa2Today: today, all, empty, msg) with the CAST family, 390x844 and
// 1360x900, next to D:/platform/redesign-ref/ref/parent/001_* … 004_*. Not a CI suite.
//
//   flutter test test/visual/redesign/pa/pa_today_golden_test.dart --update-goldens [--plain-name all]
@Tags(['visual'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/parent/parent_dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/redesign/pa_fakes.dart';
import '../kit_golden_harness.dart';
import 'pa_golden_harness.dart';

void main() {
  late StorageService storage;
  setUp(() async => storage = await kitGoldenSetUp());

  testWidgets('pa today', (t) => paRender(t, 'today', () => const ParentDashboardScreen(), storage: storage,
      act: (t) => paTap(t, const ValueKey('pa.kid.$paReem'))));
  testWidgets('pa today top', (t) => paRender(t, 'today_top', () => const ParentDashboardScreen(), storage: storage, langs: const ['ar'], grow: false,
      act: (t) => paTap(t, const ValueKey('pa.kid.$paReem'))));
  testWidgets('pa today all', (t) => paRender(t, 'today_all', () => const ParentDashboardScreen(), storage: storage));
  testWidgets('pa today empty', (t) => paRender(t, 'today_empty', () => const ParentDashboardScreen(), storage: storage, api: paApi(kids: 0)));
  testWidgets('pa today msg', (t) => paRender(t, 'today_msg', () => const ParentDashboardScreen(), storage: storage, langs: const ['ar'], grow: false,
      act: (t) async {
        await paTap(t, const ValueKey('pa.kid.$paReem'));
        await paTap(t, const ValueKey('pa.today.message'));
      }));
}
