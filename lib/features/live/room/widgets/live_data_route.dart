// lib/features/live/room/widgets/live_data_route.dart
//
// Which handler a LiveKit data packet goes to, by its topic. Any participant can publish data, so a packet on
// a topic the room does not know is dropped (debug log only) rather than shown to everyone.
library;

import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart' show kAnnotLaserTopic, kAnnotTopic;
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart' show kBoardLaserTopic, kBoardTopic;
import 'package:flutter_education_app/features/live/live_room_people.dart' show kLiveServerAskTopic, kLiveServerHandTopic;
import 'package:flutter_education_app/features/live/live_share_arbiter.dart' show kLiveShareTopic;
import 'package:flutter_education_app/features/live/room/widgets/live_chat.dart' show kLiveChatTopic;
import 'package:flutter_education_app/features/live/room/widgets/live_hands.dart' show kLiveHandTopic;
import 'package:flutter_education_app/features/live/room/widgets/live_quiz.dart' show kLiveQuizTopic;
import 'package:flutter_education_app/features/live/room/widgets/live_reactions.dart' show kLiveReactionTopic;

enum LiveDataRoute {
  reaction,
  quiz,

  /// Annotation over the shared screen (strokes, permission, board snapshots, laser).
  annotation,

  /// The presented whiteboard: board state, ink, shapes, text, snapshots, laser (D-087).
  board,

  /// One share at a time: requests, answers, stops (live_share_arbiter.dart).
  share,

  /// WP1: the server's host-only `nb.hand` / `nb.ask` messages about hidden students (a hand raised, a question).
  serverSignal,

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
    case kBoardTopic:
    case kBoardLaserTopic:
      return LiveDataRoute.board;
    case kLiveShareTopic:
      return LiveDataRoute.share;
    case kLiveServerHandTopic:
    case kLiveServerAskTopic:
      return LiveDataRoute.serverSignal;
    case kLiveHandTopic:
    case kLiveChatTopic:
    case null:
    case '':
      return LiveDataRoute.handOrChat;
    default:
      return LiveDataRoute.ignore;
  }
}
