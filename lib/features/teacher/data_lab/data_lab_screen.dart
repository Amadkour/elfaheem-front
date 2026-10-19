// lib/features/shared/data_lab/data_lab_screen.dart
// The teacher's Data Lab for one course — one calm sheet:
//   • tap a column title to sort, drag the edge of a title to resize it
//   • "Columns" decides what is visible in the table and what the students see
//   • tap any value to change it (a value you type replaces the automatic one; clear it to get the automatic one back)
//   • "Numbers / Bars / Both" changes how values are drawn
//   • zoom with the − / + buttons (or Ctrl + mouse wheel on the web) to fit more or read easier
//   • the ⋮ menu holds the rest: import, export, certificates, ask students, new column
//   • the sheet scrolls sideways by dragging, with Shift + wheel, or with the scrollbar
//
// Open it from the course profile / analytics hub:
//   Navigator.push(context, MaterialPageRoute(
//       builder: (_) => DataLabScreen(courseId: course.id, courseTitle: title)));
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show GestureBinding, PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, EmptyState, ErrorRetry;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../student/courses/details/student_analytics_profile_screen.dart';
import 'data_lab_certificates_sheet.dart';
import 'data_lab_column_sheet.dart';
import 'data_lab_columns_sheet.dart';
import 'data_lab_export_sheet.dart';
import 'data_lab_import_sheet.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_requests.dart';
import 'data_lab_widgets.dart';

// Base sizes at 100% zoom. Everything in the sheet is multiplied by the zoom factor,
// so rows and columns always stay perfectly aligned.
const double _nameW = 168, _rowH = 56, _headH = 54, _avgH = 38;
const double _minZoom = 0.7, _maxZoom = 1.5;

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
  Timer? _debounce;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 600) context.read<DataLabProvider>().loadMore();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _hScroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setZoom(double v) {
    final n = (v.clamp(_minZoom, _maxZoom) as num).toDouble();
    final stepped = (n * 20).round() / 20; // steps of 5%
    if (stepped == _zoom) return;
    setState(() => _zoom = stepped);
  }

  void _search(DataLabProvider p, String v) {
    _debounce?.cancel();
    // Wait until the teacher pauses typing — one request instead of one per letter.
    _debounce = Timer(const Duration(milliseconds: 350), () => p.setSearch(v));
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
          cacheExtent: 800,
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
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent && (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
                      GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
                        final dy = (ev as PointerScrollEvent).scrollDelta.dy;
                        _setZoom(_zoom * (dy > 0 ? 0.94 : 1.06));
                      });
                    }
                  },
                  child: RepaintBoundary(
                    child: DlCard(padding: EdgeInsets.zero, child: _SheetTable(p: p, hScroll: _hScroll, zoom: _zoom)),
                  ),
                ),
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
      maxWith: 2000,
      appBar: ScreenAppBar(title: 'dl_title'.tr),
      child: body,
    );
  }

  // ── header: the course, how many students, and two friendly rings ────────
  Widget _header(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final prog = p.stat('progress')?.avg, att = p.stat('attendance')?.avg;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusLarge),
        border: Border.all(color: c.divider),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
          child: Icon(Icons.table_chart_rounded, color: c.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.courseTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(16, w: FontWeight.w800, c: c.textDark, h: 1.3)),
            const SizedBox(height: 3),
            Text('${p.grid?.studentsTotal ?? 0} ${'dl_students'.tr}', style: dlText(12.5, c: c.textMedium)),
          ]),
        ),
        const SizedBox(width: 10),
        _Ring(label: 'dl_progress'.tr, value: prog, color: c.primary),
        const SizedBox(width: 12),
        _Ring(label: 'dl_attendance'.tr, value: att, color: c.success),
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
              onChanged: (v) => _search(p, v),
              style: dlText(14, c: c.textDark),
              decoration: InputDecoration(
                hintText: 'dl_search_hint'.tr,
                hintStyle: dlText(13, c: c.textLight),
                prefixIcon: Icon(Icons.search_rounded, color: c.textMedium),
                // Only this little button rebuilds while typing — not the whole sheet.
                suffixIcon: ListenableBuilder(
                  listenable: _searchCtrl,
                  builder: (_, __) => _searchCtrl.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                    icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
                    onPressed: () {
                      _debounce?.cancel();
                      _searchCtrl.clear();
                      p.setSearch('');
                    },
                  ),
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

  // ── numbers / bars / both  +  zoom  (+ selection chip when someone is ticked) ──
  Widget _subBar(BuildContext context, DataLabProvider p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _ViewToggle(p: p),
          _ZoomControl(zoom: _zoom, onChanged: _setZoom),
        ]),
        if (p.selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: p.clearSelection,
              borderRadius: BorderRadius.circular(20),
              child: DlTag('${p.selected.length} ${'dl_selected'.tr}  ✕', context.colors.primary),
            ),
          ),
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

/// A soft ring with the percentage in the middle.
class _Ring extends StatelessWidget {
  const _Ring({required this.label, required this.value, required this.color});

  final String label;
  final double? value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 46,
        height: 46,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              value: v == null ? 0 : (v / 100).clamp(0.0, 1.0),
              strokeWidth: 5,
              strokeCap: StrokeCap.round,
              backgroundColor: color.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(v == null ? '–' : '${v.round()}', style: dlText(13, w: FontWeight.w800, c: c.textDark)),
        ]),
      ),
      const SizedBox(height: 3),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10, c: c.textMedium)),
    ]);
  }
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

/// − 100% +   (tap the percentage to go back to 100%)
class _ZoomControl extends StatelessWidget {
  const _ZoomControl({required this.zoom, required this.onChanged});

  final double zoom;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget btn(IconData icon, bool enabled, VoidCallback onTap) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: enabled ? onTap : null,
      child: SizedBox(width: 34, height: 32, child: Icon(icon, size: 18, color: enabled ? c.textMedium : c.textLight.withValues(alpha: 0.5))),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(15), border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove_rounded, zoom > _minZoom + 0.001, () => onChanged(zoom - 0.1)),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onChanged(1.0),
          child: SizedBox(
            width: 46,
            height: 32,
            child: Center(child: Text('${(zoom * 100).round()}%', style: dlText(12, w: FontWeight.w800, c: c.textDark))),
          ),
        ),
        btn(Icons.add_rounded, zoom < _maxZoom - 0.001, () => onChanged(zoom + 0.1)),
      ]),
    );
  }
}

/// Numbers | Bars | Both — only the chosen one shows its name, so it stays small.
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
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: on ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: on ? Colors.white : c.textMedium),
            if (on) ...[
              const SizedBox(width: 5),
              Text(label, style: dlText(11.5, w: FontWeight.w700, c: Colors.white)),
            ],
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
  const _SheetTable({required this.p, required this.hScroll, required this.zoom});

  final DataLabProvider p;
  final ScrollController hScroll;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final cols = p.shownColumns;
    final line = BorderSide(color: c.divider.withValues(alpha: 0.6));
    final avgBg = c.primary.withValues(alpha: 0.04);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── frozen names ──────────────────────────────────────────────────
      Container(
        width: _nameW * z,
        decoration: BoxDecoration(border: BorderDirectional(end: line)),
        child: Column(children: [
          Container(
            height: _headH * z,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.only(start: 16),
            color: c.primary.withValues(alpha: 0.08),
            child: Text('dl_student'.tr, style: dlText(12.5 * z, w: FontWeight.w800, c: c.primary)),
          ),
          Container(
            height: _avgH * z,
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.only(start: 16),
            color: avgBg,
            child: Text('dl_class_avg'.tr, style: dlText(11.5 * z, w: FontWeight.w700, c: c.textMedium)),
          ),
          for (final r in p.rows) RepaintBoundary(child: _NameCell(p: p, row: r, zoom: z)),
        ]),
      ),
      // ── scrolling values (horizontal only) ────────────────────────────
      Expanded(
        child: ScrollConfiguration(
          behavior: _DragScroll(),
          child: Scrollbar(
            controller: hScroll,
            thumbVisibility: kIsWeb,
            child: SingleChildScrollView(
              controller: hScroll,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Column(children: [
                Row(children: [for (final col in cols) _HeadCell(p: p, col: col, zoom: z)]),
                Container(
                  height: _avgH * z,
                  color: avgBg,
                  child: Row(children: [
                    for (final col in cols)
                      SizedBox(
                        width: p.widthOf(col.key) * z,
                        child: Center(
                          child: Text(col.isNumber ? dlFmt(p.stat(col.key)?.avg) : '',
                              style: dlText(12 * z, w: FontWeight.w700, c: c.textMedium)),
                        ),
                      ),
                  ]),
                ),
                for (final r in p.rows)
                  RepaintBoundary(
                    child: Container(
                      height: _rowH * z,
                      decoration: BoxDecoration(border: Border(top: line)),
                      child: Row(children: [for (final col in cols) _ValueCell(p: p, row: r, col: col, zoom: z)]),
                    ),
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
  const _HeadCell({required this.p, required this.col, required this.zoom});

  final DataLabProvider p;
  final DlColumn col;
  final double zoom;

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
    final z = zoom;
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
      width: p.widthOf(col.key) * z,
      height: _headH * z,
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
                    style: dlText(12 * z, w: FontWeight.w800, c: sorted ? c.primary : c.textDark, h: 1.25)),
                // Only the few signs that really matter: sorted, calculated, shown to students.
                if (sorted || col.visibleToStudents || col.isCalculated)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(children: [
                      if (sorted) Icon(p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 12 * z, color: c.primary),
                      if (col.isCalculated) Icon(Icons.functions_rounded, size: 12 * z, color: c.purple),
                      if (col.visibleToStudents) Icon(Icons.visibility_rounded, size: 12 * z, color: c.success),
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
        // drag handle: pull the edge to resize (the drag is divided by the zoom so it follows the finger)
        PositionedDirectional(
          end: 0,
          top: 0,
          bottom: 0,
          width: 12,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => p.setWidth(col.key, p.widthOf(col.key) + (rtl ? -d.delta.dx : d.delta.dx) / z),
              child: Center(
                child: Container(
                  width: 3,
                  height: 20,
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
  const _NameCell({required this.p, required this.row, required this.zoom});

  final DataLabProvider p;
  final DlRow row;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
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
        height: _rowH * z,
        padding: const EdgeInsetsDirectional.only(start: 4, end: 6),
        decoration: BoxDecoration(
          color: picked ? c.primary.withValues(alpha: 0.07) : null,
          border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.6))),
        ),
        child: Row(children: [
          if (isStudent)
            Checkbox(
              value: picked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: c.primary,
              onChanged: (_) => p.toggleSelect(row.rowId),
            )
          else
            const SizedBox(width: 12),
          // Just the name. A small tag appears only when the student needs attention (temporary / waiting).
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(row.name.isEmpty ? '—' : row.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13 * z, w: FontWeight.w700, c: c.textDark)),
              if (row.isTemporary) ...[
                const SizedBox(height: 2),
                DlTag('dl_temporary'.tr, c.warning, icon: Icons.hourglass_bottom_rounded),
              ] else if (row.isStaged) ...[
                const SizedBox(height: 2),
                DlTag('dl_waiting'.tr, c.purple, icon: Icons.mark_email_unread_rounded),
              ],
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
  const _ValueCell({required this.p, required this.row, required this.col, required this.zoom});

  final DataLabProvider p;
  final DlRow row;
  final DlColumn col;
  final double zoom;

  bool get _editable => col.isNumber || col.isCustom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final v = row.values[col.key];
    final manual = row.overridden.contains(col.key);
    Widget content;
    if (col.isNumber && v != null) {
      final n = dlNum(v);
      final max = col.isPercent ? 100.0 : (col.maxValue == 0 ? 100.0 : col.maxValue);
      final pct = n == null ? null : n / max * 100;
      final text = Text(dlFmt(v), style: dlText(13.5 * z, w: FontWeight.w800, c: dlScoreColor(context, pct)));
      final bar = Padding(
        padding: EdgeInsets.symmetric(horizontal: (p.view == DlView.bar ? 14 : 16) * z),
        child: DlBar(value: n, max: max, height: (p.view == DlView.bar ? 9 : 5) * z, marker: p.stat(col.key)?.avg),
      );
      content = switch (p.view) {
        DlView.value => text,
        DlView.bar => Tooltip(message: dlFmt(v), child: bar),
        DlView.both => Column(mainAxisAlignment: MainAxisAlignment.center, children: [text, SizedBox(height: 2 * z), bar]),
      };
    } else if (v != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text('$v', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: dlText(12.5 * z, c: c.textDark)),
      );
    } else {
      content = Icon(_editable ? Icons.add_rounded : Icons.remove_rounded, size: 16 * z, color: c.textLight.withValues(alpha: 0.6));
    }
    return InkWell(
      onTap: _editable ? () => _edit(context, manual) : null,
      child: SizedBox(
        width: p.widthOf(col.key) * z,
        height: _rowH * z,
        child: Stack(alignment: Alignment.center, children: [
          content,
          if (manual)
            PositionedDirectional(top: 7 * z, end: 9 * z, child: Icon(Icons.edit_rounded, size: 10 * z, color: c.primary.withValues(alpha: 0.8))),
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