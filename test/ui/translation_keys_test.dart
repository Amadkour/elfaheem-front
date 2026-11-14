// Translation key guard, by reading lib/:
//
// Every literal key handed to the translation helpers must exist in assets/translation.json with a non-empty
// `en` AND `ar` value; otherwise the screen shows the raw key (`translate` falls back to the other language, then
// to the key itself). Collected:
//
//  * `'key'.tr`, and the first argument of the helpers in [_keyArgs] (`translate`, `trp`, `plFmt`, `tx`, …);
//  * a positional argument that a class / function translates later (`DashboardItem(icon, icon, 'label', …)`,
//    `FilterSpec.choice(key, 'label', {… : 'option'})`, `CertFont(id, 'label', …)` — [_keyArgs]);
//  * the string given to a named argument that the widget translates with `.tr` (`labelKey:`, `descKey:` …,
//    [_keyParams]), unless the same call also passes the inline text that replaces it (`label:` / `desc:`);
//  * the strings a getter / function returns when its result is translated (`String get labelKey => switch …`
//    with `x.labelKey.tr` somewhere in lib/), and the strings a local is set to before `local.tr`.
//
// A key built at run time (`'pl_type_$t'.tr`) cannot be checked one by one: its static parts are turned into a
// pattern, and at least one key of translation.json must match it (a typo in the prefix fails).
//
// Strings are found with a small Dart lexer (comments skipped, quotes / triple quotes / raw strings / `${…}`
// interpolation handled), not a regex over the raw text, so `Text('a'), Text('b'.tr)` reads as two strings.
//
// A key used on purpose without an entry goes in [_allowed] with a reason; an entry that no longer fails anything
// fails the test, so the list only shrinks.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Named arguments whose string the receiving widget translates with `.tr` → the named argument that replaces
/// it with an inline text (the key is then unused), or null.
const _keyParams = <String, String?>{
  'labelKey': 'label', 'descKey': 'desc', 'titleKey': null, 'hintKey': null, 'subtitleKey': null, 'addKey': null,
  'newKey': null, 'editKey': null, 'deleteKey': null, 'helperKey': null, 'yesKey': null, 'noKey': null,
  'messageKey': null, 'reasonKey': null, 'confirmKey': null,
};

/// Call name → positional argument indexes that are translation keys. A negative index `-i` means "the values
/// of the map literal at argument i". A private name only counts in the file named after `@`.
const _keyArgs = <String, List<int>>{
  'translate': [0],
  'trp': [0], // admin_common.dart, `{name}` placeholders
  'plFmt': [0], // parent_widgets.dart
  'readingTr': [0], // about_terms_parts.dart
  'tx': [0], // exam_tr.dart; the 3-argument `tx(key, en, ar)` of table_export_model.dart has its own fallback
  'DashboardItem': [2],
  'IdentifierFieldSpec': [0],
  'CertFont': [1],
  'CertPlaceholder': [1],
  'FilterSpec.choice': [1, -2],
  'FilterSpec.remoteChoice': [1],
  'FilterSpec.tri': [1],
  'FilterSpec.lookup': [1],
  'FilterSpec.dateRange': [2],
  'FilterSpec.numberRange': [2],
  '_label@admin_content_page.dart': [0],
  '_label@admin_required_documents_page.dart': [0],
  '_fmt@student_active_exam_screen.dart': [0],
  '_fieldLabel@transfer_payment_screen.dart': [0],
  '_n@complaints_hub_model.dart': [0],
};

/// Calls whose key argument is a base the callee completes with these suffixes.
const _suffixArgs = <String, (int, List<String>)>{
  'courseStatNoun': (1, ['', '_one', '_few']),
};

/// Keys that are deliberately used without a translation entry: key → reason.
const Map<String, String> _allowed = {};

class _Use {
  _Use(this.key, this.file, this.line);
  final String key;
  final String file;
  final int line;
  bool get dynamic => key.contains(r'$');
  @override
  String toString() => '$key  ($file:$line)';
}

/// One string literal: its value (escapes kept, `${…}` → `${}`), the index after the opening delimiter, the
/// index after the closing one, the index of the opening quote, and whether it sits inside another string.
class _Lit {
  _Lit(this.value, this.start, this.end, this.open, this.nested);
  final String value;
  final int start, end, open;
  final bool nested;
}

/// Lexes [src]: every string literal (including the ones nested in `${…}`) and every comment range.
(List<_Lit>, List<(int, int)>) _lex(String src) {
  final lits = <_Lit>[];
  final comments = <(int, int)>[];
  final n = src.length;
  var nesting = 0;

  late int Function(int, bool) code;

  int str(int at) {
    var raw = false;
    var p = at;
    if (src[p] == 'r') {
      raw = true;
      p++;
    }
    final q = src[p];
    final triple = p + 2 < n && src[p + 1] == q && src[p + 2] == q;
    final delim = triple ? '$q$q$q' : q;
    p += delim.length;
    final start = p;
    final buf = StringBuffer();
    final mine = nesting;
    while (p < n) {
      if (src.startsWith(delim, p)) {
        lits.add(_Lit(buf.toString(), start, p + delim.length, at, mine > 0));
        return p + delim.length;
      }
      final ch = src[p];
      if (!triple && ch == '\n') break; // unterminated: give up on this one
      if (!raw && ch == r'\') {
        buf.write(src.substring(p, (p + 2).clamp(0, n)));
        p += 2;
        continue;
      }
      if (!raw && ch == r'$' && p + 1 < n && src[p + 1] == '{') {
        buf.write(r'${}');
        nesting++;
        p = code(p + 2, true);
        nesting--;
        continue;
      }
      buf.write(ch);
      p++;
    }
    return p;
  }

  final ident = RegExp(r'[A-Za-z0-9_$]');
  code = (int p, bool inInterp) {
    var depth = 0;
    while (p < n) {
      final ch = src[p];
      if (ch == '/' && p + 1 < n && src[p + 1] == '/') {
        final e = src.indexOf('\n', p);
        comments.add((p, e < 0 ? n : e));
        p = e < 0 ? n : e;
        continue;
      }
      if (ch == '/' && p + 1 < n && src[p + 1] == '*') {
        final e = src.indexOf('*/', p + 2);
        comments.add((p, e < 0 ? n : e + 2));
        p = e < 0 ? n : e + 2;
        continue;
      }
      if (ch == "'" || ch == '"') {
        p = str(p);
        continue;
      }
      if (ch == 'r' && p + 1 < n && (src[p + 1] == "'" || src[p + 1] == '"') && (p == 0 || !ident.hasMatch(src[p - 1]))) {
        p = str(p);
        continue;
      }
      if (inInterp) {
        if (ch == '{') depth++;
        if (ch == '}') {
          if (depth == 0) return p + 1;
          depth--;
        }
      }
      p++;
    }
    return p;
  };

  var i = 0;
  while (i < n) {
    i = code(i, false);
  }
  return (lits, comments);
}

/// [src] with string contents and comments blanked out (same length), so brackets / commas are code only.
String _mask(String src, List<_Lit> lits, List<(int, int)> comments) {
  final b = src.codeUnits.toList();
  void blank(int from, int to) {
    for (var k = from; k < to && k < b.length; k++) {
      if (b[k] != 10) b[k] = 32;
    }
  }

  for (final l in lits.where((l) => !l.nested)) {
    blank(l.start, l.end - _delimLen(src, l));
  }
  for (final (a, z) in comments) {
    blank(a, z);
  }
  return String.fromCharCodes(b);
}

int _delimLen(String src, _Lit l) {
  final q = src[l.end - 1];
  return l.end - 3 >= l.start && src[l.end - 2] == q && src[l.end - 3] == q ? 3 : 1;
}

final _keyShape = RegExp(r'^[A-Za-z0-9_.\-${}]+$');
final _afterTr = RegExp(r'^\s*\.tr(?![A-Za-z0-9_$])');
final _namedBefore = RegExp(r'\b([A-Za-z_]\w*)\s*:\s*$');
final _nameBeforeParen = RegExp(r'([A-Za-z_][\w.]*)\s*(?:<[^<>()]*>)?\s*$');

/// The call that holds the argument starting at [at] in [masked]: (name, positional index, named argument
/// name, index of its `(`), or null when [at] is not directly inside `(…)`.
(String, int, String?, int)? _call(String masked, int at) {
  var depth = 0;
  var p = at - 1;
  final argStarts = <int>[at];
  while (p >= 0) {
    final ch = masked[p];
    if (ch == ')' || ch == ']' || ch == '}') {
      depth++;
    } else if (ch == '(' || ch == '[' || ch == '{') {
      if (depth == 0) break;
      depth--;
    } else if (depth == 0 && (ch == ';')) {
      return null;
    } else if (depth == 0 && ch == ',') {
      argStarts.add(p + 1);
    }
    p--;
  }
  if (p < 0 || masked[p] != '(') return null;
  final m = _nameBeforeParen.firstMatch(masked.substring((p - 80).clamp(0, p), p));
  if (m == null) return null;
  // the commas left to right; our argument starts after the last one
  final bounds = [p + 1, ...argStarts.skip(1).toList().reversed];
  final named = _namedBefore.firstMatch(masked.substring(bounds.last, at));
  // positional index: the earlier arguments that are not `name: value`
  var index = 0;
  for (var k = 0; k < bounds.length - 1; k++) {
    final arg = masked.substring(bounds[k], bounds[k + 1] - 1);
    if (!RegExp(r'^\s*[A-Za-z_]\w*\s*:(?!:)').hasMatch(arg)) index++;
  }
  return (m.group(1)!, index, named?.group(1), p);
}

/// The number of arguments of the call whose `(` is at [open] in [masked].
int _argCount(String masked, int open) {
  final close = _bodyEnd(masked, open, block: true);
  var depth = 0, commas = 0;
  for (var p = open + 1; p < close; p++) {
    final ch = masked[p];
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') depth--;
    if (depth == 0 && ch == ',') commas++;
  }
  final trailing = masked.substring(open + 1, close).trimRight().endsWith(',');
  return commas + 1 - (trailing ? 1 : 0);
}

/// The enclosing `{` of a map value at [at] (its index), or null.
int? _mapOpen(String masked, int at) {
  var depth = 0;
  for (var p = at - 1; p >= 0; p--) {
    final ch = masked[p];
    if (ch == ')' || ch == ']' || ch == '}') depth++;
    if (ch == '(' || ch == '[' || ch == '{') {
      if (depth == 0) return ch == '{' ? p : null;
      depth--;
    }
    if (depth == 0 && ch == ';') return null;
  }
  return null;
}

/// The code token right before [at] (whitespace skipped).
String _tokenBefore(String masked, int at) {
  var p = at - 1;
  while (p >= 0 && masked[p].trim().isEmpty) {
    p--;
  }
  if (p < 0) return '';
  final m = RegExp(r'(=>|\?\?|[=!<>]=|[?:=(,\[{]|\b\w+)$').firstMatch(masked.substring((p - 20).clamp(0, p), p + 1));
  return m?.group(1) ?? masked[p];
}

/// The code text right after [at] (whitespace skipped), a few characters.
String _after(String masked, int at) => masked.substring(at, (at + 12).clamp(0, masked.length)).trimLeft();

/// Whether the literal at [l] is a result of the expression it sits in (`return 'x'`, `=> 'x'`, `c ? 'x' : 'y'`,
/// `= 'x'`), not a pattern / comparison / map key.
bool _isResult(String masked, _Lit l) {
  final before = _tokenBefore(masked, l.open);
  final after = _after(masked, l.end);
  if (after.startsWith('=>') || after.startsWith('==') || after.startsWith('.')) return false;
  return const {'return', '=>', '?', ':', '??', '='}.contains(before);
}

/// The end of the expression / block that starts at [from] in [masked]: the `;` (or `,` / `)` / `}` that closes
/// the enclosing bracket) at depth 0 for `=>` / `=`, the matching `}` for a block.
int _bodyEnd(String masked, int from, {required bool block}) {
  var depth = 0;
  for (var p = from; p < masked.length; p++) {
    final ch = masked[p];
    if (ch == '(' || ch == '[' || ch == '{') depth++;
    if (ch == ')' || ch == ']' || ch == '}') {
      depth--;
      if (block && depth == 0) return p;
      if (!block && depth < 0) return p;
    }
    if (!block && depth == 0 && ch == ';') return p;
  }
  return masked.length;
}

class _File {
  _File(this.path, this.src) {
    final (l, c) = _lex(src);
    lits = l;
    masked = _mask(src, l, c);
  }
  final String path, src;
  late final List<_Lit> lits;
  late final String masked;
  int lineOf(int at) => '\n'.allMatches(src.substring(0, at)).length + 1;
}

List<_Use> _scan(String root) {
  final files = [
    for (final f in Directory(root).listSync(recursive: true).whereType<File>())
      if (f.path.endsWith('.dart')) _File(f.path.replaceAll(r'\', '/'), f.readAsStringSync()),
  ];
  final uses = <_Use>[];
  void add(_File f, _Lit l, [String suffix = '']) {
    if (l.value.isEmpty || !_keyShape.hasMatch(l.value)) return;
    uses.add(_Use('${l.value}$suffix', f.path, f.lineOf(l.open)));
  }

  // Names whose result is translated: `x.name.tr`, `name(…).tr`.
  final translated = <String>{};
  final trUse = RegExp(r'\.([A-Za-z_]\w*)\s*\.tr\b|\b([A-Za-z_]\w*)\s*\([^()]*\)\s*\.tr\b|(?<![.\w])([A-Za-z_]\w*)\s*\.tr\b');
  for (final f in files) {
    for (final m in trUse.allMatches(f.masked)) {
      final g = m.group(1) ?? m.group(2) ?? m.group(3)!;
      if (m.group(3) == null || g.endsWith('Key')) translated.add(g);
    }
  }
  translated.removeAll(const {'String', 'key', 'k', 'l', 'x', 'id', 'label', 'hint', 'base', 'ok', 'p'});

  for (final f in files) {
    final name = f.path.split('/').last;
    final seen = <int>{};
    void take(_Lit l, [String suffix = '']) {
      if (seen.add(l.open * 10 + suffix.length)) add(f, l, suffix);
    }

    // Getters / functions whose result is translated: the strings they return.
    final decl = RegExp(r'\bString\??\s+(?:get\s+)?([A-Za-z_]\w*)\s*(\([^()]*\))?\s*(=>|\{)');
    final bodies = <(int, int)>[];
    for (final m in decl.allMatches(f.masked)) {
      if (!translated.contains(m.group(1))) continue;
      final block = m.group(3) == '{';
      final from = m.end - (block ? 1 : 0);
      bodies.add((from, _bodyEnd(f.masked, from, block: block)));
    }
    // Locals translated in this file: `final k = c ? 'a' : 'b'; … k.tr`.
    for (final m in RegExp(r'(?<![.\w])([A-Za-z_]\w*)\s*\.tr\b').allMatches(f.masked)) {
      final v = m.group(1)!;
      for (final d in RegExp('\\b(?:final|var|String\\??)\\s+${RegExp.escape(v)}\\s*=(?!=)').allMatches(f.masked)) {
        if (d.start > m.start) continue;
        bodies.add((d.end, _bodyEnd(f.masked, d.end, block: false)));
      }
    }

    for (final l in f.lits) {
      // 'key'.tr — also inside interpolations.
      if (_afterTr.hasMatch(f.src.substring(l.end, (l.end + 80).clamp(0, f.src.length)))) {
        take(l);
        continue;
      }
      if (l.nested) continue;
      if (bodies.any((b) => l.open >= b.$1 && l.open < b.$2) && _isResult(f.masked, l)) {
        take(l);
        continue;
      }
      final call = _call(f.masked, l.open);
      if (call != null) {
        final (fn, index, named, _) = call;
        if (named != null) {
          if (_keyParams.containsKey(named)) {
            final inline = _keyParams[named];
            final args = f.masked.substring(call.$4, _bodyEnd(f.masked, call.$4, block: true));
            if (inline == null || !RegExp('[(,]\\s*$inline\\s*:').hasMatch(args)) take(l);
          }
          continue;
        }
        final spec = _keyArgs[fn] ?? _keyArgs['$fn@$name'];
        if (spec != null && spec.contains(index)) {
          // tx(key, en, ar) carries its own fallback text
          if (fn == 'tx' && _argCount(f.masked, call.$4) >= 3) continue;
          take(l);
          continue;
        }
        final suffix = _suffixArgs[fn];
        if (suffix != null && suffix.$1 == index) {
          for (final s in suffix.$2) {
            take(l, s);
          }
          continue;
        }
      }
      // A map value inside an argument listed as `-i`.
      final open = _mapOpen(f.masked, l.open);
      if (open != null && _tokenBefore(f.masked, l.open) == ':') {
        final outer = _call(f.masked, open);
        if (outer != null && outer.$3 == null) {
          final spec = _keyArgs[outer.$1] ?? _keyArgs['${outer.$1}@$name'];
          if (spec != null && spec.contains(-outer.$2)) take(l);
        }
      }
    }
  }
  return uses;
}

/// A run-time key ('pl_type_$t', 'x_${a.b}') → a pattern over its static parts; null when it has none.
RegExp? _pattern(String key) {
  final parts = key.split(RegExp(r'\$\{\}|\$[A-Za-z_]\w*'));
  if (parts.every((p) => p.isEmpty)) return null;
  return RegExp('^${parts.map(RegExp.escape).join('.+')}\$');
}

void main() {
  late Map<String, dynamic> json;
  late List<_Use> uses;

  setUpAll(() {
    json = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    uses = _scan('lib');
  });

  bool complete(String key) {
    final v = json[key];
    if (v is! Map) return false;
    return '${v['en'] ?? ''}'.trim().isNotEmpty && '${v['ar'] ?? ''}'.trim().isNotEmpty;
  }

  test('the lexer finds the strings and skips comments', () {
    final (lits, _) = _lex(r'''
// 'commented'.tr
Text('a'), Text('b'.tr); /* 'c'.tr */ final x = "it's";
final y = '${'nested'.tr} ${z}'; final w = r'raw\';
''');
    expect(lits.map((l) => l.value), ['a', 'b', 'it\'s', 'nested', r'${} ${}', r'raw\']);
  });

  test('the scan sees the app (sanity)', () {
    expect(uses.length, greaterThan(3000));
    expect(uses.where((u) => u.dynamic), isNotEmpty);
    final keys = uses.map((u) => u.key).toSet();
    // one of each source kind
    expect(keys, containsAll(['auth_sign_in', 'course_status_in_progress', 'email_or_phone', 'course_hero_students_one']));
  });

  test('every literal translation key has an en and ar value', () {
    final missing = <String, List<_Use>>{};
    for (final u in uses.where((u) => !u.dynamic)) {
      if (!complete(u.key)) missing.putIfAbsent(u.key, () => []).add(u);
    }
    final unexpected = [
      for (final e in missing.entries)
        if (!_allowed.containsKey(e.key)) '${e.value.first}',
    ]..sort();
    expect(unexpected, isEmpty, reason: 'Add these keys (en + ar) to assets/translation.json');
    final stale = _allowed.keys.where((k) => !missing.containsKey(k)).toList();
    expect(stale, isEmpty, reason: 'These _allowed entries no longer fail anything: remove them');
  });

  test('every run-time key pattern matches at least one key', () {
    final keys = json.keys.where(complete).toList();
    final bad = <String>[];
    for (final u in uses.where((u) => u.dynamic)) {
      final re = _pattern(u.key);
      if (re == null) continue;
      if (!keys.any(re.hasMatch)) bad.add('$u');
    }
    expect(bad, isEmpty, reason: 'No translation key matches these run-time keys (typo in the static part?)');
  });

  test('translation.json values are non-empty in both languages', () {
    final bad = [
      for (final e in json.entries)
        if (!e.key.startsWith('__') && !complete(e.key)) e.key,
    ];
    expect(bad, isEmpty);
  });
}
