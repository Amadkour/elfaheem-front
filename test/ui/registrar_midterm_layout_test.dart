// The midterm roster (org_registrar_midterm.dart) lays out at 320×640 and 1400×900, ar / en, text scale 1.3: ready,
// with a locked row, every row locked, empty, a refused save, busy.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/org/org_registrar_midterm.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/registrar_midterm_test.dart' show sampleMidtermJson;
import 'layout_harness.dart';

List<RegMidtermRow> get _rows => RegMidtermRoster.fromJson(sampleMidtermJson()).rows;

Map<int, TextEditingController> _ctrl(List<RegMidtermRow> rows) => {for (final r in rows) if (!r.locked) r.studentId: TextEditingController(text: r.text)};

void main() {
  testWidgets('ready, with a locked row', (tester) async {
    await expectNoLayoutErrors(tester, () => RegMidtermList(rows: _rows, controllers: _ctrl(_rows), onSave: () {}));
  });

  testWidgets('every row locked', (tester) async {
    final rows = [for (final r in _rows) if (r.locked) r];
    await expectNoLayoutErrors(tester, () => RegMidtermList(rows: rows, controllers: const {}));
  });

  testWidgets('empty', (tester) async {
    await expectNoLayoutErrors(tester, () => const RegMidtermList(rows: [], controllers: {}));
  });

  testWidgets('a refused save', (tester) async {
    await expectNoLayoutErrors(tester, () => RegMidtermList(rows: _rows, controllers: _ctrl(_rows), errorText: 'Score must be 0–100', onSave: () {}));
  });

  testWidgets('busy', (tester) async {
    await expectNoLayoutErrors(tester, () => RegMidtermList(rows: _rows, controllers: _ctrl(_rows), busy: true, onSave: () {}));
  });
}
