// lib/features/shared/profile/profile_hero.dart — the Account page's hero block (Warm Editorial, D-613 / D-622, D-713).
//
//   ProfileHero(name:, role:, email:, username:, imageUrl:, heroTag:, onEdit:, onShare:, stats: [ProfileHeroStat(…)])
//
// The page's ONE tinted block, the identity tone (a soft primary gradient, D-713): the avatar on a paper ring, the
// name in the editorial face, the role / @username / e-mail chips, up to three figures the page already holds (no
// request of its own) and the two actions, "Update account" and, for a shareable profile, "Share".
// Phones stack it centred with the actions side by side under it; from [wideFrom] it reads as a masthead:
// avatar · name, chips and figures · the actions.
// Plain values only (test/ui/profile_hero_layout_test.dart). Kill switches: `profile.header` (the whole block),
// `auth.username` (the @username chip).
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_motion_kit.dart' show AppTilt, AppPressScale;
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/parent_component.dart';

/// One figure in the hero (students, courses, rating): a value the page already has.
@immutable
class ProfileHeroStat {
  const ProfileHeroStat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value, label;
}

class ProfileHero extends StatelessWidget {
  const ProfileHero({
    super.key,
    required this.name,
    this.role = '',
    this.email = '',
    this.username = '',
    this.imageUrl = '',
    this.heroTag,
    this.onEdit,
    this.onShare,
    this.stats = const [],
  });

  final String name, role, email, imageUrl;

  /// The @username without the "@" ('' = none).
  final String username;
  final String? heroTag;

  /// Opens "Update account" (the avatar's camera badge and the button).
  final VoidCallback? onEdit;

  /// Shares the public profile link (null = no shareable profile: no button).
  final VoidCallback? onShare;

  /// Up to three figures under the chips (more are ignored).
  final List<ProfileHeroStat> stats;

  /// From this block width the hero is a masthead (one row) instead of a centred stack.
  static const double wideFrom = 640;

  /// The avatar's side and its paper ring.
  static const double avatar = AppSettingsHeader.avatar;

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: 'profile.header',
        child: RepaintBoundary(
          child: AppTilt(
            radius: AppRadius.block,
            maxTilt: 2.5,
            glare: true,
            child: AppBlock(
              tone: AppBlockTone.identity,
              hero: true,
              child: LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth >= wideFrom)),
            ),
          ),
        ),
      );

  Widget _body(BuildContext context, bool wide) {
    final b = AppBlock.colorsOf(context);
    final chips = Wrap(
      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        if (role.isNotEmpty) _Chip(icon: Icons.verified_user_rounded, text: appRoleLabel(role), strong: true),
        if (username.isNotEmpty)
          ParentComponent(featureKey: 'auth.username', child: _Chip(icon: Icons.person_pin_rounded, text: '@$username', ltr: true)),
        if (email.isNotEmpty) _Chip(icon: Icons.alternate_email_rounded, text: email, ltr: true),
      ],
    );
    final nameText = Semantics(
      header: true,
      child: Text(
        name,
        textAlign: wide ? TextAlign.start : TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: b.ink),
      ),
    );
    final shown = stats.take(3).toList();
    final figures = shown.isEmpty
        ? null
        : Wrap(
            alignment: wide ? WrapAlignment.start : WrapAlignment.center,
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [for (final s in shown) _Figure(stat: s)],
          );
    final edit = onEdit == null
        ? null
        : AppButton.primary(
            label: wide || onShare == null ? 'update_account'.tr : 'profile_edit_short'.tr,
            tooltip: 'update_account'.tr,
            icon: Icons.edit_rounded,
            onPressed: onEdit,
            size: AppButtonSize.sm,
            expand: true);
    final share = onShare == null
        ? null
        : AppButton.secondary(
            label: 'profile_share'.tr, icon: Icons.ios_share_rounded, onPressed: onShare, size: AppButtonSize.sm, expand: true);
    final face = ProfileAvatar(name: name, imageUrl: imageUrl, heroTag: heroTag, onEdit: onEdit);
    final Widget content;
    if (wide) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        face,
        const SizedBox(width: AppSpace.lg),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            nameText,
            const SizedBox(height: AppSpace.sm),
            chips,
            if (figures != null) ...[const SizedBox(height: AppSpace.md), figures],
          ]),
        ),
        if (edit != null || share != null) ...[
          const SizedBox(width: AppSpace.lg),
          IntrinsicWidth(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ?edit,
              if (edit != null && share != null) const SizedBox(height: AppSpace.xs),
              ?share,
            ]),
          ),
        ],
      ]);
    } else {
      content = Column(children: [
        face,
        const SizedBox(height: AppSpace.md),
        nameText,
        const SizedBox(height: AppSpace.sm),
        chips,
        if (figures != null) ...[const SizedBox(height: AppSpace.md), figures],
        if (edit != null || share != null) ...[
          const SizedBox(height: AppSpace.md),
          Row(children: [
            if (edit != null) Expanded(child: edit),
            if (edit != null && share != null) const SizedBox(width: AppSpace.xs),
            if (share != null) Expanded(child: share),
          ]),
        ],
      ]);
    }
    return SizedBox(width: double.infinity, child: content);
  }
}

/// A figure on the block: a paper plate with the value in the figure face and its label.
class _Figure extends StatelessWidget {
  const _Figure({required this.stat});
  final ProfileHeroStat stat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // a paper plate over the identity tint (opaque, so every ink below is checked against what is really there)
    final plate = Color.alphaBlend(c.cardBg.withValues(alpha: c.isDark ? 0.45 : 0.8), c.blockIdentity);
    return Semantics(
      label: '${stat.value} ${stat.label}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xs, AppSpace.md, AppSpace.xs),
        decoration: BoxDecoration(
          color: plate,
          borderRadius: AppRadius.chipAll,
          border: Border.all(color: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.14), width: AppBorder.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(stat.icon, size: AppIconSize.lg, color: c.blockAccentInk(c.isDark ? c.textDark : c.primary, plate)),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.figure(context).copyWith(color: c.blockAccentInk(c.textDark, plate))),
              Text(stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: c.blockAccentInk(c.textMedium, plate))),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The avatar on its paper ring (96 px), the initial in the editorial face when there is no picture, and with
/// [onEdit] the primary camera badge (the whole avatar is the button). Shared by the Account hero and the public page.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, required this.imageUrl, this.heroTag, this.onEdit});

  final String name, imageUrl;
  final String? heroTag;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first.toUpperCase();
    final box = Container(
      width: ProfileHero.avatar,
      height: ProfileHero.avatar,
      padding: const EdgeInsets.all(AppSettingsHeader.ring),
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
      child: ClipOval(
        child: imageUrl.isNotEmpty
            ? AppNetworkImage(url: imageUrl, heroTag: heroTag ?? 'profile-user-$name')
            : ColoredBox(
                color: b.surface,
                child: Center(
                  child: Text(initial.isEmpty ? '?' : initial,
                      style: AppType.display(context).copyWith(color: b.accentInk(c.primary))),
                ),
              ),
      ),
    );
    if (onEdit == null) return box;
    return Semantics(
      button: true,
      label: 'update_account'.tr,
      child: AppPressScale(
        child: GestureDetector(
          onTap: onEdit,
          behavior: HitTestBehavior.opaque,
          child: Stack(clipBehavior: Clip.none, children: [
            box,
            PositionedDirectional(
              bottom: 0,
              end: 0,
              child: Container(
                width: AppIconSize.xl,
                height: AppIconSize.xl,
                decoration: BoxDecoration(
                  color: c.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.cardBg, width: AppBorder.focus),
                ),
                child: Icon(Icons.photo_camera_rounded, size: AppIconSize.sm, color: c.onHero),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// An identity chip on the block: paper, a warm hairline, the text flexes (ellipsis) instead of clipping.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.ltr = false, this.strong = false});

  final IconData icon;
  final String text;

  /// The role chip: a primary tint with primary ink, so the role reads first.
  final bool strong;

  /// An e-mail or a @username reads left to right in Arabic too.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = Color.alphaBlend(c.primary.withValues(alpha: c.isDark ? 0.30 : 0.12), c.cardBg);
    final ink = c.blockAccentInk(c.isDark ? c.textDark : c.primary, fill);
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: strong ? Color.alphaBlend(c.primary.withValues(alpha: c.isDark ? 0.30 : 0.12), c.cardBg) : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: strong ? c.primary.withValues(alpha: 0.35) : c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.sm, color: strong ? ink : c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: AppType.label(context).copyWith(color: strong ? ink : c.textDark)),
        ),
      ]),
    );
  }
}
