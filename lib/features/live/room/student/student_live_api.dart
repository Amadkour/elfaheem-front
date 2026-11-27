// lib/features/live/room/student/student_live_api.dart
//
// The student's private live room (backend D-1950, docs/redesign/api/privacy.md): the join token of a student in a
// course session is PRIVATE (hidden, no data channel, metadata {"privacy": "private"}), so the hand and the question
// to the teacher go through the server, never the data channel:
//
//   POST {ref.basePath}/hand {raised}   → {raised}
//   POST {ref.basePath}/ask  {text}     → {sent}       (≤ 500 characters; 429 after 20 a minute)
//
// [liveTokenIsPrivate] reads the local participant's metadata: that is what turns the room's student mode on, so
// every way into a room (the course page, the home's live banner, a rejoin) gets it without a new join field.
library;

import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomRef;

/// The longest question the server takes.
const int kLiveAskMaxLength = 500;

/// True when a participant's [metadata] (the LiveKit token's JSON) marks a private learner.
bool liveTokenIsPrivate(String? metadata) {
  if (metadata == null || metadata.trim().isEmpty) return false;
  try {
    final m = jsonDecode(metadata);
    return m is Map && m['privacy'] == 'private' && m['role'] != 'guest';
  } catch (_) {
    return false;
  }
}

class StudentLiveApi {
  StudentLiveApi(this.ref, {ApiClient? api}) : _api = api ?? ApiClient();

  final LiveRoomRef ref;
  final ApiClient _api;

  /// Raises or lowers the hand; answers what the server stored.
  Future<bool> hand(bool raised) async {
    final r = await _api.post('${ref.basePath}/hand', body: {'raised': raised});
    return r is Map ? r['raised'] == true : raised;
  }

  /// Sends a question to the teacher only.
  Future<bool> ask(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final r = await _api.post(
      '${ref.basePath}/ask',
      body: {'text': t.length > kLiveAskMaxLength ? t.substring(0, kLiveAskMaxLength) : t},
    );
    return r is Map ? r['sent'] != false : true;
  }
}

/// The guest's side of the same two calls (a public guest link): no account, so the PUBLIC routes with the guest's
/// own LiveKit token, sent with `auth: false` (no bearer, and a 401 never sends the visitor to the login screen):
///
///   POST /api/v1/public/live/hand {token, raised}   → {raised}
///   POST /api/v1/public/live/ask  {token, text}     → {sent}     (401 bad_token, 403 participant_removed)
class GuestStudentLiveApi extends StudentLiveApi {
  GuestStudentLiveApi(super.ref, {required this.token, super.api});

  /// The guest's LiveKit token (the join answer's, RoomPage.guestToken).
  final String? Function() token;

  @override
  Future<bool> hand(bool raised) async {
    final r = await _api.post('/api/v1/public/live/hand', body: {'token': token() ?? '', 'raised': raised}, auth: false);
    return r is Map ? r['raised'] == true : raised;
  }

  @override
  Future<bool> ask(String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final r = await _api.post(
      '/api/v1/public/live/ask',
      body: {'token': token() ?? '', 'text': t.length > kLiveAskMaxLength ? t.substring(0, kLiveAskMaxLength) : t},
      auth: false,
    );
    return r is Map ? r['sent'] != false : true;
  }
}

/// Which room a person gets: the private one (student/student_room_view.dart: the stage, "you and the teacher", no
/// head count, no participant list) for a private learner AND for every guest of a public link (each guest's token is
/// private, D-1950); the full room for the teacher, a host and everyone else.
bool liveRoomIsPrivate({required bool isTeacher, required bool isGuest, required bool host, String? metadata}) {
  if (isGuest) return true;
  return !isTeacher && !host && liveTokenIsPrivate(metadata);
}
