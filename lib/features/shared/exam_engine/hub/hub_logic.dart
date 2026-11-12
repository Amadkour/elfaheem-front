// The Exam Hub's decisions (D-350), all of them pure: which list an exam is in, what its flag says, what a tap on it
// does, what needs the teacher now. Everything comes from the ONE list call (`loadAllExams`, `grading` of each item);
// a server without `grading` leaves every flag out and a tap goes straight to the flow. `exam_hub_screen.dart` draws it.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../admin/admin_common.dart' show t;
import '../exam_all.dart';

/// The hub's three lists: tab Creation, and the two sides of tab Results & Correction.
enum HubSurface { creation, correction, results }

/// The flag of the Correction list.
enum HubCorrection { notCorrected, inProgress, notEnded, corrected }

/// The chips of the Results list (null = all).
enum HubResultsFilter { hasDegrees, noDegrees, unpublished }

/// Everything a person can do to an exam from the hub.
enum HubAction { edit, deliver, results, publish, paper, correct, getResult, addDegrees, importDegrees, revision }

/// Kill switches the hub respects on its own buttons (the servers refuse them too).
const kHubImportKey = 'exam.results.import';
const kHubRevisionKey = 'exam.grade_review';

bool _off(String key) => AppConfig.disableList.contains(key);

/// Published or closed: drafts have nothing to correct, the archive is out of the way.
bool hubActive(AllExam e) => e.status != 'draft' && e.status != 'archived';

/// Did the server send the flags at all?
bool hubHasFlags(AllExamsData d) => d.exams.any((e) => e.grading != null);

/// The Correction flag; null on a server without `grading`, or for a draft / archived exam.
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
  return g.hasDegrees && !g.resultsPublished && '${e.raw['results_policy'] ?? ''}' != 'after_submit';
}

bool _matches(AllExamsData d, AllExam e, List<String> words) {
  if (words.isEmpty) return true;
  final hay = '${e.title} ${d.courseName(e) ?? ''} ${d.orgName(e) ?? ''}'.toLowerCase();
  return words.every(hay.contains);
}

List<String> _words(String q) => q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

int _newestFirst(AllExam a, AllExam b) {
  final wa = a.endsAt ?? a.when, wb = b.endsAt ?? b.when;
  if (wa != null && wb != null && wa != wb) return wb.compareTo(wa);
  return b.id.compareTo(a.id);
}

/// The order of the Correction list: what waits first, what is done last.
int _correctionRank(AllExam e) => switch (hubCorrectionOf(e)) {
      HubCorrection.notCorrected => hubNeedsCorrection(e) ? 0 : 3,
      HubCorrection.inProgress => 1,
      HubCorrection.notEnded => 2,
      HubCorrection.corrected => 4,
      null => 2,
    };

/// The Correction list, [only] = one flag.
List<AllExam> hubCorrectionList(AllExamsData d, {String query = '', HubCorrection? only}) {
  final words = _words(query);
  final out = d.exams.where((e) => hubActive(e) && _matches(d, e, words) && (only == null || hubCorrectionOf(e) == only)).toList();
  out.sort((a, b) {
    final r = _correctionRank(a).compareTo(_correctionRank(b));
    return r != 0 ? r : _newestFirst(a, b);
  });
  return out;
}

/// How many exams each Correction chip holds (null = all).
Map<HubCorrection?, int> hubCorrectionCounts(AllExamsData d, {String query = ''}) => {
      null: hubCorrectionList(d, query: query).length,
      for (final k in HubCorrection.values) k: hubCorrectionList(d, query: query, only: k).length,
    };

bool _inResults(AllExam e, HubResultsFilter? f) {
  final g = e.grading;
  return switch (f) {
    null => true,
    HubResultsFilter.hasDegrees => g?.hasDegrees == true,
    HubResultsFilter.noDegrees => g != null && !g.hasDegrees,
    HubResultsFilter.unpublished => hubUnpublished(e),
  };
}

int _resultsRank(AllExam e) {
  final g = e.grading;
  if (g == null) return 1;
  if (hubUnpublished(e)) return 0;
  if (!g.hasDegrees) return g.ended ? 1 : 3;
  return 2;
}

/// The Results list, [only] = one chip.
List<AllExam> hubResultsList(AllExamsData d, {String query = '', HubResultsFilter? only}) {
  final words = _words(query);
  final out = d.exams.where((e) => hubActive(e) && _matches(d, e, words) && _inResults(e, only)).toList();
  out.sort((a, b) {
    final r = _resultsRank(a).compareTo(_resultsRank(b));
    return r != 0 ? r : _newestFirst(a, b);
  });
  return out;
}

Map<HubResultsFilter?, int> hubResultsCounts(AllExamsData d, {String query = ''}) => {
      null: hubResultsList(d, query: query).length,
      for (final k in HubResultsFilter.values) k: hubResultsList(d, query: query, only: k).length,
    };

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

// ─────────────────────────────── what needs the teacher now ───────────────────────────────

enum HubAttentionKind { toCorrect, inCorrection, unpublished, drafts }

class HubAttention {
  const HubAttention(this.kind, this.count);
  final HubAttentionKind kind;
  final int count;
}

/// The smart header: most urgent first, only what is not zero. Nothing on a server without `grading`.
List<HubAttention> hubAttention(AllExamsData d) {
  if (!hubHasFlags(d)) return const [];
  int n(bool Function(AllExam) f) => d.exams.where(f).length;
  return [
    for (final a in [
      HubAttention(HubAttentionKind.toCorrect, n(hubNeedsCorrection)),
      HubAttention(HubAttentionKind.inCorrection, n((e) => hubCorrectionOf(e) == HubCorrection.inProgress)),
      HubAttention(HubAttentionKind.unpublished, n(hubUnpublished)),
      HubAttention(HubAttentionKind.drafts, n((e) => e.draft)),
    ])
      if (a.count > 0) a,
  ];
}

String hubAttentionText(HubAttention a) => switch (a.kind) {
      HubAttentionKind.toCorrect => countText(a.count,
          ar1: 'اختبار واحد ينتظر التصحيح',
          ar2: 'اختباران ينتظران التصحيح',
          arFew: '{n} اختبارات تنتظر التصحيح',
          arMany: '{n} اختباراً تنتظر التصحيح',
          en1: '1 exam waiting to be corrected',
          en: '{n} exams waiting to be corrected'),
      HubAttentionKind.inCorrection => countText(a.count,
          ar1: 'اختبار واحد لم يكتمل تصحيحه',
          ar2: 'اختباران لم يكتمل تصحيحهما',
          arFew: '{n} اختبارات لم يكتمل تصحيحها',
          arMany: '{n} اختباراً لم يكتمل تصحيحها',
          en1: '1 correction to finish',
          en: '{n} corrections to finish'),
      HubAttentionKind.unpublished => countText(a.count,
          ar1: 'نتيجة واحدة لم تُنشر',
          ar2: 'نتيجتان لم تُنشرا',
          arFew: '{n} نتائج لم تُنشر',
          arMany: '{n} نتيجة لم تُنشر',
          en1: '1 result not published',
          en: '{n} results not published'),
      HubAttentionKind.drafts => countText(a.count,
          ar1: 'مسودة واحدة لم تكتمل',
          ar2: 'مسودتان لم تكتملا',
          arFew: '{n} مسودات لم تكتمل',
          arMany: '{n} مسودة لم تكتمل',
          en1: '1 draft to finish',
          en: '{n} drafts to finish'),
    };

String hubAttentionAction(HubAttentionKind k) => switch (k) {
      HubAttentionKind.toCorrect => t('صحّح الآن', 'Correct now'),
      HubAttentionKind.inCorrection => t('أكمل التصحيح', 'Continue'),
      HubAttentionKind.unpublished => t('راجع وانشر', 'Review and publish'),
      HubAttentionKind.drafts => t('أكمل المسودات', 'Open drafts'),
    };

// ─────────────────────────────── a tap and the menu ───────────────────────────────

/// What a tap on the exam (or its main button) does on that list.
HubAction hubMainAction(AllExam e, HubSurface s) => switch (s) {
      HubSurface.creation => e.draft ? HubAction.edit : (e.published ? HubAction.deliver : HubAction.results),
      HubSurface.correction => hubCorrectionOf(e) == HubCorrection.corrected ? HubAction.getResult : HubAction.correct,
      HubSurface.results => e.grading == null || e.grading!.hasDegrees ? HubAction.getResult : HubAction.addDegrees,
    };

/// Everything else the exam offers there. Nothing a person could do from "All exams" is lost.
List<HubAction> hubMoreActions(AllExam e, HubSurface s) {
  final main = hubMainAction(e, s);
  final revision = e.courseId != null && !_off(kHubRevisionKey);
  switch (s) {
    case HubSurface.creation:
      return [
        if (main != HubAction.edit) HubAction.edit,
        if (!e.draft && main != HubAction.results) HubAction.results,
        if (e.draft) HubAction.publish,
        if (e.type != AllExamType.file) HubAction.paper,
      ];
    case HubSurface.correction:
      return [
        if (main != HubAction.correct) HubAction.correct,
        if (main != HubAction.getResult && e.grading?.hasDegrees == true) HubAction.getResult,
        if (revision) HubAction.revision,
      ];
    case HubSurface.results:
      return [
        if (revision) HubAction.revision,
        if (hubCanImport(e) && main != HubAction.addDegrees) HubAction.importDegrees,
        HubAction.correct,
      ];
  }
}

/// The degrees import needs a course (the roster it matches against) and its kill switch on.
bool hubCanImport(AllExam e) => e.courseId != null && !_off(kHubImportKey);

/// In the "no degrees yet" sheet: is Excel the better way? Once papers or answers exist, correcting them is.
bool hubImportRecommended(AllExam e) {
  final g = e.grading;
  return hubCanImport(e) && (g == null || (g.papers == 0 && g.submitted == 0));
}

String hubActionLabel(HubAction a) => switch (a) {
      HubAction.edit => t('تعديل', 'Edit'),
      HubAction.deliver => t('تسليم الاختبار', 'Deliver'),
      HubAction.results => t('النتائج', 'Results'),
      HubAction.publish => t('نشر', 'Publish'),
      HubAction.paper => t('ورقة الطباعة', 'Printable paper'),
      HubAction.correct => t('تصحيح', 'Correct'),
      HubAction.getResult => t('عرض النتيجة', 'Get result'),
      HubAction.addDegrees => t('إضافة الدرجات', 'Add degrees'),
      HubAction.importDegrees => t('استيراد من Excel', 'Import from Excel'),
      HubAction.revision => t('مراجعة الاختبار', 'Exam revision'),
    };

// ─────────────────────────────── texts ───────────────────────────────

String hubCorrectionLabel(HubCorrection c) => switch (c) {
      HubCorrection.notCorrected => t('لم يُصحَّح', 'Not corrected'),
      HubCorrection.inProgress => t('جارٍ التصحيح', 'In progress'),
      HubCorrection.notEnded => t('لم ينتهِ بعد', 'Not ended yet'),
      HubCorrection.corrected => t('تم التصحيح', 'Corrected'),
    };

String hubResultsFilterLabel(HubResultsFilter f) => switch (f) {
      HubResultsFilter.hasDegrees => t('بها درجات', 'Has degrees'),
      HubResultsFilter.noDegrees => t('بلا درجات', 'No degrees'),
      HubResultsFilter.unpublished => t('لم تُنشر', 'Not published'),
    };

/// "Ends Thu 5 Nov, 11:00", or what an exam without an end time does.
String hubEndsText(AllExam e) => e.endsAt != null
    ? t('ينتهي ${AppTime.dateTime(e.endsAt!)}', 'Ends ${AppTime.dateTime(e.endsAt!)}')
    : t('بلا موعد انتهاء، يبقى مفتوحاً حتى تغلقه', 'No end time: it stays open until you close it');

/// One line under the flag: where the correction stands.
String? hubCorrectionDetail(AllExam e) {
  final g = e.grading;
  if (g == null) return null;
  final parts = <String>[
    if (g.papers > 0) countText(g.papers, ar1: 'ورقة واحدة', ar2: 'ورقتان', arFew: '{n} أوراق', arMany: '{n} ورقة', en1: '1 paper', en: '{n} papers'),
    if (g.submitted > 0) countText(g.submitted, ar1: 'تسليم واحد', ar2: 'تسليمان', arFew: '{n} تسليمات', arMany: '{n} تسليماً', en1: '1 submission', en: '{n} submissions'),
    if (g.reviewOpen > 0) countText(g.reviewOpen, ar1: 'عنصر للمراجعة', ar2: 'عنصران للمراجعة', arFew: '{n} عناصر للمراجعة', arMany: '{n} عنصراً للمراجعة', en1: '1 to review', en: '{n} to review'),
    if (g.answersOpen > 0) countText(g.answersOpen, ar1: 'إجابة تنتظر درجة', ar2: 'إجابتان تنتظران درجة', arFew: '{n} إجابات تنتظر درجة', arMany: '{n} إجابة تنتظر درجة', en1: '1 answer to mark', en: '{n} answers to mark'),
  ];
  if (hubCorrectionOf(e) == HubCorrection.notEnded) return hubEndsText(e);
  if (parts.isNotEmpty) return parts.join(' · ');
  if (hubCorrectionOf(e) == HubCorrection.notCorrected) {
    return e.type == AllExamType.online
        ? t('لم يسلّم أحد إجابات', 'Nobody submitted answers')
        : t('لم تُرفع أوراق بعد', 'No papers scanned yet');
  }
  return null;
}

/// The degrees flag of the Results list.
String hubDegreesLabel(ExamGrading g) {
  if (!g.hasDegrees) return t('لا درجات بعد', 'No degrees yet');
  return g.degreesSource == 'import' ? t('درجات من ملف Excel', 'Degrees from Excel') : t('توجد درجات', 'Has degrees');
}

/// The explanation in the "not ended yet" sheet.
String hubNotEndedText(AllExam e) => e.endsAt != null
    ? t('موعد انتهائه ${AppTime.dateTime(e.endsAt!)}. يمكنك الانتظار حتى يسلّم الجميع، أو البدء الآن إن كنت جمعت الأوراق مبكراً.',
        'It ends ${AppTime.dateTime(e.endsAt!)}. You can wait until everyone has handed in, or start now if you collected the papers early.')
    : t('ليس له موعد انتهاء، ويبقى مفتوحاً حتى تغلقه. يمكنك البدء الآن إن كنت جمعت الأوراق.',
        'It has no end time and stays open until you close it. You can start now if you have collected the papers.');

// ── the action row and Grade papers (D-660) ────────────────────────────────────────────────────────────────────────

/// The hub's four ways in, above the tabs.
enum HubQuickAction { newExam, grade, previous, results }

/// How the papers being graded were answered.
enum GradeKind { bubble, essay }

/// Bubble runs (`exam.bubble`, and automatic correction behind it) and written-paper runs (`exam.essay_run`).
const kHubBubbleKey = 'exam.bubble';
const kHubAutoCorrectKey = 'exam.auto_correct';
const kHubEssayRunKey = 'exam.essay_run';

/// What Grade papers offers under the platform's switches; empty = the action is hidden.
List<GradeKind> hubGradeKinds() => [
      if (!_off(kHubBubbleKey) && !_off(kHubAutoCorrectKey)) GradeKind.bubble,
      if (!_off(kHubEssayRunKey)) GradeKind.essay,
    ];

/// The action row, Grade papers only while it has something to offer.
List<HubQuickAction> hubQuickActions() => [
      HubQuickAction.newExam,
      if (hubGradeKinds().isNotEmpty) HubQuickAction.grade,
      HubQuickAction.previous,
      HubQuickAction.results,
    ];

String hubQuickLabel(HubQuickAction a) => switch (a) {
      HubQuickAction.newExam => t('اختبار جديد', 'New exam'),
      HubQuickAction.grade => t('تصحيح أوراق', 'Grade papers'),
      HubQuickAction.previous => t('الاختبارات السابقة', 'Previous exams'),
      HubQuickAction.results => t('النتائج', 'Results'),
    };

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
