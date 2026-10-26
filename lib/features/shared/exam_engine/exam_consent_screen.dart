// Consent before an Exam Engine attempt (brief §7.6: informed consent is mandatory, versioned, never covert).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asMap, t;
import '../../student/courses/security/device_id_service.dart';
import 'exam_engine_api.dart';
import 'exam_integrity.dart';
import 'exam_taking.dart';

/// Plain-values body (what the layout harness pumps): the text, what it requires, what this platform can do.
class ConsentBody extends StatelessWidget {
  const ConsentBody({super.key, required this.title, required this.body, required this.version, required this.requires,
      required this.capabilities, required this.accepted, required this.busy, required this.onAccept});
  final String title;
  final String body;
  final int version;
  final Map<String, dynamic> requires;
  final List<String> capabilities;
  final bool accepted;
  final bool busy;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final monitoring = monitoringText(requires);
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppHero(title: title, subtitle: t('النسخة $version — اقرأ قبل البدء', 'Version $version — read before you start'), icon: Icons.verified_user_rounded),
      const SizedBox(height: 12),
      AppCard(child: Text(body, style: appText(14.5, h: 1.6, c: c.textDark))),
      const SizedBox(height: 12),
      AppBanner(
        icon: monitoring == null ? Icons.visibility_off_rounded : Icons.videocam_rounded,
        text: monitoring ??
            t('لا تُستخدم الكاميرا أو الميكروفون في هذا الاختبار — تُسجَّل أحداث الاختبار فقط (مثل تبديل النوافذ).',
                'No camera or microphone is used in this exam — only exam events are recorded (such as switching windows).'),
      ),
      const SizedBox(height: 12),
      AppSectionTitle(t('ما يستطيعه هذا الجهاز', 'What this device can do')),
      for (final cap in capabilities)
        Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
          Icon(Icons.check_circle_outline_rounded, size: 18, color: c.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(cap, style: appText(13, c: c.textMedium))),
        ])),
      const SizedBox(height: 20),
      AppPrimaryButton(
        key: const ValueKey('consent.accept'),
        label: accepted ? t('تم القبول — ابدأ', 'Accepted — start') : t('قرأت وأوافق', 'I have read and I agree'),
        busy: busy,
        onPressed: onAccept,
      ),
    ]);
  }
}

class ExamConsentScreen extends StatefulWidget {
  const ExamConsentScreen({super.key, required this.examId, required this.onAccepted});
  final int examId;
  final Future<void> Function(BuildContext context) onAccepted;

  @override
  State<ExamConsentScreen> createState() => _ExamConsentScreenState();
}

class _ExamConsentScreenState extends State<ExamConsentScreen> {
  final _api = ExamEngineApi();
  Map<String, dynamic>? _consent;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(EngineResult r) => examCodeText(r.code ?? '') == (r.code ?? '') ? r.message : examCodeText(r.code ?? '');

  Future<void> _load() async {
    final r = await _api.consent(widget.examId, lang: AppConfig.lang == 'ar' ? 'ar' : 'en');
    if (!mounted) return;
    setState(() {
      _consent = r.ok ? r.map : null;
      _error = r.ok ? null : _text(r);
    });
  }

  Future<void> _accept() async {
    final consent = _consent;
    if (consent == null) return;
    setState(() => _busy = true);
    final deviceId = await DeviceIdService.instance.id();
    final r = await _api.acceptConsent(widget.examId, textHash: consentHashOf(consent), lang: '${consent['lang'] ?? 'ar'}',
        deviceId: deviceId, platform: DeviceIdService.platform == 'web' ? 'web' : 'mobile');
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _busy = false);
      appToast(_text(r), error: true);
      if (r.code == 'consent_changed') await _load();
      return;
    }
    await widget.onAccepted(context);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final consent = _consent;
    return BasePage(
      key: const ValueKey('exam.consent'),
      appBar: AppBar(title: Text(t('قبل الاختبار', 'Before the exam'))),
      child: _error != null
          ? AppEmpty(icon: Icons.error_outline_rounded, title: _error!)
          : consent == null
              ? const AppListSkeleton()
              : ConsentBody(
                  title: '${consent['title'] ?? ''}',
                  body: '${consent['body'] ?? ''}',
                  version: (consent['version'] as num?)?.toInt() ?? 1,
                  requires: asMap(consent['requires']),
                  capabilities: ExamIntegrity.capabilities(),
                  accepted: consent['accepted'] == true,
                  busy: _busy,
                  onAccept: _accept,
                ),
    );
  }
}
