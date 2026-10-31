// lib/design/context_switcher.dart
//
// THE context switcher — "where am I?": Personal, or one of my organizations.
//
//   ContextSwitcher            a calm pill in the home header: the current context (icon + name + what waits
//                              elsewhere) → one tap opens the picker. Inside an organization a second, explicit
//                              "Personal" button leaves it in one tap.
//   ContextPill                the pill itself (also the organization dashboard's header, org_page_header.dart).
//   showContextSwitcherSheet   Personal + every organization, the current one checked; one tap switches.
//                              From a personal home, an organization where I am NOT a student opens the organization
//                              dashboard on it (D-103); one where I study opens its member view, as before.
//                              Inside the dashboard (`session:`) the organizations I manage / work in switch IN PLACE
//                              (OrgSession.select, remembered by AppModeController), the others open their member page.
//   ContextExitButton          the "back to Personal" app-bar action of every organization / department page.
//   leaveToPersonal            what both do: Individual mode + org context cleared + every org page closed.
//
// State lives in AppModeController (remembered per user, smart default, deep links); entering / leaving an
// organization applies / clears its context (timezone, 12h/24h, feature offs) there — nothing is duplicated here.
// Hidden while there is nothing to switch to (no live organization, organizations off, or 'home.org_tab' off).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';

import '../features/admin/admin_common.dart' show asInt, asMap, t;
import '../features/org/org_access_joining.dart' show openOrgJoin;
import '../features/org/org_common.dart' show orgColor, orgTypeIcons;
import '../features/org/org_member_dashboard.dart' show orgRolesLine;
import '../features/org/org_providers.dart' show OrgSession, orgAccessOf;
import '../features/org/org_ui.dart' show memberRoleLabels, orgNameOf;
import 'package:flutter_education_app/design/app_icons.dart';

/// Feature key that hides the organization side of the home screens (platform kill-switch).
const String kContextSwitchFeature = 'home.org_tab';

/// The switcher sits at the top of every home as long as organizations exist on the platform: a person with no
/// membership yet still opens it to find or join one (`AppModeController.available` only says whether there is a
/// live organization to switch INTO).
bool contextSwitchVisible(AppModeController ctl) =>
    AppConfig.orgsEnabled && !AppConfig.disableList.contains(kContextSwitchFeature);

/// What waits in every organization except the one open now (badge on the pill).
int pendingElsewhere(AppModeController ctl) {
  if (!ctl.isOrg) return ctl.pendingTotal;
  var n = 0;
  for (final e in ctl.liveEntries) {
    if (asInt(asMap(e['organization'])['id']) != ctl.currentOrgId) n += AppModeController.pendingOf(e);
  }
  return n;
}

/// Leaves any organization / department screen for the personal space in one tap: Individual mode (remembered per
/// user), the organization's context (timezone, feature offs) cleared and every org page above the root closed.
/// Org admins / staff, whose root screen IS an org page, land on the personal dashboard instead — before, "Personal"
/// only flipped the mode while the org pages stayed on screen, so there was no way out.
Future<void> leaveToPersonal(BuildContext context) async {
  final nav = Navigator.of(context, rootNavigator: true);
  // an org page opened inside a tab of the personal shell (D-081): that tab goes back to its own first page too
  final near = Navigator.maybeOf(context);
  final ctl = AppModeController.instance;
  await ctl.setMode(AppMode.individual);
  ctl.applyOrgContext();
  if (near != null && !identical(near, nav) && near.mounted) near.popUntil((r) => r.isFirst);
  String? root;
  nav.popUntil((r) {
    if (r.isFirst) root = r.settings.name;
    return r.isFirst;
  });
  if (AppModeController.isOrgRoute(root)) nav.pushNamedAndRemoveUntil(AppModeController.personalRoute, (_) => false);
}

/// Opens the organization dashboard on [orgId] from a personal home (D-103): remembered as the last organization,
/// selected in [OrgSession] (at once, or as soon as `/org/mine` lists it) and '/org_dashboard' pushed on top.
Future<void> openOrgDashboard(BuildContext context, int orgId) async {
  final nav = Navigator.of(context, rootNavigator: true);
  OrgSession? session;
  try {
    session = context.read<OrgSession>();
  } catch (_) {}
  session?.open(orgId);
  await AppModeController.instance.rememberDashboardOrg(orgId);
  nav.pushNamed('/org_dashboard');
}

/// App-bar action of organization / department pages: always visible, one tap back to the personal space.
class ContextExitButton extends StatelessWidget {
  const ContextExitButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('ctx.leave'),
        tooltip: 'ctx_exit'.tr,
        onPressed: () => leaveToPersonal(context),
        icon: Icon(DirIcons.logout, color: context.colors.primary, textDirection: TextDirection.ltr),
      );
}

/// The pill: a round mark (icon in [tone]) · an optional small [caption] over the [label] · a count · the
/// "choose" chevron. At least 48 px tall; one tap runs [onTap].
class ContextPill extends StatelessWidget {
  const ContextPill({
    super.key,
    required this.icon,
    required this.tone,
    required this.label,
    required this.onTap,
    this.caption,
    this.badge = 0,
    this.inkKey,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final String? caption;
  final int badge;
  final VoidCallback onTap;

  /// Key of the tappable surface (tests find it).
  final Key? inkKey;

  /// Below this width the pill keeps only its mark and the chevron (the name stays in the tooltip, the screen
  /// reader label and the sheet).
  static const double markOnlyBelow = 132;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      // a long name degrades in steps: one line → two lines (no caption) → the mark alone on a very narrow row
      final markOnly = box.maxWidth.isFinite && box.maxWidth < markOnlyBelow;
      final twoLines = caption == null;
      return Semantics(
        button: true,
        label: '${'ctx_current'.tr}: $label',
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Material(
              color: c.cardBg,
              shape: StadiumBorder(side: BorderSide(color: tone.withValues(alpha: 0.35))),
              child: InkWell(
                key: inkKey,
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(6, 6, markOnly ? 6 : 12, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ContextMark(icon: icon, tone: tone),
                      if (!markOnly) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (caption != null)
                                Text(
                                  caption!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: appText(10.5, w: FontWeight.w500, c: c.textMedium),
                                ),
                              Text(
                                label,
                                maxLines: twoLines ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: appText(twoLines ? 13 : 13.5, w: FontWeight.w600, c: c.textDark, h: twoLines ? 1.2 : null),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (badge > 0) ...[const SizedBox(width: 6), _Count(badge, color: c.danger)],
                      const SizedBox(width: 2),
                      Icon(Icons.unfold_more_rounded, size: 18, color: c.textMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class ContextSwitcher extends StatefulWidget {
  const ContextSwitcher({super.key, this.allowPersonal = true, this.compact = false});

  /// False where there is no personal space (org staff on '/org_member'): only organizations are offered.
  final bool allowPersonal;

  /// App-bar size (no "Personal" exit button, shorter label).
  final bool compact;

  @override
  State<ContextSwitcher> createState() => _ContextSwitcherState();
}

class _ContextSwitcherState extends State<ContextSwitcher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      int? uid;
      try {
        uid = context.read<MyAuthProvider>().currentUser?.id;
      } catch (_) {
        return; // no auth in scope (tests / previews): keep whatever the controller holds
      }
      AppModeController.instance.bindUser(uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctl = AppModeController.instance;
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        if (!contextSwitchVisible(ctl)) return const SizedBox.shrink();
        final c = context.colors;
        final inOrg = ctl.isOrg;
        final org = asMap(ctl.current?['organization']);
        final tone = inOrg ? orgColor(context, org) : c.primary;
        final label = inOrg ? orgNameOf(org) : 'ctx_personal'.tr;

        final pill = ContextPill(
          inkKey: const ValueKey('ctx.pill'),
          icon: inOrg ? (orgTypeIcons[org['type']] ?? Icons.account_balance_rounded) : Icons.person_rounded,
          tone: tone,
          label: label,
          caption: widget.compact ? null : (inOrg ? 'ctx_in_org'.tr : 'ctx_personal_space'.tr),
          badge: pendingElsewhere(ctl),
          onTap: () => showContextSwitcherSheet(context, allowPersonal: widget.allowPersonal), // always: join is offered
        );

        if (!inOrg || !widget.allowPersonal || widget.compact) return pill;
        // Inside an organization: the way back is always one visible tap.
        return LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 400; // phones: the exit button keeps only its icon (tooltip says it all)
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: pill),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'ctx_exit'.tr,
                  child: Material(
                    color: c.primaryTint,
                    shape: const StadiumBorder(),
                    child: InkWell(
                      key: const ValueKey('ctx.exit'),
                      customBorder: const StadiumBorder(),
                      onTap: () => leaveToPersonal(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(DirIcons.logout, size: 18, color: c.primary, textDirection: TextDirection.ltr),
                            if (!narrow) ...[
                              const SizedBox(width: 6),
                              Text(
                                'ctx_personal'.tr,
                                maxLines: 1,
                                style: appText(12.5, w: FontWeight.w600, c: c.primary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Personal + every organization; the current one is checked. One tap switches (remembered per user).
///
/// [session] = opened from the organization dashboard: its organizations (the ones `/org/mine` lists, sub-units
/// indented) switch in place; the overview's other live organizations (where I study) open their member page.
/// [onCreateOrg] adds "New organization" (the dashboard passes it when I may create a root organization).
Future<void> showContextSwitcherSheet(
  BuildContext context, {
  bool allowPersonal = true,
  OrgSession? session,
  VoidCallback? onCreateOrg,
}) async {
  final ctl = AppModeController.instance;
  if (session != null && !ctl.loaded) {
    // the dashboard does not load the membership overview on open: only when its switcher is used
    int? uid;
    try {
      uid = context.read<MyAuthProvider>().currentUser?.id;
    } catch (_) {}
    if (uid != null) ctl.bindUser(uid);
  }
  await showAppSheet<void>(context, (ctx) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (ctx, _) {
        final c = ctx.colors;
        Widget check(bool on) => on ? Icon(Icons.check_circle_rounded, color: c.success) : const SizedBox.shrink();
        final managed = session?.items ?? const <Map<String, dynamic>>[];
        final managedIds = {for (final o in managed) asInt(o['id'])};
        final inDashboard = session != null;
        int idOf(Map<String, dynamic> e) => asInt(asMap(e['organization'])['id']);
        final others = [for (final e in ctl.liveEntries) if (!managedIds.contains(idOf(e))) e];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSheetHeader('ctx_switch_title'.tr),
              if (allowPersonal)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: AppActionCard(
                    key: const ValueKey('ctx.sheet.personal'),
                    icon: Icons.person_rounded,
                    color: c.primary,
                    title: 'ctx_personal'.tr,
                    subtitle: 'ctx_personal_hint'.tr,
                    trailing: check(!inDashboard && !ctl.isOrg),
                    onTap: () {
                      Navigator.pop(ctx);
                      leaveToPersonal(context);
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Text(
                  'ctx_organizations'.tr,
                  style: appText(12, w: FontWeight.w600, c: c.textMedium),
                ),
              ),
              if (ctl.entries.isEmpty && managed.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'ctx_no_orgs'.tr,
                    key: const ValueKey('ctx.sheet.empty'),
                    style: appText(13, c: c.textMedium),
                  ),
                ),
              // inside the dashboard: the organizations I manage / work in, switched in place
              for (final o in managed)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: 16.0 * asInt(o['depth']).clamp(0, 4), bottom: 8),
                  child: AppActionCard(
                    key: ValueKey('ctx.sheet.org.${asInt(o['id'])}'),
                    icon: orgTypeIcons[o['type']] ?? Icons.account_balance_rounded,
                    color: orgColor(ctx, o),
                    title: OrgSession.nameOf(o),
                    subtitle: _dashboardLine(o),
                    trailing: check(asInt(o['id']) == session!.currentId),
                    onTap: () {
                      Navigator.pop(ctx);
                      final id = asInt(o['id']);
                      AppModeController.instance.rememberDashboardOrg(id);
                      session.select(id);
                    },
                  ),
                ),
              for (final e in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppActionCard(
                    key: ValueKey('ctx.sheet.org.${idOf(e)}'),
                    icon: orgTypeIcons[asMap(e['organization'])['type']] ?? Icons.account_balance_rounded,
                    color: orgColor(ctx, asMap(e['organization'])),
                    title: orgNameOf(asMap(e['organization'])),
                    subtitle: orgRolesLine(e),
                    badge: AppModeController.pendingOf(e),
                    trailing: check(!inDashboard && ctl.isOrg && idOf(e) == ctl.currentOrgId),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEntry(context, e, fromDashboard: inDashboard);
                    },
                  ),
                ),
              // organizations that are not open yet (under review / suspended): shown, not enterable
              for (final e in notOpenEntries(ctl.entries, ctl.liveEntries))
                if (!managedIds.contains(idOf(e)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Opacity(
                      opacity: 0.7,
                      child: AppActionCard(
                        key: ValueKey('ctx.sheet.pending.${idOf(e)}'),
                        icon: Icons.hourglass_top_rounded,
                        color: c.warning,
                        title: orgNameOf(asMap(e['organization'])),
                        subtitle: _statusText(asMap(e['organization'])['status']),
                        onTap: () {},
                      ),
                    ),
                  ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: AppActionCard(
                  key: const ValueKey('ctx.sheet.join'),
                  icon: Icons.group_add_rounded,
                  color: c.primary,
                  title: 'ctx_join_new'.tr,
                  subtitle: 'ctx_join_new_hint'.tr,
                  onTap: () {
                    Navigator.pop(ctx);
                    openOrgJoin(context, onDone: () {
                      ctl.refresh();
                      session?.load();
                    });
                  },
                ),
              ),
              if (onCreateOrg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppActionCard(
                    key: const ValueKey('ctx.sheet.create'),
                    icon: Icons.add_business_rounded,
                    color: c.primary,
                    title: t('مؤسسة جديدة', 'New organization'),
                    subtitle: t('أنشئ جامعة أو مدرسة أو أكاديمية', 'Create a university, school or academy'),
                    onTap: () {
                      Navigator.pop(ctx);
                      onCreateOrg();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  });
}

/// An overview organization was chosen. Inside the dashboard it is one where I study → its member page. From a
/// personal home: not a student there → the organization dashboard (D-103); a student → Organization mode, as before.
void _openEntry(BuildContext context, Map<String, dynamic> e, {required bool fromDashboard}) {
  final id = asInt(asMap(e['organization'])['id']);
  final ctl = AppModeController.instance;
  if (fromDashboard) {
    ctl.setMode(AppMode.organization, orgId: id);
    Navigator.of(context, rootNavigator: true).pushNamed('/org_member', arguments: id);
    return;
  }
  if (AppModeController.opensDashboard(e)) {
    openOrgDashboard(context, id);
    return;
  }
  ctl.setMode(AppMode.organization, orgId: id);
}

/// "Organization admin" / "Staff" / my membership role, or the status of an organization not open yet.
String _dashboardLine(Map<String, dynamic> o) {
  final status = '${o['status'] ?? 'approved'}';
  if (status != 'approved') return _statusText(status);
  return switch (orgAccessOf(o)) {
    'admin' => t('مدير المؤسسة', 'Organization admin'),
    'staff' => t('فريق العمل', 'Staff'),
    _ => memberRoleLabels()['${o['member_role']}'] ?? t('عضو', 'Member'),
  };
}

/// The organizations of [entries] that cannot be opened yet (under review / suspended), without the ones the person
/// already sees as open: the same organization id, or an organization of the same name (a creation request for a
/// university the person already belongs to listed it twice, M10).
List<Map<String, dynamic>> notOpenEntries(List<Map<String, dynamic>> entries, List<Map<String, dynamic>> live) {
  String norm(Object? v) => '$v'.trim().toLowerCase();
  final liveIds = {for (final e in live) asInt(asMap(e['organization'])['id'])};
  final liveNames = {for (final e in live) norm(orgNameOf(asMap(e['organization'])))};
  final seen = <int>{};
  return [
    for (final e in entries)
      if (!live.contains(e))
        if (!liveIds.contains(asInt(asMap(e['organization'])['id'])))
          if (!liveNames.contains(norm(orgNameOf(asMap(e['organization'])))))
            if (seen.add(asInt(asMap(e['organization'])['id']))) e,
  ];
}

String _statusText(Object? status) => switch ('$status') {
      'pending' || 'submitted' || 'review' => 'ctx_org_pending'.tr,
      'suspended' => 'ctx_org_suspended'.tr,
      'rejected' => 'ctx_org_rejected'.tr,
      _ => 'ctx_org_pending'.tr,
    };

class _ContextMark extends StatelessWidget {
  const _ContextMark({required this.icon, required this.tone});
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a dark organization colour on the dark card is barely visible: lift it towards the text colour there
    final ink = c.isDark ? Color.lerp(tone, c.textDark, 0.45)! : tone;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.24 : 0.14), shape: BoxShape.circle),
      child: Icon(icon, size: 17, color: ink),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, {required this.color});
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
    child: Text(
      n > 99 ? '99+' : '$n',
      style: appText(11, w: FontWeight.w600, c: context.colors.button.color),
    ),
  );
}
