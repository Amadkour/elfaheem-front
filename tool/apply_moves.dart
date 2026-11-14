// Applies the feature-folder move maps in tool/moves/*.tsv (plan P3).
//
//   dart run tool/apply_moves.dart --check         every map source exists, no two rows touch the same file
//   dart run tool/apply_moves.dart --dry-run       print the plan, write nothing
//   dart run tool/apply_moves.dart                 apply every map (git mv + import / path rewrite)
//   dart run tool/apply_moves.dart --maps=M1,M2    apply only these maps (rows of the others already
//                                                  applied still drive the import rewrite)
//   dart run tool/apply_moves.dart --fix-imports   move nothing; only rewrite directives and paths that
//                                                  still name an old path (after merging the move into a
//                                                  branch that kept working on the old layout)
//
// A map row is `old_path<TAB>new_path`, a file or a whole folder, relative to the repository root.
// Blank lines and lines starting with `#` are ignored.
//
// What a run does:
//   1. `git mv` every file of every pending row (untracked files are renamed on disk);
//   2. in every Dart file of the repository, rewrites ONLY the URIs of import / export / part / part of
//      directives whose target moved, and every relative import / export of a moved file. Imports and
//      exports become `package:<name>/…` when the target is under lib/, `part` / `part of` stay relative.
//      `show` / `hide` / `as` / `deferred as` and the `if (dart.library.x) '…'` branches are kept: only the
//      characters between the quotes change;
//   3. rewrites path mentions of a moved row (`lib/features/x/…`, `features/x/…`, `package:<name>/features/x/…`,
//      and in Markdown also the short `x/y/…`) in Markdown, Dart comments and strings, TOML, YAML, Kotlin,
//      Swift, JS and shell files.
// No line is reformatted (D-003). A second run finds nothing to do.
//
// The logic is in plain functions so test/tool/apply_moves_test.dart can run it on a fixture tree.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final opts = MoveOptions.parse(args);
  if (opts == null) {
    stderr.writeln('usage: dart run tool/apply_moves.dart [--check|--dry-run|--fix-imports] [--maps=M1,M2] [--root=dir]');
    exitCode = 64;
    return;
  }
  final report = runMoves(opts);
  stdout.write(report.render(verbose: opts.dryRun || opts.verbose));
  if (report.errors.isNotEmpty) exitCode = 1;
}

class MoveOptions {
  final String root;
  final bool check;
  final bool dryRun;
  final bool fixImports;
  final bool verbose;
  final Set<String>? maps;

  MoveOptions({
    required this.root,
    this.check = false,
    this.dryRun = false,
    this.fixImports = false,
    this.verbose = false,
    this.maps,
  });

  static MoveOptions? parse(List<String> args) {
    var root = Directory.current.path;
    var check = false, dry = false, fix = false, verbose = false;
    Set<String>? maps;
    for (final a in args) {
      if (a == '--check') {
        check = true;
      } else if (a == '--dry-run') {
        dry = true;
      } else if (a == '--fix-imports') {
        fix = true;
      } else if (a == '--verbose' || a == '-v') {
        verbose = true;
      } else if (a.startsWith('--maps=')) {
        maps = a.substring(7).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
      } else if (a.startsWith('--root=')) {
        root = a.substring(7);
      } else {
        return null;
      }
    }
    return MoveOptions(root: root, check: check, dryRun: dry, fixImports: fix, verbose: verbose, maps: maps);
  }
}

class MoveRow {
  final String map;
  final int line;
  final String from;
  final String to;

  MoveRow(this.map, this.line, this.from, this.to);

  String get where => '$map.tsv:$line';
}

class MoveReport {
  final List<String> errors = [];
  final List<String> warnings = [];
  final Map<String, int> movedPerMap = {};
  final Map<String, int> appliedPerMap = {};
  final List<String> moveLines = [];
  final Map<String, int> directiveEdits = {};
  final Map<String, int> textEdits = {};
  bool wrote = false;

  int get directiveTotal => directiveEdits.values.fold(0, (a, b) => a + b);
  int get textTotal => textEdits.values.fold(0, (a, b) => a + b);

  String render({bool verbose = false}) {
    final b = StringBuffer();
    if (verbose) {
      for (final l in moveLines) {
        b.writeln(l);
      }
    }
    final maps = {...movedPerMap.keys, ...appliedPerMap.keys}.toList()..sort(compareMapNames);
    for (final m in maps) {
      b.writeln('$m: ${movedPerMap[m] ?? 0} files to move, ${appliedPerMap[m] ?? 0} already moved');
    }
    b.writeln('directives: $directiveTotal URIs in ${directiveEdits.length} files');
    final byKind = <String, int>{};
    textEdits.forEach((f, n) {
      final dot = f.lastIndexOf('.');
      final kind = f.endsWith('CLAUDE.md') ? 'CLAUDE.md' : (dot < 0 ? f : f.substring(dot));
      byKind[kind] = (byKind[kind] ?? 0) + n;
    });
    final kinds = byKind.keys.toList()..sort();
    b.writeln('path mentions: $textTotal in ${textEdits.length} files'
        '${kinds.isEmpty ? '' : ' (${kinds.map((k) => '$k ${byKind[k]}').join(', ')})'}');
    if (verbose) {
      final files = textEdits.keys.toList()..sort();
      for (final f in files) {
        b.writeln('  text  $f: ${textEdits[f]}');
      }
    }
    for (final w in warnings) {
      b.writeln('warning: $w');
    }
    for (final e in errors) {
      b.writeln('error: $e');
    }
    b.writeln(errors.isNotEmpty ? 'FAILED' : (wrote ? 'applied' : 'nothing written'));
    return b.toString();
  }
}

/// M2 before M10: the number after the letters, then the name.
int compareMapNames(String a, String b) {
  int n(String s) => int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '') ?? 1 << 30;
  final c = n(a).compareTo(n(b));
  return c != 0 ? c : a.compareTo(b);
}

// ─── paths ──────────────────────────────────────────────────────────────────────────────────────────────

String normalizePath(String p) {
  final out = <String>[];
  for (final s in p.replaceAll('\\', '/').split('/')) {
    if (s.isEmpty || s == '.') continue;
    if (s == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else {
        out.add('..');
      }
    } else {
      out.add(s);
    }
  }
  return out.join('/');
}

String dirOf(String p) {
  final i = p.lastIndexOf('/');
  return i < 0 ? '' : p.substring(0, i);
}

String baseOf(String p) => p.substring(p.lastIndexOf('/') + 1);

String joinPath(String dir, String rel) => normalizePath(dir.isEmpty ? rel : '$dir/$rel');

/// The relative URI from a file in [fromDir] to [target], both repository paths.
String relativeUri(String fromDir, String target) {
  final a = fromDir.isEmpty ? <String>[] : fromDir.split('/');
  final b = target.split('/');
  var i = 0;
  while (i < a.length && i < b.length - 1 && a[i] == b[i]) {
    i++;
  }
  return [for (var k = i; k < a.length; k++) '..', ...b.sublist(i)].join('/');
}

bool _under(String path, String prefix) => path == prefix || path.startsWith('$prefix/');

// ─── git / file system ──────────────────────────────────────────────────────────────────────────────────

List<String> _git(String root, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: root, stdoutEncoding: utf8);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
  return (r.stdout as String).split('\x00').where((s) => s.isNotEmpty).toList();
}

class Tree {
  final String root;
  final Set<String> tracked;
  final Set<String> untracked;

  Tree(this.root, this.tracked, this.untracked);

  factory Tree.load(String root) {
    bool onDisk(String p) => File('$root/$p').existsSync();
    final tracked = _git(root, ['ls-files', '-z', '--cached']).where(onDisk).toSet();
    final untracked = _git(root, ['ls-files', '-z', '--others', '--exclude-standard']).where(onDisk).toSet();
    return Tree(root, tracked, untracked);
  }

  Set<String> get all => {...tracked, ...untracked};
}

// ─── maps ───────────────────────────────────────────────────────────────────────────────────────────────

List<MoveRow> loadRows(String root, MoveReport report) {
  final dir = Directory('$root/tool/moves');
  if (!dir.existsSync()) {
    report.errors.add('tool/moves/ does not exist');
    return [];
  }
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.tsv')).toList()
    ..sort((a, b) => compareMapNames(_mapName(a.path), _mapName(b.path)));
  final rows = <MoveRow>[];
  for (final f in files) {
    final name = _mapName(f.path);
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i].trimRight();
      if (l.trim().isEmpty || l.trimLeft().startsWith('#')) continue;
      final parts = l.split('\t');
      if (parts.length != 2 || parts[0].trim().isEmpty || parts[1].trim().isEmpty) {
        report.errors.add('$name.tsv:${i + 1}: expected `old_path<TAB>new_path`');
        continue;
      }
      final from = normalizePath(parts[0].trim()), to = normalizePath(parts[1].trim());
      if (from == to || from.startsWith('..') || to.startsWith('..')) {
        report.errors.add('$name.tsv:${i + 1}: bad row `$from` -> `$to`');
        continue;
      }
      rows.add(MoveRow(name, i + 1, from, to));
    }
  }
  return rows;
}

String _mapName(String path) {
  final b = baseOf(normalizePath(path));
  return b.substring(0, b.length - 4);
}

class MovePlan {
  /// Every old file path -> new file path, pending and already applied rows alike.
  final Map<String, String> oldToNew = {};

  /// Only the files this run moves.
  final Map<String, String> pending = {};

  /// Which row a pending / applied file came from.
  final Map<String, MoveRow> rowOf = {};

  /// Rows that drive path mentions in text (pending + applied).
  final List<MoveRow> textRows = [];

  Map<String, String> get newToOld => {for (final e in oldToNew.entries) e.value: e.key};
}

MovePlan buildPlan(Tree tree, List<MoveRow> rows, MoveOptions opts, MoveReport report) {
  final plan = MovePlan();
  final all = tree.all;
  final owner = <String, MoveRow>{};
  final sorted = all.toList()..sort();

  List<String> filesUnder(String p) {
    if (all.contains(p)) return [p];
    final pre = '$p/';
    return [for (final f in sorted) if (f.startsWith(pre)) f];
  }

  for (final row in rows) {
    final selected = opts.maps == null || opts.maps!.contains(row.map);
    final src = filesUnder(row.from);
    // A file under a deeper destination of another row (`profile/display` inside `profile`) is that row's.
    final deeper = [for (final o in rows) if (o.to != row.to && _under(o.to, row.to)) o.to];
    final dst = [for (final f in filesUnder(row.to)) if (!deeper.any((d) => _under(f, d))) f];
    final isFileRow = all.contains(row.from) || all.contains(row.to) || row.from.endsWith('.dart');
    final Map<String, String> files;
    var applied = false;
    if (src.isNotEmpty) {
      files = {
        for (final f in src) f: isFileRow ? row.to : '${row.to}${f.substring(row.from.length)}',
      };
    } else if (dst.isNotEmpty) {
      applied = true;
      files = {
        for (final f in dst) (isFileRow ? row.from : '${row.from}${f.substring(row.to.length)}'): f,
      };
    } else {
      report.errors.add('${row.where}: `${row.from}` does not exist (and `${row.to}` neither)');
      continue;
    }
    for (final e in files.entries) {
      final prev = owner[e.key];
      if (prev != null) {
        report.errors.add('${row.where} and ${prev.where} both move `${e.key}`');
        continue;
      }
      owner[e.key] = row;
      plan.rowOf[e.key] = row;
      plan.oldToNew[e.key] = e.value;
      if (!applied && selected && !opts.fixImports) plan.pending[e.key] = e.value;
    }
    if (applied) {
      report.appliedPerMap[row.map] = (report.appliedPerMap[row.map] ?? 0) + files.length;
      plan.textRows.add(row);
    } else if (selected && !opts.fixImports) {
      report.movedPerMap[row.map] = (report.movedPerMap[row.map] ?? 0) + files.length;
      plan.textRows.add(row);
      report.moveLines.add('${row.where}  ${row.from}  ->  ${row.to}  (${files.length} files)');
    } else {
      report.movedPerMap.putIfAbsent(row.map, () => 0);
    }
  }

  // Destinations: unique, and not an existing file that stays where it is.
  final seen = <String, String>{};
  for (final e in plan.oldToNew.entries) {
    final other = seen[e.value];
    if (other != null) {
      report.errors.add('`$other` and `${e.key}` would both become `${e.value}`');
    }
    seen[e.value] = e.key;
  }
  for (final e in plan.pending.entries) {
    if (all.contains(e.value) && !plan.pending.containsKey(e.value)) {
      report.errors.add('${plan.rowOf[e.key]!.where}: `${e.value}` already exists');
    }
  }
  // A new path inside some row's old path would be matched again by the next run.
  for (final r in rows) {
    for (final o in rows) {
      if (_under(r.to, o.from)) {
        report.errors.add('${r.where}: `${r.to}` lies inside `${o.from}` (${o.where}), so a second run would move it again');
      }
    }
  }
  return plan;
}

// ─── Dart directives ────────────────────────────────────────────────────────────────────────────────────

class UriLit {
  final int start; // first character after the opening quote(s)
  final int end; // the closing quote
  final String value;

  UriLit(this.start, this.end, this.value);
}

class Directive {
  final String kind; // import, export, part, part of, library
  final int start;
  final int end; // after the `;`
  final List<UriLit> uris;

  Directive(this.kind, this.start, this.end, this.uris);
}

bool _idChar(int c) =>
    (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x5f || c == 0x24;

/// The directives at the top of a Dart file (everything before the first declaration).
List<Directive> parseDirectives(String s) {
  final out = <Directive>[];
  var i = 0;
  final n = s.length;
  if (n > 0 && s.codeUnitAt(0) == 0xfeff) i = 1;
  if (s.startsWith('#!', i)) {
    while (i < n && s[i] != '\n') {
      i++;
    }
  }

  int skipBlock(int j) {
    var depth = 0;
    while (j < n) {
      if (s.startsWith('/*', j)) {
        depth++;
        j += 2;
      } else if (s.startsWith('*/', j)) {
        depth--;
        j += 2;
        if (depth == 0) return j;
      } else {
        j++;
      }
    }
    return n;
  }

  int skipTrivia(int j) {
    while (j < n) {
      final c = s[j];
      if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
        j++;
      } else if (s.startsWith('//', j)) {
        while (j < n && s[j] != '\n') {
          j++;
        }
      } else if (s.startsWith('/*', j)) {
        j = skipBlock(j);
      } else {
        break;
      }
    }
    return j;
  }

  // A string literal at j; returns its end (after the closing quote) and the literal.
  (int, UriLit)? readString(int j) {
    var k = j;
    if (k < n && (s[k] == 'r' || s[k] == 'R')) k++;
    if (k >= n || (s[k] != "'" && s[k] != '"')) return null;
    final q = s[k];
    final triple = s.startsWith('$q$q$q', k);
    final open = triple ? 3 : 1;
    final close = triple ? '$q$q$q' : q;
    final start = k + open;
    var e = start;
    while (e < n && !s.startsWith(close, e)) {
      if (s[e] == '\\') e++;
      e++;
    }
    if (e >= n) return null;
    return (e + close.length, UriLit(start, e, s.substring(start, e)));
  }

  while (true) {
    i = skipTrivia(i);
    if (i >= n) break;
    if (s[i] == '@') {
      // An annotation (on a library directive, or on the first declaration: then we stop at the word).
      var j = i + 1;
      while (j < n && (_idChar(s.codeUnitAt(j)) || s[j] == '.')) {
        j++;
      }
      j = skipTrivia(j);
      if (j < n && s[j] == '(') {
        var depth = 0;
        while (j < n) {
          final str = readString(j);
          if (str != null && (s[j] == "'" || s[j] == '"')) {
            j = str.$1;
            continue;
          }
          if (s[j] == '(') depth++;
          if (s[j] == ')') {
            depth--;
            if (depth == 0) {
              j++;
              break;
            }
          }
          j++;
        }
      }
      i = j;
      continue;
    }
    var w = i;
    while (w < n && _idChar(s.codeUnitAt(w))) {
      w++;
    }
    final word = s.substring(i, w);
    if (word != 'import' && word != 'export' && word != 'part' && word != 'library') break;
    var kind = word;
    if (word == 'part') {
      final j = skipTrivia(w);
      if (s.startsWith('of', j) && (j + 2 >= n || !_idChar(s.codeUnitAt(j + 2)))) kind = 'part of';
    }
    final uris = <UriLit>[];
    var j = w;
    var done = false;
    while (j < n) {
      j = skipTrivia(j);
      if (j >= n) break;
      final c = s[j];
      if (c == ';') {
        j++;
        done = true;
        break;
      }
      final str = readString(j);
      if (str != null && (c == "'" || c == '"' || ((c == 'r' || c == 'R') && (j == 0 || !_idChar(s.codeUnitAt(j - 1)))))) {
        uris.add(str.$2);
        j = str.$1;
        continue;
      }
      j++;
    }
    if (!done) break;
    out.add(Directive(kind, i, j, kind == 'library' ? const [] : uris));
    i = j;
  }
  return out;
}

// ─── rewriting ──────────────────────────────────────────────────────────────────────────────────────────

class Edit {
  final int start;
  final int end;
  final String text;

  Edit(this.start, this.end, this.text);
}

String applyEdits(String s, List<Edit> edits) {
  if (edits.isEmpty) return s;
  edits.sort((a, b) => a.start.compareTo(b.start));
  final b = StringBuffer();
  var at = 0;
  for (final e in edits) {
    b.write(s.substring(at, e.start));
    b.write(e.text);
    at = e.end;
  }
  b.write(s.substring(at));
  return b.toString();
}

class Rewriter {
  final String package;
  final MovePlan plan;

  /// Files that exist once this run's moves are done.
  final Set<String> after;
  final Map<String, String> newToOld;
  final MoveReport report;

  Rewriter(this.package, this.plan, this.after, this.report) : newToOld = plan.newToOld;

  String get _pkgPrefix => 'package:$package/';

  /// The repository path an URI in [file] (its path after this run) points at, before mapping.
  String? _resolve(String file, String uri, {required bool movedNow}) {
    if (uri.startsWith(_pkgPrefix)) return 'lib/${uri.substring(_pkgPrefix.length)}';
    if (uri.contains(':')) return null; // dart:, other packages, http:
    if (movedNow) return joinPath(dirOf(newToOld[file]!), uri);
    final here = joinPath(dirOf(file), uri);
    if (after.contains(here) || plan.oldToNew.containsKey(here)) return here;
    // A file a merge moved by rename detection still carries its old relative imports.
    final old = newToOld[file];
    if (old != null) {
      final there = joinPath(dirOf(old), uri);
      if (after.contains(there) || plan.oldToNew.containsKey(there)) return there;
    }
    return here;
  }

  /// The edits for the directive URIs of one Dart file whose path after this run is [file].
  List<Edit> directiveEdits(String file, List<Directive> dirs) {
    final old = newToOld[file];
    final movedNow = old != null && plan.pending[old] == file;
    final edits = <Edit>[];
    for (final d in dirs) {
      for (final u in d.uris) {
        final relative = !u.value.contains(':');
        final raw = _resolve(file, u.value, movedNow: movedNow);
        if (raw == null) continue;
        final target = plan.oldToNew[raw] ?? raw;
        final changed = target != raw;
        if (!changed && !(movedNow && relative)) continue;
        if (!after.contains(target)) {
          report.warnings.add('$file: `${u.value}` points at `$target`, which does not exist');
          continue;
        }
        final String uri;
        if ((d.kind == 'import' || d.kind == 'export') && target.startsWith('lib/')) {
          uri = '$_pkgPrefix${target.substring(4)}';
        } else {
          uri = relativeUri(dirOf(file), target);
        }
        if (uri != u.value) edits.add(Edit(u.start, u.end, uri));
      }
    }
    return edits;
  }
}

/// Mentions of moved rows in text: `lib/features/a/b`, `features/a/b`, `package:<name>/features/a/b`,
/// and (with [short], for Markdown) `a/b` when it has two segments or more: `shared/live/x.dart` becomes
/// `features/live/x.dart`. A mention must end at a path edge (`shared/live_x` is not `shared/live`).
class Mentions {
  final RegExp? re;
  final Map<String, String> to;

  Mentions._(this.re, this.to);

  factory Mentions(List<MoveRow> rows, String package, {bool short = false}) {
    final to = <String, String>{};
    for (final r in rows) {
      to[r.from] = r.to;
      if (r.from.startsWith('lib/') && r.to.startsWith('lib/')) {
        final from = r.from.substring(4), dest = r.to.substring(4);
        if (from.contains('/')) to[from] = dest;
        if (short && from.startsWith('features/')) {
          final bare = from.substring(9);
          if (bare.contains('/')) to[bare] = dest;
        }
      }
    }
    if (to.isEmpty) return Mentions._(null, to);
    final keys = to.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    final pkg = RegExp.escape('package:$package/');
    return Mentions._(
        RegExp('(?:(?<=$pkg)|' r'(?<![\w/.\-]))(' '${keys.map(RegExp.escape).join('|')}' r')(?![\w\-]|\.\w)'), to);
  }
}

/// The edits for path mentions in [s], outside the [skip] ranges (the directives).
List<Edit> mentionEdits(String s, Mentions mentions, List<(int, int)> skip) {
  final re = mentions.re;
  if (re == null) return [];
  final edits = <Edit>[];
  for (final m in re.allMatches(s)) {
    if (skip.any((r) => m.start < r.$2 && m.end > r.$1)) continue;
    edits.add(Edit(m.start, m.end, mentions.to[m.group(1)!]!));
  }
  return edits;
}

const _textExtensions = {'.md', '.dart', '.toml', '.yaml', '.yml', '.kt', '.swift', '.js', '.sh', '.py', '.txt', '.json'};

bool _isTextTarget(String p) {
  if (p.startsWith('tool/moves/') || p == 'tool/apply_moves.dart' || p.startsWith('test/tool/')) return false;
  if (p == 'pubspec.lock' || p.endsWith('.lock') || p.contains('/fixtures/') || p.endsWith('package-lock.json')) return false;
  final b = baseOf(p);
  final dot = b.lastIndexOf('.');
  return dot >= 0 && _textExtensions.contains(b.substring(dot));
}

String? _readText(String path) {
  try {
    return utf8.decode(File(path).readAsBytesSync());
  } on FormatException {
    return null;
  }
}

// ─── the run ────────────────────────────────────────────────────────────────────────────────────────────

MoveReport runMoves(MoveOptions opts) {
  final report = MoveReport();
  final root = opts.root;
  final pubspec = File('$root/pubspec.yaml');
  if (!pubspec.existsSync()) {
    report.errors.add('no pubspec.yaml in $root');
    return report;
  }
  final name = RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec.readAsStringSync())?.group(1);
  if (name == null) {
    report.errors.add('pubspec.yaml has no name');
    return report;
  }
  final rows = loadRows(root, report);
  final tree = Tree.load(root);
  final plan = buildPlan(tree, rows, opts, report);

  final after = {...tree.all}
    ..removeAll(plan.pending.keys)
    ..addAll(plan.pending.values);
  final pendingNewToOld = {for (final e in plan.pending.entries) e.value: e.key};
  String sourceOf(String p) => '$root/${pendingNewToOld[p] ?? p}';

  // part / part of pairs must move together.
  for (final old in plan.pending.keys.where((p) => p.endsWith('.dart'))) {
    final content = _readText('$root/$old');
    if (content == null) continue;
    for (final d in parseDirectives(content)) {
      if (d.kind != 'part' && d.kind != 'part of') continue;
      for (final u in d.uris) {
        if (u.value.contains(':')) continue;
        final other = joinPath(dirOf(old), u.value);
        if (!plan.pending.containsKey(other) && tree.all.contains(other)) {
          report.errors.add('`$old` moves but its ${d.kind} `$other` stays: put both in the map');
        }
      }
    }
  }
  if (opts.check || report.errors.isNotEmpty) {
    if (opts.check && report.errors.isEmpty) report.moveLines.insert(0, 'check: ${rows.length} rows OK');
    return report;
  }

  final rewriter = Rewriter(name, plan, after, report);
  final mentions = Mentions(plan.textRows, name);
  final mdMentions = Mentions(plan.textRows, name, short: true);
  final out = <String, String>{}; // path after the run -> new content (only changed files)
  final paths = after.toList()..sort();
  for (final p in paths) {
    final isDart = p.endsWith('.dart');
    if (!isDart && !_isTextTarget(p)) continue;
    final content = _readText(sourceOf(p));
    if (content == null) continue;
    final edits = <Edit>[];
    var skip = <(int, int)>[];
    if (isDart && p != 'tool/apply_moves.dart' && !p.startsWith('test/tool/')) {
      final dirs = parseDirectives(content);
      final de = rewriter.directiveEdits(p, dirs);
      if (de.isNotEmpty) report.directiveEdits[p] = de.length;
      edits.addAll(de);
      skip = [for (final d in dirs) (d.start, d.end)];
    }
    if (_isTextTarget(p)) {
      final me = mentionEdits(content, p.endsWith('.md') ? mdMentions : mentions, skip);
      if (me.isNotEmpty) report.textEdits[p] = me.length;
      edits.addAll(me);
    }
    final text = applyEdits(content, edits);
    if (text != content) out[p] = text;
  }

  if (opts.dryRun) {
    final files = out.keys.toList()..sort();
    for (final f in files) {
      report.moveLines.add('edit  $f');
    }
    return report;
  }

  // Move.
  if (plan.pending.isNotEmpty) {
    final groups = <String, List<String>>{};
    final renames = <MapEntry<String, String>>[];
    for (final e in plan.pending.entries) {
      if (!tree.tracked.contains(e.key)) {
        final dst = File('$root/${e.value}');
        dst.parent.createSync(recursive: true);
        File('$root/${e.key}').renameSync(dst.path);
      } else if (baseOf(e.key) == baseOf(e.value)) {
        (groups[dirOf(e.value)] ??= []).add(e.key);
      } else {
        renames.add(e);
      }
    }
    final dirs = groups.keys.toList()..sort();
    for (final d in dirs) {
      Directory('$root/$d').createSync(recursive: true);
      final files = groups[d]!..sort();
      for (var i = 0; i < files.length; i += 40) {
        _git(root, ['mv', '--', ...files.sublist(i, i + 40 > files.length ? files.length : i + 40), d]);
      }
    }
    for (final e in renames) {
      Directory('$root/${dirOf(e.value)}').createSync(recursive: true);
      _git(root, ['mv', '--', e.key, e.value]);
    }
    // Empty source folders, then their empty parents.
    final emptied = {for (final old in plan.pending.keys) dirOf(old)}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (var d in emptied) {
      while (d.isNotEmpty) {
        final dir = Directory('$root/$d');
        if (!dir.existsSync()) {
          d = dirOf(d);
          continue;
        }
        if (dir.listSync().isNotEmpty) break;
        dir.deleteSync();
        d = dirOf(d);
      }
    }
    for (final d in emptied) {
      final dir = Directory('$root/$d');
      if (dir.existsSync() && plan.textRows.any((r) => _under(d, r.from))) {
        final left = dir.listSync(recursive: true).whereType<File>().map((f) => normalizePath(f.path.substring(root.length + 1)));
        for (final f in left) {
          report.warnings.add('left behind (ignored file?): $f');
        }
      }
    }
  }
  for (final e in out.entries) {
    File('$root/${e.key}').writeAsBytesSync(utf8.encode(e.value));
  }
  if (out.isNotEmpty) {
    final files = out.keys.where((p) => tree.tracked.contains(pendingNewToOld[p] ?? p)).toList()..sort();
    for (var i = 0; i < files.length; i += 40) {
      _git(root, ['add', '--', ...files.sublist(i, i + 40 > files.length ? files.length : i + 40)]);
    }
  }
  report.wrote = plan.pending.isNotEmpty || out.isNotEmpty;
  return report;
}
