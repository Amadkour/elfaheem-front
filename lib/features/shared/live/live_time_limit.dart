// lib/features/shared/live/live_time_limit.dart
//
// The free-time limit of a student's live meeting (docs/backend/live-rooms-spec.md §8, §11).
//
//   time_limit      every successful meeting join payload carries `time_limit: {ends_at, free_minutes} | null`
//                   (null = unlimited). `ends_at` is naive UTC. parseLiveTimeLimit / parseNaiveUtc read it.
//   LiveTimeLimit   pure countdown rules: what is left, the tone of the pill, when the owner is offered
//                   "Upgrade" (from [kLiveUpgradeWindow] = 3 minutes left), and whether a room the server deleted
//                   was ended by the limit (the owner then sees "Free time ended" with Subscribe).
//   LiveTimeLimitPill        the countdown pill drawn in the room (plain values).
//   LiveFreeTimeEndedCard    the owner's "Free time ended" card (plain values), shown in a dialog by the room.
//
// Everything here takes plain values: test/org/live_time_limit_test.dart (rules) and
// test/ui/live_time_limit_layout_test.dart (layout harness).
library;

import 'package:flutter/material.dart';

import '../../admin/admin_common.dart' show t;
import '../../teacher/sessions/live/widgets/live_palette.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// The owner is offered "Upgrade" once this little time is left.
const Duration kLiveUpgradeWindow = Duration(minutes: 3);

/// A room the server deleted this close to (or after) `ends_at` was ended by the limit: the server's tick runs
/// every 60 s, so the deletion lands up to a minute (plus clock skew) after the end.
const Duration kLiveLimitEndSlack = Duration(seconds: 90);

/// A naive-UTC ISO string (the server's convention: no `Z`) → a UTC DateTime. A string that carries its own offset
/// is honoured. Null for anything unreadable.
DateTime? parseNaiveUtc(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v.toUtc();
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(s);
  final d = DateTime.tryParse(hasZone ? s : '${s}Z');
  return d?.toUtc();
}

/// `time_limit` of a join payload / meeting detail → its end (UTC), or null when unlimited / absent.
DateTime? parseLiveTimeLimit(dynamic timeLimit) {
  if (timeLimit is! Map) return null;
  return parseNaiveUtc(timeLimit['ends_at']);
}

/// `time_limit.free_minutes`, or null.
int? parseLiveFreeMinutes(dynamic timeLimit) {
  if (timeLimit is! Map) return null;
  return int.tryParse('${timeLimit['free_minutes'] ?? ''}');
}

/// How urgent the countdown looks.
enum LiveLimitTone { calm, warn, over }

/// The countdown of one room. [isOwner] = the meeting's owner (the only one who can lift the limit by
/// subscribing); [lifted] = the owner subscribed during this visit (the pill disappears).
class LiveTimeLimit {
  const LiveTimeLimit({required this.endsAt, this.isOwner = false, this.lifted = false});

  final DateTime endsAt;
  final bool isOwner;
  final bool lifted;

  LiveTimeLimit copyWith({bool? lifted}) => LiveTimeLimit(endsAt: endsAt, isOwner: isOwner, lifted: lifted ?? this.lifted);

  /// Never negative.
  Duration remaining(DateTime now) {
    final d = endsAt.toUtc().difference(now.toUtc());
    return d.isNegative ? Duration.zero : d;
  }

  bool expired(DateTime now) => !now.toUtc().isBefore(endsAt.toUtc());

  /// Everyone sees the pill until the owner subscribes.
  bool showPill(DateTime now) => !lifted;

  /// The owner, from [kLiveUpgradeWindow] left (and after the end, while still in the room).
  bool showUpgrade(DateTime now) => isOwner && !lifted && remaining(now) <= kLiveUpgradeWindow;

  LiveLimitTone tone(DateTime now) {
    final r = remaining(now);
    if (r == Duration.zero) return LiveLimitTone.over;
    if (r <= kLiveUpgradeWindow) return LiveLimitTone.warn;
    return LiveLimitTone.calm;
  }

  /// The server deleted the room: was it the limit? (not lifted, and the end is near or past).
  bool endedByLimit(DateTime now, {Duration slack = kLiveLimitEndSlack}) =>
      !lifted && !now.toUtc().isBefore(endsAt.toUtc().subtract(slack));

  /// The owner gets "Free time ended" with Subscribe; everyone else the usual "ended" dialog.
  bool showFreeTimeEnded(DateTime now) => isOwner && endedByLimit(now);

  /// `mm:ss`, or `h:mm:ss` from an hour.
  static String format(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill (the room)
// ─────────────────────────────────────────────────────────────────────────────

/// "Free time 12:34" — and, for the owner near the end, an "Upgrade" button. Dark room styling (LivePalette).
class LiveTimeLimitPill extends StatelessWidget {
  const LiveTimeLimitPill({
    super.key,
    required this.remaining,
    required this.tone,
    this.showUpgrade = false,
    this.onUpgrade,
    this.busy = false,
  });

  final Duration remaining;
  final LiveLimitTone tone;
  final bool showUpgrade;
  final VoidCallback? onUpgrade;

  /// The plan sheet is open: the button shows a spinner.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      LiveLimitTone.calm => LivePalette.textMid,
      LiveLimitTone.warn => LivePalette.warning,
      LiveLimitTone.over => LivePalette.danger,
    };
    final label = tone == LiveLimitTone.over
        ? t('انتهى الوقت المجاني', 'Free time is over')
        : '${t('الوقت المجاني', 'Free time')} ${LiveTimeLimit.format(remaining)}';
    return Container(
      key: const ValueKey('live_room.time_limit'),
      padding: EdgeInsetsDirectional.fromSTEB(10, 4, showUpgrade ? 4 : 10, 4),
      decoration: BoxDecoration(
        color: LivePalette.shade(0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.hourglass_bottom_rounded, size: 12, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3),
          ),
        ),
        if (showUpgrade) ...[
          const SizedBox(width: 8),
          Material(
            color: LivePalette.warning,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              key: const ValueKey('live_room.time_limit.upgrade'),
              borderRadius: BorderRadius.circular(999),
              onTap: busy ? null : onUpgrade,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (busy)
                    const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.6, color: Colors.black87))
                  else
                    const Icon(Icons.bolt_rounded, size: 13, color: Colors.black87),
                  const SizedBox(width: 4),
                  Text(
                    t('ترقية', 'Upgrade'),
                    maxLines: 1,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black87),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// "Free time ended" (the owner, after the server ended the room)
// ─────────────────────────────────────────────────────────────────────────────

/// The owner's end card: the meeting stopped because the free minutes ran out; Subscribe opens the live plan,
/// Close leaves the room. [freeMinutes] (when known) is said in the text.
class LiveFreeTimeEndedCard extends StatelessWidget {
  const LiveFreeTimeEndedCard({super.key, required this.onSubscribe, required this.onClose, this.freeMinutes});

  final VoidCallback onSubscribe;
  final VoidCallback onClose;
  final int? freeMinutes;

  @override
  Widget build(BuildContext context) {
    final mins = freeMinutes;
    final msg = mins == null
        ? t('انتهت الدقائق المجانية لهذا الاجتماع. اشترك في باقة الاجتماعات المباشرة لتكمل دون حد للوقت، ثم أعد فتح الاجتماع.',
            'The free minutes of this meeting ran out. Subscribe to the live-meeting plan to go on without a time limit, then open the meeting again.')
        : t('انتهت الدقائق المجانية ($mins دقيقة) لهذا الاجتماع. اشترك في باقة الاجتماعات المباشرة لتكمل دون حد للوقت، ثم أعد فتح الاجتماع.',
            'The $mins free minutes of this meeting ran out. Subscribe to the live-meeting plan to go on without a time limit, then open the meeting again.');
    return Container(
      key: const ValueKey('live_room.free_time_ended'),
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      decoration: BoxDecoration(
        color: LivePalette.surfaceHi,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: LivePalette.glassBorder),
        boxShadow: [BoxShadow(color: LivePalette.shade(0.5), blurRadius: 20)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: LivePalette.warning.withValues(alpha: 0.14),
            border: Border.all(color: LivePalette.warning.withValues(alpha: 0.45), width: 2),
          ),
          child: Icon(Icons.hourglass_disabled_rounded, color: LivePalette.warning, size: 30),
        ),
        const SizedBox(height: 16),
        Text(
          t('انتهى الوقت المجاني', 'Free time ended'),
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: AppFonts.family, color: LivePalette.textHigh, fontWeight: FontWeight.w800, fontSize: 19),
        ),
        const SizedBox(height: 8),
        Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: AppFonts.family, color: LivePalette.textMid, fontSize: 13.5, height: 1.5),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const ValueKey('live_room.free_time_ended.subscribe'),
            style: FilledButton.styleFrom(
              backgroundColor: LivePalette.warning,
              foregroundColor: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: onSubscribe,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(t('اشترك', 'Subscribe'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('live_room.free_time_ended.close'),
          onPressed: onClose,
          child: Text(t('إغلاق', 'Close'), style: TextStyle(fontFamily: AppFonts.family, color: LivePalette.textMid, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
