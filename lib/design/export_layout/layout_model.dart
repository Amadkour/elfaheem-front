// lib/design/export_layout/layout_model.dart
//
// The design engine document: export layout v3 (D-142, docs/export_studio/LAYOUT_V3.md) + the v4 additions (D-164,
// docs/design_engine/ENGINE.md) — the contract with the server, which renders every file AND the preview pages.
// Plain mutable Dart classes with a toJson / fromJson round trip:
//
//   LayoutDocument   schema_version 4 · purpose · format · languages · designs {ar, en} · computed · source
//   LayoutDesign     page · mode list | table | custom | page · header / before_items / after_items / footer bands ·
//                    list · table · row · sort · group · totals · watermark · frame
//   LayoutBand       height · placement · elements                 LayoutRow   ONE card of the custom mode
//   LayoutElement    kind · x y w h (mm, from the band's / card's top-LEFT, physical in Arabic too) · value · bind ·
//                    computed · rules + else · style
//
// Every class keeps the keys it does not know in [extra] and writes them back, so a newer server's additions survive
// an edit in an older app. All lengths are millimetres, font sizes pt, colours `#RRGGBB` / `#AARRGGBB`.
library;

/// The layout schema this app writes.
const kLayoutSchemaVersion = 4;

/// The schemas this app reads (a v3 template is a v4 one that uses none of the new keys).
const kLayoutSchemaVersions = {3, 4};

/// The variables any text may hold (the server fills them in).
const kLayoutVariables = ['date', 'exporter', 'org_name', 'total', 'page', 'pages', 'title', 'filters', 'group'];

// ── json helpers ─────────────────────────────────────────────────────────────────────────────────────────────────
Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) _map(x)] : const [];
double _d(Object? v, double fallback) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? fallback);
int _i(Object? v, int fallback) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);
String? _s(Object? v) => v == null ? null : '$v';
bool _b(Object? v, bool fallback) => v is bool ? v : fallback;

Map<String, dynamic> _extra(Map<String, dynamic> j, Set<String> known) =>
    {for (final e in j.entries) if (!known.contains(e.key)) e.key: e.value};

/// Rounds a length to 0.01 mm, so a drag does not store 17 decimals.
double mm(double v) => (v * 100).roundToDouble() / 100;

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Small values
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class LayoutBorder {
  LayoutBorder({this.width = 0.3, this.color = '#D0D5DD', this.style = 'solid', Map<String, dynamic>? extra}) : extra = extra ?? {};

  double width;
  String color;

  /// solid | dashed
  String style;
  final Map<String, dynamic> extra;

  static const _known = {'width', 'color', 'style'};

  static LayoutBorder? maybe(Object? v) => v is Map ? LayoutBorder.fromJson(_map(v)) : null;

  factory LayoutBorder.fromJson(Map<String, dynamic> j) => LayoutBorder(
        width: _d(j['width'], 0.3),
        color: _s(j['color']) ?? '#D0D5DD',
        style: _s(j['style']) ?? 'solid',
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {...extra, 'width': width, 'color': color, 'style': style};

  LayoutBorder copy() => LayoutBorder.fromJson(toJson());
}

class LayoutStyle {
  LayoutStyle({
    this.font,
    this.size,
    this.weight = 400,
    this.italic = false,
    this.color = '#1A1A1A',
    this.bg,
    this.align = 'start',
    this.valign = 'middle',
    this.padding = 1,
    this.border,
    this.radius = 0,
    this.wrap = true,
    this.maxLines = 0,
    this.dir = 'auto',
    this.letterSpacing = 0,
    this.lineHeight = 1.3,
    this.shrink = false,
    this.shadow,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  /// null = the page font.
  String? font;

  /// pt; null = the page's font size (left out of the JSON: the server then uses `page.font_size`).
  double? size;

  /// 400 | 700
  int weight;
  bool italic;
  String color;
  String? bg;

  /// start | center | end (logical: start is the right edge in an Arabic design)
  String align;

  /// top | middle | bottom
  String valign;
  double padding;
  LayoutBorder? border;
  double radius;
  bool wrap;

  /// 0 = as many as fit (the rest is clipped); n = n lines then an ellipsis.
  int maxLines;

  /// auto | rtl | ltr (only the bidi base: start / end follow the page direction)
  String dir;

  /// v4: pt between letters; line height × the font size; shrink a text that does not fit (down to 50 %) instead of
  /// clipping it; a drop shadow (text and shapes).
  double letterSpacing, lineHeight;
  bool shrink;
  LayoutShadow? shadow;
  final Map<String, dynamic> extra;

  bool get bold => weight >= 600;

  static const _known = {
    'font', 'size', 'weight', 'italic', 'color', 'bg', 'align', 'valign', 'padding', 'border', 'radius', 'wrap', //
    'max_lines', 'dir', 'letter_spacing', 'line_height', 'shrink', 'shadow',
  };

  factory LayoutStyle.fromJson(Map<String, dynamic> j) => LayoutStyle(
        font: _s(j['font']),
        // the server reads 0 / a missing size as "the page's"
        size: j['size'] is num && (j['size'] as num) > 0 ? (j['size'] as num).toDouble() : null,
        weight: _i(j['weight'], 400),
        italic: _b(j['italic'], false),
        color: _s(j['color']) ?? '#1A1A1A',
        bg: _s(j['bg']),
        align: _s(j['align']) ?? 'start',
        valign: _s(j['valign']) ?? 'middle',
        padding: _d(j['padding'], 1),
        border: LayoutBorder.maybe(j['border']),
        radius: _d(j['radius'], 0),
        wrap: _b(j['wrap'], true),
        maxLines: _i(j['max_lines'], 0),
        dir: _s(j['dir']) ?? 'auto',
        letterSpacing: _d(j['letter_spacing'], 0),
        lineHeight: _d(j['line_height'], 1.3),
        shrink: _b(j['shrink'], false),
        shadow: LayoutShadow.maybe(j['shadow']),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'font': font,
        if (size != null) 'size': size,
        'weight': weight,
        'italic': italic,
        'color': color,
        'bg': bg,
        'align': align,
        'valign': valign,
        'padding': padding,
        if (border != null) 'border': border!.toJson(),
        'radius': radius,
        'wrap': wrap,
        'max_lines': maxLines,
        'dir': dir,
        if (letterSpacing != 0) 'letter_spacing': letterSpacing,
        if (lineHeight != 1.3) 'line_height': lineHeight,
        if (shrink) 'shrink': true,
        if (shadow != null) 'shadow': shadow!.toJson(),
      };

  LayoutStyle copy() => LayoutStyle.fromJson(toJson());
}

/// v4: a drop shadow, offsets in mm.
class LayoutShadow {
  LayoutShadow({this.color = '#00000055', this.dx = 0.4, this.dy = 0.4});
  String color;
  double dx, dy;

  static LayoutShadow? maybe(Object? v) => v is Map ? LayoutShadow.fromJson(_map(v)) : null;

  factory LayoutShadow.fromJson(Map<String, dynamic> j) =>
      LayoutShadow(color: _s(j['color']) ?? '#00000055', dx: _d(j['dx'], 0.4), dy: _d(j['dy'], 0.4));

  Map<String, dynamic> toJson() => {'color': color, 'dx': dx, 'dy': dy};
}

/// How a field's value is printed (`bind`, also the FieldRef of list fields and table columns).
class LayoutBind {
  LayoutBind({
    required this.field,
    this.format = 'text',
    this.decimals,
    this.currency,
    this.datePattern,
    this.prefix = '',
    this.suffix = '',
    this.empty = '—',
    this.label,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  String field;

  /// text | upper | lower | title | number | integer | percent | currency | date | datetime
  String format;
  int? decimals;
  String? currency, datePattern;
  String prefix, suffix, empty;

  /// The heading of a table column / list field in this design's language (the dataset's label when null).
  String? label;
  final Map<String, dynamic> extra;

  static const formats = ['text', 'upper', 'lower', 'title', 'number', 'integer', 'percent', 'currency', 'date', 'datetime'];
  static const _known = {'field', 'format', 'decimals', 'currency', 'date_pattern', 'prefix', 'suffix', 'empty', 'label'};

  factory LayoutBind.fromJson(Map<String, dynamic> j) => LayoutBind(
        field: _s(j['field']) ?? '',
        format: _s(j['format']) ?? 'text',
        decimals: j['decimals'] == null ? null : _i(j['decimals'], 0),
        currency: _s(j['currency']),
        datePattern: _s(j['date_pattern']),
        prefix: _s(j['prefix']) ?? '',
        suffix: _s(j['suffix']) ?? '',
        empty: _s(j['empty']) ?? '—',
        label: _s(j['label']),
        extra: _extra(j, _known),
      );

  /// A FieldRef may be written as a bare field name.
  static LayoutBind of(Object? v) => v is Map ? LayoutBind.fromJson(_map(v)) : LayoutBind(field: '${v ?? ''}');

  Map<String, dynamic> toJson() => {
        ...extra,
        'field': field,
        'format': format,
        if (decimals != null) 'decimals': decimals,
        if (currency != null) 'currency': currency,
        if (datePattern != null) 'date_pattern': datePattern,
        'prefix': prefix,
        'suffix': suffix,
        'empty': empty,
        if (label != null) 'label': label,
      };

  LayoutBind copy() => LayoutBind.fromJson(toJson());
}

class LayoutComputed {
  LayoutComputed({this.op = 'index', List<String>? fields, this.sep = ' ', Map<String, dynamic>? extra})
      : fields = fields ?? [],
        extra = extra ?? {};

  /// index (the item's number) | concat (fields joined by [sep])
  String op;
  final List<String> fields;
  String sep;
  final Map<String, dynamic> extra;

  static const _known = {'op', 'fields', 'sep'};

  factory LayoutComputed.fromJson(Map<String, dynamic> j) => LayoutComputed(
        op: _s(j['op']) ?? 'index',
        fields: [if (j['fields'] is List) for (final f in j['fields'] as List) '$f'],
        sep: _s(j['sep']) ?? ' ',
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {...extra, 'op': op, 'fields': [...fields], 'sep': sep};
}

/// One condition of a rule: `field op value`.
class LayoutCond {
  LayoutCond({required this.field, this.op = '=', this.value, Map<String, dynamic>? extra}) : extra = extra ?? {};

  String field;

  /// = != > >= < <= contains not_contains empty not_empty in starts_with ends_with
  String op;
  Object? value;
  final Map<String, dynamic> extra;

  static const ops = ['=', '!=', '>', '>=', '<', '<=', 'contains', 'not_contains', 'empty', 'not_empty', 'in', 'starts_with', 'ends_with'];
  static const _known = {'field', 'op', 'value'};

  bool get needsValue => op != 'empty' && op != 'not_empty';

  factory LayoutCond.fromJson(Map<String, dynamic> j) =>
      LayoutCond(field: _s(j['field']) ?? '', op: _s(j['op']) ?? '=', value: j['value'], extra: _extra(j, _known));

  Map<String, dynamic> toJson() => {...extra, 'field': field, 'op': op, 'value': value};
}

/// What a matching rule (or `else`) does to its element.
class LayoutThen {
  LayoutThen({this.show = true, this.text, this.color, this.bg, this.icon, this.bold, Map<String, dynamic>? extra}) : extra = extra ?? {};

  bool show;
  bool? bold;
  String? text, color, bg, icon;
  final Map<String, dynamic> extra;

  static const _known = {'show', 'text', 'color', 'bg', 'icon', 'bold'};

  /// The icon names older app versions wrote, as the server's names (check · x · dot · star · warning).
  static const _legacyIcon = {'close': 'x', 'info': 'dot'};

  static LayoutThen? maybe(Object? v) => v is Map ? LayoutThen.fromJson(_map(v)) : null;

  factory LayoutThen.fromJson(Map<String, dynamic> j) => LayoutThen(
        show: _b(j['show'], true),
        text: _s(j['text']),
        color: _s(j['color']),
        bg: _s(j['bg']),
        icon: _legacyIcon[_s(j['icon'])] ?? _s(j['icon']),
        bold: j['bold'] is bool ? j['bold'] as bool : null,
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'show': show,
        if (bold != null) 'bold': bold,
        if (text != null) 'text': text,
        if (color != null) 'color': color,
        if (bg != null) 'bg': bg,
        if (icon != null) 'icon': icon,
      };
}

class LayoutRule {
  LayoutRule({List<LayoutCond>? when, this.match = 'all', LayoutThen? then, Map<String, dynamic>? extra})
      : when = when ?? [],
        then = then ?? LayoutThen(),
        extra = extra ?? {};

  final List<LayoutCond> when;

  /// all | any
  String match;
  LayoutThen then;
  final Map<String, dynamic> extra;

  static const _known = {'when', 'match', 'then'};

  factory LayoutRule.fromJson(Map<String, dynamic> j) => LayoutRule(
        when: [for (final c in _maps(j['when'])) LayoutCond.fromJson(c)],
        match: _s(j['match']) ?? 'all',
        then: LayoutThen.maybe(j['then']),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {...extra, 'when': [for (final c in when) c.toJson()], 'match': match, 'then': then.toJson()};
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Elements, bands, the row
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The studio's element type switch (derived from the element, see [LayoutElement.type]).
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  v4 computed fields ("computed columns"): cases of (condition group → value), first match wins, else a value.
//  Data only — the server evaluates them (services/export_layout/computed.py), layout_computed.dart mirrors it.
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// A condition group: all / any of conditions and nested groups (depth ≤ 3). Empty = always true.
class LayoutCondGroup {
  LayoutCondGroup({this.match = 'all', List<Object>? items}) : items = items ?? [];

  /// all | any
  String match;

  /// [LayoutCond] or [LayoutCondGroup].
  final List<Object> items;

  factory LayoutCondGroup.fromJson(Map<String, dynamic> j) => LayoutCondGroup(
        match: _s(j['match']) == 'any' ? 'any' : 'all',
        items: [
          for (final x in _maps(j['items'])) x.containsKey('items') ? LayoutCondGroup.fromJson(x) : LayoutCond.fromJson(x),
        ],
      );

  Map<String, dynamic> toJson() => {
        'match': match,
        'items': [
          for (final x in items) x is LayoutCondGroup ? x.toJson() : (x as LayoutCond).toJson(),
        ],
      };
}

/// A value expression: exactly one of text · number · field · concat (+ sep) · math (+ args).
class LayoutExpr {
  LayoutExpr({this.text, this.number, this.field, this.concat, this.sep = ' ', this.math, this.args});
  LayoutExpr.text(String this.text) : sep = ' ';
  LayoutExpr.number(num this.number) : sep = ' ';
  LayoutExpr.field(String this.field) : sep = ' ';

  String? text;
  num? number;
  String? field;
  List<LayoutExpr>? concat;
  String sep;

  /// + - * / min max round abs percent
  String? math;
  List<LayoutExpr>? args;

  static const mathOps = ['+', '-', '*', '/', 'min', 'max', 'round', 'abs', 'percent'];

  static LayoutExpr? maybe(Object? v) => v is Map ? LayoutExpr.fromJson(_map(v)) : null;

  factory LayoutExpr.fromJson(Map<String, dynamic> j) {
    if (j.containsKey('text')) return LayoutExpr.text(_s(j['text']) ?? '');
    if (j['number'] is num) return LayoutExpr.number(j['number'] as num);
    if (j.containsKey('field')) return LayoutExpr.field(_s(j['field']) ?? '');
    if (j['concat'] is List) {
      return LayoutExpr(concat: [for (final x in _maps(j['concat'])) LayoutExpr.fromJson(x)], sep: _s(j['sep']) ?? ' ');
    }
    return LayoutExpr(math: _s(j['math']) ?? '+', args: [for (final x in _maps(j['args'])) LayoutExpr.fromJson(x)]);
  }

  Map<String, dynamic> toJson() {
    if (text != null) return {'text': text};
    if (number != null) return {'number': number};
    if (field != null) return {'field': field};
    if (concat != null) return {'concat': [for (final x in concat!) x.toJson()], 'sep': sep};
    return {'math': math ?? '+', 'args': [for (final x in args ?? const <LayoutExpr>[]) x.toJson()]};
  }
}

class LayoutCase {
  LayoutCase({LayoutCondGroup? when, required this.value}) : when = when ?? LayoutCondGroup();
  LayoutCondGroup when;
  LayoutExpr value;

  factory LayoutCase.fromJson(Map<String, dynamic> j) =>
      LayoutCase(when: LayoutCondGroup.fromJson(_map(j['when'])), value: LayoutExpr.maybe(j['value']) ?? LayoutExpr.text(''));

  Map<String, dynamic> toJson() => {'when': when.toJson(), 'value': value.toJson()};
}

/// One computed field: its `calc.` key, names, type, cases and else. Usable anywhere a column is.
class LayoutComputedField {
  LayoutComputedField({required this.key, this.labelAr = '', this.labelEn = '', this.type = 'text', List<LayoutCase>? cases, this.otherwise})
      : cases = cases ?? [];

  /// `calc.` + letters / digits / _ (≤ 40).
  String key;
  String labelAr, labelEn;

  /// text | number | date
  String type;
  final List<LayoutCase> cases;

  /// `else` (null = empty).
  LayoutExpr? otherwise;

  static const prefix = 'calc.';
  static final keyPattern = RegExp(r'^calc\.[A-Za-z0-9_]{1,40}$');

  String label(String lang) => lang == 'ar' ? (labelAr.isEmpty ? labelEn : labelAr) : (labelEn.isEmpty ? labelAr : labelEn);

  /// The column the designer offers for it.
  LayoutField asField() => LayoutField(key: key, labelAr: labelAr, labelEn: labelEn, type: type == 'number' ? 'number' : type == 'date' ? 'date' : 'text');

  factory LayoutComputedField.fromJson(Map<String, dynamic> j) => LayoutComputedField(
        key: _s(j['key']) ?? '',
        labelAr: _s(j['label_ar']) ?? '',
        labelEn: _s(j['label_en']) ?? '',
        type: _s(j['type']) ?? 'text',
        cases: [for (final c in _maps(j['cases'])) LayoutCase.fromJson(c)],
        otherwise: LayoutExpr.maybe(j['else']),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label_ar': labelAr,
        'label_en': labelEn,
        'type': type,
        'cases': [for (final c in cases) c.toJson()],
        'else': otherwise?.toJson(),
      };
}

enum LayoutElementType { staticValue, dynamic, conditional, computed }

class LayoutElement {
  LayoutElement({
    required this.id,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.w = 40,
    this.h = 8,
    this.rotation = 0,
    this.locked = false,
    this.name,
    this.value,
    this.bind,
    this.computed,
    List<LayoutRule>? rules,
    this.otherwise,
    LayoutStyle? style,
    this.fit,
    this.sigName,
    this.sigTitle,
    this.opacity = 1,
    this.shape = 'rect',
    Map<String, dynamic>? extra,
  })  : rules = rules ?? [],
        style = style ?? LayoutStyle(),
        extra = extra ?? {};

  String id;

  /// text | field | image | line | rect | badge | qr | page_number | signature
  String kind;
  double x, y, w, h, rotation;
  bool locked;
  String? name;

  /// Static text (variables allowed) / image upload id / qr text.
  String? value;
  LayoutBind? bind;
  LayoutComputed? computed;
  final List<LayoutRule> rules;

  /// `else`: applied when no rule matches.
  LayoutThen? otherwise;
  LayoutStyle style;

  /// Images / signatures: contain | cover | fill.
  String? fit;

  /// Signatures: the name and title lines under the image (variables allowed).
  String? sigName, sigTitle;

  /// v4: 0–1 (every kind).
  double opacity;

  /// v4, images / signatures (photos): rect | rounded | circle.
  String shape;
  final Map<String, dynamic> extra;

  static const kinds = ['text', 'field', 'image', 'line', 'rect', 'badge', 'qr', 'page_number', 'signature', 'ellipse'];
  static const _known = {
    'id', 'kind', 'x', 'y', 'w', 'h', 'rotation', 'locked', 'name', 'value', 'bind', 'computed', 'rules', 'else', //
    'style', 'fit', 'sig_name', 'sig_title', 'opacity', 'shape',
  };

  bool get isText => kind == 'text' || kind == 'field' || kind == 'badge' || kind == 'page_number';
  bool get isImage => kind == 'image' || kind == 'signature';

  LayoutElementType get type {
    if (computed != null) return LayoutElementType.computed;
    if (rules.isNotEmpty) return LayoutElementType.conditional;
    if (bind != null || kind == 'field') return LayoutElementType.dynamic;
    return LayoutElementType.staticValue;
  }

  factory LayoutElement.fromJson(Map<String, dynamic> j) => LayoutElement(
        id: _s(j['id']) ?? '',
        kind: _s(j['kind']) ?? 'text',
        x: _d(j['x'], 0),
        y: _d(j['y'], 0),
        w: _d(j['w'], 40),
        h: _d(j['h'], 8),
        rotation: _d(j['rotation'], 0),
        locked: _b(j['locked'], false),
        name: _s(j['name']),
        value: _s(j['value']),
        bind: j['bind'] is Map ? LayoutBind.fromJson(_map(j['bind'])) : null,
        computed: j['computed'] is Map ? LayoutComputed.fromJson(_map(j['computed'])) : null,
        rules: [for (final r in _maps(j['rules'])) LayoutRule.fromJson(r)],
        otherwise: LayoutThen.maybe(j['else']),
        style: LayoutStyle.fromJson(_map(j['style'])),
        fit: _s(j['fit']),
        sigName: _s(j['sig_name']),
        sigTitle: _s(j['sig_title']),
        opacity: _d(j['opacity'], 1).clamp(0, 1).toDouble(),
        shape: _s(j['shape']) ?? 'rect',
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'id': id,
        'kind': kind,
        'x': mm(x),
        'y': mm(y),
        'w': mm(w),
        'h': mm(h),
        'rotation': rotation,
        'locked': locked,
        if (name != null) 'name': name,
        if (value != null) 'value': value,
        if (bind != null) 'bind': bind!.toJson(),
        if (computed != null) 'computed': computed!.toJson(),
        if (rules.isNotEmpty) 'rules': [for (final r in rules) r.toJson()],
        if (otherwise != null) 'else': otherwise!.toJson(),
        'style': style.toJson(),
        if (fit != null) 'fit': fit,
        if (sigName != null) 'sig_name': sigName,
        if (sigTitle != null) 'sig_title': sigTitle,
        if (opacity != 1) 'opacity': opacity,
        if (shape != 'rect') 'shape': shape,
      };

  LayoutElement copy({String? id}) => LayoutElement.fromJson({...toJson(), 'id': ?id});
}

/// A fixed part of the page: the header, the footer, the blocks right before / after the items, a group header.
class LayoutBand {
  LayoutBand({this.height = 20, this.placement = 'every_page', List<LayoutElement>? elements, this.background, Map<String, dynamic>? extra})
      : elements = elements ?? [],
        extra = extra ?? {};

  double height;

  /// header: first_page | every_page · footer: after_items | every_page · before / after items: flow (ignored)
  String placement;
  final List<LayoutElement> elements;
  String? background;
  final Map<String, dynamic> extra;

  static const _known = {'height', 'placement', 'elements', 'background'};

  static LayoutBand? maybe(Object? v) => v is Map ? LayoutBand.fromJson(_map(v)) : null;

  factory LayoutBand.fromJson(Map<String, dynamic> j) => LayoutBand(
        height: _d(j['height'], 20),
        placement: _s(j['placement']) ?? 'every_page',
        elements: [for (final e in _maps(j['elements'])) LayoutElement.fromJson(e)],
        background: _s(j['background']),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'height': mm(height),
        'placement': placement,
        'elements': [for (final e in elements) e.toJson()],
        'background': background,
      };

  LayoutBand copy() => LayoutBand.fromJson(toJson());
}

/// The custom mode's item block: ONE card, repeated for every item ([perLine] cards side by side).
class LayoutRow {
  LayoutRow({
    this.height = 22,
    this.perLine = 1,
    this.gap = 3,
    List<LayoutElement>? elements,
    this.zebra,
    this.separator,
    this.background,
    this.border,
    this.radius = 2,
    this.keepTogether = true,
    this.perPage = 0,
    this.fillPage = false,
    Map<String, dynamic>? extra,
  })  : elements = elements ?? [],
        extra = extra ?? {};

  double height;

  /// 1–4 cards side by side.
  int perLine;

  /// v4: a page break after this many cards (0 = as many as fit; 2×2 grid = perLine 2, perPage 4).
  int perPage;

  /// v4: the card height is computed so perPage ÷ perLine lines fill the page ([height] ignored).
  bool fillPage;
  double gap;
  final List<LayoutElement> elements;
  String? zebra, background;
  LayoutBorder? separator, border;
  double radius;
  bool keepTogether;
  final Map<String, dynamic> extra;

  static const _known = {
    'height', 'per_line', 'gap', 'elements', 'zebra', 'separator', 'background', 'border', 'radius', 'keep_together', //
    'per_page', 'fill_page',
  };

  /// One card's width in a band [contentWidth] wide.
  double cardWidth(double contentWidth) => (contentWidth - gap * (perLine - 1)) / perLine;

  factory LayoutRow.fromJson(Map<String, dynamic> j) => LayoutRow(
        height: _d(j['height'], 22),
        perLine: _i(j['per_line'], 1).clamp(1, 4),
        perPage: _i(j['per_page'], 0).clamp(0, 100),
        fillPage: _b(j['fill_page'], false),
        gap: _d(j['gap'], 3),
        elements: [for (final e in _maps(j['elements'])) LayoutElement.fromJson(e)],
        zebra: _s(j['zebra']),
        separator: LayoutBorder.maybe(j['separator']),
        background: _s(j['background']),
        border: LayoutBorder.maybe(j['border']),
        radius: _d(j['radius'], 2),
        keepTogether: _b(j['keep_together'], true),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'height': mm(height),
        'per_line': perLine,
        'gap': gap,
        'elements': [for (final e in elements) e.toJson()],
        if (zebra != null) 'zebra': zebra,
        if (separator != null) 'separator': separator!.toJson(),
        'background': background,
        if (border != null) 'border': border!.toJson(),
        'radius': radius,
        'keep_together': keepTogether,
        if (perPage > 0) 'per_page': perPage,
        if (fillPage) 'fill_page': true,
      };
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  The page, list / table modes, sort / group / totals
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

class LayoutMargins {
  LayoutMargins({this.top = 15, this.right = 12, this.bottom = 15, this.left = 12});
  double top, right, bottom, left;

  factory LayoutMargins.fromJson(Map<String, dynamic> j) =>
      LayoutMargins(top: _d(j['top'], 15), right: _d(j['right'], 12), bottom: _d(j['bottom'], 15), left: _d(j['left'], 12));

  Map<String, dynamic> toJson() => {'top': top, 'right': right, 'bottom': bottom, 'left': left};
}

class LayoutPage {
  LayoutPage({
    this.size = 'A4',
    this.orientation = 'portrait',
    LayoutMargins? margins,
    this.rtl = false,
    this.font = 'tajawal',
    this.fontSize = 10,
    this.background,
    this.customWidth = 210,
    this.customHeight = 297,
    this.backgroundImage,
    this.backgroundFit = 'cover',
    Map<String, dynamic>? extra,
  })  : margins = margins ?? LayoutMargins(),
        extra = extra ?? {};

  /// A4 | A3 | A5 | Letter | custom
  String size;

  /// v4, size custom: the page in mm (portrait sides; [orientation] still swaps them).
  double customWidth, customHeight;

  /// v4: an asset id / allowed image URL drawn under everything; cover | contain | fill.
  String? backgroundImage;
  String backgroundFit;

  /// portrait | landscape
  String orientation;
  LayoutMargins margins;
  bool rtl;
  String font;
  double fontSize;
  String? background;
  final Map<String, dynamic> extra;

  static const sizes = {'A4': (210.0, 297.0), 'A3': (297.0, 420.0), 'A5': (148.0, 210.0), 'Letter': (215.9, 279.4)};
  static const _known = {
    'size', 'orientation', 'margins', 'rtl', 'font', 'font_size', 'background', 'width', 'height', 'background_image', //
    'background_fit',
  };

  bool get landscape => orientation == 'landscape';
  (double, double) get _sides => size == 'custom' ? (customWidth, customHeight) : (sizes[size] ?? sizes['A4']!);
  double get width => landscape ? _sides.$2 : _sides.$1;
  double get height => landscape ? _sides.$1 : _sides.$2;

  /// The band width: page width − margins.
  double get contentWidth => width - margins.left - margins.right;
  double get contentHeight => height - margins.top - margins.bottom;

  factory LayoutPage.fromJson(Map<String, dynamic> j) => LayoutPage(
        size: _s(j['size']) ?? 'A4',
        orientation: _s(j['orientation']) ?? 'portrait',
        margins: LayoutMargins.fromJson(_map(j['margins'])),
        rtl: _b(j['rtl'], false),
        font: _s(j['font']) ?? 'tajawal',
        fontSize: _d(j['font_size'], 10),
        background: _s(j['background']),
        customWidth: _d(j['width'], 210),
        customHeight: _d(j['height'], 297),
        backgroundImage: _s(j['background_image']),
        backgroundFit: _s(j['background_fit']) ?? 'cover',
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'size': size,
        if (size == 'custom') 'width': customWidth,
        if (size == 'custom') 'height': customHeight,
        if (backgroundImage != null) 'background_image': backgroundImage,
        if (backgroundImage != null) 'background_fit': backgroundFit,
        'orientation': orientation,
        'margins': margins.toJson(),
        'rtl': rtl,
        'font': font,
        'font_size': fontSize,
        'background': background,
      };
}

class LayoutListSpec {
  LayoutListSpec({
    List<LayoutBind>? fields,
    this.separator = ' · ',
    this.numbered = true,
    LayoutStyle? style,
    this.rowHeight,
    this.columns = 1,
    this.columnGap = 6,
    this.itemsPerPage = 0,
    Map<String, dynamic>? extra,
  })
      : fields = fields ?? [],
        style = style ?? LayoutStyle(),
        extra = extra ?? {};

  final List<LayoutBind> fields;
  String separator;
  bool numbered;
  LayoutStyle style;

  /// Fixed line height (mm); null = the server's default (font size × 1.3 × lines + padding).
  double? rowHeight;

  /// v4: newspaper columns side by side (1–4), the gap between them (mm), a page break every N items (0 = auto).
  int columns;
  double columnGap;
  int itemsPerPage;
  final Map<String, dynamic> extra;

  static const _known = {'fields', 'separator', 'numbered', 'style', 'row_height', 'columns', 'column_gap', 'items_per_page'};

  factory LayoutListSpec.fromJson(Map<String, dynamic> j) => LayoutListSpec(
        fields: [if (j['fields'] is List) for (final f in j['fields'] as List) LayoutBind.of(f)],
        separator: _s(j['separator']) ?? ' · ',
        numbered: _b(j['numbered'], true),
        style: LayoutStyle.fromJson(_map(j['style'])),
        rowHeight: j['row_height'] is num ? (j['row_height'] as num).toDouble() : null,
        columns: _i(j['columns'], 1).clamp(1, 4),
        columnGap: _d(j['column_gap'], 6),
        itemsPerPage: _i(j['items_per_page'], 0),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'fields': [for (final f in fields) f.toJson()],
        if (columns > 1) 'columns': columns,
        if (columns > 1) 'column_gap': columnGap,
        if (itemsPerPage > 0) 'items_per_page': itemsPerPage,
        'separator': separator,
        'numbered': numbered,
        'style': style.toJson(),
        if (rowHeight != null) 'row_height': rowHeight,
      };
}

class LayoutColumn {
  LayoutColumn({required this.field, this.width = 30, this.align = 'start', LayoutStyle? style, Map<String, dynamic>? extra})
      : style = style ?? LayoutStyle(),
        extra = extra ?? {};

  LayoutBind field;
  double width;

  /// start | center | end
  String align;
  LayoutStyle style;
  final Map<String, dynamic> extra;

  static const _known = {'field', 'width', 'align', 'style'};

  factory LayoutColumn.fromJson(Map<String, dynamic> j) => LayoutColumn(
        field: LayoutBind.of(j['field']),
        width: _d(j['width'], 30),
        align: _s(j['align']) ?? 'start',
        style: LayoutStyle.fromJson(_map(j['style'])),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {...extra, 'field': field.toJson(), 'width': mm(width), 'align': align, 'style': style.toJson()};
}

class LayoutTableSpec {
  LayoutTableSpec({
    List<LayoutColumn>? columns,
    LayoutStyle? headerStyle,
    this.zebra,
    this.borders,
    this.repeatHeader = true,
    this.rowHeight,
    this.headerHeight,
    this.itemsPerPage = 0,
    Map<String, dynamic>? extra,
  })
      : columns = columns ?? [],
        headerStyle = headerStyle ?? LayoutStyle(weight: 700),
        extra = extra ?? {};

  final List<LayoutColumn> columns;
  LayoutStyle headerStyle;
  String? zebra;
  LayoutBorder? borders;
  bool repeatHeader;

  /// Fixed heights (mm); null = the server's default from the font size.
  double? rowHeight, headerHeight;

  /// v4: a page break every N rows (0 = as many as fit).
  int itemsPerPage;
  final Map<String, dynamic> extra;

  static const _known = {'columns', 'header_style', 'zebra', 'borders', 'repeat_header', 'row_height', 'header_height', 'items_per_page'};

  factory LayoutTableSpec.fromJson(Map<String, dynamic> j) => LayoutTableSpec(
        columns: [for (final c in _maps(j['columns'])) LayoutColumn.fromJson(c)],
        headerStyle: LayoutStyle.fromJson(_map(j['header_style'])),
        zebra: _s(j['zebra']),
        borders: LayoutBorder.maybe(j['borders']),
        repeatHeader: _b(j['repeat_header'], true),
        rowHeight: j['row_height'] is num ? (j['row_height'] as num).toDouble() : null,
        headerHeight: j['header_height'] is num ? (j['header_height'] as num).toDouble() : null,
        itemsPerPage: _i(j['items_per_page'], 0),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'columns': [for (final c in columns) c.toJson()],
        'header_style': headerStyle.toJson(),
        'zebra': zebra,
        if (borders != null) 'borders': borders!.toJson(),
        'repeat_header': repeatHeader,
        if (rowHeight != null) 'row_height': rowHeight,
        if (headerHeight != null) 'header_height': headerHeight,
        if (itemsPerPage > 0) 'items_per_page': itemsPerPage,
      };
}

class LayoutSort {
  LayoutSort({required this.field, this.dir = 'asc'});
  String field;

  /// asc | desc
  String dir;

  factory LayoutSort.fromJson(Map<String, dynamic> j) => LayoutSort(field: _s(j['field']) ?? '', dir: _s(j['dir']) ?? 'asc');
  Map<String, dynamic> toJson() => {'field': field, 'dir': dir};
}

class LayoutGroup {
  LayoutGroup({required this.field, this.header, this.pageBreak = false, Map<String, dynamic>? extra}) : extra = extra ?? {};
  String field;

  /// Repeats per group; `{{group}}` is the group's value.
  LayoutBand? header;

  /// v4: every group after the first starts on a new page.
  bool pageBreak;
  final Map<String, dynamic> extra;

  static const _known = {'field', 'header', 'page_break'};

  static LayoutGroup? maybe(Object? v) => v is Map ? LayoutGroup.fromJson(_map(v)) : null;

  factory LayoutGroup.fromJson(Map<String, dynamic> j) =>
      LayoutGroup(field: _s(j['field']) ?? '', header: LayoutBand.maybe(j['header']), pageBreak: _b(j['page_break'], false), extra: _extra(j, _known));

  Map<String, dynamic> toJson() => {...extra, 'field': field, if (header != null) 'header': header!.toJson(), if (pageBreak) 'page_break': true};
}

class LayoutTotal {
  LayoutTotal({required this.field, this.fn = 'sum', this.label = ''});
  String field;

  /// sum | avg | count | min | max
  String fn;
  String label;

  static const fns = ['sum', 'avg', 'count', 'min', 'max'];

  factory LayoutTotal.fromJson(Map<String, dynamic> j) =>
      LayoutTotal(field: _s(j['field']) ?? '', fn: _s(j['fn']) ?? 'sum', label: _s(j['label']) ?? '');
  Map<String, dynamic> toJson() => {'field': field, 'fn': fn, 'label': label};
}

class LayoutWatermark {
  LayoutWatermark({this.text = '', this.opacity = 0.08, this.angle = 45, this.fontSize = 60, this.color = '#808080', Map<String, dynamic>? extra})
      : extra = extra ?? {};
  String text, color;
  double opacity, angle, fontSize;
  final Map<String, dynamic> extra;

  static const _known = {'text', 'opacity', 'angle', 'font_size', 'color'};

  static LayoutWatermark? maybe(Object? v) => v is Map ? LayoutWatermark.fromJson(_map(v)) : null;

  factory LayoutWatermark.fromJson(Map<String, dynamic> j) => LayoutWatermark(
        text: _s(j['text']) ?? '',
        opacity: _d(j['opacity'], 0.08),
        angle: _d(j['angle'], 45),
        fontSize: _d(j['font_size'], 60),
        color: _s(j['color']) ?? '#808080',
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {...extra, 'text': text, 'opacity': opacity, 'angle': angle, 'font_size': fontSize, 'color': color};
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Design + document
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The four fixed parts, in page order.
enum LayoutBandSlot {
  header('header'),
  beforeItems('before_items'),
  afterItems('after_items'),
  footer('footer');

  const LayoutBandSlot(this.key);
  final String key;

  /// The placements the slot offers (before / after items flow once, where they are).
  List<String> get placements => switch (this) {
        header => const ['first_page', 'every_page'],
        footer => const ['after_items', 'every_page'],
        _ => const [],
      };
}

class LayoutDesign {
  LayoutDesign({
    LayoutPage? page,
    this.mode = 'table',
    LayoutBand? header,
    LayoutBand? footer,
    this.beforeItems,
    this.afterItems,
    LayoutListSpec? list,
    LayoutTableSpec? table,
    LayoutRow? row,
    List<LayoutSort>? sort,
    this.group,
    List<LayoutTotal>? totals,
    this.watermark,
    this.frame,
    Map<String, dynamic>? extra,
  })  : page = page ?? LayoutPage(),
        header = header ?? LayoutBand(placement: 'first_page'),
        footer = footer ?? LayoutBand(height: 10, placement: 'every_page'),
        list = list ?? LayoutListSpec(),
        table = table ?? LayoutTableSpec(),
        row = row ?? LayoutRow(),
        sort = sort ?? [],
        totals = totals ?? [],
        extra = extra ?? {};

  LayoutPage page;

  /// list | table | custom | page (v4: one page per item — certificates, covers; uses [row])
  String mode;
  LayoutBand header, footer;
  LayoutBand? beforeItems, afterItems;
  LayoutListSpec list;
  LayoutTableSpec table;
  LayoutRow row;
  final List<LayoutSort> sort;
  LayoutGroup? group;
  final List<LayoutTotal> totals;
  LayoutWatermark? watermark;
  LayoutBorder? frame;
  final Map<String, dynamic> extra;

  static const modes = ['list', 'table', 'custom', 'page'];
  static const _known = {
    'page', 'mode', 'header', 'footer', 'before_items', 'after_items', 'list', 'table', 'row', 'sort', 'group', //
    'totals', 'watermark', 'frame',
  };

  LayoutBand? band(LayoutBandSlot s) => switch (s) {
        LayoutBandSlot.header => header,
        LayoutBandSlot.footer => footer,
        LayoutBandSlot.beforeItems => beforeItems,
        LayoutBandSlot.afterItems => afterItems,
      };

  void setBand(LayoutBandSlot s, LayoutBand? b) {
    switch (s) {
      case LayoutBandSlot.header:
        header = b ?? LayoutBand(height: 0, placement: 'first_page');
      case LayoutBandSlot.footer:
        footer = b ?? LayoutBand(height: 0, placement: 'every_page');
      case LayoutBandSlot.beforeItems:
        beforeItems = b;
      case LayoutBandSlot.afterItems:
        afterItems = b;
    }
  }

  /// Every band of the design (the group header included), for walks over all elements.
  List<LayoutBand> get bands => [header, ?beforeItems, ?afterItems, footer, ?group?.header];

  /// Every element of the design: the bands' and the row's.
  Iterable<LayoutElement> get allElements sync* {
    for (final b in bands) {
      yield* b.elements;
    }
    yield* row.elements;
  }

  factory LayoutDesign.fromJson(Map<String, dynamic> j) => LayoutDesign(
        page: LayoutPage.fromJson(_map(j['page'])),
        mode: _s(j['mode']) ?? 'table',
        header: LayoutBand.maybe(j['header']) ?? LayoutBand(height: 0, placement: 'first_page'),
        footer: LayoutBand.maybe(j['footer']) ?? LayoutBand(height: 0, placement: 'every_page'),
        beforeItems: LayoutBand.maybe(j['before_items']),
        afterItems: LayoutBand.maybe(j['after_items']),
        list: LayoutListSpec.fromJson(_map(j['list'])),
        table: LayoutTableSpec.fromJson(_map(j['table'])),
        row: LayoutRow.fromJson(_map(j['row'])),
        sort: [for (final s in _maps(j['sort'])) LayoutSort.fromJson(s)],
        group: LayoutGroup.maybe(j['group']),
        totals: [for (final t in _maps(j['totals'])) LayoutTotal.fromJson(t)],
        watermark: LayoutWatermark.maybe(j['watermark']),
        frame: LayoutBorder.maybe(j['frame']),
        extra: _extra(j, _known),
      );

  Map<String, dynamic> toJson() => {
        ...extra,
        'page': page.toJson(),
        'mode': mode,
        'header': header.toJson(),
        'footer': footer.toJson(),
        if (beforeItems != null) 'before_items': beforeItems!.toJson(),
        if (afterItems != null) 'after_items': afterItems!.toJson(),
        'list': list.toJson(),
        'table': table.toJson(),
        'row': row.toJson(),
        'sort': [for (final s in sort) s.toJson()],
        if (group != null) 'group': group!.toJson(),
        'totals': [for (final t in totals) t.toJson()],
        if (watermark != null) 'watermark': watermark!.toJson(),
        if (frame != null) 'frame': frame!.toJson(),
      };

  LayoutDesign copy() => LayoutDesign.fromJson(toJson());

  /// The ids [newId] handed out (not in the JSON): a paste / duplicate of several elements asks for all its ids
  /// before any of them is added.
  final Set<String> _issued = {};

  /// A new element id not used anywhere in the design and never handed out before.
  String newId([String prefix = 'e']) {
    final used = {for (final e in allElements) e.id, ..._issued};
    var i = used.length + 1;
    while (used.contains('$prefix$i')) {
      i++;
    }
    _issued.add('$prefix$i');
    return '$prefix$i';
  }
}

class LayoutDocument {
  LayoutDocument({
    this.format = 'pdf',
    List<String>? languages,
    Map<String, LayoutDesign>? designs,
    Map<String, dynamic>? source,
    this.name,
    this.purpose = 'export',
    List<LayoutComputedField>? computed,
    Map<String, dynamic>? extra,
  })  : languages = languages ?? ['ar'],
        designs = designs ?? {},
        source = source ?? {},
        computed = computed ?? [],
        extra = extra ?? {};

  /// pdf | docx | xlsx
  String format;

  /// ['ar'] | ['en'] | ['ar', 'en'] (both = two files / two sheets)
  List<String> languages;
  final Map<String, LayoutDesign> designs;

  /// {dataset, params} or {rows_upload}
  Map<String, dynamic> source;

  /// The title of a run (optional): the server prints it as {{title}} and names the file after it.
  String? name;

  /// v4: export | certificate | exam_paper | exam_cover | bubble_sheet | guide
  String purpose;

  /// v4: the computed fields (language-independent, evaluated in order: one may read the earlier ones).
  final List<LayoutComputedField> computed;
  final Map<String, dynamic> extra;

  static const formats = ['pdf', 'docx', 'xlsx'];
  static const purposes = ['export', 'certificate', 'exam_paper', 'exam_cover', 'bubble_sheet', 'guide'];
  static const _known = {'schema_version', 'format', 'languages', 'designs', 'source', 'name', 'purpose', 'computed'};

  /// The computed fields as columns the designer can place.
  List<LayoutField> get computedFields => [for (final c in computed) c.asField()];

  /// ar | en | both (the templates' `lang`).
  String get langKey => languages.length > 1 ? 'both' : languages.first;

  LayoutDesign? design(String lang) => designs[lang];

  factory LayoutDocument.fromJson(Map<String, dynamic> j) {
    final designs = _map(j['designs']);
    return LayoutDocument(
      format: _s(j['format']) ?? 'pdf',
      languages: [if (j['languages'] is List) for (final l in j['languages'] as List) '$l'],
      designs: {for (final e in designs.entries) if (e.value is Map) e.key: LayoutDesign.fromJson(_map(e.value))},
      source: _map(j['source']),
      name: _s(j['name']),
      purpose: _s(j['purpose']) ?? 'export',
      computed: [for (final c in _maps(j['computed'])) LayoutComputedField.fromJson(c)],
      extra: _extra(j, _known),
    )..languages.removeWhere((l) => l != 'ar' && l != 'en');
  }

  Map<String, dynamic> toJson({bool withSource = true}) => {
        ...extra,
        'schema_version': kLayoutSchemaVersion,
        'format': format,
        'languages': [...languages],
        'designs': {for (final e in designs.entries) e.key: e.value.toJson()},
        if (withSource) 'source': source,
        if (name != null) 'name': name,
        if (purpose != 'export') 'purpose': purpose,
        if (computed.isNotEmpty) 'computed': [for (final c in computed) c.toJson()],
      };

  LayoutDocument copy() => LayoutDocument.fromJson(toJson());
}

// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════
//  Fields (the dataset / table columns the designer picks from)
// ═════════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// One column of the items: its key in each row, its names, its type.
class LayoutField {
  const LayoutField({required this.key, required this.labelAr, required this.labelEn, this.type = 'text', this.visible = true, this.currency, this.statusLabels = const {}});

  final String key, labelAr, labelEn;

  /// text | number | integer | money | percent | date | datetime | status
  final String type;

  /// Preselected (the table shows it by default).
  final bool visible;
  final String? currency;

  /// Raw status value → its label per language ({'ar': {...}, 'en': {...}}).
  final Map<String, Map<String, String>> statusLabels;

  String label(String lang) => lang == 'ar' ? (labelAr.isEmpty ? labelEn : labelAr) : (labelEn.isEmpty ? labelAr : labelEn);

  bool get numeric => type == 'number' || type == 'integer' || type == 'money' || type == 'percent';

  /// The bind format a starter design gives this field.
  String get defaultFormat => switch (type) {
        'number' => 'number',
        'integer' => 'integer',
        'money' => 'currency',
        'percent' => 'percent',
        'date' => 'date',
        'datetime' => 'datetime',
        _ => 'text',
      };

  LayoutBind bind({String? lang}) => LayoutBind(field: key, format: defaultFormat, currency: currency, label: lang == null ? null : label(lang));

  Map<String, dynamic> toJson() => {'key': key, 'label_ar': labelAr, 'label_en': labelEn, 'type': type};
}
