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
    test('sticks to the nearer side', () {
      expect(appAssistantSnap(const Offset(50, 300), screen, EdgeInsets.zero).dx, 12);
      expect(appAssistantSnap(const Offset(300, 300), screen, EdgeInsets.zero).dx, 400 - 54 - 12);
    });

    test('stays inside the safe area vertically', () {
      const pad = EdgeInsets.only(top: 30, bottom: 20);
      expect(appAssistantSnap(const Offset(0, -100), screen, pad).dy, 42);
      expect(appAssistantSnap(const Offset(0, 5000), screen, pad).dy, 800 - 20 - 54 - 12);
    });
  });

  group('layout', () {
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
          tester, () => SingleChildScrollView(child: RagLibraryOverview(library: lib, onUpload: () {}, onSync: () {}, onTry: () {})));
    });
  });
}
