// lib/features/profile/student_profile_view.dart
//
// The student's "حسابي" (redesign phase 2, Stu2Profile `screen=profile`): plain values in slots, no provider, so the
// layout harness and the review renders draw it as it is. `ProfileScreen` fills the slots for a student; the other
// roles keep their own page.
//
//   hero          the identity band: the initial (never a photo for a student, RULES §2), the name, @username and
//                 "عدّل"
//   shortcuts     four tinted cards riding up over the hero (grades, wallet, payments, favourites), dealt in (M5)
//   menuA, menuB  two cards of rows (public profile, downloads, rewards, parent link · notifications, display,
//                 security, help); side by side from 900 px
//   advanced      "إعدادات متقدمة": one folded card with everything else the page keeps (study details, language,
//                 dark mode, the assistant, data copy, certificate check, terms, privacy, about, accounts, …)
//   exits         sign out and delete the account, quiet rows at the end
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/profile/sd_area.dart';

/// One shortcut card: its accent, icon, title and one line.
class SdShortcut {
  const SdShortcut({required this.id, required this.accent, required this.icon, required this.title, this.meta, required this.onTap, this.featureKey});

  final String id;
  final AppAccent accent;
  final IconData icon;
  final String title;
  final String? meta;
  final VoidCallback onTap;

  /// The kill switch; a switched-off card leaves no hole.
  final String? featureKey;
}

/// The identity band of the student's account page.
class StudentProfileHero extends StatelessWidget {
  const StudentProfileHero({super.key, required this.name, this.username, this.onEdit});

  final String name;
  final String? username;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '؟' : name.trim().characters.first;
    final user = username == null || username!.isEmpty ? null : '@$username';
    return AppHero(
      title: name.trim().isEmpty ? 'sd_profile_title'.tr : name,
      subtitle: user,
      leading: _Avatar(initial: initial, onEdit: onEdit),
      actions: [
        if (onEdit != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              key: const ValueKey('profile.edit'),
              label: 'sd_profile_edit'.tr,
              icon: Icons.edit_outlined,
              size: AppButtonSize.sm,
              onPressed: onEdit,
            ),
          ),
      ],
      icon: Icons.person_outline_rounded,
    );
  }
}

/// The initial in a soft square with the area gradient, and a small pencil at its bottom corner.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial, this.onEdit});

  final String initial;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    return LayoutBuilder(builder: (context, box) {
      final side = box.maxWidth;
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [set.a, set.b]),
            borderRadius: BorderRadius.circular(AppRadius.tile),
            border: Border.all(color: c.heroGlassBorder, width: AppBorder.focus),
          ),
          child: Text(initial, style: AppType.headline(context).copyWith(color: c.onHero)),
        ),
        if (onEdit != null)
          PositionedDirectional(
            start: -AppSpace.xxs,
            bottom: -AppSpace.xxs,
            child: Container(
              width: AppIconSize.lg,
              height: AppIconSize.lg,
              decoration: BoxDecoration(color: c.cardBg, shape: BoxShape.circle, border: Border.all(color: set.a, width: AppBorder.strong)),
              child: Icon(Icons.edit_outlined, size: AppIconSize.xs, color: set.ink),
            ),
          ),
      ]);
    });
  }
}

class StudentProfileView extends StatelessWidget {
  const StudentProfileView({
    super.key,
    required this.hero,
    required this.shortcuts,
    required this.menuA,
    required this.menuB,
    required this.advanced,
    this.exits = const [],
    this.footer,
    this.extra,
    this.advancedOpen = false,
  });

  final Widget hero;
  final List<SdShortcut> shortcuts;
  final List<Widget> menuA, menuB, advanced, exits;

  /// Under the cards: recommendations (personal accounts) and the version line.
  final Widget? footer;

  /// Above the menus (the recommendations).
  final Widget? extra;

  /// Starts with "إعدادات متقدمة" open (the review renders, `adv=1`).
  final bool advancedOpen;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final s in shortcuts) if (s.featureKey == null || !AppConfig.disableList.contains(s.featureKey)) s];
    return SdHeroList(hero: hero, width: AppWidth.content, children: [
      if (shown.isNotEmpty) _ShortcutGrid(items: shown),
      ?extra,
      const SizedBox(height: AppSpace.md),
      LayoutBuilder(builder: (context, box) {
        final a = SdRowsCard(children: menuA);
        final b = SdRowsCard(children: menuB);
        if (box.maxWidth < _twoFrom) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: AppSpace.md), b]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: AppSpace.md),
          Expanded(child: b),
        ]);
      }),
      const SizedBox(height: AppSpace.md),
      _AdvancedCard(initiallyOpen: advancedOpen, children: advanced),
      if (exits.isNotEmpty) ...[const SizedBox(height: AppSpace.md), SdRowsCard(children: exits)],
      if (footer != null) ...[const SizedBox(height: AppSpace.lg), footer!],
    ]);
  }

  static const double _twoFrom = 900;
}

/// The shortcut cards: two per row on a phone, four from 700 px.
class _ShortcutGrid extends StatelessWidget {
  const _ShortcutGrid({required this.items});

  final List<SdShortcut> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= Breakpoints.mobile ? 4 : 2;
        const gap = AppSpace.sm;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final (i, s) in items.indexed)
            SizedBox(width: w, child: AppDeal(index: i, group: 'profile.shortcuts', child: _ShortcutCard(item: s))),
        ]);
      });
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({required this.item});

  final SdShortcut item;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.kit.accent(item.accent);
    return Semantics(
      button: true,
      label: item.meta == null ? item.title : '${item.title}, ${item.meta}',
      excludeSemantics: true,
      child: AppCard(
        key: ValueKey('profile.shortcut.${item.id}'),
        variant: AppCardVariant.tint,
        tone: tone,
        onTap: item.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppIconBox(icon: item.icon, tone: tone, solid: true),
          const SizedBox(height: AppSpace.sm),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
          if (item.meta != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(appDigits(item.meta!), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ]),
      ),
    );
  }
}

/// A card of settings rows parted by hairlines (the rows draw their own padding); rows a kill switch hides leave no
/// line behind because each row is its own widget.
class SdRowsCard extends StatelessWidget {
  const SdRowsCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );
}

/// A row tinted in one accent: an [AppSettingsTile] (or a tile that builds one) whose icon well takes the colour.
class SdAccentRow extends StatelessWidget {
  const SdAccentRow({super.key, required this.accent, required this.child});

  final AppAccent accent;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AppSettingsAccent(color: context.colors.kit.accent(accent).color, child: child);
}

/// "إعدادات متقدمة": folded by default, with one line of what is inside.
class _AdvancedCard extends StatefulWidget {
  const _AdvancedCard({required this.children, this.initiallyOpen = false});

  final List<Widget> children;
  final bool initiallyOpen;

  @override
  State<_AdvancedCard> createState() => _AdvancedCardState();
}

class _AdvancedCardState extends State<_AdvancedCard> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSettingsTile(
            key: const ValueKey('profile.advanced'),
            icon: Icons.tune_rounded,
            label: 'sd_profile_advanced'.tr,
            subtitle: 'sd_profile_advanced_sub'.tr,
            trailing: AnimatedRotation(
              turns: _open ? .5 : 0,
              duration: AppMotion.of(context).base,
              child: Icon(Icons.expand_more_rounded, color: context.colors.textLight),
            ),
            onTap: () => setState(() => _open = !_open),
          ),
          AnimatedSize(
            duration: AppMotion.of(context).base,
            alignment: AlignmentDirectional.topCenter,
            child: _open
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: context.colors.kit.line),
                    ...widget.children,
                  ])
                : const SizedBox(width: double.infinity),
          ),
        ]),
      );
}
