// lib/features/org/workspace/ws_overview.dart
//
// The teacher workspace's Overview tab (لمحة, D-1150 – D-1151, docs/teacher-org/PLAN.md task F2): my statistics in
// this organization, read from the ONE GET …/my-workspace the shell's WsController already holds (no request of its
// own). Top to bottom:
//   greeting      the greeting, the organization and what I am here (head of …, manages …, member of …)
//   kpis          the key figures (AppStatCard): people in the units I manage (only when I manage one) or my units,
//                 active alerts (red while one is high), open requests (red while one is overdue), votes waiting —
//                 only what my role has
//   alerts        active alerts split by severity, the unread count, "Open alerts" → the Alerts tab
//   units         the units I manage and belong to: role, people (a bar against the largest unit), waiting;
//                 a row opens the Management / Membership tab
//   trends        the last 8 weeks (people in my units · requests) as a bar chart, this week vs the week before
//   session       my next council session (date plate, council, time) and the votes waiting
// Every box but the greeting has a key and a small menu that pins it to the Pinned tab (WsPin('box', key));
// wsOverviewBox draws one box on its own for that tab. One column on phones (alerts first); from a reading column's
// width up the key figures span the page and the boxes sit in two columns (units + session | alerts + trends: the two columns end near the same line).
// Layout test + review renders: test/org/ws_overview_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/design/home_a2.dart' show HomeGreetingRow;
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh;
import '../org_providers.dart' show OrgSession;
import '../org_ui.dart' show deptIcon;
import '../org_v3.dart' show orgErrorText;
import 'ws_models.dart';
import 'ws_shell.dart' show WsController, WsTabs;

// ═════════════════════════════════════════════════════════════════════════════
//  Public names (the shell and the Pinned tab)
// ═════════════════════════════════════════════════════════════════════════════

/// The Overview's pinnable boxes: (key, Arabic label, English label), in the Overview's order.
const List<(String, String, String)> wsOverviewBoxes = [
  ('kpis', 'الأرقام الرئيسية', 'Key figures'),
  ('alerts', 'التنبيهات', 'Alerts'),
  ('units', 'وحداتي', 'My units'),
  ('trends', 'آخر 8 أسابيع', 'Last 8 weeks'),
  ('session', 'الجلسة القادمة', 'Next session'),
];

/// One Overview box on its own (the Pinned tab draws a pinned box with this); empty for an unknown key.
Widget wsOverviewBox(BuildContext context, String key) {
  if (!wsOverviewBoxes.any((b) => b.$1 == key)) return const SizedBox.shrink();
  return _OverviewBox(boxKey: key, key: ValueKey('ws.overview.box.$key'));
}

/// The Overview tab: pull to refresh, a skeleton until the first answer, the error with Retry when it failed.
class WsOverviewTab extends StatefulWidget {
  const WsOverviewTab({super.key});

  @override
  State<WsOverviewTab> createState() => _WsOverviewTabState();
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pure helpers (unit-tested)
// ═════════════════════════════════════════════════════════════════════════════

/// "12.8K" for a big figure, the plain number below ten thousand.
String wsFigure(int n) => n >= 10000 ? appCompactNumber(n) : '$n';

/// The change from the week before to this week as a fraction (+0.25 = 25 % more); null without a base.
double? wsWeekDelta(List<int> weeks) {
  if (weeks.length < 2) return null;
  final prev = weeks[weeks.length - 2], now = weeks.last;
  if (prev <= 0) return null;
  return (now - prev) / prev;
}

/// The weekly series the trends box offers, as (key, values): people only when I manage a unit; a series that is
/// all zeros is left out.
List<(String, List<int>)> wsTrendSeries(WsHome h) => [
      for (final k in const ['people', 'requests'])
        if ((k != 'people' || h.managed.isNotEmpty) && (h.weeks[k] ?? const []).length >= 2 && h.weeks[k]!.any((v) => v > 0))
          (k, h.weeks[k]!),
    ];

/// Which boxes the Overview draws for [h] (the greeting is not a box): a box with nothing for my role stays away —
/// the trends without any activity, the session box without a session or a vote.
List<String> wsOverviewVisible(WsHome h) => [
      'kpis',
      'alerts',
      'units',
      if (wsTrendSeries(h).isNotEmpty) 'trends',
      if (h.stats.nextSession != null || h.stats.votesWaiting > 0) 'session',
    ];

/// What I am in this organization, in one line: "Head of Student affairs · member of 2 units", "Manages 3 units".
String wsRoleLine(WsHome h) {
  final heads = h.managed.where((u) => u.role == WsUnitRole.head).toList();
  final parts = <String>[];
  if (heads.length == 1) {
    parts.add(t('رئيس ${heads.first.name}', 'Head of ${heads.first.name}'));
    final others = h.managed.length - 1;
    if (others > 0) {
      parts.add(countText(others,
          ar1: 'يدير وحدة أخرى', ar2: 'يدير وحدتين أخريين', arFew: 'يدير {n} وحدات أخرى', arMany: 'يدير {n} وحدة أخرى',
          en1: 'manages 1 more unit', en: 'manages {n} more units'));
    }
  } else if (h.managed.isNotEmpty) {
    parts.add(countText(h.managed.length,
        ar1: 'يدير وحدة واحدة', ar2: 'يدير وحدتين', arFew: 'يدير {n} وحدات', arMany: 'يدير {n} وحدة',
        en1: 'Manages 1 unit', en: 'Manages {n} units'));
  }
  if (h.memberOf.isNotEmpty) {
    final first = parts.isEmpty;
    parts.add(countText(h.memberOf.length,
        ar1: 'عضو في وحدة واحدة', ar2: 'عضو في وحدتين', arFew: 'عضو في {n} وحدات', arMany: 'عضو في {n} وحدة',
        en1: first ? 'Member of 1 unit' : 'member of 1 unit', en: first ? 'Member of {n} units' : 'member of {n} units'));
  }
  return parts.join(' · ');
}

// ═════════════════════════════════════════════════════════════════════════════
//  The tab
// ═════════════════════════════════════════════════════════════════════════════

class _WsOverviewTabState extends State<WsOverviewTab> {
  OrgPageRefresh? _refresh;
  WsController? _ws;

  Future<void> _reload() async => _ws?.load(quiet: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ws = context.read<WsController>();
    _refresh ??= OrgPageRefresh.register(context, _reload);
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final h = ws.home;
    String? errorText() => ws.error?.error == null ? null : orgErrorText(ws.error!.error!);
    if (h == null && ws.error != null) {
      return AppRefresh(
        onRefresh: ws.load,
        scrollable: false,
        child: Center(child: AppErrorState(key: const ValueKey('ws.overview.error'), message: errorText(), onRetry: ws.load)),
      );
    }
    const pad = EdgeInsets.symmetric(vertical: AppSpace.md);
    if (h == null) {
      return ListView(
        key: const ValueKey('ws.overview.loading'),
        padding: pad,
        physics: const NeverScrollableScrollPhysics(),
        children: const [AppWidthBox(width: AppWidth.wide, child: _Skeleton())],
      );
    }
    final visible = wsOverviewVisible(h);
    return AppRefresh(
      onRefresh: () => ws.load(quiet: true),
      child: ListView(
        key: const ValueKey('ws.overview'),
        padding: pad,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppWidthBox(
            width: AppWidth.wide,
            child: LayoutBuilder(builder: (context, box) {
              final twoCols = box.maxWidth >= Breakpoints.contentMax;
              Widget b(String k) => _OverviewBox(boxKey: k, key: ValueKey('ws.overview.box.$k'));
              List<Widget> column(List<String> keys) => [
                    for (var i = 0; i < keys.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpace.md),
                      b(keys[i]),
                    ],
                  ];
              List<String> shown(List<String> keys) => [for (final k in keys) if (visible.contains(k)) k];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (ws.error != null) ...[
                  AppErrorState(compact: true, message: errorText(), onRetry: ws.load),
                  const SizedBox(height: AppSpace.md),
                ],
                _Greeting(home: h),
                const SizedBox(height: AppSpace.lg),
                b('kpis'),
                const SizedBox(height: AppSpace.lg),
                if (twoCols)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: column(shown(const ['units', 'session'])))),
                    const SizedBox(width: AppSpace.md),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: column(shown(const ['alerts', 'trends'])))),
                  ])
                else
                  // a phone reads what needs me first: the alerts, then my units, the trends and the session
                  ...column(shown(const ['alerts', 'units', 'trends', 'session'])),
              ]);
            }),
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(alignment: AlignmentDirectional.centerStart, child: AppSkeletonBox(width: AppWidth.phoneMax / 2, height: AppSpace.lg)),
        const SizedBox(height: AppSpace.lg),
        AppKpiGrid(children: [for (var i = 0; i < 4; i++) const AppKpiCard(label: '', value: '', loading: true)]),
        const SizedBox(height: AppSpace.lg),
        const AppListSkeleton(items: 4),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Greeting
// ═════════════════════════════════════════════════════════════════════════════

class _Greeting extends StatelessWidget {
  const _Greeting({required this.home});
  final WsHome home;

  static String _firstName(BuildContext context) {
    try {
      final n = (context.read<MyAuthProvider>().currentUser?.name ?? '').trim();
      return n.isEmpty ? '' : n.split(RegExp(r'\s+')).first;
    } catch (_) {
      return '';
    }
  }

  static String _org(BuildContext context) {
    try {
      final n = context.watch<OrgSession>().name.trim();
      return n == '—' ? '' : n;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final org = _org(context);
    final role = wsRoleLine(home);
    return KeyedSubtree(
      key: const ValueKey('ws.overview.greeting'),
      child: HomeGreetingRow(name: _firstName(context), subline: [if (org.isNotEmpty) org, if (role.isNotEmpty) role].join(' · ')),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Boxes
// ═════════════════════════════════════════════════════════════════════════════

class _OverviewBox extends StatelessWidget {
  const _OverviewBox({super.key, required this.boxKey});
  final String boxKey;

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WsController>();
    final h = ws.home;
    if (h == null) return const AppListSkeleton(items: 2);
    return switch (boxKey) {
      'kpis' => _KpiBox(ws: ws, home: h),
      'alerts' => _AlertsBox(ws: ws),
      'units' => _UnitsBox(ws: ws, home: h),
      'trends' => _TrendsBox(home: h),
      'session' => _SessionBox(stats: h.stats),
      _ => const SizedBox.shrink(),
    };
  }
}

/// A box's menu: pin it to the Pinned tab, or unpin it.
class _PinMenu extends StatelessWidget {
  const _PinMenu({required this.boxKey});
  final String boxKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ws = context.watch<WsController>();
    final spec = wsOverviewBoxes.firstWhere((b) => b.$1 == boxKey);
    final pin = WsPin('box', boxKey, labelAr: spec.$2, labelEn: spec.$3);
    final pinned = ws.prefs.prefs.pinned(pin);
    return PopupMenuButton<int>(
      key: ValueKey('ws.overview.menu.$boxKey'),
      tooltip: t('خيارات ${spec.$2}', '${spec.$3} options'),
      constraints: const BoxConstraints(minWidth: AppTouch.min * 4),
      icon: Icon(Icons.more_horiz_rounded, size: AppIconSize.md, color: c.textMedium),
      onSelected: (_) {
        ws.prefs.update((p) => p.togglePin(pin));
        showAppNotice(pinned ? t('أُزيلت من المثبّتة', 'Removed from Pinned') : t('ثُبّتت في المثبّتة', 'Pinned'));
      },
      itemBuilder: (_) => [
        PopupMenuItem<int>(
          value: 0,
          child: Row(children: [
            Icon(pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined, size: AppIconSize.md, color: c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(pinned ? t('إلغاء التثبيت', 'Unpin') : t('تثبيت في لوحتي', 'Pin to dashboard'),
                  style: AppType.body(context).copyWith(color: c.textDark)),
            ),
          ]),
        ),
      ],
    );
  }
}

/// A box's paper card: the title, an optional line under it, the pin menu at the end.
class _Card extends StatelessWidget {
  const _Card({required this.boxKey, required this.title, required this.child, this.subtitle});
  final String boxKey, title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AppSectionCard(title: title, subtitle: subtitle, actions: [_PinMenu(boxKey: boxKey)], child: child);
}

/// A calm line inside a box: a tinted mark, one title, one line, an optional action.
class _CalmLine extends StatelessWidget {
  const _CalmLine({required this.icon, required this.title, required this.line, this.action});
  final IconData icon;
  final String title, line;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appToneStrong(context, AppBlockTone.emerald);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: AppTouch.min - AppSpace.xs,
          height: AppTouch.min - AppSpace.xs,
          decoration: BoxDecoration(color: appTintOn(context, ink), borderRadius: AppRadius.cardAll),
          child: Icon(icon, size: AppIconSize.md, color: ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
            Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
      ]),
      if (action != null) ...[
        const SizedBox(height: AppSpace.sm),
        Align(alignment: AlignmentDirectional.centerEnd, child: action),
      ],
    ]);
  }
}

// ── key figures ─────────────────────────────────────────────────────────────

class _KpiBox extends StatelessWidget {
  const _KpiBox({required this.ws, required this.home});
  final WsController ws;
  final WsHome home;

  @override
  Widget build(BuildContext context) {
    final s = home.stats;
    final a = ws.alertCounts;
    final manages = home.managed.isNotEmpty;
    final cards = <Widget>[
      if (manages)
        AppStatCard(
          key: const ValueKey('ws.kpi.people'),
          icon: Icons.groups_rounded,
          value: wsFigure(s.peopleManaged),
          label: t('أشخاص في وحداتك', 'People in your units'),
          tone: AppBlockTone.emerald,
          footer: s.peopleManaged <= 0
              ? t('لا أحد بعد', 'No one yet')
              : '${t('الفريق', 'Team')} ${wsFigure(s.teamManaged)} · ${countText(s.membersTotal, ar1: 'عضو واحد', ar2: 'عضوان', arFew: '{n} أعضاء', arMany: '{n} عضوًا', en1: '1 member', en: '{n} members')}',
          onTap: () => ws.go(WsTabs.management),
        )
      else
        AppStatCard(
          key: const ValueKey('ws.kpi.units'),
          icon: Icons.apartment_rounded,
          value: wsFigure(home.memberOf.length),
          label: t('وحداتك', 'Your units'),
          tone: AppBlockTone.emerald,
          footer: home.memberOf.isEmpty ? t('لم تنضم إلى وحدة بعد', 'Not in a unit yet') : t('أنت عضو فيها', 'You are a member'),
          onTap: home.memberOf.isEmpty ? null : () => ws.go(WsTabs.membership),
        ),
      AppStatCard(
        key: const ValueKey('ws.kpi.alerts'),
        icon: Icons.notifications_active_rounded,
        value: wsFigure(a.active),
        label: t('تنبيهات نشطة', 'Active alerts'),
        tone: AppBlockTone.peach,
        warn: a.high > 0,
        footer: a.high > 0
            ? countText(a.high,
                ar1: 'تنبيه عاجل', ar2: 'تنبيهان عاجلان', arFew: '{n} تنبيهات عاجلة', arMany: '{n} تنبيهًا عاجلًا', en1: '1 high priority', en: '{n} high priority')
            : (a.active > 0 ? t('لا شيء عاجل', 'Nothing urgent') : t('كل شيء هادئ', 'All calm')),
        onTap: () => ws.go(WsTabs.alerts),
      ),
      if (manages || s.requestsOpen > 0)
        AppStatCard(
          key: const ValueKey('ws.kpi.requests'),
          icon: Icons.assignment_rounded,
          value: wsFigure(s.requestsOpen),
          label: t('طلبات مفتوحة', 'Open requests'),
          tone: AppBlockTone.gold,
          warn: s.requestsOverdue > 0,
          footer: s.requestsOverdue > 0
              ? countText(s.requestsOverdue,
                  ar1: 'طلب متأخر', ar2: 'طلبان متأخران', arFew: '{n} طلبات متأخرة', arMany: '{n} طلبًا متأخرًا', en1: '1 overdue', en: '{n} overdue')
              : (s.requestsOpen > 0 ? t('كلها في موعدها', 'All on time') : t('لا طلبات', 'No requests')),
        ),
      if (s.votesWaiting > 0 || s.nextSession != null)
        AppStatCard(
          key: const ValueKey('ws.kpi.votes'),
          icon: Icons.how_to_vote_rounded,
          value: wsFigure(s.votesWaiting),
          label: t('تصويتات بانتظارك', 'Votes waiting'),
          tone: AppBlockTone.sky,
          footer: s.votesWaiting > 0 ? t('صوتك مطلوب', 'Your vote is needed') : t('لا تصويتات الآن', 'No votes right now'),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(t('الأرقام الرئيسية', 'Key figures'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          ),
        ),
        const _PinMenu(boxKey: 'kpis'),
      ]),
      const SizedBox(height: AppSpace.xs),
      // as many columns as cards (up to four): two figures share the row instead of leaving half of it empty
      AppKpiGrid(maxColumns: cards.length.clamp(2, 4), children: cards),
    ]);
  }
}

// ── alerts ──────────────────────────────────────────────────────────────────

class _AlertsBox extends StatelessWidget {
  const _AlertsBox({required this.ws});
  final WsController ws;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = ws.alertCounts;
    final high = a.high.clamp(0, a.active), other = a.active - high;
    final open = AppButton.ghost(
      key: const ValueKey('ws.overview.alerts.open'),
      label: t('فتح التنبيهات', 'Open alerts'),
      icon: Icons.arrow_forward_rounded,
      size: AppButtonSize.sm,
      onPressed: () => ws.go(WsTabs.alerts),
    );
    if (a.active <= 0) {
      return _Card(
        boxKey: 'alerts',
        title: t('التنبيهات', 'Alerts'),
        child: _CalmLine(
          icon: Icons.verified_rounded,
          title: t('لا تنبيهات نشطة', 'No active alerts'),
          line: t('سيظهر هنا ما يحتاج انتباهك', 'What needs you will show up here'),
          action: open,
        ),
      );
    }
    final danger = c.danger, calm = appToneStrong(context, AppBlockTone.gold);
    Widget figure(String label, int n, Color dot) => Expanded(
          child: Semantics(
            label: '$label: $n',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Container(width: AppSpace.xs, height: AppSpace.xs, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textMedium)),
                ),
              ]),
              const SizedBox(height: AppSpace.xxs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(wsFigure(n), style: AppType.figure(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
          ),
        );
    return _Card(
      boxKey: 'alerts',
      title: t('التنبيهات', 'Alerts'),
      subtitle: a.unread > 0
          ? countText(a.unread,
              ar1: 'تنبيه واحد غير مقروء', ar2: 'تنبيهان غير مقروءين', arFew: '{n} تنبيهات غير مقروءة', arMany: '{n} تنبيهًا غير مقروء',
              en1: '1 unread', en: '{n} unread')
          : t('قرأتها كلها', 'All read'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          figure(t('عاجلة', 'High'), high, danger),
          const SizedBox(width: AppSpace.md),
          figure(t('أخرى', 'Other'), other, calm),
          const SizedBox(width: AppSpace.md),
          figure(t('الكل', 'All'), a.active, c.textLight),
        ]),
        const SizedBox(height: AppSpace.md),
        // the split in one bar (decorative: the figures above say it)
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              height: AppSpace.xs,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (n, col) in [(high, danger), (other, calm)])
                  if (n > 0) Expanded(flex: (n * 1000 ~/ a.active).clamp(40, 1000), child: ColoredBox(color: col)),
              ]),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Align(alignment: AlignmentDirectional.centerEnd, child: open),
      ]),
    );
  }
}

// ── my units ────────────────────────────────────────────────────────────────

class _UnitsBox extends StatelessWidget {
  const _UnitsBox({required this.ws, required this.home});
  final WsController ws;
  final WsHome home;

  /// Rows drawn per group; the rest is one tap away in its tab.
  static const _perGroup = 5;

  @override
  Widget build(BuildContext context) {
    final all = home.all;
    final both = home.managed.isNotEmpty && home.memberOf.isNotEmpty;
    final summary = [
      if (home.managed.isNotEmpty) t('تدير ${home.managed.length}', 'Managing ${home.managed.length}'),
      if (home.memberOf.isNotEmpty) t('عضو في ${home.memberOf.length}', 'Member of ${home.memberOf.length}'),
    ].join(' · ');
    if (all.isEmpty) {
      return _Card(
        boxKey: 'units',
        title: t('وحداتي', 'My units'),
        child: _CalmLine(
          icon: Icons.apartment_rounded,
          title: t('لست في أي وحدة بعد', 'You are not in any unit yet'),
          line: t('تظهر هنا الأقسام التي تديرها أو تنتمي إليها', 'The departments you run or belong to show up here'),
        ),
      );
    }
    final most = all.fold<int>(0, (m, u) => u.people > m ? u.people : m);
    List<Widget> group(String label, List<WsUnit> units, String tab) => [
          if (both)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpace.xs, bottom: AppSpace.xxs),
              child: Semantics(
                header: true,
                child: Text(label, style: AppType.overline(context).copyWith(color: context.colors.textLight)),
              ),
            ),
          for (final u in units.take(_perGroup)) _UnitRow(unit: u, most: most, onTap: () => ws.go(tab)),
          if (units.length > _perGroup)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                label: t('و${units.length - _perGroup} أخرى', '${units.length - _perGroup} more'),
                size: AppButtonSize.sm,
                onPressed: () => ws.go(tab),
              ),
            ),
        ];
    return _Card(
      boxKey: 'units',
      title: t('وحداتي', 'My units'),
      subtitle: summary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (home.managed.isNotEmpty) ...group(t('أديرها', 'I manage'), home.managed, WsTabs.management),
        if (both) const SizedBox(height: AppSpace.sm),
        if (home.memberOf.isNotEmpty) ...group(t('عضو فيها', 'I belong to'), home.memberOf, WsTabs.membership),
      ]),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit, required this.most, required this.onTap});
  final WsUnit unit;
  final int most;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = unit;
    final tint = hexColor(u.color, c.primary);
    final (roleLabel, roleTone) = switch (u.role) {
      WsUnitRole.head => (t('رئيس', 'Head'), AppTone.brand),
      WsUnitRole.manager => (t('مدير', 'Manager'), AppTone.info),
      WsUnitRole.member => (t('عضو', 'Member'), AppTone.neutral),
    };
    final people = countText(u.people,
        ar1: 'شخص واحد', ar2: 'شخصان', arFew: '{n} أشخاص', arMany: '{n} شخصًا', en1: '1 person', en: '{n} people');
    final meta = [
      people,
      if (u.manages && u.team > 0) t('الفريق ${wsFigure(u.team)}', 'team ${wsFigure(u.team)}'),
    ].join(' · ');
    final share = most <= 0 ? 0.0 : u.people / most;
    return Semantics(
      button: true,
      label: [u.name, roleLabel, people, if (u.waiting > 0) t('${u.waiting} بانتظارك', '${u.waiting} waiting')].join(', '),
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('ws.overview.unit.${u.id}'),
        onTap: onTap,
        borderRadius: AppRadius.cardAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              Container(
                width: AppTouch.min - AppSpace.xs,
                height: AppTouch.min - AppSpace.xs,
                decoration: BoxDecoration(color: appTintOn(context, tint), borderRadius: AppRadius.cardAll),
                child: Icon(deptIcon(u.icon), size: AppIconSize.md, color: AppBlockColors.of(context, AppBlockTone.paper).accentInk(tint)),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  LayoutBuilder(builder: (context, box) {
                    // the badges sit at the row's end and give way to the name on a narrow row (their labels
                    // ellipsize): each takes at most 30 % of the row
                    Widget badge(String label, AppTone tone) => ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.3),
                          child: AppStatusBadge(label: label, tone: tone, dense: true),
                        );
                    return Row(children: [
                      Expanded(child: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                      const SizedBox(width: AppSpace.xs),
                      if (u.waiting > 0) ...[
                        badge(t('${wsFigure(u.waiting)} بانتظارك', '${wsFigure(u.waiting)} waiting'), AppTone.warning),
                        const SizedBox(width: AppSpace.xxs),
                      ],
                      badge(roleLabel, roleTone),
                    ]);
                  }),
                  const SizedBox(height: AppSpace.xxs),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    // people against the largest unit: the "people per unit" chart, one bar per row
                    Expanded(
                      flex: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: SizedBox(
                          height: AppSpace.xxs + AppBorder.hairline,
                          child: Stack(children: [
                            Positioned.fill(child: ColoredBox(color: c.divider)),
                            // positioned: an unpositioned child gets loose constraints and the fill collapses to 0 high
                            Positioned.fill(
                              child: FractionallySizedBox(
                                alignment: AlignmentDirectional.centerStart,
                                widthFactor: share.clamp(0.0, 1.0),
                                heightFactor: 1,
                                child: ColoredBox(color: appToneStrong(context, AppBlockTone.emerald)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ── trends ──────────────────────────────────────────────────────────────────

class _TrendsBox extends StatefulWidget {
  const _TrendsBox({required this.home});
  final WsHome home;

  @override
  State<_TrendsBox> createState() => _TrendsBoxState();
}

class _TrendsBoxState extends State<_TrendsBox> {
  int _i = 0;

  static String _name(String k) => switch (k) {
        'people' => t('الأشخاص', 'People'),
        'requests' => t('الطلبات', 'Requests'),
        _ => k,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final series = wsTrendSeries(widget.home);
    if (series.isEmpty) {
      return _Card(
        boxKey: 'trends',
        title: t('آخر 8 أسابيع', 'Last 8 weeks'),
        child: _CalmLine(
          icon: Icons.insights_rounded,
          title: t('لا نشاط بعد', 'No activity yet'),
          line: t('تظهر الاتجاهات بعد أسبوع من النشاط', 'Trends show up after a week of activity'),
        ),
      );
    }
    final i = _i.clamp(0, series.length - 1);
    final (key, values) = series[i];
    final now = DateTime.now().toUtc();
    final labels = [
      for (var w = 0; w < values.length; w++) AppTime.date(now.subtract(Duration(days: 7 * (values.length - 1 - w))), pattern: 'd/M'),
    ];
    final delta = wsWeekDelta(values);
    final upGood = key != 'requests';
    final deltaColor = delta == null || delta == 0 ? c.textLight : ((delta > 0) == upGood ? c.success : c.danger);
    final week = t('هذا الأسبوع', 'this week');
    return _Card(
      boxKey: 'trends',
      title: t('آخر 8 أسابيع', 'Last 8 weeks'),
      subtitle: series.length == 1 ? _name(key) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (series.length > 1) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppTabs(
              key: const ValueKey('ws.overview.trends.tabs'),
              items: [for (final s in series) AppTabItem(_name(s.$1))],
              index: i,
              hug: true,
              onChanged: (v) => setState(() => _i = v),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Semantics(
          label: [_name(key), week, wsFigure(values.last), if (delta != null) appDeltaText(delta)].join(', '),
          excludeSemantics: true,
          child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(wsFigure(values.last), style: AppType.figureLarge(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            Text(week, style: AppType.meta(context).copyWith(color: c.textLight)),
            if (delta != null)
              AppStatusBadge(
                label: '${appDeltaText(delta)} ${t('عن الأسبوع الماضي', 'vs last week')}',
                tone: delta == 0 ? AppTone.neutral : (deltaColor == c.success ? AppTone.success : AppTone.danger),
                dense: true,
              ),
          ]),
        ),
        const SizedBox(height: AppSpace.md),
        AppBarChart(
          key: ValueKey('ws.overview.trends.$key'),
          title: _name(key),
          labels: labels,
          integerAxis: true,
          height: AppSpace.xxxl * 2 + AppSpace.lg,
          series: [
            AppChartSeries(_name(key), [for (final v in values) v.toDouble()],
                color: appToneStrong(context, key == 'requests' ? AppBlockTone.gold : AppBlockTone.emerald)),
          ],
        ),
      ]),
    );
  }
}

// ── next session ────────────────────────────────────────────────────────────

class _SessionBox extends StatelessWidget {
  const _SessionBox({required this.stats});
  final WsStats stats;

  static DateTime? _at(Object? v) {
    final s = '${v ?? ''}';
    if (s.isEmpty) return null;
    // the server stores naive UTC
    return DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
  }

  static String _pick(Map<String, dynamic> n, String base) {
    final ar = '${n['${base}_ar'] ?? ''}'.trim(), en = '${n['${base}_en'] ?? ''}'.trim();
    return AppConfig.lang == 'ar' ? (ar.isNotEmpty ? ar : en) : (en.isNotEmpty ? en : ar);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = stats.nextSession;
    final votes = stats.votesWaiting > 0
        ? countText(stats.votesWaiting,
            ar1: 'تصويت واحد بانتظارك', ar2: 'تصويتان بانتظارك', arFew: '{n} تصويتات بانتظارك', arMany: '{n} تصويتًا بانتظارك',
            en1: '1 vote waits for you', en: '{n} votes wait for you')
        : null;
    final at = n == null ? null : _at(n['at'] ?? n['starts_at']);
    if (n == null || at == null) {
      return _Card(
        boxKey: 'session',
        title: t('الجلسة القادمة', 'Next session'),
        child: _CalmLine(
          icon: Icons.event_available_rounded,
          title: t('لا جلسات مجدولة', 'No sessions scheduled'),
          line: votes ?? t('ستظهر جلستك القادمة هنا', 'Your next session will show up here'),
        ),
      );
    }
    final council = _pick(n, 'council');
    final title = '${n['title'] ?? ''}'.trim();
    final block = AppBlockColors.of(context, AppBlockTone.peach);
    return _Card(
      boxKey: 'session',
      title: t('الجلسة القادمة', 'Next session'),
      child: Semantics(
        label: [AppTime.date(at, pattern: 'EEEE d MMMM'), AppTime.time(at), if (title.isNotEmpty) title, if (council.isNotEmpty) council, ?votes].join(', '),
        excludeSemantics: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the date plate: the day large, the month under it
          Container(
            width: AppTouch.primary + AppSpace.xs,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            decoration: BoxDecoration(color: block.surface, borderRadius: AppRadius.cardAll),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(AppTime.date(at, pattern: 'd'), style: AppType.figureLarge(context).copyWith(color: block.ink)),
              Text(AppTime.date(at, pattern: 'MMM'),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.overline(context).copyWith(color: block.muted)),
            ]),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title.isEmpty ? t('جلسة مجلس', 'Council session') : title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              if (council.isNotEmpty)
                Text(council, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Row(children: [
                Icon(Icons.schedule_rounded, size: AppIconSize.sm, color: c.textLight),
                const SizedBox(width: AppSpace.xxs),
                Flexible(
                  child: Text('${AppTime.date(at, pattern: 'EEEE')} · ${AppTime.time(at)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                ),
              ]),
              if (votes != null) ...[
                const SizedBox(height: AppSpace.xs),
                AppStatusBadge(label: votes, tone: AppTone.info, icon: Icons.how_to_vote_rounded, dense: true),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
