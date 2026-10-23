// lib/design/context_switcher.dart
//
// THE context switcher — "where am I?" for students and instructors: Personal, or one of my organizations.
//
//   ContextSwitcher            a calm pill in the home header: the current context (icon + name + what waits
//                              elsewhere) → one tap opens the picker. Inside an organization a second, explicit
//                              "Personal" button leaves it in one tap.
//   showContextSwitcherSheet   Personal + every live organization, the current one checked; one tap switches.
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

import '../features/admin/admin_common.dart' show asInt, asMap;
import '../features/org/org_common.dart' show orgColor, orgTypeIcons;
import '../features/org/org_member_dashboard.dart' show orgRolesLine;
import '../features/org/org_ui.dart' show orgNameOf;

/// Feature key that hides the organization side of the home screens (platform kill-switch).
const String kContextSwitchFeature = 'home.org_tab';

bool contextSwitchVisible(AppModeController ctl) => ctl.available && !AppConfig.disableList.contains(kContextSwitchFeature);

/// What waits in every organization except the one open now (badge on the pill).
int pendingElsewhere(AppModeController ctl) {
  if (!ctl.isOrg) return ctl.pendingTotal;
  var n = 0;
  for (final e in ctl.liveEntries) {
    if (asInt(asMap(e['organization'])['id']) != ctl.currentOrgId) n += AppModeController.pendingOf(e);
  }
  return n;
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
        final badge = pendingElsewhere(ctl);
        final canPick = ctl.liveEntries.length > 1 || widget.allowPersonal;

        final pill = Semantics(
          button: true,
          label: '${'ctx_current'.tr}: $label',
          child: Material(
            color: c.cardBg,
            shape: StadiumBorder(side: BorderSide(color: tone.withValues(alpha: 0.35))),
            child: InkWell(
              key: const ValueKey('ctx.pill'),
              customBorder: const StadiumBorder(),
              onTap: canPick ? () => showContextSwitcherSheet(context, allowPersonal: widget.allowPersonal) : null,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(5, 5, 12, 5),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _ContextMark(icon: inOrg ? (orgTypeIcons[org['type']] ?? Icons.account_balance_rounded) : Icons.person_rounded, tone: tone),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (!widget.compact)
                        Text(inOrg ? 'ctx_in_org'.tr : 'ctx_personal_space'.tr,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(10.5, w: FontWeight.w600, c: c.textLight)),
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w800, c: c.textDark)),
                    ]),
                  ),
                  if (badge > 0) ...[const SizedBox(width: 6), _Count(badge, color: c.danger)],
                  if (canPick) ...[const SizedBox(width: 2), Icon(Icons.unfold_more_rounded, size: 18, color: c.textMedium)],
                ]),
              ),
            ),
          ),
        );

        if (!inOrg || !widget.allowPersonal || widget.compact) return pill;
        // Inside an organization: the way back is always one visible tap.
        return Row(mainAxisSize: MainAxisSize.min, children: [
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
                onTap: () => ctl.setMode(AppMode.individual),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.logout_rounded, size: 16, color: c.primary, textDirection: TextDirection.ltr),
                    const SizedBox(width: 6),
                    Text('ctx_personal'.tr, maxLines: 1, style: appText(12.5, w: FontWeight.w800, c: c.primary)),
                  ]),
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// Personal + every live organization; the current one is checked. One tap switches (remembered per user).
Future<void> showContextSwitcherSheet(BuildContext context, {bool allowPersonal = true}) async {
  final ctl = AppModeController.instance;
  await showAppSheet<void>(context, (ctx) {
    final c = ctx.colors;
    Widget check(bool on) => on ? Icon(Icons.check_circle_rounded, color: c.success) : const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              trailing: check(!ctl.isOrg),
              onTap: () {
                Navigator.pop(ctx);
                ctl.setMode(AppMode.individual);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text('ctx_organizations'.tr, style: appText(12, w: FontWeight.w800, c: c.textLight)),
        ),
        for (final e in ctl.liveEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppActionCard(
              key: ValueKey('ctx.sheet.org.${asInt(asMap(e['organization'])['id'])}'),
              icon: orgTypeIcons[asMap(e['organization'])['type']] ?? Icons.account_balance_rounded,
              color: orgColor(ctx, asMap(e['organization'])),
              title: orgNameOf(asMap(e['organization'])),
              subtitle: orgRolesLine(e),
              badge: AppModeController.pendingOf(e),
              trailing: check(ctl.isOrg && asInt(asMap(e['organization'])['id']) == ctl.currentOrgId),
              onTap: () {
                Navigator.pop(ctx);
                ctl.setMode(AppMode.organization, orgId: asInt(asMap(e['organization'])['id']));
              },
            ),
          ),
      ]),
    );
  });
}

class _ContextMark extends StatelessWidget {
  const _ContextMark({required this.icon, required this.tone});
  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: tone),
      );
}

class _Count extends StatelessWidget {
  const _Count(this.n, {required this.color});
  final int n;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Text(n > 99 ? '99+' : '$n', style: appText(11, w: FontWeight.w800, c: context.colors.button.color)),
      );
}
