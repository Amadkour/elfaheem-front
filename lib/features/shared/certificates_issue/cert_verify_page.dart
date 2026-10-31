// lib/features/shared/certificates_issue/cert_verify_page.dart
//
// The public verification page at `/verify/<token>` — the link and QR printed on every issued certificate
// (services/certificate_issue_service.verify_base). No sign-in: main.dart resolves the route before the login
// guard, and the ONLY call is GET /api/v1/public/certificates/verify/{token} with `auth: false` (ApiClient neither
// sends a token nor redirects to the login). Never call an authenticated API from here.
library;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import 'cert_issue_api.dart';
import 'cert_issue_logic.dart';
import 'cert_issue_parts.dart';

class CertVerifyPage extends StatefulWidget {
  const CertVerifyPage({super.key, required this.token, this.load});

  final String token;

  /// Tests: replaces the network call.
  final Future<VerifyResult> Function(String token)? load;

  @override
  State<CertVerifyPage> createState() => _CertVerifyPageState();
}

class _CertVerifyPageState extends State<CertVerifyPage> {
  VerifyState _state = VerifyState.loading;
  VerifyResult? _result;
  String? _error;
  String _lang = AppConfig.lang;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = VerifyState.loading;
      _error = null;
    });
    try {
      final r = await (widget.load ?? CertIssueApi.verify)(widget.token);
      if (!mounted) return;
      setState(() {
        _result = r;
        _state = VerifyState.found;
      });
    } catch (e) {
      if (!mounted) return;
      final ex = ApiException.from(e);
      setState(() {
        if (ex.statusCode == 404) {
          _state = VerifyState.notFound;
        } else {
          _state = VerifyState.error;
          _error = certIssueErrorText(e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        automaticallyImplyLeading: Navigator.of(context).canPop(),
        centerTitle: false,
        title: Text('ci_verify_bar'.tr, style: c.h4),
      ),
      body: SafeArea(
        child: CertVerifyView(
          state: _state,
          result: _result,
          lang: _lang,
          onLang: (l) => setState(() => _lang = l),
          onRetry: _load,
          errorText: _error,
        ),
      ),
    );
  }
}
