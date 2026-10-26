// Exam Engine authoring screens: the exam editor (settings · sections & questions · proctoring · publish), the
// question bank, the question editor sheet for every type, the section sheet, the bank picker and accommodations.
//
// The presentational parts (ExamSettingsForm, ExamSectionsPanel, QuestionEditorForm, SectionForm, ProctoringPolicyForm,
// AccommodationsPanel, AccommodationForm, ExamPublishPanel, BankQuestionTile) take plain values and callbacks, so
// test/org/exam_authoring_test.dart runs them under the layout harness; the stateful screens own the API calls.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, asMapList, t;
import 'exam_authoring.dart';
import 'offline/offline_exam_teacher.dart';

/// Text controllers for dynamic rows, created on first use and disposed with the state. Rows are keyed by their
/// stable uid, so a removed row's controller is simply never asked for again.
mixin _Controllers<T extends StatefulWidget> on State<T> {
  final Map<String, TextEditingController> _ctls = {};
  TextEditingController ctl(String key, String initial) => _ctls.putIfAbsent(key, () => TextEditingController(text: initial));

  @override
  void dispose() {
    for (final c in _ctls.values) {
      c.dispose();
    }
    super.dispose();
  }
}

const _numKeyboard = TextInputType.numberWithOptions(decimal: true);

Widget _errorsBanner(BuildContext context, List<String> codes, {String? extra}) {
  final c = context.colors;
  final lines = [for (final code in codes) '• ${authoringCodeText(code)}', ?extra];
  if (lines.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: AppBanner(icon: Icons.error_outline_rounded, text: lines.join('\n'), color: c.danger),
  );
}

Widget _gap([double h = 10]) => SizedBox(height: h);

/// Small icon button that never grows the row.
Widget _iconBtn(IconData icon, String tip, VoidCallback? onTap, {Color? color}) => IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: color),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),   // the minimum touch target (accessibility)
      padding: EdgeInsets.zero,
    );

/// A date + time picked in the platform / organization zone and sent as UTC.
Future<DateTime?> pickEngineDateTime(BuildContext context, DateTime? currentUtc) async {
  final now = AppTime.toZone(DateTime.now().toUtc());
  final init = currentUtc == null ? now : AppTime.toZone(currentUtc);
  final first = DateTime(init.year < now.year - 1 ? init.year : now.year - 1);
  final last = DateTime(init.year > now.year + 3 ? init.year + 1 : now.year + 4);
  final d = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
  if (d == null || !context.mounted) return null;
  final tm = await showTimePicker(context: context, initialTime: TimeOfDay(hour: init.hour, minute: init.minute));
  if (tm == null) return null;
  return AppTime.fromZone(DateTime(d.year, d.month, d.day, tm.hour, tm.minute));
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: c.inputBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final v = await pickEngineDateTime(context, value);
            if (v != null) onChanged(v);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
            child: Row(children: [
              Icon(Icons.event_rounded, size: 20, color: c.textMedium),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: appText(12, c: c.textMedium)),
                  Text(value == null ? t('غير محدد', 'Not set') : AppTime.dateTime(value!), style: appText(14, c: c.textDark)),
                ]),
              ),
              if (value != null) _iconBtn(Icons.clear_rounded, t('مسح', 'Clear'), () => onChanged(null), color: c.textLight),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Exam settings
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// The exam's settings. Edits [draft] in place; [onSave] returns an error text (or null when saved).
class ExamSettingsForm extends StatefulWidget {
  const ExamSettingsForm({super.key, required this.draft, required this.onSave, this.creating = false});
  final ExamDraft draft;
  final Future<String?> Function(ExamDraft draft) onSave;
  final bool creating;

  @override
  State<ExamSettingsForm> createState() => _ExamSettingsFormState();
}

class _ExamSettingsFormState extends State<ExamSettingsForm> with _Controllers {
  List<String> _codes = const [];
  String? _error;
  bool _busy = false;
  bool _removePasscode = false;

  ExamDraft get d => widget.draft;

  Future<void> _save() async {
    final codes = d.validate();
    setState(() {
      _codes = codes;
      _error = null;
    });
    if (codes.isNotEmpty) return;
    setState(() => _busy = true);
    final err = await widget.onSave(d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final locked = d.status != 'draft' && d.status != 'published';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      if (locked) AppBanner(icon: Icons.lock_outline_rounded, text: t('الاختبار مغلق — لا يمكن تعديله', 'The exam is closed — it cannot be edited'), color: c.warning),
      AppSectionTitle(t('بيانات الاختبار', 'Exam details')),
      AppField(controller: ctl('title', d.title), label: t('العنوان', 'Title'), onChanged: (v) => d.title = v),
      AppField(controller: ctl('desc', d.description), label: t('الوصف (اختياري)', 'Description (optional)'), maxLines: 3, onChanged: (v) => d.description = v),
      AppSectionTitle(t('التوقيت', 'Timing'), subtitle: t('بتوقيت ${AppTime.zoneId}', 'In ${AppTime.zoneId} time')),
      _DateTimeField(label: t('يبدأ', 'Opens'), value: d.startsAt, onChanged: (v) => setState(() => d.startsAt = v)),
      _DateTimeField(label: t('ينتهي', 'Closes'), value: d.endsAt, onChanged: (v) => setState(() => d.endsAt = v)),
      AppField(
          controller: ctl('dur', d.durationMinutes?.toString() ?? ''), label: t('المدة بالدقائق', 'Duration (minutes)'),
          hint: t('فارغ = حتى موعد الانتهاء', 'Empty = until the closing time'), keyboard: TextInputType.number, ltr: true,
          onChanged: (v) => d.durationMinutes = v.trim().isEmpty ? null : (parseIntField(v) ?? -1)),
      AppField(
          controller: ctl('att', '${d.maxAttempts}'), label: t('عدد المحاولات', 'Attempts allowed'), keyboard: TextInputType.number, ltr: true,
          onChanged: (v) => d.maxAttempts = parseIntField(v) ?? 0),
      if (d.status == 'published')
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(t('بعد بدء الطلاب لا تتغير المدة ولا عدد المحاولات', 'Once students start, the duration and attempts are fixed'),
              style: appText(12, c: c.textMedium)),
        ),
      AppSectionTitle(t('الدخول', 'Access')),
      AppField(
          controller: ctl('pass', ''), label: t('رمز الدخول (اختياري)', 'Passcode (optional)'),
          hint: d.hasPasscode ? t('محدد — اكتب رمزاً جديداً لتغييره', 'Set — type a new one to change it') : null, ltr: true,
          onChanged: (v) => d.passcode = v.trim().isEmpty ? (_removePasscode ? '' : null) : v),
      if (d.hasPasscode)
        AppSwitchTile(
            title: t('إزالة رمز الدخول', 'Remove the passcode'), value: _removePasscode,
            onChanged: (v) => setState(() {
                  _removePasscode = v;
                  if (v) {
                    d.passcode = '';
                  } else {
                    d.passcode = null;
                  }
                })),
      Text(t('المنصات المسموحة', 'Allowed platforms'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
      _gap(6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in examPlatforms)
          AppChoiceChip(
            label: p == 'web' ? t('الويب', 'Web') : t('تطبيق الجوال', 'Mobile app'),
            icon: p == 'web' ? Icons.computer_rounded : Icons.smartphone_rounded,
            selected: d.platforms.contains(p),
            onTap: () => setState(() => d.platforms.contains(p) ? d.platforms.remove(p) : d.platforms.add(p)),
          ),
      ]),
      _gap(),
      AppBanner(icon: Icons.tips_and_updates_outlined, text: platformAdvice(d.platforms, highStakes: d.highStakes)),
      AppSectionTitle(t('النتائج والتصحيح', 'Results and grading')),
      AppDropdown<String>(
        value: d.resultsPolicy,
        decoration: InputDecoration(labelText: t('ظهور النتائج', 'Results visibility')),
        items: [for (final p in resultsPolicies) DropdownMenuItem(value: p, child: Text(resultsPolicyLabel(p)))],
        onChanged: (v) => setState(() => d.resultsPolicy = v ?? d.resultsPolicy),
      ),
      _gap(),
      AppSwitchTile(
          title: t('اختبار مصيري', 'High-stakes exam'),
          subtitle: t('يعتمد المعلم كل درجة مقالية، ولا تُنشر النتائج والمراجعة معلقة', 'The teacher approves every open mark; results wait for the review'),
          value: d.highStakes, onChanged: (v) => setState(() => d.highStakes = v)),
      AppSwitchTile(
          title: t('تصحيح بلا أسماء', 'Anonymous grading'), subtitle: t('يرى المصحح رمزاً بدل اسم الطالب', 'Markers see a code instead of the student'),
          value: d.anonymousGrading, onChanged: (v) => setState(() => d.anonymousGrading = v)),
      AppSwitchTile(
          title: t('إظهار درجة كل سؤال للطالب', 'Show each question\'s score to students'), value: d.showPerQuestion,
          onChanged: (v) => setState(() => d.showPerQuestion = v)),
      AppField(
          controller: ctl('pass%', fmtPoints(d.passingPercent)), label: t('نسبة النجاح ٪', 'Pass mark %'), keyboard: _numKeyboard, ltr: true,
          onChanged: (v) => d.passingPercent = parseNum(v) ?? -1),
      AppSectionTitle(t('التظلمات', 'Appeals')),
      AppSwitchTile(title: t('السماح بالتظلم على الدرجات', 'Allow appeals on marks'), value: d.appealsEnabled, onChanged: (v) => setState(() => d.appealsEnabled = v)),
      if (d.appealsEnabled) ...[
        AppField(
            controller: ctl('apd', '${d.appealDays}'), label: t('مدة التظلم بالأيام بعد ظهور النتيجة', 'Appeal window (days after results show)'),
            keyboard: TextInputType.number, ltr: true, onChanged: (v) => d.appealDays = parseIntField(v) ?? 0),
        AppField(
            controller: ctl('apn', '${d.appealsPerAttempt}'), label: t('أقصى عدد تظلمات للمحاولة', 'Most appeals per attempt'),
            keyboard: TextInputType.number, ltr: true, onChanged: (v) => d.appealsPerAttempt = parseIntField(v) ?? 0),
        AppSwitchTile(
            title: t('مراجع مستقل', 'Independent reviewer'), subtitle: t('يقرر التظلم شخص غير من صحح الإجابة', 'Someone other than the original marker decides'),
            value: d.independentReviewer, onChanged: (v) => setState(() => d.independentReviewer = v)),
      ],
      _gap(),
      _errorsBanner(context, _codes, extra: _error),
      AppPrimaryButton(
          label: widget.creating ? t('إنشاء الاختبار', 'Create the exam') : t('حفظ الإعدادات', 'Save settings'),
          icon: widget.creating ? Icons.add_rounded : Icons.save_rounded, busy: _busy, onPressed: locked ? null : _save),
      _gap(24),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Sections and placed questions
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class ExamSectionsPanel extends StatelessWidget {
  const ExamSectionsPanel({
    super.key,
    required this.view,
    required this.onAddSection,
    required this.onEditSection,
    required this.onDeleteSection,
    required this.onMoveSection,
    required this.onAddQuestions,
    required this.onRemoveQuestion,
    required this.onEditQuestion,
  });
  final ExamView view;
  final VoidCallback onAddSection;
  final ValueChanged<SectionDraft> onEditSection;
  final ValueChanged<SectionDraft> onDeleteSection;
  final void Function(SectionDraft section, int delta) onMoveSection;
  final ValueChanged<SectionDraft> onAddQuestions;
  final ValueChanged<PlacedQuestion> onRemoveQuestion;
  final void Function(SectionDraft section, PlacedQuestion question) onEditQuestion;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final draft = view.exam.isDraft;
    final editable = draft || view.exam.status == 'published';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppBadgePill(t('${view.sections.length} قسم', '${view.sections.length} sections'), icon: Icons.view_agenda_outlined),
        AppBadgePill(t('${view.questionCount} سؤال', '${view.questionCount} questions'), icon: Icons.help_outline_rounded),
        AppBadgePill(t('الدرجة العظمى ${fmtPoints(view.maxScore)}', 'Max score ${fmtPoints(view.maxScore)}'), icon: Icons.emoji_events_outlined, color: c.success),
      ]),
      _gap(),
      if (!draft)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppBanner(
              icon: Icons.lock_outline_rounded, color: c.warning,
              text: t('الاختبار ليس مسودة: الأسئلة وبنية الأقسام ثابتة، ويمكن تعديل العناوين والتعليمات ووقت القسم فقط',
                  'The exam is not a draft: questions and section structure are fixed; titles, instructions and section time can still change')),
        ),
      if (view.sections.isEmpty)
        AppEmpty(
            icon: Icons.view_agenda_outlined, title: t('لا توجد أقسام بعد', 'No sections yet'),
            message: t('أضف قسماً ثم ضع فيه أسئلة من البنك', 'Add a section, then place bank questions in it'),
            actionLabel: draft ? t('إضافة قسم', 'Add a section') : null, onAction: draft ? onAddSection : null),
      for (var i = 0; i < view.sections.length; i++) _sectionCard(context, view.sections[i], i, draft: draft, editable: editable),
      if (draft && view.sections.isNotEmpty) ...[
        _gap(4),
        AppPrimaryButton(label: t('إضافة قسم', 'Add a section'), icon: Icons.add_rounded, onPressed: onAddSection),
      ],
      _gap(24),
    ]);
  }

  Widget _sectionCard(BuildContext context, SectionView sv, int index, {required bool draft, required bool editable}) {
    final c = context.colors;
    final s = sv.section;
    final title = s.title.trim().isEmpty ? t('القسم ${index + 1}', 'Section ${index + 1}') : s.title.trim();
    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: appText(15, w: FontWeight.w800, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
              _gap(6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                AppBadgePill(sectionModeLabel(s.mode), icon: s.mode == 'paper' ? Icons.description_outlined : Icons.computer_rounded),
                if (s.navigation == 'one_way') AppBadgePill(navigationLabel(s.navigation), icon: Icons.arrow_forward_rounded, color: c.warning),
                if (s.weight != 1) AppBadgePill(t('وزن ×${fmtPoints(s.weight)}', 'Weight ×${fmtPoints(s.weight)}')),
                if (s.timeBoxMinutes != null) AppBadgePill(t('${s.timeBoxMinutes} دقيقة', '${s.timeBoxMinutes} min'), icon: Icons.timer_outlined),
                if (s.poolSize != null) AppBadgePill(t('سحب ${s.poolSize} من ${sv.eligible}', 'Draw ${s.poolSize} of ${sv.eligible}'), icon: Icons.casino_outlined),
                if (s.shuffleQuestions || s.shuffleOptions) AppBadgePill(t('ترتيب عشوائي', 'Shuffled'), icon: Icons.shuffle_rounded),
                AppBadgePill(t('${fmtPoints(sv.points)} درجة', '${fmtPoints(sv.points)} pts'), color: c.success),
              ]),
            ]),
          ),
          if (editable)
            PopupMenuButton<String>(
              tooltip: t('خيارات القسم', 'Section options'),
              icon: Icon(Icons.more_vert_rounded, color: c.textMedium),
              onSelected: (v) {
                switch (v) {
                  case 'edit':
                    onEditSection(s);
                  case 'up':
                    onMoveSection(s, -1);
                  case 'down':
                    onMoveSection(s, 1);
                  case 'delete':
                    onDeleteSection(s);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(t('تعديل القسم', 'Edit section'))),
                if (index > 0) PopupMenuItem(value: 'up', child: Text(t('نقل لأعلى', 'Move up'))),
                if (index < view.sections.length - 1) PopupMenuItem(value: 'down', child: Text(t('نقل لأسفل', 'Move down'))),
                if (draft) PopupMenuItem(value: 'delete', child: Text(t('حذف القسم', 'Delete section'), style: TextStyle(color: c.danger))),
              ],
            ),
        ]),
        if (s.instructions.trim().isNotEmpty) ...[
          _gap(6),
          Text(s.instructions.trim(), style: appText(12.5, c: c.textMedium, h: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
        _gap(8),
        if (sv.questions.isEmpty)
          Text(s.mode == 'paper' ? t('قسم ورقي — الأسئلة اختيارية (تُدخل الدرجات أو تُمسح الأوراق)', 'Paper section — questions optional (marks entered or scanned)')
              : t('لا توجد أسئلة في هذا القسم', 'No questions in this section'), style: appText(12.5, c: c.textLight)),
        for (var qi = 0; qi < sv.questions.length; qi++) _questionRow(context, s, sv.questions[qi], qi, draft: draft),
        if (draft) ...[
          _gap(6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => onAddQuestions(s), icon: const Icon(Icons.playlist_add_rounded), label: Text(t('إضافة أسئلة', 'Add questions'))),
          ),
        ],
      ]),
    );
  }

  Widget _questionRow(BuildContext context, SectionDraft s, PlacedQuestion q, int index, {required bool draft}) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.divider)),
      child: Row(children: [
        Text('${index + 1}.', style: appText(13, w: FontWeight.w700, c: c.textMedium)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.prompt.isEmpty ? '—' : q.prompt, style: appText(13.5, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            _gap(4),
            Wrap(spacing: 6, runSpacing: 4, children: [
              AppBadgePill(questionTypeLabel(q.type)),
              AppBadgePill(t('${fmtPoints(q.points)} د', '${fmtPoints(q.points)} pt'), color: c.success),
              if (q.required) AppBadgePill(t('إلزامي', 'Required'), color: c.warning),
              if (q.outdated) AppBadgePill(t('نسخة أحدث متاحة', 'Newer version'), icon: Icons.update_rounded, color: c.warning),
            ]),
          ]),
        ),
        _iconBtn(Icons.edit_outlined, t('تعديل السؤال', 'Edit question'), () => onEditQuestion(s, q), color: c.primary),
        if (draft) _iconBtn(Icons.remove_circle_outline_rounded, t('إزالة من الاختبار', 'Remove from the exam'), () => onRemoveQuestion(q), color: c.danger),
      ]),
    );
  }
}

/// Section form (sheet). Structural fields are read-only once the exam is published.
class SectionForm extends StatefulWidget {
  const SectionForm({super.key, required this.section, required this.onSave, this.published = false});
  final SectionDraft section;
  final Future<String?> Function(SectionDraft section) onSave;
  final bool published;

  @override
  State<SectionForm> createState() => _SectionFormState();
}

class _SectionFormState extends State<SectionForm> with _Controllers {
  List<String> _codes = const [];
  String? _error;
  bool _busy = false;
  SectionDraft get s => widget.section;

  Future<void> _save() async {
    final codes = s.validate();
    setState(() {
      _codes = codes;
      _error = null;
    });
    if (codes.isNotEmpty) return;
    setState(() => _busy = true);
    final err = await widget.onSave(s);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final structural = !widget.published;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSectionTitle(s.id == null ? t('قسم جديد', 'New section') : t('تعديل القسم', 'Edit section')),
        AppField(controller: ctl('title', s.title), label: t('عنوان القسم', 'Section title'), onChanged: (v) => s.title = v),
        AppField(controller: ctl('ins', s.instructions), label: t('تعليمات للطلاب (اختياري)', 'Instructions for students (optional)'), maxLines: 3,
            onChanged: (v) => s.instructions = v),
        AppField(
            controller: ctl('box', s.timeBoxMinutes?.toString() ?? ''), label: t('وقت القسم بالدقائق (اختياري)', 'Section time in minutes (optional)'),
            keyboard: TextInputType.number, ltr: true, onChanged: (v) => s.timeBoxMinutes = v.trim().isEmpty ? null : (parseIntField(v) ?? -1)),
        if (!structural)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppBanner(icon: Icons.lock_outline_rounded, color: c.warning,
                text: t('الاختبار منشور: طريقة التقديم والتنقل والوزن والسحب تُعدَّل في المسودة فقط', 'Published: mode, navigation, weight and pool change only in a draft')),
          ),
        AppDropdown<String>(
          value: s.mode,
          enabled: structural,
          decoration: InputDecoration(labelText: t('طريقة التقديم', 'Mode')),
          items: [for (final m in sectionModes) DropdownMenuItem(value: m, child: Text(sectionModeLabel(m)))],
          onChanged: (v) => setState(() => s.mode = v ?? s.mode),
        ),
        _gap(),
        AppDropdown<String>(
          value: s.navigation,
          enabled: structural,
          decoration: InputDecoration(labelText: t('التنقل بين الأسئلة', 'Navigation')),
          items: [for (final n in sectionNavigations) DropdownMenuItem(value: n, child: Text(navigationLabel(n)))],
          onChanged: (v) => setState(() => s.navigation = v ?? s.navigation),
        ),
        _gap(),
        if (structural) ...[
          AppField(controller: ctl('w', fmtPoints(s.weight)), label: t('وزن القسم (مضاعف الدرجة)', 'Section weight (score multiplier)'), keyboard: _numKeyboard,
              ltr: true, onChanged: (v) => s.weight = parseNum(v) ?? 0),
          AppSwitchTile(title: t('ترتيب الأسئلة عشوائياً لكل طالب', 'Shuffle questions per student'), value: s.shuffleQuestions,
              onChanged: (v) => setState(() => s.shuffleQuestions = v)),
          AppSwitchTile(title: t('ترتيب الخيارات عشوائياً', 'Shuffle options'), value: s.shuffleOptions, onChanged: (v) => setState(() => s.shuffleOptions = v)),
          AppField(
              controller: ctl('pool', s.poolSize?.toString() ?? ''), label: t('سحب عشوائي: عدد الأسئلة لكل طالب (اختياري)', 'Random pool: questions per student (optional)'),
              keyboard: TextInputType.number, ltr: true, onChanged: (v) => s.poolSize = v.trim().isEmpty ? null : (parseIntField(v) ?? -1)),
          AppField(
              controller: ctl('ptags', s.poolTags.join(', ')), label: t('وسوم السحب (اختياري، مفصولة بفواصل)', 'Pool tags (optional, comma separated)'),
              onChanged: (v) => s.poolTags = splitList(v)),
        ],
        _errorsBanner(context, _codes, extra: _error),
        AppPrimaryButton(label: t('حفظ القسم', 'Save section'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Question editor (every type)
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class QuestionEditorForm extends StatefulWidget {
  const QuestionEditorForm({super.key, required this.draft, required this.onSave, this.scrollable = true});
  final QuestionDraft draft;

  /// Saves the (already validated) draft; returns an error text, or null when saved.
  final Future<String?> Function(QuestionDraft draft) onSave;
  final bool scrollable;

  @override
  State<QuestionEditorForm> createState() => _QuestionEditorFormState();
}

class _QuestionEditorFormState extends State<QuestionEditorForm> with _Controllers {
  late QuestionDraft d = widget.draft;
  List<String> _codes = const [];
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final codes = d.validate();
    setState(() {
      _codes = codes;
      _error = null;
    });
    if (codes.isNotEmpty) return;
    setState(() => _busy = true);
    final err = await widget.onSave(d);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Widget _partial(String value, List<(String, String)> choices, ValueChanged<String> onChanged) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppDropdown<String>(
          value: value,
          decoration: InputDecoration(labelText: t('الدرجة الجزئية', 'Partial credit')),
          items: [for (final ch in choices) DropdownMenuItem(value: ch.$1, child: Text(ch.$2))],
          onChanged: (v) => setState(() => onChanged(v ?? value)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSectionTitle(d.isNew ? t('سؤال جديد', 'New question') : t('تعديل السؤال', 'Edit question'),
          subtitle: d.isNew ? null : t('الحفظ ينشئ نسخة جديدة؛ الاختبارات الجارية تبقى على نسختها', 'Saving creates a new version; running exams keep theirs')),
      if (d.isNew)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppDropdown<String>(
            value: d.type,
            decoration: InputDecoration(labelText: t('نوع السؤال', 'Question type')),
            items: [for (final ty in questionTypes) DropdownMenuItem(value: ty, child: Text(questionTypeLabel(ty)))],
            onChanged: (v) => setState(() {
              if (v != null && v != d.type) d = d.withType(v);
              _codes = const [];
            }),
          ),
        )
      else
        Padding(padding: const EdgeInsets.only(bottom: 12), child: Align(alignment: AlignmentDirectional.centerStart, child: AppBadgePill(questionTypeLabel(d.type)))),
      AppField(
          controller: ctl('prompt', d.prompt), label: t('نص السؤال', 'Question text'), maxLines: 4,
          hint: d.type == 'fill_blank' ? t('ضع ___ مكان كل فراغ', 'Put ___ where each blank goes') : null,
          onChanged: (v) => setState(() => d.prompt = v)),
      ..._typeEditor(context),
      AppSectionTitle(t('الدرجة والتصنيف', 'Points and tags')),
      AppField(controller: ctl('pts', fmtPoints(d.points)), label: t('الدرجة', 'Points'), keyboard: _numKeyboard, ltr: true,
          onChanged: (v) => setState(() => d.points = parseNum(v) ?? 0)),
      Text(t('الصعوبة', 'Difficulty'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
      _gap(6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (var i = 1; i <= 5; i++) AppChoiceChip(label: '$i', selected: d.difficulty == i, onTap: () => setState(() => d.difficulty = i)),
      ]),
      _gap(12),
      AppField(controller: ctl('tags', d.tags.join(', ')), label: t('الوسوم (مفصولة بفواصل)', 'Tags (comma separated)'), onChanged: (v) => d.tags = splitList(v)),
      AppField(controller: ctl('expl', d.explanation), label: t('شرح يظهر مع النتيجة (اختياري)', 'Explanation shown with the result (optional)'), maxLines: 2,
          onChanged: (v) => d.explanation = v),
      _errorsBanner(context, _codes, extra: _error),
      AppPrimaryButton(label: d.isNew ? t('حفظ في البنك', 'Save to the bank') : t('حفظ نسخة جديدة', 'Save a new version'), icon: Icons.save_rounded,
          busy: _busy, onPressed: _save),
      _gap(16),
    ]);
    return widget.scrollable ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), child: content) : content;
  }

  List<Widget> _typeEditor(BuildContext context) {
    final c = context.colors;
    switch (d.type) {
      case 'mcq_single':
      case 'mcq_multi':
        final multi = d.type == 'mcq_multi';
        return [
          AppSectionTitle(t('الخيارات', 'Options'), subtitle: multi ? t('علّم كل الإجابات الصحيحة', 'Mark every correct answer') : t('علّم الإجابة الصحيحة', 'Mark the correct answer')),
          for (final o in d.options)
            Row(key: ValueKey('opt.${o.uid}'), children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _iconBtn(
                  multi
                      ? (d.correctMulti.contains(o.id) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded)
                      : (d.correctSingle == o.id ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded),
                  t('الإجابة الصحيحة', 'Correct answer'),
                  () => setState(() {
                    if (multi) {
                      d.correctMulti.contains(o.id) ? d.correctMulti.remove(o.id) : d.correctMulti.add(o.id);
                    } else {
                      d.correctSingle = o.id;
                    }
                  }),
                  color: (multi ? d.correctMulti.contains(o.id) : d.correctSingle == o.id) ? c.success : c.textLight,
                ),
              ),
              Expanded(child: AppField(controller: ctl('opt.${o.uid}', o.text), label: t('الخيار ${o.id}', 'Option ${o.id}'), onChanged: (v) => o.text = v)),
              if (d.options.length > 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _iconBtn(Icons.delete_outline_rounded, t('حذف', 'Remove'), () => setState(() {
                        d.options.remove(o);
                        d.correctMulti.remove(o.id);
                        if (d.correctSingle == o.id) d.correctSingle = null;
                      }), color: c.danger),
                ),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: () => setState(() => d.options.add(QOption(nextOptionId(d.options.map((o) => o.id))))),
                icon: const Icon(Icons.add_rounded), label: Text(t('إضافة خيار', 'Add an option'))),
          ),
          if (multi)
            _partial(d.multiPartial, [('proportional', t('نسبية (الصحيح ناقص الخطأ)', 'Proportional (right minus wrong)')), ('none', t('كل شيء أو لا شيء', 'All or nothing'))],
                (v) => d.multiPartial = v),
        ];
      case 'true_false':
        return [
          AppSectionTitle(t('الإجابة الصحيحة', 'Correct answer')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(label: t('صح', 'True'), icon: Icons.check_rounded, selected: d.tfCorrect == true, onTap: () => setState(() => d.tfCorrect = true)),
            AppChoiceChip(label: t('خطأ', 'False'), icon: Icons.close_rounded, selected: d.tfCorrect == false, onTap: () => setState(() => d.tfCorrect = false)),
          ]),
          _gap(12),
        ];
      case 'fill_blank':
        final marks = blankMarkers(d.prompt);
        return [
          AppSectionTitle(t('الفراغات', 'Blanks'), subtitle: t('لكل فراغ الإجابات المقبولة مفصولة بفواصل (تُقبل الأخطاء الإملائية البسيطة)', 'Accepted answers of each blank, comma separated (small typos are tolerated)')),
          if (marks > 0 && marks != d.blanks.length)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning,
                  text: t('في النص $marks فراغات و${d.blanks.length} إجابات', 'The text has $marks blanks and ${d.blanks.length} answer lists')),
            ),
          for (var i = 0; i < d.blanks.length; i++)
            Row(key: ValueKey('blank.${d.blanks[i].uid}'), children: [
              Expanded(child: AppField(controller: ctl('blank.${d.blanks[i].uid}', d.blanks[i].text), label: t('الفراغ ${i + 1}', 'Blank ${i + 1}'),
                  onChanged: (v) => d.blanks[i].text = v)),
              if (d.blanks.length > 1)
                Padding(padding: const EdgeInsets.only(bottom: 12),
                    child: _iconBtn(Icons.delete_outline_rounded, t('حذف', 'Remove'), () => setState(() => d.blanks.removeAt(i)), color: c.danger)),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => setState(() => d.blanks.add(TextItem())), icon: const Icon(Icons.add_rounded), label: Text(t('إضافة فراغ', 'Add a blank'))),
          ),
          _partial(d.blankPartial, [('per_blank', t('لكل فراغ درجته', 'Per blank')), ('none', t('كل شيء أو لا شيء', 'All or nothing'))], (v) => d.blankPartial = v),
        ];
      case 'matching':
        return [
          AppSectionTitle(t('أزواج المطابقة', 'Pairs to match'), subtitle: t('يرى الطالب العمود الأيمن بترتيب مختلف', 'Students see the right column in another order')),
          for (final p in d.pairs)
            Row(key: ValueKey('pair.${p.uid}'), children: [
              Expanded(child: AppField(controller: ctl('pl.${p.uid}', p.left), label: t('العنصر', 'Item'), onChanged: (v) => p.left = v)),
              Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 12), child: Icon(Icons.swap_horiz_rounded, size: 18, color: c.textLight)),
              Expanded(child: AppField(controller: ctl('pr.${p.uid}', p.right), label: t('يطابق', 'Matches'), onChanged: (v) => p.right = v)),
              if (d.pairs.length > 2)
                Padding(padding: const EdgeInsets.only(bottom: 12),
                    child: _iconBtn(Icons.delete_outline_rounded, t('حذف', 'Remove'), () => setState(() => d.pairs.remove(p)), color: c.danger)),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => setState(() => d.pairs.add(MatchPair())), icon: const Icon(Icons.add_rounded), label: Text(t('إضافة زوج', 'Add a pair'))),
          ),
          AppField(controller: ctl('distr', d.distractors), label: t('خيارات مضللة في العمود الأيمن (اختياري)', 'Extra distractors on the right (optional)'),
              onChanged: (v) => d.distractors = v),
          _partial(d.matchPartial, [('proportional', t('لكل زوج درجته', 'Per pair')), ('none', t('كل شيء أو لا شيء', 'All or nothing'))], (v) => d.matchPartial = v),
        ];
      case 'ordering':
        return [
          AppSectionTitle(t('العناصر بالترتيب الصحيح', 'Items in the correct order'), subtitle: t('يراها الطالب بترتيب مختلف', 'Students get them in another order')),
          for (var i = 0; i < d.items.length; i++)
            Row(key: ValueKey('item.${d.items[i].uid}'), children: [
              Padding(padding: const EdgeInsetsDirectional.only(end: 6, bottom: 12), child: Text('${i + 1}', style: appText(13, w: FontWeight.w700, c: c.textMedium))),
              Expanded(child: AppField(controller: ctl('item.${d.items[i].uid}', d.items[i].text), label: t('العنصر ${i + 1}', 'Item ${i + 1}'),
                  onChanged: (v) => d.items[i].text = v)),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _iconBtn(Icons.arrow_upward_rounded, t('لأعلى', 'Up'), i == 0 ? null : () => setState(() => d.items.insert(i - 1, d.items.removeAt(i)))),
                  _iconBtn(Icons.arrow_downward_rounded, t('لأسفل', 'Down'),
                      i == d.items.length - 1 ? null : () => setState(() => d.items.insert(i + 1, d.items.removeAt(i)))),
                  if (d.items.length > 2) _iconBtn(Icons.delete_outline_rounded, t('حذف', 'Remove'), () => setState(() => d.items.removeAt(i)), color: c.danger),
                ]),
              ),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: () => setState(() => d.items.add(TextItem())), icon: const Icon(Icons.add_rounded), label: Text(t('إضافة عنصر', 'Add an item'))),
          ),
          _partial(d.orderPartial, [
            ('position', t('لكل عنصر في مكانه', 'Per item in its place')),
            ('adjacent', t('لكل زوج متتالٍ صحيح', 'Per correct neighbour pair')),
            ('none', t('كل شيء أو لا شيء', 'All or nothing')),
          ], (v) => d.orderPartial = v),
        ];
      case 'numeric':
        return [
          AppSectionTitle(t('الإجابة الرقمية', 'Numeric answer')),
          AppField(controller: ctl('nv', d.numValue), label: t('القيمة الصحيحة', 'Correct value'), keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
              ltr: true, onChanged: (v) => d.numValue = v),
          AppField(controller: ctl('nt', d.numTolerance), label: t('التسامح (اختياري)', 'Tolerance (optional)'), keyboard: _numKeyboard, ltr: true,
              onChanged: (v) => d.numTolerance = v),
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppChoiceChip(label: t('قيمة مطلقة ±', 'Absolute ±'), selected: d.toleranceKind == 'abs', onTap: () => setState(() => d.toleranceKind = 'abs')),
            AppChoiceChip(label: t('نسبة مئوية ٪', 'Percent %'), selected: d.toleranceKind == 'pct', onTap: () => setState(() => d.toleranceKind = 'pct')),
          ]),
          AppSectionTitle(t('الوحدات (اختياري)', 'Units (optional)'),
              subtitle: t('وحدة القيمة الصحيحة معاملها 1؛ والأخرى كم تساوي منها (مثلاً cm = 0.01 إذا كانت الأساسية m)', 'The correct value\'s unit has factor 1; others say how much of it they are (cm = 0.01 when the base is m)')),
          for (final u in d.units)
            Row(key: ValueKey('unit.${u.uid}'), children: [
              Expanded(child: AppField(controller: ctl('un.${u.uid}', u.name), label: t('الوحدة', 'Unit'), ltr: true, onChanged: (v) => u.name = v)),
              const SizedBox(width: 8),
              Expanded(child: AppField(controller: ctl('uf.${u.uid}', u.factor), label: t('المعامل', 'Factor'), keyboard: _numKeyboard, ltr: true,
                  onChanged: (v) => u.factor = v)),
              Padding(padding: const EdgeInsets.only(bottom: 12),
                  child: _iconBtn(Icons.delete_outline_rounded, t('حذف', 'Remove'), () => setState(() => d.units.remove(u)), color: c.danger)),
            ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: () => setState(() => d.units.add(NumericUnit('', d.units.isEmpty ? '1' : ''))),
                icon: const Icon(Icons.add_rounded), label: Text(t('إضافة وحدة', 'Add a unit'))),
          ),
        ];
      default:
        final total = rubricTotal(d.rubric);
        return [
          if (d.type == 'file_upload')
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(icon: Icons.upload_file_rounded, text: t('يرفع الطالب ملفاً؛ يُصحَّح يدوياً بالمعايير أدناه', 'Students upload a file; it is marked by hand with the criteria below')),
            ),
          AppSectionTitle(t('مفتاح التصحيح', 'Marking key'), subtitle: t('إجابة نموذجية أو معايير — أو كلاهما', 'A model answer or criteria — or both')),
          AppField(controller: ctl('model', d.model), label: t('الإجابة النموذجية', 'Model answer'), maxLines: 4, onChanged: (v) => d.model = v),
          AppField(controller: ctl('alts', d.alternatives), label: t('صيغ مقبولة أخرى (سطر لكل صيغة)', 'Other accepted wordings (one per line)'), maxLines: 3,
              onChanged: (v) => d.alternatives = v),
          AppSectionTitle(t('معايير التصحيح', 'Rubric criteria'),
              trailing: d.rubric.isEmpty ? null : AppBadgePill(t('المجموع ${fmtPoints(total)}', 'Total ${fmtPoints(total)}'), color: c.success)),
          if (d.rubric.isNotEmpty && (total - d.points).abs() > 1e-9)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppBanner(icon: Icons.info_outline_rounded,
                  text: t('مجموع المعايير ${fmtPoints(total)} ودرجة السؤال ${fmtPoints(d.points)}: تُحوَّل درجات المعايير بالنسبة', 'Criteria total ${fmtPoints(total)}, question points ${fmtPoints(d.points)}: criterion scores are scaled')),
            ),
          for (final cr in d.rubric)
            AppCard(
              key: ValueKey('crit.${cr.uid}'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  AppBadgePill(cr.id),
                  const Spacer(),
                  _iconBtn(Icons.delete_outline_rounded, t('حذف المعيار', 'Remove criterion'), () => setState(() => d.rubric.remove(cr)), color: c.danger),
                ]),
                _gap(8),
                AppField(controller: ctl('cc.${cr.uid}', cr.criterion), label: t('المعيار', 'Criterion'), maxLines: 2, onChanged: (v) => cr.criterion = v),
                AppField(controller: ctl('cp.${cr.uid}', fmtPoints(cr.points)), label: t('درجة المعيار', 'Criterion points'), keyboard: _numKeyboard, ltr: true,
                    onChanged: (v) => setState(() => cr.points = parseNum(v) ?? 0)),
                AppField(controller: ctl('cm.${cr.uid}', cr.model), label: t('صياغة مرجعية (اختياري)', 'Reference wording (optional)'), maxLines: 2,
                    onChanged: (v) => cr.model = v),
                AppField(
                    controller: ctl('ck.${cr.uid}', keywordsText(cr.keywords)), label: t('كلمات مفتاحية (سطر لكل كلمة)', 'Keywords (one per line)'),
                    hint: t('الكلمة = مرادف، مرادف', 'term = synonym, synonym'), maxLines: 3, onChanged: (v) => cr.keywords = parseKeywords(v)),
              ]),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
                onPressed: () => setState(() => d.rubric.add(RubricCriterion(id: nextCriterionId(d.rubric)))),
                icon: const Icon(Icons.add_rounded), label: Text(t('إضافة معيار', 'Add a criterion'))),
          ),
        ];
    }
  }
}

/// Opens the question editor; pops with the saved question (the server's reply) or null.
Future<Map<String, dynamic>?> showQuestionEditor(BuildContext context, {QuestionDraft? draft, int? orgId, int? courseId, ExamAuthoringApi? api}) {
  final a = api ?? ExamAuthoringApi();
  return showAppSheet<Map<String, dynamic>>(
    context,
    (ctx) => QuestionEditorForm(
      draft: draft ?? QuestionDraft(),
      onSave: (d) async {
        final r = d.isNew ? await a.createQuestion(d.toCreate(orgId: orgId, courseId: courseId)) : await a.updateQuestion(d.id!, d.toUpdate());
        if (!r.ok) return authoringError(r);
        if (ctx.mounted) Navigator.of(ctx).pop(r.map);
        return null;
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Question bank
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class BankQuestionTile extends StatelessWidget {
  const BankQuestionTile({super.key, required this.question, this.trailing, this.onTap});
  final BankQuestion question;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = question;
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: onTap,
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q.prompt.isEmpty ? '—' : q.prompt, style: appText(13.5, w: FontWeight.w600, c: c.textDark), maxLines: 2, overflow: TextOverflow.ellipsis),
            _gap(6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              AppBadgePill(questionTypeLabel(q.type)),
              AppBadgePill(t('${fmtPoints(q.points)} د', '${fmtPoints(q.points)} pt'), color: c.success),
              AppBadgePill(t('نسخة ${q.version}', 'v${q.version}'), color: c.textMedium),
              if (q.status != 'active') AppBadgePill(t('مؤرشف', 'Archived'), color: c.warning),
              for (final tag in q.tags.take(3)) AppBadgePill('#$tag', color: c.textMedium),
            ]),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

/// The bank of a space (an organization, or the personal one) with search and a type filter.
class QuestionBankBrowser extends StatefulWidget {
  const QuestionBankBrowser({super.key, required this.orgId, this.courseId, required this.api, this.header = const [], this.trailing, this.onTap, this.refreshTick = 0});
  final int? orgId;
  final int? courseId;
  final ExamAuthoringApi api;
  final List<Widget> header;
  final Widget? Function(BankQuestion q)? trailing;
  final ValueChanged<BankQuestion>? onTap;

  /// Bump to reload (after a question was created elsewhere).
  final int refreshTick;

  @override
  State<QuestionBankBrowser> createState() => _QuestionBankBrowserState();
}

class _QuestionBankBrowserState extends State<QuestionBankBrowser> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _type;
  List<BankQuestion>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QuestionBankBrowser old) {
    super.didUpdateWidget(old);
    if (old.refreshTick != widget.refreshTick) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  int _gen = 0;

  Future<void> _load() async {
    final gen = ++_gen;                                  // a slower, older search never replaces a newer one
    final r = await widget.api.questions(orgId: widget.orgId, courseId: widget.courseId, type: _type, q: _search.text);
    if (!mounted || gen != _gen) return;
    setState(() {
      _error = r.ok ? null : authoringError(r);
      _items = r.ok ? [for (final q in asMapList(r.map['items'])) BankQuestion.fromJson(q)] : (_items ?? const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = _items;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      ...widget.header,
      AppField(
          controller: _search, label: t('بحث في نص السؤال', 'Search the question text'),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          }),
      AppDropdown<String?>(
        value: _type,
        decoration: InputDecoration(labelText: t('النوع', 'Type')),
        items: [
          DropdownMenuItem<String?>(value: null, child: Text(t('كل الأنواع', 'All types'))),
          for (final ty in questionTypes) DropdownMenuItem<String?>(value: ty, child: Text(questionTypeLabel(ty))),
        ],
        onChanged: (v) {
          setState(() => _type = v);
          _load();
        },
      ),
      _gap(12),
      if (_error != null) AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: c.danger),
      if (items == null) const SizedBox(height: 260, child: AppListSkeleton(items: 3, withAvatar: false, padding: EdgeInsets.zero)),
      if (items != null && items.isEmpty && _error == null)
        AppEmpty(icon: Icons.quiz_outlined, title: t('البنك فارغ', 'The bank is empty'), message: t('أنشئ سؤالاً جديداً', 'Create a new question')),
      if (items != null)
        for (final q in items)
          BankQuestionTile(question: q, trailing: widget.trailing?.call(q), onTap: widget.onTap == null ? null : () => widget.onTap!(q)),
    ]);
  }
}

class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key, this.orgId, this.courseId});
  final int? orgId;
  final int? courseId;

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  final _api = ExamAuthoringApi();
  int _tick = 0;

  Future<void> _edit(BankQuestion? q) async {
    final saved = await showQuestionEditor(context, draft: q == null ? null : QuestionDraft.fromJson(q.raw), orgId: widget.orgId, courseId: widget.courseId, api: _api);
    if (saved != null && mounted) setState(() => _tick++);
  }

  Future<void> _archive(BankQuestion q) async {
    final ok = await appConfirm(context, danger: true, confirmLabel: t('أرشفة', 'Archive'),
        message: t('أرشفة السؤال؟ يبقى في الاختبارات التي وُضع فيها', 'Archive the question? Exams that placed it keep it'));
    if (!ok) return;
    final r = await _api.archiveQuestion(q.id);
    if (!r.ok) return appToast(authoringError(r), error: true);
    if (mounted) setState(() => _tick++);
  }

  @override
  Widget build(BuildContext context) => BasePage(
        key: const ValueKey('exam.question_bank'),
        appBar: AppBar(title: Text(t('بنك الأسئلة', 'Question bank')), actions: [
          IconButton(onPressed: () => _edit(null), icon: const Icon(Icons.add_rounded), tooltip: t('سؤال جديد', 'New question')),
        ]),
        child: QuestionBankBrowser(
          courseId: widget.courseId,
          orgId: widget.orgId,
          api: _api,
          refreshTick: _tick,
          onTap: _edit,
          trailing: (q) => _iconBtn(Icons.archive_outlined, t('أرشفة', 'Archive'), () => _archive(q), color: context.colors.textMedium),
        ),
      );
}

/// Pick bank questions into a section (or write a new one and place it).
class QuestionPickerSheet extends StatefulWidget {
  const QuestionPickerSheet({super.key, required this.orgId, this.courseId, required this.api, required this.placedIds, required this.onPlace, this.sectionTitle = ''});
  final int? orgId;
  final int? courseId;
  final ExamAuthoringApi api;
  final Set<int> placedIds;
  final String sectionTitle;

  /// Places the question; returns an error text or null.
  final Future<String?> Function(int questionId, double? points, bool required) onPlace;

  @override
  State<QuestionPickerSheet> createState() => _QuestionPickerSheetState();
}

class _QuestionPickerSheetState extends State<QuestionPickerSheet> {
  final _points = TextEditingController();
  bool _required = false;
  late final Set<int> _placed = {...widget.placedIds};
  final Set<int> _busy = {};
  int _tick = 0;

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  Future<void> _place(int qid) async {
    final pts = _points.text.trim().isEmpty ? null : parseNum(_points.text);
    if (_points.text.trim().isNotEmpty && (pts == null || pts <= 0)) return appToast(authoringCodeText('points_positive'), error: true);
    setState(() => _busy.add(qid));
    final err = await widget.onPlace(qid, pts, _required);
    if (!mounted) return;
    setState(() {
      _busy.remove(qid);
      if (err == null) _placed.add(qid);
    });
    if (err != null) appToast(err, error: true);
  }

  Future<void> _new() async {
    final saved = await showQuestionEditor(context, orgId: widget.orgId, courseId: widget.courseId, api: widget.api);
    if (saved == null || !mounted) return;
    setState(() => _tick++);
    await _place(asInt(saved['id']));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return QuestionBankBrowser(
      courseId: widget.courseId,
      orgId: widget.orgId,
      api: widget.api,
      refreshTick: _tick,
      header: [
        AppSectionTitle(t('إضافة أسئلة', 'Add questions'), subtitle: widget.sectionTitle.isEmpty ? null : widget.sectionTitle),
        AppField(controller: _points, label: t('درجة السؤال في هذا الاختبار (اختياري)', 'Points in this exam (optional)'),
            hint: t('فارغ = درجة السؤال في البنك', 'Empty = the bank question\'s points'), keyboard: _numKeyboard, ltr: true),
        AppSwitchTile(title: t('إلزامي', 'Required'), value: _required, onChanged: (v) => setState(() => _required = v)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(onPressed: _new, icon: const Icon(Icons.add_circle_outline_rounded), label: Text(t('كتابة سؤال جديد', 'Write a new question'))),
        ),
        _gap(4),
      ],
      trailing: (q) => _placed.contains(q.id)
          ? Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.check_circle_rounded, color: c.success))
          : _busy.contains(q.id)
              ? const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : _iconBtn(Icons.add_circle_outline_rounded, t('إضافة', 'Add'), q.status == 'active' ? () => _place(q.id) : null, color: c.primary),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Proctoring + accommodations
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class ProctoringPolicyForm extends StatefulWidget {
  const ProctoringPolicyForm({super.key, required this.draft, required this.consents, required this.onSave, this.consentsLoaded = true});
  final ProctoringDraft draft;
  final List<Map<String, dynamic>> consents;
  final bool consentsLoaded;
  final Future<String?> Function(ProctoringDraft draft) onSave;

  @override
  State<ProctoringPolicyForm> createState() => _ProctoringPolicyFormState();
}

class _ProctoringPolicyFormState extends State<ProctoringPolicyForm> {
  List<String> _codes = const [];
  String? _error;
  bool _busy = false;
  ProctoringDraft get p => widget.draft;

  Future<void> _save() async {
    final codes = p.validate();
    setState(() {
      _codes = codes;
      _error = null;
    });
    if (codes.isNotEmpty) return;
    setState(() => _busy = true);
    final err = await widget.onSave(p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final undeclared = widget.consentsLoaded ? undeclaredSensors(p, widget.consents) : const <String>[];
    final idle = p.idleRules;
    final unused = p.unusedCategories;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppBanner(
          icon: Icons.verified_user_outlined,
          text: t('يقرأ كل طالب نص الإقرار ويوافق عليه قبل البدء (إلزامي دائماً). لا تُراقب الكاميرا أو الميكروفون أو الشاشة إلا إذا ذكرها النص.',
              'Every student reads and accepts the consent text before starting (always required). Camera, microphone and screen are monitored only when the text declares them.')),
      if (undeclared.isNotEmpty) ...[
        _gap(8),
        AppBanner(
            icon: Icons.warning_amber_rounded, color: c.warning,
            text: t('نص الإقرار الحالي لا يذكر: ${undeclared.map(sensorLabel).join('، ')} — لن تُسجَّل هذه المراقبة حتى يُحدَّث النص',
                'The active consent text does not declare: ${undeclared.map(sensorLabel).join(', ')} — that monitoring is ignored until the text is updated')),
      ],
      AppSectionTitle(t('ما يُراقَب', 'What is monitored')),
      AppSwitchTile(title: t('الكاميرا (الوجه والنظر)', 'Camera (face and gaze)'), icon: Icons.videocam_outlined, value: p.camera,
          onChanged: (v) => setState(() => p.camera = v)),
      AppSwitchTile(title: t('الميكروفون (الكلام)', 'Microphone (speech)'), icon: Icons.mic_none_rounded, value: p.mic, onChanged: (v) => setState(() => p.mic = v)),
      AppSwitchTile(title: t('الشاشة (لقطات الشاشة)', 'Screen (screenshots)'), icon: Icons.screenshot_monitor_outlined, value: p.screen,
          onChanged: (v) => setState(() => p.screen = v)),
      AppSectionTitle(t('القواعد', 'Rules'), subtitle: t('عدد المرات المسموحة لكل مخالفة، ثم النتيجة', 'How many times each signal is allowed, then the consequence'),
          trailing: TextButton(onPressed: () => setState(() => p.rules = defaultProctorRules()), child: Text(t('الافتراضي', 'Defaults')))),
      for (final r in p.rules)
        AppCard(
          key: ValueKey('rule.${r.category}'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(categoryLabel(r.category), style: appText(14, w: FontWeight.w700, c: c.textDark))),
              _iconBtn(Icons.delete_outline_rounded, t('حذف القاعدة', 'Remove rule'), () => setState(() => p.rules.remove(r)), color: c.danger),
            ]),
            if (idle.contains(r))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(t('لا تعمل إلا مع مراقبة ${sensorLabel(categorySensor[r.category]!)}', 'Works only with ${sensorLabel(categorySensor[r.category]!)} monitoring'),
                    style: appText(12, c: c.warning)),
              ),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 8, children: [
              _iconBtn(Icons.remove_rounded, t('أقل', 'Fewer'), r.max <= 0 ? null : () => setState(() => r.max--)),
              Text(t('مسموح ${r.max}', 'Allowed ${r.max}'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              _iconBtn(Icons.add_rounded, t('أكثر', 'More'), r.max >= 99 ? null : () => setState(() => r.max++)),
            ]),
            _gap(6),
            AppDropdown<String>(
              value: r.consequence,
              decoration: InputDecoration(labelText: t('ثم', 'Then')),
              items: [for (final cons in proctorConsequences) DropdownMenuItem(value: cons, child: Text(consequenceLabel(cons)))],
              onChanged: (v) => setState(() => r.consequence = v ?? r.consequence),
            ),
            if (r.consequence == 'reject' && !p.autoReject)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t('بدون «الرفض التلقائي» تُعلَّم المحاولة للمراجعة فقط', 'Without "automatic rejection" the attempt is only flagged'),
                    style: appText(12, c: c.textMedium)),
              ),
          ]),
        ),
      if (unused.isNotEmpty)
        AppDropdown<String>(
          value: null,
          decoration: InputDecoration(labelText: t('إضافة قاعدة', 'Add a rule')),
          items: [for (final cat in unused) DropdownMenuItem(value: cat, child: Text(categoryLabel(cat)))],
          onChanged: (v) {
            if (v != null) setState(() => p.rules.add(ProctorRule(v, 1, 'flag')));
          },
        ),
      _gap(),
      AppSwitchTile(
          title: t('الرفض التلقائي', 'Automatic rejection'), subtitle: t('قاعدة «رفض» تنهي المحاولة كمرفوضة بلا مراجعة بشرية', 'A "reject" rule finalises the attempt as rejected without human review'),
          value: p.autoReject, onChanged: (v) => setState(() => p.autoReject = v)),
      AppSwitchTile(
          title: t('معايرة الكاميرا قبل البدء', 'Camera calibration before starting'), value: p.calibration, onChanged: (v) => setState(() => p.calibration = v)),
      _gap(),
      _errorsBanner(context, _codes, extra: _error),
      AppPrimaryButton(label: t('حفظ سياسة المراقبة', 'Save the proctoring policy'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
    ]);
  }
}

class AccommodationsPanel extends StatelessWidget {
  const AccommodationsPanel({super.key, required this.items, required this.onAdd, required this.onRevoke, this.error});
  final List<Map<String, dynamic>>? items;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onRevoke;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = items;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSectionTitle(t('التيسيرات', 'Accommodations'), subtitle: t('وقت إضافي وتسهيلات لطلاب محددين', 'Extra time and aids for specific students'),
          trailing: _iconBtn(Icons.person_add_alt_rounded, t('إضافة تيسير', 'Add an accommodation'), onAdd, color: c.primary)),
      if (error != null) AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
      if (list == null && error == null) const SizedBox(height: 120, child: AppListSkeleton(items: 2, withAvatar: false, padding: EdgeInsets.zero)),
      if (list != null && list.isEmpty) Text(t('لا توجد تيسيرات', 'No accommodations'), style: appText(13, c: c.textLight)),
      if (list != null)
        for (final a in list)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              Icon(Icons.accessibility_new_rounded, color: c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('الطالب #${asInt(a['student_id'])}', 'Student #${asInt(a['student_id'])}'), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                  Text(accommodationSummary(a), style: appText(12.5, c: c.textMedium)),
                  if ('${a['note'] ?? ''}'.isNotEmpty) Text('${a['note']}', style: appText(12, c: c.textLight), maxLines: 2, overflow: TextOverflow.ellipsis),
                ]),
              ),
              _iconBtn(Icons.delete_outline_rounded, t('إلغاء التيسير', 'Revoke'), () => onRevoke(a), color: c.danger),
            ]),
          ),
      _gap(24),
    ]);
  }
}

class AccommodationForm extends StatefulWidget {
  const AccommodationForm({super.key, required this.onSave});
  final Future<String?> Function(AccommodationDraft draft) onSave;

  @override
  State<AccommodationForm> createState() => _AccommodationFormState();
}

class _AccommodationFormState extends State<AccommodationForm> with _Controllers {
  final a = AccommodationDraft();
  List<String> _codes = const [];
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final codes = a.validate();
    setState(() {
      _codes = codes;
      _error = null;
    });
    if (codes.isNotEmpty) return;
    setState(() => _busy = true);
    final err = await widget.onSave(a);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          AppSectionTitle(t('تيسير لطالب', 'Accommodation for a student')),
          AppField(controller: ctl('sid', ''), label: t('رقم الطالب', 'Student id'), keyboard: TextInputType.number, ltr: true, onChanged: (v) => a.studentId = v),
          AppField(controller: ctl('min', ''), label: t('دقائق إضافية', 'Extra minutes'), keyboard: TextInputType.number, ltr: true, onChanged: (v) => a.extraMinutes = v),
          AppField(controller: ctl('pct', ''), label: t('أو نسبة إضافية من الوقت ٪', 'Or extra time %'), keyboard: TextInputType.number, ltr: true,
              onChanged: (v) => a.extraPercent = v),
          AppSwitchTile(title: t('خط كبير', 'Large text'), value: a.largeText, onChanged: (v) => setState(() => a.largeText = v)),
          AppSwitchTile(title: t('قارئ شاشة', 'Screen reader'), value: a.screenReader, onChanged: (v) => setState(() => a.screenReader = v)),
          AppSwitchTile(title: t('مراقبة مخففة (ضعف الحدود)', 'Relaxed proctoring (double limits)'), value: a.relaxedThresholds,
              onChanged: (v) => setState(() => a.relaxedThresholds = v)),
          AppSwitchTile(title: t('لهذا الاختبار فقط', 'This exam only'), subtitle: t('أوقفه ليشمل كل اختبارات المساحة', 'Turn off to cover every exam of the space'),
              value: a.examOnly, onChanged: (v) => setState(() => a.examOnly = v)),
          AppField(controller: ctl('note', ''), label: t('ملاحظة (اختياري)', 'Note (optional)'), maxLines: 2, onChanged: (v) => a.note = v),
          _errorsBanner(context, _codes, extra: _error),
          AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.save_rounded, busy: _busy, onPressed: _save),
        ]),
      );
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// Publish / lifecycle
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

class ExamPublishPanel extends StatelessWidget {
  const ExamPublishPanel({super.key, required this.view, required this.onAction, this.busy, this.error});
  final ExamView view;
  final ValueChanged<ExamAction> onAction;
  final ExamAction? busy;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = view.exam;
    final blockers = e.isDraft ? publishBlockers(view) : const <PublishBlocker>[];
    final actions = lifecycleActions(e.status, resultsPublished: e.resultsPublishedAt != null);
    final statusColor = switch (e.status) { 'published' => c.success, 'closed' => c.textMedium, _ => c.warning };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppCard(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            AppBadgePill(examStatusLabel(e.status), color: statusColor, icon: Icons.flag_outlined),
            if (e.resultsPublishedAt != null) AppBadgePill(t('النتائج منشورة', 'Results published'), color: c.success, icon: Icons.campaign_outlined),
            AppBadgePill(t('${view.questionCount} سؤال', '${view.questionCount} questions')),
            AppBadgePill(t('الدرجة ${fmtPoints(view.maxScore)}', 'Score ${fmtPoints(view.maxScore)}')),
          ]),
          _gap(10),
          if (e.startsAt != null) Text(t('يبدأ: ${AppTime.dateTime(e.startsAt!)}', 'Opens: ${AppTime.dateTime(e.startsAt!)}'), style: appText(13, c: c.textMedium)),
          if (e.endsAt != null) Text(t('ينتهي: ${AppTime.dateTime(e.endsAt!)}', 'Closes: ${AppTime.dateTime(e.endsAt!)}'), style: appText(13, c: c.textMedium)),
          if (e.durationMinutes != null) Text(t('المدة: ${e.durationMinutes} دقيقة', 'Duration: ${e.durationMinutes} min'), style: appText(13, c: c.textMedium)),
          Text(resultsPolicyLabel(e.resultsPolicy), style: appText(13, c: c.textMedium)),
        ]),
      ),
      if (e.isDraft && blockers.isNotEmpty) ...[
        AppSectionTitle(t('قبل النشر', 'Before publishing')),
        for (final b in blockers)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
              const SizedBox(width: 8),
              Expanded(child: Text(b.text, style: appText(13.5, c: c.textDark, h: 1.4))),
            ]),
          ),
        _gap(4),
      ],
      if (e.isDraft && blockers.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppBanner(icon: Icons.check_circle_outline_rounded, color: c.success, text: t('جاهز للنشر', 'Ready to publish')),
        ),
      if (e.status == 'published')
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppBanner(icon: Icons.info_outline_rounded,
              text: t('إلغاء النشر ممكن قبل أن يبدأ أي طالب؛ بعدها أغلق الاختبار', 'Unpublishing works until a student starts; after that, close the exam')),
        ),
      if (error != null)
        Padding(padding: const EdgeInsets.only(bottom: 12), child: AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger)),
      for (final a in actions)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: a == ExamAction.publish || a == ExamAction.publishResults
              ? AppPrimaryButton(label: examActionLabel(a), icon: a == ExamAction.publish ? Icons.publish_rounded : Icons.campaign_rounded, busy: busy == a,
                  onPressed: busy != null || (a == ExamAction.publish && blockers.isNotEmpty) ? null : () => onAction(a))
              : SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: busy != null ? null : () => onAction(a),
                    icon: Icon(a == ExamAction.close ? Icons.lock_outline_rounded : Icons.undo_rounded),
                    label: Text(examActionLabel(a), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
        ),
      if (actions.isEmpty) Text(t('لا إجراءات متاحة لهذا الاختبار', 'No actions for this exam'), style: appText(13, c: c.textLight)),
      _gap(24),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
// The editor screen
// ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

/// Create ([examId] null) or edit an Exam Engine exam. [courseId] / [orgId] are the space for a new exam; when the
/// course belongs to an organization the server names it (409 `course_not_in_org` + `course_org_id`) and the
/// exam is created there.
class ExamEditorScreen extends StatefulWidget {
  const ExamEditorScreen({super.key, this.examId, this.courseId, this.orgId});
  final int? examId;
  final int? courseId;
  final int? orgId;

  @override
  State<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends State<ExamEditorScreen> {
  final _api = ExamAuthoringApi();
  late int? _examId = widget.examId;
  ExamView? _view;
  ExamDraft? _working;
  ExamDraft? _newDraft;
  String? _error;
  ProctoringDraft _proctor = ProctoringDraft();
  List<Map<String, dynamic>> _consents = const [];
  bool _consentsLoaded = false;
  List<Map<String, dynamic>>? _accommodations;
  String? _accError;
  ExamAction? _busyAction;
  String? _publishError;

  @override
  void initState() {
    super.initState();
    if (_examId == null) {
      _newDraft = ExamDraft()
        ..courseId = widget.courseId
        ..orgId = widget.orgId;
    } else {
      _load();
    }
  }

  int _settingsGen = 0;

  /// The PUT / create replies carry no `proctoring`: the policy loaded before stays. Unsaved settings edits survive
  /// reloads made by the other tabs unless [resetSettings].
  void _apply(Map<String, dynamic> j, {bool resetSettings = false}) {
    final hasPolicy = j.containsKey('proctoring');
    final v = ExamView.fromJson(hasPolicy ? j : {...j, 'proctoring': _view?.proctoring});
    _view = v;
    if (resetSettings || _working == null) {
      _working = v.exam.copy();
      _settingsGen++;
    }
    if (hasPolicy) _proctor = ProctoringDraft.fromJson(j['proctoring'] is Map ? asMap(j['proctoring']) : null);
  }

  Future<void> _load({bool side = true, bool resetSettings = false}) async {
    final id = _examId;
    if (id == null) return;
    final r = await _api.exam(id);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _apply(r.map, resetSettings: resetSettings);
        _error = null;
      } else {
        _error = authoringError(r);
      }
    });
    if (r.ok && side) {
      _loadAccommodations();
      _loadConsents();
    }
  }

  Future<void> _loadAccommodations() async {
    final id = _examId;
    if (id == null) return;
    final r = await _api.accommodations(id);
    if (!mounted) return;
    setState(() {
      _accommodations = r.ok ? asMapList(r.map['items']) : (_accommodations ?? const []);
      _accError = r.ok ? null : authoringError(r);
    });
  }

  Future<void> _loadConsents() async {
    final r = await _api.consents(orgId: _view?.exam.orgId);
    if (!mounted) return;
    setState(() {
      _consentsLoaded = r.ok;
      _consents = r.ok ? asMapList(r.map['items']) : const [];
    });
  }

  // ── settings ──
  Future<String?> _create(ExamDraft d) async {
    var r = await _api.createExam(d.toBody());
    final named = orgFromScopeError(r);
    if (named != null) {
      d.orgId = named;
      r = await _api.createExam(d.toBody());
    }
    if (!r.ok) return authoringError(r);
    if (!mounted) return null;
    setState(() {
      _examId = asInt(r.map['id']);
      _newDraft = null;
      _apply(r.map, resetSettings: true);
    });
    _load();
    appToast(t('أُنشئ الاختبار — أضف الأقسام والأسئلة', 'Exam created — add sections and questions'));
    return null;
  }

  Future<String?> _saveSettings(ExamDraft d) async {
    final v = _view;
    if (v == null) return null;
    final r = await _api.updateExam(v.exam.id!, d.toBody(original: v.exam));
    if (!r.ok) {
      if (r.code == 'stale_version') _load(side: false, resetSettings: true);
      return authoringError(r);
    }
    if (!mounted) return null;
    setState(() => _apply(r.map, resetSettings: true));
    appToast(t('حُفظت الإعدادات', 'Settings saved'));
    return null;
  }

  // ── sections ──
  Future<void> _sectionSheet(SectionDraft s) async {
    final v = _view;
    if (v == null) return;
    final published = !v.exam.isDraft;
    final saved = await showAppSheet<bool>(context, (ctx) => SectionForm(
          section: s,
          published: published,
          onSave: (sd) async {
            final r = sd.id == null
                ? await _api.addSection(v.exam.id!, sd.toBody())
                : await _api.updateSection(v.exam.id!, sd.id!, published ? sd.toPublishedBody() : sd.toBody());
            if (!r.ok) return authoringError(r);
            if (ctx.mounted) Navigator.of(ctx).pop(true);
            return null;
          },
        ));
    if (saved == true) _load(side: false);
  }

  Future<void> _deleteSection(SectionDraft s) async {
    final ok = await appConfirm(context, danger: true, confirmLabel: t('حذف', 'Delete'),
        message: t('حذف القسم «${s.title}» وإزالة أسئلته من الاختبار؟ (تبقى في البنك)', 'Delete the section "${s.title}" and remove its questions from the exam? (They stay in the bank)'));
    if (!ok) return;
    final r = await _api.deleteSection(_view!.exam.id!, s.id!);
    if (!r.ok) return appToast(authoringError(r), error: true);
    _load(side: false);
  }

  Future<void> _moveSection(SectionDraft s, int delta) async {
    final v = _view!;
    final ids = [for (final sv in v.sections) sv.section.id!];
    final order = moveInOrder(ids, s.id!, delta);
    if (order.join(',') == ids.join(',')) return;
    final r = await _api.reorderSections(v.exam.id!, order);
    if (!r.ok) return appToast(authoringError(r), error: true);
    _load(side: false);
  }

  Future<void> _addQuestions(SectionDraft s) async {
    final v = _view!;
    await showAppSheet<void>(context, (_) => QuestionPickerSheet(
          courseId: v.exam.courseId,
          orgId: v.exam.orgId,
          api: _api,
          placedIds: v.placedIds,
          sectionTitle: s.title,
          onPlace: (qid, pts, req) async {
            final r = await _api.place(v.exam.id!, s.id!, questionId: qid, points: pts, required: req);
            return r.ok ? null : authoringError(r);
          },
        ));
    _load(side: false);
  }

  Future<void> _removeQuestion(PlacedQuestion q) async {
    final ok = await appConfirm(context, danger: true, confirmLabel: t('إزالة', 'Remove'),
        message: t('إزالة السؤال من هذا الاختبار؟ يبقى في البنك', 'Remove the question from this exam? It stays in the bank'));
    if (!ok) return;
    final r = await _api.unplace(_view!.exam.id!, q.placementId);
    if (!r.ok) return appToast(authoringError(r), error: true);
    _load(side: false);
  }

  /// Edit = a new version in the bank, written over the bank's CURRENT version (the exam may pin an older one).
  /// A draft exam can switch its placement to the new version at once.
  Future<void> _editQuestion(SectionDraft s, PlacedQuestion q) async {
    final v = _view!;
    final cur = await _api.question(q.questionId);
    if (!mounted) return;
    if (!cur.ok) return appToast(authoringError(cur), error: true);
    final saved = await showQuestionEditor(context, draft: QuestionDraft.fromJson(cur.map), orgId: v.exam.orgId, courseId: v.exam.courseId, api: _api);
    if (saved == null || !mounted) return;
    final newVersion = asInt(saved['version']);
    if (!v.exam.isDraft) {
      appToast(t('حُفظت النسخة $newVersion في البنك؛ يبقى هذا الاختبار على النسخة ${q.pinnedVersion}',
          'Saved as version $newVersion; this exam keeps version ${q.pinnedVersion}'));
      _load(side: false);
      return;
    }
    final use = await appConfirm(context, confirmLabel: t('استخدام النسخة الجديدة', 'Use the new version'),
        message: t('استخدام النسخة $newVersion في هذا الاختبار؟', 'Use version $newVersion in this exam?'));
    if (use) {
      // the placement's points differ from the bank's: that was an override, keep it
      final pts = q.points != asDouble(cur.map['points']) ? q.points : null;
      final position = asInt(q.raw['position']);
      final r1 = await _api.unplace(v.exam.id!, q.placementId);
      final r2 = r1.ok ? await _api.place(v.exam.id!, s.id!, questionId: q.questionId, version: newVersion, points: pts, position: position, required: q.required) : r1;
      if (!r2.ok) appToast(authoringError(r2), error: true);
    }
    _load(side: false);
  }

  // ── proctoring ──
  Future<String?> _saveProctoring(ProctoringDraft p) async {
    final r = await _api.setProctoring(_view!.exam.id!, p.toBody());
    if (!r.ok) return authoringError(r);
    if (!mounted) return null;
    setState(() => _proctor = ProctoringDraft.fromJson(r.map));
    appToast(t('حُفظت سياسة المراقبة', 'Proctoring policy saved'));
    return null;
  }

  Future<void> _addAccommodation() async {
    final saved = await showAppSheet<bool>(context, (ctx) => AccommodationForm(onSave: (a) async {
          final r = await _api.grantAccommodation(_view!.exam.id!, a.toBody());
          if (!r.ok) return authoringError(r);
          if (ctx.mounted) Navigator.of(ctx).pop(true);
          return null;
        }));
    if (saved == true) _loadAccommodations();
  }

  Future<void> _revokeAccommodation(Map<String, dynamic> a) async {
    final ok = await appConfirm(context, danger: true, message: t('إلغاء هذا التيسير؟', 'Revoke this accommodation?'));
    if (!ok) return;
    final r = await _api.revokeAccommodation(asInt(a['id']));
    if (!r.ok) return appToast(authoringError(r), error: true);
    _loadAccommodations();
  }

  // ── lifecycle ──
  Future<void> _action(ExamAction a) async {
    final msg = switch (a) {
      ExamAction.publish => t('نشر الاختبار للطلاب؟ بعد النشر تثبت الأسئلة وبنية الأقسام', 'Publish the exam to students? Questions and section structure become fixed'),
      ExamAction.unpublish => t('إعادة الاختبار إلى مسودة؟', 'Return the exam to draft?'),
      ExamAction.close => t('إغلاق الاختبار؟ لن يبدأ أحد بعدها', 'Close the exam? Nobody can start after this'),
      ExamAction.publishResults => t('نشر النتائج؟ يراها الطلاب حسب سياسة النتائج', 'Publish the results? Students see them per the results policy'),
    };
    final ok = await appConfirm(context, message: msg, confirmLabel: examActionLabel(a), danger: a == ExamAction.close);
    if (!ok || !mounted) return;
    setState(() {
      _busyAction = a;
      _publishError = null;
    });
    final r = await _api.lifecycle(_view!.exam.id!, a);
    if (!mounted) return;
    setState(() {
      _busyAction = null;
      if (!r.ok) {
        final pending = r.detail['pending'];
        _publishError = pending == null ? authoringError(r) : '${authoringError(r)} (${asInt(pending)})';
      }
    });
    if (r.ok) appToast(t('تم', 'Done'));
    _load(side: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nd = _newDraft;
    if (nd != null) {
      return BasePage(
        key: const ValueKey('exam.authoring'),
        appBar: AppBar(title: Text(t('اختبار جديد', 'New exam'))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppHero(title: t('اختبار جديد', 'New exam'), subtitle: t('ابدأ بالإعدادات، ثم الأقسام والأسئلة والمراقبة', 'Start with the settings, then sections, questions and proctoring'),
                icon: Icons.edit_note_rounded),
            ExamSettingsForm(draft: nd, creating: true, onSave: _create),
          ]),
        ),
      );
    }
    final v = _view;
    final w = _working;
    return DefaultTabController(
      length: 4,
      child: BasePage(
        key: const ValueKey('exam.authoring'),
        appBar: AppBar(
          title: Text(v?.exam.title.isNotEmpty == true ? v!.exam.title : t('تحرير الاختبار', 'Edit exam'), maxLines: 1, overflow: TextOverflow.ellipsis),
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: t('الإعدادات', 'Settings')),
            Tab(text: t('الأقسام والأسئلة', 'Sections & questions')),
            Tab(text: t('المراقبة', 'Proctoring')),
            Tab(text: t('النشر', 'Publish')),
          ]),
        ),
        child: v == null || w == null
            ? (_error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: AppEmpty(icon: Icons.error_outline_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load))
                : const AppListSkeleton(items: 4, withAvatar: false))
            : TabBarView(children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: ExamSettingsForm(key: ValueKey('settings.$_settingsGen'), draft: w, onSave: _saveSettings),
                ),
                RefreshIndicator(
                  onRefresh: () => _load(side: false),
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                    ExamSectionsPanel(
                      view: v,
                      onAddSection: () => _sectionSheet(SectionDraft()..title = t('القسم ${v.sections.length + 1}', 'Section ${v.sections.length + 1}')),
                      onEditSection: (s) => _sectionSheet(s.copy()),
                      onDeleteSection: _deleteSection,
                      onMoveSection: _moveSection,
                      onAddQuestions: _addQuestions,
                      onRemoveQuestion: _removeQuestion,
                      onEditQuestion: _editQuestion,
                    ),
                  ]),
                ),
                ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  if (v.proctoring == null)
                    AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: authoringCodeText('policy_not_found'))
                  else
                    ProctoringPolicyForm(key: ValueKey('proctor.${v.exam.version}'), draft: _proctor, consents: _consents, consentsLoaded: _consentsLoaded,
                        onSave: _saveProctoring),
                  AccommodationsPanel(items: _accommodations, error: _accError, onAdd: _addAccommodation, onRevoke: _revokeAccommodation),
                ]),
                ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
                  if (v.exam.id != null) OfflineExamEntryTile(examId: v.exam.id!, title: v.exam.title),
                  ExamPublishPanel(view: v, onAction: _action, busy: _busyAction, error: _publishError),
                ]),
              ]),
      ),
    );
  }
}
