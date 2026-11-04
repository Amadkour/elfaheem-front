/// A student's access to ONE course, as the server decides it (D-210), and the texts that explain a refusal.
///
/// `CourseAccess` mirrors `CourseAccess.to_dict()` of the backend. Every part is optional: an older server sends no
/// `access` block at all (the app then trusts `is_enrolled`), and an unknown `reason` / `status` is kept as the raw
/// string and treated as "denied for an unknown reason" rather than crashing.
library;

import '../config/app_config.dart';
import 'api_client.dart';
import 'app_time.dart';

/// Reasons that stop a downloaded copy from playing: the plan ended or the access was withdrawn.
const Set<String> kOfflineBlockingReasons = {'expired', 'cancelled', 'refunded'};

class CourseAccess {
  const CourseAccess({
    required this.hasAccess,
    required this.reason,
    this.courseId,
    this.source,
    this.plan,
    this.startsAt,
    this.expiresAt,
    this.daysLeft,
    this.status,
    this.flags = const [],
  });

  final bool hasAccess;

  /// `enrolled` `staff` (granted) · `not_enrolled` `expired` `cancelled` `refunded` `payment_pending`
  /// `payment_failed` `org_subscription_required` (denied) · anything else the server adds later.
  final String reason;
  final int? courseId;
  final String? source;
  final String? plan;
  final DateTime? startsAt;

  /// UTC; null = no end date (lifetime / free).
  final DateTime? expiresAt;
  final int? daysLeft;
  final String? status;
  final List<String> flags;

  bool get isExpired => reason == 'expired';
  bool get isPending => reason == 'payment_pending';

  /// The plan ends within a week (and has not ended yet).
  bool get expiringSoon =>
      hasAccess && expiresAt != null && (status == 'expiring_soon' || (daysLeft != null && daysLeft! >= 0 && daysLeft! < 7));

  /// Parses a server block; null for anything that is not a map with a reason.
  static CourseAccess? tryParse(Object? j) {
    if (j is! Map) return null;
    final m = j.map((k, v) => MapEntry('$k', v));
    final reason = m['reason'];
    if (reason is! String || reason.isEmpty) return null;
    final flags = m['flags'];
    return CourseAccess(
      hasAccess: m['has_access'] == true,
      reason: reason,
      courseId: _int(m['course_id']),
      source: m['source'] is String ? m['source'] as String : null,
      plan: m['plan'] is String ? m['plan'] as String : null,
      startsAt: parseUtc(m['starts_at']),
      expiresAt: parseUtc(m['expires_at']),
      daysLeft: _int(m['days_left']),
      status: m['status'] is String ? m['status'] as String : null,
      flags: flags is List ? [for (final f in flags) '$f'] : const [],
    );
  }

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
}

/// An ISO instant from the server as UTC (no offset means UTC), or null.
DateTime? parseUtc(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final s = v.trim();
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// What to tell the student about [reason]; [expiresAt] fills the end date of an expired plan.
String accessReasonTextFor(String reason, {DateTime? expiresAt}) {
  switch (reason) {
    case 'expired':
      return expiresAt == null
          ? _t('انتهت خطتك — جدّد اشتراكك لتواصل المشاهدة', 'Your plan has ended — renew to keep watching')
          : _t('انتهت خطتك في ${AppTime.date(expiresAt)} — جدّد اشتراكك لتواصل المشاهدة',
              'Your plan ended on ${AppTime.date(expiresAt)} — renew to keep watching');
    case 'payment_pending':
      return _t('دفعتك قيد المراجعة — سيُفتح الكورس فور تأكيدها', 'Your payment is being reviewed — the course opens as soon as it is confirmed');
    case 'payment_failed':
      return _t('لم تكتمل عملية الدفع — حاول مرة أخرى أو تواصل مع الدعم', 'The payment did not go through — try again or contact support');
    case 'cancelled':
      return _t('تم إيقاف وصولك إلى هذا الكورس — تواصل مع الدعم', 'Your access to this course was stopped — contact support');
    case 'refunded':
      return _t('تم استرداد ثمن هذا الكورس فلم يعد متاحاً لك — تواصل مع الدعم إن كان ذلك بالخطأ',
          'This course was refunded, so it is no longer open to you — contact support if that is a mistake');
    case 'org_subscription_required':
      return _t('اشتراك المؤسسة غير مفعّل — تواصل مع إدارة المؤسسة', "The organization's subscription is not active — contact the organization");
    case 'not_enrolled':
      return _t('اشترك في الكورس لتفتح هذا المحتوى', 'Subscribe to the course to open this content');
    default:
      return _t('لا تملك صلاحية الوصول إلى هذا الكورس حالياً', 'You do not have access to this course right now');
  }
}

String accessReasonText(CourseAccess access) => accessReasonTextFor(access.reason, expiresAt: access.expiresAt);

/// The text of a 403 `course_access_denied` / 402 `SUBSCRIPTION_REQUIRED` error, or null when [e] is neither.
String? accessDeniedText(ApiException e) {
  final code = e.code;
  if (code != 'course_access_denied' && code != 'SUBSCRIPTION_REQUIRED') return null;
  final d = ApiException.asMap(e.body)?['detail'];
  final Map detail = d is Map ? d : const {};
  final r = detail['reason'];
  final reason = r is String && r.isNotEmpty ? r : (code == 'SUBSCRIPTION_REQUIRED' ? 'org_subscription_required' : 'not_enrolled');
  return accessReasonTextFor(reason, expiresAt: parseUtc(detail['expires_at']));
}

/// Reads access from the server.
class CourseAccessApi {
  CourseAccessApi({ApiClient? client}) : _client = client;
  final ApiClient? _client;
  ApiClient get _api => _client ?? ApiClient();

  /// `GET /api/v1/me/courses/{id}/access`; null when the answer is not an access block.
  /// Throws [ApiException] on a network / server error so the caller can fail open.
  Future<CourseAccess?> one(int courseId) async {
    final r = await _api.get('/api/v1/me/courses/$courseId/access');
    return CourseAccess.tryParse(r);
  }

  /// `GET /api/v1/me/courses/access?ids=1,2,3` (max 200 per call) → course id → access.
  Future<Map<int, CourseAccess>> many(Iterable<int> ids) async {
    final out = <int, CourseAccess>{};
    final list = ids.toSet().toList();
    for (var i = 0; i < list.length; i += 200) {
      final chunk = list.sublist(i, i + 200 > list.length ? list.length : i + 200);
      final r = await _api.get('/api/v1/me/courses/access', queryParams: {'ids': chunk.join(',')});
      final items = r is Map ? r['items'] : null;
      if (items is! Map) continue;
      items.forEach((k, v) {
        final id = int.tryParse('$k');
        final a = CourseAccess.tryParse(v);
        if (id != null && a != null) out[id] = a;
      });
    }
    return out;
  }
}

// ── Pure decisions (no network, so they are unit-tested) ─────────────────────

/// How the course page's bottom bar / side card behaves.
enum EnrollBarMode { subscribe, renew, pending, support, hidden }

/// [enrolled] = the course's `is_enrolled`; [access] = its `access` block (null on an older server).
EnrollBarMode enrollBarMode({required bool enrolled, CourseAccess? access}) {
  if (enrolled) return EnrollBarMode.hidden;
  switch (access?.reason) {
    case 'expired':
      return EnrollBarMode.renew;
    case 'payment_pending':
      return EnrollBarMode.pending;
    case 'cancelled':
    case 'refunded':
      return EnrollBarMode.support;
    default:
      return EnrollBarMode.subscribe;
  }
}

/// Why a locked session is locked.
enum LockedKind { finishPrevious, blockingExam, subscribe, renew, pending, support }

/// [enrolled] true → the lock comes from progress (or an exam); otherwise the access reason decides.
LockedKind lockedSessionKind({required bool enrolled, required bool hasBlockingExam, CourseAccess? access}) {
  if (enrolled) return hasBlockingExam ? LockedKind.blockingExam : LockedKind.finishPrevious;
  switch (enrollBarMode(enrolled: false, access: access)) {
    case EnrollBarMode.renew:
      return LockedKind.renew;
    case EnrollBarMode.pending:
      return LockedKind.pending;
    case EnrollBarMode.support:
      return LockedKind.support;
    default:
      return LockedKind.subscribe;
  }
}

/// A downloaded copy's verdict.
enum OfflineVerdict { allow, refuse }

/// Online and the server DEFINITELY answered "no access" for a blocking reason → refuse. Everything else (offline,
/// network error / timeout → [access] null, a granted answer, an unknown reason, a course id that is unknown)
/// → allow; the 30-day rule of the copy itself still applies offline.
OfflineVerdict offlineVerdict({required bool online, required bool courseKnown, CourseAccess? access}) {
  if (!online || !courseKnown || access == null) return OfflineVerdict.allow;
  if (!access.hasAccess && kOfflineBlockingReasons.contains(access.reason)) return OfflineVerdict.refuse;
  return OfflineVerdict.allow;
}

/// The sentence for a locked session. [previousName] = the session right before it ([finishPrevious]);
/// [examName] = the blocking exam ([blockingExam], keeps its own message).
String lockedSessionMessage(LockedKind kind, {String? previousName, String? examName, CourseAccess? access}) {
  switch (kind) {
    case LockedKind.blockingExam:
      return '${'session_exam_must_pass'.tr}${examName == null || examName.isEmpty ? '' : ': $examName'}';
    case LockedKind.finishPrevious:
      return previousName == null || previousName.trim().isEmpty
          ? 'session_locked_finish_previous'.tr
          : 'session_locked_finish_first'.tr.replaceAll('{name}', previousName.trim());
    case LockedKind.renew:
    case LockedKind.pending:
    case LockedKind.support:
      return access == null ? 'session_locked_subscribe'.tr : accessReasonText(access);
    case LockedKind.subscribe:
      return 'session_locked_subscribe'.tr;
  }
}
