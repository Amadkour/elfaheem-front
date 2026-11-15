// lib/design/export_hub/export_design.dart
//
// The Export Hub's pure model (no Flutter widgets — unit-tested in test/export/export_hub_test.dart):
//   ExportDesign    the design document of docs/backend/governance-spec.md §7 (page, font, header / footer,
//                   table, votes, blocks) — fromJson / toJson / copy, clamping, the standard presets
//   ExportBlock     one block: text · logo · signature · table · items · line, at page fractions like the
//                   complaints report designer (org_reports/report_model.dart)
//   ExportDataset   what the server's `GET …/governance/export/data` returns (or a table turned into one)
//   ExportContent   what the person wants in the file (vote results, decisions, notes, audit, columns, languages)
//   fillPlaceholders
//
// Blocks sit at (x, y, w, h) as fractions of the content box. The flow blocks (`table`, `items`) split the page:
// the blocks above the first flow block print before it, the blocks between two flow blocks print between them,
// the rest after the last one — so long content spans pages without covering a signature.
library;

import 'dart:math' as math;

import 'package:flutter_education_app/core/app_time.dart';

import '../../features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../export/export_fonts.dart' show ExportFonts;
import '../export/export_watermark.dart';

export '../export/export_watermark.dart';
import '../export/export_studio_model.dart' show ExportNumerals, ExportRule;
import '../export/table_export_model.dart' show AppColType, AppExportColumn, AppTableExport, AppTotal, cellText;

// ═════════════════════════════════════════════════════════════════════════════
//  Vocabularies
// ═════════════════════════════════════════════════════════════════════════════

const exportBlockKinds = ['text', 'logo', 'signature', 'table', 'items', 'line'];
const exportFlowKinds = ['table', 'items'];
const exportPageSizes = ['A4', 'Letter', 'A3'];
/// Every font a design may name: the export font catalog (= the certificate studio's fonts + Bahij, IBM Plex).
List<String> get exportFontFamilies => ExportFonts.ids;
const exportTableStyles = ['grid', 'zebra', 'minimal'];
const exportVotePositions = ['beside', 'below', 'both'];
const exportVoteStyles = ['bar', 'pill', 'text'];
const exportModules = ['items', 'complaints', 'requests', 'council', 'minutes', 'grades', 'table'];

Map<String, String> exportFontLabels([String lang = 'ar']) => {for (final f in ExportFonts.sortedFor(lang)) f.id: f.label};

Map<String, String> exportBlockLabels() => {
      'text': t('نص', 'Text'),
      'logo': t('شعار', 'Logo'),
      'signature': t('توقيع', 'Signature'),
      'table': t('الجدول', 'Table'),
      'items': t('البنود', 'Items'),
      'line': t('خط', 'Line'),
    };

Map<String, String> exportTableStyleLabels() => {
      'grid': t('شبكة', 'Grid'),
      'zebra': t('صفوف متبادلة', 'Zebra'),
      'minimal': t('بسيط', 'Minimal'),
    };

Map<String, String> exportVotePositionLabels() => {
      'beside': t('بجانب البند', 'Beside the item'),
      'below': t('تحت البند', 'Below the item'),
      'both': t('بجانبه وتحته', 'Beside and below'),
    };

Map<String, String> exportVoteStyleLabels() => {
      'bar': t('شريط', 'Bar'),
      'pill': t('شارة', 'Pill'),
      'text': t('نص', 'Text'),
    };

Map<String, String> exportVoteOutcomeLabels() => {
      'approved': t('موافقة', 'Approved'),
      'rejected': t('رفض', 'Rejected'),
      'tied': t('تعادل', 'Tied'),
      'no_quorum': t('لا نصاب', 'No quorum'),
      'postponed': t('مؤجل', 'Postponed'),
      'pending': t('قيد التصويت', 'Pending'),
    };

/// The placeholders every text block understands (label per key; `meta.<key>` comes from the dataset).
Map<String, String> exportPlaceholderLabels() => {
      'org': t('اسم المؤسسة', 'Organization name'),
      'dept': t('اسم الجهة', 'Department name'),
      'title': t('العنوان', 'Title'),
      'period': t('الفترة', 'Period'),
      'date': t('تاريخ الإصدار', 'Date'),
      'count': t('عدد العناصر', 'Number of items'),
      'signer': t('اسم الموقّع', 'Signer name'),
      'session': t('الجلسة', 'Session'),
      'council': t('المجلس', 'Council'),
      'session_date': t('تاريخ الجلسة', 'Session date'),
      'page': t('رقم الصفحة', 'Page number'),
      'pages': t('عدد الصفحات', 'Page count'),
      'org_name': t('اسم المؤسسة', 'Organization name'),
      'rows': t('عدد الصفوف', 'Number of rows'),
      'exporter': t('اسم المُصدِّر', 'Exported by'),
    };

/// The header / footer variables of the Export Studio (the server fills the same names in scheduled runs).
const exportStudioVariables = ['org_name', 'date', 'page', 'pages', 'rows', 'exporter'];

final _ph = RegExp(r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_.]*)\s*\}\}');

/// Replaces {{key}} with values[key]; unknown keys are left as they are (a typo stays visible).
String fillPlaceholders(String text, Map<String, String> values) =>
    text.replaceAllMapped(_ph, (m) => values[m.group(1)!] ?? m.group(0)!);

// ═════════════════════════════════════════════════════════════════════════════
//  Small helpers
// ═════════════════════════════════════════════════════════════════════════════

double _d(Object? v, double or) => v is num ? v.toDouble() : double.tryParse('$v') ?? or;

bool _b(Object? v, bool or) => v is bool ? v : or;

String _pick(Object? v, List<String> allowed, String or) => allowed.contains(v) ? '$v' : or;

/// "#1E293B" / "1e293b" / "#FF1E293B" → "1E293B"; anything else → [or].
String hexOf(Object? v, String or) {
  var s = '${v ?? ''}'.replaceAll('#', '').trim().toUpperCase();
  if (s.length == 8) s = s.substring(2);
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(s) ? s : or;
}

/// Colour as the JSON stores it ("#RRGGBB").
String hexJson(String hex) => '#$hex';

const exportInk = '1E293B', exportMuted = '64748B', exportLine = 'CBD5E1', exportBrand = '0F766E';

// ═════════════════════════════════════════════════════════════════════════════
//  Design
// ═════════════════════════════════════════════════════════════════════════════

/// A font override of one block (empty family = the page font).
class BlockFont {
  BlockFont({this.family = '', this.size = 11, this.weight = 'normal', this.color = ''});

  String family;
  double size;

  /// normal | bold
  String weight;

  /// RRGGBB, empty = the page colour.
  String color;

  bool get bold => weight == 'bold';

  factory BlockFont.fromJson(Map<String, dynamic> j, {double size = 11}) => BlockFont(
        family: _pick(j['family'], exportFontFamilies, ''),
        size: _d(j['size'], size).clamp(5, 60).toDouble(),
        weight: _pick(j['weight'], const ['normal', 'bold'], 'normal'),
        color: j['color'] == null || '${j['color']}'.isEmpty ? '' : hexOf(j['color'], ''),
      );

  Map<String, dynamic> toJson() => {'family': family, 'size': size, 'weight': weight, 'color': color.isEmpty ? '' : hexJson(color)};

  BlockFont copy() => BlockFont(family: family, size: size, weight: weight, color: color);
}

class ExportBlock {
  ExportBlock({
    required this.id,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.w = 1,
    this.h = .06,
    this.text = '',
    BlockFont? font,
    this.align = 'start',
    this.url = '',
    this.name = '',
    this.title = '',
    this.color = '',
    this.background = '',
  }) : font = font ?? BlockFont();

  final String id, kind;
  double x, y, w, h;

  /// text block: the text with {{placeholders}}.
  String text;
  BlockFont font;

  /// start | center | end (reading-direction aware).
  String align;

  /// logo / signature: image URL (optional for a signature).
  String url;

  /// signature: the name line (placeholders allowed) and the title under it.
  String name, title;

  /// line: RRGGBB (empty = the page's line colour).
  String color;

  /// text / signature / logo: a fill behind the block (RRGGBB, empty = none).
  String background;

  bool get isFlow => exportFlowKinds.contains(kind);
  bool get isImage => kind == 'logo' || kind == 'signature';

  factory ExportBlock.fromJson(Map<String, dynamic> j, {double baseSize = 11}) => ExportBlock(
        id: '${j['id'] ?? ''}',
        kind: _pick(j['kind'], exportBlockKinds, 'text'),
        x: _d(j['x'], 0),
        y: _d(j['y'], 0),
        w: _d(j['w'], 1),
        h: _d(j['h'], .06),
        text: '${j['text'] ?? ''}',
        font: BlockFont.fromJson(asMap(j['font']), size: baseSize),
        align: _pick(j['align'], const ['start', 'center', 'end'], 'start'),
        url: '${j['url'] ?? ''}',
        name: '${j['name'] ?? ''}',
        title: '${j['title'] ?? ''}',
        color: j['color'] == null || '${j['color']}'.isEmpty ? '' : hexOf(j['color'], ''),
        background: j['background'] == null || '${j['background']}'.isEmpty ? '' : hexOf(j['background'], ''),
      )..clamp();

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        if (kind == 'text') 'text': text,
        if (kind == 'text' || kind == 'signature') 'font': font.toJson(),
        if (!isFlow && kind != 'line') 'align': align,
        if (isImage) 'url': url,
        if (kind == 'signature') ...{'name': name, 'title': title},
        if (kind == 'line') 'color': color.isEmpty ? '' : hexJson(color),
        if (!isFlow && kind != 'line' && background.isNotEmpty) 'background': hexJson(background),
      };

  ExportBlock copy() => ExportBlock.fromJson(toJson(), baseSize: font.size);

  /// Keeps the block inside the page.
  void clamp() {
    final minH = kind == 'line' ? .002 : .02;
    w = w.clamp(.06, 1).toDouble();
    h = h.clamp(minH, .8).toDouble();
    x = x.clamp(0, 1 - w).toDouble();
    y = y.clamp(0, 1 - h).toDouble();
  }

  /// Rounds the position to the designer's 2 % grid.
  void snap([double grid = .02]) {
    x = (x / grid).round() * grid;
    y = (y / grid).round() * grid;
    clamp();
  }
}

class ExportPage {
  ExportPage({this.size = 'A4', this.orientation = 'portrait', this.top = 16, this.right = 16, this.bottom = 16, this.left = 16});

  String size, orientation;

  /// Margins in millimetres.
  double top, right, bottom, left;

  bool get landscape => orientation == 'landscape';

  /// Paper (width, height) in millimetres, orientation applied.
  (double, double) get mm {
    final (w, h) = switch (size) { 'Letter' => (215.9, 279.4), 'A3' => (297.0, 420.0), _ => (210.0, 297.0) };
    return landscape ? (h, w) : (w, h);
  }

  /// Content box (width, height) in millimetres.
  (double, double) get contentMm {
    final (w, h) = mm;
    return (math.max(20, w - left - right), math.max(20, h - top - bottom));
  }

  factory ExportPage.fromJson(Map<String, dynamic> j) {
    final m = asMap(j['margins']);
    double mg(String k) => _d(m[k], 16).clamp(0, 60).toDouble();
    return ExportPage(
      size: _pick(j['size'], exportPageSizes, 'A4'),
      orientation: _pick(j['orientation'], const ['portrait', 'landscape'], 'portrait'),
      top: mg('top'),
      right: mg('right'),
      bottom: mg('bottom'),
      left: mg('left'),
    );
  }

  Map<String, dynamic> toJson() => {
        'size': size,
        'orientation': orientation,
        'margins': {'top': top, 'right': right, 'bottom': bottom, 'left': left},
      };
}

class ExportTableStyle {
  ExportTableStyle({this.style = 'zebra', this.headerColor = exportBrand, this.headerTextColor = 'FFFFFF', this.fontSize = 10, List<String>? columns, Map<String, double>? widths})
      : columns = columns ?? [],
        widths = widths ?? {};

  String style, headerColor, headerTextColor;
  double fontSize;

  /// Column ids printed, in order. Empty = every dataset column.
  List<String> columns;

  /// Column id → relative width; a missing column gets export_layout.exportColumnWeight. Empty = all automatic.
  final Map<String, double> widths;

  factory ExportTableStyle.fromJson(Map<String, dynamic> j) => ExportTableStyle(
        style: _pick(j['style'], exportTableStyles, 'zebra'),
        headerColor: hexOf(j['header_color'], exportBrand),
        headerTextColor: hexOf(j['header_text_color'], 'FFFFFF'),
        fontSize: _d(j['font_size'], 10).clamp(5, 24).toDouble(),
        columns: [for (final c in (j['columns'] as List? ?? const [])) '$c'],
        widths: {
          if (j['widths'] is Map)
            for (final e in (j['widths'] as Map).entries)
              if (_d(e.value, 0) > 0) '${e.key}': _d(e.value, 0).clamp(.05, 100).toDouble(),
        },
      );

  Map<String, dynamic> toJson() => {
        'style': style,
        'header_color': hexJson(headerColor),
        'header_text_color': hexJson(headerTextColor),
        'font_size': fontSize,
        'columns': columns,
        if (widths.isNotEmpty) 'widths': widths,
      };
}

class ExportVotes {
  ExportVotes({this.position = 'below', this.showCounts = true, this.showPercent = true, this.showOutcome = true, this.showVoters = false, this.style = 'bar'});

  String position, style;
  bool showCounts, showPercent, showOutcome, showVoters;

  bool get beside => position == 'beside' || position == 'both';
  bool get below => position == 'below' || position == 'both';

  factory ExportVotes.fromJson(Map<String, dynamic> j) => ExportVotes(
        position: _pick(j['position'], exportVotePositions, 'below'),
        showCounts: _b(j['show_counts'], true),
        showPercent: _b(j['show_percent'], true),
        showOutcome: _b(j['show_outcome'], true),
        showVoters: _b(j['show_voters'], false),
        style: _pick(j['style'], exportVoteStyles, 'bar'),
      );

  Map<String, dynamic> toJson() => {
        'position': position,
        'show_counts': showCounts,
        'show_percent': showPercent,
        'show_outcome': showOutcome,
        'show_voters': showVoters,
        'style': style,
      };
}

const exportFrameStyles = ['none', 'solid', 'dashed', 'double'];

/// A border drawn around every page: [inset] millimetres outside the content box (inside the margins).
class ExportFrame {
  ExportFrame({this.style = 'none', this.width = 1, this.color = exportLine, this.radius = 0, this.inset = 4});

  /// none | solid | dashed | double
  String style;

  /// Line width and corner radius in points (Word draws square corners: page borders have no radius).
  double width, radius;
  String color;

  /// Millimetres between the content box and the frame.
  double inset;

  bool get visible => style != 'none' && width > 0;

  factory ExportFrame.fromJson(Map<String, dynamic> j) => ExportFrame(
        style: _pick(j['style'], exportFrameStyles, 'none'),
        width: _d(j['width'], 1).clamp(.25, 12).toDouble(),
        color: hexOf(j['color'], exportLine),
        radius: _d(j['radius'], 0).clamp(0, 40).toDouble(),
        inset: _d(j['inset'], 4).clamp(0, 30).toDouble(),
      );

  Map<String, dynamic> toJson() => {'style': style, 'width': width, 'color': hexJson(color), 'radius': radius, 'inset': inset};
}

/// One print area: [blocks] (static, top to bottom) followed by [flow] (the table / items block, or null at the end).
class ExportSegment {
  const ExportSegment(this.blocks, this.flow, this.top);
  final List<ExportBlock> blocks;
  final ExportBlock? flow;

  /// The y fraction this segment starts at (0 for the first).
  final double top;

  /// Bottom of the static blocks (fraction), or [top] when there are none.
  double get blocksBottom => blocks.isEmpty ? top : blocks.map((b) => b.y + b.h).reduce(math.max);
}

class ExportDesign {
  ExportDesign({
    ExportPage? page,
    this.rtl = true,
    this.fontFamily = 'tajawal',
    this.fontSize = 11,
    this.fontColor = exportInk,
    this.lineSpacing = 1.3,
    this.headerText = '',
    this.showPageNumbers = true,
    this.showDate = true,
    this.footerText = '',
    ExportTableStyle? table,
    ExportVotes? votes,
    List<ExportBlock>? blocks,
    ExportFrame? frame,
    ExportWatermark? watermark,
  })  : page = page ?? ExportPage(),
        table = table ?? ExportTableStyle(),
        votes = votes ?? ExportVotes(),
        blocks = blocks ?? [],
        frame = frame ?? ExportFrame(),
        watermark = watermark ?? ExportWatermark();

  static const version = 2;

  final ExportPage page;
  bool rtl;

  /// A catalog font id (export_fonts.dart) — the page font (blocks may override the family).
  String fontFamily;
  double fontSize, lineSpacing;
  String fontColor;
  String headerText, footerText;
  bool showPageNumbers, showDate;
  final ExportTableStyle table;
  final ExportVotes votes;
  final List<ExportBlock> blocks;

  /// The page border and the watermark (additive keys of schema v2: an older app ignores them).
  final ExportFrame frame;
  final ExportWatermark watermark;

  String get lang => rtl ? 'ar' : 'en';

  ExportBlock? get tableBlock => blocks.where((b) => b.kind == 'table').firstOrNull;
  ExportBlock? get itemsBlock => blocks.where((b) => b.kind == 'items').firstOrNull;

  /// The flow blocks, top to bottom.
  List<ExportBlock> get flows => _sorted(blocks.where((b) => b.isFlow));

  /// Static blocks above the first flow block (every block when there is none).
  List<ExportBlock> get before {
    final f = flows;
    return _sorted(blocks.where((b) => !b.isFlow && (f.isEmpty || b.y < f.first.y)));
  }

  /// Static blocks at or below the last flow block.
  List<ExportBlock> get after {
    final f = flows;
    return f.isEmpty ? [] : _sorted(blocks.where((b) => !b.isFlow && b.y >= f.last.y));
  }

  /// The page as print areas: static blocks, then a flow block, … , then the static blocks after the last flow.
  List<ExportSegment> get segments {
    final f = flows;
    final statics = _sorted(blocks.where((b) => !b.isFlow));
    final out = <ExportSegment>[];
    var top = 0.0;
    var rest = statics;
    for (final flow in f) {
      final mine = rest.where((b) => b.y < flow.y).toList();
      rest = rest.where((b) => b.y >= flow.y).toList();
      out.add(ExportSegment(mine, flow, top));
      top = flow.y;
    }
    out.add(ExportSegment(rest, null, rest.isEmpty ? top : rest.first.y));
    return out;
  }

  static List<ExportBlock> _sorted(Iterable<ExportBlock> it) => it.toList()..sort((a, b) => a.y.compareTo(b.y));

  String nextId() {
    var n = blocks.length + 1;
    while (blocks.any((b) => b.id == 'b$n')) {
      n++;
    }
    return 'b$n';
  }

  /// Adds a block of [kind] at a sensible place (one table / items block only — the existing one is returned).
  ExportBlock add(String kind) {
    if (kind == 'table' && tableBlock != null) return tableBlock!;
    if (kind == 'items' && itemsBlock != null) return itemsBlock!;
    final b = switch (kind) {
      'table' || 'items' => ExportBlock(id: nextId(), kind: kind, x: 0, y: .3, w: 1, h: .4),
      'logo' => ExportBlock(id: nextId(), kind: kind, x: .4, y: .02, w: .2, h: .08, align: 'center'),
      'signature' => ExportBlock(
          id: nextId(), kind: kind, x: rtl ? 0 : .66, y: .82, w: .34, h: .12, name: '{{signer}}', title: '', align: 'center', font: BlockFont(size: fontSize)),
      'line' => ExportBlock(id: nextId(), kind: kind, x: 0, y: .25, w: 1, h: .004, color: exportLine),
      _ => ExportBlock(id: nextId(), kind: 'text', x: .1, y: .2, w: .8, h: .05, text: t('نص جديد', 'New text'), font: BlockFont(size: fontSize)),
    };
    blocks.add(b..clamp());
    return b;
  }

  void remove(String id) => blocks.removeWhere((b) => b.id == id);

  factory ExportDesign.fromJson(Map<String, dynamic> j) {
    final font = asMap(j['font']);
    final header = asMap(j['header']), footer = asMap(j['footer']);
    final size = _d(font['size'], 11).clamp(6, 30).toDouble();
    return ExportDesign(
      page: ExportPage.fromJson(asMap(j['page'])),
      rtl: _b(j['rtl'], true),
      fontFamily: _pick(font['family'], exportFontFamilies, 'tajawal'),
      fontSize: size,
      fontColor: hexOf(font['color'], exportInk),
      lineSpacing: _d(font['line_spacing'], 1.3).clamp(1, 2.5).toDouble(),
      headerText: '${header['text'] ?? ''}',
      showPageNumbers: _b(header['show_page_numbers'], true),
      showDate: _b(header['show_date'], true),
      footerText: '${footer['text'] ?? ''}',
      table: ExportTableStyle.fromJson(asMap(j['table'])),
      votes: ExportVotes.fromJson(asMap(j['votes'])),
      blocks: [for (final b in asMapList(j['blocks'])) ExportBlock.fromJson(b, baseSize: size)],
      frame: ExportFrame.fromJson(asMap(j['frame'])),
      watermark: ExportWatermark.fromJson(asMap(j['watermark'])),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'page': page.toJson(),
        'rtl': rtl,
        'font': {'family': fontFamily, 'size': fontSize, 'color': hexJson(fontColor), 'line_spacing': lineSpacing},
        'header': {'text': headerText, 'show_page_numbers': showPageNumbers, 'show_date': showDate},
        'footer': {'text': footerText},
        'table': table.toJson(),
        'votes': votes.toJson(),
        'blocks': [for (final b in blocks) b.toJson()],
        if (frame.visible) 'frame': frame.toJson(),
        if (watermark.visible) 'watermark': watermark.toJson(),
      };

  ExportDesign copy() => ExportDesign.fromJson(toJson());

  /// The font families the design uses (page + overrides).
  Set<String> get fontFamilies => {fontFamily, for (final b in blocks) if (b.font.family.isNotEmpty) b.font.family};

  /// The ready layouts per module and language. Arabic and English are different layouts, not mirrors:
  /// the Arabic letter is the formal centred letterhead (logo on top, organization and department under it);
  /// the English one is a left-aligned business header (logo and organization side by side, a rule, the date on
  /// the right). Council / minutes presets add the items block and two signatures (chair + secretary).
  factory ExportDesign.standard(String module, String lang) {
    final ar = lang == 'ar';
    final council = module == 'council' || module == 'minutes';
    final minutes = module == 'minutes';
    BlockFont f(double size, {bool bold = false, String color = ''}) => BlockFont(size: size, weight: bold ? 'bold' : 'normal', color: color);
    final blocks = <ExportBlock>[];
    if (ar) {
      blocks.addAll([
        ExportBlock(id: 'b1', kind: 'logo', x: .4, y: 0, w: .2, h: .08, align: 'center'),
        ExportBlock(id: 'b2', kind: 'text', x: 0, y: .09, w: 1, h: .035, text: '{{org}}', font: f(14, bold: true), align: 'center'),
        ExportBlock(id: 'b3', kind: 'text', x: 0, y: .125, w: 1, h: .03, text: council ? '{{council}}' : '{{dept}}', font: f(11, color: exportMuted), align: 'center'),
        ExportBlock(id: 'b4', kind: 'line', x: .2, y: .162, w: .6, h: .003, color: exportLine),
        ExportBlock(id: 'b5', kind: 'text', x: 0, y: .175, w: 1, h: .04, text: minutes ? 'محضر {{session}}' : '{{title}}', font: f(16, bold: true), align: 'center'),
        if (council)
          ExportBlock(id: 'b6', kind: 'text', x: 0, y: .22, w: 1, h: .03, text: '{{session}} · تاريخ الانعقاد: {{session_date}} · عدد البنود: {{count}}', font: f(10), align: 'center')
        else ...[
          ExportBlock(id: 'b6', kind: 'text', x: .35, y: .22, w: .65, h: .03, text: 'الفترة: {{period}} · العدد: {{count}}', font: f(10), align: 'start'),
          ExportBlock(id: 'b7', kind: 'text', x: 0, y: .22, w: .33, h: .03, text: 'التاريخ: {{date}}', font: f(10), align: 'end'),
        ],
        ExportBlock(id: 'b8', kind: council ? 'items' : 'table', x: 0, y: .27, w: 1, h: .45),
        // D-974: the official minutes print the attendance groups and the named chair + secretary
        if (minutes) ExportBlock(id: 'b11', kind: 'text', x: 0, y: .73, w: 1, h: .06, text: '{{attendance}}', font: f(9), align: 'start'),
        ExportBlock(id: 'b9', kind: 'signature', x: 0, y: .8, w: .34, h: .12, name: minutes ? '{{chair}}' : '{{signer}}', title: council ? 'رئيس المجلس' : 'المسؤول', align: 'center', font: f(11)),
        if (council) ExportBlock(id: 'b10', kind: 'signature', x: .66, y: .8, w: .34, h: .12, name: minutes ? '{{secretary}}' : '', title: 'أمين المجلس', align: 'center', font: f(11)),
      ]);
    } else {
      blocks.addAll([
        ExportBlock(id: 'b1', kind: 'logo', x: 0, y: 0, w: .16, h: .07, align: 'start'),
        ExportBlock(id: 'b2', kind: 'text', x: .18, y: .005, w: .82, h: .03, text: '{{org}}', font: f(13, bold: true), align: 'start'),
        ExportBlock(id: 'b3', kind: 'text', x: .18, y: .038, w: .82, h: .03, text: council ? '{{council}}' : '{{dept}}', font: f(10, color: exportMuted), align: 'start'),
        ExportBlock(id: 'b4', kind: 'line', x: 0, y: .085, w: 1, h: .003, color: exportBrand),
        ExportBlock(id: 'b5', kind: 'text', x: 0, y: .1, w: .7, h: .04, text: minutes ? 'Minutes of {{session}}' : '{{title}}', font: f(18, bold: true), align: 'start'),
        ExportBlock(id: 'b6', kind: 'text', x: .7, y: .105, w: .3, h: .03, text: 'Date: {{date}}', font: f(10, color: exportMuted), align: 'end'),
        ExportBlock(
            id: 'b7',
            kind: 'text',
            x: 0,
            y: .145,
            w: 1,
            h: .03,
            text: council ? '{{session}} · held on {{session_date}} · {{count}} items' : 'Period: {{period}} · {{count}} items',
            font: f(10),
            align: 'start'),
        ExportBlock(id: 'b8', kind: council ? 'items' : 'table', x: 0, y: .19, w: 1, h: .5),
        if (minutes) ExportBlock(id: 'b11', kind: 'text', x: 0, y: .71, w: 1, h: .08, text: '{{attendance}}', font: f(9), align: 'start'),
        if (council) ExportBlock(id: 'b9', kind: 'signature', x: 0, y: .82, w: .34, h: .12, name: minutes ? '{{secretary}}' : '', title: 'Council secretary', align: 'start', font: f(11)),
        ExportBlock(id: 'b10', kind: 'signature', x: .66, y: .82, w: .34, h: .12, name: minutes ? '{{chair}}' : '{{signer}}', title: council ? 'Chair' : 'Authorized signature', align: 'end', font: f(11)),
      ]);
    }
    return ExportDesign(
      rtl: ar,
      fontFamily: ar ? 'tajawal' : 'plex',
      headerText: ar ? '{{org}} · {{title}}' : '{{title}} — {{org}}',
      footerText: ar ? 'صدر في {{date}}' : 'Generated on {{date}}',
      table: ExportTableStyle(style: ar ? 'zebra' : 'minimal', headerColor: ar ? exportBrand : '1E293B'),
      votes: ExportVotes(position: council && !minutes ? 'both' : 'below', style: minutes ? 'text' : 'bar', showVoters: minutes),
      blocks: blocks,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Dataset
// ═════════════════════════════════════════════════════════════════════════════

class ExportColumn {
  const ExportColumn(this.id, {this.labelAr = '', this.labelEn = '', this.type = 'text', this.total = 'none', this.currency = ''});
  final String id, labelAr, labelEn;

  /// text | number | integer | money | percent | date | datetime | status
  final String type;

  /// The aggregate of the totals / subtotal rows: none | sum | average | count | min | max.
  final String total;

  /// Money suffix ("EGP").
  final String currency;

  /// The table exporter's column for this one in [lang] (types, totals and formatting are shared with
  /// lib/design/export: groups, aggregates and cell text come from there).
  AppExportColumn toAppColumn(String lang, {String? label}) => AppExportColumn(
        id,
        label ?? this.label(lang),
        type: switch (type) {
          'number' => AppColType.number,
          'integer' || 'int' => AppColType.integer,
          'money' => AppColType.money,
          'percent' => AppColType.percent,
          'date' => AppColType.date,
          'datetime' || 'date_time' => AppColType.dateTime,
          'status' => AppColType.status,
          _ => AppColType.text,
        },
        total: AppTotal.values.where((x) => x.name == total).firstOrNull ?? AppTotal.none,
        currency: currency.isEmpty ? null : currency,
      );

  String label(String lang) {
    final a = labelAr.isEmpty ? labelEn : labelAr, e = labelEn.isEmpty ? labelAr : labelEn;
    final v = lang == 'ar' ? a : e;
    return v.isEmpty ? id : v;
  }

  bool get numeric => const ['number', 'integer', 'money', 'percent'].contains(type);

  factory ExportColumn.fromJson(Map<String, dynamic> j) => ExportColumn(
        '${j['id'] ?? ''}',
        labelAr: '${j['label_ar'] ?? j['label'] ?? ''}',
        labelEn: '${j['label_en'] ?? j['label'] ?? ''}',
        type: '${j['type'] ?? 'text'}'.toLowerCase(),
        total: '${j['total'] ?? 'none'}',
        currency: '${j['currency'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label_ar': labelAr,
        'label_en': labelEn,
        'type': type,
        if (total != 'none') 'total': total,
        if (currency.isNotEmpty) 'currency': currency,
      };
}

class ExportVoteResult {
  const ExportVoteResult({this.approve = 0, this.reject = 0, this.abstain = 0, this.eligible = 0, this.approvePct = 0, this.outcome = 'pending', this.voters = const []});
  final int approve, reject, abstain, eligible;
  final double approvePct;
  final String outcome;

  /// [{name, vote, note}] when the server sent the voters.
  final List<Map<String, dynamic>> voters;

  int get cast => approve + reject + abstain;

  factory ExportVoteResult.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final voters = [
      for (final v in asMapList(j['voters'] ?? j['votes']))
        {'name': '${asMap(v['user'])['name'] ?? v['name'] ?? ''}', 'vote': '${v['vote'] ?? ''}', 'note': '${v['note'] ?? ''}'},
    ];
    final approve = i(j['approve'] ?? j['approve_count']), reject = i(j['reject'] ?? j['reject_count']), abstain = i(j['abstain'] ?? j['abstain_count']);
    final pct = j['approve_pct'] is num ? (j['approve_pct'] as num).toDouble() : (approve + reject == 0 ? 0.0 : 100.0 * approve / (approve + reject));
    return ExportVoteResult(
      approve: approve,
      reject: reject,
      abstain: abstain,
      eligible: i(j['eligible'] ?? j['eligible_count']),
      approvePct: pct,
      outcome: '${j['outcome'] ?? 'pending'}',
      voters: voters,
    );
  }

  Map<String, dynamic> toJson() => {
        'approve': approve,
        'reject': reject,
        'abstain': abstain,
        'eligible': eligible,
        'approve_pct': approvePct,
        'outcome': outcome,
        if (voters.isNotEmpty) 'voters': voters,
      };

  String get percentText => '${approvePct == approvePct.roundToDouble() ? approvePct.toInt() : approvePct.toStringAsFixed(1)}%';
}

/// One council / agenda item of the dataset.
class ExportItem {
  const ExportItem({required this.item, this.votes, this.decision = '', this.notes = '', this.audit = const []});

  /// The item JSON (`ref`, `title`, `type`, `status`, `body`, `source`, `owner_dept`, `created_at`, …).
  final Map<String, dynamic> item;
  final ExportVoteResult? votes;
  final String decision, notes;

  /// [{kind, actor, body, created_at}] when the audit trail was included.
  final List<Map<String, dynamic>> audit;

  String get ref => '${item['ref'] ?? ''}';
  String get title => '${item['title'] ?? ''}';
  String get body => '${item['body'] ?? ''}';
  String get type => '${item['type'] ?? ''}';
  String get status => '${item['status'] ?? ''}';

  /// "Source dept · person" for the meta line.
  String source(String lang) {
    final s = asMap(item['source']);
    final d = asMap(s['dept']);
    final dept = lang == 'ar' ? '${d['name_ar'] ?? d['name_en'] ?? ''}' : '${d['name_en'] ?? d['name_ar'] ?? ''}';
    final user = '${asMap(s['user'])['name'] ?? ''}';
    return [dept, user].where((x) => x.isNotEmpty).join(' · ');
  }

  factory ExportItem.fromJson(Map<String, dynamic> j) {
    final d = j['decision'];
    return ExportItem(
      item: j['item'] is Map ? asMap(j['item']) : j,
      votes: j['votes'] is Map ? ExportVoteResult.fromJson(asMap(j['votes'])) : null,
      decision: d is Map ? '${d['outcome'] ?? ''}${(d['note'] ?? '').toString().isEmpty ? '' : ' — ${d['note']}'}' : '${d ?? ''}',
      notes: '${j['notes'] ?? ''}',
      audit: asMapList(j['audit']),
    );
  }

  Map<String, dynamic> toJson() => {'item': item, 'votes': votes?.toJson(), 'decision': decision, 'notes': notes, 'audit': audit};
}

/// The data one export prints: `GET …/governance/export/data`, or a table turned into one ([fromTable]).
class ExportDataset {
  ExportDataset({
    required this.module,
    required this.title,
    this.lang = 'ar',
    Map<String, dynamic>? meta,
    List<ExportColumn>? columns,
    List<Map<String, Object?>>? rows,
    List<ExportItem>? items,
    DateTime? generatedAt,
    this.id,
  })  : meta = meta ?? {},
        columns = columns ?? [],
        rows = rows ?? [],
        items = items ?? [],
        generatedAt = generatedAt ?? DateTime.now().toUtc();

  final String module, title, lang;

  /// `org`, `dept`, `period`, `count`, `signer`, `session`, `council`, `session_date`, … (the server's meta).
  final Map<String, dynamic> meta;
  final List<ExportColumn> columns;
  final List<Map<String, Object?>> rows;
  final List<ExportItem> items;
  final DateTime generatedAt;

  /// Stable id under which the hub remembers the last choice (defaults to the module).
  final String? id;

  String get prefId => id ?? module;
  bool get hasItems => items.isNotEmpty;
  bool get hasVotes => items.any((i) => i.votes != null);
  bool get hasDecisions => items.any((i) => i.decision.isNotEmpty) || rows.any((r) => r['decision'] != null);
  bool get hasNotes => items.any((i) => i.notes.isNotEmpty);
  bool get hasAudit => items.any((i) => i.audit.isNotEmpty);

  ExportColumn? column(String id) => columns.where((c) => c.id == id).firstOrNull;

  String labelFor(String colId, String lang) => column(colId)?.label(lang) ?? colId;

  /// The columns of [design] that exist in this dataset (every column when the design names none).
  List<ExportColumn> columnsFor(ExportDesign d, [List<String>? selected]) {
    final ids = selected ?? (d.table.columns.isEmpty ? null : d.table.columns);
    if (ids == null) return columns;
    final out = [for (final id in ids) ?column(id)];
    return out.isEmpty ? columns : out;
  }

  /// The printed text of a cell (numbers, dates and status values formatted like the table exporter).
  String cell(ExportColumn c, Object? v) {
    if (v == null) return '';
    final type = switch (c.type) {
      'number' => AppColType.number,
      'integer' || 'int' => AppColType.integer,
      'money' => AppColType.money,
      'percent' => AppColType.percent,
      'date' => AppColType.date,
      'datetime' || 'date_time' => AppColType.dateTime,
      _ => AppColType.text,
    };
    if (type == AppColType.text) return v is Map ? '${v['name'] ?? v['name_ar'] ?? v['title'] ?? ''}' : '$v';
    return cellText(AppExportColumn(c.id, c.label('en'), type: type), v);
  }

  /// The values every placeholder resolves to for [lang].
  Map<String, String> placeholderValues(String lang, {DateTime? now}) {
    String s(Object? v) => v == null ? '' : v is Map ? '${lang == 'ar' ? (v['name_ar'] ?? v['name'] ?? v['name_en']) : (v['name_en'] ?? v['name'] ?? v['name_ar']) ?? ''}' : '$v';
    final out = <String, String>{
      for (final e in meta.entries) 'meta.${e.key}': s(e.value),
      'org': s(meta['org']),
      'dept': s(meta['dept']),
      'title': title,
      'period': s(meta['period']),
      'date': _dateText(now ?? generatedAt, lang),
      'count': meta['count'] == null ? '${hasItems ? items.length : rows.length}' : s(meta['count']),
      'signer': s(meta['signer']),
      'session': s(meta['session']),
      'council': s(meta['council']),
      'session_date': meta['session_date'] == null ? '' : _dateText(DateTime.tryParse('${meta['session_date']}')?.toUtc(), lang),
      'page': '{{page}}',
      'pages': '{{pages}}',
      'org_name': s(meta['org']),
      'rows': '${meta['rows'] ?? rows.length}',
      'exporter': s(meta['exporter']),
      // D-974 official minutes (empty until the results are visible)
      'chair': s(meta['chair']),
      'secretary': s(meta['secretary']),
      'attendance': s(meta['attendance']),
      'session_no': s(meta['session_no']),
      'year': s(meta['year']),
    };
    if (out['session_date']!.isEmpty && meta['session_date'] != null) out['session_date'] = s(meta['session_date']);
    return out;
  }

  static String _dateText(DateTime? d, [String lang = 'en']) => exportDateText(d, lang);

  factory ExportDataset.fromJson(Map<String, dynamic> j) {
    final lang = '${j['lang'] ?? 'ar'}';
    final official = j['official'] is Map ? asMap(j['official']) : null;   // D-974, minutes only
    final items = [for (final i in asMapList(j['items'])) ExportItem.fromJson(i)];
    return ExportDataset(
      module: '${j['module'] ?? 'items'}',
      title: '${j['title'] ?? ''}',
      lang: lang,
      meta: {...asMap(j['meta']), if (official != null) ...exportOfficialMeta(official, lang)},
      columns: [for (final c in asMapList(j['columns'])) ExportColumn.fromJson(c)],
      rows: [for (final r in asMapList(j['rows'])) r.cast<String, Object?>()],
      items: official == null ? items : exportOfficialItems(items, official),
      generatedAt: DateTime.tryParse('${j['generated_at'] ?? ''}')?.toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'module': module,
        'title': title,
        'lang': lang,
        'generated_at': generatedAt.toIso8601String(),
        'meta': meta,
        'columns': [for (final c in columns) c.toJson()],
        'rows': rows,
        'items': [for (final i in items) i.toJson()],
      };

  /// A generic table (the AppTableExport sheet's "Design…" entry): columns keep their type, every row is kept,
  /// the brand becomes `org` and the info lines become `period`.
  factory ExportDataset.fromTable(AppTableExport e, {String module = 'table', String? exporter}) => ExportDataset(
        id: 'table.${e.id}',
        module: module,
        title: e.title,
        lang: e.rtl ? 'ar' : 'en',
        meta: {
          'org': e.brand ?? '',
          'dept': '',
          'period': e.infoLines.join(' · '),
          'count': e.rows.length,
          'signer': '',
          'exporter': exporter ?? '',
        },
        columns: [
          for (final c in e.columns)
            ExportColumn(c.id,
                labelAr: c.labelIn('ar'), labelEn: c.labelIn('en'), type: c.type.name.toLowerCase(), total: c.total.name, currency: c.currency ?? ''),
        ],
        rows: [
          for (final r in e.rows)
            {for (final c in e.columns) c.id: c.type == AppColType.status ? cellText(c, r[c.id]) : r[c.id]},
        ],
        generatedAt: e.generatedAt,
      );
}

/// The official minutes block (D-974, `official` of `GET …/export/data?module=minutes`) as placeholders: `chair`,
/// `secretary`, `session_no`, `year` and `attendance` (one line per group: voted · excused for a conflict of
/// interest · did not respond; the chair and the secretary are marked, a weight other than 1 is shown).
Map<String, dynamic> exportOfficialMeta(Map<String, dynamic> o, String lang) {
  final ar = lang != 'en';
  String name(dynamic p) => p is Map ? '${p['name'] ?? ''}' : '';
  String who(Map<String, dynamic> a) {
    final w = asInt(a['weight'], 1);
    final tags = [
      if (a['is_chair'] == true) ar ? 'رئيس المجلس' : 'chair',
      if (a['is_secretary'] == true) ar ? 'أمين المجلس' : 'secretary',
      if (w != 1) ar ? 'الوزن $w' : 'weight $w',
    ];
    return tags.isEmpty ? name(a) : '${name(a)} (${tags.join(ar ? '، ' : ', ')})';
  }

  final groups = <String, List<String>>{'voted': [], 'excused_coi': [], 'not_responded': []};
  for (final a in asMapList(o['attendance'])) {
    groups.putIfAbsent('${a['status']}', () => []).add(who(a));
  }
  const labels = {
    'voted': ('الحاضرون المصوّتون', 'Present and voting'),
    'excused_coi': ('المعتذرون لتعارض المصالح', 'Excused (conflict of interest)'),
    'not_responded': ('لم يردّوا', 'Did not respond'),
  };
  final lines = [
    for (final e in groups.entries)
      if (e.value.isNotEmpty) '${ar ? (labels[e.key]?.$1 ?? e.key) : (labels[e.key]?.$2 ?? e.key)}: ${e.value.join(ar ? '، ' : ', ')}',
  ];
  return {
    'chair': name(o['chair']),
    'secretary': name(o['secretary']),
    'session_no': o['session_no'] == null ? '' : '${o['session_no']}',
    'year': o['year'] == null ? '' : '${o['year']}',
    'attendance': lines.join('\n'),
  };
}

/// Each minutes row gets its official decision text ("قرار رقم 1/1/2026: موافقة") and `decision_no`, matched by
/// item id (else by position).
List<ExportItem> exportOfficialItems(List<ExportItem> items, Map<String, dynamic> o) {
  final rows = asMapList(o['items']);
  ExportItem one(int i) {
    final it = items[i];
    final id = it.item['id'];
    final row = rows.where((r) => id != null && '${r['item_id']}' == '$id').firstOrNull ?? (i < rows.length ? rows[i] : null);
    if (row == null) return it;
    final text = '${row['decision_text'] ?? ''}';
    final note = '${row['decision_note'] ?? ''}';
    return ExportItem(
      item: {...it.item, 'decision_no': row['decision_no']},
      votes: it.votes,
      decision: text.isEmpty ? it.decision : (note.isEmpty ? text : '$text — $note'),
      notes: it.notes,
      audit: it.audit,
    );
  }

  return [for (var i = 0; i < items.length; i++) one(i)];
}

// ═════════════════════════════════════════════════════════════════════════════
//  Content switches
// ═════════════════════════════════════════════════════════════════════════════

/// What the file holds: the switches of the hub sheet. [langs] is `ar` · `en` · `both` ("both" renders two
/// files, each from its own template); [lang] is the language of ONE rendering, resolved from the design.
class ExportContent {
  ExportContent({
    this.votes = true,
    this.decisions = true,
    this.notes = true,
    this.audit = false,
    this.columns,
    this.langs = 'both',
    List<ExportRule>? rules,
    this.numerals = ExportNumerals.western,
    this.groupBy,
    this.totals = false,
    Map<String, String>? labels,
  })  : rules = rules ?? [],
        labels = labels ?? {};

  bool votes, decisions, notes, audit;

  /// Column ids to print (null = the design's columns, else every dataset column).
  List<String>? columns;
  String langs;

  /// The Export Studio's table choices (not part of the content JSON — they belong to the template): conditional
  /// styling rules, the digits, a group-by column (each group gets a heading and, with [totals], a subtotal row),
  /// a totals row (the columns whose [ExportColumn.total] aggregates), and header overrides per column id in the
  /// rendering's language.
  List<ExportRule> rules;
  ExportNumerals numerals;
  String? groupBy;
  bool totals;
  Map<String, String> labels;

  List<String> get languages => langs == 'both' ? const ['ar', 'en'] : [langs];

  /// The language of a rendering with [d]: the design's own (a template is per language).
  String langFor(ExportDesign d) => d.lang;

  Map<String, dynamic> toJson() => {'votes': votes, 'decisions': decisions, 'notes': notes, 'audit': audit, 'columns': columns, 'langs': langs};

  factory ExportContent.fromJson(Map<String, dynamic> j) => ExportContent(
        votes: _b(j['votes'], true),
        decisions: _b(j['decisions'], true),
        notes: _b(j['notes'], true),
        audit: _b(j['audit'], false),
        columns: j['columns'] is List ? [for (final c in j['columns'] as List) '$c'] : null,
        langs: _pick(j['langs'], const ['ar', 'en', 'both'], 'both'),
      );

  ExportContent copy() => ExportContent.fromJson(toJson());
}

/// Sample council items for the designer's live preview and the tests.
List<ExportItem> exportSampleItems(String lang) {
  final ar = lang == 'ar';
  return [
    ExportItem(
      item: {
        'ref': 'W-2026-000041',
        'title': ar ? 'اعتماد نتائج الفصل الدراسي الأول' : 'Approve the first-term results',
        'type': 'request',
        'status': 'approved',
        'source': {'dept': {'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer Science'}, 'user': {'name': ar ? 'د. سارة علي' : 'Dr Sara Ali'}},
      },
      votes: ExportVoteResult(approve: 9, reject: 2, abstain: 1, eligible: 14, approvePct: 81.8, outcome: 'approved', voters: [
        {'name': ar ? 'د. أحمد' : 'Dr Ahmed', 'vote': 'approve', 'note': ''},
        {'name': ar ? 'د. منى' : 'Dr Mona', 'vote': 'reject', 'note': ''},
      ]),
      decision: ar ? 'موافقة' : 'Approved',
      notes: ar ? 'تُرفع النتائج إلى الكلية.' : 'Results go up to the faculty.',
    ),
    ExportItem(
      item: {
        'ref': 'W-2026-000042',
        'title': ar ? 'طلب تعيين معيد جديد' : 'Request to appoint a new teaching assistant',
        'type': 'request',
        'status': 'rejected',
        'source': {'dept': {'name_ar': 'شؤون أعضاء هيئة التدريس', 'name_en': 'Faculty affairs'}},
      },
      votes: const ExportVoteResult(approve: 4, reject: 7, abstain: 0, eligible: 14, approvePct: 36.4, outcome: 'rejected'),
      decision: ar ? 'رفض' : 'Rejected',
    ),
  ];
}

/// A sample dataset for the designer preview when the caller has none yet.
ExportDataset exportSampleDataset(String module, String lang) {
  final ar = lang == 'ar';
  final council = module == 'council' || module == 'minutes';
  return ExportDataset(
    module: module,
    title: council ? (ar ? 'جلسة مجلس القسم' : 'Department council session') : (ar ? 'تقرير الطلبات' : 'Requests report'),
    lang: lang,
    meta: {
      'org': ar ? 'جامعة النور' : 'Al Noor University',
      'dept': ar ? 'كلية الهندسة' : 'Faculty of Engineering',
      'council': ar ? 'مجلس قسم علوم الحاسب' : 'Computer Science council',
      'session': ar ? 'الجلسة 12' : 'Session 12',
      'session_date': '2026-10-20',
      'period': ar ? '1 – 24 أكتوبر 2026' : '1 – 24 Oct 2026',
      'count': 2,
      'signer': ar ? 'د. محمد حسن' : 'Dr Mohamed Hassan',
    },
    columns: [
      const ExportColumn('n', labelAr: '#', labelEn: '#', type: 'integer'),
      const ExportColumn('ref', labelAr: 'المرجع', labelEn: 'Ref'),
      const ExportColumn('title', labelAr: 'العنوان', labelEn: 'Title'),
      const ExportColumn('status', labelAr: 'الحالة', labelEn: 'Status', type: 'status'),
      const ExportColumn('created_at', labelAr: 'التاريخ', labelEn: 'Date', type: 'date'),
    ],
    rows: [
      {'n': 1, 'ref': 'W-2026-000041', 'title': ar ? 'اعتماد نتائج الفصل' : 'Approve term results', 'status': ar ? 'مقبول' : 'Approved', 'created_at': '2026-10-12'},
      {'n': 2, 'ref': 'W-2026-000042', 'title': ar ? 'تعيين معيد' : 'Appoint a TA', 'status': ar ? 'مرفوض' : 'Rejected', 'created_at': '2026-10-14'},
    ],
    items: council ? exportSampleItems(lang) : [],
    generatedAt: DateTime.utc(2026, 10, 24, 9),
  );
}


const _arabicMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
const _englishMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A printed date in the document's language: "27 أكتوبر 2026" in Arabic layouts (an Arabic month name keeps the
/// line right-to-left — a Latin month inside an Arabic sentence gets reordered by the bidi algorithm to
/// "27 2026 Oct"), "27 Oct 2026" in English ones. Shown in the organization's zone through AppTime.
String exportDateText(DateTime? d, String lang) {
  if (d == null) return '';
  DateTime local;
  try {
    local = AppTime.toZone(d.toUtc());
  } catch (_) {
    local = d;
  }
  final month = lang == 'ar' ? _arabicMonths[local.month - 1] : _englishMonths[local.month - 1];
  return '${local.day} $month ${local.year}';
}
