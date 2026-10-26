// Static scan of the paths the app hands to `ApiClient` (D-026, Phase 10): finds every
// `.get / .post / .put / .patch / .delete / .getBytes / .postForBytes / .postFiles / .postForm / .postMultipart /
// .uploadImage(` call in lib/**.dart and turns its first argument into a path template, `{}` standing for each
// value only known at run time:
//
//   _api.get('$base/questions/${q.id}?lang=ar')    with  static const base = '/api/v1/exam'
//     → GET /api/v1/exam/questions/{}
//
// Names inside the path are resolved the way Dart scopes them, approximately: a local (`final url = '…'`) is seen
// after its declaration up to the end of its block; a class member (`static const _base`, `String get base => …`,
// `String _pub(int id) => …`) anywhere in its class; a top-level const in its file and, when public, in every file
// (imports are not followed). `X.name` looks in class X; `obj.name` in the instance members called `name` (those of the
// same file first). Ternaries and `??` give one template per branch. A name that is not a path stays a `{}`.
//
// Not a Dart parser: it knows strings (raw, triple, interpolation), comments and brackets, which is all a path needs.
// What it cannot resolve (a path passed in as a parameter) is reported as unresolved, never guessed.

class ApiCall {
  ApiCall(this.method, this.templates, this.file, this.line, this.source);

  /// GET, POST, …
  final String method;

  /// One template per branch; empty when the path could not be resolved.
  final List<String> templates;
  final String file;
  final int line;

  /// The first argument as written.
  final String source;

  bool get resolved => templates.isNotEmpty;
  @override
  String toString() => '$method ${resolved ? templates.join(' | ') : '<unresolved: $source>'}  ($file:$line)';
}

const _methods = {
  'get': 'GET',
  'getBytes': 'GET',
  'post': 'POST',
  'postForBytes': 'POST',
  'postFiles': 'POST',
  'postForm': 'POST',
  'postMultipart': 'POST',
  'uploadImage': 'POST',
  'put': 'PUT',
  'patch': 'PATCH',
  'delete': 'DELETE',
};

/// String methods that keep a path a path (`base.replaceFirst(RegExp(r'/$'), '')`).
const _stringMethods = {'replaceFirst', 'replaceAll', 'trim', 'toString', 'toLowerCase'};
const _maxAlternatives = 16;
const hole = '{}';
const _Tpl _holeOnly = [null];

// ── AST of a path expression ─────────────────────────────────────────────────

sealed class _Node {}

class _Lit extends _Node {
  _Lit(this.text);
  final String text;
}

class _Ref extends _Node {
  _Ref(this.chain, this.offset);
  final String chain;
  final int offset;
}

class _Cat extends _Node {
  _Cat(this.parts);
  final List<_Node> parts;
}

class _Alt extends _Node {
  _Alt(this.options);
  final List<_Node> options;
}

class _Unknown extends _Node {}

// A template while resolving: literal strings and holes (null).
typedef _Tpl = List<String?>;

// ── one source file ───────────────────────────────────────────────────────────

class _Block {
  _Block(this.start, this.end, this.className, this.stateOf);
  final int start, end;

  /// The class / mixin / extension / enum this block is the body of, or null.
  final String? className;

  /// For `class _XState extends State<X>`: X, the class `widget.…` refers to.
  final String? stateOf;
}

enum _Kind { top, member, local }

class _Def {
  _Def(this.file, this.name, this.offset, this.exprStart, this.kind, this.isStatic, this.className, this.block);
  final _File file;
  final String name;
  final int offset, exprStart;
  final _Kind kind;
  final bool isStatic;
  final String? className;
  final _Block? block;
  _Node? node;
  List<_Tpl>? value;
  bool resolving = false;
}

class _File {
  _File(this.path, String source) : code = _maskComments(source) {
    _blocks();
    _defs();
  }

  final String path;

  /// The source with comments blanked out (offsets unchanged).
  final String code;
  final blocks = <_Block>[];
  final defs = <_Def>[];

  int lineOf(int offset) => '\n'.allMatches(code.substring(0, offset)).length + 1;

  void _blocks() {
    final stack = <(int, String?, String?)>[];
    var segStart = 0;
    for (var i = 0; i < code.length;) {
      final c = code[i];
      final s = _stringEnd(code, i);
      if (s != null) {
        i = s;
        continue;
      }
      if (c == '{') {
        final header = code.substring(segStart, i);
        final m = RegExp(r'\b(?:class|mixin|extension|enum)\s+(\w+)').firstMatch(header);
        final st = m == null ? null : RegExp(r'\bextends\s+State<(\w+)>').firstMatch(header);
        stack.add((i, m?.group(1), st?.group(1)));
        segStart = i + 1;
      } else if (c == '}') {
        if (stack.isNotEmpty) {
          final (start, cls, state) = stack.removeLast();
          blocks.add(_Block(start, i, cls, state));
        }
        segStart = i + 1;
      } else if (c == ';') {
        segStart = i + 1;
      }
      i++;
    }
    blocks.sort((a, b) => a.start.compareTo(b.start));
  }

  /// Innermost block containing [offset].
  _Block? blockAt(int offset) {
    _Block? best;
    for (final b in blocks) {
      if (b.start < offset && offset < b.end && (best == null || b.start > best.start)) best = b;
    }
    return best;
  }

  /// Every class body containing [offset], innermost first.
  Iterable<_Block> classesAt(int offset) =>
      blocks.where((b) => b.className != null && b.start < offset && offset < b.end).toList().reversed;

  static final _varDef = RegExp(r'\b((?:(?:static|late)\s+)*)(?:const|final|var)\s+(?:String\??\s+)?([A-Za-z_]\w*)\s*=(?![=>])');
  static final _typedVar = RegExp(r'(?<![\w.<])((?:static\s+)?)String\??\s+([A-Za-z_]\w*)\s*=(?![=>])');
  static final _getter = RegExp(r'((?:static\s+)?)String\??\s+get\s+([A-Za-z_]\w*)\s*(=>|\{)');
  static final _function = RegExp(r'((?:static\s+)?)String\??\s+([A-Za-z_]\w*)\s*\(');

  void _defs() {
    void add(int offset, String name, int exprStart, bool isStatic) {
      final block = blockAt(offset);
      final kind = block == null ? _Kind.top : (block.className != null ? _Kind.member : _Kind.local);
      defs.add(_Def(this, name, offset, exprStart, kind, isStatic, block?.className, block));
    }

    for (final m in _varDef.allMatches(code)) {
      if (_inString(m.start)) continue;
      add(m.start, m.group(2)!, m.end, m.group(1)!.contains('static'));
    }
    for (final m in _typedVar.allMatches(code)) {
      if (_inString(m.start)) continue;
      if (RegExp(r'\b(?:const|final|var)\s+$').hasMatch(code.substring(m.start < 20 ? 0 : m.start - 20, m.start))) continue;
      add(m.start, m.group(2)!, m.end, m.group(1)!.contains('static'));
    }
    for (final m in _getter.allMatches(code)) {
      if (_inString(m.start)) continue;
      final start = m.group(3) == '=>' ? m.end : _returnIn(m.end - 1);
      if (start != null) add(m.start, m.group(2)!, start, m.group(1)!.contains('static'));
    }
    for (final m in _function.allMatches(code)) {
      if (_inString(m.start)) continue;
      final close = _skipBalanced(code, m.end - 1);
      if (close == null) continue;
      var j = _ws(code, close);
      int? start;
      if (code.startsWith('=>', j)) {
        start = j + 2;
      } else if (j < code.length && code[j] == '{') {
        start = _returnIn(j);
      }
      if (start != null) add(m.start, m.group(2)!, start, m.group(1)!.contains('static'));
    }
  }

  /// `{ return expr; }` → the start of expr, when the body's first statement is that return.
  int? _returnIn(int brace) {
    final j = _ws(code, brace + 1);
    return code.startsWith('return', j) ? j + 6 : null;
  }

  List<int>? _stringRanges;

  bool _inString(int offset) {
    if (_stringRanges == null) {
      final r = <int>[];
      for (var i = 0; i < code.length;) {
        final s = _stringEnd(code, i);
        if (s != null) {
          r
            ..add(i)
            ..add(s);
          i = s;
        } else {
          i++;
        }
      }
      _stringRanges = r;
    }
    final r = _stringRanges!;
    for (var k = 0; k < r.length; k += 2) {
      if (r[k] <= offset && offset < r[k + 1]) return true;
      if (r[k] > offset) break;
    }
    return false;
  }
}

// ── lexing helpers ────────────────────────────────────────────────────────────

bool _isIdStart(String c) => RegExp(r'[A-Za-z_$]').hasMatch(c);
bool _isId(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

int _ws(String s, int i) {
  while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\r' || s[i] == '\t')) {
    i++;
  }
  return i;
}

/// If a string literal starts at [i], the index just after it.
int? _stringEnd(String s, int i) {
  var j = i;
  var raw = false;
  if (s[j] == 'r' && j + 1 < s.length && (s[j + 1] == '\'' || s[j + 1] == '"') && (j == 0 || !_isId(s[j - 1]))) {
    raw = true;
    j++;
  }
  if (s[j] != '\'' && s[j] != '"') return null;
  if (!raw && j > 0 && _isId(s[j - 1])) return null;
  final q = s[j];
  final triple = s.startsWith(q * 3, j);
  final close = triple ? q * 3 : q;
  j += close.length;
  while (j < s.length) {
    if (!raw && s[j] == '\\') {
      j += 2;
      continue;
    }
    if (s.startsWith(close, j)) return j + close.length;
    if (!triple && s[j] == '\n') return j; // unterminated: stop at the line end
    if (!raw && s.startsWith(r'${', j)) {
      j = _codeEnd(s, j + 2);
      continue;
    }
    j++;
  }
  return j;
}

/// From inside `${`, the index after its closing `}`.
int _codeEnd(String s, int i) {
  var depth = 1;
  while (i < s.length) {
    final e = _stringEnd(s, i);
    if (e != null) {
      i = e;
      continue;
    }
    if (s[i] == '{') depth++;
    if (s[i] == '}' && --depth == 0) return i + 1;
    i++;
  }
  return i;
}

/// [i] is at `(`, `[`, `{` or `<`: the index after the matching close, or null.
int? _skipBalanced(String s, int i) {
  const pairs = {'(': ')', '[': ']', '{': '}', '<': '>'};
  final stack = <String>[pairs[s[i]]!];
  i++;
  while (i < s.length && stack.isNotEmpty) {
    final e = _stringEnd(s, i);
    if (e != null) {
      i = e;
      continue;
    }
    final c = s[i];
    if (pairs.containsKey(c) && (c != '<' || stack.last == '>')) {
      stack.add(pairs[c]!);
    } else if (c == stack.last) {
      stack.removeLast();
    } else if (stack.last == '>' && (c == ';' || c == ')' || c == '{')) {
      return null; // a less-than, not a type argument list
    }
    i++;
  }
  return stack.isEmpty ? i : null;
}

String _maskComments(String s) {
  final b = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final e = _stringEnd(s, i);
    if (e != null) {
      b.write(s.substring(i, e));
      i = e;
      continue;
    }
    if (s.startsWith('//', i)) {
      final nl = s.indexOf('\n', i);
      final end = nl < 0 ? s.length : nl;
      b.write(' ' * (end - i));
      i = end;
      continue;
    }
    if (s.startsWith('/*', i)) {
      var depth = 0, j = i;
      while (j < s.length) {
        if (s.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (s.startsWith('*/', j)) {
          j += 2;
          if (--depth == 0) break;
        } else {
          j++;
        }
      }
      b.write(s.substring(i, j).replaceAll(RegExp(r'[^\n]'), ' '));
      i = j;
      continue;
    }
    b.write(s[i]);
    i++;
  }
  return b.toString();
}

// ── expression parser (on one file's masked code) ────────────────────────────

class _Parser {
  _Parser(this.s);
  final String s;

  (_Node, int) expr(int i) {
    var (n, j) = _concat(i);
    j = _ws(s, j);
    if (j < s.length && s[j] == '?' && !s.startsWith('?.', j) && !s.startsWith('??', j) && !s.startsWith('?[', j)) {
      final (a, k) = expr(j + 1);
      final c = _ws(s, k);
      if (c < s.length && s[c] == ':') {
        final (b, m) = expr(c + 1);
        return (_Alt([a, b]), m);
      }
      return (_Unknown(), k);
    }
    return (n, j);
  }

  (_Node, int) _concat(int i) {
    var (n, j) = _term(i);
    final parts = [n];
    while (true) {
      final k = _ws(s, j);
      if (k < s.length && s[k] == '+' && !s.startsWith('++', k) && !s.startsWith('+=', k)) {
        final (t, m) = _term(k + 1);
        parts.add(t);
        j = m;
      } else if (s.startsWith('??', k) && !s.startsWith('??=', k)) {
        // `a ?? b`: either side
        final (t, m) = _term(k + 2);
        final left = parts.length == 1 ? parts.single : _Cat(List.of(parts));
        parts
          ..clear()
          ..add(_Alt([left, t]));
        j = m;
      } else {
        break;
      }
    }
    return (parts.length == 1 ? parts.single : _Cat(parts), j);
  }

  (_Node, int) _term(int i) {
    i = _ws(s, i);
    if (i >= s.length) return (_Unknown(), i);
    if (_stringEnd(s, i) != null) {
      final parts = <_Node>[];
      var j = i;
      while (j < s.length && _stringEnd(s, j) != null) {
        final (n, e) = _string(j);
        parts.add(n);
        j = _ws(s, e);
      }
      return (parts.length == 1 ? parts.single : _Cat(parts), j);
    }
    if (s[i] == '(') {
      final (n, j) = expr(i + 1);
      final k = _ws(s, j);
      return (n, k < s.length && s[k] == ')' ? k + 1 : k);
    }
    if (_isIdStart(s[i])) {
      final j = _chainEnd(i);
      return (_Ref(s.substring(i, j), i), j);
    }
    return (_Unknown(), i);
  }

  int _chainEnd(int i) {
    var j = i;
    while (j < s.length) {
      if (_isId(s[j])) {
        j++;
      } else if (s[j] == '(' || s[j] == '[' || s[j] == '<') {
        final e = _skipBalanced(s, j);
        if (e == null) break;
        j = e;
      } else if (s[j] == '!' && !s.startsWith('!=', j)) {
        j++;
      } else if (s[j] == '.' && j + 1 < s.length && _isIdStart(s[j + 1])) {
        j++;
      } else if (s.startsWith('?.', j) && j + 2 < s.length && _isIdStart(s[j + 2])) {
        j += 2;
      } else {
        break;
      }
    }
    return j;
  }

  (_Node, int) _string(int i) {
    final end = _stringEnd(s, i)!;
    var j = i;
    var raw = false;
    if (s[j] == 'r') {
      raw = true;
      j++;
    }
    final q = s[j];
    final close = s.startsWith(q * 3, j) ? q * 3 : q;
    j += close.length;
    final stop = end - (s.startsWith(close, end - close.length) && end - close.length >= j ? close.length : 0);
    if (raw) return (_Lit(s.substring(j, stop)), end);
    final parts = <_Node>[];
    final lit = StringBuffer();
    void flush() {
      if (lit.isNotEmpty) parts.add(_Lit(lit.toString()));
      lit.clear();
    }

    while (j < stop) {
      final c = s[j];
      if (c == '\\' && j + 1 < stop) {
        final n = s[j + 1];
        lit.write(n == 'n' || n == 't' || n == 'r' ? ' ' : n);
        j += 2;
      } else if (s.startsWith(r'${', j)) {
        final e = _codeEnd(s, j + 2);
        flush();
        final (n, _) = expr(j + 2);
        parts.add(n);
        j = e;
      } else if (c == r'$' && j + 1 < stop && RegExp(r'[A-Za-z_]').hasMatch(s[j + 1])) {
        var k = j + 1;
        while (k < stop && RegExp(r'[A-Za-z0-9_]').hasMatch(s[k])) {
          k++;
        }
        flush();
        parts.add(_Ref(s.substring(j + 1, k), j + 1));
        j = k;
      } else {
        lit.write(c);
        j++;
      }
    }
    flush();
    return (parts.isEmpty ? _Lit('') : (parts.length == 1 ? parts.single : _Cat(parts)), end);
  }
}

// ── the scan over every file ──────────────────────────────────────────────────

class ApiCallScan {
  ApiCallScan(Map<String, String> sources) {
    for (final e in sources.entries) {
      final f = _File(e.key, e.value);
      _files.add(f);
      _parsers[f] = _Parser(f.code);
      for (final d in f.defs) {
        _byName.putIfAbsent(d.name, () => []).add(d);
      }
      _classes.addAll(f.blocks.map((b) => b.className).whereType<String>());
    }
  }

  final _files = <_File>[];
  final _parsers = <_File, _Parser>{};
  final _byName = <String, List<_Def>>{};
  final _classes = <String>{};

  static final _call = RegExp(r'\.(' + _methods.keys.join('|') + r')\s*(?:<[^<>()]*>)?\(');
  static final _receiver = RegExp(r'(?:ApiClient(?:\(\)|\.instance)|\b\w*[Aa]pi\w*|\b_?client)\s*$');

  /// Every ApiClient-like call in the sources. A call whose path is not resolved is kept (unresolved) only when its
  /// receiver looks like an ApiClient (`_api`, `api`, `ApiClient()`, `client`, …): `.get(key)` on a map is not a call.
  List<ApiCall> calls() {
    final out = <ApiCall>[];
    for (final f in _files) {
      for (final m in _call.allMatches(f.code)) {
        if (f._inString(m.start)) continue;
        final argStart = m.end;
        final (node, end) = _parsers[f]!.expr(argStart);
        final after = _ws(f.code, end);
        if (after >= f.code.length || (f.code[after] != ',' && f.code[after] != ')')) continue; // not a lone first arg
        final source = f.code.substring(argStart, end).trim();
        if (source.isEmpty) continue;
        final tpls = _resolve(node, f, 0);
        final paths = <String>{};
        var external = false, unresolved = false;
        for (final t in tpls) {
          final first = t.isEmpty ? null : t.first;
          if (first == null) {
            unresolved = true;
          } else if (first.startsWith('http')) {
            external = true;
          } else if (first.startsWith('/')) {
            paths.add(normalizeTemplate(t));
          } else {
            unresolved = true;
          }
        }
        if (external && paths.isEmpty) continue; // a full URL (signed file link, a third party): not our API
        final looksApi = _receiver.hasMatch(f.code.substring(0, m.start));
        if (paths.isEmpty && (!looksApi || node is _Lit)) continue; // `prefs.get('key')`, `map.get(k)`
        out.add(ApiCall(_methods[m.group(1)]!, unresolved && paths.isEmpty ? const [] : (paths.toList()..sort()),
            f.path, f.lineOf(m.start), source));
      }
    }
    return out;
  }

  List<_Tpl> _resolve(_Node n, _File f, int depth) {
    if (depth > 12) return [_holeOnly];
    switch (n) {
      case _Lit(:final text):
        return [
          [text]
        ];
      case _Unknown():
        return [_holeOnly];
      case _Alt(:final options):
        return _cap([for (final o in options) ..._resolve(o, f, depth + 1)]);
      case _Cat(:final parts):
        var acc = <_Tpl>[[]];
        for (final p in parts) {
          final r = _resolve(p, f, depth + 1);
          acc = _cap([
            for (final a in acc)
              for (final b in r) [...a, ...b]
          ]);
        }
        return acc;
      case _Ref():
        return _ref(n, f, depth);
    }
  }

  List<_Tpl> _cap(List<_Tpl> l) {
    final seen = <String>{};
    final out = <_Tpl>[];
    for (final t in l) {
      if (seen.add(t.map((p) => p ?? '<hole>').join('|')) && out.length < _maxAlternatives) out.add(t);
    }
    return out;
  }

  /// `a.b<T>(x).c` → [(a, false, null), (b, true, T), (c, false, null)]
  List<(String, bool, String?)> _segments(String chain) {
    final segs = <(String, bool, String?)>[];
    var i = 0;
    while (i < chain.length) {
      var j = i;
      while (j < chain.length && _isId(chain[j])) {
        j++;
      }
      final name = chain.substring(i, j);
      var call = false;
      String? typeArg;
      while (j < chain.length && chain[j] != '.' && !chain.startsWith('?.', j)) {
        if (chain[j] == '(') call = true;
        if (chain[j] == '<' && typeArg == null) typeArg = RegExp(r'^<\s*(\w+)').firstMatch(chain.substring(j))?.group(1);
        if (chain[j] == '(' || chain[j] == '[' || chain[j] == '<') {
          j = _skipBalanced(chain, j) ?? chain.length;
        } else {
          j++;
        }
      }
      segs.add((name, call, typeArg));
      i = j + (chain.startsWith('?.', j) ? 2 : 1);
    }
    return segs;
  }

  List<_Tpl> _ref(_Ref r, _File f, int depth) {
    final segs = _segments(r.chain);
    for (var k = segs.length - 1; k >= 0; k--) {
      final name = segs[k].$1;
      final defs = k == 0 ? _bare(name, f, r.offset) : _member(name, segs[k - 1], f, r.offset);
      final values = <List<_Tpl>>[];
      for (final d in defs) {
        final v = _value(d, depth);
        if (v != null) values.add(v);
      }
      if (values.isEmpty) continue;
      // Several declarations of that name (two classes with a `base` getter, two files with a public `base`):
      // only trusted when they all give the same path, else the name is ambiguous and stays a run-time value.
      String key(List<_Tpl> v) => (v.map(normalizeTemplate).toSet().toList()..sort()).join('|');
      if (values.map(key).toSet().length > 1) return [_holeOnly];
      final tailOk = segs.skip(k + 1).every((s) => _stringMethods.contains(s.$1));
      return tailOk ? values.first : [_holeOnly];
    }
    return [_holeOnly];
  }

  /// The templates of [d] when it is a path (starts with `/`, `http`, or a resolved path), else null.
  List<_Tpl>? _value(_Def d, int depth) {
    if (d.value != null) return d.value!.isEmpty ? null : d.value;
    if (d.resolving) return null;
    d.resolving = true;
    d.node ??= _parsers[d.file]!.expr(d.exprStart).$1;
    final v = _resolve(d.node!, d.file, depth + 1);
    d.resolving = false;
    final isPath = v.any((t) => t.isNotEmpty && t.first != null && (t.first!.startsWith('/') || t.first!.startsWith('http')));
    d.value = isPath ? v : const [];
    return isPath ? v : null;
  }

  Iterable<_Def> _bare(String name, _File f, int offset) {
    final all = _byName[name] ?? const [];
    // a local of an enclosing block, declared before
    final locals = all.where((d) =>
        d.file == f && d.kind == _Kind.local && d.offset < offset && d.block!.start < offset && offset < d.block!.end);
    if (locals.isNotEmpty) return [locals.reduce((a, b) => a.offset > b.offset ? a : b)];
    // a member of an enclosing class
    for (final c in f.classesAt(offset)) {
      final m = all.where((d) => d.file == f && d.kind == _Kind.member && d.block == c);
      if (m.isNotEmpty) return m;
    }
    final top = all.where((d) => d.file == f && d.kind == _Kind.top);
    if (top.isNotEmpty) return top;
    if (name.startsWith('_')) return const [];
    return all.where((d) => d.kind == _Kind.top);
  }

  Iterable<_Def> _member(String name, (String, bool, String?) qualifier, _File f, int offset) {
    final all = (_byName[name] ?? const <_Def>[]).where((d) => d.kind == _Kind.member);
    final (q, qCall, qType) = qualifier;
    Iterable<_Def> ofClass(String cls) => all.where((d) => d.className == cls && !d.isStatic);
    if (RegExp(r'^_?[A-Z]').hasMatch(q)) {
      // `ClassName.name`: a static member of that class; `ClassName(…).name`: an instance member
      return qCall ? ofClass(q) : all.where((d) => d.className == q && d.isStatic);
    }
    if ((q == 'read' || q == 'watch' || q == 'select') && qType != null) return ofClass(qType); // context.read<T>()
    if (q == 'widget') {
      // inside `State<X>`: a member of X (usually a constructor field, so not resolvable — never a guess)
      final widgetClass = f.classesAt(offset).map((b) => b.stateOf).whereType<String>().firstOrNull;
      return widgetClass == null ? const [] : ofClass(widgetClass);
    }
    final type = _typeOf(q, f, offset);
    if (type != null && _classes.contains(type)) return ofClass(type);
    // unknown type: any instance member of that name (private ones only in this file); _ref keeps it only when
    // they all give the same path
    return all.where((d) => !d.isStatic && (!name.startsWith('_') || d.file == f));
  }

  /// The declared type of the variable / field / getter [q] seen from [offset] in [f]: `OrgSession s`,
  /// `OrgSession get _s => …`, `final s = context.read<OrgSession>()`, `final p = Provider(…)`. The nearest
  /// declaration before [offset] wins, else the first one in the file.
  String? _typeOf(String q, _File f, int offset) {
    final id = RegExp.escape(q);
    final patterns = [
      RegExp('\\b(?:final|var)\\s+$id\\s*=\\s*\\w+\\.(?:read|watch)<(\\w+)>'),
      RegExp('\\b(?:final|var)\\s+$id\\s*=\\s*([A-Z]\\w*)(?:\\.\\w+)?\\('),
      RegExp('\\b([A-Z]\\w*)\\??\\s+(?:get\\s+)?$id\\b(?!\\s*\\()'),
    ];
    (int, String)? best, first;
    for (final re in patterns) {
      for (final m in re.allMatches(f.code)) {
        final t = (m.start, m.group(1)!);
        if (first == null || t.$1 < first.$1) first = t;
        if (m.start < offset && (best == null || t.$1 > best.$1)) best = t;
      }
    }
    return (best ?? first)?.$2;
  }

}

/// A resolved template as a path: query and fragment dropped, `//` collapsed, holes as `{}`.
String normalizeTemplate(List<String?> parts) {
  final b = StringBuffer();
  for (final p in parts) {
    if (p == null) {
      b.write(hole);
      continue;
    }
    final q = p.indexOf(RegExp(r'[?#]'));
    if (q >= 0) {
      b.write(p.substring(0, q));
      break;
    }
    b.write(p);
  }
  return b.toString().replaceAll(RegExp(r'/{2,}'), '/');
}

// ── matching a template against the server's routes ──────────────────────────

/// Which service answers [path] (the split nginx makes, docs/DEPLOY.md in ../back).
String serviceOf(String path) {
  if (path == '/api/v1/exam' || path.startsWith('/api/v1/exam/')) return 'exam';
  if (path == '/api/v1/rag' || path.startsWith('/api/v1/rag/')) return 'rag';
  return 'core';
}

/// True when the app template [app] (holes `{}`) can reach the server route [server]. Server parameters are
/// `{name}` (any segment), `{name:int}` (digits) or `{name:a|b}` (one of those words: a `Literal` / enum). Either
/// side may be the more specific one: the app may send a literal where the server takes a parameter
/// (`/theme/mobile` → `/theme/{platform}`), or a run-time value where the server has a fixed segment
/// (`/payouts/$kind` → `/payouts/bank`). A literal never matches an integer parameter or a word outside the enum
/// (`/payments/transfer-status` is not `/payments/{payment_id:int}`: FastAPI would answer 422).
bool templatesMatch(String app, String server) {
  if (RegExp('^${_serverPattern(server)}\$').hasMatch(app.replaceAll(hole, '0'))) return true;
  final serverSample = server.replaceAllMapped(RegExp(r'\{[^}:]*(?::([^}]*))?\}'), (m) {
    final kind = m[1];
    return kind == null ? 'X0' : (kind == 'int' ? '0' : kind.split('|').first);
  });
  return RegExp('^${_appPattern(app)}\$').hasMatch(serverSample);
}

/// An app template with a hole glued to a literal and followed by `/` or the end (`'$_base$path'`,
/// `'$_write$path/$id'`): that hole is a sub-path of any length, so only the rest of the template is checked.
bool isPrefixOnly(String app) => RegExp(r'[^/]\{\}(?:/|$)').hasMatch(app);

String _serverPattern(String server) {
  final b = StringBuffer();
  for (final m in RegExp(r'\{([^}]*)\}|[^{]+').allMatches(server)) {
    final param = m.group(1);
    final kind = param == null || !param.contains(':') ? null : param.substring(param.indexOf(':') + 1);
    b.write(param == null
        ? RegExp.escape(m.group(0)!)
        : kind == null
            ? '[^/]+'
            : kind == 'int'
                ? '[0-9]+'
                : '(?:${kind.split('|').map(RegExp.escape).join('|')}|0)'); // `0`: a run-time value from the app
  }
  return b.toString();
}

String _appPattern(String app) {
  final parts = app.split(hole);
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    b.write(RegExp.escape(parts[i]));
    if (i == parts.length - 1) break;
    final before = parts[i], after = parts[i + 1];
    final wholeSegment = (before.isEmpty || before.endsWith('/')) && (after.isEmpty || after.startsWith('/'));
    if (before.isNotEmpty && !before.endsWith('/') && (after.isEmpty || after.startsWith('/'))) {
      b.write('.*'); // `'$_base$path'`: a sub-path
    } else {
      b.write(wholeSegment ? '[^/]+' : '[^/]*');
    }
  }
  return b.toString();
}
