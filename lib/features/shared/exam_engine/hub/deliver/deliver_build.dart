// Exam Hub, delivery: everything that turns an exam into files. Loads the exam exactly as the print sheet prints it (the
// saved design, the cover, the template, the pictures), and builds the sample copy, the all-in-one files and the per-student
// emails. Long builds run paper by paper through a PaperBuildControl (progress and cancel); see exam_paper_pdf.dart.
library;

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../admin/admin_common.dart' show t;
import '../../../../../design/export_layout/layout_model.dart' show LayoutDocument;
import '../../exam_authoring.dart' show ExamAuthoringApi, ExamView, authoringError;
import '../../exam_media.dart' show bankQuestionBytes;
import '../../exam_paper.dart';
import '../../exam_paper_bands.dart' show ExamPaperCopy, PaperPrintedId;
import '../../exam_paper_design_api.dart';
import '../../exam_paper_designer.dart' show paperWithDesign, resolvePaperAssets, paperSampleRow;
import '../../exam_paper_docx.dart';
import '../../exam_paper_pdf.dart';
import '../../exam_paper_sheet.dart' show examPaperOrgOf, fetchPaperLogo, printableImage, buildPaperCopies, PaperCopiesResult;
import '../../exam_quick.dart' show paperFileOf;
import '../../exam_versions.dart';
import '../../paper/exam_setup.dart';
import '../../paper/omr_counts.dart' show omrMinutesText;
import 'deliver_logic.dart';
import 'paper_page_replay.dart';

const _kTemplate = 'exam_paper.template', _kInstitution = 'exam_paper.institution';

/// A blank, printable sample: the name that stands in for a real student on the preview.
String get sampleStudentName => t('اسم الطالب', 'Student name');

/// Everything delivery needs about one exam.
class DeliverSource {
  DeliverSource({required this.view, required this.base, required this.tpl, required this.versions, required this.regular, required this.bold,
      required this.delivery, required this.bubble, required this.printed, this.design, this.cover, this.designVersion = 0, this.identifier, this.orgId, this.hasCourse = false, this.plan});
  final ExamView view;

  /// The exam's paper with the design and every picture applied, in the exam's own order.
  final ExamPaperDoc base;
  final PaperTemplate tpl;
  final ExamVersions versions;
  final ByteData regular, bold;

  /// online | paper.
  final String delivery;

  /// What the wizard planned (`settings.paper_plan`); null on an exam made any other way.
  final DeliverPlan? plan;

  /// The exam uses bubble answer sheets.
  final bool bubble;
  final List<PrintedIdSpec> printed;
  final LayoutDocument? design;
  final PaperCoverSpec? cover;
  final int designVersion;
  final IdentifierChoice? identifier;
  final int? orgId;
  final bool hasCourse;

  bool get isPaper => delivery == 'paper';
  List<PaperPrintedId> get blankLabels => [for (final p in printed) p.blank];
}

/// `load`: the exam can be delivered, else a [message] (and maybe [noQuestions] / [fileExam]).
class DeliverLoad {
  const DeliverLoad.ok(DeliverSource this.source) : message = null, noQuestions = false, fileExam = false;
  const DeliverLoad.fail(String this.message, {this.noQuestions = false, this.fileExam = false}) : source = null;
  final DeliverSource? source;
  final String? message;
  final bool noQuestions, fileExam;
}

Future<DeliverLoad> loadDeliverSource(int examId, {required String accentFallback, String course = '', ExamVersionsApi? versionsApi, ExamSetupApi? setupApi, ExamPaperDesignApi? designApi}) async {
  final r = await ExamAuthoringApi().exam(examId);
  if (!r.ok) return DeliverLoad.fail(authoringError(r));
  final view = ExamView.fromJson(r.map);
  if (paperFileOf(r.map) != null) return DeliverLoad.fail(t('هذا الاختبار ملف مرفوع، نزّله واطبعه من صفحة النتائج.', 'This exam is an uploaded file. Download and print it from the results page.'), fileExam: true);
  if (view.questionCount == 0) return DeliverLoad.fail(t('لا توجد أسئلة بعد. أضف أسئلة ثم ارجع هنا.', 'There are no questions yet. Add some, then come back here.'), noQuestions: true);
  final vApi = versionsApi ?? ExamVersionsApi();
  final sApi = setupApi ?? ExamSetupApi();
  final dApi = designApi ?? ExamPaperDesignApi();
  final results = await Future.wait([vApi.versions(examId), sApi.setup(examId)]);
  final designOn = !AppConfig.disableList.contains('exam.paper_designer');
  final pd = designOn ? await dApi.load(examId) : null;
  final setup = results[1].ok ? ExamSetup.fromJson(results[1].map) : null;
  final versions = results[0].ok ? ExamVersions.fromJson(results[0].map) : const ExamVersions();
  final rtl = AppConfig.lang == 'ar';
  final org = examPaperOrgOf(view.exam.orgId);
  final logo = await fetchPaperLogo(org['logo_url'] as String?);
  var institution = rtl ? '${org['name_ar'] ?? org['name_en'] ?? ''}' : '${org['name_en'] ?? org['name_ar'] ?? ''}';
  PaperTemplate tpl = PaperTemplate.auto;
  try {
    final p = await SharedPreferences.getInstance();
    final name = p.getString(_kTemplate);
    tpl = PaperTemplate.values.firstWhere((x) => x.name == name, orElse: () => PaperTemplate.auto);
    if (institution.isEmpty) institution = p.getString(_kInstitution) ?? '';
  } catch (_) {}
  // a custom Word template cannot make the PDF these screens are built on: it stays a choice of the print sheet
  if (tpl == PaperTemplate.custom) tpl = PaperTemplate.auto;
  tpl = resolvePaperTemplate(tpl, highStakes: view.exam.highStakes);
  final brand = '${org['color'] ?? ''}'.replaceAll('#', '');
  final accent = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(brand)
      ? brand.toUpperCase()
      : accentFallback;
  var d = ExamPaperDoc.fromView(view,
      institution: institution,
      course: course,
      dateText: view.exam.startsAt == null ? '' : AppTime.date(view.exam.startsAt!),
      instructions: defaultPaperInstructions(rtl: rtl, questions: view.questionCount, duration: view.exam.durationMinutes == null ? '' : omrMinutesText(view.exam.durationMinutes!)),
      rtl: rtl,
      logo: logo,
      accentHex: accent);
  if (pd != null && !pd.isEmpty) {
    final raw = await resolvePaperAssets([pd.document, pd.cover?.design]);
    final assets = <String, Uint8List>{};
    for (final e in raw.entries) {
      final b = printableImage(e.value);
      if (b != null) assets[e.key] = b;
    }
    d = paperWithDesign(d, design: pd.document, cover: pd.cover, assets: assets);
  }
  d = await attachPaperImages(d, bankQuestionBytes);
  final style = PaperStyle.of(tpl);
  final fonts = await Future.wait([rootBundle.load(style.regular), rootBundle.load(style.bold)]);
  return DeliverLoad.ok(DeliverSource(
    view: view,
    base: d,
    tpl: tpl,
    versions: versions,
    regular: fonts[0],
    bold: fonts[1],
    delivery: setup?.delivery ?? 'online',
    plan: DeliverPlan.ofSettings(r.map['settings']),
    bubble: setup?.isBubble ?? false,
    printed: results[1].ok ? printedIdsOfSetup(results[1].map) : const [],
    design: pd?.document,
    cover: pd?.cover,
    designVersion: pd?.version ?? 0,
    identifier: setup?.identifier,
    orgId: view.exam.orgId,
    hasCourse: view.exam.courseId != null,
  ));
}

/// The design block's sample row (the real paper's values).
Map<String, Object?> deliverDesignerSample(DeliverSource s, {List<PaperPrintedId> identifiers = const []}) => paperSampleRow(
    institution: s.base.institution, course: s.base.course, title: s.base.title, date: s.base.dateText, duration: s.base.durationText,
    total: '${s.base.total}', instructions: s.base.instructions.join('\n'), university: s.cover?.university ?? '', identifiers: identifiers);

/// The whole class: every student's name, printed identifiers and version from one plan call. Empty (and no error)
/// for an exam with no course. A stale version answers its error text in [PlanRoster.error].
class PlanRoster {
  const PlanRoster(this.items, [this.error]);
  final List<PrintPlanItem> items;
  final String? error;
}

Future<PlanRoster> loadPlanRoster(int examId, ExamVersionsApi api) async {
  final r = await api.printPlan(examId, printPlanBody(named: true, pages: 1));
  if (!r.ok) return PlanRoster(const [], versionsErrorText(r));
  return PlanRoster(PrintPlan.fromJson(r.map).items);
}

/// A real sample copy: laid out to count its pages, its QR codes asked for, drawn into pages.
class SampleCopy {
  const SampleCopy(this.pages, this.studentName, this.version);
  final List<ReplayedPage> pages;
  final String studentName;
  final String? version;

  void dispose() {
    for (final p in pages) {
      p.dispose();
    }
  }
}

/// The sample copy of [version] (null = the first, or the exam's own order) for [student] (null = a blank one).
Future<SampleCopy> buildSample(DeliverSource s, {String? version, PrintPlanItem? student, required ExamVersionsApi api, required int examId}) async {
  // a student's own version by default: the preview is that student's real copy
  final code = version ?? student?.form ?? (s.versions.items.isEmpty ? null : s.versions.items.first.code);
  final v = s.versions.byCode(code);
  final base = v == null ? s.base : applyVersion(s.base, v);
  final ids = student?.identifiers ?? s.blankLabels;
  // the count pass reserves the QR's room and the same boxes the real copy will have
  ExamPaperDoc fitted = base.copyWith(qrSlots: 1);
  if (ids.isNotEmpty) fitted = ExamPaperCopy.of(fitted, ids);
  final count = (await examPaperPdfMany([fitted], s.tpl, regular: s.regular, bold: s.bold)).pages.first;
  var qr = const <String>[];
  if (s.isPaper) {
    final r = await api.printPlan(examId, printPlanBody(named: student != null, studentIds: student == null ? null : [student.studentId!], copies: 1, pages: count, form: code));
    if (r.ok) {
      final items = PrintPlan.fromJson(r.map).items;
      if (items.isNotEmpty) qr = items.first.pages;
    }
  }
  ExamPaperDoc copy = base.copyWith(studentName: student?.studentName ?? '', qrPages: qr, qrSlots: qr.isEmpty ? 1 : 0);
  if (ids.isNotEmpty) copy = ExamPaperCopy.of(copy, ids);
  final out = await examPaperPdfMany([copy], s.tpl, regular: s.regular, bold: s.bold);
  return SampleCopy(await replayPdfPages(out.document!), student?.studentName ?? '', code);
}

/// Every version once, one file (a single paper when the exam has no versions). [labels] leave the boxes to write in.
Future<Uint8List> buildAllVersionsFile(DeliverSource s, {required bool word, PaperBuildControl? control}) async {
  final docs = <ExamPaperDoc>[
    if (s.versions.items.isEmpty) s.base else for (final v in s.versions.items) applyVersion(s.base, v),
  ];
  final labelled = [for (final d in docs) s.blankLabels.isEmpty ? d : ExamPaperCopy.of(d, s.blankLabels)];
  if (word) return examPaperDocxMany(labelled, s.tpl, control: control);
  return (await examPaperPdfMany(labelled, s.tpl, regular: s.regular, bold: s.bold, control: control)).bytes;
}

/// One personal copy per student (versions rotate down the class) or [blank] blank copies, in one file.
Future<PaperCopiesResult> buildClassFile(DeliverSource s, int examId,
        {required bool word, required bool named, List<int> studentIds = const [], int blank = 1, required ExamVersionsApi api, PaperBuildControl? control}) =>
    buildPaperCopies(
        base: s.base, versions: s.versions, api: api, examId: examId, tpl: s.tpl, regular: s.regular, bold: s.bold, named: named, studentIds: studentIds, blank: blank, word: word,
        printedLabels: s.blankLabels, control: control);

/// What a per-student email run did.
class StudentsSendResult {
  const StudentsSendResult({this.sent = 0, this.batches = 0, this.error, this.cancelled = false});
  final int sent, batches;
  final String? error;
  final bool cancelled;
}

/// Builds each student's own copy on this device and uploads them in rounds (a round holds at most 25 MB or 100 copies,
/// and is uploaded before the next one is built, so a large class never sits in memory).
Future<StudentsSendResult> sendPerStudentCopies(DeliverSource s, int examId, List<PrintPlanItem> students,
    {required bool word, String? message, required ExamVersionsApi api, required ExamDeliverApi deliver, required PaperBuildControl control, void Function(String stage)? onStage}) async {
  final codes = <String?>[if (s.versions.items.isEmpty) null else ...s.versions.items.map((v) => v.code)];
  final pagesOf = <String?, int>{};
  for (final code in codes) {
    final v = s.versions.byCode(code);
    var doc = (v == null ? s.base : applyVersion(s.base, v)).copyWith(qrSlots: 1);
    if (s.blankLabels.isNotEmpty) doc = ExamPaperCopy.of(doc, s.blankLabels);
    pagesOf[code] = word ? wordPageCount(doc, s.tpl) : (await examPaperPdfMany([doc], s.tpl, regular: s.regular, bold: s.bold)).pages.first;
  }
  final maxPages = pagesOf.values.fold(1, (m, x) => x > m ? x : m);
  final plan = await api.printPlan(examId, printPlanBody(named: true, studentIds: [for (final x in students) x.studentId!], pages: maxPages));
  if (!plan.ok) return StudentsSendResult(error: deliverErrorText(plan));
  final items = PrintPlan.fromJson(plan.map).items;
  var sent = 0, batches = 0, bytes = 0;
  final ext = word ? 'docx' : 'pdf';
  var round = <int, Uint8List>{};
  Future<String?> flush() async {
    if (round.isEmpty) return null;
    onStage?.call(t('جارٍ إرسال الدفعة ${batches + 1} ...', 'Uploading round ${batches + 1} ...'));
    final r = await deliver.sendStudents(examId, round, ext: ext, message: message);
    if (!r.ok) return deliverErrorText(r);
    sent += round.length;
    batches++;
    round = {};
    bytes = 0;
    return null;
  }

  try {
    onStage?.call(t('جارٍ إنشاء النسخ على هذا الجهاز ...', 'Building the copies on this device ...'));
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final doc = copiesFor(s.base, PrintPlan([item]), s.versions, pagesOf: pagesOf).first;
      final Uint8List b = word ? examPaperDocx(doc, s.tpl) : (await examPaperPdfMany([doc], s.tpl, regular: s.regular, bold: s.bold)).bytes;
      if (b.length > 20 * 1024 * 1024) return StudentsSendResult(sent: sent, batches: batches, error: deliverCodeText('delivery_file_too_large'));
      if (round.isNotEmpty && (bytes + b.length > 25 * 1024 * 1024 || round.length >= 100)) {
        final e = await flush();
        if (e != null) return StudentsSendResult(sent: sent, batches: batches, error: e);
      }
      round[item.studentId!] = b;
      bytes += b.length;
      await control.tick(i + 1, items.length);
    }
    final e = await flush();
    return StudentsSendResult(sent: sent, batches: batches, error: e);
  } on PaperBuildCancelled {
    return StudentsSendResult(sent: sent, batches: batches, cancelled: true);
  }
}
