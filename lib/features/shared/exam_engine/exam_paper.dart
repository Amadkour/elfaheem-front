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

import '../../admin/admin_common.dart' show asDouble, asInt, asMap, t;
import 'exam_authoring.dart' show ExamView, fmtPoints;
import 'paper/omr_counts.dart';

enum PaperTemplate { auto, classic, modern, minimal, custom }

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
      this.blanks = 0, this.tfCorrect, this.answerText = ''});
  final int number;
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

/// Everything a writer needs.
class ExamPaperDoc {
  ExamPaperDoc({required this.institution, required this.course, required this.title, required this.dateText, required this.durationText,
      required this.total, required this.sections, required this.instructions, required this.rtl, this.logo, this.accentHex = '0F7B5F',
      this.showPoints = true, this.seatNumber = true, this.answerKey = false});
  final String institution, course, title, dateText, durationText;
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

  /// The manager's exam view → the paper. Questions are numbered across sections; empty sections are left out.
  static ExamPaperDoc fromView(ExamView v, {required String institution, String course = '', String? dateText, required List<String> instructions,
      required bool rtl, Uint8List? logo, String accentHex = '0F7B5F', bool showPoints = true, bool seatNumber = true, bool answerKey = false}) {
    var n = 0;
    final sections = <PaperSection>[];
    for (final s in v.sections) {
      final qs = <PaperQuestion>[];
      for (final p in s.questions) {
        qs.add(paperQuestion(++n, p.type, asMap(p.raw['body']), asMap(p.raw['answer']), p.points * s.section.weight));
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
    );
  }
}

List<String> _strings(dynamic v) => [for (final x in (v as List?) ?? const []) x is Map ? '${x['text'] ?? x['id'] ?? ''}' : '$x'];

/// One engine question (body + key) as printed.
PaperQuestion paperQuestion(int number, String type, Map<String, dynamic> body, Map<String, dynamic> key, double points) {
  final prompt = '${body['prompt'] ?? ''}'.trim();
  switch (type) {
    case 'mcq_single':
    case 'mcq_multi':
      final raw = (body['options'] as List?) ?? const [];
      final ids = [for (final o in raw) o is Map ? '${o['id']}' : '$o'];
      final right = type == 'mcq_single' ? {'${key['correct']}'} : {for (final c in (key['correct'] as List?) ?? const []) '$c'};
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, options: _strings(raw),
          correct: {for (var i = 0; i < ids.length; i++) if (right.contains(ids[i])) i});
    case 'true_false':
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, tfCorrect: key['correct'] is bool ? key['correct'] as bool : null);
    case 'fill_blank':
      final blanks = (key['blanks'] as List?) ?? const [];
      final n = asInt(body['blanks_count'], blanks.length);
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, blanks: n < 1 ? 1 : n,
          answerText: [for (final b in blanks) b is List ? (b.isEmpty ? '' : '${b.first}') : '$b'].join(' · '));
    case 'matching':
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, left: _strings(body['left']), right: _strings(body['right']),
          pairs: {for (final e in asMap(key['pairs']).entries) e.key: '${e.value}'});
    case 'ordering':
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, items: _strings(body['items']), order: _strings(key['order']));
    case 'numeric':
      final unit = (body['units'] as List?)?.isNotEmpty == true ? ' ${(body['units'] as List).first}' : '';
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points, answerText: key['value'] == null ? '' : '${key['value']}$unit');
    default:
      final model = '${key['model'] ?? ''}'.trim();
      final rubric = [for (final c in (key['rubric'] as List?) ?? const []) if (c is Map) '• ${c['criterion']} (${fmtPoints(asDouble(c['points']))})'];
      return PaperQuestion(number: number, type: type, prompt: prompt, points: points,
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
