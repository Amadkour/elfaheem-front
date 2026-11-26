// Consent before an Exam Engine attempt (brief §7.6: informed consent is mandatory, versioned, never covert).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppDeal;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asMap, t;
import 'package:flutter_education_app/features/courses/student/security/device_id_service.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/exam_integrity.dart';
import 'package:flutter_education_app/features/exams/exam_taking.dart';
import 'package:flutter_education_app/features/exams/exam_page_width.dart';

/// Plain-values body (what the layout harness pumps): "Ready, Faisal?" (redesign S-C, Stu2Exams?screen=consent): the
/// exam in the hero, three figures (questions, minutes, attempts), three short rules and ONE forward button; the
/// consent text itself (versioned, what this device can do, any monitoring) stays one tap away under the button,
/// and a camera / microphone requirement is said on the page, never hidden.
class ConsentBody extends StatelessWidget {
  const ConsentBody({super.key, required this.title, required this.body, required this.version, required this.requires,
      required this.capabilities, required this.accepted, required this.busy, required this.onAccept,
      this.examTitle, this.subtitle, this.closes, this.firstName, this.questions, this.minutes, this.attempts});
  final String title;
  final String body;
  final int version;
  final Map<String, dynamic> requires;
  final List<String> capabilities;
  final bool accepted;
  final bool busy;
  final VoidCallback onAccept;

  /// The exam (the consent's own title when null), its course line and when it closes ("Closes tomorrow 9:00 pm").
  final String? examTitle, subtitle, closes;
  final String? firstName;
  final int? questions, minutes, attempts;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = c.kit;
    final monitoring = monitoringText(requires);
    Widget figure(IconData icon, int n, String label, KitTone tone) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
            decoration: BoxDecoration(color: tone.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
            child: Column(children: [
              Icon(icon, size: AppIconSize.md, color: tone.ink),
              const SizedBox(height: AppSpace.xxs),
              Text(appDigits('$n'), style: AppType.figure(context).copyWith(color: tone.ink)),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: tone.ink)),
            ]),
          ),
        );
    final figures = <Widget>[
      if (questions != null) figure(Icons.format_list_bulleted_rounded, questions!, t('سؤال', 'questions'), k.accent(AppAccent.grape)),
      if (minutes != null) figure(Icons.schedule_rounded, minutes!, t('دقيقة', 'minutes'), k.accent(AppAccent.sun)),
      if (attempts != null)
        figure(Icons.repeat_rounded, attempts!, attempts == 1 ? t('محاولة', 'attempt') : t('محاولات', 'attempts'), k.accent(AppAccent.mint)),
    ];
    final hero = AppHero(wipe: false, kicker: closes, title: examTitle ?? title, subtitle: subtitle);
    final card = AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(firstName == null ? t('جاهز؟', 'Ready?') : t('جاهز يا $firstName؟', 'Ready, $firstName?'), style: AppType.section(context)),
        if (figures.isNotEmpty) ...[
          AppSpace.gapMd,
          Row(children: [
            for (var i = 0; i < figures.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.sm), figures[i]],
          ]),
        ],
        AppSpace.gapMd,
        AppRules(items: [
          (icon: Icons.pause_rounded, text: t('ما تقدر توقفه', "You can't pause it")),
          (icon: Icons.visibility_outlined, text: t('خلّك في الشاشة', 'Stay on this screen')),
          (icon: Icons.send_outlined, text: t('ينرسل لحاله إذا خلص الوقت', 'It sends itself when time is up')),
        ]),
        if (monitoring != null) ...[
          AppSpace.gapSm,
          AppBanner(icon: Icons.videocam_rounded, text: monitoring),
        ],
        AppSpace.gapMd,
        AppButton.hot(
          key: const ValueKey('consent.accept'),
          label: t('ابدأ الاختبار', 'Start the exam'),
          icon: Icons.play_arrow_rounded,
          size: AppButtonSize.lg,
          expand: true,
          busy: busy,
          onPressed: onAccept,
        ),
        AppSpace.gapSm,
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.schedule_rounded, size: AppIconSize.sm, color: c.textMedium),
          const SizedBox(width: AppSpace.xxs),
          Flexible(child: Text(t('وقتك يبدأ أول ما تضغط', 'Your time starts when you tap'), style: AppType.meta(context))),
        ]),
        AppSpace.gapSm,
        // the consent itself: versioned, read before agreeing, never covert (brief §7.6)
        AppExpandCard(
          card: false,
          header: Text(t('اللي توافق عليه لما تبدأ (النسخة $version)', 'What you agree to by starting (version $version)'),
              style: AppType.label(context).copyWith(color: c.textMedium)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: AppType.bodyStrong(context)),
            AppSpace.gapXs,
            Text(body, style: AppType.body(context).copyWith(color: c.textDark, height: 1.7)),
            if (monitoring == null) ...[
              AppSpace.gapSm,
              Text(
                  t('لا تُستخدم الكاميرا أو الميكروفون في هذا الاختبار، تُسجَّل أحداث الاختبار فقط (مثل تبديل النوافذ).',
                      'No camera or microphone is used in this exam; only exam events are recorded (such as switching windows).'),
                  style: AppType.meta(context)),
            ],
            if (capabilities.isNotEmpty) ...[
              AppSpace.gapSm,
              for (final cap in capabilities)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle_outline_rounded, size: AppIconSize.sm, color: k.ok.ink),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(cap, style: AppType.meta(context))),
                  ]),
                ),
            ],
          ]),
        ),
      ]),
    );
    return AppAreaScope(
      area: AppArea.exam,
      child: ExamPageWidth(
        width: AppWidth.form,
        builder: (side) => ListView(padding: const EdgeInsets.only(bottom: AppSpace.xl), children: [
          AppHeroOverlap(hero: hero, body: Padding(padding: EdgeInsets.symmetric(horizontal: side), child: AppDeal(child: card))),
        ]),
      ),
    );
  }
}

class ExamConsentScreen extends StatefulWidget {
  const ExamConsentScreen({super.key, required this.examId, required this.onAccepted, this.exam = const {}});
  final int examId;

  /// The exam's card from the list (title, course, duration, attempts, end), for the page's figures.
  final Map<String, dynamic> exam;
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

  static String? _str(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
  static int? _int(Object? v) => v is num && v > 0 ? v.toInt() : null;

  String? _closes() {
    final raw = widget.exam['ends_at'];
    if (raw == null) return null;
    final s = '$raw';
    final end = DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
    return end == null ? null : t('يقفل ${AppTime.dateTime(end)}', 'Closes ${AppTime.dateTime(end)}');
  }

  String? _firstName(BuildContext context) {
    final name = context.read<MyAuthProvider>().currentUser?.name.trim() ?? '';
    return name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
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
                  examTitle: _str(widget.exam['title']),
                  subtitle: _str(widget.exam['course_title'] ?? widget.exam['course_name']),
                  closes: _closes(),
                  firstName: _firstName(context),
                  questions: _int(widget.exam['question_count'] ?? widget.exam['questions_count']),
                  minutes: _int(widget.exam['duration_minutes']),
                  attempts: _int(widget.exam['attempts_allowed']),
                ),
    );
  }
}
