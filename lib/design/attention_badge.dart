// lib/design/attention_badge.dart
//
// AttentionBadge(tabKey: AttentionTabs.orgAcademics, orgId: 12, child: …)
//   draws the count of open items of that tab (AttentionService) on its child and rebuilds by itself.
//   Tapping the bubble: one item → opens its deep link; several → a sheet listing them, each opens its link.
//   The child keeps its own taps (a tab still switches tab). The bubble is the danger count pill of the kit
//   (it means "waiting on you"), popping once when its number changes (AppBump, D-581), with a hit area a little
//   wider than the pill itself.
//
// openAttentionItem(context, item)        opens one item's deep link (also usable from any list)
// showAttentionItems(context, tabKey, …)  the list sheet
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../core/app_mode.dart';
import '../core/attention/attention_service.dart';
import '../core/notif_link.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart' show TeacherTransfersScreen;
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart' show InboxItem, openInboxItem;
import '../main.dart' show navigatorKey;
import '../utils/top_route_observer.dart' show topRouteObserver;
import 'app_shell_nav.dart' show AppShellNav;
import '../utils/widget/app_navigator.dart';
import 'app_kit.dart';
import 'listenable_selector.dart';

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

class AttentionBadge extends StatelessWidget {
  const AttentionBadge({super.key, required this.tabKey, required this.child, this.orgId, this.onOpen});

  final String tabKey;
  final Widget child;
  /// Only this organization's items (org dashboards). Null = everything of the tab.
  final int? orgId;
  /// Called for items that have no deep link of their own (e.g. "open this tab").
  final VoidCallback? onOpen;

  /// How far the pill hangs over the child's top-end corner.
  static const double _overhang = 6;

  /// The invisible margin around the pill that also takes the tap (the pill is 20 px; the fringe makes 36).
  static const double _fringe = AppSpace.xs;

  @override
  Widget build(BuildContext context) {
    final svc = AttentionService.instance;
    // rebuilds when THIS tab's count moves, not on every answer of the feed (UX v3 phase 5)
    return ListenableSelector<int>(
      listenable: svc,
      select: () => svc.count(tabKey, orgId: orgId),
      builder: (context, n) {
        if (n <= 0) return child;
        return Stack(clipBehavior: Clip.none, children: [
          child,
          PositionedDirectional(
            top: -(_overhang + _fringe),
            end: -(_overhang + _fringe),
            child: Semantics(
              button: true,
              label: _tx('$n عنصر يحتاج انتباهك', '$n items need your attention'),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showAttentionItems(context, tabKey, orgId: orgId, onOpen: onOpen),
                child: Padding(
                  padding: const EdgeInsets.all(_fringe),
                  child: AppCountBadge(count: n),
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
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
          children: [
            AppSectionTitle(_tx('يحتاج انتباهك', 'Needs your attention')),
            for (final x in items)
              AppCard(
                margin: const EdgeInsets.only(bottom: AppSpace.xs),
                onTap: () => Navigator.pop(ctx, x),
                child: Row(children: [
                  Icon(
                    x.isSuggestion ? Icons.auto_fix_high_rounded : Icons.notification_important_rounded,
                    size: AppIconSize.lg,
                    color: x.severity == 'danger' ? c.danger : (x.severity == 'warning' ? c.warning : c.primary),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_tx(x.titleAr, x.titleEn),
                          style: AppType.row(ctx).copyWith(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      if ((x.subtitle ?? '').isNotEmpty)
                        Text(x.subtitle!, style: AppType.meta(ctx), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  if (x.count > 1) ...[const SizedBox(width: AppSpace.xs), AppCountBadge(count: x.count)],
                  const SizedBox(width: AppSpace.xxs),
                  Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight),
                ]),
              ),
          ],
        ),
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
      ('timetable', 'generate') => 'generate',           // the term cards ("Generate now")
      _ => null,
    };

/// Opens the org dashboard of [orgId] on [section] (and its sub-page). Works from any screen.
Future<void> openOrgSection(int orgId, String section, {String? sub}) async {
  AttentionService.instance.orgTabRequest.value = OrgTabRequest(orgId, section, sub);
  if (topRouteObserver.rootRoute?.settings.name == '/org_dashboard') {             // the dashboard picks it up
    WidgetsBinding.instance.addPostFrameCallback((_) => AppShellNav.popVisibleToRoot()); // the section, not a page on it
    return;
  }
  await AppModeController.instance.openOrg(orgId);
  await navigatorKey.currentState?.pushNamed('/org_dashboard');
}

/// UX v3 phase 2: a governance row's `target` (on the row or inside its action): `{module, id, org_id}` when one
/// item waits (that item), `{module: action_inbox}` when several do (Needs my action). Null = the old routing.
NotifLink? attentionTargetLink(AttentionItem x) {
  final t = x.raw['target'] ?? x.action['target'];
  final l = NotifLink.fromAttentionTarget(t);
  if (l == null || l.orgId != null || x.orgId == null) return l;
  return NotifLink.fromAttentionTarget({...(t as Map), 'org_id': x.orgId});
}

/// Opens what an attention item points to, then refreshes the counts.
Future<void> openAttentionItem(BuildContext context, AttentionItem x, {VoidCallback? onOpen}) async {
  final a = x.action;
  final orgId = x.orgId ?? int.tryParse('${a['org_id'] ?? ''}');
  final target = attentionTargetLink(x);
  if (target != null) {
    await AppNavigator.openLink(target);
    AttentionService.instance.refresh();
    return;
  }
  switch (x.actionType) {
    case 'org_tab':
      final section = '${a['tab']}';
      if (orgId != null) await openOrgSection(orgId, section, sub: orgSubPage(section, a['sub']?.toString()));
    case 'org_decision':
      // drafts (auto-create suggestions) are approved where they are created; other decisions in the registrar
      if (orgId != null) await openOrgSection(orgId, 'academics', sub: x.isSuggestion ? 'structure' : 'registrar');
    case 'complaints':
      if (x.tab == AttentionTabs.profile) {
        await AppNavigator.openModule('support'); // the profile's Complaints page (D-086)
      } else {
        onOpen?.call();
      }
    case 'transfers':
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherTransfersScreen()));
    case 'parent_alerts':
      _requestShellTab('parent_alerts');
    case 'chat': // D-330: unread messages
      await AppNavigator.openModule('chat');
    case 'chat_reports': // an admin: chat reports to review
      await AppNavigator.openModule('chat_reports');
    case 'teacher_todo': // D-303: the teacher's automatic to-do list
      await AppNavigator.openModule('teacher_todo');
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
  AppShellNav.popVisibleToRootAfterSwitch(); // that tab's own first page, not a page left open on it (D-081)
}
