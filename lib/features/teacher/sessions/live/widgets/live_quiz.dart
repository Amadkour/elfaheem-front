// lib/features/teacher/sessions/live/widgets/live_quiz.dart
//
// "A quiz started" over the LiveKit room (Track D.3, docs/polish/realtime-inventory.md): the teacher's client
// publishes ONE reliable data packet on topic 'quiz' when they publish an exam of the course while their room is
// open, and every student's RoomPage fetches GET /courses/{id}/exams/active on receipt — instead of polling it
// every 30 s. One fetch on join and a 5-minute fallback poll stay in room.dart; the server's live event
// `quiz_started{course_id}` (LiveEvents.quizStarted), when the backend emits it, triggers the same fetch.
//
// Wire format (LiveKit data packet, reliable, topic 'quiz'):
//   {"type":"quiz_started","exam_id":12,"course_id":3}
//
// [LiveQuizBroadcast] is the hook between the exam hub and the room: TeacherExamProvider.togglePublish →
// LiveQuizBroadcast.started(examId:, courseId:); the teacher's RoomPage listens to [LiveQuizBroadcast.latest] and
// publishes [encode]. Pure (encode / decode) so it can be unit-tested without a Room.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

const kLiveQuizTopic = 'quiz';

class LiveQuizStart {
  const LiveQuizStart({required this.examId, this.courseId});

  final int examId;
  final int? courseId;
}

class LiveQuizBroadcast {
  LiveQuizBroadcast._();

  /// The latest exam the teacher published (null until the first). Set again even when equal: listeners compare
  /// nothing.
  static final ValueNotifier<LiveQuizStart?> latest = ValueNotifier<LiveQuizStart?>(null);

  static void started({required int examId, int? courseId}) {
    latest.value = null;
    latest.value = LiveQuizStart(examId: examId, courseId: courseId);
  }

  static List<int> encode(LiveQuizStart s) => utf8.encode(jsonEncode({
        'type': 'quiz_started',
        'exam_id': s.examId,
        if (s.courseId != null) 'course_id': s.courseId,
      }));

  /// The packet's start, or null for anything else on the topic.
  static LiveQuizStart? decode(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['type'] != 'quiz_started') return null;
      final examId = int.tryParse('${j['exam_id'] ?? ''}');
      if (examId == null) return null;
      return LiveQuizStart(examId: examId, courseId: int.tryParse('${j['course_id'] ?? ''}'));
    } catch (_) {
      return null;
    }
  }
}
