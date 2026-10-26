// The "generate this exam for me" sheet (logic in exam_generate.dart). At most: give the course file (only when the
// course has none yet, with one line on the best format) → question types → how many → Generate. The questions come
// back to the quick builder as an editable draft. [ExamGenForm] and [QuickGenerateCard] are presentational (tested
// under the layout harness); the sheet owns the calls and the polling.
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../rag/rag_library.dart';
import 'exam_generate.dart';
import 'exam_quick.dart';

/// Opens the generator; the questions to add, or null when the teacher left without generating.
Future<List<QuickQuestion>?> openExamGenerator(BuildContext context, {required int courseId, int? orgId}) =>
    showAppSheet<List<QuickQuestion>>(context, (_) => ExamGenSheet(courseId: courseId, orgId: orgId));

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
  String? _picked;
  String? _err;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  List<RagDocument> get _mine => _docs.where((d) => d.scope == 'course' && d.courseId == widget.courseId && !d.archived).toList();

  Future<void> _load() async {
    _poll?.cancel();
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
    if (_step == ExamGenStep.processing) _poll = Timer(const Duration(seconds: 4), _load);
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
    final r = await _api.create(courseId: widget.courseId, orgId: widget.orgId, types: _types, count: _count);
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
    final questions = draft == null ? const <QuickQuestion>[] : quickQuestionsOf(draft.questions);
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
    Navigator.pop(context, questions);
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
          error: _err,
          onUpload: _upload,
          onTypes: (v) => setState(() => _types = v),
          onCount: (v) => setState(() => _count = v.clamp(1, genMaxCount)),
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
          _working(context, t('نكتب الأسئلة من أهم أجزاء المستند…', 'Writing the questions from the key parts of the document…')),
        ],
      ExamGenStep.ready => <Widget>[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.description_outlined, size: 20, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${t('من:', 'From:')} ${documents.join('، ')}', maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(13, c: c.textDark)),
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
          AppPrimaryButton(label: t('أنشئ $count سؤالاً', 'Generate $count questions'), icon: Icons.auto_awesome_rounded, onPressed: onGenerate),
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
