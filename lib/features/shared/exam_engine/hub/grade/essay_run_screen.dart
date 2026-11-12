// Grade Papers, essay path (D-662): the screens. 1) Setup — the questions with their marks and a model answer or
// rubric criteria (add one by one or paste many at once); 2) the run — add each student's paper (photos or a PDF,
// the pages assigned to questions), live progress through EventOrPoll on `job_updated {kind: essay_run}`, the
// students with what is left; 3) one student — every answer's photo, what was read, the suggested mark and why,
// accept in one tap or set the mark (uncertain readings first); 4) results and export — the exam's own Get Result
// screen. Pure part: essay_run.dart; widgets: essay_run_widgets.dart. The engine decides nothing final by itself.
library;


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../paper/scan/omr_audience_picker.dart' show OmrAudiencePicker;
import '../../paper/scan/omr_routes.dart' show openOmrReview;
import '../../paper/scan/scan_files.dart' show ScanPrepareError;
import '../../paper/scan/scan_prepare.dart' show kScanPhotoMaxSide, prepareScanFile;
import '../../paper/scan/scan_sources.dart' show ScanSource, scanPrepareErrorText, showScanSourceSheet;
import '../result/exam_get_result_screen.dart' show openExamGetResult;
import 'essay_run.dart';
import 'essay_run_widgets.dart';

/// Setup, then the run; returns when the teacher is back on the caller's page.
Future<void> openEssayRunFlow(BuildContext context, {required int courseId, required String courseTitle, int? orgId, EssayRunApi? api}) async {
  final run = await Navigator.of(context).push<EssayRun>(
      MaterialPageRoute(builder: (_) => EssaySetupScreen(courseId: courseId, courseTitle: courseTitle, api: api)));
  if (run == null || !context.mounted) return;
  await openEssayRunScreen(context, examId: run.id, initial: run, courseTitle: courseTitle, api: api);
}

/// An existing run (the Hub's correction entry of an exam with `settings.essay_run`).
Future<void> openEssayRunScreen(BuildContext context, {required int examId, EssayRun? initial, String? courseTitle, EssayRunApi? api}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => EssayRunScreen(examId: examId, initial: initial, courseTitle: courseTitle, api: api)));

// ── 1. setup ───────────────────────────────────────────────────────────────────────────────────────────────────

class EssaySetupScreen extends StatefulWidget {
  const EssaySetupScreen({super.key, required this.courseId, required this.courseTitle, this.api});
  final int courseId;
  final String courseTitle;
  final EssayRunApi? api;

  @override
  State<EssaySetupScreen> createState() => _EssaySetupScreenState();
}

class _EssaySetupScreenState extends State<EssaySetupScreen> {
  late final EssayRunApi _api = widget.api ?? EssayRunApi();
  late final _title = TextEditingController(text: t('تصحيح أوراق ${widget.courseTitle}', 'Papers of ${widget.courseTitle}'));
  final List<EssayQuestionDraft> _qs = [EssayQuestionDraft()];
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final text = TextEditingController();
    final got = await showAppSheet<List<EssayQuestionDraft>>(
        context,
        (ctx) => StatefulBuilder(builder: (ctx, set) {
              final parsed = parseEssayPaste(text.text);
              return AppSheetContent(title: t('لصق عدة أسئلة', 'Paste several questions'), children: [
                Text(
                    t('سؤال في كل سطر مرقّم، والدرجة في آخره بين قوسين. سطر «الإجابة: …» إجابة نموذجية، وسطر يبدأ بـ «-» معيار.',
                        'One numbered line per question, its mark in brackets at the end. An "Answer: …" line is the model answer; a line starting with "-" is a criterion.'),
                    style: AppType.meta(ctx).copyWith(color: ctx.colors.textLight)),
                const SizedBox(height: AppSpace.sm),
                AppField(
                    controller: text,
                    label: t('الأسئلة', 'Questions'),
                    hint: t('1) اشرح عملية البناء الضوئي (5)\nالإجابة: ينتج النبات الجلوكوز والأكسجين…', '1) Explain photosynthesis (5)\nAnswer: plants make glucose and oxygen…'),
                    maxLines: 10,
                    onChanged: (_) => set(() {})),
                const SizedBox(height: AppSpace.sm),
                AppPrimaryButton(
                    label: parsed.isEmpty ? t('إضافة', 'Add') : t('إضافة ${parsed.length} سؤال', 'Add ${parsed.length} questions'),
                    icon: Icons.playlist_add_rounded,
                    onPressed: parsed.isEmpty ? null : () => Navigator.pop(ctx, parsed)),
              ]);
            }));
    text.dispose();
    if (got == null || got.isEmpty || !mounted) return;
    setState(() {
      if (_qs.length == 1 && _qs.first.toJson().isEmpty) _qs.clear();
      _qs.addAll(got.take(kEssayMaxQuestions - _qs.length));
    });
  }

  Future<void> _start() async {
    final problem = essayDraftProblem(_title.text, _qs);
    if (problem != null) {
      showAppNotice(problem, error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await _api.create(courseId: widget.courseId, title: _title.text, questions: _qs);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(essayCodeText(r), error: true);
      return;
    }
    Navigator.of(context).pop(EssayRun.fromJson(r.map));
  }

  @override
  Widget build(BuildContext context) {
    final total = _qs.fold<double>(0, (s, q) => s + (q.mark ?? 0));
    return BasePage(
      key: const ValueKey(kEssayRunFeature),
      appBar: ScreenAppBar(title: t('تصحيح أوراق مكتوبة', 'Grade written papers')),
      child: ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppHero(
                icon: Icons.history_edu_rounded,
                title: t('صحّح الأوراق المكتوبة بدون إنشاء اختبار', 'Grade written papers without making an exam'),
                subtitle: t('اكتب الأسئلة ودرجاتها مع إجابة نموذجية أو معايير، ثم صوّر أوراق الطلاب. نقترح الدرجة وأنت تعتمدها.',
                    'Write the questions with their marks and a model answer or criteria, then photograph the papers. We suggest a mark; you decide.'),
              ),
              const SizedBox(height: AppSpace.md),
              AppField(controller: _title, label: t('اسم التصحيح', 'Name of this correction')),
              const SizedBox(height: AppSpace.md),
              for (var i = 0; i < _qs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: EssayQuestionEditor(
                    key: ObjectKey(_qs[i]),
                    n: i + 1,
                    draft: _qs[i],
                    onChanged: () => setState(() {}),
                    onRemove: _qs.length > 1 ? () => setState(() => _qs.removeAt(i)) : null,
                  ),
                ),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppButton.secondary(
                    label: t('إضافة سؤال', 'Add a question'),
                    icon: Icons.add_rounded,
                    onPressed: _qs.length >= kEssayMaxQuestions ? null : () => setState(() => _qs.add(EssayQuestionDraft()))),
                AppButton.ghost(label: t('لصق عدة أسئلة', 'Paste several questions'), icon: Icons.content_paste_rounded, onPressed: _paste),
              ]),
              const SizedBox(height: AppSpace.lg),
              Text(t('المجموع: ${essayNum(total)} درجة', 'Total: ${essayNum(total)} marks'), style: AppType.bodyStrong(context), textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.sm),
              AppPrimaryButton(label: t('ابدأ التصحيح', 'Start grading'), icon: Icons.arrow_forward_rounded, busy: _busy, onPressed: _busy ? null : _start),
              const SizedBox(height: AppSpace.xl),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ── 2. the run ─────────────────────────────────────────────────────────────────────────────────────────────────

class EssayRunScreen extends StatefulWidget {
  const EssayRunScreen({super.key, required this.examId, this.initial, this.courseTitle, this.api});
  final int examId;
  final EssayRun? initial;
  final String? courseTitle;
  final EssayRunApi? api;

  @override
  State<EssayRunScreen> createState() => _EssayRunScreenState();
}

class _EssayRunScreenState extends State<EssayRunScreen> {
  late final EssayRunApi _api = widget.api ?? EssayRunApi();
  late EssayRun? _run = widget.initial;
  EventOrPoll? _watch;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _watch = EventOrPoll(
      poll: _load,
      every: const Duration(seconds: 15),
      fallbackEvery: const Duration(seconds: 60),
      match: (e) => essayRunEvent(e, widget.examId),
    )..start(pollNow: true);
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.get(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _run = EssayRun.fromJson(r.map);
        _error = null;
      } else {
        _error = essayCodeText(r);
      }
    });
  }

  Future<int?> _pickStudent() {
    var chosen = <int>{};
    return showAppSheet<int>(
        context,
        (ctx) => StatefulBuilder(
            builder: (ctx, set) => AppSheetContent(title: t('ورقة أي طالب؟', 'Whose paper is it?'), children: [
                  OmrAudiencePicker(
                    examId: widget.examId,
                    selected: chosen,
                    onChanged: (s) {
                      final added = s.difference(chosen);
                      if (added.isNotEmpty) Navigator.pop(ctx, added.first);
                      set(() => chosen = s);
                    },
                  ),
                ])));
  }

  Future<List<(String, Uint8List)>> _pickPages(String who) async {
    final pick = await showScanSourceSheet(context, camera: !kIsWeb, title: t('صفحات ورقة $who', 'Pages of $who\'s paper'));
    if (pick == null) return const [];
    if (pick.source == ScanSource.camera) {
      final x = await ImagePicker().pickImage(
          source: ImageSource.camera, maxWidth: kScanPhotoMaxSide * 1.0, maxHeight: kScanPhotoMaxSide * 1.0, imageQuality: 92, requestFullMetadata: false);
      if (x == null) return const [];
      return [(x.name, await x.readAsBytes())];
    }
    final out = <(String, Uint8List)>[];
    for (final f in pick.files.take(kEssayMaxPages)) {
      try {
        out.addAll(await prepareScanFile(f));
      } on ScanPrepareError catch (e) {
        showAppNotice(scanPrepareErrorText(e.code), error: true);
        return const [];
      }
    }
    return out;
  }

  Future<List<int>?> _assign(List<(String, Uint8List)> files, int questions) async {
    var numbers = essayDefaultNumbers(files.length, questions);
    return showAppSheet<List<int>>(
        context,
        (ctx) => StatefulBuilder(builder: (ctx, set) {
              final problem = essayNumbersProblem(numbers, questions);
              return AppSheetContent(title: t('الصفحات والأسئلة', 'Pages and questions'), children: [
                EssayPageAssign(
                  names: [for (final f in files) f.$1],
                  numbers: numbers,
                  questions: questions,
                  problem: problem,
                  onChanged: (i, q) => set(() => numbers = [...numbers]..[i] = q),
                ),
                const SizedBox(height: AppSpace.md),
                AppPrimaryButton(label: t('إرسال', 'Send'), icon: Icons.send_rounded, onPressed: problem != null ? null : () => Navigator.pop(ctx, numbers)),
              ]);
            }));
  }

  Future<void> _addPaper() async {
    final run = _run;
    if (run == null) return;
    final student = await _pickStudent();
    if (student == null || !mounted) return;
    final who = run.students.where((s) => s.id == student).firstOrNull?.name ?? t('الطالب', 'the student');
    final files = await _pickPages(who);
    if (files.isEmpty || !mounted) return;
    List<int>? numbers;
    final hasPdf = files.any((f) => f.$1.toLowerCase().endsWith('.pdf'));
    if (run.questions.length > 1 && !hasPdf && files.length != run.questions.length) {
      numbers = await _assign(files, run.questions.length);
      if (numbers == null || !mounted) return;
    }
    setState(() => _busy = true);
    final r = await _api.sendPaper(widget.examId, studentId: student, files: files, numbers: numbers);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showAppNotice(essayCodeText(r), error: true);
      return;
    }
    final sent = (r.map['answers'] is List) ? (r.map['answers'] as List).length : 0;
    showAppNotice(sent == 0
        ? t('هذه الصفحات أُرسلت من قبل', 'These pages were already sent')
        : t('أُرسلت $sent إجابة — نقرؤها الآن', '$sent answers sent: reading them now'));
    await _load();
  }

  Future<void> _openStudent(EssayStudent s) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => EssayStudentScreen(examId: widget.examId, studentId: s.id, initial: _run, api: _api)));
    if (mounted) await _load();
  }

  Future<void> _results() async {
    final run = _run;
    if (run == null) return;
    await openExamGetResult(context, examId: run.id, title: run.title, courseId: run.courseId);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final run = _run;
    final Widget body;
    if (run == null) {
      body = _error != null
          ? AppEmpty(icon: Icons.history_edu_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Try again'), onAction: _load)
          : const AppListSkeleton(items: 4, withAvatar: false);
    } else {
      final toCheck = [for (final s in run.students) if (s.open > 0) s];
      final reading = [for (final s in run.students) if (s.open == 0 && s.waiting > 0) s];
      final done = [for (final s in run.students) if (s.finished) s];
      body = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppHero(
                icon: Icons.history_edu_rounded,
                title: run.title,
                subtitle: [
                  if ((widget.courseTitle ?? '').isNotEmpty) widget.courseTitle!,
                  t('${run.questions.length} سؤال · ${essayNum(run.maxScore)} درجة', '${run.questions.length} questions · ${essayNum(run.maxScore)} marks'),
                ].join(' · '),
              ),
              const SizedBox(height: AppSpace.md),
              EssayRunSummary(run: run, busy: _busy, onAddPaper: _addPaper, onResults: run.students.isEmpty ? null : _results),
              const SizedBox(height: AppSpace.lg),
              if (run.students.isEmpty)
                AppEmpty(
                  icon: Icons.add_a_photo_rounded,
                  title: t('لا توجد أوراق بعد', 'No papers yet'),
                  message: t('أضف ورقة أول طالب: صورة لكل صفحة أو ملف PDF.', 'Add the first student\'s paper: a photo per page, or a PDF.'),
                ),
              for (final (title, list) in [
                (t('للمراجعة', 'To check'), toCheck),
                (t('تُقرأ الآن', 'Being read'), reading),
                (t('اكتمل', 'Done'), done),
              ])
                if (list.isNotEmpty) ...[
                  AppSectionTitle(title),
                  const SizedBox(height: AppSpace.xs),
                  for (final s in list)
                    Padding(padding: const EdgeInsets.only(bottom: AppSpace.xs), child: EssayStudentCard(student: s, onTap: () => _openStudent(s))),
                  const SizedBox(height: AppSpace.md),
                ],
            ]),
          ),
        ),
      ]);
    }
    return BasePage(key: const ValueKey(kEssayRunFeature), appBar: ScreenAppBar(title: t('تصحيح أوراق مكتوبة', 'Grade written papers')), child: body);
  }
}

// ── 3. one student ─────────────────────────────────────────────────────────────────────────────────────────────

class EssayStudentScreen extends StatefulWidget {
  const EssayStudentScreen({super.key, required this.examId, required this.studentId, this.initial, this.api});
  final int examId, studentId;
  final EssayRun? initial;
  final EssayRunApi? api;

  @override
  State<EssayStudentScreen> createState() => _EssayStudentScreenState();
}

class _EssayStudentScreenState extends State<EssayStudentScreen> {
  late final EssayRunApi _api = widget.api ?? EssayRunApi();
  late EssayRun? _run = widget.initial;
  EventOrPoll? _watch;
  final Map<int, Uint8List?> _crops = {};
  final Set<int> _loadingCrops = {};
  int? _busyItem;

  @override
  void initState() {
    super.initState();
    _watch = EventOrPoll(
      poll: _load,
      every: const Duration(seconds: 20),
      fallbackEvery: const Duration(seconds: 90),
      match: (e) => essayRunEvent(e, widget.examId),
    )..start();
    _fetchCrops();
  }

  @override
  void dispose() {
    _watch?.dispose();
    super.dispose();
  }

  EssayStudent? get _student => _run?.students.where((s) => s.id == widget.studentId).firstOrNull;

  Future<void> _load() async {
    final r = await _api.get(widget.examId);
    if (!mounted || !r.ok) return;
    setState(() => _run = EssayRun.fromJson(r.map));
    _fetchCrops();
  }

  void _fetchCrops() {
    for (final a in _student?.answers ?? const <EssayAnswer>[]) {
      final s = a.suggestion;
      if (s == null || s.cropUrl == null || _crops.containsKey(s.itemId) || _loadingCrops.contains(s.itemId)) continue;
      _loadingCrops.add(s.itemId);
      _api.crop(s.cropUrl).then((b) {
        if (!mounted) return;
        setState(() {
          _crops[s.itemId] = b;
          _loadingCrops.remove(s.itemId);
        });
      });
    }
  }

  Future<void> _accept(EssaySuggestion s) async {
    setState(() => _busyItem = s.itemId);
    final r = await _api.accept(widget.examId, s.itemId);
    if (!mounted) return;
    setState(() => _busyItem = null);
    if (!r.ok) {
      showAppNotice(essayCodeText(r), error: true);
      return;
    }
    await _load();
  }

  Future<void> _edit(EssaySuggestion s, double points) async {
    final ctl = TextEditingController(text: s.suggested == null ? '' : essayNum(s.suggested));
    final v = await showAppSheet<double>(
        context,
        (ctx) => AppSheetContent(title: t('الدرجة من ${essayNum(points)}', 'Mark out of ${essayNum(points)}'), children: [
              AppNumberField(controller: ctl, label: t('الدرجة', 'Mark'), min: 0, max: points, step: 0.5, decimals: 1, autofocus: true),
              const SizedBox(height: AppSpace.md),
              AppPrimaryButton(
                  label: t('حفظ', 'Save'),
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final x = double.tryParse(ctl.text.trim());
                    if (x == null || x < 0 || x > points) {
                      showAppNotice(t('اكتب درجة من 0 إلى ${essayNum(points)}', 'Enter a mark from 0 to ${essayNum(points)}'), error: true);
                      return;
                    }
                    Navigator.pop(ctx, (x * 2).round() / 2);
                  }),
            ]));
    ctl.dispose();
    if (v == null || !mounted) return;
    setState(() => _busyItem = s.itemId);
    final r = await _api.setScore(widget.examId, s.itemId, v);
    if (!mounted) return;
    setState(() => _busyItem = null);
    if (!r.ok) {
      showAppNotice(essayCodeText(r), error: true);
      return;
    }
    await _load();
  }

  Future<void> _openPage(EssayStudent st, EssayAnswer a) async {
    if (st.attemptId == null) return;
    await openOmrReview(context, widget.examId, focus: (attemptId: st.attemptId!, questionId: a.questionId, code: null));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = _student;
    final run = _run;
    final Widget body;
    if (st == null || run == null) {
      body = const AppListSkeleton(items: 3, withAvatar: false);
    } else {
      final answers = essayAnswerOrder(st.answers);
      body = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(essayStudentLine(st), style: AppType.meta(context).copyWith(color: context.colors.textLight)),
              const SizedBox(height: AppSpace.sm),
              for (final a in answers)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: EssayAnswerCard(
                    answer: a,
                    question: run.question(a.n),
                    crop: a.suggestion == null ? null : _crops[a.suggestion!.itemId],
                    cropLoading: a.suggestion != null && _loadingCrops.contains(a.suggestion!.itemId),
                    busy: a.suggestion != null && _busyItem == a.suggestion!.itemId,
                    onAccept: a.suggestion == null ? null : () => _accept(a.suggestion!),
                    onEdit: a.suggestion == null ? null : () => _edit(a.suggestion!, run.question(a.n)?.points ?? 0),
                    onOpenPage: a.suggestion == null || st.attemptId == null ? null : () => _openPage(st, a),
                  ),
                ),
            ]),
          ),
        ),
      ]);
    }
    return BasePage(key: const ValueKey(kEssayRunFeature), appBar: ScreenAppBar(title: st?.name ?? t('ورقة الطالب', 'Student\'s paper')), child: body);
  }
}
