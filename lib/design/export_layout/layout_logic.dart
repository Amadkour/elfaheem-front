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

import '../export/table_export_model.dart' show AppExportColumn, AppColType;
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
        {double size = 10, int weight = 400, String color = _ink, String align = 'start', String? name}) =>
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
        {double size = 10, int weight = 400, String color = _ink, String align = 'start', String kind = 'field'}) =>
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
/// for Arabic, so the first field sits on the right of an Arabic page.
LayoutDesign layoutStarter({required String mode, required String lang, required List<LayoutField> fields, int perLine = 1}) {
  final ids = _Ids();
  final picked = layoutPreselected(fields);
  final d = LayoutDesign(mode: mode, page: LayoutPage(rtl: false, font: 'tajawal'));
  if (mode == 'table' && picked.length > 6) d.page.orientation = 'landscape';
  _bands(d, lang, ids);
  final w = d.page.contentWidth;
  switch (mode) {
    case 'list':
      d.list
        ..fields.addAll([for (final f in picked.take(4)) f.bind()])
        ..separator = ' · '
        ..numbered = true
        ..style = LayoutStyle(size: 10, color: _ink);
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
/// static labels that name a field and the list / table headings switched to [lang]'s names.
LayoutDesign layoutCopyForLang(LayoutDesign src, String lang, List<LayoutField> fields) {
  final d = src.copy();
  if (d.page.rtl != (lang == 'ar')) layoutMirror(d);
  final other = lang == 'ar' ? 'en' : 'ar';
  final byOtherLabel = {for (final f in fields) f.label(other): f};
  for (final e in d.allElements) {
    final f = e.kind == 'text' && e.bind == null ? byOtherLabel[e.value] : null;
    if (f != null) e.value = f.label(lang);
  }
  final byKey = {for (final f in fields) f.key: f};
  for (final b in [...d.list.fields, for (final c in d.table.columns) c.field]) {
    final f = byKey[b.field];
    if (f != null && b.label != null) b.label = f.label(lang);
  }
  return d;
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Values, rules, variables
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// `{{name}}` → [vars]`[name]` (unknown names stay as written).
String layoutFillVars(String s, Map<String, String> vars) =>
    s.replaceAllMapped(RegExp(r'\{\{\s*([a-z_]+)\s*\}\}'), (m) => vars[m.group(1)] ?? m.group(0)!);

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}'.replaceAll(',', '').trim());

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

/// [v] printed as [b] says (format, decimals, currency, prefix / suffix, the empty text). Dates as yyyy-MM-dd
/// (the server applies the pattern and the timezone in the file).
String layoutFormat(Object? v, LayoutBind b, {LayoutField? field, String lang = 'en'}) {
  final raw = v == null ? '' : '$v'.trim();
  if (raw.isEmpty) return b.empty;
  String out;
  switch (b.format) {
    case 'upper':
      out = raw.toUpperCase();
    case 'lower':
      out = raw.toLowerCase();
    case 'title':
      out = raw.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
    case 'number' || 'integer' || 'percent' || 'currency':
      final n = _num(v);
      if (n == null) {
        out = raw;
        break;
      }
      final dec = b.format == 'integer' ? 0 : (b.decimals ?? (b.format == 'currency' ? 2 : (b.format == 'percent' ? 1 : (n is int ? 0 : 2))));
      out = _grouped(n.toStringAsFixed(dec));
      if (b.format == 'percent') out = '$out%';
      if (b.format == 'currency' && (b.currency ?? field?.currency ?? '').isNotEmpty) out = '$out ${b.currency ?? field?.currency}';
    case 'date' || 'datetime':
      final d = v is DateTime ? v : DateTime.tryParse(raw);
      if (d == null) {
        out = raw;
        break;
      }
      out = '${d.year}-${_two(d.month)}-${_two(d.day)}';
      if (b.format == 'datetime') out = '$out ${_two(d.hour)}:${_two(d.minute)}';
    default:
      final labels = field?.statusLabels[lang] ?? field?.statusLabels['any'];
      out = labels?[raw] ?? raw;
  }
  return '${b.prefix}$out${b.suffix}';
}

bool _empty(Object? v) => v == null || '$v'.trim().isEmpty;

/// One condition against one item (the server's semantics: numbers compare as numbers when both sides are numbers,
/// text otherwise, case-insensitive for contains; `in` takes a comma-separated list or a JSON list).
bool layoutCondMatches(LayoutCond c, Map<String, Object?> item) {
  final v = item[c.field];
  switch (c.op) {
    case 'empty':
      return _empty(v);
    case 'not_empty':
      return !_empty(v);
    case 'contains':
      return '${v ?? ''}'.toLowerCase().contains('${c.value ?? ''}'.toLowerCase());
    case 'not_contains':
      return !'${v ?? ''}'.toLowerCase().contains('${c.value ?? ''}'.toLowerCase());
    case 'in':
      final list = c.value is List ? [for (final x in c.value as List) '$x'.trim()] : '${c.value ?? ''}'.split(',').map((s) => s.trim());
      return list.contains('${v ?? ''}'.trim());
  }
  final a = _num(v), b = _num(c.value);
  final int cmp;
  if (a != null && b != null) {
    cmp = a.compareTo(b);
  } else {
    cmp = '${v ?? ''}'.trim().compareTo('${c.value ?? ''}'.trim());
  }
  return switch (c.op) {
    '=' => cmp == 0,
    '!=' => cmp != 0,
    '>' => cmp > 0,
    '>=' => cmp >= 0,
    '<' => cmp < 0,
    '<=' => cmp <= 0,
    _ => false,
  };
}

bool layoutRuleMatches(LayoutRule r, Map<String, Object?> item) {
  if (r.when.isEmpty) return false;
  return r.match == 'any' ? r.when.any((c) => layoutCondMatches(c, item)) : r.when.every((c) => layoutCondMatches(c, item));
}

/// What one element shows for one item.
class LayoutResolved {
  const LayoutResolved({required this.show, required this.text, this.color, this.bg, this.icon, this.ruleIndex});
  final bool show;
  final String text;
  final String? color, bg, icon;

  /// The rule that matched (null = none; -1 = `else`).
  final int? ruleIndex;
}

/// [e] for [item] (number [index], 1-based): its text (static value with variables / the bound field formatted / the
/// computed value) and the first matching rule's changes, else `else`.
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
        : [for (final f in c.fields) '${item[f] ?? ''}'.trim()].where((s) => s.isNotEmpty).join(c.sep);
  } else if (e.bind != null) {
    text = layoutFormat(item[e.bind!.field], e.bind!, field: fieldOf?.call(e.bind!.field), lang: lang);
  } else {
    text = e.value ?? '';
  }
  text = layoutFillVars(text, {...vars, 'index': '$index'});
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
    text: t == null || t.isEmpty ? text : layoutFillVars(t, vars),
    color: hit.color,
    bg: hit.bg,
    icon: hit.icon,
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
