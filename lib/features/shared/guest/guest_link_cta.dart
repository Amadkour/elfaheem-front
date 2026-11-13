// lib/features/shared/guest/guest_link_cta.dart — the soft "create an account / sign in" card a guest sees on a
// guest link's page (D-844): under the video, or back on the meeting's page after leaving the room. Never a wall:
// the page works the same whether the card is used or not. Plain values (test/ui/guest_share_layout_test.dart).
//
//   GuestLinkCta(onRegister: …, onSignIn: …)
//   openGuestSignUp(context, '/register')   pushes the sign-up / sign-in page OVER the guest page, so Back returns
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_icons.dart';
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart' show t;

/// Opens the sign-up ([route] `/register`) or sign-in (`/login`) page on top of the guest page.
void openGuestSignUp(BuildContext context, String route) => Navigator.of(context).pushNamed(route);

class GuestLinkCta extends StatelessWidget {
  const GuestLinkCta({super.key, this.afterMeeting = false, this.onRegister, this.onSignIn});

  /// The words for a guest back from a meeting ("Enjoyed the meeting?") instead of a video.
  final bool afterMeeting;
  final VoidCallback? onRegister;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    return AppCard(
      key: const ValueKey('guest_link.cta'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Icon(Icons.auto_awesome_rounded, color: ink, size: AppIconSize.md),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              afterMeeting ? t('أعجبك الاجتماع؟', 'Enjoyed the meeting?') : t('أعجبك ما شاهدته؟', 'Enjoyed it?'),
              style: AppType.section(context).copyWith(color: c.textDark),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(
          t('أنشئ حساباً مجانياً لتتابع الدروس والاجتماعات وتحفظ تقدّمك — أو سجّل الدخول إن كان لديك حساب.',
              'Create a free account to follow lessons and meetings and keep your progress — or sign in if you have one.'),
          style: AppType.body(context).copyWith(color: c.textMedium),
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppButton(
            key: const ValueKey('guest_link.cta.register'),
            label: t('إنشاء حساب', 'Create an account'),
            icon: Icons.person_add_alt_1_rounded,
            variant: AppButtonVariant.tonal,
            onPressed: onRegister,
          ),
          AppButton.ghost(
            key: const ValueKey('guest_link.cta.sign_in'),
            label: t('تسجيل الدخول', 'Sign in'),
            icon: DirIcons.login,
            onPressed: onSignIn,
          ),
        ]),
      ]),
    );
  }
}
