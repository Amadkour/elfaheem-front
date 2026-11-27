// The "generate this exam for me" sheet (logic in exam_generate.dart). At most: give the course file (only when the
// course has none yet, with one line on the best format) → question types → how many → difficulty → Generate; under
// "Advanced": a focus ("chapter 3 only") and the questions' language (D-012). The questions come back to the quick
// builder as an editable draft, with one line on what the planner and the reviewer did. [ExamGenForm] and
// [QuickGenerateCard] are presentational (tested under the layout harness); the sheet owns the calls and the polling.
// Track F: [GenReviewBar] (Accept / Edit / Reject on a generated question in the builder) and [GenRejectSheet] (why).
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/exams/exam_words.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, t;
import 'package:flutter_education_app/features/rag/rag_library.dart';
import 'package:flutter_education_app/features/rag/rag_learning.dart' show examReasonLabel, examReasons;
import 'package:flutter_education_app/features/exams/exam_gen_api.dart' show GenQMeta;
import 'package:flutter_education_app/features/exams/exam_generate.dart';
import 'package:flutter_education_app/features/exams/exam_generate_wizard.dart' show ExamGenEntry;
import 'package:flutter_education_app/features/exams/exam_quick.dart';
import 'package:flutter_education_app/config/app_config.dart';

/// Opens the generator; the draft's questions to add (with their indexes in the draft, for the Track F review), or
/// null when the teacher left without generating. The five-step wizard (exam_generate_wizard.dart, generation v2);
/// on an older server [ExamGenEntry] shows the sheet below, unchanged.
/// [avoidPrompts]: the questions already in the exam (D-301: never written again). A job still being written for this
/// course (the teacher left the sheet) opens on its progress.
Future<ExamGenResult?> openExamGenerator(BuildContext context, {required int courseId, int? orgId, List<String> avoidPrompts = const []}) =>
    showAppSheet<ExamGenResult>(context, (_) => ExamGenEntry(courseId: courseId, orgId: orgId, avoidPrompts: avoidPrompts));

class ExamGenSheet extends StatefulWidget {
  const ExamGenSheet({super.key, required this.courseId, this.orgId, this.api, this.library, this.pickFile});
  final int courseId;
  final int? orgId;
  final ExamGenApi? api;
  final RagLibraryApi? library;

  /// test hook / platform seam: (name, bytes) or null
  final Future<(String, Uint8List)?> Function()? pickFile;

  @override
  State<ExamGenSheet> createState() => _ExamGenSheetState();
}

class _ExamGenSheetState extends State<ExamGenSheet> {
  late final ExamGenApi _api = widget.api ?? ExamGenApi();
  late final RagLibraryApi _lib = widget.library ?? RagLibraryApi();
  ExamGenStep _step = ExamGenStep.loading;
  List<RagDocument> _docs = const [];
  GenTypes _types = GenTypes.mixed;
  int _count = genDefaultCount;
  GenDifficulty _difficulty = GenDifficulty.mixed;
  GenLang _lang = GenLang.auto;
  final _focus = TextEditingController();
  bool _advanced = false;
  String? _picked;
  String? _err;
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
    super.dispose();
  }

  List<RagDocument> get _mine => _docs.where((d) => d.scope == 'course' && d.courseId == widget.courseId && !d.archived).toList();

  Future<void> _load() async {
    final r = await _lib.list(courseId: widget.courseId);
    if (!mounted) return;
    setState(() {
      if (!r.ok) {
        _step = ExamGenStep.needDocument;
        _err = r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update') : examGenCodeText(r.code, r.message);
        return;
      }
      _docs = RagLibrary.fromJson(asMap(r.map)).items;
      if (_step != ExamGenStep.generating) _step = examGenStepOf(_docs, widget.courseId);
    });
    // the uploaded file being read: `job_updated{kind: rag_ingest}` reloads at once; the poll (4 s, 16 s while the
    // live stream is connected) is the fallback
    if (_step == ExamGenStep.processing) {
      (_poll ??= EventOrPoll(
              match: (e) => e.kind == 'rag_ingest' || e.kind == 'ingest',
              every: const Duration(seconds: 4),
              fallbackEvery: const Duration(seconds: 16),
              poll: _load))
          .start();
    } else {
      _poll?.stop();
    }
  }

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
      _step = ExamGenStep.processing;
    });
    final r = await _lib.upload(d, courseId: widget.courseId);
    if (!mounted) return;
    if (!r.ok) {
      return setState(() {
        _err = ragResultText(r);
        _step = _mine.any((x) => x.status == 'ready') ? ExamGenStep.ready : ExamGenStep.needDocument;
      });
    }
    _load();
  }

  Future<void> _generate() async {
    setState(() {
      _step = ExamGenStep.generating;
      _err = null;
    });
    final r = await _api.create(courseId: widget.courseId, orgId: widget.orgId, types: _types, count: _count, difficulty: _difficulty, focus: _focus.text, lang: _lang);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _step = ExamGenStep.ready;
        _err = r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This feature needs a server update') : examGenCodeText(r.code, r.message);
      });
      if (r.code == 'no_course_documents') _load();
      return;
    }
    final done = await _api.waitFor(asInt(asMap(r.map)['id']));
    if (!mounted) return;
    final draft = done.ok ? ExamGenDraft.fromJson(asMap(done.map)) : null;
    final items = draft == null ? const <(int, QuickQuestion)>[] : genItemsOf(draft.questions);
    final questions = [for (final (_, q) in items) q];
    if (draft == null || !draft.done || questions.isEmpty) {
      return setState(() {
        _step = ExamGenStep.ready;
        _err = draft == null
            ? examGenCodeText(done.code, done.message)
            : !draft.done
                ? t('ما زالت الأسئلة قيد الكتابة — حاول بعد قليل', 'The questions are still being written — try again shortly')
                : examGenCodeText(draft.error ?? 'no_questions', t('تعذر إنشاء الأسئلة', 'Could not generate the questions'));
      });
    }
    final summary = examGenSummary(draft);
    if (summary != null) appToast(summary);
    Navigator.pop(context, ExamGenResult(draft.id, items));
  }

  @override
  Widget build(BuildContext context) {
    final mine = _mine;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('أسئلة من مستندات المقرر', 'Questions from the course documents')),
        ExamGenForm(
          step: _step,
          documents: [for (final d in mine.where((d) => d.status == 'ready')) d.displayTitle],
          warning: mine.map(ragOcrWarning).whereType<String>().firstOrNull,
          picked: _picked,
          types: _types,
          count: _count,
          difficulty: _difficulty,
          lang: _lang,
          focus: _focus,
          advanced: _advanced,
          error: _err,
          onUpload: _upload,
          onTypes: (v) => setState(() => _types = v),
          onCount: (v) => setState(() => _count = v.clamp(1, genMaxCount)),
          onDifficulty: (v) => setState(() => _difficulty = v),
          onLang: (v) => setState(() => _lang = v),
          onAdvanced: () => setState(() => _advanced = !_advanced),
          onGenerate: _generate,
        ),
      ]),
    );
  }
}

/// The sheet's content for one [step] (plain values).
class ExamGenForm extends StatelessWidget {
  const ExamGenForm({
    super.key,
    required this.step,
    required this.types,
    required this.count,
    required this.onUpload,
    required this.onTypes,
    required this.onCount,
    required this.onGenerate,
    this.documents = const [],
    this.warning,
    this.picked,
    this.error,
    this.difficulty = GenDifficulty.mixed,
    this.lang = GenLang.auto,
    this.focus,
    this.advanced = false,
    this.onDifficulty,
    this.onLang,
    this.onAdvanced,
  });
  final ExamGenStep step;
  final List<String> documents;
  final String? warning;
  final String? picked;
  final GenTypes types;
  final int count;
  final String? error;
  final VoidCallback onUpload;
  final ValueChanged<GenTypes> onTypes;
  final ValueChanged<int> onCount;
  final VoidCallback onGenerate;

  /// D-012: difficulty, and under "Advanced" the focus text and the questions' language.
  final GenDifficulty difficulty;
  final GenLang lang;
  final TextEditingController? focus;
  final bool advanced;
  final ValueChanged<GenDifficulty>? onDifficulty;
  final ValueChanged<GenLang>? onLang;
  final VoidCallback? onAdvanced;

  Widget _working(BuildContext context, String text) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(borderRadius: BorderRadius.circular(4), child: const LinearProgressIndicator(minHeight: 5)),
      const SizedBox(height: 10),
      Text(text, style: appText(13.5, c: c.textMedium)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final body = switch (step) {
      ExamGenStep.loading => <Widget>[const AppSkeletonBox(height: 18), const SizedBox(height: 10), const AppSkeletonBox(height: 44)],
      ExamGenStep.needDocument => <Widget>[
          AppBanner(
              icon: Icons.upload_file_rounded,
              color: c.primary,
              text: t('لا يوجد مستند لهذا المقرر بعد. أعطنا ملف المقرر ونكتب الأسئلة منه.',
                  'This course has no document yet. Give us the course file and we will write the questions from it.')),
          const SizedBox(height: 8),
          Text(ragFormatAdvice(picked), style: appText(12.5, c: c.textMedium)),
          const SizedBox(height: 12),
          AppPrimaryButton(label: t('اختر ملف المقرر', 'Choose the course file'), icon: Icons.attach_file_rounded, onPressed: onUpload),
        ],
      ExamGenStep.processing => <Widget>[
          _working(context, t('نقرأ المستند${picked == null ? '' : ' «$picked»'} — عادةً أقل من دقيقة.',
              'Reading the document${picked == null ? '' : ' "$picked"'} — usually under a minute.')),
          if (picked != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(ragFormatAdvice(picked), style: appText(12, c: c.textLight))),
        ],
      ExamGenStep.generating => <Widget>[
          _working(context, t('نختار الموضوعات المهمة، نكتب الأسئلة، ثم نراجعها…', 'Picking the key topics, writing the questions, then reviewing them…')),
        ],
      ExamGenStep.ready => <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.description_outlined, size: 20, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${t('من:', 'From:')} ${documents.join((AppConfig.lang == 'ar' ? '، ' : ', '))}', maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textDark)),
            ),
          ]),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(onPressed: onUpload, icon: const Icon(Icons.add_rounded, size: 18), label: Text(t('أضف مستنداً آخر', 'Add another document'))),
          ),
          if (warning != null) ...[AppBanner(icon: Icons.document_scanner_outlined, color: c.warning, text: warning!), const SizedBox(height: 8)],
          Text(t('نوع الأسئلة', 'Question type'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final g in GenTypes.values) AppChoiceChip(label: genTypesLabel(g), selected: types == g, onTap: () => onTypes(g)),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: Text(t('عدد الأسئلة', 'How many questions?'), style: appText(13, w: FontWeight.w700, c: c.textDark))),
            IconButton.outlined(
                tooltip: t('أقل', 'Fewer'), onPressed: count > 1 ? () => onCount(count - 1) : null, icon: const Icon(Icons.remove_rounded, size: 18)),
            SizedBox(width: 44, child: Text('$count', textAlign: TextAlign.center, style: appText(17, w: FontWeight.w800, c: c.textDark))),
            IconButton.outlined(
                tooltip: t('أكثر', 'More'), onPressed: count < genMaxCount ? () => onCount(count + 1) : null, icon: const Icon(Icons.add_rounded, size: 18)),
          ]),
          const SizedBox(height: 14),
          Text(t('الصعوبة', 'Difficulty'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in GenDifficulty.values) AppChoiceChip(label: genDifficultyLabel(d), selected: difficulty == d, onTap: () => onDifficulty?.call(d)),
          ]),
          if (onAdvanced != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                  onPressed: onAdvanced,
                  icon: Icon(advanced ? Icons.expand_less_rounded : Icons.tune_rounded, size: 18),
                  label: Text(t('خيارات متقدمة', 'Advanced'))),
            ),
          if (advanced) ...[
            if (focus != null)
              AppField(controller: focus!, label: t('ركّز على (اختياري)', 'Focus on (optional)'), hint: t('مثال: الفصل الثالث فقط، أو موضوع التمثيل الضوئي', 'e.g. chapter 3 only, or photosynthesis')),
            const SizedBox(height: 10),
            Text(t('لغة الأسئلة', 'Question language'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final l in GenLang.values) AppChoiceChip(label: genLangLabel(l), selected: lang == l, onTap: () => onLang?.call(l)),
            ]),
          ],
          const SizedBox(height: 14),
          AppPrimaryButton(label: t('أنشئ ${questionsText(count)}', 'Generate ${questionsText(count)}'), icon: Icons.auto_awesome_rounded, onPressed: onGenerate),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(t('تُضاف كمسودة تراجعها وتعدّلها قبل النشر.', 'They are added as a draft you review and edit before publishing.'),
                textAlign: TextAlign.center, style: appText(12, c: c.textLight)),
          ),
        ],
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...body,
      if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: error!)),
    ]);
  }
}

/// The builder's entry: "Generate the questions for me" (plain values).
class QuickGenerateCard extends StatelessWidget {
  const QuickGenerateCard({super.key, required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Container(
          width: 44, height: 44, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
          child: Icon(Icons.auto_awesome_rounded, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('أنشئ الأسئلة لي من مستندات المقرر', 'Generate the questions for me from the course documents'),
                style: appText(14.5, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 2),
            Text(t('تختار النوع والعدد فقط، ثم تراجعها قبل النشر', 'You pick the type and how many; you review them before publishing'),
                style: appText(12.5, c: c.textMedium)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    );
  }
}

/// Track F: the strip on a generated question in the builder — "Generated" and Accept / Edit / Reject (plain values).
/// Accept and Edit only mark it (what counts is the question when the exam is saved: unchanged = accepted, changed =
/// edited with its final text); Reject asks why and takes the question out. Generation v2 adds [onRegenerate] (another
/// question for the same slot; the builder swaps it in) and the source chip: pages and section, the passage it was
/// written from in a popover ([meta], `genMetaOf(question)`).
class GenReviewBar extends StatefulWidget {
  const GenReviewBar({super.key, required this.mark, required this.onAccept, required this.onEdit, required this.onReject, this.onRegenerate, this.meta});
  final GenMark mark;
  final VoidCallback onAccept, onEdit, onReject;

  /// Resolves to the replacement question (null = could not write another; the old one stays).
  final Future<QuickQuestion?> Function()? onRegenerate;
  final GenQMeta? meta;

  @override
  State<GenReviewBar> createState() => _GenReviewBarState();
}

class _GenReviewBarState extends State<GenReviewBar> {
  bool _busy = false;

  Future<void> _regenerate() async {
    if (_busy || widget.onRegenerate == null) return;
    setState(() => _busy = true);
    QuickQuestion? q;
    try {
      q = await widget.onRegenerate!();
    } catch (_) {
      q = null;
    }
    if (q == null) appToast(t('تعذر كتابة سؤال آخر — أبقينا السؤال الحالي', 'Could not write another question — the current one stays'), error: true);
    if (mounted) setState(() => _busy = false);
  }

  void _showEvidence(GenQMeta m) {
    showAppSheet<void>(context, (ctx) {
      final c = ctx.colors;
      final s = m.source;
      return AppSheetContent(title: t('مصدر السؤال', 'Where this question comes from'), children: [
        if (s != null) ...[
          Text(s.title, style: appText(14, w: FontWeight.w700, c: c.textDark)),
          Text(s.label, style: appText(13, c: c.textMedium)),
          const SizedBox(height: AppSpace.sm),
        ],
        if (m.evidence.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.primaryWash, borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: SelectableText(m.evidence, style: appText(13.5, c: c.textDark, h: 1.5)),
          )
        else
          Text(t('لا يوجد مقتطف محفوظ لهذا السؤال.', 'No passage was kept for this question.'), style: appText(13, c: c.textMedium)),
        if (m.needsLook) ...[
          const SizedBox(height: AppSpace.sm),
          AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: t('لم نجد الإجابة صراحةً في هذا المقتطف — راجع السؤال بعناية.', 'The answer was not clearly in this passage — look at the question twice.')),
        ],
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.meta;
    final mark = widget.mark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppBadgePill(t('مُنشأ تلقائياً', 'Generated'), icon: Icons.auto_awesome_rounded, color: c.primary),
        if (m != null && m.hasSource)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: AppPill(icon: Icons.menu_book_outlined, label: m.source!.label, onTap: () => _showEvidence(m)),
          ),
        if (m != null && m.needsLook) AppBadgePill(t('يحتاج مراجعة', 'Needs a look'), icon: Icons.warning_amber_rounded, color: c.warning),
        AppChoiceChip(label: t('قبول', 'Accept'), icon: Icons.check_rounded, selected: mark == GenMark.accepted, onTap: widget.onAccept),
        AppChoiceChip(label: t('تعديل', 'Edit'), icon: Icons.edit_outlined, selected: mark == GenMark.edited, onTap: widget.onEdit),
        if (widget.onRegenerate != null)
          AppChoiceChip(label: _busy ? t('نكتب سؤالاً آخر…', 'Writing another…') : t('سؤال آخر', 'Regenerate'), icon: Icons.refresh_rounded, selected: false, onTap: _regenerate),
        AppChoiceChip(label: t('رفض', 'Reject'), icon: Icons.close_rounded, selected: false, onTap: widget.onReject),
        if (mark == GenMark.edited)
          Text(t('عدّل السؤال أدناه؛ يُسجَّل نصه النهائي عند الحفظ', 'Edit the question below; its final text is recorded when you save'),
              style: appText(12, c: c.textMedium)),
      ]),
    );
  }
}

/// Why the generated question is rejected (one reason or none). Pops the reason ('' = none given); a dismissed sheet
/// pops null = keep the question.
class GenRejectSheet extends StatefulWidget {
  const GenRejectSheet({super.key});

  @override
  State<GenRejectSheet> createState() => _GenRejectSheetState();
}

class _GenRejectSheetState extends State<GenRejectSheet> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(tone: AppTone.danger, icon: Icons.block_rounded, t('رفض السؤال', 'Reject the question')),
        Text(t('لماذا؟ يساعد ذلك المولّد على كتابة أسئلة أفضل.', 'Why? It helps the generator write better questions.'),
            style: appText(13, c: c.textMedium)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in examReasons)
            AppChoiceChip(label: examReasonLabel(r), selected: _reason == r, onTap: () => setState(() => _reason = _reason == r ? null : r)),
        ]),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t('إلغاء', 'Cancel'))),
          AppPrimaryButton(label: t('رفض وحذف', 'Reject and remove'), icon: Icons.delete_outline_rounded, onPressed: () => Navigator.of(context).pop(_reason ?? '')),
        ]),
      ]),
    );
  }
}
