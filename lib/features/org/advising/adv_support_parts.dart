// lib/features/org/advising/adv_support_parts.dart — the pieces the Phase 7 advising screens share
// (docs/advising/PHASE7.md):
//   AdvStagePill       a request's stage (postponed / escalated shown with it)
//   AdvStageTrack      THE stage tracker: sent → each approval step → the decision → closed, horizontal when there
//                      is room, else vertical, every point with its date, why it was skipped, "needs information"
//   AdvTrackDots       the same track as a row of dots (list cards)
//   AdvRequestCard     one request / referral in a list (staff and student)
//   AdvOutcomeCard     the decision with its note and the accommodations it granted
//   AdvChoiceCard      a radio card (review decision, plan status)
//   AdvSmallAction     a compact text action under a card
//   pickAdvDate        the date picker of the sheets
// Plain values only except pickAdvDate; sizes from app_tokens.dart, colours from context.colors.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'adv_case_parts.dart' show AdvPriorityPill, AdvTypedText;
import 'adv_models.dart' show AdvAccommodation;
import 'adv_parts.dart' show advDate, advTextDirection;
import 'adv_support_models.dart';

/// The colour of a stage's tone ([advStageTone]).
Color advStageColor(BuildContext context, String? stage) {
  final c = context.colors;
  return switch (advStageTone(stage)) {
    'muted' => c.textMedium,
    'warn' => c.warning,
    'council' => c.purple,
    'good' => c.success,
    'bad' => c.danger,
    _ => c.primary,
  };
}

IconData advStageIcon(String? stage) => switch (stage) {
      'draft' => Icons.edit_note_rounded,
      'submitted' || 'sent' => Icons.send_rounded,
      'needs_info' => Icons.help_outline_rounded,
      'in_review' || 'in_progress' => Icons.manage_search_rounded,
      'at_department_council' || 'at_faculty_council' => Icons.how_to_vote_rounded,
      'approved' || 'handled' => Icons.check_circle_rounded,
      'rejected' || 'declined' => Icons.cancel_rounded,
      'closed' => Icons.lock_outline_rounded,
      _ => Icons.radio_button_unchecked_rounded,
    };

IconData advRequestKindIcon(String kind) => kind == 'referral' ? Icons.alt_route_rounded : Icons.support_rounded;

/// [s] isolated from the text around it (U+2068 … U+2069): an Arabic name in an English line (or a code like
/// 2023-0142 in an Arabic one) keeps its own order and never pulls a date or a dot across.
String advIso(String s) => '${String.fromCharCode(0x2068)}$s${String.fromCharCode(0x2069)}';

/// The 360 timeline's icon of a Phase 7 kind (any other kind: a plain circle).
IconData advSupportTimelineIcon(String kind) => switch (kind) {
      'request_submitted' => Icons.support_rounded,
      'request_stage' => Icons.route_rounded,
      'request_decided' => Icons.gavel_rounded,
      'request_closed' => Icons.task_alt_rounded,
      'referral_sent' || 'referral_outcome' => Icons.alt_route_rounded,
      'plan_created' || 'plan_status' => Icons.route_outlined,
      'plan_review_due' || 'plan_reviewed' => Icons.event_repeat_rounded,
      'accommodation_granted' || 'accommodation_ended' => Icons.accessible_rounded,
      _ => Icons.circle_outlined,
    };

class AdvStagePill extends StatelessWidget {
  const AdvStagePill({super.key, required this.stage, this.postponed = false});
  final String stage;
  final bool postponed;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        postponed ? '${advStageLabel(stage)} · ${t('مؤجّل', 'postponed')}' : advStageLabel(stage),
        color: advStageColor(context, stage),
        icon: advStageIcon(stage),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  The stage track
// ═════════════════════════════════════════════════════════════════════════════

Color _pointColor(BuildContext context, AdvTrackState s) {
  final c = context.colors;
  return switch (s) {
    AdvTrackState.done => c.success,
    AdvTrackState.current => c.primary,
    AdvTrackState.attention => c.warning,
    AdvTrackState.failed => c.danger,
    _ => c.textLight,
  };
}

IconData? _pointIcon(AdvTrackState s) => switch (s) {
      AdvTrackState.done => Icons.check_rounded,
      AdvTrackState.attention => Icons.priority_high_rounded,
      AdvTrackState.failed => Icons.close_rounded,
      AdvTrackState.skipped => Icons.redo_rounded,
      AdvTrackState.stopped => Icons.remove_rounded,
      _ => null,
    };

/// The word under a point that has no date.
String _stateWord(AdvTrackState s) => switch (s) {
      AdvTrackState.done => t('تم', 'Done'),
      AdvTrackState.current => t('الآن', 'Now'),
      AdvTrackState.attention => t('بحاجة إلى معلومات', 'Needs information'),
      AdvTrackState.waiting => t('بالانتظار', 'Waiting'),
      AdvTrackState.skipped => t('تُجووزت', 'Skipped'),
      AdvTrackState.failed => t('توقّف هنا', 'Stopped here'),
      AdvTrackState.stopped => t('لم تُبلغ', 'Not reached'),
    };

/// The round marker of one point: filled with an icon once reached, a ring with a dot for the current one, hollow
/// while waiting.
class _TrackMarker extends StatelessWidget {
  const _TrackMarker({required this.state, this.size = 26});
  final AdvTrackState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = _pointColor(context, state);
    final icon = _pointIcon(state);
    final filled = state == AdvTrackState.done || state == AdvTrackState.failed || state == AdvTrackState.attention;
    final live = state == AdvTrackState.current;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? col : (live ? col.withValues(alpha: 0.14) : c.cardBg),
        border: Border.all(color: filled ? col : (live ? col : c.divider), width: live ? AppBorder.focus : AppBorder.strong),
      ),
      child: Center(
        child: live
            ? Container(width: size * 0.36, height: size * 0.36, decoration: BoxDecoration(shape: BoxShape.circle, color: col))
            : (icon == null ? null : Icon(icon, size: size * 0.6, color: filled ? c.onHero : c.textMedium)),
      ),
    );
  }
}

/// The stage tracker of a request. Horizontal when every point gets about 120 px (scaled with the text), else a
/// vertical list. Points come from [advRequestTrack].
class AdvStageTrack extends StatelessWidget {
  const AdvStageTrack({super.key, required this.points, this.forceVertical = false});
  final List<AdvTrackPoint> points;
  final bool forceVertical;

  static String _sub(AdvTrackPoint p) => p.at != null ? advDate(p.at) : _stateWord(p.state);

  String _semantic(int i) {
    final p = points[i];
    return [
      t('الخطوة ${i + 1} من ${points.length}', 'Step ${i + 1} of ${points.length}'),
      p.label,
      _sub(p),
      ?p.hint,
    ].join('، ');
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);
      final horizontal = !forceVertical && box.maxWidth / points.length >= 120 * scale;
      return horizontal ? _horizontal(context) : _vertical(context);
    });
  }

  Widget _vertical(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < points.length; i++)
        Semantics(
          label: _semantic(i),
          excludeSemantics: true,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  _TrackMarker(state: points[i].state),
                  if (i < points.length - 1)
                    Expanded(
                      child: Container(
                        width: AppBorder.focus,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: points[i].state == AdvTrackState.done && points[i + 1].state != AdvTrackState.waiting && points[i + 1].state != AdvTrackState.stopped
                            ? c.success.withValues(alpha: 0.5)
                            : c.divider,
                      ),
                    ),
                ]),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: i == points.length - 1 ? 0 : AppSpace.sm, top: 2),
                  child: _PointText(point: points[i], align: CrossAxisAlignment.start),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _horizontal(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < points.length; i++)
        Expanded(
          child: Semantics(
            label: _semantic(i),
            excludeSemantics: true,
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Container(
                    height: AppBorder.focus,
                    color: i == 0 ? Colors.transparent : (points[i - 1].state == AdvTrackState.done && points[i].state != AdvTrackState.waiting && points[i].state != AdvTrackState.stopped ? c.success.withValues(alpha: 0.5) : c.divider),
                  ),
                ),
                _TrackMarker(state: points[i].state, size: 28),
                Expanded(
                  child: Container(
                    height: AppBorder.focus,
                    color: i == points.length - 1 ? Colors.transparent : (points[i].state == AdvTrackState.done && points[i + 1].state != AdvTrackState.waiting && points[i + 1].state != AdvTrackState.stopped ? c.success.withValues(alpha: 0.5) : c.divider),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs),
                child: _PointText(point: points[i], align: CrossAxisAlignment.center),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _PointText extends StatelessWidget {
  const _PointText({required this.point, required this.align});
  final AdvTrackPoint point;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = point;
    final strong = p.state == AdvTrackState.current || p.state == AdvTrackState.attention;
    final faded = p.state == AdvTrackState.waiting || p.state == AdvTrackState.stopped || p.state == AdvTrackState.skipped;
    final center = align == CrossAxisAlignment.center;
    final textAlign = center ? TextAlign.center : TextAlign.start;
    final col = _pointColor(context, p.state);
    return Column(crossAxisAlignment: align, mainAxisSize: MainAxisSize.min, children: [
      Text(
        p.label,
        textAlign: textAlign,
        maxLines: center ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: AppType.row(context).copyWith(
          fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
          color: faded ? c.textMedium : c.textDark,
          decoration: p.state == AdvTrackState.skipped ? TextDecoration.lineThrough : null,
          decorationColor: c.textLight,
        ),
      ),
      Text(
        AdvStageTrack._sub(p),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context).copyWith(color: strong || p.state == AdvTrackState.failed ? appInk(context, col) : null, fontWeight: strong ? FontWeight.w600 : null),
      ),
      if (p.hint != null)
        Text(
          p.hint!,
          textAlign: textAlign,
          maxLines: center ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: AppType.meta(context).copyWith(color: p.state == AdvTrackState.attention ? appInk(context, c.warning) : null),
        ),
    ]);
  }
}

/// The track as a row of small dots (a list card): reached points filled, the current one ringed.
class AdvTrackDots extends StatelessWidget {
  const AdvTrackDots({super.key, required this.points});
  final List<AdvTrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (points.isEmpty) return const SizedBox.shrink();
    final reached = points.where((p) => p.state == AdvTrackState.done || p.state == AdvTrackState.skipped).length;
    return Semantics(
      label: t('اجتاز $reached من ${points.length} مراحل', 'Passed $reached of ${points.length} stages'),
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 28.0 * points.length),
        child: Row(children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(height: AppBorder.focus, color: points[i - 1].state == AdvTrackState.done ? c.success.withValues(alpha: 0.5) : c.divider),
              ),
            _dot(context, points[i].state),
          ],
        ]),
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, AdvTrackState s) {
    final c = context.colors;
    final col = _pointColor(context, s);
    final live = s == AdvTrackState.current || s == AdvTrackState.attention;
    final filled = s == AdvTrackState.done || s == AdvTrackState.failed || live;
    return Container(
      width: live ? 10 : 8,
      height: live ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? col : c.cardBg,
        border: Border.all(color: filled ? col : c.divider, width: AppBorder.strong),
        boxShadow: live ? [BoxShadow(color: col.withValues(alpha: 0.3), blurRadius: 0, spreadRadius: 3)] : null,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  A request in a list
// ═════════════════════════════════════════════════════════════════════════════

class AdvRequestCard extends StatelessWidget {
  const AdvRequestCard({
    super.key,
    required this.kind,
    required this.title,
    required this.typeLabel,
    required this.stage,
    this.track = const [],
    this.postponed = false,
    this.priority = 'normal',
    this.student,
    this.meta,
    this.due,
    this.overdue = false,
    this.escalated = false,
    this.sensitive = false,
    this.infoPending = false,
    this.onTap,
  });

  /// A staff request.
  factory AdvRequestCard.staff(AdvRequest r, {bool showStudent = true, VoidCallback? onTap}) => AdvRequestCard(
        kind: r.kind,
        title: r.shownTitle,
        typeLabel: r.typeLabel,
        stage: r.stage,
        track: r.track,
        postponed: r.postponed,
        priority: r.priority,
        student: showStudent ? advIso(r.studentName) : null,
        meta: [
          if (r.draft && r.updatedAt != null) t('آخر تعديل ${advDate(r.updatedAt)}', 'Edited ${advDate(r.updatedAt)}'),
          if (!r.draft && r.submittedAt != null) t('أُرسل ${advDate(r.submittedAt)}', 'Submitted ${advDate(r.submittedAt)}'),
          if (r.createdBy != null) t('بواسطة ${advIso(r.createdBy!.shown)}', 'by ${advIso(r.createdBy!.shown)}'),
        ].join(' · '),
        due: !r.decided && r.step?.dueAt != null ? r.step!.dueAt : null,
        overdue: !r.decided && (r.step?.overdue ?? false),
        escalated: r.escalated && !r.decided,
        sensitive: r.sensitive,
        infoPending: r.infoPending,
        onTap: onTap,
      );

  /// The student's own request.
  factory AdvRequestCard.student(AdvStudentRequest r, {VoidCallback? onTap}) => AdvRequestCard(
        kind: r.kind,
        title: r.shownTitle,
        typeLabel: r.typeLabel,
        stage: r.stage,
        track: r.track,
        postponed: r.postponed,
        priority: r.priority,
        meta: [
          if (r.submittedAt != null) t('أُرسل ${advDate(r.submittedAt)}', 'Submitted ${advDate(r.submittedAt)}'),
          if (r.advisorName.isNotEmpty) t('من مرشدك ${advIso(r.advisorName)}', 'by your advisor ${advIso(r.advisorName)}'),
        ].join(' · '),
        onTap: onTap,
      );

  final String kind, title, typeLabel, stage, priority;
  final List<AdvTrackPoint> track;
  final bool postponed;
  final String? student, meta;
  final DateTime? due;
  final bool overdue, escalated, sensitive, infoPending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = advStageColor(context, stage);
    final sub = [typeLabel, ?student].join(' · ');
    final pills = <Widget>[
      if (priority == 'urgent' || priority == 'high') AdvPriorityPill(priority: priority),
      if (infoPending) AppBadgePill(t('ينتظر معلوماتك', 'Waiting for your information'), color: c.warning, icon: Icons.help_outline_rounded),
      if (escalated) AppBadgePill(t('صُعّد', 'Escalated'), color: c.danger, icon: Icons.trending_up_rounded),
      if (sensitive) AppBadgePill(t('حساس', 'Sensitive'), color: c.textMedium, icon: Icons.lock_outline_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: onTap != null,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpace.sm),
          child: LayoutBuilder(builder: (context, box) {
            final atEnd = box.maxWidth >= 420 * MediaQuery.textScalerOf(context).scale(1);
            final pill = AdvStagePill(stage: stage, postponed: postponed);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ExcludeSemantics(
                  child: Container(
                    width: AppTouch.min - AppSpace.xs,
                    height: AppTouch.min - AppSpace.xs,
                    decoration: BoxDecoration(color: col.withValues(alpha: 0.12), borderRadius: AppRadius.chipAll),
                    child: Icon(advRequestKindIcon(kind), size: AppIconSize.md, color: appInk(context, col)),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, textDirection: advTextDirection(title), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    if (!atEnd) ...[const SizedBox(height: AppSpace.xxs), pill],
                  ]),
                ),
                if (atEnd) ...[const SizedBox(width: AppSpace.xs), pill],
              ]),
              if (track.isNotEmpty) ...[
                const SizedBox(height: AppSpace.sm),
                Padding(padding: const EdgeInsetsDirectional.only(start: AppTouch.min - AppSpace.xs + AppSpace.sm), child: AdvTrackDots(points: track)),
              ],
              if (pills.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: pills),
              ],
              if ((meta ?? '').isNotEmpty || due != null) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if ((meta ?? '').isNotEmpty) Text(meta!, style: AppType.meta(context)),
                  if (due != null)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      ExcludeSemantics(child: Icon(overdue ? Icons.alarm_rounded : Icons.schedule_rounded, size: AppIconSize.sm, color: overdue ? appInk(context, c.danger) : c.textMedium)),
                      const SizedBox(width: AppSpace.xxs),
                      Flexible(
                        child: Text(
                          overdue ? t('متأخر — كان مستحقاً ${advDate(due)}', 'Overdue — was due ${advDate(due)}') : t('مستحق ${advDate(due)}', 'Due ${advDate(due)}'),
                          style: AppType.meta(context).copyWith(color: overdue ? appInk(context, c.danger) : null, fontWeight: overdue ? FontWeight.w600 : null),
                        ),
                      ),
                    ]),
                ]),
              ],
            ]);
          }),
        ),
      ),
    );
  }

}

// ═════════════════════════════════════════════════════════════════════════════
//  The decision
// ═════════════════════════════════════════════════════════════════════════════

class AdvOutcomeCard extends StatelessWidget {
  const AdvOutcomeCard({super.key, required this.outcome, this.note, this.at, this.accommodations = const [], this.until, this.closeNote, this.closedAt});
  final String outcome;
  final String? note;
  final DateTime? at;

  /// What an approved accommodation request granted.
  final List<AdvAccommodation> accommodations;
  final DateTime? until;

  /// The advisor's follow-up note when the case was closed.
  final String? closeNote;
  final DateTime? closedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final good = outcome == 'approved' || outcome == 'handled';
    final bad = outcome == 'rejected' || outcome == 'declined';
    final col = good ? c.success : (bad ? c.danger : c.textMedium);
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: col.withValues(alpha: 0.07), borderRadius: AppRadius.cardAll, border: Border.all(color: col.withValues(alpha: 0.28))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: Icon(good ? Icons.verified_rounded : (bad ? Icons.cancel_rounded : Icons.do_not_disturb_on_outlined), color: appInk(context, col), size: AppIconSize.lg)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(header: true, child: Text(t('القرار: ${advOutcomeLabel(outcome)}', 'Decision: ${advOutcomeLabel(outcome)}'), style: AppType.section(context).copyWith(color: appInk(context, col)))),
              if (at != null) Text(advDate(at), style: AppType.meta(context)),
            ]),
          ),
        ]),
        if (note != null && note!.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          AdvTypedText(note!),
        ],
        if (accommodations.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            until == null ? t('التسهيلات الممنوحة', 'Accommodations granted') : t('التسهيلات الممنوحة حتى ${advDate(until, dateOnly: true)}', 'Accommodations granted until ${advDate(until, dateOnly: true)}'),
            style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpace.xxs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
            for (final a in accommodations) AppBadgePill(a.label, color: c.primary, icon: Icons.accessible_rounded),
          ]),
        ],
        if (closeNote != null && closeNote!.isNotEmpty) ...[
          Divider(height: AppSpace.lg, color: col.withValues(alpha: 0.2)),
          Text(closedAt == null ? t('متابعة المرشد', 'The advisor\'s follow-up') : t('متابعة المرشد · ${advDate(closedAt)}', 'The advisor\'s follow-up · ${advDate(closedAt)}'),
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpace.xxs),
          AdvTypedText(closeNote!),
        ],
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Small shared controls
// ═════════════════════════════════════════════════════════════════════════════

/// One radio card of a choice (a review decision, a plan's next status).
class AdvChoiceCard extends StatelessWidget {
  const AdvChoiceCard({super.key, required this.title, this.hint, required this.selected, required this.color, this.icon, this.onTap});
  final String title;
  final String? hint;
  final bool selected;
  final Color color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? color.withValues(alpha: 0.07) : c.cardBg,
          borderRadius: AppRadius.cardAll,
          child: InkWell(
            borderRadius: AppRadius.cardAll,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              decoration: BoxDecoration(
                borderRadius: AppRadius.cardAll,
                border: Border.all(color: selected ? color : c.divider, width: selected ? AppBorder.strong : AppBorder.hairline),
              ),
              child: Row(children: [
                ExcludeSemantics(child: Icon(icon ?? Icons.circle, size: icon == null ? AppIconSize.xs : AppIconSize.md, color: appInk(context, color))),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                    if (hint != null && hint!.isNotEmpty) Text(hint!, style: AppType.meta(context)),
                  ]),
                ),
                ExcludeSemantics(
                  child: Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: AppIconSize.md, color: selected ? appInk(context, color) : c.textLight),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact text action under a card ("Edit", "Change status").
class AdvSmallAction extends StatelessWidget {
  const AdvSmallAction({super.key, required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, AppTouch.min),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          foregroundColor: danger ? appInk(context, context.colors.danger) : null,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: AppIconSize.sm),
        label: Text(label),
      );
}

/// A card with a titled header (icon + title + an optional trailing widget) over [child].
class AdvBlockCard extends StatelessWidget {
  const AdvBlockCard({super.key, required this.icon, required this.title, required this.child, this.trailing, this.color});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final col = color ?? context.colors.primary;
    return AppCard(
      padding: AppSpace.card,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExcludeSemantics(child: Icon(icon, size: AppIconSize.md, color: appInk(context, col))),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Semantics(header: true, child: Text(title, style: AppType.bodyStrong(context)))),
          ?trailing,
        ]),
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

/// Picks a calendar date: from [first] (default today) up to two years ahead.
Future<DateTime?> pickAdvDate(BuildContext context, DateTime? initial, {DateTime? first, int days = 7}) {
  final now = DateTime.now();
  final from = first ?? DateTime(now.year, now.month, now.day);
  final init = initial == null || initial.isBefore(from) ? from.add(Duration(days: days)) : DateTime(initial.year, initial.month, initial.day);
  return showDatePicker(context: context, initialDate: init, firstDate: from, lastDate: DateTime(now.year + 2, 12, 31));
}
