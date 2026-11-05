// Complaints / requests report: pure model (period, items, page design, placeholders). No Flutter widgets here —
// it is unit-tested in test/org/org_reports_test.dart. API: ../back/routers/organization/org_reports_router.py.
//
// The design is one A4 page. Every block sits at (x, y) with width w and height h, all as fractions of the page
// content box, so it renders the same at any size. The single `table` block marks where the items table starts:
// blocks above it print before the table, blocks below it print after the table (keeping their spacing), so a long
// table flows over several pages without covering the signature.

import 'package:flutter_education_app/core/app_time.dart';

import '../../admin/admin_common.dart' show t, asInt, asMap, asMapList;
import '../org_v3.dart' show orgParseUtc;

// ═════════════════════════════════════════════════════════════════════════════
//  Period
// ═════════════════════════════════════════════════════════════════════════════

enum ReportPeriodKind { today, week, month, custom }

class ReportPeriod {
  const ReportPeriod(this.kind, this.from, this.to);

  final ReportPeriodKind kind;

  /// Local wall-clock bounds, [from, to).
  final DateTime from, to;

  /// today → [00:00, tomorrow) · week → the 7 days ending today · month → since the 1st · custom → whole days.
  factory ReportPeriod.of(ReportPeriodKind kind, {DateTime? now, DateTime? from, DateTime? to}) {
    final n = now ?? DateTime.now();
    final day = DateTime(n.year, n.month, n.day), next = day.add(const Duration(days: 1));
    return switch (kind) {
      ReportPeriodKind.today => ReportPeriod(kind, day, next),
      ReportPeriodKind.week => ReportPeriod(kind, day.subtract(const Duration(days: 6)), next),
      ReportPeriodKind.month => ReportPeriod(kind, DateTime(n.year, n.month), next),
      ReportPeriodKind.custom => ReportPeriod(
          kind,
          DateTime((from ?? day).year, (from ?? day).month, (from ?? day).day),
          DateTime((to ?? day).year, (to ?? day).month, (to ?? day).day).add(const Duration(days: 1))),
    };
  }

  Map<String, String> get query => {'date_from': from.toUtc().toIso8601String(), 'date_to': to.toUtc().toIso8601String()};

  /// "1 Oct 2026 – 24 Oct 2026" (the end is inclusive for people).
  String get label {
    final last = to.subtract(const Duration(days: 1));
    final a = _day(from), b = _day(last);
    return a == b ? a : '$a – $b';
  }

  static String _day(DateTime d) => reportDay(d);
}

/// A calendar day picked by a person (not an instant) → printed date, via AppTime at noon UTC so no zone shifts it.
String reportDay(DateTime d) => AppTime.date(DateTime.utc(d.year, d.month, d.day, 12));

Map<ReportPeriodKind, String> reportPeriodLabels() => {
      ReportPeriodKind.today: t('اليوم', 'Today'),
      ReportPeriodKind.week: t('هذا الأسبوع', 'This week'),
      ReportPeriodKind.month: t('هذا الشهر', 'This month'),
      ReportPeriodKind.custom: t('فترة مخصصة', 'Custom range'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Items
// ═════════════════════════════════════════════════════════════════════════════

class ReportItem {
  ReportItem({
    required this.key,
    required this.kind,
    required this.subject,
    this.ref = '',
    this.date,
    this.body = '',
    this.from = '',
    this.status = '',
    this.priority = '',
    this.dept = '',
    this.manual = false,
  });

  /// `complaint:12` · `request:4` · `manual:N`.
  final String key;
  final String kind; // complaint | request
  final String subject, ref, body, from, status, priority, dept;
  final DateTime? date;
  final bool manual;

  factory ReportItem.fromJson(Map<String, dynamic> j) => ReportItem(
        key: '${j['key']}',
        kind: '${j['kind'] ?? 'complaint'}',
        subject: '${j['subject'] ?? ''}',
        ref: '${j['ref'] ?? ''}',
        date: orgParseUtc(j['date']),
        body: '${j['body'] ?? ''}',
        from: '${j['from'] ?? ''}',
        status: '${j['status'] ?? ''}',
        priority: '${j['priority'] ?? ''}',
        dept: '${j['dept'] ?? ''}',
      );

  /// The row printed in the table (keys = [reportColumnLabels]).
  Map<String, Object?> row(int index) => {
        'n': index + 1,
        'ref': ref.isEmpty ? (manual ? t('يدوي', 'Manual') : '') : ref,
        'date': date == null ? '' : AppTime.date(date!),
        'kind': reportKindLabels()[kind] ?? kind,
        'subject': subject,
        'from': from.isEmpty ? t('—', '—') : from,
        'status': reportStatusLabels()[status] ?? status,
        'priority': reportPriorityLabels()[priority] ?? priority,
        'dept': dept,
        'body': body,
      };
}

Map<String, String> reportKindLabels() => {'complaint': t('شكوى', 'Complaint'), 'request': t('طلب', 'Request')};

Map<String, String> reportStatusLabels() => {
      'open': t('مفتوحة', 'Open'),
      'in_progress': t('قيد المعالجة', 'In progress'),
      'waiting': t('بانتظار الرد', 'Waiting'),
      'resolved': t('تم الحل', 'Resolved'),
      'closed': t('مغلقة', 'Closed'),
      'submitted': t('مُرسل', 'Submitted'),
      'in_review': t('قيد المراجعة', 'In review'),
      'approved': t('مقبول', 'Approved'),
      'rejected': t('مرفوض', 'Rejected'),
      'manual': t('مضاف يدوياً', 'Added manually'),
    };

Map<String, String> reportPriorityLabels() =>
    {'low': t('منخفضة', 'Low'), 'medium': t('متوسطة', 'Medium'), 'high': t('عالية', 'High'), 'urgent': t('عاجلة', 'Urgent')};

/// Table columns that can be printed, in their default order.
Map<String, String> reportColumnLabels() => {
      'n': '#',
      'ref': t('المرجع', 'Ref'),
      'date': t('التاريخ', 'Date'),
      'kind': t('النوع', 'Type'),
      'subject': t('الموضوع', 'Subject'),
      'from': t('مقدّم من', 'From'),
      'status': t('الحالة', 'Status'),
      'priority': t('الأولوية', 'Priority'),
      'dept': t('الإدارة', 'Department'),
      'body': t('التفاصيل', 'Details'),
    };

/// The working set: server items minus the removed ones, plus manual ones, oldest first.
class ReportItems {
  final List<ReportItem> fetched = [];
  final List<ReportItem> manual = [];
  final Set<String> removed = {};
  int _seq = 0;

  void load(List<ReportItem> items) {
    fetched
      ..clear()
      ..addAll(items);
    removed.removeWhere((k) => !items.any((i) => i.key == k));
  }

  ReportItem addManual({required String kind, required String subject, String from = '', String body = '', DateTime? date}) {
    final it = ReportItem(
        key: 'manual:${++_seq}', kind: kind, subject: subject.trim(), from: from.trim(), body: body.trim(), date: (date ?? DateTime.now()).toUtc(),
        status: 'manual', manual: true);
    manual.add(it);
    return it;
  }

  /// Manual items are dropped for good; fetched ones can be restored.
  void remove(String key) => manual.any((m) => m.key == key) ? manual.removeWhere((m) => m.key == key) : removed.add(key);

  void restore(String key) => removed.remove(key);

  List<ReportItem> get active {
    final out = [...fetched.where((i) => !removed.contains(i.key)), ...manual];
    out.sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return out;
  }

  List<ReportItem> get removedItems => fetched.where((i) => removed.contains(i.key)).toList();
}

// ═════════════════════════════════════════════════════════════════════════════
//  Placeholders
// ═════════════════════════════════════════════════════════════════════════════

/// Placeholders the designer and uploaded Word / Excel templates understand.
Map<String, String> reportPlaceholderLabels() => {
      'org': t('اسم المؤسسة', 'Organization name'),
      'dept': t('اسم الإدارة', 'Department name'),
      'title': t('عنوان التقرير', 'Report title'),
      'period': t('الفترة', 'Period'),
      'date': t('تاريخ التقرير', 'Report date'),
      'count': t('عدد العناصر', 'Number of items'),
      'complaints': t('عدد الشكاوى', 'Complaints'),
      'requests': t('عدد الطلبات', 'Requests'),
      'signer': t('اسم الموقّع', 'Signer name'),
    };

/// Row placeholders for templates: {{item.subject}} …, one table row per item.
List<String> get reportItemPlaceholders => [for (final k in reportColumnLabels().keys) 'item.$k'];

final _ph = RegExp(r'\{\{\s*([a-zA-Z_.]+)\s*\}\}');

/// Replaces {{key}} with values[key]; unknown keys are left as they are (so a typo stays visible).
String fillPlaceholders(String text, Map<String, String> values) =>
    text.replaceAllMapped(_ph, (m) => values[m.group(1)!] ?? m.group(0)!);

bool hasItemPlaceholder(String text) => RegExp(r'\{\{\s*item\.').hasMatch(text);

/// Everything one rendering needs, already filled (strings are final, as printed).
class ReportData {
  ReportData({
    required this.items,
    required this.values,
    required this.columns,
    this.logo,
    this.signature,
    this.rtl = true,
  });

  final List<ReportItem> items;
  final Map<String, String> values;
  final List<String> columns;

  /// PNG / JPEG bytes, already loaded. null → the block prints nothing (unsigned / no logo).
  final List<int>? logo, signature;
  final bool rtl;

  List<Map<String, Object?>> get rows => [for (var i = 0; i < items.length; i++) items[i].row(i)];

  Map<String, String> itemValues(int i) => {for (final e in items[i].row(i).entries) 'item.${e.key}': '${e.value ?? ''}'};

  static Map<String, String> buildValues({
    required String org,
    required String dept,
    required String title,
    required ReportPeriod period,
    required DateTime printedDate,
    required List<ReportItem> items,
    String signer = '',
  }) =>
      {
        'org': org,
        'dept': dept,
        'title': title,
        'period': period.label,
        'date': reportDay(printedDate),
        'count': '${items.length}',
        'complaints': '${items.where((i) => i.kind == 'complaint').length}',
        'requests': '${items.where((i) => i.kind == 'request').length}',
        'signer': signer,
      };
}

// ═════════════════════════════════════════════════════════════════════════════
//  Design
// ═════════════════════════════════════════════════════════════════════════════

/// text (free text with {{placeholders}}) · table (the items, one only) · logo · signature (image + signer line).
const reportBlockKinds = ['text', 'table', 'logo', 'signature'];

class ReportBlock {
  ReportBlock({
    required this.id,
    required this.kind,
    this.x = 0,
    this.y = 0,
    this.w = 1,
    this.h = .06,
    this.text = '',
    this.size = 11,
    this.align = 'start',
    this.bold = false,
  });

  final String id, kind;
  double x, y, w, h;
  String text;
  double size;

  /// start | center | end (reading direction aware).
  String align;
  bool bold;

  bool get isImage => kind == 'logo' || kind == 'signature';

  factory ReportBlock.fromJson(Map<String, dynamic> j) => ReportBlock(
        id: '${j['id'] ?? ''}',
        kind: reportBlockKinds.contains(j['kind']) ? '${j['kind']}' : 'text',
        x: _d(j['x'], 0),
        y: _d(j['y'], 0),
        w: _d(j['w'], 1),
        h: _d(j['h'], .06),
        text: '${j['text'] ?? ''}',
        size: _d(j['size'], 11).clamp(6, 40).toDouble(),
        align: const {'start', 'center', 'end'}.contains(j['align']) ? '${j['align']}' : 'start',
        bold: j['bold'] == true,
      )..clamp();

  Map<String, dynamic> toJson() =>
      {'id': id, 'kind': kind, 'x': x, 'y': y, 'w': w, 'h': h, 'text': text, 'size': size, 'align': align, 'bold': bold};

  /// Keeps the block inside the page.
  void clamp() {
    w = w.clamp(.08, 1).toDouble();
    h = h.clamp(.02, .6).toDouble();
    x = x.clamp(0, 1 - w).toDouble();
    y = y.clamp(0, 1 - h).toDouble();
  }

  static double _d(Object? v, double or) => v is num ? v.toDouble() : double.tryParse('$v') ?? or;
}

class ReportLayout {
  ReportLayout({
    List<ReportBlock>? blocks,
    List<String>? columns,
    this.font = 'tajawal',
    this.margin = 16,
    this.lineSpacing = 1.3,
    this.logoUrl,
    this.signatureUrl,
  })  : blocks = blocks ?? [],
        columns = columns ?? ['n', 'ref', 'date', 'kind', 'subject', 'from', 'status'];

  final List<ReportBlock> blocks;
  final List<String> columns;

  /// tajawal | bahij (both bundled with Arabic glyphs).
  String font;

  /// Page margin in millimetres.
  double margin;

  /// Line height multiplier for text blocks and table cells.
  double lineSpacing;
  String? logoUrl, signatureUrl;

  ReportBlock? get table => blocks.where((b) => b.kind == 'table').firstOrNull;

  /// Blocks printed before / after the table, top to bottom.
  List<ReportBlock> get before {
    final tb = table;
    return _sorted(blocks.where((b) => b.kind != 'table' && (tb == null || b.y < tb.y)));
  }

  List<ReportBlock> get after {
    final tb = table;
    return tb == null ? [] : _sorted(blocks.where((b) => b.kind != 'table' && b.y >= tb.y));
  }

  static List<ReportBlock> _sorted(Iterable<ReportBlock> it) => it.toList()..sort((a, b) => a.y.compareTo(b.y));

  String nextId() {
    var n = blocks.length + 1;
    while (blocks.any((b) => b.id == 'b$n')) {
      n++;
    }
    return 'b$n';
  }

  ReportBlock add(String kind) {
    if (kind == 'table' && table != null) return table!;
    final b = switch (kind) {
      'table' => ReportBlock(id: nextId(), kind: kind, x: 0, y: .3, w: 1, h: .3),
      'logo' => ReportBlock(id: nextId(), kind: kind, x: .4, y: .02, w: .2, h: .08, align: 'center'),
      'signature' => ReportBlock(id: nextId(), kind: kind, x: 0, y: .8, w: .32, h: .1, text: '{{signer}}', align: 'center'),
      _ => ReportBlock(id: nextId(), kind: 'text', x: .1, y: .2, w: .8, h: .05, text: t('نص جديد', 'New text')),
    };
    blocks.add(b..clamp());
    return b;
  }

  factory ReportLayout.fromJson(Map<String, dynamic> j) => ReportLayout(
        blocks: [for (final b in asMapList(j['blocks'])) ReportBlock.fromJson(b)],
        columns: [for (final c in (j['columns'] as List? ?? const [])) if (reportColumnLabels().containsKey('$c')) '$c'],
        font: j['font'] == 'bahij' ? 'bahij' : 'tajawal',
        margin: ReportBlock._d(j['margin'], 16).clamp(6, 40).toDouble(),
        lineSpacing: ReportBlock._d(j['line_spacing'], 1.3).clamp(1, 2.5).toDouble(),
        logoUrl: j['logo_url'] as String?,
        signatureUrl: j['signature_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'blocks': [for (final b in blocks) b.toJson()],
        'columns': columns,
        'font': font,
        'margin': margin,
        'line_spacing': lineSpacing,
        'logo_url': logoUrl,
        'signature_url': signatureUrl,
      };

  ReportLayout copy() => ReportLayout.fromJson(toJson());

  /// A ready, formal letter: logo, organization and department, title, period line, the table, then the signature.
  factory ReportLayout.standard() => ReportLayout(blocks: [
        ReportBlock(id: 'b1', kind: 'logo', x: .4, y: 0, w: .2, h: .08, align: 'center'),
        ReportBlock(id: 'b2', kind: 'text', x: 0, y: .09, w: 1, h: .035, text: '{{org}}', size: 14, bold: true, align: 'center'),
        ReportBlock(id: 'b3', kind: 'text', x: 0, y: .125, w: 1, h: .03, text: '{{dept}}', size: 11, align: 'center'),
        ReportBlock(id: 'b4', kind: 'text', x: 0, y: .17, w: 1, h: .04, text: '{{title}}', size: 16, bold: true, align: 'center'),
        ReportBlock(
            id: 'b5',
            kind: 'text',
            x: 0,
            y: .215,
            w: 1,
            h: .03,
            text: t('الفترة: {{period}} · العدد: {{count}} (شكاوى {{complaints}} · طلبات {{requests}})',
                'Period: {{period}} · Items: {{count}} ({{complaints}} complaints · {{requests}} requests)'),
            size: 10),
        ReportBlock(id: 'b6', kind: 'text', x: .6, y: .215, w: .4, h: .03, text: t('التاريخ: {{date}}', 'Date: {{date}}'), size: 10, align: 'end'),
        ReportBlock(id: 'b7', kind: 'table', x: 0, y: .26, w: 1, h: .4),
        ReportBlock(id: 'b8', kind: 'signature', x: .66, y: .7, w: .34, h: .12, text: '{{signer}}', align: 'center'),
      ]);
}

/// A saved design (`GET …/reports/templates`).
class ReportTemplate {
  ReportTemplate({required this.id, required this.name, required this.kind, this.layout, this.fileUrl, this.fileName});

  final int id;
  final String name, kind; // designer | docx | xlsx
  final ReportLayout? layout;
  final String? fileUrl, fileName;

  factory ReportTemplate.fromJson(Map<String, dynamic> j) => ReportTemplate(
        id: asInt(j['id']),
        name: '${j['name'] ?? ''}',
        kind: '${j['kind'] ?? 'designer'}',
        layout: j['layout'] is Map ? ReportLayout.fromJson(asMap(j['layout'])) : null,
        fileUrl: j['file_url'] as String?,
        fileName: j['file_name'] as String?,
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Sharing
// ═════════════════════════════════════════════════════════════════════════════

/// The `meta` of `POST …/reports/share`. There is deliberately no `emails` key: the server answers 422
/// `share_target_not_allowed` for a free address, so people are picked from the members list, teams and consenting
/// organizations only.
Map<String, dynamic> reportShareMeta({
  int? deptId,
  required String title,
  String? message,
  required String channel,
  Set<int> userIds = const {},
  Set<int> deptIds = const {},
  Set<int> orgIds = const {},
}) =>
    {
      'dept_id': deptId,
      'title': title,
      'message': message,
      'channel': channel,
      'user_ids': userIds.toList(),
      'dept_ids': deptIds.toList(),
      'org_ids': orgIds.toList(),
    };
