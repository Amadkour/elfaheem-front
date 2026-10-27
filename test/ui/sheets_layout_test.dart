// Shared sheets / dialogs / wide tables: long content must scroll inside them (320x640 … 1400x900, Arabic + English,
// textScaler 1.3, light + dark, keyboard open) — no overflow and no "ListTile background … invisible" report.
import 'package:flutter/material.dart';
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
}
