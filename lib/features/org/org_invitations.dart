// lib/features/org/org_invitations.dart — invitations by e-mail / phone (contract C1, kill switch `org.invitations`).
//
// Pure parts and the API; the screens are in org_invitations_pages.dart.
//   parseContacts(raw, channel)   paste many contacts → valid (normalised, de-duplicated) / invalid / over the limit
//   OrgInvitation                 one invitation row (staff list, create response, the invitee's own list)
//   InviteResult                  POST …/invitations → created + skipped (with the reason code)
//   InviteLookup                  GET /public/invitations/{token} (no sign-in needed)
//   OrgInvitationsApi             every route of the contract, through orgCall (never throws)
//
// Staff routes live under `/api/v1/org/orgs/{org}/invitations`, the invitee's under `/api/v1/org/public/…`. Times
// are naive UTC on the server: read with orgParseUtc, show with AppTime.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_badges.dart' show AppTone;

import '../admin/admin_common.dart' show t, asMap, asMapList, asInt;
import 'org_providers.dart' show orgBase;
import 'org_v3.dart';

/// The kill switch of the whole feature (super admin, `feature_catalog.py`).
const invitationsFeatureKey = 'org.invitations';

/// The contract's limit of contacts per request.
const maxInviteContacts = 200;

const inviteChannels = ['email', 'phone'];
const inviteRoles = ['student', 'teacher', 'staff'];
const inviteExpiryDays = [3, 7, 14, 30, 60];
const inviteDefaultExpiryDays = 14;

/// The invitation statuses the staff list can filter by.
const inviteStatuses = ['pending', 'accepted', 'declined', 'cancelled', 'expired', 'all'];

// ═════════════════════════════════════════════════════════════════════════════
//  Contacts
// ═════════════════════════════════════════════════════════════════════════════

final _emailRe = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");

/// A lower-cased e-mail address, or null when it isn't one.
String? normalizeEmail(String raw) {
  final s = raw.trim().toLowerCase();
  return s.length <= 254 && _emailRe.hasMatch(s) ? s : null;
}

/// A phone number as `+digits` (spaces, dashes and brackets dropped, `00` read as `+`), or null when it has fewer
/// than 7 or more than 15 digits. A number without a country code stays without one: the server knows the platform's
/// default region.
String? normalizePhone(String raw) {
  var s = raw.trim().replaceAll(RegExp(r'[\s\-().\u200e\u200f]'), '');
  s = _latinDigits(s);
  if (s.startsWith('00')) s = '+${s.substring(2)}';
  final plus = s.startsWith('+');
  final digits = plus ? s.substring(1) : s;
  if (!RegExp(r'^\d{7,15}$').hasMatch(digits)) return null;
  return plus ? '+$digits' : digits;
}

String _latinDigits(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    b.writeCharCode(r >= 0x0660 && r <= 0x0669 ? r - 0x0660 + 0x30 : r);
  }
  return b.toString();
}

/// What a pasted block of contacts holds.
class ContactParse {
  const ContactParse(this.valid, this.invalid, this.duplicates, this.overLimit);

  /// Normalised, first-seen order, no repeats.
  final List<String> valid;

  /// The tokens that are not a contact of the chosen channel, as typed.
  final List<String> invalid;

  /// How many valid entries repeated an earlier one.
  final int duplicates;

  /// How many valid entries are past [maxInviteContacts] (left out of [valid]).
  final int overLimit;

  bool get isEmpty => valid.isEmpty && invalid.isEmpty;
}

/// Splits [raw] on new lines, commas, semicolons, Arabic commas and spaces, drops `<…>` / quotes around an address
/// (`Ahmed <a@b.com>` gives a@b.com) and sorts every piece into valid / invalid for [channel] ('email' | 'phone').
ContactParse parseContacts(String raw, String channel) {
  final valid = <String>[];
  final invalid = <String>[];
  final seen = <String>{};
  var dup = 0, over = 0;
  // "Ahmed Ali <a@b.com>" keeps only the address
  if (channel != 'phone') raw = raw.replaceAllMapped(RegExp(r'[^,;\n\r<>]*<([^<>]+)>'), (m) => m[1]!);
  final pieces = channel == 'phone'
      // a phone number may hold spaces ("0100 123 4567"): split on lines and separators only
      ? raw.split(RegExp(r'[\n\r,;،؛\t]+'))
      : raw.split(RegExp(r'[\s,;،؛]+'));
  for (var p in pieces) {
    p = p.trim().replaceAll(RegExp('^[<"\'\\[(]+|[>"\'\\])]+\$'), '');
    if (p.isEmpty) continue;
    final n = channel == 'phone' ? normalizePhone(p) : normalizeEmail(p);
    if (n == null) {
      invalid.add(p);
    } else if (!seen.add(n)) {
      dup++;
    } else if (valid.length >= maxInviteContacts) {
      over++;
    } else {
      valid.add(n);
    }
  }
  return ContactParse(valid, invalid, dup, over);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

String inviteRoleLabel(String r) => switch (r) {
      'student' => t('طالب', 'Student'),
      'teacher' => t('مدرس', 'Teacher'),
      'staff' => t('فريق العمل (بلا صلاحيات بعد)', 'Staff (no permissions yet)'),
      _ => r,
    };

/// The role an invitation gives (`member_role` of the C7 contract, else the invitation vocabulary of [inviteRoleLabel]).
String inviteMemberRoleLabel(String memberRole, String fallbackRole) => switch (memberRole) {
      'student' => t('طالب', 'Student'),
      'teacher' => t('مدرس', 'Teacher'),
      'teacher_assistant' => t('مساعد مدرس', 'Teaching assistant'),
      'admin_assistant' => t('مساعد إداري', 'Administrative assistant'),
      'org_admin' => t('مدير مؤسسة', 'Organization admin'),
      'staff' => t('فريق العمل', 'Staff'),
      '' => inviteRoleLabel(fallbackRole),
      _ => memberRole,
    };

/// Where an invitation came from, for the admin's list.
String inviteSourceLabel(String source) => switch (source) {
      'manual' => t('أضافه مدير', 'Added by an admin'),
      'excel' => t('ملف Excel', 'Excel sheet'),
      _ => t('رابط دعوة', 'Invitation link'),
    };

String inviteChannelLabel(String c) => c == 'phone' ? t('رقم هاتف', 'Phone number') : t('بريد إلكتروني', 'E-mail');

String inviteStatusLabel(String s) => switch (s) {
      'pending' => t('بانتظار الرد', 'Pending'),
      'accepted' => t('قُبلت', 'Accepted'),
      'declined' => t('رُفضت', 'Declined'),
      'cancelled' => t('أُلغيت', 'Cancelled'),
      'expired' => t('انتهت', 'Expired'),
      'all' => t('الكل', 'All'),
      _ => s,
    };

AppTone inviteStatusTone(String s) => switch (s) {
      'pending' => AppTone.warning,
      'accepted' => AppTone.success,
      'declined' || 'cancelled' => AppTone.danger,
      _ => AppTone.neutral,
    };

/// Why a contact was skipped when inviting (`skipped[].code`).
String inviteSkipText(String code) => switch (code) {
      'already_member' => t('عضو بالفعل في المؤسسة', 'Already a member'),
      'already_invited' => t('لديه دعوة قائمة بانتظار الرد', 'Already has a pending invitation'),
      'invalid_contact' => t('بريد أو رقم غير صالح', 'Not a valid e-mail or phone number'),
      _ => code,
    };

/// "Expires 12 Nov 2026" / "Expired 12 Nov 2026" in the platform or organization time zone.
String inviteExpiryText(DateTime? expiresAt, {DateTime? now}) {
  if (expiresAt == null) return t('بلا انتهاء', 'No expiry');
  final d = AppTime.date(expiresAt.toUtc());
  return (now ?? DateTime.now()).isAfter(expiresAt) ? t('انتهت في $d', 'Expired $d') : t('تنتهي في $d', 'Expires $d');
}

// ═════════════════════════════════════════════════════════════════════════════
//  Models
// ═════════════════════════════════════════════════════════════════════════════

class OrgInvitation {
  const OrgInvitation({
    required this.id,
    required this.channel,
    required this.contact,
    required this.role,
    required this.status,
    this.deptId,
    this.programId,
    this.createdAt,
    this.expiresAt,
    this.acceptedAt,
    this.invitedBy = '',
    this.sentCount = 0,
    this.lastSentAt,
    this.link,
    this.source = 'invite',
    this.memberRole = '',
  });

  final int id;
  final String channel, contact, role, status;

  /// How it was made (C7): `invite` (link / e-mail / phone) · `manual` (added by an admin) · `excel` (a sheet).
  final String source;

  /// The role it gives on accept (`member_role`: student · teacher · teacher_assistant · …); empty on an older server.
  final String memberRole;
  final int? deptId, programId;
  final DateTime? createdAt, expiresAt, acceptedAt, lastSentAt;
  final String invitedBy;
  final int sentCount;

  /// `https://nextbrain.site/i/<token>`: only the create response carries it (the server keeps a hash).
  final String? link;

  factory OrgInvitation.fromJson(Map<String, dynamic> j) {
    int? n(dynamic v) => v == null ? null : int.tryParse('$v');
    return OrgInvitation(
      id: n(j['id']) ?? 0,
      channel: '${j['channel'] ?? 'email'}',
      contact: '${j['contact'] ?? ''}',
      role: '${j['role'] ?? 'student'}',
      status: '${j['status'] ?? 'pending'}',
      deptId: n(j['dept_id']),
      programId: n(j['program_id']),
      createdAt: orgParseUtc(j['created_at']),
      expiresAt: orgParseUtc(j['expires_at']),
      acceptedAt: orgParseUtc(j['accepted_at']),
      invitedBy: j['invited_by'] is Map ? '${(j['invited_by'] as Map)['name'] ?? ''}' : '',
      sentCount: n(j['sent_count']) ?? 0,
      lastSentAt: orgParseUtc(j['last_sent_at']),
      link: j['link'] == null ? null : '${j['link']}',
      source: '${j['source'] ?? 'invite'}',
      memberRole: '${j['member_role'] ?? ''}',
    );
  }

  /// A pending row whose date has passed reads as expired even before the server's sweep marks it.
  String effectiveStatus({DateTime? now}) =>
      status == 'pending' && expiresAt != null && (now ?? DateTime.now()).isAfter(expiresAt!) ? 'expired' : status;

  /// May still be resent / cancelled.
  bool canAct({DateTime? now}) => effectiveStatus(now: now) == 'pending';
}

class InviteSkip {
  const InviteSkip(this.contact, this.code);
  final String contact, code;
}

/// The answer of `POST …/invitations`.
class InviteResult {
  const InviteResult(this.created, this.skipped);
  final List<OrgInvitation> created;
  final List<InviteSkip> skipped;

  factory InviteResult.fromJson(Map<String, dynamic> j) => InviteResult(
        [for (final x in asMapList(j['created'])) OrgInvitation.fromJson(x)],
        [for (final x in asMapList(j['skipped'])) InviteSkip('${x['contact'] ?? ''}', '${x['code'] ?? ''}')],
      );

  /// One line per created link ("contact: link"), for Copy all.
  String get allLinks => [for (final i in created) if (i.link != null) '${i.contact}: ${i.link}'].join('\n');
}

/// What the invitee sees before answering (`GET /public/invitations/{token}`).
class InviteLookup {
  const InviteLookup({
    required this.orgId,
    required this.nameAr,
    required this.nameEn,
    required this.role,
    required this.status,
    this.logoUrl,
    this.expiresAt,
    this.contactMasked = '',
  });

  final int orgId;
  final String nameAr, nameEn, role, status, contactMasked;
  final String? logoUrl;
  final DateTime? expiresAt;

  String get orgName => t(nameAr.isNotEmpty ? nameAr : nameEn, nameEn.isNotEmpty ? nameEn : nameAr);

  bool get pending => status == 'pending';

  factory InviteLookup.fromJson(Map<String, dynamic> j) {
    final o = asMap(j['org']);
    return InviteLookup(
      orgId: asInt(o['id']),
      nameAr: '${o['name_ar'] ?? ''}',
      nameEn: '${o['name_en'] ?? ''}',
      logoUrl: o['logo_url'] as String?,
      role: '${j['role'] ?? 'student'}',
      status: '${j['status'] ?? 'pending'}',
      expiresAt: orgParseUtc(j['expires_at']),
      contactMasked: '${j['contact_masked'] ?? ''}',
    );
  }
}

/// A pending invitation addressed to me (`GET /public/me/invitations`).
class MyInvitation {
  const MyInvitation({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.role,
    this.logoUrl,
    this.expiresAt,
    this.memberRole = '',
    this.source = 'invite',
    this.message = '',
    this.createdAt,
    this.invitedByName = '',
  });

  final int id, orgId;
  final String orgName, role, memberRole, source, message, invitedByName;
  final String? logoUrl;
  final DateTime? expiresAt, createdAt;

  /// The role it gives, as a label.
  String get roleLabel => inviteMemberRoleLabel(memberRole, role);

  factory MyInvitation.fromJson(Map<String, dynamic> j) {
    final o = asMap(j['org']);
    final ar = '${o['name_ar'] ?? ''}', en = '${o['name_en'] ?? ''}';
    return MyInvitation(
      id: asInt(j['id']),
      orgId: asInt(o['id']),
      orgName: t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar),
      logoUrl: o['logo_url'] as String?,
      role: '${j['role'] ?? 'student'}',
      expiresAt: orgParseUtc(j['expires_at']),
      memberRole: '${j['member_role'] ?? ''}',
      source: '${j['source'] ?? 'invite'}',
      message: '${j['message'] ?? ''}'.trim(),
      createdAt: orgParseUtc(j['created_at']),
      invitedByName: '${j['invited_by_name'] ?? ''}'.trim(),
    );
  }
}

/// The invitation message to share with a link.
String inviteShareText(String orgName, String role, String link) => t(
      'دعوة للانضمام إلى «$orgName» بصفة ${inviteRoleLabel(role)} على نكست برين:\n$link',
      'You are invited to join "$orgName" as ${inviteRoleLabel(role)} on NextBrain:\n$link',
    );

// ═════════════════════════════════════════════════════════════════════════════
//  API
// ═════════════════════════════════════════════════════════════════════════════

/// The body of `POST …/invitations`.
Map<String, dynamic> inviteBody({
  required String channel,
  required List<String> contacts,
  required String role,
  int? deptId,
  int? programId,
  String? message,
  int expiresDays = inviteDefaultExpiryDays,
}) =>
    {
      'channel': channel,
      'contacts': contacts,
      'role': role,
      'dept_id': ?deptId,
      'program_id': ?programId,
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      'expires_days': expiresDays,
    };

class OrgInvitationsApi {
  OrgInvitationsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static String _staff(int orgId) => '$orgBase/orgs/$orgId/invitations';
  static const _pub = '$orgBase/public';

  Future<OrgCall> create(int orgId, Map<String, dynamic> body) => orgCall(() => _api.post(_staff(orgId), body: body), quiet: true);

  Future<OrgCall> list(int orgId, {String status = 'pending', String q = '', int page = 1, int pageSize = 20}) =>
      orgCall(() => _api.get(_staff(orgId), queryParams: {'status': status, if (q.trim().isNotEmpty) 'q': q.trim(), 'page': page, 'page_size': pageSize}),
          quiet: true);

  Future<OrgCall> resend(int orgId, int id) => orgCall(() => _api.post('${_staff(orgId)}/$id/resend'), quiet: true);

  Future<OrgCall> cancel(int orgId, int id) => orgCall(() => _api.post('${_staff(orgId)}/$id/cancel'), quiet: true);

  Future<OrgCall> lookup(String token) => orgCall(() => _api.get('$_pub/invitations/$token'), quiet: true);

  Future<OrgCall> accept(String token) => orgCall(() => _api.post('$_pub/invitations/$token/accept'), quiet: true);

  Future<OrgCall> decline(String token) => orgCall(() => _api.post('$_pub/invitations/$token/decline'), quiet: true);

  Future<OrgCall> mine() => orgCall(() => _api.get('$_pub/me/invitations'), quiet: true);

  Future<OrgCall> acceptMine(int id) => orgCall(() => _api.post('$_pub/me/invitations/$id/accept'), quiet: true);

  Future<OrgCall> declineMine(int id) => orgCall(() => _api.post('$_pub/me/invitations/$id/decline'), quiet: true);
}
