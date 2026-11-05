// lib/features/org/org_member_parts.dart
//
// Small shared pieces of the organization member screens (member home, member space, "My organization" tab, the
// sheets of the mix), all on the D-180 kit: flat cards (no tinted gradient washes behind text), tokens, one
// type scale. Plain values in, so they are layout-tested (test/ui/of_r2_member_layout_test.dart).
//
//   MemberRow          one tappable row: tinted icon · title · subtitle · count / trailing · chevron
//   MemberNote         a quiet one-line "nothing here" inside a section (a full state uses AppEmpty with an action)
//   MemberSlotTile     a timetable slot: start / end on the leading side, title and where under it, tags at the end
//   memberStatusTone   the badge tone of a request / complaint status
//   MemberStatusBadge  AppStatusBadge from a status code
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';


/// The badge tone of an organization status code (request, complaint, join, organization).
AppTone memberStatusTone(String? s) => switch (s) {
      'approved' || 'active' || 'published' || 'resolved' || 'open' => AppTone.success,
      'pending' || 'submitted' || 'in_review' || 'waiting' || 'draft' => AppTone.warning,
      'rejected' || 'suspended' || 'closed' || 'archived' => AppTone.danger,
      'in_progress' => AppTone.info,
      _ => AppTone.neutral,
    };

/// A status code drawn as the kit's badge ([label] overrides the standard text of the code).
class MemberStatusBadge extends StatelessWidget {
  const MemberStatusBadge(this.status, {super.key, this.label, this.dense = true});
  final String status;
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) =>
      AppStatusBadge(label: label ?? statusLabel(status), tone: memberStatusTone(status), dense: dense);
}

/// One row of a list on a member screen: a tinted icon, the title (two lines at most), a quiet subtitle, then a count
/// badge, an optional [trailing] widget and the chevron when it opens something.
class MemberRow extends StatelessWidget {
  const MemberRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone,
    this.count = 0,
    this.countTone = AppTone.danger,
    this.trailing,
    this.onTap,
    this.leading,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// The icon's colour (default: the primary); a muted row passes `c.textLight`.
  final Color? tone;
  final int count;
  final AppTone countTone;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Replaces the icon square (a logo, an avatar).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = tone ?? c.primary;
    final sub = subtitle;
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.sm),
      onTap: onTap,
      child: Row(children: [
        leading ??
            Container(
              width: AppTouch.min - AppSpace.xxs,
              height: AppTouch.min - AppSpace.xxs,
              decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
              child: Icon(icon, size: AppIconSize.md, color: appInk(context, col)),
            ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            if (sub != null && sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ),
          ]),
        ),
        if (count > 0) ...[AppSpace.gapXs, AppCountBadge(count: count, tone: countTone)],
        if (trailing != null) ...[
          AppSpace.gapXs,
          // a long status text shrinks instead of squeezing the title or overflowing a narrow phone
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerEnd, child: trailing),
          ),
        ],
        if (onTap != null) ...[AppSpace.gapXs, Icon(Icons.chevron_right_rounded, size: AppIconSize.lg, color: c.textLight)],
      ]),
    );
  }
}

/// A quiet line for an empty part of a section ("No open forms right now"). A whole empty page uses AppEmpty.
class MemberNote extends StatelessWidget {
  const MemberNote(this.text, {super.key, this.icon = Icons.info_outline_rounded});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: AppIconSize.md, color: c.textLight),
        AppSpace.gapXs,
        Expanded(child: Text(text, style: AppType.body(context).copyWith(color: c.textMedium))),
      ]),
    );
  }
}

/// A timetable slot: the start (and end) time in a small block on the leading side, then the title and where, with
/// the tags (lab · special · changed) under them.
class MemberSlotTile extends StatelessWidget {
  const MemberSlotTile({super.key, required this.start, required this.end, required this.title, this.where = '', this.tags = const [], this.accent, this.onTap, this.cancelled = false});
  final String start, end, title, where;

  /// A cancelled slot: struck through and muted.
  final bool cancelled;
  final List<Widget> tags;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = cancelled ? c.textLight : (accent ?? c.primary);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      onTap: onTap,
      child: Row(children: [
        Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          decoration: BoxDecoration(color: col.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(start, maxLines: 1, style: AppType.label(context).copyWith(color: appInk(context, col)))),
            if (end.isNotEmpty) FittedBox(fit: BoxFit.scaleDown, child: Text(end, maxLines: 1, style: AppType.meta(context))),
          ]),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.row(context).copyWith(
                    decoration: cancelled ? TextDecoration.lineThrough : null, color: cancelled ? c.textLight : null)),
            if (where.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(where, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ),
            if (tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: tags),
              ),
          ]),
        ),
      ]),
    );
  }
}
