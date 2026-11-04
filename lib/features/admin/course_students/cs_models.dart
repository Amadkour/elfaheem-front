// lib/features/admin/course_students/cs_models.dart
//
// Models, the reason -> words mapping and the server error texts of the Super Admin's "Courses & students" console
// (GET/POST /api/v1/admin/course-students/..., contract: back docs/subscriptions/CONTRACT.md). Plain Dart, tolerant
// of missing keys and unknown enum values; every time is a UTC instant.
library;

import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

// ── parsing helpers ─────────────────────────────────────────────────────────

Map<String, dynamic> csMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> csList(Object? v) => v is List ? v : const [];
String? csStr(Object? v) => v == null ? null : (v.toString().isEmpty ? null : v.toString());
int csInt(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
int? csIntOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double csNum(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

final RegExp _hasZone = RegExp(r'(Z|z|[+-]\d\d:?\d\d)$');

/// The server writes naive UTC strings; one with an offset is converted. Null for anything unreadable.
DateTime? csTime(Object? v) {
  if (v is! String || v.isEmpty) return null;
  final d = DateTime.tryParse(_hasZone.hasMatch(v) ? v : '${v}Z');
  return d?.toUtc();
}

// ── statuses ────────────────────────────────────────────────────────────────

enum CsStatus { active, expiringSoon, expired, cancelled, paymentIssue, accessError, notEnrolled, staff, unknown }

CsStatus csStatusOf(String? s) => switch (s) {
      'active' => CsStatus.active,
      'expiring_soon' => CsStatus.expiringSoon,
      'expired' => CsStatus.expired,
      'cancelled' => CsStatus.cancelled,
      'payment_issue' => CsStatus.paymentIssue,
      'access_error' => CsStatus.accessError,
      'not_enrolled' => CsStatus.notEnrolled,
      'staff' => CsStatus.staff,
      _ => CsStatus.unknown,
    };

/// The wire value of a status filter (the roster's `status=`).
String csStatusWire(CsStatus s) => switch (s) {
      CsStatus.expiringSoon => 'expiring_soon',
      CsStatus.paymentIssue => 'payment_issue',
      CsStatus.accessError => 'access_error',
      CsStatus.notEnrolled => 'not_enrolled',
      _ => s.name,
    };

/// The statuses a roster can be filtered by, in display order.
const List<CsStatus> csFilterStatuses = [
  CsStatus.active,
  CsStatus.expiringSoon,
  CsStatus.expired,
  CsStatus.cancelled,
  CsStatus.paymentIssue,
  CsStatus.accessError,
  CsStatus.notEnrolled,
];

String csStatusLabel(CsStatus s) => switch (s) {
      CsStatus.active => t('نشط', 'Active'),
      CsStatus.expiringSoon => t('ينتهي قريباً', 'Expiring soon'),
      CsStatus.expired => t('منتهي', 'Expired'),
      CsStatus.cancelled => t('ملغي', 'Cancelled'),
      CsStatus.paymentIssue => t('مشكلة في الدفع', 'Payment issue'),
      CsStatus.accessError => t('خطأ في الوصول', 'Access error'),
      CsStatus.notEnrolled => t('غير مسجّل', 'Not enrolled'),
      CsStatus.staff => t('طاقم', 'Staff'),
      CsStatus.unknown => t('غير معروف', 'Unknown'),
    };

String csPlanLabel(String? p) => switch (p) {
      'monthly' => t('شهري', 'Monthly'),
      'six_months' => t('6 أشهر', '6 months'),
      'yearly' => t('سنوي', 'Yearly'),
      null || '' => t('بدون باقة', 'No plan'),
      _ => p,
    };

String csSourceLabel(String? s) => switch (s) {
      'package' => t('باقة', 'Bundle'),
      'direct' => t('شراء مباشر', 'Direct purchase'),
      'admin_grant' => t('منحة من الإدارة', 'Admin grant'),
      'free' => t('مجاني', 'Free'),
      'org' => t('مؤسسة', 'Organization'),
      'staff' => t('طاقم', 'Staff'),
      _ => '-',
    };

// ── CourseAccess ────────────────────────────────────────────────────────────

class CsAccess {
  const CsAccess({
    this.hasAccess = false,
    this.reason = '',
    this.courseId,
    this.source,
    this.subscriptionId,
    this.paymentId,
    this.plan,
    this.startsAt,
    this.expiresAt,
    this.daysLeft,
    this.status = '',
    this.flags = const [],
  });

  final bool hasAccess;
  final String reason;
  final int? courseId;
  final String? source;
  final int? subscriptionId;
  final int? paymentId;
  final String? plan;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? daysLeft;
  final String status;
  final List<String> flags;

  CsStatus get kind => csStatusOf(status);
  bool get paidNoAccess => flags.contains('paid_no_access');
  bool get accessNoPayment => flags.contains('access_no_payment');

  factory CsAccess.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsAccess(
      hasAccess: j['has_access'] == true,
      reason: csStr(j['reason']) ?? '',
      courseId: csIntOrNull(j['course_id']),
      source: csStr(j['source']),
      subscriptionId: csIntOrNull(j['subscription_id']),
      paymentId: csIntOrNull(j['payment_id']),
      plan: csStr(j['plan']),
      startsAt: csTime(j['starts_at']),
      expiresAt: csTime(j['expires_at']),
      daysLeft: csIntOrNull(j['days_left']),
      status: csStr(j['status']) ?? '',
      flags: csList(j['flags']).map((e) => '$e').toList(),
    );
  }
}

String _d(DateTime? d) => d == null ? '-' : AppTime.date(d);

/// The exact reason for the access answer, in plain words (the diagnostic box's line).
String csReasonText(CsAccess a) {
  final end = a.expiresAt;
  switch (a.reason) {
    case 'staff':
      return t('وصول بحكم الدور (طاقم) دون حاجة لباقة', 'Access through the staff role, no plan needed');
    case 'enrolled':
      return end == null
          ? t('وصول مفتوح بدون تاريخ انتهاء', 'Open access with no end date')
          : t('الباقة سارية حتى ${_d(end)}', 'The plan runs until ${_d(end)}');
    case 'expired':
      return t('انتهت الباقة في ${_d(end)}', 'Plan ended on ${_d(end)}');
    case 'cancelled':
      if (a.paidNoAccess && end != null && end.isAfter(DateTime.now().toUtc())) {
        return t('أزالته الإدارة بينما الباقة المدفوعة سارية حتى ${_d(end)}',
            'Removed by an admin while the paid plan still runs until ${_d(end)}');
      }
      return t('أُلغي الاشتراك', 'The enrollment was cancelled');
    case 'refunded':
      return t('أُعيد مبلغ الدفعة فسقط الوصول', 'The payment was refunded, so access ended');
    case 'payment_pending':
      return t('الدفع قيد المراجعة', 'Payment pending review');
    case 'payment_failed':
      return t('فشلت عملية الدفع', 'The payment failed');
    case 'org_subscription_required':
      return t('تتطلب المؤسسة اشتراكاً ساري المفعول', "The organization's subscription is required");
    case 'not_enrolled':
      return t('لم يسجّل في هذه الدورة', 'Never enrolled in this course');
    default:
      return a.hasAccess ? t('لديه وصول', 'Has access') : t('لا وصول', 'No access');
  }
}

String csFlagText(String flag) => switch (flag) {
      'paid_no_access' => t('دفع لكن لا يملك وصولاً', 'Paid but has no access'),
      'access_no_payment' => t('لديه وصول دون دفعة مكتملة', 'Has access without a completed payment'),
      _ => flag,
    };

/// Whether the console offers [action] for a course in this state (the server re-checks every rule).
bool csActionValid(String action, CsAccess a) {
  final enrolledRow = a.reason != 'not_enrolled' && a.status != 'not_enrolled';
  switch (action) {
    case 'extend':
      return enrolledRow && a.expiresAt != null;
    case 'reactivate':
      return !a.hasAccess && (a.reason == 'cancelled' || a.reason == 'expired');
    case 'grant':
      return !a.hasAccess;
    case 'cancel':
      return a.hasAccess && a.reason != 'staff';
  }
  return false;
}

// ── lookups, rows ───────────────────────────────────────────────────────────

class CsPerson {
  const CsPerson({required this.id, this.name = '', this.nameEn});
  final int id;
  final String name;
  final String? nameEn;

  factory CsPerson.fromJson(Object? raw) {
    final j = csMap(raw);
    final ar = csStr(j['name']) ?? csStr(j['name_ar']) ?? '';
    return CsPerson(id: csInt(j['id']), name: csPick(ar, csStr(j['name_en'])), nameEn: csStr(j['name_en']));
  }
}

/// Picks the Arabic or English name of a row that carries both.
String csPick(String ar, String? en) => t(ar, (en == null || en.isEmpty) ? ar : en);

class CsCourseRow {
  const CsCourseRow({
    required this.id,
    this.nameAr = '',
    this.nameEn = '',
    this.imageUrl,
    this.teacher,
    this.category,
    this.org,
    this.status = '',
    this.active = 0,
    this.expiringSoon = 0,
    this.expired = 0,
    this.issues = 0,
    this.revenue = 0,
    this.currency = '',
  });

  final int id;
  final String nameAr;
  final String nameEn;
  final String? imageUrl;
  final CsPerson? teacher;
  final CsPerson? category;
  final CsPerson? org;
  final String status;
  final int active;
  final int expiringSoon;
  final int expired;
  final int issues;
  final double revenue;
  final String currency;

  String get name => csPick(nameAr, nameEn);

  factory CsCourseRow.fromJson(Object? raw) {
    final j = csMap(raw);
    final rev = csMap(j['revenue']);
    return CsCourseRow(
      id: csInt(j['id']),
      nameAr: csStr(j['name_ar']) ?? csStr(j['name']) ?? '',
      nameEn: csStr(j['name_en']) ?? '',
      imageUrl: csStr(j['image_url']),
      teacher: j['teacher'] is Map ? CsPerson.fromJson(j['teacher']) : null,
      category: j['category'] is Map ? CsPerson.fromJson(j['category']) : null,
      org: j['org'] is Map ? CsPerson.fromJson(j['org']) : null,
      status: csStr(j['status']) ?? '',
      active: csInt(j['active_students']),
      expiringSoon: csInt(j['expiring_soon']),
      expired: csInt(j['expired_subscriptions']),
      issues: csInt(j['issues']),
      revenue: csNum(rev['amount']),
      currency: csStr(rev['currency']) ?? '',
    );
  }
}

String csCourseStatusLabel(String s) => switch (s) {
      'published' => t('منشورة', 'Published'),
      'draft' => t('مسودة', 'Draft'),
      'archived' => t('مؤرشفة', 'Archived'),
      _ => s.isEmpty ? '-' : s,
    };

class CsCoursesPage {
  const CsCoursesPage({this.items = const [], this.total = 0, this.page = 1, this.pageSize = 20, this.teachers = const [], this.categories = const [], this.orgs = const []});
  final List<CsCourseRow> items;
  final int total;
  final int page;
  final int pageSize;
  final List<CsPerson> teachers;
  final List<CsPerson> categories;
  final List<CsPerson> orgs;

  int get pages => total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize;

  factory CsCoursesPage.fromJson(Object? raw) {
    final j = csMap(raw);
    final f = csMap(j['filters']);
    List<CsPerson> people(Object? v) => csList(v).map(CsPerson.fromJson).toList();
    return CsCoursesPage(
      items: csList(j['items']).map(CsCourseRow.fromJson).toList(),
      total: csInt(j['total']),
      page: csInt(j['page'], 1),
      pageSize: csInt(j['page_size'], 20),
      teachers: people(f['teachers']),
      categories: people(f['categories']),
      orgs: people(f['orgs']),
    );
  }
}

class CsStudent {
  const CsStudent({required this.id, this.name = '', this.email, this.phone, this.username, this.imageUrl, this.matchedBy});
  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? username;
  final String? imageUrl;
  final String? matchedBy;

  String get contact => email ?? phone ?? (username == null ? '' : '@$username');

  factory CsStudent.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsStudent(
      id: csInt(j['id']),
      name: csStr(j['name']) ?? '',
      email: csStr(j['email']),
      phone: csStr(j['phone']),
      username: csStr(j['username']),
      imageUrl: csStr(j['image_url']),
      matchedBy: csStr(j['matched_by']),
    );
  }
}

String csMatchedByLabel(String? m) => switch (m) {
      'id' => t('رقم المستخدم', 'User id'),
      'email' => t('البريد', 'E-mail'),
      'phone' => t('الهاتف', 'Phone'),
      'username' => t('اسم المستخدم', 'Username'),
      'name' => t('الاسم', 'Name'),
      'academic_id' => t('الرقم الأكاديمي', 'Academic ID'),
      'national_id' => t('الرقم القومي', 'National ID'),
      'student_code' => t('كود الطالب', 'Student code'),
      _ => '',
    };

class CsPayment {
  const CsPayment({required this.id, this.courseId, this.status = '', this.amount = 0, this.currency = '', this.provider, this.method, this.plan, this.createdAt, this.paidAt, this.refundedAt});
  final int id;
  final int? courseId;
  final String status;
  final double amount;
  final String currency;
  final String? provider;
  final String? method;
  final String? plan;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? refundedAt;

  factory CsPayment.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsPayment(
      id: csInt(j['id']),
      courseId: csIntOrNull(j['course_id']),
      status: csStr(j['status']) ?? '',
      amount: csNum(j['amount']),
      currency: csStr(j['currency']) ?? '',
      provider: csStr(j['provider']),
      method: csStr(j['method']),
      plan: csStr(j['plan']),
      createdAt: csTime(j['created_at']),
      paidAt: csTime(j['paid_at']),
      refundedAt: csTime(j['refunded_at']),
    );
  }
}

class CsRosterRow {
  const CsRosterRow({required this.student, required this.access, this.lastPayment});
  final CsStudent student;
  final CsAccess access;
  final CsPayment? lastPayment;

  factory CsRosterRow.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsRosterRow(
      student: CsStudent.fromJson(j['student']),
      access: CsAccess.fromJson(j['access']),
      lastPayment: j['last_payment'] is Map ? CsPayment.fromJson(j['last_payment']) : null,
    );
  }
}

class CsRoster {
  const CsRoster({this.courseId = 0, this.courseName = '', this.teacherName = '', this.counts = const {}, this.items = const [], this.total = 0, this.page = 1, this.pageSize = 25});
  final int courseId;
  final String courseName;
  final String teacherName;
  final Map<String, int> counts;
  final List<CsRosterRow> items;
  final int total;
  final int page;
  final int pageSize;

  int get pages => total <= 0 ? 1 : (total + pageSize - 1) ~/ pageSize;
  int countOf(CsStatus s) => counts[csStatusWire(s)] ?? 0;

  factory CsRoster.fromJson(Object? raw) {
    final j = csMap(raw);
    final c = csMap(j['course']);
    return CsRoster(
      courseId: csInt(c['id']),
      courseName: csPick(csStr(c['name_ar']) ?? '', csStr(c['name_en'])),
      teacherName: csStr(csMap(c['teacher'])['name']) ?? '',
      counts: {for (final e in csMap(j['counts']).entries) e.key: csInt(e.value)},
      items: csList(j['items']).map(CsRosterRow.fromJson).toList(),
      total: csInt(j['total']),
      page: csInt(j['page'], 1),
      pageSize: csInt(j['page_size'], 25),
    );
  }
}

// ── student profile ─────────────────────────────────────────────────────────

class CsEvent {
  const CsEvent({required this.id, this.type = '', this.actorType = '', this.actorId, this.actorName, this.courseId, this.paymentId, this.reason, this.before, this.after, this.backfilled = false, this.at});
  final int id;
  final String type;
  final String actorType;
  final int? actorId;
  final String? actorName;
  final int? courseId;
  final int? paymentId;
  final String? reason;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
  final bool backfilled;
  final DateTime? at;

  factory CsEvent.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsEvent(
      id: csInt(j['id']),
      type: csStr(j['type']) ?? '',
      actorType: csStr(j['actor_type']) ?? '',
      actorId: csIntOrNull(j['actor_id']),
      actorName: csStr(j['actor_name']),
      courseId: csIntOrNull(j['course_id']),
      paymentId: csIntOrNull(j['payment_id']),
      reason: csStr(j['reason']),
      before: j['before'] is Map ? csMap(j['before']) : null,
      after: j['after'] is Map ? csMap(j['after']) : null,
      backfilled: j['backfilled'] == true,
      at: csTime(j['occurred_at']) ?? csTime(j['recorded_at']),
    );
  }
}

String csEventLabel(String type) => switch (type) {
      'created' => t('أُنشئ الاشتراك', 'Enrollment created'),
      'payment_succeeded' => t('نجح الدفع', 'Payment succeeded'),
      'payment_failed' => t('فشل الدفع', 'Payment failed'),
      'activated' => t('تم التفعيل', 'Activated'),
      'renewed' => t('جُدّد', 'Renewed'),
      'expired' => t('انتهى', 'Expired'),
      'cancelled' => t('أُلغي', 'Cancelled'),
      'refunded' => t('أُعيد المبلغ', 'Refunded'),
      'admin_extended' => t('مدّده مشرف', 'Extended by an admin'),
      'admin_reactivated' => t('أعاد مشرف تفعيله', 'Reactivated by an admin'),
      'admin_granted' => t('منحه مشرف وصولاً', 'Access granted by an admin'),
      'plan_backfilled' => t('استُنتجت الباقة', 'Plan inferred'),
      'access_denied' => t('رُفض الوصول', 'Access denied'),
      _ => type,
    };

String csActorLabel(CsEvent e) => switch (e.actorType) {
      'admin' => (e.actorName ?? '').trim().isNotEmpty
          ? e.actorName!.trim()
          : e.actorId == null ? t('مشرف', 'Admin') : t('مشرف #${e.actorId}', 'Admin #${e.actorId}'),
      'user' => t('الطالب', 'The student'),
      'webhook' => t('بوابة الدفع', 'Payment gateway'),
      _ => t('النظام', 'System'),
    };

/// "active -> cancelled · until 14 Nov 2026" from an event's before / after snapshots; null when there is nothing.
String? csChangeText(CsEvent e) {
  String side(Map<String, dynamic>? m) {
    if (m == null) return '';
    final parts = <String>[];
    final st = csStr(m['status']);
    if (st != null) parts.add(st);
    final plan = csStr(m['plan']);
    if (plan != null) parts.add(csPlanLabel(plan));
    final end = csTime(m['expires_at'] ?? m['ends_at']);
    if (end != null) parts.add(_d(end));
    return parts.join(' · ');
  }

  final b = side(e.before), a = side(e.after);
  if (b.isEmpty && a.isEmpty) return null;
  return '${b.isEmpty ? '-' : b}  ->  ${a.isEmpty ? '-' : a}';
}

class CsCourseAccess {
  const CsCourseAccess({required this.courseId, this.nameAr = '', this.nameEn = '', this.teacherName = '', required this.access});
  final int courseId;
  final String nameAr;
  final String nameEn;
  final String teacherName;
  final CsAccess access;
  String get name => csPick(nameAr, nameEn);

  factory CsCourseAccess.fromJson(Object? raw) {
    final j = csMap(raw);
    final c = csMap(j['course']);
    return CsCourseAccess(
      courseId: csInt(c['id']),
      nameAr: csStr(c['name_ar']) ?? '',
      nameEn: csStr(c['name_en']) ?? '',
      teacherName: csStr(c['teacher_name']) ?? '',
      access: CsAccess.fromJson(j['access']),
    );
  }
}

class CsMoney {
  const CsMoney(this.currency, this.amount);
  final String currency;
  final double amount;
}

String csMoneyText(double amount, String currency) {
  final whole = amount == amount.roundToDouble();
  return '${whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)} $currency'.trim();
}

class CsPlatformSub {
  const CsPlatformSub({this.plan, this.status = '', this.startsAt, this.endsAt});
  final String? plan;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;

  factory CsPlatformSub.fromJson(Object? raw) {
    final j = csMap(raw);
    return CsPlatformSub(
      plan: csStr(j['plan_code']) ?? csStr(j['plan']),
      status: csStr(j['status']) ?? '',
      startsAt: csTime(j['starts_at']),
      endsAt: csTime(j['ends_at']),
    );
  }
}

class CsProfile {
  const CsProfile({
    required this.student,
    this.role = '',
    this.isActive = true,
    this.joinedAt,
    this.academicId,
    this.nationalId,
    this.studentCodes = const [],
    this.totalSpent = const [],
    this.courses = const [],
    this.platformSubs = const [],
    this.payments = const [],
    this.events = const [],
  });

  final CsStudent student;
  final String role;
  final bool isActive;
  final DateTime? joinedAt;
  final String? academicId;
  final String? nationalId;
  final List<String> studentCodes;
  final List<CsMoney> totalSpent;
  final List<CsCourseAccess> courses;
  final List<CsPlatformSub> platformSubs;
  final List<CsPayment> payments;
  final List<CsEvent> events;

  factory CsProfile.fromJson(Object? raw) {
    final j = csMap(raw);
    final s = csMap(j['student']);
    final ids = csMap(s['identifiers']);
    return CsProfile(
      student: CsStudent.fromJson(s),
      role: csStr(s['role']) ?? '',
      isActive: s['is_active'] != false,
      joinedAt: csTime(s['joined_at']),
      academicId: csStr(ids['academic_id']),
      nationalId: csStr(ids['national_id']),
      studentCodes: csList(ids['student_codes']).map((e) => '$e').toList(),
      totalSpent: csList(j['total_spent']).map((e) => CsMoney(csStr(csMap(e)['currency']) ?? '', csNum(csMap(e)['amount']))).toList(),
      courses: csList(j['courses']).map(CsCourseAccess.fromJson).toList(),
      platformSubs: csList(j['platform_subscriptions']).map(CsPlatformSub.fromJson).toList(),
      payments: csList(j['payments']).map(CsPayment.fromJson).toList(),
      events: csList(j['events']).map(CsEvent.fromJson).toList(),
    );
  }

  String courseName(int? id) {
    if (id == null) return '';
    for (final c in courses) {
      if (c.courseId == id) return c.name;
    }
    return '#$id';
  }
}

/// One line of the visual timeline: an event or a payment.
class CsTimelineItem {
  const CsTimelineItem({required this.at, this.event, this.payment});
  final DateTime? at;
  final CsEvent? event;
  final CsPayment? payment;
}

/// Events and payments merged, newest first. A payment that an event already describes (same payment id) is dropped
/// so one purchase does not show twice.
List<CsTimelineItem> csTimeline(CsProfile p) {
  final covered = <int>{for (final e in p.events) if (e.paymentId != null) e.paymentId!};
  final items = <CsTimelineItem>[
    for (final e in p.events) CsTimelineItem(at: e.at, event: e),
    for (final pay in p.payments) if (!covered.contains(pay.id)) CsTimelineItem(at: pay.paidAt ?? pay.createdAt, payment: pay),
  ];
  items.sort((a, b) {
    final x = a.at, y = b.at;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return items;
}

// ── action errors ───────────────────────────────────────────────────────────

/// Server codes of the console as bilingual text; [fallback] (the server's own message) otherwise.
String csErrorText(String? code, String fallback) => switch (code) {
      'reason_required' => t('اكتب سبباً من 5 إلى 500 حرف', 'Write a reason of 5 to 500 characters'),
      'no_enrollment' => t('لا يوجد اشتراك لهذا الطالب في الدورة', 'The student has no enrollment in this course'),
      'no_expiry' => t('اشتراكه بلا تاريخ انتهاء فلا يمكن تمديده', 'The enrollment has no end date, so it cannot be extended'),
      'already_has_access' => t('لديه وصول بالفعل', 'The student already has access'),
      'no_access' => t('لا يملك وصولاً لإلغائه', 'The student has no access to cancel'),
      'not_found' => t('غير موجود', 'Not found'),
      'super_admin_required' || 'forbidden' => t('هذه الصفحة للمشرف العام فقط', 'This page is for the super admin only'),
      _ => fallback,
    };
