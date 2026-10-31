// lib/features/shared/course/course_space/course_sessions.dart
//
// The session list of the course page, the same for the student and the teacher: a timeline inside ONE calm card.
// Plain values only (no provider), so the layout harness and the visual renders pump it; the role screens
// (SessionMaterialCard, used by student/…/session.dart and teacher/…/sessions_section.dart) draw each row with
// [CourseSessionTile] and add their own actions in its slots.
//
//   ┌───────────────────────────────────────────────┐
//   │  ✓✓  5 completed sessions             Show    │   CourseSessionFoldRow (the leading done sessions, long lists)
//   │  │                                            │
//   │  ⑥  Logistic regression          [Up next]    │   CourseSessionTile: node · title · chip · trailing
//   │  │   ▶ Recorded  ◷ 45 min  ⌀ 4             │                      meta (kind · date · length · files)
//   │  │   ━━━━━━━━━━━──────── 2/5                  │                      progress (student) · below (actions)
//   │  ●  Neural networks              [● Live]     │
//   │  ⑧  Sun 2 Nov · 6:00 PM                       │
//   └───────────────────────────────────────────────┘
//
// Pure helpers (unit-tested in test/ui/course_space_layout_test.dart): courseStudentStates, courseTeacherStates,
// courseSessionGroups (month headers),
// courseSessionRail, courseSessionFoldCount, courseSessionLength.
library;

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/app_time.dart';
import '../../../../core/plural.dart' show arabicPluralForm;
import '../../../../core/display/app_fonts.dart';
import '../../../../design/app_display.dart' show syncMotionLoop;
import '../../../../utils/helpers.dart';
import 'course_space.dart' show kCourseGutter;

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

TextStyle _ts(double size, FontWeight w, Color color, {double? h}) =>
    TextStyle(fontFamily: AppFonts.family, fontSize: size, fontWeight: w, color: color, height: h);

/// A tone as ink on the page: in dark mode a deep brand colour is mixed toward the light text.
Color _ink(BuildContext context, Color tone) {
  final c = context.colors;
  return c.isDark ? Color.lerp(tone, c.textDark, 0.35)! : tone;
}

// ═════════════════════════════════════════════════════════════════════════════
// Plain values + pure helpers
// ═════════════════════════════════════════════════════════════════════════════

/// Where a session stands for the person looking at it.
enum CourseSessionState {
  /// On air right now.
  live,

  /// The one to take next (student: first open lesson not done · teacher: the soonest scheduled one).
  next,

  /// Completed (student) / delivered (teacher: its time has passed).
  done,

  /// Available, nothing special.
  open,

  /// Student only: not reachable yet (prerequisite, exam or not enrolled).
  locked,

  /// Has a start time in the future.
  scheduled,
}

/// What kind of session it is (the icon and word on the meta line).
enum CourseSessionKind { live, recorded, section }

/// The tone of one half of the timeline line; null = no line.
enum CourseRailTone { plain, done }

typedef CourseSessionRail = ({CourseRailTone? top, CourseRailTone? bottom});

/// One row of the session timeline.
class CourseSessionView {
  const CourseSessionView({
    required this.number,
    required this.title,
    this.subtitle,
    this.kind = CourseSessionKind.recorded,
    this.state = CourseSessionState.open,
    this.when,
    this.durationMinutes = 0,
    this.materials = 0,
    this.materialsDone = 0,
    this.showProgress = false,
    this.hint,
  });

  final int number;
  final String title;
  final String? subtitle;
  final CourseSessionKind kind;
  final CourseSessionState state;

  /// The scheduled start as a UTC instant (drawn through AppTime); null = none.
  final DateTime? when;
  final int durationMinutes;
  final int materials, materialsDone;

  /// Student: the materials progress bar under the meta line (only while partly done).
  final bool showProgress;

  /// A short warning in place of the files count (teacher: "No materials yet").
  final String? hint;

  /// 0…1 while partly done, else null.
  double? get progress {
    if (!showProgress || materials <= 0 || materialsDone <= 0 || materialsDone >= materials) return null;
    return materialsDone / materials;
  }
}

/// Student: is this session done? (N1: the server's `completeness` is true for a session with nothing in it, so a
/// course of empty future sessions read all done at 0%.)
/// - a future session is never done;
/// - with materials: the server's flag (every material completed AND the session's exam passed, if it has one),
///   checked against the counts;
/// - without materials: done only when it already took place (start + length has passed) and the server agrees —
///   an ended live session with nothing to watch has nothing left to do; one without a date has not happened.
bool courseStudentSessionDone({
  required bool serverDone,
  required int materials,
  required int materialsDone,
  DateTime? when,
  int minutes = 0,
  DateTime? now,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  if (when != null && when.isAfter(t)) return false;
  if (materials > 0) return serverDone && materialsDone >= materials;
  if (when == null) return false;
  return serverDone && !when.add(Duration(minutes: minutes)).isAfter(t);
}

/// Student: one state per session, in list order. The first session that is neither live, locked nor done is "next";
/// a future session is never done.
List<CourseSessionState> courseStudentStates(
  List<({bool live, bool locked, bool done, DateTime? when})> sessions, {
  DateTime? now,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  var nextTaken = false;
  final out = <CourseSessionState>[];
  for (final s in sessions) {
    final future = s.when != null && s.when!.isAfter(t);
    if (s.live) {
      out.add(CourseSessionState.live);
    } else if (s.locked) {
      out.add(CourseSessionState.locked);
    } else if (s.done && !future) {
      out.add(CourseSessionState.done);
    } else if (!nextTaken && !future) {
      nextTaken = true;
      out.add(CourseSessionState.next);
    } else {
      out.add(future ? CourseSessionState.scheduled : CourseSessionState.open);
    }
  }
  return out;
}

/// Teacher: live · done (its start + length has passed) · next (the soonest future start) · scheduled · open.
List<CourseSessionState> courseTeacherStates(
  List<({bool live, DateTime? when, int minutes})> sessions, {
  DateTime? now,
}) {
  final t = (now ?? DateTime.now()).toUtc();
  int? soonest;
  for (var i = 0; i < sessions.length; i++) {
    final w = sessions[i].when;
    if (sessions[i].live || w == null || !w.isAfter(t)) continue;
    if (soonest == null || w.isBefore(sessions[soonest].when!)) soonest = i;
  }
  return [
    for (var i = 0; i < sessions.length; i++)
      if (sessions[i].live)
        CourseSessionState.live
      else if (i == soonest)
        CourseSessionState.next
      else if (sessions[i].when == null)
        CourseSessionState.open
      else if (sessions[i].when!.isAfter(t))
        CourseSessionState.scheduled
      else if (sessions[i].when!.add(Duration(minutes: sessions[i].minutes)).isAfter(t))
        CourseSessionState.open
      else
        CourseSessionState.done,
  ];
}

/// The two halves of the line through row [i]: none above the first row / below the last; a segment is "done"
/// when the row above it is done.
CourseSessionRail courseSessionRail(List<CourseSessionState> states, int i) => (
  top: i <= 0 ? null : (states[i - 1] == CourseSessionState.done ? CourseRailTone.done : CourseRailTone.plain),
  bottom: i >= states.length - 1
      ? null
      : (states[i] == CourseSessionState.done ? CourseRailTone.done : CourseRailTone.plain),
);

/// How many leading done sessions fold behind "n completed" — only in a long list ([minLength]) and only when at
/// least [minFold] of them are done; a list that is all done never folds (there would be nothing left).
int courseSessionFoldCount(List<CourseSessionState> states, {int minLength = 8, int minFold = 3}) {
  if (states.length < minLength) return 0;
  var n = 0;
  while (n < states.length && states[n] == CourseSessionState.done) {
    n++;
  }
  if (n >= states.length || n < minFold) return 0;
  return n;
}

/// The noun under a hero number (drawn apart from it) in its plural form (L2: "4 طالب"): the translation keys
/// `<base>_one` (1), `<base>_few` (Arabic 2–10, English plural) and `<base>` (Arabic 0 / 11+ / a fraction, English
/// plural) — e.g. `courseStatNoun(4, 'course_hero_students')` → "طلاب" / "Students".
String courseStatNoun(num n, String base, {String? lang}) {
  final whole = n == n.roundToDouble() ? n.toInt() : null;
  final ar = (lang ?? AppConfig.lang) == 'ar';
  if (whole == 1) return '${base}_one'.tr;
  if (ar && whole != null && whole != 0 && arabicPluralForm(whole) != 'many') return '${base}_few'.tr;
  return base.tr;
}

/// "45 min" · "1 h 30 min" · "2 h".
String courseSessionLength(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return _t('$m د', '$m min');
  if (m == 0) return _t('$h س', '$h h');
  return _t('$h س $m د', '$h h $m min');
}

/// Month headers for a dated timeline: the label of the month a row opens ("November 2026"), else null. Only when
/// the dated sessions span two months or more (one month needs no header); an undated row stays in the group above.
List<String?> courseSessionGroups(List<DateTime?> whens, {String Function(DateTime utc)? label}) {
  String key(DateTime d) {
    final l = AppTime.toZone(d.toUtc());
    return '${l.year}-${l.month}';
  }

  final months = {for (final w in whens) if (w != null) key(w)};
  if (months.length < 2) return List<String?>.filled(whens.length, null);
  final out = <String?>[];
  String? last;
  for (final w in whens) {
    if (w == null || key(w) == last) {
      out.add(null);
      continue;
    }
    last = key(w);
    out.add(label == null ? AppTime.date(w, pattern: 'MMMM y') : label(w));
  }
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
// Surface · fold
// ═════════════════════════════════════════════════════════════════════════════

/// Where the timeline sits: the page's gutter (each session is its own card on the line, D-112).
class CourseSessionsSurface extends StatelessWidget {
  const CourseSessionsSurface({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin ?? const EdgeInsets.symmetric(horizontal: kCourseGutter - 4),
    child: child,
  );
}

/// The session rows on their line; the leading [foldCount] (done) rows hide behind one "n completed" row.
/// [itemBuilder] gets the index in the FULL list.
class CourseSessionsTimeline extends StatefulWidget {
  const CourseSessionsTimeline({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.foldCount = 0,
    this.margin,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int foldCount;
  final EdgeInsetsGeometry? margin;

  @override
  State<CourseSessionsTimeline> createState() => _CourseSessionsTimelineState();
}

class _CourseSessionsTimelineState extends State<CourseSessionsTimeline> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final fold = widget.foldCount.clamp(0, widget.itemCount);
    final from = fold > 0 && !_open ? fold : 0;
    return CourseSessionsSurface(
      margin: widget.margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fold > 0) CourseSessionFoldRow(count: fold, open: _open, onTap: () => setState(() => _open = !_open)),
          for (var i = from; i < widget.itemCount; i++) widget.itemBuilder(context, i),
        ],
      ),
    );
  }
}

/// "✓✓ 5 completed sessions · Show" — the first row of a long list once the student is under way.
class CourseSessionFoldRow extends StatelessWidget {
  const CourseSessionFoldRow({super.key, required this.count, required this.open, required this.onTap});

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ok = _ink(context, c.success);
    return Semantics(
      button: true,
      expanded: open,
      child: _Rail(
        rail: (top: null, bottom: CourseRailTone.done),
        nodeTop: 10,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: _railW,
                child: Center(
                  child: Container(
                    width: _nodeSize,
                    height: _nodeSize,
                    decoration: BoxDecoration(color: c.success.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: Icon(Icons.done_all_rounded, size: 15, color: ok),
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: BorderRadius.circular(14),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _t('$count جلسات مكتملة', '$count completed sessions'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _ts(13, FontWeight.w500, c.textMedium),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              open ? _t('إخفاء', 'Hide') : _t('عرض', 'Show'),
                              style: _ts(12.5, FontWeight.w600, _ink(context, c.primary)),
                            ),
                            AnimatedRotation(
                              turns: open ? 0.5 : 0,
                              duration: const Duration(milliseconds: 220),
                              child: Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: _ink(context, c.primary)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Row
// ═════════════════════════════════════════════════════════════════════════════

/// Geometry: the line runs down the middle of a [_railW] column at the row's start; the node sits [_nodeTop] below
/// the row's top, level with the middle of the card's kind tile.
const double _railW = 36, _nodeSize = 28, _rowGap = 5, _cardPad = 12, _tileSize = 44;
const double _nodeTop = _rowGap + _cardPad + _tileSize / 2 - _nodeSize / 2;
const double _railX = _railW / 2;

/// Draws the timeline line behind [child]: above the node and below it.
class _Rail extends StatelessWidget {
  const _Rail({required this.rail, required this.child, this.nodeTop = _nodeTop});

  final CourseSessionRail rail;
  final Widget child;
  final double nodeTop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color tone(CourseRailTone t) => t == CourseRailTone.done ? c.success.withValues(alpha: 0.5) : c.divider;
    const w = 2.0;
    return Stack(
      children: [
        if (rail.top != null)
          PositionedDirectional(
            start: _railX - w / 2,
            top: 0,
            height: nodeTop - 3,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(color: tone(rail.top!), borderRadius: BorderRadius.circular(1)),
            ),
          ),
        if (rail.bottom != null)
          PositionedDirectional(
            start: _railX - w / 2,
            top: nodeTop + _nodeSize + 3,
            bottom: 0,
            width: w,
            child: DecoratedBox(
              decoration: BoxDecoration(color: tone(rail.bottom!), borderRadius: BorderRadius.circular(1)),
            ),
          ),
        child,
      ],
    );
  }
}

/// The round node on the line: its number (with a ring of the student's progress through it), or a check / lock /
/// live mark (the live one breathes, unless Reduce motion is on).
class CourseSessionNode extends StatelessWidget {
  const CourseSessionNode({super.key, required this.number, required this.state, this.progress});

  final int number;
  final CourseSessionState state;

  /// 0…1: a ring around the node (how much of the session the student has done); null = none.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final primary = _ink(context, c.primary);
    final (Color bg, Color? border, Widget mark) = switch (state) {
      CourseSessionState.done => (
        c.success.withValues(alpha: c.isDark ? 0.24 : 0.14),
        null,
        Icon(Icons.check_rounded, size: 15, color: _ink(context, c.success)),
      ),
      CourseSessionState.live => (c.danger, null, Icon(Icons.sensors_rounded, size: 15, color: c.onHero)),
      CourseSessionState.locked => (
        c.textDark.withValues(alpha: 0.06),
        null,
        Icon(Icons.lock_rounded, size: 13, color: c.textLight),
      ),
      CourseSessionState.next => (c.primary, null, _num(number, c.onHero)),
      _ => (c.cardBg, c.divider, _num(number, c.textMedium)),
    };
    final ring = progress != null && state != CourseSessionState.done && state != CourseSessionState.locked
        ? progress!.clamp(0.0, 1.0)
        : null;
    Widget node = Container(
      width: _nodeSize,
      height: _nodeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: 1.5),
        boxShadow: state == CourseSessionState.next
            ? [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 3))]
            : null,
      ),
      child: mark,
    );
    if (ring != null) {
      node = SizedBox(
        width: _nodeSize,
        height: _nodeSize,
        child: CustomPaint(
          foregroundPainter: _RingPainter(
            value: ring,
            color: state == CourseSessionState.next ? c.onHero.withValues(alpha: 0.9) : primary,
            track: state == CourseSessionState.next ? c.onHero.withValues(alpha: 0.25) : c.primary.withValues(alpha: 0.14),
          ),
          child: node,
        ),
      );
    }
    if (state == CourseSessionState.live) node = _Halo(color: c.danger, child: node);
    return SizedBox(width: _nodeSize, height: _nodeSize, child: node);
  }

  static Widget _num(int n, Color color) => Padding(
    padding: const EdgeInsets.all(4),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('$n', maxLines: 1, style: _ts(12, FontWeight.w600, color)),
    ),
  );
}

/// The arc of the student's progress, inside the node's edge.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.color, required this.track});

  final double value;
  final Color color, track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.2;
    final r = Rect.fromLTWH(stroke / 2 + 1, stroke / 2 + 1, size.width - stroke - 2, size.height - stroke - 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 6.2832, false, p..color = track);
    if (value > 0) canvas.drawArc(r, -1.5708, 6.2832 * value, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

/// A soft ring that breathes out of the live node (parked by Reduce motion).
class _Halo extends StatefulWidget {
  const _Halo({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_Halo> createState() => _HaloState();
}

class _HaloState extends State<_Halo> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
    ..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _a);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (_, child) {
      final t = Curves.easeOut.transform(_a.value);
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: widget.color.withValues(alpha: 0.35 * (1 - t)), spreadRadius: 7 * t, blurRadius: 2),
          ],
        ),
        child: child,
      );
    },
    child: widget.child,
  );
}

/// The kind of a session as a soft tile at the card's start: live · recorded · section.
class CourseSessionKindTile extends StatelessWidget {
  const CourseSessionKindTile({super.key, required this.kind, this.state = CourseSessionState.open, this.size = _tileSize});

  final CourseSessionKind kind;
  final CourseSessionState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, Color base, String label) = switch (kind) {
      CourseSessionKind.live => (Icons.sensors_rounded, c.danger, _t('مباشر', 'Live')),
      CourseSessionKind.section => (Icons.science_rounded, c.purple, _t('سكشن', 'Section')),
      CourseSessionKind.recorded => (Icons.play_arrow_rounded, c.primary, _t('فيديو', 'Video')),
    };
    final quiet = state == CourseSessionState.done || state == CourseSessionState.locked;
    final tone = quiet ? c.textLight : base;
    final live = state == CourseSessionState.live;
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.3),
            color: live ? null : tone.withValues(alpha: c.isDark ? 0.2 : (quiet ? 0.07 : 0.10)),
            gradient: live
                ? LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [c.danger, Color.lerp(c.danger, c.heroShade, 0.25)!],
                  )
                : null,
          ),
          child: Icon(icon, size: size * 0.48, color: live ? c.onHero : _ink(context, tone)),
        ),
      ),
    );
  }
}

/// A month header on the line ("November 2026").
class CourseSessionGroupHeader extends StatelessWidget {
  const CourseSessionGroupHeader({super.key, required this.label, this.top});

  final String label;

  /// The line above (null on the first row).
  final CourseRailTone? top;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Rail(
      rail: (top: top, bottom: CourseRailTone.plain),
      nodeTop: 14,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: _railW,
              child: Center(
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: c.background,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.textLight, width: 2),
                  ),
                ),
              ),
            ),
            Flexible(
              child: Semantics(
                header: true,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(12.5, FontWeight.w600, c.textMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One session of the timeline: the node on the line, then the session's card — kind tile · (state chip) · title ·
/// date chip · length · files · (progress) · [below] — and [trailing] at its end (the teacher's ⋮, the student's
/// chevron). "Up next" and "Live now" are the highlighted cards; a done one steps back.
class CourseSessionTile extends StatelessWidget {
  const CourseSessionTile({
    super.key,
    required this.data,
    this.rail = (top: null, bottom: null),
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.below,
    this.panel,
    this.wide = false,
    this.group,
  });

  final CourseSessionView data;
  final CourseSessionRail rail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? below;

  /// Under the row inside the card (the opened materials).
  final Widget? panel;

  /// Room for the description line (desktop).
  final bool wide;

  /// A month header drawn above the row, on the line ([courseSessionGroups]).
  final String? group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = data.state;
    final locked = s == CourseSessionState.locked;
    final done = s == CourseSessionState.done;
    final Color? tone = switch (s) {
      CourseSessionState.live => c.danger,
      CourseSessionState.next => c.primary,
      _ => null,
    };
    final titleColor = locked ? c.textLight : (done ? c.textMedium : c.textDark);
    final metaColor = locked ? c.textLight : c.textMedium;

    final chip = switch (s) {
      CourseSessionState.live => _Chip(label: _t('مباشر الآن', 'Live now'), tone: c.danger, live: true),
      CourseSessionState.next => _Chip(label: _t('التالي', 'Up next'), tone: c.primary),
      _ => null,
    };

    final title = Directionality(
      textDirection: Helpers.textDirOf(data.title),
      child: Text(
        data.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _ts(tone != null ? 15 : 14.5, tone != null ? FontWeight.w600 : FontWeight.w500, titleColor, h: 1.35),
      ),
    );

    final progress = data.progress;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chip != null) ...[chip, const SizedBox(height: 6)],
        title,
        const SizedBox(height: 6),
        _Meta(data: data, color: metaColor, tone: tone),
        if (wide && data.subtitle != null && data.subtitle!.trim().isNotEmpty && !done) ...[
          const SizedBox(height: 6),
          Text(
            data.subtitle!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ts(12.5, FontWeight.w400, c.textLight, h: 1.4),
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: c.primary.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation(_ink(context, c.primary)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${data.materialsDone}/${data.materials}', style: _ts(11.5, FontWeight.w600, c.textMedium)),
              ],
            ),
          ),
        ],
        if (below != null) ...[const SizedBox(height: 12), below!],
      ],
    );

    final row = LayoutBuilder(
      builder: (context, box) {
        // a narrow card keeps its title room: a smaller tile
        final tile = box.maxWidth < 300 ? 36.0 : _tileSize;
        return Padding(
          padding: EdgeInsetsDirectional.fromSTEB(_cardPad, _cardPad, trailing == null ? _cardPad : 2, _cardPad),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: (_tileSize - tile) / 2),
                child: CourseSessionKindTile(kind: data.kind, state: s, size: tile),
              ),
              const SizedBox(width: 12),
              Expanded(child: body),
              ?trailing,
            ],
          ),
        );
      },
    );

    final radius = BorderRadius.circular(18);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: tone != null
            ? Color.alphaBlend(tone.withValues(alpha: c.isDark ? 0.12 : 0.045), c.cardBg)
            : (done || locked ? c.cardBg.withValues(alpha: c.isDark ? 0.5 : 0.6) : c.cardBg),
        border: Border.all(
          color: tone != null
              ? tone.withValues(alpha: c.isDark ? 0.5 : 0.32)
              : c.divider.withValues(alpha: done || locked ? 0.45 : 0.85),
          width: tone != null ? 1.2 : 1,
        ),
        boxShadow: tone != null
            ? [BoxShadow(color: tone.withValues(alpha: c.isDark ? 0.10 : 0.08), blurRadius: 18, offset: const Offset(0, 6))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, onLongPress: onLongPress, child: row),
            ),
            if (panel != null)
              Padding(padding: const EdgeInsetsDirectional.fromSTEB(_cardPad, 0, _cardPad, 4), child: panel),
          ],
        ),
      ),
    );

    final line = _Rail(
      rail: group != null ? (top: CourseRailTone.plain, bottom: rail.bottom) : rail,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _rowGap),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _railW,
              child: Padding(
                padding: const EdgeInsets.only(top: _nodeTop - _rowGap),
                child: Center(
                  child: CourseSessionNode(
                    number: data.number,
                    state: s,
                    progress: data.showProgress && data.materials > 0 && data.materialsDone > 0
                        ? data.materialsDone / data.materials
                        : null,
                  ),
                ),
              ),
            ),
            Expanded(child: card),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      child: group == null
          ? line
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CourseSessionGroupHeader(label: group!, top: rail.top),
                line,
              ],
            ),
    );
  }
}

/// date chip · length · files — one quiet line (the kind is the tile).
class _Meta extends StatelessWidget {
  const _Meta({required this.data, required this.color, this.tone});

  final CourseSessionView data;
  final Color color;

  /// The card's accent (next / live): the date chip takes it.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final when = data.when;
    final length = courseSessionLength(data.durationMinutes);
    final hint = data.hint != null && data.hint!.isNotEmpty;
    // Each fact is one unbreakable item (icon + words); the items wrap as wholes, never mid-fact.
    Widget item(IconData icon, String text, {Color? ink}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: ink ?? color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ts(12, FontWeight.w400, ink ?? color, h: 1.45),
          ),
        ),
      ],
    );
    final dateInk = tone == null ? color : _ink(context, tone!);
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (when != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tone == null ? c.inputBg : tone!.withValues(alpha: c.isDark ? 0.2 : 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_rounded, size: 13, color: dateInk),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${AppTime.date(when, pattern: 'EEE d MMM')} · ${AppTime.time(when)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(11.5, FontWeight.w500, dateInk, h: 1.4),
                  ),
                ),
              ],
            ),
          ),
        if (length.isNotEmpty) item(Icons.schedule_rounded, length),
        if (hint)
          item(Icons.info_outline_rounded, data.hint!, ink: _ink(context, c.warning))
        else if (data.materials > 0)
          item(Icons.attach_file_rounded, data.materials == 1 ? _t('ملف واحد', '1 file') : _t('${data.materials} ملفات', '${data.materials} files')),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.tone, this.live = false});

  final String label;
  final Color tone;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final ink = _ink(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[_Pulse(color: ink), const SizedBox(width: 5)],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(11, FontWeight.w600, ink, h: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});

  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncMotionLoop(context, _a, reverse: true);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(_a),
    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Row actions
// ═════════════════════════════════════════════════════════════════════════════

/// A small action under a row's meta line (Join · End · Start exam …): tinted, or [filled] for the one that matters.
class CourseSessionAction extends StatelessWidget {
  const CourseSessionAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.tone,
    this.filled = false,
    this.loading = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? tone;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = tone ?? c.primary;
    final fg = filled ? c.onHero : _ink(context, t);
    final disabled = onTap == null && !loading;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: filled ? t : t.withValues(alpha: c.isDark ? 0.2 : 0.10),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: fg))
                  else if (icon != null)
                    Icon(icon, size: 16, color: fg),
                  if (loading || icon != null) const SizedBox(width: 6),
                  Flexible(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: _ts(12.5, FontWeight.w600, fg)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The expand chevron at a row's end (student) — turns while the materials are open.
class CourseSessionChevron extends StatelessWidget {
  const CourseSessionChevron({super.key, required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 44,
    child: AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: const Duration(milliseconds: 220),
      child: Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: context.colors.textLight),
    ),
  );
}

/// The "materials" panel a row opens (header + the role's grid), aligned with the row's text.
class CourseSessionPanel extends StatelessWidget {
  const CourseSessionPanel({super.key, required this.child, this.title, this.action, this.footer});

  final Widget child;
  final String? title;

  /// At the header's end (the teacher's "Add material").
  final Widget? action;

  /// Under the grid (the session rating).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: c.divider.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  title ?? _t('المواد', 'Materials'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _ts(12.5, FontWeight.w600, c.textMedium),
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 10),
          child,
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}
