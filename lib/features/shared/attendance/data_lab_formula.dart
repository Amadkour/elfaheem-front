// lib/features/shared/data_lab/data_lab_formula.dart
// A small Excel-style formula engine for Data Lab columns (pure Dart, no Flutter import).
//
//   =ROUND(([Quiz] + [Midterm]) / 2)          operators:  + - * / ^ %   and comparisons  = <> < > <= >=
//   =CEILING([Project] * 0.4 + [Exam] * 0.6, 5)
//   =IF([Attendance] >= 75, [Total], 0)
//
// Teachers type column NAMES in [square brackets]. Before saving, names are turned into column KEYS
// ({quiz_1}), so renaming a column never breaks a formula (see DlFormulaText).
//
// Functions: SUM AVERAGE MIN MAX COUNT · ROUND ROUNDUP ROUNDDOWN TRUNC INT CEILING FLOOR ABS SQRT POWER MOD
//            IF AND OR NOT
// An empty value counts as 0 (missing = 'zero') or makes the result empty (missing = 'skip');
// SUM / AVERAGE / MIN / MAX / COUNT simply ignore empty values in 'skip' mode.
library;

import 'dart:math' as math;

import '../../teacher/data_lab/data_lab_model.dart';

class DlFormulaError implements Exception {
  DlFormulaError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Returns the number behind a column key, or null when that cell is empty.
typedef DlLookup = double? Function(String key);

double? _fin(double? v) => (v == null || v.isNaN || v.isInfinite) ? null : v;

/// Removes floating point dust (1.1 * 10 = 11.000000000000002) before rounding up / down.
double _fix(double v) => double.parse(v.toStringAsFixed(9));

// ─────────────────────────────────────────────────────────────────────────────
// Syntax tree
// ─────────────────────────────────────────────────────────────────────────────

abstract class _Node {
  const _Node();

  double? eval(DlLookup l);

  void collect(Set<String> out);
}

class _Num extends _Node {
  const _Num(this.v);

  final double v;

  @override
  double? eval(DlLookup l) => v;

  @override
  void collect(Set<String> out) {}
}

class _Ref extends _Node {
  const _Ref(this.key);

  final String key;

  @override
  double? eval(DlLookup l) => l(key);

  @override
  void collect(Set<String> out) => out.add(key);
}

class _Neg extends _Node {
  const _Neg(this.a);

  final _Node a;

  @override
  double? eval(DlLookup l) {
    final x = a.eval(l);
    return x == null ? null : -x;
  }

  @override
  void collect(Set<String> out) => a.collect(out);
}

class _Pct extends _Node {
  const _Pct(this.a);

  final _Node a;

  @override
  double? eval(DlLookup l) {
    final x = a.eval(l);
    return x == null ? null : x / 100;
  }

  @override
  void collect(Set<String> out) => a.collect(out);
}

class _Bin extends _Node {
  const _Bin(this.op, this.a, this.b);

  final String op;
  final _Node a, b;

  @override
  double? eval(DlLookup l) {
    final x = a.eval(l), y = b.eval(l);
    if (x == null || y == null) return null;
    final eq = (x - y).abs() < 1e-9;
    switch (op) {
      case '+':
        return _fin(x + y);
      case '-':
        return _fin(x - y);
      case '*':
        return _fin(x * y);
      case '/':
        return y == 0 ? null : _fin(x / y);
      case '^':
        return _fin(math.pow(x, y).toDouble());
      case '=':
        return eq ? 1 : 0;
      case '<>':
        return eq ? 0 : 1;
      case '<':
        return (!eq && x < y) ? 1 : 0;
      case '>':
        return (!eq && x > y) ? 1 : 0;
      case '<=':
        return (eq || x < y) ? 1 : 0;
      case '>=':
        return (eq || x > y) ? 1 : 0;
    }
    return null;
  }

  @override
  void collect(Set<String> out) {
    a.collect(out);
    b.collect(out);
  }
}

class _Call extends _Node {
  const _Call(this.name, this.args);

  final String name;
  final List<_Node> args;

  @override
  void collect(Set<String> out) {
    for (final a in args) {
      a.collect(out);
    }
  }

  static double _rnd(double x, int digits, double Function(double) f) {
    final m = math.pow(10, digits).toDouble();
    return f(_fix(x * m)) / m;
  }

  @override
  double? eval(DlLookup l) {
    // IF only evaluates the branch it needs, so "IF([B]=0, 0, [A]/[B])" never divides by zero.
    if (name == 'IF') {
      final c = args[0].eval(l);
      if (c == null) return null;
      if (c != 0) return args[1].eval(l);
      return args.length > 2 ? args[2].eval(l) : 0;
    }

    final vals = [for (final a in args) a.eval(l)];
    final nums = vals.whereType<double>().toList();

    // Functions that work on a list and ignore empty cells.
    switch (name) {
      case 'SUM':
        return nums.isEmpty ? null : _fin(nums.fold<double>(0, (s, e) => s + e));
      case 'AVERAGE':
        return nums.isEmpty ? null : _fin(nums.fold<double>(0, (s, e) => s + e) / nums.length);
      case 'MIN':
        return nums.isEmpty ? null : nums.reduce(math.min);
      case 'MAX':
        return nums.isEmpty ? null : nums.reduce(math.max);
      case 'COUNT':
        return nums.length.toDouble();
      case 'AND':
        return nums.isEmpty ? null : (nums.every((e) => e != 0) ? 1 : 0);
      case 'OR':
        return nums.isEmpty ? null : (nums.any((e) => e != 0) ? 1 : 0);
    }

    // Everything else needs every value to be present.
    if (vals.any((e) => e == null)) return null;
    final x = vals[0]!;
    final y = vals.length > 1 ? vals[1] : null;
    final int d = y == null ? 0 : math.max(-9, math.min(9, y.toInt()));

    switch (name) {
      case 'ABS':
        return x.abs();
      case 'SQRT':
        return x < 0 ? null : math.sqrt(x);
      case 'INT':
        return _fix(x).floorToDouble();
      case 'NOT':
        return x == 0 ? 1 : 0;
      case 'ROUND':
        return _fin(_rnd(x, d, (v) => v.roundToDouble()));
      case 'ROUNDUP':
        return _fin(_rnd(x, d, (v) => v < 0 ? v.floorToDouble() : v.ceilToDouble()));
      case 'ROUNDDOWN':
      case 'TRUNC':
        return _fin(_rnd(x, d, (v) => v.truncateToDouble()));
      case 'CEILING':
        {
          final s = (y ?? 1).abs();
          return s == 0 ? 0 : _fin(_fix(_fix(x / s).ceilToDouble() * s));
        }
      case 'FLOOR':
        {
          final s = (y ?? 1).abs();
          return s == 0 ? 0 : _fin(_fix(_fix(x / s).floorToDouble() * s));
        }
      case 'POWER':
        return _fin(math.pow(x, y!).toDouble());
      case 'MOD':
        return y == 0 ? null : _fin(_fix(x - y! * _fix(x / y).floorToDouble()));
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lexer
// ─────────────────────────────────────────────────────────────────────────────

enum _T { num, ref, id, op, lp, rp, comma, end }

class _Tok {
  const _Tok(this.t, this.s);

  final _T t;
  final String s;
}

const _arity = <String, List<int>>{
  'ABS': [1, 1],
  'SQRT': [1, 1],
  'INT': [1, 1],
  'NOT': [1, 1],
  'TRUNC': [1, 2],
  'ROUND': [1, 2],
  'ROUNDUP': [1, 2],
  'ROUNDDOWN': [1, 2],
  'CEILING': [1, 2],
  'FLOOR': [1, 2],
  'POWER': [2, 2],
  'MOD': [2, 2],
  'IF': [2, 3],
  'SUM': [1, 99],
  'AVERAGE': [1, 99],
  'MIN': [1, 99],
  'MAX': [1, 99],
  'COUNT': [1, 99],
  'AND': [1, 99],
  'OR': [1, 99],
};

const _alias = <String, String>{'AVG': 'AVERAGE', 'CEIL': 'CEILING', 'TRUNCATE': 'TRUNC'};

/// Arabic digits / signs → the ones the parser understands.
String _normalize(String s) {
  const digits = '٠١٢٣٤٥٦٧٨٩';
  const map = <String, String>{'×': '*', '÷': '/', '−': '-', '–': '-', '٫': '.', '٬': '', '،': ',', ';': ',', '٪': '%', '＝': '='};
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final k = digits.indexOf(ch);
    b.write(k >= 0 ? '$k' : (map[ch] ?? ch));
  }
  return b.toString();
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

bool _isAlpha(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
}

List<_Tok> _lex(String src) {
  final out = <_Tok>[];
  var i = 0;
  while (i < src.length) {
    final ch = src[i];
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
      i++;
      continue;
    }
    if (_isDigit(ch) || (ch == '.' && i + 1 < src.length && _isDigit(src[i + 1]))) {
      var j = i;
      var dot = false;
      while (j < src.length && (_isDigit(src[j]) || (src[j] == '.' && !dot))) {
        if (src[j] == '.') dot = true;
        j++;
      }
      out.add(_Tok(_T.num, src.substring(i, j)));
      i = j;
      continue;
    }
    if (ch == '{') {
      final j = src.indexOf('}', i);
      if (j < 0) throw DlFormulaError('A column reference is not closed');
      out.add(_Tok(_T.ref, src.substring(i + 1, j)));
      i = j + 1;
      continue;
    }
    if (_isAlpha(ch)) {
      var j = i;
      while (j < src.length && (_isAlpha(src[j]) || _isDigit(src[j]))) {
        j++;
      }
      out.add(_Tok(_T.id, src.substring(i, j).toUpperCase()));
      i = j;
      continue;
    }
    final two = i + 1 < src.length ? src.substring(i, i + 2) : '';
    if (two == '<>' || two == '<=' || two == '>=' || two == '!=') {
      out.add(_Tok(_T.op, two));
      i += 2;
      continue;
    }
    switch (ch) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '^':
      case '%':
      case '=':
      case '<':
      case '>':
        out.add(_Tok(_T.op, ch));
      case '(':
        out.add(const _Tok(_T.lp, '('));
      case ')':
        out.add(const _Tok(_T.rp, ')'));
      case ',':
        out.add(const _Tok(_T.comma, ','));
      default:
        throw DlFormulaError('Unexpected "$ch" in the formula');
    }
    i++;
  }
  out.add(const _Tok(_T.end, ''));
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Parser (precedence like Excel: comparison < + - < * / < ^ < unary minus < %)
// ─────────────────────────────────────────────────────────────────────────────

class _Parser {
  _Parser(this.t);

  final List<_Tok> t;
  int i = 0;

  _Tok get _peek => t[i];

  _Node parseAll() {
    final n = _cmp();
    if (_peek.t != _T.end) {
      throw DlFormulaError(_peek.t == _T.rp ? 'There is an extra ")"' : 'Unexpected "${_peek.s}" — is an operator missing?');
    }
    return n;
  }

  bool _isOp(Set<String> ops) => _peek.t == _T.op && ops.contains(_peek.s);

  _Node _cmp() {
    var l = _add();
    while (_isOp(const {'=', '<>', '!=', '<', '>', '<=', '>='})) {
      final op = _peek.s == '!=' ? '<>' : _peek.s;
      i++;
      l = _Bin(op, l, _add());
    }
    return l;
  }

  _Node _add() {
    var l = _mul();
    while (_isOp(const {'+', '-'})) {
      final op = _peek.s;
      i++;
      l = _Bin(op, l, _mul());
    }
    return l;
  }

  _Node _mul() {
    var l = _pow();
    while (_isOp(const {'*', '/'})) {
      final op = _peek.s;
      i++;
      l = _Bin(op, l, _pow());
    }
    return l;
  }

  _Node _pow() {
    var l = _unary();
    while (_isOp(const {'^'})) {
      i++;
      l = _Bin('^', l, _unary());
    }
    return l;
  }

  _Node _unary() {
    if (_isOp(const {'-'})) {
      i++;
      return _Neg(_unary());
    }
    if (_isOp(const {'+'})) {
      i++;
      return _unary();
    }
    var n = _primary();
    while (_isOp(const {'%'})) {
      i++;
      n = _Pct(n);
    }
    return n;
  }

  _Node _primary() {
    final tok = _peek;
    switch (tok.t) {
      case _T.num:
        i++;
        return _Num(double.parse(tok.s));
      case _T.ref:
        i++;
        return _Ref(tok.s);
      case _T.lp:
        i++;
        final n = _cmp();
        if (_peek.t != _T.rp) throw DlFormulaError('A ")" is missing');
        i++;
        return n;
      case _T.id:
        i++;
        final name = _alias[tok.s] ?? tok.s;
        final range = _arity[name];
        if (range == null) {
          throw DlFormulaError(_peek.t == _T.lp
              ? 'Unknown function ${tok.s}'
              : '"${tok.s}" is not a function — write column names in [square brackets]');
        }
        if (_peek.t != _T.lp) throw DlFormulaError('$name needs brackets, like $name(…)');
        i++;
        final args = <_Node>[];
        if (_peek.t == _T.rp) {
          i++;
        } else {
          while (true) {
            args.add(_cmp());
            if (_peek.t == _T.comma) {
              i++;
              continue;
            }
            if (_peek.t == _T.rp) {
              i++;
              break;
            }
            throw DlFormulaError('A ")" is missing after ${tok.s}(…');
          }
        }
        if (args.length < range[0] || args.length > range[1]) {
          throw DlFormulaError(range[0] == range[1]
              ? '$name needs ${range[0]} value${range[0] == 1 ? '' : 's'}'
              : '$name needs ${range[0]}${range[1] == 99 ? ' or more' : ' to ${range[1]}'} values');
        }
        return _Call(name, args);
      case _T.end:
        throw DlFormulaError('The formula ends too early');
      default:
        throw DlFormulaError('Unexpected "${tok.s}"');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

class DlFormula {
  DlFormula._(this._root, this.refs);

  final _Node _root;

  /// Column keys used by the formula.
  final Set<String> refs;

  static final Map<String, DlFormula> _cache = {};

  /// Parses an expression written with column KEYS: `ROUND(({quiz}+{mid})/2)`. Throws [DlFormulaError].
  static DlFormula compile(String src) {
    final hit = _cache[src];
    if (hit != null) return hit;
    var s = _normalize(src).trim();
    if (s.startsWith('=')) s = s.substring(1);
    if (s.trim().isEmpty) throw DlFormulaError('Type a formula first');
    final root = _Parser(_lex(s)).parseAll();
    final refs = <String>{};
    root.collect(refs);
    final f = DlFormula._(root, refs);
    if (_cache.length > 300) _cache.clear();
    return _cache[src] = f;
  }

  double? eval(DlLookup lookup) => _fin(_root.eval(lookup));
}

/// Converts between what the teacher types ([Quiz]) and what is stored ({quiz_1}).
class DlFormulaText {
  static final _label = RegExp(r'\[([^\]]+)\]');
  static final _key = RegExp(r'\{([^}]+)\}');

  /// `[Quiz] + 1` → `{quiz_1} + 1`. Throws [DlFormulaError] for an unknown column name.
  static String toKeys(String text, List<DlColumn> cols) {
    final byLabel = <String, String>{for (final c in cols) c.label.trim().toLowerCase(): c.key};
    return text.replaceAllMapped(_label, (m) {
      final name = m[1]!.trim();
      final key = byLabel[name.toLowerCase()];
      if (key == null) throw DlFormulaError('There is no column called [$name]');
      return '{$key}';
    });
  }

  /// `{quiz_1} + 1` → `[Quiz] + 1` (for showing a stored formula to the teacher).
  static String toLabels(String expr, List<DlColumn> cols) {
    final byKey = <String, String>{for (final c in cols) c.key: c.label};
    return expr.replaceAllMapped(_key, (m) => '[${byKey[m[1]] ?? m[1]}]');
  }
}
