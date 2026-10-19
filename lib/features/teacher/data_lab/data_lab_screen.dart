// lib/features/shared/data_lab/data_lab_screen.dart
// The teacher's Data Lab for one course — a full-screen sheet:
//   • slim top bar: small "exit full screen" icon, course name, quick numbers, and one button that
//     shows / hides the tools panel (search, columns, view, zoom, import / export …) so the table gets the whole height
//   • the table header and the student names stay pinned while you scroll; rows load lazily, so it stays fast
//   • two synced horizontal scrollbars: one above the table and one at its end (drag, Shift + wheel, or the bars)
//   • tap a column title to sort · press and hold it (or right-click) for that column's settings
//   • a green line under a column title means "students can see this column"
//   • zoom with − / + (or Ctrl + mouse wheel on the web)
//
// Open it from the course profile / analytics hub:
//   Navigator.push(context, MaterialPageRoute(
//       builder: (_) => DataLabScreen(courseId: course.id, courseTitle: title)));
library;

import 'dart:async';

import 'package:flutter/gestures.dart' show GestureBinding, PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, EmptyState, ErrorRetry;
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
const double _nameW = 168, _rowH = 54, _headH = 46, _avgH = 36;
const double _minZoom = 0.7, _maxZoom = 1.5;

/// Translation with a friendly English fallback while a key is not in the language files yet.
String _tr(String key, String fallback) {
  final v = key.tr;
  return (v.isEmpty || v == key) ? fallback : v;
}

/// Lets a mouse / trackpad drag the sheet (Flutter web only scrolls with touch by default).
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
  final _hTop = ScrollController(); // the scrollbar above the table
  final _hMain = ScrollController(); // the scrollbar at the end of the table
  final _vNames = ScrollController(); // student names (left)
  final _vRows = ScrollController(); // values (right) — kept in step with the names
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _syncing = false;
  bool _panelOpen = false;
  double _zoom = 1.0;

  @override
  void initState() {
    super.initState();
    _link(_hTop, _hMain);
    _link(_hMain, _hTop);
    _link(_vNames, _vRows);
    _link(_vRows, _vNames);
    _vRows.addListener(() {
      if (_vRows.hasClients && _vRows.position.extentAfter < 600) context.read<DataLabProvider>().loadMore();
    });
    // The teacher always starts with plain numbers — calm and easy to read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<DataLabProvider>();
      if (p.view != DlView.value) p.setView(DlView.value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _hTop.dispose();
    _hMain.dispose();
    _vNames.dispose();
    _vRows.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Keeps two scroll controllers at the same offset.
  void _link(ScrollController a, ScrollController b) {
    a.addListener(() {
      if (_syncing || !a.hasClients || !b.hasClients) return;
      if (!b.position.hasContentDimensions) return;
      final t = a.offset.clamp(0.0, b.position.maxScrollExtent).toDouble();
      if ((b.offset - t).abs() < 0.5) return;
      _syncing = true;
      b.jumpTo(t);
      _syncing = false;
    });
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
    final c = context.colors;
    Widget content;
    if (p.loading && p.grid == null) {
      content = const Center(child: AppLoadingIndicator());
    } else if (p.error != null && p.grid == null) {
      content = ErrorRetry(message: p.error!, onRetry: p.load);
    } else if (p.rows.isEmpty) {
      content = _empty(context, p);
    } else {
      content = Listener(
        onPointerSignal: (e) {
          if (e is PointerScrollEvent && (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed)) {
            GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
              final dy = (ev as PointerScrollEvent).scrollDelta.dy;
              _setZoom(_zoom * (dy > 0 ? 0.94 : 1.06));
            });
          }
        },
        child: _SheetTable(p: p, zoom: _zoom, hTop: _hTop, hMain: _hMain, vNames: _vNames, vRows: _vRows),
      );
    }
    return Directionality(
      textDirection: pageDirection,
      child: Scaffold(
        backgroundColor: c.cardBg,
        body: SafeArea(
          child: Column(children: [
            Container(
              decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
              child: Column(children: [_topBar(context, p), _panel(context, p)]),
            ),
            Expanded(child: content),
          ]),
        ),
      ),
    );
  }

  // ── slim top bar ─────────────────────────────────────────────────────────
  Widget _topBar(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final prog = p.stat('progress')?.avg, att = p.stat('attendance')?.avg;
    var sub = '${p.grid?.studentsTotal ?? 0} ${'dl_students'.tr}';
    if (prog != null) sub += '  ·  ${prog.round()}% ${'dl_progress'.tr}';
    if (att != null) sub += '  ·  ${att.round()}% ${'dl_attendance'.tr}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(children: [
        _BarButton(
          icon: Icons.fullscreen_exit_rounded,
          tooltip: _tr('dl_exit_full', 'Back'),
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(14.5, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 1),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(11.5, c: c.textMedium)),
          ]),
        ),
        if (p.selected.isNotEmpty) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: p.clearSelection,
            borderRadius: BorderRadius.circular(20),
            child: DlTag('${p.selected.length} ${'dl_selected'.tr}  ✕', c.primary),
          ),
        ],
        const SizedBox(width: 8),
        _BarButton(
          icon: _panelOpen ? Icons.keyboard_arrow_up_rounded : Icons.tune_rounded,
          tooltip: _tr('dl_tools', 'Tools'),
          active: _panelOpen,
          badge: _panelOpen ? 0 : p.hiddenCount,
          onTap: () => setState(() => _panelOpen = !_panelOpen),
        ),
      ]),
    );
  }

  // ── tools panel: shows / hides with one tap ──────────────────────────────
  Widget _panel(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_panelOpen
          ? const SizedBox(width: double.infinity)
          : Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
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
            _SquareButton(
              icon: Icons.refresh_rounded,
              tooltip: _tr('dl_refresh', 'Refresh'),
              onTap: () => p.load(silent: true),
            ),
            const SizedBox(width: 8),
            _moreMenu(context, p),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _ViewToggle(p: p),
            _ZoomControl(zoom: _zoom, onChanged: _setZoom),
            _Legend(),
          ]),
        ]),
      ),
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

  Widget _empty(BuildContext context, DataLabProvider p) => Center(
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(height: 200, child: EmptyState(p.search.isEmpty ? 'dl_empty'.tr : 'dl_no_match'.tr, icon: Icons.table_chart_rounded)),
        if (p.search.isEmpty && p.config.allowImport)
          DlActionPill(icon: Icons.upload_file_rounded, label: 'dl_import'.tr, onTap: () => showImportWizard(context, p)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small controls
// ─────────────────────────────────────────────────────────────────────────────

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.tooltip, required this.onTap, this.active = false, this.badge = 0});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active ? c.primary.withValues(alpha: 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: active ? c.primary.withValues(alpha: 0.35) : c.divider),
            ),
            child: Icon(icon, size: 20, color: active ? c.primary : c.textMedium),
          ),
          if (badge > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: c.warning, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge', style: dlText(9.5, w: FontWeight.w800, c: Colors.white)),
              ),
            ),
        ]),
      ),
    );
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

/// Explains the green line under a column title.
class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: c.success.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 3, decoration: BoxDecoration(color: c.success, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 7),
        Text(_tr('dl_legend_students', 'Shown to students'), style: dlText(11.5, w: FontWeight.w700, c: c.success)),
      ]),
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
// The sheet
//   ┌ top scrollbar ─────────────────────────┐
//   │ names (frozen) │ pinned column titles  │
//   │                │ class average         │
//   │  lazy rows     │  lazy rows            │   ← both lists scroll together
//   └ bottom scrollbar ──────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class _SheetTable extends StatelessWidget {
  const _SheetTable({
    required this.p,
    required this.zoom,
    required this.hTop,
    required this.hMain,
    required this.vNames,
    required this.vRows,
  });

  final DataLabProvider p;
  final double zoom;
  final ScrollController hTop, hMain, vNames, vRows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final cols = p.shownColumns;
    final rows = p.rows;
    final line = BorderSide(color: c.divider.withValues(alpha: 0.6));
    final avgBg = c.primary.withValues(alpha: 0.04);
    var totalW = 0.0;
    for (final col in cols) {
      totalW += p.widthOf(col.key) * z;
    }
    final rowCount = rows.length + 1; // +1 = footer ("showing x / y" or the loading spinner)

    final scrollbarTheme = ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(8),
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(true),
      thumbColor: WidgetStatePropertyAll(c.primary.withValues(alpha: 0.45)),
      trackColor: WidgetStatePropertyAll(c.primary.withValues(alpha: 0.06)),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    );

    return ScrollbarTheme(
      data: scrollbarTheme,
      child: ScrollConfiguration(
        behavior: _DragScroll(),
        child: Column(children: [
          // ── top horizontal scrollbar ──────────────────────────────────
          Container(
            color: c.cardBg,
            child: Row(children: [
              SizedBox(width: _nameW * z),
              Expanded(
                child: Scrollbar(
                  controller: hTop,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: hTop,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(width: totalW, height: 14),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── frozen names ──────────────────────────────────────────
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
                  Expanded(
                    child: ListView.builder(
                      controller: vNames,
                      itemExtent: _rowH * z,
                      itemCount: rowCount,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemBuilder: (_, i) {
                        if (i == rows.length) return _Footer(p: p, zoom: z);
                        return RepaintBoundary(child: _NameCell(p: p, row: rows[i], zoom: z));
                      },
                    ),
                  ),
                ]),
              ),
              // ── values: titles stay pinned, rows scroll down ──────────
              Expanded(
                child: Scrollbar(
                  controller: hMain,
                  thumbVisibility: true,
                  trackVisibility: true,
                  child: SingleChildScrollView(
                    controller: hMain,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: totalW,
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
                        Expanded(
                          child: ListView.builder(
                            controller: vRows,
                            itemExtent: _rowH * z,
                            itemCount: rowCount,
                            padding: const EdgeInsets.only(bottom: 16),
                            itemBuilder: (_, i) {
                              if (i == rows.length) return const SizedBox.shrink();
                              final r = rows[i];
                              final picked = p.selected.contains(r.rowId);
                              return RepaintBoundary(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: picked ? c.primary.withValues(alpha: 0.05) : null,
                                    border: Border(top: line),
                                  ),
                                  child: Row(children: [for (final col in cols) _ValueCell(p: p, row: r, col: col, zoom: z)]),
                                ),
                              );
                            },
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Last item of the names list: a tiny spinner while more students load, otherwise "showing x / y".
class _Footer extends StatelessWidget {
  const _Footer({required this.p, required this.zoom});

  final DataLabProvider p;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: p.loadingMore
          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
          : Text('${'dl_showing'.tr} ${p.rows.length} / ${p.total}', style: dlText(11 * zoom, c: c.textLight)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column title
// ─────────────────────────────────────────────────────────────────────────────

class _HeadCell extends StatelessWidget {
  const _HeadCell({required this.p, required this.col, required this.zoom});

  final DataLabProvider p;
  final DlColumn col;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sorted = p.sort == col.key;
    final shown = col.visibleToStudents;
    return SizedBox(
      width: p.widthOf(col.key) * z,
      height: _headH * z,
      child: Tooltip(
        message: _tr('dl_header_hint', 'Tap to sort · hold for settings'),
        triggerMode: TooltipTriggerMode.manual, // hover only — never fights with press-and-hold
        waitDuration: const Duration(milliseconds: 700),
        child: Stack(children: [
          Positioned.fill(
            child: InkWell(
              onTap: () => p.toggleSort(col.key),
              onLongPress: () => showColumnSettings(context, p, col),
              onSecondaryTap: () => showColumnSettings(context, p, col),
              child: Container(
                color: shown ? c.success.withValues(alpha: 0.09) : c.primary.withValues(alpha: 0.08),
                padding: const EdgeInsetsDirectional.only(start: 12, end: 14),
                alignment: AlignmentDirectional.centerStart,
                child: Row(children: [
                  // The title shrinks to stay on one line.
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(col.label,
                          maxLines: 1, softWrap: false, style: dlText(12.5 * z, w: FontWeight.w800, c: sorted ? c.primary : c.textDark)),
                    ),
                  ),
                  if (col.isCalculated) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.functions_rounded, size: 13 * z, color: c.purple),
                  ],
                  if (sorted) ...[
                    const SizedBox(width: 4),
                    Icon(p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 13 * z, color: c.primary),
                  ],
                ]),
              ),
            ),
          ),
          // The green line = students can see this column.
          if (shown)
            PositionedDirectional(
              start: 10,
              end: 10,
              bottom: 0,
              height: 3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: c.success, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                ),
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
                    height: 18,
                    decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column settings: a floating card (press and hold / right-click a column title)
// ─────────────────────────────────────────────────────────────────────────────

void showColumnSettings(BuildContext context, DataLabProvider p, DlColumn col) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => Directionality(
      textDirection: pageDirection,
      child: _ColumnSheet(p: p, col: col, outer: context),
    ),
  );
}

class _ColumnSheet extends StatefulWidget {
  const _ColumnSheet({required this.p, required this.col, required this.outer});

  final DataLabProvider p;
  final DlColumn col;
  final BuildContext outer; // the screen's context — still alive after this sheet closes

  @override
  State<_ColumnSheet> createState() => _ColumnSheetState();
}

class _ColumnSheetState extends State<_ColumnSheet> {
  late bool _students = widget.col.visibleToStudents;

  DataLabProvider get p => widget.p;
  DlColumn get col => widget.col;

  Future<void> _toggleStudents(bool v) async {
    setState(() => _students = v);
    final e = await p.setColumnFlags(col, students: v);
    if (e != null) {
      if (mounted) setState(() => _students = !v);
      toast(e, error: true);
    }
  }

  Future<void> _hide() async {
    Navigator.pop(context);
    final e = await p.setColumnFlags(col, hidden: true);
    if (e != null) toast(e, error: true);
  }

  Future<void> _delete() async {
    final outer = widget.outer;
    Navigator.pop(context);
    if (!outer.mounted) return;
    if (!await confirm(outer, message: 'dl_delete_column_q'.tr, danger: true)) return;
    final e = await p.deleteColumn(col.key);
    if (e != null) toast(e, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = p.sort == col.key;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: c.cardBg,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(4))),
              ),
              const SizedBox(height: 16),
              // ── who is this column ──
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Icon(col.isCalculated ? Icons.functions_rounded : Icons.view_column_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(col.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(17, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                    const SizedBox(height: 5),
                    if (col.isCalculated)
                      DlTag(_tr('dl_calculated', 'Calculated'), c.purple, icon: Icons.functions_rounded)
                    else if (col.isBuiltin)
                      DlTag(_tr('dl_builtin', 'Built-in'), c.primary)
                    else
                      DlTag(_tr('dl_custom', 'Custom'), c.accent),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              // ── students switch ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: _students ? c.success.withValues(alpha: 0.10) : c.textLight.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _students ? c.success.withValues(alpha: 0.35) : Colors.transparent),
                ),
                child: Row(children: [
                  Icon(_students ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: _students ? c.success : c.textMedium),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_tr('dl_shown_students', 'Shown to students'), style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
                      const SizedBox(height: 2),
                      Text(_tr('dl_shown_students_hint', 'Students can see this column in their own results.'),
                          style: dlText(11.5, c: c.textMedium, h: 1.4)),
                    ]),
                  ),
                  Switch(value: _students, activeColor: c.success, onChanged: _toggleStudents),
                ]),
              ),
              const SizedBox(height: 12),
              // ── actions ──
              Row(children: [
                Expanded(
                  child: _ActionTile(
                    icon: col.isCalculated ? Icons.functions_rounded : Icons.edit_outlined,
                    label: 'dl_menu_edit'.tr,
                    color: c.primary,
                    onTap: () {
                      final outer = widget.outer;
                      Navigator.pop(context);
                      if (outer.mounted) showColumnEditor(outer, p, column: col);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: sorted ? (p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded) : Icons.swap_vert_rounded,
                    label: _tr('dl_sort', 'Sort'),
                    color: c.accent,
                    onTap: () {
                      p.toggleSort(col.key);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: _ActionTile(icon: Icons.visibility_off_rounded, label: 'dl_menu_hide'.tr, color: c.warning, onTap: _hide)),
                const SizedBox(width: 10),
                Expanded(
                  child: col.isBuiltin
                      ? const SizedBox.shrink()
                      : _ActionTile(icon: Icons.delete_outline_rounded, label: 'dl_delete_column'.tr, color: c.danger, onTap: _delete),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(alpha: 0.09),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(label, maxLines: 1, style: dlText(13, w: FontWeight.w800, c: color)),
            ),
          ),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cells
// ─────────────────────────────────────────────────────────────────────────────

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