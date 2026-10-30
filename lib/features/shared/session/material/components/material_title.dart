// The title a material card shows (pure, unit-tested in test/ui/session_material_title_test.dart).
//
// The server names a class recording "<session name> — تسجيل الحصة[ (لقاء n)]" (LiveKit_service.py,
// local_recorder.py). Inside the session's own row the session name repeats the row's title and the suffix repeats
// the "Recorded" pill, and the two together were cut to "نن — تسجيل الح…" (N9). Such a name reads
// "Session recording" (· "round n" for a later meeting); any other name is kept as the teacher wrote it.

import '../../../../../config/app_config.dart';

final RegExp _serverRecording = RegExp(r'^(.*?)\s*[—–-]\s*تسجيل الحصة\s*(?:\(\s*لقاء\s*(\d+)\s*\))?\s*$');

/// [name] as a card title; [recorded] = the material is a class recording.
String materialTitle(String name, {required bool recorded}) {
  if (!recorded) return name;
  final m = _serverRecording.firstMatch(name.trim());
  if (m == null) return name;
  final round = m.group(2);
  final base = 'material_session_recording'.tr;
  return round == null ? base : '$base · ${'material_recording_round'.tr.replaceAll('{n}', round)}';
}

/// What a rating row draws (N9).
enum RatingShow { stars, invite, none }

/// The stars only once someone rated: the server sends `rate: {total: 0, average: 0.0}` for every file and session,
/// and "☆☆☆☆☆ 0.0 (0)" under each read as noise. A student who may rate gets a small "Rate" link instead.
RatingShow ratingShow({required int total, required bool canRate}) =>
    total > 0 ? RatingShow.stars : (canRate ? RatingShow.invite : RatingShow.none);

/// A student may rate a session once it has happened or he finished one of its files; a teacher never rates.
bool sessionRateable({required bool isTeacher, required int completedFiles, DateTime? scheduledAt, DateTime? now}) =>
    !isTeacher && (completedFiles > 0 || (scheduledAt != null && scheduledAt.isBefore(now ?? DateTime.now())));
