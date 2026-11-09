// The "New exam" wizard of the Exam Hub, pure part: what the teacher has chosen so far, which steps that means, what
// each step says in the summary, and the problems stated before they bite. No widget and no call lives here.
//
// Order: Where (a course, an organization or personal) → Type (bubble sheet or normal) → Template (bubble only) →
// Questions (automatic, manual, a file or Google Forms) → Publish (electronic or paper) → Students (the identifier
// plan, where a paper is matched to a student).
//
// Unit-tested in test/org/exam_hub_f2_test.dart.
library;

import '../../../../admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/plural.dart';

import '../../exam_all.dart' show NewExamPlace;
import '../../exam_authoring.dart' show fmtPoints;
import '../../exam_quick.dart';
import '../../paper/exam_setup.dart' show ObjectiveQuestion, OmrTemplateItem;

enum CreateStep { where, type, template, questions, publish, identify }

enum CreateType { normal, bubble }

enum PublishKind { electronic, paper }

/// One printed exam per version, or a paper named for each student.
enum PaperPlan { versions, personal }

/// The question types a bubble can hold, in the order of the "add a question" row.
const kBubbleQuestionTypes = <String>['mcq_single', 'true_false'];

/// How the printed versions are told apart. QR is what the scanner reads; the printed code is for people. Not "bubble":
/// not every sheet has a version row to shade.
const kVersionMarkers = <String>['qr', 'printed'];

String questionsCountText(int n) =>
    countText(n, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالًا', en1: '1 question', en: '{n} questions');

String versionsCountText(int n) =>
    countText(n, ar1: 'نموذج واحد', ar2: 'نموذجان', arFew: '{n} نماذج', arMany: '{n} نموذجًا', en1: '1 version', en: '{n} versions');

/// A question a bubble sheet can carry.
bool bubbleCanHold(String type) => ObjectiveQuestion.types.contains(type);

class ExamCreatePlan {
  ExamCreatePlan({NewExamPlace? place, String? title})
      : place = place,
        exam = QuickExam(kind: QuickKind.quiz, courseId: place?.courseId, orgId: place?.orgId, title: title);

  NewExamPlace? place;
  QuickExam exam;
  CreateType? type;
  OmrTemplateItem? template;
  PublishKind? publish;
  PaperPlan paperPlan = PaperPlan.versions;
  int versions = 1;
  bool shuffleQuestions = true;
  bool shuffleOptions = true;

  // questions already on the server (a Google Forms import): counted, never touched by the wizard
  int importedQuestions = 0;
  double importedPoints = 0;
  int importedNotBubble = 0;

  bool get isBubble => type == CreateType.bubble;
  bool get hasCourse => exam.courseId != null;
  bool get isPaper => publish == PublishKind.paper;
  bool get isElectronic => publish == PublishKind.electronic;

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

  void setType(CreateType v) {
    type = v;
    if (v == CreateType.bubble) publish = PublishKind.paper;
    normalize();
  }

  void setPublish(PublishKind v) {
    publish = v;
    normalize();
  }

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

/// The students step: where a paper must be matched to a student and the course knows its students.
bool needsIdentifierStep(ExamCreatePlan p, {required bool identifiersOn}) =>
    identifiersOn && p.isPaper && p.hasCourse && (p.paperPlan == PaperPlan.personal || p.isBubble);

List<CreateStep> createSteps(ExamCreatePlan p, {required bool whereNeeded, required bool omrOn, required bool identifiersOn}) => [
      if (whereNeeded) CreateStep.where,
      if (omrOn) CreateStep.type,
      if (omrOn && p.isBubble) CreateStep.template,
      CreateStep.questions,
      CreateStep.publish,
      if (needsIdentifierStep(p, identifiersOn: identifiersOn)) CreateStep.identify,
    ];

String createStepLabel(CreateStep s) => switch (s) {
      CreateStep.where => t('المكان', 'Where'),
      CreateStep.type => t('النوع', 'Type'),
      CreateStep.template => t('ورقة التظليل', 'Bubble sheet'),
      CreateStep.questions => t('الأسئلة', 'Questions'),
      CreateStep.publish => t('النشر', 'Publish'),
      CreateStep.identify => t('الطلاب', 'Students'),
    };

String createTypeLabel(CreateType v) => v == CreateType.bubble ? t('ورقة تظليل', 'Bubble sheet') : t('عادي', 'Normal');

/// One line for the summary rail / the chips; null = nothing chosen yet.
String? createStepValue(CreateStep s, ExamCreatePlan p) => switch (s) {
      CreateStep.where => p.place?.name,
      CreateStep.type => p.type == null ? null : createTypeLabel(p.type!),
      CreateStep.template => p.template?.title,
      CreateStep.questions => _questionsValue(p),
      CreateStep.publish => _publishValue(p),
      CreateStep.identify => null,
    };

String? _questionsValue(ExamCreatePlan p) {
  if (p.exam.isFile) return p.exam.hasFile ? '${t('ملف', 'File')} · ${fmtPoints(p.exam.filePoints)} ${t('درجة', 'marks')}' : null;
  if (p.questionCount == 0) return null;
  return '${questionsCountText(p.questionCount)} · ${fmtPoints(p.totalPoints)} ${t('درجة', 'marks')}';
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
      if (p.isElectronic) (t('المدة', 'Duration'), t('${p.exam.durationMinutes} دقيقة', '${p.exam.durationMinutes} min')),
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
    notHeld: [for (final q in p.exam.questions) if (!bubbleCanHold(q.type)) q],
    importedNotHeld: p.importedNotBubble,
    over: cap != null && p.questionCount > cap ? p.questionCount - cap : 0,
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
    case CreateStep.type:
      return p.type != null;
    case CreateStep.template:
      return p.template != null;
    case CreateStep.questions:
      final (errors, perQ) = questionStepErrors(p);
      return errors.isEmpty && perQ.isEmpty && !bubbleCheckOf(p).blocks;
    case CreateStep.publish:
      return p.publish != null && publishStepErrors(p).isEmpty;
    case CreateStep.identify:
      return identifierValid;
  }
}
