class LiveResponseModel {
  final int sessionId;
  final String url;
  final String token;

  LiveResponseModel(
      {required this.sessionId, required this.url, required this.token});

  Map<String, dynamic> get toJson =>
      {'session_id': sessionId, 'url': url, 'token': token};
}