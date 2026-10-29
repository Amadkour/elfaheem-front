// lib/features/teacher/sessions/live/widgets/live_data_route.dart
//
// Which handler a LiveKit data packet goes to, by its topic. Any participant can publish data, so a packet on
// a topic the room does not know is dropped (debug log only) rather than shown to everyone.
library;

import '../annotation/annotation_protocol.dart' show kAnnotLaserTopic, kAnnotTopic;
import 'live_chat.dart' show kLiveChatTopic;
import 'live_hands.dart' show kLiveHandTopic;
import 'live_quiz.dart' show kLiveQuizTopic;
import 'live_reactions.dart' show kLiveReactionTopic;

enum LiveDataRoute {
  reaction,
  quiz,

  /// Annotation over the shared screen (strokes, permission, board snapshots, laser).
  annotation,

  /// Hands and chat: matched by topic, or by payload type for senders that set no topic.
  handOrChat,

  /// Unknown topic: ignored.
  ignore,
}

LiveDataRoute liveDataRoute(String? topic) {
  switch (topic) {
    case kLiveReactionTopic:
      return LiveDataRoute.reaction;
    case kLiveQuizTopic:
      return LiveDataRoute.quiz;
    case kAnnotTopic:
    case kAnnotLaserTopic:
      return LiveDataRoute.annotation;
    case kLiveHandTopic:
    case kLiveChatTopic:
    case null:
    case '':
      return LiveDataRoute.handOrChat;
    default:
      return LiveDataRoute.ignore;
  }
}
