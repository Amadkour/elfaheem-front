// lib/features/payments/points/points_api.dart — the points wallet and the student live-meeting plan: pure models,
// code → text, price maths and the API calls. Contract: docs/backend/live-rooms-spec.md §8 – §9.
//
//   GET  /api/v1/me/points                      wallet: balance, price per point, currency, minimum, methods,
//                                               history (ledger), my top-ups
//   POST /api/v1/me/points/topups               multipart: points · method · receipt
//   GET  /api/v1/me/live-plan · POST …/subscribe   the live-meeting plan (402 points_insufficient)
//   PUT  /api/v1/me/live-plan {auto_renew}          Part 3 §15: renew automatically from the points
//   POST /api/v1/me/points/checkout {points}        Part 3 §13: buy points by card → the provider's payment page
//   GET  /api/v1/me/points/topups/{id}              the top-up, polled after the payment page closes (pollTopup)
//   Admin:  /api/v1/admin/points/users · /grant · /users/{uid}/history · /topups[?status] · /topups/{id}/approve |
//           reject | receipt · /settings
//
// Everything above the API section takes plain values and is unit-tested in test/org/points_test.dart. Server times
// are naive UTC (parsed as UTC, shown through AppTime). Inline strings use t(ar, en) (no translation.json edits).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/payments/payer_methods.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/core/app_digits.dart';

/// Kill-switch keys (ParentComponent / AppConfig.disableList).
const String kPointsFeatureKey = 'profile.points';
const String kAdminPointsFeatureKey = 'admin.points';
const String kQuickMeetingFeatureKey = 'live.quick_meeting';

const Duration pointsTimeout = Duration(seconds: 25);

/// Receipts above this size are refused by the server (§9); the app says so before uploading.
const int kReceiptMaxBytes = 10 * 1024 * 1024;

// ─────────────────────────────────────────────────────────────────────────────
// Readers
// ─────────────────────────────────────────────────────────────────────────────

DateTime? pointsParseUtc(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null') return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? d);

int? _intOrNull(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double _double(dynamic v, [double d = 0]) => v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? d);

String? _strOrNull(dynamic v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _maps(dynamic v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

// ─────────────────────────────────────────────────────────────────────────────
// Roles
// ─────────────────────────────────────────────────────────────────────────────

/// The server's `subscription_service.STAFF_VALUES`: everyone else is a "student" for meetings (§8).
const Set<String> kStaffRoles = {'teacher', 'admin', 'super-admin', 'developer', 'parent', 'org-admin', 'org-staff'};

/// A signed-in user whose role is not staff: online + private meetings only, free time unless on the plan.
bool isStudentForMeetings(String? role) => role != null && role.isNotEmpty && !kStaffRoles.contains(role);

// ─────────────────────────────────────────────────────────────────────────────
// Price maths
// ─────────────────────────────────────────────────────────────────────────────

/// Money for [points] at [pricePerPoint], rounded to cents.
double pointsMoney(int points, double pricePerPoint) => (points * pricePerPoint * 100).roundToDouble() / 100;

/// "30 SAR" / "12.50 SAR".
String moneyText(double amount, String currency) {
  final s = amount == amount.roundToDouble() ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  return appDigits(currency.isEmpty ? s : '$s $currency'); // platform_settings.digits
}

/// The points typed in the "Buy points" field: null when empty or not a whole number.
int? parsePoints(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'[\s,]'), '');
  if (s.isEmpty) return null;
  final western = s.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0660}');
  return int.tryParse(western);
}

/// Why the "Buy points" amount cannot be sent (null = fine).
String? topupAmountError(int? points, int min) {
  if (points == null || points <= 0) return t('اكتب عدد النقاط', 'Enter the number of points');
  if (points < min) return t('أقل عدد للشحن $min نقطة', 'The minimum top-up is $min points');
  return null;
}

/// How many points are missing to pay [price] from [balance] (0 = enough).
int pointsShortfall(int balance, int price) => balance >= price ? 0 : price - balance;

// ─────────────────────────────────────────────────────────────────────────────
// Labels
// ─────────────────────────────────────────────────────────────────────────────

String pointsMethodText(String method) => switch (method) {
      'bank_transfer' => t('تحويل بنكي', 'Bank transfer'),
      'instapay' => t('إنستاباي', 'InstaPay'),
      'wallet' => t('محفظة إلكترونية', 'Mobile wallet'),
      'cash' => t('نقداً', 'Cash'),
      'card' => t('بطاقة بنكية', 'Card'),
      _ => method,
    };

/// A payment provider's name as shown (`moyasar` → Moyasar).
String pointsProviderText(String? provider) => switch ((provider ?? '').toLowerCase()) {
      'moyasar' => 'Moyasar',
      'paymob' => 'Paymob',
      '' => '',
      final p => p[0].toUpperCase() + p.substring(1),
    };

/// One ledger row's kind as text; a spend on the live plan says so.
String ledgerKindText(String kind, {String? refType}) => switch (kind) {
      'grant' => t('منحة من الإدارة', 'Granted by the admin'),
      'deduct' => t('خصم من الإدارة', 'Deducted by the admin'),
      'topup' => t('شحن رصيد', 'Top-up'),
      'spend' => refType == 'live_meeting' || refType == 'service_subscription'
          ? t('اشتراك الاجتماعات المباشرة', 'Live-meeting plan')
          : t('صرف', 'Spent'),
      'refund' => t('استرداد', 'Refund'),
      _ => kind,
    };

enum TopupStatus { pending, approved, rejected, unknown }

TopupStatus topupStatusFrom(dynamic v) => switch ('${v ?? ''}') {
      'pending' => TopupStatus.pending,
      'approved' => TopupStatus.approved,
      'rejected' => TopupStatus.rejected,
      _ => TopupStatus.unknown,
    };

String topupStatusText(TopupStatus s) => switch (s) {
      TopupStatus.pending => t('قيد المراجعة', 'Under review'),
      TopupStatus.approved => t('مقبول', 'Approved'),
      TopupStatus.rejected => t('مرفوض', 'Rejected'),
      TopupStatus.unknown => '—',
    };

/// Server codes of §7 – §9 as bilingual text; null for a code this file does not know.
String? pointsCodeText(String? code) => switch (code) {
      'points_insufficient' => t('رصيد النقاط لا يكفي', 'Not enough points'),
      'plan_not_needed' => t('حسابك لا يحتاج هذا الاشتراك: اجتماعاتك بلا حد', 'Your account does not need the plan: your meetings are unlimited'),
      'live_plan_required' => t('انتهى الوقت المجاني لهذا الاجتماع. اشترك في باقة الاجتماعات المباشرة للمتابعة.',
          'The free time of this meeting is over. Subscribe to the live-meeting plan to continue.'),
      'meeting_time_limit' => t('انتهى الوقت المجاني لهذا الاجتماع، ولا يمكن الدخول حتى يشترك منظّمه في باقة الاجتماعات.',
          "This meeting's free time is over. You can join again once its organizer subscribes to the live-meeting plan."),
      'student_meeting_online_private' => t('يمكن للطلاب إنشاء اجتماعات عبر الإنترنت خاصة فقط؛ شارك الرابط لدعوة الآخرين',
          'Students can create online private meetings only; share the link to invite people'),
      'topup_decided' => t('تم البت في طلب الشحن هذا من قبل', 'This top-up was already decided'),
      'points_negative_balance' => t('لا يمكن أن يصبح الرصيد أقل من صفر', 'The balance cannot go below zero'),
      'topup_below_min' || 'points_below_min' => t('العدد أقل من الحد الأدنى للشحن', 'Below the minimum top-up'),
      'bad_method' || 'invalid_method' || 'method_invalid' => t('اختر طريقة دفع صحيحة', 'Choose a valid payment method'),
      'receipt_required' => t('أرفق إيصال الدفع', 'Attach the payment receipt'),
      'receipt_missing' => t('لا يوجد إيصال لهذا الطلب', 'This top-up has no receipt'),
      'receipt_upload_failed' => t('تعذّر رفع الإيصال، حاول مرة أخرى', 'The receipt could not be uploaded, try again'),
      'bad_setting' => t('إحدى القيم خارج المدى المسموح', 'One of the values is out of the allowed range'),
      'admin_required' => t('هذه الصفحة للمديرين فقط', 'This page is for admins only'),
      'receipt_too_large' || 'file_too_large' => t('الإيصال أكبر من 10 ميجابايت', 'The receipt is larger than 10 MB'),
      'receipt_invalid' || 'invalid_file_type' => t('الإيصال يجب أن يكون صورة أو PDF', 'The receipt must be an image or a PDF'),
      'points_zero' => t('اكتب عدداً غير الصفر', 'Enter a number other than zero'),
      'user_not_found' => t('المستخدم غير موجود', 'User not found'),
      'topup_not_found' => t('طلب الشحن غير موجود', 'Top-up not found'),
      'card_disabled' || 'points_card_disabled' || 'card_not_available' || 'card_unavailable' =>
        t('الدفع بالبطاقة غير متاح الآن', 'Paying by card is not available right now'),
      'provider_not_configured' || 'no_payment_provider' || 'payment_provider_unavailable' || 'bad_provider' =>
        t('بوابة الدفع غير متاحة الآن', 'The payment gateway is not available right now'),
      'gateway_error' => t('تعذّر فتح صفحة الدفع الآن، حاول بعد قليل', 'The payment page could not be opened now, try again shortly'),
      'topup_by_card' => t('طلبات البطاقة يقرّرها مزوّد الدفع', 'Card top-ups are decided by the payment provider'),
      'checkout_failed' || 'payment_session_failed' => t('تعذّر فتح صفحة الدفع، حاول مرة أخرى', 'The payment page could not be opened, try again'),
      'card_topup_readonly' || 'topup_card' =>
        t('طلبات البطاقة يقرّرها مزوّد الدفع', 'Card top-ups are decided by the payment provider'),
      _ => null,
    };

/// `reason` of a 402 `live_plan_required` (spec §14): `daily_limit` = the owner's free minutes of today are used up.
const String kDailyLimitReason = 'daily_limit';

/// The plan sheet's header for a 402 reason (null = the usual title).
String? livePlanReasonText(String? reason) =>
    reason == kDailyLimitReason ? t('انتهى وقتك المجاني لليوم', "Today's free time is used up") : null;

/// A notification / push type of the wallet and the plan → the AppNavigator module (null = not ours).
/// `live_plan_expiring` · `live_plan_renewed` · `live_plan_renew_failed` (§15) open the plan like `live_plan`.
String? pointsModuleFor(String? type) => switch ((type ?? '').trim()) {
      'points' || 'points_topup' => 'points',
      'live_plan' || 'live_plan_required' || 'live_plan_expiring' || 'live_plan_renewed' || 'live_plan_renew_failed' =>
        'live_plan',
      _ => null,
    };

/// The server code of an error (null for a plain error).
String? pointsErrorCode(Object e) {
  if (e is TimeoutException) return null;
  final x = ApiException.from(e);
  return x.code ?? ApiException.codedDetail(x.body).$1;
}

/// The `detail` extras of a coded error ({code, message, balance, price_points, …}); empty otherwise.
Map<String, dynamic> pointsErrorDetail(Object e) {
  if (e is TimeoutException) return const {};
  final d = ApiException.asMap(ApiException.from(e).body)?['detail'];
  return d is Map ? Map<String, dynamic>.from(d) : const {};
}

/// User-facing text of any points / plan / quick-meeting error.
String pointsErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  return pointsCodeText(pointsErrorCode(e)) ?? ApiException.from(e).message;
}

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// GET /me/live-plan — {active, ends_at|null, price_points, days, free_minutes, balance, needed} + Part 3:
/// `daily_free_minutes`, `daily_free_left` (§14), `auto_renew`, `days_left` (§15).
class LivePlan {
  const LivePlan({
    this.active = false,
    this.endsAt,
    this.pricePoints = 30,
    this.days = 30,
    this.freeMinutes = 15,
    this.balance = 0,
    this.needed = true,
    this.dailyFreeMinutes = 0,
    this.dailyFreeLeft,
    this.autoRenew = false,
    this.serverDaysLeft,
  });

  final bool active;
  final DateTime? endsAt;
  final int pricePoints;
  final int days;
  final int freeMinutes;
  final int balance;

  /// False for staff: their meetings are unlimited, the plan is never shown to them.
  final bool needed;

  /// The daily cap of free live minutes over all of the person's meetings (`daily_free_minutes`; 0 = no cap).
  final int dailyFreeMinutes;

  /// Free minutes left today (`daily_free_left`); null when the server does not say (an older server / no cap).
  final int? dailyFreeLeft;

  /// Renew the plan from the points when it ends (`auto_renew`, `PUT /me/live-plan {auto_renew}`).
  final bool autoRenew;

  /// The server's `days_left` (null on an older server: [daysLeft] computes it).
  final int? serverDaysLeft;

  factory LivePlan.fromJson(dynamic json) {
    final j = _map(json);
    return LivePlan(
      active: j['active'] == true,
      endsAt: pointsParseUtc(j['ends_at']),
      pricePoints: _int(j['price_points'], 30),
      days: _int(j['days'], 30),
      freeMinutes: _int(j['free_minutes'], 15),
      balance: _int(j['balance']),
      needed: j['needed'] != false,
      dailyFreeMinutes: _int(j['daily_free_minutes']),
      dailyFreeLeft: _intOrNull(j['daily_free_left']),
      autoRenew: j['auto_renew'] == true,
      serverDaysLeft: _intOrNull(j['days_left']),
    );
  }

  bool get canAfford => balance >= pricePoints;

  int get shortfall => pointsShortfall(balance, pricePoints);

  /// A daily cap applies (a student without an active plan, the setting above 0).
  bool get hasDailyCap => needed && !active && dailyFreeMinutes > 0;

  /// Free minutes left today under the cap (the whole cap when the server does not say), never negative.
  int get dailyLeft => (dailyFreeLeft ?? dailyFreeMinutes).clamp(0, dailyFreeMinutes < 0 ? 0 : dailyFreeMinutes);

  /// Today's free minutes are all used: a new meeting cannot go live until tomorrow (or the plan).
  bool get dailyUsedUp => hasDailyCap && dailyLeft <= 0;

  /// Whole days left of an active plan (0 when it ends today or is inactive / unlimited). The server's `days_left`
  /// wins when it sent one.
  int daysLeft(DateTime nowUtc) {
    final e = endsAt;
    if (!active || e == null) return 0;
    final s = serverDaysLeft;
    if (s != null) return s < 0 ? 0 : s;
    if (!e.isAfter(nowUtc)) return 0;
    return e.difference(nowUtc).inHours ~/ 24;
  }

  LivePlan copyWith({int? balance, bool? autoRenew}) => LivePlan(
        active: active,
        endsAt: endsAt,
        pricePoints: pricePoints,
        days: days,
        freeMinutes: freeMinutes,
        balance: balance ?? this.balance,
        needed: needed,
        dailyFreeMinutes: dailyFreeMinutes,
        dailyFreeLeft: dailyFreeLeft,
        autoRenew: autoRenew ?? this.autoRenew,
        serverDaysLeft: serverDaysLeft,
      );
}

/// "3 days left" / "1 day left" / "Ends today".
String planDaysLeftText(int days) => days <= 0
    ? t('ينتهي اليوم', 'Ends today')
    : days == 1
        ? t('متبقٍ يوم واحد', '1 day left')
        : t('متبقٍ $days يوم', '$days days left');

/// "12 of 30 free minutes left today" (the daily cap, §14).
String dailyFreeLeftText(int left, int cap) => left <= 0
    ? t('انتهت دقائقك المجانية لليوم ($cap دقيقة)', 'Your $cap free minutes of today are used up')
    : t('متبقٍ $left من $cap دقيقة مجانية اليوم', '$left of $cap free minutes left today');

/// A meeting's free-time limit (`time_limit` of the join payload and the meeting detail); null = unlimited.
class MeetingTimeLimit {
  const MeetingTimeLimit({this.endsAt, this.freeMinutes = 15, this.dailyMinutes = 0, this.dailyLeft});

  final DateTime? endsAt;
  final int freeMinutes;

  /// The owner's daily cap (`daily_minutes`, §14; 0 = none) and what is left of it today (`daily_left`).
  final int dailyMinutes;
  final int? dailyLeft;

  static MeetingTimeLimit? parse(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return MeetingTimeLimit(
      endsAt: pointsParseUtc(j['ends_at']),
      freeMinutes: _int(j['free_minutes'], 15),
      dailyMinutes: _int(j['daily_minutes']),
      dailyLeft: _intOrNull(j['daily_left']),
    );
  }

  bool get hasDailyCap => dailyMinutes > 0 && dailyLeft != null;

  /// The free window this meeting will get when it goes live: `min(free_minutes, daily_left)` under a cap.
  int get windowMinutes {
    final d = dailyLeft;
    if (!hasDailyCap || d == null) return freeMinutes;
    return d < freeMinutes ? (d < 0 ? 0 : d) : freeMinutes;
  }

  /// Minutes of free time left at [nowUtc] (the full allowance before the room was first joined).
  int minutesLeft(DateTime nowUtc) {
    final e = endsAt;
    if (e == null) return freeMinutes;
    final s = e.difference(nowUtc).inSeconds;
    return s <= 0 ? 0 : (s + 59) ~/ 60;
  }
}

/// One ledger row (newest first in every list).
class PointsLedgerEntry {
  const PointsLedgerEntry({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.kind,
    this.refType,
    this.refId,
    this.note,
    this.byName,
    this.createdAt,
  });

  final int id;
  final int delta;
  final int balanceAfter;
  final String kind;
  final String? refType;
  final int? refId;
  final String? note;
  final String? byName;
  final DateTime? createdAt;

  factory PointsLedgerEntry.fromJson(Map<String, dynamic> j) => PointsLedgerEntry(
        id: _int(j['id']),
        delta: _int(j['delta']),
        balanceAfter: _int(j['balance_after']),
        kind: '${j['kind'] ?? ''}',
        refType: _strOrNull(j['ref_type']),
        refId: _intOrNull(j['ref_id']),
        note: _strOrNull(j['note']),
        byName: _strOrNull(_map(j['by_user'])['name'] ?? j['by_name']),
        createdAt: pointsParseUtc(j['created_at']),
      );

  String get kindText => ledgerKindText(kind, refType: refType);

  /// "+50" / "−30".
  String get deltaText => delta > 0 ? '+$delta' : (delta < 0 ? '−${-delta}' : '0');

  static List<PointsLedgerEntry> listFrom(dynamic v) =>
      [for (final m in _maps(v is Map ? v['items'] : v)) PointsLedgerEntry.fromJson(m)];
}

class PointsUser {
  const PointsUser({required this.id, this.name = '', this.email, this.phone, this.role, this.username});

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;

  /// The @username (D-071), null when the account has none or the server is older.
  final String? username;

  factory PointsUser.fromJson(dynamic json) {
    final j = _map(json);
    return PointsUser(
      id: _int(j['id']),
      name: '${j['name'] ?? ''}',
      email: _strOrNull(j['email']),
      phone: _strOrNull(j['phone']),
      role: _strOrNull(j['role']),
      username: _strOrNull(j['username']),
    );
  }

  /// The second line of a user row: e-mail · phone.
  String get contact => [?email, ?phone].join(' · ');
}

/// A top-up request (mine, or the admin's list where it carries the user).
class PointsTopup {
  const PointsTopup({
    required this.id,
    required this.points,
    required this.amount,
    this.currency = '',
    this.method = '',
    this.status = TopupStatus.pending,
    this.note,
    this.createdAt,
    this.decidedAt,
    this.user,
    this.provider,
    this.paymentId,
    this.hasReceipt = true,
    this.failureReason,
  });

  final int id;
  final int points;
  final double amount;
  final String currency;
  final String method;
  final TopupStatus status;
  final String? note;
  final DateTime? createdAt;
  final DateTime? decidedAt;
  final PointsUser? user;

  /// Card top-ups (§13): the payment provider (`moyasar` | `paymob`) and its payment id.
  final String? provider;
  final String? paymentId;

  /// A transfer's receipt is on the server (`has_receipt`; a card top-up has none).
  final bool hasReceipt;

  /// Why the provider refused a card payment (`failure_reason`), when it said.
  final String? failureReason;

  factory PointsTopup.fromJson(Map<String, dynamic> j) {
    final method = '${j['method'] ?? ''}';
    return PointsTopup(
      id: _int(j['id'] ?? j['topup_id']),
      points: _int(j['points']),
      amount: _double(j['amount']),
      currency: '${j['currency'] ?? ''}',
      method: method,
      status: topupStatusFrom(j['status']),
      note: _strOrNull(j['note']),
      createdAt: pointsParseUtc(j['created_at']),
      decidedAt: pointsParseUtc(j['decided_at']),
      user: j['user'] is Map ? PointsUser.fromJson(j['user']) : null,
      provider: _strOrNull(j['provider']),
      paymentId: _strOrNull(j['payment_id']),
      hasReceipt: j['has_receipt'] is bool ? j['has_receipt'] == true : method != 'card',
      failureReason: _strOrNull(j['failure_reason']),
    );
  }

  bool get isPending => status == TopupStatus.pending;

  /// Paid by card: decided by the provider, never by an admin (§13).
  bool get isCard => method == 'card';

  /// "Card · Moyasar" / "Bank transfer".
  String get methodText => [pointsMethodText(method), if (isCard && provider != null) pointsProviderText(provider)].join(' · ');

  /// The status as the owner reads it: a pending card top-up waits for the payment, not for a review.
  String get statusText => isCard && isPending ? t('بانتظار الدفع', 'Waiting for payment') : topupStatusText(status);

  String get amountText => moneyText(amount, currency);

  static List<PointsTopup> listFrom(dynamic v) =>
      [for (final m in _maps(v is Map ? v['items'] : v)) PointsTopup.fromJson(m)];

  /// Pending first (oldest pending first: it waited longest), then the decided ones newest first.
  static List<PointsTopup> sorted(Iterable<PointsTopup> items) {
    final pending = items.where((x) => x.isPending).toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
    final rest = items.where((x) => !x.isPending).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return [...pending, ...rest];
  }
}

/// GET /me/points.
class PointsWallet {
  const PointsWallet({
    this.balance = 0,
    this.pricePerPoint = 1,
    this.currency = 'SAR',
    this.topupMin = 10,
    this.methods = const ['bank_transfer', 'instapay'],
    this.history = const [],
    this.topups = const [],
  });

  final int balance;
  final double pricePerPoint;
  final String currency;
  final int topupMin;
  final List<String> methods;
  final List<PointsLedgerEntry> history;
  final List<PointsTopup> topups;

  factory PointsWallet.fromJson(dynamic json) {
    final j = _map(json);
    final methods = j['methods'] is List
        ? [
            for (final m in j['methods'] as List)
              if (m is Map) '${m['id'] ?? m['key'] ?? m['method'] ?? ''}' else '$m'
          ].where((m) => m.isNotEmpty).toList()
        : const ['bank_transfer', 'instapay'];
    return PointsWallet(
      balance: _int(j['balance']),
      pricePerPoint: _double(j['price_per_point'], 1),
      currency: '${j['currency'] ?? 'SAR'}',
      topupMin: _int(j['topup_min'], 10),
      methods: methods,
      history: PointsLedgerEntry.listFrom(j['history']),
      topups: PointsTopup.listFrom(j['topups']),
    );
  }

  double priceOf(int points) => pointsMoney(points, pricePerPoint);

  int get pendingTopups => topups.where((x) => x.isPending).length;

  /// The server offers paying by card (`methods` has `card`: the setting is on and a provider is configured).
  bool get hasCard => methods.contains('card');

  /// Only the methods the payer's country may use (GET /payments/methods, payments.md §1: InstaPay only in Egypt,
  /// and so on); null [keys] keeps the list. A card counts when the country list has `card` or `mada`.
  PointsWallet forPayer(Set<String>? keys) {
    if (keys == null) return this;
    return PointsWallet(balance: balance, pricePerPoint: pricePerPoint, currency: currency, topupMin: topupMin,
        methods: [for (final m in methods) if (payerAllows(keys, m)) m], history: history, topups: topups);
  }
}

/// `POST /me/points/checkout` (§13): the card top-up row and what opens the provider's payment page — the same
/// `checkout_url` the course checkout returns (opened in the WebView on mobile, the iframe on web).
class PointsCheckout {
  const PointsCheckout({
    required this.topupId,
    required this.checkoutUrl,
    this.provider,
    this.amount = 0,
    this.currency = '',
    this.points = 0,
    this.alreadyPaid = false,
  });

  final int topupId;
  final String checkoutUrl;
  final String? provider;
  final double amount;
  final String currency;
  final int points;

  /// The server credited the points without a payment page (a repeated call on a paid top-up).
  final bool alreadyPaid;

  factory PointsCheckout.fromJson(dynamic json) {
    final j = _map(json);
    final topup = _map(j['topup']);
    return PointsCheckout(
      topupId: _int(j['topup_id'] ?? topup['id'] ?? j['id']),
      checkoutUrl: '${j['checkout_url'] ?? j['payment_url'] ?? j['url'] ?? j['redirect_url'] ?? ''}'.trim(),
      provider: _strOrNull(j['provider'] ?? topup['provider']),
      amount: _double(j['amount'] ?? topup['amount']),
      currency: '${j['currency'] ?? topup['currency'] ?? ''}',
      points: _int(j['points'] ?? topup['points']),
      alreadyPaid: j['already_paid'] == true || '${j['status'] ?? topup['status'] ?? ''}' == 'approved',
    );
  }

  /// The payment page can be opened.
  bool get canOpen => checkoutUrl.startsWith('https://') || checkoutUrl.startsWith('http://');
}

/// What polling a card top-up ended with.
class TopupPollResult {
  const TopupPollResult({this.topup, this.timedOut = false, this.error});

  /// The latest top-up read (null when no read succeeded).
  final PointsTopup? topup;

  /// Still pending when the time ran out: the screen offers "Check again".
  final bool timedOut;

  /// The last read failed (and nothing was read after it).
  final Object? error;

  bool get approved => topup?.status == TopupStatus.approved;

  bool get rejected => topup?.status == TopupStatus.rejected;
}

/// Polls [fetch] every [every] until the top-up is no longer pending, or [timeout] passes. A failed read is retried
/// (it never ends the wait early); [sleep] is the test seam.
Future<TopupPollResult> pollTopup(
  Future<PointsTopup> Function() fetch, {
  Duration every = const Duration(seconds: 3),
  Duration timeout = const Duration(minutes: 2),
  Future<void> Function(Duration)? sleep,
  bool Function()? cancelled,
}) async {
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  var waited = Duration.zero;
  PointsTopup? last;
  Object? error;
  while (true) {
    if (cancelled?.call() == true) return TopupPollResult(topup: last, timedOut: true, error: error);
    try {
      last = await fetch();
      error = null;
      if (!last.isPending) return TopupPollResult(topup: last);
    } catch (e) {
      error = e;
    }
    if (waited >= timeout) return TopupPollResult(topup: last, timedOut: true, error: error);
    await wait(every);
    waited += every;
  }
}

/// One row of the admin's user search.
class PointsUserRow {
  const PointsUserRow({required this.user, this.balance = 0});

  final PointsUser user;
  final int balance;

  factory PointsUserRow.fromJson(Map<String, dynamic> j) =>
      PointsUserRow(user: PointsUser.fromJson(j['user'] ?? j), balance: _int(j['balance']));

  static (List<PointsUserRow>, int) pageFrom(dynamic v) {
    final j = _map(v);
    final items = [for (final m in _maps(j['items'])) PointsUserRow.fromJson(m)];
    return (items, _int(j['total'], items.length));
  }
}

/// The app settings of §9 + Part 3 (`live_meeting_free_minutes_daily` §14, `points_card_enabled` §13).
class PointsSettings {
  const PointsSettings({
    this.freeMinutes = 15,
    this.pricePoints = 30,
    this.planDays = 30,
    this.pointPrice = 1.0,
    this.currency = 'SAR',
    this.topupMin = 10,
    this.freeMinutesDaily = 30,
    this.cardEnabled = true,
  });

  final int freeMinutes;
  final int pricePoints;
  final int planDays;
  final double pointPrice;
  final String currency;
  final int topupMin;

  /// A student's free live minutes per day over all meetings (0 = no daily cap).
  final int freeMinutesDaily;

  /// Offer "Card" in Buy points (when a payment provider is configured).
  final bool cardEnabled;

  factory PointsSettings.fromJson(dynamic json) {
    final j = _map(json);
    final s = j['settings'] is Map ? _map(j['settings']) : j;
    return PointsSettings(
      freeMinutes: _int(s['live_meeting_free_minutes'], 15),
      pricePoints: _int(s['live_meeting_price_points'], 30),
      planDays: _int(s['live_meeting_plan_days'], 30),
      pointPrice: _double(s['points_price'], 1),
      currency: '${s['points_currency'] ?? 'SAR'}',
      topupMin: _int(s['points_topup_min'], 10),
      freeMinutesDaily: _int(s['live_meeting_free_minutes_daily'], 30),
      cardEnabled: s['points_card_enabled'] is bool ? s['points_card_enabled'] == true : '${s['points_card_enabled']}' != 'false',
    );
  }

  Map<String, dynamic> toJson() => {
        'live_meeting_free_minutes': freeMinutes,
        'live_meeting_price_points': pricePoints,
        'live_meeting_plan_days': planDays,
        'points_price': pointPrice,
        'points_currency': currency,
        'points_topup_min': topupMin,
        'live_meeting_free_minutes_daily': freeMinutesDaily,
        'points_card_enabled': cardEnabled,
      };

  /// What the plan costs in money at the current point price.
  double get planMoney => pointsMoney(pricePoints, pointPrice);

  /// Why the form cannot be saved (null = fine).
  String? get error {
    if (freeMinutes < 1 || freeMinutes > 1440) {
      return t('الدقائق المجانية بين 1 و1440', 'Free minutes must be between 1 and 1440');
    }
    if (pricePoints < 0) return t('سعر الباقة لا يكون سالباً', 'The plan price cannot be negative');
    if (planDays < 1 || planDays > 3650) return t('مدة الباقة بين يوم و3650 يوماً', 'The plan must last 1 to 3650 days');
    if (pointPrice <= 0) return t('سعر النقطة يجب أن يكون أكبر من صفر', 'The point price must be above zero');
    if (currency.trim().isEmpty) return t('اكتب العملة', 'Enter the currency');
    if (topupMin <= 0) return t('أقل شحن يجب أن يكون نقطة على الأقل', 'The minimum top-up must be at least one point');
    if (freeMinutesDaily < 0 || freeMinutesDaily > 1440) {
      return t('الدقائق المجانية اليومية بين 0 و1440', 'Daily free minutes must be between 0 and 1440');
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

const _me = '/api/v1/me';
const _admin = '/api/v1/admin/points';

class PointsApi {
  const PointsApi();

  ApiClient get _api => ApiClient();

  // ── me ──
  Future<PointsWallet> wallet() async {
    final keys = payerMethodKeys(_api, timeout: pointsTimeout);
    final w = PointsWallet.fromJson(await _api.get('$_me/points').timeout(pointsTimeout));
    return w.forPayer(await keys);
  }

  Future<LivePlan> livePlan() async => LivePlan.fromJson(await _api.get('$_me/live-plan').timeout(pointsTimeout));

  Future<LivePlan> subscribe() async =>
      LivePlan.fromJson(await _api.post('$_me/live-plan/subscribe').timeout(pointsTimeout));

  /// Renew automatically from the points when the plan ends (§15). Answers the plan.
  Future<LivePlan> setAutoRenew(bool on) async =>
      LivePlan.fromJson(await _api.put('$_me/live-plan', body: {'auto_renew': on}).timeout(pointsTimeout));

  /// Buy [points] by card (§13): creates the pending card top-up and the provider's payment session.
  Future<PointsCheckout> checkout({required int points, String? provider}) async => PointsCheckout.fromJson(
      await _api.post('$_me/points/checkout', body: {'points': points, 'provider': ?provider}).timeout(pointsTimeout));

  /// One of my top-ups (polled after the payment page closes).
  Future<PointsTopup> topup(int id) async =>
      PointsTopup.fromJson(_map(await _api.get('$_me/points/topups/$id').timeout(pointsTimeout)));

  Future<PointsTopup> createTopup({
    required int points,
    required String method,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final r = await _api.postMultipart('$_me/points/topups',
        fields: {'points': '$points', 'method': method}, fileField: 'receipt', fileName: fileName, fileBytes: bytes);
    return PointsTopup.fromJson(_map(r));
  }

  // ── admin ──
  Future<(List<PointsUserRow>, int)> users({String q = '', int page = 1}) async => PointsUserRow.pageFrom(await _api
      .get('$_admin/users', queryParams: {if (q.trim().isNotEmpty) 'q': q.trim(), 'page': page}).timeout(pointsTimeout));

  /// [points] ≠ 0; negative = deduct. Returns the new balance.
  Future<int> grant({required int userId, required int points, String note = ''}) async {
    final r = await _api
        .post('$_admin/grant', body: {'user_id': userId, 'points': points, 'note': note}).timeout(pointsTimeout);
    return _int(_map(r)['balance']);
  }

  Future<List<PointsLedgerEntry>> history(int userId) async =>
      PointsLedgerEntry.listFrom(await _api.get('$_admin/users/$userId/history').timeout(pointsTimeout));

  Future<List<PointsTopup>> topups({String? status}) async => PointsTopup.listFrom(
      await _api.get('$_admin/topups', queryParams: {'status': ?status}).timeout(pointsTimeout));

  Future<PointsTopup> approve(int id, {String note = ''}) async => PointsTopup.fromJson(_map(await _api
      .post('$_admin/topups/$id/approve', body: {if (note.trim().isNotEmpty) 'note': note.trim()}).timeout(pointsTimeout)));

  Future<PointsTopup> reject(int id, {String note = ''}) async => PointsTopup.fromJson(_map(await _api
      .post('$_admin/topups/$id/reject', body: {if (note.trim().isNotEmpty) 'note': note.trim()}).timeout(pointsTimeout)));

  Future<Uint8List> receipt(int id) => _api.getBytes('$_admin/topups/$id/receipt').timeout(const Duration(seconds: 60));

  Future<PointsSettings> settings() async =>
      PointsSettings.fromJson(await _api.get('$_admin/settings').timeout(pointsTimeout));

  Future<PointsSettings> saveSettings(PointsSettings s) async =>
      PointsSettings.fromJson(await _api.put('$_admin/settings', body: s.toJson()).timeout(pointsTimeout));
}

/// Is [bytes] a PDF (the receipt viewer opens it outside the app)?
bool isPdfBytes(Uint8List bytes) =>
    bytes.length >= 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46;

/// Thrown by a join (`JoinArgs.onStart`) when the meeting owner was offered the live-meeting plan (402
/// `live_plan_required`) and closed the sheet without subscribing: the join stops. The pre-join page may treat it as
/// "stay here, say nothing" (`error is LivePlanDeclined`); shown as an error, its text explains why.
class LivePlanDeclined implements Exception {
  const LivePlanDeclined();

  @override
  String toString() => pointsCodeText('live_plan_required')!;
}

/// A join that cannot go on, with a clear text (403 `meeting_time_limit`): the pre-join page shows `toString()`.
class LiveJoinMessage implements Exception {
  const LiveJoinMessage(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The meeting detail's free-time line for a student-owned meeting without a plan; [owner] words it for the owner.
/// Under the daily cap (§14) the owner also reads how much free time is left today.
String meetingFreeNote(MeetingTimeLimit l, DateTime nowUtc, {bool owner = false}) {
  final e = l.endsAt;
  final daily = l.hasDailyCap && owner ? ' ${dailyFreeLeftText(l.dailyLeft ?? 0, l.dailyMinutes)}.' : '';
  if (e == null) {
    if (l.hasDailyCap && l.windowMinutes <= 0) {
      return owner
          ? t('انتهى وقتك المجاني لليوم (${l.dailyMinutes} دقيقة). اشترك في باقة الاجتماعات لتبدأ الآن، أو عد غداً.',
              "Today's free time is used up (${l.dailyMinutes} minutes). Get the live-meeting plan to start now, or come back tomorrow.")
          : t('انتهى الوقت المجاني لمنظّم هذا الاجتماع لهذا اليوم.', "The organizer's free time for today is used up.");
    }
    final w = l.windowMinutes;
    return owner
        ? t('اجتماعك مجاني لأول $w دقيقة من البث، ثم يتوقف. اشترك في باقة الاجتماعات لإزالة الحد.',
                'Your meeting is free for its first $w live minutes, then it stops. Get the live-meeting plan to remove the limit.') +
            daily
        : t('هذا الاجتماع مجاني لأول $w دقيقة من البث.', 'This meeting is free for its first $w live minutes.');
  }
  final left = l.minutesLeft(nowUtc);
  if (left <= 0) {
    return owner
        ? t('انتهى الوقت المجاني لهذا الاجتماع. اشترك في باقة الاجتماعات للمتابعة.',
                "This meeting's free time is over. Get the live-meeting plan to continue.") +
            daily
        : t('انتهى الوقت المجاني لهذا الاجتماع.', "This meeting's free time is over.");
  }
  return t('متبقٍ $left دقيقة من الوقت المجاني لهذا الاجتماع.', '$left free minutes left in this meeting.') + daily;
}
