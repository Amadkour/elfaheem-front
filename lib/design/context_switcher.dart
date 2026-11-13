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
//
//   switchOrganization         org A -> org B: closes A's pages, clears A's per-org state (timezone, feature offs,
//                              attention focus: OrgSession.select) and selects B in BOTH AppModeController and OrgSession.
//   Who drops it in            student / teacher / admin homes and every org page header (ContextPill logo + name);
//                              the parent home drops in `ContextSwitcher(compact: true)` the same way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionService, OrgTabRequest;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'app_shell_nav.dart' show AppShellNav;
import 'chrome_button.dart' show ChromeBar;

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

/// Org A -> org B (the sheet of the dashboard, a notification for another organization): every org page of A closes,
/// A's per-org state is cleared (OrgSession.select: timezone / 12h-24h, feature offs, attention focus) and B is
/// selected in BOTH [AppModeController] (remembered) and [OrgSession]. Never throws.
Future<void> switchOrganization(BuildContext context, int orgId, {OrgSession? session}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  var s = session;
  if (s == null) {
    try {
      s = context.read<OrgSession>();
    } catch (_) {}
  }
  closeOrgPages(nav);
  await AppModeController.instance.rememberDashboardOrg(orgId);
  if (s != null) {
    s.open(orgId);
    s.select(orgId);
  }
}

/// "Open the organization" right after I joined it (an accepted invitation, an approved request): the SAME rule as
/// the switcher and a notification tap - an organization where I am NOT a student ([AppModeController.opensDashboardFor];
/// [staff] is the fallback while the overview does not list it yet) opens the dashboard on it, one where I study the
/// member home (Organization mode). Everything above the root closes first. Never throws.
Future<void> openJoinedOrganization(BuildContext context, int orgId, {bool? staff}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final ctl = AppModeController.instance;
  final asStaff = ctl.opensDashboardFor(orgId) ?? staff ?? false;
  try {
    if (asStaff) {
      await switchOrganization(context, orgId);
      nav.pushNamedAndRemoveUntil('/org_dashboard', (_) => false);
    } else {
      await ctl.setMode(AppMode.organization, orgId: orgId);
      nav.pushNamedAndRemoveUntil(AppModeController.personalRoute, (_) => false);
    }
  } catch (_) {/* never block the tap */}
}

/// Closes every page above the organization dashboard (or the app root), in the root navigator and in the tab on screen.
void closeOrgPages(NavigatorState nav) {
  nav.popUntil((r) => r.isFirst || r.settings.name == '/org_dashboard' || r.settings.name == '/org_member');
  AppShellNav.popVisibleToRoot();
}

/// Opens the organization dashboard on [orgId] from a personal home (D-103): remembered as the last organization,
/// selected in [OrgSession] (at once, or as soon as `/org/mine` lists it) and '/org_dashboard' pushed on top.
/// [section] (+ [sub]) opens it on that section / sub-page, e.g. `academics` · `courses` (the dashboard consumes
/// the request once its organizations are loaded, as for an attention item).
Future<void> openOrgDashboard(BuildContext context, int orgId, {String? section, String? sub}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  if (section != null) AttentionService.instance.orgTabRequest.value = OrgTabRequest(orgId, section, sub);
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
/// "choose" chevron. Paper with a warm hairline — the organization's colour lives in the mark alone, never in the
/// pill's edge. At least 48 px tall; one tap runs [onTap].
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
    this.logoUrl,
  });

  final IconData icon;
  final Color tone;
  final String label;
  final String? caption;
  final int badge;
  final VoidCallback onTap;

  /// The organization's logo (shown in the mark when it loads; the icon otherwise).
  final String? logoUrl;

  /// Key of the tappable surface (tests find it).
  final Key? inkKey;

  /// Below this width the pill keeps only its mark and the chevron (the name stays in the tooltip, the screen
  /// reader label and the sheet).
  static const double markOnlyBelow = 132;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // on the forest hero (D-630, inside a ChromeBar) the pill is a translucent cream plate in cream ink; the mark
    // keeps its paper disc so the organization's colour still reads
    final glass = ChromeBar.of(context);
    final ink = glass ? c.onHero : c.textDark;
    final inkSoft = glass ? c.onHeroMuted : c.textMedium;
    return LayoutBuilder(builder: (context, box) {
      // a long name degrades in steps: one line → two lines (no caption) → the mark alone on a very narrow row
      final markOnly = box.maxWidth.isFinite && box.maxWidth < markOnlyBelow;
      // narrower than mark + chevron (a 320 px Arabic top bar): the mark alone, the pill still opens the sheet
      final bare = box.maxWidth.isFinite &&
          box.maxWidth < _ContextMark.size + AppSpace.xxs + AppIconSize.md + AppSpace.xs * 2;
      final twoLines = caption == null;
      return Semantics(
        button: true,
        label: '${'ctx_current'.tr}: $label',
        excludeSemantics: true,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
            child: Material(
              color: glass ? c.heroGlass : c.cardBg,
              shape: StadiumBorder(side: BorderSide(color: glass ? c.heroGlassBorder : c.divider, width: AppBorder.hairline)),
              child: InkWell(
                key: inkKey,
                customBorder: const StadiumBorder(),
                hoverColor: glass ? c.heroGlass : c.inputBg,
                focusColor: glass ? c.heroGlass : c.inputBg,
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                      AppSpace.xs, AppSpace.xs, markOnly || bare ? AppSpace.xs : AppSpace.sm, AppSpace.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // bare: the count rides on the mark's corner
                      AppCountBadge(
                        count: bare ? badge : 0,
                        child: glass
                            ? DecoratedBox(
                                decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle),
                                child: _ContextMark(icon: icon, tone: tone, logoUrl: logoUrl),
                              )
                            : _ContextMark(icon: icon, tone: tone, logoUrl: logoUrl),
                      ),
                      if (!markOnly) ...[
                        AppSpace.gapXs,
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
                                  style: AppType.meta(context).copyWith(color: glass ? c.onHeroMuted : c.textLight),
                                ),
                              Text(
                                label,
                                maxLines: twoLines ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.label(context).copyWith(
                                    fontWeight: FontWeight.w600, color: ink, height: twoLines ? 1.2 : null),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (badge > 0 && !bare) ...[AppSpace.gapXs, AppCountBadge(count: badge)],
                      if (!bare) ...[
                        const SizedBox(width: AppSpace.xxs),
                        Icon(Icons.unfold_more_rounded, size: AppIconSize.md, color: inkSoft),
                      ],
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
          logoUrl: inOrg ? '${org['logo_url'] ?? ''}' : null,
          onTap: () => showContextSwitcherSheet(context, allowPersonal: widget.allowPersonal), // always: join is offered
        );

        if (!inOrg || !widget.allowPersonal || widget.compact) return pill;
        // Inside an organization: the way back is always one visible tap — an emerald-tinted pill (the block's
        // tint with its text-safe ink), the one action beside the paper pill.
        final emerald = AppBlockColors.of(context, AppBlockTone.emerald);
        final exitInk = emerald.accentInk(c.primary);
        return LayoutBuilder(
          builder: (context, box) {
            final narrow = box.maxWidth < 400; // phones: the exit button keeps only its icon (tooltip says it all)
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: pill),
                AppSpace.gapXs,
                Tooltip(
                  message: 'ctx_exit'.tr,
                  child: Material(
                    color: emerald.surface,
                    shape: StadiumBorder(
                        side: emerald.border == null
                            ? BorderSide.none
                            : BorderSide(color: emerald.border!, width: AppBorder.hairline)),
                    child: InkWell(
                      key: const ValueKey('ctx.exit'),
                      customBorder: const StadiumBorder(),
                      onTap: () => leaveToPersonal(context),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppTouch.min, minWidth: AppTouch.min),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(DirIcons.logout, size: AppIconSize.md, color: exitInk, textDirection: TextDirection.ltr),
                              if (!narrow) ...[
                                AppSpace.gapXs,
                                Text(
                                  'ctx_personal'.tr,
                                  maxLines: 1,
                                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: exitInk),
                                ),
                              ],
                            ],
                          ),
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
  if (!ctl.loaded) {
    // the dashboard / admin home do not load the membership overview on open: only when the switcher is used
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
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSheetHeader('ctx_switch_title'.tr),
              // the list could not be refreshed: the last known one stays below, with a way to retry
              if (ctl.refreshFailed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: AppErrorState(
                    key: const ValueKey('ctx.sheet.error'),
                    compact: true,
                    title: t('تعذّر تحديث مؤسساتك', 'Could not refresh your organizations'),
                    onRetry: () => ctl.refresh(),
                  ),
                ),
              if (allowPersonal)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
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
              // the editorial rhythm inside a sheet: more room above the heading than below it
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, top: AppSpace.xs, bottom: AppSpace.sm),
                child: Text('ctx_organizations'.tr, style: AppType.section(ctx)),
              ),
              if (ctl.entries.isEmpty && managed.isEmpty && !ctl.refreshFailed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text(
                    'ctx_no_orgs'.tr,
                    key: const ValueKey('ctx.sheet.empty'),
                    style: AppType.body(ctx),
                  ),
                ),
              // inside the dashboard: the organizations I manage / work in, switched in place
              for (final o in managed)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: AppSpace.md * asInt(o['depth']).clamp(0, 4), bottom: AppSpace.xs),
                  child: AppActionCard(
                    key: ValueKey('ctx.sheet.org.${asInt(o['id'])}'),
                    icon: orgTypeIcons[o['type']] ?? Icons.account_balance_rounded,
                    color: orgColor(ctx, o),
                    title: OrgSession.nameOf(o),
                    subtitle: _dashboardLine(o),
                    trailing: check(asInt(o['id']) == session!.currentId),
                    onTap: () {
                      Navigator.pop(ctx);
                      switchOrganization(context, asInt(o['id']), session: session);
                    },
                  ),
                ),
              for (final e in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
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
                    padding: const EdgeInsets.only(bottom: AppSpace.xs),
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
                padding: const EdgeInsets.only(top: AppSpace.xs),
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
                  padding: const EdgeInsets.only(top: AppSpace.xs),
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
    final nav = Navigator.of(context, rootNavigator: true);
    closeOrgPages(nav); // the pages of the organization I leave
    ctl.setMode(AppMode.organization, orgId: id);
    nav.pushNamed('/org_member', arguments: id);
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
  const _ContextMark({required this.icon, required this.tone, this.logoUrl});
  final IconData icon;
  final Color tone;
  final String? logoUrl;

  /// The mark's diameter: the icon size [AppIconSize.xl]; with the pill's 8 px padding it reaches the 48 px target.
  static const double size = AppIconSize.xl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // the organization's colour as text-safe ink on the mark's own tint (dark on light, lifted in dark mode)
    final tint = tone.withValues(alpha: c.isDark ? 0.24 : 0.14);
    final ink = c.blockAccentInk(tone, Color.alphaBlend(tint, c.cardBg));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: logoUrl == null || logoUrl!.isEmpty
          ? Icon(icon, size: AppIconSize.md, color: ink)
          : Image.network(logoUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(icon, size: AppIconSize.md, color: ink)),
    );
  }
}
