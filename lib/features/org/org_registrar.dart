// lib/features/org/org_registrar.dart — the credit-hour registrar: shared, PURE logic and texts
// (API: /orgs/{org}/registrar/… for staff, /public/{org}/registrar/… for students and instructors;
// backend: ../back/services/organization/registrar/).
//
//   registrarCodeText     every block / warning / decision code → bilingual sentence
//   milestoneLabel        the generated calendar's milestones
//   RegCart               the courses a student is about to register together (coreqs need one cart)
//   loadAfter             credit load if the cart is registered, against the term's min / max
//   meetingText           "Sun 08:00–09:30" (AppTime.clock applies 12h/24h)
//   decisionKindText / riskText / decisionActionText
library;

import 'dart:math';

import 'package:flutter_education_app/design/app_kit.dart' show AppTime;

import '../admin/admin_common.dart';

const registrarMilestones = [
  'registration_start', 'registration_end', 'classes_start', 'add_drop_end', 'midterm_start', 'withdraw_deadline',
  'classes_end', 'exam_start', 'exam_end', 'grade_deadline', 'results_release',
];

String milestoneLabel(String k) => switch (k) {
      'registration_start' => t('بدء التسجيل', 'Registration opens'),
      'registration_end' => t('نهاية التسجيل', 'Registration closes'),
      'classes_start' => t('بدء الدراسة', 'Classes start'),
      'add_drop_end' => t('نهاية الحذف والإضافة', 'Add / drop ends'),
      'midterm_start' => t('منتصف الفصل', 'Midterm'),
      'withdraw_deadline' => t('آخر موعد للانسحاب', 'Withdrawal deadline'),
      'classes_end' => t('نهاية الدراسة', 'Classes end'),
      'exam_start' => t('بدء الامتحانات', 'Exams start'),
      'exam_end' => t('نهاية الامتحانات', 'Exams end'),
      'grade_deadline' => t('آخر موعد لرصد الدرجات', 'Grade submission deadline'),
      'results_release' => t('إعلان النتائج', 'Results released'),
      _ => k,
    };

String windowText(String? w) => switch (w) {
      'before' => t('التسجيل لم يبدأ بعد', 'Registration has not opened yet'),
      'registration' => t('التسجيل مفتوح', 'Registration is open'),
      'add_drop' => t('فترة الحذف والإضافة', 'Add / drop period'),
      'withdraw' => t('فترة الانسحاب فقط', 'Withdrawal period only'),
      'closed' => t('التسجيل مغلق', 'Registration is closed'),
      _ => '',
    };

String termKindText(String? k) => switch (k) {
      'term1' => t('الفصل الأول', 'Fall'),
      'term2' => t('الفصل الثاني', 'Spring'),
      'summer' => t('الفصل الصيفي', 'Summer'),
      _ => k ?? '',
    };

String termTitle(Map<String, dynamic> term) => '${termKindText(term['kind'])} ${term['year_label'] ?? ''}'.trim();

String courseKindText(String? k) => switch (k) {
      'theory' => t('نظري', 'Theory'),
      'theory_lab' => t('نظري وعملي', 'Theory + lab'),
      'lab' => t('عملي فقط', 'Lab only'),
      _ => k ?? '',
    };

String reqModeText(String? m) => switch (m) {
      'passed' => t('نجاح سابق', 'Passed before'),
      'concurrent' => t('سابق أو متزامن', 'Before or together'),
      'coreq' => t('متزامن (معاً)', 'Co-requisite'),
      _ => m ?? '',
    };

String rankText(String? r) => switch (r) {
      'professor' => t('أستاذ', 'Professor'),
      'associate_professor' => t('أستاذ مشارك', 'Associate professor'),
      'assistant_professor' => t('أستاذ مساعد', 'Assistant professor'),
      'lecturer' => t('مدرس', 'Lecturer'),
      'assistant_lecturer' => t('مدرس مساعد', 'Assistant lecturer'),
      'demonstrator' => t('معيد', 'Teaching assistant (demonstrator)'),
      _ => r ?? t('غير محددة', 'Not set'),
    };

String standingText(String? s) => switch (s) {
      'good' => t('وضع أكاديمي جيد', 'Good standing'),
      'probation' => t('إنذار أكاديمي', 'Academic probation'),
      'honours' => t('قائمة الشرف', "Dean's list"),
      _ => '',
    };

String regStatusText(String? s) => switch (s) {
      'registered' => t('مسجّل', 'Registered'),
      'waitlisted' => t('قائمة الانتظار', 'Waitlisted'),
      'dropped' => t('محذوف', 'Dropped'),
      'withdrawn' => t('منسحب (W)', 'Withdrawn (W)'),
      'completed' => t('مكتمل', 'Completed'),
      _ => s ?? '',
    };

String gradeStateText(String? s) => switch (s) {
      'none' => t('لم تُرصد', 'Not entered'),
      'draft' => t('مسودة', 'Draft'),
      'submitted' => t('مرسلة للاعتماد', 'Submitted'),
      'approved' => t('معتمدة', 'Approved'),
      _ => s ?? '',
    };

/// Block / warning / error codes of the registrar (registrar_text.py MSG keeps the same wording).
String registrarCodeText(String code) => switch (code) {
      'not_org_course' => t('المقرر لا يتبع هذه المؤسسة', 'This course does not belong to the organization'),
      'auto_registration' => t('التسجيل في برنامجك تلقائي حسب الفرقة', 'Registration in your program is automatic by year'),
      'course_not_configured' => t('لم تُحدَّد الساعات المعتمدة للمقرر بعد', "The course's credit hours are not set yet"),
      'window_closed' => t('فترة التسجيل مغلقة', 'The registration window is closed'),
      'pending_limit' => t('لديك طلبات قيد الانتظار بالفعل — انتظر نتيجتها أولاً', 'You already have requests waiting — wait for their result first'),
      'idempotency_mismatch' => t('أُعيد استخدام مفتاح الطلب لطلب مختلف — أعد المحاولة', 'The request key was reused for a different request — try again'),
      'gone' => t('لم يعد المقرر أو الفصل موجوداً', 'The course or term no longer exists'),
      'internal' => t('تعذر إتمام الطلب — تواصل مع شؤون الطلاب', 'The request could not be completed — contact the registrar'),
      'not_offered_this_term' => t('لا يُطرح في هذا الفصل', 'Not offered this term'),
      'other_program' => t('تابع لقسم علمي آخر', 'Belongs to another department'),
      'already_registered' => t('مسجّل بالفعل', 'Already registered'),
      'withdrawn_this_term' => t('انسحبت منه هذا الفصل', 'You withdrew from it this term'),
      'already_passed' => t('نجحت فيه بتقدير لا يسمح بإعادته', 'Already passed — cannot be retaken'),
      'max_attempts' => t('استنفدت مرات الإعادة', 'No retake attempts left'),
      'retake_counts' => t('إعادة: يُحتسب التقدير حسب لائحة الإعادة', 'Retake: the grade counts per the retake policy'),
      'missing_prereq' => t('لم تستوفِ المتطلبات السابقة', 'Prerequisites not met'),
      'prereq_pending' => t('المتطلب قيد الدراسة — مقبول بشرط النجاح فيه', 'Prerequisite in progress — allowed if you pass it'),
      'max_load' => t('تتجاوز الحد الأقصى للساعات', 'Above your maximum credit load'),
      'no_sections' => t('لا توجد شعب مطروحة بعد', 'No sections offered yet'),
      'bad_section' => t('الشعبة غير موجودة', 'Unknown section'),
      'time_conflict' => t('تعارض في المواعيد', 'Time conflict'),
      'section_full' => t('الشعبة ممتلئة', 'The section is full'),
      'waitlist_full' => t('قائمة الانتظار ممتلئة', 'The waitlist is full'),
      'offered_once' => t('يُطرح مرة واحدة سنوياً — تأجيله قد يؤخر تخرجك', 'Offered once a year — postponing it may delay graduation'),
      'not_registered' => t('غير مسجّل', 'Not registered'),
      'grade_locked' => t('الدرجة معتمدة ومغلقة', 'The grade is approved and locked'),
      'grade_submitted' => t('أُرسلت للاعتماد', 'Already submitted'),
      'bad_percent' => t('الدرجة بين 0 و100', 'Score must be 0–100'),
      'bad_letter' => t('تقدير غير موجود في السلم', 'Letter not in the grade scale'),
      'requisite_cycle' => t('المتطلبات تكوّن حلقة لا يمكن استيفاؤها', 'The requisites form a cycle that can never be met'),
      'requisite_self' => t('لا يكون المقرر متطلباً لنفسه', 'A course cannot require itself'),
      'theory_has_lab' => t('المقرر النظري لا يحتوي ساعات معمل', 'A theory course has no lab hours'),
      'lab_hours_required' => t('حدد ساعات المعمل', 'Set the lab hours'),
      'lab_has_lecture' => t('المقرر العملي فقط لا يحتوي محاضرات', 'A lab-only course has no lecture hours'),
      'bad_calendar' => t('تواريخ التقويم ناقصة أو غير مرتبة', 'Calendar dates are missing or out of order'),
      'no_active_schedule' => t('لا يوجد جدول دراسي معتمد لهذا الفصل', 'No active timetable for this term'),
      'capacity_below_enrolled' => t('السعة أقل من عدد المسجلين', 'Capacity is below the enrolled count'),
      'override_reason_required' => t('اكتب سبب الاستثناء', 'Write the reason for the exception'),
      'not_eligible_to_graduate' => t('لم يستوفِ متطلبات التخرج', 'Graduation requirements are not met'),
      'decision_closed' => t('تم البت في هذا القرار', 'This decision was already taken'),
      'decision_cannot_apply' => t('تعذّر تنفيذ القرار', 'The decision cannot be applied'),
      'no_exception_needed' => t('يمكنك التسجيل مباشرة', 'You can register directly'),
      'exception_not_possible' => t('لا يمكن طلب استثناء لهذا السبب', 'No exception is possible for this reason'),
      'bad_registrar_rules' => t('قيمة غير صحيحة في اللائحة (راجع سلم التقديرات والحدود)', 'Invalid rule value (check the grade scale and limits)'),
      'staff_consent_pending' => t('بانتظار موافقة أعضاء هيئة التدريس', 'Waiting for staff consent'),
      'not_advisor' => t('لست المرشد الأكاديمي لهذا الطالب', "You are not this student's advisor"),
      'not_instructor' => t('لست مدرس هذا المقرر', 'You do not teach this course'),
      'students_only' => t('التسجيل للطلاب فقط', 'Registration is for students'),
      _ => code,
    };

/// The first block of an evaluation, with its details (missing courses, limits …) when useful.
String blockText(Map<String, dynamic> b, {String Function(int id)? courseName}) {
  final code = '${b['code']}';
  var s = registrarCodeText(code);
  if (code == 'max_load') {
    final lim = asMap(b['limits']);
    s += ' (${asDouble(b['load']).toStringAsFixed(0)} + ${asDouble(b['credits']).toStringAsFixed(0)} > ${lim['max']})';
  }
  if (code == 'missing_prereq' && courseName != null) {
    final names = [for (final m in asMapList(b['missing'])) courseName(asInt(m['course_id']))];
    if (names.isNotEmpty) s += ': ${names.join('، ')}';
  }
  return s;
}

String decisionKindText(String? k) => switch (k) {
      'registration_exception' => t('طلب استثناء تسجيل', 'Registration exception'),
      'prereq_failed' => t('رسوب في متطلب سابق', 'Prerequisite failed'),
      'coreq_dropped' => t('حذف مقرر متزامن', 'Co-requisite dropped'),
      'section_overbooked' => t('شعبة أكبر من قاعتها', 'Section larger than its room'),
      'section_removed' => t('شعبة حُذفت من الجدول', 'Section removed from the timetable'),
      'attendance_denial' => t('حرمان من الامتحان', 'Exam denial (attendance)'),
      'graduation_candidates' => t('مرشحون للتخرج', 'Graduation candidates'),
      'calendar_generated' => t('تقويم مولّد تلقائياً', 'Generated calendar'),
      'grades_submitted' => t('درجات بانتظار الاعتماد', 'Grades awaiting approval'),
      'staff_consent' => t('موافقة عضو على الجدول', 'Staff consent'),
      'staff_overload' => t('عبء تدريسي زائد', 'Teaching overload'),
      'allocation_tie' => t('تساوٍ عند حد القبول', 'Tie at the admission cut-off'),
      'allocation_done' => t('توزيع الأقسام بالجدارة', 'Departments allocated by merit'),
      'missing_term' => t('فصل ناقص — مسودة جاهزة', 'Missing term — draft ready'),
      'missing_offerings' => t('مقررات فصل غير مطروحة — مسودة جاهزة', 'Term without offerings — draft ready'),
      'missing_periods' => t('فترات اليوم ناقصة — مسودة جاهزة', 'No periods — draft ready'),
      _ => k ?? '',
    };

String riskText(String? r) => switch (r) {
      'false_positive' => t('خطر السماح بما لا يجب', 'Risk: allowing something invalid'),
      'false_negative' => t('خطر منع ما يحق للطالب', 'Risk: blocking something valid'),
      _ => t('لا خطر', 'No risk'),
    };

String decisionActionText(Map<String, dynamic>? a) => switch (a?['action']) {
      'register' => t('تسجيل الطالب استثناءً', 'Register as an exception'),
      'drop' => t('حذف التسجيل', 'Drop the registration'),
      'capacity' => t('تغيير سعة الشعبة', 'Change the section capacity'),
      'waive_denial' => t('إلغاء الحرمان', 'Waive the denial'),
      'graduate' => t('اعتماد التخرج', 'Approve graduation'),
      'program_seat' => t('مقعد إضافي وقبولهم', 'Add seats and admit them'),
      'keep' => t('الإبقاء كما هو', 'Keep as it is'),
      'open_offerings' => t('طرح ${(a?['params']?['course_ids'] as List?)?.length ?? 0} مقرر', 'Offer ${(a?['params']?['course_ids'] as List?)?.length ?? 0} courses'),
      'create_periods' => t('إنشاء فترات اليوم', 'Create the day periods'),
      'create_term' => t('إنشاء الفصل ${a?['params']?['year_label'] ?? ''}', 'Create the term ${a?['params']?['year_label'] ?? ''}'),
      'none' || null => t('لا إجراء', 'No action'),
      _ => '${a?['action']}',
    };

const _days = {
  'saturday': ('السبت', 'Sat'), 'sunday': ('الأحد', 'Sun'), 'monday': ('الاثنين', 'Mon'),
  'tuesday': ('الثلاثاء', 'Tue'), 'wednesday': ('الأربعاء', 'Wed'), 'thursday': ('الخميس', 'Thu'),
  'friday': ('الجمعة', 'Fri'),
};

/// Weekday key ("sunday") → short localized name.
String dayText(String day) {
  final d = _days[day];
  return d == null ? day : t(d.$1, d.$2);
}

/// One meeting {day, start, end} (minutes after midnight) → "Sun 08:00–09:30".
String meetingText(Map<String, dynamic> m) {
  final d = _days[m['day']];
  final day = d == null ? '${m['day']}' : t(d.$1, d.$2);
  return '$day ${AppTime.clockMinutes(asInt(m['start']))}–${AppTime.clockMinutes(asInt(m['end']))}';
}

String sectionLabel(Map<String, dynamic> s) =>
    s['kind'] == 'lab' ? t('سكشن ${s['group_no']}', 'Lab ${s['group_no']}') : t('مجموعة ${s['group_no']}', 'Group ${s['group_no']}');

// ═════════════════════════════════════════════════════════════════════════════
//  Cart (pure — unit tested)
// ═════════════════════════════════════════════════════════════════════════════

class RegCart {
  final Map<int, ({int? section, int? lab, double credits})> items = {};

  bool has(int courseId) => items.containsKey(courseId);
  void put(int courseId, double credits, {int? section, int? lab}) =>
      items[courseId] = (section: section, lab: lab, credits: credits);
  void remove(int courseId) => items.remove(courseId);
  void clear() => items.clear();
  bool get isEmpty => items.isEmpty;
  double get credits => items.values.fold(0.0, (a, b) => a + b.credits);

  List<Map<String, dynamic>> toJson() => [
        for (final e in items.entries)
          {'course_id': e.key, if (e.value.section != null) 'section_id': e.value.section, if (e.value.lab != null) 'lab_section_id': e.value.lab},
      ];

  /// Co-requisites of [courseId] (from its requisites) that are neither in the cart nor already registered —
  /// the student must add them to the same cart.
  static List<int> missingCoreqs(Map<String, dynamic> course, Set<int> inCart, Set<int> registered) => [
        for (final r in asMapList(course['requisites']))
          if (r['mode'] == 'coreq' && !inCart.contains(asInt(r['course_id'])) && !registered.contains(asInt(r['course_id'])))
            asInt(r['course_id']),
      ];
}

/// Load after registering [extra] credits: {load, min, max, over, under}.
({double load, int min, int max, bool over, bool under}) loadAfter(double current, double extra, Map<String, dynamic> limits) {
  final load = current + extra;
  final lo = asInt(limits['min']), hi = asInt(limits['max'], 99);
  return (load: load, min: lo, max: hi, over: load > hi, under: load < lo);
}

/// GPA to two decimals (null → "—").
String gpaText(dynamic v) => v == null ? '—' : asDouble(v).toStringAsFixed(2);

// ── queue-first registration (server: POST …/register-requests, D-015) ──────────────────────────────────────────

/// Is a queued registration request finished?
bool regRequestDone(String? status) => status == 'done' || status == 'failed';

/// What the waiting sheet says while the request is in the queue.
String regQueueText(String? status, {int? depth}) => switch (status) {
      'queued' => depth != null && depth > 1
          ? t('طلبك في الصف — أمامك ${depth - 1}', 'In line — ${depth - 1} ahead of you')
          : t('طلبك في الصف', 'Your request is in line'),
      'processing' => t('يتم تسجيلك الآن…', 'Registering you now…'),
      'done' => t('تم', 'Done'),
      'failed' => t('لم يُقبل الطلب', 'The request was not accepted'),
      _ => t('جارٍ الإرسال…', 'Sending…'),
    };

/// One line per course from a finished request (`result` of the status reply or the synchronous reply):
/// a cart `{results: {courseId: {status, blocks}}}` or a single `{status, registration, blocks}`.
List<String> regResultLines(Map<String, dynamic> result, String Function(int id) nameOf) {
  final lines = <String>[];
  final results = asMap(result['results']);
  if (results.isNotEmpty) {
    results.forEach((cid, v) {
      final m = asMap(v);
      final st = '${m['status']}';
      final why = st == 'rejected' ? blockText(asMapList(m['blocks']).firstOrNull ?? const {}, courseName: nameOf) : regStatusText(st);
      lines.add('${nameOf(asInt(cid))}: $why');
    });
    return lines;
  }
  final st = '${result['status'] ?? ''}';
  if (st.isEmpty) return lines;
  final cid = asInt(asMap(result['registration'])['course_id']);
  final why = st == 'rejected' ? blockText(asMapList(result['blocks']).firstOrNull ?? const {}, courseName: nameOf) : regStatusText(st);
  lines.add(cid > 0 ? '${nameOf(cid)}: $why' : why);
  return lines;
}

/// Was a submit turned away before anything was stored (admission control 503, throttle 429, a dying server, or
/// no answer at all — a dropped socket, status 0)? The client may retry with the SAME idempotency key; nothing is
/// registered until a 202 / 200 comes back, and a key that did get through returns the same request.
bool regQueueBusy(String? code, int statusCode) =>
    code != 'pending_limit' && code != 'idempotency_mismatch' && (code == 'too_many_attempts' || statusCode == 429 || statusCode >= 500 || statusCode <= 0);

/// After the retries: was the request CERTAINLY not stored (429 throttle, 503 admission control) — or do we simply
/// not know (another 5xx, no answer)? The server stores the request before it dispatches it, so a 500 or a dropped
/// socket may hide a stored request: say "could not confirm" and point to My requests, never "nothing was registered".
bool regSubmitCertainlyRejected(String? code, int statusCode) => statusCode == 429 || statusCode == 503 || code == 'too_many_attempts';

/// How long to wait before the next status poll: what the server says (`poll_after_ms`), kept between 1 and 10 s.
int regPollAfterMs(Object? v) {
  final n = asInt(v);
  return n <= 0 ? 1500 : n.clamp(1000, 10000);
}

/// A client-side idempotency key: one per submit attempt, reused by that attempt's retries.
String newIdempotencyKey() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${Random().nextInt(1 << 30).toRadixString(36)}';
