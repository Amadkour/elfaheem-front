// Consent before an Exam Engine attempt (brief §7.6: informed consent is mandatory, versioned, never covert).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart' show AppFonts;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, t;
import 'package:flutter_education_app/features/student/courses/security/device_id_service.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_integrity.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';

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
    final b = AppBlockColors.of(context, AppBlockTone.sky);
    return ExamPageWidth(width: AppWidth.reading, builder: (side) => ListView(padding: EdgeInsets.fromLTRB(side, AppSpace.md, side, AppSpace.xl), children: [
      // the page's one block: what is being agreed to, and which version of it
      AppBlock(
        tone: AppBlockTone.sky,
        hero: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.verified_user_rounded, size: AppIconSize.xl, color: b.ink),
          const SizedBox(height: AppSpace.md),
          Text(title, style: AppType.headline(context).copyWith(color: b.ink, fontFamilyFallback: AppFonts.fallback)),
          const SizedBox(height: AppSpace.xxs),
          Text(t('النسخة $version — اقرأ قبل البدء', 'Version $version — read before you start'), style: AppType.meta(context).copyWith(color: b.muted)),
        ]),
      ),
      AppSpace.gapMd,
      AppCard(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Text(body, style: AppType.body(context).copyWith(color: c.textDark, height: 1.7)),
      ),
      AppSpace.gapMd,
      AppBanner(
        icon: monitoring == null ? Icons.visibility_off_rounded : Icons.videocam_rounded,
        text: monitoring ??
            t('لا تُستخدم الكاميرا أو الميكروفون في هذا الاختبار — تُسجَّل أحداث الاختبار فقط (مثل تبديل النوافذ).',
                'No camera or microphone is used in this exam — only exam events are recorded (such as switching windows).'),
      ),
      AppSection(
        title: t('ما يستطيعه هذا الجهاز', 'What this device can do'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final cap in capabilities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.check_circle_outline_rounded, size: AppIconSize.md, color: c.success),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text(cap, style: AppType.body(context))),
              ]),
            ),
        ]),
      ),
      AppSpace.gapXl,
      AppButton.primary(
        key: const ValueKey('consent.accept'),
        label: accepted ? t('تم القبول — ابدأ', 'Accepted — start') : t('قرأت وأوافق', 'I have read and I agree'),
        icon: Icons.check_rounded,
        size: AppButtonSize.lg,
        expand: true,
        busy: busy,
        onPressed: onAccept,
      ),
    ]));
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
      appBar: AppHeader(title: t('قبل الاختبار', 'Before the exam')),
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
