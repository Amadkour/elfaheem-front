// AppDataTable / AppPagination / AppSearchField at 320 / 1400 wide, ar + en, textScaler 1.3.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_pagination.dart';
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../layout_harness.dart';

class _Row {
  const _Row(this.id, this.name);
  final int id;
  final String name;
}

final _rows = [for (var i = 0; i < 25; i++) _Row(i, 'اسم طويل جدا للطالب رقم $i Long student name number $i')];

List<AppTableColumn<_Row>> _cols() => [
      AppTableColumn.text(key: 'name', label: 'Name / الاسم', text: (r) => r.name, sortable: true, primary: true, flex: 3),
      AppTableColumn.text(key: 'id', label: 'ID', text: (r) => '${r.id}', numeric: true, sortable: true),
      AppTableColumn.text(key: 'a', label: 'Email address', text: (r) => 'student${r.id}@example.com', flex: 2),
      AppTableColumn.text(key: 'b', label: 'Course', text: (r) => 'Physics ${r.id}'),
      AppTableColumn.text(key: 'c', label: 'Status', text: (r) => 'Active'),
      AppTableColumn.text(key: 'd', label: 'Joined', text: (r) => '2026-01-${r.id + 1}', showOnPhone: false),
    ];

List<AppRowAction<_Row>> _actions(_Row r) => [
      AppRowAction(icon: Icons.edit_outlined, label: 'Edit', onTap: () {}),
      AppRowAction(icon: Icons.copy_outlined, label: 'Copy', onTap: () {}),
      AppRowAction(icon: Icons.delete_outline, label: 'Delete', danger: true, onTap: () {}),
    ];

Widget _table({
  AppTableState state = AppTableState.ready,
  List<_Row>? rows,
  bool selectable = false,
  Set<Object>? selected,
  bool filters = false,
}) {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: AppDataTable<_Row>(
      columns: _cols(),
      rows: rows ?? _rows,
      state: state,
      errorText: 'Server said no',
      onRetry: () {},
      onSearch: (_) {},
      sortKey: 'name',
      onSort: (_, _) {},
      onRowTap: (_) {},
      rowActions: _actions,
      toolbarTrailing: OutlinedButton(onPressed: () {}, child: const Text('Export')),
      filters: filters
          ? [
              AppTableFilter(label: 'Status', options: const [('a', 'Active'), ('b', 'Blocked')], value: 'a', onChanged: (_) {}),
              AppTableFilter(
                  label: 'Course',
                  options: [for (var i = 0; i < 8; i++) ('$i', 'Course $i')],
                  onChanged: (_) {}),
            ]
          : null,
      onClearFilters: () {},
      selectable: selectable,
      selected: selected,
      rowId: (r) => r.id,
      bulkActions: (s) => [TextButton(onPressed: () {}, child: Text('Delete ${s.length}'))],
      pagination: AppPagination(page: 3, pageCount: 20, onPage: (_) {}, total: 345, pageSize: 20, pageSizes: const [10, 20, 50], onPageSize: (_) {}),
    ),
  );
}

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});
  testWidgets('ready, 25 rows, 6 columns', (tester) async {
    await expectNoLayoutErrors(tester, () => _table(filters: true));
  });
  testWidgets('loading', (tester) async {
    await expectNoLayoutErrors(tester, () => _table(state: AppTableState.loading));
  });
  testWidgets('error', (tester) async {
    await expectNoLayoutErrors(tester, () => _table(state: AppTableState.error));
  });
  testWidgets('empty with filters', (tester) async {
    await expectNoLayoutErrors(tester, () => _table(rows: const [], filters: true));
  });
  testWidgets('selection with the bulk bar', (tester) async {
    await expectNoLayoutErrors(tester, () => _table(selectable: true, selected: {0, 1}));
  });
  testWidgets('shrink wrapped in a list', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(children: [
        AppDataTable<_Row>(columns: _cols(), rows: _rows.take(5).toList(), shrinkWrap: true, rowActions: _actions),
      ]),
    );
  });
  group('8 columns with the column menu, density toggle and an open row (D-290)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugClearAppTableLayouts();
    });
    List<AppTableColumn<_Row>> cols8() => [
          ..._cols(),
          AppTableColumn.text(
              key: 'e',
              label: 'A very long header label that must end in an ellipsis',
              text: (r) => '${r.id * 1000}',
              numeric: true),
          AppTableColumn.text(
              key: 'f',
              label: 'المعدل التراكمي للفصل الدراسي الحالي',
              text: (r) => '3.${r.id}',
              numeric: true,
              sortable: true),
        ];
    Widget t8() => Padding(
          padding: const EdgeInsets.all(8),
          child: AppDataTable<_Row>(
            columns: cols8(),
            rows: _rows,
            rowId: (r) => r.id,
            tableId: 'layout.t8',
            columnMenu: true,
            selectedRowId: 2,
            onSearch: (_) {},
            sortKey: 'f',
            onSort: (_, _) {},
            onRowTap: (_) {},
            onRowHover: (_) {},
            rowActions: _actions,
            toolbarTrailing: OutlinedButton(onPressed: () {}, child: const Text('Export')),
            pagination:
                AppPagination(page: 1, pageCount: 9, onPage: (_) {}, total: 170, pageSize: 20, onPageSize: (_) {}),
          ),
        );
    testWidgets('table', (tester) async {
      await expectNoLayoutErrors(tester, t8);
    });
    testWidgets('compact', (tester) async {
      await expectNoLayoutErrors(tester, t8, act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('app_table_density')));
      });
    });
    testWidgets('the Columns sheet', (tester) async {
      await expectNoLayoutErrors(tester, t8, act: (tester) async {
        await tester.tap(find.byKey(const ValueKey('app_table_columns')));
      });
    });
  });
  testWidgets('AppPagination alone', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => AppPagination(page: 7, pageCount: 40, onPage: (_) {}, total: 800, pageSize: 20, pageSizes: const [10, 20, 50], onPageSize: (_) {}),
    );
  });
  testWidgets('AppSearchField alone', (tester) async {
    await expectNoLayoutErrors(tester, () => Padding(padding: const EdgeInsets.all(8), child: AppSearchField(onChanged: (_) {})));
  });
}
