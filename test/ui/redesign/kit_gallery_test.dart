// The kit gallery (KIT_SPEC §7.1): builds at both sizes, every section builds with Reduce motion on, role-only in a
// release build, behind the `admin.kit_gallery` kill switch.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/routing/route_roles.dart';
import 'package:flutter_education_app/design/gallery/kit_gallery_page.dart';
import 'package:flutter_education_app/design/gallery/kit_gallery_sections.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';
import 'redesign_harness.dart';

void main() {
  late List<String> savedDisable;

  setUpAll(() {
    final kit = jsonDecode(File('docs/redesign/strings/kit.json').readAsStringSync()) as Map<String, dynamic>;
    translation = {...translation, ...kit};
  });

  setUp(() {
    savedDisable = [...AppConfig.disableList];
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.disableList = savedDisable);

  testWidgets('the page builds at both sizes', (tester) async {
    await expectNoLayoutErrors(tester, () => const KitGalleryPage(), scaffold: false);
  });

  testWidgets('every section builds with Reduce motion on, at both sizes', (tester) async {
    final n = kitGallerySections().length;
    for (var i = 0; i < n; i++) {
      for (final size in layoutSizes) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(kitHost(KitGalleryPage(key: ValueKey(i), initialSection: i), reduce: true));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'section $i at $size');
      }
    }
    tester.view.reset();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the kill switch shows the coming-soon page', (tester) async {
    AppConfig.disableList = [kKitGalleryKey];
    await tester.pumpWidget(kitHost(const KitGalleryPage(), reduce: true));
    await tester.pump();
    expect(find.text('coming_soon'.tr), findsOneWidget);
  });

  test('a student is sent home in a release build; a super admin and a developer open it', () {
    debugOpenRoutesEnabled = false;
    addTearDown(() => debugOpenRoutesEnabled = true);
    expect(routeRoleRedirect('/kit_gallery', role: 'student', homeRoute: '/dashboard'), '/dashboard');
    expect(routeRoleRedirect('/kit_gallery', role: 'teacher', homeRoute: '/teacher_dashboard'), '/teacher_dashboard');
    expect(routeRoleRedirect('/kit_gallery', role: 'super-admin', homeRoute: '/admin_dashboard'), isNull);
    expect(routeRoleRedirect('/kit_gallery', role: 'developer', homeRoute: '/admin_dashboard'), isNull);
    debugOpenRoutesEnabled = true;
    expect(routeRoleRedirect('/kit_gallery', role: 'student', homeRoute: '/dashboard'), isNull);
  });
}
