// lib/design/export_layout/layout_logic.dart
//
// The pure logic around the v3 document (no widgets, unit-tested in test/export/layout_model_test.dart):
//
//   layoutStarter(mode:, lang:, fields:, perLine:)   the starter designs — List, Table, Custom card 1 / 2 / 3 per
//                                                     line — built left-to-right, MIRRORED for Arabic
//   layoutMirror(design)                              flips every element across its band / card (x = W − x − w)
//   layoutCopyForLang(design, lang, fields)           the other language's design as a start for this one
//   layoutResolve(element, item, …)                   what the live row preview draws for one item: the server's
//                                                     rule order (first match wins, else), formats, variables
//   layoutLocalIssues(design, format)                 the "can't be shown in Excel / Word" notes the studio shows
//                                                     before the server's /validate answers
//   layoutFieldsOf(columns)                           AppExportColumns → LayoutFields
//
// The SERVER is the renderer: this file only has to agree with it closely enough for the canvas and the row preview.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../export/table_export_model.dart' show AppExportColumn, AppColType, dateValue;
import 'layout_model.dart';

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Fields
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

String _typeOf(AppColType t) => switch (t) {
      AppColType.text => 'text',
      AppColType.number => 'number',
      AppColType.integer => 'integer',
      AppColType.money => 'money',
      AppColType.percent => 'percent',
      AppColType.date => 'date',
      AppColType.dateTime => 'datetime',
      AppColType.status => 'status',
    };

/// The table's columns as designer fields (labels per language, type, preselection).
List<LayoutField> layoutFieldsOf(List<AppExportColumn> columns) => [
      for (final c in columns)
        LayoutField(
          key: c.id,
          labelAr: c.labelIn('ar'),
          labelEn: c.labelIn('en'),
          type: _typeOf(c.type),
          visible: c.visible || c.locked,
          currency: c.currency,
          statusLabels: {
            ...?c.statusLabelsByLang,
            if (c.statusLabelsByLang == null && c.statusLabels != null) 'any': c.statusLabels!,
          },
        ),
    ];

/// A server dataset's columns (`GET /exports/datasets/{key}/columns`: `{key, label_ar, label_en, type}`) as designer
/// fields — the keys the server renders. A key the app table also has keeps the app column's preselection, status
/// labels and currency; the others start unselected (all are, when none matches).
List<LayoutField> layoutFieldsOfDataset(List<Map<String, dynamic>> columns, List<LayoutField> app) {
  final byKey = {for (final f in app) f.key: f};
  return [
    for (final c in columns)
      if ('${c['key'] ?? ''}'.isNotEmpty)
        () {
          final key = '${c['key']}';
          final a = byKey[key];
          final type = switch ('${c['type'] ?? 'text'}') {
            'int' || 'integer' => 'integer',
            final x when const {'number', 'money', 'percent', 'date', 'datetime'}.contains(x) => x,
            _ => a?.type == 'status' ? 'status' : 'text',
          };
          return LayoutField(
            key: key,
            labelAr: '${c['label_ar'] ?? a?.labelAr ?? key}',
            labelEn: '${c['label_en'] ?? a?.labelEn ?? key}',
            type: type,
            visible: a?.visible ?? false,
            currency: a?.currency,
            statusLabels: a?.statusLabels ?? const {},
          );
        }(),
  ];
}

/// One value of an app table's row as it is uploaded (`POST /rows`) and as the row preview reads it, so both print
/// the same: a date / time becomes the wall clock of the platform / organization timezone as ISO text without an
/// offset (the server prints the clock it gets; a naive server timestamp is UTC), a date-only value stays its
/// calendar day, a status code becomes its label in [lang] (what the table shows). Other values are unchanged.
Object? layoutRowValue(LayoutField? f, Object? v, String lang) {
  if (f == null || v == null) return v;
  if (f.type == 'date' || f.type == 'datetime') {
    final dv = dateValue(v);
    if (dv == null) return v;
    final (d, timed) = dv;
    String two(int x) => x.toString().padLeft(2, '0');
    final day = '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
    return timed ? '${day}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}' : day;
  }
  if (f.type == 'status') {
    final labels = f.statusLabels[lang] ?? f.statusLabels['any'];
    return labels?['$v'] ?? v;
  }
  return v;
}

/// Every field [d] reads (printed, ruled on, joined, sorted, grouped or totalled) — the server's
/// `referenced_fields` for one design (the items part of its own mode only).
Set<String> layoutReferencedFields(LayoutDesign d) {
  final out = <String>{};
  void els(Iterable<LayoutElement> list) {
    for (final e in list) {
      if (e.bind != null) out.add(e.bind!.field);
      out.addAll(e.computed?.fields ?? const []);
      for (final r in e.rules) {
        out.addAll(r.when.map((c) => c.field));
      }
    }
  }

  els(d.bands.expand((b) => b.elements));
  switch (d.mode) {
    case 'list':
      out.addAll(d.list.fields.map((b) => b.field));
    case 'table':
      out.addAll(d.table.columns.map((c) => c.field.field));
    default:
      els(d.row.elements);
  }
  out.addAll(d.sort.map((s) => s.field));
  if (d.group != null) out.add(d.group!.field);
  out.addAll(d.totals.map((t) => t.field));
  out.remove('');
  return out;
}

/// [d] with every field reference renamed by [names] (binds, joined fields, rule conditions, list fields, table
/// columns, sort, group, totals) — in place; returns [d].
LayoutDesign layoutRenameFields(LayoutDesign d, Map<String, String> names) {
  if (names.isEmpty) return d;
  String n(String k) => names[k] ?? k;
  for (final e in d.allElements) {
    if (e.bind != null) e.bind!.field = n(e.bind!.field);
    final c = e.computed;
    if (c != null) {
      final f = [for (final x in c.fields) n(x)];
      c.fields
        ..clear()
        ..addAll(f);
    }
    for (final r in e.rules) {
      for (final w in r.when) {
        w.field = n(w.field);
      }
    }
  }
  for (final b in [...d.list.fields, for (final c in d.table.columns) c.field]) {
    b.field = n(b.field);
  }
  for (final s in d.sort) {
    s.field = n(s.field);
  }
  if (d.group != null) d.group!.field = n(d.group!.field);
  for (final t in d.totals) {
    t.field = n(t.field);
  }
  return d;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Starters
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

const _ink = '#101828', _muted = '#667085', _soft = '#475467', _hair = '#EAECF0', _headBg = '#F2F4F7';

String _t(String lang, String ar, String en) => lang == 'ar' ? ar : en;

class _Ids {
  int _n = 0;
  String next(String p) => '$p${++_n}';
}

LayoutElement _text(_Ids ids, String value, double x, double y, double w, double h,
        {double? size, int weight = 400, String color = _ink, String align = 'start', String? name}) =>
    LayoutElement(
      id: ids.next('e'),
      kind: 'text',
      x: x,
      y: y,
      w: w,
      h: h,
      value: value,
      name: name,
      style: LayoutStyle(size: size, weight: weight, color: color, align: align, maxLines: 1),
    );

LayoutElement _field(_Ids ids, LayoutField f, String lang, double x, double y, double w, double h,
        {double? size, int weight = 400, String color = _ink, String align = 'start', String kind = 'field'}) =>
    LayoutElement(
      id: ids.next('e'),
      kind: kind,
      x: x,
      y: y,
      w: w,
      h: h,
      name: f.label(lang),
      bind: f.bind(),
      style: LayoutStyle(size: size, weight: weight, color: color, align: align, maxLines: 1),
    );

/// The header / filters / footer every starter has (left-to-right; mirrored with the rest).
void _bands(LayoutDesign d, String lang, _Ids ids) {
  final w = d.page.contentWidth;
  d.header = LayoutBand(height: 24, placement: 'first_page', elements: [
    _text(ids, '{{title}}', 0, 2, w * .66, 9, size: 16, weight: 700, name: _t(lang, 'العنوان', 'Title')),
    _text(ids, '{{org_name}}', 0, 12, w * .66, 6, color: _soft, name: _t(lang, 'اسم المؤسسة', 'Organization')),
    _text(ids, '{{date}}', w - 60, 3, 60, 6, size: 9, color: _soft, align: 'end', name: _t(lang, 'التاريخ', 'Date')),
    _text(ids, _t(lang, 'العدد: {{total}}', 'Items: {{total}}'), w - 60, 10, 60, 6, size: 9, color: _soft, align: 'end',
        name: _t(lang, 'العدد', 'Total count')),
    LayoutElement(
      id: ids.next('e'),
      kind: 'line',
      x: 0,
      y: 21,
      w: w,
      h: 1,
      name: _t(lang, 'خط', 'Line'),
      style: LayoutStyle(border: LayoutBorder(width: 0.4, color: '#D0D5DD')),
    ),
  ]);
  d.beforeItems = LayoutBand(height: 8, placement: 'flow', elements: [
    _text(ids, '{{filters}}', 0, 1, w, 5, size: 8.5, color: _muted, name: _t(lang, 'عوامل التصفية', 'Filters')),
  ]);
  d.footer = LayoutBand(height: 9, placement: 'every_page', elements: [
    _text(ids, '{{exporter}}', 0, 2, w * .5, 5, size: 8, color: _muted, name: _t(lang, 'المُصدِّر', 'Exported by')),
    LayoutElement(
      id: ids.next('e'),
      kind: 'page_number',
      x: w - 40,
      y: 2,
      w: 40,
      h: 5,
      value: '{{page}} / {{pages}}',
      name: _t(lang, 'رقم الصفحة', 'Page number'),
      style: LayoutStyle(size: 8, color: _muted, align: 'end', maxLines: 1),
    ),
  ]);
}

/// The fields a starter shows: the preselected ones (all when none is), in the table's order.
List<LayoutField> layoutPreselected(List<LayoutField> fields) {
  final v = fields.where((f) => f.visible).toList();
  return v.isEmpty ? List.of(fields) : v;
}

String _alignOf(LayoutField f) =>
    f.numeric ? 'end' : (f.type == 'date' || f.type == 'datetime' || f.type == 'status' ? 'center' : 'start');

/// A starter design. [mode] list | table | custom ([perLine] 1 – 3 cards per line). Built left-to-right and mirrored
/// for Arabic, so the first field sits on the right of an Arabic page. [page] = the page to build on (a copy is
/// used: size, orientation, margins, font), so the starter fills the design's current content width.
LayoutDesign layoutStarter({required String mode, required String lang, required List<LayoutField> fields, int perLine = 1, LayoutPage? page}) {
  final ids = _Ids();
  final picked = layoutPreselected(fields);
  final d = LayoutDesign(mode: mode, page: page == null ? LayoutPage(rtl: false, font: 'tajawal') : (LayoutPage.fromJson(page.toJson())..rtl = false));
  if (mode == 'table' && picked.length > 6) d.page.orientation = 'landscape';
  _bands(d, lang, ids);
  final w = d.page.contentWidth;
  switch (mode) {
    case 'list':
      d.list
        ..fields.addAll([for (final f in picked.take(4)) f.bind()])
        ..separator = ' · '
        ..numbered = true
        ..style = LayoutStyle(color: _ink);
    case 'table':
      final weights = [for (final f in picked) f.type == 'text' ? 2.0 : (f.type == 'status' ? 1.2 : 1.0)];
      final sum = weights.fold<double>(0, (a, b) => a + b);
      d.table
        ..columns.addAll([
          for (var i = 0; i < picked.length; i++)
            LayoutColumn(field: picked[i].bind(lang: lang), width: mm(w * weights[i] / sum), align: _alignOf(picked[i]), style: LayoutStyle(size: 9)),
        ])
        ..headerStyle = LayoutStyle(size: 9, weight: 700, color: _ink, bg: _headBg)
        ..zebra = '#F7F9FB'
        ..borders = LayoutBorder(width: 0.3, color: _hair)
        ..repeatHeader = true;
    default:
      d.mode = 'custom';
      _card(d, lang, picked, perLine.clamp(1, 3), ids);
  }
  if (lang == 'ar') layoutMirror(d);
  return d;
}

void _card(LayoutDesign d, String lang, List<LayoutField> picked, int perLine, _Ids ids) {
  final row = d.row
    ..perLine = perLine
    ..gap = 3
    ..radius = 2
    ..keepTogether = true
    ..border = LayoutBorder(width: 0.3, color: _hair);
  final cw = row.cardWidth(d.page.contentWidth);
  const pad = 2.5;
  if (picked.isEmpty) {
    row.height = 12;
    return;
  }
  final status = picked.where((f) => f.type == 'status').firstOrNull;
  final main = picked.firstWhere((f) => f.type == 'text', orElse: () => picked.first);
  final badgeW = status == null || status == main ? 0.0 : math.min(24.0, cw * .35);
  row.elements.add(_field(ids, main, lang, pad, 2, cw - 2 * pad - (badgeW > 0 ? badgeW + 2 : 0), 7, size: 11, weight: 700));
  if (badgeW > 0) {
    row.elements.add(_field(ids, status!, lang, cw - pad - badgeW, 2.5, badgeW, 6, size: 8, align: 'center', kind: 'badge')
      ..style.bg = _headBg
      ..style.radius = 3);
  }
  final rest = [for (final f in picked) if (f != main && f != status) f].take(perLine == 1 ? 4 : (perLine == 2 ? 3 : 2)).toList();
  if (rest.isEmpty) {
    row.height = 12;
    return;
  }
  final colW = (cw - 2 * pad) / rest.length;
  for (var i = 0; i < rest.length; i++) {
    final x = pad + i * colW;
    row.elements
      ..add(_text(ids, rest[i].label(lang), x, 10.5, colW - 1.5, 4, size: 7.5, color: _muted, name: '${rest[i].label(lang)} · ${_t(lang, 'عنوان', 'label')}'))
      ..add(_field(ids, rest[i], lang, x, 14.5, colW - 1.5, 5.5, size: 9));
  }
  row.height = 22;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The page's width: elements follow it
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// Stretches / shrinks [d]'s horizontal geometry after its content width changed from [oldWidth]: every band
/// element and the table's column widths by the band's ratio, the card's elements by the card's ratio (as a change
/// of cards per line does), so a design keeps reaching both edges (an Arabic design its right edge).
void layoutRescaleWidth(LayoutDesign d, double oldWidth, {double? oldCardWidth}) {
  final w = d.page.contentWidth;
  if (oldWidth <= 0 || (w - oldWidth).abs() < 0.001) return;
  final k = w / oldWidth;
  for (final b in d.bands) {
    for (final e in b.elements) {
      e.x = mm(e.x * k);
      e.w = mm(e.w * k);
    }
  }
  for (final c in d.table.columns) {
    c.width = mm(c.width * k);
  }
  final before = oldCardWidth ?? d.row.cardWidth(oldWidth);
  final kc = before <= 0 ? 1.0 : d.row.cardWidth(w) / before;
  for (final e in d.row.elements) {
    e.x = mm(e.x * kc);
    e.w = mm(e.w * kc);
  }
}

/// A copy of [doc] for a run: `{{title}}` in every text of each language's design replaced by [titleOf] that
/// language (the server has ONE title per run: the second language of a two-language export gets its own here).
LayoutDocument layoutWithTitles(LayoutDocument doc, String Function(String lang) titleOf) {
  final out = LayoutDocument.fromJson(doc.toJson());
  final re = RegExp(r'\{\{\s*title\s*\}\}');
  for (final e in out.designs.entries) {
    final t = titleOf(e.key);
    String? sub(String? s) => s == null || !s.contains('{{') ? s : s.replaceAll(re, t);
    for (final el in e.value.allElements) {
      el.value = sub(el.value);
      el.sigName = sub(el.sigName);
      el.sigTitle = sub(el.sigTitle);
      for (final r in el.rules) {
        r.then.text = sub(r.then.text);
      }
      final o = el.otherwise;
      if (o != null) o.text = sub(o.text);
    }
  }
  return out;
}

/// Changes [d]'s page with [mutate] (size, orientation, margins) and re-lays the elements to the new width.
void layoutSetPage(LayoutDesign d, void Function(LayoutPage p) mutate) {
  final before = d.page.contentWidth;
  mutate(d.page);
  layoutRescaleWidth(d, before);
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Mirroring
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

void _mirrorAll(List<LayoutElement> els, double width) {
  for (final e in els) {
    e.x = mm(width - e.x - e.w);
    if (e.rotation != 0) e.rotation = -e.rotation;
  }
}

/// Flips [d] across the page: every band element and every element of the card moves to the other side
/// (x = W − x − w), turned elements turn the other way, and the page direction flips. Twice = the original.
LayoutDesign layoutMirror(LayoutDesign d) {
  final w = d.page.contentWidth;
  for (final b in d.bands) {
    _mirrorAll(b.elements, w);
  }
  _mirrorAll(d.row.elements, d.row.cardWidth(w));
  d.page.rtl = !d.page.rtl;
  return d;
}

/// [src] (the other language's design) as a start for [lang]: a copy, mirrored when the direction differs, with the
/// static labels that name a field, the starters' own texts ("العدد: {{total}}" → "Items: {{total}}") and element
/// names, and the list / table headings switched to [lang]'s names.
LayoutDesign layoutCopyForLang(LayoutDesign src, String lang, List<LayoutField> fields) {
  final d = src.copy();
  if (d.page.rtl != (lang == 'ar')) layoutMirror(d);
  final other = lang == 'ar' ? 'en' : 'ar';
  final byOtherLabel = {for (final f in fields) f.label(other): f};
  // the starters are built with the same ids in both languages: element by element, their texts translate
  final texts = <String, String>{}, names = <String, String>{};
  for (final mode in const ['list', 'table', 'custom']) {
    final a = layoutStarter(mode: mode, lang: other, fields: fields), b = layoutStarter(mode: mode, lang: lang, fields: fields);
    final byId = {for (final e in b.allElements) e.id: e};
    for (final e in a.allElements) {
      final t = byId[e.id];
      if (t == null) continue;
      if (e.value != null && t.value != null && e.value != t.value) texts[e.value!] = t.value!;
      if (e.name != null && t.name != null && e.name != t.name) names[e.name!] = t.name!;
    }
  }
  for (final e in d.allElements) {
    final f = e.kind == 'text' && e.bind == null ? byOtherLabel[e.value] : null;
    if (f != null) {
      e.value = f.label(lang);
    } else if (e.bind == null && texts[e.value] != null) {
      e.value = texts[e.value];
    }
    if (names[e.name] != null) e.name = names[e.name];
  }
  final byKey = {for (final f in fields) f.key: f};
  for (final b in [...d.list.fields, for (final c in d.table.columns) c.field]) {
    final f = byKey[b.field];
    if (f != null && b.label != null) b.label = f.label(lang);
  }
  return d;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Values, rules, variables — a port of the server's services/export_layout/values.py (format_value, cond_matches,
//  item_text, expand), so the row preview prints and rules exactly as the file does
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

const _pageVars = {'page', 'pages'};

/// `{{name}}` → [vars]`[name]`, as the server's `expand`: an unknown name becomes empty text, except `{{page}}` /
/// `{{pages}}`, which stay as written until the page is known.
String layoutFillVars(String s, Map<String, String> vars) {
  if (!s.contains('{{')) return s;
  return s.replaceAllMapped(RegExp(r'\{\{\s*([a-z_]+)\s*\}\}'), (m) {
    final k = m.group(1)!;
    final v = vars[k];
    return v ?? (_pageVars.contains(k) ? '{{$k}}' : '');
  });
}

/// Python's truthiness (`x or ""`).
bool _truthy(Object? v) => !(v == null || v == false || v == 0 || (v is String && v.isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty));

/// Python's `str(v)` for the values a row holds (bool → True / False).
String _str(Object? v) => v == null ? 'None' : (v is bool ? (v ? 'True' : 'False') : '$v');

/// Python's `float(text)`: surrounding blanks, a sign, inf / nan in any case, `_` between digits.
double? _pyFloat(String s) {
  var t = s.trim();
  if (t.isEmpty) return null;
  final l = t.toLowerCase();
  final sign = l.startsWith('-') ? -1.0 : 1.0;
  final body = l.startsWith('-') || l.startsWith('+') ? l.substring(1) : l;
  if (body == 'inf' || body == 'infinity') return sign * double.infinity;
  if (body == 'nan') return double.nan;
  if (t.contains('_')) {
    if (!RegExp(r'^[+-]?(\d+(_\d+)*)?(\.(\d+(_\d+)*)?)?([eE][+-]?\d+(_\d+)*)?$').hasMatch(t)) return null;
    t = t.replaceAll('_', '');
  }
  if (!RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$').hasMatch(t)) return null;
  return double.tryParse(t);
}

/// The server's `as_number`: a number, or text that reads as one once `,` and `%` are removed (bool → none).
double? layoutAsNumber(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isNaN ? null : v.toDouble();
  return _pyFloat('$v'.trim().replaceAll(',', '').replaceAll('%', ''));
}

final _iso = RegExp(r'^(\d{4})-?(\d{2})-?(\d{2})(?:[T ](\d{2})(?::?(\d{2})(?::?(\d{2})(?:[.,](\d+))?)?)?)?'
    r'(Z|[+-]\d{2}(?::?\d{2}(?::?\d{2}(?:\.\d+)?)?)?)?$');

/// The server's `as_datetime`: a DateTime (its clock as written), or ISO text of 10+ characters (its offset dropped,
/// the clock kept: the rows carry wall-clock times).
DateTime? layoutAsDateTime(Object? v) {
  if (v is DateTime) return DateTime.utc(v.year, v.month, v.day, v.hour, v.minute, v.second, v.millisecond, v.microsecond);
  if (v is! String || v.length < 10) return null;
  final m = _iso.firstMatch(v.trim());
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i) ?? '0');
  final y = g(1), mo = g(2), d = g(3), h = g(4), mi = g(5), s = g(6);
  final frac = (m.group(7) ?? '').padRight(6, '0').substring(0, 6);
  if (mo < 1 || mo > 12 || d < 1 || h > 23 || mi > 59 || s > 59) return null;
  final out = DateTime.utc(y, mo, d, h, mi, s, 0, int.parse(frac));
  return out.month == mo && out.day == d ? out : null;
}

/// The server's `is_empty`.
bool layoutIsEmpty(Object? v) => v == null || (v is String && v.trim().isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

/// [x] with [dec] decimals as Python's `f"{x:.{dec}f}"` prints it: the double's exact value, ties to even.
String layoutFixed(double x, int dec) {
  if (x.isNaN) return 'nan';
  if (x.isInfinite) return x > 0 ? 'inf' : '-inf';
  final b = ByteData(8)..setFloat64(0, x.abs());
  final hi = b.getUint32(0), lo = b.getUint32(4);
  final expBits = (hi >> 20) & 0x7FF;
  var mant = (BigInt.from(hi & 0xFFFFF) << 32) | BigInt.from(lo);
  final int e;
  if (expBits == 0) {
    e = -1074;
  } else {
    mant |= BigInt.one << 52;
    e = expBits - 1075;
  }
  final p = BigInt.from(10).pow(dec);
  BigInt q;
  if (e >= 0) {
    q = (mant << e) * p;
  } else {
    final n = mant * p, d = BigInt.one << -e;
    q = n ~/ d;
    final twice = (n - q * d) * BigInt.two;
    if (twice > d || (twice == d && q.isOdd)) q += BigInt.one;
  }
  var s = q.toString();
  if (dec > 0) {
    s = s.padLeft(dec + 1, '0');
    s = '${s.substring(0, s.length - dec)}.${s.substring(s.length - dec)}';
  }
  return '${x.isNegative ? '-' : ''}$s';
}

String _grouped(String digits) {
  final neg = digits.startsWith('-');
  final s = neg ? digits.substring(1) : digits;
  final parts = s.split('.');
  final b = StringBuffer();
  for (var i = 0; i < parts[0].length; i++) {
    if (i > 0 && (parts[0].length - i) % 3 == 0) b.write(',');
    b.write(parts[0][i]);
  }
  return '${neg ? '-' : ''}$b${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String _two(int v) => v.toString().padLeft(2, '0');

const _arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The server's `format_date`: yyyy yy MMMM MMM MM M dd d HH H hh h mm ss a.
String layoutFormatDate(DateTime d, String pattern, String lang) {
  final months = lang == 'ar' ? _arMonths : _enMonths;
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return pattern.replaceAllMapped(RegExp(r'yyyy|yy|MMMM|MMM|MM|M|dd|d|HH|H|hh|h|mm|ss|a'), (m) => switch (m.group(0)!) {
        'yyyy' => d.year.toString().padLeft(4, '0'),
        'yy' => _two(d.year % 100),
        'MMMM' => months[d.month - 1],
        'MMM' => lang == 'ar' ? months[d.month - 1] : months[d.month - 1].substring(0, 3),
        'MM' => _two(d.month),
        'M' => '${d.month}',
        'dd' => _two(d.day),
        'd' => '${d.day}',
        'HH' => _two(d.hour),
        'H' => '${d.hour}',
        'hh' => _two(h12),
        'h' => '$h12',
        'mm' => _two(d.minute),
        'ss' => _two(d.second),
        _ => lang == 'ar' ? (d.hour >= 12 ? 'م' : 'ص') : (d.hour >= 12 ? 'PM' : 'AM'),
      });
}

/// Python's `str.title()`: a cased letter after a cased letter is lower case, after anything else upper case.
String _pyTitle(String s) {
  final b = StringBuffer();
  var prevCased = false;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final up = ch.toUpperCase(), low = ch.toLowerCase();
    if (up == low) {
      b.write(ch);
      prevCased = false;
    } else {
      b.write(prevCased ? low : up);
      prevCased = true;
    }
  }
  return b.toString();
}

/// [v] printed as [b] says — the server's `format_value`: the empty text for an empty value, Yes / No for a bool,
/// numbers with [LayoutBind.decimals] (2 when unset, ties to even) and `,` grouping, dates with the pattern
/// (yyyy-MM-dd / yyyy-MM-dd HH:mm), prefix / suffix around a non-empty value. A status field's code shows its label
/// in [lang] ([field]'s labels).
String layoutFormat(Object? v, LayoutBind b, {LayoutField? field, String lang = 'en'}) {
  if (layoutIsEmpty(v)) return b.empty;
  String? out;
  final fmt = b.format;
  if (v is bool) {
    out = lang == 'ar' ? (v ? 'نعم' : 'لا') : (v ? 'Yes' : 'No');
  } else if (fmt == 'number' || fmt == 'integer' || fmt == 'percent' || fmt == 'currency') {
    final n = layoutAsNumber(v);
    if (n != null) {
      out = _grouped(layoutFixed(n, fmt == 'integer' ? 0 : (b.decimals ?? 2)));
      if (fmt == 'percent') {
        out = '$out%';
      } else if (fmt == 'currency' && (b.currency ?? '').isNotEmpty) {
        out = '$out ${b.currency}';
      }
    }
  } else if (fmt == 'date' || fmt == 'datetime') {
    final d = layoutAsDateTime(v);
    if (d != null) out = layoutFormatDate(d, b.datePattern ?? (fmt == 'date' ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm'), lang);
  }
  if (out == null) {
    out = '$v';
    if (field?.type == 'status') {
      final labels = field!.statusLabels[lang] ?? field.statusLabels['any'];
      out = labels?[out] ?? out;
    }
    if (fmt == 'upper') {
      out = out.toUpperCase();
    } else if (fmt == 'lower') {
      out = out.toLowerCase();
    } else if (fmt == 'title') {
      out = _pyTitle(out);
    }
  }
  return '${b.prefix}$out${b.suffix}';
}

bool _cmp(String op, int c) => switch (op) {
      '=' => c == 0,
      '!=' => c != 0,
      '>' => c > 0,
      '>=' => c >= 0,
      '<' => c < 0,
      '<=' => c <= 0,
      _ => false,
    };

/// One condition against one item — the server's `cond_matches`, case for case:
///   empty / not_empty    the server's emptiness (null, blank text, an empty list)
///   in                   a list, or comma-separated text; an item matches as text (trimmed, any case) or as a number
///   contains             the target (trimmed, any case) inside the value (any case); no target never matches
///   an empty value       matches only `!=` a non-empty target
///   = != > >= < <=       as numbers when both read as numbers, else as dates when both are ISO dates, else as text
///                        (trimmed, any case)
bool layoutCondMatches(LayoutCond c, Map<String, Object?> item) {
  final v = item[c.field], op = c.op, target = c.value;
  switch (op) {
    case 'empty':
      return layoutIsEmpty(v);
    case 'not_empty':
      return !layoutIsEmpty(v);
    case 'in':
      final items = target is List ? target : _str(_truthy(target) ? target : '').split(',').map((x) => x.trim()).toList();
      final sv = v == null ? '' : _str(v).trim().toLowerCase();
      final nv = layoutAsNumber(v);
      return items.any((it) => _str(it).trim().toLowerCase() == sv || (nv != null && layoutAsNumber(it) == nv));
    case 'contains' || 'not_contains':
      final hit = target != null && (v == null ? '' : _str(v)).toLowerCase().contains(_str(target).trim().toLowerCase());
      return op == 'contains' ? hit : !hit;
  }
  if (layoutIsEmpty(v)) return op == '!=' && !layoutIsEmpty(target);
  final n = layoutAsNumber(v), t = layoutAsNumber(target);
  if (n != null && t != null) {
    return switch (op) {
      '=' => n == t,
      '!=' => n != t,
      '>' => n > t,
      '>=' => n >= t,
      '<' => n < t,
      '<=' => n <= t,
      _ => false,
    };
  }
  final dv = layoutAsDateTime(v), dt = layoutAsDateTime(target);
  if (dv != null && dt != null) return _cmp(op, dv.compareTo(dt));
  return _cmp(op, _str(v).trim().toLowerCase().compareTo((target == null ? '' : _str(target)).trim().toLowerCase()));
}

bool layoutRuleMatches(LayoutRule r, Map<String, Object?> item) {
  if (r.when.isEmpty) return false;
  return r.match == 'any' ? r.when.any((c) => layoutCondMatches(c, item)) : r.when.every((c) => layoutCondMatches(c, item));
}

/// What one element shows for one item.
class LayoutResolved {
  const LayoutResolved({required this.show, required this.text, this.color, this.bg, this.icon, this.bold, this.ruleIndex});
  final bool show;
  final String text;
  final String? color, bg, icon;

  /// A rule's bold override (null = the style's weight).
  final bool? bold;

  /// The rule that matched (null = none; -1 = `else`).
  final int? ruleIndex;
}

/// [e] for [item] (number [index], 1-based) — the server's `item_text`: the computed value (index / joined fields),
/// a bound field's formatted value (field, badge and QR elements), page numbers, the static text with variables; then
/// the first matching rule's changes, else `else`.
LayoutResolved layoutResolve(
  LayoutElement e,
  Map<String, Object?> item, {
  int index = 1,
  String lang = 'en',
  Map<String, String> vars = const {},
  LayoutField? Function(String key)? fieldOf,
}) {
  String text;
  final c = e.computed;
  if (c != null) {
    text = c.op == 'index'
        ? '$index'
        : [for (final f in c.fields) layoutFormat(item[f], LayoutBind(field: f, empty: ''), lang: lang)].where((s) => s.isNotEmpty).join(c.sep);
  } else if ((e.kind == 'field' || e.kind == 'badge' || e.kind == 'qr') && e.bind != null) {
    text = layoutFormat(item[e.bind!.field], e.bind!, field: fieldOf?.call(e.bind!.field), lang: lang);
  } else if (e.kind == 'page_number') {
    text = layoutFillVars((e.value ?? '').isEmpty ? '{{page}} / {{pages}}' : e.value!, vars);
  } else if (e.kind == 'image' || e.kind == 'signature' || e.kind == 'line' || e.kind == 'rect') {
    text = '';
  } else {
    text = layoutFillVars(e.value ?? '', vars);
  }
  LayoutThen? hit;
  int? at;
  for (var i = 0; i < e.rules.length; i++) {
    if (layoutRuleMatches(e.rules[i], item)) {
      hit = e.rules[i].then;
      at = i;
      break;
    }
  }
  if (hit == null && e.rules.isNotEmpty && e.otherwise != null) {
    hit = e.otherwise;
    at = -1;
  }
  if (hit == null) return LayoutResolved(show: true, text: text, ruleIndex: at);
  final t = hit.text;
  return LayoutResolved(
    show: hit.show,
    text: t == null ? text : layoutFillVars(t, vars),
    color: hit.color,
    bg: hit.bg,
    icon: hit.icon,
    bold: hit.bold,
    ruleIndex: at,
  );
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Issues ("can't be shown in Excel / Word")
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// One note of /validate or /preview (or of [layoutLocalIssues]).
class LayoutIssue {
  const LayoutIssue({required this.code, this.element, this.format, required this.messageAr, required this.messageEn, this.severity = 'note'});
  final String code;
  final String? element, format;
  final String messageAr, messageEn;

  /// note | warning | error
  final String severity;

  String message(String lang) => lang == 'ar' ? (messageAr.isEmpty ? messageEn : messageAr) : (messageEn.isEmpty ? messageAr : messageEn);

  factory LayoutIssue.fromJson(Map<String, dynamic> j) => LayoutIssue(
        code: '${j['code'] ?? ''}',
        element: j['element']?.toString(),
        format: j['format']?.toString(),
        messageAr: '${j['message_ar'] ?? j['message'] ?? ''}',
        messageEn: '${j['message_en'] ?? j['message'] ?? ''}',
        severity: switch ('${j['level'] ?? j['severity'] ?? ''}') {
          'error' => 'error',
          'warning' => 'warning',
          _ => 'note',
        },
      );

  /// The same note from the server and from the app counts once.
  String get key => '$code|${element ?? ''}|${format ?? ''}';
}

/// Pairs of elements whose boxes overlap (more than a hair) — Word and Excel cannot keep them.
List<(LayoutElement, LayoutElement)> layoutOverlaps(List<LayoutElement> els) {
  const tol = 0.3;
  final out = <(LayoutElement, LayoutElement)>[];
  for (var i = 0; i < els.length; i++) {
    for (var j = i + 1; j < els.length; j++) {
      final a = els[i], b = els[j];
      final ox = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x);
      final oy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y);
      if (ox > tol && oy > tol) out.add((a, b));
    }
  }
  return out;
}

/// The server draws at most this many distinct images per document (`assets_capped`).
const kLayoutMaxImages = 10;

/// The notes the studio can tell before the server does: what Excel / Word will change, with the closest alternative.
List<LayoutIssue> layoutLocalIssues(LayoutDesign d, String format) {
  final out = <LayoutIssue>[];
  final images = {for (final e in d.allElements) if (e.isImage && (e.value ?? '').isNotEmpty) e.value};
  if (images.length > kLayoutMaxImages) {
    out.add(LayoutIssue(
      code: 'assets_capped',
      severity: 'warning',
      messageAr: 'التصميم يستعمل ${images.length} صور مختلفة: يُرسم أول $kLayoutMaxImages فقط.',
      messageEn: 'The design uses ${images.length} different images: only the first $kLayoutMaxImages are drawn.',
    ));
  }
  if (format == 'pdf') return out;
  final parts = <List<LayoutElement>>[for (final b in d.bands) b.elements, if (d.mode == 'custom') d.row.elements];
  for (final els in parts) {
    for (final (a, b) in layoutOverlaps(els)) {
      out.add(LayoutIssue(
        code: 'overlap',
        element: b.id,
        format: format,
        messageAr: '«${b.name ?? b.id}» يتداخل مع «${a.name ?? a.id}»: التداخل يُحفظ في PDF فقط، وسيُنقل تحته في ${format == 'xlsx' ? 'Excel' : 'Word'}.',
        messageEn: '"${b.name ?? b.id}" overlaps "${a.name ?? a.id}": overlaps are kept in PDF only; ${format == 'xlsx' ? 'Excel' : 'Word'} moves it under it.',
      ));
    }
  }
  if (format != 'xlsx') return out;
  for (final e in d.allElements) {
    if (e.rotation != 0) {
      out.add(LayoutIssue(
        code: 'xlsx_rotation',
        element: e.id,
        format: format,
        messageAr: 'لا يدعم Excel تدوير «${e.name ?? e.id}»: سيظهر مستقيمًا.',
        messageEn: 'Excel cannot turn "${e.name ?? e.id}": it is shown straight.',
      ));
    }
    if (e.kind == 'qr') {
      out.add(LayoutIssue(
        code: 'xlsx_qr',
        element: e.id,
        format: format,
        messageAr: 'رمز QR لا يُرسم في Excel: يُكتب نصه بدلًا منه.',
        messageEn: 'Excel cannot draw a QR code: its text is written instead.',
      ));
    }
  }
  if (d.mode == 'custom' && d.row.perLine > 1) {
    out.add(const LayoutIssue(
      code: 'xlsx_per_line',
      format: 'xlsx',
      messageAr: 'في Excel تظهر بطاقة واحدة في كل سطر بدلًا من عدة بطاقات.',
      messageEn: 'Excel shows one card per line instead of several.',
    ));
  }
  if (d.watermark != null && d.watermark!.text.trim().isNotEmpty) {
    out.add(const LayoutIssue(
      code: 'xlsx_watermark',
      format: 'xlsx',
      messageAr: 'العلامة المائية تصبح نصًا في رأس الورقة في Excel.',
      messageEn: 'In Excel the watermark becomes text in the sheet header.',
    ));
  }
  if (d.footer.placement == 'every_page' && d.footer.elements.any((e) => !e.isText)) {
    out.add(const LayoutIssue(
      code: 'xlsx_footer',
      format: 'xlsx',
      messageAr: 'في Excel يحتفظ تذييل كل صفحة بالنصوص فقط (الصور والخطوط لا تظهر).',
      messageEn: 'In Excel an every-page footer keeps its text only (images and lines are left out).',
    ));
  }
  return out;
}
