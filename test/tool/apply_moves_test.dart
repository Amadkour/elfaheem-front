// tool/apply_moves.dart on a fixture tree: rename, import rewrite, relative imports, part directives,
// conditional and deferred imports, path mentions, idempotence, and the refusals of --check.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/apply_moves.dart';

const _x = '''
// x
import 'dart:async';
import 'y.dart';
import '../b/z.dart' show Z;
import 'p_stub.dart'
    if (dart.library.html) 'p_web.dart' as p;

part 'x_part.dart';

// see lib/features/old/y.dart, not lib/features/older/y.dart
const a = 'features/old/y.dart';
''';

const _xMoved = '''
// x
import 'dart:async';
import 'package:demo/features/new/inner/y.dart';
import 'package:demo/features/c/z2.dart' show Z;
import 'package:demo/features/new/inner/p_stub.dart'
    if (dart.library.html) 'package:demo/features/new/inner/p_web.dart' as p;

part 'x_part.dart';

// see lib/features/new/inner/y.dart, not lib/features/older/y.dart
const a = 'features/new/inner/y.dart';
''';

const _fixture = {
  'pubspec.yaml': 'name: demo\n',
  'lib/features/old/x.dart': _x,
  'lib/features/old/x_part.dart': "part of 'x.dart';\n",
  'lib/features/old/y.dart': 'class Y {}\n',
  'lib/features/old/p_stub.dart': 'const p = 0;\n',
  'lib/features/old/p_web.dart': 'const p = 1;\n',
  'lib/features/old/sub/s.dart': "import '../y.dart';\r\nimport '../../stay.dart';\r\n",
  'lib/features/b/z.dart': "import '../old/y.dart';\nclass Z {}\n",
  'lib/features/stay.dart': "import 'old/y.dart';\nimport 'b/keep.dart';\n",
  'lib/features/b/keep.dart': 'class K {}\n',
  'lib/main.dart': "import 'features/old/y.dart';\n"
      "import 'package:demo/features/b/z.dart' deferred as z;\n"
      "import 'features/stay.dart';\n\nvoid main() {}\n",
  'test/a_test.dart': "import 'package:demo/features/old/y.dart';\n\n"
      "final f = File('lib/features/old/y.dart');\nfinal g = 'lib/features/older/q.dart';\n",
  'docs/notes.md': 'See `lib/features/old/y.dart` and `package:demo/features/b/z.dart`; '
      'not `lib/features/oldest/`.\n',
  'tool/moves/M1.tsv': '# M1\nlib/features/old\tlib/features/new/inner\n',
  'tool/moves/M2.tsv': 'lib/features/b/z.dart\tlib/features/c/z2.dart\n',
};

Directory _tree(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('apply_moves_');
  for (final e in files.entries) {
    File('${dir.path}/${e.key}')
      ..createSync(recursive: true)
      ..writeAsStringSync(e.value);
  }
  Process.runSync('git', ['init', '-q'], workingDirectory: dir.path);
  Process.runSync('git', ['add', '-A'], workingDirectory: dir.path);
  return dir;
}

Map<String, String> _snapshot(Directory dir) {
  final out = <String, String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    final p = f.path.substring(dir.path.length + 1).replaceAll('\\', '/');
    if (p.startsWith('.git/')) continue;
    out[p] = f.readAsStringSync();
  }
  return out;
}

MoveReport _run(Directory dir, {bool check = false, bool dryRun = false, bool fix = false}) =>
    runMoves(MoveOptions(root: dir.path, check: check, dryRun: dryRun, fixImports: fix));

void main() {
  late Directory dir;
  setUp(() => dir = _tree(_fixture));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('path helpers', () {
    expect(normalizePath('lib/a/../b/./c.dart'), 'lib/b/c.dart');
    expect(relativeUri('lib/a/b', 'lib/a/c/d.dart'), '../c/d.dart');
    expect(relativeUri('lib/a', 'lib/a/x.dart'), 'x.dart');
  });

  test('parseDirectives reads multi-line conditional imports and part of, and stops at code', () {
    final d = parseDirectives(_x);
    expect(d.map((e) => e.kind).toList(), ['import', 'import', 'import', 'import', 'part']);
    expect(d[3].uris.map((u) => u.value).toList(), ['p_stub.dart', 'p_web.dart']);
    expect(parseDirectives("part of 'x.dart';\nclass A { final s = \"import 'no.dart';\"; }").single.kind, 'part of');
  });

  test('--check passes on a good tree and writes nothing', () {
    final before = _snapshot(dir);
    final r = _run(dir, check: true);
    expect(r.errors, isEmpty);
    expect(r.movedPerMap, {'M1': 6, 'M2': 1});
    expect(_snapshot(dir), before);
  });

  test('--dry-run reports the edits and writes nothing', () {
    final before = _snapshot(dir);
    final r = _run(dir, dryRun: true);
    expect(r.errors, isEmpty);
    expect(r.directiveTotal, greaterThan(0));
    expect(_snapshot(dir), before);
  });

  test('apply: git mv, directives, relative imports, part, mentions; a second run is a no-op', () {
    final r = _run(dir);
    expect(r.errors, isEmpty, reason: r.render());
    expect(r.warnings, isEmpty, reason: r.render());
    final s = _snapshot(dir);
    expect(s.keys.where((k) => k.startsWith('lib/features/old/') || k == 'lib/features/b/z.dart'), isEmpty);
    expect(s['lib/features/new/inner/x.dart'], _xMoved);
    expect(s['lib/features/new/inner/x_part.dart'], "part of 'x.dart';\n");
    // CRLF kept; a relative import of a file that did not move becomes a package import too.
    expect(s['lib/features/new/inner/sub/s.dart'],
        "import 'package:demo/features/new/inner/y.dart';\r\nimport 'package:demo/features/stay.dart';\r\n");
    expect(s['lib/features/c/z2.dart'], "import 'package:demo/features/new/inner/y.dart';\nclass Z {}\n");
    // A file that did not move: only the line pointing at a moved file changes.
    expect(s['lib/features/stay.dart'], "import 'package:demo/features/new/inner/y.dart';\nimport 'b/keep.dart';\n");
    expect(s['lib/main.dart'], "import 'package:demo/features/new/inner/y.dart';\n"
        "import 'package:demo/features/c/z2.dart' deferred as z;\n"
        "import 'features/stay.dart';\n\nvoid main() {}\n");
    expect(s['test/a_test.dart'], "import 'package:demo/features/new/inner/y.dart';\n\n"
        "final f = File('lib/features/new/inner/y.dart');\nfinal g = 'lib/features/older/q.dart';\n");
    expect(s['docs/notes.md'], 'See `lib/features/new/inner/y.dart` and `package:demo/features/c/z2.dart`; '
        'not `lib/features/oldest/`.\n');
    // git mv: the index holds the new paths, not the old ones.
    final index = (Process.runSync('git', ['ls-files'], workingDirectory: dir.path).stdout as String).split(RegExp(r'\s+'));
    expect(index, containsAll(['lib/features/new/inner/y.dart', 'lib/features/c/z2.dart']));
    expect(index, isNot(contains('lib/features/old/y.dart')));
    expect(Directory('${dir.path}/lib/features/old').existsSync(), isFalse);

    final again = _run(dir);
    expect(again.errors, isEmpty, reason: again.render());
    expect(again.wrote, isFalse);
    expect(again.appliedPerMap, {'M1': 6, 'M2': 1});
    expect(_snapshot(dir), s);
  });

  test('--fix-imports rewrites a file written on the old layout after the move', () {
    _run(dir);
    File('${dir.path}/lib/features/later.dart').writeAsStringSync("import 'old/y.dart';\n// lib/features/b/z.dart\n");
    final r = _run(dir, fix: true);
    expect(r.errors, isEmpty);
    expect(File('${dir.path}/lib/features/later.dart').readAsStringSync(),
        "import 'package:demo/features/new/inner/y.dart';\n// lib/features/c/z2.dart\n");
  });

  test('--check refuses a missing source, two rows on one file, a split part pair', () {
    File('${dir.path}/tool/moves/M3.tsv').writeAsStringSync('lib/features/nope\tlib/features/x\n'
        'lib/features/old/y.dart\tlib/features/y.dart\n');
    var r = _run(dir, check: true);
    expect(r.errors.any((e) => e.contains('does not exist')), isTrue, reason: r.render());
    expect(r.errors.any((e) => e.contains('both move `lib/features/old/y.dart`')), isTrue, reason: r.render());

    File('${dir.path}/tool/moves/M3.tsv').deleteSync();
    File('${dir.path}/tool/moves/M1.tsv').writeAsStringSync('lib/features/old/x.dart\tlib/features/x.dart\n');
    r = _run(dir, check: true);
    expect(r.errors.any((e) => e.contains('part `lib/features/old/x_part.dart` stays')), isTrue, reason: r.render());

    File('${dir.path}/tool/moves/M1.tsv').writeAsStringSync('lib/features/old/y.dart\tlib/features/b/keep.dart\n');
    r = _run(dir, check: true);
    expect(r.errors.any((e) => e.contains('already exists')), isTrue, reason: r.render());
  });
}
