// QA of the certificate studio (agent E, docs/studio_requests/): the defects seen in the 1440 px renders.
//   • the designer's app bar draws the design's name in either script (an Arabic name in the English app drew
//     only its "—": the Latin UI font has no Arabic glyphs, the other language's font is the fallback);
//   • the layers list in the desktop's 224 px column keeps the SELECTED row's name (its lock / delete fold into one
//     "more" menu) instead of showing only icons;
//   • the studio toolbar never clips its last command: labels only where the labelled bar fits, and a bar that
//     still does not fit shows a chevron on the cut edge that scrolls it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/studio/studio.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_designer_panels.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/cert_studio_adapter.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_provider.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designer_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

StudioController<CertField> _controller() {
  var slice = const CertLangSlice(fields: [
    CertField(id: 't', kind: CertFieldKind.text, text: 'Hello', x: 100, y: 100, w: 300),
    CertField(id: 'q', kind: CertFieldKind.qr, x: 600, y: 400, w: 90),
  ], orientation: 'landscape');
  final c = StudioController<CertField>(
    adapter: CertStudioAdapter(lang: 'en', read: () => slice, write: (s) => slice = s),
    page: const StudioPage(1000, 707),
  );
  c.select('t');
  return c;
}

Future<void> _pumpAt(WidgetTester t, double width, Widget child) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width + 40, 600);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(const SizedBox());
  await t.pumpWidget(layoutHost(
    Align(alignment: AlignmentDirectional.topStart, child: SizedBox(width: width, child: child)),
    scale: 1,
  ));
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

ScrollPosition _toolbarScroll(WidgetTester t) => t
    .state<ScrollableState>(find.descendant(of: find.byType(StudioToolbar), matching: find.byType(Scrollable)).first)
    .position;

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() {
    AppConfig.disableList = [];
    AppConfig.lang = 'en';
  });

  group('layers list in the desktop column', () {
    for (final lang in ['en', 'ar']) {
      testWidgets('the selected row keeps its name; lock and delete in its menu ($lang)', (t) async {
        AppConfig.lang = lang;
        String? deleted, locked;
        await _pumpAt(
          t,
          224,
          SizedBox(
            height: 400,
            child: CertLayersList(
              fields: const [
                CertField(id: 'a', kind: CertFieldKind.text, text: 'x', name: 'Serial number'),
                CertField(id: 'b', kind: CertFieldKind.qr, w: 90, name: 'Verification QR'),
              ],
              arabic: lang == 'ar',
              selectedId: 'a',
              onSelect: (_) {},
              onToggleVisible: (_) {},
              onToggleLock: (id) => locked = id,
              onReorder: (_, _) {},
              onDelete: (id) => deleted = id,
            ),
          ),
        );
        expect(t.takeException(), isNull);
        final name = find.text('Serial number');
        expect(name, findsOneWidget);
        expect(t.getSize(name).width, greaterThan(70), reason: 'the name has room beside the actions');

        await t.tap(find.byTooltip('more'.tr));
        await t.pumpAndSettle();
        await t.tap(find.text('certd_lock'.tr));
        await t.pumpAndSettle();
        expect(locked, 'a');
        await t.tap(find.byTooltip('more'.tr));
        await t.pumpAndSettle();
        await t.tap(find.text('certd_delete'.tr));
        await t.pumpAndSettle();
        expect(deleted, 'a');
      });
    }

    testWidgets('a wide list (the phone sheet) keeps its separate buttons', (t) async {
      await _pumpAt(
        t,
        420,
        SizedBox(
          height: 300,
          child: CertLayersList(
            fields: const [CertField(id: 'a', kind: CertFieldKind.text, text: 'x', name: 'Serial number')],
            arabic: false,
            selectedId: 'a',
            onSelect: (_) {},
            onToggleVisible: (_) {},
            onToggleLock: (_) {},
            onDelete: (_) {},
          ),
        ),
      );
      expect(find.byTooltip('more'.tr), findsNothing);
      expect(find.byTooltip('certd_lock'.tr), findsOneWidget);
      expect(find.byTooltip('certd_delete'.tr), findsOneWidget);
    });
  });

  group('studio toolbar', () {
    testWidgets('wide enough: every label, nothing to scroll', (t) async {
      final c = _controller();
      addTearDown(c.dispose);
      await _pumpAt(t, 1500, CertToolbarRow(controller: c));
      expect(find.text('studio_undo'.tr), findsOneWidget);
      expect(_toolbarScroll(t).maxScrollExtent, 0);
      expect(find.byTooltip('studio_scroll_more'.tr), findsNothing);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('the 1440 px canvas column: the whole bar shows, nothing clipped ($lang)', (t) async {
        AppConfig.lang = lang;
        final c = _controller();
        addTearDown(c.dispose);
        await _pumpAt(t, 860, CertToolbarRow(controller: c));
        expect(t.takeException(), isNull);
        // the labelled bar does not fit 860 px: it drops its labels rather than cut its last command
        expect(_toolbarScroll(t).maxScrollExtent, 0);
        expect(find.byTooltip('studio_scroll_more'.tr), findsNothing);
      });

      testWidgets('too narrow even for the icons: a chevron on the cut edge scrolls on ($lang)', (t) async {
        AppConfig.lang = lang;
        final c = _controller();
        addTearDown(c.dispose);
        await _pumpAt(t, 360, CertToolbarRow(controller: c));
        expect(_toolbarScroll(t).maxScrollExtent, greaterThan(0));
        expect(find.byTooltip('studio_scroll_back'.tr), findsNothing);
        await t.tap(find.byTooltip('studio_scroll_more'.tr));
        await t.pumpAndSettle();
        expect(_toolbarScroll(t).pixels, greaterThan(0));
        expect(find.byTooltip('studio_scroll_back'.tr), findsOneWidget);
        // scrolled on, the "earlier tools" chevron sits on the start edge (the right in Arabic)
        final bar = t.getRect(find.byType(StudioToolbar));
        final cue = t.getRect(find.byTooltip('studio_scroll_back'.tr));
        expect(lang == 'ar' ? cue.center.dx > bar.center.dx : cue.center.dx < bar.center.dx, isTrue,
            reason: 'the "earlier tools" chevron is on the start edge');
      });
    }
  });

  group('a locked layer in the properties panel', () {
    Future<List<String>> pumpProps(WidgetTester t, {required bool locked}) async {
      final edits = <String>[];
      await _pumpAt(
        t,
        360,
        SizedBox(
          height: 560,
          child: SingleChildScrollView(
            child: CertFieldProps(
              field: CertField(id: 'l', kind: CertFieldKind.logo, x: 40, y: 50, w: 120, h: 80, rotation: 10, locked: locked),
              arabic: false,
              onEdit: (change, {label = 'edit', coalesce = true}) => edits.add(label),
              onText: (_) {},
              onDelete: () {},
            ),
          ),
        ),
      );
      return edits;
    }

    Iterable<StudioStepper> placeSteppers(WidgetTester t) => t
        .widgetList<StudioStepper>(find.byType(StudioStepper))
        .where((s) => const {'X', 'Y'}.contains(s.label) || s.label == 'certd_w'.tr || s.label == 'certd_h'.tr || s.label == 'certd_rotation'.tr);

    testWidgets('X / Y / W / H / rotation are read-only and the turn buttons do nothing', (t) async {
      final edits = await pumpProps(t, locked: true);
      expect(placeSteppers(t).length, 5);
      expect(placeSteppers(t).every((s) => !s.enabled), isTrue);
      expect(find.text('certd_locked_position'.tr), findsOneWidget);
      for (final f in t.widgetList<TextField>(find.descendant(of: find.byWidgetPredicate((w) => w is StudioStepper && w.label == 'X'), matching: find.byType(TextField)))) {
        expect(f.enabled, isFalse);
      }
      final turn = t.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.rotate_90_degrees_cw_outlined));
      expect(turn.onPressed, isNull);
      expect(find.byTooltip('certd_delete'.tr), findsNothing, reason: 'a locked layer cannot be deleted');
      expect(edits, isEmpty);
    });

    testWidgets('unlocked: the same fields edit the layer', (t) async {
      final edits = await pumpProps(t, locked: false);
      expect(placeSteppers(t).every((s) => s.enabled), isTrue);
      expect(find.text('certd_locked_position'.tr), findsNothing);
      final turn = find.widgetWithIcon(IconButton, Icons.rotate_90_degrees_cw_outlined);
      await t.ensureVisible(turn);
      await t.tap(turn);
      await t.pump();
      expect(edits, ['rotate']);
    });
  });

  testWidgets('the designer app bar draws an Arabic design name in the English app', (t) async {
    final fake = FakeApi({}, latency: Duration.zero, fallback: (_) => const <String, dynamic>{})..install();
    addTearDown(fake.uninstall);
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1440, 900);
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    const name = 'شهادة التخرج — كلية الهندسة';
    final p = CertificateDesignerProvider(initialLang: 'en', drafts: CertMemoryDraftStore())
      ..adopt(CertDesign.fromJson({
        'id': 9,
        'name': name,
        'orientation': 'landscape',
        'fields': const [],
        'fields_en': const [],
        'can_edit': true,
        'langs': const ['ar', 'en'],
      }));
    final theme = ThemeConfigProvider(api: ApiClient());
    await t.pumpWidget(ThemeConfigScope(
      provider: theme,
      child: MaterialApp(theme: theme.materialTheme(dark: false), home: CertificateDesignerScreen(provider: p)),
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final title = t.widget<Text>(find.descendant(of: find.byType(AppHeader), matching: find.text(name)));
    expect(title.style?.fontFamilyFallback, containsAll(AppFonts.fallback));
    expect(AppFonts.fallback.length, 2, reason: 'the current language font, then the other one');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  });
}
