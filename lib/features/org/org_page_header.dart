// lib/features/org/org_page_header.dart
//
// THE page header of every page of the organization dashboard (D-103) — phones included (they have no shell top
// bar), and the shell's own top bar is off (AppShell(showTopBar: false)), so nothing is drawn twice.
//
//   OrgPageHeader({required String title, String? subtitle, Widget? primaryAction})
//       title (+ one-line subtitle) · at most ONE primary action · Search (the command palette, when the shell's
//       AppCommandPaletteScope is on: a chip on wide, a full-width bar under the title on phones) · Refresh with
//       "Updated 2 min ago" · calendar ·
//       notifications with the unread badge · the context switcher pill (all my organizations + Personal; an
//       organization switches in place, Personal leaves). Wide (≥ 760 px): one row. Narrow: row 1 = the pill + the
//       Refresh / calendar / bell buttons, row 2 = the title block with "Updated …", the primary action under it.
//       Refresh state comes from the nearest OrgPageRefreshScope (the shell gives each page its own); without one
//       there is no Refresh button.
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
// Layout test: test/ui/org_page_header_layout_test.dart; renders: test/visual/org_shell_golden_test.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_keyboard.dart' show AppCommandPaletteScope;
import 'package:flutter_education_app/design/app_shell.dart' show NotificationIcon;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/calendar_entry.dart' show CalendarEntryIcon;
import 'package:flutter_education_app/design/chrome_button.dart' show ChromeIconButton;
import 'package:flutter_education_app/design/context_switcher.dart' show ContextPill;
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
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
//  The header
// ═════════════════════════════════════════════════════════════════════════════

class OrgPageHeader extends StatelessWidget {
  const OrgPageHeader({super.key, required this.title, this.subtitle, this.primaryAction, this.searchBar = false});

  final String title;

  /// Phones: draw the full-width "Search pages, departments, people" bar under the title. Only Home asks for it:
  /// the other pages have their own search box, and two look-alike search fields stacked confuse. (Wide screens
  /// always keep the Search chip; Ctrl+K works everywhere.)
  final bool searchBar;

  /// One line under the title (e.g. what the page is for); null = none.
  final String? subtitle;

  /// The page's ONE primary action (e.g. "Add member"), drawn after the title; null = none.
  final Widget? primaryAction;

  /// From this width the header is one row.
  static const double wideFrom = 760;

  @override
  Widget build(BuildContext context) {
    final refresh = OrgPageRefresh.maybeOf(context);
    final session = _maybe<OrgSession>(context);
    final unread = _unread(context);
    // the command palette (D-103): only under the shell's AppCommandPaletteScope, which is off with `org.search`
    final search = AppCommandPaletteScope.openerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= wideFrom;
      // the pages under the header (section chips, lists, settings) all start 16 px in: the header lines up with them
      const gutter = AppSpace.md;
      final pill = session == null || session.currentId == null ? null : _OrgPill(session: session);
      final tools = <Widget>[
        if (refresh != null && !wide) _RefreshIcon(refresh: refresh),
        const CalendarEntryIcon(),
        NotificationIcon(unreadCount: unread),
      ];
      final titleBlock = _TitleBlock(
        title: title,
        subtitle: subtitle,
        updated: refresh != null && !wide ? refresh : null,
      );
      final Widget body;
      if (wide) {
        body = Row(children: [
          Expanded(flex: 3, child: titleBlock),
          if (primaryAction != null) ...[AppSpace.gapSm, primaryAction!],
          if (search != null) ...[AppSpace.gapSm, _ChipButton(icon: Icons.search_rounded, label: _searchLabel, onTap: search)],
          if (refresh != null) ...[
            AppSpace.gapMd,
            Flexible(child: _UpdatedText(refresh: refresh, align: TextAlign.end)),
            AppSpace.gapXs,
            _RefreshButton(refresh: refresh),
          ],
          const SizedBox(width: AppSpace.xxs),
          ...tools,
          if (pill != null) ...[
            AppSpace.gapXs,
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: pill),
          ],
        ]);
      } else {
        body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Align(alignment: AlignmentDirectional.centerStart, child: pill ?? const SizedBox.shrink()),
            ),
            AppSpace.gapXs,
            ...tools,
          ]),
          AppSpace.gapSm,
          titleBlock,
          // phones: ONE calm full-width search bar under the title (the icon row keeps its room for the pill)
          if (search != null && searchBar) ...[AppSpace.gapSm, _SearchBar(onTap: search)],
          if (primaryAction != null) ...[
            AppSpace.gapSm,
            Align(alignment: AlignmentDirectional.centerStart, child: primaryAction!),
          ],
        ]);
      }
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.sm, gutter, AppSpace.sm),
        child: body,
      );
    });
  }

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
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

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.title, this.subtitle, this.updated});

  final String title;
  final String? subtitle;

  /// Narrow layouts carry "Updated …" under the title.
  final OrgPageRefresh? updated;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
      ),
      if (sub != null && sub.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
      ],
      if (updated != null) ...[
        const SizedBox(height: AppSpace.xxs),
        _UpdatedText(refresh: updated!),
      ],
    ]);
  }
}

/// "Updated 2 min ago", re-drawn once a minute (only this text, never the page).
class _UpdatedText extends StatelessWidget {
  const _UpdatedText({required this.refresh, this.align});

  final OrgPageRefresh refresh;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: OrgClock.minute,
        builder: (context, _) => Text(
          orgUpdatedText(refresh.updatedAt, OrgClock.now()),
          key: const ValueKey('org.header.updated'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: AppType.meta(context),
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
                Icon(Icons.search_rounded, size: 20, color: c.textMedium),
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
  const _ChipButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.all(2),
          child: Material(
            color: c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
            child: InkWell(
              key: const ValueKey('org.header.search'),
              borderRadius: AppRadius.chipAll,
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 20, color: c.textMedium),
                    const SizedBox(width: AppSpace.xs),
                    Text(label, style: AppType.row(context).copyWith(color: c.textDark)),
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

/// Phones: the icon only (tooltip + screen-reader label), the same 48 px square as the calendar and the bell.
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

/// Wide: icon + "Refresh".
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.refresh});
  final OrgPageRefresh refresh;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = refresh.busy;
    return Semantics(
      button: true,
      label: _refreshLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll, side: BorderSide(color: c.divider)),
          child: InkWell(
            key: const ValueKey('org.header.refresh'),
            borderRadius: AppRadius.chipAll,
            onTap: busy ? null : refresh.refresh,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox.square(
                    dimension: 20,
                    child: busy
                        ? Padding(
                            padding: const EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.textMedium),
                          )
                        : Icon(Icons.refresh_rounded, size: 20, color: c.textMedium),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Text(_refreshLabel, style: AppType.row(context).copyWith(color: c.textDark)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
      onTap: () => showOrgSwitcher(context),
    );
  }
}
