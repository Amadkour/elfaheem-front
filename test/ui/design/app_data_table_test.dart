// AppDataTable / AppPagination / AppSearchField behaviour.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_pagination.dart';
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

class _Row {
  const _Row(this.id, this.name);
  final int id;
  final String name;
}

final _rows = [for (var i = 0; i < 5; i++) _Row(i, 'Student $i')];

List<AppTableColumn<_Row>> _cols() => [
      AppTableColumn.text(key: 'name', label: 'Name', text: (r) => r.name, sortable: true, primary: true),
      AppTableColumn.text(key: 'id', label: 'Number', text: (r) => '${r.id}', numeric: true),
    ];

Future<void> _pump(WidgetTester tester, Widget w, {Size size = const Size(1400, 900)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(layoutHost(w, scale: 1));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  tearDownAll(() => translation = {});
  setUp(() => AppConfig.lang = 'en');

  testWidgets('tapping a sortable header calls onSort(key, !asc)', (tester) async {
    String? key;
    bool? asc;
    await _pump(
      tester,
      AppDataTable<_Row>(
        columns: _cols(),
        rows: _rows,
        sortKey: 'name',
        sortAscending: true,
        onSort: (k, a) {
          key = k;
          asc = a;
        },
      ),
    );
    await tester.tap(find.text('Name'));
    expect(key, 'name');
    expect(asc, false);
  });

  testWidgets('phone width renders cards, not a header row', (tester) async {
    await _pump(tester, AppDataTable<_Row>(columns: _cols(), rows: _rows, onSort: (_, _) {}),
        size: const Size(360, 700));
    expect(find.byKey(const ValueKey('app_table_header')), findsNothing);
    expect(find.text('Student 0'), findsOneWidget);
    expect(find.text('Number'), findsWidgets); // "label: value" lines
    await _pump(tester, AppDataTable<_Row>(columns: _cols(), rows: _rows, onSort: (_, _) {}));
    expect(find.byKey(const ValueKey('app_table_header')), findsOneWidget);
  });

  testWidgets('search debounces and the clear button fires ""', (tester) async {
    final calls = <String>[];
    await _pump(tester, AppDataTable<_Row>(columns: _cols(), rows: _rows, onSearch: calls.add));
    final field = find.byType(TextField);
    await tester.enterText(field, 'a');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(field, 'ab');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(field, 'abc');
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(calls, ['abc']);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(calls, ['abc', '']);
  });

  testWidgets('pagination: next calls onPage(page+1), prev disabled on page 1', (tester) async {
    int? got;
    await _pump(tester, AppPagination(page: 1, pageCount: 5, onPage: (p) => got = p));
    await tester.tap(find.byTooltip('Previous page'));
    expect(got, isNull);
    await tester.tap(find.byTooltip('Next page'));
    expect(got, 2);
  });

  testWidgets('error state: Retry calls onRetry', (tester) async {
    var n = 0;
    await _pump(
      tester,
      AppDataTable<_Row>(
          columns: _cols(), rows: const [], state: AppTableState.error, errorText: 'Boom', onRetry: () => n++),
    );
    expect(find.text('Boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(n, 1);
  });

  testWidgets('selecting two rows shows the bulk bar with the count', (tester) async {
    await _pump(
      tester,
      AppDataTable<_Row>(
        columns: _cols(),
        rows: _rows,
        selectable: true,
        rowId: (r) => r.id,
        bulkActions: (s) => [Text('bulk ${s.length}')],
      ),
    );
    expect(find.textContaining('selected'), findsNothing);
    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(1)); // 0 = header
    await tester.pump();
    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('bulk 2'), findsOneWidget);
  });

  testWidgets('scrolling to the end calls onLoadMore exactly once per cycle', (tester) async {
    var calls = 0;
    final rows = [for (var i = 0; i < 40; i++) _Row(i, 'Student $i')];
    await _pump(
      tester,
      SizedBox(
        height: 500,
        child: AppDataTable<_Row>(columns: _cols(), rows: rows, hasMore: true, onLoadMore: () => calls++),
      ),
    );
    expect(calls, 0);
    for (var i = 0; i < 4; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(calls, 1);
  });

  testWidgets('AppSearchField is a search field for Ctrl+K (search icon + search action)', (tester) async {
    await _pump(tester, AppSearchField(onChanged: (_) {}));
    final tf = tester.widget<TextField>(find.byType(TextField));
    expect(tf.textInputAction, TextInputAction.search);
    expect((tf.decoration!.prefixIcon! as Icon).icon, Icons.search_rounded);
  });
}
