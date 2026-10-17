// features/admin/admin_auth_settings_page.dart
// Admin: how accounts are verified, what the login form accepts, how codes are sent.
// Open it from your admin settings list:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuthSettingsPage()));
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../auth/verify_way.dart';

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
      _toast('$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final r = await _api.put('/api/v1/admin/settings', body: {
        'verification_methods': _order.where((w) => _ways.contains(w.name)).map((w) => w.name).toList(),
        'verification_require_all': _requireAll && _hasEmail && _hasPhone,
        'default_verification_way': _ways.contains(_default) ? _default : 'auto',
        'whatsapp_delivery': _waDelivery,
        'login_identifiers': ['email', 'phone'].where(_login.contains).toList(),
      });
      if (r is Map && r['availability'] is Map) _avail = r['availability'] as Map;
      _toast('Saved');
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

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

  static const _names = {
    VerifyWay.email: 'Email',
    VerifyWay.telegram: 'Telegram',
    VerifyWay.whatsapp: 'WhatsApp',
    VerifyWay.sms: 'SMS',
  };

  Widget _card(String title, String hint, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          ...children,
        ]),
      ),
    );
  }

  Widget _wayTile(VerifyWay w) {
    final on = _ways.contains(w.name);
    final key = _availKey(w);
    final good = _ok(key);
    final d = _delivery(w);
    return CheckboxListTile(
      value: on,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.trailing,
      secondary: CircleAvatar(
        backgroundColor: w.brand.withValues(alpha: 0.14),
        child: Icon(w.icon, color: w.brand, size: 20),
      ),
      title: Text(_names[w]!),
      subtitle: Text(
        !good
            ? 'Not configured on the server — missing: ${_missing(key).join(', ')}. '
                'It will not be offered to users until this is set.'
            : (d == 'link' ? 'Link — free, the user messages us' : 'Code — we send a code'),
        style: TextStyle(color: good ? null : Colors.orange.shade800),
      ),
      onChanged: (v) => setState(() {
        if (v == true) {
          _ways.add(w.name);
        } else if (_ways.length > 1) {
          _ways.remove(w.name);
          if (_default == w.name) _default = 'auto';
        } else {
          _toast('Keep at least one way');
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification & login')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _card(
                'Verify new accounts by',
                'Tick every way users may choose. When several are ticked they are offered in this '
                    'order: Telegram, Email, WhatsApp, SMS. Sending is automatic for each way.',
                [
                  for (final w in _order) _wayTile(w),
                  if (_hasEmail && _hasPhone)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Require email AND phone'),
                      subtitle: const Text(
                          'Off: verifying with any one ticked way is enough. On: the user must also verify '
                          'the other channel (email + one phone way).'),
                      value: _requireAll,
                      onChanged: (v) => setState(() => _requireAll = v),
                    ),
                ],
              ),
              _card(
                'Offer first',
                'The way shown first and selected by default.',
                [
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: const Text('Automatic'),
                      selected: _default == 'auto',
                      onSelected: (_) => setState(() => _default = 'auto'),
                    ),
                    for (final w in _order.where((w) => _ways.contains(w.name)))
                      ChoiceChip(
                        avatar: Icon(w.icon, size: 16, color: w.brand),
                        label: Text(_names[w]!),
                        selected: _default == w.name,
                        onSelected: (_) => setState(() => _default = w.name),
                      ),
                  ]),
                ],
              ),
              if (_ways.contains('whatsapp'))
                _card(
                  'How WhatsApp is verified',
                  'Telegram is always a link, Email and SMS are always a code. WhatsApp can be either.',
                  [
                    RadioGroup<String>(
                      groupValue: _waDelivery,
                      onChanged: (v) => setState(() => _waDelivery = v!),
                      child: Column(children: const [
                        RadioListTile<String>(
                          value: 'auto',
                          title: Text('Automatic (recommended)'),
                          subtitle: Text('Link when the WhatsApp webhook is set up (free), otherwise a code'),
                        ),
                        RadioListTile<String>(
                          value: 'link',
                          title: Text('Link (free)'),
                          subtitle: Text('The user messages our business number'),
                        ),
                        RadioListTile<String>(
                          value: 'code',
                          title: Text('Code (paid provider)'),
                          subtitle: Text('We send a code through Twilio / WhatsApp Cloud'),
                        ),
                      ]),
                    ),
                  ],
                ),
              _card(
                'Login with',
                'What the login form accepts. Tick one or both.',
                [
                  for (final e in const {'email': 'Email', 'phone': 'Phone'}.entries)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _login.contains(e.key),
                      title: Text(e.value),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _login.add(e.key);
                        } else if (_login.length > 1) {
                          _login.remove(e.key);
                        } else {
                          _toast('Keep at least one way');
                        }
                      }),
                    ),
                ],
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
    );
  }
}
