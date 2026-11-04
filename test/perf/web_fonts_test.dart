// The lazy web fonts (D-171): the prune step's pure functions and LazyFonts, with a fake manifest and a fake
// registrar (no network, no platform).
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_education_app/core/display/lazy_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/web/prune_font_manifest.dart';

List<Map<String, dynamic>> _manifest() => [
      {'family': 'MaterialIcons', 'fonts': [{'asset': 'fonts/MaterialIcons-Regular.otf'}]},
      {'family': 'tajawal', 'fonts': [{'asset': 'a/T-R.ttf'}, {'asset': 'a/T-B.ttf', 'weight': 700}]},
      {'family': 'uiPlexArabic', 'fonts': [{'asset': 'a/P.ttf'}]},
      {'family': 'uiInter', 'fonts': [{'asset': 'a/I.ttf'}]},
      {'family': 'packages/moyasar/ReadexPro', 'fonts': [{'asset': 'packages/moyasar/R.ttf', 'weight': 400}]},
    ];

void main() {
  group('pruneFontManifest', () {
    test('splits the lazy families from the start-up ones', () {
      final r = pruneFontManifest(_manifest());
      expect(r.kept.map((e) => e['family']).toList(), ['MaterialIcons', 'uiPlexArabic']);
      expect(r.removed.map((e) => e['family']).toList(), ['tajawal', 'uiInter', 'packages/moyasar/ReadexPro']);
      expect((r.removed.first['fonts'] as List).length, 2); // the entry is kept whole
    });

    test('is idempotent: a pruned manifest prunes to itself and the earlier lazy entries survive the merge', () {
      final first = pruneFontManifest(_manifest());
      final second = pruneFontManifest(first.kept);
      expect(second.kept, first.kept);
      expect(second.removed, isEmpty);
      final lazy = mergeLazyEntries(first.removed, second.removed);
      expect(lazy, first.removed);
    });

    test('a family seen again replaces its earlier entry', () {
      final a = [{'family': 'tajawal', 'fonts': [{'asset': 'old'}]}];
      final b = [{'family': 'tajawal', 'fonts': [{'asset': 'new'}]}];
      expect(mergeLazyEntries(a, b), b);
    });

    test('the lazy list never holds a family the first frame draws with', () {
      for (final f in ['MaterialIcons', 'packages/cupertino_icons/CupertinoIcons', 'uiPlexArabic', 'NotoSansSC']) {
        expect(lazyFamilies, isNot(contains(f)));
      }
    });
  });

  group('LazyFonts', () {
    late List<String> registered;
    late int manifestReads;

    void arm({bool pruned = true, bool web = true}) {
      LazyFonts.reset();
      registered = [];
      manifestReads = 0;
      LazyFonts.enabled = web;
      LazyFonts.readManifest = () async {
        manifestReads++;
        return pruned ? jsonEncode(pruneFontManifest(_manifest()).removed) : null;
      };
      LazyFonts.register = (family, assets) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        registered.add('$family:${assets.join(',')}');
      };
    }

    tearDown(LazyFonts.reset);

    test('loads a lazy family from its manifest files, once', () async {
      arm();
      await LazyFonts.ensure('tajawal');
      await LazyFonts.ensure('tajawal');
      expect(registered, ['tajawal:a/T-R.ttf,a/T-B.ttf']);
    });

    test('concurrent calls share one future and one manifest read', () async {
      arm();
      final a = LazyFonts.ensure('uiInter');
      final b = LazyFonts.ensure('uiInter');
      final c = LazyFonts.ensureAll(const ['uiInter', 'tajawal']);
      expect(identical(a, b), isTrue);
      await Future.wait([a, b, c]);
      expect(registered.where((r) => r.startsWith('uiInter')).length, 1);
      expect(registered.length, 2);
      expect(manifestReads, 1);
    });

    test('a family that is not lazy in this build is a no-op', () async {
      arm();
      await LazyFonts.ensure('uiPlexArabic');
      expect(registered, isEmpty);
      expect(LazyFonts.isReady('uiPlexArabic'), isTrue);
    });

    test('off the web, and on an unpruned build, nothing is touched', () async {
      arm(web: false);
      await LazyFonts.ensure('tajawal');
      expect(registered, isEmpty);
      expect(manifestReads, 0);
      expect(LazyFonts.isReady('tajawal'), isTrue);
      arm(pruned: false);
      await LazyFonts.ensure('tajawal');
      expect(registered, isEmpty);
    });

    test('a failed load is not remembered: the next call tries again', () async {
      arm();
      var fail = true;
      LazyFonts.register = (family, assets) async {
        if (fail) throw StateError('network');
        registered.add(family);
      };
      await LazyFonts.ensure('bahji'); // not in the fake manifest: harmless
      await LazyFonts.ensure('tajawal');
      expect(registered, isEmpty);
      expect(LazyFonts.isReady('tajawal'), isFalse);
      fail = false;
      await LazyFonts.ensure('tajawal');
      expect(registered, ['tajawal']);
      expect(LazyFonts.isReady('tajawal'), isTrue);
    });

    testWidgets('LazyFontGate hides its child until the family is loaded', (tester) async {
      arm();
      await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: LazyFontGate(families: ['tajawal'], child: Text('hello')),
      ));
      double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
      expect(opacity(), 0);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      expect(opacity(), 1);
      expect(registered.length, 1);
    });
  });
}
