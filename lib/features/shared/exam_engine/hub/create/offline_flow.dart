// The offline (paper) exam flow, pure part (D-697): the four answer-sheet layouts the owner set out, which of them fit the
// question mix and which one is the best fit, and how an exam saved before this flow (F1's `sheet_plan`, the D-661
// `answer_format`) reads back into it. No widget and no call lives here.
//
//   1. allInPaper       every answer, multiple choice and true / false included, is written in the question paper
//   2. bubbleMcq        written answers in the paper, a bubble sheet for multiple choice (true / false in the paper)
//   3. bubbleObjective  written answers in the paper, a bubble sheet for multiple choice AND true / false
//   4. questionsOnly    the questions alone, no answer room: marked by hand or on sheets the teacher already has
//
// Saved as `settings.sheet_plan` v2 (`answer_layout`, back contract OFFLINE_FLOW_CONTRACT.md §1, through
// `PUT /exams/{id}/offline-plan`); `answer_format` keeps being written beside it (bubble for 2 / 3, on_paper for 1 / 4)
// so every reader older than this flow (the hub's rows) still understands the exam.
//
// Unit-tested in test/org/offline_flow_test.dart.
library;

import '../../../../admin/admin_common.dart' show asInt, asMap, t;
import 'answer_format.dart';
import 'answer_sheet_plan.dart';

enum PaperLayout { allInPaper, bubbleMcq, bubbleObjective, questionsOnly }

String paperLayoutKey(PaperLayout l) => switch (l) {
      PaperLayout.allInPaper => 'all_in_paper',
      PaperLayout.bubbleMcq => 'paper_plus_bubble_mcq',
      PaperLayout.bubbleObjective => 'paper_plus_bubble_objective',
      PaperLayout.questionsOnly => 'questions_only',
    };

PaperLayout? paperLayoutOfKey(Object? v) {
  for (final l in PaperLayout.values) {
    if (paperLayoutKey(l) == '${v ?? ''}') return l;
  }
  return null;
}

extension PaperLayoutX on PaperLayout {
  bool get usesBubble => this == PaperLayout.bubbleMcq || this == PaperLayout.bubbleObjective;

  /// The format older readers understand.
  AnswerFormat get answerFormat => usesBubble ? AnswerFormat.bubble : AnswerFormat.onPaper;

  /// The question types the bubble sheet holds in this layout (none without a sheet).
  Set<String> get bubbleTypes => switch (this) {
        PaperLayout.bubbleMcq => kMcqTypes,
        PaperLayout.bubbleObjective => const {...kMcqTypes, 'true_false'},
        _ => const <String>{},
      };
}

const kMcqTypes = <String>{'mcq_single', 'mcq_multi'};

/// Below this many objective questions a bubble sheet is not worth printing: the best fit stays the paper.
const kFewObjective = 3;

/// What the questions are made of, as far as the layout cares.
class QuestionMix {
  const QuestionMix({this.mcq = 0, this.trueFalse = 0, this.written = 0, this.isFile = false});

  /// [types]: one per question; [importedObjective] / [importedOther]: questions already on the server (a Forms import),
  /// whose split between multiple choice and true / false is unknown (counted as multiple choice).
  factory QuestionMix.of(Iterable<String> types, {bool isFile = false, int importedObjective = 0, int importedOther = 0}) {
    var mcq = importedObjective, tf = 0, written = importedOther;
    for (final ty in types) {
      if (kMcqTypes.contains(ty)) {
        mcq++;
      } else if (ty == 'true_false') {
        tf++;
      } else {
        written++;
      }
    }
    return QuestionMix(mcq: mcq, trueFalse: tf, written: written, isFile: isFile);
  }

  final int mcq, trueFalse, written;

  /// An uploaded exam file: printed as it is, nothing to put on a bubble sheet.
  final bool isFile;

  int get objective => mcq + trueFalse;
  int get total => objective + written;
}

/// One of the four cards: off with the reason, or on.
typedef LayoutOption = ({PaperLayout layout, bool available, String? why});

/// The cards to show for [mix]. Without the scanner (`exam.omr` off) the two bubble layouts are not shown at all; when
/// they make no sense for the questions they stay, greyed, with the reason.
List<LayoutOption> paperLayoutOptions(QuestionMix mix, {required bool omrOn}) => [
      (layout: PaperLayout.allInPaper, available: true, why: null),
      if (omrOn) ...[
        (layout: PaperLayout.bubbleMcq, available: _why(PaperLayout.bubbleMcq, mix) == null, why: _why(PaperLayout.bubbleMcq, mix)),
        (layout: PaperLayout.bubbleObjective, available: _why(PaperLayout.bubbleObjective, mix) == null, why: _why(PaperLayout.bubbleObjective, mix)),
      ],
      (layout: PaperLayout.questionsOnly, available: true, why: null),
    ];

String? _why(PaperLayout l, QuestionMix m) {
  if (!l.usesBubble) return null;
  if (m.isFile) return t('الملف المرفوع يُطبع كما هو، فلا أسئلة نضعها على ورقة تظليل', 'An uploaded file prints as it is, so there is nothing to put on a bubble sheet');
  if (m.objective == 0) return t('لا أسئلة اختيار من متعدد أو صح وخطأ لتُظلَّل', 'No multiple choice or true / false questions to shade');
  if (l == PaperLayout.bubbleMcq && m.mcq == 0) {
    return t('لا أسئلة اختيار من متعدد. الخيار 3 يضع الصح والخطأ على ورقة التظليل', 'No multiple choice questions. Option 3 puts the true / false on the bubble sheet');
  }
  if (l == PaperLayout.bubbleObjective && m.trueFalse == 0) {
    return t('لا أسئلة صح وخطأ، فهو مثل الخيار 2', 'No true / false questions, so it is the same as option 2');
  }
  return null;
}

bool paperLayoutAvailable(PaperLayout l, QuestionMix mix, {required bool omrOn}) =>
    paperLayoutOptions(mix, omrOn: omrOn).any((o) => o.layout == l && o.available);

/// The best fit for [mix]: the paper when there is little or nothing to shade (or a file); a bubble sheet for multiple
/// choice, with the true / false on it too when there are some (option 3), or alone (option 2).
PaperLayout recommendedPaperLayout(QuestionMix mix, {required bool omrOn}) {
  if (!omrOn || mix.isFile || mix.objective < kFewObjective) return PaperLayout.allInPaper;
  if (mix.trueFalse > 0) return PaperLayout.bubbleObjective;
  return PaperLayout.bubbleMcq;
}

String paperLayoutLabel(PaperLayout l) => switch (l) {
      PaperLayout.allInPaper => t('كل الإجابات في ورقة الأسئلة', 'Everything in the question paper'),
      PaperLayout.bubbleMcq => t('ورقة الأسئلة + ورقة تظليل للاختيار من متعدد', 'Question paper + bubble sheet for multiple choice'),
      PaperLayout.bubbleObjective => t('ورقة الأسئلة + ورقة تظليل للاختيار والصح والخطأ', 'Question paper + bubble sheet for multiple choice and true / false'),
      PaperLayout.questionsOnly => t('الأسئلة فقط', 'Questions only'),
    };

/// A short name for the summary rail and the review.
String paperLayoutShort(PaperLayout l) => switch (l) {
      PaperLayout.allInPaper => t('كل شيء في الورقة', 'All in the paper'),
      PaperLayout.bubbleMcq => t('ورقة تظليل للاختيار', 'Bubble sheet: multiple choice'),
      PaperLayout.bubbleObjective => t('ورقة تظليل للاختيار والصح والخطأ', 'Bubble sheet: choice + true / false'),
      PaperLayout.questionsOnly => t('الأسئلة فقط', 'Questions only'),
    };

String paperLayoutHint(PaperLayout l) => switch (l) {
      PaperLayout.allInPaper =>
        t('يكتب الطالب كل إجاباته في ورقة الأسئلة، ومنها الاختيار والصح والخطأ', 'Students write every answer in the question paper, multiple choice and true / false included'),
      PaperLayout.bubbleMcq => t('المقالي في ورقة الأسئلة، والاختيار من متعدد يُظلَّل ويُصحَّح بالمسح. الصح والخطأ في الورقة',
          'Written answers in the paper; multiple choice is shaded and marked by scanning. True / false is answered in the paper'),
      PaperLayout.bubbleObjective => t('المقالي في ورقة الأسئلة، والاختيار والصح والخطأ يُظلَّلان ويُصحَّحان بالمسح',
          'Written answers in the paper; multiple choice and true / false are shaded and marked by scanning'),
      PaperLayout.questionsOnly => t('بلا أماكن للإجابة: تصحّح يدويًا أو على أوراق لديك بالفعل', 'No answer room: marked by hand, or on sheets you already have'),
    };

// ── the plan on the server (contract §1) ──────────────────────────────────────────────────────────────────────────

/// Where a bubble form came from (contract §1 `bubble.source`).
enum BubbleFormSource { template, imported, designed }

/// The paper part is answered on the machine-read NB2 sheet, or in the booklet a person marks.
enum WrittenSheet { nb2, booklet }

/// `settings.sheet_plan` v2, as the wizard writes it and as every reader reads it back. An old plan (F1's v1, or none at
/// all) reads as the contract's table says, with [version] 1: Deliver keeps routing it exactly as before.
class OfflinePlan {
  const OfflinePlan({
    required this.layout,
    this.version = 2,
    this.writtenSheet = WrittenSheet.nb2,
    this.bubbleSource,
    this.bubbleIds = const [],
    this.bubblePrint = true,
    this.copies = SheetCopies.generic,
    this.fromFile = false,
    this.attributes = const [],
    this.idSource = IdSource.academic,
  });

  final int version;
  final PaperLayout layout;
  final WrittenSheet writtenSheet;

  /// Null without a bubble sheet (layouts 1 and 4).
  final BubbleFormSource? bubbleSource;
  final List<int> bubbleIds;

  /// False = the teacher already has the sheets (F1's `have`).
  final bool bubblePrint;
  final SheetCopies copies;

  /// Per-student copies of an exam with no course: the uploaded list.
  final bool fromFile;

  /// The ordered attribute keys printed on every copy; empty = the server's default.
  final List<String> attributes;
  final IdSource idSource;

  bool get personal => copies == SheetCopies.personal;
  bool get hasBubble => layout.usesBubble;

  /// The NB2 sheet is printed for the paper part.
  bool get nb2 => layout != PaperLayout.questionsOnly && writtenSheet == WrittenSheet.nb2;

  Map<String, dynamic> toJson() => {
        'v': 2,
        'answer_layout': paperLayoutKey(layout),
        'written_sheet': writtenSheet == WrittenSheet.booklet ? 'booklet' : 'NB2',
        'bubble': hasBubble ? {'source': (bubbleSource ?? BubbleFormSource.template).name, 'ids': bubbleIds, 'print': bubblePrint} : null,
        'copies': personal ? 'per_student' : 'one',
        if (personal) 'students': {'source': fromFile ? 'file' : 'course'},
        if (attributes.isNotEmpty) 'attributes': attributes,
        'id_source': idSourceKey(idSource),
        'paper_design': null,
      };

  /// The plan of a saved exam's [settings]; null on an online exam or when nothing says. [templateId]: the exam's
  /// bubble sheet (`omr_template_id`), for a plan older than v2.
  static OfflinePlan? ofSettings(Map settings, {int? templateId}) {
    final raw = asMap(settings['sheet_plan']);
    final v2 = paperLayoutOfKey(raw['answer_layout']);
    if (v2 != null) {
      final b = asMap(raw['bubble']);
      return OfflinePlan(
        layout: v2,
        version: asInt(raw['v'], 2),
        writtenSheet: '${raw['written_sheet'] ?? 'NB2'}' == 'booklet' ? WrittenSheet.booklet : WrittenSheet.nb2,
        bubbleSource: b.isEmpty ? null : BubbleFormSource.values.where((s) => s.name == '${b['source']}').firstOrNull ?? BubbleFormSource.template,
        bubbleIds: [for (final x in (b['ids'] as List?) ?? const []) asInt(x)],
        bubblePrint: b['print'] != false,
        copies: '${raw['copies'] ?? ''}' == 'per_student' ? SheetCopies.personal : SheetCopies.generic,
        fromFile: '${asMap(raw['students'])['source'] ?? ''}' == 'file',
        attributes: [for (final x in (raw['attributes'] as List?) ?? const []) '$x'],
        idSource: idSourceOf(raw['id_source']) ?? IdSource.academic,
      );
    }
    // F1's v1 plan (D-687)
    final v1Bubble = bubbleSourceOf(raw['bubble']);
    if (raw.isNotEmpty && sheetCopiesOf(raw['copies']) != null) {
      return OfflinePlan(
        version: 1,
        layout: v1Bubble != null ? PaperLayout.bubbleObjective : PaperLayout.allInPaper,
        writtenSheet: '${raw['answer_sheet'] ?? ''}' == 'NB2' ? WrittenSheet.nb2 : WrittenSheet.booklet,
        bubbleSource: v1Bubble == null ? null : BubbleFormSource.template,
        bubbleIds: [if (v1Bubble != null && templateId != null) templateId],
        bubblePrint: v1Bubble != BubbleSource.have,
        copies: sheetCopiesOf(raw['copies'])!,
        fromFile: '${raw['students'] ?? ''}' == 'file',
        idSource: idSourceOf(raw['id_source']) ?? IdSource.academic,
      );
    }
    // no plan: the D-661 answer format and F2's print plan
    final layout = switch (answerFormatOf(settings)) {
      AnswerFormat.bubble => PaperLayout.bubbleObjective,
      AnswerFormat.onPaper || AnswerFormat.table => PaperLayout.allInPaper,
      _ => null,
    };
    if (layout == null) return null;
    return OfflinePlan(
      version: 1,
      layout: layout,
      writtenSheet: WrittenSheet.booklet,
      bubbleSource: layout.usesBubble ? BubbleFormSource.template : null,
      bubbleIds: [if (layout.usesBubble && templateId != null) templateId],
      copies: '${asMap(settings['paper_plan'])['mode'] ?? ''}' == 'personal' ? SheetCopies.personal : SheetCopies.generic,
    );
  }
}

/// The layout of a saved exam (see [OfflinePlan.ofSettings]); null on an online exam or when nothing says.
PaperLayout? paperLayoutOf(Map settings) => OfflinePlan.ofSettings(settings)?.layout;

/// One copy per student or generic copies of a saved exam.
SheetCopies? paperCopiesOf(Map settings) => OfflinePlan.ofSettings(settings)?.copies;

// ── the attributes on each copy ───────────────────────────────────────────────────────────────────────────────────

/// "28/30 have it" under an attribute chip; empty when the count is unknown.
String attributeCoverageText(int filled, int total) => total <= 0 ? '' : t('$filled/$total لديهم', '$filled/$total have it');

/// Moves the item at [from] to [to] (the index it lands on after the move), as a reorderable list reports it.
List<T> reorderedList<T>(List<T> list, int from, int to) {
  if (from < 0 || from >= list.length) return list;
  final out = List<T>.of(list);
  final x = out.removeAt(from);
  out.insert(to.clamp(0, out.length), x);
  return out;
}
