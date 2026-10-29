// lib/features/shared/live/live_end_signal.dart
//
// "The host ended the session" instead of "You were removed" after End for everyone (live hardening L2).
//
// The server's end-for-all (../back/services/live_controls.py `end_for_all`) ends a course session by REMOVING
// every participant (the room itself is deleted later, after the egress flushed), so a student's room closes with
// DisconnectReason.participantRemoved — the same reason a single "Remove" gives. A meeting's room is deleted
// (roomDeleted → "the session ended" already). To tell the two apart without a request at disconnect time, the
// host's room publishes one reliable data packet on [kLiveEndForAllTopic] right BEFORE it calls end-for-all
// (`ending: true`), and `ending: false` when the call failed. Every room keeps the last one in a
// [LiveEndForAllSignal]; a removal within [LiveEndForAllSignal.window] of "ending" is the session ending.
//
// The packet only changes the wording of a dialog the person sees anyway (they really were disconnected), so a
// forged one can do no more than that; guests' packets are ignored all the same. Pure, unit-tested in
// test/org/live_end_signal_test.dart.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../teacher/sessions/live/widgets/live_room_rules.dart' show LiveDisconnectAction;
import 'live_controls_api.dart' show liveIsGuestIdentity;

/// The data topic of the host's "ending the room for everyone" packet.
const String kLiveEndForAllTopic = 'room_end';

const String _kType = 'end_for_all';

/// The packet the host publishes: `{"type": "end_for_all", "ending": true|false}`.
Uint8List liveEndForAllPacket({required bool ending}) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'type': _kType, 'ending': ending})));

/// `ending` of a packet on [kLiveEndForAllTopic]; null when it is not one.
bool? parseLiveEndForAllPacket(List<int> data) {
  try {
    final j = jsonDecode(utf8.decode(data));
    if (j is! Map || j['type'] != _kType) return null;
    final ending = j['ending'];
    return ending is bool ? ending : null;
  } catch (_) {
    return null;
  }
}

/// What the room remembers of the host's packets.
class LiveEndForAllSignal {
  LiveEndForAllSignal({this.window = const Duration(minutes: 5)});

  /// How long "ending" counts: a course session's end can take a while server-side before the removal lands.
  final Duration window;

  DateTime? _endingSince;

  /// Takes a packet from [senderIdentity]; true when it was one (handled, whatever it said).
  bool receive(List<int> data, {required String? senderIdentity, DateTime? now}) {
    final ending = parseLiveEndForAllPacket(data);
    if (ending == null) return false;
    if (senderIdentity == null || senderIdentity.isEmpty || liveIsGuestIdentity(senderIdentity)) return true;
    _endingSince = ending ? (now ?? DateTime.now()) : null;
    return true;
  }

  /// The host said it is ending the room for everyone, recently enough to explain a removal now.
  bool hostEnding(DateTime now) {
    final since = _endingSince;
    return since != null && !now.isBefore(since) && now.difference(since) <= window;
  }
}

/// The disconnect action once the host's packet is known: a removal right after "ending for everyone" is the
/// session ending (no "you were removed", no Rejoin).
LiveDisconnectAction liveDisconnectActionAfterEndSignal(LiveDisconnectAction action, {required bool hostEnding}) =>
    action == LiveDisconnectAction.removed && hostEnding ? LiveDisconnectAction.sessionEnded : action;
