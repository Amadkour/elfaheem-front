// Quick exam UI (logic in exam_quick.dart): Online or Offline? → questions (multiple choice / essay, typed or generated
// from the course documents — exam_generate_sheet.dart) or one uploaded file → Publish. Every other setting is a
// default under "Advanced"; the full editor stays one tap away there.
//
// Entry points: `openQuickExam` (a course's "new exam", an exam-timetable slot) and `showSlotExamSheet` (tapping an
// exam in a timetable: create it now / not now, or open the one already made from that slot).
//
// Track F: questions that came from the generator carry a review strip (Accept / Edit / Reject, GenReviewBar); a
// rejection asks why and is reported at once, the rest are reported as one batch when the exam is saved (ExamGenReview).
import 'dart:async' show unawaited;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/features/shared/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppSpace;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asInt, t;
import '../rag/rag_learning.dart' show LearningApi, kRagLearningFeatureKey;
import 'exam_authoring.dart';
import 'exam_authoring_screen.dart' show ExamEditorScreen, SessionLockPicker, pickEngineDateTime;
import 'exam_gen_api.dart' show genMetaOf;
import 'exam_generate.dart' show ExamGenReview, GenMark, deleteGenItem, regenerateGenItem, sendGenFeedback;
import 'exam_generate_sheet.dart' show GenRejectSheet, GenReviewBar, QuickGenerateCard, openExamGenerator;
import 'exam_paper_sheet.dart' show openExamPaper;
import 'exam_quick.dart';
import 'exam_results_screen.dart';
import 'paper/exam_setup.dart' show ExamSetup, ExamSetupApi;
import 'paper/exam_setup_wizard.dart' show openExamSetupWizard;
import 'paper/paper_exam_entry.dart' show isPaperExam, showPaperExamReady;
import 'paper/templates/omr_template_learn.dart' show openOmrTemplateLearn;

const _numKeyboard = TextInputType.numberWithOptions(decimal: true);
/// The builder's column on a wide window.
const quickScreenMaxWidth = 820.0;
const paperFileExtensions = ['pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg'];

/// Opens the quick builder; returns the created exam's id (null when the creator left without creating).
/// An offline exam with in-app questions goes straight on to its printable paper. When the paper setup was finished,
/// the builder ends on "The paper exam is ready" instead: the paper section (print, scan, review, results) or the
/// printable paper, from one sheet.
///
/// [sessionId] pre-selects the session whose lessons the exam locks ("Lock the lessons after …"). [onClassic] shows the
/// chooser's quiet "Classic exam (live quiz in the room)" link: tapping it closes the builder and calls it (the caller
/// opens the legacy create sheet), so the legacy path stays reachable wherever it exists. [api] is for tests.
Future<int?> openQuickExam(BuildContext context, {int? courseId, int? orgId, QuickKind kind = QuickKind.quiz, int? scheduleSlotId, int? sessionId,
    String? title, DateTime? startsAt, DateTime? endsAt, String course = '', VoidCallback? onClassic, ExamAuthoringApi? api}) async {
  final q = QuickExam(
      kind: kind, courseId: courseId, orgId: orgId, scheduleSlotId: scheduleSlotId, sessionId: sessionId, title: title, startsAt: startsAt, endsAt: endsAt);
  var classic = false;
  final id = await Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => QuickExamScreen(
          exam: q,
          api: api,
          onClassic: onClassic == null
              ? null
              : () {
                  classic = true;
                  Navigator.of(context).pop();
                })));
  if (classic) {
    onClassic?.call();
    return null;
  }
  var setUp = false;
  if (id != null && q.mode == QuickMode.offline && q.courseId != null && context.mounted) {
    setUp = await openExamSetupWizard(context, examId: id, initialDelivery: 'paper', onLearnTemplate: () => openOmrTemplateLearn(context).then((_) {})) == true;
  }
  if (id != null && setUp && context.mounted) {
    final r = await ExamSetupApi().setup(id);
    final s = r.ok ? ExamSetup.fromJson(r.map) : null;
    if (isPaperExam(s) && context.mounted) {
      await showPaperExamReady(context,
          examId: id,
          examTitle: q.title,
          paperFormat: s!.paperFormat,
          onExamPaper: q.isFile ? null : () => openExamPaper(context, examId: id, course: course));
      return id;
    }
    // the wizard's "Online" step: the exam is taken in the app after all, so no printable paper
    if (s != null && s.delivery == 'online') return id;
  }
  if (id != null && q.mode == QuickMode.offline && !q.isFile && context.mounted) await openExamPaper(context, examId: id, course: course);
  return id;
}

/// Tapping an exam of a timetable. [exam] is the engine exam already made from this slot, if any.
/// Returns true when something changed (an exam was created).
Future<bool> showSlotExamSheet(BuildContext context, {required String courseName, required int courseId, int? orgId, required int slotId,
    required String kind, DateTime? startsAt, DateTime? endsAt, Map<String, dynamic>? exam, VoidCallback? onChangeTime}) async {
  final r = await showAppSheet<String>(
      context,
      (ctx) => SlotExamSheet(
            courseName: courseName,
            when: startsAt == null ? null : AppTime.dateTime(startsAt),
            exam: exam,
            canChangeTime: onChangeTime != null,
            onPick: (v) => Navigator.pop(ctx, v),
          ));
  if (!context.mounted || r == null) return false;
  switch (r) {
    case 'create':
      final id = await openQuickExam(context,
          courseId: courseId, orgId: orgId, kind: quickKindOf(kind), scheduleSlotId: slotId, title: '${quickKindTitle(quickKindOf(kind))} — $courseName',
          startsAt: startsAt, endsAt: endsAt, course: courseName);
      return id != null;
    case 'results':
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ExamResultsScreen(examId: asInt(exam!['id']), examTitle: '${exam['title'] ?? ''}', courseId: courseId)));
    case 'paper':
      await openExamPaper(context, examId: asInt(exam!['id']), course: courseName);
    case 'edit':
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: asInt(exam!['id']), courseId: courseId, orgId: orgId)));
    case 'time':
      onChangeTime?.call();
  }
  return false;
}

/// The sheet's content (plain values; under the layout harness).
class SlotExamSheet extends StatelessWidget {
  const SlotExamSheet({super.key, required this.courseName, this.when, this.exam, this.canChangeTime = false, required this.onPick});
  final String courseName;
  final String? when;
  final Map<String, dynamic>? exam;
  final bool canChangeTime;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exam;
    return AppSheetContent(title: courseName, children: [
      if (when != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(when!, style: appText(13, c: c.textMedium))),
      if (e == null) ...[
        AppBanner(icon: Icons.edit_note_rounded, text: t('لم يُنشأ الاختبار بعد. تنشئه الآن؟', 'The exam isn\'t created yet. Create it now?')),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('أنشئ الاختبار الآن', 'Create the exam now'), icon: Icons.add_task_rounded, onPressed: () => onPick('create')),
        TextButton(onPressed: () => onPick(null), child: Text(t('ليس الآن', 'Not now'))),
      ] else ...[
        AppBanner(
            icon: Icons.task_alt_rounded,
            color: c.success,
            text: '${e['title'] ?? ''} · ${examStatusLabel('${e['status'] ?? ''}')}'),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('النتائج والتصحيح', 'Results and marking'), icon: Icons.leaderboard_rounded, onPressed: () => onPick('results')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => onPick('paper'), icon: const Icon(Icons.print_rounded, size: 18), label: Text(t('ورقة الامتحان للطباعة', 'Printable exam paper'))),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => onPick('edit'), icon: const Icon(Icons.edit_outlined, size: 18), label: Text(t('تعديل الاختبار', 'Edit the exam'))),
      ],
      if (canChangeTime)
        TextButton.icon(onPressed: () => onPick('time'), icon: const Icon(Icons.schedule_rounded, size: 18), label: Text(t('تغيير الموعد', 'Change the time'))),
    ]);
  }
}

// ═══════════════════════════════════════ Online or Offline ═══════════════════════════════════════════════════════

/// How the creator starts: write the questions, have them generated, or upload a ready file.
enum QuickStart { manual, generate, file }

IconData quickTypeIcon(String type) => switch (type) {
      'true_false' => Icons.rule_rounded,
      'fill_blank' => Icons.space_bar_rounded,
      'short_answer' => Icons.short_text_rounded,
      'matching' => Icons.compare_arrows_rounded,
      'essay' => Icons.notes_rounded,
      _ => Icons.radio_button_checked_rounded,
    };

/// The first question of a new exam (plain values; under the layout harness).
class QuickStartChooser extends StatelessWidget {
  const QuickStartChooser({super.key, required this.onPick, required this.canGenerate, this.onClassic});
  final ValueChanged<QuickStart> onPick;
  final bool canGenerate;

  /// The quiet "Classic exam (live quiz in the room)" link; null hides it (shown only where the legacy sheet exists).
  final VoidCallback? onClassic;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSectionTitle(t('كيف تريد إنشاء الاختبار؟', 'How do you want to create it?')),
      _ModeCard(
        icon: Icons.edit_note_rounded,
        title: t('أنشئه يدوياً', 'Create manually'),
        text: t('اكتب الأسئلة بنفسك: اختيار من متعدد، صح / خطأ، أكمل، مطابقة وغيرها', 'Write the questions yourself: multiple choice, true / false, complete, matching and more'),
        onTap: () => onPick(QuickStart.manual),
      ),
      const SizedBox(height: AppSpace.sm),
      _ModeCard(
        icon: Icons.auto_awesome_rounded,
        title: t('أنشئه لي', 'Generate for me'),
        text: canGenerate
            ? t('أسئلة من مستندات المقرر، تراجعها وتعدّلها قبل النشر', 'Questions written from the course documents; you review and edit them before publishing')
            : t('يحتاج إلى مقرر: افتح الاختبار من داخل مقرر', 'Needs a course: start the exam from inside a course'),
        onTap: canGenerate ? () => onPick(QuickStart.generate) : null,
      ),
      const SizedBox(height: AppSpace.sm),
      _ModeCard(
        icon: Icons.upload_file_rounded,
        title: t('ارفع ملف امتحان جاهز', 'Upload a ready exam file'),
        text: t('PDF أو Word أو صورة', 'A PDF, Word file or photo'),
        onTap: () => onPick(QuickStart.file),
      ),
      if (onClassic != null)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Center(
            child: TextButton.icon(
              key: const ValueKey('exam.quick.classic'),
              onPressed: onClassic,
              icon: Icon(Icons.sensors_rounded, size: 18, color: context.colors.textMedium),
              label: Text(t('اختبار تقليدي (مسابقة مباشرة في الغرفة)', 'Classic exam (live quiz in the room)'),
                  textAlign: TextAlign.center, style: appText(13, c: context.colors.textMedium)),
            ),
          ),
        ),
    ]);
  }
}

/// The last question, once the questions are in: how will students take it (plain values; under the layout harness).
class QuickDeliveryChooser extends StatelessWidget {
  const QuickDeliveryChooser({super.key, required this.onPick});
  final ValueChanged<QuickMode> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _ModeCard(
        icon: Icons.devices_rounded,
        title: quickModeTitle(QuickMode.online),
        text: t('يجيب الطلاب في التطبيق، والتصحيح تلقائي', 'Students answer in the app, grading is automatic'),
        onTap: () => onPick(QuickMode.online),
      ),
      const SizedBox(height: AppSpace.sm),
      _ModeCard(
        icon: Icons.print_outlined,
        title: quickModeTitle(QuickMode.offline),
        text: t('ورقة للقاعة، وتُدخل الدرجات أو تمسح الإجابات بعدها', 'A paper for the room; you enter the marks or scan the answers after'),
        onTap: () => onPick(QuickMode.offline),
      ),
    ]);
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.icon, required this.title, required this.text, required this.onTap});
  final IconData icon;
  final String title, text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(opacity: onTap == null ? .55 : 1, child: AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Row(children: [
        Container(
          width: 52, height: 52, alignment: Alignment.center,
          decoration: BoxDecoration(color: c.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: c.primary, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: appText(17, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 2),
            Text(text, style: appText(13, c: c.textMedium)),
          ]),
        ),
        Icon(Icons.chevron_right_rounded, color: c.textLight),
      ]),
    ));
  }
}

// ═══════════════════════════════════════ the builder ════════════════════════════════════════════════════════════

class QuickExamScreen extends StatefulWidget {
  const QuickExamScreen({super.key, required this.exam, this.api, this.onClassic});
  final QuickExam exam;
  final ExamAuthoringApi? api;

  /// The chooser's "Classic exam" link (see [openQuickExam]); null hides it.
  final VoidCallback? onClassic;

  @override
  State<QuickExamScreen> createState() => _QuickExamScreenState();
}

class _QuickExamScreenState extends State<QuickExamScreen> {
  late final ExamAuthoringApi _api = widget.api ?? ExamAuthoringApi();
  QuickExam get q => widget.exam;
  late final _title = TextEditingController(text: q.title);
  bool _busy = false;
  bool _tried = false;
  late bool _started = q.questions.isNotEmpty || q.isFile;
  final _review = ExamGenReview();
  late final _learning = LearningApi();
  List<LockSession> _sessions = const [];

  @override
  void initState() {
    super.initState();
    final cid = q.courseId;
    if (cid != null) {
      _api.courseSessions(cid).then((s) {
        if (mounted) setState(() => _sessions = s);
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  /// The review strip shows on generated questions while the server takes the feedback and the feature is on.
  bool _reviewing(QuickQuestion x) =>
      _review.supported && _review.isGenerated(x) && !AppConfig.disableList.contains(kRagLearningFeatureKey);

  /// Reject (or delete) a generated question: why → out of the exam, reported at once. A dismissed sheet keeps it.
  Future<void> _reject(QuickQuestion x) async {
    final reason = await showAppSheet<String>(context, (_) => const GenRejectSheet());
    if (reason == null || !mounted) return;
    final ref = _review.of(x);
    final v2 = genMetaOf(x) != null;
    final call = _review.reject(x, reason.isEmpty ? null : reason);
    setState(() => q.questions.remove(x));
    if (call != null) unawaited(sendGenFeedback(_learning, _review, [call]));
    // generation v2 (D-194): the draft drops the item too, so a later regenerate never brings it back
    if (ref != null && v2) unawaited(deleteGenItem(ref.draftId, ref.n));
  }

  /// "Regenerate" on a generated question: the server writes another from a different idea of the same section; it
  /// takes the old one's place in the list and in the review. Null = it could not (the old one stays).
  Future<QuickQuestion?> _regenerate(QuickQuestion old) async {
    final ref = _review.of(old);
    if (ref == null) return null;
    final fresh = await regenerateGenItem(ref.draftId, ref.n);
    if (fresh == null || !mounted) return null;
    setState(() {
      final at = q.questions.indexOf(old);
      if (at >= 0) q.questions[at] = fresh;
      _review.replace(old, fresh);
    });
    return fresh;
  }

  Future<void> _pickFile() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: paperFileExtensions);
    if (f == null) return;
    final bytes = kIsWeb || f.path == null ? await f.readAsBytes() : null;
    setState(() {
      q.fileName = f.name;
      q.fileBytes = bytes;
      q.filePath = kIsWeb ? null : f.path;
    });
  }

  /// Questions written from the course documents, added to the list as an editable draft.
  Future<void> _generate() async {
    final got = await openExamGenerator(context, courseId: q.courseId!, orgId: q.orgId);
    if (got == null || got.items.isEmpty || !mounted) return;
    _review.track(got);
    setState(() => q.questions.addAll(got.questions));
    appToast(t('أُضيف ${got.items.length} سؤالاً — راجعها وعدّلها قبل النشر', '${got.items.length} questions added — review and edit them before publishing'));
  }

  void _start(QuickStart s) {
    setState(() {
      _started = true;
      if (s == QuickStart.file) q.source = QuickSource.file;
    });
    if (s == QuickStart.generate) _generate();
  }

  /// The last question: how will students take it.
  Future<QuickMode?> _askDelivery() => showAppSheet<QuickMode>(
      context,
      (ctx) => AppSheetContent(
          title: t('كيف سيؤدي الطلاب الاختبار؟', 'How will students take it?'),
          children: [QuickDeliveryChooser(onPick: (m) => Navigator.pop(ctx, m))]));

  /// [editor]: save a draft and continue in the full editor (questions may still be missing there).
  Future<void> _save({required bool publish, bool editor = false}) async {
    q.title = _title.text;
    if (editor) q.mode ??= QuickMode.online;
    final (all, perQ) = q.validate();
    final errors = [
      for (final e in all)
        if (e != 'mode_required' && !(editor && (e == 'no_questions' || e == 'file_required'))) e
    ];
    if (editor && q.isFile && !q.hasFile) q.source = QuickSource.questions;
    if (errors.isNotEmpty || perQ.isNotEmpty) {
      setState(() => _tried = true);
      return appToast(errors.isNotEmpty ? quickCodeText(errors.first) : t('أكمل الأسئلة المعلّمة', 'Complete the marked questions'), error: true);
    }
    if (q.mode == null) {
      final m = await _askDelivery();
      if (m == null || !mounted) return;
      q.mode = m;
    }
    setState(() => _busy = true);
    final r = await createQuickExam(_api, q, publish: publish);
    // the exam exists: every generated question still in it counts as accepted, or edited with its final text
    if (r.examId != null) unawaited(sendGenFeedback(_learning, _review, _review.onSave(q.questions)));
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok && editor) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: r.examId, courseId: q.courseId, orgId: q.orgId)));
      return;
    }
    if (r.ok) {
      appToast(r.published ? t('نُشر الاختبار', 'The exam is published') : t('حُفظ كمسودة', 'Saved as a draft'));
      Navigator.of(context).pop(r.examId);
      return;
    }
    if (r.examId == null) return appToast(r.error!, error: true);
    // the exam exists but a later step failed: finish it in the full editor
    appToast('${r.error} — ${t('أكمل في المحرر', 'finish it in the editor')}', error: true);
    final nav = Navigator.of(context);
    nav.pop(r.examId);
    nav.push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: r.examId, courseId: q.courseId, orgId: q.orgId)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (rawErrors, perQ) = _tried ? q.validate() : (const <String>[], const <int, List<String>>{});
    final errors = rawErrors.where((e) => e != 'mode_required').toList();
    return BasePage(
      key: const ValueKey('exam.quick'),
      appBar: AppBar(title: Text(t('اختبار جديد', 'New exam')), actions: const [HelpInfoButton(pageId: 'teacher.exam_quick')]),
      // a desktop window: the builder reads as one column, not as 1400 px wide cards
      child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: quickScreenMaxWidth), child: !_started
          ? SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: QuickStartChooser(onPick: _start, canGenerate: q.courseId != null, onClassic: widget.onClassic))
          : Column(children: [
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
                  AppField(controller: _title, label: t('اسم الاختبار', 'Exam name'), onChanged: (v) => q.title = v),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    AppChoiceChip(label: t('أسئلة في التطبيق', 'Questions in the app'), icon: Icons.quiz_outlined, selected: !q.isFile,
                        onTap: () => setState(() => q.source = QuickSource.questions)),
                    AppChoiceChip(label: t('رفع ملف الامتحان', 'Upload the exam file'), icon: Icons.upload_file_rounded, selected: q.isFile,
                        onTap: () => setState(() => q.source = QuickSource.file)),
                  ]),
                  const SizedBox(height: 12),
                  if (q.isFile)
                    QuickFilePanel(
                      fileName: q.fileName,
                      points: q.filePoints,
                      offline: q.mode == QuickMode.offline,
                      onPick: _busy ? null : _pickFile,
                      onPoints: (v) => q.filePoints = v,
                    )
                  else ...[
                    if (q.courseId != null)
                      Padding(padding: const EdgeInsets.only(bottom: 10), child: QuickGenerateCard(onTap: _busy ? null : _generate)),
                    for (var i = 0; i < q.questions.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (_reviewing(q.questions[i]))
                            GenReviewBar(
                              key: ObjectKey(_review.of(q.questions[i])),
                              mark: _review.of(q.questions[i])!.mark,
                              onAccept: () => setState(() => _review.mark(q.questions[i], GenMark.accepted)),
                              onEdit: () => setState(() => _review.mark(q.questions[i], GenMark.edited)),
                              onReject: () => _reject(q.questions[i]),
                              meta: genMetaOf(q.questions[i]),
                              onRegenerate: genMetaOf(q.questions[i]) == null ? null : () => _regenerate(q.questions[i]),
                            ),
                          QuickQuestionCard(
                            key: ObjectKey(q.questions[i]),
                            index: i,
                            question: q.questions[i],
                            errors: perQ[i] ?? const [],
                            onChanged: () => setState(() {}),
                            onRemove: _reviewing(q.questions[i]) ? () => _reject(q.questions[i]) : () => setState(() => q.questions.removeAt(i)),
                          ),
                        ]),
                      ),
                    if (q.questions.isEmpty)
                      AppEmpty(icon: Icons.post_add_rounded, title: t('أضف أول سؤال', 'Add the first question'),
                          message: t('اختر نوع السؤال من الأسفل', 'Pick a question type below')),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final ty in quickQuestionTypes)
                        AppPill(icon: quickTypeIcon(ty), label: quickTypeLabel(ty), onTap: () => setState(() => q.questions.add(QuickQuestion.ofType(ty)))),
                    ]),
                  ],
                  const SizedBox(height: 14),
                  QuickAdvancedPanel(exam: q, sessions: _sessions, onChanged: () => setState(() {}), onFullEditor: _busy ? null : () => _save(publish: false, editor: true)),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: errors.map(quickCodeText).join('\n')),
                  ],
                ]),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Flexible(child: TextButton(onPressed: _busy ? null : () => _save(publish: false), child: Text(t('حفظ كمسودة', 'Save as draft')))),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: AppPrimaryButton(
                          label: t('نشر · ${fmtPoints(q.totalPoints)} درجة', 'Publish · ${fmtPoints(q.totalPoints)} pts'),
                          icon: Icons.send_rounded,
                          busy: _busy,
                          onPressed: _busy ? null : () => _save(publish: true)),
                    ),
                  ]),
                ),
              ),
            ]))),
    );
  }
}

/// The uploaded-paper part (plain values; under the layout harness).
class QuickFilePanel extends StatefulWidget {
  const QuickFilePanel({super.key, this.fileName, required this.points, required this.offline, required this.onPick, required this.onPoints});
  final String? fileName;
  final double points;
  final bool offline;
  final VoidCallback? onPick;
  final ValueChanged<double> onPoints;

  @override
  State<QuickFilePanel> createState() => _QuickFilePanelState();
}

class _QuickFilePanelState extends State<QuickFilePanel> {
  late final _points = TextEditingController(text: fmtPoints(widget.points));

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(widget.fileName == null ? Icons.upload_file_rounded : Icons.insert_drive_file_rounded, color: c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(widget.fileName ?? t('PDF أو Word أو صورة', 'PDF, Word or a photo'),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: widget.fileName == null ? c.textMedium : c.textDark)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: widget.onPick, child: Text(widget.fileName == null ? t('اختر ملفاً', 'Choose a file') : t('تغيير', 'Change'))),
        ]),
        const SizedBox(height: 12),
        AppField(controller: _points, label: t('الدرجة الكاملة', 'Full mark'), keyboard: _numKeyboard, ltr: true,
            onChanged: (v) => widget.onPoints(parseNum(v) ?? 0)),
        const SizedBox(height: 8),
        Text(
          widget.offline
              ? t('اطبع الملف للقاعة، ثم أدخل درجة كل طالب من النتائج.', 'Print it for the room, then enter each student\'s mark from the results.')
              : t('يفتح الطلاب الملف ويرفعون ملف إجابتهم، وتصححها أنت من النتائج.', 'Students open the file and upload their answer; you mark it from the results.'),
          style: appText(12.5, c: c.textMedium),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════ one question ═══════════════════════════════════════════════════════════

/// One question of the quick builder; edits [question] in place and calls [onChanged] (under the layout harness).
class QuickQuestionCard extends StatefulWidget {
  const QuickQuestionCard({super.key, required this.index, required this.question, this.errors = const [], required this.onChanged, required this.onRemove});
  final int index;
  final QuickQuestion question;
  final List<String> errors;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<QuickQuestionCard> createState() => _QuickQuestionCardState();
}

class _QuickQuestionCardState extends State<QuickQuestionCard> {
  QuickQuestion get q => widget.question;
  late final _prompt = TextEditingController(text: q.prompt);
  late final _points = TextEditingController(text: fmtPoints(q.points));
  late final _key = TextEditingController(text: q.keyText);
  late final Map<int, TextEditingController> _opts = {for (final o in q.options) o.uid: TextEditingController(text: o.text)};

  final Map<String, TextEditingController> _more = {};
  TextEditingController _ctl(String key, String init) => _more.putIfAbsent(key, () => TextEditingController(text: init));

  @override
  void dispose() {
    for (final x in [_prompt, _points, _key, ..._opts.values, ..._more.values]) {
      x.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    final o = QOption(nextOptionId(q.options.map((o) => o.id)));
    setState(() {
      q.options.add(o);
      _opts[o.uid] = TextEditingController();
    });
  }

  void _removeOption(QOption o) {
    setState(() {
      q.options.remove(o);
      _opts.remove(o.uid)?.dispose();
      if (q.correct == o.id) q.correct = null;
    });
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppBadgePill('${widget.index + 1}', color: c.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(quickTypeLabel(q.type),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w700, c: c.textMedium))),
          SizedBox(
            width: 84,
            child: TextField(
              controller: _points,
              keyboardType: _numKeyboard,
              textAlign: TextAlign.center,
              decoration: InputDecoration(isDense: true, labelText: t('الدرجة', 'Points')),
              onChanged: (v) {
                q.points = parseNum(v) ?? 0;
                widget.onChanged();
              },
            ),
          ),
          IconButton(onPressed: widget.onRemove, icon: Icon(Icons.delete_outline_rounded, color: c.danger), tooltip: t('حذف', 'Delete')),
        ]),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: TextField(
            controller: _prompt,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
                hintText: q.type == 'fill_blank' ? t('اكتب السؤال وضع ___ مكان كل فراغ', 'Write the text and put ___ where each blank goes') : t('اكتب السؤال', 'Write the question')),
            onChanged: (v) {
              q.prompt = v;
              if (q.type == 'fill_blank') setState(() {});
            },
          ),
        ),
        const SizedBox(height: 8),
        ...switch (q.type) {
          'true_false' => _trueFalse(context),
          'fill_blank' => _blanks(context),
          'matching' => _pairs(context),
          'mcq_single' => _options(context),
          _ => _essay(context),
        },
        _difficulty(context),
        if (widget.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6, end: 8),
            child: Text(widget.errors.map(quickCodeText).join(' · '), style: appText(12.5, c: c.danger)),
          ),
      ]),
    );
  }

  Widget _difficulty(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: AppSpace.sm, end: AppSpace.xs),
      child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(t('الصعوبة', 'Difficulty'), style: appText(12.5, w: FontWeight.w700, c: c.textMedium)),
        for (var i = 1; i <= 5; i++)
          AppChoiceChip(
              label: '$i',
              selected: q.difficulty == i,
              onTap: () {
                setState(() => q.difficulty = i);
                widget.onChanged();
              }),
      ]),
    );
  }

  List<Widget> _trueFalse(BuildContext context) {
    final d = q.engine!;
    void pick(bool v) {
      setState(() => d.tfCorrect = v);
      widget.onChanged();
    }

    return [
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppChoiceChip(label: t('صح', 'True'), icon: Icons.check_rounded, selected: d.tfCorrect == true, onTap: () => pick(true)),
        AppChoiceChip(label: t('خطأ', 'False'), icon: Icons.close_rounded, selected: d.tfCorrect == false, onTap: () => pick(false)),
      ]),
    ];
  }

  List<Widget> _blanks(BuildContext context) {
    final c = context.colors;
    final d = q.engine!;
    final marks = blankMarkers(q.prompt);
    return [
      if (marks > 0 && marks != d.blanks.length)
        Padding(
          padding: const EdgeInsetsDirectional.only(bottom: AppSpace.xs, end: AppSpace.xs),
          child: Text(t('في النص $marks فراغات و${d.blanks.length} إجابات', 'The text has $marks blanks and ${d.blanks.length} answer lists'),
              style: appText(12.5, c: c.warning)),
        ),
      for (var i = 0; i < d.blanks.length; i++)
        Row(key: ValueKey('blank.${d.blanks[i].uid}'), children: [
          Expanded(
            child: TextField(
              controller: _ctl('blank.${d.blanks[i].uid}', d.blanks[i].text),
              decoration: InputDecoration(isDense: true, labelText: t('الفراغ ${i + 1}: الإجابات المقبولة', 'Blank ${i + 1}: accepted answers')),
              onChanged: (v) {
                d.blanks[i].text = v;
                widget.onChanged();
              },
            ),
          ),
          if (d.blanks.length > 1)
            IconButton(
                onPressed: () {
                  setState(() => _more.remove('blank.${d.blanks[i].uid}')?.dispose());
                  setState(() => d.blanks.removeAt(i));
                  widget.onChanged();
                },
                tooltip: t('حذف', 'Remove'),
                icon: Icon(Icons.close_rounded, size: 18, color: c.textLight)),
        ]),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: () => setState(() => d.blanks.add(TextItem())), icon: const Icon(Icons.add_rounded, size: 18), label: Text(t('فراغ', 'Blank'))),
      ),
      Text(t('افصل الإجابات المقبولة بفواصل', 'Separate accepted answers with commas'), style: appText(12, c: c.textLight)),
    ];
  }

  List<Widget> _pairs(BuildContext context) {
    final c = context.colors;
    final d = q.engine!;
    return [
      for (final p in d.pairs)
        Row(key: ValueKey('pair.${p.uid}'), children: [
          Expanded(
            child: TextField(
              controller: _ctl('pl.${p.uid}', p.left),
              decoration: InputDecoration(isDense: true, hintText: t('العنصر', 'Item')),
              onChanged: (v) {
                p.left = v;
                widget.onChanged();
              },
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.swap_horiz_rounded, size: 18, color: c.textLight)),
          Expanded(
            child: TextField(
              controller: _ctl('pr.${p.uid}', p.right),
              decoration: InputDecoration(isDense: true, hintText: t('يطابق', 'Matches')),
              onChanged: (v) {
                p.right = v;
                widget.onChanged();
              },
            ),
          ),
          if (d.pairs.length > 2)
            IconButton(
                onPressed: () {
                  setState(() {
                    d.pairs.remove(p);
                    _more.remove('pl.${p.uid}')?.dispose();
                    _more.remove('pr.${p.uid}')?.dispose();
                  });
                  widget.onChanged();
                },
                tooltip: t('حذف', 'Remove'),
                icon: Icon(Icons.close_rounded, size: 18, color: c.textLight)),
        ]),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: () => setState(() => d.pairs.add(MatchPair())), icon: const Icon(Icons.add_rounded, size: 18), label: Text(t('زوج', 'Pair'))),
      ),
    ];
  }

  List<Widget> _options(BuildContext context) {
    final c = context.colors;
    return [
      for (final o in q.options)
        Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs), child: Row(children: [
          IconButton(
            tooltip: t('الإجابة الصحيحة', 'The right answer'),
            onPressed: () {
              setState(() => q.correct = o.id);
              widget.onChanged();
            },
            icon: Icon(q.correct == o.id ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: q.correct == o.id ? c.success : c.textLight),
          ),
          Expanded(
            child: TextField(
              controller: _opts[o.uid],
              decoration: InputDecoration(isDense: true, hintText: t('خيار', 'Choice')),
              onChanged: (v) => o.text = v,
            ),
          ),
          if (q.options.length > 2) IconButton(onPressed: () => _removeOption(o), tooltip: t('حذف الخيار', 'Remove option'), icon: Icon(Icons.close_rounded, size: 18, color: c.textLight)),
        ])),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(onPressed: _addOption, icon: const Icon(Icons.add_rounded, size: 18), label: Text(t('خيار', 'Choice'))),
      ),
      Text(t('اضغط الدائرة بجانب الإجابة الصحيحة', 'Tap the circle next to the right answer'), style: appText(12, c: c.textLight)),
    ];
  }

  List<Widget> _essay(BuildContext context) {
    final c = context.colors;
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: AppSwitchTile(
          title: t('تصحيح تلقائي', 'Auto-grading'),
          subtitle: q.autoGrade ? t('يقترح النظام الدرجة وتراجعها أنت', 'The system grades it; you can review') : t('تصححه أنت يدوياً', 'You mark it by hand'),
          value: q.autoGrade,
          dense: true,
          onChanged: (v) {
            setState(() => q.autoGrade = v);
            widget.onChanged();
          },
        ),
      ),
      if (q.autoGrade) ...[
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final k in EssayKey.values)
            AppChoiceChip(
              label: essayKeyLabel(k),
              selected: q.keyBy == k,
              onTap: () {
                setState(() => q.keyBy = k);
                widget.onChanged();
              },
            ),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: TextField(
            controller: _key,
            minLines: q.keyBy == EssayKey.model ? 3 : 2,
            maxLines: 8,
            decoration: InputDecoration(hintText: essayKeyHint(q.keyBy)),
            onChanged: (v) {
              q.keyText = v;
              widget.onChanged();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(essayKeyHint(q.keyBy), style: appText(12, c: c.textLight)),
        ),
      ],
    ];
  }
}

// ═══════════════════════════════════════ Advanced ═══════════════════════════════════════════════════════════════

/// The defaults, closed until opened (under the layout harness).
class QuickAdvancedPanel extends StatefulWidget {
  const QuickAdvancedPanel({super.key, required this.exam, required this.onChanged, this.onFullEditor, this.sessions = const []});
  final QuickExam exam;

  /// The course's sessions for "Lock the lessons after …" (empty hides the picker).
  final List<LockSession> sessions;
  final VoidCallback onChanged;

  /// Saves a draft and opens the full editor (sections, question bank, proctoring, accommodations …).
  final VoidCallback? onFullEditor;

  @override
  State<QuickAdvancedPanel> createState() => _QuickAdvancedPanelState();
}

class _QuickAdvancedPanelState extends State<QuickAdvancedPanel> {
  QuickExam get q => widget.exam;
  late final _duration = TextEditingController(text: '${q.durationMinutes}');
  late final _attempts = TextEditingController(text: '${q.maxAttempts}');
  late final _passing = TextEditingController(text: fmtPoints(q.passingPercent));
  late final _passcode = TextEditingController(text: q.passcode);
  late final _description = TextEditingController(text: q.description);
  late final _pool = TextEditingController(text: q.poolSize?.toString() ?? '');

  @override
  void dispose() {
    for (final x in [_duration, _attempts, _passing, _passcode, _description, _pool]) {
      x.dispose();
    }
    super.dispose();
  }

  void _set(VoidCallback f) {
    setState(f);
    widget.onChanged();
  }

  String _summary() {
    final parts = <String>[
      t('${q.durationMinutes} دقيقة', '${q.durationMinutes} min'),
      q.maxAttempts == 0 ? t('محاولات بلا حد', 'unlimited attempts') : t('${q.maxAttempts} محاولة', '${q.maxAttempts} attempt(s)'),
      if (q.sessionId != null) t('يقفل ما بعد جلسة', 'locks after a session'),
      if (q.startsAt != null) AppTime.dateTime(q.startsAt!),
      resultsPolicyLabel(q.resultsPolicy),
    ];
    return parts.join(' · ');
  }

  Widget _when(String label, DateTime? v, ValueChanged<DateTime?> set) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Text('$label: ${v == null ? t('غير محدد', 'not set') : AppTime.dateTime(v)}', style: appText(13.5, c: c.textDark)),
        ),
        IconButton(
            onPressed: () async {
              final d = await pickEngineDateTime(context, v);
              if (d != null) _set(() => set(d));
            },
            tooltip: t('اختيار الموعد', 'Pick a date'),
            icon: Icon(Icons.edit_calendar_rounded, color: c.primary)),
        if (v != null) IconButton(onPressed: () => _set(() => set(null)), tooltip: t('مسح', 'Clear'), icon: Icon(Icons.close_rounded, size: 18, color: c.textLight)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final online = q.mode != QuickMode.offline;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.tune_rounded, color: c.textMedium),
          title: Text(t('متقدم', 'Advanced'), style: appText(14.5, w: FontWeight.w700, c: c.textDark)),
          subtitle: Text(_summary(), maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                  child: AppField(controller: _duration, label: t('المدة (دقيقة)', 'Duration (min)'), keyboard: TextInputType.number, ltr: true,
                      onChanged: (v) => _set(() => q.durationMinutes = parseIntField(v) ?? 0))),
              const SizedBox(width: 10),
              Expanded(
                  child: AppField(controller: _attempts, label: t('المحاولات', 'Attempts'), hint: t('0 = بلا حد', '0 = unlimited'), keyboard: TextInputType.number, ltr: true,
                      onChanged: (v) => _set(() => q.maxAttempts = parseIntField(v) ?? 0))),
            ]),
            const SizedBox(height: 10),
            AppField(controller: _description, label: t('وصف (اختياري)', 'Description (optional)'), maxLines: 2, onChanged: (v) => q.description = v),
            const SizedBox(height: 10),
            SessionLockPicker(sessions: widget.sessions, selected: q.sessionId, onChanged: (v) => _set(() => q.sessionId = v)),
            if (!q.isFile && q.mode != QuickMode.offline) ...[
              AppField(
                  controller: _pool,
                  label: t('عدد الأسئلة لكل طالب', 'Questions per student'),
                  hint: t('فارغ = كل الأسئلة؛ أقل من ذلك يعني سحباً عشوائياً', 'Empty = all of them; fewer means a random draw'),
                  keyboard: TextInputType.number,
                  ltr: true,
                  onChanged: (v) => _set(() => q.poolSize = v.trim().isEmpty ? null : (parseIntField(v) ?? 0))),
              const SizedBox(height: 10),
            ],
            _when(t('يبدأ', 'Opens'), q.startsAt, (d) => q.startsAt = d),
            _when(t('ينتهي', 'Closes'), q.endsAt, (d) => q.endsAt = d),
            if (online)
              AppSwitchTile(
                  title: t('ترتيب عشوائي للأسئلة والخيارات', 'Shuffle questions and choices'),
                  value: q.shuffle,
                  dense: true,
                  onChanged: (v) => _set(() => q.shuffle = v)),
            AppSwitchTile(
                title: t('أراجع كل درجة قبل اعتمادها', 'I approve every grade first'),
                subtitle: t('للامتحانات المهمة: الدرجات الآلية تنتظر موافقتك', 'For important exams: automatic grades wait for you'),
                value: q.highStakes,
                dense: true,
                onChanged: (v) => _set(() => q.highStakes = v)),
            const SizedBox(height: 6),
            Text(t('متى يرى الطالب نتيجته؟', 'When does a student see the result?'), style: appText(13, w: FontWeight.w700, c: c.textDark)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in resultsPolicies)
                AppChoiceChip(label: resultsPolicyLabel(p), selected: q.resultsPolicy == p, onTap: () => _set(() => q.resultsPolicy = p)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: AppField(controller: _passing, label: t('نسبة النجاح %', 'Pass mark %'), keyboard: _numKeyboard, ltr: true,
                      onChanged: (v) => _set(() => q.passingPercent = parseNum(v) ?? 50))),
              if (online) ...[
                const SizedBox(width: 10),
                Expanded(
                    child: AppField(controller: _passcode, label: t('رمز دخول (اختياري)', 'Passcode (optional)'), ltr: true,
                        onChanged: (v) => q.passcode = v)),
              ],
            ]),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: widget.onFullEditor,
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(t('المحرر الكامل (أقسام، بنك أسئلة، مراقبة)', 'Full editor (sections, question bank, proctoring)')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
