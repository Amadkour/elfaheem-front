// Shared sheets / dialogs / wide tables: long content must scroll inside them (320x640 … 1400x900, Arabic + English,
// textScaler 1.3, light + dark, keyboard open) — no overflow and no "ListTile background … invisible" report.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show contrastRatio;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _long = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي — Office of Student Affairs, Graduate Studies and Research';

Widget _opener(void Function(BuildContext) open, {bool dark = false}) => Builder(
      builder: (context) {
        final child = Center(
          child: Builder(builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open'))),
        );
        return dark ? Theme(data: ThemeData.dark(), child: child) : child;
      },
    );

/// The common sheet shape: a header, then a plain Column of many rows — some tappable with a tile colour.
Widget _longSheet(BuildContext ctx) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppSheetHeader(_long),
        for (var i = 0; i < 25; i++)
          ListTile(
            title: Text('$_long $i'),
            tileColor: i.isEven ? Colors.teal.withValues(alpha: 0.07) : null,
            onTap: () {},
          ),
        const TextField(),
      ]),
    );

/// The picker shape: a header and a Flexible shrink-wrapped list.
Widget _pickerSheet(BuildContext ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
      const AppSheetHeader(_long),
      Flexible(
        child: ListView(shrinkWrap: true, children: [
          for (var i = 0; i < 40; i++) ListTile(title: Text('$_long $i'), onTap: () {}),
        ]),
      ),
    ]);

void main() {
  for (final dark in [false, true]) {
    testWidgets('showAppSheet with long content (dark: $dark)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _opener((c) => showAppSheet<void>(c, _longSheet), dark: dark),
        act: (tester) => tester.tap(find.text('open')),
      );
    });

    testWidgets('showAppSheet with a flexible list (dark: $dark)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _opener((c) => showAppSheet<void>(c, _pickerSheet), dark: dark),
        act: (tester) => tester.tap(find.text('open')),
      );
    });

    testWidgets('appConfirm with a very long message (dark: $dark)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => _opener((c) => appConfirm(c, message: List.filled(14, _long).join('\n'), danger: true, confirmLabel: _long),
            dark: dark),
        act: (tester) => tester.tap(find.text('open')),
      );
    });
  }

  testWidgets('showAppSheet with the keyboard open', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await expectNoLayoutErrors(
      tester,
      () => _opener((c) => showAppSheet<void>(c, _longSheet)),
      act: (tester) => tester.tap(find.text('open')),
    );
  });

  testWidgets('AppHScroll with a wide table', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppHScroll(
          child: DataTable(
            columns: [for (var i = 0; i < 12; i++) DataColumn(label: Text('$_long $i'.substring(0, 30)))],
            rows: [
              for (var r = 0; r < 6; r++) DataRow(cells: [for (var i = 0; i < 12; i++) DataCell(Text('$r · $i'))]),
            ],
          ),
        ),
      ]),
    );
  });

  // ── D-710: where a sheet opens, and that it sizes to its content ─────────────────────────────────────────────

  Widget shortSheet(BuildContext ctx) => AppSheetContent(
        title: _long,
        tone: AppTone.danger,
        icon: Icons.delete_outline_rounded,
        children: [
          const Text('two buttons'),
          Row(children: [
            Expanded(child: TextButton(onPressed: () {}, child: const Text('Cancel'))),
            Expanded(child: FilledButton(onPressed: () {}, child: const Text('Delete'))),
          ]),
        ],
      );

  Future<void> open(WidgetTester tester, Size size, void Function(BuildContext) open) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(layoutHost(_opener(open)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('auto: a wide window opens a content-sized dialog, not the side panel', (tester) async {
    await open(tester, const Size(1400, 900), (c) => showAppSheet<void>(c, shortSheet));
    final panel = find.byKey(const ValueKey('app.dialog_sheet.panel'));
    expect(panel, findsOneWidget);
    expect(find.byKey(const ValueKey('app.side_sheet.panel')), findsNothing);
    final box = tester.getRect(panel);
    expect(box.height, lessThan(400), reason: 'two buttons must not take the full height');
    expect(box.center.dx, closeTo(700, 1), reason: 'centred');
    expect(box.width, appSheetDialogWidth);
  });

  testWidgets('auto: a long sheet stops at 85 % of the window and scrolls', (tester) async {
    await open(tester, const Size(1400, 900), (c) => showAppSheet<void>(c, _longSheet));
    final box = tester.getRect(find.byKey(const ValueKey('app.dialog_sheet.panel')));
    expect(box.height, lessThanOrEqualTo(900 * appSheetDialogMaxHeight + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('side: an editor keeps the full-height panel on wide windows', (tester) async {
    await open(tester, const Size(1400, 900), (c) => showAppSheet<void>(c, shortSheet, mode: AppSheetMode.side));
    final box = tester.getRect(find.byKey(const ValueKey('app.side_sheet.panel')));
    expect(box.height, greaterThan(850));
  });

  testWidgets('auto on a phone: a bottom sheet that sizes to its content', (tester) async {
    await open(tester, const Size(360, 740), (c) => showAppSheet<void>(c, shortSheet));
    expect(find.byKey(const ValueKey('app.dialog_sheet.panel')), findsNothing);
    expect(find.byKey(const ValueKey('app.side_sheet.panel')), findsNothing);
    final header = tester.getRect(find.byKey(const ValueKey('app.sheet.header')));
    expect(header.top, greaterThan(740 / 2), reason: 'a short bottom sheet sits low, not at 92 %');
  });

  testWidgets('showAppModalSheet opens the dialog on wide windows too', (tester) async {
    await open(tester, const Size(1400, 900),
        (c) => showAppModalSheet<void>(context: c, builder: (_) => const Padding(padding: EdgeInsets.all(24), child: Text('menu'))));
    expect(find.byKey(const ValueKey('app.dialog_sheet.panel')), findsOneWidget);
  });

  for (final mode in AppSheetMode.values) {
    for (final dark in [false, true]) {
      testWidgets('mode $mode with long and short content (dark: $dark)', (tester) async {
        await expectNoLayoutErrors(
          tester,
          () => _opener((c) => showAppSheet<void>(c, _longSheet, mode: mode), dark: dark),
          act: (tester) => tester.tap(find.text('open')),
        );
        await expectNoLayoutErrors(
          tester,
          () => _opener((c) => showAppSheet<void>(c, shortSheet, mode: mode), dark: dark),
          act: (tester) => tester.tap(find.text('open')),
        );
      });
    }
  }

  testWidgets('the dialog with the keyboard open', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await expectNoLayoutErrors(
      tester,
      () => _opener((c) => showAppSheet<void>(c, _longSheet, mode: AppSheetMode.dialog)),
      act: (tester) => tester.tap(find.text('open')),
    );
  });

  // ── D-711: the toned header band ─────────────────────────────────────────────────────────────────────────────

  for (final dark in [false, true]) {
    testWidgets('every header tone, long title, icon and trailing (dark: $dark)', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => Builder(builder: (context) {
          final child = SingleChildScrollView(
            child: Column(children: [
              for (final tone in AppTone.values)
                AppSheetHeader(_long, tone: tone, icon: Icons.download_rounded, subtitle: _long,
                    trailing: TextButton(onPressed: () {}, child: const Text('Reset'))),
            ]),
          );
          return dark ? Theme(data: ThemeData.dark(), child: child) : child;
        }),
      );
    });

    testWidgets('the title and the icon read at AA on every tone (dark: $dark)', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(layoutHost(Builder(builder: (context) {
        final child = Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        });
        return dark ? Theme(data: ThemeData.dark(), child: child) : child;
      })));
      final c = ctx.colors;
      for (final tone in AppTone.values) {
        final base = appSheetToneColor(ctx, tone);
        final tint = appTintOn(ctx, base);
        expect(contrastRatio(c.textDark, tint), greaterThanOrEqualTo(4.5), reason: 'title on $tone');
        expect(contrastRatio(appInkOnFill(ctx, base), base), greaterThanOrEqualTo(3), reason: 'icon on $tone');
      }
    });
  }
}
