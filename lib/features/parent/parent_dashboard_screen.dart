// lib/features/parent/parent_dashboard_screen.dart
//
// The Parent shell — same structure as the admin / teacher dashboards (DashboardItem tabs rendered by
// AppShell, lib/design/app_shell.dart), Track B.5:
//   Today (GET /parent/overview, ONE call) · Children · Reports · Alerts · Link · More (AppSettingsPage groups)
// Only the Today tab loads on the first paint; every other tab is built — and fetches — when it is first opened
// (_LazyTab), and the Children / Link tabs start from the overview's config / requests / children
// (ParentLinkProvider.seed) and refetch only on pull. An older server without /parent/overview hides the Today
// tab (ParentOverviewProvider.unsupported). Badges: the attention feed, drawn at the leaf.
//
// Register the route in main.dart (and send role == 'parent' here after login):
//   case '/parent_dashboard': → const ParentDashboardScreen()
library;

import 'package:flutter_education_app/design/app_shell_nav.dart' show ShellChrome;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
import 'package:flutter_education_app/design/app_responsive.dart' show AppWidthBox;
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/calendar_entry.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'pa_child_pages.dart';
import 'pa_kit.dart';
import 'pa_more_page.dart';
import 'pay/pa_book_page.dart';
import 'pay/pa_payments_page.dart';
import 'signup/pa_add_child_page.dart';
import 'signup/pa_child_api.dart';
import 'signup/pa_child_code_page.dart';
import 'parent_alerts_page.dart';
import 'parent_children_page.dart';
import 'parent_link_providers.dart';
import 'parent_link_screen.dart';
import 'parent_overview.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredParentOrgChildrenCard;
import 'parent_overview_page.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/quick_meeting_entry.dart';
import 'package:flutter_education_app/design/master_detail/entity_search_palette.dart';

class ParentTabProvider extends ChangeNotifier {
  int currentTab = 0;

  void onChangeTab(int i) {
    if (i == currentTab) return;
    currentTab = i;
    notifyListeners();
  }
}

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _tabs = ParentTabProvider();
  final _link = ParentLinkProvider();
  final _alerts = ParentAlertsProvider();
  final _overview = ParentOverviewProvider();
  final _kids = PaKids();
  final _epochs = {for (final k in _allKeys) k: ValueNotifier<int>(0)};
  late final Map<String, DashboardItem> _byKey;
  ParentOverviewData? _seededFrom;

  static const _allKeys = ['today', 'children', 'reports', 'alerts', 'link', 'more'];

  bool get _isParent => (context.read<MyAuthProvider>().currentUser?.role ?? '') == 'parent';

  /// The tabs in order; the Today tab only while the server has /parent/overview.
  List<String> get _keys => [for (final k in _allKeys) if (k != 'today' || !_overview.unsupported) k];

  int _index(String key) => _keys.indexOf(key);

  /// Opens a tab by key; the Alerts tab optionally filtered on one child (null clears the filter).
  void _go(String key, {int? childId}) {
    if (key == 'alerts' && childId != _alerts.childId) _alerts.setChild(childId);
    if (key == 'alerts') _kids.select(childId);
    final i = _index(key);
    if (i >= 0) _tabs.onChangeTab(i);
  }

  Future<void> _refresh(String key) async {
    switch (key) {
      case 'today':
        await _overview.load(silent: true);
      case 'children':
      case 'link':
        _epochs[key]!.value++;
        await _link.loadAll();
      case 'alerts':
        await _alerts.load(silent: true);
      default:
        _epochs[key]!.value++;
    }
  }

  /// Deep links (attention items): 'parent_alerts' → Alerts tab, 'parent_link' → Link tab.
  void _onTabRequested() {
    final key = switch (AppNavigator.requestedTab.value) {
      'parent_alerts' => 'alerts',
      'parent_link' => 'link',
      _ => null,
    };
    if (key == null) return;
    AppNavigator.requestedTab.value = null;
    _go(key);
  }

  /// The overview arrived: the Children / Link tabs start from its config / requests / children, and the top bar's
  /// child switcher from its children (no request of its own).
  void _onOverview() {
    final d = _overview.data;
    if (d == null || identical(d, _seededFrom)) return;
    _seededFrom = d;
    _link.seed(config: d.linkConfig, requests: d.requests, children: [for (final c in d.children) c.child]);
    _kids.setKids([
      for (final c in d.children)
        PaKid(id: c.id, name: c.name, status: c.pulse?.status.wire, grade: '${c.child['grade_name'] ?? ''}'),
    ]);
  }

  /// An older server without the overview: the switcher follows the Children tab's list.
  void _onLink() {
    if (!_overview.unsupported) return;
    _kids.setKids([
      for (final c in _link.children)
        if (c['id'] is num) PaKid(id: (c['id'] as num).toInt(), name: '${c['name'] ?? ''}', grade: '${c['grade_name'] ?? ''}'),
    ]);
  }

  /// "Add your child": the form, then the children reload (the top bar's "+", the Children tab, the empty Today).
  VoidCallback? get _addChild => paCreateChildOn()
      ? () async {
          if (!await paOpenAddChild(context)) return;
          await Future.wait([_overview.load(silent: true), _link.loadAll()]);
        }
      : null;

  /// "Book for your child" (kill switch `booking`), optionally with the child picked.
  VoidCallback? get _book => paBookingOn() ? () => paPush<void>(context, const ParentBookPage()) : null;

  /// "Payments and invoices" (kill switch `payments`).
  VoidCallback? get _payments =>
      AppConfig.disableList.contains('payments') ? null : () => paPush<void>(context, const ParentPaymentsPage());

  Widget _lazy(String key, Widget child) => _LazyTab(indexOf: () => _index(key), child: child);

  @override
  void initState() {
    super.initState();
    AppNavigator.requestedTab.addListener(_onTabRequested);
    _overview.addListener(_onOverview);
    _link.addListener(_onLink);
    ParentChildPage.codeBlock = PaChildCodeBlock.forRow;
    ParentChildPage.onBook = paBookingOn() ? (ctx, id) => paPush<void>(ctx, ParentBookPage(childId: id)) : null;
    _byKey = {
      'today': DashboardItem(
        Icons.wb_sunny_outlined,
        Icons.wb_sunny_rounded,
        'pl_tab_today',
        () => _refresh('today'),
        _lazy(
          'today',
          // No context switcher here (D-287): parents cannot join an organization (403 role_cannot_join), so the pill
          // would only open a join flow that refuses them. A parent reaches an organization through the child's card.
          _ParentTab(
            titleKey: 'pa_tab_today',
            helpPageId: 'home.parent',
            band: true,
            onAdd: _addChild,
            child: ParentOverviewPage(
              onOpenAlerts: (childId) => _go('alerts', childId: childId),
              onOpenLink: () => _go('link'),
              onOpenChildren: () => _go('children'),
              onAddChild: _addChild,
              // C2: my children's organizations under the day, nothing at all when no child is in one (kill switch
              // parent.org_view, one call: GET /org/parent/children)
              footer: deferredParentOrgChildrenCard(),
            ),
          ),
        ),
        attentionKeys: const [AttentionTabs.home], // badges: GET /me/attention, drawn at the leaf
      ),
      'children': DashboardItem(
        Icons.family_restroom_outlined,
        Icons.family_restroom_rounded,
        'pl_tab_children',
        () => _refresh('children'),
        _lazy(
          'children',
          _ParentTab(
            titleKey: 'pl_tab_children',
            band: true,
            onAdd: _addChild,
            epoch: _epochs['children'],
            child: ParentChildrenPage(onOpenLinkTab: () => _go('link'), onAddChild: _addChild),
          ),
        ),
      ),
      'reports': DashboardItem(
        Icons.insights_outlined,
        Icons.insights_rounded,
        'pl_tab_reports',
        () => _refresh('reports'),
        _lazy('reports', _ParentTab(titleKey: 'pl_tab_reports', band: true,
            onAdd: _addChild, epoch: _epochs['reports'], child: const ParentReportsPage())),
      ),
      'alerts': DashboardItem(
        Icons.notifications_none_rounded,
        Icons.notifications_rounded,
        'pl_tab_alerts',
        () => _refresh('alerts'),
        _lazy('alerts', _ParentTab(titleKey: 'pl_tab_alerts', band: true,
            onAdd: _addChild, epoch: _epochs['alerts'], child: const ParentAlertsPage())),
        attentionKeys: const [AttentionTabs.parentAlerts],
      ),
      'link': DashboardItem(
        Icons.link_outlined,
        Icons.link_rounded,
        'pl_tab_link',
        () => _refresh('link'),
        _lazy('link', _ParentTab(titleKey: 'pl_tab_link', epoch: _epochs['link'], width: AppWidth.reading, child: const ParentLinkPage())),
        attentionKeys: const [AttentionTabs.parentLink],
      ),
      'more': DashboardItem(
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
        'pl_tab_more',
        null,
        _lazy('more', _ParentTab(titleKey: 'pl_tab_more', child: ParentMorePage(onOpenLink: () => _go('link'), onBook: _book, onPayments: _payments))),
        attentionKeys: const [AttentionTabs.profile],
      ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isParent) return;
      _overview.load(); // ONE call for the first paint; the other tabs load when opened
      // a child the join flow kept for after sign-up: created now (nothing at all when there is none)
      paSendPendingChild(context, parentName: context.read<MyAuthProvider>().currentUser?.name.split(' ').first).then((_) {
        if (mounted && _seededFrom != null) _overview.load(silent: true);
      });
      context.read<NotificationsProvider>().fetchNotifications(); // the header's unread count, one request
    });
  }

  @override
  void dispose() {
    AppNavigator.requestedTab.removeListener(_onTabRequested);
    _overview.removeListener(_onOverview);
    _link.removeListener(_onLink);
    _tabs.dispose();
    _kids.dispose();
    _link.dispose();
    _alerts.dispose();
    _overview.dispose();
    for (final e in _epochs.values) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isParent) {
      return BasePage(child: AppEmpty(icon: Icons.lock_rounded, title: 'pl_parents_only'.tr));
    }
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ParentTabProvider>.value(value: _tabs),
        ChangeNotifierProvider<ParentLinkProvider>.value(value: _link),
        ChangeNotifierProvider<ParentAlertsProvider>.value(value: _alerts),
        ChangeNotifierProvider<ParentOverviewProvider>.value(value: _overview),
        ChangeNotifierProvider<PaKids>.value(value: _kids),
      ],
      builder: (context, _) {
        final tabs = context.watch<ParentTabProvider>();
        // the shell only rebuilds when the Today tab appears / disappears (older server), never on a load tick
        context.select<ParentOverviewProvider, bool>((p) => p.unsupported);
        final keys = _keys;
        final items = [for (final k in keys) _byKey[k]!];
        final current = tabs.currentTab.clamp(0, items.length - 1);
        return KeyedSubtree(
          // Back is the shell's alone (AppShell: the tab's pages, then the home tab, then out — D-081). A second
          // PopScope here also jumped to the first tab on the same press: Back from a tab's page skipped its tab (D-170).
          child: Directionality(
            textDirection: plIsAr ? TextDirection.rtl : TextDirection.ltr,
            child: LayoutBuilder(builder: (context, constraints) {
              void onTap(int i) {
                if (mounted) tabs.onChangeTab(i);
              }

              return EntitySearchScope(child: AppShell(width: constraints.maxWidth, currentIndex: current, onTap: onTap, items: items));
            }),
          ),
        );
      },
    );
  }
}

/// A tab that is built (and so starts loading) the first time it is selected, and then kept by the shell's
/// IndexedStack. [indexOf] is read at build time because the Today tab may disappear (older server).
class _LazyTab extends StatefulWidget {
  const _LazyTab({required this.indexOf, required this.child});

  final int Function() indexOf;
  final Widget child;

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

class _LazyTabState extends State<_LazyTab> {
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    final current = context.watch<ParentTabProvider>().currentTab;
    if (current == widget.indexOf()) _built = true;
    return _built ? widget.child : const SizedBox.shrink();
  }
}

class _ParentTab extends StatelessWidget {
  const _ParentTab({required this.titleKey, required this.child, this.epoch, this.width, this.band = false, this.helpPageId, this.onAdd});

  /// The switcher's "+" (add a child); null = none.
  final VoidCallback? onAdd;

  final String titleKey;
  final Widget child;
  final ValueNotifier<int>? epoch;

  /// The child switcher under the top bar (the pages about the children).
  final bool band;
  final String? helpPageId;

  /// The width role of a page of cards or a form; null = the page manages its own width.
  final AppWidth? width;

  @override
  Widget build(BuildContext context) {
    final body = epoch == null
        ? child
        : ValueListenableBuilder<int>(
            valueListenable: epoch!,
            builder: (_, e, _) => KeyedSubtree(key: ValueKey(e), child: child),
          );
    final framed = width == null ? body : AppWidthBox(width: width!, gutters: false, child: body);
    return BasePage(
      // the shell's bar carries the calendar and messages on a tablet / desktop: here only on phones (once per screen);
      // the phone bar shows two (the bell and the messages), the rest fold into its "more" menu
      appBar: ScreenAppBar(
        title: titleKey.tr,
        showBack: false,
        helpPageId: helpPageId,
        actions: ShellChrome.ownsHeaderOf(context)
            ? const [QuickMeetingIcon()]
            : [
                NotificationIcon(unreadCount: context.select<NotificationsProvider, int>((p) => p.unreadCount)),
                const ChatEntryIcon(),
                const CalendarEntryIcon(),
                const QuickMeetingIcon(),
              ],
      ),
      child: band ? Column(children: [PaSwitcherBand(onAdd: onAdd), Expanded(child: framed)]) : framed,
    );
  }
}
