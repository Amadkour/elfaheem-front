// features/auth/reauth_sheet.dart
// ─────────────────────────────────────────────────────────────────────────────
// The small "confirm it's you" sheet: the current password (+ the two-step code
// for MFA accounts) that the server requires before a sensitive account change —
// deleting the account, changing the phone number (audit S9 / S1). The caller
// sends the values with its request; the server answers 400 REAUTH_REQUIRED when
// they are missing or wrong, which `apiErrorText` turns into a sentence.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../design/app_inputs.dart';
import '../../design/app_kit.dart';

/// What the person typed: the password, and the two-step code when they gave one.
class Reauth {
  const Reauth({required this.password, this.mfaCode});

  final String password;
  final String? mfaCode;
}

/// Asks for the current password (and an optional two-step code). Null when dismissed.
Future<Reauth?> askReauth(BuildContext context) =>
    showAppSheet<Reauth>(context, (_) => const ReauthSheet());

class ReauthSheet extends StatefulWidget {
  const ReauthSheet({super.key});

  @override
  State<ReauthSheet> createState() => _ReauthSheetState();
}

class _ReauthSheetState extends State<ReauthSheet> {
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
    Navigator.pop(context, Reauth(password: p, mfaCode: c.isEmpty ? null : c));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader('reauth_title'.tr),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('reauth_body'.tr, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 12),
                // minLength 1: an existing password may predate the 8-character rule
                AppPasswordField(controller: _password, label: 'current_password'.tr, minLength: 1),
                AppField(controller: _code, label: 'reauth_mfa_code'.tr, keyboard: TextInputType.number),
                const SizedBox(height: 8),
                AppPrimaryButton(label: 'confirm'.tr, onPressed: _submit),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
