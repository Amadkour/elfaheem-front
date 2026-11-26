// دفتر المادة (S-B, WP10): the panel in view / keyboard / pen / empty at every layout size, the ink's delta
// encoding both ways, and the save path over a 409 note_stale.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/notebook/notebook_api.dart';
import 'package:flutter_education_app/features/notebook/notebook_models.dart';
import 'package:flutter_education_app/features/notebook/notebook_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../support/redesign/sb_notebook_fakes.dart';
import 'layout_harness.dart';

Widget _panel({NotebookMode mode = NotebookMode.view}) => SizedBox.expand(
  child: NotebookPanel(courseId: 41, subjectId: 3, subjectTitle: 'الرياضيات', initialMode: mode),
);

void main() {
  group('ink encoding', () {
    test('absolute points become deltas and come back', () {
      final s = InkStroke(
        tool: InkTool.pen,
        color: '#0F3F2C',
        width: 3,
        points: const [Offset(10, 20), Offset(15, 18), Offset(15.4, 30.6), Offset(4, 2)],
      );
      final wire = s.toWire();
      expect(wire[0], 'pen');
      expect(wire[2], 3);
      expect(wire[3], [10, 20, 5, -2, 0, 13, -11, -29]);
      final back = InkStroke.fromWire(wire)!;
      expect(back.points, const [Offset(10, 20), Offset(15, 18), Offset(15, 31), Offset(4, 2)]);
      expect(back.tool, InkTool.pen);
    });

    test('a dot is sent as two points; the highlighter keeps its tool; bad strokes are dropped', () {
      final dot = InkStroke(tool: InkTool.highlighter, color: '#FFC53D', width: 18, points: const [Offset(3, 4)]);
      expect(dot.toWire()[3], [3, 4, 0, 0]);
      expect(InkStroke.fromWire(dot.toWire())!.tool, InkTool.highlighter);
      expect(InkStroke.fromWire(['pen', '#000000', 3, [1, 2, 3]]), isNull);
      final ink = NoteInk.fromJson({
        'w': 400,
        'h': 360,
        's': [
          ['pen', '#000000', 3, [1, 2, 3, 4]],
          'junk',
        ],
      })!;
      expect(ink.strokes, hasLength(1));
      expect(ink.toJson()['s'], [
        ['pen', '#000000', 3, [1, 2, 3, 4]],
      ]);
    });

    test('a page knows its kind from what it holds', () {
      expect(noteKindOf(const [NoteBlock(NoteBlockKind.heading, 'x')], null), 'typed');
      final ink = NoteInk(width: 10, height: 10, strokes: [InkStroke(tool: InkTool.pen, color: '#000000', width: 2, points: const [Offset(1, 1)])]);
      expect(noteKindOf(const [], ink), 'ink');
      expect(noteKindOf(const [NoteBlock(NoteBlockKind.paragraph, 'x')], ink), 'mixed');
    });
  });

  group('api', () {
    late NotebookFakeStore store;
    late FakeApi fake;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      store = NotebookFakeStore();
      fake = FakeApi(store.routes, latency: Duration.zero)..install();
    });
    tearDown(() => fake.uninstall());

    test('create is idempotent on the client id', () async {
      final api = NotebookApi();
      const draft = NotePage(id: 0, clientId: 'device_page_1', courseId: 41, blocks: [NoteBlock(NoteBlockKind.paragraph, 'سطر')]);
      final a = await api.save(draft);
      final b = await api.save(draft);
      expect(a.id, isNot(0));
      expect(b.id, a.id);
    });

    test('a 409 note_stale is merged: the device text is sent again on the stored version', () async {
      final api = NotebookApi();
      final page = (await api.pages(courseId: 41)).items.firstWhere((p) => p.id == 1);
      store.staleOnce = true; // another device saved in between
      final mine = page.copyWith(blocks: [...page.blocks, const NoteBlock(NoteBlockKind.paragraph, 'من جوالي')]);
      final saved = await api.save(mine);
      expect(saved.blocks.last.text, 'من جوالي');
      expect(saved.version, page.version + 2);
      expect(fake.calls.where((c) => c.method == 'PUT'), hasLength(2));
    });
  });

  group('layout', () {
    late FakeApi fake;
    late NotebookFakeStore store;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
      store = NotebookFakeStore();
      fake = FakeApi(store.routes, latency: const Duration(milliseconds: 10))..install();
    });
    tearDown(() => fake.uninstall());

    testWidgets('view: the ruled pages and the two write buttons', (tester) async {
      await expectNoLayoutErrors(tester, _panel);
    });

    testWidgets('keyboard mode', (tester) async {
      await expectNoLayoutErrors(tester, () => _panel(mode: NotebookMode.type));
    });

    testWidgets('pen mode, with a stroke drawn', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _panel(mode: NotebookMode.pen),
        act: (tester) async {
          final box = find.byType(CustomPaint).last;
          final g = await tester.startGesture(tester.getCenter(box));
          await g.moveBy(const Offset(20, 10));
          await g.moveBy(const Offset(20, -6));
          await g.up();
        },
      );
    });

    testWidgets('empty notebook', (tester) async {
      store.pages.clear();
      await expectNoLayoutErrors(tester, _panel);
    });

    testWidgets('switched off on the server: nothing is drawn', (tester) async {
      store.disabled = true;
      await tester.pumpWidget(layoutHost(_panel()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(NotebookPanelBody), findsOneWidget);
      expect(find.text('sb_nb_write_note'), findsNothing);
    });

    testWidgets('typing a heading and saving adds the page on top', (tester) async {
      await tester.pumpWidget(layoutHost(_panel(mode: NotebookMode.type)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(find.byType(TextField), 'اللوغاريتمات');
      await tester.tap(find.text('sb_nb_save'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(store.pages.values.any((p) => (p['blocks'] as List).any((b) => (b as Map)['x'] == 'اللوغاريتمات')), isTrue);
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
