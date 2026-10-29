// The floating app assistant (where its pop-up and its dropped bubble go), the app assistant's dashboard header,
// and the list skeleton inside another scroll view (the chat's loading state used to throw "Vertical viewport was
// given unbounded height").
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library.dart';
import 'package:flutter_education_app/features/shared/rag/rag_library_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('pop-up placement', () {
    test('a wide window gets a corner card on the end side', () {
      const screen = Size(1400, 900);
      final ltr = appAssistantPanelRect(screen, EdgeInsets.zero, rtl: false);
      expect(ltr.width, 420);
      expect(ltr.right, 1400 - 16);
      expect(ltr.bottom, 900 - 16);
      expect(ltr.height, 680); // capped
      final rtl = appAssistantPanelRect(screen, EdgeInsets.zero, rtl: true);
      expect(rtl.left, 16);
    });

    test('a phone gets almost the whole screen, inside the safe area', () {
      final r = appAssistantPanelRect(const Size(360, 640), const EdgeInsets.only(top: 24, bottom: 16), rtl: false);
      expect(r, const Rect.fromLTRB(8, 32, 352, 616));
    });
  });

  group('bubble snapping', () {
    const screen = Size(400, 800);
    const size = appAssistantBubbleSize;
    test('sticks to the nearer side', () {
      expect(size, 48, reason: 'a 48 dp touch target');
      expect(appAssistantSnap(const Offset(50, 300), screen, EdgeInsets.zero).dx, 12);
      expect(appAssistantSnap(const Offset(300, 300), screen, EdgeInsets.zero).dx, 400 - size - 12);
    });

    test('stays inside the safe area vertically', () {
      const pad = EdgeInsets.only(top: 30, bottom: 20);
      expect(appAssistantSnap(const Offset(0, -100), screen, pad).dy, 42);
      expect(appAssistantSnap(const Offset(0, 5000), screen, pad).dy, 800 - 20 - size - 12);
    });

    test('never over the bottom tab bar, the primary-button strip or the app bar', () {
      const pad = EdgeInsets.only(top: 30, bottom: 20);
      final low = appAssistantSnap(const Offset(0, 5000), screen, pad,
          bottomBar: 70, topClear: kToolbarHeight, bottomClear: appAssistantBottomClear);
      expect(low.dy, 800 - 70 - appAssistantBottomClear - size - 12, reason: 'the bar (70) is taller than the inset (20)');
      final high = appAssistantSnap(const Offset(0, -100), screen, pad,
          bottomBar: 70, topClear: kToolbarHeight, bottomClear: appAssistantBottomClear);
      expect(high.dy, 30 + kToolbarHeight + 12);
      // a window too short for the band: pinned to its top, never negative
      final (minY, maxY) = appAssistantBand(const Size(400, 150), pad, bottomBar: 70, bottomClear: appAssistantBottomClear);
      expect(maxY, minY);
    });

    test('dropped on the hide target', () {
      final target = appAssistantDismissCenter(screen, const EdgeInsets.only(bottom: 20), bottomBar: 70);
      expect(target, const Offset(200, 800 - 70 - 88));
      expect(appAssistantOverDismiss(target + const Offset(20, 20), target), isTrue);
      expect(appAssistantOverDismiss(target + const Offset(0, -120), target), isFalse);
    });

    test('the remembered place survives another window size', () {
      const pad = EdgeInsets.only(top: 24, bottom: 16);
      final band = appAssistantBand(screen, pad, bottomBar: 64, topClear: 56, bottomClear: 72);
      final snapped = appAssistantSnap(const Offset(390, 400), screen, pad, bottomBar: 64, topClear: 56, bottomClear: 72);
      final spot = AppAssistantSpot.fromOffset(snapped, screen, band);
      expect(spot.left, isFalse);
      expect(spot.toOffset(screen, pad, band).dy, closeTo(snapped.dy, 0.001));
      final back = AppAssistantSpot.decode(spot.encode())!;
      expect(back.left, spot.left);
      expect(back.fraction, closeTo(spot.fraction, 0.001));
      // landscape: same side, same relative height, inside the new band
      const land = Size(844, 390);
      final band2 = appAssistantBand(land, pad, topClear: 56, bottomClear: 72);
      final o = back.toOffset(land, pad, band2);
      expect(o.dx, 844 - size - 12);
      expect(o.dy, inInclusiveRange(band2.$1, band2.$2));
      expect(AppAssistantSpot.decode('x:1'), isNull);
      expect(AppAssistantSpot.decode('l:abc'), isNull);
      expect(AppAssistantSpot.decode(null), isNull);
      expect(AppAssistantSpot.fallback(rtl: true).left, isFalse, reason: 'the start side in Arabic is the right');
    });
  });

  group('the bubble choice is remembered per user on this device', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AppAssistantPrefs.instance.debugReset();
    });

    test('hide for one user, the other still sees it, coming back keeps the choice', () async {
      final prefs = AppAssistantPrefs.instance;
      prefs.bind(7);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.bubbleHidden, isFalse);
      await prefs.setBubbleHidden(true);
      expect(prefs.bubbleHidden, isTrue);
      final store = await SharedPreferences.getInstance();
      expect(store.getBool(appAssistantPrefKey('bubble_hidden', 7)), isTrue);
      expect(store.getBool(appAssistantPrefKey('hide_notice', 7)), isTrue, reason: 'the notice is shown once');

      prefs.bind(8);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.bubbleHidden, isFalse, reason: 'another person on the same device');
      prefs.bind(7);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.bubbleHidden, isTrue);
      await prefs.setBubbleHidden(false);
      expect(store.getBool(appAssistantPrefKey('bubble_hidden', 7)), isFalse);
      prefs.bind(null);
      await Future<void>.delayed(Duration.zero);
      expect(prefs.bubbleHidden, isFalse, reason: 'signed out');
    });
  });

  group('layout', () {
    testWidgets('the bubble, its menu and the hide target', (tester) async {
      await expectNoLayoutErrors(tester, () => Center(child: AppAssistantBubble(onTap: () {})));
      await expectNoLayoutErrors(
          tester, () => Center(child: SizedBox(width: 208, child: AppAssistantBubbleMenu(onOpen: () {}, onHide: () {}))));
      for (final active in [false, true]) {
        await expectNoLayoutErrors(
            tester,
            () => LayoutBuilder(
                builder: (context, c) => AppAssistantDismissTarget(
                    center: Offset(c.maxWidth / 2, c.maxHeight - 100), active: active)));
      }
    });

    testWidgets('the settings tiles, and the open tile opens the pop-up', (tester) async {
      await expectNoLayoutErrors(tester,
          () => const SingleChildScrollView(child: AppSettingsGroup(title: 'Settings', children: [AppAssistantOpenTile(), AppAssistantBubbleTile()])));
      AppAssistant.open.value = false;
      await tester.pumpWidget(layoutHost(const AppSettingsGroup(title: 'Settings', children: [AppAssistantOpenTile()])));
      await tester.tap(find.text('assistant_entry_title'.tr));
      expect(AppAssistant.open.value, isTrue);
      AppAssistant.open.value = false;
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the list skeleton inside a ListView (the chat while loading)', (tester) async {
      await expectNoLayoutErrors(tester, () => ListView(children: const [Text('above'), AppListSkeleton(items: 2), Text('below')]));
    });

    testWidgets('the app assistant dashboard header', (tester) async {
      final lib = RagLibrary.fromJson({
        'manager': true,
        'items': [
          {'id': 1, 'title': 'User guide', 'filename': 'guide.pdf', 'status': 'ready', 'scope': 'app', 'size': 2048000, 'chunks': 140},
          {'id': 2, 'title': 'FAQ', 'filename': 'faq.docx', 'status': 'processing', 'scope': 'app', 'size': 30000},
          {'id': 3, 'title': 'Old', 'filename': 'old.pdf', 'status': 'failed', 'scope': 'app'},
        ],
      });
      await expectNoLayoutErrors(
          tester, () => SingleChildScrollView(child: RagLibraryOverview(library: lib, onUpload: () {}, onSync: () {}, onGuide: () {}, onTry: () {})));
    });
  });
}
