// The "Two-step verification" settings entry for every role the server lets use MFA (back/services/mfa_service.py:
// MFA_ALLOWED_ROLES, by default super-admin / admin / developer / org-admin / org-staff, plus every role in
// MFA_REQUIRED_ROLES). The app does not hard-code that list: the entry asks GET /auth/mfa/status and shows itself
// only when the answer is `allowed` (or MFA is already on), so a server change of the role lists needs no app update.
//
//   const MfaSettingsEntry()   // profile screen, org settings ("More") — opens AdminMfaPage
//
// Feature key `profile.mfa` hides it. Never shown to guests or while a super admin views as someone else (the MFA
// routes always act on the caller's own account). [MfaSecurityGroup] is the plain-values part the layout test pumps.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';

import '../admin/admin_common.dart' show t;
import '../admin/admin_mfa_page.dart' show AdminMfaPage, mfaEntryLabel;
import 'mfa.dart';

/// Whether the settings entry is offered for [s]: the role may enroll, or MFA is on (so it can be managed).
bool mfaEntryVisible(MfaStatus s) => s.allowed || s.enabled || s.required;

/// The pill next to the entry: On · Required (not on yet) · Off.
(String, bool) mfaEntryState(MfaStatus s) => s.enabled
    ? (t('مفعّل', 'On'), true)
    : s.required
        ? (t('مطلوب', 'Required'), false)
        : (t('غير مفعّل', 'Off'), false);

/// "Security" group with the single MFA row, from plain values.
class MfaSecurityGroup extends StatelessWidget {
  const MfaSecurityGroup({super.key, required this.status, this.onTap});

  final MfaStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (label, on) = mfaEntryState(status);
    final color = on ? c.success : (status.required ? c.warning : c.textMedium);
    return AppSettingsGroup(title: t('الأمان', 'Security'), icon: Icons.shield_rounded, children: [
      AppSettingsTile(
        key: const ValueKey('mfa.entry'),
        icon: Icons.phonelink_lock_rounded,
        color: c.primary,
        label: mfaEntryLabel(),
        onTap: onTap,
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: AppBadgePill(label, color: color),
        ),
      ),
    ]);
  }
}

/// Loads the caller's MFA status and shows [MfaSecurityGroup] (followed by [gap]) when the account may use MFA;
/// nothing otherwise, also while loading or when the status cannot be read.
class MfaSettingsEntry extends StatefulWidget {
  const MfaSettingsEntry({super.key, this.api, this.gap = 20, this.padding = EdgeInsets.zero});

  /// For tests; defaults to [RemoteMfaApi] with the stored session.
  final MfaApi? api;

  /// Space below the group when it is shown.
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  State<MfaSettingsEntry> createState() => _MfaSettingsEntryState();
}

class _MfaSettingsEntryState extends State<MfaSettingsEntry> {
  late final MfaApi _api = widget.api ?? RemoteMfaApi();
  MfaStatus? _status;

  bool get _blocked => GuestState.active || ViewAsState.active;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_blocked) return;
    try {
      final s = await _api.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // optional entry: no status (offline, older server) → no row; the page itself reports errors
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdminMfaPage(api: widget.api)));
    if (mounted) await _load(); // turned on / off in there
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (_blocked || s == null || !mfaEntryVisible(s)) return const SizedBox.shrink();
    return ParentComponent(
      featureKey: 'profile.mfa',
      child: Padding(
        padding: widget.padding,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MfaSecurityGroup(status: s, onTap: _open),
          SizedBox(height: widget.gap),
        ]),
      ),
    );
  }
}
