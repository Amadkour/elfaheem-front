// features/auth/reauth_sheet.dart
// ─────────────────────────────────────────────────────────────────────────────
// The small "confirm it's you" sheet: the current password (+ the two-step code
// for MFA accounts) that the server requires before a sensitive account change —
// deleting the account, changing the phone number (audit S9 / S1). The caller
// sends the values with its request; the server answers 400 REAUTH_REQUIRED when
// they are missing or wrong, which `apiErrorText` turns into a sentence.
// `ReauthSheetBody` takes plain values so the layout harness can pump it.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../design/app_kit.dart';
import 'auth_widgets.dart' show ScreenIcon;

/// What the person typed: the password, and the two-step code when they gave one.
class Reauth {
  const Reauth({required this.password, this.mfaCode});

  final String password;
  final String? mfaCode;
}

/// Asks for the current password (and an optional two-step code). Null when dismissed.
Future<Reauth?> askReauth(BuildContext context) => showAppSheet<Reauth>(
      context,
      (ctx) => ReauthSheetBody(onSubmit: (r) => Navigator.pop(ctx, r)),
    );

/// The sheet's content: header, hint, password field, the two-step code field when [showMfa], Confirm.
class ReauthSheetBody extends StatefulWidget {
  const ReauthSheetBody({super.key, required this.onSubmit, this.showMfa = true});

  final void Function(Reauth) onSubmit;

  /// The app has no cached MFA flag, so the optional code field is shown by default.
  final bool showMfa;

  @override
  State<ReauthSheetBody> createState() => _ReauthSheetBodyState();
}

class _ReauthSheetBodyState extends State<ReauthSheetBody> {
  final _password = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _password.text;
    if (p.isEmpty) return;
    final c = _code.text.trim();
    widget.onSubmit(Reauth(password: p, mfaCode: c.isEmpty ? null : c));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader('reauth_title'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ScreenIcon(icon: Icons.verified_user_rounded),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text('reauth_body'.tr, style: AppType.body(context).copyWith(height: 1.55)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                // minLength 1: an existing password may predate the 8-character rule
                AppPasswordField(controller: _password, label: 'current_password'.tr, minLength: 1),
                if (widget.showMfa)
                  AppField(controller: _code, label: 'reauth_mfa_code'.tr, keyboard: TextInputType.number),
                const SizedBox(height: AppSpace.xs),
                AppPrimaryButton(label: 'confirm'.tr, onPressed: _submit),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
