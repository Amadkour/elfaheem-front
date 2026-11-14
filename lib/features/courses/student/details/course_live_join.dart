// lib/features/courses/student/details/course_live_join.dart — a student INTO a course's live session, from anywhere.
//
//   openCourseLiveRoom(context, sessionId:, courseId:, …)   the pre-join page of that session (GET
//                                                            /live-sessions/{id}/join on Join; 202 → the lobby wait)
//   joinCourseLiveAsStudent(api, sessionId)                 that join call → LiveResponseModel | JoinOutcome
//
// The course page's "Live now" card (wide: the side column, phone: the spotlight) and the home's "Live now" banner
// open the room through here, so they no longer depend on the course page's TeacherCourseScreenProvider (the side
// card only switched to the Live tab — on a wide window already on that tab the tap did nothing). Same join as
// TeacherCourseScreenProvider.joinLive for a student. The pre-join page waits for Join (D-106).
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/view_as_state.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/live/live_controls_api.dart' show liveJoinRefusalText;
import 'package:flutter_education_app/features/live/live_room.dart' show JoinOutcome;
import 'package:flutter_education_app/features/live/room/join_args.dart';
import 'package:flutter_education_app/features/teacher/sessions/model/live_response_model.dart';

/// GET /live-sessions/{id}/join as a student: the room (LiveResponseModel), or the lobby outcome (202 waiting …).
/// A refusal of the host's controls (423 room_locked, 403 participant_removed) is rethrown so the pre-join page says
/// why; anything else returns null (the pre-join page shows its generic failure).
Future<dynamic> joinCourseLiveAsStudent(ApiClient api, int sessionId) async {
  try {
    final result = await api.get('/api/v1/live-sessions/$sessionId/join');
    if (result is! Map) return null;
    final m = Map<String, dynamic>.from(result);
    final outcome = JoinOutcome.parse(m);
    if (!outcome.isAdmitted) return outcome;
    return LiveResponseModel(
      sessionId: sessionId,
      url: m['ws_url'] as String? ?? '',
      token: m['token'] as String? ?? '',
      recordingEnabled: m['recording_enabled'] as bool? ?? true,
      liveStartedAt: outcome.liveStartedAt,
      liveConfig: outcome.liveConfig, // D-090
    );
  } on ApiException catch (e) {
    if (liveJoinRefusalText(e) != null) rethrow;
    return null;
  }
}

/// The student's pre-join page of a live course session; the student presses Join there (D-106). Leaving the room
/// marks the session complete, as the Live tab's join does.
Future<void> openCourseLiveRoom(
  BuildContext context, {
  required int sessionId,
  required int courseId,
  String? sessionName,
  String? hostName,
}) async {
  final auth = context.read<MyAuthProvider>();
  final api = ApiClient();
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => deferredPreJoin(
      args: JoinArgs(
        sessionId: sessionId,
        courseId: courseId,
        maxStudents: 100,
        isTeacher: false,
        userId: auth.currentUser?.id ?? -1,
        userName: auth.currentUser?.name ?? '--',
        sessionName: sessionName,
        hostName: hostName,
        apiClient: api,
        onStart: () => joinCourseLiveAsStudent(api, sessionId),
        onEnd: () async {},
        onComplete: () async {
          if (ViewAsState.active) return; // view-as is read-only
          try {
            await api.post('/api/v1/sessions/$sessionId/complete');
          } catch (_) {}
        },
      ),
    ),
  ));
}
