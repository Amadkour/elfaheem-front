// lib/features/live/live_room_words.dart
//
// The words of a live room depend on its kind (D-106): a course session is «الحصة» / "session", a calendar meeting
// (a student's free meeting, "Meet now", a meeting link, a guest link to a meeting) is «الاجتماع» / "meeting" — on
// the pre-join page, the waiting-for-host page, the guest landing page and everywhere in the room.
//
//   liveRoomNoun(kind)          «حصة» / «اجتماع» · "session" / "meeting" (definite: «الحصة» / «الاجتماع»)
//   liveTr(key, kind)           a translation.json text: `<key>_meeting` for a meeting when it exists, else `<key>`
//   liveT(kind, ar:, en:, …)    an inline t(ar, en) text with its meeting wording
//   liveRoleLabel(host:, kind)  Teacher / Student in a session, Host / Participant in a meeting
//   LiveRoomWords.current       the kind of the room that is open now. RoomPage sets it while it is mounted, so
//                               the leaf texts deep in the room (the background-call notification, the whiteboard
//                               export hint, the share sheet) need no kind threaded through every widget.
//
// Arabic grammar: «الحصة» is feminine, «الاجتماع» masculine — a meeting text carries its own verbs and adjectives
// («انتهى الاجتماع», «هذا الاجتماع», «قد يتم تسجيله»), never the session text with the noun swapped.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomKind;

/// The kind of the live room that is open now (D-106). Only one room is open at a time (LiveRoomHost).
class LiveRoomWords {
  LiveRoomWords._();

  static LiveRoomKind current = LiveRoomKind.session;

  /// RoomPage.initState: this room's kind is the one every room text follows.
  static void enter(LiveRoomKind kind) => current = kind;

  /// RoomPage.dispose: back to the default, unless another room took over meanwhile.
  static void leave(LiveRoomKind kind) {
    if (current == kind) current = LiveRoomKind.session;
  }
}

bool _ar() => AppConfig.lang == 'ar';

/// «حصة» / «اجتماع» (definite: «الحصة» / «الاجتماع»), "session" / "meeting" ([capital]: "Session" / "Meeting").
String liveRoomNoun(LiveRoomKind kind, {bool definite = false, bool capital = false}) {
  final meeting = kind == LiveRoomKind.meeting;
  if (_ar()) {
    final n = meeting ? 'اجتماع' : 'حصة';
    return definite ? 'ال$n' : n;
  }
  final n = meeting ? 'meeting' : 'session';
  return capital ? '${n[0].toUpperCase()}${n.substring(1)}' : n;
}

/// The translation of [key] for a room of [kind] (default: the open room, [LiveRoomWords.current]): a meeting reads
/// `<key>_meeting` when translation.json has it, else the key itself (missing → the key, as `.tr`).
String liveTr(String key, [LiveRoomKind? kind]) {
  if ((kind ?? LiveRoomWords.current) == LiveRoomKind.meeting) {
    final m = '${key}_meeting';
    if (translation.containsKey(m)) return translate(m);
  }
  return translate(key);
}

/// [liveTr] with `{name}` placeholders filled (as trp in admin_common.dart).
String liveTrp(String key, Map<String, Object?> params, [LiveRoomKind? kind]) {
  var s = liveTr(key, kind);
  params.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  return s;
}

/// An inline text with its meeting wording (default kind: the open room).
String liveT(LiveRoomKind? kind,
    {required String ar, required String en, required String meetingAr, required String meetingEn}) {
  final meeting = (kind ?? LiveRoomWords.current) == LiveRoomKind.meeting;
  if (_ar()) return meeting ? meetingAr : ar;
  return meeting ? meetingEn : en;
}

/// The role tag of a person: Teacher / Student in a course session, Host / Participant in a meeting.
String liveRoleLabel({required bool host, LiveRoomKind? kind}) {
  final meeting = (kind ?? LiveRoomWords.current) == LiveRoomKind.meeting;
  if (meeting) return host ? translate('lr_host') : (_ar() ? 'مشارك' : 'Participant');
  return translate(host ? 'teacher' : 'student');
}
