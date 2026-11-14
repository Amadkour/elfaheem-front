// Display & reading: the settings page at every size / language, the preferences model, the text scaler, the
// whole-interface zoom, and the home's Meet-now icon in a crowded header.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/design/home_kit.dart';
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'ar');

  group('DisplayPrefs', () {
    test('clamps the scales and survives a JSON round trip', () {
      final p = const DisplayPrefs().copyWith(textScale: 9, zoom: 0.1, boldText: true, arabicFont: 'readex', latinFont: 'atkinson');
      expect(p.textScale, DisplayPrefs.maxText);
      expect(p.zoom, DisplayPrefs.minZoom);
      expect(DisplayPrefs.fromJson(p.toJson()), p);
    });

    test('unknown or broken values fall back to the defaults', () {
      final p = DisplayPrefs.fromJson({'ar': 'inter', 'en': 'nope', 'text': 'big', 'zoom': null, 'bold': 'yes'});
      expect(p.arabicFont, AppFonts.arabicDefault); // a Latin-only font is never the Arabic choice
      expect(p.latinFont, AppFonts.latinDefault);
      expect(p.textScale, 1.0);
      expect(p.boldText, isFalse);
      expect(p.isDefault, isTrue);
    });

    test('a preset is recognised only while every field matches it', () {
      final easy = DisplaySettings.presets.firstWhere((p) => p.id == 'easy').prefs;
      expect(DisplaySettings.presets.where((p) => p.prefs == easy).single.id, 'easy');
      expect(DisplaySettings.presets.where((p) => p.prefs == easy.copyWith(zoom: 1.0)), isEmpty);
    });
  });

  group('AppFonts', () {
    tearDown(() => AppFonts.setChoices(arabic: AppFonts.arabicDefault, latin: AppFonts.latinDefault));

    test('the family follows the language; the fallback is the other language\'s choice', () {
      AppFonts.setChoices(arabic: 'plex_arabic', latin: 'inter');
      AppConfig.lang = 'ar';
      expect(AppFonts.family, 'uiPlexArabic');
      expect(AppFonts.fallback, ['uiPlexArabic', 'uiInter']);
      AppConfig.lang = 'en';
      expect(AppFonts.family, 'uiInter');
      expect(AppFonts.fallback.last, 'uiPlexArabic');
    });

    test('every option has a distinct (case-insensitive) family and an Arabic option draws Arabic', () {
      final families = AppFonts.catalog.map((f) => f.family.toLowerCase()).toList();
      expect(families.toSet().length, families.length);
      expect(AppFonts.optionsFor('ar').every((f) => f.arabic), isTrue);
      expect(AppFonts.optionsFor('en').length, AppFonts.catalog.length);
    });
  });

  test('UserTextScaler multiplies the system scaler', () {
    const s = UserTextScaler(TextScaler.linear(1.2), 1.5);
    expect(s.scale(10), closeTo(18, 1e-9));
    expect(displayMediaQuery(const MediaQueryData(), const DisplayPrefs()).textScaler, TextScaler.noScaling);
    final mq = displayMediaQuery(const MediaQueryData(), const DisplayPrefs(textScale: 1.25, boldText: true, reduceMotion: true));
    expect(mq.textScaler.scale(10), closeTo(12.5, 1e-9));
    expect(mq.boldText, isTrue);
    expect(mq.disableAnimations, isTrue);
  });

  test('reading spacing: taller lines, wider words, letter spacing only outside Arabic', () {
    const base = TextStyle(fontSize: 14, height: 1.2);
    expect(spacedStyle(base, ReadingSpacing.of(0), 'en'), base);
    final wide = spacedStyle(base, ReadingSpacing.of(2), 'en');
    expect(wide.height, closeTo(1.2 * 1.3, 1e-9));
    expect(wide.wordSpacing, 3);
    expect(wide.letterSpacing, 0.5);
    final ar = spacedStyle(const TextStyle(fontSize: 14), ReadingSpacing.of(1), 'ar');
    expect(ar.height, closeTo(kNaturalLineHeight * 1.15, 1e-9)); // no height → the natural line, spaced
    expect(ar.letterSpacing, isNull); // spaced Arabic letters lose their joins
    expect(ReadingSpacing.of(9), ReadingSpacing.steps.last);
    expect(DisplayPrefs.fromJson(const DisplayPrefs(spacing: 2).toJson()).spacing, 2);
  });

  testWidgets('a decorative loop parks under reduce motion and runs again without it', (tester) async {
    late AnimationController c;
    Widget host(bool still) => MediaQuery(
          data: MediaQueryData(disableAnimations: still),
          child: _Loop(onController: (x) => c = x),
        );
    await tester.pumpWidget(host(false));
    expect(c.isAnimating, isTrue);
    await tester.pumpWidget(host(true));
    expect(c.isAnimating, isFalse);
    expect(c.value, 1.0);
    await tester.pumpWidget(host(false));
    expect(c.isAnimating, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('DisplayZoom lays the child out smaller and draws it at full size', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Size? seen;
    await tester.pumpWidget(MaterialApp(
      home: DisplayZoom(
        zoom: 1.25,
        child: Builder(builder: (context) {
          seen = MediaQuery.sizeOf(context);
          return const SizedBox.expand(key: ValueKey('page'));
        }),
      ),
    ));
    expect(seen, const Size(320, 640));
    expect(tester.getSize(find.byKey(const ValueKey('page'))), const Size(320, 640));
    // drawn scaled: the page's bottom-right corner lands on the screen's
    expect(tester.getBottomRight(find.byKey(const ValueKey('page'))), const Offset(400, 800));
  });

  testWidgets('the settings page has no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => DisplaySettingsView(prefs: const DisplayPrefs(), loadFonts: false, onChanged: (_) {}));
  });

  testWidgets('the settings page at the largest text and zoom has no layout errors', (tester) async {
    const big = DisplayPrefs(textScale: DisplayPrefs.maxText, zoom: DisplayPrefs.maxZoom, boldText: true, largeTargets: true);
    await expectNoLayoutErrors(
      tester,
      () => AppDisplayApply(prefs: big, child: DisplaySettingsView(prefs: big, loadFonts: false, onChanged: (_) {})),
    );
  });

  testWidgets('a preset tap reports that preset\'s prefs', (tester) async {
    AppConfig.lang = 'en';
    DisplayPrefs? got;
    await tester.pumpWidget(layoutHost(DisplaySettingsView(prefs: const DisplayPrefs(), loadFonts: false, onChanged: (p) => got = p)));
    await tester.tap(find.text('Easy reading'));
    expect(got, DisplaySettings.presets.firstWhere((p) => p.id == 'easy').prefs);
  });

  testWidgets('a home header with the Meet-now, calendar and bell icons fits a phone', (tester) async {
    Widget icon(IconData i) => Container(
          padding: const EdgeInsets.all(7),
          margin: const EdgeInsets.all(5),
          child: Icon(i, size: 20),
        );
    await expectNoLayoutErrors(
      tester,
      () => HomeHeader(
        name: 'A very long student name that keeps going and going',
        leading: const CircleAvatar(radius: 20),
        actions: [icon(Icons.video_call_rounded), icon(Icons.event_rounded), icon(Icons.notifications_rounded)],
      ),
    );
  });
}

/// A minimal decorative loop, as the app's shimmers and pulses use syncMotionLoop.
class _Loop extends StatefulWidget {
  const _Loop({required this.onController});
  final ValueChanged<AnimationController> onController;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _c, reverse: true);
    widget.onController(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: _c, child: const SizedBox(width: 10, height: 10));
}
