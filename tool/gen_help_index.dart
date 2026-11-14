// Regenerates assets/help/help_index.json from the backend's data/help_seed.json: the (page_id, role) pairs that
// have a help entry. The app shows the Info button from this bundled index, so a home needs no request to know
// whether a page has help (a cached server catalogue overrides it). test/ui/help_index_test.dart fails when the two drift.
//
//   dart run tool/gen_help_index.dart ../back/data/help_seed.json
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final src = args.isNotEmpty ? args.first : '../back/data/help_seed.json';
  final seed = jsonDecode(File(src).readAsStringSync()) as Map;
  final pairs = [
    for (final p in seed['pages'] as List) [(p as Map)['page_id'] as String, p['role'] as String],
  ]..sort((a, b) => '${a[0]}|${a[1]}'.compareTo('${b[0]}|${b[1]}'));
  final out = const JsonEncoder.withIndent(' ').convert({'version': 1, 'pages': pairs});
  File('assets/help/help_index.json').writeAsStringSync('$out\n');
  stdout.writeln('${pairs.length} pairs -> assets/help/help_index.json');
}
