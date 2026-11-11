// lib/features/shared/profile/profile_hero.dart — the Account page's hero block (Warm Editorial, D-613 / D-622).
//
//   ProfileHero(name:, role:, email:, username:, imageUrl:, heroTag:, onEdit:)
//
// The page's ONE tinted block (peach) and its memorable element: the person's initial set as a large editorial
// letter that bleeds off the block's end edge (a quiet monogram, Markazi in the block's faint ink, shifting a little
// against the tilt), the avatar on a paper ring, the name in the editorial face and the identity chips on paper.
// Phones stack it centred; from [wideFrom] it reads as a masthead: avatar · name and chips · "Update account".
// Plain values only (test/ui/profile_hero_layout_test.dart). Kill switches: `profile.header` (the whole block),
// `auth.username` (the @username chip).
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/display/app_fonts.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_motion_kit.dart' show AppTilt, AppTiltLayer, AppPressScale;
import '../../../utils/widget/app_network_image.dart';
import '../../../utils/widget/parent_component.dart';

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
  });

  final String name, role, email, imageUrl;

  /// The @username without the "@" ('' = none).
  final String username;
  final String? heroTag;

  /// Opens "Update account" (the avatar's camera badge and, on wide blocks, the button).
  final VoidCallback? onEdit;

  /// From this block width the hero is a masthead (one row) instead of a centred stack.
  static const double wideFrom = 640;

  /// The avatar's side and its paper ring.
  static const double avatar = AppSettingsHeader.avatar;

  /// How much larger than the display face the monogram is drawn.
  static const double _monogramScale = 5.5;

  /// How much of the block's ink the monogram carries (a watermark that never competes with the name).
  static const double _monogramInk = 0.07;

  String get _initial => name.trim().isEmpty ? '' : name.trim().characters.first.toUpperCase();

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: 'profile.header',
        child: RepaintBoundary(
          child: AppTilt(
            radius: AppRadius.block,
            maxTilt: 2.5,
            glare: true,
            child: AppBlock(
              tone: AppBlockTone.peach,
              hero: true,
              child: LayoutBuilder(builder: (context, box) => _body(context, box.maxWidth >= wideFrom)),
            ),
          ),
        ),
      );

  Widget _body(BuildContext context, bool wide) {
    final b = AppBlock.colorsOf(context);
    final display = AppType.display(context);
    final monogram = _initial.isEmpty
        ? const SizedBox.shrink()
        : PositionedDirectional(
            // the letter rises from the block's bottom edge at its end: its foot bleeds off, its top stays in
            end: -AppSpace.lg,
            bottom: -(AppSpace.xxl + AppSpace.xl),
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: AppTiltLayer(
                  depth: 1.5,
                  child: Text(
                    _initial,
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: display.copyWith(
                      fontFamily: AppFonts.editorialFamily,
                      fontFamilyFallback: AppFonts.editorialFallback,
                      fontSize: (display.fontSize ?? AppSpace.xl) * _monogramScale,
                      height: 1,
                      // a watermark, not a second heading: a few percent of the ink over the block
                      color: Color.lerp(b.surface, b.ink, _monogramInk),
                    ),
                  ),
                ),
              ),
            ),
          );
    final chips = Wrap(
      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      children: [
        if (role.isNotEmpty) _Chip(icon: Icons.verified_user_rounded, text: appRoleLabel(role)),
        if (email.isNotEmpty) _Chip(icon: Icons.alternate_email_rounded, text: email, ltr: true),
        if (username.isNotEmpty)
          ParentComponent(featureKey: 'auth.username', child: _Chip(icon: Icons.person_pin_rounded, text: '@$username', ltr: true)),
      ],
    );
    final nameText = Semantics(
      header: true,
      child: Text(
        name,
        textAlign: wide ? TextAlign.start : TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (wide ? display : AppType.headline(context)).copyWith(color: b.ink),
      ),
    );
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
          ]),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: AppSpace.lg),
          AppButton.secondary(label: 'update_account'.tr, icon: Icons.edit_rounded, onPressed: onEdit),
        ],
      ]);
    } else {
      content = Column(children: [
        face,
        const SizedBox(height: AppSpace.md),
        nameText,
        const SizedBox(height: AppSpace.sm),
        chips,
      ]);
    }
    return Stack(clipBehavior: Clip.none, children: [
      monogram,
      SizedBox(width: double.infinity, child: content),
    ]);
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
  const _Chip({required this.icon, required this.text, this.ltr = false});

  final IconData icon;
  final String text;

  /// An e-mail or a @username reads left to right in Arabic too.
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: AppIconSize.xl),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: AppIconSize.sm, color: c.textMedium),
        const SizedBox(width: AppSpace.xs),
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: AppType.label(context).copyWith(color: c.textDark)),
        ),
      ]),
    );
  }
}
