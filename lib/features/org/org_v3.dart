// lib/features/org/org_v3.dart
//
// Organizations v3 — the pieces every v3 screen shares (no widgets here, so it is unit-tested directly):
//   orgCall / OrgCall        a mutation that keeps the server error (code + extra keys) for inline display
//   orgErrorText             the server's `detail.code` → a short bilingual sentence (falls back to the server text)
//   joinReasonText           one eligibility reason ({code, message, field?}) → text
//   JoinPolicyDraft          GET /units/{t}/{id}/join-policy ⇄ PUT body (the PUT replaces the whole policy)
//   ScheduleDraft            GET /schedules/{sid} ⇄ POST/PUT body (the PUT replaces the whole scope)
//   orgUtc / orgParseUtc     the server stores naive UTC; we always send UTC and show local time
//   labels                   membership statuses · cohorts · join methods · solver statuses · conflict types
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../admin/admin_common.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  Calls
// ═════════════════════════════════════════════════════════════════════════════

class OrgCall {
  const OrgCall(this.data, [this.error]);
  final dynamic data;
  final ApiException? error;

  bool get ok => error == null;
  Map<String, dynamic> get map => asMap(data);
  String? get code => error?.code;

  /// The extra keys of a coded error: `{code, message, reasons, conflicts, run, …}`.
  Map<String, dynamic> get detail => asMap(ApiException.asMap(error?.body)?['detail']);

  /// The server has no such route yet (FastAPI's bare 404 "Not Found" / 405) — not "this record is missing".
  bool get endpointMissing => error != null && orgEndpointMissing(error!);
}

bool orgEndpointMissing(ApiException e) =>
    e.statusCode == 405 || (e.statusCode == 404 && ApiException.asMap(e.body)?['detail'] == 'Not Found');

/// Runs [fn]; on success toasts [ok] (when given), on failure toasts [orgErrorText] unless [quiet].
/// Never throws — the screen decides what to do with [OrgCall.error].
Future<OrgCall> orgCall(Future<dynamic> Function() fn, {String? ok, bool quiet = false}) async {
  try {
    final r = await fn();
    if (ok != null) toast(ok);
    return OrgCall(r ?? true);
  } catch (e) {
    final err = ApiException.from(e);
    if (!quiet) toast(orgErrorText(err), error: true);
    return OrgCall(null, err);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Error texts
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> _codeTexts() => {
      // organization review / access
      'org_not_approved': t('المؤسسة بانتظار اعتماد إدارة المنصة', 'The organization is waiting for platform approval'),
      'org_forbidden': t('لا تملك صلاحية لهذا الإجراء في هذه المؤسسة', 'You don\'t have the right to do this in this organization'),
      'org_admin_only': t('هذا الإجراء لمدير المؤسسة فقط', 'Only the organization admin can do this'),
      'not_member': t('لست عضواً نشطاً في هذه المؤسسة', 'You are not an active member of this organization'),
      'membership_ended': t('انتهت عضويتك في هذه المؤسسة — تواصل مع إدارتها لتجديدها. حسابك وباقي خدماتك تعمل كالمعتاد.',
          'Your membership in this organization has ended — contact it to renew. Your account and other services still work.'),
      'too_many_attempts': t('محاولات كثيرة خاطئة — انتظر قليلاً ثم حاول مجدداً', 'Too many wrong attempts — wait a little and try again'),
      'weak_password': t('كلمة المرور يجب أن تحتوي على حروف وأرقام (8 على الأقل)', 'The password needs letters and digits (8+ characters)'),
      'email_taken': t('هذا البريد مسجّل بالفعل — سجّل الدخول به', 'This e-mail is already registered — log in with it'),
      'root_only': t('طلب الاعتماد للمؤسسات الرئيسية فقط', 'Applications are for top-level organizations only'),
      'not_rejected': t('يمكن إعادة الإرسال بعد الرفض فقط', 'You can resubmit only after a rejection'),
      'decision_conflict': t('اتُّخذ قرار آخر للتو — حدّث الصفحة', 'Someone else decided just now — refresh'),
      // members
      'already_member': t('عضو بالفعل', 'Already a member'),
      'role_mismatch': t('هذا البريد لحساب بدور مختلف', 'This e-mail belongs to an account with a different role'),
      'last_admin': t('لا يمكن إنهاء عضوية آخر مدير للمؤسسة', 'The last organization admin can\'t be removed'),
      'self': t('لا يمكنك إنهاء عضويتك بنفسك', 'You can\'t end your own membership'),
      'bad_window': t('تاريخ البداية يجب أن يسبق تاريخ الانتهاء', 'The start must be before the end'),
      'expiry_in_past': t('تاريخ الانتهاء في الماضي', 'The expiry date is in the past'),
      'expired_window': t('انتهت مدة العضوية — مدّدها أولاً', 'The membership period is over — extend it first'),
      'not_member_yet': t('الطلب لم يُقبل بعد', 'This request has not been accepted yet'),
      'inactive': t('العضوية غير نشطة — اختر إعادة التفعيل', 'The membership is not active — choose reactivate'),
      'student_program': t('القسم العلمي للطالب يُحدَّد من مساره الأكاديمي', 'A student\'s academic department comes from their academic path'),
      'student_only': t('هذا الحقل للطلاب فقط', 'This field is for students only'),
      'bad_level': t('الفرقة / المستوى غير معرّف في إعدادات المؤسسة', 'This year / level is not configured for the institution'),
      'level_in_use': t('هذا المستوى مستخدم لطلاب حاليين', 'Students still use this level'),
      // academic departments (programs)
      'electives': t('عدد الاختياريات المطلوب أكبر من عدد المقررات الاختيارية المختارة', 'The electives required exceed the elective courses selected'),
      'both': t('المقرر لا يكون إجبارياً واختيارياً معاً', 'A course can\'t be both required and elective'),
      'bad_course': t('أحد المقررات لم يعد من مقررات المؤسسة — حدّث القائمة', 'A course is no longer one of the institution\'s — refresh the list'),
      'already_assigned': t('الدور ممنوح بالفعل', 'The role is already granted'),
      'bad_cohort': t('الدفعة غير صحيحة', 'Invalid cohort'),
      'program_not_found': t('القسم العلمي غير موجود', 'Academic department not found'),
      'dept_not_found': t('الإدارة غير موجودة', 'Department not found'),
      'not_staff_member': t('يجب أن يكون عضواً نشطاً من الهيئة', 'Must be a live staff member'),
      'bad_manager': t('المدير يجب أن يكون مدرساً أو إدارياً نشطاً في المؤسسة', 'The manager must be a live teacher or admin of the organization'),
      'bad_manager_role': t('دور المدير غير مسموح', 'This role can\'t be a manager'),
      'user_not_found': t('المستخدم غير موجود', 'User not found'),
      'preset_exists': t('هذه الإدارة الجاهزة موجودة بالفعل', 'This ready-made department already exists'),
      'dept_has_content': t('للإدارة محتوى — أرشفها بدلاً من حذفها', 'The department has content — archive it instead'),
      'has_students': t('في القسم طلاب — أوقفه بدلاً من حذفه', 'The department has students — deactivate it instead'),
      // join policy / codes / requests
      'feature_off': t('فعّل خدمة "الأعضاء" لهذه الإدارة أولاً', 'Switch on the "Members" service for this department first'),
      'no_manager': t('عيّن مديراً للوحدة أو اختر المساعدين كمعتمدين', 'Appoint a manager or choose assistants as approvers'),
      'no_assistants': t('اختر مساعداً واحداً على الأقل', 'Pick at least one assistant'),
      'bad_assistant': t('أحد المساعدين ليس عضواً نشطاً', 'One of the assistants is not a live member'),
      'bad_roles': t('اختر فئة واحدة على الأقل', 'Pick at least one audience'),
      'too_many_fields': t('عدد الحقول أكبر من المسموح (30)', 'Too many fields (30 max)'),
      'bad_bind': t('ربط الحقل غير صحيح', 'Invalid field binding'),
      'bad_allowed': t('الإجابات المقبولة يجب أن تكون من الخيارات', 'Accepted answers must be among the options'),
      'field_label': t('كل حقل يحتاج عنواناً', 'Every field needs a label'),
      'field_type': t('نوع الحقل غير مدعوم', 'Unsupported field type'),
      'field_options': t('حقل الاختيار يحتاج خيارات', 'A choice field needs options'),
      'unit_not_found': t('الوحدة غير موجودة', 'Unit not found'),
      'bad_max_uses': t('عدد الاستخدامات غير صحيح', 'Invalid number of uses'),
      'code_not_found': t('الكود غير موجود', 'Code not found'),
      'revoked': t('الكود ملغى نهائياً — أنشئ كوداً جديداً', 'The code is revoked — create a new one'),
      'bad_code': t('الكود غير صحيح', 'Wrong code'),
      'code_inactive': t('الكود موقوف حالياً', 'The code is switched off'),
      'code_revoked': t('الكود ملغى', 'The code was revoked'),
      'code_expired': t('انتهت صلاحية الكود', 'The code has expired'),
      'code_not_yet_valid': t('الكود لم يبدأ بعد', 'The code is not valid yet'),
      'code_exhausted': t('استُنفد عدد استخدامات الكود', 'The code has no uses left'),
      'code_other_unit': t('هذا الكود لوحدة أخرى', 'This code belongs to another unit'),
      'code_required': t('الانضمام لهذه الوحدة بكود فقط', 'This unit is joined with a code only'),
      'not_eligible': t('لا تنطبق عليك شروط الانضمام', 'You don\'t meet the joining conditions'),
      'already_pending': t('لديك طلب قيد المراجعة بالفعل', 'You already have a pending request'),
      'already_in_program': t('أنت مسجّل في قسم علمي آخر', 'You are already in another academic department'),
      'graduated': t('تخرّجت بالفعل', 'Already graduated'),
      'not_pending': t('الطلب لم يعد قيد المراجعة', 'The request is no longer pending'),
      'request_not_found': t('الطلب غير موجود', 'Request not found'),
      'not_approver': t('لست من المعتمدين لهذه الوحدة', 'You are not an approver of this unit'),
      'own_request': t('لا يمكنك اعتماد طلبك بنفسك', 'You can\'t decide your own request'),
      'no_longer_eligible': t('لم يعد المتقدم مستوفياً للشروط', 'The applicant no longer meets the conditions'),
      'verification_note': t('اكتب ملاحظة التحقق — بيانات المتقدم تحتاج مراجعة', 'Write a verification note — the applicant\'s data needs checking'),
      'note_required': t('اكتب سبب القرار', 'Write the reason'),
      'not_unit_member': t('ليس عضواً في هذه الوحدة', 'Not a member of this unit'),
      'program_leave': t('لا يمكن مغادرة القسم العلمي من هنا — تواصل مع شؤون الطلاب', 'An academic department can\'t be left from here — contact student affairs'),
      'field_required': t('حقل مطلوب لم يُملأ', 'A required field is empty'),
      'field_number': t('أدخل رقماً صحيحاً', 'Enter a valid number'),
      'field_option': t('اختر من الخيارات المتاحة', 'Pick one of the options'),
      'field_email': t('أدخل بريداً صحيحاً', 'Enter a valid e-mail'),
      // courses
      'code_taken': t('هذا الكود مستخدم بالفعل في المؤسسة', 'This code is already used in the organization'),
      'no_teacher': t('عيّن مدرساً قبل النشر', 'Assign a teacher before publishing'),
      'not_org_teacher': t('المدرس ليس عضواً في المؤسسة', 'The teacher is not a member of the organization'),
      'teacher_not_eligible': t('المدرس غير مؤهل لهذا المقرر', 'This teacher is not eligible for the course'),
      'term_not_found': t('الفصل الدراسي غير موجود', 'Term not found'),
      'bad_prereq': t('متطلب سابق غير صحيح', 'Invalid prerequisite'),
      // facilities / staff
      'bad_kind': t('نوع المكان غير معرّف', 'Unknown facility type'),
      'bad_url': t('رابط الصورة يجب أن يبدأ بـ http', 'The image link must start with http'),
      'room_in_use': t('المكان مستخدم في جدول منشور — أوقفه بدلاً من حذفه', 'Used by a published timetable — deactivate it instead'),
      'too_many_members': t('عدد الموجودين أكبر من السعة الجديدة', 'More occupants than the new limit'),
      'not_office': t('الأعضاء للمكاتب فقط', 'Occupants are for offices only'),
      'office_full': t('المكتب ممتلئ', 'The office is full'),
      'duplicate': t('شخص مكرر', 'Duplicate person'),
      'bad_keys': t('مفتاح نوع مكرر أو محجوز', 'Duplicate or reserved type key'),
      'type_in_use': t('النوع مستخدم لأماكن حالية', 'Rooms still use this type'),
      'contradictory': t('الخلية نفسها لا يمكن أن تكون مفضلة وغير متاحة معاً', 'A cell can\'t be both preferred and unavailable'),
      'bad_courses': t('مقرر غير صحيح', 'Invalid course'),
      'lab_needs_assistant': t('السكشن يحتاج معيداً (أو اسمح للمدرس بتدريسه من الإعدادات)', 'The lab needs an assistant (or allow teachers to teach labs in settings)'),
      // schedules
      'bad_dates': t('تاريخ البداية يجب أن يسبق النهاية', 'The start date must be before the end'),
      'outside_term': t('التواريخ خارج حدود الفصل الدراسي', 'The dates are outside the term'),
      'bad_days': t('أيام غير صحيحة', 'Invalid days'),
      'schedule_published': t('الجدول منشور — أوقف النشر أولاً للتعديل', 'The timetable is published — unpublish it to edit'),
      'published': t('تعديل الجدول المنشور يحتاج صلاحية الاعتماد', 'Editing a published timetable needs approval rights'),
      'generation_running': t('يوجد توليد جارٍ لهذا الجدول', 'A generation is already running for this timetable'),
      'stale_version': t('عدّل مستخدم آخر هذا الجدول — حمّلنا أحدث نسخة، أعد المحاولة', 'Someone else changed this timetable — the latest version is loaded, try again'),
      // suggestions & horizon (docs/backend/scheduling-spec.md)
      'suggestion_stale': t('تغيّر الجدول منذ هذا الاقتراح — حدّثنا الاقتراحات، راجعها مجدداً', 'The timetable changed since this suggestion — suggestions were refreshed, review them again'),
      'suggestion_invalid': t('لم يعد الاقتراح صالحاً على أحدث نسخة من الجدول', 'The suggestion is no longer valid on the latest timetable'),
      'suggestion_already_applied': t('طُبّق هذا الاقتراح من قبل', 'This suggestion was already applied'),
      'suggestion_not_pending': t('تم البت في هذا الاقتراح من قبل', 'This suggestion was already decided'),
      'suggestion_not_found': t('الاقتراح غير موجود', 'Suggestion not found'),
      'suggestions_overlap': t('اقتراحان يغيّران الحصة نفسها — طبّقهما كلٌّ على حدة', 'Two suggestions change the same session — apply them one at a time'),
      'suggestion_running': t('يجري حساب الاقتراحات الآن', 'Suggestions are being computed'),
      'horizon_exceeded': t('التغيير يتجاوز حدود الأيام / الفترات المسموح بها', 'The change exceeds the allowed days / periods'),
      'expansion_not_allowed': t('اقتراح أيام أو فترات إضافية غير مسموح لهذا الجدول', 'Proposing extra days or periods is not allowed for this timetable'),
      'suggestion_not_applicable': t('هذا الاقتراح نصيحة تُنفَّذ خارج الجدول (مثل فتح معمل) — لا يمكن تطبيقه تلقائياً', 'This is advice to act on outside the timetable (e.g. open a lab) — it cannot be applied automatically'),
      'approval_required': t('هذا التغيير يحتاج صلاحية الاعتماد', 'This change needs approval rights'),
      'bad_types': t('نوع اقتراح غير معروف', 'Unknown suggestion type'),
      'bad_horizon':t('حدود الأيام / الفترات غير صحيحة', 'Invalid days / periods limits'),
      'no_history': t('لا يوجد عدد طلاب من فصل سابق مكتمل لهذا المقرر', 'No completed previous offering of this course'),
      // enrollment & groups
      'schedule_not_found': t('الجدول غير موجود', 'Timetable not found'),
      'course_not_in_schedule': t('المقرر ليس ضمن هذا الجدول', 'This course is not part of the timetable'),
      'bad_plan': t('الأعداد يجب أن تكون 1 أو أكثر', 'Numbers must be 1 or more'),
      'too_many_groups': t('عدد المجموعات كبير جداً (40 كحد أقصى)', 'Too many groups (40 at most)'),
      'bad_group_staff': t('تعيين المدرسين للمجموعات غير صحيح — راجع أرقام المجموعات', 'The group staff do not match the groups — check the group numbers'),
      'bad_group': t('رقم المجموعة غير موجود لهذا المقرر', 'That group does not exist for this course'),
      'generation_failed': t('فشل التوليد — لم يتغير شيء في الجدول', 'Generation failed — nothing in the timetable changed'),
      'not_running': t('التوليد انتهى بالفعل', 'The generation already finished'),
      'schedule_conflict': t('توجد تعارضات تمنع الحفظ', 'There are clashes that block this'),
      'cannot_shift': t('لا يوجد وقت فارغ قريب لنقل الحصص المتعارضة', 'No nearby free time to move the clashing sessions'),
    };

/// The text of one server code (local checks reuse the server's wording).
String orgCodeText(String code) => _codeTexts()[code] ?? code;

/// A short, translated sentence for any [ApiException] the org API can raise.
String orgErrorText(ApiException e) {
  final c = e.code;
  if (c != null) {
    final txt = _codeTexts()[c];
    if (txt != null) {
      if (c == 'too_many_attempts') {
        final m = asInt(asMap(ApiException.asMap(e.body)?['detail'])['retry_after_minutes']);
        if (m > 0) return '$txt (${t('$m دقيقة', '$m min')})';
      }
      return txt;
    }
  }
  return e.message;
}

/// Eligibility reason codes (join_service.py REASONS).
String joinReasonText(Map<String, dynamic> r) =>
    {
      'closed': t('الانضمام مغلق حالياً', 'Joining is closed'),
      'not_member': t('يجب أن تكون عضواً نشطاً في المؤسسة', 'You must be an active member of the organization'),
      'role': t('الانضمام متاح لفئة أخرى', 'Open to a different group'),
      'cohort': t('متاح لدفعة أخرى (حالية / جديدة)', 'Open to a different cohort (current / incoming)'),
      'program': t('متاح لطلاب أقسام علمية أخرى', 'Open to students of other academic departments'),
      'level': t('متاح لفرقة / مستوى آخر', 'Open to a different year / level'),
      'answer_conflict': t('إجابتك لا تطابق بياناتك المسجّلة لدى المؤسسة', 'Your answer doesn\'t match the record the institution holds'),
      'answer_not_allowed': t('هذه الإجابة لا تستوفي الشرط', 'This answer doesn\'t meet the condition'),
      'entry_courses': t('لم تجتز متطلبات الالتحاق بعد', 'You haven\'t passed the entry courses yet'),
      'full': t('اكتمل العدد', 'It is full'),
      'unverified': t('بياناتك غير مسجّلة بعد لدى المؤسسة — سيتحقق منها المسؤول', 'The institution has no record of this yet — a staff member will verify it'),
      'inactive_unit': t('الوحدة غير متاحة', 'The unit is not available'),
      'feature_off': t('الانضمام غير مفعّل لهذه الوحدة', 'Joining is not switched on here'),
    }['${r['code']}'] ??
    '${r['message'] ?? r['code'] ?? ''}';

// ═════════════════════════════════════════════════════════════════════════════
//  Dates — the server stores naive UTC
// ═════════════════════════════════════════════════════════════════════════════

/// What we send: an ISO string in UTC (with `Z`). null stays null.
String? orgUtc(DateTime? d) => d?.toUtc().toIso8601String();

/// What we read: a naive server timestamp is UTC → shown in local time.
DateTime? orgParseUtc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final d = DateTime.tryParse(hasZone || s.length <= 10 ? s : '${s}Z');
  if (d == null) return null;
  return s.length <= 10 ? d : d.toLocal();
}

String orgDay(DateTime? d) => d == null ? '' : d.toIso8601String().substring(0, 10);

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

/// effective_status of a member row.
Map<String, String> membershipStatusLabels() => {
      'active': t('نشط', 'Active'),
      'pending': t('بانتظار الموافقة', 'Pending'),
      'scheduled': t('تبدأ لاحقاً', 'Starts later'),
      'expired': t('منتهية', 'Expired'),
      'suspended': t('موقوفة', 'Suspended'),
      'rejected': t('مرفوض', 'Rejected'),
    };

/// One sentence that explains a member row's period.
String membershipPeriodText(Map<String, dynamic> row) {
  final st = '${row['effective_status'] ?? row['status']}';
  final start = orgParseUtc(row['starts_at']), end = orgParseUtc(row['expires_at']);
  String d(DateTime x) => shortDate(x.toIso8601String());
  return switch (st) {
    'scheduled' when start != null => t('تبدأ العضوية في ${d(start)}', 'Starts on ${d(start)}'),
    'expired' => end == null
        ? t('انتهت العضوية', 'The membership ended')
        : t('انتهت في ${d(end)} — الحساب وباقي المؤسسات لم تتأثر', 'Ended on ${d(end)} — the account and other organizations are unaffected'),
    'suspended' => t('العضوية موقوفة — لا صلاحيات حتى إعادة التفعيل', 'Suspended — no access until reactivated'),
    _ => end == null ? t('عضوية دائمة', 'Permanent membership') : t('حتى ${d(end)}', 'Until ${d(end)}'),
  };
}

Map<String, String> memberCohortLabels() => {'current': t('طالب حالي', 'Current student'), 'incoming': t('طالب مستجد', 'Incoming student')};

Map<String, String> audienceCohortLabels() => {
      'current': t('الحاليون فقط', 'Current only'),
      'incoming': t('المستجدون فقط', 'Incoming only'),
      'both': t('الحاليون والمستجدون', 'Current and incoming'),
    };

Map<String, String> joinMethodLabels() => {
      'closed': t('مغلق', 'Closed'),
      'auto': t('قبول تلقائي', 'Automatic'),
      'approval': t('بموافقة', 'With approval'),
      'code': t('بكود دعوة', 'Invitation code'),
    };

String joinMethodHelp(String m) => switch (m) {
      'auto' => t('يُقبل فوراً كل من تنطبق عليه الشروط — يتحقق الخادم من الشروط والسعة دائماً.',
          'Anyone who meets the conditions is in at once — the server always checks the conditions and capacity.'),
      'approval' => t('يصل الطلب للمعتمد المحدد بالأسفل ليقبله أو يرفضه.', 'The request goes to the approver below, who accepts or rejects it.'),
      'code' => t('ينضم من لديه كود صالح وتنطبق عليه الشروط. أدِر الأكواد من تبويب "الأكواد".',
          'People with a valid code who meet the conditions join. Manage codes in the "Codes" tab.'),
      _ => t('لا أحد يستطيع طلب الانضمام الآن.', 'Nobody can ask to join right now.'),
    };

Map<String, String> joinRoleLabels() => {
      'student': t('الطلاب', 'Students'),
      'teacher': t('المدرسون', 'Teachers'),
      'teacher_assistant': t('المعيدون', 'Teaching assistants'),
      'admin_assistant': t('الإداريون', 'Admin staff'),
    };

Map<String, String> bindLabels() => {
      'academic_level': t('الفرقة / المستوى', 'Year / level'),
      'cohort': t('الدفعة (حالي / مستجد)', 'Cohort (current / incoming)'),
      'program': t('القسم العلمي', 'Academic department'),
    };

Map<String, String> codeStateLabels() => {
      'active': t('فعّال', 'Active'),
      'inactive': t('موقوف', 'Switched off'),
      'revoked': t('ملغى', 'Revoked'),
      'not_yet_valid': t('لم يبدأ', 'Not started'),
      'expired': t('منتهي', 'Expired'),
      'exhausted': t('استُنفد', 'Used up'),
    };

Map<String, String> requestStatusLabels() => {
      'pending': t('قيد المراجعة', 'Pending'),
      'approved': t('مقبول', 'Approved'),
      'rejected': t('مرفوض', 'Rejected'),
      'cancelled': t('ملغى', 'Cancelled'),
    };

Map<String, String> runStatusLabels() => {
      'queued': t('في الانتظار', 'Queued'),
      'running': t('جارٍ التوليد', 'Generating'),
      'succeeded': t('اكتمل', 'Finished'),
      'failed': t('فشل', 'Failed'),
      'cancelled': t('أُلغي', 'Cancelled'),
    };

bool runIsOpen(Map<String, dynamic>? run) => const {'queued', 'running'}.contains(run?['status']);

/// The solver's verdict (schedule.result.status / run.result_status).
Map<String, String> resultStatusLabels() => {
      'feasible': t('جدول كامل بلا تعارضات', 'Complete, no clashes'),
      'feasible_relaxed': t('كامل — مع تخفيف بعض التفضيلات', 'Complete — some preferences relaxed'),
      'partial': t('جزئي — بعض الحصص لم تُجدول', 'Partial — some sessions not placed'),
      'infeasible': t('تعذّر الجدولة بالقيود الحالية', 'Not possible with the current constraints'),
    };

String resultStatusHelp(String s) => switch (s) {
      'feasible' => t('كل الحصص في أماكنها وكل التفضيلات محترمة. راجعه ثم انشره.', 'Every session is placed and every preference kept. Review it, then publish.'),
      'feasible_relaxed' => t('كل القيود الإلزامية محترمة، وخُففت تفضيلات بعض الأشخاص (القائمة بالأسفل).',
          'Every hard rule holds; some people\'s preferences were relaxed (listed below).'),
      'partial' => t('لم تُوضع بعض الحصص — الأسباب والاقتراحات بالأسفل. الجدول لم يُنشر.',
          'Some sessions could not be placed — reasons and suggestions below. Nothing was published.'),
      'infeasible' => t('لم يمكن وضع الحصص المطلوبة. راجع الأسباب والاقتراحات، عدّل الإعداد ثم أعد التوليد.',
          'The required sessions could not be placed. Check the reasons and suggestions, adjust the setup and generate again.'),
      _ => '',
    };

/// Why a session could not be placed (solver reasons / invalid-load types).
String scheduleReasonText(String? r) =>
    {
      'teacher_unavailable': t('المدرس غير متاح', 'teacher unavailable'),
      'teacher_busy': t('المدرس مشغول', 'teacher busy'),
      'teacher_day_limit': t('حد الحمل اليومي للمدرس', 'teacher daily limit'),
      'students_clash': t('تعارض طلاب مع مقرر آخر', 'students clash with another course'),
      'students_busy_elsewhere': t('الطلاب لديهم حصص في جدول آخر', 'students busy in another timetable'),
      'students_unavailable': t('الطلاب غير متاحين', 'students unavailable'),
      'course_already_there': t('المقرر موجود في هذا الوقت', 'course already scheduled then'),
      'no_room_fits': t('لا توجد قاعة بالسعة / النوع / الإمكانات المطلوبة', 'no room with the capacity / type / capabilities'),
      'rooms_busy': t('القاعات مشغولة', 'rooms are busy'),
      'no_consecutive_periods': t('لا توجد فترات متتالية كافية', 'not enough consecutive periods'),
      'no_free_cell': t('لا توجد خلية فارغة', 'no free cell'),
      'no_teacher': t('المقرر بلا مدرس', 'the course has no teacher'),
      'teacher_not_eligible': t('المدرس المعيّن غير مؤهل', 'the assigned teacher is not eligible'),
      'no_lab_instructor': t('السكشن بلا معيد أو مدرس مسموح له', 'the lab has no allowed instructor'),
      'no_slot': t('لا يوجد موعد مناسب', 'no suitable time'),
      'no_assistant_slot': t('لم يتوفر وقت لمعيد', 'no time found for an assistant'),
      'soft_preferences': t('تفضيلات', 'preferences'),
    }[r] ??
    (r ?? '');

/// validate() conflict types — hard errors first, then warnings.
String conflictTypeText(String? type) =>
    {
      'teacher_double_booked': t('مدرس لديه حصتان متداخلتان', 'Teacher has overlapping sessions'),
      'assistant_double_booked': t('معيد لديه حصتان متداخلتان', 'Teaching assistant has overlapping sessions'),
      'admin_assistant_double_booked': t('مساعد إداري لديه حصتان متداخلتان', 'Admin assistant has overlapping sessions'),
      'room_double_booked': t('مكان حصري محجوز لحصتين متداخلتين', 'Exclusive room booked twice at overlapping times'),
      'course_overlap': t('المقرر نفسه في وقتين متداخلين', 'The same course twice at overlapping times'),
      'students_clash': t('طلاب لديهم حصتان إلزاميتان متداخلتان', 'Students have overlapping required sessions'),
      'room_busy_elsewhere': t('المكان محجوز في جدول مفعّل آخر', 'Room booked in another active timetable'),
      'staff_busy_elsewhere': t('عضو الهيئة لديه حصة في جدول مفعّل آخر', 'Staff member busy in another active timetable'),
      'students_busy_elsewhere': t('الطلاب لديهم حصة في جدول مفعّل آخر', 'Students busy in another active timetable'),
      'room_inactive': t('المكان موقوف', 'Room is inactive'),
      'room_unavailable': t('المكان غير متاح في هذا الوقت', 'Room unavailable at this time'),
      'room_too_small': t('المكان أصغر من عدد الطلاب', 'Room too small'),
      'room_missing_capabilities': t('المكان ينقصه إمكانات مطلوبة', 'Room lacks required capabilities'),
      'teacher_unavailable': t('المدرس غير متاح (قيد إلزامي)', 'Teacher unavailable (hard rule)'),
      'staff_unavailable': t('عضو الهيئة غير متاح (قيد إلزامي)', 'Staff member unavailable (hard rule)'),
      'students_unavailable': t('الطلاب غير متاحين في هذا الوقت', 'Students unavailable at this time'),
      'room_kind_mismatch': t('نوع المكان غير المطلوب', 'Room type differs from the requested one'),
      'teacher_unavailable_overridden': t('المدرس غير متاح — مسموح باستثناء معتمد', 'Teacher unavailable — allowed by an approved override'),
      'staff_unavailable_overridden': t('عضو الهيئة غير متاح — مسموح باستثناء معتمد', 'Staff unavailable — allowed by an approved override'),
      'teacher_overloaded': t('حمل المدرس اليومي أكبر من الحد', 'Teacher daily load above the limit'),
    }[type] ??
    (type ?? '');

// ═════════════════════════════════════════════════════════════════════════════
//  Join policy draft
// ═════════════════════════════════════════════════════════════════════════════

class JoinPolicyDraft {
  JoinPolicyDraft({
    this.method = 'closed',
    this.approver = 'manager',
    Set<int>? assistantIds,
    Set<String>? roles,
    this.cohort = 'both',
    Set<int>? programIds,
    Set<String>? levels,
    this.capacity,
    this.unverified = 'review',
    List<Map<String, dynamic>>? fields,
  })  : assistantIds = assistantIds ?? <int>{},
        roles = roles ?? <String>{'student'},
        programIds = programIds ?? <int>{},
        levels = levels ?? <String>{},
        fields = fields ?? <Map<String, dynamic>>[];

  String method, approver, cohort, unverified;
  final Set<int> assistantIds, programIds;
  final Set<String> roles, levels;
  int? capacity;
  final List<Map<String, dynamic>> fields;

  /// `policy` of GET /join-policy (`{method:"closed", configured:false}` when never configured).
  factory JoinPolicyDraft.fromJson(Map<String, dynamic> p) => JoinPolicyDraft(
        method: '${p['method'] ?? 'closed'}',
        approver: '${p['approver'] ?? 'manager'}',
        assistantIds: {...((p['assistant_ids'] as List?) ?? const []).map((e) => asInt(e))},
        roles: p['roles'] is List ? {...(p['roles'] as List).map((e) => '$e')} : null,
        cohort: '${p['cohort'] ?? 'both'}',
        programIds: {...((p['program_ids'] as List?) ?? const []).map((e) => asInt(e))},
        levels: {...((p['levels'] as List?) ?? const []).map((e) => '$e')},
        capacity: p['capacity'] == null ? null : asInt(p['capacity']),
        unverified: '${p['unverified'] ?? 'review'}',
        fields: [for (final f in asMapList(p['fields'])) Map<String, dynamic>.from(f)],
      );

  bool get needsApprover => method == 'approval';

  /// Audience narrowing by cohort / level only makes sense for students.
  bool get targetsStudents => roles.contains('student');

  /// The PUT body. The PUT replaces the whole policy, so every field is sent; settings that don't apply to the
  /// chosen method are sent with their neutral defaults instead of stale values.
  Map<String, dynamic> toBody() => {
        'method': method,
        'approver': needsApprover ? approver : 'manager',
        'assistant_ids': needsApprover && approver == 'assistants' ? (assistantIds.toList()..sort()) : <int>[],
        'roles': roles.toList(),
        'cohort': targetsStudents ? cohort : 'both',
        'program_ids': programIds.toList()..sort(),
        'levels': targetsStudents ? (levels.toList()..sort()) : <String>[],
        'capacity': capacity,
        'unverified': unverified,
        'fields': [
          for (final f in fields)
            {
              'key': f['key'] ?? '',
              'label': '${f['label'] ?? ''}',
              'type': '${f['type'] ?? 'text'}',
              'required': f['required'] == true,
              'options': [for (final o in (f['options'] as List? ?? const [])) '$o'],
              if ('${f['help'] ?? ''}'.isNotEmpty) 'help': f['help'],
              if (f['bind'] != null) 'bind': f['bind'],
              if (f['bind'] != null && (f['allowed'] as List? ?? const []).isNotEmpty) 'allowed': [for (final a in f['allowed'] as List) '$a'],
            }
        ],
      };

  /// Local checks that mirror the server's (the server stays authoritative).
  String? validate() {
    if (roles.isEmpty) return _codeTexts()['bad_roles'];
    if (needsApprover && approver == 'assistants' && assistantIds.isEmpty) return _codeTexts()['no_assistants'];
    if (capacity != null && capacity! < 1) return t('السعة يجب أن تكون 1 أو أكثر', 'Capacity must be 1 or more');
    for (final f in fields) {
      if ('${f['label'] ?? ''}'.trim().isEmpty) return _codeTexts()['field_label'];
      final choice = f['type'] == 'select' || f['type'] == 'multiselect';
      if (choice && f['bind'] == null && (f['options'] as List? ?? const []).isEmpty) return _codeTexts()['field_options'];
    }
    return null;
  }
}

/// The code a member must type: only when the method is `code` (or the server says one is required).
bool unitNeedsCode(Map<String, dynamic> policy) => policy['code_required'] == true || policy['method'] == 'code';

// ═════════════════════════════════════════════════════════════════════════════
//  Schedule draft
// ═════════════════════════════════════════════════════════════════════════════

const scheduleDays = ['saturday', 'sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday'];

class ScheduleDraft {
  ScheduleDraft();

  int? id;
  String name = '', termLabel = '', status = 'draft';
  int? termId;
  DateTime? start, end;
  final Set<int> courseIds = {};
  Map<String, dynamic> settings = {};

  bool get published => status == 'active';

  List<String> get days => settings['days'] is List
      ? [for (final d in scheduleDays) if ((settings['days'] as List).contains(d)) d]
      : scheduleDays.take(6).toList();
  set days(List<String> v) => settings['days'] = [for (final d in scheduleDays) if (v.contains(d)) d];

  factory ScheduleDraft.fromJson(Map<String, dynamic> s, {Iterable<int> allCourses = const []}) {
    final d = ScheduleDraft()
      ..id = s['id'] == null ? null : asInt(s['id'])
      ..name = '${s['name'] ?? ''}'
      ..termLabel = '${s['term_label'] ?? ''}'
      ..status = '${s['status'] ?? 'draft'}'
      ..termId = s['term_id'] == null ? null : asInt(s['term_id'])
      ..start = DateTime.tryParse('${s['start_date'] ?? ''}')
      ..end = DateTime.tryParse('${s['end_date'] ?? ''}')
      ..settings = Map<String, dynamic>.from(asMap(s['settings']));
    // course_ids == null on the server means "every course"
    d.courseIds.addAll(s['course_ids'] is List ? (s['course_ids'] as List).map((e) => asInt(e)) : allCourses);
    return d;
  }

  /// POST/PUT body. The PUT replaces everything, so the full current state is always sent.
  Map<String, dynamic> toBody() => {
        'name': name.trim(),
        'term_label': termLabel.trim().isEmpty ? null : termLabel.trim(),
        'term_id': termId,
        'start_date': start == null ? null : orgDay(start),
        'end_date': end == null ? null : orgDay(end),
        'course_ids': courseIds.toList()..sort(),
        'settings': settings,
      };

  String? validate() {
    if (name.trim().isEmpty) return t('اكتب اسماً للجدول', 'Give the timetable a name');
    if (start != null && end != null && !start!.isBefore(end!)) return _codeTexts()['bad_dates'];
    if (courseIds.isEmpty) return t('اختر مقرراً واحداً على الأقل', 'Pick at least one course');
    if (days.isEmpty) return t('اختر يوماً دراسياً واحداً على الأقل', 'Pick at least one teaching day');
    return null;
  }
}
