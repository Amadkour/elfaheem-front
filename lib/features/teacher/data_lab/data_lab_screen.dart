// lib/features/teacher/data_lab/data_lab_screen.dart
// The teacher's Data Lab for one course.
//
//   • a calm header: the course, a few live numbers (students, average progress / attendance, locked columns)
//   • two small buttons always reachable:
//       ⛶  full screen — the sheet fills the whole screen (and hides the phone's status bar)
//       ⌃  hide / show the toolbar (search, columns, tools)
//   • the table header and the student names stay pinned while you scroll; rows load lazily, so it stays fast
//   • two synced horizontal scrollbars: one above the table and one at its end (drag, Shift + wheel, or the bars)
//   • tap a column title to sort (tap "Student" to sort by name) · press and hold it (or right-click) for that
//     column's card: how it is drawn, class insights, show to students, lock, history, edit
//   • a green line under a column title means "students can see this column", a lock means "approved — read only"
//   • select students with the check boxes: a floating bar offers export / certificates for just them
//   • zoom with − / + (or Ctrl + mouse wheel on the web)
//
// Open it from the course profile / analytics hub:
//   Navigator.push(context, MaterialPageRoute(
//       builder: (_) => DataLabScreen(courseId: course.id, courseTitle: title)));
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' show GestureBinding, PointerDeviceKind, PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HardwareKeyboard, SystemChrome, SystemUiMode, SystemUiOverlay;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, ErrorRetry;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design/app_switch.dart';
import '../../student/analysis/student_analytics_profile_screen.dart';
import 'data_lab_api.dart';
import 'data_lab_certificates_sheet.dart';
import 'data_lab_column_sheet.dart';
import 'data_lab_columns_sheet.dart';
import 'data_lab_export_sheet.dart';
import 'data_lab_formula.dart';
import 'data_lab_history_sheet.dart';
import 'data_lab_import_sheet.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_requests.dart';
import 'data_lab_style_sheet.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/core/api_error_text.dart';

// Base sizes at 100% zoom. Everything in the sheet is multiplied by the zoom factor,
// so rows and columns always stay perfectly aligned.
const double _rowH = 54, _headH = 46, _avgH = 36;
const double _minZoom = 0.7, _maxZoom = 1.5;

String _tr(String key, String fallback) => dlTr(key, fallback);

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
  bool _syncing = false;
  bool _fullScreen = false; // the sheet fills the whole screen
  bool _barVisible = true; // the toolbar (title, search, columns, tools)
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
  }

  @override
  void dispose() {
    if (_fullScreen) _systemBars(show: true);
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

  void _systemBars({required bool show}) {
    SystemChrome.setEnabledSystemUIMode(show ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
        overlays: show ? SystemUiOverlay.values : null);
  }

  /// Full screen = hide the toolbar and the phone's status bar; leaving it brings both back.
  void _toggleFull() {
    final on = !_fullScreen;
    setState(() {
      _fullScreen = on;
      _barVisible = !on;
    });
    _systemBars(show: !on);
  }

  void _setZoom(double v) {
    final n = (v.clamp(_minZoom, _maxZoom) as num).toDouble();
    final stepped = (n * 20).round() / 20; // steps of 5%
    if (stepped == _zoom) return;
    setState(() => _zoom = stepped);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DataLabProvider>();
    final c = context.colors;
    Widget content;
    if (p.loading && p.grid == null) {
      content = const DlSheetSkeleton();
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
    return PopScope(
      canPop: !_fullScreen, // the back button first leaves full screen
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toggleFull();
      },
      child: Directionality(
        textDirection: pageDirection,
        child: Scaffold(
          backgroundColor: c.cardBg,
          body: SafeArea(
            child: Column(children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: c.cardBg, border: Border(bottom: BorderSide(color: c.divider))),
                  child: _barVisible
                      ? Column(children: [_topBar(context, p), _panel(context, p)])
                      : _miniBar(context, p),
                ),
              ),
              Expanded(
                child: Stack(children: [
                  // No cross-fade here on purpose: two tables must never share the scroll controllers.
                  Positioned.fill(child: content),
                  // Floating actions for the selected students.
                  PositionedDirectional(
                    start: 12,
                    end: 12,
                    bottom: 14,
                    child: IgnorePointer(
                      ignoring: p.selected.isEmpty,
                      child: AnimatedSlide(
                        offset: p.selected.isEmpty ? const Offset(0, 1.6) : Offset.zero,
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        child: AnimatedOpacity(
                          opacity: p.selected.isEmpty ? 0 : 1,
                          duration: const Duration(milliseconds: 200),
                          child: _SelectionBar(p: p),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // The two buttons that are always reachable (in the toolbar and in the slim strip).
  List<Widget> _modeButtons(DataLabProvider p) => [
    _BarButton(
      icon: _fullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      tooltip: _fullScreen ? _tr('dl_exit_full', 'Exit full screen') : _tr('dl_full', 'Full screen'),
      active: _fullScreen,
      onTap: _toggleFull,
    ),
    const SizedBox(width: 8),
    _BarButton(
      icon: _barVisible ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
      tooltip: _barVisible ? _tr('dl_hide_bar', 'Hide toolbar') : _tr('dl_show_bar', 'Show toolbar'),
      badge: _barVisible ? 0 : p.hiddenCount,
      onTap: () => setState(() => _barVisible = !_barVisible),
    ),
  ];

  // ── header: course, live numbers, mode buttons ───────────────────────────
  Widget _topBar(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final prog = p.stat('progress')?.avg, att = p.stat('attendance')?.avg;
    final students = p.grid?.studentsTotal ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _BarButton(icon: Icons.arrow_back_rounded, tooltip: _tr('dl_back', 'Back'), onTap: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 10),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: [c.primary, c.primaryDark],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              boxShadow: c.primaryShadow,
            ),
            child: Icon(Icons.science_rounded, color: c.onHero, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(15, w: FontWeight.w800, c: c.textDark)),
              Text(_tr('dl_header_sub', 'Grades, attendance and everything you track — in one sheet'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(11.5, c: c.textMedium)),
            ]),
          ),
          const SizedBox(width: 8),
          ..._modeButtons(p),
        ]),
        if (p.grid != null) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              DlStatChip(icon: Icons.groups_rounded, value: '$students', label: 'dl_students'.tr),
              if (prog != null) ...[
                const SizedBox(width: 8),
                DlStatChip(icon: Icons.trending_up_rounded, value: '${prog.round()}%', label: 'dl_progress'.tr, color: dlScoreColor(context, prog)),
              ],
              if (att != null) ...[
                const SizedBox(width: 8),
                DlStatChip(icon: Icons.event_available_rounded, value: '${att.round()}%', label: 'dl_attendance'.tr, color: dlScoreColor(context, att)),
              ],
              if (p.lockedCount > 0) ...[
                const SizedBox(width: 8),
                DlStatChip(
                  icon: Icons.lock_rounded,
                  value: '${p.lockedCount}',
                  label: _tr('dl_locked_cols', 'locked'),
                  color: c.warning,
                  tooltip: _tr('dl_locked_cols_hint', 'Approved columns: they cannot be edited until you unlock them'),
                ),
              ],
              if (p.hiddenCount > 0) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => showColumnsSheet(context, p),
                  child: DlStatChip(icon: Icons.visibility_off_rounded, value: '${p.hiddenCount}', label: _tr('dl_hidden_cols', 'hidden'), color: c.textMedium),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  // ── slim strip shown while the toolbar is hidden ─────────────────────────
  Widget _miniBar(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Row(children: [
        _BarButton(icon: Icons.arrow_back_rounded, tooltip: _tr('dl_back', 'Back'), onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 10),
        Expanded(
          child: Text(widget.courseTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13, w: FontWeight.w800, c: c.textDark)),
        ),
        ..._modeButtons(p),
      ]),
    );
  }

  // ── tools: search, columns, history, more, how numbers look, zoom ────────
  Widget _panel(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    OutlineInputBorder b(Color col, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col, width: w));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: _searchCtrl,
                onChanged: p.setSearch, // the provider waits until typing stops
                textInputAction: TextInputAction.search,
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
                      tooltip: AppConfig.lang == 'ar' ? 'مسح البحث' : 'Clear search',
                      icon: Icon(Icons.close_rounded, color: c.textMedium, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        p.setSearch('');
                      },
                    ),
                  ),
                  filled: true,
                  fillColor: c.inputBg,
                  contentPadding: EdgeInsets.zero,
                  border: b(c.divider),
                  enabledBorder: b(c.divider),
                  focusedBorder: b(c.primary, 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _SquareButton(icon: Icons.view_column_rounded, tooltip: 'dl_columns'.tr, badge: p.hiddenCount, onTap: () => showColumnsSheet(context, p)),
          const SizedBox(width: 8),
          _SquareButton(
            icon: Icons.push_pin_rounded,
            tooltip: _tr('dl_pinned_title', 'Pinned columns'),
            badge: p.frozenKeys.length > 1 ? p.frozenKeys.length : 0,
            onTap: () => showPinSheet(context, p),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            icon: Icons.format_paint_rounded,
            tooltip: _tr('dl_look_title', 'Sheet look'),
            onTap: () => showSheetLookSheet(context, p),
          ),
          const SizedBox(width: 8),
          _SquareButton(
            icon: Icons.history_rounded,
            tooltip: _tr('dl_history', 'Change history'),
            onTap: () => showHistorySheet(context, p),
          ),
          const SizedBox(width: 8),
          _moreMenu(context, p),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tooltip(
            message: _tr('dl_view_all_hint', 'Applies to every column. Press and hold a column title to set just that column.'),
            child: _ViewToggle(p: p),
          ),
          _ZoomControl(zoom: _zoom, onChanged: _setZoom),
          _Legend(),
          if (p.loading && p.grid != null)
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)),
        ]),
      ]),
    );
  }

  Widget _moreMenu(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final cfg = p.config;
    bool on(String key) => !AppConfig.disableList.contains(key);
    PopupMenuEntry<String> item(String value, IconData icon, String label, {String? sub, bool enabled = true, Color? color}) =>
        PopupMenuItem<String>(
          value: value,
          enabled: enabled,
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: (enabled ? (color ?? c.primary) : c.textLight).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 18, color: enabled ? (color ?? c.primary) : c.textLight),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: dlText(13.5, w: FontWeight.w700, c: enabled ? c.textDark : c.textLight)),
                if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(11, c: c.textLight)),
              ]),
            ),
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
          case 'refresh':
            p.load(silent: true, keep: true);
        }
      },
      itemBuilder: (_) => [
        if (on('data_lab.import'))
          item('import', Icons.upload_file_rounded, 'dl_import'.tr, sub: _tr('dl_import_sub', 'Excel or CSV'), enabled: cfg.allowImport),
        if (on('data_lab.export'))
          item('export', Icons.ios_share_rounded, 'dl_export'.tr, sub: _tr('dl_export_sub', 'File, e-mail or students'), enabled: cfg.allowExport, color: c.success),
        if (on('data_lab.certificates'))
          item('certs', Icons.workspace_premium_rounded, 'dl_certificates'.tr, enabled: cfg.allowCertificates, color: c.success),
        if (on('data_lab.requests'))
          item('ask', Icons.mark_chat_unread_rounded, 'dl_ask_students'.tr, enabled: cfg.allowStudentRequests, color: c.warning),
        if (on('data_lab.columns')) item('column', Icons.add_chart_rounded, 'dl_new_column'.tr, color: c.purple),
        const PopupMenuDivider(),
        item('refresh', Icons.refresh_rounded, _tr('dl_refresh', 'Refresh'), color: c.textMedium),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
          borderRadius: BorderRadius.circular(16),
          boxShadow: c.primaryShadow,
        ),
        child: Icon(Icons.auto_awesome_motion_rounded, color: c.onHero, size: 22),
      ),
    );
  }

  /// No students yet, or nothing matches the search — say so kindly and show the next step.
  Widget _empty(BuildContext context, DataLabProvider p) {
    final c = context.colors;
    final searching = p.search.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [c.primary.withValues(alpha: 0.16), c.primary.withValues(alpha: 0.04)]),
              ),
              child: Icon(searching ? Icons.search_off_rounded : Icons.table_chart_rounded, size: 44, color: c.primary),
            ),
            const SizedBox(height: 18),
            Text(
              searching ? 'dl_no_match'.tr : _tr('dl_empty_title', 'Your sheet is ready'),
              textAlign: TextAlign.center,
              style: dlText(18, w: FontWeight.w800, c: c.textDark),
            ),
            const SizedBox(height: 6),
            Text(
              searching
                  ? _tr('dl_no_match_sub', 'Try another name, e-mail, phone or ID.')
                  : _tr('dl_empty_sub', 'Students appear here as soon as they enrol. You can also bring in a sheet you already have.'),
              textAlign: TextAlign.center,
              style: dlText(13, c: c.textMedium, h: 1.55),
            ),
            const SizedBox(height: 18),
            if (searching)
              DlActionPill(
                icon: Icons.close_rounded,
                label: _tr('dl_clear_search', 'Clear the search'),
                onTap: () {
                  _searchCtrl.clear();
                  p.setSearch('');
                },
              )
            else
              Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                if (p.config.allowImport)
                  DlActionPill(icon: Icons.upload_file_rounded, label: 'dl_import'.tr, onTap: () => showImportWizard(context, p)),
                DlActionPill(icon: Icons.add_chart_rounded, label: 'dl_new_column'.tr, color: c.purple, onTap: () => showColumnEditor(context, p)),
              ]),
          ]),
        ),
      ),
    );
  }
}

/// Floating bar shown while students are selected: what can be done for just them.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.p});

  final DataLabProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cfg = p.config;
    Widget action(IconData icon, String label, VoidCallback? onTap) => Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: c.onHero,
          backgroundColor: c.onHero.withValues(alpha: 0.14),
          disabledForegroundColor: c.onHeroMuted,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label, style: dlText(12.5, w: FontWeight.w800, c: c.onHero)),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [c.primary, c.primaryDark], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
              borderRadius: BorderRadius.circular(20),
              boxShadow: c.primaryShadow,
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(20)),
                child: Text('${p.selected.length}', style: dlText(13, w: FontWeight.w800, c: c.primary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('dl_selected'.tr, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13, w: FontWeight.w700, c: c.onHero)),
              ),
              Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(children: [
                    action(Icons.select_all_rounded, _tr('dl_select_all', 'All'), p.selectAllLoaded),
                    if (cfg.allowExport) action(Icons.ios_share_rounded, 'dl_export'.tr, () => showExportSheet(context, p)),
                    if (cfg.allowCertificates)
                      action(Icons.workspace_premium_rounded, 'dl_certificates'.tr, () => showCertificatesSheet(context, p)),
                  ]),
                ),
              ),
              IconButton(
                tooltip: _tr('dl_clear_selection', 'Clear selection'),
                onPressed: p.clearSelection,
                icon: Icon(Icons.close_rounded, color: c.onHero),
              ),
            ]),
          ),
        ),
      ),
    );
  }
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
                child: Text('$badge', style: dlText(9.5, w: FontWeight.w800, c: c.onHero)),
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
                child: Text('$badge', style: dlText(10, w: FontWeight.w800, c: c.onHero)),
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

/// Numbers | Progress | Both — for every column at once. Only the chosen one shows its name, so it stays small.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.p});

  final DataLabProvider p;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(DlView v, IconData icon, String label) {
      final on = p.view == v && p.columns.every((col) => p.viewOf(col) == v || !col.isNumber);
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => p.setView(v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: on ? c.primary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: on ? c.onHero : c.textMedium),
            if (on) ...[
              const SizedBox(width: 5),
              Text(label, style: dlText(11.5, w: FontWeight.w700, c: c.onHero)),
            ],
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(15), border: Border.all(color: c.divider)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg(DlView.value, Icons.pin_rounded, _tr('dl_pres_numbers', 'Numbers')),
        seg(DlView.bar, Icons.align_horizontal_left_rounded, _tr('dl_pres_progress', 'Progress')),
        seg(DlView.both, Icons.view_agenda_rounded, _tr('dl_pres_both', 'Both')),
      ]),
    );
  }
}

/// Three little previews — pick how ONE column is drawn.
class _PresentationPicker extends StatelessWidget {
  const _PresentationPicker({required this.value, required this.onChanged});

  final DlView value;
  final ValueChanged<DlView> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget bar(Color col) => Container(
      width: 38,
      height: 6,
      alignment: AlignmentDirectional.centerStart,
      decoration: BoxDecoration(color: col.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(6)),
      child: FractionallySizedBox(
        widthFactor: 0.7,
        child: Container(decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(6))),
      ),
    );
    Widget tile(DlView v, String label, Widget Function(Color) preview) {
      final on = value == v;
      final col = on ? c.primary : c.textMedium;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(
              color: on ? c.primary.withValues(alpha: 0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: on ? c.primary : c.divider, width: on ? 1.6 : 1),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 28, child: Center(child: preview(col))),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(11.5, w: FontWeight.w800, c: col)),
            ]),
          ),
        ),
      );
    }

    return Row(children: [
      tile(DlView.value, _tr('dl_pres_numbers', 'Numbers'), (col) => Text('83', style: dlText(16, w: FontWeight.w800, c: col))),
      const SizedBox(width: 8),
      tile(DlView.bar, _tr('dl_pres_progress', 'Progress'), bar),
      const SizedBox(width: 8),
      tile(DlView.both, _tr('dl_pres_both', 'Both'), (col) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text('83', style: dlText(12, w: FontWeight.w800, c: col)),
        const SizedBox(height: 3),
        bar(col),
      ])),
    ]);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// The sheet
//   ┌ top scrollbar ────────────────────────────────────┐
//   │ ☐ │ pinned columns (frozen) │ column titles  ⠿  │   ← drag ⠿ onto another title to move a column
//   │   │ class average           │ class average      │
//   │ ☐ │ lazy rows               │ lazy rows          │   ← both lists scroll together
//   └ bottom scrollbar ─────────────────────────────────┘
// The pinned part is chosen by the teacher (name, ID, e-mail, phone and/or any data columns), every pinned column
// can be resized, and the choice is remembered per course. When the pinned part is wider than ~60 % of the screen
// it scrolls sideways on its own, so the data always keeps room.
// ─────────────────────────────────────────────────────────────────────────────

const double _slotW = 44; // check box (students) or delete button (temporary / waiting lines)

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
    final frozen = p.frozenKeys;
    final cols = p.scrollColumns;
    final rows = p.rows;
    final line = BorderSide(color: c.divider.withValues(alpha: 0.6));
    var totalW = 0.0;
    for (final col in cols) {
      totalW += p.widthOf(col.key) * z;
    }
    var frozenW = _slotW * z;
    for (final k in frozen) {
      frozenW += p.widthOf(k) * z;
    }
    final rowCount = rows.length + 1; // +1 = footer ("showing x / y" or the loading spinner)
    // Room for the floating selection bar, the same on both lists so they stay aligned.
    final bottomPad = EdgeInsets.only(bottom: p.selected.isEmpty ? 16 : 96);

    final scrollbarTheme = ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(8),
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(true),
      thumbColor: WidgetStatePropertyAll(c.primary.withValues(alpha: 0.45)),
      trackColor: WidgetStatePropertyAll(c.primary.withValues(alpha: 0.06)),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    );

    return LayoutBuilder(builder: (context, box) {
      final viewW = math.min(frozenW, box.maxWidth * 0.62);
      final frozenScrolls = frozenW > viewW + 0.5;

      // ── pinned part: header, class average, rows ──
      // ── class averages: a band above the titles (default), under them, or hidden ──
      final hlAvg = p.avgHighlight;
      final firstLabel = frozen.indexWhere(DataLabProvider.isIdentity);
      final frozenAvg = _avgBand(context, [
        SizedBox(
          width: _slotW * z,
          child: hlAvg ? Icon(Icons.functions_rounded, size: 17 * z, color: c.primary) : null,
        ),
        for (var i = 0; i < frozen.length; i++)
          SizedBox(
            width: p.widthOf(frozen[i]) * z,
            // the label goes under the first student detail (or the first pinned column when none is pinned)
            child: _frozenAvg(context, frozen[i], first: i == (firstLabel < 0 ? 0 : firstLabel)),
          ),
      ]);
      final scrollAvg = _avgBand(context, [
        for (final col in cols) SizedBox(width: p.widthOf(col.key) * z, child: _avgValue(context, col)),
      ]);
      final avgTop = p.avgPlace == 'top', avgUnder = p.avgPlace == 'header';

      final frozenPart = SizedBox(
        width: frozenW,
        child: Column(children: [
          if (avgTop) frozenAvg,
          _FrozenHeader(p: p, keys: frozen, zoom: z),
          if (avgUnder) frozenAvg,
          Expanded(
            child: ListView.builder(
              controller: vNames,
              itemExtent: _rowH * z,
              itemCount: rowCount,
              padding: bottomPad,
              itemBuilder: (_, i) {
                if (i == rows.length) return _Footer(p: p, zoom: z);
                return RepaintBoundary(child: _FrozenRow(p: p, row: rows[i], keys: frozen, zoom: z, even: i.isEven));
              },
            ),
          ),
        ]),
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
                SizedBox(width: viewW),
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
                // ── pinned (frozen) part ──────────────────────────────────
                Container(
                  width: viewW,
                  // The separator line is painted ON TOP (foregroundDecoration): a border in `decoration` would
                  // take 1.4 px from the content's width — that was the "RenderFlex overflowed by 1.4 pixels".
                  decoration: BoxDecoration(
                    color: c.cardBg,
                    boxShadow: [
                      BoxShadow(color: c.heroShade.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(2, 0)),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    border: BorderDirectional(end: BorderSide(color: c.primary.withValues(alpha: 0.25), width: 1.4)),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: frozenScrolls
                      ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: frozenPart,
                  )
                      : frozenPart,
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
                          if (avgTop) scrollAvg,
                          Row(children: [for (final col in cols) _HeadCell(p: p, col: col, zoom: z)]),
                          if (avgUnder) scrollAvg,
                          Expanded(
                            child: ListView.builder(
                              controller: vRows,
                              itemExtent: _rowH * z,
                              itemCount: rowCount,
                              padding: bottomPad,
                              itemBuilder: (_, i) {
                                if (i == rows.length) return const SizedBox.shrink();
                                final r = rows[i];
                                final picked = p.selected.contains(r.rowId);
                                return RepaintBoundary(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: picked
                                          ? c.primary.withValues(alpha: 0.06)
                                          : (i.isEven ? null : c.inputBg.withValues(alpha: 0.45)),
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
    });
  }

  /// The class-average band: tinted with a clear edge when highlighted, so it never reads like a student.
  Widget _avgBand(BuildContext context, List<Widget> children) {
    final c = context.colors;
    final z = zoom;
    final hl = p.avgHighlight;
    return Container(
      height: _avgH * z,
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: hl ? 0.10 : 0.04),
        border: hl
            ? Border.symmetric(horizontal: BorderSide(color: c.primary.withValues(alpha: 0.35)))
            : null,
      ),
      child: Row(children: children),
    );
  }

  /// The class average of one data column (a pill when the band is highlighted).
  Widget _avgValue(BuildContext context, DlColumn? col) {
    final c = context.colors;
    final z = zoom;
    if (col == null || !col.isNumber || p.avgOf(col) == null) return const SizedBox.shrink();
    final text = dlFmt(p.avgOf(col));
    if (!p.avgHighlight) {
      return Center(child: Text(text, style: dlText(12 * z, w: FontWeight.w700, c: c.textMedium)));
    }
    return Center(
      child: Tooltip(
        message: '${'dl_class_avg'.tr} · ${col.label}',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 9 * z, vertical: 2 * z),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.primary.withValues(alpha: 0.35)),
          ),
          child: Text(text, maxLines: 1, style: dlText(12 * z, w: FontWeight.w800, c: c.primary)),
        ),
      ),
    );
  }

  /// Under a pinned column: the "Class average" label under the first one, the average under data columns.
  Widget _frozenAvg(BuildContext context, String key, {required bool first}) {
    final c = context.colors;
    final z = zoom;
    if (DataLabProvider.isIdentity(key)) {
      if (!first) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('dl_class_avg'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dlText(11.5 * z, w: FontWeight.w800, c: p.avgHighlight ? c.primary : c.textMedium)),
        ),
      );
    }
    return _avgValue(context, p.columnOf(key));
  }
}

/// Last item of the pinned list: a tiny spinner while more students load, otherwise "showing x / y".
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
// Pinned (frozen) part
// ─────────────────────────────────────────────────────────────────────────────

/// Drag handle on the end edge of a title: pull to resize (the drag is divided by the zoom so it follows the finger).
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.p, required this.keyName, required this.zoom});

  final DataLabProvider p;
  final String keyName;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: Tooltip(
        message: _tr('dl_resize_hint', 'Drag to resize · double-tap for the default width'),
        triggerMode: TooltipTriggerMode.manual,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => p.setWidth(keyName, p.widthOf(keyName) + (rtl ? -d.delta.dx : d.delta.dx) / zoom),
          onDoubleTap: () => p.setWidth(keyName, DataLabProvider.isIdentity(keyName) ? 172 : DataLabProvider.defaultColWidth),
          child: Center(
            child: Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(color: c.textLight.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

class _FrozenHeader extends StatelessWidget {
  const _FrozenHeader({required this.p, required this.keys, required this.zoom});

  final DataLabProvider p;
  final List<String> keys;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final students = p.rows.where((r) => r.studentId != null).map((r) => r.rowId).toList();
    final picked = students.where(p.selected.contains).length;
    final all = students.isNotEmpty && picked == students.length;
    return Container(
      height: _headH * z,
      color: c.primary.withValues(alpha: 0.08),
      child: Row(children: [
        SizedBox(
          width: _slotW * z,
          child: Center(
            child: Tooltip(
              message: _tr('dl_select_all', 'All'),
              child: Checkbox(
                tristate: true,
                value: all ? true : (picked == 0 ? false : null),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                activeColor: c.primary,
                onChanged: students.isEmpty ? null : (_) => all ? p.clearSelection() : p.selectAllLoaded(),
              ),
            ),
          ),
        ),
        for (final k in keys) _FrozenHeadCell(p: p, keyName: k, zoom: z),
      ]),
    );
  }
}

class _FrozenHeadCell extends StatelessWidget {
  const _FrozenHeadCell({required this.p, required this.keyName, required this.zoom});

  final DataLabProvider p;
  final String keyName;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final sorted = p.sort == keyName;
    final col = DataLabProvider.isIdentity(keyName) ? null : p.columns.where((x) => x.key == keyName).firstOrNull;
    void menu() => col != null ? showColumnSettings(context, p, col) : showPinSheet(context, p);
    return SizedBox(
      width: p.widthOf(keyName) * z,
      height: _headH * z,
      child: Stack(children: [
        Positioned.fill(
          child: InkWell(
            onTap: () => p.toggleSort(keyName),
            onLongPress: menu,
            onSecondaryTap: menu,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 8, end: 14),
              child: Row(children: [
                Icon(Icons.push_pin_rounded, size: 12 * z, color: c.primary.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(p.frozenLabel(keyName, (k) => k.tr),
                        maxLines: 1, softWrap: false, style: dlText(12.5 * z, w: FontWeight.w800, c: sorted ? c.primary : c.textDark)),
                  ),
                ),
                if (sorted)
                  Icon(p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 13 * z, color: c.primary)
                else if (keyName == DataLabProvider.idName)
                  Icon(Icons.sort_by_alpha_rounded, size: 13 * z, color: c.textLight),
              ]),
            ),
          ),
        ),
        PositionedDirectional(end: 0, top: 0, bottom: 0, width: 12, child: _ResizeHandle(p: p, keyName: keyName, zoom: z)),
      ]),
    );
  }
}

/// One line of the pinned part: the check box (or delete button) and every pinned cell.
class _FrozenRow extends StatelessWidget {
  const _FrozenRow({required this.p, required this.row, required this.keys, required this.zoom, required this.even});

  final DataLabProvider p;
  final DlRow row;
  final List<String> keys;
  final double zoom;
  final bool even;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final isStudent = row.studentId != null;
    final picked = p.selected.contains(row.rowId);
    return Container(
      height: _rowH * z,
      decoration: BoxDecoration(
        color: picked ? c.primary.withValues(alpha: 0.07) : (even ? null : c.inputBg.withValues(alpha: 0.45)),
        border: Border(top: BorderSide(color: c.divider.withValues(alpha: 0.6))),
      ),
      child: Row(children: [
        SizedBox(
          width: _slotW * z,
          child: Center(
            child: isStudent
                ? Checkbox(
              value: picked,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: c.primary,
              onChanged: (_) => p.toggleSelect(row.rowId),
            )
                : IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              tooltip: _tr('dl_delete_row', 'Remove this line'),
              icon: Icon(Icons.delete_outline_rounded, size: 18 * z, color: c.danger),
              onPressed: () async {
                if (!await confirm(context, message: 'dl_delete_row_q'.tr, danger: true)) return;
                final err = await p.deleteRow(row);
                if (err != null) toast(err, error: true);
              },
            ),
          ),
        ),
        for (final k in keys)
          if (DataLabProvider.isIdentity(k))
            _IdentityCell(p: p, row: row, keyName: k, zoom: z)
          else if (p.columns.where((x) => x.key == k).firstOrNull case final col?)
            _ValueCell(p: p, row: row, col: col, zoom: z),
      ]),
    );
  }
}

/// Name / ID / e-mail / phone of a line. Tap → the student's analytics profile · hold → the line's history.
class _IdentityCell extends StatelessWidget {
  const _IdentityCell({required this.p, required this.row, required this.keyName, required this.zoom});

  final DataLabProvider p;
  final DlRow row;
  final String keyName;
  final double zoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final isStudent = row.studentId != null;
    final value = switch (keyName) {
      DataLabProvider.idIdentifier => row.identifier,
      DataLabProvider.idEmail => row.email,
      DataLabProvider.idPhone => row.phone,
      _ => row.name,
    };
    final isName = keyName == DataLabProvider.idName;
    final empty = value == null || value.trim().isEmpty;
    return SizedBox(
      width: p.widthOf(keyName) * z,
      height: _rowH * z,
      child: InkWell(
        onTap: isStudent
            ? () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StudentAnalyticsProfileScreen.forTeacher(studentId: row.studentId!, studentName: row.name, courseId: p.courseId),
          ),
        )
            : null,
        onLongPress: () => _rowActions(context, p, row),
        onSecondaryTap: () => _rowActions(context, p, row),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              empty ? '—' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: isName ? null : TextDirection.ltr,
              style: (isName
                  ? dlText(13 * z * p.sheetSize, w: FontWeight.w700, c: c.textDark)
                  : dlText(12.5 * z * p.sheetSize, w: FontWeight.w600, c: empty ? c.textLight : c.textDark))
                  .copyWith(fontFamily: p.sheetFont ?? 'tajawal'),
            ),
            if (isName) ...[
              if (row.isTemporary) ...[
                const SizedBox(height: 2),
                DlTag('dl_temporary'.tr, c.warning, icon: Icons.hourglass_bottom_rounded),
              ] else if (row.isStaged) ...[
                const SizedBox(height: 2),
                DlTag('dl_waiting'.tr, c.purple, icon: Icons.mark_email_unread_rounded),
              ] else if ((row.identifier ?? '').isNotEmpty && z >= 0.9 && !p.isFrozen(DataLabProvider.idIdentifier))
                Text(row.identifier!, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10.5 * z, c: c.textLight)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Hold a student's name: history of the line · new login details (students only).
Future<void> _rowActions(BuildContext context, DataLabProvider p, DlRow row) async {
  final picked = await showModalBottomSheet<String>(
      useSafeArea: true,
    context: context,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) {
      final c = ctx.colors;
      Widget tile(String v, IconData icon, String title, String sub, Color color) => ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: dlText(14, w: FontWeight.w800, c: c.textDark)),
        subtitle: Text(sub, style: dlText(11.5, c: c.textMedium, h: 1.35)),
        onTap: () => Navigator.pop(ctx, v),
      );
      return Directionality(
        textDirection: pageDirection,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Material(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(24),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(row.name.isEmpty ? '—' : row.name, style: dlText(16, w: FontWeight.w800, c: c.textDark)),
                  ),
                  tile('history', Icons.history_rounded, _tr('dl_history_short', 'History'),
                      _tr('dl_row_history_sub', 'Every change on this line'), c.purple),
                  if (row.studentId != null)
                    tile('login', Icons.key_rounded, _tr('dl_login_details', 'Login details'),
                        _tr('dl_login_details_sub', 'A new temporary password to give the student (e-mailed too when there is an e-mail)'), c.primary),
                ]),
              ),
            ),
          ),
        ),
      );
    },
  );
  if (picked == null || !context.mounted) return;
  if (picked == 'history') {
    await showHistorySheet(context, p, rowId: row.rowId, title: row.name.isEmpty ? null : row.name);
  } else if (picked == 'login') {
    final ok = await confirm(context,
        message: _tr('dl_login_details_q', 'Create new temporary login details? The old password stops working and the student chooses a new one at sign-in.'));
    if (!ok || !context.mounted) return;
    try {
      final r = await DataLabApi().newLoginDetails(p.courseId, row.rowId);
      if (context.mounted) await _showLoginDetails(context, r, p.grid?.title ?? '');
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
    }
  }
}

/// The login details of one student, to copy or share (WhatsApp, SMS …).
Future<void> _showLoginDetails(BuildContext context, Map<String, dynamic> r, String course) => showModalBottomSheet<void>(
      useSafeArea: true,
  context: context,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (ctx) {
    final c = ctx.colors;
    final msg = dlLoginMessage(name: '${r['name']}', login: '${r['login']}', password: '${r['password']}', link: '${r['link']}', course: course);
    Widget line(String label, String value, {bool big = false}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
      child: Row(children: [
        Expanded(child: Text(label, style: dlText(12, c: c.textMedium))),
        SelectableText(value, textDirection: TextDirection.ltr,
            style: dlText(big ? 17 : 13.5, w: FontWeight.w800, c: big ? c.primary : c.textDark).copyWith(letterSpacing: big ? 1 : 0)),
      ]),
    );
    return Directionality(
      textDirection: pageDirection,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.key_rounded, size: 32, color: c.primary),
                ),
                const SizedBox(height: 10),
                Text('${r['name']}', style: dlText(17, w: FontWeight.w800, c: c.textDark)),
                const SizedBox(height: 4),
                Text(
                  r['emailed'] == true
                      ? _tr('dl_login_emailed', 'Also sent to the student by e-mail.')
                      : _tr('dl_login_give', 'Give these to the student — they are shown only now.'),
                  textAlign: TextAlign.center,
                  style: dlText(12, c: r['emailed'] == true ? c.success : c.warning, h: 1.4),
                ),
                const SizedBox(height: 14),
                line(_tr('dl_login_login', 'Login'), '${r['login']}'),
                line(_tr('dl_login_password', 'Temporary password'), '${r['password']}', big: true),
                line(_tr('dl_login_link', 'Link'), '${r['link']}'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        side: BorderSide(color: c.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: msg));
                        toast('dl_copied'.tr);
                      },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(_tr('dl_copy', 'Copy'), style: dlText(13, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.primary,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => SharePlus.instance.share(ShareParams(text: msg)),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(_tr('dl_file_share', 'Share'), style: dlText(13, w: FontWeight.w800, c: context.colors.onHero)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  },
);

/// Which columns are pinned on the start side (student details and / or data columns) + reset of the widths.
void showPinSheet(BuildContext context, DataLabProvider p) {
  showModalBottomSheet<void>(
      useSafeArea: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => Directionality(
      textDirection: pageDirection,
      child: ListenableBuilder(
        listenable: p,
        builder: (ctx, _) {
          final c = ctx.colors;
          final pinned = p.frozenKeys;
          Widget tile(String key, String label, IconData icon) {
            final on = pinned.contains(key);
            final order = on ? pinned.indexOf(key) + 1 : null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: on ? c.primary.withValues(alpha: 0.08) : c.inputBg,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    if (!p.toggleFrozen(key)) toast(_tr('dl_pin_keep_one', 'Keep at least one pinned column'), error: true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      Icon(icon, size: 19, color: on ? c.primary : c.textMedium),
                      const SizedBox(width: 10),
                      Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13.5, w: FontWeight.w700, c: c.textDark))),
                      if (order != null)
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                          child: Text('$order', style: dlText(11, w: FontWeight.w800, c: context.colors.onHero)),
                        )
                      else
                        Icon(Icons.push_pin_outlined, size: 18, color: c.textLight),
                    ]),
                  ),
                ),
              ),
            );
          }

          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Material(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(28),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.85),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    children: [
                      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(4)))),
                      const SizedBox(height: 14),
                      Row(children: [
                        Icon(Icons.push_pin_rounded, color: c.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_tr('dl_pinned_title', 'Pinned columns'), style: dlText(17, w: FontWeight.w800, c: c.textDark))),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        _tr('dl_pinned_sub', 'Pinned columns stay on the side while the rest of the sheet scrolls. Tap to pin or unpin — the number is their order. Drag the edge of a title to change its width.'),
                        style: dlText(12, c: c.textMedium, h: 1.5),
                      ),
                      DlSectionTitle(_tr('dl_pinned_student', 'Student details')),
                      tile(DataLabProvider.idName, 'dl_student'.tr, Icons.person_rounded),
                      tile(DataLabProvider.idIdentifier, 'dl_t_identifier'.tr, Icons.badge_rounded),
                      tile(DataLabProvider.idEmail, 'dl_t_email'.tr, Icons.alternate_email_rounded),
                      tile(DataLabProvider.idPhone, 'dl_t_phone'.tr, Icons.phone_rounded),
                      DlSectionTitle(_tr('dl_pinned_data', 'Sheet columns')),
                      for (final col in p.shownColumns)
                        tile(col.key, col.label, col.isCalculated ? Icons.functions_rounded : Icons.view_column_rounded),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: BorderSide(color: c.divider),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: p.resetWidths,
                        icon: const Icon(Icons.width_normal_rounded, size: 18),
                        label: Text(_tr('dl_reset_widths', 'Reset all widths'), style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Column title (scrolling part): tap = sort · hold = column card · drag ⠿ = move · drag the edge = resize
// ─────────────────────────────────────────────────────────────────────────────

class _HeadCell extends StatelessWidget {
  const _HeadCell({required this.p, required this.col, required this.zoom});

  final DataLabProvider p;
  final DlColumn col;
  final double zoom;

  Future<void> _drop(String dragged) async {
    final e = await p.moveColumn(dragged, col.key);
    if (e != null) toast(e, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final z = zoom;
    final sorted = p.sort == col.key;
    final shown = col.visibleToStudents;
    final w = p.widthOf(col.key) * z;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != col.key,
      onAcceptWithDetails: (d) => _drop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return SizedBox(
          width: w,
          height: _headH * z,
          child: Tooltip(
            message: _tr('dl_header_hint2', 'Tap to sort · hold for settings · drag ⠿ to move'),
            triggerMode: TooltipTriggerMode.manual, // hover only — never fights with press-and-hold
            waitDuration: const Duration(milliseconds: 700),
            child: Stack(children: [
              Positioned.fill(
                child: InkWell(
                  onTap: () => p.toggleSort(col.key),
                  onLongPress: () => showColumnSettings(context, p, col),
                  onSecondaryTap: () => showColumnSettings(context, p, col),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    color: hovering
                        ? c.primary.withValues(alpha: 0.18)
                        : (dlStyleColor(context, col.style.color)?.withValues(alpha: 0.20) ??
                        (shown ? c.success.withValues(alpha: 0.09) : c.primary.withValues(alpha: 0.08))),
                    padding: const EdgeInsetsDirectional.only(start: 2, end: 14),
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(children: [
                      // ⠿ grip: drag it onto another title to move this column there
                      Draggable<String>(
                        data: col.key,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.primary,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: c.primaryShadow,
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.drag_indicator_rounded, size: 16, color: c.onHero),
                              const SizedBox(width: 6),
                              Text(col.label, style: dlText(12.5, w: FontWeight.w800, c: c.onHero)),
                            ]),
                          ),
                        ),
                        childWhenDragging: Icon(Icons.drag_indicator_rounded, size: 16 * z, color: c.primary),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3 * z, vertical: 10 * z),
                            child: Icon(Icons.drag_indicator_rounded, size: 16 * z, color: c.textLight.withValues(alpha: 0.8)),
                          ),
                        ),
                      ),
                      if (col.isLocked) ...[
                        Icon(Icons.lock_rounded, size: 12 * z, color: c.warning),
                        const SizedBox(width: 4),
                      ],
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
                        Icon(col.isNumber ? Icons.functions_rounded : Icons.text_fields_rounded, size: 13 * z, color: c.purple),
                      ],
                      if (col.style.rules.isNotEmpty || col.style.scale) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.palette_rounded, size: 12 * z, color: c.accent2),
                      ],
                      if (sorted) ...[
                        const SizedBox(width: 4),
                        Icon(p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 13 * z, color: c.primary),
                      ],
                    ]),
                  ),
                ),
              ),
              // where the column will land
              if (hovering)
                PositionedDirectional(
                  start: 0,
                  top: 4,
                  bottom: 4,
                  width: 3,
                  child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(3)))),
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
              PositionedDirectional(end: 0, top: 0, bottom: 0, width: 12, child: _ResizeHandle(p: p, keyName: col.key, zoom: z)),
            ]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column card: a floating sheet (press and hold / right-click a column title)
// ─────────────────────────────────────────────────────────────────────────────

void showColumnSettings(BuildContext context, DataLabProvider p, DlColumn col) {
  showModalBottomSheet<void>(
      useSafeArea: true,
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.heroShade.withValues(alpha: 0.35),
    constraints: const BoxConstraints(maxWidth: 540),
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
  late bool _locked = widget.col.isLocked;
  late DlView _pres = widget.p.viewOf(widget.col);

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

  Future<void> _toggleLock(bool v) async {
    setState(() => _locked = v);
    final e = await p.setColumnFlags(col, locked: v);
    if (e != null) {
      if (mounted) setState(() => _locked = !v);
      toast(e, error: true);
    } else {
      toast(v ? _tr('dl_locked_done', 'Locked — values are now read-only') : _tr('dl_unlocked_done', 'Unlocked — values can be edited again'));
    }
  }

  void _setPres(DlView v) {
    setState(() => _pres = v);
    p.setColumnView(col, v);
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

  void _then(void Function(BuildContext outer) f) {
    final outer = widget.outer;
    Navigator.pop(context);
    if (outer.mounted) f(outer);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = p.sort == col.key;
    final st = col.isNumber ? p.stat(col.key) : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: c.cardBg,
          elevation: 8,
          shadowColor: c.heroShade.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
            child: SingleChildScrollView(
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
                    child: Icon(col.isCalculated ? Icons.functions_rounded : Icons.view_column_rounded, color: c.onHero, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(col.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(17, w: FontWeight.w800, c: c.textDark, h: 1.25)),
                      const SizedBox(height: 5),
                      Wrap(spacing: 6, runSpacing: 4, children: [
                        if (col.isCalculated)
                          DlTag(_tr('dl_calculated', 'Calculated'), c.purple, icon: Icons.functions_rounded)
                        else if (col.isBuiltin)
                          DlTag(_tr('dl_builtin', 'Built-in'), c.primary)
                        else
                          DlTag(_tr('dl_custom', 'Custom'), c.warning),
                        if (col.isNumber) DlTag('${_tr('dl_full_mark', 'Full mark')} ${dlFmt(col.maxValue)}', c.textMedium),
                        if (_locked) DlTag(_tr('dl_locked', 'Locked'), c.warning, icon: Icons.lock_rounded),
                      ]),
                    ]),
                  ),
                ]),
                if (col.hasExpr)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: c.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                    child: Text('=  ${DlFormulaText.toLabels(col.expr!, p.columns)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: dlText(12, w: FontWeight.w700, c: c.purple).copyWith(fontFamily: 'monospace')),
                  ),
                // ── class insights ──
                if (st != null && st.filled > 0) ...[
                  const SizedBox(height: 16),
                  _Insights(stat: st, col: col, total: p.grid?.studentsTotal ?? st.filled, passPercent: p.config.passPercent),
                ],
                const SizedBox(height: 16),
                // ── how this column is drawn ──
                if (col.isNumber) ...[
                  Text(_tr('dl_pres_title', 'How this column looks'), style: dlText(12.5, w: FontWeight.w800, c: c.textMedium)),
                  const SizedBox(height: 8),
                  _PresentationPicker(value: _pres, onChanged: _setPres),
                  const SizedBox(height: 14),
                ],
                // ── switches ──
                _ToggleTile(
                  on: _students,
                  color: c.success,
                  iconOn: Icons.visibility_rounded,
                  iconOff: Icons.visibility_off_rounded,
                  title: _tr('dl_shown_students', 'Shown to students'),
                  sub: _tr('dl_shown_students_hint', 'Students can see this column in their own results.'),
                  onChanged: _toggleStudents,
                ),
                const SizedBox(height: 8),
                if (col.isNumber || col.isCustom)
                  _ToggleTile(
                    on: _locked,
                    color: c.warning,
                    iconOn: Icons.lock_rounded,
                    iconOff: Icons.lock_open_rounded,
                    title: _tr('dl_lock_title', 'Lock the results'),
                    sub: _tr('dl_lock_hint', 'For approved marks: nobody can edit or import into this column until you unlock it.'),
                    onChanged: _toggleLock,
                  ),
                const SizedBox(height: 12),
                // ── actions ──
                Row(children: [
                  Expanded(
                    child: _ActionTile(
                      icon: col.isCalculated ? Icons.functions_rounded : Icons.edit_outlined,
                      label: col.isCalculated ? _tr('dl_edit_formula', 'Edit formula') : 'dl_menu_edit'.tr,
                      color: c.primary,
                      onTap: () => _then((o) => showColumnEditor(o, p, column: col)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionTile(
                      icon: sorted ? (p.desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded) : Icons.swap_vert_rounded,
                      label: _tr('dl_sort', 'Sort'),
                      color: c.primary,
                      onTap: () {
                        p.toggleSort(col.key);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _ActionTile(
                      icon: p.isFrozen(col.key) ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                      label: p.isFrozen(col.key) ? _tr('dl_unpin', 'Unpin') : _tr('dl_pin', 'Pin to the side'),
                      color: c.primary,
                      onTap: () {
                        if (!p.toggleFrozen(col.key)) toast(_tr('dl_pin_keep_one', 'Keep at least one pinned column'), error: true);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionTile(
                      icon: Icons.history_rounded,
                      label: _tr('dl_history_short', 'History'),
                      color: c.purple,
                      onTap: () => _then((o) => showHistorySheet(o, p, columnKey: col.key, title: col.label)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _ActionTile(icon: Icons.visibility_off_rounded, label: 'dl_menu_hide'.tr, color: c.warning, onTap: _hide)),
                ]),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.palette_rounded,
                  label: col.style.isEmpty
                      ? _tr('dl_style_title', 'Style & colours')
                      : '${_tr('dl_style_title', 'Style & colours')} · ${col.style.rules.length} ${_tr('dl_rules_short', 'rules')}',
                  color: c.accent2,
                  onTap: () => _then((o) => showColumnStyleSheet(o, p, col)),
                ),
                if (!col.isBuiltin) ...[
                  const SizedBox(height: 10),
                  _ActionTile(icon: Icons.delete_outline_rounded, label: 'dl_delete_column'.tr, color: c.danger, onTap: _locked ? null : _delete),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Average, median, spread, pass rate and the distribution of one column — at a glance.
class _Insights extends StatelessWidget {
  const _Insights({required this.stat, required this.col, required this.total, required this.passPercent});

  final DlStat stat;
  final DlColumn col;
  final int total;
  final double passPercent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mx = col.maxValue == 0 ? 100.0 : col.maxValue;
    final counts = col.source == 'read_flags' || col.source == 'review_flags';
    Widget cell(String label, String value, {Color? color}) => Expanded(
      child: Column(children: [
        Text(value, maxLines: 1, style: dlText(16, w: FontWeight.w800, c: color ?? c.textDark)),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(10.5, c: c.textMedium)),
      ]),
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.insights_rounded, size: 18, color: c.primary),
          const SizedBox(width: 6),
          Expanded(child: Text(_tr('dl_insights', 'Class insights'), style: dlText(13, w: FontWeight.w800, c: c.textDark))),
          Text('${stat.filled} / $total ${_tr('dl_filled', 'filled')}', style: dlText(11, c: c.textMedium)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          cell(_tr('dl_avg', 'Average'), dlFmt(stat.avg), color: dlScoreColor(context, stat.avg == null ? null : stat.avg! / mx * 100)),
          cell(_tr('dl_median', 'Median'), dlFmt(stat.median)),
          cell(_tr('dl_range', 'Lowest – highest'), '${dlFmt(stat.min)}–${dlFmt(stat.max)}'),
          if (!counts)
            cell('${_tr('dl_pass_rate', 'Passed')} (≥${passPercent.round()}%)', stat.passRate == null ? '–' : '${stat.passRate!.round()}%',
                color: dlScoreColor(context, stat.passRate)),
        ]),
        if (!counts && stat.buckets.length == 5) ...[
          const SizedBox(height: 14),
          DlHistogram(buckets: stat.buckets),
        ],
        if (stat.std != null && stat.filled > 2) ...[
          const SizedBox(height: 10),
          Text(
            (stat.std! / mx * 100) > 25
                ? _tr('dl_spread_wide', 'Results are spread widely — some students may need extra support.')
                : _tr('dl_spread_tight', 'Results are close together across the class.'),
            style: dlText(11.5, c: c.textMedium, h: 1.4),
          ),
        ],
      ]),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.on,
    required this.color,
    required this.iconOn,
    required this.iconOff,
    required this.title,
    required this.sub,
    required this.onChanged,
  });

  final bool on;
  final Color color;
  final IconData iconOn, iconOff;
  final String title, sub;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.10) : c.textLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? color.withValues(alpha: 0.35) : Colors.transparent),
      ),
      child: Row(children: [
        Icon(on ? iconOn : iconOff, color: on ? color : c.textMedium),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 2),
            Text(sub, style: dlText(11.5, c: c.textMedium, h: 1.4)),
          ]),
        ),
        const SizedBox(width: 8),
        AppSwitch(value: on, activeColor: color, onChanged: onChanged, semanticLabel: title),
        const SizedBox(width: 4),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.45 : 1,
    child: Material(
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
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cells
// ─────────────────────────────────────────────────────────────────────────────

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
    final v = p.cellValue(row, col); // a formula's result, or the stored value
    final manual = row.overridden.contains(col.key);
    final view = p.viewOf(col); // this column's own way of drawing, else the sheet's default

    // ── style: hand highlight › first matching rule › colour scale › column tint ──
    final st = col.style;
    final look = p.lookOf(row, col);
    final hl = dlStyleColor(context, look.bg) ?? (look.scale != null ? dlScaleColor(context, look.scale!) : null);
    final fg = dlStyleColor(context, look.fg);
    final tint = dlStyleColor(context, st.color);
    final font = st.font ?? p.sheetFont;
    final k = st.size * p.sheetSize;
    final align = st.align ?? p.sheetAlign;
    TextStyle ts(double size, FontWeight w, Color color) {
      final t = dlText(size * z * k, w: w, c: color);
      return font == null ? t : t.copyWith(fontFamily: font);
    }

    final pad = EdgeInsets.symmetric(horizontal: (align == 'center' ? 6 : 12) * z);
    Widget content;
    if (col.isNumber && v != null) {
      final n = dlNum(v);
      final max = col.isPercent ? 100.0 : (col.maxValue == 0 ? 100.0 : col.maxValue);
      final pct = n == null ? null : n / max * 100;
      final text = Text(
        dlFmt(v),
        maxLines: 1,
        style: ts(13.5, look.bold ? FontWeight.w900 : FontWeight.w800, fg ?? (hl != null ? c.textDark : dlScoreColor(context, pct))),
      );
      final bar = Padding(
        padding: EdgeInsets.symmetric(horizontal: (view == DlView.bar ? 14 : 16) * z),
        child: DlBar(value: n, max: max, height: (view == DlView.bar ? 9 : 5) * z, marker: p.avgOf(col)),
      );
      content = switch (view) {
        DlView.value => Align(alignment: dlAlignment(align), child: Padding(padding: pad, child: text)),
        DlView.bar => Tooltip(message: dlFmt(v), child: Center(child: bar)),
        DlView.both => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Align(alignment: dlAlignment(align), child: Padding(padding: pad, child: text)),
          SizedBox(height: 2 * z),
          bar,
        ]),
      };
    } else if (v != null && '$v'.isNotEmpty) {
      content = Align(
        alignment: dlAlignment(align),
        child: Padding(
          padding: pad,
          child: Text('$v',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: dlTextAlign(align),
              style: ts(12.5, look.bold ? FontWeight.w800 : FontWeight.w500, fg ?? c.textDark)),
        ),
      );
    } else {
      content = Center(
        child: Icon(_editable && !col.isLocked ? Icons.add_rounded : Icons.remove_rounded,
            size: 16 * z, color: c.textLight.withValues(alpha: 0.6)),
      );
    }
    return InkWell(
      onTap: !_editable
          ? null
          : () {
        if (col.isLocked) {
          toast(dlLockedMessage(col), error: true);
          return;
        }
        _edit(context, manual, v);
      },
      // hold any cell (even a calculated one) to highlight it by hand
      onLongPress: () => _quickHighlight(context),
      onSecondaryTap: () => _quickHighlight(context),
      child: Container(
        width: p.widthOf(col.key) * z,
        height: _rowH * z,
        color: tint?.withValues(alpha: 0.06),
        child: Stack(children: [
          if (hl != null)
            Positioned.fill(
              child: Container(
                margin: EdgeInsets.all(3 * z),
                decoration: BoxDecoration(
                  color: hl.withValues(alpha: look.scale != null ? 0.16 : 0.22),
                  borderRadius: BorderRadius.circular(8 * z),
                  border: Border.all(color: hl.withValues(alpha: 0.45)),
                ),
              ),
            ),
          Positioned.fill(child: content),
          if (manual)
            PositionedDirectional(
              top: 7 * z,
              end: 9 * z,
              child: Tooltip(
                message: 'dl_manual_value'.tr,
                child: Icon(Icons.edit_rounded, size: 10 * z, color: c.primary.withValues(alpha: 0.8)),
              ),
            ),
        ]),
      ),
    );
  }

  /// Hand highlight of this one cell (shared with everyone on the sheet).
  Future<void> _quickHighlight(BuildContext context) async {
    final current = p.columnOf(col.key)?.style.cells[row.rowId];
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) {
        final c = ctx.colors;
        return Directionality(
          textDirection: pageDirection,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Material(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(24),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.format_color_fill_rounded, color: c.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('${row.name.isEmpty ? '—' : row.name} · ${col.label}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(14.5, w: FontWeight.w800, c: c.textDark)),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Text(_tr('dl_hl_cell_sub', 'Highlight this cell by hand. Everyone who opens the sheet sees it.'),
                        style: dlText(12, c: c.textMedium, h: 1.4)),
                    const SizedBox(height: 14),
                    DlSwatches(value: current, size: 34, onChanged: (t) => Navigator.pop(ctx, (t,))),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || picked.$1 == current) return;
    final e = await p.setCellColor(col, row, picked.$1);
    if (e != null) toast(e, error: true);
  }

  Future<void> _edit(BuildContext context, bool manual, dynamic current) async {
    final res = await showModalBottomSheet<String>(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.heroShade.withValues(alpha: 0.35),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => Directionality(
        textDirection: pageDirection,
        child: _CellEditor(p: p, row: row, col: col, manual: manual, current: current, outer: context),
      ),
    );
    if (res == null) return;
    final err = await p.saveCell(row, col, res);
    if (err != null) toast(err, error: true);
  }
}

/// Arabic / Persian digits and decimal comma → what double.tryParse understands.
String _latinNumber(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩', fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.trim().split('')) {
    final i = ar.indexOf(ch), j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : (j >= 0 ? '$j' : (ch == '٫' || ch == ',' ? '.' : ch)));
  }
  return b.toString().replaceAll('%', '').trim();
}

/// One value: big, focused, checked before it is sent (0 – full mark), with its history one tap away.
class _CellEditor extends StatefulWidget {
  const _CellEditor({required this.p, required this.row, required this.col, required this.manual, required this.current, required this.outer});

  final DataLabProvider p;
  final DlRow row;
  final DlColumn col;
  final bool manual;
  final dynamic current;
  final BuildContext outer;

  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  /// The exact stored value (dlFmt rounds to one decimal — editing must never lose precision).
  late final TextEditingController _ctrl = TextEditingController(text: _exact(widget.current));

  /// Hand highlight of this cell (applied at once).
  late String? _hl = widget.p.columnOf(widget.col.key)?.style.cells[widget.row.rowId];

  Future<void> _setHighlight(String? t) async {
    setState(() => _hl = t);
    final e = await widget.p.setCellColor(widget.col, widget.row, t);
    if (e != null) toast(e, error: true);
  }

  static String _exact(dynamic v) {
    if (v == null) return '';
    if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    return '$v';
  }
  String? _error;

  DlColumn get col => widget.col;

  bool get _counts => col.source == 'read_flags' || col.source == 'review_flags';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Null when the value can be saved, otherwise a friendly reason.
  String? _check(String raw) {
    if (!col.isNumber || raw.trim().isEmpty) return null;
    final n = double.tryParse(_latinNumber(raw));
    if (n == null) return _tr('dl_err_number', 'Please type a number, e.g. 17.5');
    if (n < 0) return _tr('dl_err_negative', 'The value cannot be below 0');
    if (!_counts && n > col.maxValue + 1e-9) {
      return '${_tr('dl_err_above_max', 'The full mark of this column is')} ${dlFmt(col.maxValue)}';
    }
    return null;
  }

  void _save() {
    final raw = _ctrl.text;
    final e = _check(raw);
    if (e != null) return setState(() => _error = e);
    Navigator.pop(context, col.isNumber ? _latinNumber(raw) : raw.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = widget.row;
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(4)))),
                const SizedBox(height: 14),
                Row(children: [
                  DlAvatar(name: r.name, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r.name.isEmpty ? '—' : r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(15.5, w: FontWeight.w800, c: c.textDark)),
                      Text(col.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(12.5, w: FontWeight.w600, c: c.primary)),
                    ]),
                  ),
                  IconButton(
                    tooltip: _tr('dl_history_short', 'History'),
                    icon: Icon(Icons.history_rounded, color: c.textMedium),
                    onPressed: () {
                      final outer = widget.outer;
                      Navigator.pop(context);
                      if (outer.mounted) showHistorySheet(outer, widget.p, rowId: r.rowId, title: '${r.name} · ${col.label}');
                    },
                  ),
                ]),
                if (widget.manual && !col.isCustom) ...[
                  const SizedBox(height: 12),
                  DlBanner(icon: Icons.edit_rounded, text: 'dl_manual_hint'.tr, color: c.primary),
                ],
                const SizedBox(height: 16),
                if (col.options.isNotEmpty)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final o in col.options)
                      DlChoiceChip(label: o, selected: '${widget.current ?? ''}' == o, onTap: () => Navigator.pop(context, o)),
                  ])
                else
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    textAlign: col.isNumber ? TextAlign.center : TextAlign.start,
                    keyboardType: col.isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    onSubmitted: (_) => _save(),
                    style: col.isNumber ? dlText(30, w: FontWeight.w800, c: c.textDark) : dlText(15, c: c.textDark),
                    decoration: InputDecoration(
                      hintText: col.isNumber ? '0 – ${dlFmt(col.maxValue)}' : 'dl_value'.tr,
                      hintStyle: col.isNumber ? dlText(26, w: FontWeight.w700, c: c.textLight) : dlText(14, c: c.textLight),
                      suffixText: col.isNumber && !_counts ? '/ ${dlFmt(col.maxValue)}' : null,
                      suffixStyle: dlText(14, w: FontWeight.w700, c: c.textMedium),
                      errorText: _error,
                      filled: true,
                      fillColor: c.inputBg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.divider)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.divider)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.primary, width: 1.6)),
                    ),
                  ),
                if (col.isNumber && widget.p.avgOf(col) != null) ...[
                  const SizedBox(height: 8),
                  Text('${'dl_class_avg'.tr}: ${dlFmt(widget.p.avgOf(col))}', textAlign: TextAlign.center, style: dlText(11.5, c: c.textMedium)),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  Icon(Icons.format_color_fill_rounded, size: 16, color: c.textMedium),
                  const SizedBox(width: 6),
                  Text(_tr('dl_hl_cell', 'Highlight this cell'), style: dlText(12, w: FontWeight.w800, c: c.textMedium)),
                ]),
                const SizedBox(height: 8),
                DlSwatches(value: _hl, size: 28, onChanged: _setHighlight),
                const SizedBox(height: 16),
                Row(children: [
                  if (widget.manual && !col.isCustom)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(color: c.divider),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(context, ''),
                        icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                        label: Text('dl_auto_value'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
                      ),
                    )
                  else if (col.isCustom && widget.current != null)
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: BorderSide(color: c.divider),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () => Navigator.pop(context, ''),
                        icon: Icon(Icons.backspace_outlined, size: 18, color: c.danger),
                        label: Text('dl_clear_value'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.danger)),
                      ),
                    ),
                  if ((widget.manual && !col.isCustom) || (col.isCustom && widget.current != null)) const SizedBox(width: 10),
                  if (col.options.isEmpty)
                    Expanded(flex: 2, child: DlPrimaryButton(label: 'save'.tr, icon: Icons.check_rounded, onPressed: _save))
                  else
                    Expanded(
                      flex: 2,
                      child: TextButton(onPressed: () => Navigator.pop(context), child: Text('cancel'.tr)),
                    ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
