// lib/features/auth/biometric_widgets.dart
// ─────────────────────────────────────────────────────────────────────────────
// The fingerprint / Face ID sign-in UI (D-082), in the auth design language (auth_widgets.dart). Everything below
// the flow helpers takes plain values, so the layout harness and the visual renders can pump it:
//   BiometricGlyph          the hero-gradient disc with the fingerprint / face mark (the offer, the login button)
//   AuthAccountAvatar       the remembered account's photo (or initials) in a hero-gradient ring
//   BiometricQuickSignIn    the login card's top for a remembered account: who · "Not you?" · the big button
//   BiometricOfferSheetBody "Sign in with your fingerprint next time?" after a password sign-in
//   maybeOfferBiometric     shows the offer once per account and phone, then enrolls (biometric.dart)
//   biometricOutcomeNotice  the toast for a sign-in / enrolment that did not go through
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../design/app_charts.dart' show appInk;
import '../../design/app_kit.dart' show showAppSheet;
import '../../design/app_notice.dart';
import '../../utils/widget/app_network_image.dart';
import 'auth_provider.dart';
import 'auth_widgets.dart';
import 'biometric.dart';

// ── Flow helpers ─────────────────────────────────────────────────────────────

/// After a successful sign-in (password, its second step, Google): offers fingerprint sign-in once per account on
/// this phone, and enrolls when accepted. [identifier] is what the person typed (prefilled next time).
Future<void> maybeOfferBiometric(BuildContext context, MyAuthProvider auth, {String? identifier}) async {
  final bio = BiometricAuth.instance;
  final user = auth.currentUser;
  if (user == null || user.id <= 0) return;
  if (!bio.loaded) await bio.load();
  final declined = await bio.declined(user.id);
  final offer = shouldOfferBiometric(
    supported: bio.supported,
    featureOn: bio.featureOn,
    hasEnrollToken: bio.enrollToken != null,
    userId: user.id,
    enrolledUserId: bio.record?.userId,
    declined: declined,
  );
  if (!offer || !context.mounted) return;
  final yes = await showAppSheet<bool>(
    context,
    (ctx) => BiometricOfferSheetBody(
      kind: bio.kind,
      onEnable: () => Navigator.of(ctx).pop(true),
      onLater: () => Navigator.of(ctx).pop(false),
    ),
  );
  if (yes != true) {
    await bio.setDeclined(user.id, true); // asked once; the Security switch stays available
    return;
  }
  final typed = identifier?.trim();
  final r = await bio.enroll(
    userId: user.id,
    name: user.name,
    identifier: (typed != null && typed.isNotEmpty) ? typed : (user.username != null ? '@${user.username}' : user.gmail),
    imageUrl: user.imageUrl,
  );
  biometricEnrollNotice(r);
}

/// The toast after an enrolment (nothing for a cancelled prompt).
void biometricEnrollNotice(BiometricEnrollResult r) {
  switch (r.outcome) {
    case BiometricEnrollOutcome.enabled:
      showAppNotice('bio_enabled_notice'.tr);
    case BiometricEnrollOutcome.lockout:
      showAppNotice('bio_lockout_notice'.tr, error: true);
    case BiometricEnrollOutcome.unavailable:
      showAppNotice('bio_unavailable_notice'.tr, error: true);
    case BiometricEnrollOutcome.failed:
    case BiometricEnrollOutcome.needsPassword:
      showAppNotice(r.message ?? 'bio_failed_notice'.tr, error: true);
    case BiometricEnrollOutcome.cancelled:
      break;
  }
}

/// The toast for a fingerprint sign-in that did not open a session (null = say nothing: cancelled).
String? biometricOutcomeNotice(BiometricOutcome o, {String? message}) => switch (o) {
      BiometricOutcome.lockout => 'bio_lockout_notice'.tr,
      BiometricOutcome.unavailable => 'bio_unavailable_notice'.tr,
      BiometricOutcome.gone => 'bio_gone_notice'.tr,
      BiometricOutcome.failed => message ?? 'bio_failed_notice'.tr,
      _ => null,
    };

// ── Pieces ───────────────────────────────────────────────────────────────────

/// The hero-gradient disc with the fingerprint / face mark and a soft brand halo.
class BiometricGlyph extends StatelessWidget {
  const BiometricGlyph({super.key, required this.kind, this.size = 56, this.halo = true});

  final BiometricKind kind;
  final double size;

  /// A faint ring around the disc (the offer's illustration).
  final bool halo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disc = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: authHeroGradient(c),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.28),
            blurRadius: size * 0.36,
            spreadRadius: -size * 0.06,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Icon(biometricIcon(kind), color: c.onHero, size: size * 0.52),
    );
    if (!halo) return disc;
    final ring = size * 0.22;
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.primary.withValues(alpha: c.isDark ? 0.14 : 0.07),
        border: Border.all(color: c.primary.withValues(alpha: c.isDark ? 0.28 : 0.14)),
      ),
      child: disc,
    );
  }
}

/// The remembered account's photo (or initials) inside a 2 px hero-gradient ring.
class AuthAccountAvatar extends StatelessWidget {
  const AuthAccountAvatar({super.key, required this.initials, this.imageUrl, this.size = 52});

  final String initials;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = imageUrl;
    final inner = size - 6;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: authHeroGradient(c)),
      child: Container(
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
        child: ClipOval(
          child: SizedBox(
            width: inner,
            height: inner,
            child: url != null && url.isNotEmpty
                ? AppNetworkImage(url: url, width: inner, height: inner, fit: BoxFit.cover)
                : ColoredBox(
                    color: c.primary.withValues(alpha: c.isDark ? 0.24 : 0.10),
                    child: Center(
                      child: Text(
                        initials,
                        style: authText(inner * 0.36, w: FontWeight.w800, c: appInk(context, c.primary), h: 1),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The login card's top for a remembered account: avatar · name · identifier · "Not you?", then the large
/// fingerprint / Face ID button and "or use your password" above the form.
class BiometricQuickSignIn extends StatelessWidget {
  const BiometricQuickSignIn({
    super.key,
    required this.name,
    required this.initials,
    required this.kind,
    required this.onSignIn,
    this.identifier,
    this.imageUrl,
    this.busy = false,
    this.onForget,
  });

  final String name;
  final String initials;
  final String? identifier;
  final String? imageUrl;
  final BiometricKind kind;
  final bool busy;
  final VoidCallback onSignIn;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final link = appInk(context, c.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AuthAccountAvatar(initials: initials, imageUrl: imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: authText(17, w: FontWeight.w800, c: c.textDark, h: 1.25, ls: authTracking(-0.2)),
                  ),
                  if (identifier != null && identifier!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      identifier!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      textAlign: AppConfig.lang == 'ar' ? TextAlign.right : TextAlign.left,
                      style: authText(13, c: c.textMedium, h: 1.3),
                    ),
                  ],
                ],
              ),
            ),
            if (onForget != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onForget,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor: link,
                ),
                child: Text('bio_not_you'.tr, style: authText(13.5, w: FontWeight.w700, c: link)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        BiometricSignInButton(kind: kind, busy: busy, onTap: onSignIn),
        const SizedBox(height: 24),
        AuthOrDivider(label: 'bio_or_password'.tr),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// The large tinted button: the glyph, "Sign in with fingerprint", an arrow (a spinner while busy). 64 dp tall.
class BiometricSignInButton extends StatefulWidget {
  const BiometricSignInButton({super.key, required this.kind, required this.onTap, this.busy = false});

  final BiometricKind kind;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<BiometricSignInButton> createState() => _BiometricSignInButtonState();
}

class _BiometricSignInButtonState extends State<BiometricSignInButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    final label = biometricActionLabel(widget.kind);
    final r = BorderRadius.circular(20);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: authDuration(context, 120),
        child: Material(
          color: c.primary.withValues(alpha: c.isDark ? 0.16 : 0.07),
          shape: RoundedRectangleBorder(
            borderRadius: r,
            side: BorderSide(color: c.primary.withValues(alpha: c.isDark ? 0.36 : 0.20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.busy
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    widget.onTap();
                  },
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 16, 10),
                child: Row(
                  children: [
                    BiometricGlyph(kind: widget.kind, size: 44, halo: false),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: authText(15.5, w: FontWeight.w700, c: ink, h: 1.3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: AnimatedSwitcher(
                        duration: authDuration(context, 180),
                        child: widget.busy
                            ? CircularProgressIndicator(key: const ValueKey('busy'), strokeWidth: 2.4, color: ink)
                            : Icon(Icons.arrow_forward_rounded, key: const ValueKey('go'), size: 22, color: ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Sign in with your fingerprint next time?" — the glyph in its halo, the promise, two reassurances, Turn on /
/// Not now.
class BiometricOfferSheetBody extends StatelessWidget {
  const BiometricOfferSheetBody({
    super.key,
    required this.kind,
    required this.onEnable,
    required this.onLater,
    this.busy = false,
  });

  final BiometricKind kind;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget point(IconData icon, String text) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.success.withValues(alpha: c.isDark ? 0.20 : 0.10),
              ),
              child: Icon(icon, size: 16, color: appInk(context, c.success)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(text, style: authText(14, w: FontWeight.w500, c: c.textMedium, h: 1.45)),
              ),
            ),
          ],
        );
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: BiometricGlyph(kind: kind, size: 72)),
            const SizedBox(height: 24),
            Semantics(
              header: true,
              child: Text(
                biometricOfferTitle(kind),
                textAlign: TextAlign.center,
                style: authText(21, w: FontWeight.w800, c: c.textDark, h: 1.3, ls: authTracking(-0.3)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'bio_offer_body'.tr,
              textAlign: TextAlign.center,
              style: authText(14.5, c: c.textMedium, h: 1.55),
            ),
            const SizedBox(height: 24),
            point(Icons.lock_rounded, 'bio_offer_point_private'.tr),
            const SizedBox(height: 12),
            point(Icons.phone_android_rounded, 'bio_offer_point_device'.tr),
            const SizedBox(height: 32),
            AuthButton(
              label: 'bio_offer_enable'.tr,
              icon: biometricIcon(kind),
              iconBefore: true,
              loading: busy,
              onPressed: onEnable,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy ? null : onLater,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: c.textMedium,
              ),
              child: Text('bio_offer_later'.tr, style: authText(14.5, w: FontWeight.w700, c: c.textMedium)),
            ),
          ],
        ),
      ),
    );
  }
}
