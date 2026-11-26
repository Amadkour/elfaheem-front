// lib/features/profile/teacher/t2b_account.dart
//
// The teacher's "حسابي" (redesign T2b, Tea2Account `screen=account`): the identity hero (the avatar with its verified
// mark, the name, the chips, Edit account, Share on wide screens, the figures), four shortcut cards riding up over
// its lower edge, then the sections' cards (two columns on wide screens), the exits and the version line. Plain
// values only: ProfileScreen builds every row (with its kill switch) and hands them in.
//
//   T2bAccountPage(hero: T2bAccountHero(...), shortcuts: [T2bShortcut(...)], sections: [(rows, AppSettingsGroup)],
//                  exits: T2bAccountExits(onLogout:, onDelete:), footer: const AppVersionLine())
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_education_app/features/profile/teacher/t2b_parts.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

export 'package:flutter_education_app/design/app_kit.dart' show AppAccent, AppHeroStat;

/// One shortcut card under the hero.
class T2bShortcut {
  const T2bShortcut({
    required this.id,
    required this.accent,
    required this.icon,
    required this.title,
    required this.onTap,
    this.meta,
    this.badge,
    this.featureKey,
  });

  final String id;
  final AppAccent accent;
  final IconData icon;
  final String title;
  final String? meta;

  /// A small pill on the card's end corner ("3 requests"); null for none.
  final String? badge;
  final VoidCallback onTap;

  /// The kill switch; a switched-off card leaves no hole.
  final String? featureKey;
}

/// The identity band: avatar, name, chips, the actions and the figures.
class T2bAccountHero extends StatelessWidget {
  const T2bAccountHero({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.verified = false,
    this.chips = const [],
    this.stats = const [],
    this.onEdit,
    this.onShare,
  });

  final String name, imageUrl;
  final bool verified;

  /// Short facts beside the name: (icon, text, left-to-right). The first is the strongest.
  final List<(IconData?, String, bool)> chips;
  final List<AppHeroStat> stats;
  final VoidCallback? onEdit, onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.mobile;
    final ride = AppHeroOverlap.defaultOverlap(context);
    final avatar = _T2bAvatar(name: name, imageUrl: imageUrl, verified: verified, size: AppHero.leadingSize(wide));
    final chipRow = Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (final (icon, text, ltr) in chips) _HeroChip(icon: icon, text: text, ltr: ltr),
    ]);
    final edit = onEdit == null
        ? null
        : AppButton.primary(
            key: const ValueKey('profile.edit'), label: 'update_account'.tr, icon: Icons.edit_outlined, onPressed: onEdit);
    final share = onShare == null || !wide
        ? null
        : T2bHeroButton(key: const ValueKey('profile.share'), label: 'profile_share'.tr, icon: Icons.share_outlined, onTap: onShare);
    final buttons = Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [?edit, ?share]);
    final title = Semantics(
      header: true,
      child: Text(name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (wide ? AppType.display(context) : AppType.headline(context)).copyWith(color: c.onHero)),
    );
    final head = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      avatar,
      SizedBox(width: wide ? AppSpace.md : AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          title,
          if (chips.isNotEmpty) ...[const SizedBox(height: AppSpace.xs), chipRow],
        ]),
      ),
      if (wide && (edit != null || share != null)) ...[const SizedBox(width: AppSpace.md), buttons],
    ]);
    return AppHeroSurface(
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          wide ? AppSpace.lg : AppSpace.md,
          wide ? AppHeroMetrics.padTopWide : AppHeroMetrics.padTopPhone + AppSpace.xs,
          wide ? AppSpace.lg : AppSpace.md,
          AppHeroMetrics.padBottom(ride),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          head,
          if (!wide && edit != null) ...[
            const SizedBox(height: AppSpace.md),
            Align(alignment: AlignmentDirectional.centerStart, child: buttons),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(widthFactor: wide ? .6 : 1, child: T2bHeroFigures(stats: stats)),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The avatar in a rounded square on a glass ring, the verified mark at its bottom corner.
class _T2bAvatar extends StatelessWidget {
  const _T2bAvatar({required this.name, required this.imageUrl, required this.verified, required this.size});

  final String name, imageUrl;
  final bool verified;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = AppAreaScope.of(context);
    final initial = name.trim().isEmpty ? '' : name.trim().characters.first;
    final radius = BorderRadius.circular(AppRadius.tile);
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [set.a, set.b]),
        borderRadius: radius,
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.focus),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isNotEmpty
          ? SizedBox.expand(child: AppNetworkImage(url: imageUrl))
          : Text(initial, style: AppType.headline(context).copyWith(color: c.onHero)),
    );
    return Semantics(
      image: true,
      label: verified ? '$name, ${'t2_acc_verified'.tr}' : name,
      excludeSemantics: true,
      child: Stack(clipBehavior: Clip.none, children: [
        face,
        if (verified)
          PositionedDirectional(
            start: -AppSpace.xxs,
            bottom: -AppSpace.xxs,
            child: Container(
              width: AppSpace.lg,
              height: AppSpace.lg,
              decoration: BoxDecoration(
                color: c.success,
                shape: BoxShape.circle,
                border: Border.all(color: c.kit.deep, width: AppBorder.focus),
              ),
              child: Icon(Icons.check_rounded, size: AppIconSize.xs, color: appInkOnFill(context, c.success)),
            ),
          ),
      ]),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.text, this.icon, this.ltr = false});

  final IconData? icon;
  final String text;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs + 2),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: AppIconSize.xs, color: c.onHero),
          const SizedBox(width: AppSpace.xxs),
        ],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: ltr ? TextDirection.ltr : null,
              style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A tinted shortcut card: its accent's icon well, the title, one line, and an optional pill on the end corner.
class T2bShortcutCard extends StatelessWidget {
  const T2bShortcutCard({super.key, required this.item});

  final T2bShortcut item;

  @override
  Widget build(BuildContext context) {
    final tone = context.colors.kit.accent(item.accent);
    final badge = item.badge;
    Widget card = Semantics(
      button: true,
      label: [item.title, ?item.meta, ?badge].join(', '),
      excludeSemantics: true,
      child: AppCard(
        key: ValueKey('profile.shortcut.${item.id}'),
        variant: AppCardVariant.tint,
        tone: tone,
        onTap: item.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppIconBox(icon: item.icon, tone: tone, solid: true),
            const Spacer(),
            if (badge != null) Flexible(child: AppStatusBadge(label: appDigits(badge), dense: true)),
          ]),
          const SizedBox(height: AppSpace.sm),
          Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
          if (item.meta != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(appDigits(item.meta!), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ]),
      ),
    );
    if (item.featureKey != null) card = ParentComponent(featureKey: item.featureKey!, child: card);
    return card;
  }
}

/// The account's exits at the page's end: Log out and Delete account (each caller confirms first).
class T2bAccountExits extends StatelessWidget {
  const T2bAccountExits({super.key, this.onLogout, this.onDelete});

  final VoidCallback? onLogout, onDelete;

  @override
  Widget build(BuildContext context) {
    if (onLogout == null && onDelete == null) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
      if (onLogout != null)
        AppButton.danger(
            key: const ValueKey('profile.hero.logout'),
            label: 'logout'.tr,
            icon: DirIcons.logout,
            dangerOutline: true,
            onPressed: onLogout),
      if (onDelete != null)
        AppButton.ghost(
            key: const ValueKey('profile.hero.delete'),
            label: 'delete_account_title'.tr,
            icon: Icons.delete_forever_outlined,
            onPressed: onDelete),
    ]);
  }
}

/// The page: the hero, the shortcut cards over its edge, the sections (two balanced columns from 900 px), the exits.
class T2bAccountPage extends StatelessWidget {
  const T2bAccountPage({
    super.key,
    required this.hero,
    required this.shortcuts,
    required this.sections,
    this.exits,
    this.footer,
    this.title,
    this.onRefresh,
  });

  final Widget hero;
  final List<T2bShortcut> shortcuts;

  /// (row count, the section's card) in page order; the count balances the two columns.
  final List<(int, Widget)> sections;
  final Widget? exits, footer;
  final String? title;
  final Future<void> Function()? onRefresh;

  static const double _twoColumnsFrom = 900;

  @override
  Widget build(BuildContext context) {
    final cards = LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= _twoColumnsFrom ? 4 : 2;
      final items = [for (final s in shortcuts) T2bShortcutCard(item: s)];
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < items.length; r += perRow) ...[
          if (r > 0) const SizedBox(height: AppSpace.sm),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = r; i < r + perRow; i++) ...[
                if (i > r) const SizedBox(width: AppSpace.sm),
                Expanded(child: i < items.length ? items[i] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ],
      ]);
    });
    final body = LayoutBuilder(builder: (context, box) {
      final two = box.maxWidth >= _twoColumnsFrom;
      if (!two) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final s in sections) s.$2]);
      }
      final cols = <List<Widget>>[[], []];
      final h = [0.0, 0.0];
      for (final s in sections) {
        final k = h[0] <= h[1] ? 0 : 1;
        cols[k].add(s.$2);
        h[k] += 1.5 + s.$1;
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cols[0])),
        const SizedBox(width: AppSpace.lg),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cols[1])),
      ]);
    });
    return T2HeroPage(
      pageKey: const ValueKey('profile'),
      title: title,
      onRefresh: onRefresh,
      hero: hero,
      children: [
        if (shortcuts.isNotEmpty) cards,
        body,
        ?exits,
        ?footer,
      ],
    );
  }
}
