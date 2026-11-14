// The Exam Hub's decisions (D-350, made plain by D-700 – D-703), all of them pure: which stage an exam is in, the one
// sentence that says where it stands, its one next step, what its ⋯ menu offers, the steps of the detail panel, and
// what needs the teacher now. Everything comes from the ONE list call (`loadAllExams`, `grading` of each item); a
// server without `grading` keeps the stages and the sentences that need no counts. `exam_hub_screen.dart` draws it.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/hub/hub_duplicate.dart' show hubCanDuplicate;

/// Everything a person can do to an exam from the hub.
enum HubAction { edit, deliver, results, publish, paper, correct, getResult, addDegrees, importDegrees, revision, duplicate }

/// Kill switches the hub respects on its own buttons (the servers refuse them too).
const kHubImportKey = 'exam.results.import';
const kHubRevisionKey = 'exam.grade_review';

bool _off(String key) => AppConfig.disableList.contains(key);

// ─────────────────────────────── the grading flags (D-350) ───────────────────────────────

/// Published or closed: drafts have nothing to correct, the archive is out of the way.
bool hubActive(AllExam e) => e.status != 'draft' && e.status != 'archived';

/// Did the server send the flags at all?
bool hubHasFlags(AllExamsData d) => d.exams.any((e) => e.grading != null);

/// Where the correction of an exam stands.
enum HubCorrection { notCorrected, inProgress, notEnded, corrected }

/// The correction flag; null on a server without `grading`, or for a draft / archived exam.
///
/// An exam that has not ended normally reads "Not ended yet". Papers can be collected early, so once scanned sheets of
/// it are being worked on the flag follows the work instead. Online answers arriving while students still sit it do not count.
HubCorrection? hubCorrectionOf(AllExam e) {
  final g = e.grading;
  if (g == null || !hubActive(e)) return null;
  if (!g.ended && !(g.papers > 0 && g.state != 'waiting')) return HubCorrection.notEnded;
  return switch (g.state) {
    'corrected' => HubCorrection.corrected,
    'in_progress' => HubCorrection.inProgress,
    _ => HubCorrection.notCorrected,
  };
}

/// Really waiting for the teacher: an online exam nobody sat has "not been corrected", and never will need to be.
bool hubNeedsCorrection(AllExam e) {
  if (hubCorrectionOf(e) != HubCorrection.notCorrected) return false;
  final g = e.grading!;
  return !(e.type == AllExamType.online && g.submitted == 0 && g.papers == 0);
}

/// Has degrees and students cannot see them yet. An exam whose results show right after submitting has nothing to publish.
bool hubUnpublished(AllExam e) {
  final g = e.grading;
  if (g == null || !hubActive(e) || !g.ended) return false;
  return g.hasDegrees && !g.resultsPublished && !_afterSubmit(e);
}

bool _afterSubmit(AllExam e) => '${e.raw['results_policy'] ?? ''}' == 'after_submit';

/// The list scoped to one organization (the hub opened from its dashboard).
AllExamsData hubScoped(AllExamsData d, int? orgId) => orgId == null
    ? d
    : AllExamsData(
        exams: [for (final e in d.exams) if (e.orgId == orgId) e],
        courseNames: d.courseNames,
        courseOrgs: d.courseOrgs,
        orgNames: d.orgNames,
        fallback: d.fallback,
      );

// ─────────────────────────────── the three stages (D-700) ───────────────────────────────

/// The list's three plain tabs: not sent yet, students can sit it (or soon will), over.
enum HubStage { drafts, running, finished }

/// Has the sitting ended? The server's word when it sent one, else the end time.
bool hubEnded(AllExam e, {DateTime? now}) {
  final g = e.grading;
  if (g != null) return g.ended;
  final end = e.endsAt;
  return end != null && end.isBefore(now ?? DateTime.now().toUtc());
}

/// A published exam whose window is over is finished too: nobody can sit it any more, what is left is grading and results.
HubStage hubStageOf(AllExam e, {DateTime? now}) {
  if (e.draft) return HubStage.drafts;
  if (e.published && !hubEnded(e, now: now)) return HubStage.running;
  return HubStage.finished;
}

/// Published, its start still ahead.
bool hubScheduled(AllExam e, {DateTime? now}) =>
    e.published && e.startsAt != null && e.startsAt!.isAfter(now ?? DateTime.now().toUtc()) && !hubEnded(e, now: now);

String hubStageLabel(HubStage s) => switch (s) {
      HubStage.drafts => t('مسودات', 'Drafts'),
      HubStage.running => t('جارية', 'Running'),
      HubStage.finished => t('منتهية', 'Finished'),
    };

bool _matches(AllExamsData d, AllExam e, AllExamsFilter f, List<String> words) {
  if (f.courseId == AllExamsFilter.noCourse ? e.courseId != null : (f.courseId != null && e.courseId != f.courseId)) return false;
  if (f.type != null && e.type != f.type) return false;
  if (words.isEmpty) return true;
  final hay = '${e.title} ${d.courseName(e) ?? ''} ${d.orgName(e) ?? ''}'.toLowerCase();
  return words.every(hay.contains);
}

List<String> _words(String q) => q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// How much an exam asks of the teacher now: the lower, the higher in its list.
int _urgency(AllExam e) {
  if (hubNeedsCorrection(e)) return 0;
  if (hubCorrectionOf(e) == HubCorrection.inProgress) return 1;
  if (hubUnpublished(e)) return 2;
  return e.status == 'archived' ? 4 : 3;
}

int _newestFirst(AllExam a, AllExam b) {
  final wa = a.endsAt ?? a.when, wb = b.endsAt ?? b.when;
  if (wa != null && wb != null && wa != wb) return wb.compareTo(wa);
  return b.id.compareTo(a.id);
}

/// What ends first comes first; an exam without an end time after the dated ones.
int _endingFirst(AllExam a, AllExam b) {
  final wa = a.endsAt, wb = b.endsAt;
  if (wa != null && wb != null && wa != wb) return wa.compareTo(wb);
  if ((wa == null) != (wb == null)) return wa == null ? 1 : -1;
  return b.id.compareTo(a.id);
}

int _byUrgency(AllExam a, AllExam b) {
  final r = _urgency(a).compareTo(_urgency(b));
  return r != 0 ? r : _newestFirst(a, b);
}

/// The exams of [stage] under [f] (search, course, type): drafts newest first, running ones by their end, finished ones
/// by what they still ask. [focus] (an attention card) lists its exams whatever their stage.
List<AllExam> hubStageList(AllExamsData d, HubStage stage, {AllExamsFilter f = const AllExamsFilter(), HubAttentionKind? focus, DateTime? now}) {
  final words = _words(f.query);
  final out = d.exams
      .where((e) => (focus == null ? hubStageOf(e, now: now) == stage : hubInFocus(e, focus)) && _matches(d, e, f, words))
      .toList();
  out.sort(focus != null
      ? _byUrgency
      : switch (stage) {
          HubStage.drafts => _newestFirst,
          HubStage.running => _endingFirst,
          HubStage.finished => _byUrgency,
        });
  return out;
}

/// How many exams each stage tab holds under [f].
Map<HubStage, int> hubStageCounts(AllExamsData d, {AllExamsFilter f = const AllExamsFilter(), DateTime? now}) => {
      for (final s in HubStage.values) s: hubStageList(d, s, f: f, now: now).length,
    };

/// The tab the hub opens on: where students are sitting exams, else the first stage that has any.
HubStage hubInitialStage(AllExamsData d, {DateTime? now}) {
  final counts = hubStageCounts(d, now: now);
  for (final s in const [HubStage.running, HubStage.drafts, HubStage.finished]) {
    if ((counts[s] ?? 0) > 0) return s;
  }
  return HubStage.running;
}

// ─────────────────────────────── what needs the teacher now ───────────────────────────────

enum HubAttentionKind { toCorrect, inCorrection, unpublished, drafts }

class HubAttention {
  const HubAttention(this.kind, this.count);
  final HubAttentionKind kind;
  final int count;
}

/// Is [e] one of the exams an attention card stands for?
bool hubInFocus(AllExam e, HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => hubNeedsCorrection(e),
      HubAttentionKind.inCorrection => hubCorrectionOf(e) == HubCorrection.inProgress,
      HubAttentionKind.unpublished => hubUnpublished(e),
      HubAttentionKind.drafts => e.draft,
    };

/// "Needs you now": most urgent first, only what is not zero. The grading cards need a server that sends `grading`;
/// drafts are known from the status alone.
List<HubAttention> hubAttention(AllExamsData d) {
  int n(HubAttentionKind k) => d.exams.where((e) => hubInFocus(e, k)).length;
  final flags = hubHasFlags(d);
  return [
    for (final k in HubAttentionKind.values)
      if ((flags || k == HubAttentionKind.drafts) && n(k) > 0) HubAttention(k, n(k)),
  ];
}

String hubAttentionText(HubAttention a) => switch (a.kind) {
      HubAttentionKind.toCorrect => countText(a.count,
          ar1: 'اختبار واحد به إجابات تنتظر تصحيحك',
          ar2: 'اختباران بهما إجابات تنتظر تصحيحك',
          arFew: '{n} اختبارات بها إجابات تنتظر تصحيحك',
          arMany: '{n} اختباراً بها إجابات تنتظر تصحيحك',
          en1: '1 exam has answers waiting for your grading',
          en: '{n} exams have answers waiting for your grading'),
      HubAttentionKind.inCorrection => countText(a.count,
          ar1: 'تصحيح اختبار واحد لم يكتمل بعد',
          ar2: 'تصحيح اختبارين لم يكتمل بعد',
          arFew: 'تصحيح {n} اختبارات لم يكتمل بعد',
          arMany: 'تصحيح {n} اختباراً لم يكتمل بعد',
          en1: 'The grading of 1 exam is not finished',
          en: 'The grading of {n} exams is not finished'),
      HubAttentionKind.unpublished => countText(a.count,
          ar1: 'اختبار واحد صُحّح ولم يرَ الطلاب نتيجته بعد',
          ar2: 'اختباران صُحّحا ولم يرَ الطلاب نتيجتهما بعد',
          arFew: '{n} اختبارات صُحّحت ولم يرَ الطلاب نتائجها بعد',
          arMany: '{n} اختباراً صُحّحت ولم يرَ الطلاب نتائجها بعد',
          en1: '1 exam is graded; students cannot see the result yet',
          en: '{n} exams are graded; students cannot see the results yet'),
      HubAttentionKind.drafts => countText(a.count,
          ar1: 'مسودة واحدة لم تكتمل',
          ar2: 'مسودتان لم تكتملا',
          arFew: '{n} مسودات لم تكتمل',
          arMany: '{n} مسودة لم تكتمل',
          en1: '1 draft is not finished',
          en: '{n} drafts are not finished'),
    };

String hubAttentionAction(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => t('صحّح الآن', 'Grade now'),
      HubAttentionKind.inCorrection => t('أكمل التصحيح', 'Continue grading'),
      HubAttentionKind.unpublished => t('انشر النتائج', 'Publish results'),
      HubAttentionKind.drafts => t('أكمل', 'Continue'),
    };

/// The short name of a card's exams, on the "Showing" line above the list it narrows.
String hubFocusLabel(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => t('تنتظر التصحيح', 'Waiting for grading'),
      HubAttentionKind.inCorrection => t('تصحيح لم يكتمل', 'Grading not finished'),
      HubAttentionKind.unpublished => t('نتائج لم تُنشر', 'Results not published'),
      HubAttentionKind.drafts => t('مسودات لم تكتمل', 'Unfinished drafts'),
    };

// ─────────────────────────────── one sentence per exam (D-701) ───────────────────────────────

String _questions(int n) =>
    countText(n, ar1: 'سؤال واحد', ar2: 'سؤالان', arFew: '{n} أسئلة', arMany: '{n} سؤالاً', en1: '1 question', en: '{n} questions');

String _answered(int n) => countText(n,
    ar1: 'أجاب طالب واحد',
    ar2: 'أجاب طالبان',
    arFew: 'أجاب {n} طلاب',
    arMany: 'أجاب {n} طالباً',
    en1: '1 student answered',
    en: '{n} students answered',
    ar0: 'لم يُجب أحد بعد',
    en0: 'nobody answered yet');

String _papersLeft(int n) => countText(n,
    ar1: 'ورقة واحدة تنتظر التصحيح',
    ar2: 'ورقتان تنتظران التصحيح',
    arFew: '{n} أوراق تنتظر التصحيح',
    arMany: '{n} ورقة تنتظر التصحيح',
    en1: '1 paper waits for grading',
    en: '{n} papers wait for grading');

String _answersLeft(int n) => countText(n,
    ar1: 'إجابة واحدة تنتظر التصحيح',
    ar2: 'إجابتان تنتظران التصحيح',
    arFew: '{n} إجابات تنتظر التصحيح',
    arMany: '{n} إجابة تنتظر التصحيح',
    en1: '1 answer waits for grading',
    en: '{n} answers wait for grading');

String get _comma => t('، ', ', ');

/// "13 Nov, 11:00": a day read at a glance (the year only when it is not this one).
String hubShortWhen(DateTime utc, {DateTime? now}) {
  final sameYear = AppTime.toZone(utc).year == AppTime.toZone(now ?? DateTime.now().toUtc()).year;
  return '${AppTime.date(utc, pattern: sameYear ? 'd MMM' : 'd MMM y')}$_comma${AppTime.time(utc)}';
}

/// How an exam is sat, in words.
String hubTypeLabel(AllExamType k) => switch (k) {
      AllExamType.online => t('إلكتروني', 'Online'),
      AllExamType.paper => t('على الورق', 'On paper'),
      AllExamType.file => t('ملف امتحان', 'Exam file'),
    };

/// The plain sentence under an exam's name: where it stands, in the teacher's words, with the one count that matters.
/// Drafts carry no date (a draft's start is a placeholder until it is sent).
String hubStatusText(AllExam e, {DateTime? now}) {
  final g = e.grading;
  final paperLike = e.type != AllExamType.online;
  switch (hubStageOf(e, now: now)) {
    case HubStage.drafts:
      if (e.questionCount == 0) return t('مسودة: لا أسئلة بعد', 'Draft: no questions yet');
      final q = _questions(e.questionCount);
      return paperLike ? t('مسودة: $q، لم تُجهَّز للطباعة بعد', 'Draft: $q, not ready to print yet') : t('مسودة: $q، لم تُرسل للطلاب بعد', 'Draft: $q, not sent to students yet');
    case HubStage.running:
      if (hubScheduled(e, now: now)) return t('مجدول: يفتح ${hubShortWhen(e.startsAt!, now: now)}', 'Scheduled: opens ${hubShortWhen(e.startsAt!, now: now)}');
      final open = e.endsAt != null
          ? t('مفتوح حتى ${hubShortWhen(e.endsAt!, now: now)}', 'Open until ${hubShortWhen(e.endsAt!, now: now)}')
          : t('مفتوح بلا موعد انتهاء', 'Open, no end time');
      if (!paperLike) return '$open$_comma${_answered(g?.submitted ?? e.attempts)}';
      if (g == null || g.papers == 0) return open;
      return '$open$_comma${countText(g.papers, ar1: 'رُفعت ورقة واحدة', ar2: 'رُفعت ورقتان', arFew: 'رُفعت {n} أوراق', arMany: 'رُفعت {n} ورقة', en1: '1 paper scanned', en: '{n} papers scanned')}';
    case HubStage.finished:
      final head = e.status == 'archived' ? t('مؤرشف', 'Archived') : t('انتهى', 'Finished');
      if (g == null) return '$head$_comma${_answered(e.attempts)}';
      final left = g.answersOpen + g.reviewOpen;
      if (hubNeedsCorrection(e)) {
        if (left > 0) return '$head: ${_answersLeft(left)}';
        if (paperLike && g.papers == 0) return t('$head: لم تُرفع الأوراق بعد', '$head: papers not scanned yet');
        if (paperLike) return '$head: ${_papersLeft(g.papers)}';
        return '$head: ${_answersLeft(g.submitted)}';
      }
      if (hubCorrectionOf(e) == HubCorrection.inProgress) {
        return left > 0 ? t('التصحيح جارٍ: ${_answersLeft(left)}', 'Grading under way: ${_answersLeft(left)}') : t('التصحيح جارٍ', 'Grading under way');
      }
      if (hubUnpublished(e)) return t('صُحّح: لم تُنشر النتائج للطلاب بعد', 'Graded: results not published to students yet');
      if (g.hasDegrees) {
        if (g.degreesSource == 'import' && !g.resultsPublished) return t('$head: الدرجات مستوردة من Excel', '$head: grades imported from Excel');
        return t('$head: النتائج ظاهرة للطلاب', '$head: students can see the results');
      }
      if (!paperLike && g.submitted == 0) return t('$head: لم يُجب أحد', '$head: nobody answered');
      return t('$head: لا درجات بعد', '$head: no grades yet');
  }
}

/// The tone of the sentence's dot: the teacher owes something, students are sitting it, results wait, done, or nothing to say.
enum HubMood { todo, live, waiting, done, quiet }

HubMood hubMoodOf(AllExam e, {DateTime? now}) {
  switch (hubStageOf(e, now: now)) {
    case HubStage.drafts:
      return HubMood.todo;
    case HubStage.running:
      return hubScheduled(e, now: now) ? HubMood.quiet : HubMood.live;
    case HubStage.finished:
      if (hubNeedsCorrection(e) || hubCorrectionOf(e) == HubCorrection.inProgress) return HubMood.todo;
      if (hubUnpublished(e)) return HubMood.waiting;
      if (e.status == 'archived') return HubMood.quiet;
      return e.grading?.hasDegrees == true ? HubMood.done : HubMood.quiet;
  }
}

// ─────────────────────────────── the one next step and the ⋯ menu (D-701) ───────────────────────────────

/// The ONE thing to do with [e] now: the row's button and the detail panel's primary.
HubAction hubNextStep(AllExam e, {DateTime? now}) {
  final paperLike = e.type != AllExamType.online;
  switch (hubStageOf(e, now: now)) {
    case HubStage.drafts:
      return e.questionCount == 0 ? HubAction.edit : HubAction.publish;
    case HubStage.running:
      // papers collected early and being graded: the grading leads
      if (hubCorrectionOf(e) == HubCorrection.inProgress) return HubAction.correct;
      if (paperLike) return HubAction.deliver;
      // an online exam not open yet: a last look at its questions; once open, its answers as they come
      return hubScheduled(e, now: now) ? HubAction.edit : HubAction.results;
    case HubStage.finished:
      final g = e.grading;
      if (g == null) return HubAction.results;
      if (hubNeedsCorrection(e) || hubCorrectionOf(e) == HubCorrection.inProgress) return HubAction.correct;
      if (g.hasDegrees) return HubAction.getResult;
      if (!paperLike && g.submitted == 0) return HubAction.results;
      return HubAction.addDegrees;
  }
}

/// The next step's words on [e]'s button: the same action reads as the step it is.
String hubNextLabel(AllExam e, {DateTime? now}) {
  final a = hubNextStep(e, now: now);
  return switch (a) {
    HubAction.edit => e.draft ? t('أكمل التعديل', 'Continue editing') : t('راجع الأسئلة', 'Check questions'),
    HubAction.publish => e.type == AllExamType.online ? t('أرسل للطلاب', 'Send to students') : t('انشره للطباعة', 'Publish to print'),
    HubAction.deliver => t('اطبع', 'Print'),
    HubAction.results => hubStageOf(e, now: now) == HubStage.running ? t('تابع الإجابات', 'Follow answers') : t('اعرض النتائج', 'See results'),
    HubAction.correct => hubCorrectionOf(e) == HubCorrection.inProgress ? t('أكمل التصحيح', 'Continue grading') : t('صحّح', 'Grade'),
    HubAction.getResult => hubUnpublished(e) ? t('انشر النتائج', 'Publish results') : t('اعرض النتائج', 'See results'),
    _ => hubActionLabel(a),
  };
}

/// Everything else [e] offers, for its ⋯ menu (the detail panel lists them as quiet links). Nothing the older tabs
/// offered is lost.
List<HubAction> hubMenuActions(AllExam e, {DateTime? now}) {
  final next = hubNextStep(e, now: now);
  final finished = hubActive(e) && hubStageOf(e, now: now) == HubStage.finished;
  final graded = e.grading?.hasDegrees == true;
  return [
    for (final a in [
      HubAction.edit,
      if (e.draft && e.questionCount > 0) HubAction.publish,
      if (e.published && e.type != AllExamType.online) HubAction.deliver,
      if (e.type != AllExamType.file) HubAction.paper,
      if (!e.draft) HubAction.results,
      if (finished) HubAction.correct,
      if (graded) HubAction.getResult,
      if (finished && !graded) HubAction.addDegrees,
      if (finished && hubCanImport(e)) HubAction.importDegrees,
      if (!e.draft && e.courseId != null && !_off(kHubRevisionKey)) HubAction.revision,
      if (hubCanDuplicate(e)) HubAction.duplicate,
    ])
      if (a != next) a,
  ];
}

/// The degrees import needs a course (the roster it matches against) and its kill switch on.
bool hubCanImport(AllExam e) => e.courseId != null && !_off(kHubImportKey);

/// In the "no degrees yet" sheet: is Excel the better way? Once papers or answers exist, correcting them is.
bool hubImportRecommended(AllExam e) {
  final g = e.grading;
  return hubCanImport(e) && (g == null || (g.papers == 0 && g.submitted == 0));
}

String hubActionLabel(HubAction a) => switch (a) {
      HubAction.edit => t('تعديل الأسئلة', 'Edit questions'),
      HubAction.deliver => t('طباعة الأوراق وإرسالها', 'Print and send papers'),
      HubAction.results => t('الإجابات والمحاولات', 'Answers and attempts'),
      HubAction.publish => t('نشر', 'Publish'),
      HubAction.paper => t('ورقة الطباعة', 'Printable paper'),
      HubAction.correct => t('تصحيح', 'Grade'),
      HubAction.getResult => t('النتائج', 'Results'),
      HubAction.addDegrees => t('إضافة الدرجات', 'Add grades'),
      HubAction.importDegrees => t('استيراد الدرجات من Excel', 'Import grades from Excel'),
      HubAction.revision => t('مراجعة الدرجات', 'Grade review'),
      HubAction.duplicate => t('نسخ الاختبار', 'Duplicate'),
    };

// ─────────────────────────────── the detail panel's steps (D-702) ───────────────────────────────

/// The four steps every exam walks through.
enum HubStep { questions, send, grade, results }

enum HubStepState { done, current, upcoming }

/// Which step an action belongs to.
HubStep hubStepOfAction(HubAction a) => switch (a) {
      HubAction.edit || HubAction.duplicate => HubStep.questions,
      HubAction.publish || HubAction.deliver || HubAction.paper => HubStep.send,
      HubAction.correct || HubAction.addDegrees || HubAction.importDegrees || HubAction.revision => HubStep.grade,
      HubAction.results || HubAction.getResult => HubStep.results,
    };

/// The step [e] is on: the step of its next action, except an online exam already sent (scheduled: still on Send;
/// open: the grading waits for its end).
HubStep hubCurrentStep(AllExam e, {DateTime? now}) {
  final next = hubNextStep(e, now: now);
  if (hubStageOf(e, now: now) == HubStage.running && e.type == AllExamType.online && next != HubAction.correct) {
    return hubScheduled(e, now: now) ? HubStep.send : HubStep.grade;
  }
  return hubStepOfAction(next);
}

/// Done, current or still ahead. Every step before the current one is done; a finished exam whose results students
/// can see has all four done.
HubStepState hubStepState(AllExam e, HubStep s, {DateTime? now}) {
  final cur = hubCurrentStep(e, now: now);
  if (s.index < cur.index) return HubStepState.done;
  if (s.index > cur.index) return HubStepState.upcoming;
  final g = e.grading;
  if (s == HubStep.results && g != null && g.hasDegrees && (g.resultsPublished || _afterSubmit(e))) return HubStepState.done;
  return HubStepState.current;
}

String hubStepTitle(HubStep s, AllExam e) => switch (s) {
      HubStep.questions => t('الأسئلة', 'Questions'),
      HubStep.send => e.type == AllExamType.online ? t('الإرسال للطلاب', 'Send to students') : t('الطباعة والتسليم', 'Print and hand out'),
      HubStep.grade => t('التصحيح', 'Grading'),
      HubStep.results => t('النتائج', 'Results'),
    };

/// One short line under a step: what it holds now (null: nothing worth saying).
String? hubStepNote(AllExam e, HubStep s, {DateTime? now}) {
  final g = e.grading;
  final state = hubStepState(e, s, now: now);
  final running = hubStageOf(e, now: now) == HubStage.running;
  switch (s) {
    case HubStep.questions:
      return e.questionCount == 0 ? t('لا أسئلة بعد', 'No questions yet') : _questions(e.questionCount);
    case HubStep.send:
      if (e.draft) return e.type == AllExamType.online ? t('لم يُرسل بعد', 'Not sent yet') : t('لم يُنشر بعد', 'Not published yet');
      if (running) return hubStatusText(e, now: now);
      if (e.endsAt != null) return t('انتهى ${hubShortWhen(e.endsAt!, now: now)}', 'Ended ${hubShortWhen(e.endsAt!, now: now)}');
      return null;
    case HubStep.grade:
      if (state == HubStepState.upcoming) return t('بعد انتهاء الاختبار', 'After the exam ends');
      if (g == null) return null;
      if (state == HubStepState.done) {
        if (g.degreesSource == 'import') return t('درجات من Excel', 'Grades from Excel');
        if (!g.hasDegrees && g.submitted == 0 && g.papers == 0) return t('لم يُجب أحد', 'Nobody answered');
        return t('اكتمل', 'Done');
      }
      if (running && hubCorrectionOf(e) != HubCorrection.inProgress) return t('بعد انتهاء الاختبار', 'After the exam ends');
      final left = g.answersOpen + g.reviewOpen;
      if (left > 0) return _answersLeft(left);
      if (e.type != AllExamType.online) return g.papers == 0 ? t('لم تُرفع الأوراق بعد', 'Papers not scanned yet') : _papersLeft(g.papers);
      if (g.submitted == 0) return t('لم يُجب أحد', 'Nobody answered');
      return g.hasDegrees ? null : _answersLeft(g.submitted);
    case HubStep.results:
      if (state == HubStepState.upcoming || g == null) return null;
      if (state == HubStepState.done) return t('ظاهرة للطلاب', 'Students can see them');
      if (hubUnpublished(e)) return t('لم تُنشر للطلاب بعد', 'Not published to students yet');
      return null;
  }
}

// ─────────────────────────────── the sheets ───────────────────────────────

/// "Ends Thu 5 Nov, 11:00", or what an exam without an end time does.
String hubEndsText(AllExam e) => e.endsAt != null
    ? t('ينتهي ${AppTime.dateTime(e.endsAt!)}', 'Ends ${AppTime.dateTime(e.endsAt!)}')
    : t('بلا موعد انتهاء، يبقى مفتوحاً حتى تغلقه', 'No end time: it stays open until you close it');

/// The explanation in the "not ended yet" sheet.
String hubNotEndedText(AllExam e) => e.endsAt != null
    ? t('موعد انتهائه ${AppTime.dateTime(e.endsAt!)}. يمكنك الانتظار حتى يسلّم الجميع، أو البدء الآن إن كنت جمعت الأوراق مبكراً.',
        'It ends ${AppTime.dateTime(e.endsAt!)}. You can wait until everyone has handed in, or start now if you collected the papers early.')
    : t('ليس له موعد انتهاء، ويبقى مفتوحاً حتى تغلقه. يمكنك البدء الآن إن كنت جمعت الأوراق.',
        'It has no end time and stays open until you close it. You can start now if you have collected the papers.');

// ── Grade papers (D-660) ────────────────────────────────────────────────────────────────────────────────────────────

/// How the papers being graded were answered.
enum GradeKind { bubble, essay }

/// Bubble runs (`exam.bubble`, and automatic correction behind it) and written-paper runs (`exam.essay_run`).
const kHubBubbleKey = 'exam.bubble';
const kHubAutoCorrectKey = 'exam.auto_correct';
const kHubEssayRunKey = 'exam.essay_run';
const kHubAutoGradeKey = 'exam.auto_grade'; // D-808: written-paper runs are AI grading

/// What Grade papers offers under the platform's switches; empty = the action is hidden.
List<GradeKind> hubGradeKinds() => [
      if (!_off(kHubBubbleKey) && !_off(kHubAutoCorrectKey)) GradeKind.bubble,
      if (!_off(kHubEssayRunKey) && !_off(kHubAutoGradeKey)) GradeKind.essay,
    ];

/// The courses papers can be graded in: a run belongs to a course (its students, its results).
List<NewExamPlace> hubGradePlaces(AllExamsData d) => [for (final p in newExamPlaces(d)) if (p.courseId != null) p];

String gradeKindLabel(GradeKind k) => switch (k) {
      GradeKind.bubble => t('أوراق تظليل', 'Bubble sheets'),
      GradeKind.essay => t('أوراق مكتوبة', 'Written papers'),
    };

String gradeKindHint(GradeKind k) => switch (k) {
      GradeKind.bubble => t('صوّر الأوراق المظللة أو امسحها، وتُصحَّح على مفتاح الإجابة', 'Photograph or scan the shaded sheets; they are marked against the answer key'),
      GradeKind.essay => t('صوّر الإجابات المكتوبة، وتُقترح الدرجات من نموذج الإجابة لتراجعها',
          'Photograph the written answers; marks are suggested from the model answer for you to review'),
    };
