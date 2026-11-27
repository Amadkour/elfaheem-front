// lib/features/messaging/inbox/inbox_page.dart
//
// THE inbox page: the unified inbox and the notifications list merged into ONE page with tabs.
//
//   To do                    the inbox's `todo` segment (forms, availability, terms, approvals, exams, replies …)
//   Notifications            the notifications list (NotificationsTab: Today / Yesterday, Mark all read — unchanged)
//   Announcements & offers   the `news` and `offers` segments, one under the other ("Announcements" in an
//                            organization's own inbox, which has no offers)
//   Done                     the `done` segment (my requests and what was answered)
//
// Badge rule: only ACTIONABLE things count — the To do tab shows its count, the Notifications tab its unread count;
// Announcements & offers and Done show none. The bell and the homes' inbox entry carry the same sum
// (inboxActionableCount: to-dos + unread notifications, core/inbox_badge.dart).
//
// Entry points open the right tab: the bell and '/notifications' → Notifications; a home's inbox entry → To do;
// '/inbox' (arguments: an InboxTab or its name, or `?tab=`) → that tab; a push / notification deep link with
// module `notifications` or `inbox` (AppNavigator) → its tab.
//
// Kill switches: `student_home.inbox` hides the inbox's tabs (and the homes' entry), `notifications` the
// Notifications tab; one tab left → no tab bar; none → the "coming soon" page. The platform admins have no inbox
// (Notifications only), an organization's own inbox ([InboxPage.orgId]) no Notifications tab (the list is not
// per organization). A tab is built on its first visit: the notifications list is asked for only then; the inbox
// (one GET /me/inbox[?org_id=]) is asked for on open, since the To do tab's count is on the bar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart' show NotificationsProvider;
import 'package:flutter_education_app/features/messaging/notification/notifications_screen.dart' show NotificationsTab;
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Tabs (pure, unit-tested)
// ═════════════════════════════════════════════════════════════════════════════

enum InboxTab { todo, notifications, announcements, done }

/// The kill switch of the inbox (its tabs and the homes' entry) — the catalog's "Inbox card (home)".
const kInboxFeatureKey = 'student_home.inbox';

/// The kill switch of the notifications list.
const kNotificationsFeatureKey = 'notifications';

/// Roles without an inbox: their page is the notifications list alone.
const kInboxlessRoles = {'admin', 'super-admin', 'developer'};

/// The tabs, in order, from what is switched on. An organization's own inbox ([orgScoped]) has no Notifications tab.
List<InboxTab> inboxTabsFor({required bool inboxOn, required bool notificationsOn, bool orgScoped = false}) => [
      if (inboxOn) InboxTab.todo,
      if (notificationsOn && !orgScoped) InboxTab.notifications,
      if (inboxOn) ...[InboxTab.announcements, InboxTab.done],
    ];

/// The tabs this person sees: [role] (the platform admins have no inbox), the organization filter and the kill
/// switches in [disabled].
List<InboxTab> inboxPageTabs({String? role, int? orgId, Iterable<String> disabled = const []}) {
  final off = disabled.toSet();
  return inboxTabsFor(
    inboxOn: !kInboxlessRoles.contains(role) && !off.contains(kInboxFeatureKey),
    notificationsOn: !off.contains(kNotificationsFeatureKey),
    orgScoped: orgId != null,
  );
}

/// The tab an inbox segment lives on.
InboxTab inboxTabOfSegment(InboxSegment s) => switch (s) {
      InboxSegment.todo => InboxTab.todo,
      InboxSegment.news || InboxSegment.offers => InboxTab.announcements,
      InboxSegment.done => InboxTab.done,
    };

/// The inbox segments a tab draws, in order (none for Notifications). An organization's inbox has no offers.
List<InboxSegment> inboxTabSegments(InboxTab t, {bool orgScoped = false}) => switch (t) {
      InboxTab.todo => const [InboxSegment.todo],
      InboxTab.announcements => orgScoped ? const [InboxSegment.news] : const [InboxSegment.news, InboxSegment.offers],
      InboxTab.done => const [InboxSegment.done],
      InboxTab.notifications => const [],
    };

/// A tab by name (a route's `?tab=`, a push's `kind`); the segment names map onto their tab. Null when unknown.
InboxTab? inboxTabFromName(String? name) => switch (name?.trim().toLowerCase()) {
      'todo' || 'to_do' => InboxTab.todo,
      'notifications' => InboxTab.notifications,
      'announcements' || 'news' || 'offers' => InboxTab.announcements,
      'done' => InboxTab.done,
      _ => null,
    };

/// The inbox page's routes: '/notifications' (the old notifications page) → Notifications; '/inbox' → the tab its
/// [arguments] name (an [InboxTab] or its name) or its `?tab=` names, else To do. Any other route → null.
InboxTab? inboxRouteTab(String? name, [Object? arguments]) {
  if (name == null || name.isEmpty) return null;
  final uri = Uri.tryParse(name);
  final path = uri?.path ?? name;
  if (path == '/notifications') return InboxTab.notifications;
  if (path != '/inbox') return null;
  if (arguments is InboxTab) return arguments;
  return inboxTabFromName(arguments is String ? arguments : uri?.queryParameters['tab']) ?? InboxTab.todo;
}

/// The tab the page shows: [wanted] when it is there, else the first one.
InboxTab inboxStartTab(InboxTab wanted, List<InboxTab> tabs) => tabs.contains(wanted) || tabs.isEmpty ? wanted : tabs.first;

String inboxTabLabel(InboxTab t, {bool orgScoped = false}) => switch (t) {
      InboxTab.todo => 'inbox_seg_todo'.tr,
      InboxTab.notifications => 'notifications'.tr,
      InboxTab.announcements => orgScoped ? 'inbox_seg_news'.tr : 'inbox_tab_news_offers'.tr,
      InboxTab.done => 'inbox_seg_done'.tr,
    };

IconData inboxTabIcon(InboxTab t) => switch (t) {
      InboxTab.todo => Icons.task_alt_rounded,
      InboxTab.notifications => Icons.notifications_rounded,
      InboxTab.announcements => Icons.campaign_rounded,
      InboxTab.done => Icons.inventory_2_rounded,
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Tab bar (plain values)
// ═════════════════════════════════════════════════════════════════════════════

/// The page's tabs as one segmented card: the selected tab on the brand gradient, a count only where [counts] has
/// one above zero (the actionable tabs), in the danger tone on To do while something is overdue ([urgent]).
/// Spread over the row from [evenFrom] (the long "Announcements & offers" gets the larger share), else it scrolls
/// sideways, fades the edge that hides more and keeps the selected tab in view. 48 px targets.
class InboxTabBar extends StatefulWidget {
  const InboxTabBar({
    super.key,
    required this.tabs,
    required this.current,
    required this.onTap,
    this.counts = const {},
    this.orgScoped = false,
    this.urgent = false,
  });

  final List<InboxTab> tabs;
  final InboxTab current;
  final ValueChanged<InboxTab> onTap;
  final Map<InboxTab, int> counts;
  final bool orgScoped;
  final bool urgent;

  /// From this width the tabs share the row (each label ellipsized if it must).
  static const double evenFrom = 520;

  /// A tab's share of a spread row.
  static int flexOf(InboxTab t) => t == InboxTab.announcements ? 3 : 2;

  @override
  State<InboxTabBar> createState() => _InboxTabBarState();
}

class _InboxTabBarState extends State<InboxTabBar> {
  final Map<InboxTab, GlobalKey> _keys = {};
  final ScrollController _scroll = ScrollController();

  /// A scrolled bar hides tabs before / after the visible part (reading order).
  bool _moreBefore = false, _moreAfter = false;

  GlobalKey _keyOf(InboxTab t) => _keys.putIfAbsent(t, () => GlobalKey(debugLabel: 'inbox_tab_${t.name}'));

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_edges);
    _reveal();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _edges() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return;
    final p = _scroll.position;
    final before = p.pixels > p.minScrollExtent + 1;
    final after = p.pixels < p.maxScrollExtent - 1;
    if (before != _moreBefore || after != _moreAfter) {
      setState(() {
        _moreBefore = before;
        _moreAfter = after;
      });
    }
  }

  @override
  void didUpdateWidget(InboxTabBar old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _reveal();
  }

  /// A scrolled bar keeps the selected tab in view (a page opened on Done, on a phone).
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _edges();
      final ctx = _keys[widget.current]?.currentContext;
      if (ctx == null || Scrollable.maybeOf(ctx) == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: AppMotion.of(context).base, curve: AppMotion.curve);
    });
  }

  /// Fades the edge(s) of a scrolled bar that hide more tabs, so a cut label reads as "scroll for more". Always the
  /// same mask (opaque where nothing hides): swapping the tree would rebuild the scroll view at its start.
  Widget _faded(BuildContext context, Widget child) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // left / right of the reading-order edges
    final fadeLeft = rtl ? _moreAfter : _moreBefore;
    final fadeRight = rtl ? _moreBefore : _moreAfter;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (r) {
        final f = r.width <= 0 ? 0.0 : (AppSpace.lg / r.width).clamp(0.0, 0.5);
        return LinearGradient(
          colors: [
            fadeLeft ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            fadeRight ? Colors.transparent : Colors.black,
          ],
          stops: [0, f, 1 - f, 1],
        ).createShader(r);
      },
      child: child,
    );
  }

  Widget _tab(BuildContext context, InboxTab t, {required bool even}) {
    final c = context.colors;
    final selected = t == widget.current;
    final n = widget.counts[t] ?? 0;
    final fg = selected ? c.onHero : c.textMedium;
    final label = inboxTabLabel(t, orgScoped: widget.orgScoped);
    final tone = t == InboxTab.todo && widget.urgent ? c.danger : c.primary;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: appText(13.5, w: selected ? FontWeight.w600 : FontWeight.w500, c: fg, h: 1.2),
    );
    final count = n <= 0
        ? null
        : Container(
            constraints: const BoxConstraints(minWidth: AppSpace.lg - 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? c.onHero.withValues(alpha: 0.22) : tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              n > 99 ? '99+' : '$n',
              textAlign: TextAlign.center,
              style: appText(12, w: FontWeight.w600, c: selected ? c.onHero : appInk(context, tone))
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          );
    final radius = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      key: _keyOf(t),
      button: true,
      selected: selected,
      label: n > 0 ? '$label, $n' : label,
      onTap: () => widget.onTap(t),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => widget.onTap(t),
          child: AnimatedContainer(
            duration: AppMotion.of(context).base,
            curve: AppMotion.curve,
            constraints: const BoxConstraints(minHeight: AppTouch.min),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
            decoration: BoxDecoration(color: selected ? c.primary : null, borderRadius: radius),
            child: Row(
              mainAxisSize: even ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(inboxTabIcon(t), size: AppIconSize.sm + 2, color: fg),
                const SizedBox(width: 6),
                if (even) Flexible(child: text) else text,
                if (count != null) ...[const SizedBox(width: 6), count],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, 0),
      padding: const EdgeInsets.all(AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.chip + AppSpace.xxs),
        border: Border.all(color: c.divider),
        boxShadow: AppShadow.card(context),
      ),
      child: LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= InboxTabBar.evenFrom) {
          return Row(children: [
            for (final t in widget.tabs) Expanded(flex: InboxTabBar.flexOf(t), child: _tab(context, t, even: true)),
          ]);
        }
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            _edges();
            return false;
          },
          child: _faded(
            context,
            SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final t in widget.tabs) _tab(context, t, even: false),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  The page
// ═════════════════════════════════════════════════════════════════════════════

/// The inbox page on [initial] (falls back to the first tab shown). [orgId] = one organization's inbox, titled
/// [title]. [controller]: a filled inbox for tests (the page then asks for nothing itself).
class InboxPage extends StatefulWidget {
  const InboxPage({super.key, this.orgId, this.initial = InboxTab.todo, this.title, this.controller});

  final int? orgId;
  final InboxTab initial;
  final String? title;
  final InboxController? controller;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  InboxController? _inbox;
  bool _ownsInbox = false;
  InboxTab? _tab;

  /// The tabs built so far (a tab is built on its first visit, then kept).
  final Set<InboxTab> _built = {};

  bool get _orgScoped => widget.orgId != null;

  String? _role() {
    try {
      return context.read<MyAuthProvider>().currentUser?.role;
    } catch (_) {
      return null; // no provider above (a test)
    }
  }

  InboxController _ensureInbox() {
    final c = _inbox;
    if (c != null) return c;
    if (widget.controller != null) return _inbox = widget.controller!;
    _ownsInbox = true;
    return _inbox = InboxController(orgId: widget.orgId)..load();
  }

  @override
  void dispose() {
    if (_ownsInbox) _inbox?.dispose();
    super.dispose();
  }

  Future<void> _refresh(InboxTab t) async {
    if (t == InboxTab.notifications) {
      try {
        await context.read<NotificationsProvider>().fetchNotifications();
      } catch (_) {}
      return;
    }
    await _ensureInbox().load();
  }

  int _unread(BuildContext context) {
    try {
      return context.select<NotificationsProvider, int>((p) => p.unreadCount);
    } catch (_) {
      return 0;
    }
  }

  Widget _body(InboxTab t) => switch (t) {
        InboxTab.notifications => const NotificationsTab(),
        _ => InboxSegmentList(
            controller: _inbox!,
            segments: inboxTabSegments(t, orgScoped: _orgScoped),
            empty: t == InboxTab.announcements && !_orgScoped
                ? AppEmpty(
                    icon: Icons.campaign_rounded,
                    title: 'inbox_empty_announcements_title'.tr,
                    message: 'inbox_empty_announcements_msg'.tr,
                  )
                : null,
          ),
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppConfig.disableListVersion,
      builder: (context, _, _) {
        final tabs = inboxPageTabs(role: _role(), orgId: widget.orgId, disabled: AppConfig.disableList);
        // both switched off: the "coming soon" page of the notifications key (BasePage)
        if (tabs.isEmpty) {
          return BasePage(
            key: const ValueKey(kNotificationsFeatureKey),
            appBar: ScreenAppBar(title: widget.title ?? 'inbox_title'.tr),
            child: const SizedBox.shrink(),
          );
        }
        final tab = _tab != null && tabs.contains(_tab) ? _tab! : inboxStartTab(widget.initial, tabs);
        _built.add(tab);
        final hasInbox = tabs.any((t) => t != InboxTab.notifications);
        final inbox = hasInbox ? _ensureInbox() : null;
        final unread = _unread(context);
        // a student's inbox (redesign S-C, Stu1Comm?screen=inbox): the chat area, the count in a hero that holds the tabs
        final student = _role() == 'student' && !_orgScoped;
        final page = BasePage(
          useWebCard: !student,
          width: AppWidth.wide,
          appBar: ScreenAppBar(helpPageId: 'inbox', 
            title: widget.title ?? 'inbox_title'.tr,
            actions: [AppRefreshAction(onRefresh: () => _refresh(tab))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (student)
                ListenableBuilder(
                  listenable: inbox ?? Listenable.merge(const []),
                  builder: (context, _) => ScInboxHero(
                    waiting: inbox?.countOf(InboxSegment.todo) ?? 0,
                    late: inbox?.overdue ?? 0,
                    tabs: tabs.length > 1
                        ? AppTabs(
                            expand: true,
                            index: tabs.indexOf(tab),
                            onChanged: (i) => setState(() => _tab = tabs[i]),
                            items: [
                              for (final t in tabs)
                                AppTabItem(inboxTabLabel(t),
                                    count: switch (t) {
                                      InboxTab.todo => inbox?.countOf(InboxSegment.todo),
                                      InboxTab.notifications => unread,
                                      _ => null,
                                    }),
                            ],
                          )
                        : null,
                  ),
                )
              else if (tabs.length > 1)
                ListenableBuilder(
                  listenable: inbox ?? Listenable.merge(const []),
                  builder: (context, _) => InboxTabBar(
                    tabs: tabs,
                    current: tab,
                    orgScoped: _orgScoped,
                    urgent: inbox != null && inbox.overdue > 0,
                    counts: {
                      if (inbox != null) InboxTab.todo: inbox.countOf(InboxSegment.todo),
                      InboxTab.notifications: unread,
                    },
                    onTap: (t) => setState(() => _tab = t),
                  ),
                ),
              Expanded(
                child: IndexedStack(
                  index: tabs.indexOf(tab),
                  sizing: StackFit.expand,
                  children: [
                    for (final t in tabs)
                      KeyedSubtree(
                        key: ValueKey('inbox_tab_${t.name}'),
                        child: _built.contains(t) ? _body(t) : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
        return student ? AppAreaScope(area: AppArea.chat, child: page) : page;
      },
    );
  }
}

/// A student's inbox head (plain values): "4 things wait for you, one is late", the tabs on the hero.
class ScInboxHero extends StatelessWidget {
  const ScInboxHero({super.key, required this.waiting, required this.late, this.tabs});
  final int waiting;
  final int late;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    final title = waiting == 0
        ? 'sc_inbox_all_done'.tr
        : countText(waiting,
                ar1: 'شي واحد ينتظرك',
                ar2: 'شيئين ينتظرونك',
                arFew: '{n} أشياء تنتظرك',
                arMany: '{n} شي ينتظرك',
                en1: '1 thing waits for you',
                en: '{n} things wait for you') +
            (late == 0
                ? ''
                : '${(AppConfig.lang == 'ar' ? '، ' : ', ')}${countText(late, ar1: 'وحدة متأخرة', ar2: 'ثنتين متأخرة', arFew: '{n} متأخرة', en1: 'one is late', en: '{n} are late')}');
    return AppHero(overlap: false, wipe: false, title: appDigits(title), bottom: tabs);
  }
}
