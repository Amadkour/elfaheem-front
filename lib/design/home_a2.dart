// lib/design/home_a2.dart
//
// THE home skeleton of every role (D-1100, the owner's layout A + style A2): one shape, so the student, the
// instructor and every organization persona read their home the same way.
//
//   HomeGreetingRow  the greeting at a modest size and ONE real line under it ("2 votes and 3 requests wait" /
//                    "Nothing waiting · next session Sunday 10:00"); at the row's end the workspace / role switcher as
//                    a compact pill and the role's ONE primary action. No dark banner, no avatar circle, no clock chip.
//   HomeStatRow      the four AppStatCards: one row of four on a wide page, 2 × 2 below 720 px
//   HomeQueueCard    the work queue (Needs attention · Tasks · Up next): ALWAYS a card, the screen's ONE highlighted
//                    card; its empty state is HomeCaughtUp ("You're all caught up" + the next thing), never a bare
//                    title over nothing
//   HomeCaughtUp     the queue's calm empty state
//   HomeSideCard     a compact side card (Today, Inbox, My departments): title, optional action, body
//   HomeA2Layout     greeting · stats · [queue 2fr | side 1fr] · the full-width content below. A side with nothing
//                    to say gives the queue the whole width (no empty column); a phone stacks queue first.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/home_kit.dart' show HomeHeader, homeIsWide;

/// The width below which the four counts wrap into 2 × 2.
const double kHomeStatRowMin = 720;

/// The greeting row: "Good morning, Ahmed" + one line, the switcher pill and the ONE primary action at its end.
class HomeGreetingRow extends StatelessWidget {
  const HomeGreetingRow({super.key, required this.name, this.subline, this.trailing = const []});

  final String name;

  /// The one line under the greeting; null / empty = none.
  final String? subline;

  /// The switcher pill and the primary action (in that order); wraps under the greeting on a narrow row.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        header: true,
        child: Text(HomeHeader.greetingLine(name), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.pageTitle(context)),
      ),
      if (subline != null && subline!.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(subline!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
      ],
    ]);
    return LayoutBuilder(builder: (context, box) {
      if (trailing.isEmpty) return text;
      final tools = Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: trailing,
      );
      if (box.maxWidth < kHomeStatRowMin) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          text,
          const SizedBox(height: AppSpace.sm),
          tools,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: text),
        const SizedBox(width: AppSpace.md),
        Flexible(child: Align(alignment: AlignmentDirectional.centerEnd, child: tools)),
      ]);
    });
  }
}

/// The four counts: one row of four from [kHomeStatRowMin], 2 × 2 below it (an odd last card spans its row).
class HomeStatRow extends StatelessWidget {
  const HomeStatRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= kHomeStatRowMin ? children.length.clamp(1, 4) : (children.length == 1 ? 1 : 2);
      final rows = (children.length / cols).ceil();
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) AppSpace.gapSm,
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < cols && r * cols + i < children.length; i++) ...[
                if (i > 0) AppSpace.gapSm,
                Expanded(child: children[r * cols + i]),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}

/// The queue's calm empty state: a check in a tinted disc, "You're all caught up", and the next thing (a line or an
/// action) so the card still says something useful.
class HomeCaughtUp extends StatelessWidget {
  const HomeCaughtUp({super.key, this.title, this.message, this.actionLabel, this.onAction});

  /// Null = "You're all caught up".
  final String? title;

  /// The next thing ("Next session Sunday 10:00"); null = the generic hint.
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(children: [
        Container(
          width: AppIconSize.hero,
          height: AppIconSize.hero,
          decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, color: appInk(context, c.success), size: AppIconSize.md),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title ?? 'home_caught_up'.tr, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            const SizedBox(height: AppBorder.focus),
            Text(message ?? 'home_caught_up_hint'.tr,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
        if (actionLabel != null && onAction != null) ...[
          AppSpace.gapSm,
          _HeadAction(label: actionLabel!, onTap: onAction!),
        ],
      ]),
    );
  }
}

/// A card's head: the title (with a count chip) and an optional text action at its end.
class _CardHead extends StatelessWidget {
  const _CardHead({required this.title, this.icon, this.count, this.subtitle, this.actionLabel, this.onAction, this.chip});
  final String title;
  final IconData? icon;
  final int? count;
  final String? subtitle, actionLabel;
  final VoidCallback? onAction;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      if (icon != null) ...[
        Icon(icon, size: AppIconSize.md, color: c.primary),
        const SizedBox(width: AppSpace.xs),
      ],
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
          if (subtitle != null && subtitle!.isNotEmpty)
            Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          // the fact chip sits under the title: beside it, a 320 px phone had no room for the title and the action
          if (chip != null) ...[const SizedBox(height: AppSpace.xxs), chip!],
        ]),
      ),
      if (count != null && count! > 0) ...[
        const SizedBox(width: AppSpace.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppBorder.focus),
          decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text('$count', style: AppType.meta(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w600)),
        ),
      ],
      if (actionLabel != null && onAction != null) Flexible(child: _HeadAction(label: actionLabel!, onTap: onAction!)),
    ]);
  }
}

/// A card head's text action: horizontally compact, the full 48 px tap target (HomeSectionTitle's own style).
class _HeadAction extends StatelessWidget {
  const _HeadAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          // no minimum width: it shrinks (ellipsis) before the title does; the 48 px height stays
          minimumSize: const Size(0, AppTouch.min),
          visualDensity: const VisualDensity(horizontal: -2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label(context).copyWith(color: appInk(context, context.colors.primary), fontWeight: FontWeight.w500)),
      );
}

/// The work queue: ALWAYS a card, the screen's ONE highlighted card. [child] is the list; [empty] = draw
/// [emptyState] (default HomeCaughtUp) instead of it.
class HomeQueueCard extends StatelessWidget {
  const HomeQueueCard({
    super.key,
    required this.title,
    required this.child,
    this.icon = Icons.inbox_rounded,
    this.count,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.empty = false,
    this.emptyState,
  });

  final String title;
  final Widget child;
  final IconData icon;
  final int? count;
  final String? subtitle, actionLabel;
  final VoidCallback? onAction;
  final bool empty;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) => AppCard(
        key: const ValueKey('home.queue'),
        highlight: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          _CardHead(title: title, icon: icon, count: empty ? null : count, subtitle: subtitle, actionLabel: empty ? null : actionLabel, onAction: onAction),
          const SizedBox(height: AppSpace.sm),
          empty ? (emptyState ?? const HomeCaughtUp()) : child,
        ]),
      );
}

/// A compact side card (Today, Inbox, My departments).
class HomeSideCard extends StatelessWidget {
  const HomeSideCard({super.key, required this.title, required this.child, this.icon, this.count, this.actionLabel, this.onAction, this.chip, this.bare = false});
  final String title;
  final Widget child;
  final IconData? icon;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? chip;

  /// The head over [child] without a card of its own ([child] is already a card, e.g. the day's agenda).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: bare ? const EdgeInsets.symmetric(horizontal: AppSpace.xs) : EdgeInsets.zero,
        child: _CardHead(title: title, icon: icon, count: count, actionLabel: actionLabel, onAction: onAction, chip: chip),
      ),
      const SizedBox(height: AppSpace.sm),
      child,
    ]);
    return bare ? body : AppCard(child: body);
  }
}

/// One quiet line inside a side card ("No sessions today · Next: Python, Sun 21").
class HomeSideLine extends StatelessWidget {
  const HomeSideLine(this.text, {super.key, this.icon = Icons.event_available_rounded});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Icon(icon, size: AppIconSize.sm, color: c.textLight),
      const SizedBox(width: AppSpace.xs),
      Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium))),
    ]);
  }
}

/// The home skeleton: [greeting] · [stats] · [queue] beside [side] (2fr | 1fr from [homeIsWide]) · [below], each on
/// the page's [inset]. [banners] (live now, a failed refresh) sit between the counts and the queue.
class HomeA2Layout extends StatelessWidget {
  const HomeA2Layout({
    super.key,
    required this.queue,
    this.greeting,
    this.stats = const [],
    this.side = const [],
    this.below = const [],
    this.banners = const [],
    this.inset = const EdgeInsets.symmetric(horizontal: AppSpace.md + AppSpace.xxs),
    this.headInset = EdgeInsets.zero,
  });

  /// Null = the page draws the greeting itself (above, e.g. pinned).
  final Widget? greeting;
  final Widget queue;
  final List<Widget> stats, side, below, banners;
  final EdgeInsetsGeometry inset;

  /// Extra inset of the greeting, the counts and the banners (a page whose sections carry their own edge).
  final EdgeInsetsGeometry headInset;

  List<Widget> _spaced(List<Widget> xs, double gap) => [
        for (var i = 0; i < xs.length; i++) ...[if (i > 0) SizedBox(height: gap), xs[i]],
      ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = homeIsWide(box.maxWidth);
        final work = wide && side.isNotEmpty
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: queue),
                const SizedBox(width: AppSpace.lg),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced(side, AppSpace.md))),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _spaced([queue, ...side], AppSpace.md));
        return Padding(
          padding: inset,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (greeting != null) ...[const SizedBox(height: AppSpace.sm), Padding(padding: headInset, child: greeting!), const SizedBox(height: AppSpace.md)],
            if (stats.isNotEmpty) Padding(padding: headInset, child: HomeStatRow(children: stats)),
            for (final b in banners) ...[const SizedBox(height: AppSpace.md), Padding(padding: headInset, child: b)],
            const SizedBox(height: AppSpace.lg),
            work,
            for (final b in below) ...[const SizedBox(height: AppSpace.lg), b],
            const SizedBox(height: AppSpace.lg),
          ]),
        );
      });
}

/// "6 published": a small fact chip for a card head.
class HomeFactChip extends StatelessWidget {
  const HomeFactChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppBorder.focus),
      decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Text(text, maxLines: 1, style: AppType.meta(context).copyWith(color: appInk(context, c.success), fontWeight: FontWeight.w600)),
    );
  }
}

/// The greeting's line for a quiet day: "Nothing waiting" or "Nothing waiting · next session Sunday 10:00".
String homeNothingWaitingLine(String? next) => ['home_nothing_waiting'.tr, ?next].join(' · ');
