// The certificate template gallery (D-384): no overflow at any size, the filter and the language toggle, one tap to
// use a design, a failed image is not cached.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_api.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_template_gallery.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 0x1F, 0x15, 0xC4, 0x89, 0, 0, 0, 13, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0, 0, 3, 1, 1, 0, 0x18, 0xDD, 0x8D, 0xB0, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _templates = [
  CertServerTemplate(key: 'classic_gold', nameAr: 'الملكي الكلاسيكي', nameEn: 'Royal classic', orientation: 'landscape', category: 'formal'),
  CertServerTemplate(key: 'academic', nameAr: 'الدبلوم الأكاديمي', nameEn: 'Academic diploma', orientation: 'portrait', category: 'academic'),
  CertServerTemplate(key: 'kids_joy', nameAr: 'نجوم الأطفال', nameEn: 'Kids stars', orientation: 'landscape', category: 'kids'),
];

void main() {
  Widget view({ValueChanged<CertGalleryPick>? onPick, List<String>? asked}) => CertTemplateGalleryView(
        templates: _templates,
        starters: const [],
        initialLang: 'ar',
        colorSeed: '#1F4E8C',
        loader: (key, lang, width, color, {bgHex, bg2Hex}) async {
          asked?.add('$key|$lang');
          return _png;
        },
        onPick: onPick ?? (_) {},
        onClose: () {},
      );

  testWidgets('no layout errors at phone and desktop sizes', (tester) async {
    await expectNoLayoutErrors(tester, () => view());
  });

  testWidgets('the category filter narrows the grid; the language toggle asks for the other render', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final asked = <String>[];
    await tester.pumpWidget(layoutHost(view(asked: asked), scale: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('cert-template-academic')), findsOneWidget);
    expect(asked, contains('classic_gold|ar'));
    await tester.tap(find.text('Kids').hitTestable().evaluate().isEmpty ? find.text('أطفال') : find.text('Kids'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('cert-template-academic')), findsNothing);
    expect(find.byKey(const ValueKey('cert-template-kids_joy')), findsOneWidget);
    await tester.tap(find.text('English').hitTestable().evaluate().isEmpty ? find.text('إنجليزي') : find.text('English'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(asked, contains('kids_joy|en'));
  });

  testWidgets('one tap uses the design, with its own colours', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    CertGalleryPick? got;
    await tester.pumpWidget(layoutHost(view(onPick: (p) => got = p), scale: 1));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('cert-template-classic_gold')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(got?.template?.key, 'classic_gold');
    expect(got?.colorHex, isNull);
  });

  test('the preview cache asks once, four at a time, and retries a failure', () async {
    var calls = 0, running = 0, peak = 0;
    var fail = true;
    Future<Uint8List> fetch(String key, {required String lang, int width = 720, String? colorHex, String? bgHex, String? bg2Hex}) async {
      calls++;
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      running--;
      if (key == 'bad' && fail) throw Exception('no');
      return _png;
    }

    final cache = CertTemplatePreviewCache(fetch);
    await Future.wait([for (var i = 0; i < 9; i++) cache.load('k$i', 'ar', 720, null)]);
    expect(calls, 9);
    expect(peak, lessThanOrEqualTo(4));
    await cache.load('k0', 'ar', 720, null);
    expect(calls, 9, reason: 'a loaded image is not asked for again');
    expect(await cache.load('bad', 'ar', 720, null), isNull);
    fail = false;
    expect(await cache.load('bad', 'ar', 720, null), isNotNull, reason: 'a failed image is retried');
  });
}
