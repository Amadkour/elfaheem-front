// Live room — how long a participant has been in the room ("joined 12 min ago" / "stayed 1 h 5 min").
// Pure, unit-tested (test/org/live_duration_test.dart).
//
// The server's attendance rows are NAIVE UTC: `/live-sessions/{id}/participants` sends `str(check_in_date)`
// ("2026-10-28 08:00:00.123456", "None" when empty). `DateTime.parse` read that as device-local time, so the
// duration was off by the UTC offset ("joined 120 min ago" right after joining in Cairo). LiveKit's
// `Participant.joinedAt` is a real instant (local), so both sides are compared as UTC instants.
library;

/// A server timestamp → UTC instant. A naive string is UTC, a `Z` / `±hh:mm` suffix is honoured, a date-only
/// string is midnight UTC, a [DateTime] is converted; null, '', 'None', 'null' and garbage → null.
DateTime? liveParseServerUtc(Object? v) {
  if (v is DateTime) return v.toUtc();
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty || s == 'null' || s == 'None') return null;
  final hasZone = s.endsWith('Z') || s.endsWith('z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  final String iso;
  if (hasZone) {
    iso = s;
  } else if (s.length <= 10) {
    iso = '${s}T00:00:00Z';
  } else {
    iso = '${s}Z';
  }
  return DateTime.tryParse(iso)?.toUtc();
}

/// Whole minutes from [from] to [to] (still in the room: [now], default the clock), compared as UTC instants.
/// Never negative (the device clock may run behind the server's). Null when [from] is null.
int? liveMinutesBetween(DateTime? from, DateTime? to, {DateTime? now}) {
  if (from == null) return null;
  final end = (to ?? now ?? DateTime.now()).toUtc();
  final mins = end.difference(from.toUtc()).inMinutes;
  return mins < 0 ? 0 : mins;
}
