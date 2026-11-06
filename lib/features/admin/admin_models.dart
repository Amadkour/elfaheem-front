// lib/features/admin/admin_models.dart — typed views of the /api/v1/admin/* JSON.
library;

import 'package:flutter_education_app/config/app_config.dart';

import 'admin_common.dart';

class SubInfo {
  SubInfo(this.j);
  final Map<String, dynamic> j;

  int get id => asInt(j['id']);
  String get planCode => asStr(j['plan_code']);
  String get status => asStr(j['status']); // pending|active|rejected|expired|cancelled
  String? get startsAt => asStrOrNull(j['starts_at']);
  String? get endsAt => asStrOrNull(j['ends_at']);
  double get amount => asDouble(j['amount']);
  String get currency => asStr(j['currency']);
  String? get paymentMethod => asStrOrNull(j['payment_method']);
  String? get rejectionReason => asStrOrNull(j['rejection_reason']);
  bool get grantedByAdmin => asBool(j['granted_by_admin']);
  String? get createdAt => asStrOrNull(j['created_at']);
  // admin list only
  int get studentId => asInt(j['student_id']);
  String get studentName => asStr(j['student_name']);
  String get studentGmail => asStr(j['student_gmail']);
  String? get senderName => asStrOrNull(j['sender_name']);
  String? get senderPhone => asStrOrNull(j['sender_phone']);
  String? get transferReference => asStrOrNull(j['transfer_reference']);
  String? get proofImageUrl => asStrOrNull(j['proof_image_url']);
}

class EnrolledCourse {
  EnrolledCourse(this.id, this.name, this.status);
  final int id;
  final String name;
  final String status;
}

class AdminUser {
  AdminUser(this.j)
      : enrolledCourses = asMapList(j['enrolled_courses'])
      .map((e) => EnrolledCourse(
      asInt(e['id']), asStr(e['name']), asStr(e['status'])))
      .toList(),
        subscription =
        j['subscription'] is Map ? SubInfo(asMap(j['subscription'])) : null;

  final Map<String, dynamic> j;
  final List<EnrolledCourse> enrolledCourses;
  final SubInfo? subscription;

  int get id => asInt(j['id']);
  String get name => asStr(j['name']);
  String get gmail => asStr(j['gmail']);
  String get phone => asStr(j['phone']);
  String get role => asStr(j['role']);
  String get country => asStr(j['country']);
  String? get dob => asStrOrNull(j['dob']);
  String? get imageUrl => asStrOrNull(j['image_url']);
  bool get isActive => asBool(j['is_active']);
  bool get isVerified => asBool(j['is_verified']);
  bool get pendingDeletion => asBool(j['pending_deletion']);
  String? get createdAt => asStrOrNull(j['created_at']);
  String? get lastLogin => asStrOrNull(j['last_login']);
  int get loginTimes => asInt(j['login_times']);
  int get coursesCount => asInt(j['courses_count']);
  double get netEarnings => asDouble(j['net_earnings']);

  bool get hasActiveSubscription => subscription?.status == 'active';
}

class AdminDevice {
  AdminDevice(this.j);
  final Map<String, dynamic> j;
  int get id => asInt(j['id']);
  String get deviceName => asStr(j['device_name'], '—');
  String get deviceId => asStr(j['device_id']);
  String? get boundAt => asStrOrNull(j['bound_at']);
  String? get lastSeenAt => asStrOrNull(j['last_seen_at']);
}

class UserDetail {
  UserDetail(this.j)
      : devices = asMapList(j['devices']).map(AdminDevice.new).toList(),
        subscriptions =
        asMapList(j['subscriptions']).map((e) => SubInfo(e)).toList();
  final Map<String, dynamic> j;
  final List<AdminDevice> devices;
  final List<SubInfo> subscriptions;

  AdminUser get user => AdminUser(j);
  String get bio => asStr(j['bio']);
  String? get lastDeviceSwitchAt => asStrOrNull(j['last_device_switch_at']);
  List<Map<String, dynamic>> get enrollments => asMapList(j['enrollments']);
  List<Map<String, dynamic>> get payments => asMapList(j['payments']);
}

class PaymentSettings {
  PaymentSettings(this.j);
  final Map<String, dynamic> j;
  String? get provider => asStrOrNull(j['payment_provider']);
  List<String>? get allowedMethods => j['allowed_methods'] is List
      ? (j['allowed_methods'] as List).map((e) => '$e').toList()
      : null;
  double? get feePercent =>
      j['platform_fee_percent'] == null ? null : asDouble(j['platform_fee_percent']);
  double get effectiveFeePercent => asDouble(j['effective_platform_fee_percent']);
}

class AdminCourse {
  AdminCourse(this.j) : paymentSettings = PaymentSettings(asMap(j['payment_settings']));
  final Map<String, dynamic> j;
  final PaymentSettings paymentSettings;

  int get id => asInt(j['id']);
  String get name => asStr(j['name']);
  String get description => asStr(j['description']);
  /// YEARLY price (the edit form's source). [listPrice]/[finalPrice] follow the default plan.
  double get fees => asDouble(j['fees']);

  /// Plan students see first: 0 yearly · 1 six months · 2 monthly.
  int get defaultPricePlanIndex => asInt(j['default_price_plan_index']);
  String get currency => asStr(j['currency'], 'EGP');
  String get type => asStr(j['type']);
  String get status => asStr(j['status']); // in_progress|completed
  bool get isPublished => asBool(j['is_published']);
  int? get maxStudents => j['max_students'] == null ? null : asInt(j['max_students']);
  String? get imageUrl => asStrOrNull(j['image_url']);
  int? get categoryId => j['category_id'] == null ? null : asInt(j['category_id']);
  int get teacherId => asInt(j['teacher_id']);
  String get teacherName => asStr(j['teacher_name']);
  int get studentsCount => asInt(j['students_count']);
  int get paidCount => asInt(j['paid_count']);
  double get income => asDouble(j['income']);
  int get pendingPayments => asInt(j['pending_payments']);
  List<Map<String, dynamic>> get recentPayments => asMapList(j['recent_payments']);

  // D-290: what the courses table shows
  String? get createdAt => asStrOrNull(j['created_at']);
  bool get isPrivate => asBool(j['is_private']);

  /// In the trash (D-260): admins still see it.
  bool get archived => asBool(j['archived']);
  double get completionRate => asDouble(j['completion_rate']);
  double get avgProgress => asDouble(j['avg_progress']);
  int get withdrawnCount => asInt(j['withdrawn_count']);

  /// Null: nobody rated it yet.
  double? get ratingAvg => j['rating_avg'] == null ? null : asDouble(j['rating_avg']);
  int get ratingCount => asInt(j['rating_count']);

  /// What students ACTUALLY paid for the course (after discounts) — `income` above.
  /// `collected` also includes platform fee / VAT / gateway fee.
  double get collected => asDouble(j['collected']);
  double get listPrice => asDouble(j['list_price'], fees);
  double get finalPrice => asDouble(j['final_price'], fees);
  bool get discountActive => asBool(j['discount_active']);
  double get discountPercentage => asDouble(j['discount_percentage']);

  // ── price plans: `fees` is the YEARLY price; the other two are optional ──
  double? get priceMonthly => j['price_monthly'] == null ? null : asDouble(j['price_monthly']);
  double? get priceSixMonths => j['price_six_months'] == null ? null : asDouble(j['price_six_months']);

  /// [{plan, duration_days, price, final_price, ...}] — only plans with a price.
  List<Map<String, dynamic>> get priceOptions => asMapList(j['price_options']);
}

class AdminCategory {
  AdminCategory(this.j);
  final Map<String, dynamic> j;
  int get id => asInt(j['id']);
  String get nameAr => asStr(j['name_ar']);
  String get nameEn => asStr(j['name_en']);
  String get display => AppConfig.lang == 'ar'
      ? (nameAr.isNotEmpty ? nameAr : nameEn)
      : (nameEn.isNotEmpty ? nameEn : nameAr);
  String get description => asStr(j['description']);
  int? get parentId => j['parent_id'] == null ? null : asInt(j['parent_id']);
  int get coursesCount => asInt(j['courses_count']);
  int get teachersCount => asInt(j['teachers_count']);
  int get studentsCount => asInt(j['students_count']);
  String? get imageUrl => asStrOrNull(j['image_url']);
}

class Plan {
  Plan(this.j);
  final Map<String, dynamic> j;
  int get id => asInt(j['id']);
  String get code => asStr(j['code']);
  String get nameAr => asStr(j['name_ar']);
  String get nameEn => asStr(j['name_en']);
  String get name => t(nameAr, nameEn);
  double get price => asDouble(j['price']);
  String get currency => asStr(j['currency'], 'EGP');
  int get durationDays => asInt(j['duration_days'], 30);
  bool get isActive => asBool(j['is_active'], true);
}

class ThemePresetModel {
  ThemePresetModel(this.j);
  final Map<String, dynamic> j;
  int get id => asInt(j['id']);
  String get key => asStr(j['key']);
  String get nameAr => asStr(j['name_ar']);
  String get nameEn => asStr(j['name_en']);
  String get name => t(nameAr, nameEn);
  bool get isBuiltin => asBool(j['is_builtin']);
  Map<String, String> get colors =>
      asMap(j['colors']).map((k, v) => MapEntry(k, '$v'));
}

class FeatureItem {
  FeatureItem(this.j);
  final Map<String, dynamic> j;

  // 1) key
  String get key => asStr(j['key']);

  // 2, 3) labels — the server sends title_ar / title_en (label_* kept as fallback)
  String get labelAr => asStr(j['title_ar'], asStr(j['label_ar'], key));
  String get labelEn => asStr(j['title_en'], asStr(j['label_en'], key));
  String get label => t(labelAr, labelEn);

  // 4) may admins see / toggle this feature?
  bool get allowToAdmin => asBool(j['allow_to_admin']);

  // 5, 6, 7) hidden per platform.
  // Explicit hidden_ios / hidden_android / hidden_web win; otherwise they are
  // derived from the `platforms` list the server sends today.
  bool get hiddenIos => _hiddenOn('ios');
  bool get hiddenAndroid => _hiddenOn('android');
  bool get hiddenWeb => _hiddenOn('web');

  bool _hiddenOn(String platform) {
    final explicit = j['hidden_$platform'];
    if (explicit != null) return asBool(explicit);
    return _platforms.contains(platform);
  }

  List<String> get _platforms => j['platforms'] is List
      ? (j['platforms'] as List).map((e) => '$e'.toLowerCase()).toList()
      : <String>[];

  /// Platforms where this feature is hidden (used by the page widget).
  List<String> get hiddenOn => [
    if (hiddenAndroid) 'android',
    if (hiddenIos) 'ios',
    if (hiddenWeb) 'web',
  ];

  bool get isHiddenAnywhere => hiddenOn.isNotEmpty;

  /// Is this feature hidden on [platform] ('ios' | 'android' | 'web')?
  bool isHiddenOn(String platform) {
    switch (platform.toLowerCase()) {
      case 'ios':
        return hiddenIos;
      case 'android':
        return hiddenAndroid;
      case 'web':
        return hiddenWeb;
    }
    return false;
  }
}

/// "1200 EGP · 300 SAR" — totals are per currency, never added together.
String moneyByCurrency(Map<String, double> m) =>
    m.isEmpty ? '0' : m.entries.map((e) => money(e.value, e.key)).join(' · ');

class Overview {
  Overview(this.j);
  final Map<String, dynamic> j;
  int i(String k) => asInt(j[k]);
  double d(String k) => asDouble(j[k]);

  /// {"EGP": 1200.0, "SAR": 300.0} for keys like `collected_by_currency`.
  Map<String, double> byCurrency(String k) =>
      asMap(j[k]).map((c, v) => MapEntry(c, asDouble(v)));
  bool get subscriptionRequired => asBool(j['subscription_required']);
}

/// Pagination envelope used by every list endpoint.
class PageData {
  PageData(Map<String, dynamic> j)
      : items = asMapList(j['items']),
        total = asInt(j['total']),
        page = asInt(j['page'], 1),
        pages = asInt(j['pages'], 1),
        extra = j;
  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final int pages;
  final Map<String, dynamic> extra;
}

/// One withdrawal request (teacher list + admin list share the same JSON).
class Withdrawal {
  Withdrawal(this.j);
  final Map<String, dynamic> j;

  int get id => asInt(j['id']);
  int get teacherId => asInt(j['teacher_id']);
  String get teacherName => asStr(j['teacher_name']);
  String get teacherGmail => asStr(j['teacher_gmail']);
  double get amount => asDouble(j['amount']);
  String get status => asStr(j['status']); // pending|approved|paid|rejected
  String? get note => asStrOrNull(j['note']);
  String? get adminNote => asStrOrNull(j['admin_note']);
  String? get bankReference => asStrOrNull(j['bank_reference']);
  String? get rejectedReason => asStrOrNull(j['rejected_reason']);
  String? get receiptUrl => asStrOrNull(j['receipt_url']);
  String? get receiptName => asStrOrNull(j['receipt_name']);
  String? get requestedAt => asStrOrNull(j['requested_at']);
  String? get processedAt => asStrOrNull(j['processed_at']);
  Map<String, dynamic> get destination => asMap(j['bank_snapshot']);

  String get method => asStr(j['payout_method'], 'bank_account');
  String? get provider => asStrOrNull(j['payout_provider']);
  bool get automatic => asBool(j['payout_automatic']);
  String get state => asStr(j['payout_state'], 'none'); // none|processing|paid|failed|unknown
  String? get providerStatus => asStrOrNull(j['payout_status']);
  String? get providerReference => asStrOrNull(j['payout_reference']);
  String? get error => asStrOrNull(j['payout_error']);

  /// The currency the money is paid out in (the server's `payout_currency`); null on an older server or when no
  /// payout was prepared yet. Every amount shown for a withdrawal carries it.
  String? get currency {
    final c = asStrOrNull(j['payout_currency']);
    return c == null || c.trim().isEmpty ? null : c.trim().toUpperCase();
  }
}

String payoutMethodLabel(String m) {
  switch (m) {
    case 'bank_account':
      return 'admin_bank_account'.tr;
    case 'instapay':
      return 'transfer_instapay_title'.tr;
    case 'moyasar':
      return 'admin_moyasar_auto'.tr;
    case 'paymob':
      return 'admin_paymob_auto'.tr;
  }
  return m;
}

/// One-line summary of a payout destination, safe to show in lists.
String payoutDestinationSummary(Map<String, dynamic> d) {
  String tail(String? v) => (v == null || v.length < 4) ? (v ?? '') : '••••${v.substring(v.length - 4)}';
  final name = asStr(d['account_name']);
  switch (asStr(d['method'])) {
    case 'instapay':
      return '$name • ${asStr(d['instapay_id'])}';
    case 'moyasar':
      return '$name • ${tail(asStrOrNull(d['iban']))}';
    case 'paymob':
      return asStr(d['kind']) == 'wallet'
          ? '$name • ${asStr(d['issuer'])} ${asStr(d['msisdn'])}'
          : '$name • ${asStr(d['bank_code'])} ${tail(asStrOrNull(d['bank_card_number']))}';
    default:
      return '${asStr(d['bank_name'])} • $name • ${tail(asStrOrNull(d['iban']))}';
  }
}