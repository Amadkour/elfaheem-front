// lib/design/app_live.dart
//
// "Live" in the redesign kit (KIT_SPEC §5.10):
//
//   AppLiveTag(label:)                 a pill: the pulsing live dot + "Live" in the live ink (onDark: glass + on-hero)
//   AppLiveBanner(title:, subtitle:, tag:, host:, actionLabel:, onAction:)
//                                      a room that is live now: the live gradient, the host, ONE breathing action
//
// Privacy (DESIGN_SYSTEM 1.2): the banner shows no participant count and no avatar but the host's. Do not add one.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'app_motion_kit.dart';
import 'app_responsive.dart' show Breakpoints;
import 'app_tokens.dart';
import 'home_kit.dart' show HomePulseDot;

/// The live pill.
class AppLiveTag extends StatelessWidget {
  const AppLiveTag({super.key, this.label, this.onDark = false, this.slap = true});

  /// Default: 'kit_live_now'.tr.
  final String? label;
  final bool onDark;

  /// Enters with AppSlap (tilt −3, student areas only).
  final bool slap;

  static const double _dot = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = c.kit.live;
    final ink = onDark ? c.onHero : live.ink;
    final pill = Container(
      constraints: const BoxConstraints(minHeight: AppSpace.lg),
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs / 2, AppSpace.sm, AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: onDark ? c.heroGlass : c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: onDark ? Border.all(color: c.heroGlassBorder, width: AppBorder.hairline) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        HomePulseDot(color: onDark ? c.onHero : live.color, size: _dot),
        Flexible(
          child: Text(label ?? 'kit_live_now'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.overline(context).copyWith(color: ink, letterSpacing: 0)),
        ),
      ]),
    );
    return slap ? AppSlap(child: pill) : pill;
  }
}

/// A room that is live now (see the file header). Phone: a column, the action full width and 56 high; from 700 px
/// one row with the action at the end, 48 high.
class AppLiveBanner extends StatelessWidget {
  const AppLiveBanner({
    super.key,
    required this.title,
    this.subtitle,
    this.tag,
    this.host,
    this.hostInitial,
    required this.actionLabel,
    required this.onAction,
    this.index = 0,
    this.onTap,
  });

  final String title;
  final String? subtitle;

  /// The tag's text ("Live · 12:04"); null = 'kit_live_now'.
  final String? tag;

  /// The host's picture (fills a 44 px circle); null draws [hostInitial].
  final Widget? host;
  final String? hostInitial;
  final String actionLabel;
  final VoidCallback onAction;

  /// The banner's place in a list: only the first one's tag slaps in.
  final int index;

  /// A tap on the banner outside the action; null = none.
  final VoidCallback? onTap;

  static const double _host = AppDashSize.ringSm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoints.mobile;
    final radius = BorderRadius.circular(AppRadius.cardFor(width));

    final avatar = ExcludeSemantics(
      child: Container(
        width: _host,
        height: _host,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.heroGlass,
          border: Border.all(color: c.heroGlassBorder, width: AppBorder.strong),
        ),
        clipBehavior: Clip.antiAlias,
        child: host ??
            Center(
              child: Text((hostInitial ?? '').trim().isEmpty ? '' : hostInitial!.trim().characters.first,
                  maxLines: 1, style: AppType.section(context).copyWith(color: c.onHero, height: 1.1)),
            ),
      ),
    );

    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      AppLiveTag(label: tag, onDark: false, slap: index == 0),
      const SizedBox(height: AppSpace.xs),
      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: c.onHero)),
      if (subtitle != null && subtitle!.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(subtitle!,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
      ],
    ]);

    final action = AppBreathe(
      color: c.onHero,
      child: Semantics(
        button: true,
        child: Material(
          color: c.cardBg,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onAction,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: wide ? AppTouch.min : AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
                child: Row(mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_arrow_rounded, size: AppIconSize.md, color: kit.live.ink),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(actionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong(context).copyWith(color: kit.live.ink)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

    final content = wide
        ? Row(children: [
            avatar,
            const SizedBox(width: AppSpace.md),
            Expanded(child: text),
            const SizedBox(width: AppSpace.md),
            Flexible(child: action),
          ])
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: text),
              const SizedBox(width: AppSpace.sm),
              avatar,
            ]),
            const SizedBox(height: AppSpace.md),
            action,
          ]);

    final banner = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: const Alignment(-1, -0.58),
          end: const Alignment(1, 0.58),
          colors: [kit.liveFill, kit.live.color],
        ),
        boxShadow: AppShadow.button(context, kit.live.color),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: wide ? AppSpace.cardWide : AppSpace.card, child: content),
        ),
      ),
    );
    return Semantics(container: true, child: banner);
  }
}
