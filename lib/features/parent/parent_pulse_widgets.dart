// lib/features/parent/parent_pulse_widgets.dart — the parent home's "How is my child doing?" parts (D-305), all
// over plain values (ParentPulse, parent_pulse.dart) so the layout harness pumps them without a provider:
//
//   ParentChildSwitcher   one chip per child (avatar · name · status dot); only drawn with two children or more
//   ParentPulseHero       who · status · ONE plain sentence · Attendance / Average mark / Missed work figures, each
//                         with its 6-week line; "Full report"
//   ParentInsightsCard    "Needs your attention": <= 4 findings in plain words, each with its one action
//   ParentWeekCard        the child's next 7 days, grouped by day (today first)
//   ParentSubjectsCard    per course: the child's average against the class average (a marker on the bar), the
//                         tone (strength / needs focus), progress, missed sessions; "Message the teacher"
//   ParentRoadmapCard     the learning path: done / total and the next course
//   parentInsightText     a finding → its sentence (translation keys pp_ins_*, countText for every count + noun)
//
// Calm-home rules (D-102): one card per section with hairline dividers, low-alpha tints, w600 at most, colours from
// context.colors only, times through AppTime.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';

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

// ── shared bits ────────────────────────────────────────────────────────────

/// A section card: title row (icon · title · optional trailing) + body, the home's one-card-per-section surface.
class ParentPulseSection extends StatelessWidget {
  const ParentPulseSection({super.key, required this.title, required this.icon, required this.child, this.trailing, this.padBody = true});

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final bool padBody;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.xs),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(children: [
              Icon(icon, size: 18, color: c.textMedium),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w600, c: c.textDark)),
              ),
              ?trailing,
            ]),
          ),
        ),
        if (padBody)
          Padding(padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md), child: child)
        else
          child,
      ]),
    );
  }
}

// ── child switcher ─────────────────────────────────────────────────────────

class ParentChildSwitcher extends StatelessWidget {
  const ParentChildSwitcher({super.key, required this.children, required this.selectedId, required this.onSelect});

  final List<ParentChildOverview> children;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'pp_switch_hint'.tr,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = child.pulse?.status;
    final dot = status == null ? (child.openAlerts > 0 ? c.danger : null) : pulseStatusColor(context, status);
    final r = BorderRadius.circular(AppRadius.hero);
    return Semantics(
      button: true,
      selected: selected,
      label: [child.name, if (status != null) pulseStatusLabel(status)].join(' · '),
      child: Material(
        color: selected ? c.primaryTint : c.cardBg,
        shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.5 : 1)),
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, maxWidth: 220),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 14, 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Stack(clipBehavior: Clip.none, children: [
                  AppAvatar(name: child.name, url: child.imageUrl.isEmpty ? null : child.imageUrl, size: 32),
                  if (dot != null)
                    PositionedDirectional(
                      end: -1,
                      bottom: -1,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle, border: Border.all(color: c.cardBg, width: 2)),
                      ),
                    ),
                ]),
                const SizedBox(width: AppSpace.xs),
                Flexible(
                  child: Text(
                    child.name.split(' ').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(13.5, w: selected ? FontWeight.w600 : FontWeight.w500, c: selected ? appInk(context, c.primary) : c.textDark),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── hero: how is my child doing ────────────────────────────────────────────

class ParentPulseHero extends StatelessWidget {
  const ParentPulseHero({super.key, required this.child, required this.pulse, required this.onOpenReport});

  final ParentChildOverview child;
  final ParentPulse pulse;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = pulseStatusColor(context, pulse.status);
    final first = child.name.split(' ').first;
    final headline = _fmt('pp_head_${pulse.status.wire}', {'name': first});
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // a hairline of the status colour along the top: the one accent of the card
        Container(height: 3, color: tone.withValues(alpha: 0.85)),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AppAvatar(name: child.name, url: child.imageUrl.isEmpty ? null : child.imageUrl, size: 52),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fmt('pp_how_title', {'name': first}), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: appText(17, w: FontWeight.w600, c: c.textDark, h: 1.3)),
                const SizedBox(height: 6),
                AppBadgePill(pulseStatusLabel(pulse.status), color: tone, icon: pulseStatusIcon(pulse.status)),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(headline, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.45)),
          ]),
        ),
        Divider(height: 1, color: c.divider),
        _PulseFigures(pulse: pulse),
        Divider(height: 1, color: c.divider),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xs),
            child: AppButton.ghost(
              label: 'pp_full_report'.tr,
              icon: Icons.insights_rounded,
              trailingIcon: Icons.chevron_right_rounded,
              onPressed: onOpenReport,
            ),
          ),
        ),
      ]),
    );
  }
}

class _Figure {
  const _Figure({required this.icon, required this.label, required this.value, required this.sub, required this.tone, this.spark = const []});
  final IconData icon;
  final String label, value, sub;
  final Color tone;
  final List<double> spark;
}

class _PulseFigures extends StatelessWidget {
  const _PulseFigures({required this.pulse});
  final ParentPulse pulse;

  List<_Figure> _figures(BuildContext context) {
    final c = context.colors;
    final w = pulse.week, g = pulse.grades;
    final att = w.rate;
    final trend = [for (final v in pulse.attendanceTrend) if (v != null) v.toDouble()];
    final gTrend = [for (final v in g?.trend ?? const <double?>[]) ?v];
    final missedWork = w.missed + w.homeworkMissing;
    final delta = g?.delta;
    final gSub = <String>[
      if (g?.classAvg != null) _fmt('pp_m_grades_class', {'n': g!.classAvg!.round()}),
      if (delta != null && delta.round() != 0) '${delta > 0 ? '+' : '-'}${delta.abs().round()} ${'pp_m_vs_prev'.tr}',
    ];
    return [
      _Figure(
        icon: Icons.how_to_reg_rounded,
        label: 'pp_m_attendance'.tr,
        value: att == null ? '—' : '$att%',
        sub: w.scheduled == 0 ? 'pp_m_attendance_none'.tr : _fmt('pp_m_attendance_sub', {'a': w.attended, 's': w.scheduled}),
        tone: att == null ? c.textLight : appScoreColor(context, att.toDouble()),
        spark: trend.length >= 2 ? trend : const [],
      ),
      _Figure(
        icon: Icons.grading_rounded,
        label: 'pp_m_grades'.tr,
        value: g?.avg == null ? '—' : '${g!.avg!.round()}%',
        sub: g?.avg == null ? 'pp_m_grades_none'.tr : (gSub.isEmpty ? _exams(g!.count) : gSub.join(' · ')),
        tone: g?.avg == null ? c.textLight : appScoreColor(context, g!.avg),
        spark: gTrend.length >= 2 ? gTrend : const [],
      ),
      _Figure(
        icon: Icons.assignment_late_rounded,
        label: 'pp_m_work'.tr,
        value: '$missedWork',
        sub: missedWork == 0
            ? 'pp_m_work_none'.tr
            : [if (w.missed > 0) _sessions(w.missed), if (w.homeworkMissing > 0) _homework(w.homeworkMissing)].join(' · '),
        tone: missedWork == 0 ? c.success : c.danger,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final figures = _figures(context);
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 560) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < figures.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: context.colors.divider),
              Expanded(child: _FigureTile(f: figures[i])),
            ],
          ]),
        );
      }
      return Column(children: [
        for (var i = 0; i < figures.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: AppSpace.md, endIndent: AppSpace.md, color: context.colors.divider),
          _FigureRow(f: figures[i]),
        ],
      ]);
    });
  }
}

class _FigureTile extends StatelessWidget {
  const _FigureTile({required this.f});
  final _Figure f;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(f.icon, size: 16, color: c.textMedium),
          const SizedBox(width: 6),
          Expanded(child: Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w500, c: c.textMedium))),
        ]),
        const SizedBox(height: AppSpace.xs),
        Text(f.value, style: appText(26, w: FontWeight.w600, c: appInk(context, f.tone), h: 1.1)),
        const SizedBox(height: 4),
        Text(f.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
        if (f.spark.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xs),
          AppSparkline(f.spark, color: f.tone, height: 28, label: f.label),
        ],
      ]),
    );
  }
}

class _FigureRow extends StatelessWidget {
  const _FigureRow({required this.f});
  final _Figure f;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: f.tone.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(f.icon, size: 18, color: appInk(context, f.tone)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: c.textDark)),
            Text(f.sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
          ]),
        ),
        if (f.spark.isNotEmpty) ...[
          const SizedBox(width: AppSpace.xs),
          SizedBox(width: 56, child: AppSparkline(f.spark, color: f.tone, height: 24, fill: false, label: f.label)),
        ],
        const SizedBox(width: AppSpace.sm),
        Text(f.value, style: appText(18, w: FontWeight.w600, c: appInk(context, f.tone))),
      ]),
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
                Icon(Icons.check_circle_rounded, size: 18, color: c.success),
                const SizedBox(width: AppSpace.xs),
                Expanded(child: Text('pp_all_clear'.tr, style: appText(13, w: FontWeight.w400, c: c.textMedium))),
              ]),
            )
          : Column(children: [
              for (var i = 0; i < insights.length; i++) ...[
                if (i > 0) Divider(height: 1, indent: 60, color: c.divider),
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
    final c = context.colors;
    final tone = _levelColor(context, insight.level);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: Icon(_insightIcon(insight.code), size: 17, color: appInk(context, tone)),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text, style: appText(13.5, w: FontWeight.w500, c: c.textDark, h: 1.45)),
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
      trailing: groups.isEmpty ? null : Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpace.xs),
        child: Text('${events.length}', style: appText(13, w: FontWeight.w600, c: c.textMedium)),
      ),
      child: groups.isEmpty
          ? Text('pp_week_empty'.tr, style: appText(13, w: FontWeight.w400, c: c.textMedium))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs, bottom: 4),
                  child: Text(g.key, style: appText(12, w: FontWeight.w600, c: c.textMedium)),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final exam = event.source == 'exam' || event.kind == 'exam';
    final tone = exam ? c.accent2 : c.primary;
    final sub = [if (event.subtitle.isNotEmpty) event.subtitle, if (event.location.isNotEmpty) event.location].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 64,
          child: Text(event.startsAt == null ? '—' : AppTime.time(event.startsAt!), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: appText(12.5, w: FontWeight.w600, c: appInk(context, tone))),
        ),
        Container(
          width: 3,
          height: 30,
          margin: const EdgeInsetsDirectional.only(end: 10, top: 2),
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(2)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w500, c: c.textDark, h: 1.3)),
            if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w400, c: c.textMedium)),
            if (exam)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AppBadgePill('pp_exam_tag'.tr, color: c.accent2, icon: Icons.quiz_rounded),
              ),
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
    return ParentPulseSection(
      title: 'pp_subjects'.tr,
      icon: Icons.menu_book_rounded,
      padBody: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < subjects.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: AppSpace.md, endIndent: AppSpace.md, color: c.divider),
          _SubjectRow(subject: subjects[i], onMessage: onMessage == null || subjects[i].teacher == null ? null : () => onMessage!(subjects[i])),
        ],
        if (anyClass)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, 4, AppSpace.md, AppSpace.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, size: 14, color: c.textLight),
              const SizedBox(width: 6),
              Expanded(child: Text('pp_subj_privacy'.tr, style: appText(11, w: FontWeight.w400, c: c.textLight, h: 1.4))),
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = subject;
    final tone = s.isFocus ? c.warning : (s.isStrength ? c.success : c.textMedium);
    final meta = [
      if (s.classAvg != null) _fmt('pp_subj_class', {'n': s.classAvg!.round()}),
      _fmt('pp_subj_progress', {'n': s.progress.round()}),
      if (s.missed > 0) _fmt('pp_subj_missed', {'n': s.missed}),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.xs, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w500, c: c.textDark)),
              if (s.isStrength || s.isFocus) AppBadgePill('pp_subj_${s.tone}'.tr, color: tone),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: AppProgressBar(
                  value: s.avg ?? 0,
                  marker: s.classAvg,
                  color: s.avg == null ? c.divider : appScoreColor(context, s.avg),
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              SizedBox(
                width: 44,
                child: Text(s.avg == null ? '—' : '${s.avg!.round()}%', textAlign: TextAlign.end,
                    style: appText(13, w: FontWeight.w600, c: s.avg == null ? c.textLight : appInk(context, appScoreColor(context, s.avg)))),
              ),
            ]),
            const SizedBox(height: 4),
            Text(s.avg == null ? '${'pp_subj_no_marks'.tr} · $meta' : meta, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: appText(11.5, w: FontWeight.w400, c: c.textMedium, h: 1.35)),
          ]),
        ),
        if (onMessage != null)
          IconButton(
            tooltip: '${'pp_act_message'.tr} · ${s.teacher!.name}',
            onPressed: onMessage,
            icon: Icon(Icons.chat_bubble_outline_rounded, size: 20, color: c.primary),
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
              style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.4)),
        if (r.total > 0) ...[
          const SizedBox(height: AppSpace.xs),
          Text(_fmt('pp_road_progress', {'done': r.done, 'total': r.total}), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: appText(12, w: FontWeight.w600, c: c.textDark)),
          const SizedBox(height: 6),
          AppProgressBar(value: r.ratio * 100, color: c.primary),
        ],
        if (r.next.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            Icon(Icons.flag_rounded, size: 16, color: c.accent2),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_fmt('pp_road_next', {'name': r.next}), maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: appText(13, w: FontWeight.w500, c: c.textDark)),
            ),
            if (r.nextProgress != null && r.nextProgress! > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Text('${r.nextProgress!.round()}%', style: appText(12, w: FontWeight.w600, c: c.textMedium)),
            ],
          ]),
        ],
      ]),
    );
  }
}
