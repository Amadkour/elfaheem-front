// lib/features/org/org_sharing.dart — cross-organization sharing + graduate verification: the pure part.
//
// Server: routers/organization/org_sharing_router.py (FLUTTER_API_CHANGES.md, phase 3). What lives here is what
// gets unit-tested without a session: labels, state texts, the share draft that builds the POST / PUT body, the
// identifier parser for the verification box and the result summary. Screens are in org_sharing_pages.dart.
library;

import 'package:flutter/foundation.dart' show setEquals;

import '../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import 'org_v3.dart' show orgParseUtc, orgUtc;

const List<String> shareMethods = ['invite', 'auto', 'request', 'public'];
const List<String> shareResourceTypes = ['department', 'program', 'course', 'graduates'];

String shareMethodLabel(String m) => switch (m) {
      'invite' => t('كود دعوة', 'Invite code'),
      'auto' => t('انضمام تلقائي', 'Auto-join'),
      'request' => t('طلب بموافقة', 'Request + approval'),
      'public' => t('عام للجميع', 'Public'),
      _ => m,
    };

String shareMethodHint(String m) => switch (m) {
      'invite' => t('تعطي الكود للمؤسسة التي تريدها؛ يظهر مرة واحدة ويمكن تجديده', 'You hand the code to the organization you choose; shown once, regeneratable'),
      'auto' => t('أي مؤسسة تطلب الوصول تحصل عليه فوراً', 'Any organization that asks gets access at once'),
      'request' => t('المؤسسة تطلب، وأنتم توافقون أو ترفضون', 'An organization asks; your staff approve or reject'),
      'public' => t('مرئي لكل المؤسسات وقابل للقراءة بدون طلب', 'Visible to every organization and readable without a grant'),
      _ => '',
    };

String shareResourceLabel(String type) => switch (type) {
      'department' => t('قسم / إدارة', 'Department'),
      'program' => t('برنامج أكاديمي', 'Academic program'),
      'course' => t('مقرر', 'Course'),
      'graduates' => t('التحقق من الخريجين', 'Graduate verification'),
      _ => type,
    };

String shareStateText(String state) => switch (state) {
      'active' => t('نشطة', 'Active'),
      'revoked' => t('ملغاة', 'Revoked'),
      'expired' => t('منتهية', 'Expired'),
      'not_yet_valid' => t('لم تبدأ بعد', 'Not started yet'),
      _ => state,
    };

String grantStateText(String state) => switch (state) {
      'active' => t('وصول نشط', 'Active access'),
      'pending' => t('بانتظار الموافقة', 'Awaiting approval'),
      'rejected' => t('مرفوض', 'Rejected'),
      'revoked' => t('مُنهى', 'Revoked'),
      'expired' => t('منتهي', 'Expired'),
      'share_revoked' => t('أُلغيت المشاركة', 'Share revoked'),
      'share_expired' => t('انتهت المشاركة', 'Share expired'),
      'share_not_yet_valid' => t('المشاركة لم تبدأ', 'Share not started'),
      _ => state,
    };

String grantViaText(String via) => switch (via) {
      'invite' => t('بكود دعوة', 'by invite code'),
      'auto' => t('تلقائياً', 'automatically'),
      'request' => t('بطلب', 'by request'),
      'public' => t('عام', 'public'),
      _ => via,
    };

/// The share title to show: the server's title, else the resource name, else the type.
String shareTitleOf(Map<String, dynamic> share) {
  final title = '${share['title'] ?? ''}'.trim();
  if (title.isNotEmpty) return title;
  final res = asMap(share['resource']);
  final name = t('${res['name_ar'] ?? res['title_ar'] ?? ''}', '${res['name_en'] ?? res['title_en'] ?? ''}').trim();
  return name.isNotEmpty ? name : shareResourceLabel('${share['resource_type'] ?? ''}');
}

String orgNameOfBrief(Map<String, dynamic> org) {
  final n = t('${org['name_ar'] ?? ''}', '${org['name_en'] ?? ''}').trim();
  if (n.isNotEmpty) return n;
  return '${org['name_en'] ?? org['name_ar'] ?? '#${org['id'] ?? ''}'}';
}

/// What the grantor fills in for a share. `toBody()` is the POST body; `patch(original)` the PUT body (only the
/// changed fields; the server merges).
class ShareDraft {
  ShareDraft({
    this.resourceType = 'department',
    this.resourceId,
    this.title = '',
    this.description = '',
    Set<String>? methods,
    this.year = false,
    this.startsAt,
    this.expiresAt,
    this.maxGrantees,
  }) : methods = methods ?? {'request'};

  factory ShareDraft.fromShare(Map<String, dynamic> s) => ShareDraft(
        resourceType: '${s['resource_type'] ?? 'department'}',
        resourceId: s['resource_id'] == null ? null : asInt(s['resource_id']),
        title: '${s['title'] ?? ''}',
        description: '${s['description'] ?? ''}',
        methods: (s['methods'] as List? ?? const []).map((e) => '$e').toSet(),
        year: asMap(s['scope'])['year'] == true,
        startsAt: _date(s['starts_at']),
        expiresAt: _date(s['expires_at']),
        maxGrantees: s['max_grantees'] == null ? null : asInt(s['max_grantees']),
      );

  String resourceType;
  int? resourceId;
  String title;
  String description;
  Set<String> methods;
  bool year;
  DateTime? startsAt;
  DateTime? expiresAt;
  int? maxGrantees;

  bool get needsResource => resourceType != 'graduates';
  bool get isGraduates => resourceType == 'graduates';

  /// The first problem, in the user's language, or null when the draft can be sent.
  String? validate() {
    if (methods.isEmpty) return t('اختر طريقة وصول واحدة على الأقل', 'Choose at least one access method');
    if (needsResource && resourceId == null) return t('اختر العنصر الذي تريد مشاركته', 'Choose what to share');
    if (expiresAt != null && !expiresAt!.isAfter(DateTime.now())) return t('تاريخ الانتهاء في الماضي', 'The expiry date is in the past');
    if (startsAt != null && expiresAt != null && !expiresAt!.isAfter(startsAt!)) {
      return t('نهاية الصلاحية يجب أن تكون بعد بدايتها', 'The end must be after the start');
    }
    if (maxGrantees != null && maxGrantees! < 1) return t('الحد الأقصى للمؤسسات 1 على الأقل', 'Max organizations must be 1 or more');
    return null;
  }

  Map<String, dynamic> toBody() => {
        'resource_type': resourceType,
        if (needsResource) 'resource_id': resourceId,
        if (title.trim().isNotEmpty) 'title': title.trim(),
        if (description.trim().isNotEmpty) 'description': description.trim(),
        'methods': shareMethods.where(methods.contains).toList(),
        'scope': isGraduates ? {'year': year} : <String, dynamic>{},
        'starts_at': orgUtc(startsAt),
        'expires_at': orgUtc(shareExpiryInstant(expiresAt)),
        'max_grantees': maxGrantees,
      };

  /// Only what changed against the share the draft was made from.
  Map<String, dynamic> patch(Map<String, dynamic> original) {
    final o = ShareDraft.fromShare(original);
    final out = <String, dynamic>{};
    if (title.trim() != o.title.trim()) out['title'] = title.trim();
    if (description.trim() != o.description.trim()) out['description'] = description.trim();
    if (!setEquals(methods, o.methods)) {
      out['methods'] = shareMethods.where(methods.contains).toList();
    }
    if (isGraduates && year != o.year) out['scope'] = {'year': year};
    if (startsAt != o.startsAt) out['starts_at'] = orgUtc(startsAt);
    if (shareExpiryInstant(expiresAt) != shareExpiryInstant(o.expiresAt)) out['expires_at'] = orgUtc(shareExpiryInstant(expiresAt));
    if (maxGrantees != o.maxGrantees) out['max_grantees'] = maxGrantees;
    return out;
  }

  /// The server stores naive UTC: read it as such (a plain parse would take it for local time and shift every date).
  static DateTime? _date(Object? v) => orgParseUtc(v);
}

/// A share picked to end on a DAY ends at the end of that local day, not at its first second (which the server
/// would read as "already expired" for most of the day). A value that already carries a time of day is kept.
DateTime? shareExpiryInstant(DateTime? d) {
  if (d == null) return null;
  if (d.hour == 0 && d.minute == 0 && d.second == 0) return DateTime(d.year, d.month, d.day, 23, 59, 59);
  return d;
}

/// One identifier per line (or comma / semicolon separated) → verification queries. An `@` makes an e-mail, a
/// mostly-digit value starting with `+`, `00` or `0` a phone, anything else a student code. `ref` is the line number.
List<Map<String, dynamic>> parseIdentifiers(String text) {
  final out = <Map<String, dynamic>>[];
  var n = 0;
  for (final raw in text.split(RegExp(r'[\n,;]'))) {
    final v = raw.trim();
    if (v.isEmpty) continue;
    n++;
    final digits = v.replaceAll(RegExp(r'[^0-9٠-٩]'), '').length;
    final q = <String, dynamic>{'ref': '$n'};
    if (v.contains('@')) {
      q['email'] = v.toLowerCase();
    } else if (digits >= 8 && (v.startsWith('+') || v.startsWith('0') || v.startsWith('٠'))) {
      q['phone'] = v;
    } else {
      q['student_code'] = v;
    }
    out.add(q);
  }
  return out;
}

/// `(yes, no, unreadable)` of a verification reply.
(int, int, int) verificationSummary(Map<String, dynamic> result) {
  var yes = 0, no = 0, bad = 0;
  for (final r in asMapList(result['results'])) {
    final g = r['graduate'];
    if (g == true) {
      yes++;
    } else if (g == false) {
      no++;
    } else {
      bad++;
    }
  }
  return (yes, no, bad);
}

/// Text of one verification result line.
String verificationLine(Map<String, dynamic> r, {required bool yearIncluded}) {
  final g = r['graduate'];
  if (g == null) return t('لا يوجد معرّف', 'No identifier');
  if (g != true) return t('ليس خريجاً', 'Not a graduate');
  final y = r['year'];
  return yearIncluded && y != null ? t('خريج — $y', 'Graduate — $y') : t('خريج', 'Graduate');
}
