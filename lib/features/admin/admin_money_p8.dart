// Phase 8 money screens (app): fee policy, per-organization fee overrides, refunds, the ledger report.
//
//   GET  /admin/fees                         `policy` {fee_bearer, student_share, vat_on, is_default, …}
//   PUT  /admin/fees/policy                  {fee_bearer?, student_share?, vat_on?} | {reset: true}      (super admin)
//   GET|PUT /admin/fees/orgs/{id}            settings (null = inherit) + effective; {reset: true}        (super admin)
//   POST /payments/{id}/refund               {amount?, reason?, idempotency_key?, manual?, force?}; 202 = pending
//   POST /payments/refunds/{id}/resolve      {action: reconcile|succeeded|failed, reason?}
//   GET  /admin/finance/ledger-report        group_by=teacher|org|month, date_from, date_to, currency, format=json|csv
//
// Every write is super-admin only on the server: an admin sees the same screens read-only. The pure parts
// ([FeePolicy], [FeePolicyDraft], [OrgFeeSettings], [OrgFeeDraft], [RefundDraft], [RefundOutcome], [LedgerReport],
// [feeCodeText]) are unit-tested; the forms are presentational and run under the layout harness.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_responsive.dart' show Breakpoints;
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../shared/exam_engine/exam_engine_api.dart' show EngineResult, engineCall;
import 'admin_page.dart';
import 'admin_common.dart' show asBool, asDouble, asInt, asMap, asMapList, asStr, asStrOrNull, isSuperNow, money, shortDateTime, t;

// ── shared pure helpers (also used by the feedback / RAG library screens) ───────────────────────────────────────

/// "12,5" · "١٢٫٥" · " 7 " → 12.5 / 12.5 / 7; null when it is not a number.
double? parseNum(String s) {
  var x = s.trim();
  if (x.isEmpty) return null;
  const ar = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final r in x.runes) {
    final ch = String.fromCharCode(r);
    final i = ar.indexOf(ch);
    b.write(i >= 0 ? '$i' : (ch == '٫' ? '.' : ch));
  }
  x = b.toString();
  // a comma is a thousands separator only ("1,000" = 1000), never a decimal point: refunding 1 instead of 1000 must be impossible
  if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(x)) x = x.replaceAll(',', '');
  if (x.contains(',') || x.contains('،')) return null;
  return double.tryParse(x);
}

/// "2,5" · "٢،٥" · "12.5" · "1,000" → 2.5 / 2.5 / 12.5 / 1000. [parseNum] reads Arabic digits and refuses a lone
/// comma (it could be a thousands separator); here a comma followed by one or two digits at the very end is a
/// decimal comma, because nobody types "2,5" to mean 25.
double? parseAmountLoose(String s) {
  final v = parseNum(s);
  if (v != null) return v;
  final m = RegExp(r'^([0-9٠-٩]+)[,،]([0-9٠-٩]{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  return parseNum('${m[1]}.${m[2]}');
}

String numText(num? v) {
  if (v == null) return '';
  final d = v.toDouble();
  return d == d.truncateToDouble() ? d.toStringAsFixed(0) : '$d';
}

/// Saves downloaded bytes (browser download · Downloads · share sheet, whichever the platform offers).
/// A file name from server data made safe to save: no path separators or control characters, a sane length.
String safeFileName(String raw, {String fallback = 'download'}) {
  var s = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').replaceAll(RegExp(r'\.{2,}'), '.').trim();
  s = s.replaceAll(RegExp(r'^[.\s_]+'), '');
  if (s.length > 120) s = s.substring(s.length - 120);
  return s.isEmpty ? fallback : s;
}

Future<void> p8SaveBytes(Uint8List bytes, String rawName, {String mime = 'application/octet-stream'}) async {
  final filename = safeFileName(rawName);
  final dot = filename.lastIndexOf('.');
  final name = dot > 0 ? filename.substring(0, dot) : filename;
  final ext = dot > 0 ? filename.substring(dot + 1) : '';
  await FileSaver.instance.saveFile(
      name: name, bytes: bytes, fileExtension: ext, mimeType: MimeType.custom, customMimeType: mime);
}

/// Server codes of the fee / refund / ledger routes as bilingual text; [fallback] (the server's own message) otherwise.
String feeCodeText(String? code, String fallback) => switch (code) {
      'super_admin_required' || 'fee_settings_super_admin_only' =>
        t('تعديل الرسوم للمشرف العام فقط', 'Only the super admin can change fees'),
      'refund_not_completed' => t('الدفعة غير مكتملة فلا يمكن استردادها', 'This payment is not completed, so it cannot be refunded'),
      'refund_invalid_amount' => t('مبلغ الاسترداد غير صالح', 'The refund amount is not valid'),
      'refund_exceeds_remaining' => t('المبلغ أكبر من المتبقي القابل للاسترداد', 'The amount is more than what is left to refund'),
      'refund_not_supported' => t('بوابة الدفع لا تدعم الاسترداد الآلي — استخدم الاسترداد اليدوي', 'The gateway cannot refund by API — use a manual refund'),
      'refund_key_conflict' => t('مفتاح العملية استُخدم لمبلغ آخر', 'This request key was used for another amount'),
      'refund_in_progress' => t('هناك استرداد قيد التنفيذ لهذه الدفعة', 'A refund is already in progress for this payment'),
      'refund_gateway_failed' => t('رفضت البوابة الاسترداد أو تعذر الوصول إليها', 'The gateway refused the refund or could not be reached'),
      'refund_failed' => t('فشلت هذه العملية سابقاً — ابدأ عملية جديدة', 'This request failed earlier — start a new one'),
      'refund_manual_forbidden' => t('الاسترداد اليدوي للمشرف العام فقط', 'Manual refunds are for the super admin only'),
      'refund_manual_needs_force' => t('هذه البوابة تسترد آلياً — فعّل «إجبار» واكتب السبب لتسجيل استرداد يدوي', 'This gateway refunds by API — tick "Force" and give a reason to record a manual refund'),
      'refund_external_recorded' => t('سُجّل استرداد تم من لوحة بوابة الدفع مباشرة — راجع المتبقي ثم أعد المحاولة', 'A refund made in the gateway dashboard was just recorded — check what is left, then try again'),
      'reason_required' => t('اكتب السبب', 'A reason is required'),
      'currency_mismatch' => t('عملة الدورة تختلف عن عملة البوابة', 'The course currency differs from the gateway currency'),
      'orgs_disabled' => t('المؤسسات متوقفة على المنصة', 'Organizations are switched off on the platform'),
      _ => fallback,
    };

// ── fee policy ────────────────────────────────────────────────────────────────────────────────────────────────

const feeBearers = ['both', 'student', 'teacher', 'split'];
const vatBases = ['fee', 'price', 'none'];

String feeBearerText(String v) => switch (v) {
      'both' => t('كل طرف يتحمل رسومه (افتراضي)', 'Each side pays its own (default)'),
      'student' => t('الطالب يتحمل الرسوم كلها', 'The student pays the whole fee'),
      'teacher' => t('المعلّم يتحمل الرسوم كلها', 'The teacher pays the whole fee'),
      'split' => t('تقسيم الرسوم بنسبة', 'Split the fee by a share'),
      _ => v,
    };

String vatBaseText(String v) => switch (v) {
      'fee' => t('على رسوم المنصة (افتراضي)', 'On the platform fee (default)'),
      'price' => t('على سعر الدورة', 'On the course price'),
      'none' => t('بدون ضريبة', 'No VAT'),
      _ => v,
    };

class FeePolicy {
  const FeePolicy({this.feeBearer = 'both', this.studentShare = 0.5, this.vatOn = 'fee', this.isDefault = true});
  final String feeBearer;
  final double studentShare; // 0..1
  final String vatOn;
  final bool isDefault;

  factory FeePolicy.fromJson(Map<String, dynamic> j) => FeePolicy(
      feeBearer: feeBearers.contains(j['fee_bearer']) ? '${j['fee_bearer']}' : 'both',
      studentShare: (asDouble(j['student_share'], 0.5)).clamp(0.0, 1.0),
      vatOn: vatBases.contains(j['vat_on']) ? '${j['vat_on']}' : 'fee',
      isDefault: j['is_default'] is bool ? j['is_default'] as bool : true);
}

/// The editor's state. [share] is typed as a percentage (0–100) and sent as 0–1.
class FeePolicyDraft {
  FeePolicyDraft({this.bearer = 'both', this.share = '50', this.vatOn = 'fee'});
  String bearer;
  String share;
  String vatOn;

  factory FeePolicyDraft.of(FeePolicy p) => FeePolicyDraft(bearer: p.feeBearer, share: numText(p.studentShare * 100), vatOn: p.vatOn);

  /// null when valid, else a code ('bad_share' …).
  String? validate() {
    if (!feeBearers.contains(bearer) || !vatBases.contains(vatOn)) return 'bad_choice';
    if (bearer == 'split') {
      final s = parseNum(share);
      if (s == null || s < 0 || s > 100) return 'bad_share';
    }
    return null;
  }

  Map<String, dynamic> body() => {
        'fee_bearer': bearer,
        if (bearer == 'split') 'student_share': (parseNum(share)! / 100),
        'vat_on': vatOn,
      };
}

String draftErrorText(String code) => switch (code) {
      'bad_share' => t('حصة الطالب بين 0 و100', 'The student share must be between 0 and 100'),
      'bad_percent' => t('النسبة بين 0 و100', 'A percentage must be between 0 and 100'),
      'bad_fixed' => t('المبلغ الثابت بين 0 و10000', 'The fixed amount must be between 0 and 10000'),
      'bad_amount' => t('أدخل مبلغاً صحيحاً أكبر من صفر', 'Enter a valid amount above zero'),
      'amount_exceeds' => t('المبلغ أكبر من المتبقي', 'The amount is more than what is left'),
      'reason_required' => t('اكتب السبب', 'A reason is required'),
      'manual_super_only' => t('الاسترداد اليدوي للمشرف العام فقط', 'Manual refunds are for the super admin only'),
      'bad_days' => t('مدة الاحتفاظ بين 1 و3650 يوماً', 'Retention must be between 1 and 3650 days'),
      'title_required' => t('اكتب عنواناً', 'A title is required'),
      'file_required' => t('اختر ملفاً', 'Pick a file'),
      'course_required' => t('اختر المقرر', 'Pick the course'),
      _ => t('تحقق من الحقول', 'Check the fields'),
    };

// ── per-organization overrides ────────────────────────────────────────────────────────────────────────────────

class OrgFeeSettings {
  const OrgFeeSettings(this.orgId, this.own, this.effective);
  final int orgId;

  /// the organization's own values; null = inherit
  final Map<String, dynamic> own;
  final Map<String, dynamic> effective;

  factory OrgFeeSettings.fromJson(Map<String, dynamic> j) =>
      OrgFeeSettings(asInt(j['org_id']), asMap(j['settings']), asMap(j['effective']));

  /// true when at least one field overrides the platform value
  bool get customised => own.values.any((v) => v != null);
}

/// Text fields: '' = inherit. Percent fields are typed 0–100; [share] 0–100 (sent as 0–1).
class OrgFeeDraft {
  OrgFeeDraft({this.platformPercent = '', this.platformFixed = '', this.bearer = '', this.share = '', this.vatPercent = '',
      this.vatOn = '', this.teacherVatPercent = ''});
  String platformPercent, platformFixed, bearer, share, vatPercent, vatOn, teacherVatPercent;

  factory OrgFeeDraft.of(OrgFeeSettings s) {
    String n(String k, [double mul = 1]) => s.own[k] == null ? '' : numText(asDouble(s.own[k]) * mul);
    return OrgFeeDraft(
        platformPercent: n('platform_percent'),
        platformFixed: n('platform_fixed'),
        bearer: asStr(s.own['fee_bearer']),
        share: n('student_share', 100),
        vatPercent: n('vat_percent'),
        vatOn: asStr(s.own['vat_on']),
        teacherVatPercent: n('teacher_vat_percent'));
  }

  String? validate() {
    for (final f in [platformPercent, vatPercent, teacherVatPercent]) {
      if (f.trim().isEmpty) continue;
      final v = parseNum(f);
      if (v == null || v < 0 || v > 100) return 'bad_percent';
    }
    if (platformFixed.trim().isNotEmpty) {
      final v = parseNum(platformFixed);
      if (v == null || v < 0 || v > 10000) return 'bad_fixed';
    }
    if (share.trim().isNotEmpty) {
      final v = parseNum(share);
      if (v == null || v < 0 || v > 100) return 'bad_share';
    }
    return null;
  }

  /// Every field is sent (null = inherit), so clearing a value really goes back to the platform's.
  Map<String, dynamic> body() {
    double? n(String s, [double div = 1]) => s.trim().isEmpty ? null : parseNum(s)! / div;
    return {
      'platform_percent': n(platformPercent),
      'platform_fixed': n(platformFixed),
      'fee_bearer': bearer.isEmpty ? null : bearer,
      'student_share': n(share, 100),
      'vat_percent': n(vatPercent),
      'vat_on': vatOn.isEmpty ? null : vatOn,
      'teacher_vat_percent': n(teacherVatPercent),
    };
  }
}

// ── refunds ───────────────────────────────────────────────────────────────────────────────────────────────────

class RefundDraft {
  RefundDraft({this.amount = '', this.reason = '', this.manual = false, this.force = false, this.remaining, String? key})
      : key = key ?? newRefundKey();
  String amount, reason;
  bool manual, force;

  /// what is still refundable (major units); null = unknown
  double? remaining;

  /// reused on every retry of the same sheet so a double tap never refunds twice
  final String key;

  static String newRefundKey() => 'app-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30)}';

  String? validate({required bool superAdmin}) {
    if (amount.trim().isNotEmpty) {
      final a = parseNum(amount);
      if (a == null || a <= 0) return 'bad_amount';
      if (remaining != null && a > remaining! + 0.0001) return 'amount_exceeds';
    }
    if ((manual || force) && !superAdmin) return 'manual_super_only';
    if (force && !manual) return 'bad_choice';
    if (force && reason.trim().isEmpty) return 'reason_required';
    return null;
  }

  Map<String, dynamic> body() => {
        if (amount.trim().isNotEmpty) 'amount': parseNum(amount),
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        'idempotency_key': key,
        if (manual) 'manual': true,
        if (force) 'force': true,
      };
}

class RefundOutcome {
  const RefundOutcome(this.id, this.status, this.amount, this.currency, this.outcomeUnknown, this.manual, this.refundedAmount);
  final int id;
  final String status; // succeeded | pending | failed
  final double amount;
  final String currency;
  final bool outcomeUnknown;
  final bool manual;
  final double? refundedAmount;

  bool get pending => status == 'pending';

  /// the response of `/refund` (PaymentResponse + refund{…}) or of `/resolve` ({refund})
  factory RefundOutcome.fromJson(Map<String, dynamic> j) {
    final r = asMap(j['refund']);
    return RefundOutcome(asInt(r['id']), asStr(r['status'], 'succeeded'), asDouble(r['amount']), asStr(r['currency']),
        asBool(r['outcome_unknown']), asBool(r['manual']), j['refunded_amount'] == null ? null : asDouble(j['refunded_amount']));
  }
}

/// 409 `refund_external_recorded` `{recorded, remaining}` (major units): before calling the gateway the server found a
/// refund made in the gateway's own dashboard, recorded it, and refunded nothing. Nothing was reserved, so a retry with
/// the same idempotency key is safe — but the admin must first see what is left (they may be about to refund it twice).
class RefundExternalRecorded {
  const RefundExternalRecorded(this.recorded, this.remaining);
  final double recorded;

  /// what is still refundable after the recorded refund; null = the server did not say
  final double? remaining;

  bool get nothingLeft => remaining != null && remaining! <= 0.0001;

  static RefundExternalRecorded? from(EngineResult r) {
    if (r.ok || r.code != 'refund_external_recorded') return null;
    final d = r.detail;
    return RefundExternalRecorded(asDouble(d['recorded']), d['remaining'] == null ? null : asDouble(d['remaining']));
  }

  String text(String? currency) {
    final head = t('وُجد استرداد بقيمة ${money(recorded, currency)} تم من لوحة بوابة الدفع مباشرة، وسُجّل الآن. لم يُسترد شيء من طلبك.',
        'A refund of ${money(recorded, currency)} made in the gateway dashboard was found and recorded. Nothing of your request was refunded.');
    if (remaining == null) return '$head ${t('راجع المبلغ المتبقي ثم أعد المحاولة.', 'Check what is left, then try again.')}';
    if (nothingLeft) return '$head ${t('لم يبقَ شيء للاسترداد.', 'Nothing is left to refund.')}';
    return '$head ${t('المتبقي القابل للاسترداد الآن', 'Left to refund now')}: ${money(remaining!, currency)}. '
        '${t('راجع المبلغ ثم أعد المحاولة إن لزم.', 'Check the amount, then try again if still needed.')}';
  }
}

/// What a payment row says about refunds (`GET /admin/finance/payments` items): `refunded_amount` (succeeded refunds,
/// partial included) and `refundable_amount` (0 unless the payment is completed). An older server sends neither: then
/// the whole amount counts as refundable, as before.
({double refunded, double? refundable}) paymentRefundFigures(Map<String, dynamic> p) {
  final refunded = p['refunded_amount'] == null ? 0.0 : asDouble(p['refunded_amount']);
  final double? refundable = p['refundable_amount'] != null
      ? asDouble(p['refundable_amount'])
      : (p['amount'] == null ? null : math.max(0.0, asDouble(p['amount']) - refunded));
  return (refunded: refunded, refundable: refundable);
}

String refundStatusText(String s) => switch (s) {
      'succeeded' || 'completed' => t('تم الاسترداد', 'Refunded'),
      'pending' => t('قيد التأكيد', 'Pending'),
      'failed' => t('فشل', 'Failed'),
      _ => s,
    };

// ── ledger report ─────────────────────────────────────────────────────────────────────────────────────────────

const ledgerMetrics = ['collected', 'refunded', 'teacher_net', 'clawback', 'paid_out', 'teacher_balance', 'platform', 'tax', 'gateway'];

String ledgerMetricText(String m) => switch (m) {
      'collected' => t('المحصّل', 'Collected'),
      'refunded' => t('المسترد', 'Refunded'),
      'teacher_net' => t('صافي المعلّم', 'Teacher net'),
      'clawback' => t('الاسترجاع', 'Clawback'),
      'paid_out' => t('المدفوع للمعلّم', 'Paid out'),
      'teacher_balance' => t('رصيد المعلّم', 'Teacher balance'),
      'platform' => t('المنصة', 'Platform'),
      'tax' => t('الضريبة', 'Tax'),
      'gateway' => t('البوابة', 'Gateway'),
      _ => m,
    };

String ledgerGroupText(String g) => switch (g) {
      'teacher' => t('المعلّم', 'Teacher'),
      'org' => t('المؤسسة', 'Organization'),
      'month' => t('الشهر', 'Month'),
      _ => g,
    };

class LedgerRow {
  const LedgerRow(this.key, this.label, this.currency, this.values);
  final String key;
  final String label;
  final String currency;
  final Map<String, double> values;
}

class LedgerReport {
  const LedgerReport(this.groupBy, this.rows, this.totals, this.groups, this.unbalanced);
  final String groupBy;
  final List<LedgerRow> rows;
  final Map<String, Map<String, double>> totals; // currency → metric → amount
  final int groups;
  final int unbalanced;

  bool get balanced => unbalanced == 0;

  static Map<String, double> _vals(Map<String, dynamic> m) => {for (final k in ledgerMetrics) k: asDouble(m[k])};

  factory LedgerReport.fromJson(Map<String, dynamic> j) {
    final integrity = asMap(j['integrity']);
    return LedgerReport(
        asStr(j['group_by'], 'teacher'),
        [
          for (final r in asMapList(j['rows']))
            LedgerRow(asStr(r['key']), asStr(r['label']).isNotEmpty ? asStr(r['label']) : (asStr(r['key']).isEmpty ? '—' : '#${r['key']}'),
                asStr(r['currency']), _vals(r))
        ],
        {for (final e in asMap(j['totals']).entries) e.key: _vals(asMap(e.value))},
        asInt(integrity['groups']),
        asInt(integrity['unbalanced_groups']));
  }
}

class LedgerQuery {
  const LedgerQuery({this.groupBy = 'teacher', this.from, this.to, this.currency = ''});
  final String groupBy;
  final DateTime? from, to;
  final String currency;

  static String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// null when valid; the range must not be reversed and a currency is a 3-letter code.
  String? validate() {
    if (from != null && to != null && to!.isBefore(from!)) return 'bad_range';
    if (currency.isNotEmpty && !RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) return 'bad_currency';
    return null;
  }

  Map<String, dynamic> params({String format = 'json'}) => {
        'group_by': groupBy,
        if (from != null) 'date_from': _d(from!),
        if (to != null) 'date_to': _d(to!),
        if (currency.isNotEmpty) 'currency': currency.toUpperCase(),
        'format': format,
      };
}

// ── API ───────────────────────────────────────────────────────────────────────────────────────────────────────

class MoneyP8Api {
  MoneyP8Api([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const fees = '/api/v1/admin/fees';

  Future<EngineResult> feesOverview() => engineCall(() => _api.get(fees));
  Future<EngineResult> savePolicy(Map<String, dynamic> body) => engineCall(() => _api.put('$fees/policy', body: body));
  Future<EngineResult> resetPolicy() => engineCall(() => _api.put('$fees/policy', body: {'reset': true}));
  Future<EngineResult> orgs({String search = '', int page = 1}) =>
      engineCall(() => _api.get('/api/v1/admin/orgs', queryParams: {'status': 'approved', 'size': 30, 'page': page, if (search.isNotEmpty) 'search': search}));
  Future<EngineResult> orgFees(int orgId) => engineCall(() => _api.get('$fees/orgs/$orgId'));
  Future<EngineResult> saveOrgFees(int orgId, Map<String, dynamic> body) => engineCall(() => _api.put('$fees/orgs/$orgId', body: body));
  Future<EngineResult> resetOrgFees(int orgId) => engineCall(() => _api.put('$fees/orgs/$orgId', body: {'reset': true}));
  Future<EngineResult> refund(int paymentId, RefundDraft d) => engineCall(() => _api.post('/api/v1/payments/$paymentId/refund', body: d.body()));
  Future<EngineResult> resolveRefund(int refundId, String action, {String? reason}) =>
      engineCall(() => _api.post('/api/v1/payments/refunds/$refundId/resolve', body: {'action': action, if (reason != null && reason.isNotEmpty) 'reason': reason}));
  Future<EngineResult> ledger(LedgerQuery q) =>
      engineCall(() => _api.get('/api/v1/admin/finance/ledger-report', queryParams: q.params()));
  Future<Uint8List> ledgerCsv(LedgerQuery q) =>
      _api.getBytes('/api/v1/admin/finance/ledger-report', queryParams: q.params(format: 'csv'));
}

// ── page ──────────────────────────────────────────────────────────────────────────────────────────────────────

class AdminMoneyPage extends StatefulWidget {
  const AdminMoneyPage({super.key, this.initialTab = 0, this.superAdmin});
  final int initialTab;

  /// null = decided from the session (a super admin who is not "viewing as" an admin)
  final bool? superAdmin;

  @override
  State<AdminMoneyPage> createState() => _AdminMoneyPageState();
}

class _AdminMoneyPageState extends State<AdminMoneyPage> {
  late int _tab = widget.initialTab;
  final _policyKey = GlobalKey<_PolicyTabState>();
  final _orgsKey = GlobalKey<_OrgFeesTabState>();
  final _ledgerKey = GlobalKey<_LedgerTabState>();

  Future<void> _refresh() async {
    await switch (_tab) {
      0 => _policyKey.currentState?._load(),
      1 => _orgsKey.currentState?._load(),
      _ => _ledgerKey.currentState?._run(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final sup = widget.superAdmin ?? isSuperNow(context);
    final tabs = [t('سياسة الرسوم', 'Fee policy'), t('المؤسسات', 'Organizations'), t('دفتر الأستاذ', 'Ledger')];
    final gutter = AppSpace.gutter(MediaQuery.sizeOf(context).width);
    return BasePage(
      // the kill switch (a super admin can switch the fee screens off)
      key: const ValueKey('admin.fee_policy'),
      child: AdminPage(
        title: t('الرسوم والتقارير المالية', 'Fees & financial reports'),
        icon: Icons.account_balance_rounded,
        onRefresh: _refresh,
        body: Column(children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.md, gutter, AppSpace.xxs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppTabs(index: _tab, onChanged: (i) => setState(() => _tab = i), items: [for (final x in tabs) AppTabItem(x)]),
            ),
          ),
          if (!sup)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(gutter, AppSpace.xxs, gutter, 0),
              child: AppBanner(icon: Icons.lock_outline_rounded, text: t('عرض فقط — تعديل الرسوم للمشرف العام', 'Read-only — only the super admin can change fees')),
            ),
          Expanded(
            child: IndexedStack(index: _tab, children: [
              _PolicyTab(key: _policyKey, superAdmin: sup),
              if (sup) _OrgFeesTab(key: _orgsKey, superAdmin: sup) else AppEmpty(icon: Icons.lock_outline_rounded, title: t('رسوم المؤسسات للمشرف العام فقط', 'Organization fees are for the super admin only')),
              _LedgerTab(key: _ledgerKey),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PolicyTab extends StatefulWidget {
  const _PolicyTab({super.key, required this.superAdmin});
  final bool superAdmin;
  @override
  State<_PolicyTab> createState() => _PolicyTabState();
}

class _PolicyTabState extends State<_PolicyTab> {
  final _api = MoneyP8Api();
  FeePolicy? _policy;
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.feesOverview();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : feeCodeText(r.code, r.message);
      if (r.ok) _policy = FeePolicy.fromJson(asMap(r.map['policy']));
    });
  }

  Future<void> _save(FeePolicyDraft d) async {
    // the policy applies to every LATER payment: the confirm states exactly what changes
    final old = _policy;
    final lines = <String>[
      if (old == null || old.feeBearer != d.bearer)
        '${t('متحمل الرسوم', 'Fee bearer')}: ${old == null ? '—' : feeBearerText(old.feeBearer)} \u2192 ${feeBearerText(d.bearer)}',
      if (d.bearer == 'split' && (old == null || old.feeBearer != 'split' || numText(old.studentShare * 100) != numText(parseNum(d.share))))
        '${t('حصة الطالب', 'Student share')}: ${numText(parseNum(d.share))}%',
      if (old == null || old.vatOn != d.vatOn)
        '${t('أساس الضريبة', 'VAT base')}: ${old == null ? '—' : vatBaseText(old.vatOn)} \u2192 ${vatBaseText(d.vatOn)}',
    ];
    final ok = await appConfirm(
      context,
      message: '${lines.isEmpty ? t('لا تغيير في القيم.', 'No value changes.') : lines.join('\n')}\n\n${t('تنطبق السياسة على كل عملية دفع قادمة. حفظ؟', 'The policy applies to every later payment. Save?')}',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.savePolicy(d.body());
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      appToast(t('تم حفظ سياسة الرسوم', 'Fee policy saved'));
      _load();
    } else {
      appToast(feeCodeText(r.code, r.message), error: true);
    }
  }

  Future<void> _reset() async {
    if (!await appConfirm(context, message: t('العودة إلى السياسة الافتراضية؟ تنطبق على كل عملية دفع قادمة.', 'Go back to the default policy? It applies to every later payment.'), danger: true)) return;
    setState(() => _busy = true);
    final r = await _api.resetPolicy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      _load();
    } else {
      appToast(feeCodeText(r.code, r.message), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppListSkeleton(items: 3, withAvatar: false);
    if (_policy == null) {
      return AppEmpty(icon: Icons.error_outline_rounded, title: _error ?? t('تعذر التحميل', 'Could not load'), actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load);
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      AppCard(
        padding: const EdgeInsets.all(14),
        child: FeePolicyForm(
            key: ValueKey('${_policy!.feeBearer}${_policy!.studentShare}${_policy!.vatOn}'),
            policy: _policy!, readOnly: !widget.superAdmin, busy: _busy, onSave: _save, onReset: _policy!.isDefault ? null : _reset),
      ),
    ]);
  }
}

/// The platform fee policy editor (presentational — the page owns the calls).
class FeePolicyForm extends StatefulWidget {
  const FeePolicyForm({super.key, required this.policy, required this.onSave, this.onReset, this.readOnly = false, this.busy = false});
  final FeePolicy policy;
  final bool readOnly, busy;
  final void Function(FeePolicyDraft draft) onSave;
  final VoidCallback? onReset;

  @override
  State<FeePolicyForm> createState() => _FeePolicyFormState();
}

class _FeePolicyFormState extends State<FeePolicyForm> {
  late final FeePolicyDraft _d = FeePolicyDraft.of(widget.policy);
  late final TextEditingController _share = TextEditingController(text: _d.share);
  String? _err;

  @override
  void dispose() {
    _share.dispose();
    super.dispose();
  }

  void _submit() {
    _d.share = _share.text;
    final e = _d.validate();
    setState(() => _err = e);
    if (e == null) widget.onSave(_d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(t('من يتحمل رسوم البوابة؟', 'Who bears the gateway fee?'), style: appText(15, w: FontWeight.w800, c: c.textDark))),
        if (widget.policy.isDefault) AppBadgePill(t('افتراضي', 'Default'), color: c.textMedium),
      ]),
      const SizedBox(height: 10),
      AppDropdown<String>(
        value: _d.bearer,
        decoration: InputDecoration(labelText: t('متحمل الرسوم', 'Fee bearer')),
        items: [for (final b in feeBearers) DropdownMenuItem(value: b, child: Text(feeBearerText(b), maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: widget.readOnly ? null : (v) => setState(() => _d.bearer = v ?? 'both'),
      ),
      const SizedBox(height: 12),
      if (_d.bearer == 'split')
        AppField(controller: _share, label: t('حصة الطالب من الرسوم %', 'Student share of the fee %'), keyboard: TextInputType.number),
      AppDropdown<String>(
        value: _d.vatOn,
        decoration: InputDecoration(labelText: t('أساس الضريبة', 'VAT base')),
        items: [for (final b in vatBases) DropdownMenuItem(value: b, child: Text(vatBaseText(b), maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: widget.readOnly ? null : (v) => setState(() => _d.vatOn = v ?? 'fee'),
      ),
      if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: draftErrorText(_err!))),
      if (!widget.readOnly) ...[
        const SizedBox(height: 14),
        AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : _submit),
        if (widget.onReset != null)
          TextButton.icon(onPressed: widget.busy ? null : widget.onReset, icon: const Icon(Icons.restart_alt_rounded), label: Text(t('استعادة الافتراضي', 'Reset to default'))),
      ],
    ]);
  }
}

// ── organizations ─────────────────────────────────────────────────────────────────────────────────────────────

class _OrgFeesTab extends StatefulWidget {
  const _OrgFeesTab({super.key, required this.superAdmin});
  final bool superAdmin;
  @override
  State<_OrgFeesTab> createState() => _OrgFeesTabState();
}

class _OrgFeesTabState extends State<_OrgFeesTab> {
  final _api = MoneyP8Api();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _orgs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.orgs(search: _search.text.trim());
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : feeCodeText(r.code, r.message);
      _orgs = r.ok ? asMapList(r.map['items']) : [];
    });
  }

  static String _name(Map<String, dynamic> o) {
    for (final k in ['name', 'name_ar', 'name_en']) {
      if (asStr(o[k]).isNotEmpty) return asStr(o[k]);
    }
    return '#${o['id']}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(children: [
          Expanded(child: AppField(controller: _search, label: t('بحث عن مؤسسة', 'Find an organization'), onChanged: (_) {})),
          const SizedBox(width: 8),
          Padding(padding: const EdgeInsets.only(bottom: 12), child: IconButton.filled(tooltip: t('بحث', 'Search'), onPressed: _load, icon: const Icon(Icons.search_rounded))),
        ]),
      ),
      Expanded(
        child: _loading
            ? const AppListSkeleton()
            : _orgs.isEmpty
                ? AppEmpty(icon: Icons.apartment_rounded, title: _error ?? t('لا توجد مؤسسات', 'No organizations'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _orgs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final o = _orgs[i];
                      return AppCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(Icons.apartment_rounded, color: c.primary),
                          title: Text(_name(o), maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text('#${o['id']}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showAppSheet(context, (_) => OrgFeeSheet(orgId: asInt(o['id']), orgName: _name(o), superAdmin: widget.superAdmin)),
                        ),
                      );
                    },
                  ),
      ),
    ]);
  }
}

/// Loads and edits one organization's fee overrides.
class OrgFeeSheet extends StatefulWidget {
  const OrgFeeSheet({super.key, required this.orgId, required this.orgName, required this.superAdmin, this.api});
  final int orgId;
  final String orgName;
  final bool superAdmin;
  final MoneyP8Api? api;

  @override
  State<OrgFeeSheet> createState() => _OrgFeeSheetState();
}

class _OrgFeeSheetState extends State<OrgFeeSheet> {
  late final MoneyP8Api _api = widget.api ?? MoneyP8Api();
  OrgFeeSettings? _s;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.orgFees(widget.orgId);
    if (!mounted) return;
    setState(() {
      _error = r.ok ? null : feeCodeText(r.code, r.message);
      _s = r.ok ? OrgFeeSettings.fromJson(r.map) : null;
    });
  }

  Future<void> _save(OrgFeeDraft d) async {
    setState(() => _busy = true);
    final r = await _api.saveOrgFees(widget.orgId, d.body());
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      appToast(t('تم الحفظ', 'Saved'));
      Navigator.pop(context);
    } else {
      appToast(feeCodeText(r.code, r.message), error: true);
    }
  }

  Future<void> _reset() async {
    if (!await appConfirm(context, message: t('حذف كل تخصيصات هذه المؤسسة؟', 'Remove every override of this organization?'), danger: true)) return;
    setState(() => _busy = true);
    final r = await _api.resetOrgFees(widget.orgId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.pop(context);
    } else {
      appToast(feeCodeText(r.code, r.message), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(widget.orgName),
      Flexible(
        child: _s == null
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: _error == null ? const SizedBox(height: 120, child: AppListSkeleton(items: 2)) : AppBanner(icon: Icons.error_outline_rounded, color: context.colors.danger, text: _error!))
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: OrgFeeForm(settings: _s!, readOnly: !widget.superAdmin, busy: _busy, onSave: _save, onReset: _s!.customised ? _reset : null),
              ),
      ),
    ]);
  }
}

class OrgFeeForm extends StatefulWidget {
  const OrgFeeForm({super.key, required this.settings, required this.onSave, this.onReset, this.readOnly = false, this.busy = false});
  final OrgFeeSettings settings;
  final bool readOnly, busy;
  final void Function(OrgFeeDraft draft) onSave;
  final VoidCallback? onReset;

  @override
  State<OrgFeeForm> createState() => _OrgFeeFormState();
}

class _OrgFeeFormState extends State<OrgFeeForm> {
  late final OrgFeeDraft _d = OrgFeeDraft.of(widget.settings);
  late final _pp = TextEditingController(text: _d.platformPercent);
  late final _pf = TextEditingController(text: _d.platformFixed);
  late final _sh = TextEditingController(text: _d.share);
  late final _vp = TextEditingController(text: _d.vatPercent);
  late final _tv = TextEditingController(text: _d.teacherVatPercent);
  String? _err;

  @override
  void dispose() {
    for (final c in [_pp, _pf, _sh, _vp, _tv]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    _d
      ..platformPercent = _pp.text
      ..platformFixed = _pf.text
      ..share = _sh.text
      ..vatPercent = _vp.text
      ..teacherVatPercent = _tv.text;
    final e = _d.validate();
    setState(() => _err = e);
    if (e == null) widget.onSave(_d);
  }

  String _eff(String k, {double mul = 1, String suffix = ''}) {
    final v = widget.settings.effective[k];
    return v == null ? '' : '${t('الفعلي', 'Effective')}: ${numText(asDouble(v) * mul)}$suffix';
  }

  Widget _field(TextEditingController c, String label, String effective) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppField(controller: c, label: label, hint: t('فارغ = يرث', 'Empty = inherit'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
        if (effective.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10, top: 0), child: Text(effective, style: appText(11.5, c: context.colors.textLight))),
      ]);

  Widget _choice(String label, String value, List<String> options, String Function(String) text, void Function(String) set) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppDropdown<String>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem(value: '', child: Text(t('يرث من المنصة', 'Inherit from the platform'))),
            for (final o in options) DropdownMenuItem(value: o, child: Text(text(o), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: widget.readOnly ? null : (v) => setState(() => set(v ?? '')),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _field(_pp, t('نسبة رسوم المنصة %', 'Platform fee %'), _eff('platform_percent', suffix: '%')),
      _field(_pf, t('مبلغ ثابت لكل دورة', 'Fixed amount per course'), _eff('platform_fixed')),
      _choice(t('متحمل الرسوم', 'Fee bearer'), _d.bearer, feeBearers, feeBearerText, (v) => _d.bearer = v),
      if (_d.bearer == 'split') _field(_sh, t('حصة الطالب %', 'Student share %'), _eff('student_share', mul: 100, suffix: '%')),
      _field(_vp, t('ضريبة الطلاب %', 'Student VAT %'), _eff('vat_percent', suffix: '%')),
      _choice(t('أساس الضريبة', 'VAT base'), _d.vatOn, vatBases, vatBaseText, (v) => _d.vatOn = v),
      _field(_tv, t('ضريبة المعلّم %', 'Teacher VAT %'), _eff('teacher_vat_percent', suffix: '%')),
      if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: draftErrorText(_err!))),
      if (!widget.readOnly) ...[
        AppPrimaryButton(label: t('حفظ', 'Save'), icon: Icons.check_rounded, busy: widget.busy, onPressed: widget.busy ? null : _submit),
        if (widget.onReset != null)
          TextButton.icon(onPressed: widget.busy ? null : widget.onReset, icon: const Icon(Icons.restart_alt_rounded), label: Text(t('إزالة كل التخصيصات', 'Remove all overrides'))),
      ],
    ]);
  }
}

// ── refunds ───────────────────────────────────────────────────────────────────────────────────────────────────

/// Opens the refund sheet of a payment. Returns true when something changed (the caller reloads its list) — also
/// when the sheet was swiped away after the server recorded a gateway-dashboard refund (409 `refund_external_recorded`).
/// [refundable] is the server's `refundable_amount` when it sends one; otherwise `amount − refunded`.
Future<bool> showRefundSheet(BuildContext context,
    {required int paymentId, double? amount, double refunded = 0, double? refundable, String? currency, bool? superAdmin, MoneyP8Api? api}) async {
  final sup = superAdmin ?? isSuperNow(context);
  var changed = false;
  final r = await showAppSheet<bool>(
      context,
      (_) => RefundSheet(
          paymentId: paymentId,
          remaining: refundable ?? (amount == null ? null : math.max(0, amount - refunded)),
          refunded: refunded,
          currency: currency,
          superAdmin: sup,
          api: api,
          onChanged: () => changed = true));
  return r == true || changed;
}

class RefundSheet extends StatefulWidget {
  const RefundSheet(
      {super.key, required this.paymentId, this.remaining, this.refunded = 0, this.currency, required this.superAdmin, this.api, this.onChanged});
  final int paymentId;
  final double? remaining;

  /// already refunded (succeeded refunds, partial included)
  final double refunded;
  final String? currency;
  final bool superAdmin;
  final MoneyP8Api? api;

  /// called when the server recorded something even though this request refunded nothing
  final VoidCallback? onChanged;

  @override
  State<RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<RefundSheet> {
  late final MoneyP8Api _api = widget.api ?? MoneyP8Api();
  late double? _remaining = widget.remaining;        // lowered when the server records a gateway-dashboard refund
  late double _refunded = widget.refunded;
  late RefundDraft _d = RefundDraft(remaining: _remaining);
  String? _sentSig;                                  // what the current idempotency key was used for
  bool _renewKey = false;
  final _amount = TextEditingController(), _reason = TextEditingController();
  bool _busy = false;
  String? _err;
  RefundExternalRecorded? _external;
  RefundOutcome? _out;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _d
      ..amount = _amount.text
      ..reason = _reason.text;
    final sig = '${_d.amount.trim()}|${_d.manual}|${_d.force}';
    if (_renewKey || (_sentSig != null && _sentSig != sig)) {   // another refund than the one the key was used for
      _d = RefundDraft(amount: _d.amount, reason: _d.reason, manual: _d.manual, force: _d.force, remaining: _remaining);
      _renewKey = false;
    }
    _d.remaining = _remaining;
    final e = _d.validate(superAdmin: widget.superAdmin);
    if (e != null) {
      setState(() => _err = draftErrorText(e));
      return;
    }
    final cur = widget.currency;
    final what = _d.amount.trim().isEmpty ? t('المبلغ المتبقي كله', 'everything that is left') : money(parseNum(_d.amount)!, cur);
    if (!await appConfirm(context, message: t('استرداد $what؟', 'Refund $what?'), danger: true)) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    _sentSig = sig;
    final r = await _api.refund(widget.paymentId, _d);
    if (!mounted) return;
    if (!r.ok && (r.code == 'refund_failed' || r.code == 'refund_gateway_failed')) _renewKey = true;   // a new attempt needs a new key
    // 409 refund_external_recorded: nothing was reserved, so the same key stays valid for a deliberate retry
    final ext = RefundExternalRecorded.from(r);
    if (ext != null) widget.onChanged?.call();
    setState(() {
      _busy = false;
      if (r.ok) {
        _out = RefundOutcome.fromJson(r.map);
        _external = null;
      } else if (ext != null) {
        _external = ext;
        _err = null;
        _refunded += ext.recorded;
        if (ext.remaining != null) {
          _remaining = ext.remaining;
        } else if (_remaining != null) {
          _remaining = math.max(0, _remaining! - ext.recorded);
        }
      } else {
        _err = feeCodeText(r.code, r.message);
      }
    });
  }

  Future<void> _reconcile() async {
    setState(() => _busy = true);
    final r = await _api.resolveRefund(_out!.id, 'reconcile');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _out = RefundOutcome.fromJson(r.map);
      } else {
        _err = feeCodeText(r.code, r.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = _out;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader('${t('استرداد الدفعة', 'Refund payment')} #${widget.paymentId}'),
        if (o != null) ...[
          AppBanner(
              icon: o.pending ? Icons.hourglass_top_rounded : (o.status == 'failed' ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
              color: o.pending ? c.warning : (o.status == 'failed' ? c.danger : c.success),
              text: '${refundStatusText(o.status)} — ${money(o.amount, o.currency)}'
                  '${o.pending && o.outcomeUnknown ? '\n${t('لم تؤكد البوابة النتيجة بعد، وستُسوّى تلقائياً. يمكنك التسوية الآن.', 'The gateway has not confirmed yet; it is reconciled automatically. You can reconcile now.')}' : ''}'),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err!)),
          const SizedBox(height: 12),
          if (o.pending)
            AppPrimaryButton(label: t('تسوية مع البوابة', 'Reconcile with the gateway'), icon: Icons.sync_rounded, busy: _busy, onPressed: _busy ? null : _reconcile),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t('تم', 'Done'))),
        ] else ...[
          if (_external != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppBanner(icon: Icons.info_outline_rounded, color: c.warning, text: _external!.text(widget.currency))),
          if (_refunded > 0.0001)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('${t('مسترد سابقاً', 'Already refunded')}: ${money(_refunded, widget.currency)}', style: appText(13, c: c.textMedium))),
          if (_remaining != null)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('${t('المتبقي القابل للاسترداد', 'Left to refund')}: ${money(_remaining!, widget.currency)}', style: appText(13, c: c.textMedium))),
          AppField(controller: _amount, label: t('المبلغ (فارغ = كل المتبقي)', 'Amount (empty = everything left)'), keyboard: const TextInputType.numberWithOptions(decimal: true)),
          AppField(controller: _reason, label: t('السبب', 'Reason'), maxLines: 2),
          if (widget.superAdmin) ...[
            AppSwitchTile(
                title: t('استرداد يدوي', 'Manual refund'),
                subtitle: t('تسجيل استرداد تم خارج النظام دون استدعاء البوابة', 'Record a refund made by hand — the gateway is not called'),
                value: _d.manual,
                onChanged: (v) => setState(() {
                      _d.manual = v;
                      if (!v) _d.force = false;
                    })),
            if (_d.manual)
              AppSwitchTile(
                  title: t('إجبار', 'Force'),
                  subtitle: t('لبوابة تسترد آلياً — يتطلب كتابة السبب', 'For a gateway that refunds by API — needs a reason'),
                  value: _d.force,
                  onChanged: (v) => setState(() => _d.force = v)),
          ],
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err!)),
          const SizedBox(height: 12),
          AppPrimaryButton(
              label: t('استرداد', 'Refund'),
              icon: Icons.undo_rounded,
              busy: _busy,
              onPressed: _busy || (_remaining != null && _remaining! <= 0.0001) ? null : _submit),
          if (_external != null) TextButton(onPressed: () => Navigator.pop(context, true), child: Text(t('إغلاق', 'Close'))),
        ],
      ]),
    );
  }
}

/// Resolves a pending refund by its id (reconcile with the gateway, or record how it ended).
Future<void> showRefundResolveSheet(BuildContext context, {MoneyP8Api? api}) =>
    showAppSheet<void>(context, (_) => RefundResolveSheet(api: api));

class RefundResolveSheet extends StatefulWidget {
  const RefundResolveSheet({super.key, this.api, this.initialRefundId});
  final MoneyP8Api? api;
  final int? initialRefundId;

  @override
  State<RefundResolveSheet> createState() => _RefundResolveSheetState();
}

class _RefundResolveSheetState extends State<RefundResolveSheet> {
  late final MoneyP8Api _api = widget.api ?? MoneyP8Api();
  late final _id = TextEditingController(text: widget.initialRefundId?.toString() ?? '');
  final _reason = TextEditingController();
  String _action = 'reconcile';
  bool _busy = false;
  String? _err;
  RefundOutcome? _out;

  @override
  void dispose() {
    _id.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final id = int.tryParse(_id.text.trim());
    if (id == null || id <= 0) return setState(() => _err = t('أدخل رقم الاسترداد', 'Enter the refund number'));
    if (_action != 'reconcile' && _reason.text.trim().isEmpty) return setState(() => _err = draftErrorText('reason_required'));
    setState(() {
      _busy = true;
      _err = null;
    });
    final r = await _api.resolveRefund(id, _action, reason: _reason.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _out = RefundOutcome.fromJson(r.map);
      } else {
        _err = feeCodeText(r.code, r.message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final actions = {
      'reconcile': t('تسوية مع البوابة', 'Reconcile with the gateway'),
      'succeeded': t('تسجيل أنه تم', 'Mark as succeeded'),
      'failed': t('تسجيل أنه فشل', 'Mark as failed'),
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AppSheetHeader(t('معالجة استرداد معلّق', 'Resolve a pending refund')),
        AppField(controller: _id, label: t('رقم الاسترداد', 'Refund number'), keyboard: TextInputType.number),
        AppDropdown<String>(
          value: _action,
          decoration: InputDecoration(labelText: t('الإجراء', 'Action')),
          items: [for (final e in actions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => setState(() => _action = v ?? 'reconcile'),
        ),
        const SizedBox(height: 12),
        AppField(controller: _reason, label: t('السبب', 'Reason') + (_action == 'reconcile' ? '' : ' *'), maxLines: 2),
        if (_out != null) AppBanner(icon: Icons.check_circle_outline_rounded, color: c.success, text: '#${_out!.id}: ${refundStatusText(_out!.status)} — ${money(_out!.amount, _out!.currency)}'),
        if (_err != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _err!),
        const SizedBox(height: 12),
        AppPrimaryButton(label: t('تنفيذ', 'Apply'), icon: Icons.done_all_rounded, busy: _busy, onPressed: _busy ? null : _submit),
      ]),
    );
  }
}

// ── ledger ────────────────────────────────────────────────────────────────────────────────────────────────────

class _LedgerTab extends StatefulWidget {
  const _LedgerTab({super.key});
  @override
  State<_LedgerTab> createState() => _LedgerTabState();
}

class _LedgerTabState extends State<_LedgerTab> {
  final _api = MoneyP8Api();
  final _cur = TextEditingController();
  LedgerQuery _q = const LedgerQuery();
  LedgerReport? _report;
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Timer? _curTimer;

  @override
  void dispose() {
    _curTimer?.cancel();
    _cur.dispose();
    super.dispose();
  }

  /// A complete code (three letters) or an emptied field applies after a short pause; Enter applies at once.
  void _currencyChanged(String v) {
    _curTimer?.cancel();
    final s = v.trim();
    if (s.isEmpty || s.length == 3) _curTimer = Timer(const Duration(milliseconds: 400), _run);
  }

  LedgerQuery _query({String? groupBy, DateTime? from, DateTime? to, bool clearFrom = false, bool clearTo = false}) => LedgerQuery(
      groupBy: groupBy ?? _q.groupBy,
      from: clearFrom ? null : (from ?? _q.from),
      to: clearTo ? null : (to ?? _q.to),
      currency: _cur.text.trim());

  Future<void> _run() async {
    _q = _query();
    final bad = _q.validate();
    if (bad != null) {
      setState(() => _error = bad == 'bad_range' ? t('تاريخ النهاية قبل البداية', 'The end date is before the start') : t('العملة من ثلاثة أحرف مثل SAR', 'A currency is three letters, e.g. SAR'));
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.ledger(_q);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        _report = LedgerReport.fromJson(r.map);
      } else {
        _error = r.unavailable ? t('التقرير غير متاح على هذا الخادم بعد', 'The report is not available on this server yet') : feeCodeText(r.code, r.message);
      }
    });
  }

  Future<void> _csv() async {
    setState(() => _saving = true);
    try {
      final bytes = await _api.ledgerCsv(_q);
      await p8SaveBytes(bytes, 'ledger-${_q.groupBy}.csv', mime: 'text/csv');
    } on ApiException catch (e) {
      appToast(e.message, error: true);
    } catch (e) {
      appToast('$e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: (from ? _q.from : _q.to) ?? now, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1));
    if (d == null || !mounted) return;
    setState(() => _q = _query(from: from ? d : null, to: from ? null : d));
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final g in ['teacher', 'org', 'month'])
          AppChoiceChip(label: ledgerGroupText(g), selected: _q.groupBy == g, onTap: () {
            setState(() => _q = _query(groupBy: g));
            _run();
          }),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.event_rounded, size: 18), label: Text('${t('من', 'From')}: ${_q.from == null ? '—' : AppTime.date(_q.from!.toUtc())}')),
        OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.event_rounded, size: 18), label: Text('${t('إلى', 'To')}: ${_q.to == null ? '—' : AppTime.date(_q.to!.toUtc())}')),
        if (_q.from != null || _q.to != null)
          TextButton(onPressed: () {
            setState(() => _q = _query(clearFrom: true, clearTo: true));
            _run();
          }, child: Text(t('مسح التواريخ', 'Clear dates'))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
            child: AppField(
                controller: _cur,
                label: t('العملة (اختياري)', 'Currency (optional)'),
                ltr: true,
                onChanged: _currencyChanged,
                onSubmitted: (_) {
                  _curTimer?.cancel();
                  _run();
                })),
        const SizedBox(width: 8),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: IconButton.filled(tooltip: t('تطبيق', 'Apply'), onPressed: _run, icon: const Icon(Icons.check_rounded))),
        const SizedBox(width: 4),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: IconButton.outlined(tooltip: 'CSV', onPressed: _saving ? null : _csv, icon: const Icon(Icons.download_rounded))),
      ]),
      if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      if (_loading) const SizedBox(height: 240, child: AppListSkeleton(items: 3, withAvatar: false)),
      if (!_loading && _report != null) LedgerReportView(report: _report!),
    ]);
  }
}

/// The report: an integrity banner, the totals per currency, then the rows (a horizontally scrollable table).
class LedgerReportView extends StatelessWidget {
  const LedgerReportView({super.key, required this.report});
  final LedgerReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (report.rows.isEmpty) return AppEmpty(icon: Icons.table_chart_outlined, title: t('لا حركات في هذه الفترة', 'No entries in this period'));
    String fmt(double v) => v.toStringAsFixed(2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppBanner(
          icon: report.balanced ? Icons.verified_outlined : Icons.warning_amber_rounded,
          color: report.balanced ? c.success : c.danger,
          text: report.balanced
              ? t('الدفتر متوازن (${report.groups} عملية)', 'The ledger balances (${report.groups} transactions)')
              : t('${report.unbalanced} عملية غير متوازنة — راجع المحاسبة', '${report.unbalanced} unbalanced transactions — review the books')),
      for (final e in report.totals.entries)
        AppCard(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${t('الإجمالي', 'Total')} · ${e.key}', style: appText(14, w: FontWeight.w800, c: c.textDark)),
            const SizedBox(height: 8),
            Wrap(spacing: 14, runSpacing: 6, children: [
              for (final m in ledgerMetrics)
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ledgerMetricText(m), style: appText(11, c: c.textLight)),
                  Text(fmt(e.value[m] ?? 0), style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                ]),
            ]),
          ]),
        ),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth >= Breakpoints.mobile) return _table(context, fmt);
        // phone: one card per row (the label, its currency, then label / value lines), never a sideways-scrolling table
        return Column(children: [
          for (final r in report.rows)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: AppCard(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: Text(r.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
                    AppSpace.gapXs,
                    Text(r.currency, style: AppType.meta(context)),
                  ]),
                  AppSpace.gapXs,
                  for (final m in ledgerMetrics)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpace.xxs),
                      child: Row(children: [
                        Expanded(child: Text(ledgerMetricText(m), style: AppType.meta(context))),
                        Text(fmt(r.values[m] ?? 0), style: AppType.bodyStrong(context), textDirection: TextDirection.ltr),
                      ]),
                    ),
                ]),
              ),
            ),
        ]);
      }),
    ]);
  }

  Widget _table(BuildContext context, String Function(double) fmt) {
    return Column(children: [
      AppCard(
        padding: const EdgeInsets.all(6),
        child: AppHScroll(
          child: DataTable(
            columnSpacing: 18,
            columns: [
              DataColumn(label: Text(ledgerGroupText(report.groupBy))),
              DataColumn(label: Text(t('العملة', 'Currency'))),
              for (final m in ledgerMetrics) DataColumn(label: Text(ledgerMetricText(m)), numeric: true),
            ],
            rows: [
              for (final r in report.rows)
                DataRow(cells: [
                  DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(r.label, maxLines: 1, overflow: TextOverflow.ellipsis))),
                  DataCell(Text(r.currency)),
                  for (final m in ledgerMetrics) DataCell(Text(fmt(r.values[m] ?? 0))),
                ]),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// Used by tests and callers that show when something happened.
String p8When(String? iso) => shortDateTime(asStrOrNull(iso));
