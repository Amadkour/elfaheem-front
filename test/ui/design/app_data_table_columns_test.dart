// AppDataTable column extras (D-290 phase 5): dragging a column's edge (remembered, double tap resets, widths shrink to
// fit), `hideBelow`, `maxInlineActions`, the density a cell reads, and a phone with its own card keeping a short toolbar.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_harness.dart';

class _Row {
  const _Row(this.id, this.name);
  final int id;
  final String name;
}

final _rows = [for (var i = 0; i < 3; i++) _Row(i, 'Student $i')];

List<AppTableColumn<_Row>> _cols({double? hideCityBelow}) => [
      AppTableColumn.text(key: 'name', label: 'Name', text: (r) => r.name, primary: true, flex: 3),
      AppTableColumn.text(key: 'city', label: 'City', text: (r) => 'Cairo', flex: 2, hideBelow: hideCityBelow),
      AppTableColumn.text(key: 'score', label: 'Score', text: (r) => '${r.id}', numeric: true, width: 100),
    ];

Widget _table({double? hideCityBelow, int? maxInline, List<AppRowAction<_Row>> Function(_Row)? actions}) => AppDataTable<_Row>(
      rows: _rows,
      rowId: (r) => r.id,
      tableId: 'columns_test',
      columnResize: true,
      columns: _cols(hideCityBelow: hideCityBelow),
      maxInlineActions: maxInline,
      rowActions: actions,
    );

Future<void> _pump(WidgetTester tester, Widget w, {Size size = const Size(1000, 700)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(layoutHost(w, scale: 1));
  await tester.pump(const Duration(milliseconds: 50));
}

double _x(WidgetTester tester, String label) => tester.getTopLeft(find.text(label).first).dx;

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });

  setUp(() {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    debugClearAppTableLayouts();
  });

  test('widths survive the JSON round trip and count as a change', () {
    const l = AppTableLayout(widths: {'city': 180});
    expect(l.isDefault, isFalse);
    final back = AppTableLayout.fromJson(jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>);
    expect(back.widths, {'city': 180.0});
    expect(AppTableLayout.fromJson(const {}).widths, isEmpty, reason: 'a layout saved before this key');
    expect(l.copyWith(hidden: {'x'}).widths, {'city': 180.0});
  });

  testWidgets('dragging an edge resizes the column, is remembered, and a double tap resets it', (tester) async {
    await _pump(tester, _table());
    final before = _x(tester, 'City');
    expect(find.byKey(const ValueKey('app_table_resize_name')), findsNothing, reason: 'the primary column takes the rest');
    await tester.drag(find.byKey(const ValueKey('app_table_resize_city')), const Offset(-60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(_x(tester, 'City'), greaterThan(before + 30), reason: 'City gave up room to Name, the flex column');
    final raw = (await SharedPreferences.getInstance()).getString(AppTableLayout.prefKey('columns_test'))!;
    final stored = AppTableLayout.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(stored.widths.keys, ['city']);

    await tester.pumpWidget(const SizedBox());
    debugClearAppTableLayouts();
    await _pump(tester, _table());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.getSize(find.byKey(const ValueKey('app_table_resize_city'))).height, greaterThan(0));
    final remembered = _x(tester, 'City');

    final handle = find.byKey(const ValueKey('app_table_resize_city'));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 400));
    expect((await SharedPreferences.getInstance()).getString(AppTableLayout.prefKey('columns_test')), isNull);
    expect(_x(tester, 'City'), isNot(remembered));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dragged widths shrink to fit a narrower table: no overflow', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppTableLayout.prefKey('columns_test'): jsonEncode(const AppTableLayout(widths: {'city': 480, 'score': 480}).toJson()),
    });
    await _pump(tester, _table(), size: const Size(760, 700));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Student 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hideBelow leaves a column out of a narrow table, not of a wide one', (tester) async {
    await _pump(tester, _table(hideCityBelow: 900), size: const Size(800, 700));
    expect(find.text('City'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _table(hideCityBelow: 900), size: const Size(1000, 700));
    expect(find.text('City'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('maxInlineActions 0: one menu per row, wherever the actions number', (tester) async {
    var tapped = 0;
    await _pump(
        tester,
        _table(maxInline: 0, actions: (r) => [AppRowAction(icon: Icons.edit, label: 'Edit', onTap: () => tapped++)]));
    expect(find.byIcon(Icons.edit), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a cell reads the density; the toggle changes it', (tester) async {
    final seen = <bool>[];
    await _pump(
        tester,
        AppDataTable<_Row>(tableId: 'density_test', rows: _rows, columns: [
          AppTableColumn(
            key: 'name',
            label: 'Name',
            primary: true,
            cell: (ctx, r) {
              seen.add(AppDataTable.compactOf(ctx));
              return Text(r.name);
            },
          ),
        ]));
    expect(seen.last, isFalse);
    await tester.tap(find.byKey(const ValueKey('app_table_density')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(seen.last, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a phone with its own card has no column or density buttons', (tester) async {
    await _pump(
        tester,
        AppDataTable<_Row>(
          tableId: 'phone_test',
          columnMenu: true,
          rows: _rows,
          columns: _cols(),
          mobileCard: (ctx, r) => Text(r.name),
        ),
        size: const Size(390, 800));
    expect(find.byKey(const ValueKey('app_table_columns')), findsNothing);
    expect(find.byKey(const ValueKey('app_table_density')), findsNothing);
    expect(find.text('Student 0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
