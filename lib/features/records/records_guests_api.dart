// lib/features/records/records_guests_api.dart — Records (D-315): a record shared with GUESTS by e-mail
// (people without an account). Pure: models, parsing, the e-mail list rules, code → text and the two APIs. The
// sheet's section: records_share_parts.dart (RecordGuestsSection); the guest's page: record_guest_page.dart.
//
//   owner   POST   /api/v1/me/records/{rid}/share/guests             {emails, message?, expires_days?} → share + mail
//           POST   /api/v1/me/records/{rid}/share/guests/{gid}/resend → share + mail
//           DELETE /api/v1/me/records/{rid}/share/guests/{gid}        → share (that link dies at once)
//           POST   /api/v1/me/records/{rid}/share/guest-link          {expires_days?} → share: the ONE open guest
//                                                                      link (D-842, `kind: link`, no address)
//   guest   GET    /api/v1/public/records/guest/{token}               → GuestRecordCard   (no account, auth: false)
//           POST   /api/v1/public/records/guest/{token}/play          → RecordPlay (a short-lived signed stream)
//
// A guest link is https://nextbrain.site/s/record/g_<secret> (the share link scheme of D-312, a `g_` token).
// Contract: ../back/FLUTTER_API_CHANGES.md "Studio on session materials + record guests by e-mail". Tests:
// test/org/records_guests_api_test.dart.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_inputs.dart' show kEmailRegex;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t, asMap, asMapList, asInt;
import 'package:flutter_education_app/features/live/meeting_recording.dart' show parseRecordingTime;
import 'package:flutter_education_app/features/records/records_api.dart' show RecordPlay, recordsErrorText;
import 'package:flutter_education_app/features/records/records_share_api.dart' show RecordShare;

/// Guest tokens start with this (a share token of D-312 never needs to).
const kGuestTokenPrefix = 'g_';

bool isGuestRecordToken(String? token) => (token ?? '').startsWith(kGuestTokenPrefix) && token!.length > 10;

/// Up to this many addresses in one invite (the server's MAX_PER_CALL).
const recordGuestsPerInvite = 20;

/// The optional message's length (the server keeps 500).
const recordGuestMessageMax = 500;

/// How long a guest link works: 7 days, 30 days, or never (null).
const recordGuestExpiries = <int?>[7, 30, null];

String recordGuestExpiryLabel(int? days) => switch (days) {
      7 => t('7 أيام', '7 days'),
      30 => t('30 يوماً', '30 days'),
      _ => t('بلا انتهاء', 'Never'),
    };

String? _s(dynamic v) {
  final x = '${v ?? ''}'.trim();
  return x.isEmpty || x == 'null' ? null : x;
}

/// What the owner typed, split on commas, semicolons, spaces and new lines: the valid addresses (lower-cased, once
/// each, in order) and the ones that are not addresses.
({List<String> valid, List<String> invalid}) parseGuestEmails(String text) {
  final valid = <String>[], invalid = <String>[];
  for (final raw in text.split(RegExp(r'[\s,;،]+'))) {
    final e = raw.trim().toLowerCase();
    if (e.isEmpty) continue;
    if (e.length <= 254 && kEmailRegex.hasMatch(e)) {
      if (!valid.contains(e)) valid.add(e);
    } else if (!invalid.contains(raw.trim())) {
      invalid.add(raw.trim());
    }
  }
  return (valid: valid, invalid: invalid);
}

/// Why the typed addresses cannot be sent (null: they can).
String? guestEmailsProblem(String text) {
  final p = parseGuestEmails(text);
  if (p.invalid.isNotEmpty) {
    return t('عنوان غير صالح: ${p.invalid.first}', 'Not an e-mail address: ${p.invalid.first}');
  }
  if (p.valid.isEmpty) return t('اكتب عنوان بريد واحداً على الأقل', 'Type at least one e-mail address');
  if (p.valid.length > recordGuestsPerInvite) {
    return t('حتى $recordGuestsPerInvite عنواناً في المرة الواحدة', 'Up to $recordGuestsPerInvite addresses at a time');
  }
  return null;
}

/// One guest of a shared record.
class RecordGuest {
  const RecordGuest({
    required this.id,
    required this.email,
    required this.token,
    this.link,
    this.message,
    this.expiresAt,
    this.expired = false,
    this.createdAt,
    this.openedAt,
    this.lastOpenedAt,
    this.views = 0,
    this.emailStatus,
    this.openLink = false,
  });

  final int id;

  /// The guest's address ('' for the open link).
  final String email;

  /// The record's one open guest link (D-842): not tied to an address, never e-mailed.
  final bool openLink;
  final String token;
  final String? link;
  final String? message;
  final DateTime? expiresAt;
  final bool expired;
  final DateTime? createdAt;
  final DateTime? openedAt;
  final DateTime? lastOpenedAt;
  final int views;

  /// sent · failed · unavailable (the server could not send e-mail) · null
  final String? emailStatus;

  bool get emailed => emailStatus == 'sent';

  static RecordGuest? fromJson(Map<String, dynamic> j) {
    final id = asInt(j['id']);
    final open = j['kind'] == 'link';
    final email = open ? '' : _s(j['email']);
    final token = _s(j['token']);
    if (id <= 0 || email == null || token == null) return null;
    return RecordGuest(
      id: id,
      email: email,
      openLink: open,
      token: token,
      link: _s(j['link']),
      message: _s(j['message']),
      expiresAt: parseRecordingTime(j['expires_at']),
      expired: j['expired'] == true,
      createdAt: parseRecordingTime(j['created_at']),
      openedAt: parseRecordingTime(j['opened_at']),
      lastOpenedAt: parseRecordingTime(j['last_opened_at']),
      views: asInt(j['views']),
      emailStatus: _s(j['email_status']),
    );
  }

  /// The row's second line: opened / views / the e-mail state / expiry.
  String status() {
    if (expired) return t('انتهت صلاحية الرابط', 'The link expired');
    final parts = <String>[
      if (openedAt == null) t('لم يفتحه بعد', 'Not opened yet') else t('فتحه', 'Opened'),
      if (views > 0) t('$views مشاهدة', '$views views'),
      if (emailStatus == 'failed') t('لم يُرسل البريد', 'E-mail not sent'),
      if (!openLink && emailStatus == 'unavailable') t('انسخ الرابط وأرسله', 'Copy the link and send it'),
    ];
    return parts.join(' · ');
  }
}

List<RecordGuest> recordGuestsFrom(dynamic json) => [
      for (final j in (json is List ? asMapList(json) : asMapList(asMap(json)['guests']))) ?RecordGuest.fromJson(j),
    ];

/// The e-mail side of an invite / resend.
class GuestMailResult {
  const GuestMailResult({required this.status, this.sent = 0, this.failed = 0, this.code});

  /// sent · partial · failed · unavailable
  final String status;
  final int sent;
  final int failed;
  final String? code;

  bool get unavailable => status == 'unavailable' || code == 'email_unavailable';

  static GuestMailResult fromJson(dynamic j) {
    final m = j is Map ? asMap(j) : const <String, dynamic>{};
    return GuestMailResult(
      status: _s(m['status']) ?? 'sent',
      sent: asInt(m['sent']),
      failed: asInt(m['failed']),
      code: _s(m['code']),
    );
  }

  /// The notice after an invite.
  String notice() {
    if (unavailable) {
      return t('أُنشئت الروابط، لكن إرسال البريد غير متاح على الخادم — انسخ رابط كل ضيف وأرسله بنفسك',
          "The links are ready, but this server can't send e-mail — copy each guest's link and send it yourself");
    }
    if (status == 'failed') return t('تعذّر إرسال البريد — انسخ الرابط أو أعد الإرسال', "The e-mail couldn't be sent — copy the link or resend");
    if (status == 'partial') {
      return t('أُرسل $sent وتعذّر $failed — أعد الإرسال لمن لم يصله', 'Sent $sent, $failed failed — resend to those who did not get it');
    }
    return sent == 1 ? t('أُرسلت الدعوة', 'Invitation sent') : t('أُرسلت $sent دعوات', '$sent invitations sent');
  }
}

/// A share as answered by the guest routes: the share (with its guests) + the e-mail result.
class GuestInviteResult {
  const GuestInviteResult({required this.share, required this.guests, required this.mail});
  final RecordShare share;
  final List<RecordGuest> guests;
  final GuestMailResult mail;

  static GuestInviteResult fromJson(Map<String, dynamic> j, {int recordId = 0}) => GuestInviteResult(
        share: RecordShare.fromJson(j, recordId: recordId),
        guests: recordGuestsFrom(j),
        mail: GuestMailResult.fromJson(j['mail']),
      );
}

/// What a guest sees before the player.
class GuestRecordCard {
  const GuestRecordCard({
    required this.title,
    this.ownerName = '',
    this.ownerImage,
    this.durationSeconds = 0,
    this.audio = false,
    this.coverUrl,
    this.message,
    this.expiresAt,
    this.subtitle,
    this.personal = true,
    this.video = false,
  });

  final String title;
  final String ownerName;
  final String? ownerImage;
  final double durationSeconds;
  final bool audio;
  final String? coverUrl;
  final String? message;
  final DateTime? expiresAt;

  /// The course of a lesson video (D-841).
  final String? subtitle;

  /// A personal invitation ("don't forward it"); false for an open link and a lesson video (D-842).
  final bool personal;

  /// A course video's guest link (D-841), not a recording.
  final bool video;

  static GuestRecordCard fromJson(Map<String, dynamic> j) {
    final o = j['owner'] is Map ? asMap(j['owner']) : const <String, dynamic>{};
    final d = j['duration_seconds'];
    return GuestRecordCard(
      title: _s(j['title']) ?? t('تسجيل', 'Recording'),
      ownerName: _s(o['name']) ?? '',
      ownerImage: _s(o['image_url']),
      durationSeconds: d is num ? d.toDouble() : double.tryParse('${d ?? ''}') ?? 0,
      audio: j['media'] == 'audio',
      coverUrl: _s(j['cover_url']),
      message: _s(j['message']),
      expiresAt: parseRecordingTime(j['expires_at']),
      subtitle: AppConfig.lang == 'en' ? (_s(j['subtitle_en']) ?? _s(j['subtitle'])) : _s(j['subtitle']),
      personal: j['personal'] != false,
      video: j['kind'] == 'video',
    );
  }
}

/// A guest link that is not (or no longer) valid answers 404: one calm text for every reason.
String guestRecordErrorText(Object e) {
  final ex = ApiException.from(e);
  if (ex.code == 'record_not_found' || ex.code == 'link_not_found' || ex.statusCode == 404) {
    return t('هذا الرابط غير متاح — ربما انتهت صلاحيته أو أوقفه صاحب التسجيل',
        'This link is not available — it may have expired or its owner stopped it');
  }
  if (ex.code == 'too_many_attempts' || ex.statusCode == 429) {
    return t('محاولات كثيرة — حاول بعد قليل', 'Too many tries — try again in a few minutes');
  }
  return ex.message;
}

/// The owner's errors on the guest routes (the codes of the server, then Records' own).
String recordGuestsErrorText(Object e) {
  final ex = ApiException.from(e);
  return switch (ex.code) {
    'bad_email' => t('عنوان بريد غير صالح', 'Not a valid e-mail address'),
    'no_emails' => t('اكتب عنوان بريد واحداً على الأقل', 'Type at least one e-mail address'),
    'too_many_emails' => t('حتى $recordGuestsPerInvite عنواناً في المرة الواحدة', 'Up to $recordGuestsPerInvite addresses at a time'),
    'too_many_guests' => t('وصلت إلى الحد الأقصى للضيوف لهذا التسجيل', 'This recording has the most guests it can have'),
    'bad_expiry' => t('اختر مدة صلاحية الرابط', 'Pick how long the link works'),
    'guest_not_found' => t('هذا الضيف لم يعد في القائمة', 'This guest is not on the list any more'),
    'not_emailed' => t('هذا رابط مفتوح، لا يُرسل بالبريد', 'This is an open link, it is not e-mailed'),
    'too_many_attempts' => t('أرسلت دعوات كثيرة — حاول بعد قليل', 'You sent many invitations — try again later'),
    'feature_disabled' => t('المشاركة متوقفة حالياً', 'Sharing is switched off right now'),
    _ => recordsErrorText(e),
  };
}

abstract class RecordGuestsApi {
  Future<GuestInviteResult> invite(int recordId, List<String> emails, {String? message, int? expiresDays});
  Future<GuestInviteResult> resend(int recordId, int guestId);
  Future<GuestInviteResult> revoke(int recordId, int guestId);

  /// The record's one open guest link (D-842): made on the first call, its expiry set on every call.
  Future<GuestInviteResult> openLink(int recordId, {int? expiresDays});
}

class RemoteRecordGuestsApi implements RecordGuestsApi {
  RemoteRecordGuestsApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/me/records';

  @override
  Future<GuestInviteResult> invite(int recordId, List<String> emails, {String? message, int? expiresDays}) async =>
      GuestInviteResult.fromJson(
          asMap(await _api.post('$_base/$recordId/share/guests', body: {
            'emails': emails,
            if ((message ?? '').trim().isNotEmpty) 'message': message!.trim(),
            'expires_days': expiresDays,
          })),
          recordId: recordId);

  @override
  Future<GuestInviteResult> resend(int recordId, int guestId) async =>
      GuestInviteResult.fromJson(asMap(await _api.post('$_base/$recordId/share/guests/$guestId/resend')), recordId: recordId);

  @override
  Future<GuestInviteResult> revoke(int recordId, int guestId) async =>
      GuestInviteResult.fromJson(asMap(await _api.delete('$_base/$recordId/share/guests/$guestId')), recordId: recordId);

  @override
  Future<GuestInviteResult> openLink(int recordId, {int? expiresDays}) async => GuestInviteResult.fromJson(
      asMap(await _api.post('$_base/$recordId/share/guest-link', body: {'expires_days': expiresDays})),
      recordId: recordId);
}

/// The guest's side: no account (auth: false), so a 401 can never send them to the login page.
abstract class GuestRecordApi {
  Future<GuestRecordCard> card(String token);
  Future<RecordPlay> play(String token);
}

class RemoteGuestRecordApi implements GuestRecordApi {
  RemoteGuestRecordApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/public/records/guest';

  @override
  Future<GuestRecordCard> card(String token) async =>
      GuestRecordCard.fromJson(asMap(await _api.get('$_base/${Uri.encodeComponent(token)}', auth: false)));

  @override
  Future<RecordPlay> play(String token) async => RecordPlay.fromJson(
      asMap(await _api.post('$_base/${Uri.encodeComponent(token)}/play', auth: false)),
      base: _api.baseUrl);
}
