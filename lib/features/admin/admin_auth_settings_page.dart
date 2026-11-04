// features/admin/admin_auth_settings_page.dart
// Admin: how accounts are verified, what the login form accepts, how codes are sent.
// Open it from the admin services (Support & security):
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuthSettingsPage()));
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../auth/verify_way.dart';
import 'admin_common.dart' show t;
import 'admin_page.dart';

class AdminAuthSettingsPage extends StatefulWidget {
  const AdminAuthSettingsPage({super.key});

  @override
  State<AdminAuthSettingsPage> createState() => _AdminAuthSettingsPageState();
}

class _AdminAuthSettingsPageState extends State<AdminAuthSettingsPage> {
  final _api = ApiClient();
  bool _loading = true, _saving = false;

  /// Set when the load failed: the page shows the error and Retry and NO form (a form with defaults and a live
  /// Save would overwrite the real sign-in settings).
  Object? _error;
  DateTime? _loadedAt;

  /// Offering order when several ways are allowed: Telegram > E-mail > WhatsApp > SMS.
  static const _order = [VerifyWay.telegram, VerifyWay.email, VerifyWay.whatsapp, VerifyWay.sms];

  final Set<String> _ways = {'email'};
  final Set<String> _login = {'email'};
  bool _requireAll = false;
  String _default = 'auto'; // auto | a selected way
  String _waDelivery = 'auto'; // auto | link | code
  Map _avail = const {};

  /// "Sign in with username" (`username_login`); null = the server has no such setting yet (tile hidden, not sent).
  bool? _usernameLogin;

  /// What the server held at the last load / save: the unsaved-changes guard and the "login identifiers changed" check.
  String _saved = '';
  Set<String> _savedLogin = {};
  bool? _savedUsername;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _snapshot() => [
        (_ways.toList()..sort()).join(','),
        (_login.toList()..sort()).join(','),
        _requireAll,
        _default,
        _waDelivery,
        _usernameLogin,
      ].join('|');

  bool get _dirty => !_loading && _error == null && _snapshot() != _saved;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.get('/api/v1/admin/settings');
      if (r is! Map) throw StateError('settings');
      final w = r['verification_methods'];
      if (w is List && w.isNotEmpty) {
        _ways
          ..clear()
          ..addAll(w.map((e) => e.toString()));
      }
      final l = r['login_identifiers'];
      if (l is List && l.isNotEmpty) {
        _login
          ..clear()
          ..addAll(l.map((e) => e.toString()));
      }
      _requireAll = r['verification_require_all'] == true;
      _default = (r['default_verification_way'] ?? 'auto').toString();
      _waDelivery = (r['whatsapp_delivery'] ?? 'auto').toString();
      if (r.containsKey('username_login')) _usernameLogin = r['username_login'] != false;
      _avail = r['availability'] is Map ? r['availability'] as Map : const {};
      _markSaved();
      _loadedAt = DateTime.now();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _markSaved() {
    _saved = _snapshot();
    _savedLogin = {..._login};
    _savedUsername = _usernameLogin;
  }

  Future<void> _save() async {
    if (_saving || _error != null) return;
    final loginChanged = !(_savedLogin.length == _login.length && _savedLogin.containsAll(_login)) ||
        _savedUsername != _usernameLogin;
    if (loginChanged) {
      final ok = await appConfirm(
        context,
        message: t(
          'سيتغيّر ما يقبله نموذج تسجيل الدخول (البريد / الهاتف / اسم المستخدم). من يستخدم طريقة تم إيقافها لن يتمكن من الدخول بها. هل تريد الحفظ؟',
          'The sign-in form will accept different identifiers (e-mail / phone / username). People who sign in with a method you switched off will no longer be able to use it. Save?',
        ),
        danger: true,
        confirmLabel: 'save'.tr,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      final r = await _api.put('/api/v1/admin/settings', body: {
        'verification_methods': _order.where((w) => _ways.contains(w.name)).map((w) => w.name).toList(),
        'verification_require_all': _requireAll && _hasEmail && _hasPhone,
        'default_verification_way': _ways.contains(_default) ? _default : 'auto',
        'whatsapp_delivery': _waDelivery,
        'login_identifiers': ['email', 'phone'].where(_login.contains).toList(),
        'username_login': ?_usernameLogin,
      });
      if (r is Map && r['availability'] is Map) _avail = r['availability'] as Map;
      _markSaved();
      showAppNotice('auth_saved'.tr);
    } catch (e) {
      showAppNotice(appErrorMessage(e), error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  bool get _hasEmail => _ways.contains('email');
  bool get _hasPhone => _ways.any((w) => w != 'email');

  bool _ok(String key) => (_avail[key] is Map ? _avail[key]['ok'] : true) != false;

  List _missing(String key) =>
      (_avail[key] is Map && _avail[key]['missing'] is List) ? _avail[key]['missing'] as List : const [];

  /// What the server does for a way: "code" or "link" (WhatsApp follows the setting).
  String _delivery(VerifyWay w) {
    switch (w) {
      case VerifyWay.telegram:
        return 'link';
      case VerifyWay.whatsapp:
        if (_waDelivery != 'auto') return _waDelivery;
        if (_ok('whatsapp_link')) return 'link';
        return _ok('whatsapp_code') ? 'code' : 'link';
      default:
        return 'code';
    }
  }

  String _availKey(VerifyWay w) => switch (w) {
        VerifyWay.email => 'email',
        VerifyWay.telegram => 'telegram',
        VerifyWay.sms => 'sms',
        VerifyWay.whatsapp => _delivery(w) == 'link' ? 'whatsapp_link' : 'whatsapp_code',
      };

  String _name(VerifyWay w) => 'verify_way_${w.name}'.tr;

  void _toggleWay(VerifyWay w, bool on) {
    if (!on && _ways.length <= 1) {
      showAppNotice('auth_keep_one'.tr, error: true);
      return;
    }
    setState(() {
      if (on) {
        _ways.add(w.name);
      } else {
        _ways.remove(w.name);
        if (_default == w.name) _default = 'auto';
      }
    });
  }

  void _toggleLogin(String key, bool on) {
    if (!on && _login.length <= 1) {
      showAppNotice('auth_keep_one'.tr, error: true);
      return;
    }
    setState(() => on ? _login.add(key) : _login.remove(key));
  }

  // ── pieces ───────────────────────────────────────────────────────────────

  /// The sentence under a way that the server cannot offer yet. The raw setting names (env variables) only
  /// appear in a small "for the developer" line.
  Widget _notConfigured(VerifyWay w) {
    final missing = _missing(_availKey(w));
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          t('غير مفعّلة على الخادم بعد، ولن تظهر للمستخدمين حتى يتم إعدادها.',
              'Not set up on the server yet, so people will not be offered it until it is.'),
          style: AppType.meta(context).copyWith(color: c.warning),
        ),
        if (missing.isNotEmpty)
          Text(
            t('للمطوّر: ', 'For the developer: ') + missing.join(', '),
            style: AppType.overline(context),
          ),
      ]),
    );
  }

  Widget _wayTile(VerifyWay w) {
    final on = _ways.contains(w.name);
    final good = _ok(_availKey(w));
    final d = _delivery(w);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSwitchTile(
        icon: w.icon,
        title: _name(w),
        subtitle: good ? (d == 'link' ? 'auth_delivery_link'.tr : 'auth_delivery_code'.tr) : null,
        value: on,
        onChanged: (v) => _toggleWay(w, v),
      ),
      if (!good) _notConfigured(w),
    ]);
  }

  Widget _waOption(String value, String titleKey, String descKey, IconData icon) {
    final c = context.colors;
    final selected = _waDelivery == value;
    return InkWell(
      borderRadius: AppRadius.cardAll,
      onTap: () => setState(() => _waDelivery = value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(children: [
            Icon(icon, color: selected ? c.primary : c.textLight, size: AppIconSize.lg),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titleKey.tr, style: AppType.row(context)),
                Text(descKey.tr, style: AppType.meta(context)),
              ]),
            ),
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? c.primary : c.textLight,
            ),
          ]),
        ),
      ),
    );
  }

  Widget _section(String title, String hint, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: AppSection(
          title: title,
          subtitle: hint,
          child: AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ),
      );

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // whole page re-translates when the language changes
    final selectedWays = _order.where((w) => _ways.contains(w.name)).toList();
    final failed = !_loading && _error != null;

    return AdminPage(
      title: 'auth_settings_title'.tr,
      subtitle: 'auth_settings_sub'.tr,
      icon: Icons.verified_user_rounded,
      onRefresh: _loading || _saving ? null : _load,
      updatedAt: _loadedAt,
      dirty: _dirty,
      // no Save at all while the settings could not be loaded
      primaryAction: failed || _loading
          ? null
          : AppButton.primary(label: 'save'.tr, busy: _saving, onPressed: _dirty ? _save : null),
      body: _loading
          ? const AppListSkeleton()
          : failed
              ? Center(child: AppErrorState(message: appErrorMessage(_error), onRetry: _load))
              : ListView(
                  padding: AdminPage.bodyPadding(context),
                  children: [
                    // 1 ─ verification ways
                    _section('auth_verify_by'.tr, 'auth_verify_by_hint'.tr, [
                      for (final w in _order) _wayTile(w),
                      if (_hasEmail && _hasPhone)
                        AppSwitchTile(
                          icon: Icons.lock_person_rounded,
                          title: 'auth_require_all'.tr,
                          subtitle: 'auth_require_all_hint'.tr,
                          value: _requireAll,
                          onChanged: (v) => setState(() => _requireAll = v),
                        ),
                    ]),

                    // 2 ─ offer first
                    _section('auth_offer_first'.tr, 'auth_offer_first_hint'.tr, [
                      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                        AppChoiceChip(
                          label: 'auth_automatic'.tr,
                          icon: Icons.auto_awesome_rounded,
                          selected: _default == 'auto',
                          onTap: () => setState(() => _default = 'auto'),
                        ),
                        for (final w in selectedWays)
                          AppChoiceChip(
                            label: _name(w),
                            icon: w.icon,
                            selected: _default == w.name,
                            onTap: () => setState(() => _default = w.name),
                          ),
                      ]),
                    ]),

                    // 3 ─ WhatsApp delivery
                    if (_ways.contains('whatsapp'))
                      _section('auth_wa_title'.tr, 'auth_wa_hint'.tr, [
                        _waOption('auto', 'auth_wa_auto', 'auth_wa_auto_d', Icons.auto_awesome_rounded),
                        _waOption('link', 'auth_wa_link', 'auth_wa_link_d', Icons.link_rounded),
                        _waOption('code', 'auth_wa_code', 'auth_wa_code_d', Icons.pin_outlined),
                      ]),

                    // 4 ─ login identifiers
                    _section('auth_login_with'.tr, 'auth_login_with_hint'.tr, [
                      AppSwitchTile(
                        icon: Icons.alternate_email_rounded,
                        title: 'auth_login_email'.tr,
                        value: _login.contains('email'),
                        onChanged: (v) => _toggleLogin('email', v),
                      ),
                      AppSwitchTile(
                        icon: Icons.phone_iphone_rounded,
                        title: 'auth_login_phone'.tr,
                        value: _login.contains('phone'),
                        onChanged: (v) => _toggleLogin('phone', v),
                      ),
                      // independent of the two above: a username works next to e-mail and / or phone
                      if (_usernameLogin != null)
                        AppSwitchTile(
                          icon: Icons.person_pin_rounded,
                          title: 'auth_login_username'.tr,
                          subtitle: 'auth_login_username_hint'.tr,
                          value: _usernameLogin!,
                          onChanged: (v) => setState(() => _usernameLogin = v),
                        ),
                    ]),
                  ],
                ),
    );
  }
}
