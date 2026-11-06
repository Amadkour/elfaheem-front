// lib/design/master_detail/entity_specs.dart — how each kind of entity draws (D-290, phase 3).
//
//   wording        mdStateLabel / mdReasonLabel / mdBadgeText / mdTimelineText / mdSubscriptionText / mdSortLabel …
//                  (codes from the server, worded here in both languages; an unknown code reads as itself)
//   sections       sectionSpecOf(kind, section): the sub-list's title, icon, sorts, the contract's filter, or a block
//   stats          statSpecsOf(summary): the tiles a summary draws (only the figures the server sent)
//   rows           entityRowFor(item, …): one row of a sub-list, a link to the entity it names
//
// A course adds a one-line reading of its figures (mdCourseInsight) and of its trend (mdTrendChange).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';

import '../app_bidi.dart' show ltrIsolate;
import '../app_kit.dart';
import '../app_icons.dart' show DirIcons;
import 'entity_chip.dart';

// ── Formatting ───────────────────────────────────────────────────────────────

/// "{x}" placeholders of a translation filled in.
String mdText(String key, [Map<String, String> values = const {}]) {
  var s = key.tr;
  for (final e in values.entries) {
    s = s.replaceAll('{${e.key}}', e.value);
  }
  return s;
}

/// 42.5 → "43%" (left to right inside Arabic).
String mdPercent(num? v) => v == null ? '—' : ltrIsolate('${v.round()}%');

/// A figure as a short number ("1.2K").
String mdNumber(num? v) => v == null ? '—' : appCompactNumber(v.toDouble());

/// "250 EGP" (left to right inside Arabic).
String mdMoney(EntityMoney m) {
  final a = m.amount == m.amount.roundToDouble() ? m.amount.toInt().toString() : m.amount.toStringAsFixed(2);
  return ltrIsolate(m.currency.isEmpty ? a : '$a ${m.currency}');
}

/// [mdMoney] for a stat tile: "41.3K EGP" from ten thousand up, so the figure stays on one line.
String mdMoneyShort(EntityMoney m) {
  if (m.amount.abs() < 10000) return mdMoney(m);
  final a = appCompactNumber(m.amount);
  return ltrIsolate(m.currency.isEmpty ? a : '$a ${m.currency}');
}

String mdDate(DateTime? utc) => utc == null ? '—' : AppTime.date(utc);

String mdDateTime(DateTime? utc) => utc == null ? '—' : AppTime.dateTime(utc);

/// "3 h ago" / "منذ 3 أيام"; a date after a week.
String mdAgo(DateTime? utc, {DateTime? now}) {
  if (utc == null) return '—';
  final d = (now ?? DateTime.now().toUtc()).difference(utc);
  if (d.isNegative || d.inMinutes < 1) return 'md_just_now'.tr;
  if (d.inMinutes < 60) {
    return countText(d.inMinutes,
        ar1: 'منذ دقيقة', ar2: 'منذ دقيقتين', arFew: 'منذ {n} دقائق', arMany: 'منذ {n} دقيقة', en1: '1 min ago', en: '{n} min ago');
  }
  if (d.inHours < 24) {
    return countText(d.inHours,
        ar1: 'منذ ساعة', ar2: 'منذ ساعتين', arFew: 'منذ {n} ساعات', arMany: 'منذ {n} ساعة', en1: '1 h ago', en: '{n} h ago');
  }
  if (d.inDays < 7) {
    return countText(d.inDays,
        ar1: 'منذ يوم', ar2: 'منذ يومين', arFew: 'منذ {n} أيام', arMany: 'منذ {n} يوماً', en1: '1 day ago', en: '{n} days ago');
  }
  return mdDate(utc);
}

/// "3 courses" / "3 دورات".
String mdCourses(int n) => countText(n,
    ar0: 'لا دورات', ar1: 'دورة واحدة', ar2: 'دورتان', arFew: '{n} دورات', arMany: '{n} دورة',
    en0: 'No courses', en1: '1 course', en: '{n} courses');

/// "31 students" / "31 طالباً".
String mdStudents(int n) => countText(n,
    ar0: 'لا طلاب', ar1: 'طالب واحد', ar2: 'طالبان', arFew: '{n} طلاب', arMany: '{n} طالباً',
    en0: 'No students', en1: '1 student', en: '{n} students');

/// A code with no wording yet ("content_mismatch" → "Content mismatch").
String mdHumanize(String code) {
  final s = code.replaceAll('_', ' ').trim();
  return s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// The translation of `<prefix><code>`, or the code made readable when there is none.
String _worded(String prefix, String code) {
  final key = '$prefix$code';
  final s = key.tr;
  return s == key ? mdHumanize(code) : s;
}

// ── Wording of the server's codes ───────────────────────────────────────────

String mdSectionTitle(String section) => _worded('md_sec_', section);

/// pending · in_progress · completed · withdrawn · expired
String mdStateLabel(String state) => _worded('md_state_', state);

AppTone mdStateTone(String state) => switch (state) {
      'completed' => AppTone.success,
      'in_progress' => AppTone.brand,
      'withdrawn' => AppTone.danger,
      'expired' => AppTone.warning,
      _ => AppTone.neutral,
    };

/// A withdrawal reason code (`price`, `time`, … `unknown`); null → "Not recorded".
String mdReasonLabel(String? code) => _worded('md_reason_', code ?? 'unknown');

/// A course status filter / chip (published · draft · archived · in_progress · completed).
String mdCourseStatusLabel(String status) => _worded('md_status_', status);

String mdSortLabel(String sort) => _worded('md_sort_', sort);

String mdPaymentStatus(String? status) => _worded('md_pay_', status ?? 'pending');

AppTone mdPaymentTone(String? status) => switch (status) {
      'completed' => AppTone.success,
      'failed' => AppTone.danger,
      'refunded' => AppTone.warning,
      _ => AppTone.neutral,
    };

String mdSubscriptionText(String type) => _worded('md_sub_', type);

String? mdActorText(String? actor) {
  if (actor == null) return null;
  final key = 'md_actor_$actor';
  final s = key.tr;
  return s == key ? null : s;
}

AppTone mdBadgeTone(String level) => switch (level) {
      'good' => AppTone.success,
      'bad' => AppTone.danger,
      'warn' => AppTone.warning,
      _ => AppTone.info,
    };

IconData mdBadgeIcon(String code) => switch (code) {
      'inactive' => Icons.bedtime_outlined,
      'at_risk' => Icons.warning_amber_rounded,
      'all_done' => Icons.workspace_premium_outlined,
      'trending' => Icons.trending_up_rounded,
      'dropping' => Icons.trending_down_rounded,
      'high_withdrawal' => DirIcons.logout,
      'top_rated' => Icons.star_rounded,
      'low_engagement' => Icons.bedtime_outlined,
      'low_completion' => Icons.trending_down_rounded,
      'no_courses' || 'nothing_published' => Icons.inbox_outlined,
      _ => Icons.info_outline_rounded,
    };

/// A badge's sentence ("Inactive for 20 days", "1 course at risk", …).
String mdBadgeText(EntityBadge b) {
  final n = b.value?.round();
  switch (b.code) {
    case 'inactive':
      if (n == null) return 'md_badge_inactive'.tr;
      return countText(n,
          ar1: 'غير نشط منذ يوم', ar2: 'غير نشط منذ يومين', arFew: 'غير نشط منذ {n} أيام', arMany: 'غير نشط منذ {n} يوماً',
          en1: 'Inactive for 1 day', en: 'Inactive for {n} days');
    case 'at_risk':
      if (n == null) return 'md_badge_at_risk'.tr;
      return countText(n,
          ar1: 'دورة واحدة متعثرة', ar2: 'دورتان متعثرتان', arFew: '{n} دورات متعثرة', arMany: '{n} دورة متعثرة',
          en1: '1 course at risk', en: '{n} courses at risk');
    case 'top_rated':
      return mdText('md_p6_badge_top_rated', {'v': ltrIsolate((b.value ?? 0).toStringAsFixed(1))});
    case 'low_engagement':
      return mdText('md_p6_badge_low_engagement', {'v': mdPercent(b.value)});
    case 'low_completion':
      return mdText('md_p6_badge_low_completion', {'v': mdPercent(b.value)});
    case 'no_courses' || 'nothing_published':
      return 'md_p6_badge_${b.code}'.tr;
    default:
      return _worded('md_badge_', b.code);
  }
}

/// One history event as a sentence.
String mdTimelineText(EntityTimelineEvent e) {
  final d = e.data;
  final title = entityString(d['title']);
  switch (e.type) {
    case 'material_completed':
      return title == null ? 'md_p4_tl_lesson'.tr : mdText('md_tl_material_completed', {'t': title});
    case 'live_attended':
      return title == null ? 'md_p4_tl_live'.tr : mdText('md_tl_live_attended', {'t': title});
    case 'exam_submitted':
      final p = entityDouble(d['percentage']);
      final head = title == null ? 'md_p4_tl_exam'.tr : mdText('md_tl_exam_submitted', {'t': title});
      return p == null ? head : '$head · ${mdPercent(p)}';
    case 'rated':
      return mdText('md_tl_rated', {'v': '${entityInt(d['value'])}'});
    case 'withdrawn':
      return '${'md_tl_withdrawn'.tr} · ${mdReasonLabel(entityString(d['reason_code']))}';
    case 'subscription':
      final ev = entityString(d['event']);
      return mdText('md_tl_subscription', {'e': ev == null ? '—' : mdSubscriptionText(ev)});
    default:
      return _worded('md_tl_', e.type);
  }
}

IconData mdTimelineIcon(String type) => switch (type) {
      'enrolled' => Icons.how_to_reg_rounded,
      'first_visit' => Icons.door_front_door_outlined,
      'material_completed' => Icons.task_alt_rounded,
      'live_attended' => Icons.videocam_outlined,
      'exam_submitted' => Icons.quiz_outlined,
      'favorited' => Icons.favorite_border_rounded,
      'rated' => Icons.star_border_rounded,
      'completed' => Icons.workspace_premium_outlined,
      'withdrawn' => DirIcons.logout,
      'subscription' => Icons.receipt_long_outlined,
      _ => Icons.circle_outlined,
    };

AppTone mdTimelineTone(EntityTimelineEvent e) => switch (e.type) {
      'completed' => AppTone.success,
      'withdrawn' => AppTone.danger,
      'exam_submitted' => e.data['passed'] == false ? AppTone.warning : AppTone.success,
      'enrolled' || 'first_visit' => AppTone.brand,
      'subscription' => switch (entityString(e.data['event'])) {
          'cancelled' || 'refunded' || 'payment_failed' || 'access_denied' => AppTone.danger,
          'expired' => AppTone.warning,
          'payment_succeeded' || 'activated' || 'renewed' => AppTone.success,
          _ => AppTone.info,
        },
      _ => AppTone.info,
    };

/// The last 4 weeks of [trend] against the 4 before, in whole percent; null without 8 weeks or with nothing to compare
/// (no enrollment in the 4 before).
int? mdTrendChange(List<EntityTrendPoint> trend) {
  if (trend.length < 8) return null;
  int sum(Iterable<EntityTrendPoint> ps) => ps.fold<int>(0, (a, p) => a + p.count);
  final recent = sum(trend.skip(trend.length - 4)), before = sum(trend.skip(trend.length - 8).take(4));
  if (before == 0) return null;
  return (100 * (recent - before) / before).round();
}

/// A staff view of a course in one line: how many finished, and the main reason for leaving; null before anyone
/// counts.
String? mdCourseInsight(EntitySummary s) {
  if (s.kind != EntityKind.course || s.isLearnerView) return null;
  final enrolled = s.stat('enrolled'), done = s.stat('completed');
  if (enrolled == null || done == null) return null;
  final counted = (enrolled - (s.stat('pending') ?? 0)).round();
  if (counted <= 0) return null;
  final parts = [
    mdText('md_p5_insight_completed', {'n': mdNumber(done), 'total': mdNumber(counted)}),
  ];
  final reasons = s.withdrawalReasons.where((r) => r.$1 != 'unknown').toList()..sort((a, b) => b.$2.compareTo(a.$2));
  if (reasons.isNotEmpty) parts.add(mdText('md_p5_insight_reason', {'r': mdReasonLabel(reasons.first.$1)}));
  return parts.join(' · ');
}

// ── Sections ─────────────────────────────────────────────────────────────────

enum EntitySectionShape { list, timeline, block }

/// How one section of a summary draws.
class EntitySectionSpec {
  const EntitySectionSpec(
    this.section, {
    required this.icon,
    this.shape = EntitySectionShape.list,
    this.sorts = const [],
    this.filterKey,
    this.filterOptions = const [],
    this.searchable = true,
    this.pageSize = 10,
    this.titleKey,
  });

  final String section;
  final IconData icon;
  final EntitySectionShape shape;

  /// The contract's sorts, the default first.
  final List<String> sorts;

  /// `state` / `status`, with its values (null: no filter).
  final String? filterKey;
  final List<String> filterOptions;
  final bool searchable;
  final int pageSize;

  /// The heading's translation key when it is not the section's usual one.
  final String? titleKey;

  String get title => titleKey?.tr ?? mdSectionTitle(section);

  String filterLabel(String value) => switch (filterKey) {
        'state' => mdStateLabel(value),
        'activity' => 'md_p6_activity_$value'.tr,
        'account' => 'md_$value'.tr,
        _ => mdCourseStatusLabel(value),
      };
}

const _enrollmentSorts = ['enrolled_desc', 'enrolled_asc', 'progress_desc', 'progress_asc', 'activity_desc', 'name'];
const _courseStatuses = ['published', 'draft', 'archived', 'in_progress', 'completed'];

/// The people lists' filters (`activity` of a learner, `account` of a teacher).
const _activities = ['active', 'inactive'];

/// The spec of [section] of a [kind] entity; null for a section this app version does not know (left out).
EntitySectionSpec? sectionSpecOf(EntityKind kind, String section) => switch ((kind, section)) {
      (EntityKind.student, 'courses') => const EntitySectionSpec('courses',
          icon: Icons.auto_stories_rounded,
          sorts: _enrollmentSorts,
          filterKey: 'state',
          filterOptions: entityEnrollmentStates,
          titleKey: 'md_p4_sec_courses'),
      (EntityKind.course, 'timeline') =>
        const EntitySectionSpec('timeline', icon: Icons.history_rounded, shape: EntitySectionShape.timeline),
      (EntityKind.student, 'payments') => const EntitySectionSpec('payments',
          icon: Icons.payments_outlined, sorts: ['newest', 'oldest', 'amount_desc']),
      (EntityKind.student, 'subscriptions') => const EntitySectionSpec('subscriptions',
          icon: Icons.receipt_long_outlined, sorts: ['newest', 'oldest'], searchable: false),
      (EntityKind.course, 'students') => const EntitySectionSpec('students',
          icon: Icons.groups_rounded, sorts: _enrollmentSorts, filterKey: 'state', filterOptions: entityEnrollmentStates),
      (EntityKind.course, 'content') =>
        const EntitySectionSpec('content', icon: Icons.video_library_outlined, shape: EntitySectionShape.block),
      (EntityKind.teacher, 'courses') => const EntitySectionSpec('courses',
          icon: Icons.auto_stories_rounded,
          sorts: ['newest', 'students_desc', 'rating_desc', 'name'],
          filterKey: 'status',
          filterOptions: _courseStatuses),
      (EntityKind.teacher, 'students') || (EntityKind.category, 'students') => const EntitySectionSpec('students',
          icon: Icons.groups_rounded,
          sorts: ['activity_desc', 'progress_desc', 'name'],
          filterKey: 'activity',
          filterOptions: _activities),
      (EntityKind.category, 'courses') => const EntitySectionSpec('courses',
          icon: Icons.auto_stories_rounded,
          sorts: ['students_desc', 'newest', 'rating_desc', 'name'],
          filterKey: 'status',
          filterOptions: _courseStatuses),
      (EntityKind.category, 'teachers') => const EntitySectionSpec('teachers',
          icon: Icons.co_present_rounded,
          sorts: ['students_desc', 'name'],
          filterKey: 'account',
          filterOptions: _activities),
      _ => null,
    };

// ── Stat tiles ───────────────────────────────────────────────────────────────

/// One tile: its label, icon, tone and the value as text.
class EntityStat {
  const EntityStat(this.key, this.label, this.icon, this.value, {this.tone = AppTone.brand});

  final String key;
  final String label;
  final IconData icon;
  final String value;
  final AppTone tone;
}

/// The tiles of [s]: only the figures the server sent (a learner's course view sends fewer).
List<EntityStat> statSpecsOf(EntitySummary s) {
  final out = <EntityStat>[];
  void count(String key, String label, IconData icon, {AppTone tone = AppTone.brand, bool hideZero = false}) {
    final v = s.stat(key);
    if (v == null || (hideZero && v == 0)) return;
    out.add(EntityStat(key, label.tr, icon, mdNumber(v), tone: tone));
  }

  void percent(String key, String label, IconData icon, {AppTone tone = AppTone.brand}) {
    final v = s.stat(key);
    if (v == null) return;
    out.add(EntityStat(key, label.tr, icon, mdPercent(v), tone: tone));
  }

  void rating(String key, String label, {String? countKey}) {
    final v = s.stat(key);
    if (v == null) return;
    final n = countKey == null ? null : s.stat(countKey);
    final text = n == null || n == 0 ? v.toStringAsFixed(1) : '${v.toStringAsFixed(1)} (${mdNumber(n)})';
    out.add(EntityStat(key, label.tr, Icons.star_rounded, ltrIsolate(text), tone: AppTone.warning));
  }

  void money() {
    final r = s.revenue;
    if (r.isEmpty) return;
    out.add(EntityStat('revenue', 'md_stat_revenue'.tr, Icons.account_balance_wallet_outlined,
        r.map(mdMoneyShort).join(' · '), tone: AppTone.success));
  }

  switch (s.kind) {
    case EntityKind.student: // the states are the overview's bar (StudentOverviewCard), these its figures
      percent('avg_progress', 'md_stat_avg_progress', Icons.trending_up_rounded);
      if (s.stats.containsKey('last_activity_at')) {
        out.add(EntityStat('last_activity_at', 'md_stat_last_activity'.tr, Icons.schedule_rounded,
            s.statTime('last_activity_at') == null ? 'md_no_activity'.tr : mdAgo(s.statTime('last_activity_at')),
            tone: AppTone.info));
      }
      if (s.paid.isNotEmpty) {
        out.add(EntityStat('paid', 'md_p4_stat_paid'.tr, Icons.account_balance_wallet_outlined,
            s.paid.map(mdMoney).join(' · '), tone: AppTone.success));
      }
    case EntityKind.course:
      count('enrolled', 'md_stat_students', Icons.groups_rounded);
      if (!s.isLearnerView) {
        count('in_progress', 'md_stat_in_progress', Icons.play_circle_outline_rounded);
        count('completed', 'md_stat_completed', Icons.task_alt_rounded, tone: AppTone.success);
        count('withdrawn', 'md_stat_withdrawn', DirIcons.logout, tone: AppTone.danger);
        percent('completion_rate', 'md_stat_completion', Icons.workspace_premium_outlined, tone: AppTone.success);
        percent('avg_progress', 'md_stat_avg_progress', Icons.trending_up_rounded);
      }
      rating('rating_avg', 'md_stat_rating', countKey: 'rating_count');
      if (s.isLearnerView) {
        count('sessions', 'md_stat_sessions', Icons.event_note_outlined);
        count('materials', 'md_stat_materials', Icons.video_library_outlined);
      } else {
        count('favorites', 'md_stat_favorites', Icons.favorite_border_rounded, tone: AppTone.danger);
      }
      money();
      if (!s.isLearnerView) {
        count('expired', 'md_stat_expired', Icons.timer_off_outlined, tone: AppTone.warning, hideZero: true);
        count('pending', 'md_stat_pending', Icons.hourglass_empty_rounded, tone: AppTone.neutral, hideZero: true);
      }
    case EntityKind.teacher:
      count('courses', 'md_stat_courses', Icons.library_books_outlined);
      count('published_courses', 'md_stat_published', Icons.public_rounded);
      count('students', 'md_stat_students', Icons.groups_rounded);
      count('active_students_30d', 'md_stat_active_30d', Icons.bolt_rounded, tone: AppTone.success);
      rating('rating_avg', 'md_stat_course_rating');
      rating('teacher_rating_avg', 'md_stat_teacher_rating');
      percent('completion_rate', 'md_stat_completion', Icons.workspace_premium_outlined, tone: AppTone.success);
      money();
    case EntityKind.category:
      count('courses', 'md_stat_courses', Icons.library_books_outlined);
      count('teachers', 'md_stat_teachers', Icons.co_present_rounded);
      count('students', 'md_stat_students', Icons.groups_rounded);
      percent('completion_rate', 'md_stat_completion', Icons.workspace_premium_outlined, tone: AppTone.success);
  }
  return out;
}

// ── Rows ─────────────────────────────────────────────────────────────────────

/// The square picture of a course / category, or its icon on a tint.
class EntityThumb extends StatelessWidget {
  const EntityThumb(this.ref, {super.key, this.size = 40});

  final EntityRef ref;
  final double size;

  @override
  Widget build(BuildContext context) {
    // the initial is decoration: the name is read beside it
    if (ref.isPerson) return ExcludeSemantics(child: AppAvatar(name: ref.name, url: ref.imageUrl, size: size));
    final c = context.colors;
    final r = BorderRadius.circular(size * 0.28);
    final icon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.primaryTint, borderRadius: r),
      child: Icon(entityKindIcon(ref.kind), size: size * 0.5, color: Color.lerp(c.primary, c.textDark, 0.25)),
    );
    final url = ref.imageUrl;
    if (url == null || url.isEmpty) return icon;
    return ClipRRect(
      borderRadius: r,
      child: Image.network(url,
          width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon, semanticLabel: ref.name),
    );
  }
}

/// The frame of every sub-list row: the link area (leading · title · subtitle · body · trailing) and an optional
/// action beside it (never inside the link: one row, one link).
class EntityRowFrame extends StatelessWidget {
  const EntityRowFrame({
    super.key,
    required this.ref,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.body = const [],
    this.action,
    this.highlight = false,
  });

  final EntityRef ref;
  final String title;
  final Widget? leading;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> body;
  final Widget? action;
  final bool highlight;

  /// The most a trailing chip takes from the title.
  static const double _trailingWidth = 112;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        leading ?? EntityThumb(ref),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpace.xs),
                // a narrow sheet at a large text size: the chip shrinks instead of pushing the title out
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _trailingWidth),
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.topEnd, child: trailing!),
                ),
              ],
            ]),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
            for (final w in body) ...[const SizedBox(height: AppSpace.xs), w],
          ]),
        ),
      ]),
    );
    final link = EntityLink(ref, child: content);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight ? c.primaryTint : null,
        borderRadius: AppRadius.cardAll,
      ),
      child: action == null
          ? link
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: link),
              Padding(padding: const EdgeInsets.only(top: AppSpace.xxs), child: action!),
            ]),
    );
  }
}

/// A progress bar with its percentage, after [label] when given ("Completion").
class EntityProgress extends StatelessWidget {
  const EntityProgress(this.value, {super.key, this.tone, this.label});

  final double? value;
  final Color? tone;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).clamp(0, 100).toDouble();
    return Semantics(
      label: '${label ?? 'md_progress'.tr} ${mdPercent(v)}',
      excludeSemantics: true,
      child: Row(children: [
        if (label != null) ...[
          Flexible(child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
          AppSpace.gapXs,
        ],
        Expanded(child: AppProgressBar(value: v, height: 6, color: tone ?? appScoreColor(context, v))),
        AppSpace.gapXs,
        SizedBox(
          width: 44,
          child: Text(mdPercent(v),
              textAlign: TextAlign.end,
              style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textDark)),
        ),
      ]),
    );
  }
}

/// The dates of an enrollment as meta lines: enrolled · last activity; completed; withdrawn + reason (+ the text for
/// admins); the expected end.
List<Widget> enrollmentMeta(BuildContext context, EntityEnrollment e) {
  final meta = AppType.meta(context);
  final parts = <String>[
    if (e.enrolledAt != null) mdText('md_enrolled_on', {'d': mdDate(e.enrolledAt)}),
    e.lastActivityAt != null ? mdText('md_last_activity', {'d': mdAgo(e.lastActivityAt)}) : 'md_no_activity'.tr,
  ];
  final out = <Widget>[Text(parts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: meta)];
  if (e.state == 'completed' && e.completedAt != null) {
    out.add(Text(mdText('md_completed_on', {'d': mdDate(e.completedAt)}),
        maxLines: 1, overflow: TextOverflow.ellipsis, style: meta.copyWith(color: context.colors.success)));
  }
  if (e.state == 'withdrawn' || e.withdrawnAt != null) {
    final c = context.colors;
    out.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs + 2),
      decoration: BoxDecoration(color: c.danger.withValues(alpha: c.isDark ? 0.16 : 0.07), borderRadius: AppRadius.chipAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          [
            if (e.withdrawnAt != null) mdText('md_withdrawn_on', {'d': mdDate(e.withdrawnAt)}),
            mdText('md_reason', {'r': mdReasonLabel(e.withdrawalReasonCode)}),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: meta.copyWith(color: c.textDark),
        ),
        if (e.withdrawalReason != null)
          Text('“${e.withdrawalReason}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: meta),
      ]),
    ));
  }
  if (e.state != 'withdrawn' && e.state != 'completed' && e.expectedEndAt != null) {
    out.add(Text(mdText(e.state == 'expired' ? 'md_ended_on' : 'md_expected_end', {'d': mdDate(e.expectedEndAt)}),
        maxLines: 1, overflow: TextOverflow.ellipsis, style: meta));
  }
  return out;
}

/// A small "history" button beside an enrollment row (the student's timeline in that course).
class EntityHistoryButton extends StatelessWidget {
  const EntityHistoryButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      AppIconButton(icon: Icons.history_rounded, tooltip: 'md_history'.tr, onPressed: onPressed);
}

/// One row of a sub-list. [onHistory] (enrollment rows) opens the student's timeline in that course. [ownerKind] is
/// the entity the list belongs to: a teacher's course rows leave the teacher out, a category's the category.
Widget entityRowFor(BuildContext context, EntityItem item,
    {void Function(int studentId, int courseId, String title)? onHistory,
    int? ownerId,
    int? highlightId,
    EntityKind? ownerKind}) {
  switch (item) {
    case EnrollmentRow(:final subject, :final course, :final enrollment):
      final isCourse = subject.kind == EntityKind.course;
      final sub = isCourse
          ? [course?.teacher?.name, course?.category?.name].whereType<String>().where((s) => s.isNotEmpty).join(' · ')
          : (usernameOf(item.json['student']) != null ? '@${usernameOf(item.json['student'])}' : null);
      final studentId = isCourse ? ownerId : subject.id;
      final courseId = isCourse ? subject.id : ownerId;
      return EntityRowFrame(
        ref: subject,
        title: subject.name.isEmpty ? '#${subject.id}' : subject.name,
        subtitle: sub,
        highlight: highlightId == subject.id,
        trailing: AppStatusBadge(
            label: mdStateLabel(enrollment.state), tone: mdStateTone(enrollment.state), dense: true),
        body: [
          if (enrollment.state != 'pending') EntityProgress(enrollment.progress),
          ...enrollmentMeta(context, enrollment),
        ],
        action: onHistory == null || studentId == null || courseId == null
            ? null
            : EntityHistoryButton(onPressed: () => onHistory(studentId, courseId, subject.name)),
      );
    case CourseRow(:final course):
      final belongs = [
        if (ownerKind != EntityKind.teacher) course.teacher?.name,
        if (ownerKind != EntityKind.category) course.category?.name,
      ];
      final status = item.archivedAt != null ? 'archived' : (item.isPublished ? 'published' : 'draft');
      return EntityRowFrame(
        ref: course.ref,
        title: course.ref.name.isEmpty ? '#${course.ref.id}' : course.ref.name,
        subtitle: belongs.whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        highlight: highlightId == course.ref.id,
        trailing: AppStatusBadge(
            label: mdCourseStatusLabel(status),
            tone: status == 'published' ? AppTone.success : (status == 'archived' ? AppTone.danger : AppTone.neutral),
            dense: true),
        body: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: mdStudents(item.students)),
              if (item.ratingAvg != null) ...[
                const TextSpan(text: ' · '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.star_rounded, size: AppIconSize.xs, color: appToneInk(context, AppTone.warning)),
                ),
                TextSpan(text: ' ${ltrIsolate(item.ratingAvg!.toStringAsFixed(1))}'),
              ],
              if (item.revenue != null) TextSpan(text: ' · ${mdMoney(item.revenue!)}'),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta(context),
          ),
          if (item.completionRate != null && item.students > 0)
            // a fact about the class, not a grade: the brand colour whatever the figure
            EntityProgress(item.completionRate, label: 'md_stat_completion'.tr, tone: context.colors.primary),
        ],
      );
    case PersonRow(:final person):
      final facts = [
        if (item.students != null) mdStudents(item.students!),
        mdCourses(item.courses),
        if (item.avgProgress != null) '${'md_stat_avg_progress'.tr} ${mdPercent(item.avgProgress)}',
      ];
      return EntityRowFrame(
        ref: person,
        title: person.name.isEmpty ? '#${person.id}' : person.name,
        subtitle: item.username == null ? null : '@${item.username}',
        highlight: highlightId == person.id,
        body: [
          Text(facts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          if (item.json.containsKey('last_activity_at'))
            Text(
                item.lastActivityAt == null
                    ? 'md_no_activity'.tr
                    : mdText('md_last_activity', {'d': mdAgo(item.lastActivityAt)}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context)),
        ],
      );
    case PaymentRow(:final course):
      final ref = course?.ref ?? const EntityRef(EntityKind.course, 0);
      return EntityRowFrame(
        ref: ref,
        title: ref.name.isEmpty ? '—' : ref.name,
        subtitle: [
          mdDate(item.paidAt ?? item.createdAt),
          if (item.method != null) mdHumanize(item.method!),
        ].join(' · '),
        leading: entityToneIcon(context, Icons.payments_outlined, mdPaymentTone(item.status)),
        trailing: Text(
          item.amount == null ? '—' : mdMoney(EntityMoney(item.amount!, item.currency)),
          style: AppType.bodyStrong(context).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        body: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppStatusBadge(label: mdPaymentStatus(item.status), tone: mdPaymentTone(item.status), dense: true),
          ),
          if (item.refundedAt != null)
            Text(mdText('md_refunded_on', {'d': mdDate(item.refundedAt)}), style: AppType.meta(context)),
        ],
      );
    case SubscriptionRow(:final course):
      final ref = course?.ref ?? const EntityRef(EntityKind.course, 0);
      return EntityRowFrame(
        ref: ref,
        title: mdSubscriptionText(item.type),
        subtitle: [ref.name, mdDateTime(item.occurredAt)].where((s) => s.isNotEmpty).join(' · '),
        leading: entityToneIcon(context, Icons.receipt_long_outlined, AppTone.info),
        body: [
          if (mdActorText(item.actorType) != null)
            Text(mdActorText(item.actorType)!, style: AppType.meta(context)),
          if (item.reason != null)
            Text('“${item.reason}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
        ],
      );
    case RawRow():
      return const SizedBox.shrink();
  }
}

/// An icon on a circle of its tone (a payment, a line of a timeline).
Widget entityToneIcon(BuildContext context, IconData icon, AppTone tone, {double size = 40}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: appToneTint(context, tone), shape: BoxShape.circle),
      child: Icon(icon, size: size < 40 ? AppIconSize.sm : AppIconSize.md, color: appToneInk(context, tone)),
    );
