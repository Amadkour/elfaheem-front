// The certificate studio's workspace (D-387 – D-389): the save status and the one primary action, the phone's sheet
// that follows the selection, the inspector's folded sections, and no overflow at 320 x 640 and 1400 x 900.
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/export_layout/layout_canvas.dart';
import 'package:flutter_education_app/design/export_layout/layout_model.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_inspector.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_panels.dart';
import 'package:flutter_education_app/features/teacher/certificates/studio/cert_engine_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

List<LayoutElement> _elements() => [
      LayoutElement(id: 'a', kind: 'text', x: 20, y: 20, w: 100, h: 12, value: 'Title', style: LayoutStyle(size: 24, align: 'center')),
      LayoutElement(id: 'b', kind: 'qr', x: 150, y: 20, w: 26, h: 26, value: '{{verify_url}}'),
    ];

StudioController<LayoutElement> _ctl(List<LayoutElement> e) => StudioController<LayoutElement>(
      adapter: LayoutElementsAdapter(e, newId: () => 'n${e.length}'),
      page: const StudioPage(297, 210, unitPx: 2),
      grid: const Size(1, 1),
    );

Widget _inspector(StudioController<LayoutElement> ctl) => CertInspector(
      ctl: ctl,
      fields: const [(key: 'student_name', label: 'Student name', numeric: false)],
      upload: (_, _) async => null,
      fontControl: (_, _, _, _) => const SizedBox(key: ValueKey('cert-font'), height: 48),
      pageFont: 'tajawal',
      pageRtl: false,
      memory: <String, bool>{},
      page: const Text('the page'),
    );

Widget _shell(StudioController<LayoutElement> ctl, ValueNotifier<CertSaveState> state, {GlobalKey<CertStudioShellState>? key, VoidCallback? onIssue}) => CertStudioShell(
      key: key,
      ctl: ctl,
      title: 'A long name for a certificate design that does not fit on a phone',
      onRename: () {},
      saveState: state,
      onSave: () {},
      onIssue: onIssue,
      onConflict: () {},
      onPreview: () {},
      onBack: () {},
      languages: const ['ar', 'en'],
      lang: 'ar',
      onLang: (_) {},
      onManageLanguages: () {},
      more: const Icon(Icons.more_horiz_rounded),
      canvas: const ColoredBox(color: Colors.white, child: SizedBox.expand()),
      inspector: _inspector(ctl),
      toolBody: (_, tool) => Text('tool ${tool.name}'),
      emptyPage: (_) => CertEmptyPage(onTemplates: () {}, onAddText: () {}),
      pageCaption: 'A4 · Landscape',
      onPageTap: () {},
      keyboardAction: const SizedBox(width: 8),
    );

void main() {
  late FakeApi fake;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    fake = FakeApi({'GET /api/v1/exports/layout/fonts': (_) => <Object>[]}, latency: Duration.zero)..install();
  });
  tearDown(() => fake.uninstall());

  testWidgets('the status says one thing per state', (tester) async {
    Future<void> show(CertSaveState s) => tester.pumpWidget(layoutHost(CertStatusPill(state: s), scale: 1));
    await show(CertSaveState.saved);
    expect(find.text('All changes saved'), findsOneWidget);
    await show(CertSaveState.unsaved);
    expect(find.text('Unsaved changes'), findsOneWidget);
    await show(CertSaveState.saving);
    expect(find.text('Saving…'), findsOneWidget);
    await show(CertSaveState.conflict);
    expect(find.textContaining('Saved elsewhere'), findsOneWidget);
    expect(find.byKey(const ValueKey('cert-conflict-pill')), findsOneWidget);
  });

  testWidgets('the primary action: Save while unsaved, Issue when clean, a disabled Saved without issuing', (tester) async {
    var saved = 0, issued = 0;
    Future<void> show(CertSaveState s, {bool canIssue = true}) => tester.pumpWidget(layoutHost(
          CertPrimaryAction(state: s, onSave: () => saved++, onIssue: canIssue ? () => issued++ : null),
          scale: 1,
        ));
    await show(CertSaveState.unsaved);
    await tester.tap(find.byKey(const ValueKey('cert-save')));
    expect(saved, 1);
    await show(CertSaveState.saved);
    expect(find.byKey(const ValueKey('cert-save')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cert-issue')));
    expect(issued, 1);
    await show(CertSaveState.saved, canIssue: false);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('cert-save'))).onPressed, isNull);
    await show(CertSaveState.conflict);
    expect(find.byKey(const ValueKey('cert-save')), findsOneWidget, reason: 'a conflict still has something to save');
  });

  testWidgets('a text shows content, font, size, colour, alignment and position; the rest is folded', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final ctl = _ctl(_elements())..select('a');
    addTearDown(ctl.dispose);
    await tester.pumpWidget(layoutHost(SizedBox(width: 320, height: 860, child: _inspector(ctl)), scale: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('cert-font')), findsOneWidget);
    expect(find.text('Size (pt)'), findsOneWidget);
    expect(find.text('Text colour'), findsOneWidget);
    expect(find.byKey(const ValueKey('cert-box-x')), findsOneWidget);
    expect(find.byKey(const ValueKey('cert-letter-spacing')), findsNothing);
    expect(find.byKey(const ValueKey('cert-box-rot')), findsNothing);
    await tester.ensureVisible(find.byKey(const ValueKey('cert-section-spacing')));
    await tester.tap(find.byKey(const ValueKey('cert-section-spacing')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('cert-letter-spacing')), findsOneWidget);

    // another element: the sections it does not have are gone, the page when nothing is selected
    ctl.select('b');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('cert-font')), findsNothing);
    ctl.clearSelection();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('several selected: align and match instead of one element\'s fields', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    final ctl = _ctl(_elements())
      ..select('a')
      ..select('b', additive: true);
    addTearDown(ctl.dispose);
    await tester.pumpWidget(layoutHost(SizedBox(width: 320, height: 860, child: _inspector(ctl)), scale: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 elements selected'), findsOneWidget);
    expect(find.text('Match width'), findsOneWidget);
    expect(find.byKey(const ValueKey('cert-font')), findsOneWidget, reason: 'the font applies to the text among the selection');
  });

  testWidgets('on a phone a selection opens the inspector sheet and clearing it closes the sheet', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final ctl = _ctl(_elements());
    final state = ValueNotifier(CertSaveState.saved);
    addTearDown(ctl.dispose);
    await tester.pumpWidget(layoutHost(_shell(ctl, state), scaffold: false, scale: 1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byKey(const ValueKey('cert-sheet'))).height, 0);
    ctl.select('a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byKey(const ValueKey('cert-sheet'))).height, greaterThan(200));
    expect(find.byKey(const ValueKey('cert-font')), findsOneWidget);
    ctl.clearSelection();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(find.byKey(const ValueKey('cert-sheet'))).height, 0);
  });

  testWidgets('no overflow: the shell, each tool, the sheet, the empty page', (tester) async {
    final state = ValueNotifier(CertSaveState.conflict);
    await expectNoLayoutErrors(tester, () {
      final els = _elements();
      final ctl = _ctl(els);
      return _shell(ctl, state, onIssue: () {});
    }, scaffold: false, frames: 8, act: (t) async {
      for (final tool in ['cert-rail-layers', 'cert-rail-fields', 'cert-rail-templates']) {
        await t.tap(find.byKey(ValueKey(tool)));
        await t.pump(const Duration(milliseconds: 300));
      }
    });
    await expectNoLayoutErrors(tester, () => _shell(_ctl([]), state), scaffold: false, frames: 8);
    await expectNoLayoutErrors(tester, () => const CertDeskPreview(png: null), frames: 8);
    await expectNoLayoutErrors(tester, () => const CertStudioSkeleton(), scaffold: false, frames: 8);
    await expectNoLayoutErrors(
      tester,
      () => StatefulBuilder(builder: (_, _) {
        final d = LayoutDocument.fromJson({
          'designs': {
            'ar': {
              'mode': 'page',
              'page': {'size': 'A4', 'orientation': 'landscape', 'margins': {'top': 0, 'right': 0, 'bottom': 0, 'left': 0}, 'rtl': true, 'font': 'tajawal', 'font_size': 14},
              'row': {'height': 210, 'elements': <Object>[]},
            },
          },
        }).designs['ar']!;
        return SizedBox(width: 320, child: CertPageControls(design: d, onChanged: () {}, pickBackground: () async => null, generateBackground: (_, _, _) async => null, memory: <String, bool>{}));
      }),
      frames: 8,
    );
  });
}
