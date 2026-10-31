// The organization dashboard's command palette (D-103): matching (Arabic folding included), the server hits from a
// REAL capture (test/fixtures/payloads/org_search.json), recent items, the controller's debounce / stale-answer rules,
// the panel's arrow keys + Enter, and the Ctrl+K hook (AppCommandPaletteScope in app_keyboard.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_keyboard.dart';
import 'package:flutter_education_app/features/org/org_command_palette.dart';
import 'package:flutter_education_app/features/org/org_command_palette_logic.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart' show layoutHost;

OrgPaletteEntry _page(String key, String label, {String? group, List<String> keywords = const [], VoidCallback? onOpen}) =>
    OrgPaletteEntry(key: key, label: label, icon: Icons.circle, group: group, keywords: keywords, onOpen: onOpen ?? () {});

final _pages = [
  _page('people', 'People'),
  _page('people/members', 'Members', group: 'People'),
  _page('people/departments', 'Departments', group: 'People'),
  _page('academics/registrar', 'Registrar', group: 'Academics', keywords: ['grades']),
  _page('timetable', 'Timetable'),
  _page('services/complaints', 'الشكاوى', group: 'الخدمات'),
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('matching', () {
    test('Arabic folding', () {
      expect(orgPaletteNormalize('  الإدارة   العامّة '), orgPaletteNormalize('الاداره العامة'));
      expect(orgPaletteNormalize('مستشفى'), orgPaletteNormalize('مستشفي'));
      expect(orgPaletteNormalize('ABC'), 'abc');
    });

    test('scores: exact < prefix < word prefix < contains < group / keyword', () {
      expect(orgPaletteScore('members', 'Members'), 0);
      expect(orgPaletteScore('mem', 'Members'), 1);
      expect(orgPaletteScore('join', 'Department join requests'), 2);
      expect(orgPaletteScore('mber', 'Members'), 3);
      expect(orgPaletteScore('grades', 'Registrar', keywords: ['grades']), 4);
      expect(orgPaletteScore('zzz', 'Members'), isNull);
      expect(orgPaletteScore('  ', 'Members'), isNull);
      expect(orgPaletteScore('شكاوي', 'الشكاوى'), 3);
    });

    test('page hits best first', () {
      expect(orgPaletteFilterPages(_pages, 'peo').map((e) => e.key), ['people', 'people/members', 'people/departments']);
      expect(orgPaletteFilterPages(_pages, 'grades').single.key, 'academics/registrar');
      expect(orgPaletteFilterPages(_pages, ''), isEmpty);
    });

    test('arrow keys wrap', () {
      expect(orgPaletteMove(0, 1, 3), 1);
      expect(orgPaletteMove(2, 1, 3), 0);
      expect(orgPaletteMove(0, -1, 3), 2);
      expect(orgPaletteMove(0, 1, 0), -1);
      expect(orgPaletteMove(-1, -1, 3), 2);
    });
  });

  group('server hits (real capture)', () {
    test('departments and people', () {
      final r = OrgSearchResult.fromJson(jsonDecode(File('test/fixtures/payloads/org_search.json').readAsStringSync()));
      expect(r.departments, isNotEmpty);
      expect(r.departments.first.unitType, 'dept');
      expect(r.departments.first.nameEn, isNotEmpty);
      expect(r.people, isNotEmpty);
      expect(r.people.first.memberRole, 'student');
      expect(r.people.first.avatarUrl, isNull);
      expect(orgPaletteRoleLabel(r.people.first.memberRole), 'Student');
      AppConfig.lang = 'ar';
      expect(r.departments.first.name, r.departments.first.nameAr);
    });

    test('broken rows are skipped', () {
      final r = OrgSearchResult.fromJson({'departments': [{'id': 'x'}, 'y', {'id': 3, 'name_en': 'Law'}], 'people': null});
      expect(r.departments.single.id, 3);
      expect(r.people, isEmpty);
      expect(OrgSearchResult.fromJson(null).departments, isEmpty);
    });
  });

  group('recent', () {
    test('newest first, no twice, at most 6; round-trips', () {
      var list = <OrgPaletteRecent>[];
      for (var i = 0; i < 8; i++) {
        list = orgPaletteRemember(list, OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'p$i'));
      }
      list = orgPaletteRemember(list, const OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'p5'));
      expect(list.map((e) => e.key), ['p5', 'p7', 'p6', 'p4', 'p3', 'p2']);
      const dept = OrgPaletteRecent(kind: OrgPaletteKind.dept, key: 'dept:6', dept: OrgPaletteDept(id: 6, nameEn: 'CS'));
      final back = OrgPaletteRecent.fromJson(jsonDecode(jsonEncode(dept.toJson())))!;
      expect(back.dept!.nameEn, 'CS');
      expect(OrgPaletteRecent.fromJson({'kind': 'dept', 'key': 'dept:6'}), isNull); // a department without its data
      expect(OrgPaletteRecent.fromJson({'kind': 'nope', 'key': 'x'}), isNull);
    });

    test('a page I can no longer open drops out of the recent rows', () {
      final c = OrgPaletteController(pages: _pages, recents: const [
        OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'gone'),
        OrgPaletteRecent(kind: OrgPaletteKind.page, key: 'timetable'),
        OrgPaletteRecent(kind: OrgPaletteKind.person, key: 'person:10', person: OrgPalettePerson(userId: 10, name: 'Sara')),
      ]);
      expect(c.showingRecent, isTrue);
      expect(c.rows.map((r) => r.key), ['timetable', 'person:10']);
      c.dispose();
    });
  });

  group('controller', () {
    testWidgets('pages at once; the server 250 ms after typing stops, from 2 letters; a stale answer is ignored', (tester) async {
      {
        final asked = <String>[];
        final pending = <String, Completer<OrgSearchResult>>{};
        var cancels = 0;
        final c = OrgPaletteController(
          pages: _pages,
          search: (q) {
            asked.add(q);
            return (pending[q] = Completer<OrgSearchResult>()).future;
          },
          cancel: () => cancels++,
        );
        c.setQuery('p');
        expect(c.rows.map((r) => r.key).first, 'people');
        expect(c.searching, isFalse); // one letter: pages only
        await tester.pump(const Duration(milliseconds: 300));
        expect(asked, isEmpty);

        c.setQuery('pe');
        await tester.pump(const Duration(milliseconds: 100));
        c.setQuery('peo');
        await tester.pump(const Duration(milliseconds: 249));
        expect(asked, isEmpty);
        await tester.pump(const Duration(milliseconds: 2));
        expect(asked, ['peo']);
        expect(c.searching, isTrue);

        c.setQuery('peop');
        await tester.pump(const Duration(milliseconds: 260));
        expect(asked, ['peo', 'peop']);
        expect(cancels, greaterThanOrEqualTo(1)); // the request in flight was cancelled
        pending['peo']!.complete(const OrgSearchResult(people: [OrgPalettePerson(userId: 1, name: 'Old')]));
        await tester.pump();
        expect(c.rows.any((r) => r.kind == OrgPaletteKind.person), isFalse); // the stale answer is ignored
        pending['peop']!.complete(const OrgSearchResult(
          departments: [OrgPaletteDept(id: 6, nameEn: 'People Affairs')],
          people: [OrgPalettePerson(userId: 2, name: 'Peopleson')],
        ));
        await tester.pump();
        expect(c.searching, isFalse);
        // drawn order: pages, then departments, then people
        expect(c.rows.map((r) => r.kind).toSet().toList(), [OrgPaletteKind.page, OrgPaletteKind.dept, OrgPaletteKind.person]);
        expect(c.rows.length, 5);
        c.move(3);
        expect(c.activeRow!.kind, OrgPaletteKind.dept);
        c.move(2);
        expect(c.active, 0); // wraps
        c.dispose();
      }
    });

    testWidgets('a failed search keeps the pages and says so', (tester) async {
      {
        final c = OrgPaletteController(pages: _pages, search: (q) async => throw Exception('down'));
        c.setQuery('members');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(c.searchFailed, isTrue);
        expect(c.rows.single.key, 'people/members');
        c.dispose();
      }
    });
  });

  group('panel keyboard', () {
    testWidgets('↓ moves, Enter opens the highlighted row', (tester) async {
      final c = OrgPaletteController(pages: _pages);
      addTearDown(c.dispose);
      OrgPaletteRow? opened;
      await tester.pumpWidget(layoutHost(SizedBox(height: 600, child: OrgCommandPalettePanel(controller: c, onSelect: (r) => opened = r, wide: true)), scale: 1));
      expect(find.text('Type to search pages, departments and people'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'peo');
      await tester.pump();
      expect(find.text('Pages'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(c.active, 1);
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pump();
      expect(opened!.key, 'people/members');
    });
  });

  group('Ctrl+K', () {
    testWidgets('opens the palette of the scope on the top route; elsewhere the old behaviour', (tester) async {
      var opened = 0;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: AppCommandPaletteScope(onOpen: () => opened++, child: const Scaffold(body: Text('org'))),
      ));
      expect(AppKeyboard.openPalette(), isTrue);
      expect(opened, 1);
      nav.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('pushed'))));
      await tester.pumpAndSettle();
      expect(AppKeyboard.openPalette(), isFalse); // a page over it: Ctrl+K focuses its search box again
      expect(opened, 1);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: AppCommandPaletteScope(enabled: false, onOpen: () => opened++, child: const Text('off'))));
      expect(AppKeyboard.openPalette(), isFalse); // switched off (org.search): the search box again
      await tester.pumpWidget(const MaterialApp(home: Text('gone')));
      expect(AppKeyboard.openPalette(), isFalse); // unmounted: no longer registered
    });

    testWidgets('the key itself goes through handleKeyDown', (tester) async {
      var opened = 0;
      AppKeyboardSupport.enabledOverride = true;
      addTearDown(() => AppKeyboardSupport.enabledOverride = null);
      await tester.pumpWidget(MaterialApp(
        home: AppKeyboardSupport(child: AppCommandPaletteScope(onOpen: () => opened++, child: const Scaffold(body: Text('org')))),
      ));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(opened, 1);
    });

    testWidgets('the palette is not opened while org.search is off', (tester) async {
      final prev = List<String>.from(AppConfig.disableList);
      addTearDown(() => AppConfig.disableList = prev);
      AppConfig.disableList = [...prev, orgSearchFeatureKey];
      expect(orgPaletteEnabled, isFalse);
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(onPressed: () => showOrgCommandPalette(context, orgId: 1, pages: _pages), child: const Text('open'));
      })));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(OrgCommandPalettePanel), findsNothing);
    });
  });
}
