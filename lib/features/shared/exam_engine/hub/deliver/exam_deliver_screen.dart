// Exam Hub, "Deliver" (D-354): one screen from the real paper to the students. The preview draws the actual pages of the
// actual file for a real student with their printed identifiers; Studio changes how it looks; one button prints every
// version or every personal copy in one PDF or one Word file; email sends each student their own copy or the whole exam
// to one address. "What will be printed" (deliver_summary_card.dart) counts every document before Print; an answer
// booklet (D-663) goes after each question paper when the exam's answers go in a table or on paper. A class is built paper by paper with visible progress and Cancel (deliver_build.dart).
//
// Plain-value widgets (the layout harness pumps them): DeliverPreviewPane · DeliverPrintCard · DeliverEmailCard ·
// DeliveryRow · BuildProgressDialog.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../../design/engine/design_engine.dart' show DesignPurpose;
import '../../../../../design/export_layout/layout_api.dart' show LayoutApi;
import '../../../../teacher/data_lab/data_lab_saver_io.dart' if (dart.library.html) '../../../../teacher/data_lab/data_lab_saver_web.dart' as saver;
import '../../exam_authoring_screen.dart' show ExamEditorScreen;
import '../../exam_paper_design_api.dart';
import '../../exam_paper_designer.dart' show PaperConflictChoice, blankPaperDoc, openPaperDesigner, paperDocFrom, paperStartChoices, showPaperConflictDialog;
import '../../exam_paper_pdf.dart' show PaperBuildCancelled, PaperBuildControl;
import '../../exam_paper_sheet.dart' show openExamPaper;
import '../../exam_versions.dart';
import '../../exam_versions_sheet.dart' show openExamVersions;
import '../../paper/exam_setup.dart' show kExamOmrFeatureKey;
import '../../paper/scan/omr_sheets_sheet.dart' show showOmrSheetsSheet;
import '../create/answer_format.dart' show AnswerFormat;
import '../create/answer_sheet_plan.dart';
import '../create/answer_sheet_widgets.dart' show AnswerSheetPrintCard;
import '../create/exam_create_logic.dart' show versionsCountText;
import 'deliver_build.dart';
import 'deliver_logic.dart';
import 'deliver_summary_card.dart';
import 'identifier_plan_step.dart' show openIdentifierPlanSheet;
import 'paper_page_replay.dart';

void _notice(String m, {bool error = false}) => showAppNotice(m, error: error);

const _pdfMime = 'application/pdf';
const _docxMime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// [course]: the course's name for the paper's header, when the caller knows it.
Future<void> openExamDeliver(BuildContext context, {required int examId, required String title, int? courseId, String course = ''}) =>
    Navigator.of(context).push(MaterialPageRoute(settings: const RouteSettings(name: '/exam-deliver'), builder: (_) => ExamDeliverScreen(examId: examId, title: title, courseId: courseId, course: course)));

class ExamDeliverScreen extends StatefulWidget {
  const ExamDeliverScreen({super.key, required this.examId, required this.title, this.courseId, this.course = ''});
  final int examId;
  final String title, course;
  final int? courseId;

  @override
  State<ExamDeliverScreen> createState() => _ExamDeliverScreenState();
}

class _ExamDeliverScreenState extends State<ExamDeliverScreen> {
  final _vApi = ExamVersionsApi();
  final _dApi = ExamPaperDesignApi();
  final _api = ExamDeliverApi();

  DeliverLoad? _load;
  DeliverSource? _s;
  List<PrintPlanItem> _roster = const [];
  String? _rosterError;
  SampleCopy? _sample;
  String? _version;
  int _sampleIndex = 0;
  bool _previewBusy = true;

  DeliverScope _scope = DeliverScope.students;
  bool _scopeSettled = false;
  bool _word = false;
  int _blank = 30;

  // the NB2 written-answer sheets (D-687)
  final _sheetApi = AnswerSheetApi();
  int _nb2Blank = 30;
  bool _nb2Busy = false;
  String? _nb2Error;
  bool _printing = false;

  /// The booklet switch; null = what the exam's settings say (deliverBookletDefault).
  bool? _booklet;

  IdCoverage? _email;
  List<ExamDelivery> _deliveries = const [];
  EventOrPoll? _watch;

  int get _id => widget.examId;

  bool get _bookletOn => (_s?.bookletOffered ?? false) && (_booklet ?? _s?.bookletDefault ?? false);

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  @override
  void dispose() {
    _watch?.dispose();
    _sample?.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    final accent = (context.colors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
    setState(() => _previewBusy = true);
    final load = await loadDeliverSource(_id, accentFallback: accent, course: widget.course);
    if (!mounted) return;
    setState(() {
      _load = load;
      _s = load.source;
    });
    final s = load.source;
    if (s == null) return setState(() => _previewBusy = false);
    // a course's roster, or the uploaded list of an exam with no course planned for one copy per student (D-716)
    if (_named(s)) {
      final roster = await loadPlanRoster(_id, _vApi);
      if (!mounted) return;
      setState(() {
        _roster = roster.items;
        _rosterError = roster.error;
        _settleScope(s, rosterKnown: roster.error == null);
      });
      // only who has an address: asked for when the email card can actually be used
      if (roster.items.isEmpty || !s.hasCourse || AppConfig.disableList.contains(kDeliverEmailFeatureKey)) {
        if (mounted) setState(() => _email = null);
      } else {
        final email = await _api.values(_id, 'email', null);
        if (mounted) setState(() => _email = email.ok ? IdCoverage.fromJson(email.map) : const IdCoverage(unreadable: true));
      }
    } else {
      _settleScope(s, rosterKnown: true);
    }
    await _rebuildPreview();
    await _reloadDeliveries();
  }

  /// Copies can be named: a paper exam of a course, or one with no course whose plan is a copy per student (its list).
  bool _named(DeliverSource s) => s.isPaper && (s.hasCourse || s.plan?.personal == true);

  /// Opens once on what the wizard planned; after that the teacher's choice stands, through every reload.
  void _settleScope(DeliverSource s, {required bool rosterKnown}) {
    if (!_scopeSettled) {
      _scope = deliverOpeningScope(s.plan, paper: _named(s), hasRoster: _roster.isNotEmpty);
      _scopeSettled = rosterKnown;
    } else if (_scope == DeliverScope.students && _roster.isEmpty) {
      _scope = DeliverScope.versions;
    }
  }

  Future<void> _rebuildPreview() async {
    final s = _s;
    if (s == null) return;
    setState(() => _previewBusy = true);
    SampleCopy? fresh;
    try {
      final student = _roster.isEmpty ? null : _roster[_sampleIndex.clamp(0, _roster.length - 1)];
      fresh = await buildSample(s, version: _version, student: student, api: _vApi, examId: _id, booklet: _bookletOn);
    } catch (e) {
      debugPrint('deliver preview failed: $e');
    }
    if (!mounted) {
      fresh?.dispose();
      return;
    }
    final old = _sample;
    setState(() {
      _sample = fresh;
      _previewBusy = false;
    });
    old?.dispose();
  }

  void _pickVersion(String? code) {
    setState(() => _version = code);
    _rebuildPreview();
  }

  void _stepStudent(int by) {
    if (_roster.isEmpty) return;
    setState(() => _sampleIndex = (_sampleIndex + by) % _roster.length);
    _rebuildPreview();
  }

  // ── studio / questions ──

  Future<void> _studio() async {
    final s = _s;
    if (s == null) return;
    var doc = s.design;
    if (doc == null) {
      final r = await LayoutApi.instance.starters(purpose: DesignPurpose.examPaper);
      final choices = r.ok ? paperStartChoices(r.data!, const []) : const [];
      doc = choices.isEmpty ? blankPaperDoc(purpose: DesignPurpose.examPaper) : paperDocFrom(choices.first.document, purpose: DesignPurpose.examPaper);
    }
    if (!mounted) return;
    final student = _roster.isEmpty ? null : _roster[_sampleIndex.clamp(0, _roster.length - 1)];
    final out = await openPaperDesigner(context,
        purpose: DesignPurpose.examPaper, title: widget.title, initial: doc, sample: deliverDesignerSample(s, identifiers: student?.identifiers ?? s.blankLabels), orgId: s.orgId);
    if (out == null || !mounted) return;
    var r = await _dApi.save(_id, document: out, cover: s.cover, version: s.designVersion);
    if (!mounted) return;
    if (r.conflict) {
      final pick = await showPaperConflictDialog(context);
      if (!mounted || pick == null) return;
      final cur = await _dApi.load(_id);
      if (!mounted || cur == null) return;
      if (pick == PaperConflictChoice.reload) return _reloadAll();
      r = await _dApi.save(_id, document: out, cover: s.cover, version: cur.version);
      if (!mounted) return;
    }
    if (!r.ok) return _notice(r.error ?? t('تعذّر حفظ التصميم', 'Could not save the design'), error: true);
    await _reloadAll();
  }

  Future<void> _questions() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamEditorScreen(examId: _id, courseId: widget.courseId, orgId: _s?.orgId)));
    if (mounted) await _reloadAll();
  }

  Future<void> _versions({int? count}) async {
    final s = _s;
    if (s == null) return;
    await openExamVersions(context, examId: _id, current: s.versions, api: _vApi, bubble: s.bubble, initialCount: count);
    if (mounted) await _reloadAll();
  }

  Future<void> _identifiers() async {
    await openIdentifierPlanSheet(context, examId: _id, courseId: _s?.hasCourse == true ? (widget.courseId ?? _s!.view.exam.courseId) : null);
    if (mounted) await _reloadAll();
  }

  Future<void> _moreOptions() async {
    await openExamPaper(context, examId: _id, course: widget.course);
    if (mounted) await _reloadAll();
  }

  // ── printing ──

  Future<T?> _withProgress<T>(String title, Future<T> Function(PaperBuildControl control, ValueNotifier<BuildProgress> progress) job) async {
    final progress = ValueNotifier(BuildProgress(title: title));
    var cancelled = false;
    final control = PaperBuildControl(onStep: (a, b) => progress.value = BuildProgress(title: title, done: a, total: b), cancelled: () => cancelled);
    final closed = Completer<void>();
    unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ValueListenableBuilder<BuildProgress>(
            valueListenable: progress,
            builder: (_, p, __) => BuildProgressDialog(progress: p, onCancel: () {
                  cancelled = true;
                  progress.value = BuildProgress(title: t('جارٍ الإلغاء ...', 'Cancelling ...'), done: p.done, total: p.total);
                }))).whenComplete(closed.complete));
    try {
      return await job(control, progress);
    } on PaperBuildCancelled {
      return null;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      await closed.future;
    }
  }

  Future<void> _print() async {
    final s = _s;
    if (s == null) return;
    if (s.versions.stale) return _notice(versionsStaleText, error: true);
    setState(() => _printing = true);
    final word = _word;
    final booklet = _bookletOn;
    final title = switch (_scope) {
      DeliverScope.students => t('جارٍ تجهيز نسخ الطلاب ...', 'Building the student copies ...'),
      DeliverScope.versions => t('جارٍ تجهيز النماذج ...', 'Building the versions ...'),
      DeliverScope.blank => t('جارٍ تجهيز النسخ الفارغة ...', 'Building the blank copies ...'),
    };
    try {
      final out = await _withProgress<(Uint8List?, String?, String?)>(title, (control, progress) async {
        if (_scope == DeliverScope.versions) return (await buildAllVersionsFile(s, word: word, control: control, booklet: booklet), null, null);
        final res = await buildClassFile(s, _id,
            word: word, named: _scope == DeliverScope.students, studentIds: [for (final x in _roster) x.studentId!], blank: _blank, api: _vApi, control: control, booklet: booklet);
        return (res.bytes, res.error, res.warning);
      });
      if (out == null || !mounted) return;
      final (bytes, error, warning) = out;
      if (error != null) return _notice(error, error: true);
      final suffix = switch (_scope) {
        DeliverScope.students => t('نسخ الطلاب', 'student copies'),
        DeliverScope.versions => t('كل النماذج', 'all versions'),
        DeliverScope.blank => t('نسخ فارغة', 'blank copies'),
      };
      final path = await saver.dlSaveBytes(bytes!, '${deliverFileStem(widget.title, suffix)}.${word ? 'docx' : 'pdf'}', word ? _docxMime : _pdfMime);
      showAppNotice(path == null ? t('جاهز للطباعة', 'Ready to print') : '${t('حُفظ في', 'Saved to')} $path');
      if (warning != null) showAppNotice(warning, error: true);
    } catch (e) {
      debugPrint('deliver print failed: $e');
      showAppNotice(t('تعذّر إنشاء الملف', 'Could not create the file'), error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  // ── email ──

  /// The NB2 sheets as one PDF, saved like the paper itself.
  Future<void> _answerSheets(SheetPlan plan) async {
    setState(() {
      _nb2Busy = true;
      _nb2Error = null;
    });
    final (bytes, fail) = await _sheetApi.sheetsPdf(_id, answerSheetsBody(plan, blank: _nb2Blank));
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _nb2Busy = false;
        _nb2Error = fail == null ? null : answerSheetErrorText(fail);
      });
      return;
    }
    try {
      final path = await saver.dlSaveBytes(bytes, '${deliverFileStem(widget.title, t('أوراق الإجابة', 'answer sheets'))}.pdf', _pdfMime);
      _notice(path == null ? t('أوراق الإجابة جاهزة', 'The answer sheets are ready') : '${t('حُفظ في', 'Saved to')} $path');
    } catch (_) {
      _nb2Error = t('تعذّر حفظ الملف', 'The file could not be saved');
    }
    if (mounted) setState(() => _nb2Busy = false);
  }

  Future<void> _reloadDeliveries() async {
    final r = await _api.deliveries(_id);
    if (!mounted || !r.ok) return;
    final items = [for (final x in (r.map['items'] as List?) ?? const []) if (x is Map) ExamDelivery.fromJson(Map<String, dynamic>.from(x))];
    setState(() => _deliveries = items);
    if (anyDeliveryRunning(items)) {
      (_watch ??= EventOrPoll(poll: _reloadDeliveries, every: const Duration(seconds: 6), fallbackEvery: const Duration(seconds: 20), names: const {LiveEvents.jobUpdated})).start();
    } else {
      _watch?.stop();
    }
  }

  Future<void> _emailStudents() async {
    final s = _s;
    if (s == null) return;
    final warn = earlyEmailWarning(s.view.exam.startsAt, DateTime.now().toUtc());
    final compose = await showAppSheet<EmailCompose>(
        context, (_) => EmailComposeSheet(mode: EmailMode.students, earlyWarning: warn, count: _roster.length, noEmailNames: _email?.missingNames ?? const [], coverageKnown: _email != null && !_email!.unreadable && _email!.namesKnown));
    if (compose == null || !mounted) return;
    final out = await _withProgress<StudentsSendResult>(t('جارٍ إنشاء النسخ ...', 'Building the copies ...'), (control, progress) {
      return sendPerStudentCopies(s, _id, _roster, word: compose.word, message: compose.message, api: _vApi, deliver: _api, control: control, booklet: _bookletOn, onStage: (stage) {
        progress.value = BuildProgress(title: stage, done: progress.value.done, total: progress.value.total);
      });
    });
    if (!mounted) return;
    if (out == null) return _notice(t('أُلغي الإرسال.', 'Sending cancelled.'));
    if (out.error != null) {
      showAppNotice(out.error!, error: true);
    } else if (out.cancelled) {
      showAppNotice(t('أُلغي بعد إرسال ${out.sent}.', 'Cancelled after sending ${out.sent}.'));
    } else {
      final who = countText(out.sent, ar1: 'طالب واحد', ar2: 'طالبين', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');
      showAppNotice(t('بدأ الإرسال إلى $who. ستظهر النتيجة بالأسفل.', 'Sending to $who has started. The result will appear below.'));
    }
    await _reloadDeliveries();
  }

  Future<void> _emailWhole() async {
    final s = _s;
    if (s == null) return;
    final warn = earlyEmailWarning(s.view.exam.startsAt, DateTime.now().toUtc());
    final compose = await showAppSheet<EmailCompose>(context, (_) => EmailComposeSheet(mode: EmailMode.whole, earlyWarning: warn));
    if (compose == null || !mounted) return;
    final bytes = await _withProgress<Uint8List>(t('جارٍ تجهيز الملف ...', 'Building the file ...'), (control, _) => buildAllVersionsFile(s, word: compose.word, control: control, booklet: _bookletOn));
    if (bytes == null || !mounted) return;
    final name = '${deliverFileStem(widget.title, t('الاختبار', 'exam'))}.${compose.word ? 'docx' : 'pdf'}';
    final r = await _api.sendWhole(_id, to: compose.to!, file: bytes, fileName: name, message: compose.message);
    if (!mounted) return;
    if (deliverTooLarge(r)) {
      final download = await appConfirm(context, message: deliverTooLargeText, confirmLabel: t('تنزيل الملف', 'Download the file'));
      if (!download || !mounted) return;
      final path = await saver.dlSaveBytes(bytes, name, compose.word ? _docxMime : _pdfMime);
      showAppNotice(path == null ? t('جاهز', 'Ready') : '${t('حُفظ في', 'Saved to')} $path');
      return;
    }
    if (!r.ok) return _notice(deliverErrorText(r), error: true);
    showAppNotice(t('بدأ الإرسال. ستظهر النتيجة بالأسفل.', 'Sending has started. The result will appear below.'));
    await _reloadDeliveries();
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    return BasePage(
      appBar: AppHeader(title: t('تجهيز الاختبار وتسليمه', 'Print and deliver')),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final load = _load;
    if (load == null) return const Padding(padding: EdgeInsets.all(AppSpace.md), child: AppListSkeleton(items: 5, withAvatar: false));
    final s = _s;
    if (s == null) {
      return Center(
          child: AppEmpty(
              icon: load.noQuestions ? Icons.quiz_outlined : Icons.description_outlined,
              title: load.message ?? '',
              actionLabel: load.noQuestions ? t('إضافة أسئلة', 'Add questions') : null,
              onAction: load.noQuestions ? _questions : null));
    }
    final preview = DeliverPreviewPane(
      pages: _sample?.pages,
      busy: _previewBusy,
      versions: [for (final v in s.versions.items) v.code],
      version: _sample?.version ?? _version,
      onVersion: _pickVersion,
      studentName: _roster.isEmpty ? null : _roster[_sampleIndex.clamp(0, _roster.length - 1)].studentName,
      studentIndex: _sampleIndex,
      studentCount: _roster.length,
      onPrevStudent: _roster.length > 1 ? () => _stepStudent(-1) : null,
      onNextStudent: _roster.length > 1 ? () => _stepStudent(1) : null,
      online: !s.isPaper,
      bookletFrom: _sample?.bookletFrom,
    );
    final actions = _actions(context, s);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 980) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 5, child: SingleChildScrollView(child: preview)),
            const SizedBox(width: AppSpace.lg),
            Expanded(flex: 4, child: ListView(padding: const EdgeInsets.only(bottom: AppSpace.lg), children: actions)),
          ]),
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        children: [preview, const SizedBox(height: AppSpace.md), ...actions],
      );
    });
  }

  List<Widget> _actions(BuildContext context, DeliverSource s) {
    final c = context.colors;
    final paper = s.isPaper;
    final showStudents = paper && _roster.isNotEmpty;
    final owed = paper ? deliverVersionsOwed(s.plan, s.versions.items.length) : null;
    final noOneToName = paper && s.hasCourse && s.plan?.personal == true && _scopeSettled && _roster.isEmpty && _rosterError == null;
    return [
      if (noOneToName)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
              key: const ValueKey('deliver.plan.noStudents'),
              icon: Icons.groups_outlined,
              text: t('خططت لنسخة لكل طالب، لكن لا يوجد طلاب مسجلون في هذا المقرر بعد. ستظهر النسخ الشخصية هنا عند تسجيلهم، ويمكنك حتى ذلك الحين طباعة نسخة عامة.',
                  'You planned a copy for each student, but no students are enrolled in this course yet. Personal copies appear here once they join; until then you can print a general copy.')),
        ),
      if (owed != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
              key: const ValueKey('deliver.plan.versions'),
              icon: Icons.shuffle_rounded,
              text: t('خططت لهذا الاختبار ${versionsCountText(owed)}، ولم تُنشأ بعد.', 'You planned ${versionsCountText(owed)} for this exam. They are not made yet.'),
              action: TextButton(onPressed: () => _versions(count: owed), child: Text(t('إنشاؤها', 'Make them')))),
        ),
      if (s.versions.stale)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(
              icon: Icons.warning_amber_rounded,
              color: c.warning,
              text: versionsStaleText,
              action: TextButton(onPressed: _versions, child: Text(t('إعادة الإنشاء', 'Regenerate')))),
        ),
      if (_rosterError != null && !s.versions.stale)
        Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _rosterError!)),
      if (!paper)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppBanner(icon: Icons.phone_iphone_rounded, text: t('هذا اختبار إلكتروني يؤديه الطلاب في التطبيق. الطباعة هنا للمراجعة أو كنسخة احتياطية.', 'This exam is taken in the app. Printing here is for review or as a backup.')),
        ),
      _Step(
        n: 1,
        title: t('راجع الورقة', 'Check the paper'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('الاستوديو يغيّر شكل الورقة فقط. لتغيير الأسئلة افتح محرر الأسئلة.', 'Studio changes how the paper looks. To change the questions, open the questions editor.'), style: AppType.meta(context).copyWith(height: 1.4)),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (!AppConfig.disableList.contains('exam.paper_designer')) AppButton.tonal(label: t('تعديل في الاستوديو', 'Edit in Studio'), icon: Icons.brush_rounded, onPressed: _studio),
            AppButton.ghost(label: t('تعديل الأسئلة', 'Edit the questions'), icon: Icons.edit_rounded, onPressed: _questions),
            AppButton.ghost(label: s.versions.items.isEmpty ? t('إنشاء نماذج', 'Make versions') : t('النماذج', 'Versions'), icon: Icons.shuffle_rounded, onPressed: _versions),
          ]),
          if (paper && s.hasCourse) ...[
            const SizedBox(height: AppSpace.sm),
            InkWell(
              key: const ValueKey('deliver.identifiers'),
              onTap: _identifiers,
              borderRadius: AppRadius.cardAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                child: Row(children: [
                  Icon(Icons.badge_outlined, size: AppIconSize.sm, color: c.textMedium),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(
                      child: Text(s.printed.isEmpty ? t('لم تحدد ما يُطبع تحت اسم الطالب', 'Nothing chosen to print under the name') : t('يُطبع: ${s.printed.map((p) => p.label).join('، ')}', 'Printed: ${s.printed.map((p) => p.label).join(', ')}'),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark))),
                  Text(t('تغيير', 'Change'), style: AppType.label(context).copyWith(color: appInk(context, c.primary), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ]),
      ),
      _Step(
        n: 2,
        title: t('اطبع', 'Print'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DeliverSummaryCard(
            summary: deliverPrintSummary(
                scope: _scope, format: paper ? s.format : AnswerFormat.online, booklet: _bookletOn, students: _roster.length, versions: s.versions.items.length, blank: _blank),
            bookletOffered: s.bookletOffered,
            booklet: _bookletOn,
            onBooklet: _printing
                ? null
                : (v) {
                    setState(() => _booklet = v);
                    _rebuildPreview();
                  },
          ),
          const SizedBox(height: AppSpace.sm),
          DeliverPrintCard(
          scope: _scope,
          onScope: (v) => setState(() {
            _scope = v;
            _scopeSettled = true;
          }),
          word: _word,
          onWord: (v) => setState(() => _word = v),
          studentCount: _roster.length,
          versionCount: s.versions.items.length,
          showStudents: showStudents,
          blank: _blank,
          onBlank: (v) => setState(() => _blank = v),
          busy: _printing,
          onPrint: _printing || s.versions.stale ? null : _print,
          onMore: _moreOptions,
        ),
        ]),
      ),
      if (paper && s.sheetPlan?.answerSheet == true && !AppConfig.disableList.contains(kExamAnswerSheetFeatureKey))
        _Step(
          n: 3,
          title: t('أوراق الإجابة الكتابية', 'Written answer sheets'),
          child: AnswerSheetPrintCard(
            plan: s.sheetPlan!,
            blank: _nb2Blank,
            onBlank: (v) => setState(() => _nb2Blank = v),
            busy: _nb2Busy,
            error: _nb2Error,
            onDownload: () => _answerSheets(s.sheetPlan!),
          ),
        ),
      // sheets the teacher already has are only read, never printed here (D-687)
      if (paper && s.bubble && s.sheetPlan?.bubble != BubbleSource.have && !AppConfig.disableList.contains(kExamOmrFeatureKey))
        _Step(
          n: paper && s.sheetPlan?.answerSheet == true ? 4 : 3,
          title: t('أوراق التظليل', 'Bubble answer sheets'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('يجيب الطلاب عليها، فاطبعها مع ورقة الأسئلة.', 'Students answer on these, so print them with the question paper.'), style: AppType.meta(context).copyWith(height: 1.4)),
            const SizedBox(height: AppSpace.xs),
            Align(alignment: AlignmentDirectional.centerStart, child: AppButton.tonal(label: t('طباعة أوراق التظليل', 'Print bubble sheets'), icon: Icons.grid_on_rounded, onPressed: () => showOmrSheetsSheet(context, examId: _id))),
          ]),
        ),
      ParentComponent(
        featureKey: kDeliverEmailFeatureKey,
        child: _Step(
          n: 3 + (paper && s.bubble && s.sheetPlan?.bubble != BubbleSource.have ? 1 : 0) + (paper && s.sheetPlan?.answerSheet == true ? 1 : 0),
          title: t('أرسل بالبريد', 'Send by email'),
          child: DeliverEmailCard(
            canStudents: showStudents,
            studentCount: _roster.length,
            noEmailNames: _email?.missingNames ?? const [],
            coverageKnown: _email != null && !_email!.unreadable && _email!.namesKnown,
            earlyWarning: earlyEmailWarning(s.view.exam.startsAt, DateTime.now().toUtc()),
            deliveries: _deliveries,
            onStudents: _emailStudents,
            onWhole: _emailWhole,
          ),
        ),
      ),
    ];
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.child});
  final int n;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // An editorial step numeral in the serif instead of a tinted dot: the steps read like a printed checklist.
          Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text('$n', style: AppType.headline(context).copyWith(color: appInk(context, c.primary))),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(title, style: AppType.section(context))),
          ]),
          const SizedBox(height: AppSpace.sm),
          child,
        ]),
      ),
    );
  }
}

/// The real pages: a page strip on a phone, a column on a wide screen; tap a page to see it large.
class DeliverPreviewPane extends StatefulWidget {
  const DeliverPreviewPane({
    super.key,
    required this.pages,
    required this.busy,
    this.versions = const [],
    this.version,
    this.onVersion,
    this.studentName,
    this.studentIndex = 0,
    this.studentCount = 0,
    this.onPrevStudent,
    this.onNextStudent,
    this.online = false,
    this.bookletFrom,
  });

  /// Where the answer booklet's pages start in [pages] (null = no booklet): the pane then offers Question paper / Booklet.
  final int? bookletFrom;

  /// Null while the first preview is being made.
  final List<ReplayedPage>? pages;
  final bool busy, online;
  final List<String> versions;
  final String? version;
  final ValueChanged<String?>? onVersion;
  final String? studentName;
  final int studentIndex, studentCount;
  final VoidCallback? onPrevStudent, onNextStudent;

  @override
  State<DeliverPreviewPane> createState() => _DeliverPreviewPaneState();
}

class _DeliverPreviewPaneState extends State<DeliverPreviewPane> {
  bool _showBooklet = false;

  void _zoom(ReplayedPage p) => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpace.md),
          child: InteractiveViewer(maxScale: 5, child: Center(child: ReplayedPageView(page: p))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = widget;
    final split = w.pages != null && w.bookletFrom != null && w.bookletFrom! > 0 && w.bookletFrom! < w.pages!.length ? w.bookletFrom : null;
    final showBooklet = split != null && _showBooklet;
    final pages = split == null ? w.pages : (showBooklet ? w.pages!.sublist(split) : w.pages!.sublist(0, split));
    final head = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('معاينة الورقة الحقيقية', 'The real paper'), style: AppType.section(context))),
        if (pages != null) AppStatusBadge(dense: true, label: countText(pages.length, ar1: 'صفحة', ar2: 'صفحتان', arFew: '{n} صفحات', arMany: '{n} صفحة', en1: '1 page', en: '{n} pages')),
      ]),
      if (w.studentName != null) ...[
        const SizedBox(height: AppSpace.xxs),
        Row(children: [
          IconButton(
              key: const ValueKey('deliver.prev'), tooltip: t('الطالب السابق', 'Previous student'), onPressed: w.onPrevStudent, icon: const Icon(Icons.chevron_left_rounded)),
          Expanded(
            child: Column(children: [
              Text(w.studentName!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: AppType.bodyStrong(context)),
              Text(t('نسخة ${w.studentIndex + 1} من ${w.studentCount}', 'Copy ${w.studentIndex + 1} of ${w.studentCount}'), style: AppType.meta(context).copyWith(color: c.textLight)),
            ]),
          ),
          IconButton(key: const ValueKey('deliver.next'), tooltip: t('الطالب التالي', 'Next student'), onPressed: w.onNextStudent, icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ] else ...[
        const SizedBox(height: AppSpace.xxs),
        Text(w.online ? t('هكذا ستبدو النسخة المطبوعة.', 'How the printed copy will look.') : t('نسخة فارغة، بلا اسم طالب.', 'A blank copy, no student name.'), style: AppType.meta(context)),
      ],
      if (split != null) ...[
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          AppChoiceChip(
              key: const ValueKey('deliver.preview.paper'),
              label: printDocLabel(PrintDoc.questionPaper),
              icon: Icons.description_outlined,
              selected: !showBooklet,
              onTap: () => setState(() => _showBooklet = false)),
          AppChoiceChip(
              key: const ValueKey('deliver.preview.booklet'),
              label: printDocLabel(PrintDoc.booklet),
              icon: Icons.menu_book_outlined,
              selected: showBooklet,
              onTap: () => setState(() => _showBooklet = true)),
        ]),
      ],
      if (w.versions.length > 1) ...[
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final v in w.versions) AppChoiceChip(label: '${t('نموذج', 'Version')} $v', selected: w.version == v, onTap: () => w.onVersion?.call(v)),
        ]),
      ],
      const SizedBox(height: AppSpace.sm),
    ]);
    // The paper lies on a sky "desk" block: the one memorable surface of this page, everything else is quiet paper cards.
    return AppBlock(tone: AppBlockTone.sky, padding: const EdgeInsets.all(AppSpace.md), child: LayoutBuilder(builder: (context, box) {
      final body = pages == null
          ? AspectRatio(aspectRatio: 0.72, child: AppSkeletonBox(radius: AppRadius.card, height: double.infinity))
          : pages.isEmpty
              ? AppEmpty(icon: Icons.broken_image_outlined, title: t('تعذّر عرض المعاينة', 'The preview could not be drawn'), message: t('الطباعة ما زالت تعمل.', 'Printing still works.'))
              : box.maxWidth >= 560
                  ? Column(children: [
                      for (final p in pages)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpace.sm),
                          child: InkWell(onTap: () => _zoom(p), child: ReplayedPageView(page: p)),
                        ),
                    ])
                  : SizedBox(
                      height: (box.maxWidth * 1.3).clamp(280.0, 520.0),
                      child: PageView.builder(
                        controller: PageController(viewportFraction: .92),
                        itemCount: pages.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                          child: Center(child: InkWell(onTap: () => _zoom(pages[i]), child: ReplayedPageView(page: pages[i]))),
                        ),
                      ),
                    );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head,
        AnimatedOpacity(opacity: w.busy ? .45 : 1, duration: AppMotion.of(context).base, child: body),
        if (w.busy && pages != null) ...[
          const SizedBox(height: AppSpace.xxs),
          Text(t('جارٍ تحديث المعاينة ...', 'Updating the preview ...'), textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: AppBlock.colorsOf(context).faint)),
        ],
      ]);
    }));
  }
}

class DeliverPrintCard extends StatelessWidget {
  const DeliverPrintCard({
    super.key,
    required this.scope,
    required this.onScope,
    required this.word,
    required this.onWord,
    required this.studentCount,
    required this.versionCount,
    required this.showStudents,
    required this.blank,
    required this.onBlank,
    required this.onPrint,
    required this.onMore,
    this.busy = false,
  });

  final DeliverScope scope;
  final ValueChanged<DeliverScope> onScope;
  final bool word, showStudents, busy;
  final ValueChanged<bool> onWord;
  final int studentCount, versionCount, blank;
  final ValueChanged<int> onBlank;
  final VoidCallback? onPrint;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fileWord = word ? 'Word' : 'PDF';
    final label = switch (scope) {
      DeliverScope.students => countText(studentCount,
          ar1: 'طباعة نسخة واحدة في ملف $fileWord', ar2: 'طباعة نسختين في ملف $fileWord واحد', arFew: 'طباعة {n} نسخ في ملف $fileWord واحد', arMany: 'طباعة {n} نسخة في ملف $fileWord واحد',
          en1: 'Print 1 copy in one $fileWord', en: 'Print {n} copies in one $fileWord'),
      DeliverScope.versions => versionCount > 1 ? t('طباعة كل النماذج في ملف $fileWord واحد', 'Print all versions in one $fileWord') : t('تنزيل ملف $fileWord', 'Download the $fileWord'),
      DeliverScope.blank => countText(blank,
          ar1: 'طباعة نسخة فارغة واحدة', ar2: 'طباعة نسختين فارغتين', arFew: 'طباعة {n} نسخ فارغة', arMany: 'طباعة {n} نسخة فارغة', en1: 'Print 1 blank copy', en: 'Print {n} blank copies'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        if (showStudents)
          AppChoiceChip(
              key: const ValueKey('deliver.scope.students'),
              label: t('نسخة لكل طالب ($studentCount)', 'A copy for each student ($studentCount)'),
              icon: Icons.groups_rounded,
              selected: scope == DeliverScope.students,
              onTap: () => onScope(DeliverScope.students)),
        AppChoiceChip(
            key: const ValueKey('deliver.scope.versions'),
            label: versionCount > 1 ? t('كل نموذج مرة', 'Each version once') : t('نسخة واحدة', 'One copy'),
            icon: Icons.layers_rounded,
            selected: scope == DeliverScope.versions,
            onTap: () => onScope(DeliverScope.versions)),
        AppChoiceChip(
            key: const ValueKey('deliver.scope.blank'),
            label: t('نسخ فارغة', 'Blank copies'),
            icon: Icons.note_outlined,
            selected: scope == DeliverScope.blank,
            onTap: () => onScope(DeliverScope.blank)),
      ]),
      if (scope == DeliverScope.blank)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Row(children: [
            Expanded(child: Text(t('عدد النسخ', 'Number of copies'), style: AppType.label(context))),
            IconButton(onPressed: blank > 1 ? () => onBlank(blank - 1) : null, icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: t('أقل', 'Less')),
            SizedBox(width: AppIconSize.hero, child: Text('$blank', textAlign: TextAlign.center, style: AppType.figure(context))),
            IconButton(onPressed: blank < 500 ? () => onBlank(blank + 1) : null, icon: const Icon(Icons.add_circle_outline_rounded), tooltip: t('أكثر', 'More')),
          ]),
        ),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppChoiceChip(key: const ValueKey('deliver.pdf'), label: t('PDF (الموصى به)', 'PDF (recommended)'), icon: Icons.picture_as_pdf_rounded, selected: !word, onTap: () => onWord(false)),
        AppChoiceChip(key: const ValueKey('deliver.word'), label: 'Word', icon: Icons.description_rounded, selected: word, onTap: () => onWord(true)),
      ]),
      if (word)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Text(t('Word يرتّب الصفحات بنفسه: راجع صفحات نسخة واحدة قبل طباعة الكل.', 'Word lays out the pages itself: check one copy before printing them all.'), style: AppType.meta(context).copyWith(color: c.textLight, height: 1.4)),
        ),
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(key: const ValueKey('deliver.print'), label: label, icon: Icons.print_rounded, busy: busy, onPressed: onPrint),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(key: const ValueKey('deliver.more'), onPressed: onMore, child: Text(t('خيارات أخرى: نموذج الإجابة، Excel، الغلاف', 'More: answer key, Excel, cover'))),
      ),
    ]);
  }
}

class DeliverEmailCard extends StatelessWidget {
  const DeliverEmailCard({
    super.key,
    required this.canStudents,
    required this.studentCount,
    required this.noEmailNames,
    required this.coverageKnown,
    required this.deliveries,
    required this.onStudents,
    required this.onWhole,
    this.earlyWarning,
  });

  final bool canStudents, coverageKnown;
  final int studentCount;
  final List<String> noEmailNames;
  final String? earlyWarning;
  final List<ExamDelivery> deliveries;
  final VoidCallback onStudents, onWhole;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget row(IconData icon, String title, String body, VoidCallback? tap, Key key) => InkWell(
          key: key,
          onTap: tap,
          borderRadius: AppRadius.cardAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Row(children: [
              Icon(icon, color: tap == null ? c.textLight : appInk(context, c.primary), size: AppIconSize.lg),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppType.bodyStrong(context).copyWith(color: tap == null ? c.textLight : c.textDark)),
                  const SizedBox(height: AppSpace.xxs),
                  Text(body, style: AppType.meta(context).copyWith(height: 1.4)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (earlyWarning != null) ...[
        AppBanner(icon: Icons.schedule_rounded, color: c.warning, text: earlyWarning!),
        const SizedBox(height: AppSpace.xs),
      ],
      if (canStudents)
        row(
            Icons.groups_rounded,
            t('لكل طالب نسخته', 'Each student gets their own copy'),
            !coverageKnown
                ? t('نخبرك بعد الإرسال بمن لا يملك بريدًا.', 'We will tell you after sending who has no email.')
                : noEmailNames.isEmpty
                    ? t('كل الطلاب لديهم بريد.', 'Every student has an email.')
                    : t('بلا بريد: ${namesText(noEmailNames)}', 'No email: ${namesText(noEmailNames)}'),
            onStudents,
            const ValueKey('deliver.email.students')),
      row(Icons.forward_to_inbox_rounded, t('الاختبار كاملًا إلى عنوان واحد', 'The whole exam to one address'), t('للجنة أو لزميل أو للمطبعة.', 'For a committee, a colleague or the print shop.'), onWhole,
          const ValueKey('deliver.email.whole')),
      if (deliveries.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Text(t('سجل الإرسال', 'Sent so far'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
        for (final d in deliveries.take(10)) DeliveryRow(delivery: d),
      ],
    ]);
  }
}

class DeliveryRow extends StatelessWidget {
  const DeliveryRow({super.key, required this.delivery});
  final ExamDelivery delivery;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = delivery;
    final tone = switch (d.status) { 'sent' => AppTone.success, 'partial' => AppTone.warning, 'failed' => AppTone.danger, _ => AppTone.info };
    final when = d.createdAt == null ? '' : AppTime.dateTime(d.createdAt!);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(d.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600))),
          const SizedBox(width: AppSpace.xs),
          AppStatusBadge(label: d.statusText, tone: tone, dense: true),
        ]),
        if (when.isNotEmpty || d.createdBy.isNotEmpty) Text([if (when.isNotEmpty) when, if (d.createdBy.isNotEmpty) d.createdBy].join(' · '), style: AppType.meta(context).copyWith(color: c.textLight)),
        if (d.failedText != null) Text(d.failedText!, key: const ValueKey('deliver.row.failed'), style: AppType.meta(context).copyWith(color: appInk(context, c.danger))),
        if (d.noEmail.isNotEmpty) Text(t('بلا بريد: ${namesText([for (final x in d.noEmail) x.name])}', 'No email: ${namesText([for (final x in d.noEmail) x.name])}'), style: AppType.meta(context).copyWith(color: c.warning)),
      ]),
    );
  }
}

/// Plain values of a long build.
class BuildProgress {
  const BuildProgress({required this.title, this.done = 0, this.total = 0});
  final String title;
  final int done, total;
  double get value => total <= 0 ? 0 : done / total;
}

class BuildProgressDialog extends StatelessWidget {
  const BuildProgressDialog({super.key, required this.progress, required this.onCancel});
  final BuildProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // Back must not close it: the build would carry on with no Cancel, and the `finally` that closes it would pop the page instead
    return PopScope(
      canPop: false,
      child: Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(progress.title, style: AppType.section(context)),
            const SizedBox(height: AppSpace.sm),
            AppProgressBar(value: progress.total <= 0 ? null : progress.value * 100, height: AppSpace.xs),
            const SizedBox(height: AppSpace.xs),
            Text(t('يعمل على هذا الجهاز، لا تغلق هذه الصفحة.', 'This runs on this device. Keep this page open.'), style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xs),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(key: const ValueKey('deliver.cancel'), onPressed: onCancel, child: Text(t('إلغاء', 'Cancel')))),
          ]),
        ),
      ),
      ),
    );
  }
}

enum EmailMode { students, whole }

class EmailCompose {
  const EmailCompose({this.to, this.message, this.word = false});
  final String? to, message;
  final bool word;
}

/// What goes out, to whom, and the honest warnings before it does.
class EmailComposeSheet extends StatefulWidget {
  const EmailComposeSheet({super.key, required this.mode, this.earlyWarning, this.count = 0, this.noEmailNames = const [], this.coverageKnown = false});
  final EmailMode mode;
  final String? earlyWarning;
  final int count;
  final List<String> noEmailNames;
  final bool coverageKnown;

  @override
  State<EmailComposeSheet> createState() => _EmailComposeSheetState();
}

class _EmailComposeSheetState extends State<EmailComposeSheet> {
  final _to = TextEditingController();
  final _message = TextEditingController();
  bool _word = false, _ack = false;

  @override
  void dispose() {
    _to.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final whole = widget.mode == EmailMode.whole;
    final address = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(_to.text.trim());
    final ready = (!whole || address) && (widget.earlyWarning == null || _ack);
    return AppSheetContent(title: whole ? t('إرسال الاختبار كاملًا', 'Send the whole exam') : t('إرسال نسخة لكل طالب', 'Send each student their copy'), children: [
      if (!whole)
        Text(t('تُنشأ نسخة كل طالب (${widget.count}) على هذا الجهاز ثم تُرفع وتُرسل. لا يبقى الملف على الخادم بعد الإرسال.',
            'Each student\'s copy (${widget.count}) is built on this device, uploaded and sent. The file is not kept on the server afterwards.'), style: AppType.label(context).copyWith(height: 1.5)),
      if (!whole && widget.coverageKnown && widget.noEmailNames.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        AppBanner(icon: Icons.mail_outline_rounded, color: c.warning, text: t('لن يصل إلى من لا بريد له: ${namesText(widget.noEmailNames)}', 'Will not reach those without an email: ${namesText(widget.noEmailNames)}')),
      ],
      if (whole) AppField(key: const ValueKey('deliver.to'), controller: _to, label: t('البريد الإلكتروني', 'Email address'), ltr: true, keyboard: TextInputType.emailAddress, onChanged: (_) => setState(() {})),
      const SizedBox(height: AppSpace.sm),
      AppField(controller: _message, label: t('رسالة قصيرة (اختياري)', 'A short note (optional)'), maxLines: 3),
      const SizedBox(height: AppSpace.sm),
      Wrap(spacing: AppSpace.xs, children: [
        AppChoiceChip(label: 'PDF', icon: Icons.picture_as_pdf_rounded, selected: !_word, onTap: () => setState(() => _word = false)),
        AppChoiceChip(label: 'Word', icon: Icons.description_rounded, selected: _word, onTap: () => setState(() => _word = true)),
      ]),
      if (widget.earlyWarning != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.schedule_rounded, color: c.warning, text: widget.earlyWarning!),
        AppSwitchTile(key: const ValueKey('deliver.ack'), title: t('أفهم ذلك، أرسل قبل الموعد', 'I understand, send before the start'), value: _ack, dense: true, onChanged: (v) => setState(() => _ack = v)),
      ],
      const SizedBox(height: AppSpace.sm),
      AppPrimaryButton(
          key: const ValueKey('deliver.send'),
          label: t('إرسال', 'Send'),
          icon: Icons.send_rounded,
          onPressed: ready ? () => Navigator.of(context).pop(EmailCompose(to: _to.text.trim(), message: _message.text.trim(), word: _word)) : null),
    ]);
  }
}
