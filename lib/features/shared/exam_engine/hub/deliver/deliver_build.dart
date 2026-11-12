// Exam Hub, delivery: everything that turns an exam into files. Loads the exam exactly as the print sheet prints it (the
// saved design, the cover, the template, the pictures), and builds the sample copy, the all-in-one files and the per-student
// emails, each question paper followed by its answer booklet when the booklet is on (D-663). Long builds run paper by paper through a PaperBuildControl (progress and cancel); see exam_paper_pdf.dart.
library;

import 'dart:math' as math;
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
import '../../exam_paper_sheet.dart' show examPaperOrgOf, fetchPaperLogo, printableImage, buildPaperCopies, PaperCopiesResult, kMaxQrPages, qrPagesWarningText;
import '../../exam_quick.dart' show paperFileOf;
import '../../exam_versions.dart';
import '../../paper/exam_setup.dart';
import '../../paper/omr_counts.dart' show omrMinutesText;
import '../create/answer_format.dart';
import '../create/answer_sheet_plan.dart' show SheetPlan;
import 'deliver_logic.dart';
import 'paper_page_replay.dart';

const _kTemplate = 'exam_paper.template', _kInstitution = 'exam_paper.institution';

/// A blank, printable sample: the name that stands in for a real student on the preview.
String get sampleStudentName => t('اسم الطالب', 'Student name');

/// Everything delivery needs about one exam.
class DeliverSource {
  DeliverSource({required this.view, required this.base, required this.tpl, required this.versions, required this.regular, required this.bold,
      required this.delivery, required this.bubble, required this.printed, this.format = AnswerFormat.onPaper, this.bookletDefault = false, this.design, this.cover, this.designVersion = 0, this.identifier, this.orgId, this.hasCourse = false, this.plan, this.sheetPlan});
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

  /// The answer sheets the wizard planned (`settings.sheet_plan`, D-687); null on an exam made any other way.
  final SheetPlan? sheetPlan;

  /// The exam uses bubble answer sheets.
  final bool bubble;
  final List<PrintedIdSpec> printed;
  final LayoutDocument? design;
  final PaperCoverSpec? cover;
  final int designVersion;
  final IdentifierChoice? identifier;
  final int? orgId;
  final bool hasCourse;

  /// How the students answer (`settings.answer_format`, or what the setup implies), and whether the booklet starts on.
  final AnswerFormat format;
  final bool bookletDefault;

  bool get isPaper => delivery == 'paper';
  List<PaperPrintedId> get blankLabels => [for (final p in printed) p.blank];

  /// An answer booklet can go with this paper (D-663).
  bool get bookletOffered => isPaper && deliverBookletOffered(format);

  /// [d] as the question paper: without answer room beside a booklet, with the answer table at the end for a table exam.
  ExamPaperDoc paperOf(ExamPaperDoc d, {required bool booklet}) {
    final l = deliverPaperLayout(isPaper ? format : AnswerFormat.online, booklet: booklet && bookletOffered);
    return d.copyWith(part: l.part, answerTable: l.table);
  }

  /// [d] as its answer booklet (no cover: that belongs to the question paper).
  ExamPaperDoc bookletOf(ExamPaperDoc d) => d.copyWith(part: PaperPart.booklet, answerTable: AnswerTablePlace.none, dropCover: true);
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
  final settings = r.map['settings'] is Map ? r.map['settings'] as Map : const {};
  final format = deliverAnswerFormat(settings, paper: setup?.delivery == 'paper', bubble: setup?.isBubble ?? false);
  return DeliverLoad.ok(DeliverSource(
    view: view,
    base: d,
    tpl: tpl,
    versions: versions,
    regular: fonts[0],
    bold: fonts[1],
    delivery: setup?.delivery ?? 'online',
    plan: DeliverPlan.ofSettings(r.map['settings']),
    sheetPlan: SheetPlan.ofSettings(r.map['settings']),
    bubble: setup?.isBubble ?? false,
    printed: results[1].ok ? printedIdsOfSetup(results[1].map) : const [],
    format: format,
    bookletDefault: deliverBookletDefault(format, settings),
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
  const SampleCopy(this.pages, this.studentName, this.version, {this.bookletFrom});
  final List<ReplayedPage> pages;

  /// The index of the booklet's first page in [pages]; null without a booklet.
  final int? bookletFrom;
  final String studentName;
  final String? version;

  void dispose() {
    for (final p in pages) {
      p.dispose();
    }
  }
}

/// The sample copy of [version] (null = the first, or the exam's own order) for [student] (null = a blank one).
Future<SampleCopy> buildSample(DeliverSource s, {String? version, PrintPlanItem? student, required ExamVersionsApi api, required int examId, bool booklet = false}) async {
  // a student's own version by default: the preview is that student's real copy
  final code = version ?? student?.form ?? (s.versions.items.isEmpty ? null : s.versions.items.first.code);
  final v = s.versions.byCode(code);
  final base = v == null ? s.base : applyVersion(s.base, v);
  final withBooklet = booklet && s.bookletOffered;
  final paper = s.paperOf(base, booklet: withBooklet);
  final ids = student?.identifiers ?? s.blankLabels;
  ExamPaperDoc boxed(ExamPaperDoc d) => ids.isEmpty ? d : ExamPaperCopy.of(d, ids);
  // the count pass reserves the QR's room and the same boxes the real copy will have
  Future<int> count(ExamPaperDoc d) async => (await examPaperPdfMany([boxed(d.copyWith(qrSlots: 1))], s.tpl, regular: s.regular, bold: s.bold)).pages.first;
  final pages = await count(paper);
  final bookPages = withBooklet ? await count(s.bookletOf(base)) : 0;
  var qr = const <String>[];
  if (s.isPaper) {
    final r = await api.printPlan(examId,
        printPlanBody(named: student != null, studentIds: student == null ? null : [student.studentId!], copies: 1, pages: pages + bookPages, form: code));
    if (r.ok) {
      final items = PrintPlan.fromJson(r.map).items;
      if (items.isNotEmpty) qr = items.first.pages;
    }
  }
  final (qa, qb) = splitBookletQr(qr, pages, bookPages);
  ExamPaperDoc copyOf(ExamPaperDoc d, List<String> q) => boxed(d.copyWith(studentName: student?.studentName ?? '', qrPages: q, qrSlots: q.isEmpty ? 1 : 0));
  final docs = [copyOf(paper, qa), if (withBooklet) copyOf(s.bookletOf(base), qb)];
  final out = await examPaperPdfMany(docs, s.tpl, regular: s.regular, bold: s.bold);
  final replayed = await replayPdfPages(out.document!);
  return SampleCopy(replayed, student?.studentName ?? '', code, bookletFrom: withBooklet && out.pages.length > 1 ? replayed.length - out.pages[1] : null);
}

/// Each version's own page counts (question paper, booklet), laid out with the boxes and the QR room the real copies carry.
Future<Map<String?, (int, int)>> deliverPageCounts(DeliverSource s, List<String?> codes, {required bool word, required bool booklet}) async {
  final out = <String?, (int, int)>{};
  Future<int> count(ExamPaperDoc d) async {
    var x = d.copyWith(qrSlots: 1);
    if (s.blankLabels.isNotEmpty) x = ExamPaperCopy.of(x, s.blankLabels);
    // Word lays itself out: its page count is the writer's own split, not the PDF's
    return word ? wordPageCount(x, s.tpl) : (await examPaperPdfMany([x], s.tpl, regular: s.regular, bold: s.bold)).pages.first;
  }

  for (final code in codes) {
    final v = s.versions.byCode(code);
    final base = v == null ? s.base : applyVersion(s.base, v);
    out[code] = (await count(s.paperOf(base, booklet: booklet)), booklet && s.bookletOffered ? await count(s.bookletOf(base)) : 0);
  }
  return out;
}

/// The plan's copies as documents: each question paper, then its booklet when the version has one, one copy's QR payloads
/// split between the two.
List<ExamPaperDoc> deliverPlanDocs(DeliverSource s, PrintPlan plan, Map<String?, (int, int)> pages, {required bool booklet}) {
  final out = <ExamPaperDoc>[];
  final paperBase = s.paperOf(s.base, booklet: booklet);
  for (final item in plan.items) {
    final (p, b) = pages[item.form] ?? (pages.isEmpty ? (item.pages.length, 0) : pages.values.first);
    final (qa, qb) = splitBookletQr(item.pages, p, b);
    out.add(copiesFor(paperBase, PrintPlan([item]), s.versions, blankIds: s.blankLabels).first.copyWith(qrPages: qa));
    if (booklet && s.bookletOffered) out.add(copiesFor(s.bookletOf(s.base), PrintPlan([item]), s.versions, blankIds: s.blankLabels).first.copyWith(qrPages: qb));
  }
  return out;
}

List<String?> _codes(DeliverSource s) => <String?>[if (s.versions.items.isEmpty) null else ...s.versions.items.map((v) => v.code)];

/// Every version once, one file (a single paper when the exam has no versions). [labels] leave the boxes to write in.
Future<Uint8List> buildAllVersionsFile(DeliverSource s, {required bool word, PaperBuildControl? control, bool booklet = false}) async {
  final withBooklet = booklet && s.bookletOffered;
  final docs = <ExamPaperDoc>[
    for (final d in [if (s.versions.items.isEmpty) s.base else for (final v in s.versions.items) applyVersion(s.base, v)]) ...[
      s.paperOf(d, booklet: withBooklet),
      if (withBooklet) s.bookletOf(d),
    ],
  ];
  final labelled = [for (final d in docs) s.blankLabels.isEmpty ? d : ExamPaperCopy.of(d, s.blankLabels)];
  if (word) return examPaperDocxMany(labelled, s.tpl, control: control);
  return (await examPaperPdfMany(labelled, s.tpl, regular: s.regular, bold: s.bold, control: control)).bytes;
}

/// One personal copy per student (versions rotate down the class) or [blank] blank copies, in one file.
Future<PaperCopiesResult> buildClassFile(DeliverSource s, int examId,
    {required bool word, required bool named, List<int> studentIds = const [], int blank = 1, required ExamVersionsApi api, PaperBuildControl? control, bool booklet = false}) async {
  final withBooklet = booklet && s.bookletOffered;
  if (!withBooklet) {
    return buildPaperCopies(
        base: s.paperOf(s.base, booklet: false), versions: s.versions, api: api, examId: examId, tpl: s.tpl, regular: s.regular, bold: s.bold, named: named,
        studentIds: studentIds, blank: blank, word: word, printedLabels: s.blankLabels, control: control);
  }
  // one print-plan copy per student holds the QR payloads of the paper's pages AND the booklet's
  final pages = await deliverPageCounts(s, _codes(s), word: word, booklet: true);
  final maxPages = pages.values.fold(1, (m, x) => math.max(m, x.$1 + x.$2));
  final r = await api.printPlan(examId, printPlanBody(named: named, studentIds: named ? studentIds : null, copies: blank, pages: maxPages));
  if (!r.ok) return PaperCopiesResult(error: versionsErrorText(r));
  final plan = PrintPlan.fromJson(r.map);
  if (plan.items.isEmpty) return PaperCopiesResult(error: t('لا توجد نسخ للطباعة', 'There are no copies to print'));
  final docs = deliverPlanDocs(s, plan, pages, booklet: true);
  if (word) return PaperCopiesResult(bytes: await examPaperDocxMany(docs, s.tpl, control: control), copies: plan.items.length);
  final out = await examPaperPdfMany(docs, s.tpl, regular: s.regular, bold: s.bold, control: control);
  var mismatch = out.pages.length != docs.length || maxPages > kMaxQrPages;
  for (var i = 0; !mismatch && i < out.pages.length; i++) {
    if (out.pages[i] != docs[i].qrPages.length) mismatch = true;
  }
  return PaperCopiesResult(bytes: out.bytes, copies: plan.items.length, pages: out.pages.fold(0, (a, b) => a + b), warning: mismatch ? qrPagesWarningText : null);
}

/// What a per-student email run did.
class StudentsSendResult {
  const StudentsSendResult({this.sent = 0, this.batches = 0, this.error, this.cancelled = false});
  final int sent, batches;
  final String? error;
  final bool cancelled;
}

/// Builds each student's own copy on this device and uploads them in rounds (a round holds at most [kDeliverRoundBytes] or 100 copies,
/// and is uploaded before the next one is built, so a large class never sits in memory).
Future<StudentsSendResult> sendPerStudentCopies(DeliverSource s, int examId, List<PrintPlanItem> students,
    {required bool word, String? message, required ExamVersionsApi api, required ExamDeliverApi deliver, required PaperBuildControl control, void Function(String stage)? onStage,
    bool booklet = false}) async {
  final withBooklet = booklet && s.bookletOffered;
  final pages = await deliverPageCounts(s, _codes(s), word: word, booklet: withBooklet);
  final maxPages = pages.values.fold(1, (m, x) => math.max(m, x.$1 + x.$2));
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
      final docs = deliverPlanDocs(s, PrintPlan([item]), pages, booklet: withBooklet);
      final Uint8List b = word ? await examPaperDocxMany(docs, s.tpl) : (await examPaperPdfMany(docs, s.tpl, regular: s.regular, bold: s.bold)).bytes;
      if (b.length > 20 * 1024 * 1024) return StudentsSendResult(sent: sent, batches: batches, error: deliverCodeText('delivery_file_too_large'));
      if (round.isNotEmpty && (bytes + b.length > kDeliverRoundBytes || round.length >= 100)) {
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
