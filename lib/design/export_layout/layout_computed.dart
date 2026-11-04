// lib/design/export_layout/layout_computed.dart
//
// The app's mirror of the server's computed-field evaluator (services/export_layout/computed.py, design engine v4):
// pure functions, no Flutter. Checked against the server's answers by test/fixtures/design_engine/computed_parity.json.
//
//   applyComputed(row, specs)   a NEW row with the `calc.` values added, in spec order (a spec may read earlier ones)
//   condMatches / groupMatches  conditions and nested groups
//   evaluateExpr                one value expression
//   computedSourceFields(specs) the source columns the specs read
library;

import 'layout_logic.dart' show layoutFixed;
import 'layout_model.dart';

const kComputedMaxSpecs = 30;
const kComputedMaxCases = 20;
const kComputedMaxItems = 10;
const kComputedMaxGroupDepth = 3;
const kComputedMaxExprDepth = 4;
const kComputedMaxArgs = 10;
const kComputedMaxResult = 2000;

const _arDigits = '٠١٢٣٤٥٦٧٨٩';

// Python's float(): digits with single underscores between digits, optional exponent.
final _floatRe = RegExp(r'^[+-]?(\d+(_\d+)*\.?(\d+(_\d+)*)?|\.\d+(_\d+)*)([eE][+-]?\d+(_\d+)*)?$');

double? _num(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  var s = '$v'.trim().replaceAll(',', '').replaceAll('٫', '.');
  final b = StringBuffer();
  for (final r in s.runes) {
    final i = _arDigits.indexOf(String.fromCharCode(r));
    b.write(i >= 0 ? '$i' : String.fromCharCode(r));
  }
  s = b.toString();
  if (s.isEmpty || s.length > 40 || !_floatRe.hasMatch(s)) return null;
  final f = double.tryParse(s.replaceAll('_', ''));
  return f != null && f.isFinite ? f : null;
}

final _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2})(?::(\d{2})(?::(\d{2})(?:[.,](\d+))?)?)?)?(?:[+-]\d{2}(?::?\d{2})?)?$');

DateTime? _date(Object? v) {
  if (v is DateTime) return DateTime.utc(v.year, v.month, v.day, v.hour, v.minute, v.second);
  if (v is! String) return null;
  final s = v.trim();
  if (s.length < 8 || s.length > 32 || s.length < 5 || s[4] != '-') return null;
  final m = _dateRe.firstMatch(s.replaceAll('Z', ''));
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final y = g(1), mo = g(2), d = g(3), h = g(4), mi = g(5), sec = g(6);
  if (y < 1 || mo < 1 || mo > 12 || d < 1 || h > 23 || mi > 59 || sec > 59) return null;
  final out = DateTime.utc(y, mo, d, h, mi, sec);
  return out.month == mo && out.day == d ? out : null;
}

final _marks = RegExp('[ؐ-ًؚ-ٰٟۖ-ۭـ]');

/// NFKC where Dart has no normaliser: full-width ASCII and the no-break spaces; then marks off, trim, case-fold.
String _norm(Object? v) {
  var s = v == null ? '' : _pyStr(v);
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0);
    } else if (r == 0xA0 || r == 0x2007 || r == 0x202F || r == 0x3000) {
      b.write(' ');
    } else {
      b.writeCharCode(r);
    }
  }
  s = b.toString().replaceAll(_marks, '');
  return s.trim().toLowerCase();
}

String _pyStr(Object? v) {
  if (v == null) return 'None';
  if (v is bool) return v ? 'True' : 'False';
  if (v is List) return '[${v.map((x) => x is String ? "'$x'" : _pyStr(x)).join(', ')}]';
  return '$v';
}

bool _empty(Object? v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

int _compare(Object? a, Object? b) {
  final na = _num(a), nb = _num(b);
  if (na != null && nb != null) return na < nb ? -1 : (na > nb ? 1 : 0);
  final da = _date(a), db = _date(b);
  if (da != null && db != null) return da.compareTo(db).sign;
  return _norm(a).compareTo(_norm(b)).sign;
}

/// One condition against one row.
bool condMatches(LayoutCond c, Map<String, Object?> row) {
  final op = c.op, v = row[c.field], want = c.value;
  if (op == 'empty') return _empty(v);
  if (op == 'not_empty') return !_empty(v);
  if (op == 'in') {
    final opts = want is List ? want : (_truthyStr(want) ? _pyStr(want) : '').split(',');
    return opts.any((o) => _compare(v, o) == 0);
  }
  if (op == 'contains' || op == 'not_contains' || op == 'starts_with' || op == 'ends_with') {
    final hay = _norm(v), needle = _norm(want);
    final hit = (op == 'contains' || op == 'not_contains')
        ? hay.contains(needle)
        : op == 'starts_with'
            ? hay.startsWith(needle)
            : hay.endsWith(needle);
    return op == 'not_contains' ? !hit : hit;
  }
  if (_empty(v) && op != '!=') return false;
  final r = _compare(v, want);
  return switch (op) {
    '=' => r == 0,
    '!=' => r != 0,
    '>' => r > 0,
    '>=' => r >= 0,
    '<' => r < 0,
    '<=' => r <= 0,
    _ => false,
  };
}

bool _truthyStr(Object? v) => !(v == null || v == false || v == 0 || (v is String && v.isEmpty) || (v is List && v.isEmpty));

/// A group: an empty one matches everything.
bool groupMatches(LayoutCondGroup g, Map<String, Object?> row) {
  if (g.items.isEmpty) return true;
  bool hit(Object x) => x is LayoutCondGroup ? groupMatches(x, row) : condMatches(x as LayoutCond, row);
  return g.match == 'any' ? g.items.any(hit) : g.items.every(hit);
}

Object _fmtNumber(double f) {
  if (f == f.truncateToDouble() && f.abs() < 1e15) return f.toInt();
  return double.parse(layoutFixed(f, 6));
}

/// An expression for one row: text, number, a row value, joined parts or math. Null = empty.
Object? evaluateExpr(LayoutExpr? e, Map<String, Object?> row) {
  if (e == null) return null;
  if (e.text != null) return e.text;
  if (e.number != null) return e.number;
  if (e.field != null) return row[e.field];
  if (e.concat != null) {
    final parts = [for (final x in e.concat!) evaluateExpr(x, row)];
    final s = parts.where((p) => !_empty(p)).map(_pyStr).join(e.sep);
    return s.length > kComputedMaxResult ? s.substring(0, kComputedMaxResult) : s;
  }
  final op = e.math ?? '+';
  final nums = [for (final x in e.args ?? const <LayoutExpr>[]) _num(evaluateExpr(x, row))];
  if (nums.isEmpty || nums.any((n) => n == null)) return null;
  final n = nums.cast<double>();
  double r;
  switch (op) {
    case '+':
      r = n.fold(0.0, (a, b) => a + b);
    case '-':
      r = n.first - n.skip(1).fold(0.0, (a, b) => a + b);
    case '*':
      r = n.fold(1.0, (a, b) => a * b);
    case '/':
      if (n.length < 2 || n.skip(1).any((x) => x == 0)) return null;
      r = n.first;
      for (final x in n.skip(1)) {
        r /= x;
      }
    case 'min':
      r = n.reduce((a, b) => b < a ? b : a);
    case 'max':
      r = n.reduce((a, b) => b > a ? b : a);
    case 'abs':
      r = n.first.abs();
    case 'round':
      final d = n.length > 1 ? n[1].clamp(0, 6).toInt() : 0;
      r = double.parse(layoutFixed(n.first, d));
    default: // percent
      if (n.length < 2 || n[1] == 0) return null;
      r = n[0] / n[1] * 100;
  }
  if (!r.isFinite) return null;
  return _fmtNumber(r);
}

/// A NEW row with the computed values added, in order: a spec reads the earlier ones. The first matching case wins,
/// else the `else` value.
Map<String, Object?> applyComputed(Map<String, Object?> row, List<LayoutComputedField> specs) {
  if (specs.isEmpty) return row;
  final out = Map<String, Object?>.of(row);
  for (final s in specs) {
    Object? value;
    var hit = false;
    for (final c in s.cases) {
      if (groupMatches(c.when, out)) {
        value = evaluateExpr(c.value, out);
        hit = true;
        break;
      }
    }
    if (!hit) value = evaluateExpr(s.otherwise, out);
    if (s.type == 'number' && value != null) {
      final n = _num(value);
      value = n == null ? null : _fmtNumber(n);
    } else if (s.type == 'text' && value != null && value is! String) {
      value = _pyStr(value);
    }
    out[s.key] = value;
  }
  return out;
}

/// The source columns the specs read (their own `calc.` keys excluded), first-seen order.
List<String> computedSourceFields(List<LayoutComputedField> specs) {
  final own = {for (final s in specs) s.key};
  final out = <String>[];
  void add(String? f) {
    if (f != null && f.isNotEmpty && !own.contains(f) && !out.contains(f)) out.add(f);
  }

  void group(LayoutCondGroup g) {
    for (final x in g.items) {
      x is LayoutCondGroup ? group(x) : add((x as LayoutCond).field);
    }
  }

  void expr(LayoutExpr? e) {
    if (e == null) return;
    add(e.field);
    for (final x in e.concat ?? e.args ?? const <LayoutExpr>[]) {
      expr(x);
    }
  }

  for (final s in specs) {
    for (final c in s.cases) {
      group(c.when);
      expr(c.value);
    }
    expr(s.otherwise);
  }
  return out;
}

/// Whether [specs] respect the caps (counts, depths); the builder keeps them valid, this is the guard for loaded data.
bool computedWithinCaps(List<LayoutComputedField> specs) {
  if (specs.length > kComputedMaxSpecs) return false;
  bool g(LayoutCondGroup x, int depth) =>
      depth <= kComputedMaxGroupDepth &&
      x.items.length <= kComputedMaxItems &&
      x.items.every((i) => i is! LayoutCondGroup || g(i, depth + 1));
  for (final s in specs) {
    if (s.cases.length > kComputedMaxCases || !s.cases.every((c) => g(c.when, 1))) return false;
  }
  return true;
}
