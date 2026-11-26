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
import 'package:flutter_education_app/features/profile/legal/legal_links.dart' show legalSettingsGroup;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionTabs;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_shell.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/design/app_settings.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../design/app_switch.dart';
import '../../design/calendar_entry.dart';
import '../../utils/helpers.dart';
import '../auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import '../../design/app_language_switch.dart' show AppLanguageTile;
import 'package:flutter_education_app/features/profile/change_password_widget.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_page.dart';
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import 'pa_kit.dart';
import 'parent_alerts_page.dart';
import 'parent_children_page.dart';
import 'parent_link_providers.dart';
import 'parent_link_screen.dart';
import 'parent_overview.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredParentOrgChildrenCard;
import 'parent_overview_page.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppTile;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'package:flutter_education_app/design/quick_meeting_entry.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
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

  Widget _lazy(String key, Widget child) => _LazyTab(indexOf: () => _index(key), child: child);

  @override
  void initState() {
    super.initState();
    AppNavigator.requestedTab.addListener(_onTabRequested);
    _overview.addListener(_onOverview);
    _link.addListener(_onLink);
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
            child: ParentOverviewPage(
              onOpenAlerts: (childId) => _go('alerts', childId: childId),
              onOpenLink: () => _go('link'),
              onOpenChildren: () => _go('children'),
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
            epoch: _epochs['children'],
            child: ParentChildrenPage(onOpenLinkTab: () => _go('link')),
          ),
        ),
      ),
      'reports': DashboardItem(
        Icons.insights_outlined,
        Icons.insights_rounded,
        'pl_tab_reports',
        () => _refresh('reports'),
        _lazy('reports', _ParentTab(titleKey: 'pl_tab_reports', epoch: _epochs['reports'], child: const ParentReportsPage())),
      ),
      'alerts': DashboardItem(
        Icons.notifications_none_rounded,
        Icons.notifications_rounded,
        'pl_tab_alerts',
        () => _refresh('alerts'),
        _lazy('alerts', _ParentTab(titleKey: 'pl_tab_alerts', epoch: _epochs['alerts'], width: AppWidth.content, child: const ParentAlertsPage())),
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
        _lazy('more', const _ParentTab(titleKey: 'pl_tab_more', child: _ParentMorePage())),
        attentionKeys: const [AttentionTabs.profile],
      ),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isParent) return;
      _overview.load(); // ONE call for the first paint; the other tabs load when opened
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
  const _ParentTab({required this.titleKey, required this.child, this.epoch, this.width, this.band = false, this.helpPageId});

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
      child: band ? Column(children: [const PaSwitcherBand(), Expanded(child: framed)]) : framed,
    );
  }
}

// ── "More" tab ────────────────────────────────────────────────────────────────
class _ParentMorePage extends StatefulWidget {
  const _ParentMorePage();

  @override
  State<_ParentMorePage> createState() => _ParentMorePageState();
}

class _ParentMorePageState extends State<_ParentMorePage> {
  Future<void> _push(Widget s) async =>
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    return AppSettingsPage(
      header: AppSettingsHeader(
        name: p.name,
        role: p.role,
        email: p.email,
        username: p.username,
        imageUrl: p.imageUrl,
        heroTag: 'profile-user-${p.id}',
      ),
      groups: [
        AppSettingsGroup(
          title: 'account'.tr,
          icon: Icons.account_circle_rounded,
          children: [
            const CertVerifyEntryTile(),
            AppSettingsTile(
              icon: Icons.manage_accounts_rounded,
              color: c.primary,
              label: 'update_account'.tr,
              onTap: () async {
                await _push(const EditAccountScreen(isTeacher: false));
                if (mounted) {
                  context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
                }
              },
            ),
            AppSettingsTile(
              icon: Icons.lock_reset_rounded,
              color: c.accent2,
              label: 'change_password'.tr,
              onTap: () => _push(const ChangePasswordScreen()),
            ),
            const CalendarEntryTile(),
            const ChatEntryTile(),
          ],
        ),
        AppSettingsGroup(
          title: 'settings'.tr,
          icon: Icons.settings_rounded,
          children: [
            const AppLanguageTile(),
            const DisplaySettingsTile(),
            if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
            const AppAssistantOpenTile(),
            const AppAssistantBubbleTile(),
            AppSettingsTile(
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(
                value: p.darkMode,
                onChanged: (b) async => await p.changeMode(b),
                semanticLabel: 'dark_mode'.tr,
              ),
            ),
            AppSettingsTile(
              icon: Icons.support_agent_rounded,
              color: c.primary,
              label: 'complaints_and_support'.tr,
              onTap: () => _push(const ComplaintsHubPage()), // D-086: New complaint + My complaints
            ),
          ],
        ),
        legalSettingsGroup(context), // privacy policy · terms of service (D-308)
        AppSettingsGroup(
          title: 'exit'.tr,
          icon: DirIcons.exitToApp,
          danger: true,
          children: [
            AppSettingsTile(
              icon: DirIcons.logout,
              color: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) {
                  await context.read<ProfileProvider>().logout(context);
                }
              },
            ),
            AppSettingsTile(
              icon: Icons.delete_forever_rounded,
              color: c.danger,
              label: 'delete_account_title'.tr,
              onTap: () async {
                        final ok = await Helpers.confirmDialog(context,
                            title: 'are_you_sure_to_delete_account'.tr, confirm: 'delete'.tr);
                        if (ok != true || !context.mounted) return;
                        final re = await askReauth(context); // current password (+ two-step code), S9
                        if (re == null || !context.mounted) return;
                        final p = context.read<ProfileProvider>();
                        final after = await p.deleteAccount(context, password: re.password, mfaCode: re.mfaCode);
                        if (after == null) {
                          Helpers.showMessage(p.errorMessage ?? 'generic_error'.tr, isError: true);
                          return;
                        }
                        Helpers.showMessage('your_account_will_deleted_successfully_through_14_days'.tr);
              },
            ),
          ],
        ),
      ],
    );
  }
}
