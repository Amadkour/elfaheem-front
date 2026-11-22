// lib/features/rewards/invited_by_field.dart — the sign-up's optional "Invited by @username" (Games v3 §3.2, CONTRACT
// §8; kill switch `rewards.referral`). Folded to one quiet button; a link `ref` does not survive a store install, so
// this is the way an invited friend says who sent them. The server ignores an unknown or self value.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/rewards/rewards_models.dart';

class InvitedByField extends StatefulWidget {
  const InvitedByField({super.key, required this.controller, this.initiallyOpen = false});

  final TextEditingController controller;
  final bool initiallyOpen;

  @override
  State<InvitedByField> createState() => _InvitedByFieldState();
}

class _InvitedByFieldState extends State<InvitedByField> {
  late bool _open = widget.initiallyOpen || widget.controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (referralOff()) return const SizedBox.shrink();
    return AnimatedSize(
      duration: AppMotion.of(context).base,
      curve: AppEase.out,
      alignment: AlignmentDirectional.topStart,
      child: !_open
          ? Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                key: const ValueKey('register.invited_by.open'),
                label: t('دعاك صديق؟', 'Invited by a friend?'),
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => setState(() => _open = true),
              ),
            )
          : AppField(
              key: const ValueKey('register.invited_by'),
              controller: widget.controller,
              label: t('دعاني (اسم المستخدم)', 'Invited by (username)'),
              hint: '@username',
              helper: t('اختياري: اسم مستخدم صديقك الذي دعاك', 'Optional: the username of the friend who invited you'),
              icon: Icons.alternate_email_rounded,
              ltr: true,
              maxLength: 31,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[@A-Za-z0-9_.]'))],
              textInputAction: TextInputAction.next,
            ),
    );
  }
}
