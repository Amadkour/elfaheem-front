// lib/features/org/workspace/ws_shell.dart
//
// The teacher workspace (D-1150 – D-1158, docs/teacher-org/PLAN.md): what every non-student organization role
// WITHOUT organization-wide admin access opens instead of the D-103 admin sections. Tabs, in this order:
//   Overview · Management · Membership · Pinned · Alerts · Profile
// Management / Membership hide when empty, Pinned when nothing is pinned (D-1151). One controller ([WsController],
// provided to every tab) holds GET …/my-workspace, the alert counts and the preferences; it reloads when another
// organization is chosen (OrgSession.epoch). The shell is the same AppShell every dashboard uses (D-062), its index
// held by the dashboard's OrgTabs, so deep links (orgJump / AttentionService.orgTabRequest) keep working: a section
// that is not a tab here is pushed as a page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_shell.dart' show AppShell, DashboardItem;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_dashboard_screen.dart' show OrgShellTab, OrgTabs;
import '../org_providers.dart';
import '../org_v3.dart' show OrgCall;
import 'ws_alerts.dart' show WsAlertsTab;
import 'ws_models.dart';
import 'ws_overview.dart' show WsOverviewTab;
import 'ws_pinned.dart' show WsPinnedTab;
import 'ws_profile.dart' show WsProfileTab;
import 'ws_store.dart';
import 'ws_units.dart' show WsUnitsTab;

/// Kill switch: off → every role opens the D-103 dashboard, as before.
const wsFeatureKey = 'org.teacher_workspace';

/// D-1150: who opens the workspace in the selected organization.
bool wsEligible(OrgSession s) =>
    s.currentId != null && !s.isOrgAdmin && s.access != 'admin' && !AppConfig.disableList.contains(wsFeatureKey);

/// The tab keys, in the shell's order (D-1151).
abstract final class WsTabs {
  static const overview = 'ws_overview';
  static const management = 'ws_management';
  static const membership = 'ws_membership';
  static const pinned = 'ws_pinned';
  static const alerts = 'ws_alerts';
  static const profile = 'ws_profile';
}

/// The workspace's one state holder (provided as `ChangeNotifierProvider<WsController>`).
class WsController extends ChangeNotifier {
  WsController({required this.orgId, required int? userId, required this.tabs})
      : api = WsApi(orgId),
        prefs = WsPrefsStore(userId, orgId) {
    prefs.addListener(notifyListeners);
  }

  final int orgId;
  final WsApi api;
  final WsPrefsStore prefs;
  final OrgTabs tabs;

  WsHome? home;
  OrgCall? error;
  bool loading = false;
  DateTime? loadedAt;
  WsAlertCounts alertCounts = const WsAlertCounts();
  bool _disposed = false;

  bool get loaded => home != null;

  Future<void> load({bool quiet = false}) async {
    if (!prefs.loaded) await prefs.load();
    if (!quiet) {
      loading = true;
      _notify();
    }
    final (h, r) = await api.home();
    if (_disposed) return;
    loading = false;
    if (h != null) {
      home = h;
      error = null;
      loadedAt = DateTime.now();
      alertCounts = WsAlertCounts(active: h.stats.alertsActive, unread: alertCounts.unread, high: h.stats.alertsHigh);
    } else {
      error = r;
    }
    _notify();
    refreshAlertCounts();
  }

  /// The Alerts tab badge (unread) and the Overview's alert numbers.
  Future<void> refreshAlertCounts() async {
    final (_, counts, r) = await api.alerts();
    if (_disposed || !r.ok) return;
    setAlertCounts(counts);
  }

  void setAlertCounts(WsAlertCounts c) {
    alertCounts = c;
    _notify();
  }

  /// Opens a workspace tab ([WsTabs]); false when it is not shown (e.g. Management with nothing managed).
  bool go(String key) => tabs.go(key);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    prefs.removeListener(notifyListeners);
    prefs.dispose();
    super.dispose();
  }
}

/// The shell. [width] / [unreadCount] come from the dashboard's LayoutBuilder, like the D-103 shell.
class TeacherWorkspace extends StatefulWidget {
  const TeacherWorkspace({super.key, required this.session, required this.userId, required this.width, this.unreadCount = 0});

  final OrgSession session;
  final int? userId;
  final double width;
  final int unreadCount;

  @override
  State<TeacherWorkspace> createState() => _TeacherWorkspaceState();
}

class _TeacherWorkspaceState extends State<TeacherWorkspace> {
  WsController? _ws;
  int _epoch = -1;

  void _ensure(OrgTabs tabs) {
    final id = widget.session.currentId!;
    final e = widget.session.epoch.value;
    if (_ws != null && _ws!.orgId == id && _epoch == e) return;
    final old = _ws;
    _epoch = e;
    _ws = WsController(orgId: id, userId: widget.userId, tabs: tabs)..load();
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void dispose() {
    _ws?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<OrgTabs>();
    return ValueListenableBuilder<int>(
      valueListenable: widget.session.epoch,
      builder: (context, _, _) {
        _ensure(tabs);
        return ChangeNotifierProvider<WsController>.value(
          value: _ws!,
          child: Consumer<WsController>(builder: (context, ws, _) {
            final entries = wsShellItems(ws);
            tabs.keys = [for (final e in entries) e.$1];
            final items = [for (final e in entries) e.$2];
            return AppShell(
              width: widget.width,
              currentIndex: tabs.currentTab.clamp(0, items.length - 1),
              onTap: tabs.onChangeTab,
              items: items,
              unreadCount: widget.unreadCount,
              showTopBar: false,
            );
          }),
        );
      },
    );
  }
}

/// The shell's tabs for what [ws] holds right now (D-1151).
List<(String, DashboardItem)> wsShellItems(WsController ws) {
  final h = ws.home;
  final p = ws.prefs.prefs;
  // before the first answer both unit tabs are drawn (their pages show skeletons), so the bar doesn't jump
  final showManaged = h == null || h.managed.isNotEmpty;
  final showMember = h == null || h.memberOf.isNotEmpty;
  return [
    (WsTabs.overview, DashboardItem(Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, t('لمحة', 'Overview'), null,
        OrgShellTab(title: t('لمحة', 'Overview'), helpPageId: 'home.org/ws_overview', child: const WsOverviewTab()))),
    if (showManaged)
      (WsTabs.management, DashboardItem(Icons.admin_panel_settings_outlined, Icons.admin_panel_settings_rounded, t('الإدارة', 'Management'), null,
          OrgShellTab(title: t('الإدارة', 'Management'), helpPageId: 'home.org/ws_management', child: const WsUnitsTab(scope: 'management')))),
    if (showMember)
      (WsTabs.membership, DashboardItem(Icons.groups_2_outlined, Icons.groups_2_rounded, t('العضوية', 'Membership'), null,
          OrgShellTab(title: t('العضوية', 'Membership'), helpPageId: 'home.org/ws_membership', child: const WsUnitsTab(scope: 'membership')))),
    if (p.pins.isNotEmpty)
      (WsTabs.pinned, DashboardItem(Icons.push_pin_outlined, Icons.push_pin_rounded, t('المثبّتة', 'Pinned'), null,
          OrgShellTab(title: t('المثبّتة', 'Pinned'), helpPageId: 'home.org/ws_pinned', child: const WsPinnedTab()))),
    (WsTabs.alerts, DashboardItem(Icons.notifications_none_rounded, Icons.notifications_rounded, t('التنبيهات', 'Alerts'), null,
        OrgShellTab(title: t('التنبيهات', 'Alerts'), helpPageId: 'home.org/ws_alerts', child: const WsAlertsTab()),
        badge: ws.alertCounts.unread)),
    (WsTabs.profile, DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, t('الملف الشخصي', 'Profile'), null,
        OrgShellTab(title: t('الملف الشخصي', 'Profile'), helpPageId: 'home.org/ws_profile', child: const WsProfileTab()))),
  ];
}
