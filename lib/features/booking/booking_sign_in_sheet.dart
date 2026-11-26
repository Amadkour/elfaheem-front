// lib/features/booking/booking_sign_in_sheet.dart
//
// 4ب "سجّل دخولك عشان نثبّت حجزك" (BookM4L / BookW4L): shown only to a visitor on the review step. The picks are
// already saved (BkFlowController.saveDraft) and the course page is remembered as the pending intent, so after the
// sign-in the course opens again and the flow comes back on its review ("حجزك محفوظ لين تكمّل").
//
// Both ways leave the visitor mode the way the app's guest sheet does: Google sign-in lives on the sign-in page, a
// phone number (any country, with its code) on the create-account page with its code check.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/routing/pending_intent.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/login_screen.dart';
import 'package:flutter_education_app/features/auth/register_screen.dart';
import 'package:flutter_education_app/features/guest/guest_state.dart';

Future<void> showBkSignInSheet(BuildContext context, {String? courseId}) => showAppSheet<void>(
      context,
      (_) => BkSignInSheet(courseId: courseId),
    );

/// Leaves the visitor mode for [page], keeping the course to come back to.
Future<void> bkLeaveToSignIn(BuildContext context, {required bool register, String? courseId}) async {
  if (courseId != null) await PendingIntent.save(PendingIntent(kind: PendingIntentKind.bookCourse, id: courseId));
  GuestState.instance.stop();
  if (!context.mounted) return;
  unawaited(Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: register ? '/register' : '/login'),
      builder: (_) => register ? const RegisterScreen(initialRole: 'student') : const LoginScreen(),
    ),
    (_) => false,
  ));
}

class BkSignInSheet extends StatelessWidget {
  const BkSignInSheet({super.key, this.courseId, this.onGoogle, this.onPhone});

  final String? courseId;

  /// Tests: what the two buttons do instead of leaving.
  final VoidCallback? onGoogle, onPhone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warm = c.kit.warmTone;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppIconBox(icon: Icons.person_outline_rounded, tone: warm, size: AppDashSize.disc),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(header: true, child: Text('bk_signin_title'.tr, style: AppType.headline(context))),
          const SizedBox(height: AppSpace.xs),
          Text('bk_signin_text'.tr, style: AppType.body(context).copyWith(color: c.textMedium)),
          const SizedBox(height: AppSpace.lg),
          AppButton.secondary(
            label: 'bk_signin_google'.tr,
            icon: Icons.account_circle_outlined,
            size: AppButtonSize.lg,
            expand: true,
            onPressed: onGoogle ?? () => bkLeaveToSignIn(context, register: false, courseId: courseId),
          ),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Expanded(child: Divider(color: c.kit.line, thickness: AppBorder.hairline)),
            Flexible(
              flex: 3,
              child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Text('bk_signin_or_phone'.tr, textAlign: TextAlign.center, style: AppType.meta(context)),
            ),
            ),
            Expanded(child: Divider(color: c.kit.line, thickness: AppBorder.hairline)),
          ]),
          const SizedBox(height: AppSpace.md),
          AppButton.hot(
            label: 'bk_signin_phone'.tr,
            icon: Icons.phone_iphone_rounded,
            size: AppButtonSize.lg,
            expand: true,
            onPressed: onPhone ?? () => bkLeaveToSignIn(context, register: true, courseId: courseId),
          ),
        ],
      ),
    );
  }
}
