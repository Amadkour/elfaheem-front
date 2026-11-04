// The Super Admin global search (admin_global_search.dart): the response parser, the local page match, the
// controller's rules (nothing under 2 characters, debounce, stale answers ignored, errors), and the panel's layout
// and keyboard (arrows + Enter).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_global_search.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout_harness.dart';

const _response = {
  'q': 'sa',
  'groups': [
    {
      'kind': 'students',
      'total': 12,
      'items': [
        {'id': 7, 'label': 'سارة أحمد', 'sub': 'sara@example.test', 'username': 'sara', 'status': 'active'},
        {'id': 9, 'label': 'Sami', 'sub': null, 'username': null, 'status': 'inactive'},
      ],
    },
    {
      'kind': 'courses',
      'total': 1,
      'items': [
        {'id': 3, 'label': 'Physics 101', 'sub': 'Dr. Omar', 'username': null, 'status': 'published'},
      ],
    },
    {'kind': 'payments', 'total': 0, 'items': []},
  ],
};

List<AdminSearchPage> _pages(void Function(String) opened) => [
      AdminSearchPage(label: 'Payments', desc: 'Every payment and refund', group: 'Finance', icon: Icons.receipt_long_rounded, onOpen: () => opened('payments')),
      AdminSearchPage(label: 'Payout requests', desc: 'Teacher withdrawals', group: 'Finance', icon: Icons.account_balance_wallet_rounded, onOpen: () => opened('payouts')),
      AdminSearchPage(label: 'Theme', desc: 'Colours and the logo', group: 'Configuration', icon: Icons.palette_rounded, onOpen: () => opened('theme')),
    ];

Future<void> _wait([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  setUpAll(() => translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>);
  setUp(() => AppConfig.lang = 'en');

  test('parseAdminSearch reads the groups and drops empty ones', () {
    final g = parseAdminSearch(_response);
    expect([for (final x in g) x.kind], ['students', 'courses']);
    expect(g.first.total, 12);
    expect(g.first.items.first.username, 'sara');
    expect(g.first.items.last.sub, isNull);
    expect(parseAdminSearch(null), isEmpty);
    expect(parseAdminSearch({'groups': 'x'}), isEmpty);
  });

  test('matchAdminPages needs every word, label hits first', () {
    final p = _pages((_) {});
    expect([for (final x in matchAdminPages(p, 'pay')) x.label], ['Payments', 'Payout requests']);
    expect([for (final x in matchAdminPages(p, 'finance withdrawals')) x.label], ['Payout requests']);
    expect(matchAdminPages(p, 'zzz'), isEmpty);
    expect(matchAdminPages(p, '  '), isEmpty);
  });

  test('nothing is sent under two characters; pages still match', () async {
    var sent = 0;
    final c = AdminSearchController(
        pages: _pages((_) {}),
        debounce: const Duration(milliseconds: 5),
        search: (q) async {
          sent++;
          return [];
        });
    c.setQuery('p');
    await _wait(30);
    expect(sent, 0);
    expect(c.loading, isFalse);
    expect([for (final r in c.selectable) r.page!.label], ['Payments', 'Payout requests']);
    c.dispose();
  });

  test('typing bursts send ONE request after the debounce', () async {
    final queries = <String>[];
    final c = AdminSearchController(
        pages: const [],
        debounce: const Duration(milliseconds: 20),
        search: (q) async {
          queries.add(q);
          return parseAdminSearch(_response);
        });
    c.setQuery('sa');
    c.setQuery('sar');
    c.setQuery('sara');
    expect(c.loading, isTrue);
    await _wait(80);
    expect(queries, ['sara']);
    expect(c.loading, isFalse);
    expect(c.rows.where((r) => r.hit != null).length, 3);
    c.dispose();
  });

  test('a stale answer never replaces a newer one', () async {
    final slow = Completer<List<AdminSearchGroup>>();
    final fast = Completer<List<AdminSearchGroup>>();
    final c = AdminSearchController(pages: const [], debounce: Duration.zero, search: (q) => q == 'ab' ? slow.future : fast.future);
    c.setQuery('ab');
    await _wait(10);
    c.setQuery('abc');
    await _wait(10);
    fast.complete(parseAdminSearch({'groups': [{'kind': 'courses', 'total': 1, 'items': [{'id': 1, 'label': 'NEW'}]}]}));
    await _wait(10);
    slow.complete(parseAdminSearch({'groups': [{'kind': 'courses', 'total': 1, 'items': [{'id': 2, 'label': 'OLD'}]}]}));
    await _wait(10);
    expect([for (final r in c.rows) r.hit?.label].whereType<String>(), ['NEW']);
    c.dispose();
  });

  test('a failed search keeps the pages and reports the error; Retry runs it again', () async {
    var fail = true;
    final c = AdminSearchController(
        pages: _pages((_) {}),
        debounce: Duration.zero,
        search: (q) async {
          if (fail) throw StateError('boom');
          return parseAdminSearch(_response);
        });
    c.setQuery('pay');
    await _wait(10);
    expect(c.error, isNotNull);
    expect(c.rows.where((r) => r.page != null), isNotEmpty);
    fail = false;
    await c.run();
    expect(c.error, isNull);
    expect(c.groups, isNotEmpty);
    c.dispose();
  });

  test('arrow keys wrap around the selectable rows only', () {
    final c = AdminSearchController(pages: _pages((_) {}), search: (_) async => []);
    c.setQuery('pay'); // 2 pages (a header is not selectable)
    expect(c.active, 0);
    c.move(1);
    expect(c.active, 1);
    c.move(1);
    expect(c.active, 0);
    c.move(-1);
    expect(c.active, 1);
    c.dispose();
  });

  testWidgets('the panel lays out everywhere with pages, people and a failure', (tester) async {
    for (final mode in ['results', 'error']) {
      await expectNoLayoutErrors(
        tester,
        () {
          final c = AdminSearchController(
              pages: _pages((_) {}),
              debounce: Duration.zero,
              search: (q) async {
                if (mode == 'error') throw StateError('boom');
                return parseAdminSearch(_response);
              });
          addTearDown(c.dispose);
          return SizedBox(height: 600, child: AdminSearchPanel(controller: c, wide: true, onSelect: (_) {}));
        },
        act: (t) async {
          await t.enterText(find.byType(TextField), 'sa pay');
          await t.pump(const Duration(milliseconds: 50));
        },
      );
    }
  });

  testWidgets('Down + Enter selects the second row', (tester) async {
    AppConfig.lang = 'en';
    AdminSearchRow? picked;
    final c = AdminSearchController(pages: _pages((_) {}), debounce: Duration.zero, search: (q) async => parseAdminSearch(_response));
    addTearDown(c.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(layoutHost(AdminSearchPanel(controller: c, wide: true, onSelect: (r) => picked = r), scale: 1));
    await tester.enterText(find.byType(TextField), 'pay');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(picked?.page?.label, 'Payout requests');
    await tester.pumpWidget(const SizedBox());
  });
}
