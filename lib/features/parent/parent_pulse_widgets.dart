// lib/features/parent/parent_pulse_widgets.dart — the parent home's "How is my child doing?" parts (D-305), redrawn
// for the redesign (Pa2Today, phase 4), all over plain values (ParentPulse, parent_pulse.dart) so the layout harness
// pumps them without a provider:
//
//   ParentChildSwitcher   the child chips (PaKidSwitcher) where no dashboard band carries them
//   ParentPulseHero       the hero of one child: the greeting, "<name> is doing well this week", one sentence, the
//                         full report (the one forward action) and "Message the teacher", three glass figures
//                         (attendance · average mark · missed work)
//   ParentInsightsCard    "Needs your attention": <= 4 findings in plain words, each a tile with its one action
//   ParentWeekCard        the child's next 7 days, grouped by day (today first)
//   ParentEventLine       one dated event (times · rail · title · live tag)
//   ParentSixWeeksCard    the 6-week attendance and average-mark bars (wide screens)
//   ParentPathCard        the learning path as a ring: done of total and the next course
//   ParentSubjectsCard    per course: the child's average against the class average (a marker on the bar), the
//                         tone (strength / needs focus), progress, missed sessions; "Message the teacher"
//   ParentRoadmapCard     the learning path without a total (the field and the next course)
//   parentInsightText     a finding → its sentence (translation keys pp_ins_*, countText for every count + noun)
//
// Role rules (KIT_SPEC 4.3): the parent gets M9 / M10 / M13 / M14 only, so nothing here loops or enters on its own;
// colours from context.colors and the kit tones, type from AppType, space from AppSpace, times through AppTime.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../config/app_config.dart';
import 'pa_kit.dart';
import 'parent_overview.dart';
import 'parent_pulse.dart';

// ── texts ──────────────────────────────────────────────────────────────────

String _fmt(String key, Map<String, Object?> params) {
  var t = key.tr;
  params.forEach((k, v) => t = t.replaceAll('{$k}', '${v ?? ''}'));
  return t;
}

String _sessions(int n) =>
    countText(n, ar1: 'حصة واحدة', ar2: 'حصتين', arFew: '{n} حصص', arMany: '{n} حصة', en1: '1 class', en: '{n} classes');

String _homework(int n) =>
    countText(n, ar1: 'واجب واحد', ar2: 'واجبين', arFew: '{n} واجبات', arMany: '{n} واجبًا', en1: '1 homework', en: '{n} homework');

String _exams(int n) =>
    countText(n, ar1: 'اختبار واحد', ar2: 'اختبارين', arFew: '{n} اختبارات', arMany: '{n} اختبارًا', en1: '1 exam', en: '{n} exams');

String _dates(int n) =>
    countText(n, ar1: 'موعد واحد', ar2: 'موعدين', arFew: '{n} مواعيد', arMany: '{n} موعدًا', en1: '1 date', en: '{n} dates');

int _n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String _course(Map<String, dynamic> p) => pulseName('${p['course_ar'] ?? ''}', '${p['course_en'] ?? ''}');

String _pct(num v) => appDigits('${v.round()}%');

/// One finding as a sentence about [childName].
String parentInsightText(PulseInsight i, String childName) {
  final p = i.params;
  final name = childName.split(' ').first;
  switch (i.code) {
    case 'missed_week':
      return _fmt('pp_ins_missed_week', {'name': name, 'sessions': _sessions(_n(p['count'])), 'scheduled': _n(p['scheduled'])});
    case 'homework_missing':
      return _fmt('pp_ins_homework_missing', {'homework': _homework(_n(p['count']))});
    case 'failed_exams':
      return _fmt('pp_ins_failed_exams', {'exams': _exams(_n(p['count']))});
    case 'inactive':
      return _fmt('pp_ins_inactive', {'days': daysText(_n(p['days']))});
    case 'grades_down':
    case 'grades_up':
      return _fmt('pp_ins_${i.code}', {'delta': _n(p['delta']), 'avg': _n(p['avg'])});
    case 'focus_subject':
      return _fmt('pp_ins_focus_subject', {'course': _course(p), 'avg': _n(p['avg'])});
    case 'weak_backlog':
      return _fmt('pp_ins_weak_backlog', {'course': _course(p), 'count': _n(p['count'])});
    case 'homework_soon':
      return _fmt('pp_ins_homework_soon', {'homework': _homework(_n(p['count']))});
    case 'exam_soon':
      final at = parentUtc(p['at']);
      return _fmt('pp_ins_exam_soon', {'title': p['title'] ?? '', 'at': at == null ? '' : AppTime.dateTime(at)});
    case 'open_alerts':
      return _fmt('pp_ins_open_alerts', {'count': _n(p['count'])});
    case 'above_class':
      return _fmt('pp_ins_above_class', {'delta': _n(p['delta'])});
    case 'strength':
      return _fmt('pp_ins_strength', {'course': _course(p)});
    case 'full_attendance':
      return _fmt('pp_ins_full_attendance', {'count': _n(p['count'])});
  }
  return i.code; // a code this app does not know yet (a newer server): the code, never a blank row
}

Color pulseStatusColor(BuildContext context, PulseStatus s) {
  final kit = context.colors.kit;
  return switch (s) {
    PulseStatus.onTrack => kit.ok.color,
    PulseStatus.watch => kit.warn.color,
    PulseStatus.needsYou => kit.live.color,
    PulseStatus.quiet => context.colors.textMedium,
  };
}

IconData pulseStatusIcon(PulseStatus s) => switch (s) {
      PulseStatus.onTrack => Icons.verified_rounded,
      PulseStatus.watch => Icons.visibility_rounded,
      PulseStatus.needsYou => Icons.priority_high_rounded,
      PulseStatus.quiet => Icons.nights_stay_rounded,
    };

String pulseStatusLabel(PulseStatus s) => 'pp_status_${s.wire}'.tr;

AppTone pulseStatusTone(PulseStatus s) => switch (s) {
      PulseStatus.onTrack => AppTone.success,
      PulseStatus.watch => AppTone.warning,
      PulseStatus.needsYou => AppTone.danger,
      PulseStatus.quiet => AppTone.neutral,
    };

/// The tone of a finding's icon box: a warning in the live red, good news in the ok green, a date coming in the
/// warning gold, alerts in the primary, anything else in the parent's own tone.
KitTone parentInsightTone(BuildContext context, PulseInsight i) {
  final kit = context.colors.kit;
  if (i.level == 'warn') return kit.live;
  if (i.level == 'good') return kit.ok;
  return switch (i.code) {
    'exam_soon' || 'homework_soon' => kit.warn,
    'open_alerts' => kit.primaryTone,
    _ => AppAreaScope.of(context).tone,
  };
}

IconData _insightIcon(PulseInsight i) => switch (i.code) {
      'missed_week' || 'full_attendance' => Icons.event_busy_rounded,
      'homework_missing' => Icons.warning_amber_rounded,
      'homework_soon' || 'exam_soon' => Icons.calendar_today_rounded,
      'failed_exams' => Icons.quiz_rounded,
      'inactive' => Icons.bedtime_rounded,
      'grades_down' => Icons.trending_down_rounded,
      'grades_up' || 'above_class' => Icons.keyboard_arrow_up_rounded,
      'focus_subject' || 'weak_backlog' => Icons.center_focus_strong_rounded,
      'open_alerts' => Icons.notifications_none_rounded,
      'strength' => Icons.star_rounded,
      _ => Icons.lightbulb_rounded,
    };

/// The page gutter the old home kit used; kept for callers that still pad by it.
const double parentHomeGutter = AppSpace.md;

// ── shared bits ────────────────────────────────────────────────────────────

/// A section card: the kit card with its title row (the title, an optional trailing at the end) over the body.
class ParentPulseSection extends StatelessWidget {
  const ParentPulseSection({super.key, required this.title, required this.icon, required this.child, this.trailing, this.padBody = true});

  final String title;

  /// Kept for callers; the redesign's card head has no glyph.
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  /// Kept for callers: the kit card pads its body itself.
  final bool padBody;

  @override
  Widget build(BuildContext context) => AppCard(title: title, action: trailing, child: child);
}

// ── child switcher ─────────────────────────────────────────────────────────

/// The child chips where no dashboard band carries them (a preview of the Today body alone).
class ParentChildSwitcher extends StatelessWidget {
  const ParentChildSwitcher({super.key, required this.children, required this.selectedId, required this.onSelect, this.inset = 0});

  final List<ParentChildOverview> children;
  final int? selectedId;
  final ValueChanged<int?> onSelect;
  final double inset;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'pp_switch_hint'.tr,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: PaKidSwitcher(
            kids: [for (final c in children) PaKid(id: c.id, name: c.name, status: c.pulse?.status.wire)],
            selected: selectedId,
            onHero: false,
            onSelect: onSelect,
          ),
        ),
      );
}

// ── the child's hero ───────────────────────────────────────────────────────

/// The selected child's 6-week attendance (rates), or empty when there are fewer than two points.
List<double> parentAttendanceSpark(ParentPulse p) {
  final t = [for (final v in p.attendanceTrend) if (v != null) v.toDouble()];
  return t.length >= 2 ? t : const [];
}

/// The selected child's 6-week average marks, or empty when there are fewer than two points.
List<double> parentGradesSpark(ParentPulse p) {
  final t = [for (final v in p.grades?.trend ?? const <double?>[]) ?v];
  return t.length >= 2 ? t : const [];
}

/// The hero of one child (Pa2Today `screen=today`): the avatar, the greeting, "<name> is doing well this week", the
/// first finding as one sentence, the full report (hot) and "Message the teacher", then three glass figures.
class ParentPulseHero extends StatelessWidget {
  const ParentPulseHero({
    super.key,
    required this.child,
    required this.pulse,
    required this.onOpenReport,
    this.greeting,
    this.onMessage,
  });

  final ParentChildOverview child;
  final ParentPulse pulse;
  final VoidCallback onOpenReport;

  /// "Good evening, Ahmed" (null = none).
  final String? greeting;

  /// "Message the teacher"; null = not offered (no teacher, or the switch is off).
  final VoidCallback? onMessage;

  String _line() {
    final first = child.name.split(' ').first;
    if (pulse.insights.isNotEmpty) return parentInsightText(pulse.insights.first, child.name);
    return 'pa_head_line_${pulse.status.wire}'.tr.replaceAll('{name}', first);
  }

  @override
  Widget build(BuildContext context) {
    final w = pulse.week, g = pulse.grades;
    final first = child.name.split(' ').first;
    final missedWork = w.missed + w.homeworkMissing;
    final delta = g?.delta;
    final wide = paWide(context);
    final grade = '${child.child['grade_name'] ?? ''}';
    return AppHero(
      kicker: greeting,
      title: 'pa_head_${pulse.status.wire}'.tr.replaceAll('{name}', first),
      subtitle: _line(),
      leading: PaKidAvatar(id: child.id, name: child.name, size: AppHero.leadingSize(wide)),
      actions: [
        AppButton.hot(
          key: const ValueKey('pa.today.report'),
          label: 'pa_full_report'.tr,
          icon: Icons.bar_chart_rounded,
          expand: !wide,
          onPressed: onOpenReport,
        ),
        if (onMessage != null)
          AppButton.secondary(
            key: const ValueKey('pa.today.message'),
            label: 'pa_message_teacher'.tr,
            icon: Icons.chat_bubble_outline_rounded,
            expand: !wide,
            onPressed: onMessage,
          ),
      ],
      stats: [
        AppHeroStat(label: 'pa_attendance'.tr, value: w.rate == null ? '—' : _pct(w.rate!)),
        AppHeroStat(
          label: 'pa_grade_avg'.tr,
          value: g?.avg == null ? '—' : _pct(g!.avg!),
          delta: delta == null || delta.round() == 0 ? null : appDigits('${delta > 0 ? '+' : '−'}${delta.abs().round()}'),
        ),
        AppHeroStat(label: 'pa_missed'.tr, value: appDigits('$missedWork')),
      ],
      bottom: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: pulseStatusLabel(pulse.status), tone: pulseStatusTone(pulse.status), icon: pulseStatusIcon(pulse.status)),
          if (grade.isNotEmpty) Text(grade, style: AppType.meta(context).copyWith(color: context.colors.onHeroMuted)),
        ]),
      ),
    );
  }
}

// ── needs your attention ───────────────────────────────────────────────────

class ParentInsightsCard extends StatelessWidget {
  const ParentInsightsCard({super.key, required this.childName, required this.insights, required this.onAction, this.canMessage = true});

  final String childName;
  final List<PulseInsight> insights;
  final ValueChanged<PulseInsight> onAction;

  /// false: the `parent.message_teacher` switch is off → that action is not offered.
  final bool canMessage;

  String? _actionLabel(PulseAction? a) => switch (a?.kind) {
        PulseActionKind.messageTeacher => canMessage ? 'pa_message_teacher'.tr : null,
        PulseActionKind.openReport => 'pa_open_report'.tr,
        PulseActionKind.openAlerts => 'pa_show_alerts'.tr,
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'pa_needs_title'.tr,
      action: insights.isEmpty ? null : AppCountBadge(count: insights.length, tone: AppTone.gold),
      child: insights.isEmpty
          ? AppTile(icon: Icons.check_rounded, tone: context.colors.kit.ok, title: 'pa_all_clear'.tr)
          : PaStack(gap: AppSpace.sm, children: [
              for (final i in insights)
                _InsightTile(
                  insight: i,
                  text: parentInsightText(i, childName),
                  actionLabel: _actionLabel(i.action),
                  onAction: () => onAction(i),
                ),
            ]),
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({required this.insight, required this.text, this.actionLabel, required this.onAction});

  final PulseInsight insight;
  final String text;
  final String? actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return AppTile(
      icon: _insightIcon(insight),
      tone: parentInsightTone(context, insight),
      title: text,
      trailing: label == null ? null : AppButton.secondary(label: label, size: AppButtonSize.sm, onPressed: onAction),
    );
  }
}

// ── this week ──────────────────────────────────────────────────────────────

class ParentWeekCard extends StatelessWidget {
  const ParentWeekCard({super.key, required this.events});

  final List<ParentEventRow> events;

  String _dayLabel(DateTime wallDay, DateTime today) {
    final d = DateTime(wallDay.year, wallDay.month, wallDay.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    if (d == 0) return 'pp_today'.tr;
    if (d == 1) return 'pp_tomorrow'.tr;
    return AppTime.date(AppTime.fromZone(wallDay), pattern: 'EEEE d MMM');
  }

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    final today = AppTime.toZone(DateTime.now().toUtc());
    final groups = <String, List<ParentEventRow>>{};
    for (final e in events) {
      final s = e.startsAt;
      if (s == null) continue;
      groups.putIfAbsent(_dayLabel(AppTime.toZone(s), today), () => []).add(e);
    }
    return AppCard(
      title: 'pp_this_week'.tr,
      action: groups.isEmpty ? null : AppStatusBadge(label: _dates(events.length), tone: AppTone.info),
      child: groups.isEmpty
          ? Text('pp_week_empty'.tr, style: AppType.body(context))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, g) in groups.entries.indexed) ...[
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.sm, bottom: AppSpace.xxs),
                  child: Text(g.key, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: set.ink)),
                ),
                for (final e in g.value) ParentEventLine(event: e),
              ],
            ]),
    );
  }
}

/// One dated event: the start and end times · a rail in the event's tone · the title and its line · a live tag
/// while it runs.
class ParentEventLine extends StatelessWidget {
  const ParentEventLine({super.key, required this.event, this.now});

  final ParentEventRow event;

  /// The instant that decides "live" and "past" (default: now).
  final DateTime? now;

  static const double _timeWidth = AppSpace.xxxl;

  /// Below this width the live tag goes under the title.
  static const double _tagAtEndFrom = 360;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final set = AppAreaScope.of(context);
    final s = event.startsAt, e = event.endsAt;
    final at = now ?? DateTime.now().toUtc();
    final live = s != null && e != null && !at.isBefore(s) && at.isBefore(e);
    final past = e != null && !at.isBefore(e);
    final exam = event.source == 'exam' || event.kind == 'exam';
    final rail = exam ? kit.warn.color : (past ? c.divider : set.a);
    final sub = [
      if (event.mode == 'online') 'pa_remote'.tr,
      if (event.mode == 'offline') 'pa_in_person'.tr,
      if (event.subtitle.isNotEmpty) event.subtitle,
      if (event.location.isNotEmpty) event.location,
    ].join(paT('، ', ', '));
    const tabular = [FontFeature.tabularFigures()];
    return LayoutBuilder(builder: (context, box) {
      // the live tag stands at the end where there is room, under the title on a narrow card
      final tagAtEnd = box.maxWidth >= _tagAtEndFrom;
      return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: _timeWidth,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s == null ? '—' : AppTime.time(s), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w700, color: c.textDark, fontFeatures: tabular)),
              if (e != null)
                Text(AppTime.time(e), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(fontFeatures: tabular)),
            ]),
          ),
          Container(
            width: AppBorder.focus * 2,
            margin: const EdgeInsetsDirectional.only(end: AppSpace.sm),
            decoration: BoxDecoration(color: rail, borderRadius: BorderRadius.circular(AppRadius.pill)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppType.row(context).copyWith(color: past ? c.textMedium : c.textDark, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (exam)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: AppStatusBadge(label: 'pp_exam_tag'.tr, tone: AppTone.warning, icon: Icons.quiz_rounded, dense: true),
                ),
              if (live && !tagAtEnd)
                const Padding(padding: EdgeInsets.only(top: AppSpace.xxs), child: AppLiveTag(slap: false)),
            ]),
          ),
          if (live && tagAtEnd) ...[
            const SizedBox(width: AppSpace.xs),
            const Center(child: AppLiveTag(slap: false)),
          ],
        ]),
      ),
    );
    });
  }
}

// ── the last six weeks (wide) ──────────────────────────────────────────────

class ParentSixWeeksCard extends StatelessWidget {
  const ParentSixWeeksCard({super.key, required this.pulse});

  final ParentPulse pulse;

  @override
  Widget build(BuildContext context) {
    final att = parentAttendanceSpark(pulse), grades = parentGradesSpark(pulse);
    final kit = context.colors.kit;
    final tiles = <Widget>[
      if (att.isNotEmpty)
        _Bars(label: 'pa_attendance'.tr, value: pulse.week.rate == null ? '—' : _pct(pulse.week.rate!), values: att, tone: kit.ok),
      if (grades.isNotEmpty)
        _Bars(
          label: 'pa_grade_avg'.tr,
          value: pulse.grades?.avg == null ? '—' : _pct(pulse.grades!.avg!),
          values: grades,
          tone: kit.live,
        ),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return AppCard(
      title: 'pa_six_weeks'.tr,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: AppSpace.sm), Expanded(child: tiles[i])],
      ]),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.label, required this.value, required this.values, required this.tone});

  final String label, value;
  final List<double> values;
  final KitTone tone;

  static const double _height = AppSpace.xxxl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$label $value',
      child: Container(
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: c.kit.well,
          borderRadius: BorderRadius.circular(AppRadius.tile),
          border: Border.all(color: c.kit.line, width: AppBorder.strong),
        ),
        child: ExcludeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            Text(value, style: AppType.statFigure(context, wide: false)),
            const SizedBox(height: AppSpace.xs),
            SizedBox(
              height: _height,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpace.xxs),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (values[i] / 100).clamp(.06, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: tone.color, borderRadius: BorderRadius.circular(AppRadius.chip)),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── the learning path as a ring ────────────────────────────────────────────

class ParentPathCard extends StatelessWidget {
  const ParentPathCard({super.key, required this.roadmap});

  final PulseRoadmap roadmap;

  @override
  Widget build(BuildContext context) {
    final r = roadmap;
    final of = _fmt('pa_n_of_m', {'n': appDigits('${r.done}'), 'm': appDigits('${r.total}')});
    return AppCard(
      title: 'pa_learning_path'.tr,
      child: Row(children: [
        AppProgressRing(value: r.ratio, size: AppDashSize.ring, label: of, semanticLabel: of),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fmt('pa_path_done', {'n': of}), style: AppType.tileTitle(context)),
            if (r.next.isNotEmpty)
              Text(_fmt('pa_path_next', {'name': r.next}), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ]),
        ),
      ]),
    );
  }
}

// ── subjects ───────────────────────────────────────────────────────────────

class ParentSubjectsCard extends StatelessWidget {
  const ParentSubjectsCard({super.key, required this.subjects, this.onMessage});

  final List<PulseSubject> subjects;

  /// "Message the teacher" of one course; null: not offered (switch off).
  final ValueChanged<PulseSubject>? onMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final anyClass = subjects.any((s) => s.classAvg != null);
    return AppCard(
      title: 'pp_subjects'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < subjects.length; i++) ...[
          if (i > 0) Divider(height: AppSpace.md, thickness: AppBorder.hairline, color: c.kit.line),
          _SubjectRow(subject: subjects[i], onMessage: onMessage == null || subjects[i].teacher == null ? null : () => onMessage!(subjects[i])),
        ],
        if (anyClass) ...[
          const SizedBox(height: AppSpace.sm),
          PaNote(icon: Icons.shield_outlined, text: 'pp_subj_privacy'.tr),
        ],
      ]),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, this.onMessage});
  final PulseSubject subject;
  final VoidCallback? onMessage;

  static const double _figureWidth = AppSpace.xxl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = subject;
    final meta = [
      if (s.classAvg != null) _fmt('pp_subj_class', {'n': s.classAvg!.round()}),
      _fmt('pp_subj_progress', {'n': s.progress.round()}),
      if (s.missed > 0) _fmt('pp_subj_missed', {'n': s.missed}),
    ].join(' · ');
    final score = s.avg == null ? c.textLight : appScoreColor(context, s.avg);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
            if (s.isStrength || s.isFocus)
              AppStatusBadge(label: 'pp_subj_${s.tone}'.tr, tone: s.isFocus ? AppTone.warning : AppTone.success, dense: true),
          ]),
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            Expanded(child: AppProgressBar(value: s.avg ?? 0, marker: s.classAvg, color: s.avg == null ? c.divider : score)),
            const SizedBox(width: AppSpace.xs),
            SizedBox(
              width: _figureWidth,
              child: Text(s.avg == null ? '—' : _pct(s.avg!), textAlign: TextAlign.end,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Text(s.avg == null ? '${'pp_subj_no_marks'.tr} · $meta' : meta, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.meta(context)),
        ]),
      ),
      if (onMessage != null)
        AppIconButton(
          icon: Icons.chat_bubble_outline_rounded,
          tooltip: '${'pa_message_teacher'.tr} · ${s.teacher!.name}',
          onPressed: onMessage,
        ),
    ]);
  }
}

// ── roadmap without a total ────────────────────────────────────────────────

class ParentRoadmapCard extends StatelessWidget {
  const ParentRoadmapCard({super.key, required this.roadmap, required this.childName});
  final PulseRoadmap roadmap;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final r = roadmap;
    final set = AppAreaScope.of(context);
    return AppCard(
      title: 'pa_learning_path'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (r.field.isNotEmpty)
          Text(_fmt('pp_road_hint', {'name': childName.split(' ').first, 'field': r.field}), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.body(context)),
        if (r.next.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Icon(Icons.flag_rounded, size: AppIconSize.sm, color: set.ink),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(_fmt('pa_path_next', {'name': r.next}), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context))),
            if (r.nextProgress != null && r.nextProgress! > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Text(_pct(r.nextProgress!), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
            ],
          ]),
        ],
      ]),
    );
  }
}
