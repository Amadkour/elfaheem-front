// features/admin/admin_auth_settings_page.dart
// Admin: how accounts are verified, what the login form accepts, how phone codes are sent.
// Open it from your admin settings list:
//   Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuthSettingsPage()));
import 'package:flutter/material.dart';

import '../../core/api_client.dart';

class AdminAuthSettingsPage extends StatefulWidget {
  const AdminAuthSettingsPage({super.key});

  @override
  State<AdminAuthSettingsPage> createState() => _AdminAuthSettingsPageState();
}

class _AdminAuthSettingsPageState extends State<AdminAuthSettingsPage> {
  final _api = ApiClient();
  bool _loading = true, _saving = false;
  String _verification = 'email', _login = 'email', _channel = 'sms';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/v1/admin/settings');
      if (r is Map) {
        _verification = (r['verification_method'] ?? 'email').toString();
        _login = (r['login_identifier'] ?? 'email').toString();
        _channel = (r['otp_phone_channel'] ?? 'sms').toString();
      }
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.put('/api/v1/admin/settings', body: {
        'verification_method': _verification,
        'login_identifier': _login,
        'otp_phone_channel': _channel,
      });
      _toast('Saved');
    } catch (e) {
      _toast('$e');
    }
    if (mounted) setState(() => _saving = false);
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Widget _group(String title, String hint, String value,
      Map<String, String> options, ValueChanged<String> onChanged) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          RadioGroup<String>(
            groupValue: value,
            onChanged: (v) => onChanged(v!),
            child: Column(children: [
              for (final e in options.entries)
                RadioListTile<String>(value: e.key, title: Text(e.value)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verification & login')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _group(
                'Verify new accounts by',
                'What a user must confirm with a code after registering.',
                _verification,
                const {
                  'email': 'Email',
                  'phone': 'Phone',
                  'both': 'Both (email and phone)',
                },
                (v) => setState(() => _verification = v),
              ),
              _group(
                'Login with',
                'What the login form accepts.',
                _login,
                const {
                  'email': 'Email only',
                  'phone': 'Phone only',
                  'either': 'Email or phone',
                },
                (v) => setState(() => _login = v),
              ),
              _group(
                'Send phone codes by',
                'Used when phone verification is on. The provider (Twilio / WhatsApp Cloud) is set in the server .env.',
                _channel,
                const {'sms': 'SMS', 'whatsapp': 'WhatsApp'},
                (v) => setState(() => _channel = v),
              ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ]),
    );
  }
}
