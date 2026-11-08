// lib/features/shared/records/records_share_api.dart — Records (D-312): sharing a record and the Studio's
// filmstrip. Pure: models, parsing, text and the API. Sheets: records_share.dart; plain values:
// records_share_parts.dart. Contract: ../back/FLUTTER_API_CHANGES.md "Records: share + studio frames".
//
//   owner   GET    /api/v1/me/records/{rid}/share            → RecordShare (mode off · people · link)
//           PUT    /api/v1/me/records/{rid}/share            {mode, user_ids} → RecordShare (new people are notified)
//           DELETE /api/v1/me/records/{rid}/share            → RecordShare (mode off: the link dies)
//           GET    /api/v1/me/records/{rid}/share/people?q=  → [RecordSharePerson] the people I may pick
//           POST   /api/v1/me/records/{rid}/frames          {n} → RecordFrames (ready · pending · unavailable)
//   viewer  GET    /api/v1/me/records/shared                → [SharedRecord] shared with me
//           GET    /api/v1/me/records/shared/{token}        → SharedRecord   404 record_not_found (not allowed)
//           POST   /api/v1/me/records/shared/{token}/play   → RecordPlay (the same signed stream)
//
// A share link is https://nextbrain.site/s/record/<token> (core/share/app_links.dart, D-307). Tests:
// test/org/records_share_api_test.dart.
import '../../../core/api_client.dart';
import '../../admin/admin_common.dart' show t, asMap, asMapList, asInt;
import '../live/meeting_recording.dart' show RecordingQuality, parseRecordingTime;
import 'records_api.dart' show RecordPlay;

/// The kill switch of sharing (the Share button, the sheet, the Shared-with-me tab).
const kRecordsShareFeatureKey = 'records.share';

/// Who may watch.
enum RecordShareMode {
  off('off'),

  /// Only the people on the list.
  people('people'),

  /// Anyone signed in who has the link (the people on the list are told as well).
  link('link');

  const RecordShareMode(this.wire);
  final String wire;

  static RecordShareMode fromWire(dynamic v) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final m in values) {
      if (m.wire == s) return m;
    }
    return RecordShareMode.off;
  }

  String get label => switch (this) {
        RecordShareMode.off => t('غير مشارك', 'Not shared'),
        RecordShareMode.people => t('أشخاص أختارهم فقط', 'Only people I choose'),
        RecordShareMode.link => t('أي شخص لديه الرابط', 'Anyone with the link'),
      };

  String get hint => switch (this) {
        RecordShareMode.off => t('لا يراه أحد غيرك.', 'Nobody but you can watch it.'),
        RecordShareMode.people => t('يشاهده من تختارهم فقط بعد تسجيل الدخول.', 'Only the people you pick can watch, signed in.'),
        RecordShareMode.link =>
          t('يشاهده أي شخص مسجّل الدخول يفتح الرابط.', 'Anyone signed in who opens the link can watch.'),
      };
}

String? _s(dynamic v) {
  final x = '${v ?? ''}'.trim();
  return x.isEmpty || x == 'null' ? null : x;
}

double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// A person on (or for) a share list.
class RecordSharePerson {
  const RecordSharePerson({required this.id, required this.name, this.imageUrl, this.username, this.addedAt, this.openedAt});

  final int id;
  final String name;
  final String? imageUrl;
  final String? username;
  final DateTime? addedAt;

  /// When they first opened it (null: not yet).
  final DateTime? openedAt;

  static RecordSharePerson? fromJson(Map<String, dynamic> j) {
    final id = asInt(j['id']);
    if (id <= 0) return null;
    return RecordSharePerson(
      id: id,
      name: _s(j['name']) ?? t('مستخدم', 'User'),
      imageUrl: _s(j['image_url']),
      username: _s(j['username']),
      addedAt: parseRecordingTime(j['added_at']),
      openedAt: parseRecordingTime(j['opened_at']),
    );
  }
}

List<RecordSharePerson> sharePeopleFrom(dynamic json) => [
      for (final j in (json is List ? asMapList(json) : asMapList(asMap(json)['items']))) ?RecordSharePerson.fromJson(j),
    ];

/// The share settings of one of my records.
class RecordShare {
  const RecordShare({
    required this.recordId,
    this.mode = RecordShareMode.off,
    this.token,
    this.link,
    this.people = const [],
    this.views = 0,
    this.updatedAt,
  });

  final int recordId;
  final RecordShareMode mode;
  final String? token;
  final String? link;
  final List<RecordSharePerson> people;

  /// Plays by other people.
  final int views;
  final DateTime? updatedAt;

  bool get active => mode != RecordShareMode.off;

  static RecordShare fromJson(Map<String, dynamic> j, {int recordId = 0}) {
    final mode = RecordShareMode.fromWire(j['mode']);
    return RecordShare(
      recordId: asInt(j['record_id'], recordId),
      mode: mode,
      token: mode == RecordShareMode.off ? null : _s(j['token']),
      link: mode == RecordShareMode.off ? null : _s(j['link']),
      people: [for (final p in asMapList(j['people'])) ?RecordSharePerson.fromJson(p)],
      views: asInt(j['views']),
      updatedAt: parseRecordingTime(j['updated_at']),
    );
  }

  /// "Shared with 3 people · 12 views", for the sheet's header and the library tile.
  String summary() {
    if (!active) return RecordShareMode.off.label;
    final who = mode == RecordShareMode.link
        ? RecordShareMode.link.label
        : t('مع ${people.length} ${people.length == 1 ? 'شخص' : 'أشخاص'}', 'With ${people.length} ${people.length == 1 ? 'person' : 'people'}');
    return views > 0 ? '$who · ${t('$views مشاهدة', '$views views')}' : who;
  }
}

/// A record someone shared with me (or one of mine opened through its link).
class SharedRecord {
  const SharedRecord({
    required this.token,
    required this.recordId,
    required this.title,
    this.link,
    this.coverUrl,
    this.durationSeconds = 0,
    this.audio = false,
    this.quality = RecordingQuality.p720,
    this.mode = RecordShareMode.people,
    this.ownerId = 0,
    this.ownerName = '',
    this.ownerImage,
    this.ownerUsername,
    this.sharedAt,
    this.isOwner = false,
  });

  final String token;
  final int recordId;
  final String title;
  final String? link;
  final String? coverUrl;
  final double durationSeconds;
  final bool audio;
  final RecordingQuality quality;
  final RecordShareMode mode;
  final int ownerId;
  final String ownerName;
  final String? ownerImage;
  final String? ownerUsername;
  final DateTime? sharedAt;
  final bool isOwner;

  static SharedRecord? fromJson(Map<String, dynamic> j) {
    final token = _s(j['token']);
    if (token == null) return null;
    final o = j['owner'] is Map ? asMap(j['owner']) : const <String, dynamic>{};
    return SharedRecord(
      token: token,
      recordId: asInt(j['record_id']),
      title: _s(j['title']) ?? t('تسجيل', 'Recording'),
      link: _s(j['link']),
      coverUrl: _s(j['cover_url']),
      durationSeconds: _num(j['duration_seconds']),
      audio: j['media'] == 'audio' || j['quality'] == 'audio',
      quality: RecordingQuality.fromWire(j['quality']),
      mode: RecordShareMode.fromWire(j['mode']),
      ownerId: asInt(o['id']),
      ownerName: _s(o['name']) ?? '',
      ownerImage: _s(o['image_url']),
      ownerUsername: _s(o['username']),
      sharedAt: parseRecordingTime(j['shared_at']),
      isOwner: j['is_owner'] == true,
    );
  }
}

/// GET /me/records/shared, newest shared first.
List<SharedRecord> sharedRecordsFrom(dynamic json) {
  final out = [for (final j in (json is List ? asMapList(json) : asMapList(asMap(json)['items']))) ?SharedRecord.fromJson(j)];
  out.sort((a, b) {
    final x = a.sharedAt, y = b.sharedAt;
    if (x != null && y != null && x != y) return y.compareTo(x);
    return b.recordId.compareTo(a.recordId);
  });
  return out;
}

/// The Studio's filmstrip: ONE image of [count] frames in a row (each [tileW] × [tileH]).
class RecordFrames {
  const RecordFrames({required this.status, this.url, this.count = 0, this.tileW = 160, this.tileH = 90});

  /// ready · pending (a server job runs; `job_updated{kind: record_frames}` says when) · unavailable
  final String status;

  /// Absolute (the API's base prepended).
  final String? url;
  final int count;
  final int tileW;
  final int tileH;

  bool get ready => status == 'ready' && url != null && count > 0;
  bool get pending => status == 'pending';

  static RecordFrames fromJson(Map<String, dynamic> j, {required String base}) {
    final raw = _s(j['url']);
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final status = '${j['status'] ?? ''}';
    return RecordFrames(
      status: const ['ready', 'pending', 'unavailable'].contains(status) ? status : 'unavailable',
      url: raw == null ? null : (raw.startsWith('/') ? '$root$raw' : raw),
      count: asInt(j['count']),
      tileW: asInt(j['tile_w'], 160),
      tileH: asInt(j['tile_h'], 90),
    );
  }
}

/// How many frames the Studio asks for (the server takes 8–40).
const recordFramesCount = 24;

abstract class RecordShareApi {
  Future<RecordShare> share(int id);
  Future<RecordShare> setShare(int id, RecordShareMode mode, List<int> userIds);
  Future<RecordShare> stopShare(int id);
  Future<List<RecordSharePerson>> people(int id, {String? q});
  Future<List<SharedRecord>> sharedWithMe();
  Future<SharedRecord?> shared(String token);
  Future<RecordPlay> playShared(String token);
  Future<RecordFrames> frames(int id, {int n = recordFramesCount});
}

class RemoteRecordShareApi implements RecordShareApi {
  RemoteRecordShareApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const _base = '/api/v1/me/records';

  @override
  Future<RecordShare> share(int id) async => RecordShare.fromJson(asMap(await _api.get('$_base/$id/share')), recordId: id);

  @override
  Future<RecordShare> setShare(int id, RecordShareMode mode, List<int> userIds) async => RecordShare.fromJson(
      asMap(await _api.put('$_base/$id/share', body: {'mode': mode.wire, 'user_ids': userIds})),
      recordId: id);

  @override
  Future<RecordShare> stopShare(int id) async => RecordShare.fromJson(asMap(await _api.delete('$_base/$id/share')), recordId: id);

  @override
  Future<List<RecordSharePerson>> people(int id, {String? q}) async => sharePeopleFrom(await _api.get('$_base/$id/share/people',
      queryParams: {if (q != null && q.trim().isNotEmpty) 'q': q.trim()}));

  @override
  Future<List<SharedRecord>> sharedWithMe() async => sharedRecordsFrom(await _api.get('$_base/shared'));

  @override
  Future<SharedRecord?> shared(String token) async =>
      SharedRecord.fromJson(asMap(await _api.get('$_base/shared/${Uri.encodeComponent(token)}')));

  @override
  Future<RecordPlay> playShared(String token) async =>
      RecordPlay.fromJson(asMap(await _api.post('$_base/shared/${Uri.encodeComponent(token)}/play')), base: _api.baseUrl);

  @override
  Future<RecordFrames> frames(int id, {int n = recordFramesCount}) async =>
      RecordFrames.fromJson(asMap(await _api.post('$_base/$id/frames', body: {'n': n})), base: _api.baseUrl);
}
