// The bundled help index (assets/help/help_index.json) must equal the (page_id, role) pairs of the backend's
// data/help_seed.json, so the Info button never drifts from the real catalogue. Regenerate with
// `dart run tool/gen_help_index.dart <path to help_seed.json>`.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<String> _pairs(Iterable<dynamic> l) => [for (final p in l) '${(p as List)[0]}|${p[1]}']..sort();

void main() {
  final index = jsonDecode(File('assets/help/help_index.json').readAsStringSync()) as Map;

  test('the index is well formed and sorted', () {
    final pairs = _pairs(index['pages'] as List);
    expect(pairs, isNotEmpty);
    expect(pairs.toSet().length, pairs.length, reason: 'duplicate pair');
    expect((index['pages'] as List).map((p) => '${(p as List)[0]}|${p[1]}').toList(), pairs);
  });

  test('the index equals the seed pairs', () {
    final candidates = [
      Platform.environment['HELP_SEED'],
      '../back/data/help_seed.json',
      '../wt-back-rag/data/help_seed.json',
    ].whereType<String>().where((p) => File(p).existsSync());
    if (candidates.isEmpty) {
      markTestSkipped('help_seed.json not found (set HELP_SEED=<path>)');
      return;
    }
    final seed = jsonDecode(File(candidates.first).readAsStringSync()) as Map;
    final want = [for (final p in seed['pages'] as List) '${(p as Map)['page_id']}|${p['role']}']..sort();
    expect(_pairs(index['pages'] as List), want, reason: 'run: dart run tool/gen_help_index.dart ${candidates.first}');
  });
}
