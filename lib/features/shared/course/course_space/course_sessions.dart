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
// courseSessionRail, courseSessionFoldCount, courseSessionLength.
library;

import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/app_time.dart';
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

/// Student: one state per session, in list order. The first session that is neither live, locked nor done is "next".
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
    } else if (s.done) {
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

/// "45 min" · "1 h 30 min" · "2 h".
String courseSessionLength(int minutes) {
  if (minutes <= 0) return '';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return _t('$m د', '$m min');
  if (m == 0) return _t('$h س', '$h h');
  return _t('$h س $m د', '$h h $m min');
}

// ═════════════════════════════════════════════════════════════════════════════
// Surface · fold
// ═════════════════════════════════════════════════════════════════════════════

/// The one card the timeline sits in.
class CourseSessionsSurface extends StatelessWidget {
  const CourseSessionsSurface({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: kCourseGutter),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: child,
    );
  }
}

/// The session rows in their card; the leading [foldCount] (done) rows hide behind one "n completed" row.
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
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: _Rail(
          rail: (top: null, bottom: CourseRailTone.done),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: c.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.done_all_rounded, size: 16, color: ok),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _t('$count جلسات مكتملة', '$count completed sessions'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _ts(13.5, FontWeight.w500, c.textMedium),
                  ),
                ),
                const SizedBox(width: 8),
                Text(open ? _t('إخفاء', 'Hide') : _t('عرض', 'Show'), style: _ts(12.5, FontWeight.w600, _ink(context, c.primary))),
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
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Row
// ═════════════════════════════════════════════════════════════════════════════

/// Geometry of a row: the node sits [_nodeTop] below the row's top, [_railX] from its start edge.
const double _nodeSize = 32, _nodeTop = 12, _rowStart = 16;
const double _railX = _rowStart + _nodeSize / 2;

/// Draws the timeline line behind [child]: above the node and below it.
class _Rail extends StatelessWidget {
  const _Rail({required this.rail, required this.child});

  final CourseSessionRail rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Color tone(CourseRailTone t) => t == CourseRailTone.done ? c.success.withValues(alpha: 0.45) : c.divider;
    const w = 1.5;
    return Stack(
      children: [
        if (rail.top != null)
          PositionedDirectional(
            start: _railX - w / 2,
            top: 0,
            height: _nodeTop - 2,
            width: w,
            child: ColoredBox(color: tone(rail.top!)),
          ),
        if (rail.bottom != null)
          PositionedDirectional(
            start: _railX - w / 2,
            top: _nodeTop + _nodeSize + 2,
            bottom: 0,
            width: w,
            child: ColoredBox(color: tone(rail.bottom!)),
          ),
        child,
      ],
    );
  }
}

/// The round node of a row: its number, or a check / lock / live mark.
class CourseSessionNode extends StatelessWidget {
  const CourseSessionNode({super.key, required this.number, required this.state});

  final int number;
  final CourseSessionState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color? border, Widget mark) = switch (state) {
      CourseSessionState.done => (
        c.success.withValues(alpha: 0.12),
        null,
        Icon(Icons.check_rounded, size: 16, color: _ink(context, c.success)),
      ),
      CourseSessionState.live => (c.danger, null, Icon(Icons.sensors_rounded, size: 16, color: c.onHero)),
      CourseSessionState.locked => (
        c.textDark.withValues(alpha: 0.05),
        null,
        Icon(Icons.lock_rounded, size: 14, color: c.textLight),
      ),
      CourseSessionState.next => (
        c.primary.withValues(alpha: 0.10),
        _ink(context, c.primary),
        _num(number, _ink(context, c.primary)),
      ),
      _ => (c.cardBg, c.divider, _num(number, c.textMedium)),
    };
    return Container(
      width: _nodeSize,
      height: _nodeSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: state == CourseSessionState.next ? 1.5 : 1),
      ),
      child: mark,
    );
  }

  static Widget _num(int n, Color color) => Padding(
    padding: const EdgeInsets.all(3),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text('$n', maxLines: 1, style: _ts(12.5, FontWeight.w600, color)),
    ),
  );
}

/// One session of the timeline. [trailing] sits at the row's end (the teacher's ⋮, the student's expand chevron),
/// [below] under the meta line, aligned with the title (live / exam buttons, the materials panel).
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
  });

  final CourseSessionView data;
  final CourseSessionRail rail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;
  final Widget? below;

  /// Under the whole row, indented to the title (the opened materials); the line runs past it.
  final Widget? panel;

  /// Room for the description line (desktop).
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = data.state;
    final locked = s == CourseSessionState.locked;
    final Color? tone = switch (s) {
      CourseSessionState.live => c.danger,
      CourseSessionState.next => c.primary,
      _ => null,
    };
    final titleColor = locked ? c.textLight : c.textDark;
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
        style: _ts(14.5, FontWeight.w500, titleColor, h: 1.35),
      ),
    );

    final progress = data.progress;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: chip == null
              ? title
              : Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [title, chip],
                ),
        ),
        const SizedBox(height: 4),
        _Meta(data: data, color: metaColor),
        if (wide && data.subtitle != null && data.subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            data.subtitle!.trim(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ts(12.5, FontWeight.w400, c.textLight, h: 1.4),
          ),
        ],
        if (progress != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      backgroundColor: c.primary.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation(_ink(context, c.primary)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${data.materialsDone}/${data.materials}', style: _ts(11, FontWeight.w600, c.textMedium)),
              ],
            ),
          ),
        ],
        if (below != null) ...[const SizedBox(height: 10), below!],
      ],
    );

    final row = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(_rowStart, _nodeTop, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CourseSessionNode(number: data.number, state: s),
          const SizedBox(width: 12),
          Expanded(child: body),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!] else const SizedBox(width: 8),
        ],
      ),
    );

    return Semantics(
      container: true,
      child: Stack(
        children: [
          if (tone != null)
            PositionedDirectional(
              start: 6,
              end: 6,
              top: 2,
              bottom: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: c.isDark ? 0.12 : 0.05),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          _Rail(
            rail: rail,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(16),
                    child: row,
                  ),
                ),
                if (panel != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(_rowStart + _nodeSize + 12, 0, 12, 0),
                    child: panel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// kind · date · length · files — one quiet line.
class _Meta extends StatelessWidget {
  const _Meta({required this.data, required this.color});

  final CourseSessionView data;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData kindIcon, String kind) = switch (data.kind) {
      CourseSessionKind.live => (Icons.sensors_rounded, _t('مباشر', 'Live')),
      CourseSessionKind.section => (Icons.science_outlined, _t('سكشن', 'Section')),
      CourseSessionKind.recorded => (Icons.play_circle_outline_rounded, _t('مسجّل', 'Recorded')),
    };
    final when = data.when;
    final length = courseSessionLength(data.durationMinutes);
    final hint = data.hint != null && data.hint!.isNotEmpty;
    // Each fact is one unbreakable item (icon + words); the items wrap as wholes, never mid-fact.
    Widget item(IconData icon, String text, {Color? tone}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: tone ?? color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _ts(12, FontWeight.w400, tone ?? color, h: 1.45),
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 12,
      runSpacing: 2,
      children: [
        item(kindIcon, kind),
        if (when != null) item(Icons.event_outlined, '${AppTime.date(when, pattern: 'EEE d MMM')} · ${AppTime.time(when)}'),
        if (length.isNotEmpty) item(Icons.schedule_rounded, length),
        if (hint)
          item(Icons.info_outline_rounded, data.hint!, tone: _ink(context, c.warning))
        else if (data.materials > 0)
          item(Icons.attach_file_rounded, '${data.materials}'),
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
      decoration: BoxDecoration(color: tone.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
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
