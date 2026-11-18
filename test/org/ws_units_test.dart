// The teacher workspace's unit and people parts (D-1151 – D-1155) on a phone and a wide window, ar / en, text
// 1.3: the unit card, the unit strip, a person row (plain and selecting), the bulk bar (manager and member) and the
// history timeline. Plain values only, no network.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/workspace/ws_models.dart';
import 'package:flutter_education_app/features/org/workspace/ws_people.dart';
import 'package:flutter_education_app/features/org/workspace/ws_person.dart';
import 'package:flutter_education_app/features/org/workspace/ws_units.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _long = 'قسم الرياضيات والعلوم التطبيقية والهندسة الكهربائية للمرحلة الثانوية العليا';

final _units = [
  const WsUnit(id: 1, nameAr: _long, nameEn: 'Department of Mathematics, Applied Sciences and Electrical Engineering', people: 1234, team: 56, waiting: 12, role: WsUnitRole.head, color: '#3366AA'),
  const WsUnit(id: 2, nameAr: 'اللغة العربية', nameEn: 'Arabic', people: 1, team: 0, role: WsUnitRole.member),
  const WsUnit(id: 3, unitType: 'program', nameAr: 'برنامج', nameEn: 'Program', people: 0, team: 2, waiting: 1, role: WsUnitRole.manager),
];

final _person = WsPerson(
  userId: 7,
  name: 'عبد الرحمن محمد عبد الله الأنصاري الخزرجي',
  username: 'abdulrahman_alansari_long_username',
  kind: WsPersonKind.head,
  title: 'Senior lecturer of applied mathematics and statistics',
  joinedAt: DateTime.utc(2025, 9, 1, 8),
  joinedVia: 'invite',
  email: 'a.very.long.email.address.for.testing@example-university.edu',
  phone: '+201234567890',
);

final _history = [
  WsHistoryRow(id: 1, action: 'dept.member.add', summary: 'Added to the department as a team member with the title Senior lecturer', actorName: 'Admin', at: DateTime.utc(2026, 11, 1, 9)),
  WsHistoryRow(id: 2, action: 'dept.member.title', summary: '', at: DateTime.utc(2026, 11, 1, 12)),
  WsHistoryRow(id: 3, action: 'dept.member.remove', summary: 'Removed', actorName: 'Someone with a long name here', at: DateTime.utc(2026, 10, 3, 9)),
];

void main() {
  testWidgets('unit card + strip', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        for (final u in _units) WsUnitCard(unit: u, isMain: u.id == 1, pinned: u.id != 2, onTap: () {}, onMore: () {}),
        WsUnitStrip(units: _units, selectedId: 1, mainId: 1, onSelect: (_) {}),
      ]),
    );
  });

  testWidgets('person rows', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        WsPersonRow(person: _person, onTap: () {}),
        WsPersonRow(person: _person, selecting: true, selected: true, onTap: () {}),
        const WsPersonRow(person: WsPerson(userId: 8, name: 'A')),
      ]),
    );
  });

  testWidgets('bulk bar', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        WsBulkBar(count: 1234, allSelected: false, onSelectAll: () {}, onExport: () {}, onClose: () {}, onRemove: () {}),
        WsBulkBar(count: 2, allSelected: true, onSelectAll: () {}, onExport: () {}, onClose: () {}),
      ]),
    );
  });

  testWidgets('person hero, facts and history', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        WsPersonHero(person: _person),
        WsPersonFacts(person: _person),
        WsHistoryList(groups: wsHistoryByDay(_history), historyAll: true, hasMore: true, onLoadMore: () {}),
        const WsHistoryList(groups: [], historyAll: false),
      ]),
    );
  });
}
