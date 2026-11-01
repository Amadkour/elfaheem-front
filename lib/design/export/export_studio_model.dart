// lib/design/export/export_studio_model.dart
//
// The Export Studio's pure model (no widgets — unit-tested in test/export/export_studio_test.dart), shared by the
// guided export flow (export_hub/export_flow.dart), every writer (lib/design/export/ and lib/design/export_hub/)
// and the server's templates (`/api/v1/exports/templates`, D-130):
//
//   ExportRule / ExportRuleOp / ExportRuleStyle   conditional styling: field · condition · value · style (colour,
//                                                 background, bold, label, hide the row). The JSON and the matching
//                                                 rules are the server's (services/export_templates.clean_rules,
//                                                 services/export_render.rule_matches), so a template renders the
//                                                 same in the app and in a scheduled run.
//   exportRowLook / exportVisibleRows             what the rules do to one row / which rows are printed
//   ExportNumerals / exportDigits                 Western 0-9 or Arabic-Indic ٠-٩ digits, per language
//   XlsxSheetOptions                              the Excel studio's options (server option keys)
//   ExportTemplateOptions                         a template's `options` (sheet + totals + group-by + numerals + theme)
//   exportFileName / exportPageKey                `<title>_<yyyy-MM-dd>.<ext>` and the server's page_key
library;

import 'package:flutter_education_app/core/app_time.dart';

import 'export_watermark.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Conditional styling rules
// ═════════════════════════════════════════════════════════════════════════════

/// A rule's condition. [wire] is the server's spelling, [symbol] what the rule builder shows.
enum ExportRuleOp {
  eq('=', '='),
  ne('!=', '≠'),
  gt('>', '>'),
  ge('>=', '≥'),
  lt('<', '<'),
  le('<=', '≤'),
  contains('contains', '∋'),
  empty('empty', '∅'),
  notEmpty('not_empty', '✓');

  const ExportRuleOp(this.wire, this.symbol);
  final String wire, symbol;

  /// empty / not empty take no value.
  bool get needsValue => this != empty && this != notEmpty;

  /// Reads the server's and the app's spellings (= == ≠ != <> > ≥ >= < ≤ <= contains empty "not empty" not_empty
  /// filled); null when unknown.
  static ExportRuleOp? parse(Object? v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    return switch (s) {
      '=' || '==' => eq,
      '≠' || '!=' || '<>' => ne,
      '>' => gt,
      '≥' || '>=' => ge,
      '<' => lt,
      '≤' || '<=' => le,
      'contains' => contains,
      'empty' => empty,
      'not empty' || 'not_empty' || 'filled' => notEmpty,
      _ => null,
    };
  }
}

/// "#1E293B" / "1e293b" / "#FF1E293B" → "1E293B"; anything else → null.
String? exportHex(Object? v) {
  var s = '${v ?? ''}'.replaceAll('#', '').trim().toUpperCase();
  if (s.length == 8) s = s.substring(2);
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(s) ? s : null;
}

/// What a matching rule does to its cell. Colours are RRGGBB (no '#'); [label] prints instead of the value;
/// [hide] leaves the whole row out of the file.
class ExportRuleStyle {
  ExportRuleStyle({this.color, this.background, this.bold = false, this.label, this.hide = false});

  String? color, background, label;
  bool bold, hide;

  bool get isEmpty => color == null && background == null && !bold && (label ?? '').isEmpty && !hide;

  factory ExportRuleStyle.fromJson(Map<String, dynamic> j) => ExportRuleStyle(
        color: exportHex(j['color']),
        background: exportHex(j['background']),
        bold: j['bold'] == true,
        label: (j['label'] ?? '').toString().trim().isEmpty ? null : '${j['label']}',
        hide: j['hide'] == true,
      );

  /// The server's shape: `{color: "#RRGGBB", background, bold, label, hide}` with only what is set.
  Map<String, dynamic> toJson() => {
        if (exportHex(color) != null) 'color': '#${exportHex(color)}',
        if (exportHex(background) != null) 'background': '#${exportHex(background)}',
        if (bold) 'bold': true,
        if ((label ?? '').isNotEmpty) 'label': label,
        if (hide) 'hide': true,
      };

  ExportRuleStyle copy() => ExportRuleStyle(color: color, background: background, bold: bold, label: label, hide: hide);
}

class ExportRule {
  ExportRule({required this.field, this.op = ExportRuleOp.eq, this.value, ExportRuleStyle? style}) : style = style ?? ExportRuleStyle();

  /// The column id (row key) the rule tests and styles.
  String field;
  ExportRuleOp op;

  /// String, number or bool (null for empty / not empty).
  Object? value;
  ExportRuleStyle style;

  /// A rule without a style changes nothing (the builder still keeps it while it is being written).
  bool get effective => field.isNotEmpty && !style.isEmpty;

  factory ExportRule.fromJson(Map<String, dynamic> j) => ExportRule(
        field: '${j['field'] ?? ''}'.trim(),
        op: ExportRuleOp.parse(j['op']) ?? ExportRuleOp.eq,
        value: j['value'] is String || j['value'] is num || j['value'] is bool ? j['value'] : null,
        style: ExportRuleStyle.fromJson(j['style'] is Map ? (j['style'] as Map).cast<String, dynamic>() : const {}),
      );

  Map<String, dynamic> toJson() => {
        'field': field,
        'op': op.wire,
        'value': op.needsValue ? value : null,
        'style': style.toJson(),
      };

  ExportRule copy() => ExportRule(field: field, op: op, value: value, style: style.copy());

  /// Rules from a template / remembered JSON list (malformed entries skipped).
  static List<ExportRule> listFromJson(Object? raw) => [
        if (raw is List)
          for (final r in raw)
            if (r is Map && '${r['field'] ?? ''}'.trim().isNotEmpty) ExportRule.fromJson(r.cast<String, dynamic>()),
      ];

  static List<Map<String, dynamic>> listToJson(List<ExportRule> rules) => [for (final r in rules) if (r.field.isNotEmpty) r.toJson()];
}

double? _ruleNum(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  return double.tryParse('$v'.trim().replaceAll(',', ''));
}

bool _ruleEmpty(Object? v) => v == null || (v is String && v.trim().isEmpty);

/// Whether [rule] matches [row] — the server's `rule_matches`: empty / not empty on blank values; contains is a
/// case-insensitive substring; two numbers compare as numbers; otherwise = / ≠ compare trimmed lower-case text and
/// the order conditions never match text. A blank cell matches nothing but "empty".
bool exportRuleMatches(ExportRule rule, Map<String, Object?> row) {
  final v = row[rule.field];
  switch (rule.op) {
    case ExportRuleOp.empty:
      return _ruleEmpty(v);
    case ExportRuleOp.notEmpty:
      return !_ruleEmpty(v);
    default:
      break;
  }
  if (_ruleEmpty(v)) return false;
  final target = rule.value;
  if (rule.op == ExportRuleOp.contains) {
    return target != null && '$v'.toLowerCase().contains('$target'.trim().toLowerCase());
  }
  final n = _ruleNum(v), t = _ruleNum(target);
  if (n != null && t != null) {
    return switch (rule.op) {
      ExportRuleOp.eq => n == t,
      ExportRuleOp.ne => n != t,
      ExportRuleOp.gt => n > t,
      ExportRuleOp.ge => n >= t,
      ExportRuleOp.lt => n < t,
      ExportRuleOp.le => n <= t,
      _ => false,
    };
  }
  final sv = '$v'.trim().toLowerCase(), st = '${target ?? ''}'.trim().toLowerCase();
  return switch (rule.op) {
    ExportRuleOp.eq => sv == st,
    ExportRuleOp.ne => sv != st,
    _ => false,
  };
}

/// What the rules do to one row: [hidden] (a matching rule with `hide`) and the style per field (the FIRST
/// matching rule of a field wins — later rules for the same field are skipped, like the server).
class ExportRowLook {
  const ExportRowLook(this.hidden, this.cells);
  static const none = ExportRowLook(false, {});

  final bool hidden;
  final Map<String, ExportRuleStyle> cells;

  ExportRuleStyle? of(String field) => cells[field];

  /// The text printed for [field]: the rule's label, else [text].
  String textOf(String field, String text) {
    final l = cells[field]?.label;
    return l == null || l.isEmpty ? text : l;
  }
}

ExportRowLook exportRowLook(List<ExportRule> rules, Map<String, Object?> row) {
  if (rules.isEmpty) return ExportRowLook.none;
  final cells = <String, ExportRuleStyle>{};
  for (final r in rules) {
    if (!r.effective || cells.containsKey(r.field) || !exportRuleMatches(r, row)) continue;
    if (r.style.hide) return const ExportRowLook(true, {});
    cells[r.field] = r.style;
  }
  return cells.isEmpty ? ExportRowLook.none : ExportRowLook(false, cells);
}

/// The rows a file prints: those no rule hides (order kept).
List<Map<String, Object?>> exportVisibleRows(List<ExportRule> rules, List<Map<String, Object?>> rows) =>
    rules.any((r) => r.effective && r.style.hide) ? [for (final r in rows) if (!exportRowLook(rules, r).hidden) r] : rows;

// ═════════════════════════════════════════════════════════════════════════════
//  Numerals
// ═════════════════════════════════════════════════════════════════════════════

/// Digits of the printed text. The app shows Western digits everywhere (D-102); an Arabic export may ask for
/// Arabic-Indic ones. Excel numbers stay real numbers (the reader's Excel decides how it draws them); only text
/// cells change there.
enum ExportNumerals {
  western,
  arabic;

  static ExportNumerals parse(Object? v) => '$v' == 'arabic' ? arabic : western;
}

const _arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// [s] with 0-9 turned into ٠-٩ (and the percent sign into ٪) for [ExportNumerals.arabic]; unchanged otherwise.
String exportDigits(String s, ExportNumerals n) {
  if (n == ExportNumerals.western || s.isEmpty) return s;
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30 && r <= 0x39) {
      b.write(_arabicDigits[r - 0x30]);
    } else if (r == 0x25) {
      b.write('٪');
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// The numeral style of [lang] from a per-language map (`{"ar": "arabic"}`); English is always Western.
ExportNumerals exportNumeralsFor(String lang, Map<String, String> prefs) =>
    lang == 'ar' ? ExportNumerals.parse(prefs['ar']) : ExportNumerals.western;

// ═════════════════════════════════════════════════════════════════════════════
//  Excel studio options
// ═════════════════════════════════════════════════════════════════════════════

const xlsxNumberFormats = ['auto', '#,##0.00', '#,##0', '0.00'];
const xlsxDateFormats = ['yyyy-mm-dd', 'dd/mm/yyyy', 'd mmm yyyy'];

/// The Excel studio: a table-oriented sheet. Keys follow the server's render options
/// (services/export_render.py) so a scheduled run of the template looks the same.
class XlsxSheetOptions {
  XlsxSheetOptions({
    this.titleRow = true,
    this.title = '',
    this.freezeHeader = true,
    this.striping = true,
    this.stripeColor = 'F6F8FA',
    this.borders = true,
    this.borderColor = 'D7DDE3',
    this.headerColor = '',
    this.headerFontColor = '',
    this.headerBold = true,
    this.fontSize = 10,
    Map<String, double>? widths,
    this.numberFormat = 'auto',
    this.dateFormat = 'yyyy-mm-dd',
    this.rtl,
    this.logoUrl = '',
    this.font = '',
    ExportWatermark? watermark,
  })  : widths = widths ?? {},
        watermark = watermark ?? ExportWatermark();

  /// The title band (title, then a line with the organization · date · rows) above the header row.
  bool titleRow;

  /// The title text ({{variables}} allowed); empty = the export's title.
  String title;
  bool freezeHeader, striping, borders, headerBold;

  /// RRGGBB. [headerColor] empty = the brand colour; [headerFontColor] empty = white / ink, whichever reads better.
  String stripeColor, borderColor, headerColor, headerFontColor;
  double fontSize;

  /// Column id → width in characters (Excel units); missing = measured from the content.
  final Map<String, double> widths;

  /// One of [xlsxNumberFormats] ('auto' = by column type) and [xlsxDateFormats].
  String numberFormat, dateFormat;

  /// Right-to-left sheet; null = by language (Arabic → RTL).
  bool? rtl;

  /// A logo drawn at the top corner of the title band (an uploaded image URL).
  String logoUrl;

  /// The sheet's font: a catalog id (export_fonts.dart), '' = Arial. Excel cannot embed fonts — the file names it
  /// and the reader's Excel draws it when installed.
  String font;

  /// Printed behind the sheet as a header picture (export_watermark.dart).
  final ExportWatermark watermark;

  bool rtlFor(String lang) => rtl ?? lang == 'ar';

  factory XlsxSheetOptions.fromJson(Map<String, dynamic> j) {
    double d(Object? v, double or) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? or;
    final w = j['widths'];
    return XlsxSheetOptions(
      titleRow: j['title_row'] is bool ? j['title_row'] as bool : true,
      title: '${j['title'] ?? ''}',
      freezeHeader: j['freeze_header'] is bool ? j['freeze_header'] as bool : true,
      striping: j['striping'] is bool ? j['striping'] as bool : true,
      stripeColor: exportHex(j['stripe_color']) ?? 'F6F8FA',
      borders: j['borders'] is bool ? j['borders'] as bool : true,
      borderColor: exportHex(j['border_color']) ?? 'D7DDE3',
      headerColor: exportHex(j['header_color']) ?? '',
      headerFontColor: exportHex(j['header_font_color']) ?? '',
      headerBold: j['header_bold'] is bool ? j['header_bold'] as bool : true,
      fontSize: d(j['font_size'], 10).clamp(7, 20).toDouble(),
      widths: {
        if (w is Map)
          for (final e in w.entries)
            if (d(e.value, 0) > 0) '${e.key}': d(e.value, 0).clamp(4, 120).toDouble(),
      },
      numberFormat: xlsxNumberFormats.contains(j['number_format']) ? '${j['number_format']}' : 'auto',
      dateFormat: xlsxDateFormats.contains(j['date_format']) ? '${j['date_format']}' : 'yyyy-mm-dd',
      rtl: j['rtl'] is bool ? j['rtl'] as bool : null,
      logoUrl: '${j['logo_url'] ?? ''}',
      font: '${j['font'] ?? ''}',
      watermark: j['watermark'] is Map ? ExportWatermark.fromJson((j['watermark'] as Map).cast<String, dynamic>()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'title_row': titleRow,
        if (title.trim().isNotEmpty) 'title': title,
        'freeze_header': freezeHeader,
        'striping': striping,
        'stripe_color': '#$stripeColor',
        'borders': borders,
        'border_color': '#$borderColor',
        if (headerColor.isNotEmpty) 'header_color': '#$headerColor',
        if (headerFontColor.isNotEmpty) 'header_font_color': '#$headerFontColor',
        'header_bold': headerBold,
        'font_size': fontSize,
        if (widths.isNotEmpty) 'widths': widths,
        if (numberFormat != 'auto') 'number_format': numberFormat,
        'date_format': dateFormat,
        'datetime_format': '$dateFormat hh:mm',
        'rtl': ?rtl,
        if (logoUrl.isNotEmpty) 'logo_url': logoUrl,
        if (font.isNotEmpty) 'font': font,
        if (watermark.visible) 'watermark': watermark.toJson(),
      };

  XlsxSheetOptions copy() => XlsxSheetOptions.fromJson(toJson());
}

/// A template's `options`: the sheet options plus what the flow chose — group-by, the totals row, numerals per
/// language and the starter theme it came from. `totals` is also written as the list of aggregated column keys
/// (the server's renderer reads that list).
class ExportTemplateOptions {
  ExportTemplateOptions({XlsxSheetOptions? sheet, this.groupBy, this.showTotals = true, Map<String, String>? numerals, this.theme = 'standard', Map<String, String>? fonts})
      : sheet = sheet ?? XlsxSheetOptions(),
        numerals = numerals ?? {},
        fonts = fonts ?? {};

  final XlsxSheetOptions sheet;
  /// The group column; '' = "No grouping" chosen on purpose, null = not chosen (the page's default applies).
  String? groupBy;
  bool showTotals;
  final Map<String, String> numerals;

  /// standard | clean | formal | colorful
  String theme;

  /// Per language: the file's catalog font (export_fonts.dart). The server's renderer ignores it (it prints with
  /// its own font), the app applies it.
  final Map<String, String> fonts;

  factory ExportTemplateOptions.fromJson(Map<String, dynamic> j) => ExportTemplateOptions(
        sheet: XlsxSheetOptions.fromJson(j),
        // '' = "No grouping" saved on purpose (it clears the page's default group); a missing key = not chosen
        groupBy: j.containsKey('group_by') ? '${j['group_by'] ?? ''}' : null,
        showTotals: j['show_totals'] is bool ? j['show_totals'] as bool : (j['totals'] is List ? (j['totals'] as List).isNotEmpty : true),
        numerals: {
          if (j['numerals'] is Map)
            for (final e in (j['numerals'] as Map).entries) '${e.key}': ExportNumerals.parse(e.value).name,
        },
        theme: const ['standard', 'clean', 'formal', 'colorful'].contains(j['theme']) ? '${j['theme']}' : 'standard',
        fonts: exportFontPrefs(j['fonts']),
      );

  /// [totalKeys]: the exported columns that aggregate (written when [showTotals]).
  Map<String, dynamic> toJson({List<String> totalKeys = const []}) => {
        ...sheet.toJson(),
        'group_by': ?groupBy,
        'show_totals': showTotals,
        'totals': showTotals ? totalKeys : const <String>[],
        if (numerals.isNotEmpty) 'numerals': numerals,
        'theme': theme,
        if (fonts.isNotEmpty) 'fonts': fonts,
      };
}

/// A per-language font map (`{"ar": "amiri", "en": "playfair"}`) from JSON: only ar / en keys and plausible ids
/// (lower-case letters, digits, '_'); an id the catalog lacks falls back to Tajawal when it is used.
Map<String, String> exportFontPrefs(Object? raw) => {
      if (raw is Map)
        for (final e in raw.entries)
          if ((e.key == 'ar' || e.key == 'en') && RegExp(r'^[a-z0-9_]{1,40}$').hasMatch('${e.value}')) '${e.key}': '${e.value}',
    };

// ═════════════════════════════════════════════════════════════════════════════
//  File names and page keys
// ═════════════════════════════════════════════════════════════════════════════

String _two(int n) => n.toString().padLeft(2, '0');

/// `<title>_<yyyy-MM-dd>.<ext>` (`_<lang>` before the extension when one export writes two languages). The date
/// is today in the platform / organization timezone; characters a file system refuses become `_`.
String exportFileName(String title, String ext, {DateTime? now, String? lang}) {
  var t = title.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'^[._ ]+|[._ ]+$'), '');
  if (t.isEmpty) t = 'export';
  if (t.length > 80) t = t.substring(0, 80).trim();
  final utc = (now ?? DateTime.now()).toUtc();
  DateTime wall;
  try {
    wall = AppTime.toZone(utc);
  } catch (_) {
    wall = utc.toLocal();
  }
  final date = '${wall.year}-${_two(wall.month)}-${_two(wall.day)}';
  return '${t}_$date${lang == null ? '' : '_$lang'}.$ext';
}

/// The server's page_key for an export id (`^[a-z0-9][a-z0-9_.:/-]{0,79}$`): lower case, anything else → `_`.
String exportPageKey(String id) {
  var k = id.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.:/-]'), '_');
  k = k.replaceFirst(RegExp(r'^[^a-z0-9]+'), '');
  if (k.isEmpty) k = 'export';
  return k.length > 80 ? k.substring(0, 80) : k;
}

/// [s] as a left-to-right isolate (LRI … PDI): a file name or "24 KB" keeps its order inside Arabic text
/// ("الطلاب_2026-10-31.xlsx", not "xlsx.31-10-2026_الطلاب"; "5 KB", not "KB 5").
String exportLtr(String s) => '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}';

/// "24 KB" / "1.2 MB" for a byte count.
String exportSizeLabel(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
