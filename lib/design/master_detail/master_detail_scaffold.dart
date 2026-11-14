// lib/design/master_detail/master_detail_scaffold.dart — THE list + detail host of every role's lists (D-290).
//
//   MasterDetailScaffold(
//     controller: _panel,                       // EntityPanelController(rowKind: EntityKind.student)
//     list: AdminPage(…AppDataTable(onRowTap: (u) => _panel.open(EntityRef(…)))…),
//     actions: (ref, summary) => [EntityPanelAction(…)],   // quick actions under the header (Manage …)
//     rootLabel: 'Students',                    // the first breadcrumb
//     deepLinks: true,                          // `?open=<kind>:<id>` on the list's URL, and opened from it
//   )
//
// Measured on its own width (a page inside a shell is narrower than the window):
//   >= 1000   the list stays, the panel sits beside it at the END side (left in Arabic), resizable by its handle
//             (360 – 60 % of the width, remembered on this device)
//   700 – 999 the panel slides over the list from the end side, above a scrim
//   < 700     a draggable bottom sheet (half → full height) over the list
// Back closes the panel first (a local history entry on the page's route; the role shells honour it). Keyboard (web /
// desktop): ↑ / ↓ move between the rows (the panel follows when open), Enter opens, Esc closes, Alt+← / Alt+→ walk
// the trail. Opening, swapping and closing are announced to screen readers.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/routing/web_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_responsive.dart';
import '../app_shell_nav.dart' show ShellScope;
import '../app_tokens.dart';
import 'entity_detail_view.dart';
import 'entity_navigator.dart';
import 'entity_panel.dart';
import 'entity_panel_controller.dart';
import 'entity_specs.dart' show mdText;

class MasterDetailScaffold extends StatefulWidget {
  const MasterDetailScaffold({
    super.key,
    required this.controller,
    required this.list,
    this.actions,
    this.rootLabel,
    this.deepLinks = false,
  });

  final EntityPanelController controller;
  final Widget list;
  final EntityActionsBuilder? actions;
  final String? rootLabel;

  /// Writes `?open=<kind>:<id>` on the list's URL while the panel is open, and opens a panel the URL asked for.
  final bool deepLinks;

  /// The inline panel's width limits and default.
  static const double minPanel = 360;
  static const double defaultPanel = 440;
  static const double maxPanelShare = 0.6;

  /// The overlay panel's width (700 – 999).
  static const double overlayPanel = 480;

  static const String widthPrefKey = 'master_detail.panel_width.v1';

  /// The layout for a width.
  static EntityPanelMode modeFor(double width) => width >= Breakpoints.desktop
      ? EntityPanelMode.inline
      : (width >= Breakpoints.mobile ? EntityPanelMode.overlay : EntityPanelMode.sheet);

  @override
  State<MasterDetailScaffold> createState() => _MasterDetailScaffoldState();
}

class _MasterDetailScaffoldState extends State<MasterDetailScaffold> {
  static double? _rememberedWidth;

  double _width = _rememberedWidth ?? MasterDetailScaffold.defaultPanel;
  LocalHistoryEntry? _entry;
  ModalRoute<dynamic>? _route;
  final _focus = FocusNode(debugLabel: 'master-detail');
  final _sheet = DraggableScrollableController();
  EntityRef? _announced;
  bool _wasOpen = false;

  EntityPanelController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_changed);
    if (_rememberedWidth == null) {
      SharedPreferences.getInstance().then((p) {
        final w = p.getDouble(MasterDetailScaffold.widthPrefKey);
        if (w != null && mounted) setState(() => _width = _rememberedWidth = w);
      }, onError: (Object _) {});
    }
    if (widget.deepLinks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final from = EntityLinkRequest.takeFrom;
        final r = EntityLinkRequest.take();
        if (r == null || !mounted) return;
        _c.open(from ?? r);
        if (from != null) _c.push(r);
      });
    }
    if (_c.isOpen) WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant MasterDetailScaffold old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    final e = _entry;
    _entry = null;
    if (e != null) e.remove();
    WebHistory.instance.setPageQuery(this, 'open', null);
    _focus.dispose();
    _sheet.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final open = _c.isOpen;
    _syncBack(open);
    if (widget.deepLinks) {
      final cur = _c.current;
      WebHistory.instance.setPageQuery(this, 'open', cur == null ? null : EntityLinkRequest.token(cur, from: _c.contextRef));
    }
    _announce();
    if (open && !_wasOpen) _takeFocus();
    _wasOpen = open;
    setState(() {});
  }

  /// Back closes the panel first: a local history entry on the page's route while it is open.
  void _syncBack(bool open) {
    final shell = ShellScope.maybeOf(context);
    if (open && _entry == null && _route != null) {
      final e = LocalHistoryEntry(onRemove: _entryRemoved, impliesAppBarDismissal: false);
      _entry = e;
      _route!.addLocalHistoryEntry(e);
      shell?.popStateChanged();
    } else if (!open && _entry != null) {
      final e = _entry!;
      _entry = null;
      e.remove();
      shell?.popStateChanged();
    }
  }

  void _entryRemoved() {
    if (_entry == null) return; // removed by _syncBack
    _entry = null;
    if (mounted) ShellScope.maybeOf(context)?.popStateChanged();
    _c.close();
  }

  void _announce() {
    final cur = _c.current;
    if (cur == _announced) return;
    final String text;
    if (cur == null) {
      text = 'md_announce_closed'.tr;
    } else {
      final name = cur.name.isEmpty ? _siblingName(cur) : cur.name;
      text = mdText('md_announce_open', {'name': name.isEmpty ? '#${cur.id}' : name});
    }
    _announced = cur;
    SemanticsService.sendAnnouncement(View.of(context), text, Directionality.of(context));
  }

  String _siblingName(EntityRef r) {
    for (final s in _c.siblings) {
      if (s == r) return s.name;
    }
    return '';
  }

  /// The keys reach the list + panel (unless a text field has the focus: it keeps its own keys).
  void _takeFocus() {
    final f = FocusManager.instance.primaryFocus;
    if (f != null && f.context?.widget is EditableText) return;
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _move(int d) {
    _takeFocus();
    if (d > 0) {
      _c.next();
    } else {
      _c.previous();
    }
  }

  void _enter() {
    final r = _c.cursorRef;
    if (r != null && _c.current != r) _c.open(r);
  }

  double _panelWidth(double total) {
    final max = math.max(MasterDetailScaffold.minPanel, total * MasterDetailScaffold.maxPanelShare);
    return _width.clamp(MasterDetailScaffold.minPanel, max).toDouble();
  }

  void _resize(double dx, double total, bool rtl) {
    setState(() {
      _width = _panelWidth(total) + (rtl ? dx : -dx);
      _width = _panelWidth(total);
    });
  }

  void _saveWidth() {
    _rememberedWidth = _width;
    SharedPreferences.getInstance().then((p) => p.setDouble(MasterDetailScaffold.widthPrefKey, _width),
        onError: (Object _) => false);
  }

  @override
  Widget build(BuildContext context) {
    final list = MasterDetailScope(controller: _c, child: widget.list);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _enter,
        const SingleActivator(LogicalKeyboardKey.escape): _c.close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _c.back(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _c.forward(),
      },
      child: Focus(
        focusNode: _focus,
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final mode = MasterDetailScaffold.modeFor(w);
          final open = _c.isOpen;
          final motion = AppMotion.of(context);
          final rtl = Directionality.of(context) == TextDirection.rtl;
          final c = context.colors;
          Widget panel(EntityPanelMode m, {ScrollController? sc}) => EntityPanel(
                key: const ValueKey('md.panel'),
                controller: _c,
                mode: m,
                actions: widget.actions,
                rootLabel: widget.rootLabel,
                scrollController: sc,
                onHandleDrag: m == EntityPanelMode.sheet
                    ? (dy) {
                        if (!_sheet.isAttached || box.maxHeight <= 0) return;
                        _sheet.jumpTo((_sheet.size - dy / box.maxHeight).clamp(0.25, 1.0));
                      }
                    : null,
                onHandleTap: m == EntityPanelMode.sheet
                    ? () {
                        if (!_sheet.isAttached) return;
                        _sheet.animateTo(_sheet.size < 0.95 ? 1.0 : 0.6,
                            duration: motion.base == Duration.zero ? const Duration(milliseconds: 1) : motion.base,
                            curve: AppMotion.curve);
                      }
                    : null,
              );

          switch (mode) {
            case EntityPanelMode.inline:
            case EntityPanelMode.page:
              final pw = _panelWidth(w);
              return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: list),
                if (open) ...[
                  _ResizeHandle(onDrag: (dx) => _resize(dx, w, rtl), onEnd: _saveWidth),
                  SizedBox(
                    width: pw,
                    child: _SlideIn(
                      rtl: rtl,
                      duration: motion.base,
                      child: DecoratedBox(
                        key: const ValueKey('md.inline'),
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          boxShadow: AppElevation.of(context, 2),
                          border: AppElevation.border(context, 2),
                        ),
                        child: panel(EntityPanelMode.inline),
                      ),
                    ),
                  ),
                ],
              ]);
            case EntityPanelMode.overlay:
              final pw = math.min(MasterDetailScaffold.overlayPanel, w * 0.88);
              return Stack(children: [
                Positioned.fill(child: list),
                if (open) ...[
                  Positioned.fill(child: _Scrim(onTap: _c.close)),
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    end: 0,
                    width: pw,
                    child: _SlideIn(
                      rtl: rtl,
                      duration: motion.base,
                      child: DecoratedBox(
                        key: const ValueKey('md.overlay'),
                        decoration: BoxDecoration(
                          color: c.cardBg,
                          boxShadow: AppElevation.of(context, 3),
                          border: BorderDirectional(start: BorderSide(color: c.divider, width: AppBorder.hairline)),
                        ),
                        child: panel(EntityPanelMode.overlay),
                      ),
                    ),
                  ),
                ],
              ]);
            case EntityPanelMode.sheet:
              return Stack(children: [
                Positioned.fill(child: list),
                if (open) ...[
                  Positioned.fill(child: _Scrim(onTap: _c.close)),
                  Positioned.fill(
                    child: NotificationListener<DraggableScrollableNotification>(
                      onNotification: (n) {
                        if (n.extent <= n.minExtent + 0.01) WidgetsBinding.instance.addPostFrameCallback((_) => _c.close());
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        key: const ValueKey('md.sheet'),
                        controller: _sheet,
                        initialChildSize: 0.6,
                        minChildSize: 0.25,
                        maxChildSize: 1,
                        snap: true,
                        snapSizes: const [0.6],
                        builder: (context, sc) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.cardBg,
                            borderRadius: AppRadius.sheetTop,
                            boxShadow: AppElevation.of(context, 4),
                          ),
                          child: ClipRRect(borderRadius: AppRadius.sheetTop, child: panel(EntityPanelMode.sheet, sc: sc)),
                        ),
                      ),
                    ),
                  ),
                ],
              ]);
          }
        }),
      ),
    );
  }
}

/// The panel coming in from the end side (instant under Reduce motion).
class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.rtl, required this.duration, required this.child});

  final bool rtl;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: duration,
        curve: AppMotion.curve,
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: FractionalTranslation(translation: Offset((1 - t) * (rtl ? -0.06 : 0.06), 0), child: child),
        ),
      );
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ColoredBox(color: Theme.of(context).colorScheme.scrim.withValues(alpha: context.colors.isDark ? 0.5 : 0.32)),
      );
}

/// The drag handle between the list and the inline panel.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag, required this.onEnd});

  final ValueChanged<double> onDrag;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const ValueKey('md.resize'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          onHorizontalDragEnd: (_) => onEnd(),
          child: SizedBox(
            width: AppSpace.xs,
            child: Center(child: Container(width: AppBorder.hairline, color: context.colors.divider)),
          ),
        ),
      );
}

/// Opens [ref] in the nearest master-detail panel, or its full page (a convenience for callers outside a list).
void openEntity(BuildContext context, EntityRef ref) => EntityNavigator.open(context, ref);
