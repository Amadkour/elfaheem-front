// lib/design/attention_badge.dart
//
// AttentionBadge(tabKey: AttentionTabs.orgAcademics, orgId: 12, child: …)
//   draws the count of open items of that tab (AttentionService) on its child and rebuilds by itself.
//   Tapping the bubble: one item → opens its deep link; several → a sheet listing them, each opens its link.
//   The child keeps its own taps (a tab still switches tab).
//
// openAttentionItem(context, item)        opens one item's deep link (also usable from any list)
// showAttentionItems(context, tabKey, …)  the list sheet
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../core/app_mode.dart';
import '../core/attention/attention_service.dart';
import '../features/admin/enrollment_request/teacher_transfers_screen.dart' show TeacherTransfersScreen;
import '../features/shared/inbox/unified_inbox.dart' show InboxItem, openInboxItem;
import '../main.dart' show navigatorKey;
import '../utils/top_route_observer.dart' show topRouteObserver;
import '../utils/widget/app_navigator.dart';
import 'app_kit.dart';

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class AttentionBadge extends StatelessWidget {
  const AttentionBadge({super.key, required this.tabKey, required this.child, this.orgId, this.onOpen});

  final String tabKey;
  final Widget child;
  /// Only this organization's items (org dashboards). Null = everything of the tab.
  final int? orgId;
  /// Called for items that have no deep link of their own (e.g. "open this tab").
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final svc = AttentionService.instance;
    return ListenableBuilder(
      listenable: svc,
      builder: (context, _) {
        final n = svc.count(tabKey, orgId: orgId);
        if (n <= 0) return child;
        return Stack(clipBehavior: Clip.none, children: [
          child,
          PositionedDirectional(
            top: -6,
            end: -6,
            child: Semantics(
              button: true,
              label: _tx('$n عنصر يحتاج انتباهك', '$n items need your attention'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showAttentionItems(context, tabKey, orgId: orgId, onOpen: onOpen),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: context.colors.danger, borderRadius: BorderRadius.circular(10)),
                  child: Text(n > 99 ? '99+' : '$n',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, height: 1.1)),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// One item → open it; several → the list sheet.
Future<void> showAttentionItems(BuildContext context, String tabKey, {int? orgId, VoidCallback? onOpen}) async {
  final items = AttentionService.instance.items(tabKey, orgId: orgId);
  if (items.isEmpty) return;
  if (items.length == 1) {
    await openAttentionItem(context, items.first, onOpen: onOpen);
    return;
  }
  final picked = await showAppSheet<AttentionItem>(context, (ctx) {
    final c = ctx.colors;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .75),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
          AppSectionTitle(_tx('يحتاج انتباهك', 'Needs your attention')),
          for (final x in items)
            AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => Navigator.pop(ctx, x),
              child: Row(children: [
                Icon(x.isSuggestion ? Icons.auto_fix_high_rounded : Icons.notification_important_rounded,
                    color: x.severity == 'danger' ? c.danger : (x.severity == 'warning' ? c.warning : c.primary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_tx(x.titleAr, x.titleEn), style: appText(14, w: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if ((x.subtitle ?? '').isNotEmpty)
                      Text(x.subtitle!, style: appText(12, c: c.textMedium), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                if (x.count > 1) ...[const SizedBox(width: 8), AppBadgePill('${x.count}', color: c.danger)],
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
        ]),
      ),
    );
  });
  if (picked != null && context.mounted) await openAttentionItem(context, picked, onOpen: onOpen);
}

/// Server org sub ('join_requests', 'program_choices', …) → the org dashboard's sub-page id.
String? orgSubPage(String section, String? sub) => switch ((section, sub)) {
      ('people', 'join_requests' || 'expiring') => 'members',
      ('people', 'unit_requests') => 'join_requests',
      ('academics', 'program_choices') => 'structure',
      ('academics', 'decisions') => 'registrar',
      ('services', 'forms') => 'forms',
      ('services', 'complaints') => 'complaints',
      _ => null,
    };

/// Opens the org dashboard of [orgId] on [section] (and its sub-page). Works from any screen.
Future<void> openOrgSection(int orgId, String section, {String? sub}) async {
  AttentionService.instance.orgTabRequest.value = OrgTabRequest(orgId, section, sub);
  if (topRouteObserver.currentRoute?.settings.name == '/org_dashboard') return;   // the dashboard picks it up
  await AppModeController.instance.openOrg(orgId);
  await navigatorKey.currentState?.pushNamed('/org_dashboard');
}

/// Opens what an attention item points to, then refreshes the counts.
Future<void> openAttentionItem(BuildContext context, AttentionItem x, {VoidCallback? onOpen}) async {
  final a = x.action;
  final orgId = x.orgId ?? int.tryParse('${a['org_id'] ?? ''}');
  switch (x.actionType) {
    case 'org_tab':
      final section = '${a['tab']}';
      if (orgId != null) await openOrgSection(orgId, section, sub: orgSubPage(section, a['sub']?.toString()));
    case 'org_decision':
      // drafts (auto-create suggestions) are approved where they are created; other decisions in the registrar
      if (orgId != null) await openOrgSection(orgId, 'academics', sub: x.isSuggestion ? 'structure' : 'registrar');
    case 'complaints':
      if (x.tab == AttentionTabs.profile) {
        await AppNavigator.openModule('profile');
      } else {
        onOpen?.call();
      }
    case 'transfers':
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen()));
    case 'parent_alerts':
      _requestShellTab('parent_alerts');
    case '':
      onOpen?.call();
    default:
      if (!context.mounted) return;
      await openInboxItem(context, InboxItem({...x.raw, 'segment': 'todo', 'org_id': orgId, 'action': a}));
  }
  AttentionService.instance.refresh();
}

/// Tabs inside a role dashboard: back to the root, then the dashboard switches (AppNavigator.requestedTab).
void _requestShellTab(String id) {
  navigatorKey.currentState?.popUntil((r) => r.isFirst);
  AppNavigator.requestedTab.value = null;
  AppNavigator.requestedTab.value = id;
}
