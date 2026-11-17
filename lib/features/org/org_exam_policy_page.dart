// lib/features/org/org_exam_policy_page.dart
//
// The organization admin's exam policy (D-1133): the organization's own limits and exam methods, which can only TIGHTEN
// the platform's (the server refuses a looser value: 422 policy_looser_than_platform {field}). Every limit shows the
// platform's ceiling beside it; "Follow the platform" leaves it to the super admin. A method the platform switched off
// reads "Off for the whole platform" and cannot be switched on here; one a parent organization switched off reads
// "Off in a parent organization".
//
// GET / PUT /api/v1/org/orgs/{org_id}/exam-policy. [OrgExamPolicyBody] takes plain values (the layout harness pumps it).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/admin/admin_exam_policy_page.dart' show ExamMethod, examMethodIcon;
import 'package:flutter_education_app/features/exams/exam_policy.dart';

import '../admin/admin_common.dart' show asMap, asMapList, t;
import 'org_v3.dart';

/// One method on the organization's page.
class OrgExamMethod {
  const OrgExamMethod({required this.method, required this.platformOn, required this.on, this.inheritedOff = false});

  final ExamMethod method;
  final bool platformOn;
  final bool on;
  final bool inheritedOff;

  /// Can the organization admin change it here?
  bool get editable => platformOn && !inheritedOff;

  static OrgExamMethod from(Map<String, dynamic> m) => OrgExamMethod(
        method: ExamMethod.from(m),
        platformOn: m['platform_on'] != false,
        on: m['on'] != false,
        inheritedOff: m['inherited_off'] == true,
      );
}

/// The organization's own limits: null = follow the platform.
class OrgExamLimits {
  const OrgExamLimits({this.maxDuration, this.maxAttempts, this.maxQuestions, this.noUnlimited = false, this.noAnswerKey = false});

  final int? maxDuration;
  final int? maxAttempts;
  final int? maxQuestions;

  /// The organization forbids unlimited attempts / the answer key even where the platform allows them.
  final bool noUnlimited;
  final bool noAnswerKey;

  factory OrgExamLimits.fromJson(Map<String, dynamic> j) => OrgExamLimits(
        maxDuration: (j['max_duration_minutes'] as num?)?.toInt(),
        maxAttempts: (j['max_attempts'] as num?)?.toInt(),
        maxQuestions: (j['max_questions'] as num?)?.toInt(),
        noUnlimited: j['allow_unlimited_attempts'] == false,
        noAnswerKey: j['allow_answer_key'] == false,
      );

  /// The PUT body's `limits`: every key, null where the organization follows the platform.
  Map<String, dynamic> toJson() => {
        'max_duration_minutes': maxDuration,
        'max_attempts': maxAttempts,
        'max_questions': maxQuestions,
        'allow_unlimited_attempts': noUnlimited ? false : null,
        'allow_answer_key': noAnswerKey ? false : null,
      };

  OrgExamLimits copy({int? Function()? maxDuration, int? Function()? maxAttempts, int? Function()? maxQuestions, bool? noUnlimited, bool? noAnswerKey}) =>
      OrgExamLimits(
        maxDuration: maxDuration == null ? this.maxDuration : maxDuration(),
        maxAttempts: maxAttempts == null ? this.maxAttempts : maxAttempts(),
        maxQuestions: maxQuestions == null ? this.maxQuestions : maxQuestions(),
        noUnlimited: noUnlimited ?? this.noUnlimited,
        noAnswerKey: noAnswerKey ?? this.noAnswerKey,
      );
}

/// The words of the platform's ceiling under a field.
String platformCeilingText(int v, {bool minutes = false}) => v <= 0
    ? t('المنصة: بلا حد', 'Platform: no limit')
    : (minutes ? t('المنصة: $v دقيقة', 'Platform: $v min') : t('المنصة: $v', 'Platform: $v'));

class OrgExamPolicyBody extends StatelessWidget {
  const OrgExamPolicyBody({
    super.key,
    required this.platform,
    required this.limits,
    required this.methods,
    required this.onLimits,
    required this.onMethod,
    this.busy = false,
  });

  final ExamPolicy platform;
  final OrgExamLimits limits;
  final List<OrgExamMethod> methods;
  final ValueChanged<OrgExamLimits> onLimits;
  final void Function(OrgExamMethod m, bool on) onMethod;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = platform;
    final l = limits;
    final off = methods.where((m) => !m.on || !m.platformOn).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
        icon: Icons.policy_rounded,
        text: t('تضيّق مؤسستك حدود المنصة فقط ولا توسّعها. ما تتركه يتبع إعداد المنصة.',
            'Your organization can only tighten the platform limits, never loosen them. Anything you leave follows the platform.'),
      ),
      AppSpace.gapLg,
      AppSectionCard(
        title: t('حدود الاختبارات في مؤسستك', 'Exam limits in your organization'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _LimitRow(
            label: t('أطول مدة (دقيقة)', 'Longest duration (minutes)'),
            ceiling: platformCeilingText(p.maxDurationMinutes, minutes: true),
            value: l.maxDuration,
            max: p.maxDurationMinutes > 0 ? p.maxDurationMinutes : 24 * 60,
            step: 15,
            onChanged: (v) => onLimits(l.copy(maxDuration: () => v)),
          ),
          _LimitRow(
            label: t('أقصى عدد محاولات', 'Most attempts'),
            ceiling: platformCeilingText(p.attemptsCap),
            value: l.maxAttempts,
            max: p.attemptsCap,
            onChanged: (v) => onLimits(l.copy(maxAttempts: () => v)),
          ),
          _LimitRow(
            label: t('أقصى عدد أسئلة', 'Most questions'),
            ceiling: platformCeilingText(p.maxQuestions),
            value: l.maxQuestions,
            max: p.maxQuestions > 0 ? p.maxQuestions : 1000,
            step: 10,
            onChanged: (v) => onLimits(l.copy(maxQuestions: () => v)),
          ),
          AppSwitchTile(
            icon: Icons.all_inclusive_rounded,
            title: t('السماح بمحاولات غير محدودة', 'Allow unlimited attempts'),
            subtitle: p.allowUnlimitedAttempts ? null : t('متوقفة على المنصة كلها', 'Off for the whole platform'),
            value: p.allowUnlimitedAttempts && !l.noUnlimited,
            onChanged: p.allowUnlimitedAttempts ? (v) => onLimits(l.copy(noUnlimited: !v)) : null,
          ),
          AppSwitchTile(
            icon: Icons.key_rounded,
            title: t('السماح بإظهار الإجابات النموذجية للطلاب', 'Allow showing the answer key to students'),
            subtitle: p.allowAnswerKey ? null : t('متوقفة على المنصة كلها', 'Off for the whole platform'),
            value: p.allowAnswerKey && !l.noAnswerKey,
            onChanged: p.allowAnswerKey ? (v) => onLimits(l.copy(noAnswerKey: !v)) : null,
          ),
        ]),
      ),
      AppSpace.gapLg,
      AppSectionCard(
        title: t('طرق الاختبارات في مؤسستك', 'Exam methods in your organization'),
        subtitle: t('الإيقاف يخفي الطريقة عن كل من في مؤسستك. لا يُحذف شيء.', 'Off hides the method from everyone in your organization. Nothing is deleted.'),
        actions: [
          if (off > 0) AppStatusBadge(label: t('$off متوقفة', '$off off'), tone: AppTone.warning, icon: Icons.power_settings_new_rounded),
        ],
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final m in methods)
            AppSwitchTile(
              icon: examMethodIcon(m.method.key),
              title: m.method.title,
              subtitle: !m.platformOn
                  ? t('متوقفة على المنصة كلها', 'Off for the whole platform')
                  : m.inheritedOff
                      ? t('أوقفتها مؤسسة أعلى', 'Off in a parent organization')
                      : (m.method.about.isEmpty ? null : m.method.about),
              value: m.platformOn && m.on,
              onChanged: busy || !m.editable ? null : (v) => onMethod(m, v),
            ),
        ]),
      ),
    ]);
  }
}

/// One limit: "Follow the platform" or the organization's own number (at most the platform's).
class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.label, required this.ceiling, required this.value, required this.max, required this.onChanged, this.step = 1});

  final String label;
  final String ceiling;
  final int? value;
  final int max;
  final int step;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final own = value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSwitchTile(
          title: label,
          subtitle: own ? ceiling : t('يتبع المنصة · $ceiling', 'Follows the platform · $ceiling'),
          value: own,
          onChanged: (v) => onChanged(v ? max : null),
        ),
        if (own)
          AppNumberField(
            key: ValueKey('$label-$max'),
            initialValue: value,
            min: 1,
            max: max,
            step: step,
            onChanged: (v) => v == null ? null : onChanged(v.toInt()),
          ),
      ]),
    );
  }
}

/// The 422 codes of a save, in words.
String orgExamPolicyError(String? code) => switch (code) {
      'policy_looser_than_platform' => t('لا يمكن لمؤسستك تخفيف حدود المنصة', 'Your organization can only tighten the platform limits'),
      'bad_policy_value' => t('قيمة غير صالحة', 'A value is not valid'),
      _ => t('تعذّر الحفظ', 'Could not save'),
    };

/// The page body (pushed by the organization's settings inside its own header).
class OrgExamPolicyPage extends StatefulWidget {
  const OrgExamPolicyPage({super.key, required this.orgId});

  final int orgId;

  @override
  State<OrgExamPolicyPage> createState() => _OrgExamPolicyPageState();
}

class _OrgExamPolicyPageState extends State<OrgExamPolicyPage> {
  ExamPolicy? _platform;
  OrgExamLimits _saved = const OrgExamLimits();
  OrgExamLimits _limits = const OrgExamLimits();
  List<OrgExamMethod> _methods = const [];
  bool _busy = false;
  bool _failed = false;

  String get _path => '/api/v1/org/orgs/${widget.orgId}/exam-policy';

  bool get _dirty => '${_saved.toJson()}' != '${_limits.toJson()}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> m) {
    _platform = ExamPolicy.fromJson(asMap(m['platform']));
    _saved = OrgExamLimits.fromJson(asMap(asMap(m['org'])['limits']));
    _limits = _saved;
    _methods = [for (final x in asMapList(m['methods'])) OrgExamMethod.from(x)];
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(_path), quiet: true);
    if (!mounted) return;
    setState(() {
      _failed = !r.ok;
      if (r.ok) _take(r.map);
    });
  }

  List<String> _offKeys(List<OrgExamMethod> ms) => [for (final m in ms) if (!m.on && !m.inheritedOff) m.method.key];

  Future<void> _put(Map<String, dynamic> body, {String? ok}) async {
    setState(() => _busy = true);
    final r = await orgCall(() => ApiClient().put(_path, body: body), quiet: true);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.map);
    });
    showAppNotice(r.ok ? (ok ?? t('حُفظت سياسة الاختبارات', 'Exam policy saved')) : orgExamPolicyError(r.code), error: !r.ok);
    if (r.ok) ExamPolicy.reset();             // the next new exam reads the organization's effective policy again
  }

  Future<void> _method(OrgExamMethod m, bool on) async {
    final next = [for (final x in _methods) x.method.key == m.method.key ? OrgExamMethod(method: x.method, platformOn: x.platformOn, on: on) : x];
    await _put({'methods_off': _offKeys(next)},
        ok: on ? t('تم تشغيل «${m.method.title}»', '"${m.method.title}" is on') : t('تم إيقاف «${m.method.title}»', '"${m.method.title}" is off'));
  }

  @override
  Widget build(BuildContext context) {
    final p = _platform;
    if (p == null) {
      if (!_failed) return const AppListSkeleton(items: 4);
      return AppEmpty(
        icon: Icons.policy_rounded,
        title: t('تعذّر تحميل سياسة الاختبارات', 'Could not load the exam policy'),
        actionLabel: t('إعادة المحاولة', 'Try again'),
        onAction: () {
          setState(() => _failed = false);
          _load();
        },
      );
    }
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      OrgExamPolicyBody(
        platform: p,
        limits: _limits,
        methods: _methods,
        busy: _busy,
        onLimits: (l) => setState(() => _limits = l),
        onMethod: _method,
      ),
      AppSpace.gapLg,
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton.primary(
          label: t('حفظ الحدود', 'Save limits'),
          icon: Icons.check_rounded,
          onPressed: _dirty && !_busy ? () => _put({'limits': _limits.toJson()}) : null,
        ),
      ),
    ]);
  }
}
