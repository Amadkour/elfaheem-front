// lib/features/courses/course_space/course_overview.dart
//
// The course page's Overview tab (D-1090, the owner's A2 pick): the course's own dashboard, from the `page` block of
// GET /course-profile/{id}. Plain values only (no provider, no ApiClient) so test/ui/course_overview_layout_test.dart
// pumps every card at every size, in both languages.
//
//   wide (≥ 900)   Appointments (2/3) | Weekly schedule + Exams (1/3)  →  Course rules  →  Attendance · Team ·
//                  (personal) Reviews · After this course
//   narrow         one column in the same order
//
// Rules of the page (owner, 2026-11-16): a student only ever sees the lectures and THEIR section (the server already
// filters; the card never offers another group); staff filter by Lectures / Sections and by section group; "no
// material" is ONE staff note, not a warning per row. The page's ONE highlighted card is the "Next for you" card
// ([CourseNextCard], in the spotlight above the tabs), so no card here is highlighted.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_profile/course_page_models.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// One session row of the Appointments card (plain values; each role's screen maps its own sessions into it).
class CourseApptRow {
  const CourseApptRow({
    required this.id,
    required this.name,
    this.track = 'lecture',
    this.groupNo,
    this.at,
    this.minutes,
    this.hasMaterial = true,
    this.liveNow = false,
  });

  final int id;
  final String name;

  /// lecture · section
  final String track;
  final int? groupNo;
  final DateTime? at;
  final int? minutes;
  final bool hasMaterial;
  final bool liveNow;
  bool get isSection => track == 'section';
}

/// What the Overview's buttons do (null = the button is not drawn).
class CourseOverviewActions {
  const CourseOverviewActions({
    this.onOpenSession,
    this.onAllSessions,
    this.onNewSession,
    this.onEditSchedule,
    this.onOpenExams,
    this.onEditRules,
    this.onManageSections,
    this.onPickSection,
    this.onAttendance,
    this.onTeam,
    this.onReviews,
    this.onOpenPathCourse,
    this.onEditPath,
  });

  final ValueChanged<int>? onOpenSession;
  final VoidCallback? onAllSessions, onNewSession, onEditSchedule, onOpenExams, onEditRules, onManageSections;
  final VoidCallback? onPickSection, onAttendance, onTeam, onReviews, onEditPath;
  final ValueChanged<int>? onOpenPathCourse;
}

/// The Overview tab.
class CourseOverview extends StatefulWidget {
  const CourseOverview({
    super.key,
    required this.page,
    required this.staff,
    required this.sessions,
    this.actions = const CourseOverviewActions(),
    this.now,
    this.padding = const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
  });

  final CoursePage page;
  final bool staff;
  final List<CourseApptRow> sessions;
  final CourseOverviewActions actions;

  /// "Now" (tests pin it); null → DateTime.now().
  final DateTime? now;
  final EdgeInsetsGeometry padding;

  /// From this width: two columns.
  static const double wideAt = 900;

  @override
  State<CourseOverview> createState() => _CourseOverviewState();
}

class _CourseOverviewState extends State<CourseOverview> {
  /// all · lecture · section
  String _kind = 'all';

  /// A staff member's section-group filter (null = every group).
  int? _group;

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final a = widget.actions;
    final appts = CourseAppointmentsCard(
      page: p,
      staff: widget.staff,
      sessions: widget.sessions,
      now: widget.now ?? DateTime.now().toUtc(),
      kind: _kind,
      group: _group,
      onKind: (k) => setState(() {
        _kind = k;
        if (k == 'lecture') _group = null;
      }),
      onGroup: (g) => setState(() => _group = g),
      actions: a,
    );
    final week = CourseWeekCard(page: p, staff: widget.staff, onEdit: a.onEditSchedule);
    final exams = CourseExamsCard(exams: p.exams, staff: widget.staff, onOpen: a.onOpenExams);
    final rules = ParentComponent(
      featureKey: 'course.rules',
      child: CourseRulesCard(rules: p.rules, staff: widget.staff, onEdit: a.onEditRules),
    );
    final small = <Widget>[
      CourseAttendanceCard(attendance: p.attendance, staff: widget.staff, onOpen: a.onAttendance),
      CourseTeamCard(page: p, staff: widget.staff, onOpen: a.onTeam),
      if (p.personal != null) CourseReviewsCard(personal: p.personal!, onOpen: a.onReviews),
      if (p.personal != null)
        CoursePathCard(path: p.personal!.path, staff: widget.staff, onOpen: a.onOpenPathCourse, onEdit: a.onEditPath),
    ];
    return Padding(
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= CourseOverview.wideAt;
          const gap = SizedBox(height: AppSpace.md, width: AppSpace.md);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [appts, gap, week, gap, exams, gap, rules, for (final w in small) ...[gap, w]],
            );
          }
          // the small cards two per row (a lone last one keeps half the width)
          final rows = <Widget>[];
          for (var i = 0; i < small.length; i += 2) {
            rows.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: small[i]),
                gap,
                Expanded(child: i + 1 < small.length ? small[i + 1] : const SizedBox.shrink()),
              ],
            ));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: appts),
                  gap,
                  Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [week, gap, exams])),
                ],
              ),
              gap,
              rules,
              for (final r in rows) ...[gap, r],
            ],
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Small shared parts
// ═════════════════════════════════════════════════════════════════════════════

/// A tinted icon tile (the row's kind).
class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.tone});

  final IconData icon;
  final AppBlockTone tone;

  @override
  Widget build(BuildContext context) {
    final strong = appToneStrong(context, tone);
    return Container(
      width: AppTouch.min - AppSpace.xs,
      height: AppTouch.min - AppSpace.xs,
      decoration: BoxDecoration(color: AppBlockColors.of(context, tone).surface, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Icon(icon, size: AppIconSize.md, color: strong),
    );
  }
}

/// A quiet one-line note (icon + text), e.g. "12 sessions without material".
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color, this.action, this.onAction});

  final IconData icon;
  final String text;
  final Color? color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.sm, color: color ?? c.textLight),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: color ?? c.textLight)),
          ),
          if (action != null && onAction != null) AppButton(label: action!, onPressed: onAction, variant: AppButtonVariant.ghost, size: AppButtonSize.sm),
        ],
      ),
    );
  }
}

/// A thin bar 0…1 (the absence meter, the setup bar).
class CourseMeter extends StatelessWidget {
  const CourseMeter({super.key, required this.value, this.color});

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        height: AppSpace.xs,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: c.divider)),
            FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: value.clamp(0, 1).toDouble(),
              child: ColoredBox(color: color ?? c.primary),
            ),
          ],
        ),
      ),
    );
  }
}

String _dayName(String day) => switch (day) {
  'saturday' => _t('السبت', 'Sat'),
  'sunday' => _t('الأحد', 'Sun'),
  'monday' => _t('الاثنين', 'Mon'),
  'tuesday' => _t('الثلاثاء', 'Tue'),
  'wednesday' => _t('الأربعاء', 'Wed'),
  'thursday' => _t('الخميس', 'Thu'),
  'friday' => _t('الجمعة', 'Fri'),
  _ => day,
};

String _groupLabel(CoursePage p, int? no) {
  final g = p.sections.group(no);
  if (g != null) return g.labelFor(AppConfig.lang == 'ar');
  return no == null ? _t('سكشن', 'Section') : _t('سكشن $no', 'Section $no');
}

String _minutes(int m) => m < 60
    ? countText(m, ar1: 'دقيقة واحدة', ar2: 'دقيقتان', arFew: '{n} دقائق', arMany: '{n} دقيقة', en1: '1 min', en: '{n} min')
    : (m % 60 == 0 ? _t('${m ~/ 60} س', '${m ~/ 60} h') : _t('${m ~/ 60} س ${m % 60} د', '${m ~/ 60} h ${m % 60} min'));

// ═════════════════════════════════════════════════════════════════════════════
// Next for you (the page's ONE highlighted card) and the setup bar
// ═════════════════════════════════════════════════════════════════════════════

/// The next session for the caller, with its one action (Join / Start attendance / Start the stream). The ONE
/// highlighted card of the page (D-1081).
class CourseNextCard extends StatelessWidget {
  const CourseNextCard({
    super.key,
    required this.title,
    required this.when,
    this.caption,
    this.section = false,
    this.live = false,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.onTap,
  });

  final String title, when;
  final String? caption;
  final bool section, live;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction, onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = actionLabel == null || onAction == null
        ? null
        : AppButton(label: actionLabel!, icon: actionIcon, onPressed: onAction, size: AppButtonSize.sm);
    return AppCard(
      highlight: true,
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 420;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                live ? _t('مباشر الآن', 'Live now') : _t('التالي لك', 'Next for you'),
                style: AppType.overline(context).copyWith(color: live ? c.danger : c.textLight),
              ),
              const SizedBox(height: AppSpace.xxs),
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              Text(
                [when, ?caption].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta(context).copyWith(color: c.textLight),
              ),
            ],
          );
          final tile = _Tile(
            icon: live ? Icons.sensors_rounded : (section ? Icons.science_rounded : Icons.co_present_rounded),
            tone: section ? AppBlockTone.sky : AppBlockTone.emerald,
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [tile, const SizedBox(width: AppSpace.sm), Expanded(child: text)]),
                if (button != null) ...[const SizedBox(height: AppSpace.sm), Align(alignment: AlignmentDirectional.centerEnd, child: button)],
              ],
            );
          }
          return Row(
            children: [
              tile,
              const SizedBox(width: AppSpace.sm),
              Expanded(child: text),
              if (button != null) ...[const SizedBox(width: AppSpace.sm), button],
            ],
          );
        },
      ),
    );
  }
}

/// "Prepare your course · 2 of 5" — a thin bar while setup is unfinished (staff only); tap = the next step.
class CourseSetupBar extends StatelessWidget {
  const CourseSetupBar({super.key, required this.steps, this.onStep});

  final List<CourseSetupStep> steps;
  final ValueChanged<String>? onStep;

  static String stepLabel(String key) => switch (key) {
    'cover' => _t('صورة الغلاف', 'Cover image'),
    'description' => _t('وصف الكورس', 'Description'),
    'schedule' => _t('الجدول الأسبوعي', 'Weekly schedule'),
    'rules' => _t('قواعد الكورس', 'Course rules'),
    'first_exam' => _t('أول امتحان', 'First exam'),
    _ => key,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final done = steps.where((s) => s.done).length;
    if (steps.isEmpty || done >= steps.length) return const SizedBox.shrink();
    final next = steps.firstWhere((s) => !s.done);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
      onTap: onStep == null ? null : () => onStep!(next.key),
      child: Row(
        children: [
          Icon(Icons.rocket_launch_rounded, size: AppIconSize.md, color: c.accent2),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              _t('جهّز كورسك · $done من ${steps.length}', 'Prepare your course · $done of ${steps.length}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label(context),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: CourseMeter(value: done / steps.length)),
          const SizedBox(width: AppSpace.sm),
          Flexible(
            child: Text(
              _t('التالي: ${stepLabel(next.key)}', 'Next: ${stepLabel(next.key)}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: c.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Appointments
// ═════════════════════════════════════════════════════════════════════════════

class CourseAppointmentsCard extends StatelessWidget {
  const CourseAppointmentsCard({
    super.key,
    required this.page,
    required this.staff,
    required this.sessions,
    required this.now,
    required this.kind,
    required this.group,
    required this.onKind,
    required this.onGroup,
    this.actions = const CourseOverviewActions(),
  });

  final CoursePage page;
  final bool staff;
  final List<CourseApptRow> sessions;
  final DateTime now;
  final String kind;
  final int? group;
  final ValueChanged<String> onKind;
  final ValueChanged<int?> onGroup;
  final CourseOverviewActions actions;

  static const int perGroup = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = page.sections;
    final lectures = sessions.where((r) => !r.isSection).length;
    final sectionRows = sessions.where((r) => r.isSection).length;
    final hasSections = sectionRows > 0 || s.groups.isNotEmpty;

    if (sessions.isEmpty) {
      return AppSectionCard(
        title: _t('المواعيد', 'Appointments'),
        child: AppEmpty(
          icon: Icons.event_note_rounded,
          tone: AppBlockTone.sky,
          title: _t('لا مواعيد بعد', 'No appointments yet'),
          message: staff
              ? _t('أضف أول محاضرة أو سكشن.', 'Add the first lecture or section.')
              : _t('تظهر هنا محاضراتك وسكشنك عندما يضيفها المحاضر.', 'Your lectures and your section appear here once the teacher adds them.'),
          actionLabel: staff && actions.onNewSession != null ? _t('جلسة جديدة', 'New session') : null,
          onAction: staff ? actions.onNewSession : null,
        ),
      );
    }

    // the filter
    var rows = sessions;
    if (kind == 'lecture') rows = rows.where((r) => !r.isSection).toList();
    if (kind == 'section') rows = rows.where((r) => r.isSection).toList();
    if (staff && group != null) rows = rows.where((r) => !r.isSection || r.groupNo == group).toList();

    final today = DateTime.utc(now.year, now.month, now.day);
    final upcoming = rows.where((r) => r.liveNow || r.at == null || !r.at!.isBefore(today)).toList()
      ..sort((x, y) => (x.at ?? now).compareTo(y.at ?? now));
    final past = rows.length - upcoming.length;
    int weekOf(DateTime? at) => at == null ? 0 : at.difference(today).inDays ~/ 7;
    final groups = <int, List<CourseApptRow>>{};
    for (final r in upcoming) {
      groups.putIfAbsent(weekOf(r.at).clamp(0, 2), () => []).add(r);
    }
    final noMaterial = staff ? rows.where((r) => !r.hasMaterial).length : 0;

    final children = <Widget>[];
    // a student: their section, or the one-time pick
    if (!staff && hasSections) {
      if (s.myGroup != null) {
        children.add(_MySection(label: _groupLabel(page, s.myGroup)));
      } else if (s.canPick && actions.onPickSection != null) {
        children.add(_Note(
          icon: Icons.how_to_reg_rounded,
          text: _t('اختر سكشنك مرة واحدة لتظهر لك مواعيده.', 'Pick your section once to see its times.'),
          color: c.primary,
          action: _t('اختر', 'Pick'),
          onAction: actions.onPickSection,
        ));
      }
      children.add(const SizedBox(height: AppSpace.xs));
    }
    if (hasSections) {
      children.add(Align(
        alignment: AlignmentDirectional.centerStart,
        child: AppTabs(
          hug: true,
          index: switch (kind) { 'lecture' => 1, 'section' => 2, _ => 0 },
          onChanged: (i) => onKind(const ['all', 'lecture', 'section'][i]),
          items: [
            AppTabItem(_t('الكل', 'All')),
            AppTabItem(_t('المحاضرات', 'Lectures'), count: lectures),
            AppTabItem(staff ? _t('السكاشن', 'Sections') : _t('سكشني', 'My section'), count: sectionRows),
          ],
        ),
      ));
      if (staff && s.groups.length > 1 && kind != 'lecture') {
        children.add(Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: ParentComponent(
            featureKey: 'course.sections',
            child: Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                AppChoiceChip(label: _t('كل السكاشن', 'All sections'), selected: group == null, onTap: () => onGroup(null)),
                for (final g in s.groups)
                  AppChoiceChip(
                    label: g.students == null ? g.labelFor(AppConfig.lang == 'ar') : '${g.labelFor(AppConfig.lang == 'ar')} (${g.students})',
                    selected: group == g.groupNo,
                    onTap: () => onGroup(group == g.groupNo ? null : g.groupNo),
                  ),
              ],
            ),
          ),
        ));
      }
      children.add(const SizedBox(height: AppSpace.xs));
    }
    if (upcoming.isEmpty) {
      children.add(_Note(icon: Icons.task_alt_rounded, text: _t('لا مواعيد قادمة في هذا الاختيار.', 'Nothing coming up in this view.')));
    }
    for (final e in (groups.entries.toList()..sort((x, y) => x.key.compareTo(y.key)))) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: AppSpace.xs, bottom: AppSpace.xxs),
        child: Text(
          switch (e.key) { 0 => _t('هذا الأسبوع', 'This week'), 1 => _t('الأسبوع القادم', 'Next week'), _ => _t('لاحقًا', 'Later') },
          style: AppType.overline(context).copyWith(color: c.textLight),
        ),
      ));
      for (final r in e.value.take(perGroup)) {
        children.add(_ApptTile(row: r, page: page, staff: staff, next: r.id == page.next?.id, onTap: actions.onOpenSession));
      }
      if (e.value.length > perGroup) {
        children.add(_Note(
          icon: Icons.more_horiz_rounded,
          text: _t('${e.value.length - perGroup} أخرى', '${e.value.length - perGroup} more'),
          action: actions.onAllSessions == null ? null : _t('عرض الكل', 'View all'),
          onAction: actions.onAllSessions,
        ));
      }
    }
    if (noMaterial > 0) {
      children.add(_Note(
        icon: Icons.info_outline_rounded,
        color: c.accent2,
        text: countText(noMaterial,
            ar1: 'جلسة واحدة بلا مواد بعد', ar2: 'جلستان بلا مواد بعد', arFew: '{n} جلسات بلا مواد بعد', arMany: '{n} جلسة بلا مواد بعد',
            en1: '1 session without material yet', en: '{n} sessions without material yet'),
      ));
    }
    if (past > 0) {
      children.add(_Note(
        icon: Icons.history_rounded,
        text: countText(past, ar1: 'جلسة واحدة منتهية', ar2: 'جلستان منتهيتان', arFew: '{n} جلسات منتهية', arMany: '{n} جلسة منتهية',
            en1: '1 finished session', en: '{n} finished sessions'),
        action: actions.onAllSessions == null ? null : _t('عرض', 'Show'),
        onAction: actions.onAllSessions,
      ));
    }

    if (actions.onAllSessions != null) {
      children.add(Align(
        alignment: AlignmentDirectional.centerEnd,
        child: AppButton(label: _t('كل الجلسات', 'All sessions'), onPressed: actions.onAllSessions, variant: AppButtonVariant.ghost, size: AppButtonSize.sm),
      ));
    }
    return AppSectionCard(
      title: _t('المواعيد', 'Appointments'),
      actions: [
        if (staff && actions.onManageSections != null && hasSections)
          ParentComponent(
            featureKey: 'course.sections',
            child: AppButton(label: _t('السكاشن', 'Sections'), onPressed: actions.onManageSections, variant: AppButtonVariant.ghost, size: AppButtonSize.sm),
          ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _MySection extends StatelessWidget {
  const _MySection({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = AppBlockColors.of(context, AppBlockTone.sky);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
      decoration: BoxDecoration(color: tone.surface, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        children: [
          Icon(Icons.badge_rounded, size: AppIconSize.sm, color: appToneStrong(context, AppBlockTone.sky)),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: _t('سكشنك: ', 'Your section: ')),
                TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: _t(' · تظهر لك مواعيده فقط', ' · only its times are shown'), style: TextStyle(color: c.textLight)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.meta(context).copyWith(color: tone.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApptTile extends StatelessWidget {
  const _ApptTile({required this.row, required this.page, required this.staff, required this.next, this.onTap});

  final CourseApptRow row;
  final CoursePage page;
  final bool staff, next;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final at = row.at;
    final meta = [
      if (row.isSection) _groupLabel(page, row.groupNo),
      if (at != null) '${AppTime.date(at, pattern: 'EEE d MMM')} · ${AppTime.time(at)}',
      if (row.minutes != null && row.minutes! > 0) _minutes(row.minutes!),
    ].join(' · ');
    final tag = row.liveNow
        ? (_t('مباشر', 'Live'), c.danger)
        : next
        ? (_t('التالية', 'Next'), c.primary)
        : null;
    return Semantics(
      button: onTap != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.control),
        onTap: onTap == null ? null : () => onTap!(row.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
          child: Row(
            children: [
              _Tile(icon: row.isSection ? Icons.science_rounded : Icons.co_present_rounded, tone: row.isSection ? AppBlockTone.sky : AppBlockTone.emerald),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    if (meta.isNotEmpty)
                      Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                  ],
                ),
              ),
              if (tag != null) ...[
                const SizedBox(width: AppSpace.xs),
                Text(tag.$1, style: AppType.meta(context).copyWith(color: tag.$2, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Weekly schedule
// ═════════════════════════════════════════════════════════════════════════════

class CourseWeekCard extends StatelessWidget {
  const CourseWeekCard({super.key, required this.page, required this.staff, this.onEdit});

  final CoursePage page;
  final bool staff;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final slots = page.week;
    final edit = staff && onEdit != null && page.weekSource == 'course'
        ? [AppButton(label: slots.isEmpty ? _t('إنشاء', 'Create') : _t('تعديل', 'Edit'), onPressed: onEdit, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)]
        : const <Widget>[];
    if (slots.isEmpty) {
      return AppSectionCard(
        title: _t('الجدول الأسبوعي', 'Weekly schedule'),
        actions: edit,
        child: AppEmpty(
          icon: Icons.calendar_view_week_rounded,
          tone: AppBlockTone.sky,
          title: _t('لا جدول بعد', 'No schedule yet'),
          message: staff
              ? _t('حدّد مواعيد المحاضرة والسكاشن مرة واحدة فتتكرر كل أسبوع.', 'Set the lecture and section times once; they repeat every week.')
              : _t('يظهر جدولك عند تحديده.', 'Your schedule appears once it is set.'),
        ),
      );
    }
    final days = [
      for (final d in kCourseWeekDays)
        if (d != 'friday' || slots.any((s) => s.day == 'friday')) d,
    ];
    return AppSectionCard(
      title: _t('الجدول الأسبوعي', 'Weekly schedule'),
      subtitle: page.weekSource == 'timetable' ? _t('من جدول المؤسسة', "From the organization's timetable") : null,
      actions: edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in days)
            if (slots.any((s) => s.day == d))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: AppTouch.primary + AppSpace.md,
                      child: Text(_dayName(d), style: AppType.label(context)),
                    ),
                    Expanded(
                      child: Wrap(
                        spacing: AppSpace.xs,
                        runSpacing: AppSpace.xxs,
                        children: [
                          for (final s in slots.where((s) => s.day == d))
                            _SlotChip(
                              label: s.isSection ? _groupLabel(page, s.groupNo) : _t('محاضرة', 'Lecture'),
                              time: AppTime.clockRange(s.start, s.end),
                              section: s.isSection,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({required this.label, required this.time, required this.section});

  final String label, time;
  final bool section;

  @override
  Widget build(BuildContext context) {
    final tone = section ? AppBlockTone.sky : AppBlockTone.emerald;
    final col = AppBlockColors.of(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
      decoration: BoxDecoration(color: col.surface, borderRadius: BorderRadius.circular(AppRadius.chip)),
      child: Text(
        '$label · $time',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.meta(context).copyWith(color: appToneStrong(context, tone), fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Exams
// ═════════════════════════════════════════════════════════════════════════════

class CourseExamsCard extends StatelessWidget {
  const CourseExamsCard({super.key, required this.exams, required this.staff, this.onOpen});

  final CoursePageExams? exams;
  final bool staff;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = exams;
    final open = onOpen == null
        ? const <Widget>[]
        : [AppButton(label: _t('الامتحانات', 'Exams'), onPressed: onOpen, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)];
    if (e == null || (e.total == 0 && e.lastResult == null)) {
      return AppSectionCard(
        title: _t('الامتحانات', 'Exams'),
        actions: open,
        child: AppEmpty(
          icon: Icons.quiz_rounded,
          tone: AppBlockTone.gold,
          title: _t('لا امتحانات بعد', 'No exams yet'),
          message: staff ? _t('أنشئ امتحانًا أو كويزًا للكورس.', 'Create an exam or a quiz for the course.') : _t('تظهر امتحاناتك القادمة هنا.', 'Your upcoming exams appear here.'),
          actionLabel: staff && onOpen != null ? _t('امتحان جديد', 'New exam') : null,
          onAction: staff ? onOpen : null,
        ),
      );
    }
    final rows = <Widget>[
      for (final x in e.upcoming)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
          child: Row(
            children: [
              const _Tile(icon: Icons.quiz_rounded, tone: AppBlockTone.gold),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(x.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                    if (x.start != null)
                      Text(AppTime.dateTime(x.start!), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
                  ],
                ),
              ),
            ],
          ),
        ),
      if (e.upcoming.isEmpty) _Note(icon: Icons.event_available_rounded, text: _t('لا امتحانات قادمة.', 'No upcoming exams.')),
      if (staff && (e.toGrade ?? 0) > 0)
        _Note(
          icon: Icons.grading_rounded,
          color: c.danger,
          text: countText(e.toGrade!, ar1: 'إجابة واحدة بانتظار التصحيح', ar2: 'إجابتان بانتظار التصحيح', arFew: '{n} إجابات بانتظار التصحيح', arMany: '{n} إجابة بانتظار التصحيح',
              en1: '1 answer waiting to be graded', en: '{n} answers waiting to be graded'),
        ),
      if (!staff && e.lastResult != null)
        _Note(
          icon: Icons.grade_rounded,
          color: e.lastResult!.passed == false ? c.danger : c.primary,
          text: _t(
            'آخر نتيجة: ${e.lastResult!.name} · ${_score(e.lastResult!)}',
            'Last result: ${e.lastResult!.name} · ${_score(e.lastResult!)}',
          ),
        ),
    ];
    return AppSectionCard(
      title: _t('الامتحانات', 'Exams'),
      subtitle: e.upcomingCount > 0
          ? countText(e.upcomingCount, ar1: 'امتحان قادم واحد', ar2: 'امتحانان قادمان', arFew: '{n} امتحانات قادمة', arMany: '{n} امتحانًا قادمًا', en1: '1 upcoming exam', en: '{n} upcoming exams')
          : null,
      actions: open,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  static String _score(CourseExamResult r) {
    String n(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);
    if (r.marks != null && r.total != null) return '${n(r.marks!)}/${n(r.total!)}';
    if (r.percentage != null) return '${n(r.percentage!)}%';
    return '—';
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Course rules
// ═════════════════════════════════════════════════════════════════════════════

class CourseRulesCard extends StatelessWidget {
  const CourseRulesCard({super.key, required this.rules, required this.staff, this.onEdit});

  final CourseRules rules;
  final bool staff;
  final VoidCallback? onEdit;

  /// The grade parts' colours, in order (the theme's own tones).
  static const _tones = [AppBlockTone.emerald, AppBlockTone.sky, AppBlockTone.gold, AppBlockTone.peach];

  static const int shownItems = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = rules;
    final edit = staff && onEdit != null
        ? [AppButton(label: r.isEmpty ? _t('إضافة', 'Add') : _t('تعديل', 'Edit'), icon: r.isEmpty ? Icons.add_rounded : null, onPressed: onEdit, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)]
        : const <Widget>[];
    if (r.isEmpty) {
      return AppSectionCard(
        title: _t('قواعد الكورس', 'Course rules'),
        actions: edit,
        child: AppEmpty(
          icon: Icons.gavel_rounded,
          tone: AppBlockTone.peach,
          title: _t('لا قواعد بعد', 'No rules yet'),
          message: staff
              ? _t('أضف قواعد خاصة بهذا الكورس: حد الغياب، توزيع الدرجات، التسليم المتأخر، أو أي قاعدة تكتبها.',
                  'Add rules for this course: an absence limit, the grade breakdown, late work, or any rule you write.')
              : _t('يضيف المحاضر قواعد الكورس هنا.', 'The teacher adds the course rules here.'),
          actionLabel: staff && onEdit != null ? _t('إضافة قاعدة', 'Add a rule') : null,
          onAction: staff ? onEdit : null,
        ),
      );
    }
    final blocks = <Widget>[
      if (r.absenceLimit != null)
        _RuleBlock(
          icon: Icons.event_busy_rounded,
          title: _t('حد الغياب: ${r.absenceLimit}', 'Absence limit: ${r.absenceLimit}'),
          child: r.myAbsences == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CourseMeter(value: r.absenceLimit! == 0 ? 1 : r.myAbsences! / r.absenceLimit!, color: r.over ? c.danger : c.primary),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      r.over
                          ? _t('تجاوزت الحد: ${r.myAbsences} من ${r.absenceLimit}', 'Over the limit: ${r.myAbsences} of ${r.absenceLimit}')
                          : _t('غبت ${r.myAbsences} من ${r.absenceLimit}', 'You missed ${r.myAbsences} of ${r.absenceLimit}'),
                      style: AppType.meta(context).copyWith(color: r.over ? c.danger : c.textLight),
                    ),
                  ],
                ),
        ),
      if (r.grades.isNotEmpty)
        _RuleBlock(
          icon: Icons.donut_small_rounded,
          title: _t('توزيع الدرجات', 'Grade breakdown'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: SizedBox(
                  height: AppSpace.xs,
                  child: Row(children: [
                    for (final (i, g) in r.grades.indexed)
                      if (g.weight > 0) Expanded(flex: g.weight, child: ColoredBox(color: appToneStrong(context, _tones[i % _tones.length]))),
                  ]),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.xxs,
                children: [
                  for (final (i, g) in r.grades.indexed)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: AppSpace.xs,
                        height: AppSpace.xs,
                        decoration: BoxDecoration(color: appToneStrong(context, _tones[i % _tones.length]), borderRadius: BorderRadius.circular(AppRadius.pill)),
                      ),
                      const SizedBox(width: AppSpace.xxs),
                      Flexible(
                        child: Text('${g.label} ${g.weight}%', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                      ),
                    ]),
                ],
              ),
            ],
          ),
        ),
      if (r.latePolicy != null)
        _RuleBlock(
          icon: Icons.schedule_rounded,
          title: _t('التسليم المتأخر', 'Late work'),
          child: Text(r.latePolicy!, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
        ),
      if (r.items.isNotEmpty)
        _RuleBlock(
          icon: Icons.rule_rounded,
          title: _t('قواعد المحاضر', "The teacher's rules"),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, it) in r.items.take(shownItems).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xxs),
                  child: Text('${i + 1}. ${it.text}', maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
                ),
              if (r.items.length > shownItems)
                Text(_t('و${r.items.length - shownItems} أخرى', '+${r.items.length - shownItems} more'), style: AppType.meta(context).copyWith(color: c.primary)),
            ],
          ),
        ),
    ];
    return AppSectionCard(
      title: _t('قواعد الكورس', 'Course rules'),
      actions: edit,
      child: LayoutBuilder(
        builder: (context, box) {
          final cols = box.maxWidth >= 640 ? 2 : 1;
          if (cols == 1) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, b) in blocks.indexed) ...[if (i > 0) const SizedBox(height: AppSpace.sm), b],
            ]);
          }
          final half = (box.maxWidth - AppSpace.sm) / 2;
          return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [for (final b in blocks) SizedBox(width: half, child: b)]);
        },
      ),
    );
  }
}

class _RuleBlock extends StatelessWidget {
  const _RuleBlock({required this.icon, required this.title, this.child});

  final IconData icon;
  final String title;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: c.background, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(icon, size: AppIconSize.md, color: c.primary),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context))),
          ]),
          if (child != null) ...[const SizedBox(height: AppSpace.xs), child!],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Attendance · Team · Reviews · After this course
// ═════════════════════════════════════════════════════════════════════════════

class CourseAttendanceCard extends StatelessWidget {
  const CourseAttendanceCard({super.key, required this.attendance, required this.staff, this.onOpen});

  final CoursePageAttendance? attendance;
  final bool staff;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = attendance;
    final rate = staff ? a?.rate : a?.myRate;
    final open = onOpen == null ? const <Widget>[] : [AppButton(label: _t('فتح', 'Open'), onPressed: onOpen, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)];
    if (rate == null) {
      return AppSectionCard(
        title: _t('الحضور', 'Attendance'),
        actions: open,
        child: _Note(icon: Icons.how_to_reg_rounded, text: _t('لا حضور مسجّل بعد.', 'No attendance recorded yet.')),
      );
    }
    final warn = staff ? (a?.atRisk ?? 0) > 0 : (a?.limit != null && (a?.absences ?? 0) > a!.limit!);
    return AppSectionCard(
      title: _t('الحضور', 'Attendance'),
      actions: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${rate.round()}%', style: AppType.figure(context).copyWith(color: c.primary)),
          const SizedBox(height: AppSpace.xxs),
          CourseMeter(value: rate / 100),
          const SizedBox(height: AppSpace.xs),
          Text(
            staff
                ? ((a?.atRisk ?? 0) > 0
                    ? countText(a!.atRisk!, ar1: 'طالب واحد قريب من حد الغياب', ar2: 'طالبان قريبان من حد الغياب', arFew: '{n} طلاب قريبون من حد الغياب', arMany: '{n} طالبًا قريبًا من حد الغياب',
                        en1: '1 student near the absence limit', en: '{n} students near the absence limit')
                    : _t('متوسط حضور الكورس', "The course's attendance rate"))
                : _t('حضرت ${a?.attended ?? 0} من ${a?.expected ?? 0}', 'You attended ${a?.attended ?? 0} of ${a?.expected ?? 0}'),
            style: AppType.meta(context).copyWith(color: warn ? c.danger : c.textLight),
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.person, required this.role});

  final CoursePerson person;
  final String role;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = person.imageUrl ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        CircleAvatar(
          radius: AppIconSize.md,
          backgroundColor: c.lightPrimary,
          foregroundImage: url.isNotEmpty ? NetworkImage(url) : null,
          child: Icon(Icons.person_rounded, size: AppIconSize.md, color: c.primary),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(person.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
            Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
          ]),
        ),
      ]),
    );
  }
}

class CourseTeamCard extends StatelessWidget {
  const CourseTeamCard({super.key, required this.page, required this.staff, this.onOpen});

  final CoursePage page;
  final bool staff;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = page.team;
    final ar = AppConfig.lang == 'ar';
    String taOf(CoursePerson p) {
      final gs = page.sections.groups.where((g) => g.ta?.id == p.id).map((g) => g.labelFor(ar)).toList();
      return gs.isEmpty ? _t('مساعد تدريس', 'Teaching assistant') : '${_t('مساعد تدريس', 'Teaching assistant')} · ${gs.join('، ')}';
    }

    final people = <Widget>[
      if (t.instructor != null) _Person(person: t.instructor!, role: _t('المحاضر', 'Instructor')),
      if (staff) for (final a in t.assistants.take(4)) _Person(person: a, role: taOf(a)),
      if (!staff && t.myTa != null)
        _Person(person: t.myTa!, role: '${_t('معيد سكشنك', 'Your section’s assistant')} · ${_groupLabel(page, page.sections.myGroup)}'),
    ];
    return AppSectionCard(
      title: _t('الفريق', 'Team'),
      actions: onOpen == null ? const [] : [AppButton(label: _t('فتح', 'Open'), onPressed: onOpen, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)],
      child: people.isEmpty
          ? _Note(icon: Icons.groups_rounded, text: _t('المحاضر فقط حتى الآن.', 'Only the teacher so far.'))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: people),
    );
  }
}

class CourseReviewsCard extends StatelessWidget {
  const CourseReviewsCard({super.key, required this.personal, this.onOpen});

  final CoursePagePersonal personal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = personal;
    final open = onOpen == null ? const <Widget>[] : [AppButton(label: _t('الكل', 'All'), onPressed: onOpen, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)];
    if (p.reviews == 0 || p.rating == null) {
      return AppSectionCard(
        title: _t('التقييمات', 'Reviews'),
        actions: open,
        child: _Note(icon: Icons.reviews_rounded, text: _t('لا تقييمات بعد.', 'No reviews yet.')),
      );
    }
    final peak = p.distribution.fold<int>(0, (m, v) => v > m ? v : m);
    return AppSectionCard(
      title: _t('التقييمات', 'Reviews'),
      actions: open,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Text(p.rating!.toStringAsFixed(1), style: AppType.figure(context).copyWith(color: c.accent2)),
            Text(
              countText(p.reviews, ar1: 'تقييم واحد', ar2: 'تقييمان', arFew: '{n} تقييمات', arMany: '{n} تقييمًا', en1: '1 review', en: '{n} reviews'),
              style: AppType.meta(context).copyWith(color: c.textLight),
            ),
          ]),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(children: [
              for (final (i, n) in p.distribution.take(5).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppBorder.focus),
                  child: Row(children: [
                    SizedBox(width: AppSpace.lg, child: Text('${5 - i}★', style: AppType.meta(context).copyWith(color: c.textLight))),
                    Expanded(child: CourseMeter(value: peak == 0 ? 0 : n / peak, color: c.accent2)),
                    SizedBox(
                      width: AppSpace.xl,
                      child: Text('$n', textAlign: TextAlign.end, style: AppType.meta(context).copyWith(color: c.textLight)),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class CoursePathCard extends StatelessWidget {
  const CoursePathCard({super.key, required this.path, required this.staff, this.onOpen, this.onEdit});

  final List<CoursePathStep> path;
  final bool staff;
  final ValueChanged<int>? onOpen;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final edit = staff && onEdit != null
        ? [AppButton(label: _t('تعديل', 'Edit'), onPressed: onEdit, variant: AppButtonVariant.ghost, size: AppButtonSize.sm)]
        : const <Widget>[];
    return AppSectionCard(
      title: _t('بعد هذا الكورس', 'After this course'),
      actions: edit,
      child: path.isEmpty
          ? _Note(
              icon: Icons.route_rounded,
              text: staff ? _t('اقترح الكورس التالي لطلابك.', 'Suggest the next course to your students.') : _t('لم يقترح المحاضر كورسًا تاليًا بعد.', 'The teacher has not suggested a next course yet.'),
            )
          : Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (i, s) in path.indexed) ...[
                  if (i > 0) Icon(Icons.arrow_forward_rounded, size: AppIconSize.sm, color: c.textLight),
                  ActionChip(
                    avatar: CircleAvatar(
                      backgroundColor: c.primary,
                      child: Text('${i + 1}', style: AppType.meta(context).copyWith(color: Theme.of(context).colorScheme.onPrimary, fontWeight: FontWeight.w700)),
                    ),
                    label: Text(s.name(ar), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                    onPressed: onOpen == null ? null : () => onOpen!(s.id),
                  ),
                ],
              ],
            ),
    );
  }
}
