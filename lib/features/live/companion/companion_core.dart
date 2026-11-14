// lib/features/live/companion/companion_core.dart
//
// A phone as the camera, microphone or speaker of one person in a live room (D-520), the pure part: identities, the
// wire shapes, the API, how the phone is folded into the person and what a handover has to do.
//
// The phone joins the same LiveKit room as `companion:<person's identity>`. A participant with that identity is never a
// person of its own: its video and audio belong to the person's tile (the identity is signed by the server, so it is the
// only thing trusted). The server rules are in ../../../../../../back/services/live_companion.py.
library;

import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomKind, LiveRoomRef;

const String kCompanionFeatureKey = 'live.companion';

/// Data messages between the person's device and their phone, topic of the room's data channel (`{"t": …}`).
const String kCompanionTopic = 'companion';

const String kCompanionPrefix = 'companion:';

bool isCompanionIdentity(String identity) => identity.startsWith(kCompanionPrefix);

/// The person a companion belongs to; null for anyone else.
String? companionPrimaryOf(String identity) =>
    isCompanionIdentity(identity) ? identity.substring(kCompanionPrefix.length) : null;

String companionIdentityFor(String primary) => '$kCompanionPrefix$primary';

/// The people in a roster: everyone but the phones.
Iterable<T> withoutCompanions<T>(Iterable<T> all, String Function(T) identity) =>
    all.where((p) => !isCompanionIdentity(identity(p)));

/// Phone by the identity of the person it belongs to.
Map<String, T> companionsByPrimary<T>(Iterable<T> all, String Function(T) identity) {
  final out = <String, T>{};
  for (final p in all) {
    final primary = companionPrimaryOf(identity(p));
    if (primary != null) out[primary] = p;
  }
  return out;
}

enum CompanionSource {
  camera,
  microphone,
  speaker;

  String get wire => name;

  static CompanionSource? tryParse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }

  static Set<CompanionSource> parseAll(Object? v) {
    final items = v is List ? v : (v is String ? v.split(',') : const []);
    return {for (final x in items) ?tryParse(x is String ? x.trim() : x)};
  }
}

enum CompanionStatus {
  pending,
  active,
  declined,
  expired,
  ended,
  none;

  static CompanionStatus parse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return none;
  }
}

class CompanionRequest {
  const CompanionRequest({
    required this.id,
    required this.status,
    required this.kind,
    required this.refId,
    required this.sources,
    this.title = '',
    this.originLabel,
    this.expiresIn = 0,
    this.reason,
    this.primaryIdentity,
    this.secret,
    this.pushed = true,
  });

  final int id;
  final CompanionStatus status;
  final String kind;
  final int refId;
  final Set<CompanionSource> sources;
  final String title;
  final String? originLabel;
  final int expiresIn;
  final String? reason;
  final String? primaryIdentity;

  /// Only in the answer to the request itself: the QR link's secret.
  final String? secret;

  /// False: the server has no phone to push to (no app signed in on one): the QR is the way.
  final bool pushed;

  bool get pending => status == CompanionStatus.pending;
  bool get active => status == CompanionStatus.active;
  LiveRoomRef get ref => LiveRoomRef(kind == 'meeting' ? LiveRoomKind.meeting : LiveRoomKind.session, refId);

  static int _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  static String? _s(Object? v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  factory CompanionRequest.fromJson(Map j) => CompanionRequest(
        id: _i(j['id']),
        status: CompanionStatus.parse(j['status']),
        kind: '${j['kind'] ?? 'session'}',
        refId: _i(j['ref_id']),
        sources: CompanionSource.parseAll(j['sources']),
        title: _s(j['title']) ?? '',
        originLabel: _s(j['origin_label']),
        expiresIn: _i(j['expires_in']),
        reason: _s(j['reason']),
        primaryIdentity: _s(j['primary_identity']),
        secret: _s(j['secret']),
        pushed: j['pushed'] != false,
      );

  static CompanionRequest? maybeFrom(Object? j) => j is Map ? CompanionRequest.fromJson(j) : null;
}

/// What a phone gets on Accept: everything it needs to join.
class CompanionJoin {
  const CompanionJoin({required this.request, required this.token, required this.url, required this.identity});

  final CompanionRequest request;
  final String token;
  final String url;
  final String identity;

  factory CompanionJoin.fromJson(Map j) => CompanionJoin(
        request: CompanionRequest.fromJson(j),
        token: '${j['token'] ?? ''}',
        url: '${j['ws_url'] ?? ''}',
        identity: '${j['identity'] ?? ''}',
      );
}

class CompanionApi {
  CompanionApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  static String _room(LiveRoomRef ref) => '/api/v1/live/${ref.kindName}/${ref.id}/companion';

  Future<CompanionRequest> ask(LiveRoomRef ref, Set<CompanionSource> sources, {String? originLabel}) async =>
      CompanionRequest.fromJson(await _api.post(_room(ref), body: {
        'sources': [for (final s in sources) s.wire],
        'origin_label': ?originLabel,
      }) as Map);

  Future<CompanionRequest?> current(LiveRoomRef ref) async =>
      CompanionRequest.maybeFrom((await _api.get(_room(ref)) as Map)['request']);

  Future<CompanionRequest?> pending() async =>
      CompanionRequest.maybeFrom((await _api.get('/api/v1/me/live-companion/pending') as Map)['request']);

  Future<CompanionRequest> bySecret(String secret) async =>
      CompanionRequest.fromJson(await _api.get('/api/v1/me/live-companion/link/$secret') as Map);

  Future<CompanionJoin> accept(int id) async =>
      CompanionJoin.fromJson(await _api.post('/api/v1/me/live-companion/$id/accept') as Map);

  Future<CompanionRequest> decline(int id) async =>
      CompanionRequest.fromJson(await _api.post('/api/v1/me/live-companion/$id/decline') as Map);

  Future<CompanionRequest> setSources(int id, Set<CompanionSource> sources) async =>
      CompanionRequest.fromJson(await _api.put('/api/v1/me/live-companion/$id/sources', body: {
        'sources': [for (final s in sources) s.wire],
      }) as Map);

  Future<void> end(int id, {String reason = 'user'}) async {
    await _api.post('/api/v1/me/live-companion/$id/end', body: {'reason': reason});
  }
}

// ── the data messages between the two devices ─────────────────────────────────────────────────────────────────

/// `{"t":"set","mic":bool,"cam":bool,"spk":bool,"flip":true}` web → phone · `{"t":"state", …, "front":bool}` phone → web ·
/// `{"t":"sources","sources":[…]}` web → phone after the server changed the rights · `{"t":"bye"}` either way.
List<int> companionPacket(Map<String, Object?> m) => utf8.encode(jsonEncode(m));

Map<String, dynamic>? companionFromPacket(List<int> data) {
  try {
    final m = jsonDecode(utf8.decode(data));
    return m is Map<String, dynamic> ? m : null;
  } catch (_) {
    return null;
  }
}

// ── the handover ──────────────────────────────────────────────────────────────────────────────────────────────

class CompanionActions {
  const CompanionActions({this.webMic, this.webCam, this.roomAudioMuted});

  /// Turn this device's mic / camera on or off; null = leave it.
  final bool? webMic;
  final bool? webCam;

  /// Mute (true) or unmute (false) the room's audio on this device; null = leave it.
  final bool? roomAudioMuted;

  bool get isEmpty => webMic == null && webCam == null && roomAudioMuted == null;
}

/// Decides what this device must do when the phone starts or stops providing something. It remembers how the mic and
/// camera were when the phone took them, so a dropped phone leaves things as they were. Muting the phone while it
/// is the mic does not bring this device's mic back: the person muted, not the phone left.
class CompanionHandover {
  bool? _savedMic;
  bool? _savedCam;
  bool _speaker = false;

  bool get micHeld => _savedMic != null;
  bool get camHeld => _savedCam != null;

  CompanionActions sync({
    required bool phoneHasMic,
    required bool phoneHasCam,
    required bool phoneSpeaker,
    required bool webMicOn,
    required bool webCamOn,
  }) {
    bool? mic;
    bool? cam;
    bool? audio;
    if (phoneHasMic && _savedMic == null) {
      _savedMic = webMicOn;
      if (webMicOn) mic = false;
    } else if (!phoneHasMic && _savedMic != null) {
      if (_savedMic!) mic = true;
      _savedMic = null;
    }
    if (phoneHasCam && _savedCam == null) {
      _savedCam = webCamOn;
      if (webCamOn) cam = false;
    } else if (!phoneHasCam && _savedCam != null) {
      if (_savedCam!) cam = true;
      _savedCam = null;
    }
    if (phoneSpeaker != _speaker) {
      _speaker = phoneSpeaker;
      audio = phoneSpeaker;
    }
    return CompanionActions(webMic: mic, webCam: cam, roomAudioMuted: audio);
  }

  /// The phone is gone (the room's clean-up): what must come back on this device, once.
  CompanionActions release() => sync(phoneHasMic: false, phoneHasCam: false, phoneSpeaker: false, webMicOn: false, webCamOn: false);
}

/// Sources that leave the sound path split between the two devices: the phone's mic hears this device's speaker (or
/// the other way round) and no echo canceller can help, because neither sees the other's signal.
bool companionSplitsAudio(Set<CompanionSource> sources) =>
    sources.contains(CompanionSource.microphone) != sources.contains(CompanionSource.speaker);
