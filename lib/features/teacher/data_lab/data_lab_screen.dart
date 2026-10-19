// lib/features/shared/data_lab/data_lab_screen.dart
// The teacher's Data Lab for one course — one calm sheet:
//   • tap a column title to sort, drag the edge of a title to resize it
//   • "Columns" decides what is visible in the table and what the students see
//   • tap any value to change it (a value you type replaces the automatic one; clear it to get the automatic one back)
//   • "Numbers / Bars / Both" changes how values are drawn
//   • the ⋮ menu holds the rest: import, export, certificates, ask students, new column
//   • on the web the sheet scrolls sideways with the mouse (drag, Shift + wheel, scrollbar or the arrow buttons)
//
// Open it from the course profile / analytics hub:
//   Navigator.push(context, MaterialPageRoute(
//       builder: (_) => DataLabScreen(courseId: course.id, courseTitle: title)));
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, EmptyState, ErrorRetry;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'data_lab_certificates_sheet.dart';
import 'data_lab_column_sheet.dart';
import 'data_lab_columns_sheet.dart';
import 'data_lab_export_sheet.dart';
import 'data_lab_import_sheet.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_requests.dart';
import 'data_lab_widgets.dart';
import 'student_analytics_profile_screen.dart';

const double _nameW = 176, _rowH = 58, _headH = 56, _avgH = 40;

/// Lets a mouse / trackpad drag the sheet sideways (Flutter web only scrolls with touch by default).
class _DragScroll extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };
}

class DataLabScreen extends StatelessWidget {
  const DataLabScreen({super.key, required this.courseId, required this.courseTitle});

  final int courseId;
  final String courseTitle;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => DataLabProvider(courseId)..load(),
    child: _DataLabView(courseTitle: courseTitle),
  );
}

class _DataLabView extends StatefulWidget {
  const _DataLabView({required this.courseTitle});

  final String courseTitle;

  @override
  State<_DataLabView> createState() => _DataLabViewState();
}

class _DataLabViewState extends State<_DataLabView> {
  final _scroll = ScrollController();
  final _hScroll = ScrollController();
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 400) context.read<DataLabProvider>().loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _hScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _slide(double dx) {
    if (!_hScroll.hasClients) return;
    final max = _hScroll.position.maxScrollExtent;
    _hScroll.animateTo((_hScroll.offset + dx).clamp(0.0, max), duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DataLabProvider>();
    Widget body;
    if (p.loading && p.grid == null) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.grid == null) {
      body = ErrorRetry(message: p.error!, onRetry: p.load);
    } else {
      body = RefreshIndicator(
        onRefresh: () => p.load(silent: true),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 90),
          children: [
            _header(context, p),
            _toolbar(context, p),
            _subBar(context, p),
            if (p.rows.isEmpty)
              _empty(context, p)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DlCard(padding: EdgeInsets.zero, child: _SheetTable(p: p, hScroll: _hScroll)),
              ),
            if (p.loadingMore)
              const Padding(padding: EdgeInsets.all(18), child: Center(child: AppLoadingIndicator()))
            else if (p.rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: Text('${'dl_showing'.tr} ${p.rows.length} / ${p.total}', style: dlText(12, c: context.colors.textMedium)),
                ),
              ),
          ],
        ),
      );
    }
    return BasePage(
      key: const ValueKey('data_lab'),
      useWebCard: true,
      appBar: ScreenAppBar(title: 'dl_title'.tr),
      child: body,
    );
  }

  // ── header: course + two numbers, nothing else ───────────────────────────
  Widget _header(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final prog = p.stat('progress')?.avg, att = p.stat('attendance')?.avg;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(c.radiusLarge),
        gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
        boxShadow: c.primaryShadow,
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.courseTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(18, w: FontWeight.w800, c: Colors.white, h: 1.3)),
            const SizedBox(height: 4),
            Text('${p.grid?.studentsTotal ?? 0} ${'dl_students'.tr}', style: dlText(12.5, c: Colors.white70)),
          ]),
        ),
        const SizedBox(width: 10),
        _MiniStat(label: 'dl_progress'.tr, value: prog),
        const SizedBox(width: 8),
        _MiniStat(label: 'dl_attendance'.tr, value: att),
      ]),
    );
  }

  // ── search + columns + ⋮ ─────────────────────────────────────────────────
  Widget _toolbar(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                p.setSearch(v);
                setState(() {});
              },
              style: dlText(14, c: c.textDark),
              decoration: InputDecoration(
                hintText: 'dl_search_hint'.tr,
                hintStyle: dlText(13, c: c.textLight),
                prefixIcon: Icon(Icons.search_rounded, color: c.textMedium),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                  icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    p.setSearch('');
                    setState(() {});
                  },
                ),
                filled: true,
                fillColor: c.cardBg,
                contentPadding: EdgeInsets.zero,
                border: b(c.divider),
                enabledBorder: b(c.divider),
                focusedBorder: b(c.primary, 1.6),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _SquareButton(
          icon: Icons.view_column_rounded,
          tooltip: 'dl_columns'.tr,
          badge: p.hiddenCount,
          onTap: () => showColumnsSheet(context, p),
        ),
        const SizedBox(width: 8),
        _moreMenu(context, p),
      ]),
    );
  }

  Widget _moreMenu(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final cfg = p.config;
    bool on(String key) => !AppConfig.disableList.contains(key);
    PopupMenuEntry<String> item(String value, IconData icon, String label, {bool enabled = true, Color? color}) => PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      child: Row(children: [
        Icon(icon, size: 20, color: enabled ? (color ?? c.primary) : c.textLight),
        const SizedBox(width: 12),
        Text(label, style: dlText(13.5, w: FontWeight.w700, c: enabled ? c.textDark : c.textLight)),
      ]),
    );
    return PopupMenuButton<String>(
      tooltip: 'dl_more'.tr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: c.cardBg,
      onSelected: (v) {
        switch (v) {
          case 'import':
            showImportWizard(context, p);
          case 'export':
            showExportSheet(context, p);
          case 'certs':
            showCertificatesSheet(context, p);
          case 'ask':
            showRequestsSheet(context, p);
          case 'column':
            showColumnEditor(context, p);
        }
      },
      itemBuilder: (_) => [
        if (on('data_lab.import')) item('import', Icons.upload_file_rounded, 'dl_import'.tr, enabled: cfg.allowImport),
        if (on('data_lab.export')) item('export', Icons.ios_share_rounded, 'dl_export'.tr, enabled: cfg.allowExport, color: c.success),
        if (on('data_lab.certificates'))
          item('certs', Icons.workspace_premium_rounded, 'dl_certificates'.tr, enabled: cfg.allowCertificates, color: c.accent),
        if (on('data_lab.requests'))
          item('ask', Icons.mark_chat_unread_rounded, 'dl_ask_students'.tr, enabled: cfg.allowStudentRequests, color: c.warning),
        if (on('data_lab.columns')) item('column', Icons.add_chart_rounded, 'dl_new_column'.tr, color: c.purple),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.more_horiz_rounded, color: Colors.white),
      ),
    );
  }

  // ── numbers / bars / both  +  selection  +  web arrows ───────────────────
  Widget _subBar(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(children: [
        _ViewToggle(p: p),
        const SizedBox(width: 10),
        if (p.selected.isNotEmpty)
          Flexible(
            child: InkWell(
              onTap: p.clearSelection,
              borderRadius: BorderRadius.circular(20),
              child: DlTag('${p.selected.length} ${'dl_selected'.tr}  ✕', c.primary),
            ),
          ),
        const Spacer(),
        if (kIsWeb) ...[
          _ArrowButton(icon: Icons.chevron_left_rounded, onTap: () => _slide(-320)),
          const SizedBox(width: 6),
          _ArrowButton(icon: Icons.chevron_right_rounded, onTap: () => _slide(320)),
        ],
      ]),
    );
  }

  Widget _empty(BuildContext context, DataLabProvider p) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(children: [
      SizedBox(height: 200, child: EmptyState(p.search.isEmpty ? 'dl_empty'.tr : 'dl_no_match'.tr, icon: Icons.table_chart_rounded)),
      if (p.search.isEmpty && p.config.allowImport)
        DlActionPill(icon: Icons.upload_file_rounded, label: 'dl_import'.tr, onTap: () => showImportWizard(context, p)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small controls
// ─────────────────────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(value == null ? '–' : '${value!.round()}%', style: dlText(16, w: FontWeight.w800, c: Colors.white)),
      Text(label, style: dlText(10, c: Colors.white70)),
    ]),
  );
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
            child: Icon(icon, color: c.primary),
          ),
          if (badge > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: c.warning, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: dlText(10, w: FontWeight.w800, c: Colors.white)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.divider)),
        child: Icon(icon, color: c.textMedium),
      ),
    );
  }
}

/// Numbers | Bars | Both
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.p});

  final DataLabProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(DlView v, IconData icon, String label) {
      final on = p.view == v;
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => p.setView(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: on ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: on ? Colors.white : c.textMedium),
            const SizedBox(width: 5),
            Text(label, style: dlText(11.5, w: FontWeight.w700, c: on ? Colors.white : c.textMedium)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(15), border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(DlView.value, Icons.pin_rounded, 'dl_view_value'.tr),
        seg(DlView.bar, Icons.align_horizontal_left_rounded, 'dl_view_bar'.tr),
        seg(DlView.both, Icons.view_agenda_rounded, 'dl_view_both'.tr),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The sheet: frozen name column + sideways-scrolling value columns (fixed row heights keep them aligned)
// ─────────────────────────────────────────────────────────────────────────────

class _SheetTable extends StatelessWidget {
  const _SheetTable({required this.p, required this.hScroll});

  final DataLabProvider p;
  final ScrollController hScroll;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cols = p.shownColumns;
    final line = BorderSide(color: c.divider.withValues(alpha: 0.7));
    final avgBg = c.primary.withValues(alpha: 0.04);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── frozen names ──────────────────────────────────────────────────
      Container(
        width: _nameW,
        decoration: BoxDecoration(border: BorderDirectional(end: line)),
        child: Column(children: [
          Container(
            height: _headH,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.only(start: 16),
            color: c.primary.withValues(alpha: 0.08),
            child: Text('dl_student'.tr, style: dlText(12.5, w: FontWeight.w800, c: c.primary)),
          ),
          Container(
            height: _avgH,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.only(start: 16),
            color: avgBg,
            child: Text('dl_class_avg'.tr, style: dlText(11.5, w: FontWeight.w700, c: c.textMedium)),
          ),
          for (final r in p.rows) _NameCell(p: p, row: r),
        ]),
      ),
      // ── scrolling values ──────────────────────────────────────────────
      Expanded(
        child: ScrollConfiguration(
          behavior: _DragScroll(),
          child: Scrollbar(
            controller: hScroll,
            thumbVisibility: kIsWeb,
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              child: Column(children: [
                Row(children: [for (final col in cols) _HeadCell(p: p, col: col)]),
                Container(
                  height: _avgH,
                  color: avgBg,
                  child: Row(children: [
                    for (final col in cols)
                      SizedBox(
                        width: p.widthOf(col.key),
                        child: Center(
                          child: Text(col.isNumber ? dlFmt(p.stat(col.key)?.avg) : '',
                              style: dlText(12, w: FontWeight.w700, c: c.textMedium)),
                        ),
                      ),
                  ]),
                ),
                for (final r in p.rows)
                  Container(
                    height: _rowH,
                    decoration: BoxDecoration(border: Border(top: line)),
                    child: Row(children: [for (final col in cols) _ValueCell(p: p, row: r, col: col)]),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell({required this.p, required this.col});

  final DataLabProvider p;
  final DlColumn col;

  Future<void> _menu(BuildContext context, String v) async {
    switch (v) {
      case 'edit':
        showColumnEditor(context, p, column: col);
      case 'hide':
        final e = await p.setColumnFlags(col, hidden: true);
        if (e != null) toast(e, error: true);
      case 'students':
        final e = await p.setColumnFlags(col, students: !col.visibleToStudents);
        if (e != null) toast(e, error: true);
      case 'delete':
        if (!await confirm(context, message: 'dl_delete_column_q'.tr, danger: true)) return;
        final e = await p.deleteColumn(col.key);
        if (e != null) toast(e, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sorted = p.sort == col.key;
    PopupMenuEntry<String> it(String v, IconData icon, String label, {Color? color}) => PopupMenuItem(
      value: v,
      child: Row(children: [
        Icon(icon, size: 19, color: color ?? c.textMedium),
        const SizedBox(width: 10),
        Text(label, style: dlText(13, w: FontWeight.w700, c: color ?? c.textDark)),
      ]),
    );
    return SizedBox(
      width: p.widthOf(col.key),
      height: _headH,
      child: Stack(children: [
        Positioned.fill(
          child: InkWell(
            onTap: () => p.toggleSort(col.key),
            child: Container(
              color: c.primary.withValues(alpha: 0.08),
              padding: const EdgeInsetsDirectional.only(start: 12, end: 34),
              alignment: AlignmentDirectional.centerStart,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(col.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: dlText(12, w: FontWeight.w800, c: sorted ? c.primary : c.textDark, h: 1.25)),
                if (sorted || col.visibleToStudents || col.isCalculated)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      if (sorted) Icon(p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 12, color: c.primary),
                      if (col.isCalculated) Icon(Icons.functions_rounded, size: 12, color: c.purple),
                      if (col.visibleToStudents) Icon(Icons.visibility_rounded, size: 12, color: c.success),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
        // ⋮ menu
        PositionedDirectional(
          end: 10,
          top: 0,
          bottom: 0,
          child: PopupMenuButton<String>(
            tooltip: '',
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert_rounded, size: 18, color: c.textMedium),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: c.cardBg,
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => [
              it('edit', Icons.edit_outlined, 'dl_menu_edit'.tr),
              it('hide', Icons.visibility_off_rounded, 'dl_menu_hide'.tr),
              it('students', col.visibleToStudents ? Icons.person_off_rounded : Icons.person_rounded,
                  col.visibleToStudents ? 'dl_menu_students_hide'.tr : 'dl_menu_students_show'.tr),
              if (!col.isBuiltin) it('delete', Icons.delete_outline_rounded, 'dl_delete_column'.tr, color: c.danger),
            ],
          ),
        ),
        // drag handle: pull the edge to resize
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => p.setWidth(col.key, p.widthOf(col.key) + (rtl ? -d.delta.dx : d.delta.dx)),
              child: Center(
                child: Container(
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3)),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.p, required this.row});

  final DataLabProvider p;
  final DlRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isStudent = row.studentId != null;
    final picked = p.selected.contains(row.rowId);
    return InkWell(
      onTap: isStudent
          ? () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StudentAnalyticsProfileScreen.forTeacher(studentId: row.studentId!, studentName: row.name, courseId: p.courseId),
        ),
      )
          : null,
      child: Container(
        height: _rowH,
        padding: const EdgeInsetsDirectional.only(start: 4, end: 6),
        decoration: BoxDecoration(
          color: picked ? c.primary.withValues(alpha: 0.07) : null,
          border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.7))),
        ),
        child: Row(children: [
          if (isStudent)
            Checkbox(
              value: picked,
              visualDensity: VisualDensity.compact,
              activeColor: c.primary,
              onChanged: (_) => p.toggleSelect(row.rowId),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name.isEmpty ? '—' : row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 2),
              if (row.isTemporary)
                DlTag('dl_temporary'.tr, c.warning, icon: Icons.hourglass_bottom_rounded)
              else if (row.isStaged)
                DlTag('dl_waiting'.tr, c.purple, icon: Icons.mark_email_unread_rounded)
              else if ((row.identifier ?? row.email ?? '').isNotEmpty)
                Text(row.identifier?.isNotEmpty == true ? row.identifier! : row.email!,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10.5, c: c.textLight)),
            ]),
          ),
          if (!isStudent)
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              icon: Icon(Icons.delete_outline_rounded, size: 18, color: c.danger),
              onPressed: () async {
                if (!await confirm(context, message: 'dl_delete_row_q'.tr, danger: true)) return;
                final err = await p.deleteRow(row);
                if (err != null) toast(err, error: true);
              },
            ),
        ]),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.p, required this.row, required this.col});

  final DataLabProvider p;
  final DlRow row;
  final DlColumn col;

  bool get _editable => col.isNumber || col.isCustom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = row.values[col.key];
    final manual = row.overridden.contains(col.key);
    Widget content;
    if (col.isNumber && v != null) {
      final n = dlNum(v);
      final max = col.isPercent ? 100.0 : (col.maxValue == 0 ? 100.0 : col.maxValue);
      final pct = n == null ? null : n / max * 100;
      final text = Text(dlFmt(v), style: dlText(13.5, w: FontWeight.w800, c: dlScoreColor(context, pct)));
      final bar = Padding(
        padding: EdgeInsets.symmetric(horizontal: p.view == DlView.bar ? 14 : 16),
        child: DlBar(value: n, max: max, height: p.view == DlView.bar ? 9 : 5, marker: p.stat(col.key)?.avg),
      );
      content = switch (p.view) {
        DlView.value => text,
        DlView.bar => Tooltip(message: dlFmt(v), child: bar),
        DlView.both => Column(mainAxisAlignment: MainAxisAlignment.center, children: [text, const SizedBox(height: 2), bar]),
      };
    } else if (v != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('$v', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: dlText(12.5, c: c.textDark)),
      );
    } else {
      content = Icon(_editable ? Icons.add_rounded : Icons.remove_rounded, size: 16, color: c.textLight.withValues(alpha: 0.6));
    }
    return InkWell(
      onTap: _editable ? () => _edit(context, manual) : null,
      child: SizedBox(
        width: p.widthOf(col.key),
        height: _rowH,
        child: Stack(alignment: Alignment.center, children: [
          content,
          if (manual)
            PositionedDirectional(top: 7, end: 9, child: Icon(Icons.edit_rounded, size: 10, color: c.primary.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, bool manual) async {
    final c = context.colors;
    final ctrl = TextEditingController(text: row.values[col.key] == null ? '' : dlFmt(row.values[col.key]));
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: pageDirection,
        child: AlertDialog(
          backgroundColor: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(col.label, style: dlText(16, w: FontWeight.w800, c: c.textDark)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(row.name, style: dlText(12.5, c: c.textMedium))),
              if (manual) DlTag('dl_manual_value'.tr, c.primary, icon: Icons.edit_rounded),
            ]),
            const SizedBox(height: 12),
            if (col.options.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final o in col.options) DlChoiceChip(label: o, selected: ctrl.text == o, onTap: () => Navigator.pop(ctx, o)),
              ])
            else
              DlField(
                controller: ctrl,
                label: col.isNumber ? '${'dl_value'.tr} (0 – ${dlFmt(col.maxValue)})' : 'dl_value'.tr,
                keyboard: col.isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
              ),
            if (manual && !col.isCustom) Text('dl_manual_hint'.tr, style: dlText(11.5, c: c.textMedium, h: 1.45)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('cancel'.tr)),
            if (manual && !col.isCustom)
              TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text('dl_auto_value'.tr))
            else if (col.isCustom && ctrl.text.isNotEmpty)
              TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text('dl_clear_value'.tr)),
            if (col.options.isEmpty)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.primary),
                onPressed: () => Navigator.pop(ctx, ctrl.text),
                child: Text('save'.tr),
              ),
          ],
        ),
      ),
    );
    if (res == null) return;
    final err = await p.saveCell(row, col, res);
    if (err != null) toast(err, error: true);
  }
}
