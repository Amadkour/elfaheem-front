// Exam identifiers, the student's side (D-150): the pending requests a teacher sent ("Your teacher needs your National
// ID for the upcoming exam"), the field's rules checked before sending, and the server's answers in plain words.
// The dialog is identity_request_gate.dart.
//
// Server (core): GET /api/v1/me/identity-requests → {items: [{id, exam_ref, exam_title, course_id, source, key,
// field: {key, label_ar, label_en, kind, pattern, min_len, max_len}, paper, due_at, message_ar, message_en,
// created_at}]}; POST /api/v1/me/identity-requests/{id} {value} → {id, status: done, field_key, closed: [ids]}
// (422 identifier_invalid {rule}, 409 identifier_taken, 409 identity_request_closed, 404 identity_request_not_found).
// The rules mirror services/identity_service.py `normalize` / `validate` so the student hears the same thing before
// and after the round trip.
library;

import 'package:flutter/services.dart' show TextInputType;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'package:flutter_education_app/features/exams/exam_authoring.dart' show parseEngineUtc;
import 'package:flutter_education_app/features/exams/exam_engine_api.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart' show IdentityFieldDef;

export 'package:flutter_education_app/features/exams/paper/exam_setup.dart' show IdentityFieldDef, kExamIdentifiersFeatureKey;

/// One pending request of the signed-in student.
class IdentityRequestItem {
  const IdentityRequestItem({
    required this.id,
    required this.field,
    this.examRef = '',
    this.examTitle,
    this.courseId,
    this.source = '',
    this.key,
    this.paper = false,
    this.dueUtc,
    this.messageAr = '',
    this.messageEn = '',
  });

  final int id;
  final IdentityFieldDef field;
  final String examRef;
  final String? examTitle;
  final int? courseId;
  final String source;
  final String? key;
  final bool paper;
  final DateTime? dueUtc;
  final String messageAr;
  final String messageEn;

  static IdentityRequestItem fromJson(Map<String, dynamic> j) => IdentityRequestItem(
        id: asInt(j['id']),
        field: IdentityFieldDef.fromJson(asMap(j['field'])),
        examRef: '${j['exam_ref'] ?? ''}',
        examTitle: j['exam_title'] == null || '${j['exam_title']}'.trim().isEmpty ? null : '${j['exam_title']}',
        courseId: j['course_id'] == null ? null : asInt(j['course_id']),
        source: '${j['source'] ?? ''}',
        key: j['key'] == null ? null : '${j['key']}',
        paper: j['paper'] == true,
        dueUtc: parseEngineUtc(j['due_at']),
        messageAr: '${j['message_ar'] ?? ''}',
        messageEn: '${j['message_en'] ?? ''}',
      );

  static List<IdentityRequestItem> listFrom(Map<String, dynamic> j) => [for (final m in asMapList(j['items'])) IdentityRequestItem.fromJson(m)];

  /// The server's sentence ("Your teacher needs your National ID for the upcoming exam. Please enter it."), else
  /// the same sentence built here.
  String get message {
    final s = t(messageAr, messageEn).trim();
    if (s.isNotEmpty) return s;
    final ar = 'يحتاج معلمك إلى ${field.labelAr} للاختبار القادم. يُرجى إدخاله${paper ? ' قبل يوم الاختبار.' : '.'}';
    final en = 'Your teacher needs your ${field.labelEn} for the upcoming exam. Please enter it${paper ? ' before exam day.' : '.'}';
    return t(ar, en);
  }
}

// ── rules ────────────────────────────────────────────────────────────────────────────────────────────────────────

const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';
const _persian = '۰۱۲۳۴۵۶۷۸۹';

/// Arabic-Indic and Persian digits → Western (what the server stores).
String westernDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = _arabicIndic.indexOf(ch);
    final j = i >= 0 ? i : _persian.indexOf(ch);
    b.write(j >= 0 ? '$j' : ch);
  }
  return b.toString();
}

/// The server's `normalize`: trim, digits folded; digits drop spaces and dashes; e-mail lower-case; phone drops
/// spaces, dashes, dots and brackets.
String normalizeIdentity(String kind, String value) {
  var s = westernDigits(value).trim();
  switch (kind) {
    case 'digits':
      s = s.replaceAll(RegExp(r'[\s\-‐-―]'), '');
    case 'email':
      s = s.toLowerCase();
    case 'phone':
      s = s.replaceAll(RegExp(r'[\s\-.()‐-―]'), '');
  }
  return s;
}

/// required | digits | email | phone | length | pattern — the rule the value breaks, null when it is fine.
String? identityRuleBroken(IdentityFieldDef f, String value) {
  final norm = normalizeIdentity(f.kind, value);
  if (norm.isEmpty) return 'required';
  if (f.kind == 'digits' && !RegExp(r'^\d+$').hasMatch(norm)) return 'digits';
  if (f.kind == 'email' && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(norm)) return 'email';
  if (f.kind == 'phone' && !RegExp(r'^\+?\d{7,15}$').hasMatch(norm)) return 'phone';
  if (norm.length < f.minLen || norm.length > f.maxLen) return 'length';
  final p = f.pattern;
  if (p != null && p.isNotEmpty) {
    try {
      if (!RegExp('^(?:$p)\$').hasMatch(norm)) return 'pattern';
    } on FormatException {
      // a pattern Dart cannot read: the server decides
    }
  }
  return null;
}

/// The same sentences as the server's `validate` (ar / en).
String identityRuleText(String rule, IdentityFieldDef f) {
  final digits = f.kind == 'digits';
  return switch (rule) {
    'required' => t('أدخل القيمة', 'Please enter a value.'),
    'digits' => t('أرقام فقط', 'Digits only, please.'),
    'email' => t('البريد الإلكتروني غير صالح', 'This email address is not valid.'),
    'phone' => t('رقم الهاتف غير صالح', 'This phone number is not valid.'),
    'length' => f.minLen == f.maxLen
        ? t('يجب أن يكون ${f.minLen} ${digits ? 'رقمًا' : 'حرفًا'} بالضبط', 'This must be exactly ${f.minLen} ${digits ? 'digits' : 'characters'}.')
        : t('الطول من ${f.minLen} إلى ${f.maxLen} ${digits ? 'رقمًا' : 'حرفًا'}', 'This must be ${f.minLen} to ${f.maxLen} ${digits ? 'digits' : 'characters'}.'),
    'pattern' => t('الصيغة غير صحيحة', 'This value does not have the expected format.'),
    _ => t('القيمة غير صالحة', 'This value is not valid.'),
  };
}

/// The hint under the field: "14 digits", "6 to 9 characters", or nothing.
String identityHint(IdentityFieldDef f) {
  if (f.kind == 'email' || f.kind == 'phone') return '';
  final digits = f.kind == 'digits';
  if (f.minLen == f.maxLen) return t('${f.minLen} ${digits ? 'رقمًا' : 'حرفًا'}', '${f.minLen} ${digits ? 'digits' : 'characters'}');
  if (f.minLen <= 1 && f.maxLen >= 64) return '';
  return t('من ${f.minLen} إلى ${f.maxLen} ${digits ? 'رقمًا' : 'حرفًا'}', '${f.minLen} to ${f.maxLen} ${digits ? 'digits' : 'characters'}');
}

TextInputType identityKeyboard(String kind) => switch (kind) {
      'digits' => TextInputType.number,
      'phone' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      _ => TextInputType.text,
    };

/// A failed submit in the student's language: the server's own bilingual message (409 identifier_taken: "This number
/// is already used by another student. Please check it."; 422: the broken rule), else a text of ours.
String identitySubmitError(EngineResult r, IdentityFieldDef f) {
  final en = r.detail['message_en'];
  final ar = r.detail['message'];
  if (AppConfig.lang == 'en' && en != null && '$en'.isNotEmpty) return '$en';
  if (AppConfig.lang != 'en' && ar != null && '$ar'.isNotEmpty) return '$ar';
  return switch (r.code) {
    'identifier_taken' => t('هذا الرقم مستخدم بالفعل من طالب آخر. يرجى التحقق منه.', 'This number is already used by another student. Please check it.'),
    'identifier_invalid' => identityRuleText('${r.detail['rule'] ?? ''}', f),
    'identity_request_closed' => t('تم إغلاق هذا الطلب', 'This request is already closed.'),
    'identity_request_not_found' => t('الطلب غير موجود', 'Request not found.'),
    _ => r.status == 0 ? t('لا يوجد اتصال — أعد المحاولة', 'No connection — try again') : t('تعذّر الحفظ — أعد المحاولة', 'Could not save — try again'),
  };
}

/// The request is gone (answered elsewhere, cancelled by the teacher): skip it quietly.
bool identityRequestGone(EngineResult r) => r.code == 'identity_request_closed' || r.code == 'identity_request_not_found';

class IdentityApi {
  IdentityApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<EngineResult> pending() => engineCall(() => _api.get('/api/v1/me/identity-requests'));

  /// The typed value as is (the server normalises it, so Arabic-Indic digits are fine).
  Future<EngineResult> submit(int id, String value) => engineCall(() => _api.post('/api/v1/me/identity-requests/$id', body: {'value': value.trim()}));
}

/// The ids the server closed with one answer (the same field asked by other exams of the student).
Set<int> closedIds(EngineResult r, int id) => {id, for (final x in (r.map['closed'] as List?) ?? const []) asInt(x)};
