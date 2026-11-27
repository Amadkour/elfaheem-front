// The UI kit's ratchet (CLAUDE.md "UI kit", D-103 / D-304). Two gates over lib/:
//   1. raw spacing / radius numbers (EdgeInsets, SizedBox width / height, Radius.circular) per file may only go
//      DOWN against test/ui/kit_rules_baseline.json, and a file that is not in the baseline may have none: write
//      AppSpace / AppRadius / AppIconSize tokens (lib/design/app_tokens.dart) instead;
//   2. no SnackBar (showAppNotice), Switch / SwitchListTile (AppSwitch / AppSwitchTile) or dropdown other than
//      AppDropdown outside lib/design.
// After lowering a count, regenerate the baseline: `dart run tool/kit_rules.dart --write` (the counter lives there).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/kit_rules.dart';

void main() {
  test('raw spacing / radius numbers never go up (ratchet)', () {
    final base = jsonDecode(File(baselinePath).readAsStringSync()) as Map<String, dynamic>;
    final allowed = (base['files'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    final now = scanLib();

    final worse = <String>[];
    final better = <String>[];
    for (final e in now.entries) {
      final was = allowed[e.key] ?? 0;
      if (e.value > was) worse.add('${e.key}: ${e.value} raw numbers (baseline $was)');
      if (e.value < was) better.add('${e.key}: $was → ${e.value}');
    }
    for (final e in allowed.entries) {
      if (!now.containsKey(e.key)) better.add('${e.key}: ${e.value} → 0');
    }
    if (better.isNotEmpty) {
      // ignore: avoid_print
      print('kit_rules: ${better.length} file(s) went down — lock the gain in with '
          '`dart run tool/kit_rules.dart --write`:\n  ${better.take(20).join('\n  ')}');
    }
    expect(worse, isEmpty,
        reason: 'raw spacing / radius numbers went up: use AppSpace / AppRadius / AppIconSize '
            '(lib/design/app_tokens.dart), not a number');
  });

  test('no SnackBar, Switch or non-AppDropdown dropdown outside lib/design', () {
    final hits = <String, List<String>>{};
    for (final p in libFiles()) {
      if (p.startsWith('lib/design/')) continue;
      neverHits(p, stripCommentsAndStrings(File(p).readAsStringSync())).forEach((rule, at) {
        (hits[rule] ??= []).addAll(at);
      });
    }
    expect(hits, isEmpty,
        reason: 'use showAppNotice, AppSwitch / AppSwitchTile and AppDropdown / AppPicker (lib/design)');
  });

  test('colour literals in lib/design never go up; none in a new file (KIT_SPEC 7.2)', () {
    final base = jsonDecode(File(hexBaselinePath).readAsStringSync()) as Map<String, dynamic>;
    final allowed = (base['files'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int));
    final worse = [
      for (final e in scanDesignHex().entries)
        if (e.value > (allowed[e.key] ?? 0)) '${e.key}: ${e.value} (baseline ${allowed[e.key] ?? 0})',
    ];
    expect(worse, isEmpty, reason: 'colours come from context.colors / context.colors.kit, never a literal');
    expect(countColorLiterals("const a = Color(0xFF000000); // Color(0xFF111111)\nfinal b = '#A1B2C3';"), 2);
  });

  test('the counter sees through comments and strings and skips nested calls', () {
    String strip(String s) => stripCommentsAndStrings(s);
    expect(countRawNumbers(strip('EdgeInsets.all(8)')), 1);
    expect(countRawNumbers(strip('EdgeInsets.symmetric(horizontal: 12, vertical: 0)')), 1);
    expect(countRawNumbers(strip('EdgeInsets.all(AppSpace.md)')), 0);
    expect(countRawNumbers(strip('// EdgeInsets.all(8)\nconst x = "EdgeInsets.all(8)";')), 0);
    expect(countRawNumbers(strip('SizedBox(height: 8, child: Padding(padding: EdgeInsets.all(4)))')), 2);
    expect(countRawNumbers(strip('SizedBox(width: AppSpace.xs)')), 0);
    expect(countRawNumbers(strip('BorderRadius.circular(12) + Radius.circular(AppRadius.card)')), 1);
    expect(neverHits('a', strip('SnackBar(content: x); AppSwitch(); DropdownButton<int>(); DropdownMenuItem(')),
        {'SnackBar': ['a:1'], 'Dropdown (not AppDropdown)': ['a:1']});
  });
}
