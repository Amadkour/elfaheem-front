// features/admin/admin_auth_settings_page.dart
// Admin: how accounts are verified, what the login form accepts, how codes are sent.
// Open it from the admin services (Support & security):
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuthSettingsPage()));
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/student/courses/details/components/app_responsive.dart'
    show Breakpoints;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:provider/provider.dart';

import '../auth/verify_way.dart';
import 'admin_common.dart';
import 'admin_premium_widgets.dart';

class AdminAuthSettingsPage extends StatefulWidget {
  const AdminAuthSettingsPage({super.key});

  @override
  State<AdminAuthSettingsPage> createState() => _AdminAuthSettingsPageState();
}

class _AdminAuthSettingsPageState extends State<AdminAuthSettingsPage> {
  final _api = ApiClient();
  bool _loading = true, _saving = false;

  /// Offering order when several ways are allowed: Telegram > E-mail > WhatsApp > SMS.
  static const _order = [VerifyWay.telegram, VerifyWay.email, VerifyWay.whatsapp, VerifyWay.sms];

  final Set<String> _ways = {'email'};
  final Set<String> _login = {'email'};
  bool _requireAll = false;
  String _default = 'auto'; // auto | a selected way
  String _waDelivery = 'auto'; // auto | link | code
  Map _avail = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/v1/admin/settings');
      if (r is Map) {
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
        _avail = r['availability'] is Map ? r['availability'] as Map : const {};
      }
    } catch (e) {
      toast('$e', error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await _api.put('/api/v1/admin/settings', body: {
        'verification_methods':
            _order.where((w) => _ways.contains(w.name)).map((w) => w.name).toList(),
        'verification_require_all': _requireAll && _hasEmail && _hasPhone,
        'default_verification_way': _ways.contains(_default) ? _default : 'auto',
        'whatsapp_delivery': _waDelivery,
        'login_identifiers': ['email', 'phone'].where(_login.contains).toList(),
      });
      if (r is Map && r['availability'] is Map) _avail = r['availability'] as Map;
      toast('auth_saved'.tr);
    } catch (e) {
      toast('$e', error: true);
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
      toast('auth_keep_one'.tr, error: true);
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
      toast('auth_keep_one'.tr, error: true);
      return;
    }
    setState(() => on ? _login.add(key) : _login.remove(key));
  }

  // ── pieces ───────────────────────────────────────────────────────────────
  Widget _switch(bool value, ValueChanged<bool> onChanged) {
    final c = context.colors;
    return Switch.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: c.primary,
      thumbColor: const WidgetStatePropertyAll(Colors.white),
    );
  }

  Widget _wayTile(VerifyWay w) {
    final on = _ways.contains(w.name);
    final key = _availKey(w);
    final good = _ok(key);
    final d = _delivery(w);

    return PremiumSelectTile(
      selected: on,
      color: w.brand,
      onTap: () => _toggleWay(w, !on),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: w.brand.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(w.icon, color: w.brand, size: 22),
      ),
      title: _name(w),
      subtitle: good
          ? null
          : '${trp('auth_not_configured', {'missing': _missing(key).join(', ')})} ${'auth_not_offered'.tr}',
      subtitleColor: context.colors.warning,
      footer: good
          ? Wrap(spacing: 6, children: [
              StatusChip(
                d == 'link' ? 'auth_delivery_link'.tr : 'auth_delivery_code'.tr,
                d == 'link' ? AdminPalette.green.last : AdminPalette.blue.last,
              ),
            ])
          : null,
      trailing: _switch(on, (v) => _toggleWay(w, v)),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? avatar,
  }) {
    final c = context.colors;
    return ChoiceChip(
      avatar: avatar,
      label: Text(
        label,
        style: TextStyle(
          fontFamily: 'tajawal',
          fontWeight: FontWeight.w700,
          color: selected ? Colors.white : c.textDark,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      selectedColor: c.primary,
      backgroundColor: c.inputBg,
      side: BorderSide(color: selected ? c.primary : c.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (_) => onTap(),
    );
  }

  Widget _waOption(String value, String titleKey, String descKey, IconData icon) {
    final c = context.colors;
    final selected = _waDelivery == value;
    return PremiumSelectTile(
      selected: selected,
      color: c.primary,
      onTap: () => setState(() => _waDelivery = value),
      leading: Icon(icon, color: selected ? c.primary : c.textLight, size: 24),
      title: titleKey.tr,
      subtitle: descKey.tr,
      trailing: Icon(
        selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
        color: selected ? c.primary : c.textLight,
      ),
    );
  }

  Widget _loginTile(String key, IconData icon, String titleKey) {
    final on = _login.contains(key);
    final c = context.colors;
    return PremiumSelectTile(
      selected: on,
      color: c.primary,
      onTap: () => _toggleLogin(key, !on),
      leading: Icon(icon, color: on ? c.primary : c.textLight, size: 24),
      title: titleKey.tr,
      trailing: _switch(on, (v) => _toggleLogin(key, v)),
    );
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>(); // whole page re-translates when the language changes
    final c = context.colors;
    final selectedWays = _order.where((w) => _ways.contains(w.name)).toList();

    return BasePage(
      useWebCard: true,
      appBar: ScreenAppBar(title: 'auth_settings_title'.tr),
      bottomNavigationBar: _loading
          ? null
          : PremiumSaveBar(label: 'save'.tr, loading: _saving, onPressed: _save),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    PremiumHero(
                      icon: Icons.verified_user_rounded,
                      colors: AdminPalette.indigo,
                      title: 'auth_settings_title'.tr,
                      subtitle: 'auth_settings_sub'.tr,
                      footer: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final w in selectedWays) HeroPill(_name(w), icon: w.icon),
                        ],
                      ),
                    ),

                    // 1 ─ verification ways
                    PremiumCard(
                      icon: Icons.mark_email_read_rounded,
                      colors: AdminPalette.blue,
                      title: 'auth_verify_by'.tr,
                      hint: 'auth_verify_by_hint'.tr,
                      children: [
                        for (final w in _order) _wayTile(w),
                        if (_hasEmail && _hasPhone)
                          PremiumSwitchRow(
                            icon: Icons.lock_person_rounded,
                            title: 'auth_require_all'.tr,
                            subtitle: 'auth_require_all_hint'.tr,
                            value: _requireAll,
                            onChanged: (v) => setState(() => _requireAll = v),
                          ),
                      ],
                    ),

                    // 2 ─ offer first
                    PremiumCard(
                      icon: Icons.star_rounded,
                      colors: AdminPalette.orange,
                      title: 'auth_offer_first'.tr,
                      hint: 'auth_offer_first_hint'.tr,
                      children: [
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _chip(
                            label: 'auth_automatic'.tr,
                            selected: _default == 'auto',
                            avatar: Icon(Icons.auto_awesome_rounded,
                                size: 16,
                                color: _default == 'auto' ? Colors.white : c.textMedium),
                            onTap: () => setState(() => _default = 'auto'),
                          ),
                          for (final w in selectedWays)
                            _chip(
                              label: _name(w),
                              selected: _default == w.name,
                              avatar: Icon(w.icon,
                                  size: 16,
                                  color: _default == w.name ? Colors.white : w.brand),
                              onTap: () => setState(() => _default = w.name),
                            ),
                        ]),
                      ],
                    ),

                    // 3 ─ WhatsApp delivery
                    if (_ways.contains('whatsapp'))
                      PremiumCard(
                        icon: Icons.chat_rounded,
                        colors: AdminPalette.green,
                        title: 'auth_wa_title'.tr,
                        hint: 'auth_wa_hint'.tr,
                        children: [
                          _waOption('auto', 'auth_wa_auto', 'auth_wa_auto_d',
                              Icons.auto_awesome_rounded),
                          _waOption(
                              'link', 'auth_wa_link', 'auth_wa_link_d', Icons.link_rounded),
                          _waOption('code', 'auth_wa_code', 'auth_wa_code_d',
                              Icons.pin_outlined),
                        ],
                      ),

                    // 4 ─ login identifiers
                    PremiumCard(
                      icon: Icons.login_rounded,
                      colors: AdminPalette.violet,
                      title: 'auth_login_with'.tr,
                      hint: 'auth_login_with_hint'.tr,
                      children: [
                        _loginTile('email', Icons.alternate_email_rounded, 'auth_login_email'),
                        _loginTile('phone', Icons.phone_iphone_rounded, 'auth_login_phone'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
