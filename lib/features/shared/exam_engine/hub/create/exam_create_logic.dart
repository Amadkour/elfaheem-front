// The "New exam" wizard of the Exam Hub, pure part: what the teacher has chosen so far, which steps that means, what
// each step says in the summary, and the problems stated before they bite. No widget and no call lives here.
//
// Online (D-661, unchanged): Where (a course, an organization or personal) → How (online) → Questions → Settings.
//
// On paper (D-697, the owner's flow): Where → How (on paper) → Questions (any type: the layout follows them) → Answer
// sheet (the four layouts of offline_flow.dart, the best fit preselected) → Bubble form (layouts 2 / 3 only: a ready
// sheet, an example sheet imported, or a new one designed) → Copies (one generic copy, or one per student) → Students
// (per student and no course only: an Excel / CSV list; a course's roster is automatic) → Attributes (what each copy
// carries, per student; generic bubble copies of a course say what the students shade) → Paper design → Review and
// create. A step that does not apply is not in the list at all.
//
// Unit-tested in test/org/exam_hub_f2_test.dart and test/org/offline_flow_test.dart.
library;

import '../../../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/plural.dart';

import '../../exam_all.dart' show NewExamPlace;
import '../../exam_authoring.dart' show fmtPoints;
import '../../exam_quick.dart';
import '../../paper/exam_setup.dart' show OmrTemplateItem;
import '../../paper/omr_counts.dart' show omrMinutesText;
import 'answer_format.dart';
import 'answer_sheet_plan.dart';
import 'offline_flow.dart';

export 'answer_format.dart';
export 'answer_sheet_plan.dart';
export 'offline_flow.dart';

/// `answer` is "How": online or on paper. `publish` is the online exam's Settings; `review` is the paper exam's last step
/// (its own settings, the versions, live in Copies). `sheets` is Copies, `identify` the student list of an exam with no
/// course.
enum CreateStep { where, answer, questions, layout, template, publish, sheets, identify, attributes, design, review }

enum CreateType { normal, bubble }

enum PublishKind { electronic, paper }

/// One printed exam per version, or a paper named for each student (follows Copies).
enum PaperPlan { versions, personal }

/// The question types a bubble can hold, in the order of the "add a question" row.
const kBubbleQuestionTypes = <String>['mcq_single', 'true_false'];

/// The written types (they go in the question paper).
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

/// A question a bubble sheet can carry (in some layout).
bool bubbleCanHold(String type) => const {...kMcqTypes, 'true_false'}.contains(type);

class ExamCreatePlan {
  ExamCreatePlan({NewExamPlace? place, String? title})
      : place = place,
        exam = QuickExam(kind: QuickKind.quiz, courseId: place?.courseId, orgId: place?.orgId, title: title);

  NewExamPlace? place;
  QuickExam exam;

  /// How students answer: online, or a paper format that follows [layout]; [type] and [publish] follow it.
  AnswerFormat? answer;

  /// The paper's answer-sheet layout (D-697); null until the Answer sheet step, and on an online exam.
  PaperLayout? layout;
  CreateType? type;
  OmrTemplateItem? template;
  PublishKind? publish;
  PaperPlan paperPlan = PaperPlan.versions;
  int versions = 1;
  bool shuffleQuestions = true;
  bool shuffleOptions = true;

  // the answer sheets (D-687, kept by D-697)
  BubbleSource bubbleSource = BubbleSource.print;

  /// Null = the default: per student with a course, generic without.
  SheetCopies? copies;
  IdSource idSource = IdSource.academic;

  /// The answer-sheet step and the NB2 sheet are on offer (`exam.answer_sheet`, contract: the switch hides the whole
  /// step); the wizard sets it from the kill switch. Off: the best-fit layout, its paper part answered in the booklet.
  bool answerSheetOn = true;

  /// Where the bubble form came from (contract §1 `bubble.source`).
  BubbleFormSource bubbleForm = BubbleFormSource.template;

  /// Students on the uploaded list (an exam with no course).
  int peopleCount = 0;

  /// What each copy carries, in the printed order (the Attributes step, `sheet_plan.attributes`); empty = the server's
  /// default (the name and the exam identifier).
  List<({String key, String label})> attributes = const [];

  /// A paper design was saved for this exam (the Paper design step).
  bool designed = false;

  // questions already on the server (a Google Forms import): counted, never touched by the wizard
  int importedQuestions = 0;
  double importedPoints = 0;
  int importedNotBubble = 0;

  bool get isBubble => type == CreateType.bubble;
  bool get hasCourse => exam.courseId != null;
  bool get isPaper => publish == PublishKind.paper;
  bool get isElectronic => publish == PublishKind.electronic;

  /// What the questions are made of, for the Answer sheet step.
  QuestionMix get mix => QuestionMix.of([for (final q in exam.questions) q.type],
      isFile: exam.isFile, importedObjective: importedQuestions - importedNotBubble, importedOther: importedNotBubble);

  /// Questions that are written (they go in the paper).
  int get writtenQuestionCount => exam.isFile ? 0 : exam.questions.where((q) => answerSheetCanHold(q.type)).length;

  /// Questions that go on the bubble sheet in this layout.
  int get bubbleQuestionCount {
    if (exam.isFile || !isBubble) return 0;
    final types = (layout ?? PaperLayout.bubbleObjective).bubbleTypes;
    return exam.questions.where((q) => types.contains(q.type)).length + importedQuestions - importedNotBubble;
  }

  /// The paper part is answered on the machine-read NB2 sheet (contract default), or in the booklet: an exam made as a
  /// D-661 answer table, or while `exam.answer_sheet` is off.
  WrittenSheet get writtenSheet => answerSheetOn && answer != AnswerFormat.table ? WrittenSheet.nb2 : WrittenSheet.booklet;

  /// The NB2 sheet is printed for the paper part (layouts 1 to 3, written questions or objective ones routed to it).
  bool get wantsAnswerSheet {
    final l = layout;
    if (!isPaper || l == null || l == PaperLayout.questionsOnly || exam.isFile || writtenSheet != WrittenSheet.nb2) return false;
    return exam.questions.any((q) => answerSheetCanHold(q.type) || (bubbleCanHold(q.type) && !l.bubbleTypes.contains(q.type)));
  }

  /// NextBrain prints the bubble sheets (a sheet it can print, and the teacher does not have them already).
  bool get printsBubbleSheets => isBubble && bubbleSource == BubbleSource.print && !ownSheet;

  /// Every paper exam chooses its copies (D-697).
  bool get asksCopies => isPaper;

  SheetCopies get effectiveCopies {
    final c = copies ?? (hasCourse ? SheetCopies.personal : SheetCopies.generic);
    return c == SheetCopies.personal && !personalAllowed ? SheetCopies.generic : c;
  }

  bool get personalSheets => asksCopies && effectiveCopies == SheetCopies.personal;

  /// Per-student copies of an exam with no course: the students come from an uploaded list.
  bool get needsPeopleFile => personalSheets && !hasCourse;

  /// `settings.sheet_plan` v2 (contract §1): what is printed and for whom; null on an online exam or before a layout.
  OfflinePlan? get offlinePlan {
    final l = layout;
    if (!isPaper || l == null) return null;
    return OfflinePlan(
      layout: l,
      writtenSheet: writtenSheet,
      bubbleSource: l.usesBubble ? bubbleForm : null,
      bubbleIds: [if (l.usesBubble && template != null) template!.id],
      bubblePrint: bubbleSource == BubbleSource.print,
      copies: effectiveCopies,
      fromFile: !hasCourse,
      attributes: [for (final a in attributes) a.key],
      idSource: idSource,
    );
  }

  /// The plan in the v1 terms Deliver prints with (read back from v2 the same way).
  SheetPlan? get sheetPlan => offlinePlan == null ? null : SheetPlan.ofSettings({'sheet_plan': offlinePlan!.toJson()});

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
    attributes = const [];   // another place has other students
    normalize();
  }

  /// "How": online, or on paper (the layout comes after the questions).
  void setOffline(bool offline) {
    if (!offline) return setAnswer(AnswerFormat.online);
    publish = PublishKind.paper;
    answer = layout?.answerFormat ?? AnswerFormat.onPaper;
    type = layout?.usesBubble == true ? CreateType.bubble : CreateType.normal;
    normalize();
  }

  /// The answer-sheet layout; answer format and kind follow it.
  void setLayout(PaperLayout l) {
    layout = l;
    publish = PublishKind.paper;
    answer = l.answerFormat;
    type = l.usesBubble ? CreateType.bubble : CreateType.normal;
    normalize();
  }

  /// An answer format as D-661 knew it (old prefs, tests): online stays online; a bubble sheet is layout 3; on the paper
  /// or an answer table is layout 1 (the table keeps its booklet).
  void setAnswer(AnswerFormat v) {
    answer = v;
    type = v == AnswerFormat.bubble ? CreateType.bubble : CreateType.normal;
    publish = v == AnswerFormat.online ? PublishKind.electronic : PublishKind.paper;
    layout = switch (v) {
      AnswerFormat.online => layout,   // kept for the way back to paper; no plan is written while online
      AnswerFormat.bubble => PaperLayout.bubbleObjective,
      _ => layout?.usesBubble == false ? layout : PaperLayout.allInPaper,
    };
    normalize();
  }

  /// One copy per student (named) or generic copies; the print plan follows.
  void setCopies(SheetCopies v) {
    copies = v;
    normalize();
  }

  /// The students answer in a separate booklet / table (`settings.answer_booklet`; only an exam made as a D-661 table).
  bool get answerBooklet => answer == AnswerFormat.table;

  /// Keeps the choices consistent after any change, and the exam's own mode in step with them.
  void normalize() {
    exam.mode = isBubble || isPaper ? QuickMode.offline : (isElectronic ? QuickMode.online : exam.mode);
    if (isPaper) paperPlan = effectiveCopies == SheetCopies.personal && !exam.isFile ? PaperPlan.personal : PaperPlan.versions;
    if (paperPlan == PaperPlan.personal && !personalAllowed) paperPlan = PaperPlan.versions;
    if (!versionsAllowed) versions = 1;
  }

  /// The sheet is the teacher's own: NextBrain neither prints it nor puts a QR on it.
  bool get ownSheet => isBubble && (template?.kind ?? 'bubble') != 'bubble';

  /// An uploaded file prints as it is, and an own sheet carries no version mark: one version in both cases.
  bool get versionsAllowed => !exam.isFile && !ownSheet;

  /// Multiple choice or true / false answered on the NB2 sheet gets a row of choice boxes in the exam's own option order,
  /// so the versions may not shuffle the options (contract §4, 409 `versions_shuffle_options`).
  bool get shuffleOptionsAllowed {
    final l = layout;
    if (!wantsAnswerSheet || l == null) return true;
    return !exam.questions.any((q) => bubbleCanHold(q.type) && !l.bubbleTypes.contains(q.type));
  }

  /// A copy named for each student: something NextBrain prints must carry the name (the question paper, or the bubble
  /// sheet beside an uploaded file). The students come from the course, or from a list without one.
  bool get personalAllowed => (!exam.isFile && !ownSheet) || (exam.isFile && printsBubbleSheets);

  int get effectiveVersions => isPaper && paperPlan == PaperPlan.versions && versionsAllowed ? versions : 1;

  int get questionCount => exam.isFile ? 0 : exam.questions.length + importedQuestions;
  double get totalPoints => exam.totalPoints + importedPoints;

  /// Something the teacher would lose by leaving.
  bool get hasContent => exam.questions.isNotEmpty || exam.hasFile || importedQuestions > 0;

  /// What the wizard writes into `settings`: the answer format always; on paper the booklet, the print plan and the
  /// sheet plan v2 (contract §1; `PUT /exams/{id}/offline-plan` checks it again on Finish).
  Map<String, dynamic> get settingsJson => {
        if (answer != null) 'answer_format': answerFormatKey(answer!),
        if (isPaper) 'answer_booklet': answerBooklet,
        if (isPaper) 'paper_plan': paperPlanJson,
        if (offlinePlan != null) 'sheet_plan': offlinePlan!.toJson(),
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

/// The student list step: per-student copies of an exam with no course (a course's roster is automatic).
bool needsIdentifierStep(ExamCreatePlan p, {required bool identifiersOn}) => p.isPaper && p.needsPeopleFile;

/// The Attributes step: what each copy carries (contract §4: a named copy its values, a generic copy a labelled write-in
/// line for each). A generic copy of an exam with no course has nothing to choose from but the name, so it has no step.
bool needsAttributesStep(ExamCreatePlan p, {required bool identifiersOn}) => p.isPaper && identifiersOn && (p.personalSheets || p.hasCourse);

/// Generic copies of a course are matched on what the students write in the ID boxes: the Attributes step says which
/// (the exam identifier or the platform number).
bool asksIdSource(ExamCreatePlan p) => p.isPaper && p.hasCourse && !p.personalSheets && p.layout != PaperLayout.questionsOnly;

/// The Paper design step: a paper NextBrain draws (an uploaded file prints as it is).
bool needsDesignStep(ExamCreatePlan p) => p.isPaper && !p.exam.isFile;

/// The Answer sheet step: a paper exam, while `exam.answer_sheet` is on (off, the best fit is taken without asking).
bool needsLayoutStep(ExamCreatePlan p) => p.isPaper && p.answerSheetOn;

List<CreateStep> createSteps(ExamCreatePlan p, {required bool whereNeeded, required bool omrOn, required bool identifiersOn}) => [
      if (whereNeeded) CreateStep.where,
      CreateStep.answer,
      CreateStep.questions,
      if (!p.isPaper) CreateStep.publish,
      if (p.isPaper) ...[
        if (needsLayoutStep(p)) CreateStep.layout,
        if (omrOn && p.isBubble) CreateStep.template,
        CreateStep.sheets,
        if (needsIdentifierStep(p, identifiersOn: identifiersOn)) CreateStep.identify,
        if (needsAttributesStep(p, identifiersOn: identifiersOn)) CreateStep.attributes,
        if (needsDesignStep(p)) CreateStep.design,
        CreateStep.review,
      ],
    ];

String createStepLabel(CreateStep s) => switch (s) {
      CreateStep.where => t('المكان', 'Where'),
      CreateStep.answer => t('طريقة الاختبار', 'How'),
      CreateStep.questions => t('الأسئلة', 'Questions'),
      CreateStep.layout => t('ورقة الإجابة', 'Answer sheet'),
      CreateStep.template => t('نموذج التظليل', 'Bubble form'),
      CreateStep.publish => t('الإعدادات', 'Settings'),
      CreateStep.sheets => t('النسخ', 'Copies'),
      CreateStep.identify => t('الطلاب', 'Students'),
      CreateStep.attributes => t('بيانات الطالب', 'Attributes'),
      CreateStep.design => t('تصميم الورقة', 'Paper design'),
      CreateStep.review => t('المراجعة', 'Review'),
    };

/// The two ways an exam is taken, the first step after Where.
const kCreateModes = <AnswerFormat>[AnswerFormat.online, AnswerFormat.onPaper];

/// Kept for the callers of D-661: every format the teacher can pick (the bubble sheet only while OMR is on).
List<AnswerFormat> answerFormatsFor({required bool omrOn}) => [for (final f in AnswerFormat.values) if (omrOn || f != AnswerFormat.bubble) f];

/// The mode an answer format belongs to: online, or on paper.
AnswerFormat createModeOf(AnswerFormat f) => f == AnswerFormat.online ? AnswerFormat.online : AnswerFormat.onPaper;

String answerFormatLabel(AnswerFormat f) => switch (f) {
      AnswerFormat.online => t('على التطبيق', 'Online'),
      AnswerFormat.onPaper => t('ورقي', 'On paper'),
      AnswerFormat.table => t('جدول إجابة', 'Answer table'),
      AnswerFormat.bubble => t('ورقة تظليل', 'Bubble sheet'),
    };

/// One line under each choice: what it means for the students and for the marking.
String answerFormatHint(AnswerFormat f) => switch (f) {
      AnswerFormat.online => t('يجيب الطلاب على التطبيق، والتصحيح تلقائي', 'Students answer in the app; marking is automatic'),
      AnswerFormat.onPaper => t('يُطبع الاختبار ويُجاب عليه ورقيًا. تختار ورقة الإجابة بعد كتابة الأسئلة',
          'The exam is printed and answered on paper. You choose the answer sheet after writing the questions'),
      AnswerFormat.table => t('ورقة أسئلة وجدول إجابة منفصل، والمقالي في كراسة الإجابة', 'A question paper and a separate answer table; essays go in the booklet'),
      AnswerFormat.bubble => t('يظلل الطالب إجابته وتُصحَّح بالمسح', 'Students shade their answers, marked by scanning'),
    };

/// One line for the summary rail / the chips; null = nothing chosen yet.
String? createStepValue(CreateStep s, ExamCreatePlan p) => switch (s) {
      CreateStep.where => p.place?.name,
      CreateStep.answer => p.answer == null ? null : answerFormatLabel(createModeOf(p.answer!)),
      CreateStep.questions => _questionsValue(p),
      CreateStep.layout => p.layout == null ? null : paperLayoutShort(p.layout!),
      CreateStep.template => p.template?.title,
      CreateStep.publish => _publishValue(p),
      CreateStep.sheets => p.asksCopies ? _copiesValue(p) : null,
      CreateStep.identify => p.peopleCount > 0 ? studentsCountText(p.peopleCount) : null,
      CreateStep.attributes => p.attributes.isEmpty ? null : p.attributes.map((a) => a.label).join(t('، ', ', ')),
      CreateStep.design => p.designed ? t('تصميم محفوظ', 'Design saved') : null,
      CreateStep.review => null,
    };

String _copiesValue(ExamCreatePlan p) => p.effectiveCopies == SheetCopies.personal
    ? sheetCopiesLabel(SheetCopies.personal)
    : '${sheetCopiesLabel(SheetCopies.generic)} · ${versionsCountText(p.effectiveVersions)}';

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

  /// Questions neither the bubble sheet nor the paper can hold. Empty in the paper flow (D-697): what the sheet does not
  /// hold is answered in the question paper.
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
  final types = (p.layout ?? PaperLayout.bubbleObjective).bubbleTypes;
  return BubbleCheck(
    over: cap != null && p.bubbleQuestionCount > cap ? p.bubbleQuestionCount - cap : 0,
    choicesOver: bubbles == null ? 0 : p.exam.questions.where((q) => types.contains(q.type) && q.options.where((o) => o.text.trim().isNotEmpty).length > bubbles).length,
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
  final canOptions = p.shuffleOptions && p.shuffleOptionsAllowed && p.exam.questions.any((q) => q.type == 'mcq_single');
  return !canQuestions && !canOptions && p.importedQuestions == 0;
}

/// [identifierValid]: kept for the callers; nothing in the paper flow waits on it any more.
bool createStepReady(CreateStep s, ExamCreatePlan p, {bool identifierValid = false, bool omrOn = true}) {
  switch (s) {
    case CreateStep.where:
      return p.place != null;
    case CreateStep.answer:
      return p.answer != null;
    case CreateStep.questions:
      final (errors, perQ) = questionStepErrors(p);
      // a bubble exam made the D-661 way (its sheet chosen first) is still checked against it
      return errors.isEmpty && perQ.isEmpty && (p.layout != null || !bubbleCheckOf(p).blocks);
    case CreateStep.layout:
      final l = p.layout;
      return l != null && paperLayoutAvailable(l, p.mix, omrOn: omrOn);
    case CreateStep.template:
      // the sheet comes after the questions: it must hold them
      return p.template != null && !bubbleCheckOf(p).blocks;
    case CreateStep.publish:
      return p.publish != null && publishStepErrors(p).isEmpty;
    case CreateStep.sheets:
      return true;
    case CreateStep.identify:
      return p.peopleCount > 0;
    case CreateStep.attributes:
      return true;
    case CreateStep.design:
    case CreateStep.review:
      return true;
  }
}
