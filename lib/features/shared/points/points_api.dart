// lib/features/shared/points/points_api.dart — the points wallet and the student live-meeting plan: pure models,
// code → text, price maths and the API calls. Contract: docs/backend/live-rooms-spec.md §8 – §9.
//
//   GET  /api/v1/me/points                      wallet: balance, price per point, currency, minimum, methods,
//                                               history (ledger), my top-ups
//   POST /api/v1/me/points/topups               multipart: points · method · receipt
//   GET  /api/v1/me/live-plan · POST …/subscribe   the live-meeting plan (402 points_insufficient)
//   Admin:  /api/v1/admin/points/users · /grant · /users/{uid}/history · /topups[?status] · /topups/{id}/approve |
//           reject | receipt · /settings
//
// Everything above the API section takes plain values and is unit-tested in test/org/points_test.dart. Server times
// are naive UTC (parsed as UTC, shown through AppTime). Inline strings use t(ar, en) (no translation.json edits).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';

import '../../admin/admin_common.dart' show t;

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
  return currency.isEmpty ? s : '$s $currency';
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
      _ => method,
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

/// GET /me/live-plan — {active, ends_at|null, price_points, days, free_minutes, balance, needed}.
class LivePlan {
  const LivePlan({
    this.active = false,
    this.endsAt,
    this.pricePoints = 30,
    this.days = 30,
    this.freeMinutes = 15,
    this.balance = 0,
    this.needed = true,
  });

  final bool active;
  final DateTime? endsAt;
  final int pricePoints;
  final int days;
  final int freeMinutes;
  final int balance;

  /// False for staff: their meetings are unlimited, the plan is never shown to them.
  final bool needed;

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
    );
  }

  bool get canAfford => balance >= pricePoints;

  int get shortfall => pointsShortfall(balance, pricePoints);

  /// Whole days left of an active plan (0 when it ends today or is inactive / unlimited).
  int daysLeft(DateTime nowUtc) {
    final e = endsAt;
    if (!active || e == null || !e.isAfter(nowUtc)) return 0;
    return e.difference(nowUtc).inHours ~/ 24;
  }

  LivePlan copyWith({int? balance}) => LivePlan(
        active: active,
        endsAt: endsAt,
        pricePoints: pricePoints,
        days: days,
        freeMinutes: freeMinutes,
        balance: balance ?? this.balance,
        needed: needed,
      );
}

/// A meeting's free-time limit (`time_limit` of the join payload and the meeting detail); null = unlimited.
class MeetingTimeLimit {
  const MeetingTimeLimit({this.endsAt, this.freeMinutes = 15});

  final DateTime? endsAt;
  final int freeMinutes;

  static MeetingTimeLimit? parse(dynamic v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return MeetingTimeLimit(endsAt: pointsParseUtc(j['ends_at']), freeMinutes: _int(j['free_minutes'], 15));
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
  const PointsUser({required this.id, this.name = '', this.email, this.phone, this.role});

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? role;

  factory PointsUser.fromJson(dynamic json) {
    final j = _map(json);
    return PointsUser(
      id: _int(j['id']),
      name: '${j['name'] ?? ''}',
      email: _strOrNull(j['email']),
      phone: _strOrNull(j['phone']),
      role: _strOrNull(j['role']),
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

  factory PointsTopup.fromJson(Map<String, dynamic> j) => PointsTopup(
        id: _int(j['id']),
        points: _int(j['points']),
        amount: _double(j['amount']),
        currency: '${j['currency'] ?? ''}',
        method: '${j['method'] ?? ''}',
        status: topupStatusFrom(j['status']),
        note: _strOrNull(j['note']),
        createdAt: pointsParseUtc(j['created_at']),
        decidedAt: pointsParseUtc(j['decided_at']),
        user: j['user'] is Map ? PointsUser.fromJson(j['user']) : null,
      );

  bool get isPending => status == TopupStatus.pending;

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

/// The six app settings of §9 (super admin).
class PointsSettings {
  const PointsSettings({
    this.freeMinutes = 15,
    this.pricePoints = 30,
    this.planDays = 30,
    this.pointPrice = 1.0,
    this.currency = 'SAR',
    this.topupMin = 10,
  });

  final int freeMinutes;
  final int pricePoints;
  final int planDays;
  final double pointPrice;
  final String currency;
  final int topupMin;

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
    );
  }

  Map<String, dynamic> toJson() => {
        'live_meeting_free_minutes': freeMinutes,
        'live_meeting_price_points': pricePoints,
        'live_meeting_plan_days': planDays,
        'points_price': pointPrice,
        'points_currency': currency,
        'points_topup_min': topupMin,
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
  Future<PointsWallet> wallet() async => PointsWallet.fromJson(await _api.get('$_me/points').timeout(pointsTimeout));

  Future<LivePlan> livePlan() async => LivePlan.fromJson(await _api.get('$_me/live-plan').timeout(pointsTimeout));

  Future<LivePlan> subscribe() async =>
      LivePlan.fromJson(await _api.post('$_me/live-plan/subscribe').timeout(pointsTimeout));

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
String meetingFreeNote(MeetingTimeLimit l, DateTime nowUtc, {bool owner = false}) {
  final e = l.endsAt;
  if (e == null) {
    return owner
        ? t('اجتماعك مجاني لأول ${l.freeMinutes} دقيقة من البث، ثم يتوقف. اشترك في باقة الاجتماعات لإزالة الحد.',
            'Your meeting is free for its first ${l.freeMinutes} live minutes, then it stops. Get the live-meeting plan to remove the limit.')
        : t('هذا الاجتماع مجاني لأول ${l.freeMinutes} دقيقة من البث.', 'This meeting is free for its first ${l.freeMinutes} live minutes.');
  }
  final left = l.minutesLeft(nowUtc);
  if (left <= 0) {
    return owner
        ? t('انتهى الوقت المجاني لهذا الاجتماع. اشترك في باقة الاجتماعات للمتابعة.',
            "This meeting's free time is over. Get the live-meeting plan to continue.")
        : t('انتهى الوقت المجاني لهذا الاجتماع.', "This meeting's free time is over.");
  }
  return t('متبقٍ $left دقيقة من الوقت المجاني لهذا الاجتماع.', '$left free minutes left in this meeting.');
}
