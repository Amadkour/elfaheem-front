// lib/features/org/org_page_header.dart
//
// THE page header of every page of the organization dashboard (D-103) — phones included (they have no shell top
// bar), and the shell's own top bar is off (AppShell(showTopBar: false)), so nothing is drawn twice.
//
//   OrgPageHeader({required String title, String? subtitle, Widget? primaryAction, bool back = false})
//       back: a Back button leads the header (pages pushed on top — use OrgPushedPage, below).
//       The switcher pill degrades on narrow rows (ContextPill): one line → two lines → the mark alone (the full
//       name stays in its tooltip, its screen-reader label and the sheet).
//       title (+ one line: the subtitle · "Updated 2 min ago") · at most ONE primary action · Search (the command
//       palette, when the shell's AppCommandPaletteScope is on: a chip on wide, a full-width bar under the title on
//       phones) · Refresh · calendar · messages · assistant · notifications · help · the context switcher pill (all my
//       organizations + Personal; an organization switches in place, Personal leaves) · the focus toggle, ALWAYS last at
//       the end edge (the labelled way out while focus mode is on). From 600 px: one row, AppHeader's height. Phones:
//       row 1 = the pill + the calendar / messages / bell, row 2 = Back · the title block · Refresh, the action under it.
//       Refresh state comes from the nearest OrgPageRefreshScope (the shell gives each page its own); without one
//       there is no Refresh button.
//       The look is AppHeader's editorial masthead (D-614): the canvas, a 2 px primary strip on top, the title in the
//       editorial page-title face in ink, the tools as paper chips, the ONE primary action bare, a warm hairline under it.
//       It collapses with the page's scrolling (AppHeaderCollapse), so it must stay OUTSIDE the scrollable: a Column
//       with the header above an Expanded body. Compact keeps Back · the title · the tools; on phones the pill row
//       folds away and comes back on the first scroll up.
//
//   OrgPageRefresh — the refresh state of ONE page:
//       // initState (allowed: no dependency is made)
//       _refresh = OrgPageRefresh.register(context, _reload);    // the header's Refresh now runs _reload
//       // after each load
//       OrgPageRefresh.reportUpdated(context, data.generatedAt);  // "Updated …" shows that time
//       // dispose
//       _refresh?.unregister(_reload);
//     Keep passing the same function (a method tear-off is fine). A page that registers nothing is refreshed by
//     re-keying it: it is rebuilt from scratch and reloads only its own data; "Updated" is then the rebuild time.
//
//   OrgPageRefreshScope / OrgPageRefreshBody — what the shell wraps around each page (the scope above the header,
//     the body around the page: re-keyed on Refresh when nothing is registered; "Updated" restarts when the
//     organization changes).
//   orgUpdatedText(at, now) — the pure "Updated 2 min ago" text; OrgClock.minute ticks once a minute while shown.
//
//   OrgPushedPage(title:, subtitle:, primaryAction:, refresh:, child:) — a page pushed ON TOP of the dashboard (a
//     department, a page opened from More / a shortcut): the same header with a Back button first, its own refresh
//     scope (pass [refresh] to drive it yourself, else Refresh re-keys the page), re-keyed when my access changes and
//     closed when another organization is chosen in the switcher (it belonged to the previous one). Its card is
//     AppWidth.wide unless the page names a [width] role (forms: form · reading) or an older [maxWidth].
//   orgUsesDashboardHeader(context, orgId) — a detail / editor screen that a student, a member page or a deep link
//     may open too wears OrgPushedPage only when I work in that organization (OrgSession lists it; students never
//     are there), else it keeps its own older app bar.
//
//   OrgPageFrame(header:, body:, width:) — how a header and its page meet (D-570, D-614). The header sits on the
//     canvas edge to edge above the page (no gradient band any more); the page body takes its width role under it.
//
// Layout test: test/ui/org_page_header_layout_test.dart; renders: test/visual/org_shell_golden_test.dart.
library;

import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_back_button.dart';
import 'package:flutter_education_app/config/app_config.dart' show AppConfig, translate;
import 'package:flutter_education_app/design/app_focus_mode.dart' show AppFocusExitButton, AppFocusMode, AppFocusToggle;
import 'package:flutter_education_app/design/app_header.dart' show AppHeader, AppHeaderCollapse, appBarCardMargin;
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/design/app_shell.dart' show NotificationIcon;
import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellScope;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/calendar_entry.dart' show CalendarEntryIcon, ChatEntryIcon;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeCard, ChromeIconButton;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextPill;
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/shared/rag/app_assistant.dart' show AppAssistant, appAssistantFeatureKey;
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
import '../shared/help/help_info_button.dart';
import 'org_common.dart' show orgColor, orgTypeIcons;
import 'org_dashboard_settings.dart' show showOrgSwitcher;
import 'org_providers.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Refresh state of one page
// ═════════════════════════════════════════════════════════════════════════════

/// A clock that ticks once a minute while something shows a relative time ("Updated 2 min ago"); no timer runs
/// while nothing listens.
class OrgClock extends ChangeNotifier {
  OrgClock._();

  static final OrgClock minute = OrgClock._();

  /// Replaceable in tests.
  static DateTime Function() now = DateTime.now;

  Timer? _timer;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => notifyListeners());
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }
}

/// "Updated just now" · "Updated 2 min ago" · "Updated 3 h ago" · "Updated 12 Oct 2026 · 09:30".
String orgUpdatedText(DateTime at, DateTime now) {
  final d = now.difference(at);
  final m = d.inMinutes;
  if (m < 1) return t('تم التحديث الآن', 'Updated just now');
  String ar(int n, String one, String two, String few, String many) =>
      n == 1 ? one : n == 2 ? two : n <= 10 ? '$n $few' : '$n $many';
  if (m < 60) return t('تم التحديث منذ ${ar(m, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}', 'Updated $m min ago');
  final h = d.inHours;
  if (h < 24) return t('تم التحديث منذ ${ar(h, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}', 'Updated $h h ago');
  final when = AppTime.dateTime(at.toUtc());
  return t('آخر تحديث $when', 'Updated $when');
}

/// The refresh state of ONE page of the dashboard: who refreshes it, whether it is refreshing and when it was
/// last updated. See the file header for the page side.
class OrgPageRefresh extends ChangeNotifier {
  OrgPageRefresh() : _updatedAt = OrgClock.now();

  Future<void> Function()? _refresher;
  DateTime _updatedAt;
  bool _busy = false;
  bool _reported = false;
  bool _disposed = false;

  /// Bumped to re-key a page that registered no refresher.
  final ValueNotifier<int> generation = ValueNotifier(0);

  DateTime get updatedAt => _updatedAt;
  bool get busy => _busy;
  bool get hasRefresher => _refresher != null;

  /// The scope of [context] (null outside the dashboard). [listen]: rebuild when the state changes.
  static OrgPageRefresh? maybeOf(BuildContext context, {bool listen = true}) => listen
      ? context.dependOnInheritedWidgetOfExactType<OrgPageRefreshScope>()?.notifier
      : context.getInheritedWidgetOfExactType<OrgPageRefreshScope>()?.notifier;

  /// The page of [context] refreshes with [refresher] (callable from initState). Returns the scope, to
  /// [unregister] from dispose.
  static OrgPageRefresh? register(BuildContext context, Future<void> Function() refresher) =>
      maybeOf(context, listen: false)?..attach(refresher);

  /// The page of [context] loaded its data, as of [at] (default: now).
  static void reportUpdated(BuildContext context, [DateTime? at]) => maybeOf(context, listen: false)?.markUpdated(at);

  void attach(Future<void> Function() refresher) => _refresher = refresher;

  void unregister(Future<void> Function() refresher) {
    if (_refresher == refresher) _refresher = null;
  }

  void markUpdated([DateTime? at]) {
    _updatedAt = at ?? OrgClock.now();
    _reported = true;
    _notify();
  }

  /// The page was rebuilt from scratch (another organization): "Updated" starts again.
  void restarted() {
    _updatedAt = OrgClock.now();
    _reported = false;
    _notify();
  }

  /// The header's Refresh: the registered refresher, else a re-key of the page.
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    _reported = false;
    _notify();
    try {
      final fn = _refresher;
      if (fn != null) {
        await fn();
      } else {
        generation.value++;
      }
    } catch (_) {
      // the page shows its own error; the header only stops spinning
    } finally {
      _busy = false;
      if (!_reported) _updatedAt = OrgClock.now();
      _notify();
    }
  }

  /// Never notifies in the middle of a build (a page may report from its build): it waits for the frame's end.
  void _notify() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    generation.dispose();
    super.dispose();
  }
}

class OrgPageRefreshScope extends InheritedNotifier<OrgPageRefresh> {
  const OrgPageRefreshScope({super.key, required OrgPageRefresh controller, required super.child})
      : super(notifier: controller);
}

/// The page under the header: re-keyed by a Refresh when it registered nothing; "Updated" restarts when
/// [pageKey] (the organization + its epoch) changes.
class OrgPageRefreshBody extends StatefulWidget {
  const OrgPageRefreshBody({super.key, required this.controller, required this.pageKey, required this.child});

  final OrgPageRefresh controller;
  final String pageKey;
  final Widget child;

  @override
  State<OrgPageRefreshBody> createState() => _OrgPageRefreshBodyState();
}

class _OrgPageRefreshBodyState extends State<OrgPageRefreshBody> {
  @override
  void didUpdateWidget(OrgPageRefreshBody old) {
    super.didUpdateWidget(old);
    if (old.pageKey != widget.pageKey) widget.controller.restarted();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: widget.controller.generation,
        builder: (_, g, _) => KeyedSubtree(key: ValueKey('${widget.pageKey}#$g'), child: widget.child),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  A page pushed on top of the dashboard
// ═════════════════════════════════════════════════════════════════════════════

/// Whether a detail / editor screen of organization [orgId] wears the dashboard's header ([OrgPushedPage]): the
/// signed-in person works in that organization (the session lists it, and it never lists one where I study). A
/// student, a member page or a deep link opened before the session loaded keep the screen's own app bar.
bool orgUsesDashboardHeader(BuildContext context, int? orgId) {
  final s = OrgPageHeader._maybe<OrgSession>(context, listen: false);
  if (s == null || s.current == null) return false;
  return orgId == null || s.currentId == orgId;
}

class OrgPushedPage extends StatefulWidget {
  const OrgPushedPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.primaryAction,
    this.refresh,
    this.maxWidth,
    this.width,
    this.helpPageId,
  });

  /// The page id of the Info button (help entry); null = no button.
  final String? helpPageId;
  final String title;
  final String? subtitle;
  final Widget? primaryAction;
  final Widget child;

  /// The page's own refresh state (it attaches its loader and reports "Updated"); null = one is made here and a
  /// Refresh re-keys [child].
  final OrgPageRefresh? refresh;

  /// The card's max width in pixels (older pages); new code names a [width] role. With neither: [AppWidth.wide], so a
  /// list or a dashboard fills the window. A form or reading page says so ([AppWidth.form] / [AppWidth.reading]).
  final double? maxWidth;
  final AppWidth? width;

  @override
  State<OrgPushedPage> createState() => _OrgPushedPageState();
}

class _OrgPushedPageState extends State<OrgPushedPage> {
  OrgPageRefresh? _own;
  OrgSession? _session;
  int? _orgId;
  bool _closing = false;

  OrgPageRefresh get _refresh => widget.refresh ?? (_own ??= OrgPageRefresh());

  @override
  void initState() {
    super.initState();
    _session = OrgPageHeader._maybe<OrgSession>(context, listen: false);
    _orgId = _session?.currentId;
    _session?.addListener(_onSession);
  }

  /// Another organization was chosen in the switcher: this page belonged to the previous one.
  void _onSession() {
    final s = _session;
    if (s == null || _closing || !mounted || s.currentId == _orgId) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // exactly this page (the switcher sheet, or a page above it, may still be on top)
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      final nav = Navigator.of(context);
      route.isCurrent ? nav.pop() : nav.removeRoute(route);
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_onSession);
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final Widget body = s == null
        ? widget.child
        : ValueListenableBuilder<int>(
            valueListenable: s.epoch,
            builder: (_, e, _) => OrgPageRefreshBody(controller: _refresh, pageKey: '$_orgId-$e', child: widget.child),
          );
    return OrgPageRefreshScope(
      controller: _refresh,
      child: OrgPageFrame(
        maxWidth: widget.maxWidth,
        width: widget.width ?? (widget.maxWidth == null ? AppWidth.wide : null),
        header: OrgPageHeader(title: widget.title, subtitle: widget.subtitle, primaryAction: widget.primaryAction, back: true, helpPageId: widget.helpPageId),
        body: body,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Where the header and the page meet
// ═════════════════════════════════════════════════════════════════════════════

/// Under this, [OrgPageHeader] is laid by [OrgPageFrame], which paints the canvas behind it.
class _OrgFrameScope extends InheritedWidget {
  const _OrgFrameScope({required super.child});

  static bool on(BuildContext context) => context.getInheritedWidgetOfExactType<_OrgFrameScope>() != null;

  @override
  bool updateShouldNotify(_OrgFrameScope oldWidget) => false;
}

/// A page of the organization dashboard: its [header] and its [body] (D-570, D-614).
///
/// The editorial masthead sits on the canvas edge to edge, the page under it takes the page-width role [width] (or the
/// older [maxWidth]) and the whole height that is left. Phones: the header above the page, the full width.
class OrgPageFrame extends StatelessWidget {
  const OrgPageFrame({super.key, required this.header, required this.body, this.width = AppWidth.wide, this.maxWidth});

  final Widget header;
  final Widget body;
  final AppWidth? width;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context);
    if (window.width < AppWidth.phoneMax) {
      return BasePage(child: Column(children: [header, Expanded(child: body)]));
    }
    final page = LayoutBuilder(builder: (context, box) {
      final w = width != null ? width!.inside(box.maxWidth) : AppWidth.content.inside(box.maxWidth, max: maxWidth);
      return Align(alignment: Alignment.topCenter, child: SizedBox(width: w, height: box.maxHeight, child: body));
    });
    return Material(
      color: context.colors.background,
      // the header is above the page's Scaffold now: this is what reports the page's scrolling to its collapse
      child: ScrollNotificationObserver(
        child: _OrgFrameScope(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top), child: header),
            Expanded(
              child: MediaQuery.removePadding(context: context, removeTop: true, child: BasePage(child: page)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The header
// ═════════════════════════════════════════════════════════════════════════════

class OrgPageHeader extends StatelessWidget {
  const OrgPageHeader(
      {super.key, required this.title, this.subtitle, this.primaryAction, this.searchBar = false, this.back = false, this.helpPageId});

  /// The page id of the Info button (help entry); null = no button.
  final String? helpPageId;

  final String title;

  /// A page pushed on top of the dashboard (a department, a page opened from More): a Back button leads the header
  /// (the arrow mirrors in Arabic by itself).
  final bool back;

  /// Phones: draw the full-width "Search pages, departments, people" bar under the title. Only Home asks for it:
  /// the other pages have their own search box, and two look-alike search fields stacked confuse. (Wide screens
  /// always keep the Search chip; Ctrl+K works everywhere.)
  final bool searchBar;

  /// One line under the title (e.g. what the page is for); null = none.
  final String? subtitle;

  /// The page's ONE primary action (e.g. "Add member"), drawn after the title; null = none.
  final Widget? primaryAction;

  /// From this width the header is one row (the rail shell included).
  static const double wideFrom = 600;

  /// Below this a primary action no longer fits the row: it goes under the title.
  static const double actionInRowFrom = 900;

  /// From this width Search keeps its label and the switcher its name (a primary action in the row needs more).
  static const double roomyFrom = 1040;
  static const double roomyWithActionFrom = 1160;

  @override
  Widget build(BuildContext context) {
    final refresh = OrgPageRefresh.maybeOf(context);
    final session = _maybe<OrgSession>(context);
    final unread = _unread(context);
    final onFrame = _OrgFrameScope.on(context);
    // the command palette (D-103): only under the shell's AppCommandPaletteScope, which is off with `org.search`
    final search = AppCommandPaletteScope.openerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideFrom;
      final roomy = box.maxWidth >= (primaryAction == null ? roomyFrom : roomyWithActionFrom);
      final actionBelow = box.maxWidth < actionInRowFrom;
      final pill = session == null || session.currentId == null ? null : _OrgPill(session: session);
      // built once here and reused by every frame of the collapse: only the sizes around them animate
      final help = helpPageId == null ? null : HelpInfoButton(pageId: helpPageId!);
      final backBtn = back
          ? const KeyedSubtree(key: ValueKey('org.header.back'), child: AppBackButton())
          : null;
      // on the canvas the ONE primary action stands bare (D-614)
      final action = primaryAction;
      // under the title, a long label at a large text scale shrinks a little rather than overflow
      final actionFitted = action == null
          ? null
          : FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: action);
      final Widget? phoneRefresh = refresh != null && !wide ? _RefreshIcon(refresh: refresh) : null;
      final Widget? phoneSearch = search != null && searchBar && !wide ? _SearchBar(onTap: search) : null;
      final Widget? phoneChrome = wide
          ? null
          : Row(children: [
              Expanded(
                child: Align(alignment: AlignmentDirectional.centerStart, child: pill ?? const SizedBox.shrink()),
              ),
              AppSpace.gapXs,
              Row(mainAxisSize: MainAxisSize.min, children: [
                const CalendarEntryIcon(),
                const ChatEntryIcon(),
                NotificationIcon(unreadCount: unread),
                ?help,
              ]),
            ]);
      // the one order of every header's end (D-551): page tools, app-wide tools, the context, focus last
      final Widget? wideTools = !wide
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [
              if (search != null) _ChipButton(icon: Icons.search_rounded, label: _searchLabel, onTap: search, compact: !roomy),
              if (refresh != null) _RefreshIcon(refresh: refresh),
              const CalendarEntryIcon(),
              const ChatEntryIcon(),
              if (!AppConfig.disableList.contains(appAssistantFeatureKey))
                ChromeIconButton(icon: Icons.auto_awesome_rounded, label: translate('assistant_entry_title'), onTap: AppAssistant.openPanel),
              NotificationIcon(unreadCount: unread),
              ?help,
            ]);
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
      final hasLine = refresh != null || (subtitle ?? '').isNotEmpty;
      final openHeight = (hasLine ? AppHeader.openHeightWithSubtitle : AppHeader.openHeight) * scale;
      final shutHeight = AppHeader.compactHeight * (1 + (scale - 1) * 0.5);
      return AppHeaderCollapse(
        builder: (context, collapse, _) {
          final content = AnimatedBuilder(
            animation: collapse,
            builder: (context, _) {
              final shut = collapse.value;
              final below = wide && actionBelow ? actionFitted : null;
              final titleBlock = _TitleBlock(
                title: title,
                subtitle: subtitle,
                updated: refresh,
                below: below,
                shut: shut,
                oneLine: wide,
              );
              if (wide) {
                final row = Row(children: [
                  if (backBtn != null) ...[backBtn, const SizedBox(width: AppSpace.xxs)],
                  Expanded(child: below == null ? ClipRect(child: titleBlock) : titleBlock),
                  if (action != null && !actionBelow) ...[
                    AppSpace.gapSm,
                    // no taller than a touch target: a button that fills its height grew to the whole header
                    ConstrainedBox(constraints: const BoxConstraints(maxHeight: AppTouch.min), child: primaryAction!),
                  ],
                  AppSpace.gapSm,
                  wideTools!,
                  if (pill != null) ...[
                    AppSpace.gapXs,
                    // the switcher falls back to its mark on a short row (ContextPill)
                    ConstrainedBox(constraints: BoxConstraints(maxWidth: roomy ? 240 : ContextPill.markOnlyBelow - 1), child: pill),
                  ],
                  const _FocusEnd(),
                ]);
                // the same height as AppHeader; only a row carrying its action under the title is taller
                return Padding(
                  padding: EdgeInsetsDirectional.only(start: back ? AppSpace.xs : AppSpace.lg, end: AppSpace.md),
                  child: below == null
                      ? SizedBox(height: lerpDouble(openHeight, shutHeight, shut), child: row)
                      : ConstrainedBox(
                          constraints: BoxConstraints(minHeight: shutHeight),
                          child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs), child: row),
                        ),
                );
              }
              final vertical = lerpDouble(AppSpace.sm, AppSpace.xxs, shut)!;
              return Padding(
                padding: EdgeInsetsDirectional.fromSTEB(back ? AppSpace.xs : AppSpace.md, vertical, AppSpace.md, vertical),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  // compact keeps Back · the title · Refresh: the switcher and the tools return on the first scroll up
                  _Fold(
                    shut: shut,
                    child: Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: phoneChrome!),
                  ),
                  Row(children: [
                    if (backBtn != null) ...[backBtn, const SizedBox(width: AppSpace.xxs)],
                    Expanded(child: titleBlock),
                    if (phoneRefresh != null) ...[AppSpace.gapXs, phoneRefresh],
                  ]),
                  // phones: ONE calm full-width search bar under the title (the icon row keeps its room for the pill)
                  if (phoneSearch != null)
                    _Fold(shut: shut, child: Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: phoneSearch)),
                  if (actionFitted != null)
                    _Fold(
                      shut: shut,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpace.sm),
                        child: Align(alignment: AlignmentDirectional.centerStart, child: actionFitted),
                      ),
                    ),
                ]),
              );
            },
          );
          // the floating bar (D-648, was the editorial masthead of D-614)
          return RepaintBoundary(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: Material(
                color: onFrame ? Colors.transparent : context.colors.background,
                // the floating bar (D-648): one white card inset by the gutter, Back inside it, no strip or rule
                child: ChromeCard(margin: appBarCardMargin(box.maxWidth), child: content),
              ),
            ),
          );
        },
      );
    });
  }

  static T? _maybe<T>(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<T>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  static int _unread(BuildContext context) {
    try {
      return context.select<NotificationsProvider, int>((p) => p.unreadCount);
    } on ProviderNotFoundException {
      return 0;
    }
  }
}

/// [child] at full height while [shut] is 0, folded away at 1 (no height, no taps, no focus, no screen-reader node).
class _Fold extends StatelessWidget {
  const _Fold({required this.shut, required this.child});

  final double shut;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = (1 - shut).clamp(0.0, 1.0);
    return Offstage(
      offstage: open == 0,
      child: ExcludeFocus(
        excluding: open == 0,
        child: ClipRect(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            heightFactor: open,
            child: Opacity(opacity: open, child: child),
          ),
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, this.subtitle, this.updated, this.below, this.shut = 0, this.oneLine = false});

  /// The one-row header: a long title ends with an ellipsis rather than change the header's height.
  final bool oneLine;

  final String title;
  final String? subtitle;

  /// Narrow layouts carry "Updated …" under the title.
  final OrgPageRefresh? updated;

  /// A narrow row's primary action, under the title.
  final Widget? below;

  /// The header's collapse: 0 open … 1 compact.
  final double shut;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    final hasSub = sub != null && sub.isNotEmpty;
    final open = AppType.pageTitle(context);
    final compact = AppType.section(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text(title, maxLines: oneLine || shut >= 0.4 ? 1 : 2, overflow: TextOverflow.ellipsis, style: TextStyle.lerp(open, compact, shut)),
      ),
      if (hasSub || updated != null)
        // gone by the middle of the collapse, so this line never crowds the shrinking title
        _Fold(
          shut: shut * 2,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (hasSub)
                Flexible(
                  child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ),
              if (hasSub && updated != null)
                // a narrow title column (a long primary beside it) can leave less room than the dot itself
                Flexible(child: Text('  ·  ', maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: AppType.meta(context))),
              if (updated != null) Flexible(child: _UpdatedText(refresh: updated!)),
            ]),
          ),
        ),
      if (below != null)
        _Fold(shut: shut, child: Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: below!)),
    ]);
  }
}

/// "Updated 2 min ago", re-drawn once a minute (only this text, never the page).
class _UpdatedText extends StatelessWidget {
  const _UpdatedText({required this.refresh});

  final OrgPageRefresh refresh;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: OrgClock.minute,
        builder: (context, _) => Text(
          orgUpdatedText(refresh.updatedAt, OrgClock.now()),
          key: const ValueKey('org.header.updated'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context),
        ),
      );
}

/// The end of the row: the focus toggle, or the labelled way out while focus mode hides the sidebar.
class _FocusEnd extends StatelessWidget {
  const _FocusEnd();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AppFocusMode.instance,
        builder: (context, on, _) => Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs),
          child: on && AppFocusMode.activeIn(context) && ShellScope.maybeOf(context) != null
              ? const AppFocusExitButton()
              : const AppFocusToggle(),
        ),
      );
}

String get _refreshLabel => t('تحديث', 'Refresh');
String get _searchLabel => t('بحث', 'Search');

/// Phones: a full-width bar that looks like a search field and opens the command palette (it is a button, not a
/// field: the palette has the real one).
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = t('ابحث في الصفحات والأقسام والأشخاص', 'Search pages, departments, people');
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.divider)),
        child: InkWell(
          key: const ValueKey('org.header.search'),
          borderRadius: AppRadius.cardAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
              child: Row(children: [
                Icon(Icons.search_rounded, size: AppIconSize.md, color: c.textMedium),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(color: c.textMedium, fontWeight: FontWeight.w400)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide: icon + label in the header's quiet chip style (the search button; Ctrl+K / ⌘K opens the same palette).
class _ChipButton extends StatelessWidget {
  const _ChipButton({required this.icon, required this.label, required this.onTap, this.compact = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The icon alone (the label stays in the tooltip and the screen-reader label).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: '$label (Ctrl+K)',
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xxs / 2),
          child: Material(
            color: c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control), side: BorderSide(color: c.divider)),
            child: InkWell(
              key: const ValueKey('org.header.search'),
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xxs, minWidth: AppTouch.min - AppSpace.xxs),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: AppIconSize.md, color: c.textMedium),
                    if (!compact) ...[
                      const SizedBox(width: AppSpace.xs),
                      Text(label, style: AppType.row(context).copyWith(color: c.textMedium)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet header action with its text (e.g. a department's "Edit"): the same bordered chip as Search / Refresh.
/// For a page's ONE filled primary action use OrgPrimaryButton (org_page_kit.dart).
class OrgHeaderButton extends StatelessWidget {
  const OrgHeaderButton({super.key, required this.icon, required this.label, required this.onTap, this.tooltip});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: tooltip ?? label,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip ?? label,
        excludeFromSemantics: true,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
          child: InkWell(
            borderRadius: AppRadius.chipAll,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: AppIconSize.md, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs),
                  Text(label, style: AppType.row(context).copyWith(color: c.textDark)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Refresh: the icon alone (tooltip + screen-reader label), the same square as the calendar and the bell.
class _RefreshIcon extends StatelessWidget {
  const _RefreshIcon({required this.refresh});
  final OrgPageRefresh refresh;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: const ValueKey('org.header.refresh'),
        child: ChromeIconButton(
          icon: Icons.refresh_rounded,
          label: _refreshLabel,
          busy: refresh.busy,
          onTap: refresh.refresh,
        ),
      );
}

/// The open organization; one tap opens the shared switcher (organizations switch in place, Personal leaves).
class _OrgPill extends StatelessWidget {
  const _OrgPill({required this.session});
  final OrgSession session;

  @override
  Widget build(BuildContext context) {
    final org = session.current;
    return ContextPill(
      key: const ValueKey('org.header.switcher'),
      icon: orgTypeIcons[org?['type']] ?? Icons.account_balance_rounded,
      tone: orgColor(context, org),
      label: session.name,
      logoUrl: '${org?['logo_url'] ?? ''}',
      onTap: () => showOrgSwitcher(context),
    );
  }
}
