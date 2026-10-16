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
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import 'auth_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  Model
// ══════════════════════════════════════════════════════════════════════════════

enum VerifyWay { email, telegram, whatsapp, sms }

extension VerifyWayX on VerifyWay {
  /// The server channel this way belongs to: "email" or "phone".
  String get channel => this == VerifyWay.email ? 'email' : 'phone';

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
          a.phoneUsesLink ? 'verify_way_whatsapp_link_sub' : 'verify_way_whatsapp_code_sub',
        VerifyWay.sms => 'verify_way_sms_sub',
      };
}

/// The channels a NEW account must verify, from the admin policy.
List<String> policyChannels(MyAuthProvider a) => switch (a.verificationMethod) {
      'both' => const ['email', 'phone'],
      'phone' => const ['phone'],
      _ => const ['email'],
    };

/// Every way the admin allows for [channels], in priority order (Telegram first).
List<VerifyWay> verifyWaysForChannels(MyAuthProvider a, Iterable<String> channels) {
  final out = <VerifyWay>[];
  for (final ch in channels) {
    if (ch == 'email') {
      out.add(VerifyWay.email);
    } else if (ch == 'phone') {
      switch (a.otpPhoneChannel) {
        case 'telegram':
          out.add(VerifyWay.telegram);
        case 'whatsapp_link':
        case 'whatsapp':
          out.add(VerifyWay.whatsapp);
        case 'telegram_whatsapp':
          out.addAll(const [VerifyWay.telegram, VerifyWay.whatsapp]);
        default:
          out.add(VerifyWay.sms);
      }
    }
  }
  return out;
}

// ══════════════════════════════════════════════════════════════════════════════
//  Shared bits
// ══════════════════════════════════════════════════════════════════════════════

/// Fades + slides a child up when it first appears; [index] staggers a list.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 90),
      curve: Curves.easeOutCubic,
      builder: (_, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.way, required this.selected, this.size = 48});

  final VerifyWay way;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [way.brand, way.brandDark],
              )
            : null,
        color: selected ? null : way.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.31),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: way.brand.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: Icon(
        way.icon,
        size: size * 0.46,
        color: selected ? Colors.white : way.brand,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'tajawal',
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: color,
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                borderRadius: BorderRadius.circular(13),
                boxShadow: c.primaryShadow,
              ),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'verify_way_title'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    interactive ? 'verify_way_subtitle'.tr : 'verify_way_single_subtitle'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12.5,
                      height: 1.5,
                      color: c.secondText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (requireAll) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: c.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'verify_way_both_hint'.tr,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 12,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: c.textMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, box) {
            final twoColumns = ways.length > 1 && box.maxWidth >= 560;
            final cardWidth = twoColumns ? (box.maxWidth - 12) / 2 : box.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
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
                        recommended: ways[i] == VerifyWay.telegram && ways.contains(VerifyWay.whatsapp),
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
    final brand = way.brand;
    return AnimatedScale(
      scale: selected ? 1 : 0.985,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? brand.withValues(alpha: c.isDark ? 0.16 : 0.07) : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? brand : c.divider,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: brand.withValues(alpha: 0.26),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: interactive ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _BrandBadge(way: way, selected: selected),
                  const SizedBox(width: 14),
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
                                style: TextStyle(
                                  fontFamily: 'tajawal',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: c.textDark,
                                ),
                              ),
                            ),
                            if (recommended) ...[
                              const SizedBox(width: 8),
                              _Pill(label: 'verify_way_badge_fast'.tr, color: brand),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'tajawal',
                            fontSize: 12,
                            height: 1.45,
                            color: c.secondText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CheckDot(selected: selected, color: brand),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? color : Colors.transparent,
        border: Border.all(
          color: selected ? color : context.colors.divider,
          width: selected ? 0 : 1.6,
        ),
      ),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: selected ? 1 : 0,
        child: const Icon(Icons.check_rounded, size: 17, color: Colors.white),
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
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            'verify_way_switch_title'.tr,
            style: TextStyle(
              fontFamily: 'tajawal',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: c.secondText,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.divider),
          ),
          child: Row(
            children: [
              for (final w in ways)
                Expanded(
                  child: _SwitchItem(
                    way: w,
                    selected: w == selected,
                    done: verified.contains(w),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(w);
                    },
                  ),
                ),
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
    final fg = selected ? Colors.white : (done ? c.success : c.textMedium);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      height: 48,
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(colors: [way.brand, way.brandDark])
            : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: way.brand.withValues(alpha: 0.38),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: (selected || done) ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(done ? Icons.check_circle_rounded : way.icon, size: 18, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    way.titleKey.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: fg,
                    ),
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
    final radius = BorderRadius.circular(context.colors.radiusMedium);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [way.brand, way.brandDark],
        ),
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: way.brand.withValues(alpha: 0.36),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(way.icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'tajawal',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
              ],
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
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: way.brand.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: way.brand.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: way.brand),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: context.colors.textMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
