// lib/features/org/org_schedule_export.dart — premium timetable exports: Excel, Word and PDF, built in the app.
//
//   TimetableGrid        pure: days × periods; a session over consecutive periods (same block) is ONE merged cell,
//                        parallel sessions in the same cell are stacked
//   TimetableSummary     pure: sessions, teaching hours, days used, busiest day, first / last time, per-course and
//                        per-day breakdowns — the "smart" part printed under every grid
//   exportSheets         one sheet per member for a scope: the whole timetable, every teacher / assistant / room /
//                        student group, or a single member (only that member's sessions)
//   timetableXlsx        SpreadsheetML written by hand: merged cells, course colours, an overview sheet with links
//   timetableDocx        WordprocessingML written by hand: landscape A4, shaded cells, grid spans, page per member
//   timetablePdf         package:pdf with the bundled Arabic fonts, a page per member + an overview page
//   showTimetableExport  the sheet that picks the scope, the member and the format, then saves the file
//
// Everything is built from the sessions the caller passes (the live timetable or a stored copy); nothing is invented.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../admin/admin_common.dart';
import 'org_providers.dart' show orgDays;
import 'org_schedule_versions.dart';
import 'org_ui.dart';
import 'package:flutter_education_app/core/app_time.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Model (pure)
// ═════════════════════════════════════════════════════════════════════════════

/// What a grid cell shows depends on whose timetable it is: a teacher needs the room, a room needs the teacher.
enum ExportView { full, teacher, assistant, room, group }

ExportView exportViewOf(String memberKind) => switch (memberKind) {
      'teacher' => ExportView.teacher,
      'assistant' => ExportView.assistant,
      'room' => ExportView.room,
      'group' => ExportView.group,
      _ => ExportView.full,
    };

class GridEntry {
  const GridEntry(this.span, this.sessions);
  final int span; // columns (periods) it covers
  final List<Map<String, dynamic>> sessions; // one slot per session (block); empty = a free cell
  bool get isEmpty => sessions.isEmpty;
}

String _hhmm(Object? v) {
  final s = '${v ?? ''}';
  return s.length >= 5 ? s.substring(0, 5) : s;
}

int? _minutes(Object? v) {
  final p = _hhmm(v).split(':');
  if (p.length != 2) return null;
  final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
  return h == null || m == null ? null : h * 60 + m;
}

String blockKey(Map<String, dynamic> s) => '${s['block_id'] ?? 'slot-${s['id']}'}';

class TimetableGrid {
  TimetableGrid._(this.days, this.periods, this.rows);
  final List<String> days;
  final List<Map<String, dynamic>> periods; // ordered by start time
  final Map<String, List<GridEntry>> rows; // day → entries whose spans add up to periods.length

  /// [days]: the timetable's teaching days (week order); days that only appear in [slots] are added.
  factory TimetableGrid.build(List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods, {List<String> days = const []}) {
    final ps = [...periods]..sort((a, b) => (_minutes(a['start_time']) ?? 0).compareTo(_minutes(b['start_time']) ?? 0));
    final index = {for (var i = 0; i < ps.length; i++) asInt(ps[i]['id']): i};
    final used = {for (final s in slots) '${s['day']}'};
    final ds = [for (final d in orgDays) if (days.contains(d) || used.contains(d)) d];
    final rows = <String, List<GridEntry>>{};
    for (final d in ds) {
      // column → block key → its first slot
      final cols = List.generate(ps.length, (_) => <String, Map<String, dynamic>>{});
      for (final s in slots.where((s) => s['day'] == d)) {
        final c = index[asInt(s['period_id'])];
        if (c != null) cols[c].putIfAbsent(blockKey(s), () => s);
      }
      final out = <GridEntry>[];
      var c = 0;
      while (c < ps.length) {
        final keys = cols[c].keys.toSet();
        var span = 1;
        // the same sessions continue in the next period (a double session) → one merged cell
        while (keys.isNotEmpty && c + span < ps.length && _sameSet(cols[c + span].keys.toSet(), keys)) {
          span++;
        }
        final sessions = cols[c].values.toList()..sort((a, b) => asInt(a['course_id']).compareTo(asInt(b['course_id'])) * 10 + asInt(a['group_no'] ?? 1).compareTo(asInt(b['group_no'] ?? 1)));
        out.add(GridEntry(span, sessions));
        c += span;
      }
      rows[d] = out;
    }
    return TimetableGrid._(ds, ps, rows);
  }

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}

class CourseLine {
  CourseLine(this.courseId);
  final int courseId;
  int lectures = 0, labs = 0, periods = 0, minutes = 0;
  final rooms = <int>{};
}

class TimetableSummary {
  TimetableSummary._({
    required this.sessions,
    required this.periods,
    required this.minutes,
    required this.byDay,
    required this.courses,
    required this.rooms,
    required this.people,
    this.first,
    this.last,
  });

  final int sessions, periods, minutes;
  final Map<String, int> byDay; // day → periods taught (week order, only days with sessions)
  final List<CourseLine> courses;
  final int rooms, people;
  final String? first, last; // earliest start / latest end of the week

  double get hours => minutes / 60;
  String? get busiestDay => byDay.isEmpty ? null : (byDay.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  int get days => byDay.length;

  factory TimetableSummary.of(List<Map<String, dynamic>> slots, List<Map<String, dynamic>> periods) {
    final per = {for (final p in periods) asInt(p['id']): p};
    final blocks = <String>{}, rooms = <int>{}, people = <int>{};
    final byDay = <String, int>{};
    final courses = <int, CourseLine>{};
    var minutes = 0;
    int? first, last;
    for (final s in slots) {
      final p = per[asInt(s['period_id'])] ?? const {};
      final a = _minutes(p['start_time']), b = _minutes(p['end_time']);
      final len = a != null && b != null && b > a ? b - a : 0;
      minutes += len;
      if (a != null && (first == null || a < first)) first = a;
      if (b != null && (last == null || b > last)) last = b;
      byDay['${s['day']}'] = (byDay['${s['day']}'] ?? 0) + 1;
      final c = courses.putIfAbsent(asInt(s['course_id']), () => CourseLine(asInt(s['course_id'])));
      c.periods++;
      c.minutes += len;
      if (s['room_id'] != null) {
        rooms.add(asInt(s['room_id']));
        c.rooms.add(asInt(s['room_id']));
      }
      for (final k in const ['teacher_id', 'assistant_id', 'admin_assistant_id']) {
        if (s[k] != null) people.add(asInt(s[k]));
      }
      if (blocks.add(blockKey(s))) {
        s['kind'] == 'lab' ? c.labs++ : c.lectures++;
      }
    }
    String? hm(int? m) => m == null ? null : '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    return TimetableSummary._(
      sessions: blocks.length,
      periods: slots.length,
      minutes: minutes,
      byDay: {for (final d in orgDays) if (byDay.containsKey(d)) d: byDay[d]!},
      courses: courses.values.toList()..sort((a, b) => b.periods.compareTo(a.periods)),
      rooms: rooms.length,
      people: people.length,
      first: hm(first),
      last: hm(last),
    );
  }
}

class ExportSheet {
  ExportSheet({required this.title, required this.kindLabel, required this.view, required this.slots, required this.grid, required this.summary, this.member});
  final String title, kindLabel;
  final ExportView view;
  final TimetableMember? member;
  final List<Map<String, dynamic>> slots;
  final TimetableGrid grid;
  final TimetableSummary summary;
}

class ExportBook {
  ExportBook({required this.title, required this.subtitle, required this.sheets, required this.names, required this.generatedAt});
  final String title, subtitle;
  final List<ExportSheet> sheets;
  final TimetableNames names;
  final DateTime generatedAt;
  bool get rtl => AppConfig.lang == 'ar';
}

/// Scopes: full · teachers · assistants · rooms · groups · member (with [member]).
const exportScopes = ['full', 'teachers', 'assistants', 'rooms', 'groups', 'member'];

String exportScopeLabel(String s) => switch (s) {
      'full' => t('الجدول كاملاً', 'Whole timetable'),
      'teachers' => t('كل المدرسين', 'Every teacher'),
      'assistants' => t('كل المعيدين', 'Every assistant'),
      'rooms' => t('كل الأماكن', 'Every room'),
      'groups' => t('كل مجموعات الطلاب', 'Every student group'),
      _ => t('عضو محدد', 'One member'),
    };

String memberKindLabel(String k) => switch (k) {
      'teacher' => t('مدرس', 'Teacher'),
      'assistant' => t('معيد', 'Assistant'),
      'room' => t('مكان', 'Room'),
      'group' => t('مجموعة طلاب', 'Student group'),
      _ => t('الجدول', 'Timetable'),
    };

String exportMemberTitle(TimetableMember m, TimetableNames n) => switch (m.kind) {
      'teacher' || 'assistant' => n.person(m.id),
      'room' => n.room(m.id),
      _ => '${n.course(m.id)} · ${m.sessionKind == 'lab' ? t('عملي', 'Lab') : t('محاضرة', 'Lecture')} G${m.groupNo ?? 1}',
    };

List<ExportSheet> exportSheets(List<Map<String, dynamic>> slots, TimetableNames names, List<Map<String, dynamic>> periods,
    {required String scope, TimetableMember? member, List<String> days = const [], String fullTitle = ''}) {
  ExportSheet sheet(String title, String kind, ExportView view, List<Map<String, dynamic>> ss, [TimetableMember? m]) => ExportSheet(
        title: title,
        kindLabel: kind,
        view: view,
        member: m,
        slots: ss,
        grid: TimetableGrid.build(ss, periods, days: days),
        summary: TimetableSummary.of(ss, periods),
      );
  if (scope == 'full') return [sheet(fullTitle.isEmpty ? t('الجدول', 'Timetable') : fullTitle, memberKindLabel('full'), ExportView.full, sortSlots(slots))];
  if (scope == 'member') {
    if (member == null) return const [];
    return [sheet(exportMemberTitle(member, names), memberKindLabel(member.kind), exportViewOf(member.kind), memberTimetable(slots, member), member)];
  }
  final kind = switch (scope) { 'teachers' => 'teacher', 'assistants' => 'assistant', 'rooms' => 'room', _ => 'group' };
  final ms = timetableMembers(slots).where((m) => m.kind == kind).toList()
    ..sort((a, b) => exportMemberTitle(a, names).compareTo(exportMemberTitle(b, names)));
  return [for (final m in ms) sheet(exportMemberTitle(m, names), memberKindLabel(kind), exportViewOf(kind), memberTimetable(slots, m), m)];
}

/// The lines of one session in a cell: the course first, then what this reader needs (room / teacher / group).
List<String> sessionLines(Map<String, dynamic> s, ExportView v, TimetableNames n) {
  final kind = s['kind'] == 'lab' ? t('عملي', 'Lab') : t('محاضرة', 'Lecture');
  final g = 'G${s['group_no'] ?? 1}';
  final room = n.room(s['room_id']), teacher = n.person(s['teacher_id']), asst = n.person(s['assistant_id'] ?? s['admin_assistant_id']);
  final staff = s['kind'] == 'lab' && asst.isNotEmpty ? asst : teacher;
  return [
    n.course(s['course_id']),
    '$kind · $g',
    ...switch (v) {
      ExportView.teacher || ExportView.assistant => [room],
      ExportView.room => [staff],
      ExportView.group || ExportView.full => [room, staff],
    }.where((x) => x.isNotEmpty),
  ];
}

String periodHeader(Map<String, dynamic> p) {
  final a = _hhmm(p['start_time']), b = _hhmm(p['end_time']);
  return '${p['label'] ?? ''}${a.isEmpty ? '' : '\n${AppTime.clockRange(a, b)}'}';
}

/// Calm, print-friendly pairs: (fill, accent). A course keeps its colour across every sheet of the file.
const coursePalette = [
  ('E3F2FD', '0D47A1'),
  ('E8F5E9', '1B5E20'),
  ('FFF3E0', 'BF360C'),
  ('F3E5F5', '4A148C'),
  ('E0F7FA', '006064'),
  ('FCE4EC', '880E4F'),
  ('F1F8E9', '33691E'),
  ('FFF8E1', 'E65100'),
  ('EDE7F6', '311B92'),
  ('EFEBE9', '3E2723'),
];
const brandHex = '0F7B5F', inkHex = '1F2933', mutedHex = '6B7280', lineHex = 'D0D7DE', dayFillHex = 'F3F6F8';

Map<int, (String, String)> courseColours(Iterable<Map<String, dynamic>> slots) {
  final ids = {for (final s in slots) asInt(s['course_id'])}.toList()..sort();
  return {for (var i = 0; i < ids.length; i++) ids[i]: coursePalette[i % coursePalette.length]};
}

String _dayName(String d) => dayLabelsPlain()[d] ?? d;

List<(String, String)> summaryKpis(TimetableSummary s) => [
      (t('الحصص', 'Sessions'), '${s.sessions}'),
      (t('الفترات', 'Periods'), '${s.periods}'),
      (t('الساعات', 'Hours'), s.hours.toStringAsFixed(s.hours == s.hours.roundToDouble() ? 0 : 1)),
      (t('أيام الدوام', 'Days'), '${s.days}'),
      (t('أكثر الأيام', 'Busiest day'), s.busiestDay == null ? '—' : '${_dayName(s.busiestDay!)} (${s.byDay[s.busiestDay]})'),
      (t('من – إلى', 'First – last'), s.first == null ? '—' : AppTime.clockRange(s.first, s.last)),
    ];

List<String> courseTableHeader() => [t('المقرر', 'Course'), t('محاضرات', 'Lectures'), t('عملي', 'Labs'), t('فترات', 'Periods'), t('ساعات', 'Hours'), t('أماكن', 'Rooms')];

List<String> courseTableRow(CourseLine c, TimetableNames n) =>
    [n.course(c.courseId), '${c.lectures}', '${c.labs}', '${c.periods}', (c.minutes / 60).toStringAsFixed(c.minutes % 60 == 0 ? 0 : 1), c.rooms.map(n.room).join('، ')];

List<String> overviewHeader() => [t('العضو', 'Member'), t('النوع', 'Kind'), t('الحصص', 'Sessions'), t('الساعات', 'Hours'), t('الأيام', 'Days'), t('أكثر الأيام', 'Busiest day')];

List<String> overviewRow(ExportSheet s) => [
      s.title,
      s.kindLabel,
      '${s.summary.sessions}',
      s.summary.hours.toStringAsFixed(1),
      '${s.summary.days}',
      s.summary.busiestDay == null ? '—' : _dayName(s.summary.busiestDay!),
    ];

String _xml(Object? v) => '${v ?? ''}'
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

Uint8List _zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, body) => a.add(ArchiveFile.string(name, body)));
  return ZipEncoder().encodeBytes(a);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Excel (SpreadsheetML)
// ═════════════════════════════════════════════════════════════════════════════

class _XStyle {
  const _XStyle({this.fill, this.color = inkHex, this.bold = false, this.size = 10, this.center = true, this.wrap = true, this.border = true, this.italic = false});
  final String? fill;
  final String color;
  final bool bold, center, wrap, border, italic;
  final double size;
  String get key => '$fill|$color|$bold|$size|$center|$wrap|$border|$italic';
}

class _XStyles {
  final _fonts = <String>[], _fills = <String>[], _xfs = <String>[];
  final _index = <String, int>{};

  _XStyles() {
    style(const _XStyle(border: false, center: false, wrap: false));
  }

  int _add(List<String> list, String v) {
    final i = list.indexOf(v);
    if (i >= 0) return i;
    list.add(v);
    return list.length - 1;
  }

  int style(_XStyle s) => _index.putIfAbsent(s.key, () {
        final font = _add(_fonts, '<font>${s.bold ? '<b/>' : ''}${s.italic ? '<i/>' : ''}<sz val="${s.size}"/><color rgb="FF${s.color}"/><name val="Arial"/><family val="2"/></font>');
        final fill = s.fill == null ? 0 : 2 + _add(_fills, '<fill><patternFill patternType="solid"><fgColor rgb="FF${s.fill}"/><bgColor indexed="64"/></patternFill></fill>');
        _xfs.add('<xf numFmtId="0" fontId="$font" fillId="$fill" borderId="${s.border ? 1 : 0}" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1">'
            '<alignment horizontal="${s.center ? 'center' : 'general'}" vertical="center"${s.wrap ? ' wrapText="1"' : ''}${AppConfig.lang == 'ar' ? ' readingOrder="2"' : ''}/></xf>');
        return _xfs.length - 1;
      });

  String xml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
      '<fills count="${_fills.length + 2}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>${_fills.join()}</fills>'
      '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"><color rgb="FF$lineHex"/></left><right style="thin"><color rgb="FF$lineHex"/></right>'
      '<top style="thin"><color rgb="FF$lineHex"/></top><bottom style="thin"><color rgb="FF$lineHex"/></bottom><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="${_xfs.length}">${_xfs.join()}</cellXfs>'
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
}

String colName(int c) {
  // 0 → A, 25 → Z, 26 → AA
  var n = c + 1, s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

final _number = RegExp(r'^(0|-?[1-9]\d*)(\.\d+)?$'); // written as a number cell; "08:00", "007" stay text

class _XSheet {
  _XSheet(this.name);
  final String name;
  final _rows = <int, Map<int, (String, int)>>{}; // row → col → (value, style)
  final _heights = <int, double>{};
  final _widths = <int, double>{};
  final merges = <String>[];
  final links = <(String, String)>[]; // (cell ref, target sheet)

  void put(int r, int c, Object? v, int style) => (_rows[r] ??= {})[c] = ('${v ?? ''}', style);

  /// Writes [v] in the top-left cell and styles every cell of the range (borders and fills on merged areas).
  void merge(int r, int c, int rows, int cols, Object? v, int style) {
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        put(r + i, c + j, i == 0 && j == 0 ? v : '', style);
      }
    }
    if (rows > 1 || cols > 1) merges.add('${colName(c)}${r + 1}:${colName(c + cols - 1)}${r + rows}');
  }

  void height(int r, double h) => _heights[r] = h;
  void width(int c, double w) => _widths[c] = w;

  String xml() {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>'
        '<sheetViews><sheetView workbookViewId="0" showGridLines="0"${AppConfig.lang == 'ar' ? ' rightToLeft="1"' : ''}/></sheetViews>'
        '<sheetFormatPr defaultRowHeight="15"/>');
    if (_widths.isNotEmpty) {
      b.write('<cols>');
      for (final e in (_widths.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
        b.write('<col min="${e.key + 1}" max="${e.key + 1}" width="${e.value}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (final r in (_rows.keys.toList()..sort())) {
      final h = _heights[r];
      b.write('<row r="${r + 1}"${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      final cells = _rows[r]!;
      for (final c in (cells.keys.toList()..sort())) {
        final (v, st) = cells[c]!;
        final ref = '${colName(c)}${r + 1}';
        if (v.isEmpty) {
          b.write('<c r="$ref" s="$st"/>');
        } else if (_number.hasMatch(v)) {
          b.write('<c r="$ref" s="$st"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" s="$st" t="inlineStr"><is><t xml:space="preserve">${_xml(v)}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData>');
    if (merges.isNotEmpty) b.write('<mergeCells count="${merges.length}">${merges.map((m) => '<mergeCell ref="$m"/>').join()}</mergeCells>');
    if (links.isNotEmpty) {
      b.write('<hyperlinks>${links.map((l) => '<hyperlink ref="${l.$1}" location="${_xml("'${l.$2.replaceAll("'", "''")}'!A1")}" display="${_xml(l.$2)}"/>').join()}</hyperlinks>');
    }
    b.write('<pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>'
        '<pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/></worksheet>');
    return b.toString();
  }
}

/// Excel sheet names: ≤ 31 characters, none of []:*?/\ and unique in the workbook.
String sheetName(String raw, Set<String> taken) {
  var base = raw.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (base.isEmpty) base = 'Sheet';
  if (base.length > 28) base = base.substring(0, 28);
  var name = base, i = 2;
  while (taken.contains(name.toLowerCase())) {
    name = '${base.length > 25 ? base.substring(0, 25) : base} ($i)';
    i++;
  }
  taken.add(name.toLowerCase());
  return name;
}

Uint8List timetableXlsx(ExportBook book) {
  final st = _XStyles();
  final title = st.style(const _XStyle(fill: brandHex, color: 'FFFFFF', bold: true, size: 16, border: false));
  final sub = st.style(const _XStyle(color: mutedHex, italic: true, size: 9, border: false, wrap: false));
  final head = st.style(const _XStyle(fill: '134E4A', color: 'FFFFFF', bold: true, size: 9.5));
  final dayCell = st.style(const _XStyle(fill: dayFillHex, bold: true, size: 10.5));
  final free = st.style(const _XStyle(color: 'B0B7BF', size: 9));
  final section = st.style(const _XStyle(fill: 'E6F2EF', color: brandHex, bold: true, size: 11, center: false));
  final kLabel = st.style(const _XStyle(fill: dayFillHex, color: mutedHex, bold: true, size: 9));
  final kValue = st.style(const _XStyle(bold: true, size: 12, color: brandHex));
  final plain = st.style(const _XStyle(size: 10));
  final link = st.style(const _XStyle(size: 10, color: '0B63CE', bold: true, center: false));
  final colours = courseColours(book.sheets.expand((s) => s.slots));
  int sessionStyle(int course) {
    final (fill, accent) = colours[course] ?? coursePalette.first;
    return st.style(_XStyle(fill: fill, color: accent, bold: true, size: 9.5));
  }

  final taken = <String>{};
  final sheets = <_XSheet>[];
  final multi = book.sheets.length > 1;
  final overview = multi ? _XSheet(sheetName(t('نظرة عامة', 'Overview'), taken)) : null;
  final names = [for (final s in book.sheets) sheetName(s.title, taken)];

  for (var i = 0; i < book.sheets.length; i++) {
    final s = book.sheets[i];
    final x = _XSheet(names[i]);
    final cols = s.grid.periods.length + 1;
    final width = cols < 6 ? 6 : cols; // at least the six summary tiles
    x.width(0, 14);
    for (var c = 1; c < width; c++) {
      x.width(c, 20);
    }
    x.merge(0, 0, 1, width, '${s.title} · ${s.kindLabel}', title);
    x.height(0, 34);
    x.merge(1, 0, 1, width, '${book.title} · ${book.subtitle} · ${AppTime.dateTime(book.generatedAt.toUtc())}', sub);
    var r = 3;
    x.put(r, 0, t('اليوم', 'Day'), head);
    for (var c = 0; c < s.grid.periods.length; c++) {
      x.put(r, c + 1, periodHeader(s.grid.periods[c]), head);
    }
    x.height(r, 30);
    r++;
    for (final d in s.grid.days) {
      x.put(r, 0, _dayName(d), dayCell);
      var c = 1, lines = 2;
      for (final e in s.grid.rows[d]!) {
        if (e.isEmpty) {
          x.merge(r, c, 1, e.span, '', free);
        } else {
          final text = e.sessions.map((ss) => sessionLines(ss, s.view, book.names).join('\n')).join('\n— — —\n');
          final n = '\n'.allMatches(text).length + 1;
          if (n > lines) lines = n;
          x.merge(r, c, 1, e.span, text, sessionStyle(asInt(e.sessions.first['course_id'])));
        }
        c += e.span;
      }
      x.height(r, (lines * 13.5).clamp(40, 260).toDouble());
      r++;
    }
    if (s.grid.days.isEmpty) {
      x.merge(r, 0, 1, width, t('لا حصص', 'No sessions'), free);
      r++;
    }
    // summary: KPI tiles (label over value), then per course and per day
    r++;
    x.merge(r, 0, 1, width, t('الملخص', 'Summary'), section);
    x.height(r, 22);
    r++;
    final kpis = summaryKpis(s.summary);
    for (var k = 0; k < kpis.length && k < width; k++) {
      x.put(r, k, kpis[k].$1, kLabel);
      x.put(r + 1, k, kpis[k].$2, kValue);
    }
    x.height(r + 1, 26);
    r += 3;
    final ch = courseTableHeader();
    for (var k = 0; k < ch.length; k++) {
      x.put(r, k, ch[k], head);
    }
    r++;
    for (final cl in s.summary.courses) {
      final row = courseTableRow(cl, book.names);
      for (var k = 0; k < row.length; k++) {
        x.put(r, k, row[k], k == 0 ? sessionStyle(cl.courseId) : plain);
      }
      r++;
    }
    if (s.summary.byDay.isNotEmpty) {
      r++;
      x.put(r, 0, t('الفترات في اليوم', 'Periods per day'), head);
      var k = 1;
      for (final e in s.summary.byDay.entries) {
        if (k >= width) break;
        x.put(r, k, _dayName(e.key), kLabel);
        x.put(r + 1, k, '${e.value}', e.key == s.summary.busiestDay ? kValue : plain);
        k++;
      }
      x.put(r + 1, 0, '', plain);
      r += 2;
    }
    sheets.add(x);
  }

  if (overview != null) {
    final o = overview;
    final h = overviewHeader();
    o.width(0, 34);
    for (var c = 1; c < h.length; c++) {
      o.width(c, 16);
    }
    o.merge(0, 0, 1, h.length, book.title, title);
    o.height(0, 34);
    o.merge(1, 0, 1, h.length, '${book.subtitle} · ${book.sheets.length} ${t('ورقة', 'sheets')} · ${AppTime.dateTime(book.generatedAt.toUtc())}', sub);
    for (var c = 0; c < h.length; c++) {
      o.put(3, c, h[c], head);
    }
    for (var i = 0; i < book.sheets.length; i++) {
      final row = overviewRow(book.sheets[i]);
      for (var c = 0; c < row.length; c++) {
        o.put(4 + i, c, row[c], c == 0 ? link : plain);
      }
      o.links.add(('A${5 + i}', names[i]));
    }
  }

  final all = [?overview, ...sheets];
  final files = <String, String>{
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '${[for (var i = 0; i < all.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
        '</Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets>${[for (var i = 0; i < all.length; i++) '<sheet name="${_xml(all[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[for (var i = 0; i < all.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
        '<Relationship Id="rId${all.length + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
  };
  for (var i = 0; i < all.length; i++) {
    files['xl/worksheets/sheet${i + 1}.xml'] = all[i].xml();
  }
  files['xl/styles.xml'] = st.xml(); // after the sheets: every style they use is registered by now
  return _zip(files);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Word (WordprocessingML)
// ═════════════════════════════════════════════════════════════════════════════

class _W {
  _W(this.rtl);
  final bool rtl;
  final b = StringBuffer();

  String run(String text, {bool bold = false, String color = inkHex, int halfPt = 18, bool italic = false}) {
    final lines = text.split('\n');
    final rpr = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/>${bold ? '<w:b/><w:bCs/>' : ''}${italic ? '<w:i/>' : ''}'
        '<w:color w:val="$color"/><w:sz w:val="$halfPt"/><w:szCs w:val="$halfPt"/>${rtl ? '<w:rtl/>' : ''}</w:rPr>';
    return [for (var i = 0; i < lines.length; i++) '<w:r>$rpr${i > 0 ? '<w:br/>' : ''}<w:t xml:space="preserve">${_xml(lines[i])}</w:t></w:r>'].join();
  }

  String para(String runs, {String jc = 'center', int after = 0, String? shade}) =>
      '<w:p><w:pPr>${rtl ? '<w:bidi/>' : ''}<w:spacing w:before="0" w:after="$after"/>${shade == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$shade"/>'}<w:jc w:val="$jc"/></w:pPr>$runs</w:p>';

  String cell(String content, {required int width, int span = 1, String? fill}) => '<w:tc><w:tcPr><w:tcW w:w="$width" w:type="dxa"/>'
      '${span > 1 ? '<w:gridSpan w:val="$span"/>' : ''}${fill == null ? '' : '<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>'}'
      '<w:vAlign w:val="center"/></w:tcPr>$content</w:tc>';

  String table(List<int> grid, List<String> rows) => '<w:tbl><w:tblPr>${rtl ? '<w:bidiVisual/>' : ''}<w:tblW w:w="${grid.fold(0, (a, b) => a + b)}" w:type="dxa"/><w:jc w:val="center"/>'
      '<w:tblBorders>${['top', 'left', 'bottom', 'right', 'insideH', 'insideV'].map((e) => '<w:$e w:val="single" w:sz="4" w:space="0" w:color="$lineHex"/>').join()}</w:tblBorders>'
      '<w:tblLayout w:type="fixed"/><w:tblCellMar><w:top w:w="40" w:type="dxa"/><w:left w:w="60" w:type="dxa"/><w:bottom w:w="40" w:type="dxa"/><w:right w:w="60" w:type="dxa"/></w:tblCellMar></w:tblPr>'
      '<w:tblGrid>${grid.map((w) => '<w:gridCol w:w="$w"/>').join()}</w:tblGrid>${rows.join()}</w:tbl>';

  String row(List<String> cells, {bool header = false, int? height}) =>
      '<w:tr><w:trPr><w:cantSplit/>${header ? '<w:tblHeader/>' : ''}${height == null ? '' : '<w:trHeight w:val="$height" w:hRule="atLeast"/>'}</w:trPr>${cells.join()}</w:tr>';
}

Uint8List timetableDocx(ExportBook book) {
  final w = _W(book.rtl);
  const usable = 15398; // A4 landscape minus 0.5" margins, in twips
  final colours = courseColours(book.sheets.expand((s) => s.slots));
  final body = StringBuffer();

  /// [tint]: the (fill, accent) of each row's first cell — the course colour.
  String smallTable(List<String> header, List<List<String>> rows, {List<(String, String)>? tint}) {
    final cw = usable ~/ header.length;
    return w.table(List.filled(header.length, cw), [
      w.row([for (final h in header) w.cell(w.para(w.run(h, bold: true, color: 'FFFFFF', halfPt: 17)), width: cw, fill: '134E4A')], header: true),
      for (var i = 0; i < rows.length; i++)
        w.row([
          for (var k = 0; k < rows[i].length; k++)
            w.cell(w.para(w.run(rows[i][k], bold: k == 0, halfPt: 17, color: k == 0 && tint != null ? tint[i].$2 : inkHex)),
                width: cw, fill: k == 0 && tint != null ? tint[i].$1 : null),
        ]),
    ]);
  }

  void heading(String title, String subtitle) {
    body.write(w.para(w.run(title, bold: true, color: 'FFFFFF', halfPt: 32), shade: brandHex, after: 60));
    body.write(w.para(w.run(subtitle, italic: true, color: mutedHex, halfPt: 16), after: 160));
  }

  final stamp = AppTime.dateTime(book.generatedAt.toUtc());
  if (book.sheets.length > 1) {
    heading(book.title, '${book.subtitle} · ${book.sheets.length} ${t('عضو', 'members')} · $stamp');
    body.write(smallTable(overviewHeader(), [for (final s in book.sheets) overviewRow(s)]));
    body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }
  for (var i = 0; i < book.sheets.length; i++) {
    final s = book.sheets[i];
    heading('${s.title} · ${s.kindLabel}', '${book.title} · ${book.subtitle} · $stamp');
    final n = s.grid.periods.length;
    const dayW = 1500;
    final pw0 = n == 0 ? usable - dayW : (usable - dayW) ~/ n;
    final rows = <String>[
      w.row([
        w.cell(w.para(w.run(t('اليوم', 'Day'), bold: true, color: 'FFFFFF', halfPt: 17)), width: dayW, fill: '134E4A'),
        for (final p in s.grid.periods) w.cell(w.para(w.run(periodHeader(p), bold: true, color: 'FFFFFF', halfPt: 16)), width: pw0, fill: '134E4A'),
      ], header: true),
      for (final d in s.grid.days)
        w.row([
          w.cell(w.para(w.run(_dayName(d), bold: true, halfPt: 19)), width: dayW, fill: dayFillHex),
          for (final e in s.grid.rows[d]!)
            e.isEmpty
                ? w.cell(w.para(''), width: pw0 * e.span, span: e.span)
                : w.cell(
                    [
                      for (final ss in e.sessions)
                        () {
                          final ls = sessionLines(ss, s.view, book.names);
                          final accent = (colours[asInt(ss['course_id'])] ?? coursePalette.first).$2;
                          return w.para(w.run(ls.first, bold: true, color: accent, halfPt: 17) + (ls.length > 1 ? w.run('\n${ls.skip(1).join('\n')}', color: inkHex, halfPt: 15) : ''), after: 40);
                        }(),
                    ].join(),
                    width: pw0 * e.span,
                    span: e.span,
                    fill: (colours[asInt(e.sessions.first['course_id'])] ?? coursePalette.first).$1),
        ], height: 900),
    ];
    body.write(n == 0 ? w.para(w.run(t('لا فترات', 'No periods'))) : w.table([dayW, for (var k = 0; k < n; k++) pw0], rows));
    body.write(w.para('', after: 120));
    body.write(w.para(w.run(t('الملخص', 'Summary'), bold: true, color: brandHex, halfPt: 22), jc: book.rtl ? 'right' : 'left', after: 60));
    final k = summaryKpis(s.summary);
    final kw = usable ~/ k.length;
    body.write(w.table(List.filled(k.length, kw), [
      w.row([for (final x in k) w.cell(w.para(w.run(x.$1, bold: true, color: mutedHex, halfPt: 15)), width: kw, fill: dayFillHex)]),
      w.row([for (final x in k) w.cell(w.para(w.run(x.$2, bold: true, color: brandHex, halfPt: 24)), width: kw)]),
    ]));
    if (s.summary.courses.isNotEmpty) {
      body.write(w.para('', after: 80));
      body.write(smallTable(courseTableHeader(), [for (final c in s.summary.courses) courseTableRow(c, book.names)],
          tint: [for (final c in s.summary.courses) colours[c.courseId] ?? coursePalette.first]));
    }
    if (i < book.sheets.length - 1) body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
  }

  final doc = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<w:body>$body<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/>'
      '<w:pgMar w:top="720" w:right="720" w:bottom="720" w:left="720" w:header="360" w:footer="360" w:gutter="0"/>${book.rtl ? '<w:bidi/>' : ''}</w:sectPr></w:body></w:document>';
  return _zip({
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    'word/_rels/document.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'word/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:rPrDefault>'
        '<w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults></w:styles>',
    'word/document.xml': doc,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  PDF
// ═════════════════════════════════════════════════════════════════════════════

PdfColor _pc(String hex) => PdfColor.fromInt(0xFF000000 | int.parse(hex, radix: 16));

/// [regular] / [bold]: TTF bytes with Arabic glyphs (the app bundles Tajawal and Bahij).
Future<Uint8List> timetablePdf(ExportBook book, {required ByteData regular, required ByteData bold}) async {
  final doc = pw.Document(title: book.title, creator: 'NextBrain', theme: pw.ThemeData.withFont(base: pw.Font.ttf(regular), bold: pw.Font.ttf(bold)));
  final dir = book.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final colours = courseColours(book.sheets.expand((s) => s.slots));
  final stamp = AppTime.dateTime(book.generatedAt.toUtc());
  final format = PdfPageFormat.a4.landscape;

  pw.Widget header(String title, String subtitle) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: pw.BoxDecoration(color: _pc(brandHex), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Text(title, style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 4),
        pw.Text(subtitle, style: pw.TextStyle(color: _pc(mutedHex), fontSize: 8.5)),
        pw.SizedBox(height: 8),
      ]);

  pw.Widget footer(pw.Context c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(book.title, style: pw.TextStyle(color: _pc(mutedHex), fontSize: 7.5)),
        pw.Text('${c.pageNumber} / ${c.pagesCount}', style: pw.TextStyle(color: _pc(mutedHex), fontSize: 7.5)),
      ]);

  pw.Widget box(pw.Widget child, {String? fill, double? height, int flex = 1, bool expanded = true}) {
    final b = pw.Container(
      height: height,
      padding: const pw.EdgeInsets.all(3),
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(color: fill == null ? null : _pc(fill), border: pw.Border.all(color: _pc(lineHex), width: 0.5)),
      child: child,
    );
    return expanded ? pw.Expanded(flex: flex, child: b) : b;
  }

  pw.Widget table(List<String> head, List<List<String>> rows, {List<int>? flex, List<String?>? fills}) => pw.Column(children: [
        pw.Row(children: [
          for (var k = 0; k < head.length; k++)
            box(pw.Text(head[k], style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)), fill: '134E4A', flex: flex?[k] ?? 1, height: 20),
        ]),
        // a fixed row height keeps the bold first column in line with the rest
        for (var i = 0; i < rows.length; i++)
          pw.Row(children: [
            for (var k = 0; k < rows[i].length; k++)
              box(pw.Text(rows[i][k], maxLines: 1, style: pw.TextStyle(fontSize: 8, fontWeight: k == 0 ? pw.FontWeight.bold : null), textAlign: pw.TextAlign.center),
                  fill: k == 0 && fills != null ? fills[i] : null, flex: flex?[k] ?? 1, height: 18),
          ]),
      ]);

  if (book.sheets.length > 1) {
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      textDirection: dir,
      header: (_) => header(book.title, '${book.subtitle} · ${book.sheets.length} ${t('عضو', 'members')} · $stamp'),
      footer: footer,
      build: (_) => [table(overviewHeader(), [for (final s in book.sheets) overviewRow(s)], flex: const [3, 2, 1, 1, 1, 2])],
    ));
  }
  for (final s in book.sheets) {
    final n = s.grid.periods.length;
    final rowH = s.grid.days.isEmpty ? 40.0 : ((format.availableHeight - 230) / s.grid.days.length).clamp(34.0, 70.0);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(24),
      textDirection: dir,
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        header('${s.title} · ${s.kindLabel}', '${book.title} · ${book.subtitle} · $stamp'),
        if (n == 0)
          pw.Text(t('لا فترات', 'No periods'))
        else ...[
          pw.Row(children: [
            pw.SizedBox(
                width: 62, child: box(pw.Text(t('اليوم', 'Day'), style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold)), fill: '134E4A', height: 28, expanded: false)),
            for (final p in s.grid.periods)
              box(pw.Text(periodHeader(p), textAlign: pw.TextAlign.center, style: pw.TextStyle(color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)), fill: '134E4A', height: 28, flex: 1),
          ]),
          for (final d in s.grid.days)
            pw.Row(children: [
              pw.SizedBox(width: 62, child: box(pw.Text(_dayName(d), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)), fill: dayFillHex, height: rowH, expanded: false)),
              for (final e in s.grid.rows[d]!)
                e.isEmpty
                    ? box(pw.SizedBox(), height: rowH, flex: e.span)
                    : box(
                        pw.FittedBox(
                          fit: pw.BoxFit.scaleDown,
                          child: pw.Column(mainAxisSize: pw.MainAxisSize.min, children: [
                            for (final ss in e.sessions) ...() {
                              final ls = sessionLines(ss, s.view, book.names);
                              final accent = (colours[asInt(ss['course_id'])] ?? coursePalette.first).$2;
                              return [
                                pw.Text(ls.first, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _pc(accent))),
                                for (final l in ls.skip(1)) pw.Text(l, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 7, color: _pc(inkHex))),
                                pw.SizedBox(height: 2),
                              ];
                            }(),
                          ]),
                        ),
                        fill: (colours[asInt(e.sessions.first['course_id'])] ?? coursePalette.first).$1,
                        height: rowH,
                        flex: e.span),
            ]),
        ],
        pw.SizedBox(height: 10),
        pw.Row(children: [
          for (final k in summaryKpis(s.summary))
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                padding: const pw.EdgeInsets.symmetric(vertical: 5),
                decoration: pw.BoxDecoration(color: _pc(dayFillHex), borderRadius: pw.BorderRadius.circular(5)),
                child: pw.Column(children: [
                  pw.Text(k.$1, style: pw.TextStyle(fontSize: 7, color: _pc(mutedHex))),
                  pw.Text(k.$2, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pc(brandHex))),
                ]),
              ),
            ),
        ]),
        pw.SizedBox(height: 6),
        if (s.summary.courses.isNotEmpty)
          table(courseTableHeader(), [for (final cl in s.summary.courses.take(8)) courseTableRow(cl, book.names)],
              flex: const [3, 1, 1, 1, 1, 3], fills: [for (final cl in s.summary.courses.take(8)) (colours[cl.courseId] ?? coursePalette.first).$1]),
        pw.Spacer(),
        footer(c),
      ]),
    ));
  }
  return doc.save();
}

// ═════════════════════════════════════════════════════════════════════════════
//  UI
// ═════════════════════════════════════════════════════════════════════════════

const exportFormats = ['xlsx', 'docx', 'pdf'];

/// Builds the book for [scope] and the chosen [format]; returns the file bytes.
Future<Uint8List> buildTimetableFile(ExportBook book, String format) async => switch (format) {
      'xlsx' => timetableXlsx(book),
      'docx' => timetableDocx(book),
      _ => await timetablePdf(book, regular: await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'), bold: await rootBundle.load('assets/fonts/Bahij_TheSansArabic-Bold.ttf')),
    };

/// The export sheet: scope (whole timetable, every teacher / assistant / room / group, one member), member, format.
Future<void> showTimetableExport(BuildContext context,
    {required List<Map<String, dynamic>> slots,
    required TimetableNames names,
    required List<Map<String, dynamic>> periods,
    required String title,
    required String sourceLabel,
    List<String> days = const [],
    TimetableMember? member}) =>
    showAdminSheet<void>(
      context,
      (_) => _ExportSheet(slots: slots, names: names, periods: periods, title: title, sourceLabel: sourceLabel, days: days, member: member),
    );

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.slots, required this.names, required this.periods, required this.title, required this.sourceLabel, required this.days, this.member});
  final List<Map<String, dynamic>> slots;
  final TimetableNames names;
  final List<Map<String, dynamic>> periods;
  final String title, sourceLabel;
  final List<String> days;
  final TimetableMember? member;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late String scope = widget.member == null ? 'full' : 'member';
  late TimetableMember? member = widget.member;
  String memberKind = 'teacher';
  String format = 'xlsx';
  bool busy = false;

  late final members = timetableMembers(widget.slots);

  @override
  void initState() {
    super.initState();
    if (widget.member != null) memberKind = widget.member!.kind;
  }

  List<ExportSheet> get _sheets => exportSheets(widget.slots, widget.names, widget.periods, scope: scope, member: member, days: widget.days, fullTitle: widget.title);

  Future<void> _save() async {
    final sheets = _sheets;
    if (sheets.isEmpty) return toast(t('لا يوجد ما يُصدَّر لهذا الاختيار', 'Nothing to export for this choice'), error: true);
    setState(() => busy = true);
    try {
      final book = ExportBook(title: widget.title, subtitle: widget.sourceLabel, sheets: sheets, names: widget.names, generatedAt: DateTime.now());
      final bytes = await buildTimetableFile(book, format);
      final suffix = scope == 'member' ? exportMemberTitle(member!, widget.names) : exportScopeLabel(scope);
      await FileSaver.instance.saveFile(
        name: '${widget.title} - $suffix'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_'),
        bytes: bytes,
        fileExtension: format,
        mimeType: switch (format) { 'xlsx' => MimeType.microsoftExcel, 'docx' => MimeType.microsoftWord, _ => MimeType.pdf },
      );
      toast(t('حُفظ الملف', 'File saved'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(t('تعذر إنشاء الملف', 'Could not create the file'), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ofKind = members.where((m) => m.kind == memberKind).toList()..sort((a, b) => exportMemberTitle(a, widget.names).compareTo(exportMemberTitle(b, widget.names)));
    final sheets = _sheets;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SheetHeader(t('تصدير الجدول', 'Export the timetable')),
      Text('${widget.title} · ${widget.sourceLabel}', style: orgText(context, size: 12, color: c.textMedium)),
      const SizedBox(height: 10),
      OrgSectionTitle(t('لمن؟', 'For whom?')),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in exportScopes)
          ChoiceChip(
            label: Text(exportScopeLabel(s)),
            selected: scope == s,
            onSelected: (_) => setState(() {
              scope = s;
              if (s == 'member' && (member == null || member!.kind != memberKind)) member = ofKind.firstOrNull;
            }),
          ),
      ]),
      if (scope == 'member') ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final k in const ['teacher', 'assistant', 'room', 'group'])
            ChoiceChip(
              label: Text(memberKindLabel(k)),
              selected: memberKind == k,
              onSelected: (_) => setState(() {
                memberKind = k;
                member = members.where((m) => m.kind == k).firstOrNull;
              }),
            ),
        ]),
        const SizedBox(height: 8),
        if (ofKind.isEmpty)
          Text(t('لا أحد من هذا النوع في الجدول', 'Nobody of this kind in the timetable'), style: orgText(context, size: 12, color: c.textMedium))
        else
          DropdownButtonFormField<String>(
            initialValue: ofKind.any((m) => m.key == member?.key) ? member!.key : ofKind.first.key,
            isExpanded: true,
            decoration: InputDecoration(labelText: memberKindLabel(memberKind), isDense: true),
            items: [for (final m in ofKind) DropdownMenuItem(value: m.key, child: Text(exportMemberTitle(m, widget.names), overflow: TextOverflow.ellipsis))],
            onChanged: (k) => setState(() => member = ofKind.firstWhere((m) => m.key == k)),
          ),
      ],
      const SizedBox(height: 14),
      OrgSectionTitle(t('الصيغة', 'Format')),
      SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'xlsx', icon: const Icon(Icons.grid_on_rounded), label: Text(t('إكسل', 'Excel'))),
          ButtonSegment(value: 'docx', icon: const Icon(Icons.description_rounded), label: Text(t('وورد', 'Word'))),
          ButtonSegment(value: 'pdf', icon: const Icon(Icons.picture_as_pdf_rounded), label: Text(t('PDF', 'PDF'))),
        ],
        selected: {format},
        onSelectionChanged: (v) => setState(() => format = v.first),
      ),
      const SizedBox(height: 10),
      Text(
        sheets.isEmpty
            ? t('لا يوجد ما يُصدَّر', 'Nothing to export')
            : t('${sheets.length} ${sheets.length == 1 ? 'جدول' : 'جداول'}${sheets.length > 1 ? ' + صفحة نظرة عامة' : ''} · خلايا مدمجة للحصص الممتدة · لون لكل مقرر · ملخص تحت كل جدول',
                '${sheets.length} timetable${sheets.length == 1 ? '' : 's'}${sheets.length > 1 ? ' + an overview page' : ''} · merged cells for long sessions · a colour per course · a summary under each'),
        style: orgText(context, size: 12, color: c.textMedium),
      ),
      const SizedBox(height: 14),
      PrimaryButton(label: t('إنشاء الملف', 'Create the file'), isLoading: busy, onPressed: busy || sheets.isEmpty ? null : _save),
    ]);
  }
}
