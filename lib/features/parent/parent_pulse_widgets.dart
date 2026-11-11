// lib/features/parent/parent_pulse_widgets.dart — the parent home's "How is my child doing?" parts (D-305), all
// over plain values (ParentPulse, parent_pulse.dart) so the layout harness pumps them without a provider:
//
//   ParentChildSwitcher   one chip per child (avatar · name · status dot); only drawn with two children or more
//   ParentPulseHero       who · status · "Full report", then four AppStatCards (attendance · average mark · missed
//                         work · courses + next exam); the 6-week lines are AppKpiSparks beside it (parent_overview_page)
//   ParentInsightsCard    "Needs your attention": <= 4 findings in plain words, each with its one action
//   ParentWeekCard        the child's next 7 days, grouped by day (today first)
//   ParentSubjectsCard    per course: the child's average against the class average (a marker on the bar), the
//                         tone (strength / needs focus), progress, missed sessions; "Message the teacher"
//   ParentRoadmapCard     the learning path: done / total and the next course
//   parentInsightText     a finding → its sentence (translation keys pp_ins_*, countText for every count + noun)
//
// Calm-home rules (D-102) in the Warm Editorial theme (D-610 – D-629) and the premium dashboard (D-631): the one
// hero is the forest greeting, every other section one paper card with an editorial title and hairline dividers; tones as opaque
// tints (appTintOn / appInkOn), type from AppType, space from AppSpace, colours from context.colors only, times
// through AppTime.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;

import '../../config/app_config.dart';
import 'parent_overview.dart';
import 'parent_pulse.dart';

// ── texts ──────────────────────────────────────────────────────────────────

String _fmt(String key, Map<String, Object?> params) {
  var t = key.tr;
  params.forEach((k, v) => t = t.replaceAll('{$k}', '${v ?? ''}'));
  return t;
}

String _sessions(int n) =>
    countText(n, ar1: 'جلسة واحدة', ar2: 'جلستان', arFew: '{n} جلسات', arMany: '{n} جلسة', en1: '1 session', en: '{n} sessions');

String _homework(int n) =>
    countText(n, ar1: 'واجب واحد', ar2: 'واجبان', arFew: '{n} واجبات', arMany: '{n} واجبًا', en1: '1 homework', en: '{n} homework');

String _exams(int n) =>
    countText(n, ar1: 'اختبار واحد', ar2: 'اختباران', arFew: '{n} اختبارات', arMany: '{n} اختبارًا', en1: '1 exam', en: '{n} exams');

int _n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String _course(Map<String, dynamic> p) => pulseName('${p['course_ar'] ?? ''}', '${p['course_en'] ?? ''}');

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
  final c = context.colors;
  return switch (s) {
    PulseStatus.onTrack => c.success,
    PulseStatus.watch => c.warning,
    PulseStatus.needsYou => c.danger,
    PulseStatus.quiet => c.textMedium,
  };
}

IconData pulseStatusIcon(PulseStatus s) => switch (s) {
      PulseStatus.onTrack => Icons.verified_rounded,
      PulseStatus.watch => Icons.visibility_rounded,
      PulseStatus.needsYou => Icons.priority_high_rounded,
      PulseStatus.quiet => Icons.nights_stay_rounded,
    };

String pulseStatusLabel(PulseStatus s) => 'pp_status_${s.wire}'.tr;

Color _levelColor(BuildContext context, String level) {
  final c = context.colors;
  return switch (level) {
    'warn' => c.danger,
    'good' => c.success,
    _ => c.primary,
  };
}

IconData _insightIcon(String code) => switch (code) {
      'missed_week' || 'full_attendance' => Icons.event_busy_rounded,
      'homework_missing' || 'homework_soon' => Icons.assignment_late_rounded,
      'failed_exams' || 'exam_soon' => Icons.quiz_rounded,
      'inactive' => Icons.bedtime_rounded,
      'grades_down' => Icons.trending_down_rounded,
      'grades_up' || 'above_class' => Icons.trending_up_rounded,
      'focus_subject' || 'weak_backlog' => Icons.center_focus_strong_rounded,
      'open_alerts' => Icons.notifications_active_rounded,
      'strength' => Icons.star_rounded,
      _ => Icons.lightbulb_rounded,
    };

AppTone pulseStatusTone(PulseStatus s) => switch (s) {
      PulseStatus.onTrack => AppTone.success,
      PulseStatus.watch => AppTone.warning,
      PulseStatus.needsYou => AppTone.danger,
      PulseStatus.quiet => AppTone.neutral,
    };

/// The home kit's side gutter (HomeHeader, HomeStatStrip and HomeSectionTitle inset their content 20 px): the parent
/// home's own rows line up with it.
const double parentHomeGutter = AppSpace.md + AppSpace.xxs;

// ── shared bits ────────────────────────────────────────────────────────────

/// An icon in a soft round well of its tone: the one colour of an insight / figure row.
class _ToneWell extends StatelessWidget {
  const _ToneWell({required this.icon, required this.tone});
  final IconData icon;
  final Color tone;

  static const double size = AppTouch.min - AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final tint = appTintOn(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
      child: Icon(icon, size: AppIconSize.sm, color: appInkOn(context, tone, tint)),
    );
  }
}

/// A section card: an editorial title row (a quiet glyph · the title · an optional trailing) over the body, on paper.
class ParentPulseSection extends StatelessWidget {
  const ParentPulseSection({super.key, required this.title, required this.icon, required this.child, this.trailing, this.padBody = true});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool padBody;

  static const double _chip = AppTouch.min - AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // the premium section head (D-631): the editorial title at the start, its glyph in a soft emerald chip at
        // the end — the same head as AppSectionCard
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
            child: Row(children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
                ),
              ),
              ?trailing,
              const SizedBox(width: AppSpace.xs),
              ExcludeSemantics(
                child: Container(
                  width: _chip,
                  height: _chip,
                  decoration: BoxDecoration(color: appTintOn(context, c.primary), borderRadius: BorderRadius.circular(AppRadius.control)),
                  alignment: Alignment.center,
                  child: Icon(icon, size: AppIconSize.sm, color: appInkOn(context, c.primary, appTintOn(context, c.primary))),
                ),
              ),
            ]),
          ),
        ),
        if (padBody)
          Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md), child: child)
        else
          child,
      ]),
    );
  }
}

// ── child switcher ─────────────────────────────────────────────────────────

class ParentChildSwitcher extends StatelessWidget {
  const ParentChildSwitcher({super.key, required this.children, required this.selectedId, required this.onSelect, this.inset = parentHomeGutter});

  final List<ParentChildOverview> children;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  /// The row's side inset: the home's gutter on the page, 0 inside the greeting hero's footer.
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'pp_switch_hint'.tr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final ch in children) ...[
            _ChildChip(child: ch, selected: ch.id == selectedId, onTap: () => onSelect(ch.id)),
            const SizedBox(width: AppSpace.xs),
          ],
        ]),
      ),
    );
  }
}

class _ChildChip extends StatelessWidget {
  const _ChildChip({required this.child, required this.selected, required this.onTap});
  final ParentChildOverview child;
  final bool selected;
  final VoidCallback onTap;

  static const double _avatar = AppTouch.min - AppSpace.sm - AppSpace.xxs;
  static const double _dot = AppSpace.sm;
  static const double _maxWidth = 220;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = child.pulse?.status;
    final dot = status == null ? (child.openAlerts > 0 ? c.danger : null) : pulseStatusColor(context, status);
    final surface = selected ? appTintOn(context, c.primary) : c.cardBg;
    final r = BorderRadius.circular(AppRadius.pill);
    return Semantics(
      button: true,
      selected: selected,
      label: [child.name, if (status != null) pulseStatusLabel(status)].join(' · '),
      child: AppPressScale(
        child: Material(
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: r,
            side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
          ),
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min, maxWidth: _maxWidth),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xxs + AppBorder.focus, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Stack(clipBehavior: Clip.none, children: [
                    AppAvatar(name: child.name, url: child.imageUrl.isEmpty ? null : child.imageUrl, size: _avatar),
                    if (dot != null)
                      PositionedDirectional(
                        end: -AppBorder.hairline,
                        bottom: -AppBorder.hairline,
                        child: Container(
                          width: _dot,
                          height: _dot,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                            border: Border.all(color: surface, width: AppBorder.focus),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(
                    child: Text(
                      child.name.split(' ').first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.row(context).copyWith(
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? appInkOn(context, c.primary, surface) : c.textDark,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── the child's figures: how is my child doing ─────────────────────────────

/// The selected child's 6-week attendance line (rates), or empty when there are fewer than two points.
List<double> parentAttendanceSpark(ParentPulse p) {
  final t = [for (final v in p.attendanceTrend) if (v != null) v.toDouble()];
  return t.length >= 2 ? t : const [];
}

/// The selected child's 6-week average-mark line, or empty when there are fewer than two points.
List<double> parentGradesSpark(ParentPulse p) {
  final t = [for (final v in p.grades?.trend ?? const <double?>[]) ?v];
  return t.length >= 2 ? t : const [];
}

/// The child's figures (D-305 in the premium dashboard, D-631): a heading row — the child's avatar, "How is `name`
/// doing?" in the editorial face, the status — that opens the full report, then four stat cards (attendance in
/// the schedule tone, the average mark in emerald, missed work in peach, courses + the next exam on paper). The
/// home's one hero is the greeting above it; the plain sentence lives there.
class ParentPulseHero extends StatelessWidget {
  const ParentPulseHero({super.key, required this.child, required this.pulse, required this.onOpenReport});

  final ParentChildOverview child;
  final ParentPulse pulse;
  final VoidCallback onOpenReport;

  static const double _avatar = AppTouch.min;

  List<Widget> _stats() {
    final w = pulse.week, g = pulse.grades;
    final att = w.rate;
    final missedWork = w.missed + w.homeworkMissing;
    final delta = g?.delta;
    final gSub = <String>[
      if (g?.classAvg != null) _fmt('pp_m_grades_class', {'n': g!.classAvg!.round()}),
      if (delta != null && delta.round() != 0) '${delta > 0 ? '+' : '-'}${delta.abs().round()} ${'pp_m_vs_prev'.tr}',
    ];
    final exam = child.nextExam;
    return [
      AppStatCard(
        icon: Icons.how_to_reg_rounded,
        label: 'pp_m_attendance'.tr,
        value: att == null ? '—' : '$att%',
        tone: AppBlockTone.sage,
        footer: w.scheduled == 0 ? 'pp_m_attendance_none'.tr : _fmt('pp_m_attendance_sub', {'a': w.attended, 's': w.scheduled}),
      ),
      AppStatCard(
        icon: Icons.grading_rounded,
        label: 'pp_m_grades'.tr,
        value: g?.avg == null ? '—' : '${g!.avg!.round()}%',
        tone: AppBlockTone.emerald,
        footer: g?.avg == null ? 'pp_m_grades_none'.tr : (gSub.isEmpty ? _exams(g!.count) : gSub.join(' · ')),
      ),
      AppStatCard(
        icon: Icons.assignment_late_rounded,
        label: 'pp_m_work'.tr,
        value: '$missedWork',
        tone: AppBlockTone.peach,
        footer: missedWork == 0
            ? 'pp_m_work_none'.tr
            : [if (w.missed > 0) _sessions(w.missed), if (w.homeworkMissing > 0) _homework(w.homeworkMissing)].join(' · '),
      ),
      AppStatCard(
        icon: Icons.menu_book_rounded,
        label: 'courses'.tr,
        value: '${child.courses}',
        tone: AppBlockTone.paper,
        footer: exam == null ? 'pl_ov_no_exam'.tr : '${'pl_ov_next_exam'.tr} · ${exam.name}',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final first = child.name.split(' ').first;
    final head = Row(children: [
      AppAvatar(name: child.name, url: child.imageUrl.isEmpty ? null : child.imageUrl, size: _avatar),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(_fmt('pp_how_title', {'name': first}), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: AppType.section(context)),
            ),
            AppStatusBadge(label: pulseStatusLabel(pulse.status), tone: pulseStatusTone(pulse.status), icon: pulseStatusIcon(pulse.status)),
          ],
        ),
      ),
      const SizedBox(width: AppSpace.xs),
      Icon(Icons.chevron_right_rounded, color: context.colors.textLight),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // the heading row opens the full report (the hero's call to action says it in words)
      Semantics(
        button: true,
        hint: 'pp_full_report'.tr,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.control),
          onTap: onOpenReport,
          child: ConstrainedBox(constraints: const BoxConstraints(minHeight: AppTouch.min), child: head),
        ),
      ),
      const SizedBox(height: AppSpace.sm),
      AppKpiGrid(children: _stats()),
    ]);
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
        PulseActionKind.messageTeacher => canMessage ? 'pp_act_message'.tr : null,
        PulseActionKind.openReport => 'pp_act_report'.tr,
        PulseActionKind.openAlerts => 'pp_act_alerts'.tr,
        null => null,
      };

  IconData _actionIcon(PulseActionKind k) => switch (k) {
        PulseActionKind.messageTeacher => Icons.chat_bubble_outline_rounded,
        PulseActionKind.openReport => Icons.insights_rounded,
        PulseActionKind.openAlerts => Icons.notifications_none_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ParentPulseSection(
      title: 'pp_needs_title'.tr,
      icon: Icons.tips_and_updates_outlined,
      padBody: false,
      child: insights.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
              child: Row(children: [
                _ToneWell(icon: Icons.check_rounded, tone: c.success),
                const SizedBox(width: AppSpace.sm),
                Expanded(child: Text('pp_all_clear'.tr, style: AppType.body(context))),
              ]),
            )
          : Column(children: [
              for (var i = 0; i < insights.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: AppBorder.hairline,
                    thickness: AppBorder.hairline,
                    indent: AppSpace.md + _ToneWell.size + AppSpace.sm,
                    color: c.divider,
                  ),
                _InsightRow(
                  insight: insights[i],
                  text: parentInsightText(insights[i], childName),
                  actionLabel: _actionLabel(insights[i].action),
                  actionIcon: insights[i].action == null ? null : _actionIcon(insights[i].action!.kind),
                  onAction: () => onAction(insights[i]),
                ),
              ],
              const SizedBox(height: AppSpace.xs),
            ]),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight, required this.text, this.actionLabel, this.actionIcon, required this.onAction});
  final PulseInsight insight;
  final String text;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ToneWell(icon: _insightIcon(insight.code), tone: _levelColor(context, insight.level)),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xxs + AppBorder.focus),
              child: Text(text, style: AppType.row(context).copyWith(height: 1.5)),
            ),
            if (actionLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: AppButton.tonal(label: actionLabel!, icon: actionIcon, size: AppButtonSize.sm, onPressed: onAction),
              ),
          ]),
        ),
      ]),
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
    final c = context.colors;
    final today = AppTime.toZone(DateTime.now().toUtc());
    final groups = <String, List<ParentEventRow>>{};
    for (final e in events) {
      final s = e.startsAt;
      if (s == null) continue;
      groups.putIfAbsent(_dayLabel(AppTime.toZone(s), today), () => []).add(e);
    }
    return ParentPulseSection(
      title: 'pp_this_week'.tr,
      icon: Icons.date_range_rounded,
      trailing: groups.isEmpty ? null : AppCountBadge(count: events.length, tone: AppTone.neutral),
      child: groups.isEmpty
          ? Text('pp_week_empty'.tr, style: AppType.body(context))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, g) in groups.entries.indexed) ...[
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpace.sm, bottom: AppSpace.xxs),
                  child: Text(g.key, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
                ),
                for (final e in g.value) _WeekRow(event: e),
              ],
            ]),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.event});
  final ParentEventRow event;

  static const double _timeWidth = AppSpace.xxxl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exam = event.source == 'exam' || event.kind == 'exam';
    final tone = exam ? c.warning : c.primary;
    final sub = [if (event.subtitle.isNotEmpty) event.subtitle, if (event.location.isNotEmpty) event.location].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs + AppBorder.hairline),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: _timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: AppBorder.focus),
              child: Text(event.startsAt == null ? '—' : AppTime.time(event.startsAt!), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: appInk(context, tone),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
          // the day's rail: the tone of what it is (a class in the primary, an exam in the warning tone)
          Container(
            width: AppBorder.focus + AppBorder.hairline,
            margin: const EdgeInsetsDirectional.only(end: AppSpace.sm, top: AppSpace.xxs / 2, bottom: AppSpace.xxs / 2),
            decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(AppRadius.pill)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(height: 1.35)),
              if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              if (exam)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: AppStatusBadge(label: 'pp_exam_tag'.tr, tone: AppTone.warning, icon: Icons.quiz_rounded, dense: true),
                ),
            ]),
          ),
        ]),
      ),
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
    return ParentPulseSection(
      title: 'pp_subjects'.tr,
      icon: Icons.menu_book_rounded,
      padBody: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < subjects.length; i++) ...[
          if (i > 0) Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
          _SubjectRow(subject: subjects[i], onMessage: onMessage == null || subjects[i].teacher == null ? null : () => onMessage!(subjects[i])),
        ],
        if (anyClass)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: AppIconSize.xs, color: c.textLight),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: Text('pp_subj_privacy'.tr, style: AppType.meta(context).copyWith(color: c.textLight, height: 1.4))),
            ]),
          )
        else
          const SizedBox(height: AppSpace.xs),
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
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              if (s.isStrength || s.isFocus)
                AppStatusBadge(label: 'pp_subj_${s.tone}'.tr, tone: s.isFocus ? AppTone.warning : AppTone.success, dense: true),
            ]),
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Expanded(
                child: AppProgressBar(
                  value: s.avg ?? 0,
                  marker: s.classAvg,
                  color: s.avg == null ? c.divider : score,
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              SizedBox(
                width: _figureWidth,
                child: Text(s.avg == null ? '—' : '${s.avg!.round()}%', textAlign: TextAlign.end,
                    style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: s.avg == null ? c.textLight : appInk(context, score),
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
            const SizedBox(height: AppSpace.xxs),
            Text(s.avg == null ? '${'pp_subj_no_marks'.tr} · $meta' : meta, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(height: 1.4)),
          ]),
        ),
        if (onMessage != null)
          AppIconButton(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: '${'pp_act_message'.tr} · ${s.teacher!.name}',
            onPressed: onMessage,
          )
        else
          const SizedBox(width: AppSpace.xs),
      ]),
    );
  }
}

// ── roadmap ────────────────────────────────────────────────────────────────

class ParentRoadmapCard extends StatelessWidget {
  const ParentRoadmapCard({super.key, required this.roadmap, required this.childName});
  final PulseRoadmap roadmap;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = roadmap;
    return ParentPulseSection(
      title: 'pp_roadmap'.tr,
      icon: Icons.route_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (r.field.isNotEmpty)
          Text(_fmt('pp_road_hint', {'name': childName.split(' ').first, 'field': r.field}), maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppType.body(context).copyWith(height: 1.45)),
        if (r.total > 0) ...[
          const SizedBox(height: AppSpace.sm),
          Text(_fmt('pp_road_progress', {'done': r.done, 'total': r.total}), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          const SizedBox(height: AppSpace.xs),
          AppProgressBar(value: r.ratio * 100, color: c.primary),
        ],
        if (r.next.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Icon(Icons.flag_rounded, size: AppIconSize.sm, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(_fmt('pp_road_next', {'name': r.next}), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            ),
            if (r.nextProgress != null && r.nextProgress! > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Text('${r.nextProgress!.round()}%', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
            ],
          ]),
        ],
      ]),
    );
  }
}
