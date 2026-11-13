// The "Two-step verification" settings entry for every role the server lets use MFA (back/services/mfa_service.py:
// MFA_ALLOWED_ROLES, by default super-admin / admin / developer / org-admin / org-staff, plus every role in
// MFA_REQUIRED_ROLES). The app does not hard-code that list: the entry asks GET /auth/mfa/status and shows itself
// only when the answer is `allowed` (or MFA is already on), so a server change of the role lists needs no app update.
//
//   const MfaSettingsEntry()   // profile screen, org settings ("More") — opens AdminMfaPage
//
// Feature key `profile.mfa` hides it. Never shown to guests or while a super admin views as someone else (the MFA
// routes always act on the caller's own account). [MfaSecurityGroup] is the plain-values part the layout test pumps.
//
// The same "Security" group holds the fingerprint / Face ID sign-in switch (D-082, biometric.dart) for EVERY role on
// a phone that supports it (Android 9+ / iOS with an enrolled fingerprint or face; never on web), so the two call sites
// above carry it without a change. Feature key `auth.biometric` hides that row.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/shared/guest/guest_state.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t;
import '../admin/admin_mfa_page.dart' show AdminMfaPage, mfaEntryLabel;
import 'auth_provider.dart';
import 'biometric.dart';
import 'biometric_widgets.dart' show biometricEnrollNotice;
import 'mfa.dart';
import 'reauth_sheet.dart';

/// Whether the settings entry is offered for [s]: the role may enroll, or MFA is on (so it can be managed).
bool mfaEntryVisible(MfaStatus s) => s.allowed || s.enabled || s.required;

/// The pill next to the entry: On · Required (not on yet) · Off.
(String, bool) mfaEntryState(MfaStatus s) => s.enabled
    ? (t('مفعّل', 'On'), true)
    : s.required
        ? (t('مطلوب', 'Required'), false)
        : (t('غير مفعّل', 'Off'), false);

/// The fingerprint / Face ID row's state (D-082), plain values.
class BiometricRowState {
  const BiometricRowState({required this.kind, required this.on, this.busy = false});

  final BiometricKind kind;
  final bool on;
  final bool busy;
}

/// "Security" group from plain values: the MFA row (when [status] says the account may use MFA) and the fingerprint
/// sign-in switch (when [biometric] is given: this phone supports it).
class MfaSecurityGroup extends StatelessWidget {
  const MfaSecurityGroup({super.key, this.status, this.onTap, this.biometric, this.onBiometricChanged, this.rowsOnly = false});

  /// Only the rows, no "Security" heading or card: they join a section of the page around them (the profile's
  /// "Security & account" card, D-714).
  final bool rowsOnly;

  final MfaStatus? status;
  final VoidCallback? onTap;
  final BiometricRowState? biometric;
  final ValueChanged<bool>? onBiometricChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    final bio = biometric;
    final rows = <Widget>[
      if (s != null && mfaEntryVisible(s))
        Builder(builder: (context) {
          final (label, on) = mfaEntryState(s);
          final color = on ? c.success : (s.required ? c.warning : c.textMedium);
          return AppSettingsTile(
            key: const ValueKey('mfa.entry'),
            icon: Icons.phonelink_lock_rounded,
            color: c.primary,
            label: mfaEntryLabel(),
            featureKey: 'profile.mfa',
            onTap: onTap,
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: AppBadgePill(label, color: color),
            ),
          );
        }),
      if (bio != null)
        AppSettingsTile(
          key: const ValueKey('biometric.entry'),
          icon: biometricIcon(bio.kind),
          color: c.primary,
          label: biometricSettingLabel(bio.kind),
          subtitle: 'bio_setting_sub'.tr,
          featureKey: kBiometricFeatureKey,
          keywords: 'fingerprint face id touch id biometric بصمة وجه',
          onTap: bio.busy || onBiometricChanged == null ? null : () => onBiometricChanged!(!bio.on),
          trailing: bio.busy
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary),
                )
              : AppSwitch(
                  value: bio.on,
                  semanticLabel: biometricSettingLabel(bio.kind),
                  onChanged: onBiometricChanged,
                ),
        ),
    ];
    if (rowsOnly) {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) i == 0 ? rows[i] : AppSettingsRule(child: rows[i]),
      ]);
    }
    return AppSettingsGroup(title: t('الأمان', 'Security'), icon: Icons.shield_rounded, children: rows);
  }
}

/// Loads the caller's MFA status and this phone's fingerprint support, and shows [MfaSecurityGroup] (followed by
/// [gap]) when either row applies; nothing otherwise, also while loading or when the status cannot be read.
class MfaSettingsEntry extends StatefulWidget {
  const MfaSettingsEntry({super.key, this.api, this.gap = 20, this.padding = EdgeInsets.zero, this.rowsOnly = false});

  /// The rows only (see [MfaSecurityGroup.rowsOnly]); [gap] and [padding] are not used then.
  final bool rowsOnly;

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
  final _bio = BiometricAuth.instance;
  MfaStatus? _status;
  bool _bioBusy = false;

  bool get _blocked => GuestState.active || ViewAsState.active;

  @override
  void initState() {
    super.initState();
    _bio.addListener(_onBio);
    _load();
    if (!_blocked && !_bio.loaded) _bio.load();
  }

  @override
  void dispose() {
    _bio.removeListener(_onBio);
    super.dispose();
  }

  void _onBio() {
    if (mounted) setState(() {});
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

  /// The fingerprint switch: on = the system prompt + a new key (the password sheet when the login's enrol token is
  /// gone); off = the key is revoked on the server and forgotten here.
  Future<void> _setBiometric(bool on) async {
    final user = context.read<MyAuthProvider>().currentUser;
    if (user == null || _bioBusy) return;
    setState(() => _bioBusy = true);
    try {
      if (!on) {
        await _bio.disable();
        showAppNotice('bio_disabled_notice'.tr);
        return;
      }
      final identifier = user.username != null ? '@${user.username}' : user.gmail;
      var r = await _bio.enroll(userId: user.id, name: user.name, identifier: identifier, imageUrl: user.imageUrl);
      if (r.outcome == BiometricEnrollOutcome.needsPassword && mounted) {
        final re = await askReauth(context);
        if (re == null) return;
        r = await _bio.enroll(
          userId: user.id,
          name: user.name,
          identifier: identifier,
          imageUrl: user.imageUrl,
          password: re.password,
          code: re.mfaCode,
          confirm: false, // the prompt was answered a moment ago
        );
      }
      if (r.outcome == BiometricEnrollOutcome.enabled) await _bio.setDeclined(user.id, false);
      biometricEnrollNotice(r);
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_blocked) return const SizedBox.shrink();
    final s = _status;
    final showMfa = s != null && mfaEntryVisible(s) && !AppConfig.disableList.contains('profile.mfa');
    final userId = context.select<MyAuthProvider, int?>((a) => a.currentUser?.id);
    final showBio = _bio.supported && _bio.featureOn && userId != null;
    if (!showMfa && !showBio) return const SizedBox.shrink();
    if (widget.rowsOnly) {
      return MfaSecurityGroup(
        rowsOnly: true,
        status: showMfa ? s : null,
        onTap: _open,
        biometric: showBio ? BiometricRowState(kind: _bio.kind, on: _bio.record?.userId == userId, busy: _bioBusy) : null,
        onBiometricChanged: _setBiometric,
      );
    }
    return Padding(
      padding: widget.padding,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        MfaSecurityGroup(
          status: showMfa ? s : null,
          onTap: _open,
          biometric: showBio
              ? BiometricRowState(kind: _bio.kind, on: _bio.record?.userId == userId, busy: _bioBusy)
              : null,
          onBiometricChanged: _setBiometric,
        ),
        SizedBox(height: widget.gap),
      ]),
    );
  }
}
