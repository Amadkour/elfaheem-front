// A count with its noun on the paper-exam / bubble-sheet screens, through `countText` (lib/core/plural.dart): Arabic
// has 1 / 2 / 3–10 / 11+ forms ("سؤال واحد", "سؤالان", "3 أسئلة", "50 سؤالًا"), so "$n سؤالًا" reads wrong for most
// numbers. [after] = the count follows a preposition (من، في، إلى، بعد …): the dual takes its genitive form
// ("من سؤالين", "إلى طالبين"). English: "1 question" / "n questions". [lang] defaults to the app's language (a printed
// paper passes its own). A round hundred takes the singular after it ("100 سؤال", "200 طالب", as the built-in sheets'
// names say), not the 11–99 form ("100 سؤالًا").
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';

String _n(int n, bool after, String? lang,
        {required String ar1,
        required String ar2,
        required String ar2After,
        required String arFew,
        required String arMany,
        required String en1,
        required String en}) =>
    countText(n,
        ar1: ar1,
        ar2: after ? ar2After : ar2,
        arFew: arFew,
        // 100, 101, 102, 200 …: the singular noun (the first word of "سؤال واحد")
        arMany: n.abs() >= 100 && n.abs() % 100 <= 2 ? '{n} ${ar1.split(' ').first}' : arMany,
        en1: en1,
        en: en,
        lang: lang);

String omrQuestionsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'سؤال واحد', ar2: 'سؤالان', ar2After: 'سؤالين', arFew: '{n} أسئلة', arMany: '{n} سؤالًا', en1: '1 question', en: '{n} questions');

String omrStudentsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'طالب واحد', ar2: 'طالبان', ar2After: 'طالبين', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');

String omrDigitsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'رقم واحد', ar2: 'رقمان', ar2After: 'رقمين', arFew: '{n} أرقام', arMany: '{n} رقمًا', en1: '1 digit', en: '{n} digits');

String omrBoxesText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'خانة واحدة', ar2: 'خانتان', ar2After: 'خانتين', arFew: '{n} خانات', arMany: '{n} خانة', en1: '1 box', en: '{n} boxes');

String omrColumnsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'عمود واحد', ar2: 'عمودان', ar2After: 'عمودين', arFew: '{n} أعمدة', arMany: '{n} عمودًا', en1: '1 column', en: '{n} columns');

String omrPagesText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'صفحة واحدة', ar2: 'صفحتان', ar2After: 'صفحتين', arFew: '{n} صفحات', arMany: '{n} صفحة', en1: '1 page', en: '{n} pages');

String omrFilesText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'ملف واحد', ar2: 'ملفان', ar2After: 'ملفين', arFew: '{n} ملفات', arMany: '{n} ملفًا', en1: '1 file', en: '{n} files');

String omrSheetsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'ورقة واحدة', ar2: 'ورقتان', ar2After: 'ورقتين', arFew: '{n} أوراق', arMany: '{n} ورقة', en1: '1 sheet', en: '{n} sheets');

String omrAnswersText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'إجابة واحدة', ar2: 'إجابتان', ar2After: 'إجابتين', arFew: '{n} إجابات', arMany: '{n} إجابة', en1: '1 answer', en: '{n} answers');

String omrMinutesText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'دقيقة واحدة', ar2: 'دقيقتان', ar2After: 'دقيقتين', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 minute', en: '{n} minutes');

/// "No attempts" / "محاولة واحدة" / "محاولتان" / "3 محاولات" / "11 محاولة" — the exam lists' attempts chip.
String omrAttemptsText(int n, {String? lang}) => countText(n,
    ar0: 'لا محاولات', ar1: 'محاولة واحدة', ar2: 'محاولتان', arFew: '{n} محاولات', arMany: '{n} محاولة',
    en0: 'No attempts', en1: '1 attempt', en: '{n} attempts', lang: lang);

String omrOptionsText(int n, {bool after = false, String? lang}) => _n(n, after, lang,
    ar1: 'اختيار واحد', ar2: 'اختياران', ar2After: 'اختيارين', arFew: '{n} اختيارات', arMany: '{n} اختيارًا', en1: '1 option', en: '{n} options');

/// A question's points: "درجتان", "4 درجات", "1.5 درجة" / "1 pt", "2 pts", "1.5 pts".
String omrPointsText(num v, {String? lang}) {
  if (v == v.roundToDouble()) {
    return countText(v.toInt(), ar1: 'درجة واحدة', ar2: 'درجتان', arFew: '{n} درجات', arMany: '{n} درجة', en1: '1 pt', en: '{n} pts', lang: lang);
  }
  final s = v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return (lang ?? AppConfig.lang) == 'ar' ? '$s درجة' : '$s pts';
}

/// The super admin's bubble sheet library: "4 أنواع" / "4 types".
String omrTypesText(int n, {String? lang}) => _n(n, false, lang,
    ar1: 'نوع واحد', ar2: 'نوعان', ar2After: 'نوعين', arFew: '{n} أنواع', arMany: '{n} نوعًا', en1: '1 type', en: '{n} types');

/// How many of the library's types are published: "4 منشورة" (the types counted, the noun left out) / "4 published".
String omrPublishedText(int n, {String? lang}) => _n(n, false, lang,
    ar1: 'منشور واحد', ar2: 'منشوران', ar2After: 'منشورين', arFew: '{n} منشورة', arMany: '{n} منشورًا', en1: '1 published', en: '{n} published');

/// "3 إصدارات" / "3 versions".
String omrVersionsText(int n, {String? lang}) => _n(n, false, lang,
    ar1: 'إصدار واحد', ar2: 'إصداران', ar2After: 'إصدارين', arFew: '{n} إصدارات', arMany: '{n} إصدارًا', en1: '1 version', en: '{n} versions');

// ── a scanned page named to the person ──────────────────────────────────────────────────────────────────────────

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// "Paper 3" / "الورقة 3": a scanned sheet in a batch's views, by its name in the batch ([label], the server's
/// `page_label`), the same word for the papers read and the ones that need a clearer image.
String omrPaperText(String label) => _t('الورقة $label', 'Paper $label');

/// Where a page came from, in words: "PDF page 4 of scan.pdf" for a page inside a multi-page PDF ([filePage] = the
/// server's `page_file_page`), else the file name alone; "PDF page 4" when the file is hidden (anonymous grading).
/// Never the page number of a photo: every photo is page 1 of itself.
String? omrFilePlace(String? fileName, int? filePage) {
  final f = fileName?.trim() ?? '';
  if (filePage == null) return f.isEmpty ? null : f;
  if (f.isEmpty) return _t('صفحة PDF رقم $filePage', 'PDF page $filePage');
  return _t('صفحة PDF رقم $filePage من $f', 'PDF page $filePage of $f');
}
