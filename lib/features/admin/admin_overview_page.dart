// lib/features/admin/admin_overview_page.dart — the super admin's Overview tab (Track B.2).
//
// ONE call, GET /api/v1/admin/overview, through AdminOverviewProvider (admin_providers.dart): the last payload is
// kept in memory, so a re-created page draws at once; a coordinated AppListSkeleton only on the very first load;
// ErrorRetry when there is nothing to show yet, a warning line when a refresh fails over shown numbers. It reloads
// on open, on resume, on pull (AppRefresh) and on the live events `attention_changed` / transfers / payouts /
// payments (LiveEvents). The body is AdminHomeBody (admin_home_body.dart), presentational over AdminHomeData
// (admin_home_data.dart); this file only wires the callbacks (tabs, pages, alert deep links). Beside the overview it
// asks the RAG service for the assistant's health (GET /api/v1/rag/admin/monitoring/summary, Track E.7) — the core
// cannot import the RAG service; an older server (bare 404) or `rag.assistant` off leaves the card out. The
// assistant's open monitoring alerts (GET /api/v1/rag/admin/alerts?state=open) join "Needs you" the same way; a tap
// opens the console's Alerts tab.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/attention/decision_refresh.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart';
import '../shared/attendance/admin_data_lab_page.dart';
import '../shared/rag/rag_admin_console.dart' show RagAdminApi, RagAdminConsole;
import '../shared/rag/rag_alerts.dart' show RagAlertsApi, RagAlertsData, ragAdminAlert;
import 'admin_common.dart';
import 'admin_features_page.dart';
import 'admin_home_body.dart';
import 'admin_home_data.dart';
import 'admin_income_breakdown.dart';
import 'admin_organizations_page.dart';
import 'admin_payouts_page.dart';
import 'admin_providers.dart';
import 'admin_subscriptions_page.dart';
import 'admin_users_page.dart';
import 'enrollment_request/teacher_transfers_screen.dart';

class AdminOverviewPage extends StatelessWidget {
  const AdminOverviewPage({super.key, required this.onOpenTab});

  /// 0 overview · 1 students · 2 courses · 3 teachers · 4 more
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminOverviewProvider()..load(quiet: true),
        child: _View(onOpenTab: onOpenTab),
      );
}

class _View extends StatefulWidget {
  const _View({required this.onOpenTab});

  final ValueChanged<int> onOpenTab;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> with WidgetsBindingObserver {
  StreamSubscription<LiveEvent>? _sub;

  /// The AI assistant card's numbers (null until loaded, or when the route is missing / the assistant is off).
  AdminAssistantHealth? _assistant;

  /// The RAG service answered a bare 404: an older server, never asked again on this page.
  bool _assistantMissing = false;

  /// The assistant's open monitoring alerts (GET /api/v1/rag/admin/alerts?state=open), merged into "Needs you".
  List<AdminAlert> _ragAlerts = const [];
  bool _ragAlertsMissing = false;

  Future<void> _loadRagAlerts() async {
    if (_ragAlertsMissing || AppConfig.disableList.contains('rag.assistant')) return;
    final r = await RagAlertsApi().list(state: 'open');
    if (!mounted) return;
    if (r.ok) {
      setState(() => _ragAlerts = [for (final a in RagAlertsData.fromJson(r.map).open) ragAdminAlert(a)]);
    } else if (r.unavailable) {
      setState(() {
        _ragAlertsMissing = true;
        _ragAlerts = const [];
      });
    } // any other failure keeps the last ones
  }

  Future<void> _loadAssistant() async {
    if (_assistantMissing || AppConfig.disableList.contains('rag.assistant')) return;
    _loadRagAlerts();
    final r = await RagAdminApi().monitoringSummary();
    if (!mounted) return;
    if (r.ok) {
      setState(() => _assistant = AdminAssistantHealth.fromJson(r.map));
    } else if (r.unavailable) {
      setState(() {
        _assistantMissing = true;
        _assistant = null;
      });
    } // any other failure keeps the last numbers
  }

  @override
  void initState() {
    super.initState();
    _loadAssistant();
    WidgetsBinding.instance.addObserver(this);
    _sub = LiveEvents.instance.listen(
      {LiveEvents.attentionChanged, LiveEvents.transfers, LiveEvents.payouts, LiveEvents.payments},
      (e) => _reloadQuietly(decision: DecisionRefresh.isLocal(e)),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reloadQuietly();
  }

  void _reloadQuietly({bool decision = false}) {
    if (!mounted) return;
    context.read<AdminOverviewProvider>().load(quiet: true, decision: decision);
    context.read<AdminPendingPayoutsProvider>().refresh();
    _loadAssistant();
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<AdminOverviewProvider>().load(),
      context.read<AdminPendingPayoutsProvider>().refresh(),
      _loadAssistant(),
    ]);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _reloadQuietly();
  }

  Future<void> _openPayouts() async {
    final badge = context.read<AdminPendingPayoutsProvider>();
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminPayoutsPage()));
    badge.refresh();
    _reloadQuietly();
  }

  /// `alerts[].deep_link` → the page of this app version (an unknown key opens an explanation sheet).
  void _openAlert(AdminAlert a) {
    switch (a.key) {
      case 'jobs_failed_24h':
        _showJobsSheet(a.byKind, a.count);
      case 'payouts_overdue':
        _openPayouts();
      case 'teacher_documents_pending':
        _open(const AdminUsersPage(role: 'teacher'));
      case 'transfers_pending':
        _open(const TeacherTransfersScreen());
      case 'orgs_pending_approval':
        _open(const AdminOrganizationsPage());
      case _ when a.isRag:
        _open(const RagAdminConsole(initialTab: RagAdminConsole.alertsTab));
      default:
        _showInfoSheet(adminAlertTitleKey(a.key).tr, adminAlertHint(a) ?? '${a.count}');
    }
  }

  void _showInfoSheet(String title, String text) {
    final c = context.colors;
    showAppSheet<void>(
      context,
      (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(title),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Text(text, style: appText(14, c: c.textMedium, h: 1.5)),
        ),
      ]),
    );
  }

  /// The failed jobs of the last 24 h per kind (there is no jobs page in the app yet).
  void _showJobsSheet(Map<String, int> byKind, int total) {
    final c = context.colors;
    final rows = byKind.entries.where((e) => e.value > 0).toList();
    showAppSheet<void>(
      context,
      (_) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('admin_alert_jobs_failed_24h'.tr),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (rows.isEmpty)
              Text('$total', style: appText(22, w: FontWeight.w800, c: c.danger))
            else
              for (final e in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(child: Text(adminJobKindKey(e.key).tr, style: appText(14, c: c.textDark))),
                    Text('${e.value}', style: appText(15, w: FontWeight.w800, c: c.danger)),
                  ]),
                ),
            const SizedBox(height: 12),
            Text('admin_alert_jobs_hint'.tr, style: appText(12.5, c: c.textLight, h: 1.4)),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final p = context.watch<AdminOverviewProvider>();
    final home = p.home;
    if (home == null) {
      return p.error != null
          ? ErrorRetry(message: p.error!, onRetry: p.load)
          : const AppListSkeleton(items: 6);
    }
    // Live count owned by the dashboard shell (same number as the Finance / More badge).
    final pendingPayouts = context.watch<AdminPendingPayoutsProvider>().count;
    final name = context.watch<MyAuthProvider>().currentUser?.name ?? '';

    return AppRefresh(
      onRefresh: _refresh,
      child: AdminHomeBody(
        data: home.withAlerts(_ragAlerts),
        name: name,
        pendingPayouts: pendingPayouts,
        notice: p.error == null ? null : 'admin_home_stale'.tr,
        headerActions: const [CalendarEntryIcon()],
        assistant: _assistant,
        actions: AdminHomeActions(
          openStudents: () => widget.onOpenTab(1),
          openCourses: () => widget.onOpenTab(2),
          openTeachers: () => widget.onOpenTab(3),
          openTransfers: () => _open(const TeacherTransfersScreen()),
          openPayouts: _openPayouts,
          openSubscriptions: () => _open(const AdminSubscriptionsPage()),
          openOrganizations: () => _open(const AdminOrganizationsPage()),
          openDataLab: () => _open(const AdminDataLabPage()),
          openAssistant: () => _open(const RagAdminConsole()),
          openFeatures: () => _open(const AdminFeaturesPage()),
          openIncome: () => showIncomeBreakdown(context),
          openJobs: () => _showJobsSheet(home.jobsFailedByKind, home.jobsFailed24h),
          openAlert: _openAlert,
        ),
      ),
    );
  }
}
