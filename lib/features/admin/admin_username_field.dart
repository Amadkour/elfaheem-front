// lib/features/admin/admin_username_field.dart
//
// An admin sets, changes or removes someone's @username from the user edit forms (D-071, admin edit — round 3):
// PUT /api/v1/admin/users/{id} {username}. The server validates and claims it like PUT /auth/me (400
// USERNAME_INVALID / USERNAME_RESERVED, 409 USERNAME_TAKEN + suggestions), without the person's change cooldown.
//
//   adminUsernameOn                        the field is shown (kill switch `auth.username` off)
//   adminUsernameBody(current:, text:)     the body entry: {} unchanged (key absent), {'username': null} cleared,
//                                          {'username': 'name'} set (normalized)
//   AdminUsernameField(controller:, currentUsername:, error:, onStatusChanged:)
//                                          UsernameField (the row's own name reads as current, the live check
//                                          runs) + "Remove username" / "Keep the current username" + a note that the
//                                          person is told. Hidden by the kill switch.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../config/app_config.dart';
import '../../config/theme/theme_config_provider.dart';
import '../../utils/widget/parent_component.dart';
import '../auth/auth_widgets.dart' show authText;
import '../auth/username.dart';
import '../auth/username_field.dart';

/// The admin forms show (and send) the username only while the kill switch `auth.username` is off.
bool get adminUsernameOn => !AppConfig.disableList.contains(kUsernameFeatureKey);

/// What an admin edit sends for the username: nothing when [text] is the [current] name (or [enabled] is false),
/// `null` when the field was emptied, else the normalized name.
Map<String, Object?> adminUsernameBody({
  required String? current,
  required String text,
  bool enabled = true,
}) {
  if (!enabled) return const {};
  final cur = UsernameRules.normalize(current ?? '');
  final next = UsernameRules.normalize(text);
  if (next == cur) return const {};
  return {'username': next.isEmpty ? null : next};
}

/// Why the save must wait (translated), or null: a changed name the field still checks or already refuses.
String? adminUsernameHold(Map<String, Object?> body, UsernameStatus status) {
  if (body.isEmpty || body['username'] == null || !status.blocksSubmit) return null;
  return status == UsernameStatus.checking ? 'username_wait_check'.tr : 'username_fix_first'.tr;
}

class AdminUsernameField extends StatelessWidget {
  const AdminUsernameField({
    super.key,
    required this.controller,
    this.currentUsername,
    this.error,
    this.onStatusChanged,
    this.checker,
    this.enabled = true,
  });

  final TextEditingController controller;

  /// The edited person's username (the row's): typing it again is "current", not "taken".
  final String? currentUsername;

  /// A USERNAME_* error of the last save, shown on the field with its suggestions.
  final UsernameError? error;
  final ValueChanged<UsernameStatus>? onStatusChanged;

  /// Replaces [UsernameApi.check] (tests).
  final Future<UsernameCheck> Function(String username)? checker;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final current = UsernameRules.normalize(currentUsername ?? '');
    return ParentComponent(
      featureKey: kUsernameFeatureKey,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs, bottom: AppSpace.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            UsernameField(
              controller: controller,
              currentUsername: currentUsername,
              error: error,
              onStatusChanged: onStatusChanged,
              checker: checker,
              enabled: enabled,
              label: 'username_label'.tr,
            ),
            if (current.isNotEmpty && enabled)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, v, _) {
                  final cleared = UsernameRules.normalize(v.text).isEmpty;
                  final ink = cleared ? c.primary : c.danger;
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('admin.username.remove'),
                      onPressed: () {
                        final s = cleared ? current : '';
                        controller.value = TextEditingValue(
                          text: s,
                          selection: TextSelection.collapsed(offset: s.length),
                        );
                      },
                      style: TextButton.styleFrom(minimumSize: const Size(48, 44), foregroundColor: ink),
                      icon: Icon(cleared ? Icons.undo_rounded : Icons.person_remove_outlined, size: 18),
                      label: Text(
                        cleared ? 'admin_username_keep'.tr : 'username_remove'.tr,
                        style: authText(13, w: FontWeight.w700, c: ink),
                      ),
                    ),
                  );
                },
              ),
            Text(
              'admin_username_note'.tr,
              style: authText(12, c: c.textLight, h: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
