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
