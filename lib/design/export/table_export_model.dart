// lib/design/export/table_export_model.dart
//
// The data model of the generic table exporter (lib/design/app_table_export.dart): typed columns, rows, grouping,
// totals, and the pure formatting every writer (Excel · Word · PDF) shares. No Flutter widgets here, so the writers
// and this file are unit-tested directly (test/export/app_table_export_test.dart).
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:intl/intl.dart';

/// What a column holds — decides the Excel number format, the alignment and the text in Word / PDF.
enum AppColType { text, number, integer, money, percent, date, dateTime, status }

/// Logical alignment; [auto] = numbers at the end, dates / status centred, text at the start.
enum AppColAlign { auto, start, center, end }

/// The aggregate shown in the totals row (and in each group's subtotal row).
enum AppTotal { none, sum, average, count, min, max }

enum AppExportFormat {
  xlsx('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  docx('docx', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
  pdf('pdf', 'application/pdf');

  const AppExportFormat(this.ext, this.mime);
  final String ext, mime;

  static AppExportFormat? parse(String? v) => values.where((f) => f.name == v).firstOrNull;
}

/// The look of a status cell.
enum AppStatusTone { good, warn, bad, info, neutral }

class AppExportColumn {
  const AppExportColumn(
    this.id,
    this.label, {
    this.type = AppColType.text,
    this.align = AppColAlign.auto,
    this.visible = true,
    this.width,
    this.locked = false,
    this.total = AppTotal.none,
    this.decimals,
    this.currency,
    this.statusLabels,
    this.statusTones,
    this.labels,
    this.statusLabelsByLang,
  });

  /// Key of the value in each row map.
  final String id;
  final String label;
  final AppColType type;
  final AppColAlign align;

  /// Selected by default in the picker (the user can still add it).
  final bool visible;

  /// Width hint in characters (≈ Excel width units). null = measured from the content.
  final double? width;

  /// Always exported, cannot be unticked (e.g. the name).
  final bool locked;
  final AppTotal total;

  /// Digits after the point for number / money / percent. null = 2 for money, 1 for percent, as needed for number.
  final int? decimals;

  /// Money suffix ("EGP", "SAR", "ج.م").
  final String? currency;

  /// Raw status value → shown label (e.g. 'active' → 'Active').
  final Map<String, String>? statusLabels;

  /// Raw status value → tone; unknown values are guessed from the words (paid / active → good, pending → warn …).
  final Map<String, AppStatusTone>? statusTones;

  /// The header per language (`{'ar': 'الاسم', 'en': 'Name'}`) when the caller knows both; the Export Studio
  /// prints the one of the file's language. Missing = [label].
  final Map<String, String>? labels;

  /// [statusLabels] per language (filled by [bilingualExport]); the Export Studio prints the file's language.
  final Map<String, Map<String, String>>? statusLabelsByLang;

  /// The header in [lang]: [labels], else [label].
  String labelIn(String lang) {
    final l = labels?[lang];
    return l == null || l.trim().isEmpty ? label : l;
  }

  AppExportColumn copyWith({
    String? label,
    double? width,
    AppTotal? total,
    bool? locked,
    bool? visible,
    Map<String, String>? labels,
    Map<String, String>? statusLabels,
    Map<String, Map<String, String>>? statusLabelsByLang,
  }) =>
      AppExportColumn(
        id,
        label ?? this.label,
        type: type,
        align: align,
        visible: visible ?? this.visible,
        width: width ?? this.width,
        locked: locked ?? this.locked,
        total: total ?? this.total,
        decimals: decimals,
        currency: currency,
        statusLabels: statusLabels ?? this.statusLabels,
        statusTones: statusTones,
        labels: labels ?? this.labels,
        statusLabelsByLang: statusLabelsByLang ?? this.statusLabelsByLang,
      );

  bool get numeric => type == AppColType.number || type == AppColType.integer || type == AppColType.money || type == AppColType.percent;

  AppColAlign get resolvedAlign => align != AppColAlign.auto
      ? align
      : numeric
          ? AppColAlign.end
          : (type == AppColType.date || type == AppColType.dateTime || type == AppColType.status)
              ? AppColAlign.center
              : AppColAlign.start;
}

/// Everything one export needs. Rows are maps keyed by [AppExportColumn.id].
class AppTableExport {
  AppTableExport({
    required this.id,
    required this.title,
    required this.columns,
    required this.rows,
    this.subtitle,
    this.brand,
    this.meta = const [],
    this.filters = const {},
    this.groupBy,
    this.groupTotals = true,
    this.showTotals = true,
    this.totalLabel,
    this.allowColumnSelection = true,
    this.fileName,
    this.brandColor,
    bool? rtl,
    DateTime? generatedAt,
    this.selectedRows,
    this.orgId,
    this.serverDataset,
    this.serverParams,
    this.titles,
  })  : rtl = rtl ?? AppConfig.lang == 'ar',
        generatedAt = generatedAt ?? DateTime.now().toUtc();

  /// Stable id of the table — the picker remembers the last format / columns under it.
  final String id;
  final String title;
  final String? subtitle;

  /// Organization / platform name, shown in the header band.
  final String? brand;

  /// Extra lines under the title (scope, period, …).
  final List<String> meta;

  /// Filters applied to the rows (label → value), printed as one line.
  final Map<String, String> filters;
  final List<AppExportColumn> columns;
  final List<Map<String, Object?>> rows;

  /// Column id to group the rows by (each group gets a header row and, with totals, a subtotal row).
  final String? groupBy;
  final bool groupTotals;

  /// Adds the totals row when at least one exported column has a [AppTotal].
  final bool showTotals;
  final String? totalLabel;

  /// false → the picker offers the formats only and every column of [defaultColumns] is exported.
  final bool allowColumnSelection;

  /// File name without extension (defaults to the title).
  final String? fileName;

  /// Header colour as RRGGBB (the theme primary when the picker builds it). null = the app's brand green.
  String? brandColor;
  final bool rtl;

  /// UTC instant.
  final DateTime generatedAt;

  /// The rows the person ticked on the page (a subset of [rows]); the Export Studio then offers "Selected rows"
  /// next to "All rows". null = the page has no selection.
  final List<Map<String, Object?>>? selectedRows;

  /// The organization the data belongs to (export log, organization templates); null = the open organization.
  final int? orgId;

  /// The server dataset that produces the same table (`GET /api/v1/exports/datasets`, e.g. `org.people`) and its
  /// parameters: with it the flow offers "Schedule" (a server run of the saved template, D-130).
  final String? serverDataset;
  final Map<String, Object?>? serverParams;

  /// [title] per language (filled by [bilingualExport]); null = [title] in every language.
  final Map<String, String>? titles;

  /// A copy with other rows / columns / direction / grouping (the Export Studio builds one per language).
  AppTableExport copyWith({
    String? title,
    List<AppExportColumn>? columns,
    List<Map<String, Object?>>? rows,
    bool? rtl,
    String? groupBy,
    bool clearGroupBy = false,
    bool? showTotals,
    String? brand,
    List<String>? meta,
    Map<String, String>? filters,
    List<Map<String, Object?>>? selectedRows,
    Map<String, String>? titles,
  }) =>
      AppTableExport(
        id: id,
        title: title ?? this.title,
        columns: columns ?? this.columns,
        rows: rows ?? this.rows,
        subtitle: subtitle,
        brand: brand ?? this.brand,
        meta: meta ?? this.meta,
        filters: filters ?? this.filters,
        groupBy: clearGroupBy ? null : (groupBy ?? this.groupBy),
        groupTotals: groupTotals,
        showTotals: showTotals ?? this.showTotals,
        totalLabel: totalLabel,
        allowColumnSelection: allowColumnSelection,
        fileName: fileName,
        brandColor: brandColor,
        rtl: rtl ?? this.rtl,
        generatedAt: generatedAt,
        selectedRows: selectedRows ?? this.selectedRows,
        orgId: orgId,
        serverDataset: serverDataset,
        serverParams: serverParams,
        titles: titles ?? this.titles,
      );

  AppExportColumn? column(String id) => columns.where((c) => c.id == id).firstOrNull;

  /// Columns exported when nobody picked: every visible one plus the locked ones, in declaration order.
  List<String> get defaultColumns => [for (final c in columns) if (c.visible || c.locked) c.id];

  /// The exported columns for [selected] ids (their order is the output order). Unknown ids are dropped, locked
  /// columns are always kept (at their declared place relative to the others), and the group column is left out
  /// of the body because its value heads each group.
  List<AppExportColumn> resolve([List<String>? selected]) {
    final ids = !allowColumnSelection || selected == null ? defaultColumns : selected;
    final out = <AppExportColumn>[for (final id in ids) ?column(id)];
    final seen = <String>{};
    out.retainWhere((c) => seen.add(c.id));
    for (var i = 0; i < columns.length; i++) {
      final c = columns[i];
      if (c.locked && !seen.contains(c.id)) {
        // insert before the first output column declared after it
        final at = out.indexWhere((o) => columns.indexOf(o) > i);
        out.insert(at < 0 ? out.length : at, c);
        seen.add(c.id);
      }
    }
    if (groupBy != null) out.removeWhere((c) => c.id == groupBy);
    return out;
  }

  String get safeFileName => (fileName ?? title).replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_').trim();

  /// "Generated 23 Oct 2026 · 8:30 AM".
  String get stamp => '${tx('tx_generated', 'Generated', 'أُنشئ')} ${safeDateTime(generatedAt)}';

  /// The filters as one line, or null.
  String? get filtersLine => filters.isEmpty
      ? null
      : '${tx('tx_filters', 'Filters', 'التصفية')}: ${filters.entries.map((e) => '${e.key}: ${e.value}').join(' · ')}';

  /// Subtitle, meta and filters lines, in print order.
  List<String> get infoLines => [
        if (subtitle != null && subtitle!.trim().isNotEmpty) subtitle!,
        ...meta.where((m) => m.trim().isNotEmpty),
        ?filtersLine,
      ];

  String get totalText => totalLabel ?? tx('tx_total', 'Total', 'الإجمالي');
}

/// Builds the export with [build] in Arabic and in English and returns the build of the app language carrying both
/// headers ([AppExportColumn.labels]), both status texts ([AppExportColumn.statusLabelsByLang]) and both titles
/// ([AppTableExport.titles]), so an English or "Both" export prints English headers in the Arabic app (and the reverse).
/// [build] must be synchronous and read the language through `t()` / `tx()` / `translate()` at call time; labels the
/// caller already gave per language win.
AppTableExport bilingualExport(AppTableExport Function() build) {
  final keep = AppConfig.lang;
  AppTableExport inLang(String lang) {
    AppConfig.lang = lang;
    try {
      return build();
    } finally {
      AppConfig.lang = keep;
    }
  }

  final cur = build();
  final other = inLang(keep == 'ar' ? 'en' : 'ar');
  final (ar, en) = keep == 'ar' ? (cur, other) : (other, cur);
  return cur.copyWith(
    columns: [
      for (final c in cur.columns)
        () {
          final a = ar.column(c.id), e = en.column(c.id);
          return c.copyWith(
            labels: {'ar': a?.labelIn('ar') ?? c.label, 'en': e?.labelIn('en') ?? c.label, ...?c.labels},
            statusLabelsByLang: c.statusLabels == null ? null : {'ar': ?a?.statusLabels, 'en': ?e?.statusLabels},
          );
        }(),
    ],
    titles: {'ar': ar.title, 'en': en.title},
  );
}

/// A translated string with an inline fallback (works before translation.json loads, e.g. in tests).
String tx(String key, String en, String ar) {
  final v = translate(key);
  return v == key ? (AppConfig.lang == 'ar' ? ar : en) : v;
}

// ═════════════════════════════════════════════════════════════════════════════
//  Values
// ═════════════════════════════════════════════════════════════════════════════

/// A number from a num or a numeric string ("1,234.5" accepted); null otherwise.
num? numValue(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final s = v.trim().replaceAll(',', '').replaceAll('%', '');
    if (s.isEmpty) return null;
    return num.tryParse(s);
  }
  if (v is bool) return v ? 1 : 0;
  return null;
}

/// A date-only value ("2026-10-23") is a calendar day — no timezone shift. Returns (wall time, has time of day).
(DateTime, bool)? dateValue(Object? v, {bool withTime = true}) {
  DateTime? d;
  var dateOnly = false;
  if (v is DateTime) {
    d = v;
  } else if (v is String && v.trim().isNotEmpty) {
    final s = v.trim();
    dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
    // the server stores naive UTC: a timestamp without an offset is UTC
    final iso = !dateOnly && !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s) ? '${s.replaceFirst(' ', 'T')}Z' : s;
    d = DateTime.tryParse(iso);
  } else if (v is int) {
    d = DateTime.fromMillisecondsSinceEpoch(v, isUtc: true);
  }
  if (d == null) return null;
  if (dateOnly) return (DateTime(d.year, d.month, d.day), false);
  DateTime wall;
  try {
    wall = AppTime.toZone(d.toUtc());
  } catch (_) {
    wall = d.toLocal();
  }
  return (wall, withTime);
}

String _datePattern(DateTime d, String pattern) {
  try {
    return DateFormat(pattern, AppConfig.lang).format(d);
  } catch (_) {
    return DateFormat(pattern).format(d);
  }
}

String _clock(DateTime d) {
  try {
    return AppTime.clockMinutes(d.hour * 60 + d.minute);
  } catch (_) {
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

/// AppTime.dateTime with a fallback when the timezone data is unavailable.
String safeDateTime(DateTime utc) {
  final w = dateValue(utc.toUtc())!.$1;
  return '${_datePattern(w, 'd MMM y')} · ${_clock(w)}';
}

int decimalsOf(AppExportColumn c, Iterable<Object?> values) {
  if (c.decimals != null) return c.decimals!;
  return switch (c.type) {
    AppColType.integer => 0,
    AppColType.money => 2,
    AppColType.percent => values.map(numValue).every((v) => v == null || v == v.roundToDouble()) ? 0 : 1,
    _ => values.map(numValue).every((v) => v == null || v == v.roundToDouble()) ? 0 : 2,
  };
}

String formatNumber(num v, int decimals) =>
    NumberFormat(decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}', 'en').format(v);

/// The text of a cell as Word / PDF (and the picker preview) print it. Empty for null.
String cellText(AppExportColumn c, Object? v, {int? decimals}) {
  if (v == null) return '';
  switch (c.type) {
    case AppColType.text:
      return v is DateTime ? safeDateTime(v.toUtc()) : '$v';
    case AppColType.status:
      final s = '$v';
      return c.statusLabels?[s] ?? s;
    case AppColType.number:
    case AppColType.integer:
    case AppColType.money:
    case AppColType.percent:
      final n = numValue(v);
      if (n == null) return '$v';
      final d = decimals ?? c.decimals ?? (c.type == AppColType.money ? 2 : (n == n.roundToDouble() ? 0 : (c.type == AppColType.percent ? 1 : 2)));
      final t = formatNumber(n, c.type == AppColType.integer ? 0 : d);
      if (c.type == AppColType.percent) return '$t%';
      if (c.type == AppColType.money && (c.currency ?? '').isNotEmpty) return '$t ${c.currency}';
      return t;
    case AppColType.date:
    case AppColType.dateTime:
      final d = dateValue(v, withTime: c.type == AppColType.dateTime);
      if (d == null) return '$v';
      return d.$2 ? '${_datePattern(d.$1, 'd MMM y')} · ${_clock(d.$1)}' : _datePattern(d.$1, 'd MMM y');
  }
}

/// The tone of a status value: the column's map first, then words in English or Arabic.
AppStatusTone statusTone(AppExportColumn c, Object? v) {
  final s = '${v ?? ''}'.trim();
  final mapped = c.statusTones?[s];
  if (mapped != null) return mapped;
  final l = s.toLowerCase();
  bool any(List<String> w) => w.any(l.contains);
  if (any(['reject', 'fail', 'block', 'cancel', 'refus', 'absent', 'overdue', 'expired', 'error', 'denied', 'suspend', 'banned', 'مرفوض', 'فشل', 'محظور', 'ملغ', 'غائب', 'منتهي', 'متأخر', 'موقوف'])) {
    return AppStatusTone.bad;
  }
  if (any(['pending', 'wait', 'review', 'draft', 'late', 'partial', 'hold', 'معلق', 'انتظار', 'مراجعة', 'مسودة', 'جزئي'])) return AppStatusTone.warn;
  if (any(['active', 'paid', 'approv', 'done', 'complet', 'success', 'present', 'publish', 'accept', 'verified', 'yes', 'نشط', 'مدفوع', 'مقبول', 'مكتمل', 'ناجح', 'حاضر', 'منشور', 'موثق', 'نعم'])) {
    return AppStatusTone.good;
  }
  if (any(['new', 'open', 'info', 'جديد', 'مفتوح'])) return AppStatusTone.info;
  return AppStatusTone.neutral;
}

/// (fill, ink) hex per tone.
(String, String) toneColors(AppStatusTone t) => switch (t) {
      AppStatusTone.good => ('E3F5EC', '0F6B45'),
      AppStatusTone.warn => ('FFF4DB', '8A5A00'),
      AppStatusTone.bad => ('FDE7E7', 'A11B1B'),
      AppStatusTone.info => ('E6EEFB', '1E4FA3'),
      AppStatusTone.neutral => ('EEF1F4', '4B5563'),
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Layout shared by the writers: groups and totals
// ═════════════════════════════════════════════════════════════════════════════

class ExportGroup {
  ExportGroup(this.label, this.rows);
  final String? label; // null = no grouping
  final List<Map<String, Object?>> rows;
}

/// Groups in first-appearance order (one unlabelled group without [AppTableExport.groupBy]).
List<ExportGroup> groupRows(AppTableExport e) {
  final g = e.groupBy == null ? null : e.column(e.groupBy!);
  if (g == null) return [ExportGroup(null, e.rows)];
  final map = <String, List<Map<String, Object?>>>{};
  for (final r in e.rows) {
    final k = cellText(g, r[g.id]);
    (map[k] ??= []).add(r);
  }
  return [for (final m in map.entries) ExportGroup(m.key.isEmpty ? '-' : m.key, m.value)];
}

/// The aggregate of [c] over [rows]; null when the column has no total.
num? aggregate(AppExportColumn c, List<Map<String, Object?>> rows) {
  if (c.total == AppTotal.none) return null;
  if (c.total == AppTotal.count) return rows.where((r) => '${r[c.id] ?? ''}'.trim().isNotEmpty).length;
  final v = [for (final r in rows) ?numValue(r[c.id])];
  if (v.isEmpty) return c.total == AppTotal.sum ? 0 : null;
  return switch (c.total) {
    AppTotal.sum => v.fold<num>(0, (a, b) => a + b),
    AppTotal.average => v.fold<num>(0, (a, b) => a + b) / v.length,
    AppTotal.min => v.reduce((a, b) => a < b ? a : b),
    AppTotal.max => v.reduce((a, b) => a > b ? a : b),
    _ => null,
  };
}

/// Totals are printed when asked for and at least one exported column aggregates.
bool hasTotals(AppTableExport e, List<AppExportColumn> cols) => e.showTotals && cols.any((c) => c.total != AppTotal.none);

/// The text of an aggregate cell (a count is a plain integer whatever the column type).
String aggregateText(AppExportColumn c, num? v, int decimals) {
  if (v == null) return '';
  if (c.total == AppTotal.count) return formatNumber(v, 0);
  if (!c.numeric) return formatNumber(v, v == v.roundToDouble() ? 0 : 2);
  return cellText(c, v, decimals: c.total == AppTotal.average && c.type == AppColType.integer ? 1 : decimals);
}

/// Relative widths (characters) — the hint, else measured from the header and the first 200 values.
List<double> columnWidths(List<AppExportColumn> cols, List<Map<String, Object?>> rows) => [
      for (final c in cols)
        c.width ??
            () {
              var w = c.label.length * 1.1;
              for (final r in rows.take(200)) {
                final l = cellText(c, r[c.id]).split('\n').fold<int>(0, (a, s) => s.length > a ? s.length : a);
                if (l > w) w = l.toDouble();
              }
              if (c.total != AppTotal.none) {
                final t = aggregateText(c, aggregate(c, rows), decimalsOf(c, rows.map((r) => r[c.id]))).length * 1.15;
                if (t > w) w = t;
              }
              return (w + 3).clamp(6.0, 48.0);
            }(),
    ];

/// Landscape once the table is wide.
bool wideTable(List<AppExportColumn> cols, List<double> widths) => cols.length > 6 || widths.fold<double>(0, (a, b) => a + b) > 95;

// ═════════════════════════════════════════════════════════════════════════════
//  XML / zip helpers
// ═════════════════════════════════════════════════════════════════════════════

String xmlEsc(Object? v) => '${v ?? ''}'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

Uint8List zipFiles(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) => a.add(ArchiveFile.bytes(name, utf8.encode(body))));
  return ZipEncoder().encodeBytes(a);
}

String coreProps(AppTableExport e) {
  final now = e.generatedAt.toUtc().toIso8601String().split('.').first;
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${xmlEsc(e.title)}</dc:title><dc:creator>${xmlEsc(e.brand ?? 'NextBrain')}</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${now}Z</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">${now}Z</dcterms:modified>'
      '</cp:coreProperties>';
}

/// Default brand colour (the schedule export's green) and the neutral palette.
const exportBrandHex = '0F7B5F', exportInkHex = '1F2933', exportMutedHex = '6B7280', exportLineHex = 'D7DDE3', exportZebraHex = 'F6F8FA';

/// Mixes [hex] with white: 0 → white, 1 → the colour.
String tintHex(String hex, double amount) {
  final v = int.parse(hex, radix: 16);
  int ch(int shift) {
    final c = (v >> shift) & 0xFF;
    return (255 - (255 - c) * amount).round().clamp(0, 255);
  }

  return [ch(16), ch(8), ch(0)].map((c) => c.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

/// Darkens [hex]: 0 → unchanged, 1 → black.
String shadeHex(String hex, double amount) {
  final v = int.parse(hex, radix: 16);
  int ch(int shift) => (((v >> shift) & 0xFF) * (1 - amount)).round().clamp(0, 255);
  return [ch(16), ch(8), ch(0)].map((c) => c.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

/// Valid RRGGBB or the default brand.
String brandOf(AppTableExport e) {
  final b = (e.brandColor ?? '').replaceAll('#', '').toUpperCase();
  final hex = b.length == 8 ? b.substring(2) : b;
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(hex) ? hex : exportBrandHex;
}

/// White or ink text on [hex], whichever reads better (WCAG relative luminance).
String onColorHex(String hex) {
  final v = int.parse(hex, radix: 16);
  double lin(int c) {
    final s = c / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  final l = 0.2126 * lin((v >> 16) & 0xFF) + 0.7152 * lin((v >> 8) & 0xFF) + 0.0722 * lin(v & 0xFF);
  return l > 0.40 ? exportInkHex : 'FFFFFF';
}
