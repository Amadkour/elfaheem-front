// "Generate the questions for me", v2: a five-step wizard (D-194 / D-195) — Sources → Chapters → Questions →
// Language → Generate. The pure parts (body, models, mapping, calls) are in exam_gen_api.dart; this file has the
// presentational steps (plain values, pumped by the layout harness), the wizard that owns the calls, and
// [ExamGenEntry], which falls back to the old sheet on an older server (outline answers a bare 404 / 405).
//
//   Sources    course documents (state, pick which to use) · the course's own materials ("Use" → a document) · upload
//   Chapters   the outline of each chosen document: tick sections, per-document "Exclude pages"
//   Questions  per type: on/off, how many, marks each · the difficulty mix (easy / medium / hard, sums to 100)
//   Language   the questions' language · focus under "Advanced"
//   Generate   a percentage and the phase (JobWatch on job_updated{kind: exam_draft}); the questions land in the builder
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../rag/rag_library.dart';
import 'exam_engine_api.dart' show EngineResult;
import 'exam_gen_api.dart';
import 'exam_generate.dart';
import 'exam_generate_sheet.dart' show ExamGenSheet;
import 'exam_quick.dart' show QuickQuestion;

/// The widest the wizard gets on a desktop (it is a sheet on phones).
const genWizardMaxWidth = 720.0;

enum GenWizardStep { sources, chapters, questions, language, generate }

String genWizardStepTitle(GenWizardStep s) => switch (s) {
      GenWizardStep.sources => t('المصادر', 'Sources'),
      GenWizardStep.chapters => t('الفصول', 'Chapters'),
      GenWizardStep.questions => t('الأسئلة', 'Questions'),
      GenWizardStep.language => t('اللغة', 'Language'),
      GenWizardStep.generate => t('الإنشاء', 'Generate'),
    };

IconData _typeIcon(String type) => switch (type) {
      'true_false' => Icons.rule_rounded,
      'fill_blank' => Icons.space_bar_rounded,
      'short_answer' => Icons.short_text_rounded,
      'matching' => Icons.compare_arrows_rounded,
      'essay' => Icons.notes_rounded,
      _ => Icons.radio_button_checked_rounded,
    };

TextStyle _label(BuildContext context) => appText(13, w: FontWeight.w700, c: context.colors.textDark);

// ── the steps (plain values) ────────────────────────────────────────────────────────────────────────────────────

/// "Step 2 of 5 · Chapters" and a segmented bar.
class GenStepHeader extends StatelessWidget {
  const GenStepHeader({super.key, required this.step});
  final GenWizardStep step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = step.index, n = GenWizardStep.values.length;
    return Semantics(
      container: true,
      label: t('الخطوة ${i + 1} من $n: ${genWizardStepTitle(step)}', 'Step ${i + 1} of $n: ${genWizardStepTitle(step)}'),
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            for (var k = 0; k < n; k++) ...[
              if (k > 0) const SizedBox(width: AppSpace.xxs),
              Expanded(
                child: AnimatedContainer(
                  duration: AppMotion.of(context).base,
                  height: 4,
                  decoration: BoxDecoration(color: k <= i ? c.primary : c.textLight.withValues(alpha: .25), borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ],
          ]),
          const SizedBox(height: AppSpace.xs),
          Text('${t('الخطوة ${i + 1} من $n', 'Step ${i + 1} of $n')} · ${genWizardStepTitle(step)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
        ]),
      ),
    );
  }
}

/// One tick row: a checkbox, a title, an optional second line and a trailing widget (≥ 48 high).
class GenPickRow extends StatelessWidget {
  const GenPickRow({super.key, required this.selected, required this.onChanged, required this.title, this.subtitle, this.trailing, this.indent = 0, this.icon});
  final bool selected;
  final ValueChanged<bool>? onChanged;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double indent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      checked: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.chip),
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: indent),
            child: Row(children: [
              ExcludeSemantics(child: Checkbox(value: selected, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false))),
              if (icon != null) ...[Icon(icon, size: 18, color: c.textMedium), const SizedBox(width: AppSpace.xs)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: AppSpace.xs), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A course document in the Sources step.
class GenSourceRow {
  const GenSourceRow({required this.id, required this.title, required this.state, required this.selected});
  final int id;
  final String title;

  /// ready · processing · failed
  final String state;
  final bool selected;
}

String _stateText(String s) => switch (s) {
      'ready' => t('جاهز', 'Ready'),
      'processing' => t('قيد القراءة…', 'Being read…'),
      _ => t('تعذرت القراءة', 'Could not be read'),
    };

String _sizeText(int bytes) {
  if (bytes <= 0) return '';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// Step 1: the course documents (tick which to use), the course's own materials, and an upload.
class GenSourcesStep extends StatelessWidget {
  const GenSourcesStep({
    super.key,
    required this.loading,
    required this.documents,
    required this.materials,
    required this.onToggle,
    required this.onUseMaterial,
    required this.onUpload,
    this.busyMaterials = const {},
    this.picked,
    this.warning,
  });
  final bool loading;
  final List<GenSourceRow> documents;
  final List<GenMaterial> materials;
  final Set<int> busyMaterials;
  final ValueChanged<int> onToggle;
  final ValueChanged<GenMaterial> onUseMaterial;
  final VoidCallback onUpload;
  final String? picked;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 3; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpace.xs), child: AppSkeletonBox(height: 48)),
      ]);
    }
    final free = materials.where((m) => !m.used).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('مستندات المقرر', 'Course documents'), style: _label(context)),
      const SizedBox(height: AppSpace.xxs),
      if (documents.isEmpty)
        AppBanner(
            icon: Icons.upload_file_rounded,
            color: c.primary,
            text: t('لا يوجد مستند للمقرر بعد. استخدم أحد ملفات المقرر أو ارفع ملفاً، ونكتب الأسئلة منه.',
                'The course has no document yet. Use one of its files or upload one, and we write the questions from it.'))
      else
        for (final d in documents)
          GenPickRow(
            icon: Icons.description_outlined,
            selected: d.selected,
            onChanged: d.state == 'ready' ? (_) => onToggle(d.id) : null,
            title: d.title,
            subtitle: _stateText(d.state),
          ),
      if (warning != null) ...[const SizedBox(height: AppSpace.xs), AppBanner(icon: Icons.document_scanner_outlined, color: c.warning, text: warning!)],
      if (free.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Text(t('ملفات المقرر', 'Course materials'), style: _label(context)),
        const SizedBox(height: AppSpace.xxs),
        for (final m in free)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(children: [
              Icon(Icons.folder_open_rounded, size: 18, color: c.textMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(m.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w600, c: c.textDark)),
                  Text([if (m.sessionTitle.isNotEmpty) m.sessionTitle, _sizeText(m.size)].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
                ]),
              ),
              const SizedBox(width: AppSpace.xs),
              if (busyMaterials.contains(m.id))
                Text(t('نقرأه…', 'Reading…'), style: appText(12.5, c: c.textMedium))
              else
                TextButton(onPressed: () => onUseMaterial(m), child: Text(t('استخدم', 'Use'))),
            ]),
          ),
      ],
      const SizedBox(height: AppSpace.sm),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: onUpload, icon: const Icon(Icons.attach_file_rounded, size: 18), label: Text(t('ارفع ملفاً جديداً', 'Upload a new file'))),
      ),
      Text(ragFormatAdvice(picked), style: appText(12, c: c.textLight)),
    ]);
  }
}

/// Step 2: the outline of each chosen document. [excludes] holds one controller per document id.
class GenChaptersStep extends StatelessWidget {
  const GenChaptersStep({
    super.key,
    required this.loading,
    required this.outline,
    required this.selected,
    required this.excludes,
    required this.onToggle,
    required this.onAll,
    required this.onNone,
    this.onExcludeChanged,
  });
  final bool loading;
  final GenOutline outline;
  final Set<int> selected;
  final Map<int, TextEditingController> excludes;
  final ValueChanged<int> onToggle;
  final VoidCallback onAll, onNone;
  final VoidCallback? onExcludeChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < 5; i++) const Padding(padding: EdgeInsets.only(bottom: AppSpace.xs), child: AppSkeletonBox(height: 40)),
      ]);
    }
    final all = outline.allSections;
    if (all.isEmpty) {
      return AppBanner(
          icon: Icons.menu_book_outlined,
          color: c.warning,
          text: t('لم نجد فصولاً في المستندات المختارة بعد. ارجع واختر مستنداً جاهزاً.', 'No chapters were found in the chosen documents yet. Go back and pick a ready document.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('${selected.length} من ${all.length} محدد', '${selected.length} of ${all.length} selected'), style: appText(12.5, c: c.textMedium))),
        TextButton(onPressed: onAll, child: Text(t('الكل', 'All'))),
        TextButton(onPressed: onNone, child: Text(t('لا شيء', 'None'))),
      ]),
      for (final d in outline.documents) ...[
        if (d.sections.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxs),
            child: Row(children: [
              Icon(Icons.description_outlined, size: 18, color: c.primary),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text(d.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w800, c: c.textDark))),
            ]),
          ),
          for (final s in d.sections)
            GenPickRow(
              selected: selected.contains(s.id),
              onChanged: (_) => onToggle(s.id),
              indent: ((s.level - 1).clamp(0, 3)) * 12.0,
              title: s.title,
              subtitle: [s.pagesLabel, if (s.words > 0) t('${s.words} كلمة', '${s.words} words')].where((e) => e.isNotEmpty).join(' · '),
            ),
          if (excludes[d.id] != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs),
              child: AppField(
                controller: excludes[d.id]!,
                label: t('استبعد صفحات', 'Exclude pages'),
                hint: t('مثال: 1-3، 7، 10-12', 'e.g. 1-3, 7, 10-12'),
                onChanged: (_) => onExcludeChanged?.call(),
              ),
            ),
          if (excludes[d.id] != null && parseExcludeRanges(excludes[d.id]!.text).bad)
            Text(genV2CodeText('bad_pages', ''), style: appText(12, c: c.danger)),
        ],
      ],
    ]);
  }
}

/// A small − value + control; [label] is read out for the buttons.
class GenStepper extends StatelessWidget {
  const GenStepper({super.key, required this.label, required this.value, this.onMinus, this.onPlus, this.width = 52});
  final String label, value;
  final VoidCallback? onMinus, onPlus;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(tooltip: '${t('أقل', 'Fewer')} · $label', onPressed: onMinus, icon: const Icon(Icons.remove_rounded, size: 18)),
      Semantics(label: label, value: value, child: SizedBox(width: width, child: Text(value, textAlign: TextAlign.center, maxLines: 1, style: appText(16, w: FontWeight.w800, c: c.textDark)))),
      IconButton.outlined(tooltip: '${t('أكثر', 'More')} · $label', onPressed: onPlus, icon: const Icon(Icons.add_rounded, size: 18)),
    ]);
  }
}

/// Step 3: one row per type (switch, how many, marks each) and the difficulty mix. [rows] are edited by the callbacks.
class GenQuestionsStep extends StatelessWidget {
  const GenQuestionsStep({
    super.key,
    required this.rows,
    required this.mix,
    required this.onToggle,
    required this.onCount,
    required this.onPoints,
    required this.onMix,
  });
  final List<GenTypeRow> rows;
  final GenMix mix;
  final void Function(int index, bool on) onToggle;
  final void Function(int index, int count) onCount;
  final void Function(int index, double points) onPoints;
  final ValueChanged<GenMix> onMix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = genTotalQuestions(rows);
    final tooMany = total > genV2MaxTotal;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < rows.length; i++) _typeRow(context, i, rows[i]),
      const SizedBox(height: AppSpace.xs),
      Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(color: (tooMany ? c.danger : c.primary).withValues(alpha: .08), borderRadius: BorderRadius.circular(AppRadius.chip)),
        child: Text(
          tooMany
              ? genV2CodeText('too_many_questions', '')
              : t('المجموع: $total سؤالاً · ${genNum(genTotalMarks(rows))} درجة', 'Total: $total questions · ${genNum(genTotalMarks(rows))} marks'),
          style: appText(13.5, w: FontWeight.w700, c: tooMany ? c.danger : c.textDark),
        ),
      ),
      const SizedBox(height: AppSpace.md),
      Text(t('مزيج الصعوبة', 'Difficulty mix'), style: _label(context)),
      const SizedBox(height: AppSpace.xs),
      GenMixEditor(mix: mix, onChanged: onMix),
    ]);
  }

  Widget _typeRow(BuildContext context, int i, GenTypeRow r) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(_typeIcon(r.type), size: 20, color: r.enabled ? c.primary : c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(genV2TypeLabel(r.type), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark))),
            AppSwitch(value: r.enabled, semanticLabel: genV2TypeLabel(r.type), onChanged: (v) => onToggle(i, v)),
          ]),
          if (r.enabled)
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t('العدد', 'Count'), style: appText(12.5, c: c.textMedium)),
                const SizedBox(width: AppSpace.xxs),
                GenStepper(
                    label: t('عدد ${genV2TypeLabel(r.type)}', 'Number of ${genV2TypeLabel(r.type)}'),
                    value: '${r.count}',
                    onMinus: r.count > 1 ? () => onCount(i, r.count - 1) : null,
                    onPlus: r.count < genV2MaxPerType ? () => onCount(i, r.count + 1) : null),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t('الدرجة', 'Marks'), style: appText(12.5, c: c.textMedium)),
                const SizedBox(width: AppSpace.xxs),
                GenStepper(
                    label: t('درجة ${genV2TypeLabel(r.type)}', 'Marks of ${genV2TypeLabel(r.type)}'),
                    value: genNum(r.points),
                    width: 56,
                    onMinus: r.points - 0.5 >= genV2MinPoints ? () => onPoints(i, r.points - 0.5) : null,
                    onPlus: r.points + 0.5 <= genV2MaxPoints ? () => onPoints(i, r.points + 0.5) : null),
              ]),
            ]),
        ]),
      ),
    );
  }
}

/// The easy / medium / hard percentages: a stacked bar, ± 5 per level (the others follow, the sum stays 100) and the
/// presets.
class GenMixEditor extends StatelessWidget {
  const GenMixEditor({super.key, required this.mix, required this.onChanged});
  final GenMix mix;
  final ValueChanged<GenMix> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color colorOf(GenLevel l) => switch (l) { GenLevel.easy => c.success, GenLevel.medium => c.warning, GenLevel.hard => c.danger };
    final presetNames = [t('أسهل', 'Easier'), t('متوازن', 'Balanced'), t('أصعب', 'Harder')];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (var i = 0; i < GenMix.presets.length; i++) AppChoiceChip(label: presetNames[i], selected: mix == GenMix.presets[i], onTap: () => onChanged(GenMix.presets[i])),
      ]),
      const SizedBox(height: AppSpace.sm),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 8,
          child: Row(children: [
            for (final l in GenLevel.values)
              if (mix.of(l) > 0) Expanded(flex: mix.of(l), child: ColoredBox(color: colorOf(l))),
          ]),
        ),
      ),
      for (final l in GenLevel.values)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(l), shape: BoxShape.circle)),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(genLevelLabel(l), style: appText(13.5, w: FontWeight.w600, c: c.textDark))),
            GenStepper(
                label: genLevelLabel(l),
                value: '${mix.of(l)}%',
                width: 56,
                onMinus: mix.of(l) > 0 ? () => onChanged(mix.set(l, mix.of(l) - 5)) : null,
                onPlus: mix.of(l) < 100 ? () => onChanged(mix.set(l, mix.of(l) + 5)) : null),
          ]),
        ),
    ]);
  }
}

/// Step 4: the questions' language, and under "Advanced" the focus text.
class GenLanguageStep extends StatelessWidget {
  const GenLanguageStep({super.key, required this.lang, required this.onLang, required this.focus, required this.advanced, required this.onAdvanced});
  final GenLang lang;
  final ValueChanged<GenLang> onLang;
  final TextEditingController focus;
  final bool advanced;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('لغة الأسئلة', 'Question language'), style: _label(context)),
      const SizedBox(height: AppSpace.xs),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final l in GenLang.values) AppChoiceChip(label: genLangLabel(l), selected: lang == l, onTap: () => onLang(l)),
      ]),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
            onPressed: onAdvanced,
            icon: Icon(advanced ? Icons.expand_less_rounded : Icons.tune_rounded, size: 18),
            label: Text(t('خيارات متقدمة', 'Advanced'))),
      ),
      if (advanced)
        AppField(controller: focus, label: t('ركّز على (اختياري)', 'Focus on (optional)'), hint: t('مثال: التعاريف فقط، أو موضوع التمثيل الضوئي', 'e.g. definitions only, or photosynthesis')),
    ]);
  }
}

/// Step 5: the percentage and the phase while the questions are written.
class GenProgressView extends StatelessWidget {
  const GenProgressView({super.key, required this.progress, this.warnings = const []});
  final GenProgress progress;
  final List<GenWarning> warnings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('${progress.percent}%', textAlign: TextAlign.center, style: appText(34, w: FontWeight.w800, c: c.primary)),
      const SizedBox(height: AppSpace.xs),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: progress.total > 0 || progress.percent > 0 ? progress.percent / 100 : null, minHeight: 6),
      ),
      const SizedBox(height: AppSpace.sm),
      Semantics(liveRegion: true, child: Text(genPhaseLabel(progress.phase), textAlign: TextAlign.center, style: appText(13.5, c: c.textMedium))),
      if (progress.total > 0)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(t('${progress.done} من ${progress.total} سؤالاً', '${progress.done} of ${progress.total} questions'), textAlign: TextAlign.center, style: appText(12, c: c.textLight)),
        ),
      for (final w in warnings.take(3)) Padding(padding: const EdgeInsets.only(top: AppSpace.xs), child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: w.message)),
    ]);
  }
}

/// Back / Next (or Generate). [onBack] null hides Back.
class GenNavBar extends StatelessWidget {
  const GenNavBar({super.key, required this.primaryLabel, required this.onPrimary, this.onBack, this.primaryIcon});
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final IconData? primaryIcon;

  @override
  Widget build(BuildContext context) {
    return Wrap(alignment: WrapAlignment.end, spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (onBack != null) TextButton(onPressed: onBack, child: Text(t('رجوع', 'Back'))),
      AppPrimaryButton(label: primaryLabel, icon: primaryIcon, onPressed: onPrimary),
    ]);
  }
}

// ── the wizard ──────────────────────────────────────────────────────────────────────────────────────────────────

/// The entry: asks the outline route whether the server has generation v2; an older server gets the old sheet.
class ExamGenEntry extends StatefulWidget {
  const ExamGenEntry({super.key, required this.courseId, this.orgId, this.api, this.library, this.pickFile, this.legacyApi});
  final int courseId;
  final int? orgId;
  final ExamGenV2Api? api;
  final RagLibraryApi? library;
  final ExamGenApi? legacyApi;
  final Future<(String, Uint8List)?> Function()? pickFile;

  @override
  State<ExamGenEntry> createState() => _ExamGenEntryState();
}

class _ExamGenEntryState extends State<ExamGenEntry> {
  late final ExamGenV2Api _api = widget.api ?? ExamGenV2Api();
  EngineResult? _probe;

  @override
  void initState() {
    super.initState();
    _api.outline(widget.courseId).then((r) {
      if (mounted) setState(() => _probe = r);
    });
  }

  void _legacy() => setState(() => _probe = EngineResult.fail(404, null, 'Not Found'));

  @override
  Widget build(BuildContext context) {
    final p = _probe;
    if (p == null) {
      return AppSheetContent(title: t('أسئلة من مستندات المقرر', 'Questions from the course documents'), children: const [
        AppSkeletonBox(height: 18),
        SizedBox(height: AppSpace.sm),
        AppSkeletonBox(height: 48),
      ]);
    }
    if (!genUseWizard(p)) {
      return ExamGenSheet(courseId: widget.courseId, orgId: widget.orgId, api: widget.legacyApi, library: widget.library, pickFile: widget.pickFile);
    }
    return ExamGenWizard(
        courseId: widget.courseId, orgId: widget.orgId, api: _api, library: widget.library, pickFile: widget.pickFile, onOlderServer: _legacy);
  }
}

class ExamGenWizard extends StatefulWidget {
  const ExamGenWizard({super.key, required this.courseId, this.orgId, this.api, this.library, this.pickFile, this.onOlderServer, this.pollEvery});
  final int courseId;
  final int? orgId;
  final ExamGenV2Api? api;
  final RagLibraryApi? library;
  final Future<(String, Uint8List)?> Function()? pickFile;

  /// The server turned out to lack generation v2 (a bare 404 / 405): the entry shows the old sheet.
  final VoidCallback? onOlderServer;

  /// Test seam: how often the job is fetched.
  final Duration? pollEvery;

  @override
  State<ExamGenWizard> createState() => _ExamGenWizardState();
}

class _ExamGenWizardState extends State<ExamGenWizard> {
  late final ExamGenV2Api _api = widget.api ?? ExamGenV2Api();
  late final RagLibraryApi _lib = widget.library ?? RagLibraryApi();

  GenWizardStep _step = GenWizardStep.sources;
  bool _loading = true, _outlineLoading = false;
  List<RagDocument> _docs = const [];
  List<GenMaterial> _materials = const [];
  final Set<int> _useDocs = {};
  final Set<int> _busyMaterials = {};
  GenOutline _outline = GenOutline.empty;
  final Set<int> _sections = {};
  final Map<int, TextEditingController> _excludes = {};
  final List<GenTypeRow> _rows = defaultGenRows();
  GenMix _mix = GenMix.balanced;
  GenLang _lang = GenLang.auto;
  final _focus = TextEditingController();
  bool _advanced = false, _seeded = false;
  GenProgress _progress = const GenProgress();
  List<GenWarning> _warnings = const [];
  String? _picked, _err;
  EventOrPoll? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.dispose();
    _focus.dispose();
    for (final c in _excludes.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<RagDocument> get _mine => _docs.where((d) => d.scope == 'course' && d.courseId == widget.courseId && !d.archived).toList();

  Future<void> _load() async {
    final r = await _lib.list(courseId: widget.courseId);
    final m = await _api.materials(widget.courseId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _err = r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update') : examGenCodeText(r.code, r.message);
      } else {
        _docs = RagLibrary.fromJson(asMap(r.map)).items;
      }
      if (m.ok) _materials = genMaterialsOf(m.map);
      final ready = _mine.where((d) => d.status == 'ready').map((d) => d.id);
      if (!_seeded) {
        _useDocs.addAll(ready);
        _seeded = ready.isNotEmpty;
      } else {
        // a document that just became ready is ticked for the person who waited for it
        _useDocs.addAll(ready.where((id) => _justReady.contains(id)));
      }
      _justReady
        ..clear()
        ..addAll(_mine.where((d) => d.busy).map((d) => d.id));
    });
    final busy = _mine.any((d) => d.busy) || _busyMaterials.isNotEmpty;
    if (busy) {
      (_poll ??= EventOrPoll(
              match: (e) => e.kind == 'rag_ingest' || e.kind == 'ingest',
              every: const Duration(seconds: 4),
              fallbackEvery: const Duration(seconds: 16),
              poll: _load))
          .start();
    } else {
      _poll?.stop();
    }
    _busyMaterials.removeWhere((id) => _materials.any((x) => x.id == id && x.used));
  }

  final Set<int> _justReady = {};

  Future<(String, Uint8List)?> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ragUploadExtensions);
    if (f == null) return null;
    return (f.name, await f.readAsBytes());
  }

  Future<void> _upload() async {
    final got = await (widget.pickFile ?? _pick)();
    if (got == null || !mounted) return;
    final d = RagUploadDraft(title: ragTitleOf(got.$1), scope: 'course', fileName: got.$1, fileBytes: got.$2, onConflict: RagConflictMode.keep);
    final bad = d.validate(fixedCourseId: widget.courseId);
    if (bad != null) return setState(() => _err = examGenCodeText(bad, bad));
    setState(() {
      _picked = got.$1;
      _err = null;
    });
    final r = await _lib.upload(d, courseId: widget.courseId);
    if (!mounted) return;
    if (!r.ok) return setState(() => _err = ragResultText(r));
    _load();
  }

  Future<void> _useMaterial(GenMaterial m) async {
    setState(() {
      _busyMaterials.add(m.id);
      _err = null;
    });
    final r = await _api.fromMaterial(widget.courseId, m.id, orgId: widget.orgId);
    if (!mounted) return;
    if (!r.ok) {
      return setState(() {
        _busyMaterials.remove(m.id);
        _err = r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update') : genV2CodeText(r.code, examGenCodeText(r.code, r.message));
      });
    }
    _load();
  }

  Future<void> _toChapters() async {
    setState(() {
      _err = null;
      _outlineLoading = true;
      _step = GenWizardStep.chapters;
    });
    final r = await _api.outline(widget.courseId, documentIds: _useDocs.toList());
    if (!mounted) return;
    if (r.unavailable) return widget.onOlderServer?.call();
    setState(() {
      _outlineLoading = false;
      if (!r.ok) {
        _err = genV2CodeText(r.code, examGenCodeText(r.code, r.message));
        _outline = GenOutline.empty;
        return;
      }
      final before = _outline.allSections.map((s) => s.id).toSet();
      _outline = GenOutline.fromJson(r.map);
      // new sections are ticked; what the person unticked before stays unticked
      final ids = _outline.allSections.map((s) => s.id).toSet();
      _sections
        ..removeWhere((id) => !ids.contains(id))
        ..addAll(ids.where((id) => !before.contains(id)));
      for (final d in _outline.documents) {
        _excludes.putIfAbsent(d.id, TextEditingController.new);
      }
    });
  }

  Map<int, List<List<int>>> get _excludeRanges => {
        for (final e in _excludes.entries)
          if (_outline.documents.any((d) => d.id == e.key)) e.key: parseExcludeRanges(e.value.text).ranges,
      };

  String? get _problem => genV2Problem(
      sectionIds: _sections.toList(), rows: _rows, mix: _mix, excludeTexts: [for (final e in _excludes.entries) if (_outline.documents.any((d) => d.id == e.key)) e.value.text]);

  void _next() {
    switch (_step) {
      case GenWizardStep.sources:
        return unawaited(_toChapters());
      case GenWizardStep.chapters:
        if (_sections.isEmpty || _excludes.values.any((c) => parseExcludeRanges(c.text).bad)) return;
        return setState(() {
          _err = null;
          _step = GenWizardStep.questions;
        });
      case GenWizardStep.questions:
        if (genTotalQuestions(_rows) < 1 || genTotalQuestions(_rows) > genV2MaxTotal) return;
        return setState(() {
          _err = null;
          _step = GenWizardStep.language;
        });
      case GenWizardStep.language:
        return unawaited(_generate());
      case GenWizardStep.generate:
        return;
    }
  }

  void _back() => setState(() {
        _err = null;
        _step = GenWizardStep.values[(_step.index - 1).clamp(0, GenWizardStep.values.length - 1)];
      });

  Future<void> _generate() async {
    final bad = _problem;
    if (bad != null) return setState(() => _err = genV2CodeText(bad, bad));
    setState(() {
      _step = GenWizardStep.generate;
      _err = null;
      _progress = const GenProgress();
      _warnings = const [];
    });
    final body = examGenV2Body(
        courseId: widget.courseId,
        orgId: widget.orgId,
        documentIds: _outline.documents.map((d) => d.id).toList(),
        sectionIds: _sections.toList(),
        excludePages: _excludeRanges,
        rows: _rows,
        mix: _mix,
        lang: _lang.name,
        focus: _focus.text);
    final r = await _api.create(body);
    if (!mounted) return;
    if (r.unavailable) return widget.onOlderServer?.call();
    if (!r.ok) {
      setState(() {
        _step = GenWizardStep.language;
        _err = genV2CodeText(r.code, examGenCodeText(r.code, r.message));
      });
      if (r.code == 'no_course_documents') _load();
      return;
    }
    final id = asInt(r.map['id']);
    final done = await _api.waitFor(id,
        every: widget.pollEvery ?? const Duration(milliseconds: 1500),
        onJob: (j) {
          if (mounted) {
            setState(() {
              _progress = j.progress;
              _warnings = j.warnings;
            });
          }
        });
    if (!mounted) return;
    final job = done.ok ? GenJob.fromJson(asMap(done.map)) : null;
    final items = job == null ? const <(int, QuickQuestion)>[] : genItemsOf(job.questions);
    if (job == null || !job.done || items.isEmpty) {
      return setState(() {
        _step = GenWizardStep.language;
        _err = job == null
            ? examGenCodeText(done.code, done.message)
            : !job.done
                ? t('ما زالت الأسئلة قيد الكتابة — حاول بعد قليل', 'The questions are still being written — try again shortly')
                : examGenCodeText(job.error ?? 'no_questions', t('تعذر إنشاء الأسئلة', 'Could not generate the questions'));
      });
    }
    final left = job.questions.length - items.length;
    appToast(left > 0
        ? t('${items.length} سؤالاً جاهزاً، وتعذّر كتابة $left', '${items.length} questions ready, $left could not be written')
        : t('${items.length} سؤالاً جاهزاً', '${items.length} questions ready'));
    Navigator.pop(context, ExamGenResult(job.id, items));
  }

  bool get _canNext => switch (_step) {
        GenWizardStep.sources => _useDocs.isNotEmpty && !_loading,
        GenWizardStep.chapters => !_outlineLoading && _sections.isNotEmpty && !_excludes.values.any((c) => parseExcludeRanges(c.text).bad),
        GenWizardStep.questions => genTotalQuestions(_rows) >= 1 && genTotalQuestions(_rows) <= genV2MaxTotal,
        GenWizardStep.language => true,
        GenWizardStep.generate => false,
      };

  String get _primaryLabel => switch (_step) {
        GenWizardStep.language => t('أنشئ ${genTotalQuestions(_rows)} سؤالاً', 'Generate ${genTotalQuestions(_rows)} questions'),
        _ => t('التالي', 'Next'),
      };

  Widget _body() {
    switch (_step) {
      case GenWizardStep.sources:
        final mine = _mine;
        return GenSourcesStep(
          loading: _loading,
          documents: [
            for (final d in mine)
              GenSourceRow(id: d.id, title: d.displayTitle, state: d.status == 'ready' ? 'ready' : (d.busy ? 'processing' : 'failed'), selected: _useDocs.contains(d.id))
          ],
          materials: _materials,
          busyMaterials: _busyMaterials,
          picked: _picked,
          warning: mine.map(ragOcrWarning).whereType<String>().firstOrNull,
          onToggle: (id) => setState(() => _useDocs.contains(id) ? _useDocs.remove(id) : _useDocs.add(id)),
          onUseMaterial: _useMaterial,
          onUpload: _upload,
        );
      case GenWizardStep.chapters:
        return GenChaptersStep(
          loading: _outlineLoading,
          outline: _outline,
          selected: _sections,
          excludes: _excludes,
          onToggle: (id) => setState(() => _sections.contains(id) ? _sections.remove(id) : _sections.add(id)),
          onAll: () => setState(() => _sections.addAll(_outline.allSections.map((s) => s.id))),
          onNone: () => setState(_sections.clear),
          onExcludeChanged: () => setState(() {}),
        );
      case GenWizardStep.questions:
        return GenQuestionsStep(
          rows: _rows,
          mix: _mix,
          onToggle: (i, on) => setState(() => _rows[i].enabled = on),
          onCount: (i, v) => setState(() => _rows[i].count = v.clamp(1, genV2MaxPerType)),
          onPoints: (i, v) => setState(() => _rows[i].points = double.parse(v.clamp(genV2MinPoints, genV2MaxPoints).toStringAsFixed(2))),
          onMix: (m) => setState(() => _mix = m),
        );
      case GenWizardStep.language:
        return GenLanguageStep(lang: _lang, onLang: (v) => setState(() => _lang = v), focus: _focus, advanced: _advanced, onAdvanced: () => setState(() => _advanced = !_advanced));
      case GenWizardStep.generate:
        return GenProgressView(progress: _progress, warnings: _warnings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final generating = _step == GenWizardStep.generate;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: genWizardMaxWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSheetHeader(t('أسئلة من مستندات المقرر', 'Questions from the course documents')),
            GenStepHeader(step: _step),
            const SizedBox(height: AppSpace.sm),
            _body(),
            if (_err != null) Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err!)),
            if (!generating) ...[
              const SizedBox(height: AppSpace.md),
              GenNavBar(
                primaryLabel: _primaryLabel,
                primaryIcon: _step == GenWizardStep.language ? Icons.auto_awesome_rounded : null,
                onPrimary: _canNext ? _next : null,
                onBack: _step == GenWizardStep.sources ? null : _back,
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
