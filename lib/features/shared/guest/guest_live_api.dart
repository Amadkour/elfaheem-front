// lib/features/shared/guest/guest_live_api.dart
//
// Guest links for live sessions: a teacher creates one public link per live session, anyone with the link
// joins the LiveKit room by typing a name — no account, no token.
//
//   Teacher (auth):   POST/GET/DELETE /api/v1/live-sessions/{id}/guest-link       → GuestLinkApi
//   Public (no auth): GET  /api/v1/public/live/{token}                           → GuestLiveApi.info
//                     POST /api/v1/public/live/{token}/join {name}               → GuestLiveApi.join
//
// Public calls are sent with `auth: false`, so ApiClient neither attaches a token nor redirects to the login
// screen on a 401. Server codes (ApiException.code) are turned into bilingual text by [guestLiveErrorText].
// The pure helpers at the bottom ([guestLiveTokenFromRoute], [guestLiveRouteFromUri]) are what main.dart uses
// to resolve `/live/<token>` as a route (web path, web hash and app links).
import '../../../config/app_config.dart';
import '../../../core/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

/// The teacher's view of a session's guest link.
class GuestLink {
  const GuestLink({
    required this.url,
    required this.token,
    required this.canPublish,
    required this.maxGuests,
    required this.guestsJoined,
    this.createdAt,
  });

  final String url;
  final String token;
  final bool canPublish;
  final int? maxGuests;
  final int guestsJoined;
  final DateTime? createdAt;

  factory GuestLink.fromJson(Map<String, dynamic> j) => GuestLink(
        url: (j['url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        canPublish: j['can_publish'] == true,
        maxGuests: (j['max_guests'] as num?)?.toInt(),
        guestsJoined: (j['guests_joined'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? ''),
      );
}

/// What a visitor sees before joining (GET /public/live/{token}).
class GuestLiveInfo {
  const GuestLiveInfo({
    required this.sessionId,
    required this.sessionName,
    required this.courseName,
    required this.teacherName,
    required this.isLive,
    required this.canPublish,
    required this.recordingEnabled,
    required this.guestsJoined,
    required this.maxGuests,
  });

  final int sessionId;
  final String sessionName;
  final String courseName;
  final String teacherName;
  final bool isLive;
  final bool canPublish;
  final bool recordingEnabled;
  final int guestsJoined;
  final int? maxGuests;

  factory GuestLiveInfo.fromJson(Map<String, dynamic> j) => GuestLiveInfo(
        sessionId: (j['session_id'] as num?)?.toInt() ?? 0,
        sessionName: (j['session_name'] ?? '').toString(),
        courseName: (j['course_name'] ?? '').toString(),
        teacherName: (j['teacher_name'] ?? '').toString(),
        isLive: j['is_live'] == true,
        canPublish: j['can_publish'] == true,
        recordingEnabled: j['recording_enabled'] == true,
        guestsJoined: (j['guests_joined'] as num?)?.toInt() ?? 0,
        maxGuests: (j['max_guests'] as num?)?.toInt(),
      );
}

/// The room credentials a guest gets back from POST /public/live/{token}/join.
class GuestJoin {
  const GuestJoin({
    required this.wsUrl,
    required this.token,
    required this.sessionId,
    required this.canPublish,
    required this.recordingEnabled,
    required this.identity,
  });

  final String wsUrl;
  final String token;
  final int sessionId;
  final bool canPublish;
  final bool recordingEnabled;
  final String identity;

  factory GuestJoin.fromJson(Map<String, dynamic> j) => GuestJoin(
        wsUrl: (j['ws_url'] ?? '').toString(),
        token: (j['token'] ?? '').toString(),
        sessionId: (j['session_id'] as num?)?.toInt() ?? 0,
        canPublish: j['can_publish'] != false,
        recordingEnabled: j['recording_enabled'] == true,
        identity: (j['identity'] ?? '').toString(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Teacher API
// ─────────────────────────────────────────────────────────────────────────────

class GuestLinkApi {
  GuestLinkApi._();

  static String _path(int sessionId) => '/api/v1/live-sessions/$sessionId/guest-link';

  /// The session's current link, or null when none exists (404 `guest_link_missing`).
  static Future<GuestLink?> load(int sessionId) async {
    try {
      final r = await ApiClient().get(_path(sessionId));
      if (r is Map<String, dynamic>) return GuestLink.fromJson(r);
      return null;
    } on ApiException catch (e) {
      if (e.code == 'guest_link_missing' || e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Creates the link, changes its options (`rotate: false` keeps the URL) or mints a new URL (`rotate: true`).
  static Future<GuestLink> save(
    int sessionId, {
    required bool canPublish,
    required int? maxGuests,
    bool rotate = false,
  }) async {
    final r = await ApiClient().post(_path(sessionId), body: {
      'can_publish': canPublish,
      'max_guests': maxGuests,
      'rotate': rotate,
    });
    return GuestLink.fromJson(Map<String, dynamic>.from(r as Map));
  }

  static Future<void> revoke(int sessionId) => ApiClient().delete(_path(sessionId));
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API (no auth)
// ─────────────────────────────────────────────────────────────────────────────

class GuestLiveApi {
  GuestLiveApi._();

  static Future<GuestLiveInfo> info(String token) async {
    final r = await ApiClient().get('/api/v1/public/live/$token', auth: false);
    return GuestLiveInfo.fromJson(Map<String, dynamic>.from(r as Map));
  }

  static Future<GuestJoin> join(String token, String name) async {
    final r = await ApiClient().post('/api/v1/public/live/$token/join', body: {'name': name}, auth: false);
    return GuestJoin.fromJson(Map<String, dynamic>.from(r as Map));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error codes → text
// ─────────────────────────────────────────────────────────────────────────────

/// Bilingual text for the guest-link server codes; falls back to the ApiException message.
String guestLiveErrorText(Object e) {
  final ex = ApiException.from(e);
  switch (ex.code) {
    case 'guest_link_invalid':
      return 'guest_live_err_invalid'.tr;
    case 'guest_link_missing':
      return 'guest_live_err_missing'.tr;
    case 'live_not_started':
      return 'guest_live_err_not_started'.tr;
    case 'live_ended':
      return 'guest_live_err_ended'.tr;
    case 'guest_limit_reached':
      return 'guest_live_err_limit'.tr;
    case 'guests_disabled':
      return 'guest_live_err_disabled'.tr;
  }
  return ex.message;
}

/// True when the error means the link itself is dead: polling it again is pointless.
bool guestLiveErrorIsFinal(Object e) {
  final code = ApiException.from(e).code;
  return code == 'guest_link_invalid' || code == 'live_ended' || code == 'guests_disabled';
}

// ─────────────────────────────────────────────────────────────────────────────
// Route helpers (pure)
// ─────────────────────────────────────────────────────────────────────────────

/// `/live/<token>` (or a full URL whose path or hash is that) → token, else null.
String? guestLiveTokenFromRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return null;
  final uri = Uri.tryParse(routeName);
  if (uri == null) return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (seg.length == 2 && seg[0] == 'live' && seg[1].trim().isNotEmpty) {
    return Uri.decodeComponent(seg[1].trim());
  }
  return null;
}

/// The route to start on when the browser URL points at a guest link — path form `/live/x` (the hash
/// strategy would otherwise start on `/`) or hash form `/#/live/x` — else null.
String? guestLiveRouteFromUri(Uri base) {
  final fromPath = guestLiveTokenFromRoute(base.path);
  final fromHash = guestLiveTokenFromRoute(base.fragment);
  final token = fromPath ?? fromHash;
  return token == null ? null : '/live/$token';
}
