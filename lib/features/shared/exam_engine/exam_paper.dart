// The printed exam paper (offline exams): the pure model the PDF and Word writers draw from
// (exam_paper_pdf.dart, exam_paper_docx.dart; the sheet is exam_paper_sheet.dart).
//
// Built from the manager's `GET /exams/{id}` (sections with their questions, keys included): a cover header
// (institution, logo, course, title, date, duration, total), the student box, instructions, an examiner's marks table,
// then every question numbered across sections with room to answer — choice circles, true / false boxes, blanks,
// matching and ordering boxes, ruled lines sized by the points. The answer-key copy fills the same layout in.
//
// Templates: Classic (formal frame, serif, centred crest — finals and midterms), Modern (brand band, cards), Minimal
// (ink-saving black and white), or the creator's own Word file with {{placeholders}} (Word only). Auto = Classic for
// high-stakes exams, Modern otherwise.
//
// Pure (unit-tested): PaperTemplate · resolvePaperTemplate · ExamPaperDoc.fromView · answerLines · choiceLetter ·
// blankPrompt · defaultPaperInstructions · paperPlaceholders.
library;

import 'dart:typed_data';

import '../../../design/export_layout/layout_model.dart' show LayoutDocument;
import '../../admin/admin_common.dart' show asDouble, asInt, asMap, t;
import 'exam_authoring.dart' show ExamView, fmtPoints;
import 'exam_media.dart' show mediaOfBody;
import 'paper/omr_counts.dart';

enum PaperTemplate { auto, classic, modern, minimal, custom }

/// Where the "answer on the paper" table of the choice questions goes (none = circles in the questions only).
enum AnswerTablePlace { none, start, end }

/// Which document a writer draws from the paper (D-663): the question paper with room to answer (today's paper), the
/// question paper that goes with an answer booklet (no answer lines, no table, "answer in the booklet"), or the booklet.
enum PaperPart { full, questions, booklet }

/// One line of the key summary printed on a version's answer key (`GET …/answer-key` `display`).
class PaperKeyLine {
  const PaperKeyLine(this.n, this.display);
  final int n;
  final String display;
}

/// One row of the answer table: a choice question and the letters to circle.
class AnswerTableEntry {
  const AnswerTableEntry(this.number, this.letters, this.correct, {this.multi = false});
  final int number;
  final List<String> letters;
  final Set<int> correct;
  final bool multi;
}

/// The choice questions of [d] as table rows (single and multiple choice; the letters follow the language).
List<AnswerTableEntry> answerTableEntries(ExamPaperDoc d) => [
      for (final s in d.sections)
        for (final q in s.questions)
          if (q.isChoice && q.options.isNotEmpty)
            AnswerTableEntry(q.number, [for (var i = 0; i < q.options.length; i++) choiceLetter(i, rtl: d.rtl)], q.correct, multi: q.type == 'mcq_multi'),
    ];

/// The rows split in [groups] side-by-side groups (a page-friendly grid): rows of at most [groups] entries, in order.
List<List<AnswerTableEntry>> answerTableRows(List<AnswerTableEntry> entries, {int groups = 3}) =>
    [for (var i = 0; i < entries.length; i += groups) entries.sublist(i, i + groups > entries.length ? entries.length : i + groups)];

String paperTemplateLabel(PaperTemplate p) => switch (p) {
      PaperTemplate.auto => t('تلقائي', 'Auto'),
      PaperTemplate.classic => t('رسمي كلاسيكي', 'Classic'),
      PaperTemplate.modern => t('عصري', 'Modern'),
      PaperTemplate.minimal => t('بسيط موفّر للحبر', 'Minimal'),
      PaperTemplate.custom => t('قالب Word الخاص بك', 'Your Word template'),
    };

String paperTemplateHint(PaperTemplate p) => switch (p) {
      PaperTemplate.auto => t('نختار الأنسب: رسمي للامتحانات المهمة، وعصري لغيرها', 'We pick: Classic for important exams, Modern otherwise'),
      PaperTemplate.classic => t('إطار مزدوج وخط عربي أنيق وشعار في المنتصف', 'Double frame, elegant serif, centred crest'),
      PaperTemplate.modern => t('شريط بلون مؤسستك وبطاقات مرتبة', 'A band in your colour, tidy cards'),
      PaperTemplate.minimal => t('أبيض وأسود، أقل حبر وأوراق', 'Black and white, less ink and paper'),
      PaperTemplate.custom => t('ملف .docx فيه {{questions}} — يبقى تصميمه كما هو', 'A .docx holding {{questions}} — its design is kept'),
    };

/// Auto → Classic for high-stakes exams (finals, midterms), Modern otherwise.
PaperTemplate resolvePaperTemplate(PaperTemplate p, {required bool highStakes}) =>
    p == PaperTemplate.auto ? (highStakes ? PaperTemplate.classic : PaperTemplate.modern) : p;

/// Font pair (bundled assets) and Word font names of a built-in template. Word gets fonts every Windows / Office has.
class PaperStyle {
  const PaperStyle({required this.regular, required this.bold, required this.wordFont, required this.wordFontCs, required this.frame,
      required this.band, required this.color});
  final String regular, bold;
  final String wordFont, wordFontCs;

  /// Classic: double page frame. Modern: a coloured title band. Minimal: neither, and no colour.
  final bool frame, band, color;

  static PaperStyle of(PaperTemplate p) => switch (p) {
        PaperTemplate.classic => const PaperStyle(
            regular: 'assets/fonts/cert/Amiri-Regular.ttf', bold: 'assets/fonts/cert/Amiri-Bold.ttf',
            wordFont: 'Times New Roman', wordFontCs: 'Traditional Arabic', frame: true, band: false, color: true),
        PaperTemplate.modern => const PaperStyle(
            regular: 'assets/fonts/plex/IBMPlexSansArabic-Regular.ttf', bold: 'assets/fonts/Bahij_TheSansArabic-Bold.ttf',
            wordFont: 'Segoe UI', wordFontCs: 'Segoe UI', frame: false, band: true, color: true),
        _ => const PaperStyle(
            regular: 'assets/fonts/plex/IBMPlexSansArabic-Regular.ttf', bold: 'assets/fonts/plex/IBMPlexSansArabic-Bold.ttf',
            wordFont: 'Arial', wordFontCs: 'Arial', frame: false, band: false, color: false),
      };
}

/// One question as printed.
class PaperQuestion {
  PaperQuestion({required this.number, required this.type, required this.prompt, required this.points, this.options = const [],
      this.correct = const {}, this.left = const [], this.right = const [], this.pairs = const {}, this.items = const [], this.order = const [],
      this.blanks = 0, this.tfCorrect, this.answerText = '', this.id, this.mediaId, this.mediaAlt = '', this.image, this.imageFailed = false, this.difficulty = ''});
  final int number;

  /// easy / medium / hard as the question bank holds it (the Excel export lists it); empty = not set.
  final String difficulty;

  /// The engine question's id (versions order questions by it); null for a hand-built question.
  final int? id;
  final String type;
  final String prompt;
  final double points;

  /// Choice texts in order; [correct] their indexes (answer key).
  final List<String> options;
  final Set<int> correct;
  final List<String> left, right;
  final Map<String, String> pairs;

  /// Ordering: the items as shown (shuffled by the author's list) and the right order.
  final List<String> items, order;
  final int blanks;
  final bool? tfCorrect;

  /// The question's image (the body's `media`): its id and alt text, and once fetched ([attachPaperImages]) the bytes.
  /// [imageFailed]: the fetch failed, the writers print a placeholder line.
  final String? mediaId;
  final String mediaAlt;
  final Uint8List? image;
  final bool imageFailed;

  bool get hasMedia => mediaId != null;

  PaperQuestion withImage(Uint8List? bytes, {bool failed = false}) => PaperQuestion(
      id: id, number: number, type: type, prompt: prompt, points: points, options: options, correct: correct, left: left, right: right,
      pairs: pairs, items: items, order: order, blanks: blanks, tfCorrect: tfCorrect, answerText: answerText, mediaId: mediaId, mediaAlt: mediaAlt,
      image: bytes, imageFailed: failed, difficulty: difficulty);

  /// What a writer without pictures prints instead.
  String get imagePlaceholder => mediaAlt.isEmpty ? '[image]' : ['[image: ', mediaAlt, ']'].join();

  /// What the answer key prints for open / numeric / blank questions.
  final String answerText;

  bool get isChoice => type == 'mcq_single' || type == 'mcq_multi';
  bool get isOpen => const {'short_answer', 'essay', 'file_upload', 'numeric'}.contains(type);
  int get lines => answerLines(type, points);
}

class PaperSection {
  PaperSection({required this.title, required this.instructions, required this.questions});
  final String title, instructions;
  final List<PaperQuestion> questions;
  double get points => questions.fold(0.0, (s, q) => s + q.points);
}

/// The cover page printed before each copy: its own design (purpose exam_cover, page mode; null = the built-in cover),
/// the university line ({{university}}) and whether the per-question marks grid is drawn in the design's `marks_table`.
class ExamCover {
  const ExamCover({this.design, this.university = '', this.marksTable = true});
  final LayoutDocument? design;
  final String university;
  final bool marksTable;
}

/// Everything a writer needs.
class ExamPaperDoc {
  ExamPaperDoc({required this.institution, required this.course, required this.title, required this.dateText, required this.durationText,
      required this.total, required this.sections, required this.instructions, required this.rtl, this.logo, this.accentHex = '0F7B5F',
      this.showPoints = true, this.seatNumber = true, this.answerKey = false, this.version, this.studentName = '', this.qrPages = const [],
      this.qrSlots = 0, this.answerTable = AnswerTablePlace.none, this.keySummary = const [], this.design, this.cover,
      this.assets = const {}, this.seat = '', this.part = PaperPart.full});

  /// Which document this is: the paper, the paper beside a booklet, or the answer booklet (exam_paper_booklet.dart).
  final PaperPart part;

  /// The engine design of the paper (purpose exam_paper): its header / footer bands and page background replace the
  /// built-in ones (exam_paper_bands.dart). Null = today's Classic / Modern / Minimal, unchanged.
  final LayoutDocument? design;

  /// The cover page printed before the copy; null = none.
  final ExamCover? cover;

  /// The bytes of the designs' image / signature / background asset ids (the designer host resolves them before
  /// rendering). An id missing here is skipped quietly.
  final Map<String, Uint8List> assets;

  /// The student's seat number printed for {{seat}} (a per-student copy).
  final String seat;
  final String institution, course, title, dateText, durationText;

  /// The version's letter printed in the header ("Version A"); null = the exam's own order.
  final String? version;

  /// A per-student copy: the name printed in the student box and the running header, and the QR payload of each
  /// page ([qrPages], page 1 first). [qrSlots] > 0 reserves the QR's room on every page without drawing one (the
  /// page-count pass, so the real copy lays out identically).
  final String studentName;
  final List<String> qrPages;
  final int qrSlots;

  /// The "answer on the paper" table for the choice questions.
  final AnswerTablePlace answerTable;

  /// A version's server key (display strings) printed as a summary on the answer-key copy.
  final List<PaperKeyLine> keySummary;

  bool get qrReserved => qrPages.isNotEmpty || qrSlots > 0;

  ExamPaperDoc copyWith({List<PaperSection>? sections, String? version, String? studentName, List<String>? qrPages, int? qrSlots,
          AnswerTablePlace? answerTable, bool? answerKey, List<PaperKeyLine>? keySummary, String? seat,
          ExamCover? cover, bool dropCover = false, LayoutDocument? design, bool dropDesign = false, Map<String, Uint8List>? assets, PaperPart? part}) =>
      ExamPaperDoc(
        institution: institution, course: course, title: title, dateText: dateText, durationText: durationText, total: total,
        sections: sections ?? this.sections, instructions: instructions, rtl: rtl, logo: logo, accentHex: accentHex, showPoints: showPoints,
        seatNumber: seatNumber, answerKey: answerKey ?? this.answerKey, version: version ?? this.version, studentName: studentName ?? this.studentName,
        qrPages: qrPages ?? this.qrPages, qrSlots: qrSlots ?? this.qrSlots, answerTable: answerTable ?? this.answerTable,
        keySummary: keySummary ?? this.keySummary, design: dropDesign ? null : (design ?? this.design),
        cover: dropCover ? null : (cover ?? this.cover), assets: assets ?? this.assets,
        seat: seat ?? this.seat,
        part: part ?? this.part,
      );

  /// Every value a design's `{{…}}` can name for one copy ([copy] = the per-student paper, default this one): the Word
  /// placeholders plus `version`, `student_name`, `seat`, `university`, `org_name`. `{{page}}` / `{{pages}}` are left
  /// out: the writers fill them per page.
  Map<String, String> paperValues({ExamPaperDoc? copy}) {
    final c = copy ?? this;
    return {
      ...paperPlaceholders(c),
      'org_name': c.institution,
      'version': c.version ?? '',
      // a blank copy: a line to write on instead of nothing after the label
      'student_name': c.studentName.trim().isEmpty ? '____________________' : c.studentName,
      'seat': c.seat.trim().isEmpty ? '________' : c.seat,
      'university': c.cover?.university ?? cover?.university ?? '',
      'exporter': '',
    };
  }

  final double total;
  final List<PaperSection> sections;
  final List<String> instructions;
  final bool rtl;
  final Uint8List? logo;
  final String accentHex;
  final bool showPoints, seatNumber;

  /// The teacher's copy: answers filled in.
  final bool answerKey;

  int get questionCount => sections.fold(0, (s, x) => s + x.questions.length);

  /// Whether any question carries an image.
  bool get hasImages => sections.any((s) => s.questions.any((q) => q.hasMedia));

  /// The manager's exam view → the paper. Questions are numbered across sections; empty sections are left out.
  static ExamPaperDoc fromView(ExamView v, {required String institution, String course = '', String? dateText, required List<String> instructions,
      required bool rtl, Uint8List? logo, String accentHex = '0F7B5F', bool showPoints = true, bool seatNumber = true, bool answerKey = false,
      AnswerTablePlace answerTable = AnswerTablePlace.none}) {
    var n = 0;
    final sections = <PaperSection>[];
    for (final s in v.sections) {
      final qs = <PaperQuestion>[];
      for (final p in s.questions) {
        final q = paperQuestion(++n, p.type, asMap(p.raw['body']), asMap(p.raw['answer']), p.points * s.section.weight, id: p.questionId);
        qs.add(paperDifficulty(q, '${p.raw['difficulty'] ?? asMap(p.raw['body'])['difficulty'] ?? ''}'));
      }
      if (qs.isNotEmpty) sections.add(PaperSection(title: s.section.title.trim(), instructions: s.section.instructions.trim(), questions: qs));
    }
    final e = v.exam;
    return ExamPaperDoc(
      institution: institution.trim(),
      course: course.trim(),
      title: e.title.trim(),
      dateText: dateText ?? '',
      durationText: e.durationMinutes == null ? '' : omrMinutesText(e.durationMinutes!, lang: rtl ? 'ar' : 'en'),
      total: v.maxScore > 0 ? v.maxScore : sections.fold(0.0, (s, x) => s + x.points),
      sections: sections,
      instructions: [for (final l in instructions) if (l.trim().isNotEmpty) l.trim()],
      rtl: rtl,
      logo: logo,
      accentHex: accentHex,
      showPoints: showPoints,
      seatNumber: seatNumber,
      answerKey: answerKey,
      answerTable: answerTable,
    );
  }
}

List<String> _strings(dynamic v) => [for (final x in (v as List?) ?? const []) x is Map ? '${x['text'] ?? x['id'] ?? ''}' : '$x'];

/// One engine question (body + key) as printed.
PaperQuestion paperQuestion(int number, String type, Map<String, dynamic> body, Map<String, dynamic> key, double points, {int? id}) {
  final q = _paperQuestion(number, type, body, key, points, id);
  final m = mediaOfBody(body);
  return m == null ? q : PaperQuestion(
      id: q.id, number: q.number, type: q.type, prompt: q.prompt, points: q.points, options: q.options, correct: q.correct, left: q.left,
      right: q.right, pairs: q.pairs, items: q.items, order: q.order, blanks: q.blanks, tfCorrect: q.tfCorrect, answerText: q.answerText,
      mediaId: m.id, mediaAlt: m.alt);
}

/// [q] with its difficulty label (empty = unchanged).
PaperQuestion paperDifficulty(PaperQuestion q, String difficulty) => difficulty.isEmpty || difficulty == 'null'
    ? q
    : PaperQuestion(
        id: q.id, number: q.number, type: q.type, prompt: q.prompt, points: q.points, options: q.options, correct: q.correct, left: q.left,
        right: q.right, pairs: q.pairs, items: q.items, order: q.order, blanks: q.blanks, tfCorrect: q.tfCorrect, answerText: q.answerText,
        mediaId: q.mediaId, mediaAlt: q.mediaAlt, image: q.image, imageFailed: q.imageFailed, difficulty: difficulty);

/// Fetches every question image of [d] (through [fetch], by question id and media id) BEFORE the page-count and render passes,
/// so both lay out the same. A failed fetch keeps the question and marks it [PaperQuestion.imageFailed]. Same bytes are fetched once.
Future<ExamPaperDoc> attachPaperImages(ExamPaperDoc d, Future<Uint8List> Function(int questionId, String mediaId) fetch) async {
  if (!d.hasImages) return d;
  final sections = <PaperSection>[];
  for (final s in d.sections) {
    final qs = <PaperQuestion>[];
    for (final q in s.questions) {
      if (!q.hasMedia || q.id == null) {
        qs.add(q);
        continue;
      }
      try {
        final b = await fetch(q.id!, q.mediaId!);
        qs.add(b.isEmpty ? q.withImage(null, failed: true) : q.withImage(b));
      } catch (_) {
        qs.add(q.withImage(null, failed: true));
      }
    }
    sections.add(PaperSection(title: s.title, instructions: s.instructions, questions: qs));
  }
  return d.copyWith(sections: sections);
}

PaperQuestion _paperQuestion(int number, String type, Map<String, dynamic> body, Map<String, dynamic> key, double points, int? id) {
  final prompt = '${body['prompt'] ?? ''}'.trim();
  switch (type) {
    case 'mcq_single':
    case 'mcq_multi':
      final raw = (body['options'] as List?) ?? const [];
      final ids = [for (final o in raw) o is Map ? '${o['id']}' : '$o'];
      final right = type == 'mcq_single' ? {'${key['correct']}'} : {for (final c in (key['correct'] as List?) ?? const []) '$c'};
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, options: _strings(raw),
          correct: {for (var i = 0; i < ids.length; i++) if (right.contains(ids[i])) i});
    case 'true_false':
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, tfCorrect: key['correct'] is bool ? key['correct'] as bool : null);
    case 'fill_blank':
      final blanks = (key['blanks'] as List?) ?? const [];
      final n = asInt(body['blanks_count'], blanks.length);
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, blanks: n < 1 ? 1 : n,
          answerText: [for (final b in blanks) b is List ? (b.isEmpty ? '' : '${b.first}') : '$b'].join(' · '));
    case 'matching':
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, left: _strings(body['left']), right: _strings(body['right']),
          pairs: {for (final e in asMap(key['pairs']).entries) e.key: '${e.value}'});
    case 'ordering':
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, items: _strings(body['items']), order: _strings(key['order']));
    case 'numeric':
      final unit = (body['units'] as List?)?.isNotEmpty == true ? ' ${(body['units'] as List).first}' : '';
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points, answerText: key['value'] == null ? '' : '${key['value']}$unit');
    default:
      final model = '${key['model'] ?? ''}'.trim();
      final rubric = [for (final c in (key['rubric'] as List?) ?? const []) if (c is Map) '• ${c['criterion']} (${fmtPoints(asDouble(c['points']))})'];
      return PaperQuestion(id: id, number: number, type: type, prompt: prompt, points: points,
          answerText: [if (model.isNotEmpty) model, ...rubric].join('\n'));
  }
}

/// Ruled answer lines: none for objective types, 1–2 for numeric / short answers, essays by their points (4–16).
int answerLines(String type, double points) => switch (type) {
      'numeric' => 1,
      'short_answer' => points > 3 ? 3 : 2,
      'essay' || 'file_upload' => (points * 1.5 + 3).round().clamp(4, 16),
      _ => 0,
    };

/// Choice letters: أ ب ج د … in Arabic, A B C D … in English.
String choiceLetter(int i, {required bool rtl}) {
  const ar = ['أ', 'ب', 'ج', 'د', 'هـ', 'و', 'ز', 'ح', 'ط', 'ي'];
  if (rtl) return i < ar.length ? ar[i] : '${i + 1}';
  return i < 26 ? String.fromCharCode(65 + i) : '${i + 1}';
}

/// "(أ)" in Arabic (a closing bracket alone mirrors in RTL text), "A)" in English.
String choiceLabel(int i, {required bool rtl}) => rtl ? '(${choiceLetter(i, rtl: true)})' : '${choiceLetter(i, rtl: false)})';

/// "The ___ is …" with each run of 3+ underscores as a dotted blank; with no marks in the text, the blanks follow it.
String blankPrompt(String prompt, int blanks) {
  const gap = '……………………';
  final re = RegExp(r'_{3,}');
  if (re.hasMatch(prompt)) return prompt.replaceAll(re, gap);
  return [prompt, for (var i = 0; i < blanks; i++) '(${i + 1}) $gap'].join('\n');
}

/// Sensible exam-room instructions (editable in the sheet).
List<String> defaultPaperInstructions({required bool rtl, required int questions, required String duration}) => rtl
    ? [
        'اكتب اسمك ورقمك بوضوح في المكان المخصص.',
        'عدد الأسئلة $questions${duration.isEmpty ? '' : '، وزمن الامتحان $duration'}.',
        'أجب عن جميع الأسئلة بالقلم الأزرق أو الأسود.',
        'لا يُسمح باستخدام الهاتف المحمول أو أي وسيلة اتصال.',
      ]
    : [
        'Write your name and ID clearly in the box.',
        '$questions questions${duration.isEmpty ? '' : ', $duration'}.',
        'Answer every question in blue or black pen.',
        'Mobile phones and any other devices are not allowed.',
      ];

/// Labels the writers share.
class PaperWords {
  const PaperWords(this.rtl);
  final bool rtl;
  String get name => rtl ? 'اسم الطالب' : 'Student name';
  String get id => rtl ? 'الرقم الجامعي / الأكاديمي' : 'Student ID';
  String get group => rtl ? 'الشعبة / الفصل' : 'Class / group';
  String get seat => rtl ? 'رقم الجلوس' : 'Seat no.';
  String get course => rtl ? 'المقرر' : 'Course';
  String get date => rtl ? 'التاريخ' : 'Date';
  String get duration => rtl ? 'الزمن' : 'Time';
  String get total => rtl ? 'الدرجة الكلية' : 'Total marks';
  String get instructions => rtl ? 'تعليمات' : 'Instructions';
  String get question => rtl ? 'السؤال' : 'Question';
  String get marks => rtl ? 'الدرجة' : 'Marks';
  String get score => rtl ? 'درجة الطالب' : 'Score';
  String get examiner => rtl ? 'المصحح' : 'Examiner';
  String get reviewer => rtl ? 'المراجع' : 'Checked by';
  String get sum => rtl ? 'المجموع' : 'Total';
  String get trueW => rtl ? 'صح' : 'True';
  String get falseW => rtl ? 'خطأ' : 'False';
  String get answerKey => rtl ? 'نموذج الإجابة — نسخة المعلم' : 'Answer key — teacher\'s copy';
  String get end => rtl ? 'انتهت الأسئلة — بالتوفيق' : 'End of the exam — good luck';
  String get turnOver => rtl ? 'تابع في الصفحة التالية' : 'Please turn over';
  String get orderHint => rtl ? 'رتّب بكتابة الرقم في المربع' : 'Number the boxes in the right order';
  String get matchHint => rtl ? 'اكتب حرف الإجابة في القوس' : 'Write the matching letter in the brackets';
  String get chooseMany => rtl ? '(اختر كل الإجابات الصحيحة)' : '(choose every correct answer)';
  String version(String code) => rtl ? 'النموذج $code' : 'Version $code';
  String get answerTableTitle => rtl ? 'جدول الإجابة — ضع دائرة حول الحرف الصحيح' : 'Answer table — circle the correct letter';
  String get keySummaryTitle => rtl ? 'مفتاح الإجابة' : 'Answer key';
  String page(int n, int of) => rtl ? 'صفحة $n من $of' : 'Page $n of $of';
  String pts(double p) => rtl ? '${fmtPoints(p)} ${p == 1 ? 'درجة' : 'درجات'}' : '${fmtPoints(p)} ${p == 1 ? 'mark' : 'marks'}';
  String sectionN(int i) => rtl ? 'القسم ${i + 1}' : 'Part ${i + 1}';
}

/// The placeholders a custom Word template may hold (also listed in the sheet).
Map<String, String> paperPlaceholders(ExamPaperDoc d) => {
      'institution': d.institution,
      'org': d.institution,
      'course': d.course,
      'title': d.title,
      'date': d.dateText,
      'duration': d.durationText,
      'total': fmtPoints(d.total),
      'questions_count': '${d.questionCount}',
      'instructions': d.instructions.join('\n'),
    };
