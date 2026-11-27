// lib/features/admin/admin_exam_policy_page.dart
//
// The super admin's ONE exam settings page (D-1130): the platform's exam policy and every exam switch together.
//
//   At a glance   four soft stat cards: methods on, the default length, attempts, when results show
//   New exams     the defaults every creation flow starts from (wizard, quick exam): duration, attempts, shuffle, when
//                 results show, what students see, pass mark, class exam vs high stakes
//   Limits        what the engine refuses (422 policy_*): longest duration, most attempts, unlimited attempts, most
//                 questions, the answer key shown to students. 0 = no limit
//   Methods       the creation / grading / results methods, each an existing kill-switch key switched on every platform
//   More          the exam pages that already existed elsewhere (bubble sheet types, parents and grades, the grading
//                 feedback store, AI controls on the Features page), linked from here so exams have one home
//
// GET / PUT /api/v1/admin/exam-policy · PUT /api/v1/admin/exam-policy/methods/{key} {on}. [ExamPolicyBody] takes plain
// values (the layout harness pumps it); the page owns the calls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart' show Trans;
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/exams/exam_policy.dart';

import '../org/org_v3.dart';
import 'admin_common.dart' show asMapList, t;
import 'cfg_common.dart';
import 'sup/sup_kit.dart';

/// One method switch as the server lists it.
class ExamMethod {
  const ExamMethod({required this.key, required this.group, required this.title, required this.about, required this.on, this.partial = false});

  final String key;
  final String group;
  final String title;
  final String about;
  final bool on;
  final bool partial;

  static ExamMethod from(Map<String, dynamic> m) => ExamMethod(
        key: '${m['key']}',
        group: '${m['group'] ?? 'create'}',
        title: t('${m['title_ar'] ?? m['key']}', '${m['title_en'] ?? m['key']}'),
        about: t('${m['about_ar'] ?? ''}', '${m['about_en'] ?? ''}'),
        on: m['on'] != false,
        partial: m['partial'] == true,
      );
}

IconData examMethodIcon(String key) => switch (key) {
      'exam.auto_create' => Icons.auto_awesome_rounded,
      'exam.google_forms_import' => Icons.dynamic_form_rounded,
      'exam.omr' => Icons.grid_on_rounded,
      'exam.answer_sheet' => Icons.border_color_rounded,
      'exam.paper_designer' => Icons.design_services_rounded,
      'exam.auto_grade' => Icons.rate_review_rounded,
      'exam.auto_correct' => Icons.document_scanner_rounded,
      'exam.essay_run' => Icons.history_edu_rounded,
      'exam.results.import' => Icons.upload_file_rounded,
      'exam.question_void' => Icons.block_rounded,
      'exam.deliver_email' => Icons.forward_to_inbox_rounded,
      _ => Icons.fact_check_rounded,
    };

String _groupTitle(String g) => switch (g) {
      'grade' => t('التصحيح', 'Grading'),
      'results' => t('النتائج', 'Results'),
      _ => t('إنشاء الاختبار', 'Creating exams'),
    };

String _minutes(int m) => m <= 0 ? t('بلا حد', 'No limit') : t('$m دقيقة', '$m min');

String _attempts(int n) => n == 0 ? t('غير محدودة', 'Unlimited') : (n == 1 ? t('محاولة واحدة', 'One attempt') : t('$n محاولات', '$n attempts'));

/// The whole page body from plain values.
class ExamPolicyBody extends StatelessWidget {
  const ExamPolicyBody({
    super.key,
    required this.policy,
    required this.methods,
    required this.onChanged,
    required this.onToggle,
    this.busy = const {},
    this.links = const [],
  });

  final ExamPolicy policy;
  final List<ExamMethod> methods;
  final ValueChanged<ExamPolicy> onChanged;
  final void Function(ExamMethod m, bool on) onToggle;
  final Set<String> busy;

  /// The related exam pages: (icon, title, subtitle, onTap).
  final List<(IconData, String, String, VoidCallback)> links;

  @override
  Widget build(BuildContext context) {
    final p = policy;
    final on = methods.where((m) => m.on).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppKpiGrid(children: [
        AppStatCard(
          icon: Icons.toggle_on_rounded,
          value: '$on/${methods.length}',
          label: t('طرق مفعّلة', 'Methods on'),
          tone: AppBlockTone.emerald,
        ),
        AppStatCard(icon: Icons.timer_rounded, value: _minutes(p.durationMinutes), label: t('مدة الاختبار الجديد', 'New exam length'), tone: AppBlockTone.sky),
        AppStatCard(icon: Icons.replay_rounded, value: _attempts(p.maxAttempts), label: t('المحاولات', 'Attempts'), tone: AppBlockTone.gold),
        AppStatCard(
            icon: Icons.visibility_rounded,
            value: p.resultsPolicy == 'after_submit' ? t('فورًا', 'At once') : (p.resultsPolicy == 'when_published' ? t('عند النشر', 'On publish') : t('مخفية', 'Hidden')),
            label: t('ظهور النتائج', 'Results show'),
            tone: AppBlockTone.peach),
      ]),
      AppSpace.gapLg,
      AppSectionCard(
        title: t('الاختبار الجديد يبدأ بـ', 'A new exam starts with'),
        subtitle: t('يغيّرها المعلم لكل اختبار داخل الحدود أدناه.', 'Teachers change them per exam, inside the limits below.'),
        child: _Defaults(policy: p, onChanged: onChanged),
      ),
      AppSpace.gapLg,
      AppSectionCard(
        title: t('حدود المنصة', 'Platform limits'),
        subtitle: t('يرفض الخادم ما يتجاوزها. 0 يعني بلا حد.', 'The server refuses anything past them. 0 means no limit.'),
        child: _Limits(policy: p, onChanged: onChanged),
      ),
      for (final g in const ['create', 'grade', 'results'])
        if (methods.any((m) => m.group == g)) ...[
          AppSpace.gapLg,
          AppSectionCard(
            title: _groupTitle(g),
            subtitle: t('مفتاح على المنصة كلها؛ الإيقاف يخفي الميزة ويرفضها الخادم. لا يُحذف شيء.',
                'One switch for the whole platform; off hides it and the server refuses it. Nothing is deleted.'),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final m in methods.where((m) => m.group == g))
                AppSwitchTile(
                  icon: examMethodIcon(m.key),
                  title: m.title,
                  subtitle: m.about.isEmpty ? null : m.about,
                  subtitleWidget: m.partial
                      ? AppStatusBadge(
                          label: t('مخفية على بعض المنصات فقط', 'Hidden on some platforms only'),
                          tone: AppTone.warning,
                          icon: Icons.devices_rounded,
                          dense: true)
                      : null,
                  value: m.on,
                  onChanged: busy.contains(m.key) ? null : (v) => onToggle(m, v),
                ),
            ]),
          ),
        ],
      if (links.isNotEmpty) ...[
        AppSpace.gapLg,
        AppSectionCard(
          title: t('صفحات أخرى للاختبارات', 'More exam pages'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final l in links) AppSettingsTile(icon: l.$1, label: l.$2, subtitle: l.$3, onTap: l.$4),
          ]),
        ),
      ],
    ]);
  }
}

class _Defaults extends StatelessWidget {
  const _Defaults({required this.policy, required this.onChanged});

  final ExamPolicy policy;
  final ValueChanged<ExamPolicy> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = policy;
    final views = [for (final v in kResultsViews) if (v != 'answers_key' || p.allowAnswerKey || p.resultsView == v) v];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Pair(
        AppNumberField(
          key: ValueKey('d-dur-${p.maxDurationMinutes}'),
          label: t('المدة (دقيقة)', 'Duration (minutes)'),
          initialValue: p.durationMinutes,
          min: 1,
          max: p.maxDurationMinutes > 0 ? p.maxDurationMinutes : 24 * 60,
          step: 5,
          onChanged: (v) => v == null ? null : onChanged(p.copyWith(durationMinutes: v.toInt())),
        ),
        AppNumberField(
          key: ValueKey('d-att-${p.attemptsCap}-${p.allowUnlimitedAttempts}'),
          label: t('المحاولات', 'Attempts'),
          helper: p.allowUnlimitedAttempts ? t('0 = غير محدودة', '0 = unlimited') : null,
          initialValue: p.maxAttempts,
          min: p.allowUnlimitedAttempts ? 0 : 1,
          max: p.attemptsCap,
          onChanged: (v) => v == null ? null : onChanged(p.copyWith(maxAttempts: v.toInt())),
        ),
      ),
      AppSpace.gapMd,
      _Pair(
        AppDropdown<String>(
          decoration: InputDecoration(labelText: t('متى تظهر النتيجة', 'When results show')),
          value: p.resultsPolicy,
          items: [for (final v in kResultsPolicies) DropdownMenuItem(value: v, child: Text(policyResultsWhenLabel(v)))],
          onChanged: (v) => v == null ? null : onChanged(p.copyWith(resultsPolicy: v)),
        ),
        AppDropdown<String>(
          decoration: InputDecoration(labelText: t('ما يراه الطالب', 'What students see')),
          value: p.resultsView,
          items: [for (final v in views) DropdownMenuItem(value: v, child: Text(resultsViewLabel(v)))],
          onChanged: (v) => v == null ? null : onChanged(p.copyWith(resultsView: v)),
        ),
      ),
      AppSpace.gapMd,
      AppNumberField(
        label: t('درجة النجاح (%)', 'Pass mark (%)'),
        initialValue: p.passingPercent.round(),
        min: 0,
        max: 100,
        step: 5,
        onChanged: (v) => v == null ? null : onChanged(p.copyWith(passingPercent: v.toDouble())),
      ),
      AppSpace.gapSm,
      AppSwitchTile(
        icon: Icons.shuffle_rounded,
        title: t('خلط الأسئلة والاختيارات', 'Shuffle questions and choices'),
        subtitle: t('لكل طالب ترتيب مختلف في الاختبار الإلكتروني.', 'Each student gets their own order in an online exam.'),
        value: p.shuffle,
        onChanged: (v) => onChanged(p.copyWith(shuffle: v)),
      ),
      AppSwitchTile(
        icon: Icons.verified_user_rounded,
        title: t('اختبار عالي الأهمية', 'High-stakes exam'),
        subtitle: t('يراجع المعلم كل درجة قبل ظهورها. عند الإيقاف: اختبار فصلي تظهر درجاته تلقائيًا.',
            'The teacher approves every grade before it shows. Off: a class exam whose grades show by themselves.'),
        value: p.highStakes,
        onChanged: (v) => onChanged(p.copyWith(highStakes: v)),
      ),
    ]);
  }
}

class _Limits extends StatelessWidget {
  const _Limits({required this.policy, required this.onChanged});

  final ExamPolicy policy;
  final ValueChanged<ExamPolicy> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = policy;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Pair(
        AppNumberField(
          label: t('أطول مدة (دقيقة)', 'Longest duration (minutes)'),
          helper: t('0 = بلا حد', '0 = no limit'),
          initialValue: p.maxDurationMinutes,
          min: 0,
          max: 24 * 60,
          step: 15,
          onChanged: (v) => v == null ? null : onChanged(fitPolicyDefaults(p.copyWith(maxDurationMinutes: v.toInt()))),
        ),
        AppNumberField(
          label: t('أقصى عدد محاولات', 'Most attempts'),
          initialValue: p.attemptsCap,
          min: 1,
          max: 100,
          onChanged: (v) => v == null ? null : onChanged(fitPolicyDefaults(p.copyWith(attemptsCap: v.toInt()))),
        ),
      ),
      AppSpace.gapMd,
      AppNumberField(
        label: t('أقصى عدد أسئلة في الاختبار', 'Most questions in an exam'),
        helper: t('0 = بلا حد', '0 = no limit'),
        initialValue: p.maxQuestions,
        min: 0,
        max: 1000,
        step: 10,
        onChanged: (v) => v == null ? null : onChanged(p.copyWith(maxQuestions: v.toInt())),
      ),
      AppSpace.gapSm,
      AppSwitchTile(
        icon: Icons.all_inclusive_rounded,
        title: t('السماح بمحاولات غير محدودة', 'Allow unlimited attempts'),
        value: p.allowUnlimitedAttempts,
        onChanged: (v) => onChanged(fitPolicyDefaults(p.copyWith(allowUnlimitedAttempts: v))),
      ),
      AppSwitchTile(
        icon: Icons.key_rounded,
        title: t('السماح بإظهار الإجابات النموذجية للطلاب', 'Allow showing the answer key to students'),
        subtitle: t('تظهر بعد انتهاء الاختبار أو نشر النتائج فقط.', 'Only after the exam ends or results are published.'),
        value: p.allowAnswerKey,
        onChanged: (v) => onChanged(fitPolicyDefaults(p.copyWith(allowAnswerKey: v))),
      ),
    ]);
  }

}

/// A tighter limit pulls the defaults inside it, so the page never saves a default the server refuses.
ExamPolicy fitPolicyDefaults(ExamPolicy p) => p.copyWith(
      durationMinutes: p.clampDuration(p.durationMinutes),
      maxAttempts: p.clampAttempts(p.maxAttempts),
      resultsView: p.resultsView == 'answers_key' && !p.allowAnswerKey ? 'answers' : p.resultsView,
    );

/// Two fields side by side on a wide box, stacked on a phone.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);

  final Widget a;
  final Widget b;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => box.maxWidth < 520
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, AppSpace.gapMd, b])
            : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: a),
                AppSpace.gapMd,
                Expanded(child: b),
              ]),
      );
}

/// The 422 codes of a save, in words.
String examPolicySaveError(String? code) => switch (code) {
      'policy_default_outside_limit' => t('قيمة افتراضية خارج حدود المنصة', 'A default is outside the platform limits'),
      'bad_policy_value' => t('قيمة غير صالحة', 'A value is not valid'),
      _ => t('تعذّر الحفظ', 'Could not save'),
    };

class AdminExamPolicyPage extends StatefulWidget {
  const AdminExamPolicyPage({super.key, this.links = const []});

  /// The related pages, built by the caller (they live in other files).
  final List<(IconData, String, String, VoidCallback)> links;

  @override
  State<AdminExamPolicyPage> createState() => _AdminExamPolicyPageState();
}

class _AdminExamPolicyPageState extends State<AdminExamPolicyPage> {
  ExamPolicy? _saved;
  ExamPolicy? _draft;
  List<ExamMethod> _methods = const [];
  ApiException? _error;
  bool _saving = false;
  final Set<String> _busy = {};

  bool get _dirty =>
      _saved != null && _draft != null && ('${_saved!.defaultsJson()}${_saved!.limitsJson()}' != '${_draft!.defaultsJson()}${_draft!.limitsJson()}');

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _take(Map<String, dynamic> m) {
    final p = ExamPolicy.fromJson(m);
    _saved = p;
    _draft = p;
    _methods = [for (final x in asMapList(m['methods'])) ExamMethod.from(x)];
    ExamPolicy.current = p;
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get(kAdminExamPolicyPath), quiet: true);
    if (!mounted) return;
    setState(() {
      _error = r.error;
      if (r.ok) _take(r.map);
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _saving = true);
    final r = await orgCall(() => ApiClient().put(kAdminExamPolicyPath, body: {'defaults': d.defaultsJson(), 'limits': d.limitsJson()}),
        quiet: true);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.ok) _take(r.map);
    });
    showAppNotice(r.ok ? t('حُفظت إعدادات الاختبارات', 'Exam settings saved') : examPolicySaveError(r.code), error: !r.ok);
  }

  Future<void> _toggle(ExamMethod m, bool on) async {
    if (!on) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('إيقاف', 'Switch off'),
          message: t('إيقاف «${m.title}» على المنصة كلها؟', 'Switch off "${m.title}" for the whole platform?'));
      if (!ok || !mounted) return;
    }
    setState(() => _busy.add(m.key));
    final r = await orgCall(() => ApiClient().put('$kAdminExamPolicyPath/methods/${Uri.encodeComponent(m.key)}', body: {'on': on}),
        ok: on ? t('تم تشغيل «${m.title}»', '"${m.title}" is on') : t('تم إيقاف «${m.title}»', '"${m.title}" is off'));
    if (!mounted) return;
    setState(() {
      _busy.remove(m.key);
      if (r.ok) _methods = [for (final x in asMapList(r.map['methods'])) ExamMethod.from(x)];
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    return SupPage(
        kicker: 'a2_exams_kicker'.tr, headline: 'a2_exams_head'.tr, line: 'a2_exams_line'.tr,
        width: AppWidth.reading,
        title: t('إعدادات الاختبارات', 'Exam settings'),
        onRefresh: _load,
        dirty: _dirty,
        body: _error != null && d == null
          ? cfgErrorState(_error, onRetry: _load)
          : d == null
              ? const AppListSkeleton(items: 5)
              : AppRefresh(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.xxl), children: [
                    ExamPolicyBody(
                      policy: d,
                      methods: _methods,
                      busy: _busy,
                      links: widget.links,
                      onChanged: (p) => setState(() => _draft = p),
                      onToggle: _toggle,
                    ),
                  ]),
                ),
        actions: [?(d == null ? null : cfgSaveButton(dirty: _dirty, busy: _saving, onSave: _save))],
      );
  }
}
