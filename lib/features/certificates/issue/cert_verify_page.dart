// lib/features/certificates/issue/cert_verify_page.dart
//
// The public verification page (D-420): `/verify` to type a certificate's number or scan its QR code, `/verify/<token>`
// from the link and QR printed on every issued certificate (services/certificate_issue_service.verify_base). No
// sign-in: main.dart resolves both routes before the login guard, and the ONLY calls are
// GET /api/v1/public/certificates/verify/{token} and …/lookup, both `auth: false` (ApiClient neither sends a token nor
// redirects to the login). Never call an authenticated API from here. A scanned value goes through parseCertCode and
// is never opened as a link.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/design/app_area.dart' show AppArea;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/org_join_scan.dart' deferred as scanner;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_api.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_logic.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_view.dart';
import 'package:flutter_education_app/design/app_header.dart';
import 'package:flutter_education_app/design/app_settings.dart' show AppSettingsTile;

/// Opens the page from a settings page (kill switch `certificates.verify`); the link itself always works.
class CertVerifyEntryTile extends StatelessWidget {
  const CertVerifyEntryTile({super.key});

  @override
  Widget build(BuildContext context) => AppSettingsTile(
        key: const ValueKey('cv.tile'),
        featureKey: kCertVerifyFeature,
        icon: Icons.verified_user_outlined,
        color: context.colors.success,
        label: 'cv_entry_title'.tr,
        onTap: () => openCertVerify(context),
      );
}

Future<void> openCertVerify(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CertVerifyPage()));

class CertVerifyPage extends StatefulWidget {
  const CertVerifyPage({super.key, this.token, this.load, this.lookup, this.scan, this.scanAvailable});

  /// From `/verify/<token>`; null opens the entry form.
  final String? token;

  /// Tests: replace the network calls and the camera.
  final Future<VerifyResult> Function(String token)? load;
  final Future<VerifyResult> Function(String number)? lookup;
  final Future<String?> Function(BuildContext context)? scan;
  final bool? scanAvailable;

  @override
  State<CertVerifyPage> createState() => _CertVerifyPageState();
}

class _CertVerifyPageState extends State<CertVerifyPage> {
  final _number = TextEditingController();
  late VerifyState _state = widget.token == null ? VerifyState.entry : VerifyState.loading;
  VerifyResult? _result;
  String? _error, _fieldError, _queried, _foreignHost;
  Future<void> Function()? _last;
  int _seq = 0;
  String _lang = AppConfig.lang;

  @override
  void initState() {
    super.initState();
    final token = widget.token;
    if (token != null) unawaited(_byToken(token));
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _byToken(String token) => _run(() => (widget.load ?? CertIssueApi.verify)(token), queried: null);

  Future<void> _byNumber(String number) =>
      _run(() => (widget.lookup ?? CertIssueApi.lookup)(number), queried: number);

  Future<void> _run(Future<VerifyResult> Function() call, {required String? queried}) async {
    final seq = ++_seq;
    _last = () => _run(call, queried: queried);
    setState(() {
      _state = VerifyState.loading;
      _error = _fieldError = null;
      _queried = queried;
    });
    try {
      final r = await call();
      if (!mounted || seq != _seq) return;
      setState(() {
        _result = r;
        _state = VerifyState.found;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
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

  void _check(String? raw, {required bool scanned}) {
    final code = parseCertCode(raw);
    switch (code.kind) {
      case CertCodeKind.token:
        unawaited(_byToken(code.value));
      case CertCodeKind.number:
        unawaited(_byNumber(code.value));
      case CertCodeKind.foreign:
        _showForeign(code.value);
      case CertCodeKind.malformed:
        if (scanned) {
          _showForeign('');
        } else {
          setState(() => _fieldError = 'cv_bad_number'.tr);
        }
    }
  }

  void _showForeign(String host) {
    _seq++;
    setState(() {
      _state = VerifyState.foreign;
      _foreignHost = host;
      _fieldError = null;
    });
  }

  Future<void> _scan() async {
    final raw = await (widget.scan ?? _openCamera)(context);
    if (raw == null || !mounted) return;
    _check(raw, scanned: true);
  }

  static Future<String?> _openCamera(BuildContext context) async {
    await scanner.loadLibrary();
    if (!context.mounted) return null;
    return scanner.openQrScanner(
      context,
      parse: (raw) => (raw ?? '').trim().isEmpty ? null : raw,
      title: 'cv_scan_title'.tr,
      prompt: 'cv_scan_prompt'.tr,
    );
  }

  void _another() {
    _seq++;
    _number.clear();
    setState(() {
      _state = VerifyState.entry;
      _result = null;
      _error = _fieldError = _queried = _foreignHost = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final canScan = widget.scanAvailable ?? certScanAvailable;
    return SdArea(area: AppArea.me, child: Scaffold(
      backgroundColor: c.background,
      appBar: AppHeader(title: 'ci_verify_bar'.tr, showBack: Navigator.of(context).canPop()),
      body: SafeArea(
        child: CertVerifyView(
          state: _state,
          result: _result,
          lang: _lang,
          onLang: (l) => setState(() => _lang = l),
          onRetry: () => unawaited(_last?.call()),
          errorText: _error,
          queried: _queried,
          foreignHost: _foreignHost,
          onAnother: _another,
          entry: CertVerifyEntry(
            controller: _number,
            fieldError: _fieldError,
            onSubmit: () => _check(_number.text, scanned: false),
            onScan: canScan ? () => unawaited(_scan()) : null,
          ),
        ),
      ),
    ));
  }
}
