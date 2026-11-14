// AppDataTable / AppPagination / AppSearchField behaviour.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_data_table.dart';
import 'package:flutter_education_app/design/app_pagination.dart';
import 'package:flutter_education_app/design/app_search_field.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('columns, density, open row, hover (D-290)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      debugClearAppTableLayouts();
    });

    List<AppTableColumn<_Row>> cols3() => [
          ..._cols(),
          AppTableColumn.text(key: 'email', label: 'Email', text: (r) => 's${r.id}@x.org'),
        ];

    Widget table({String? tableId, bool columnMenu = false, Object? current, ValueChanged<_Row>? onHover, int n = 5}) =>
        SizedBox(
          height: 600,
          child: AppDataTable<_Row>(
            columns: cols3(),
            rows: [for (var i = 0; i < n; i++) _Row(i, 'Student $i')],
            rowId: (r) => r.id,
            tableId: tableId,
            columnMenu: columnMenu,
            selectedRowId: current,
            onRowTap: (_) {},
            onRowHover: onHover,
          ),
        );

    Finder header(String text) =>
        find.descendant(of: find.byKey(const ValueKey('app_table_header')), matching: find.text(text));
    Finder inTile(String key, Finder f) => find.descendant(of: find.byKey(ValueKey('app_table_col_$key')), matching: f);
    Finder row(int id) => find.byKey(AppDataTable.rowKey(id));

    Future<void> closeSheet(WidgetTester tester) async {
      await tester.tapAt(const Offset(20, 20)); // the barrier above the sheet
      await tester.pumpAndSettle();
    }

    test('AppTableLayout: stored order merged with new columns, primary never hidden, json round trip', () {
      final cols = cols3();
      const l = AppTableLayout(order: ['email', 'name'], hidden: {'name', 'id'}, density: AppTableDensity.compact);
      expect([for (final c in l.ordered(cols)) c.key], ['email', 'id', 'name']); // id: a column new since, at its default place
      expect([for (final c in l.apply(cols)) c.key], ['email', 'name']);
      final back = AppTableLayout.fromJson(l.toJson());
      expect(back.order, l.order);
      expect(back.hidden, l.hidden);
      expect(back.density, AppTableDensity.compact);
      expect(const AppTableLayout().isDefault, isTrue);
      expect([for (final c in const AppTableLayout().apply(cols)) c.key], ['name', 'id', 'email']);
    });

    testWidgets('hide + reorder persist per tableId and survive a rebuild and a fresh read', (tester) async {
      await _pump(tester, table(tableId: 't1', columnMenu: true));
      expect(header('Number'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app_table_columns')));
      await tester.pumpAndSettle();
      await tester.tap(inTile('id', find.byType(Checkbox)));
      await tester.pump();
      await tester.tap(inTile('email', find.byKey(const ValueKey('up'))));
      await tester.pump();
      await tester.tap(inTile('email', find.byKey(const ValueKey('up'))));
      await tester.pump();
      await closeSheet(tester);

      void expectCustom() {
        expect(header('Number'), findsNothing);
        expect(tester.getTopLeft(header('Email')).dx, lessThan(tester.getTopLeft(header('Name')).dx));
      }

      expectCustom();
      expect(find.textContaining('1 hidden'), findsOneWidget);
      final raw = (await SharedPreferences.getInstance()).getString(AppTableLayout.prefKey('t1'));
      expect(raw, isNotNull);

      await _pump(tester, const SizedBox());
      await _pump(tester, table(tableId: 't1', columnMenu: true));
      expectCustom();

      debugClearAppTableLayouts(); // a new app run: read from SharedPreferences
      await _pump(tester, const SizedBox());
      await _pump(tester, table(tableId: 't1', columnMenu: true));
      await tester.pump();
      expectCustom();

      // another table keeps its defaults
      await _pump(tester, table(tableId: 't2', columnMenu: true));
      await tester.pump();
      expect(header('Number'), findsOneWidget);

      // Reset restores the defaults and forgets them
      await _pump(tester, table(tableId: 't1', columnMenu: true));
      await tester.pump();
      expectCustom();
      await tester.tap(find.byKey(const ValueKey('app_table_columns')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app_table_columns_reset')));
      await tester.pump();
      await closeSheet(tester);
      expect(header('Number'), findsOneWidget);
      expect(tester.getTopLeft(header('Name')).dx, lessThan(tester.getTopLeft(header('Email')).dx));
      expect((await SharedPreferences.getInstance()).getString(AppTableLayout.prefKey('t1')), isNull);
    });

    testWidgets('the primary column cannot be hidden', (tester) async {
      await _pump(tester, table(columnMenu: true));
      await tester.tap(find.byKey(const ValueKey('app_table_columns')));
      await tester.pumpAndSettle();
      final box = tester.widget<Checkbox>(inTile('name', find.byType(Checkbox)));
      expect(box.value, isTrue);
      expect(box.onChanged, isNull);
      await tester.tap(inTile('name', find.byType(Checkbox)));
      await tester.pump();
      await closeSheet(tester);
      expect(header('Name'), findsOneWidget);
    });

    testWidgets('hidden columns leave the phone card too', (tester) async {
      await _pump(tester, table(columnMenu: true), size: const Size(360, 700));
      expect(find.text('Email'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('app_table_columns')));
      await tester.pumpAndSettle();
      await tester.tap(inTile('email', find.byType(Checkbox)));
      await tester.pump();
      await closeSheet(tester);
      expect(find.text('Email'), findsNothing);
      expect(find.text('s0@x.org'), findsNothing);
      expect(find.text('Student 0'), findsOneWidget);
    });

    testWidgets('density: compact rows are shorter, remembered per tableId', (tester) async {
      await _pump(tester, table(tableId: 'd1'));
      expect(find.byKey(const ValueKey('app_table_columns')), findsNothing); // columnMenu off
      expect(tester.getSize(row(0)).height, AppTouch.min);
      await tester.tap(find.byKey(const ValueKey('app_table_density')));
      await tester.pump();
      expect(tester.getSize(row(0)).height, AppSpace.xl + AppSpace.xxs);
      debugClearAppTableLayouts();
      await _pump(tester, const SizedBox());
      await _pump(tester, table(tableId: 'd1'));
      await tester.pump();
      expect(tester.getSize(row(0)).height, AppSpace.xl + AppSpace.xxs);
    });

    testWidgets('selectedRowId draws the open row (wide row and phone card)', (tester) async {
      await _pump(tester, table(current: 2));
      final bar = find.byKey(const ValueKey('app_table_current_bar'));
      expect(bar, findsOneWidget);
      final r = tester.getRect(row(2));
      expect(tester.getCenter(bar).dy, inInclusiveRange(r.top, r.bottom));
      final sem = find.ancestor(of: bar, matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true));
      expect(sem, findsOneWidget);
      await _pump(tester, table(current: 3), size: const Size(360, 700));
      expect(bar, findsOneWidget);
      final r3 = tester.getRect(row(3));
      expect(tester.getCenter(bar).dy, inInclusiveRange(r3.top, r3.bottom));
      await _pump(tester, table());
      expect(bar, findsNothing);
    });

    testWidgets('onRowHover fires once per mouse enter, never for touch', (tester) async {
      final hovered = <int>[];
      await _pump(tester, table(onHover: (r) => hovered.add(r.id)));
      await tester.tap(row(3), warnIfMissed: false); // touch (the cells' padding is not the body box)
      await tester.pump();
      expect(hovered, isEmpty);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(row(1)));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(row(1)) + const Offset(40, 2));
      await tester.pump();
      expect(hovered, [1]);
      await mouse.moveTo(tester.getCenter(row(2)));
      await tester.pump();
      expect(hovered, [1, 2]);
    });

    testWidgets('the header stays put while the rows scroll', (tester) async {
      await _pump(tester, table(n: 40));
      final h = find.byKey(const ValueKey('app_table_header'));
      final top = tester.getTopLeft(h).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(h, findsOneWidget);
      expect(tester.getTopLeft(h).dy, top);
      expect(row(0).hitTestable(), findsNothing);
    });

    testWidgets('a numeric column ends on the end side in Arabic (header and figures aligned)', (tester) async {
      AppConfig.lang = 'ar';
      await _pump(tester, table());
      final label = tester.getTopLeft(header('Number')).dx;
      final figure = tester.getTopLeft(find.text('3')).dx;
      // RTL: the end is the left edge
      expect((label - figure).abs(), lessThan(1));
      expect(label, lessThan(tester.getTopLeft(header('Name')).dx));
    });

    testWidgets('a table without the new options draws no extras and 48 px rows', (tester) async {
      await _pump(
          tester, SizedBox(height: 600, child: AppDataTable<_Row>(columns: cols3(), rows: _rows, rowId: (r) => r.id)));
      expect(find.byKey(const ValueKey('app_table_columns')), findsNothing);
      expect(find.byKey(const ValueKey('app_table_density')), findsNothing);
      expect(find.byKey(const ValueKey('app_table_current_bar')), findsNothing);
      expect(find.byType(AppSearchField), findsNothing);
      expect(tester.getSize(row(0)).height, AppTouch.min);
      expect(tester.getTopLeft(header('Name')).dx, lessThan(tester.getTopLeft(header('Number')).dx));
      expect(tester.getTopLeft(header('Number')).dx, lessThan(tester.getTopLeft(header('Email')).dx));
    });

    testWidgets('pagination: page size choices 20 / 50 / 100 when onPageSize + pageSize are passed', (tester) async {
      int? size;
      await _pump(tester, AppPagination(page: 1, pageCount: 5, onPage: (_) {}, pageSize: 20, onPageSize: (s) => size = s));
      expect(find.text('Rows per page'), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.text('50').last);
      await tester.pumpAndSettle();
      expect(size, 50);
      await _pump(tester, AppPagination(page: 1, pageCount: 5, onPage: (_) {}, pageSize: 20));
      expect(find.text('Rows per page'), findsNothing);
      expect(
        AppPagination(page: 1, pageCount: 5, onPage: (_) {}, pageSize: 25, onPageSize: (_) {}).sizeChoices,
        [20, 25, 50, 100],
      );
    });
  });
}
