class LiveResponseModel {
  final int sessionId;
  final String url;
  final String token;

  /// Whether this live session is recorded (`recording_enabled` from the server;
  /// the session creator can switch it off per session).
  final bool recordingEnabled;

  /// When the free time of a student's meeting ends (`time_limit.ends_at`, UTC; docs/backend/live-rooms-spec.md
  /// §8). Null = no limit. The room shows a countdown and the owner an "Upgrade" (live_time_limit.dart).
  final DateTime? freeEndsAt;

  /// When the room really went live (`live_started_at`, UTC; spec Part 3 §16): a meeting's first join, a course
  /// session's start. The room's info sheet counts "Live for" from it. Null = unknown (an older server).
  final DateTime? liveStartedAt;

  LiveResponseModel(
      {required this.sessionId,
      required this.url,
      required this.token,
      this.recordingEnabled = true,
      this.freeEndsAt,
      this.liveStartedAt});

  Map<String, dynamic> get toJson => {
        'session_id': sessionId,
        'url': url,
        'token': token,
        'recording_enabled': recordingEnabled,
        'time_limit': freeEndsAt == null ? null : {'ends_at': freeEndsAt!.toUtc().toIso8601String()},
        'live_started_at': liveStartedAt?.toUtc().toIso8601String(),
      };
}