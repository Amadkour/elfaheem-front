// The "New exam" wizard of the Exam Hub, pure part: what the teacher has chosen so far, which steps that means, what
// each step says in the summary, and the problems stated before they bite. No widget and no call lives here.
//
// Order (D-661): Where (a course, an organization or personal) → Answers (how students answer: online, on the paper, an
// answer table or a bubble sheet) → Questions (automatic, manual, a file or Google Forms) → Template (bubble only) →
// Settings (timing, or how the papers are printed) → Answer sheets (D-687: personal or generic, only when NextBrain prints
// a bubble sheet or an NB2 written-answer sheet) → Students (the identifier plan, where a paper is matched to a student;
// with no course, the uploaded list). The answer format comes first because it decides which questions are possible: a
// bubble sheet holds only multiple choice and true / false (written questions then go on the NB2 sheet).
//
// Unit-tested in test/org/exam_hub_f2_test.dart.
library;

import '../../../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/plural.dart';

import '../../exam_all.dart' show NewExamPlace;
import '../../exam_authoring.dart' show fmtPoints;
import '../../exam_quick.dart';
import '../../paper/exam_setup.dart' show ObjectiveQuestion, OmrTemplateItem;
import '../../paper/omr_counts.dart' show omrMinutesText;
import 'answer_format.dart';
import 'answer_sheet_plan.dart';

export 'answer_format.dart';
export 'answer_sheet_plan.dart';

/// `publish` is the Settings step: the publishing itself is the wizard's last press.
/// `sheets` is the answer sheets (D-687): personal or generic, for the bubble sheet and the NB2 written-answer sheet.
enum CreateStep { where, answer, questions, template, publish, sheets, identify }

enum CreateType { normal, bubble }

enum PublishKind { electronic, paper }

/// One printed exam per version, or a paper named for each student.
enum PaperPlan { versions, personal }

/// The question types a bubble can hold, in the order of the "add a question" row.
const kBubbleQuestionTypes = <String>['mcq_single', 'true_false'];

/// Added beside them in a bubble exam while the NB2 sheet is on: they go on the written-answer sheet (a number is a
/// kind of open answer, picked on the card).
const kWrittenQuestionTypes = <String>['short_answer', 'essay'];

/// How the printed versions are told apart. QR is what the scanner reads; the printed code is for people. Not "bubble":
/// not every sheet has a version row to shade.
const kVersionMarkers = <String>['qr', 'printed'];

String questionsCountText(int n) =>
    countText(n, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالًا', en1: '1 question', en: '{n} questions');

String versionsCountText(int n) =>
    countText(n, ar1: 'نموذج واحد', ar2: 'نموذجان', arFew: '{n} نماذج', arMany: '{n} نموذجًا', en1: '1 version', en: '{n} versions');

/// "5 marks" with Arabic's forms; a fraction takes the singular.
String marksCountText(double v) => v == v.roundToDouble()
    ? countText(v.toInt(), ar1: 'درجة واحدة', ar2: 'درجتان', arFew: '{n} درجات', arMany: '{n} درجة', en1: '1 mark', en: '{n} marks')
    : t('${fmtPoints(v)} درجة', '${fmtPoints(v)} marks');

/// A question a bubble sheet can carry.
bool bubbleCanHold(String type) => ObjectiveQuestion.types.contains(type);

class ExamCreatePlan {
  ExamCreatePlan({NewExamPlace? place, String? title})
      : place = place,
        exam = QuickExam(kind: QuickKind.quiz, courseId: place?.courseId, orgId: place?.orgId, title: title);

  NewExamPlace? place;
  QuickExam exam;
  /// How students answer; [type] and [publish] follow it.
  AnswerFormat? answer;
  CreateType? type;
  OmrTemplateItem? template;
  PublishKind? publish;
  PaperPlan paperPlan = PaperPlan.versions;
  int versions = 1;
  bool shuffleQuestions = true;
  bool shuffleOptions = true;

  // the answer sheets (D-687)
  BubbleSource bubbleSource = BubbleSource.print;
  /// Null = the default: personal with a course, generic without.
  SheetCopies? copies;
  IdSource idSource = IdSource.academic;
  /// The NB2 sheet is on offer (`exam.answer_sheet`); the wizard sets it from the kill switch.
  bool answerSheetOn = true;
  /// Students on the uploaded list (an exam with no course).
  int peopleCount = 0;

  // questions already on the server (a Google Forms import): counted, never touched by the wizard
  int importedQuestions = 0;
  double importedPoints = 0;
  int importedNotBubble = 0;

  bool get isBubble => type == CreateType.bubble;
  bool get hasCourse => exam.courseId != null;
  bool get isPaper => publish == PublishKind.paper;
  bool get isElectronic => publish == PublishKind.electronic;

  /// Questions that go on the NB2 written-answer sheet.
  int get writtenQuestionCount => exam.isFile ? 0 : exam.questions.where((q) => answerSheetCanHold(q.type)).length;

  /// Questions that go on the bubble sheet.
  int get bubbleQuestionCount => exam.isFile ? 0 : exam.questions.where((q) => bubbleCanHold(q.type)).length + importedQuestions - importedNotBubble;

  /// The written answers go on an NB2 sheet: a paper exam answered on a table or a bubble sheet, with written questions.
  bool get wantsAnswerSheet =>
      answerSheetOn && isPaper && !exam.isFile && (answer == AnswerFormat.table || answer == AnswerFormat.bubble) && writtenQuestionCount > 0;

  /// NextBrain prints the bubble sheets (a sheet it can print, and the teacher does not have them already).
  bool get printsBubbleSheets => isBubble && bubbleSource == BubbleSource.print && !ownSheet;

  /// Personal or generic is asked only when NextBrain prints a sheet.
  bool get asksCopies => isPaper && (printsBubbleSheets || wantsAnswerSheet);

  SheetCopies get effectiveCopies => copies ?? (hasCourse ? SheetCopies.personal : SheetCopies.generic);

  bool get personalSheets => asksCopies && effectiveCopies == SheetCopies.personal;

  /// Personal sheets of an exam with no course: the students come from an uploaded list.
  bool get needsPeopleFile => personalSheets && !hasCourse;

  /// `settings.sheet_plan`, null when no sheet is printed or read.
  SheetPlan? get sheetPlan => !isPaper || !(isBubble || wantsAnswerSheet)
      ? null
      : SheetPlan(
          bubble: isBubble ? bubbleSource : null,
          answerSheet: wantsAnswerSheet,
          copies: asksCopies ? effectiveCopies : SheetCopies.generic,
          fromFile: !hasCourse,
          idSource: idSource,
        );

  /// Moves the plan to another place, every answer kept (a question belongs to the exam, not to the course yet).
  void setPlace(NewExamPlace p) {
    final o = exam;
    place = p;
    exam = QuickExam(kind: o.kind, courseId: p.courseId, orgId: p.orgId, title: o.title, startsAt: o.startsAt, endsAt: o.endsAt)
      ..mode = o.mode
      ..source = o.source
      ..fileName = o.fileName
      ..fileBytes = o.fileBytes
      ..filePath = o.filePath
      ..filePoints = o.filePoints
      ..durationMinutes = o.durationMinutes
      ..maxAttempts = o.maxAttempts
      ..description = o.description
      ..poolSize = o.poolSize
      ..shuffle = o.shuffle
      ..highStakes = o.highStakes
      ..resultsPolicy = o.resultsPolicy
      ..passingPercent = o.passingPercent
      ..passcode = o.passcode;
    exam.questions.addAll(o.questions);
    normalize();
  }

  /// online → electronic · on the paper / a table → paper · a bubble sheet → paper on a bubble sheet.
  void setAnswer(AnswerFormat v) {
    answer = v;
    type = v == AnswerFormat.bubble ? CreateType.bubble : CreateType.normal;
    publish = v == AnswerFormat.online ? PublishKind.electronic : PublishKind.paper;
    normalize();
  }

  /// The students answer in a separate booklet / table (`settings.answer_booklet`).
  bool get answerBooklet => answer == AnswerFormat.table;

  /// Keeps the choices consistent after any change, and the exam's own mode in step with them.
  void normalize() {
    exam.mode = isBubble || isPaper ? QuickMode.offline : (isElectronic ? QuickMode.online : exam.mode);
    if (paperPlan == PaperPlan.personal && !personalAllowed) paperPlan = PaperPlan.versions;
    if (!versionsAllowed) versions = 1;
  }

  /// The sheet is the teacher's own: NextBrain neither prints it nor puts a QR on it.
  bool get ownSheet => isBubble && (template?.kind ?? 'bubble') != 'bubble';

  /// An uploaded file prints as it is, and an own sheet carries no version mark: one version in both cases.
  bool get versionsAllowed => !exam.isFile && !ownSheet;

  /// A paper named for each student: needs the course's students, and a paper NextBrain prints.
  bool get personalAllowed => hasCourse && !exam.isFile && !ownSheet;

  int get effectiveVersions => isPaper && paperPlan == PaperPlan.versions && versionsAllowed ? versions : 1;

  int get questionCount => exam.isFile ? 0 : exam.questions.length + importedQuestions;
  double get totalPoints => exam.totalPoints + importedPoints;

  /// Something the teacher would lose by leaving.
  bool get hasContent => exam.questions.isNotEmpty || exam.hasFile || importedQuestions > 0;

  /// What the wizard writes into `settings`: the answer format always, the booklet and the print plan on paper.
  Map<String, dynamic> get settingsJson => {
        if (answer != null) 'answer_format': answerFormatKey(answer!),
        if (isPaper) 'answer_booklet': answerBooklet,
        if (isPaper) 'paper_plan': paperPlanJson,
        if (sheetPlan != null) 'sheet_plan': sheetPlan!.toJson(),
      };

  /// What is left to print, and how the Deliver step reads it (`settings.paper_plan`).
  Map<String, dynamic> get paperPlanJson => {
        'mode': paperPlan == PaperPlan.personal ? 'personal' : 'versions',
        'versions': effectiveVersions,
      };

  /// `PUT /exams/{id}/setup`, with no version marks: a mark needs two versions to exist, so the marks follow them.
  Map<String, dynamic>? get setupBody {
    if (isElectronic) return {'delivery': 'online'};
    if (!isPaper) return null;
    final t0 = template;
    return {
      'delivery': 'paper',
      'paper_format': isBubble ? 'both' : 'paper',
      if (isBubble && t0 != null) ...{'omr_template_id': t0.id, 'omr_template_version': t0.version},
      'form_markers': const <String>[],
    };
  }
}

// ── the steps ───────────────────────────────────────────────────────────────────────────────────────────────────

/// The students step: where a paper must be matched to a student and the course knows its students, or where personal
/// sheets of an exam with no course need the uploaded list (D-687).
bool needsIdentifierStep(ExamCreatePlan p, {required bool identifiersOn}) {
  if (!p.isPaper) return false;
  if (p.needsPeopleFile) return true;
  return identifiersOn && p.hasCourse && (p.paperPlan == PaperPlan.personal || p.isBubble || p.personalSheets);
}

/// The course's identifier plan (IdentifierPlanStep) is needed: the printed paper or the bubble sheet is matched on it,
/// or the personal sheets carry the academic ID. Sheets on the system number alone need nothing set up.
bool needsIdentifierPlan(ExamCreatePlan p) =>
    p.hasCourse && (p.paperPlan == PaperPlan.personal || p.isBubble || (p.personalSheets && p.idSource == IdSource.academic));

List<CreateStep> createSteps(ExamCreatePlan p, {required bool whereNeeded, required bool omrOn, required bool identifiersOn}) => [
      if (whereNeeded) CreateStep.where,
      CreateStep.answer,
      CreateStep.questions,
      if (omrOn && p.isBubble) CreateStep.template,
      CreateStep.publish,
      if (p.asksCopies) CreateStep.sheets,
      if (needsIdentifierStep(p, identifiersOn: identifiersOn)) CreateStep.identify,
    ];

String createStepLabel(CreateStep s) => switch (s) {
      CreateStep.where => t('المكان', 'Where'),
      CreateStep.answer => t('الإجابة', 'Answers'),
      CreateStep.template => t('ورقة التظليل', 'Bubble sheet'),
      CreateStep.questions => t('الأسئلة', 'Questions'),
      CreateStep.publish => t('الإعدادات', 'Settings'),
      CreateStep.sheets => t('أوراق الإجابة', 'Answer sheets'),
      CreateStep.identify => t('الطلاب', 'Students'),
    };

/// The answer formats the teacher can pick: the bubble sheet only while paper exams with OMR are on.
List<AnswerFormat> answerFormatsFor({required bool omrOn}) => [for (final f in AnswerFormat.values) if (omrOn || f != AnswerFormat.bubble) f];

String answerFormatLabel(AnswerFormat f) => switch (f) {
      AnswerFormat.online => t('على التطبيق', 'Online'),
      AnswerFormat.onPaper => t('على ورقة الأسئلة', 'On the paper'),
      AnswerFormat.table => t('جدول إجابة', 'Answer table'),
      AnswerFormat.bubble => t('ورقة تظليل', 'Bubble sheet'),
    };

/// One line under each choice: what it means for the students and for the marking.
String answerFormatHint(AnswerFormat f) => switch (f) {
      AnswerFormat.online => t('يجيب الطلاب على التطبيق، والتصحيح تلقائي', 'Students answer in the app; marking is automatic'),
      AnswerFormat.onPaper => t('تُطبع الأسئلة ويكتب الطالب إجابته عليها', 'The questions are printed and students write on them'),
      AnswerFormat.table => t('ورقة أسئلة وجدول إجابة منفصل، والمقالي في كراسة الإجابة', 'A question paper and a separate answer table; essays go in the booklet'),
      AnswerFormat.bubble => t('يظلل الطالب إجابته وتُصحَّح بالمسح. اختيار من متعدد وصح / خطأ فقط',
          'Students shade their answers, marked by scanning. Multiple choice and true / false only'),
    };

/// One line for the summary rail / the chips; null = nothing chosen yet.
String? createStepValue(CreateStep s, ExamCreatePlan p) => switch (s) {
      CreateStep.where => p.place?.name,
      CreateStep.answer => p.answer == null ? null : answerFormatLabel(p.answer!),
      CreateStep.template => p.template?.title,
      CreateStep.questions => _questionsValue(p),
      CreateStep.publish => _publishValue(p),
      CreateStep.sheets => p.asksCopies ? sheetCopiesLabel(p.effectiveCopies) : null,
      CreateStep.identify => null,
    };

String? _questionsValue(ExamCreatePlan p) {
  if (p.exam.isFile) return p.exam.hasFile ? '${t('ملف', 'File')} · ${marksCountText(p.exam.filePoints)}' : null;
  if (p.questionCount == 0) return null;
  return '${questionsCountText(p.questionCount)} · ${marksCountText(p.totalPoints)}';
}

String? _publishValue(ExamCreatePlan p) {
  if (p.publish == null) return null;
  if (p.isElectronic) return t('إلكتروني', 'Online');
  if (p.paperPlan == PaperPlan.personal) return t('ورقي · ورقة لكل طالب', 'Paper · one for each student');
  return '${t('ورقي', 'Paper')} · ${versionsCountText(p.effectiveVersions)}';
}

/// The live estimate: (label, value), only what can honestly be counted.
List<(String, String)> createEstimate(ExamCreatePlan p) => [
      if (p.questionCount > 0) (t('الأسئلة', 'Questions'), '${p.questionCount}'),
      if (p.totalPoints > 0) (t('الدرجة الكلية', 'Total marks'), fmtPoints(p.totalPoints)),
      if (p.isPaper && p.paperPlan == PaperPlan.versions && (p.questionCount > 0 || p.effectiveVersions > 1)) (t('النماذج', 'Versions'), '${p.effectiveVersions}'),
      if (p.isElectronic) (t('المدة', 'Duration'), omrMinutesText(p.exam.durationMinutes)),
    ];

// ── what stands in the way ──────────────────────────────────────────────────────────────────────────────────────

/// A bubble exam's questions against its sheet.
class BubbleCheck {
  const BubbleCheck({this.notHeld = const [], this.importedNotHeld = 0, this.over = 0, this.choicesOver = 0, this.capacity});

  /// Questions a bubble cannot hold (in the builder).
  final List<QuickQuestion> notHeld;

  /// The same, among those imported to the server.
  final int importedNotHeld;

  /// Questions past the sheet's last row.
  final int over;

  /// Questions with more choices than the sheet's bubbles.
  final int choicesOver;

  /// The sheet's rows, when known.
  final int? capacity;

  bool get blocks => notHeld.isNotEmpty || importedNotHeld > 0 || over > 0 || choicesOver > 0;
}

BubbleCheck bubbleCheckOf(ExamCreatePlan p) {
  if (!p.isBubble) return const BubbleCheck();
  final tpl = p.template;
  final cap = tpl != null && tpl.questions > 0 ? tpl.questions : null;
  final bubbles = tpl?.options;
  return BubbleCheck(
    // with the NB2 sheet on, written questions go there (D-687); only what neither sheet holds stands in the way
    notHeld: [for (final q in p.exam.questions) if (!bubbleCanHold(q.type) && !(p.answerSheetOn && answerSheetCanHold(q.type))) q],
    importedNotHeld: p.importedNotBubble,
    over: cap != null && p.bubbleQuestionCount > cap ? p.bubbleQuestionCount - cap : 0,
    choicesOver: bubbles == null ? 0 : p.exam.questions.where((q) => q.options.where((o) => o.text.trim().isNotEmpty).length > bubbles).length,
    capacity: cap,
  );
}

/// The smallest sheet with room for [questions], else the largest; null when there is none. Printed sheets first.
OmrTemplateItem? recommendedTemplate(List<OmrTemplateItem> all, int questions) {
  final printed = [for (final x in all) if (x.kind == 'bubble') x];
  final list = printed.isEmpty ? all : printed;
  if (list.isEmpty) return null;
  final fit = [for (final x in list) if (x.questions >= questions) x]..sort((a, b) => a.questions.compareTo(b.questions));
  if (fit.isNotEmpty) return fit.first;
  return (List.of(list)..sort((a, b) => b.questions.compareTo(a.questions))).first;
}

/// The teacher's own sheet types waiting for the platform's approval (`omr.require_approval`).
List<OmrTemplateItem> pendingTemplates(List<OmrTemplateItem> all) => [for (final x in all) if (x.status == 'pending_approval') x];

/// The questions step: exam-level codes for [quickCodeText], and per question its index → codes.
(List<String>, Map<int, List<String>>) questionStepErrors(ExamCreatePlan p) {
  const here = {'title_required', 'no_questions', 'file_required', 'points_positive'};
  final (all, perQ) = p.exam.validate();
  return ([for (final e in all) if (here.contains(e) && !(e == 'no_questions' && p.importedQuestions > 0)) e], perQ);
}

/// The electronic exam's settings: codes for [quickCodeText].
List<String> publishStepErrors(ExamCreatePlan p) {
  if (!p.isElectronic) return const [];
  const here = {'bad_duration', 'bad_attempts', 'bad_pool', 'bad_window'};
  return [for (final e in p.exam.validate().$1) if (here.contains(e)) e];
}

/// Versions that would all come out the same: nothing to shuffle was switched on, or nothing can be shuffled.
bool versionsWouldMatch(ExamCreatePlan p) {
  if (p.effectiveVersions < 2) return false;
  final canQuestions = !p.isBubble && p.shuffleQuestions && p.questionCount > 1;
  final canOptions = p.shuffleOptions && p.exam.questions.any((q) => q.type == 'mcq_single');
  return !canQuestions && !canOptions && p.importedQuestions == 0;
}

bool createStepReady(CreateStep s, ExamCreatePlan p, {bool identifierValid = false}) {
  switch (s) {
    case CreateStep.where:
      return p.place != null;
    case CreateStep.answer:
      return p.answer != null;
    case CreateStep.template:
      // the sheet comes after the questions: it must hold them
      return p.template != null && !bubbleCheckOf(p).blocks;
    case CreateStep.questions:
      final (errors, perQ) = questionStepErrors(p);
      return errors.isEmpty && perQ.isEmpty && !bubbleCheckOf(p).blocks;
    case CreateStep.publish:
      return p.publish != null && publishStepErrors(p).isEmpty;
    case CreateStep.sheets:
      return true;
    case CreateStep.identify:
      if (p.needsPeopleFile) return p.peopleCount > 0;
      return !needsIdentifierPlan(p) || identifierValid;
  }
}
