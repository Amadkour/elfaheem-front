// Exam Hub, delivery (D-354): the pure part. Printed identifiers (`settings.print_identifiers`), the roster values behind
// them, the Excel import, email deliveries and the server codes in plain words. The screens are identifier_plan_step.dart
// and exam_deliver_screen.dart; the heavy paper work is deliver_build.dart.
library;

import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../../../../admin/admin_common.dart' show asInt, asMapList, t;
import '../../exam_authoring.dart' show parseEngineUtc;
import '../../exam_engine_api.dart' show EngineResult, engineCall;
import '../../exam_paper_bands.dart' show PaperPrintedId, kPaperMaxIdentifiers;
import '../../paper/exam_setup.dart';

/// Kill switch of the email part of delivery.
const kDeliverEmailFeatureKey = 'exam.deliver_email';

/// A printed page is white with dark ink in every theme, dark mode included: these describe the paper, not the app, so
/// they are the one place delivery writes colours by hand. Anything around the page uses `context.colors`.
abstract final class PaperInk {
  static const sheet = Color(0xFFFFFFFF);
  static const text = Color(0xFF1F2933);
  static const muted = Color(0xFF6B7280);
  static const rule = Color(0xFFB9C1CA);
  static const placeholder = Color(0xFFE1E5EA);
}

/// One upload round. Production nginx caps the exam API at 10 MB: 9 leaves room for the multipart framing.
const kDeliverRoundBytes = 9 * 1024 * 1024;

/// What one press of Print makes.
enum DeliverScope { students, versions, blank }

/// What the wizard planned to print (`settings.paper_plan`); null on an exam made any other way.
class DeliverPlan {
  const DeliverPlan({required this.personal, this.versions = 1});
  final bool personal;
  final int versions;

  static DeliverPlan? ofSettings(Object? settings) {
    final p = settings is Map ? settings['paper_plan'] : null;
    if (p is! Map) return null;
    final mode = '${p['mode'] ?? ''}';
    if (mode != 'personal' && mode != 'versions') return null;
    return DeliverPlan(personal: mode == 'personal', versions: asInt(p['versions'], 1));
  }
}

/// The choice Deliver opens on. Personal copies need a paper exam with students; with no plan they are still the default.
DeliverScope deliverOpeningScope(DeliverPlan? plan, {required bool paper, required bool hasRoster}) {
  if (!paper || !hasRoster) return DeliverScope.versions;
  return plan == null || plan.personal ? DeliverScope.students : DeliverScope.versions;
}

/// The versions the plan asked for and nobody has made (the wizard makes them on Finish; a saved draft published from the
/// list never got there). Null when there is nothing to offer, which includes a teacher who has made their own number.
int? deliverVersionsOwed(DeliverPlan? plan, int made) => plan != null && !plan.personal && plan.versions > 1 && made < 2 ? plan.versions : null;

/// One identifier printed on each copy.
class PrintedIdSpec {
  const PrintedIdSpec({required this.source, this.key, required this.labelAr, required this.labelEn});
  final String source;
  final String? key;
  final String labelAr, labelEn;

  IdentifierChoice get choice => IdentifierChoice(source, key);
  String get id => choice.id;
  String get label => t(labelAr.isEmpty ? labelEn : labelAr, labelEn.isEmpty ? labelAr : labelEn);

  /// What a blank copy shows: the label, room to write.
  PaperPrintedId get blank => PaperPrintedId(labelAr: labelAr, labelEn: labelEn);

  Map<String, dynamic> toJson() => {'source': source, 'key': key, 'label_ar': labelAr, 'label_en': labelEn};

  static PrintedIdSpec? fromJson(Object? v) {
    if (v is! Map || '${v['source'] ?? ''}'.isEmpty) return null;
    final k = v['key'];
    return PrintedIdSpec(source: '${v['source']}', key: k == null || '$k'.isEmpty ? null : '$k', labelAr: '${v['label_ar'] ?? ''}', labelEn: '${v['label_en'] ?? ''}');
  }

  static PrintedIdSpec of(IdentifierOption o) => PrintedIdSpec(source: o.choice.source, key: o.choice.key, labelAr: o.labelAr, labelEn: o.labelEn);
}

/// `settings.print_identifiers` out of a `GET …/setup` answer.
List<PrintedIdSpec> printedIdsOfSetup(Map<String, dynamic> setup) => [
      for (final x in (setup['print_identifiers'] as List?) ?? const [])
        if (PrintedIdSpec.fromJson(x) != null) PrintedIdSpec.fromJson(x)!,
    ];

/// One student's value of an identifier.
class IdValueRow {
  const IdValueRow(this.studentId, this.name, this.value);
  final int studentId;
  final String name, value;
  bool get filled => value.trim().isNotEmpty;
}

/// `GET …/identifiers/values`, or why it could not be read.
class IdCoverage {
  const IdCoverage({this.items = const [], this.filled = 0, this.total = 0, this.unreadable = false, this.masked = false});
  final List<IdValueRow> items;
  final int filled, total;

  /// The server shows real values only for the teacher's own Data Lab column. For every other source the [items] hold
  /// masked values: the counts and who is missing are usable, the values are never shown, edited or sent.
  final bool masked;

  /// The caller may not read this source's values: the coverage is unknown, which is not the same as empty.
  final bool unreadable;

  static IdCoverage fromJson(Map<String, dynamic> j) {
    final items = [for (final x in asMapList(j['items'])) IdValueRow(asInt(x['student_id']), '${x['name'] ?? ''}', '${x['value'] ?? ''}')];
    return IdCoverage(items: items, filled: asInt(j['filled'], items.where((x) => x.filled).length), total: asInt(j['total'], items.length), masked: j['masked'] == true);
  }

  bool get complete => !unreadable && total > 0 && filled >= total;
  int get missingCount => total - filled;
  List<String> get missingNames => namesKnown ? [for (final x in items) if (!x.filled) x.name] : const [];

  /// Masking must leave an empty value empty for the rows to say who is missing; if not, only the count can be trusted.
  bool get namesKnown => !masked || items.where((x) => !x.filled).length == missingCount;
}

/// "28 of 31 have a value".
String coverageText(int filled, int total) => t('$filled من $total لديهم قيمة', '$filled of $total have a value');

/// "Ali, Sara and 3 more".
String namesText(List<String> names, {int show = 4}) {
  if (names.isEmpty) return '';
  final head = names.take(show).join(t('، ', ', '));
  final rest = names.length - show;
  if (rest <= 0) return head;
  final more = countText(rest, ar1: 'واحد آخر', ar2: 'اثنان آخران', arFew: '{n} آخرون', arMany: '{n} آخرًا', en1: '1 more', en: '{n} more');
  return t('$head و$more', '$head and $more');
}

const _matchOrder = ['academic_id', 'custom', 'national_id', 'datalab', 'phone', 'email', 'name'];

/// Which identifier to match the sheets on when the exam has none yet: a value everyone holds, in order of how well it
/// identifies a person (an academic number before a phone), then the best coverage. A name is the last resort.
IdentifierOption? recommendedMatching(List<IdentifierOption> options, Map<String, IdCoverage> coverage, {IdentifierChoice? current}) {
  for (final o in options) {
    if (o.choice == current) return o;
  }
  final ranked = [for (final o in options) if (o.choice.key != '__identifier') o];
  if (ranked.isEmpty) return options.isEmpty ? null : options.first;
  int order(IdentifierOption o) {
    final i = _matchOrder.indexOf(o.choice.source);
    return i < 0 ? _matchOrder.length : i;
  }

  double ratio(IdentifierOption o) {
    final c = coverage[o.choice.id];
    return c == null || c.unreadable || c.total == 0 ? 0 : c.filled / c.total;
  }

  ranked.sort((a, b) {
    final fa = coverage[a.choice.id]?.complete == true, fb = coverage[b.choice.id]?.complete == true;
    if (fa != fb) return fa ? -1 : 1;
    final ra = ratio(a), rb = ratio(b);
    if (a.choice.source != 'name' && b.choice.source != 'name' && (ra - rb).abs() > .15) return rb.compareTo(ra);
    return order(a).compareTo(order(b));
  });
  return ranked.first;
}

/// The list to send with the matching identifier always in it, first, without duplicates, at most four.
List<PrintedIdSpec> printedWithMatching(List<PrintedIdSpec> printed, PrintedIdSpec matching) {
  final out = <PrintedIdSpec>[matching, for (final p in printed) if (p.id != matching.id) p];
  return out.length > kPaperMaxIdentifiers ? out.sublist(0, kPaperMaxIdentifiers) : out;
}

/// The mini preview's sample for a source the server only shows masked: the shape the paper will really have, a made-up
/// value like the sample name above it. National id, phone and email print their last four; everything else prints whole,
/// so showing the mask there would promise a paper that never exists.
String maskedPaperSample(String source) =>
    const {'national_id', 'phone', 'email'}.contains(source) ? '••••1234' : t('قيمة الطالب', "The student's value");

/// How [value] will look on the paper for that source: national id, phone and email are cut to the last four.
String printedValuePreview(String source, String value) {
  if (!const {'national_id', 'phone', 'email'}.contains(source) || value.length <= 4) return value;
  return '••••${value.substring(value.length - 4)}';
}

// ── Excel import ────────────────────────────────────────────────────────────────────────────────────────────────────

class IdImportIssue {
  const IdImportIssue(this.row, this.value, [this.reason]);
  final int row;
  final String value;
  final String? reason;

  static IdImportIssue fromJson(Map<String, dynamic> j) => IdImportIssue(asInt(j['row']), '${j['value'] ?? ''}', j['reason'] == null ? null : '${j['reason']}');

  String get reasonText => switch (reason) {
        'too_long' => t('القيمة طويلة جدًا', 'too long'),
        'not_a_number' => t('ليست رقمًا', 'not a number'),
        'out_of_range' => t('خارج المدى المسموح', 'out of range'),
        'not_an_option' => t('ليست من الاختيارات', 'not one of the options'),
        _ => '',
      };
}

class IdImportPreview {
  const IdImportPreview({this.rows = 0, this.matched = 0, this.unmatched = const [], this.duplicates = const [], this.invalid = const [], this.importKey = ''});
  final int rows, matched;
  final List<IdImportIssue> unmatched, duplicates, invalid;
  final String importKey;

  bool get hasProblems => unmatched.isNotEmpty || duplicates.isNotEmpty || invalid.isNotEmpty;

  static IdImportPreview fromJson(Map<String, dynamic> j) => IdImportPreview(
        rows: asInt(j['rows']),
        matched: asInt(j['matched']),
        unmatched: [for (final x in asMapList(j['unmatched'])) IdImportIssue.fromJson(x)],
        duplicates: [for (final x in asMapList(j['duplicates'])) IdImportIssue.fromJson(x)],
        invalid: [for (final x in asMapList(j['invalid'])) IdImportIssue.fromJson(x)],
        importKey: '${j['import_key'] ?? ''}',
      );
}

// ── email deliveries ────────────────────────────────────────────────────────────────────────────────────────────────

class DeliveryNoEmail {
  const DeliveryNoEmail(this.studentId, this.name);
  final int studentId;
  final String name;
}

/// A row of `GET …/deliveries`.
class ExamDelivery {
  const ExamDelivery({required this.id, required this.mode, this.toMasked, this.recipients = 0, this.sent = 0, this.failed = 0, this.noEmail = const [], this.failedNames = const [], this.status = 'queued', this.createdBy = '', this.createdAt});
  final String id, mode, status, createdBy;
  final String? toMasked;
  final int recipients, sent, failed;
  final List<DeliveryNoEmail> noEmail;

  /// Who it could not reach; a name is empty when the server no longer knows it.
  final List<DeliveryNoEmail> failedNames;
  final DateTime? createdAt;

  bool get running => status == 'queued';
  bool get whole => mode == 'whole';

  static ExamDelivery fromJson(Map<String, dynamic> j) => ExamDelivery(
        id: '${j['id'] ?? ''}',
        mode: '${j['mode'] ?? ''}',
        toMasked: j['to_masked'] == null ? null : '${j['to_masked']}',
        recipients: asInt(j['recipients']),
        sent: asInt(j['sent']),
        failed: asInt(j['failed']),
        noEmail: [for (final x in asMapList(j['no_email'])) DeliveryNoEmail(asInt(x['student_id']), '${x['name'] ?? ''}')],
        failedNames: [for (final x in asMapList(j['failed_names'])) DeliveryNoEmail(asInt(x['student_id']), '${x['name'] ?? ''}')],
        status: '${j['status'] ?? 'queued'}',
        createdBy: '${j['created_by_name'] ?? ''}',
        createdAt: parseEngineUtc(j['created_at']),
      );

  String get statusText => switch (status) {
        'queued' => t('جارٍ الإرسال', 'Sending'),
        'sent' => t('تم الإرسال', 'Sent'),
        'partial' => t('وصل لبعضهم', 'Partly sent'),
        'failed' => t('تعذّر الإرسال', 'Failed'),
        _ => status,
      };

  /// "Could not reach: Ali, Sara and 2 others"; null when nobody is listed.
  String? get failedText {
    if (failedNames.isEmpty) return null;
    final names = [for (final x in failedNames) if (x.name.isNotEmpty) x.name];
    final unnamed = failedNames.length - names.length;
    if (names.isEmpty) {
      return countText(unnamed,
          ar1: 'تعذّر الوصول إلى طالب واحد', ar2: 'تعذّر الوصول إلى طالبين', arFew: 'تعذّر الوصول إلى {n} طلاب', arMany: 'تعذّر الوصول إلى {n} طالبًا',
          en1: 'Could not reach 1 student', en: 'Could not reach {n} students');
    }
    final list = namesText(names);
    if (unnamed == 0) return t('تعذّر الوصول إلى: $list', 'Could not reach: $list');
    final others = countText(unnamed, ar1: 'طالب آخر', ar2: 'طالبين آخرين', arFew: '{n} طلاب آخرين', arMany: '{n} طالبًا آخر', en1: '1 other', en: '{n} others');
    return t('تعذّر الوصول إلى: $list، و$others', 'Could not reach: $list, and $others');
  }

  /// "Sent to 28 of 31 students · 3 have no email".
  String get summary {
    if (whole) return t('إلى ${toMasked ?? ''}', 'To ${toMasked ?? ''}');
    final who = countText(recipients, ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالبًا', en1: '1 student', en: '{n} students');
    if (running) return t('إلى $who', 'To $who');
    final parts = <String>[
      t('وصل إلى $sent من $recipients', 'Delivered to $sent of $recipients'),
      if (noEmail.isNotEmpty) t('${noEmail.length} بلا بريد', '${noEmail.length} without an email'),
      if (failed > 0) t('$failed تعذّر', '$failed failed'),
    ];
    return parts.join(' · ');
  }
}

/// True while a row is still being sent (the list is re-read on events, then a slow poll).
bool anyDeliveryRunning(List<ExamDelivery> items) => items.any((d) => d.running);

/// The warning before an email leaves: the exam has a start time still ahead of [now]. Null when it has started.
String? earlyEmailWarning(DateTime? startsAtUtc, DateTime nowUtc) {
  if (startsAtUtc == null || !startsAtUtc.isAfter(nowUtc)) return null;
  return t('الاختبار لم يبدأ بعد. أي ورقة تُرسل الآن تخرج من يدك: لا يمكن استرجاعها، وقد تُتداول قبل الموعد.',
      'The exam has not started yet. A paper emailed now is out of your hands: it cannot be taken back and could circulate before the exam.');
}

/// Splits file sizes into upload rounds of at most [maxBytes] and [maxFiles] each (end indexes, exclusive).
List<int> uploadBatches(List<int> sizes, {int maxBytes = kDeliverRoundBytes, int maxFiles = 100}) {
  final out = <int>[];
  var bytes = 0, count = 0;
  for (var i = 0; i < sizes.length; i++) {
    if (count > 0 && (bytes + sizes[i] > maxBytes || count >= maxFiles)) {
      out.add(i);
      bytes = 0;
      count = 0;
    }
    bytes += sizes[i];
    count++;
  }
  if (sizes.isNotEmpty) out.add(sizes.length);
  return out;
}

/// A safe file name stem.
String deliverFileStem(String title, String suffix) => '$title - $suffix'.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

// ── server codes ────────────────────────────────────────────────────────────────────────────────────────────────────

String deliverCodeText(String? code, [Map<String, dynamic> detail = const {}]) => switch (code) {
      'delivery_file_too_large' => t('الملف أكبر من 20 ميجابايت. جرّب PDF بدل Word أو أزل الصور الكبيرة.', 'The file is larger than 20 MB. Try PDF instead of Word, or remove large pictures.'),
      'delivery_mode' => t('طريقة الإرسال غير معروفة.', 'Unknown way of sending.'),
      'delivery_address_invalid' => t('عنوان البريد غير صالح. راجعه وأعد المحاولة.', 'This email address is not valid. Check it and try again.'),
      'delivery_file_required' || 'delivery_files_required' => t('لم يصل الملف إلى الخادم. أعد المحاولة.', 'The file did not reach the server. Try again.'),
      'delivery_file_type' => t('يُرسل PDF أو Word فقط.', 'Only PDF or Word files can be sent.'),
      'delivery_file_name' => t('تعذّر ربط ملف بطالب. أعد المحاولة.', 'A file could not be matched to a student. Try again.'),
      'delivery_student_twice' => t('طالب ظهر مرتين في الإرسال. أعد المحاولة.', 'A student appeared twice. Try again.'),
      'delivery_total_too_large' => t('مجموع حجم الملفات أكبر من 26 ميجابايت. أرسلها على دفعات أصغر.', 'The files together are larger than 26 MB. Send them in smaller rounds.'),
      'delivery_daily_limit' => detail['scope'] == 'org'
          ? t('بلغت مؤسستك حدها اليومي للإرسال إلى عناوين خارجية. حاول غدًا.', 'Your organization has reached its daily limit for outside addresses. Try again tomorrow.')
          : t('بلغ الإرسال إلى العناوين الخارجية حده اليومي على المنصة. حاول غدًا.', 'The platform has reached its daily limit for outside addresses. Try again tomorrow.'),
      'delivery_too_many' => t('500 طالب على الأكثر في المرة الواحدة.', 'At most 500 students at a time.'),
      'student_not_in_course' => t('بعض الطلاب لم يعودوا في مقرر الاختبار. حدّث الصفحة وأعد المحاولة.', 'Some students are no longer in this course. Refresh and try again.'),
      'too_many_requests' => t('أرسلت إلى عناوين خارجية 3 مرات في الساعة الأخيرة. حاول بعد ساعة.', 'You have sent to outside addresses 3 times in the last hour. Try again in an hour.'),
      'print_identifiers_invalid' => t('أربعة معرّفات على الأكثر على الورقة.', 'At most four identifiers on the paper.'),
      'print_identifier_label' => t('اكتب اسم المعرّف.', 'Name the identifier.'),
      'print_identifier_duplicate' => t('هذا المعرّف مضاف بالفعل.', 'This identifier is already added.'),
      'datalab_columns_limit' => t('وصل جدول المقرر إلى الحد الأقصى من الأعمدة.', 'The course sheet has reached its column limit.'),
      'identifier_source_readonly' => t('هذه القيمة يملكها الطالب، ولا يمكن إدخالها هنا.', 'The student owns this value. It cannot be entered here.'),
      'identifier_value_invalid' => t('قيمة غير صالحة لهذا العمود.', 'A value is not valid for this column.'),
      'identifier_value_too_long' => t('قيمة أطول من المسموح.', 'A value is too long.'),
      'identifier_values_invalid' => t('تعذّر حفظ القيم. أعد المحاولة.', 'The values could not be saved. Try again.'),
      'column_locked' => t('هذا العمود مقفل في جدول المقرر.', 'This column is locked in the course sheet.'),
      'import_key_invalid' => t('انتهت صلاحية المعاينة. ارفع الملف من جديد.', 'This preview has expired. Upload the file again.'),
      'import_too_many_rows' => t('الملف أكبر من المسموح.', 'The file has too many rows.'),
      'form_unknown' => t('هذا النموذج لم يعد موجودًا. حدّث الصفحة.', 'That version no longer exists. Refresh the page.'),
      'print_plan_too_large' => t('عدد النسخ كبير جدًا لملف واحد. اختر عددًا أقل من الطلاب.', 'Too many copies for one file. Pick fewer students.'),
      'copies_invalid' => t('عدد النسخ غير صالح.', 'That number of copies is not valid.'),
      _ => setupCodeText(code, detail),
    };

/// The request was refused for its size, by nginx (HTML, no code) or by the server.
bool deliverTooLarge(EngineResult r) => r.status == 413;

/// Said instead of whatever nginx's page held.
String get deliverTooLargeText => t('هذا الملف أكبر من أن يُرسل بالبريد. نزّله وأرسله بطريقة أخرى.', 'This file is too large to email. Download it and send it another way.');

String deliverErrorText(EngineResult r) {
  if (deliverTooLarge(r) && r.code == null) return deliverTooLargeText;   // nginx's page: no envelope, so no code
  final mapped = deliverCodeText(r.code, r.detail);
  if (mapped.isNotEmpty) return mapped;
  final en = r.detail['message_en'];
  if (en != null && AppConfig.lang == 'en') return '$en';
  if (r.message.isNotEmpty && r.message != 'Not Found') return r.message;
  return t('تعذّر إكمال العملية. أعد المحاولة.', 'Could not finish. Try again.');
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

class ExamDeliverApi {
  ExamDeliverApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> createCustom(int examId, String labelAr, String labelEn) =>
      engineCall(() => _api.post('$_b/exams/$examId/identifiers/custom', body: {'label_ar': labelAr, 'label_en': labelEn}));

  Future<EngineResult> values(int examId, String source, String? key) =>
      engineCall(() => _api.get('$_b/exams/$examId/identifiers/values', queryParams: {'source': source, 'key': ?key}));

  Future<EngineResult> putValues(int examId, String source, String? key, List<IdValueRow> values) => engineCall(() => _api.put('$_b/exams/$examId/identifiers/values', body: {
        'source': source,
        'key': key,
        'values': [for (final v in values) {'student_id': v.studentId, 'value': v.value}],
      }));

  /// The roster template (xlsx); null when the call failed.
  Future<Uint8List?> template(int examId, String source, String? key) async {
    try {
      return await _api.getBytes('$_b/exams/$examId/identifiers/template', queryParams: {'source': source, 'key': ?key});
    } catch (_) {
      return null;
    }
  }

  Future<EngineResult> importPreview(int examId, String source, String? key, Uint8List bytes, String name) => engineCall(() => _api.postForm('$_b/exams/$examId/identifiers/import/preview', fields: {
        'source': source,
        'key': ?key,
        'file': MultipartFile.fromBytes(bytes, filename: name),
      }));

  Future<EngineResult> importCommit(int examId, String importKey) =>
      engineCall(() => _api.post('$_b/exams/$examId/identifiers/import/commit', body: {'import_key': importKey}));

  Future<EngineResult> deliveries(int examId) => engineCall(() => _api.get('$_b/exams/$examId/deliveries'));

  /// The whole exam to one address.
  Future<EngineResult> sendWhole(int examId, {required String to, required Uint8List file, required String fileName, String? message}) =>
      engineCall(() => _api.postForm('$_b/exams/$examId/deliver/email', fields: {
            'mode': 'whole',
            'to': to,
            if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
            'locale': AppConfig.lang,
            'file': MultipartFile.fromBytes(file, filename: fileName),
          }));

  /// One round of `students` mode: [files] by student id.
  Future<EngineResult> sendStudents(int examId, Map<int, Uint8List> files, {required String ext, String? message}) =>
      engineCall(() => _api.postForm('$_b/exams/$examId/deliver/email', fields: {
            'mode': 'students',
            if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
            'locale': AppConfig.lang,
            'files': [for (final e in files.entries) MultipartFile.fromBytes(e.value, filename: '${e.key}.$ext')],
          }));

  Future<EngineResult> plan(int examId, Map<String, dynamic> body) => engineCall(() => _api.post('$_b/exams/$examId/print-plan', body: body));
}
