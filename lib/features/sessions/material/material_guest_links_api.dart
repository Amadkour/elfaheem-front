// lib/features/sessions/material/material_guest_links_api.dart — a course session's VIDEO shared with guests
// by link (D-841). Pure: the models, code → text and the two APIs.
//
//   staff   GET    /api/v1/sessions/{sid}/materials/{mid}/guest-links          → MaterialGuestLinks
//           POST   /api/v1/sessions/{sid}/materials/{mid}/guest-links          {expires_days: 1|7|30|null}
//           DELETE /api/v1/sessions/{sid}/materials/{mid}/guest-links/{lid}    → the list (that link dies at once)
//   guest   GET    /api/v1/public/videos/{token}                               → GuestRecordCard (auth: false)
//           POST   /api/v1/public/videos/{token}/play                          → RecordPlay (a 2 h signed stream)
//
// A link is https://alfheemacademy.com/s/video/v_<secret> (AppLink.video, D-307's scheme): the token is the only key, a
// material id never opens a video. Kill switch `materials.guest_link`. Contract: ../back/FLUTTER_API_CHANGES.md
// "Guest share links open straight to the video". Tests: test/org/guest_share_test.dart.
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t, asMap, asMapList, asInt;
import 'package:flutter_education_app/features/live/meeting_recording.dart' show parseRecordingTime;
import 'package:flutter_education_app/features/records/records_api.dart' show RecordPlay;
import 'package:flutter_education_app/features/records/records_guests_api.dart' show GuestRecordApi, GuestRecordCard;

/// The kill switch of a course video's guest links (feature catalog `materials.guest_link`).
const kMaterialGuestLinkKey = 'materials.guest_link';

/// How long a new link works: 1 day, 7 days, 30 days, or never (null).
const materialGuestExpiries = <int?>[1, 7, 30, null];

String materialGuestExpiryLabel(int? days) => switch (days) {
      1 => t('يوم واحد', '1 day'),
      7 => t('7 أيام', '7 days'),
      30 => t('30 يوماً', '30 days'),
      _ => t('بلا انتهاء', 'Never'),
    };

String? _s(dynamic v) {
  final x = '${v ?? ''}'.trim();
  return x.isEmpty || x == 'null' ? null : x;
}

/// One guest link of a video.
class MaterialGuestLink {
  const MaterialGuestLink({
    required this.id,
    required this.token,
    required this.link,
    this.expiresAt,
    this.expired = false,
    this.views = 0,
    this.openedAt,
    this.createdAt,
  });

  final int id;
  final String token;
  final String link;
  final DateTime? expiresAt;
  final bool expired;
  final int views;
  final DateTime? openedAt;
  final DateTime? createdAt;

  static MaterialGuestLink? fromJson(Map<String, dynamic> j) {
    final id = asInt(j['id']);
    final token = _s(j['token']);
    final link = _s(j['link']);
    if (id <= 0 || token == null || link == null) return null;
    return MaterialGuestLink(
      id: id,
      token: token,
      link: link,
      expiresAt: parseRecordingTime(j['expires_at']),
      expired: j['expired'] == true,
      views: asInt(j['views']),
      openedAt: parseRecordingTime(j['opened_at']),
      createdAt: parseRecordingTime(j['created_at']),
    );
  }
}

/// The staff's list (newest first) and whether the feature is on.
class MaterialGuestLinks {
  const MaterialGuestLinks({this.links = const [], this.enabled = true, this.created});

  final List<MaterialGuestLink> links;
  final bool enabled;

  /// The link the last create made (to copy / share at once).
  final MaterialGuestLink? created;

  static MaterialGuestLinks fromJson(Map<String, dynamic> j) => MaterialGuestLinks(
        links: [for (final x in asMapList(j['links'])) ?MaterialGuestLink.fromJson(x)],
        enabled: j['enabled'] != false,
        created: j['created'] is Map ? MaterialGuestLink.fromJson(asMap(j['created'])) : null,
      );
}

/// The staff's errors.
String materialGuestErrorText(Object e) {
  final ex = ApiException.from(e);
  return switch (ex.code) {
    'material_not_video' => t('روابط الضيوف للفيديو فقط', 'Guest links are for videos only'),
    'bad_expiry' => t('اختر مدة صلاحية الرابط', 'Pick how long the link works'),
    'too_many_links' => t('وصلت إلى الحد الأقصى — ألغِ رابطاً قديماً أولاً', 'This video has the most links it can have — revoke an old one first'),
    'link_not_found' => t('هذا الرابط لم يعد موجوداً', 'This link is not there any more'),
    'feature_disabled' => t('مشاركة الفيديو مع الضيوف متوقفة حالياً', 'Sharing videos with guests is switched off right now'),
    _ => ex.message,
  };
}

abstract class MaterialGuestLinksApi {
  Future<MaterialGuestLinks> list(int sessionId, int materialId);
  Future<MaterialGuestLinks> create(int sessionId, int materialId, {int? expiresDays});
  Future<MaterialGuestLinks> revoke(int sessionId, int materialId, int linkId);
}

class RemoteMaterialGuestLinksApi implements MaterialGuestLinksApi {
  RemoteMaterialGuestLinksApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  String _base(int sid, int mid) => '/api/v1/sessions/$sid/materials/$mid/guest-links';

  @override
  Future<MaterialGuestLinks> list(int sessionId, int materialId) async =>
      MaterialGuestLinks.fromJson(asMap(await _api.get(_base(sessionId, materialId))));

  @override
  Future<MaterialGuestLinks> create(int sessionId, int materialId, {int? expiresDays}) async =>
      MaterialGuestLinks.fromJson(asMap(await _api.post(_base(sessionId, materialId), body: {'expires_days': expiresDays})));

  @override
  Future<MaterialGuestLinks> revoke(int sessionId, int materialId, int linkId) async =>
      MaterialGuestLinks.fromJson(asMap(await _api.delete('${_base(sessionId, materialId)}/$linkId')));
}

/// The guest's side: no account (auth: false), so a 401 can never send them to the login page.
class RemoteGuestVideoApi implements GuestRecordApi {
  RemoteGuestVideoApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/public/videos';

  @override
  Future<GuestRecordCard> card(String token) async =>
      GuestRecordCard.fromJson(asMap(await _api.get('$_base/${Uri.encodeComponent(token)}', auth: false)));

  @override
  Future<RecordPlay> play(String token) async => RecordPlay.fromJson(
      asMap(await _api.post('$_base/${Uri.encodeComponent(token)}/play', auth: false)),
      base: _api.baseUrl);
}
