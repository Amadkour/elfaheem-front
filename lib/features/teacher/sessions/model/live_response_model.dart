class LiveResponseModel {
  final int sessionId;
  final String url;
  final String token;

  /// Whether this live session is recorded (`recording_enabled` from the server;
  /// the session creator can switch it off per session).
  final bool recordingEnabled;

  LiveResponseModel(
      {required this.sessionId, required this.url, required this.token, this.recordingEnabled = true});

  Map<String, dynamic> get toJson =>
      {'session_id': sessionId, 'url': url, 'token': token, 'recording_enabled': recordingEnabled};
}