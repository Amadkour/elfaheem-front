// features/auth/verify_way.dart
// ─────────────────────────────────────────────────────────────────────────────
// The ways a student can verify the account, as allowed by the admin
// (verification_method + otp_phone_channel), and the widgets that show them:
//
//   VerifyWayPicker      registration page  — pick how you want to verify
//   VerifyWaySwitcher    verification page  — switch between the allowed ways
//   VerifyWayButton      brand-coloured call-to-action (Telegram / WhatsApp)
//   VerifyWayStatusPill  "waiting for your confirmation" indicator
// ─────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase, AppPressScale;
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'auth_provider.dart';
import '../../design/app_tokens.dart';
import 'auth_widgets.dart' show AuthMark;

// ══════════════════════════════════════════════════════════════════════════════
//  Model
// ══════════════════════════════════════════════════════════════════════════════

enum VerifyWay { email, telegram, whatsapp, sms }

extension VerifyWayX on VerifyWay {
  /// The server channel this way belongs to: "email" or "phone".
  String get channel => this == VerifyWay.email ? 'email' : 'phone';

  bool get isPhone => this != VerifyWay.email;

  /// Verified by a link (the student messages us) instead of a typed code?
  /// Telegram always is; WhatsApp follows the admin's delivery (link / code).
  bool isLink(MyAuthProvider a) => a.wayIsLink(name);

  static VerifyWay? fromName(String? n) {
    for (final w in VerifyWay.values) {
      if (w.name == n) return w;
    }
    return null;
  }

  IconData get icon => switch (this) {
        VerifyWay.email => Icons.mail_rounded,
        VerifyWay.telegram => Icons.send_rounded,
        VerifyWay.whatsapp => Icons.chat_rounded,
        VerifyWay.sms => Icons.sms_rounded,
      };

  Color get brand => switch (this) {
        VerifyWay.email => const Color(0xFF4F6BED),
        VerifyWay.telegram => const Color(0xFF229ED9),
        VerifyWay.whatsapp => const Color(0xFF25D366),
        VerifyWay.sms => const Color(0xFFF59E0B),
      };

  Color get brandDark {
    final hsl = HSLColor.fromColor(brand);
    return hsl.withLightness((hsl.lightness - 0.09).clamp(0.0, 1.0)).toColor();
  }

  String get titleKey => switch (this) {
        VerifyWay.email => 'verify_way_email',
        VerifyWay.telegram => 'verify_way_telegram',
        VerifyWay.whatsapp => 'verify_way_whatsapp',
        VerifyWay.sms => 'verify_way_sms',
      };

  /// One-line explanation. WhatsApp is a tap-to-send link or a sent code, by admin setting.
  String subtitleKey(MyAuthProvider a) => switch (this) {
        VerifyWay.email => 'verify_way_email_sub',
        VerifyWay.telegram => 'verify_way_telegram_sub',
        VerifyWay.whatsapp =>
          a.wayIsLink('whatsapp') ? 'verify_way_whatsapp_link_sub' : 'verify_way_whatsapp_code_sub',
        VerifyWay.sms => 'verify_way_sms_sub',
      };
}

/// Every way the admin allows (and the server can send), in offering order:
/// Telegram > E-mail > WhatsApp > SMS, or the admin's default way first.
List<VerifyWay> policyWays(MyAuthProvider a) => [
      for (final n in a.verificationWays)
        if (VerifyWayX.fromName(n) != null) VerifyWayX.fromName(n)!,
    ];

/// The channels a NEW account may verify ("email" / "phone"), in offering order.
List<String> policyChannels(MyAuthProvider a) {
  final out = <String>[];
  for (final w in policyWays(a)) {
    if (!out.contains(w.channel)) out.add(w.channel);
  }
  return out.isEmpty ? const ['email'] : out;
}

/// Every allowed way that belongs to one of [channels], keeping the offering order.
List<VerifyWay> verifyWaysForChannels(MyAuthProvider a, Iterable<String> channels) =>
    policyWays(a).where((w) => channels.contains(w.channel)).toList();

// ══════════════════════════════════════════════════════════════════════════════
//  Shared bits (Warm Editorial: a way's colour lives in its mark and its selection edge — no gradient, no glow)
// ══════════════════════════════════════════════════════════════════════════════

/// The colour a way wears in the UI: our own channels (e-mail, SMS) take the theme's primary, the messaging apps
/// keep their brand hue so the person recognises them.
Color _wayTone(BuildContext context, VerifyWay way) => switch (way) {
      VerifyWay.email || VerifyWay.sms => context.colors.primary,
      _ => way.brand,
    };

/// [_wayTone] as readable ink on the card / canvas (AA in both modes).
Color _wayInk(BuildContext context, VerifyWay way) => appInk(context, _wayTone(context, way));

/// [_wayTone] deep enough to carry the on-primary ink as a fill (AA).
Color _wayFill(BuildContext context, VerifyWay way) =>
    ensureContrast(_wayTone(context, way), [context.colors.onHero], min: 4.5);

/// Fades + rises a child when it first appears; [index] starts a later card a beat later (one wave, not a queue).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final delay = (index.clamp(0, 4) * 50);
    const run = 360;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: run + delay),
      curve: Interval(delay / (run + delay), 1, curve: AppEase.out),
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, AppSpace.xs * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

/// A way's mark: its icon on its own tint; the chosen way's mark turns solid.
class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.way, required this.selected});

  final VerifyWay way;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _wayTone(context, way);
    return AnimatedContainer(
      duration: AppMotion.of(context).base,
      curve: AppEase.out,
      width: AppTouch.min - AppSpace.xxs,
      height: AppTouch.min - AppSpace.xxs,
      decoration: BoxDecoration(
        color: selected ? _wayFill(context, way) : Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.20 : 0.12), c.cardBg),
        borderRadius: AppRadius.controlAll,
      ),
      child: Icon(
        way.icon,
        size: AppIconSize.md,
        color: selected ? c.onHero : _wayInk(context, way),
      ),
    );
  }
}

/// A small status label ("Recommended", "Fastest"): a full pill on the way's tint, its ink readable on it.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = Color.alphaBlend(color.withValues(alpha: c.isDark ? 0.22 : 0.12), c.cardBg);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context).copyWith(
          fontWeight: FontWeight.w600,
          color: ensureContrast(color, [tint]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  1) Picker — registration page
// ══════════════════════════════════════════════════════════════════════════════

class VerifyWayPicker extends StatelessWidget {
  const VerifyWayPicker({
    super.key,
    required this.ways,
    required this.selected,
    required this.onChanged,
    required this.provider,
    this.requireAll = false,
  });

  final List<VerifyWay> ways;
  final VerifyWay? selected;
  final ValueChanged<VerifyWay> onChanged;
  final MyAuthProvider provider;

  /// The admin requires BOTH e-mail and phone: the choice is only which to start with.
  final bool requireAll;

  @override
  Widget build(BuildContext context) {
    if (ways.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final interactive = ways.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AuthMark(icon: Icons.verified_user_rounded, size: AppTouch.min - AppSpace.xs),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('verify_way_title'.tr, style: AppType.section(context)),
                  const SizedBox(height: 2),
                  Text(
                    interactive ? 'verify_way_subtitle'.tr : 'verify_way_single_subtitle'.tr,
                    style: AppType.meta(context).copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (requireAll) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(
              color: c.blockSky,
              borderRadius: AppRadius.controlAll,
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: AppIconSize.sm, color: c.blockInk),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    'verify_way_both_hint'.tr,
                    style: AppType.meta(context).copyWith(height: 1.5, fontWeight: FontWeight.w500, color: c.blockInk),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.sm),
        LayoutBuilder(
          builder: (context, box) {
            final twoColumns = ways.length > 1 && box.maxWidth >= 560;
            final cardWidth = twoColumns ? (box.maxWidth - AppSpace.sm) / 2 : box.maxWidth;
            return Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (var i = 0; i < ways.length; i++)
                  SizedBox(
                    width: cardWidth,
                    child: _Reveal(
                      index: i,
                      child: _WayCard(
                        way: ways[i],
                        subtitle: ways[i].subtitleKey(provider).tr,
                        selected: ways[i] == selected,
                        interactive: interactive,
                        recommended: i == 0 && ways.length > 1,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(ways[i]);
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _WayCard extends StatelessWidget {
  const _WayCard({
    required this.way,
    required this.subtitle,
    required this.selected,
    required this.interactive,
    required this.recommended,
    required this.onTap,
  });

  final VerifyWay way;
  final String subtitle;
  final bool selected;
  final bool interactive;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _wayTone(context, way);
    final edge = _wayInk(context, way);
    // paper; the chosen card takes a whisper of the way's tone and a 2 px edge in its ink (no glow)
    return AppPressScale(
      enabled: interactive,
      child: AnimatedContainer(
        duration: AppMotion.of(context).base,
        curve: AppEase.out,
        decoration: BoxDecoration(
          color: selected ? Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.12 : 0.06), c.cardBg) : c.cardBg,
          borderRadius: AppRadius.cardAll,
          border: Border.all(
            color: selected ? edge : c.divider,
            width: selected ? AppBorder.focus : AppBorder.hairline,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: interactive ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Row(
                children: [
                  _BrandBadge(way: way, selected: selected),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                way.titleKey.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.bodyStrong(context),
                              ),
                            ),
                            if (recommended) ...[
                              const SizedBox(width: AppSpace.xs),
                              Flexible(
                                child: _Pill(
                                  label: (way == VerifyWay.telegram
                                          ? 'verify_way_badge_fast'
                                          : 'verify_way_badge_recommended')
                                      .tr,
                                  color: tone,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppType.meta(context).copyWith(height: 1.45)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  _CheckDot(selected: selected, color: _wayFill(context, way)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckDot extends StatelessWidget {
  const _CheckDot({required this.selected, required this.color});

  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final d = AppMotion.of(context).base;
    return AnimatedContainer(
      duration: d,
      curve: AppEase.out,
      width: AppIconSize.lg,
      height: AppIconSize.lg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected ? color : Color.lerp(context.colors.divider, context.colors.textDark, 0.3)!,
          width: selected ? 0 : AppBorder.strong,
        ),
      ),
      child: AnimatedOpacity(
        duration: d,
        opacity: selected ? 1 : 0,
        child: Icon(Icons.check_rounded, size: AppIconSize.sm, color: context.colors.onHero),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  2) Switcher — verification page
// ══════════════════════════════════════════════════════════════════════════════

class VerifyWaySwitcher extends StatelessWidget {
  const VerifyWaySwitcher({
    super.key,
    required this.ways,
    required this.selected,
    required this.onChanged,
    this.verified = const {},
  });

  final List<VerifyWay> ways;
  final VerifyWay? selected;
  final ValueChanged<VerifyWay> onChanged;

  /// Ways already confirmed (shown with a tick, not selectable).
  final Set<VerifyWay> verified;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppSpace.xxs, bottom: AppSpace.xs),
          child: Text('verify_way_switch_title'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
        ),
        // the kit's pill track: the input surface, the chosen way a solid pill
        Container(
          padding: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: AppRadius.cardAll,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: Row(
            children: [
              for (var i = 0; i < ways.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: _SwitchItem(
                    way: ways[i],
                    selected: ways[i] == selected,
                    done: verified.contains(ways[i]),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(ways[i]);
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.way,
    required this.selected,
    required this.done,
    required this.onTap,
  });

  final VerifyWay way;
  final bool selected;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onHero : (done ? appInk(context, c.success) : c.textMedium);
    final radius = BorderRadius.circular(AppRadius.card - AppSpace.xxs);
    return AnimatedContainer(
      duration: AppMotion.of(context).base,
      curve: AppEase.out,
      height: AppTouch.primary + AppSpace.xs,
      decoration: BoxDecoration(
        color: selected ? _wayFill(context, way) : Colors.transparent,
        borderRadius: radius,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: (selected || done) ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xxs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.of(context).base,
                  child: Icon(
                    done ? Icons.check_circle_rounded : way.icon,
                    key: ValueKey(done),
                    size: AppIconSize.md,
                    color: fg,
                  ),
                ),
                const SizedBox(height: AppSpace.xxs),
                Text(
                  way.titleKey.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  3) Brand button + status pill
// ══════════════════════════════════════════════════════════════════════════════

/// The messaging app's own call to action (Telegram / WhatsApp): a solid fill in the app's colour, deepened until
/// the label reads on it, the kit's control radius, no glow; a press sinks it.
class VerifyWayButton extends StatelessWidget {
  const VerifyWayButton({
    super.key,
    required this.way,
    required this.label,
    required this.onPressed,
  });

  final VerifyWay way;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = AppRadius.controlAll;
    return AppPressScale(
      scale: 0.97,
      child: Material(
        color: _wayFill(context, way),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(way.icon, color: c.onHero, size: AppIconSize.md),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong(context).copyWith(color: c.onHero, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.open_in_new_rounded, color: c.onHero, size: AppIconSize.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VerifyWayStatusPill extends StatelessWidget {
  const VerifyWayStatusPill({super.key, required this.way, required this.label});

  final VerifyWay way;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.divider, width: AppBorder.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: AppIconSize.xs,
              height: AppIconSize.xs,
              child: CircularProgressIndicator(strokeWidth: 2, color: _wayInk(context, way)),
            ),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(
                label,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  4) Verification page extras: hero badge, destination chip, step tracker
// ══════════════════════════════════════════════════════════════════════════════

/// The mark of the way being verified: the way's icon on a paper disc inside its own tint, with one quiet hairline
/// orbit; it settles in (from 92 %, never from nothing) when the way changes. No glow, no pulse.
class VerifyWayHero extends StatelessWidget {
  const VerifyWayHero({super.key, required this.way, this.size = 84});

  final VerifyWay way;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = _wayTone(context, way);
    final motion = AppMotion.of(context);
    return AnimatedSwitcher(
      duration: motion.slow,
      switchInCurve: AppEase.out,
      switchOutCurve: AppEase.out,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
      ),
      child: Container(
        key: ValueKey(way),
        width: size,
        height: size,
        padding: const EdgeInsets.all(AppSpace.xs),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.18 : 0.10), c.background),
          border: Border.all(color: tone.withValues(alpha: c.isDark ? 0.35 : 0.22), width: AppBorder.hairline),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cardBg,
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: Icon(way.icon, color: _wayInk(context, way), size: size * 0.4),
        ),
      ),
    );
  }
}

/// "Code sent to  e•••@mail.com" — the destination on a paper capsule, the way's icon in its ink.
class VerifyDestinationChip extends StatelessWidget {
  const VerifyDestinationChip({super.key, required this.way, required this.text});

  final VerifyWay way;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: c.divider, width: AppBorder.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(way.icon, size: AppIconSize.sm, color: _wayInk(context, way)),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              text,
              textDirection: TextDirection.ltr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the admin requires BOTH e-mail and phone: which of them is done / current.
class VerifyStepTracker extends StatelessWidget {
  const VerifyStepTracker({
    super.key,
    required this.channels,
    required this.pending,
    required this.current,
  });

  /// Every channel to verify, in order ("email" / "phone").
  final List<String> channels;

  /// Channels not verified yet.
  final List<String> pending;

  /// The channel being verified now.
  final String current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = AppMotion.of(context).slow;
    final items = <Widget>[];
    for (var i = 0; i < channels.length; i++) {
      final ch = channels[i];
      final done = !pending.contains(ch);
      final active = ch == current && !done;
      final color = done ? c.success : (active ? c.primary : c.divider);
      if (i > 0) {
        items.add(Expanded(
          child: AnimatedContainer(
            duration: d,
            curve: AppEase.out,
            height: AppBorder.focus,
            margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            decoration: BoxDecoration(
              color: done ? c.success : c.divider,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ));
      }
      items.add(Flexible(
        flex: 2,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: d,
            curve: AppEase.out,
            width: AppTouch.min - AppSpace.sm,
            height: AppTouch.min - AppSpace.sm,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? c.success : (active ? c.primary : Colors.transparent),
              border: Border.all(color: color, width: AppBorder.focus),
            ),
            child: Icon(
              done
                  ? Icons.check_rounded
                  : (ch == 'email' ? Icons.mail_rounded : Icons.phone_iphone_rounded),
              size: AppIconSize.sm,
              color: (done || active) ? c.onHero : c.textLight,
            ),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            (ch == 'email' ? 'verify_channel_email' : 'verify_channel_phone').tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppType.meta(context).copyWith(
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: done ? appInk(context, c.success) : (active ? c.textDark : c.textMedium),
            ),
          ),
        ],
      )));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: items);
  }
}
