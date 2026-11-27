// lib/features/parent/pa_child_pages.dart — one child's pages (Pa2Kids `screen=detail` and `screen=course`, phase 4).
//
//   ParentChildPage        the child: avatar · grade · name · linked since · View the report (hot) · Book a subject ·
//                          four figures (courses · progress · attendance · exams); then "Overview" (the status, one
//                          plain sentence, this week's active days / missed / homework due), the consent notice, the
//                          courses (each opens its page), Reports / Games / Quran / Nahw, the sign-in code of a
//                          child this parent created (pa_child_code.dart), and the panel "as your child sees it"
//                          (D-290, EntityNavigator)
//   ParentChildCoursePage  one course of the child: progress · attendance · average · exams, the big ring with one
//                          sentence, the exam list, Message the teacher
// Data: what the dashboard already holds (ParentLinkProvider: /parent/children + /profile, the overview's pulse);
// a page opened without the dashboard loads the children itself. The switcher on top moves to another child.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/features/analytics/analytics_ui.dart' show anInsightSentence;
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart' show DlCourseBlock, DlProfile;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'pa_kit.dart';
import 'parent_children_page.dart' show ParentChildActions, paGiveConsent;
import 'parent_consent.dart';
import 'parent_link_providers.dart';
import 'parent_message_teacher.dart';
import 'parent_overview.dart';
import 'parent_pulse.dart';
import 'parent_pulse_widgets.dart';
import 'parent_reports_page.dart';
import 'parent_widgets.dart';

/// Extra blocks other parts of the parent area add to a child's page (the sign-in code of a child this parent
/// created, the "book a subject" action); set once by the dashboard.
typedef PaChildExtra = Widget? Function(BuildContext context, Map<String, dynamic> child);

class ParentChildPage extends StatefulWidget {
  const ParentChildPage({super.key, required this.childId});

  final int childId;

  /// The child's sign-in code block (pa_child_code.dart sets it; null = none).
  static PaChildExtra? codeBlock;

  /// "Book a subject" for this child (the parent's booking entry sets it; null = not offered).
  static void Function(BuildContext context, int childId)? onBook;

  @override
  State<ParentChildPage> createState() => _ParentChildPageState();
}

class _ParentChildPageState extends State<ParentChildPage> {
  ParentLinkProvider? _own;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.read<ParentLinkProvider>().ensureLoaded();
      } on ProviderNotFoundException {
        setState(() => _own = ParentLinkProvider()..loadAll());
      }
    });
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  ParentChildOverview? _overview(BuildContext context, int id) {
    try {
      for (final c in context.watch<ParentOverviewProvider>().data?.children ?? const <ParentChildOverview>[]) {
        if (c.id == id) return c;
      }
    } on ProviderNotFoundException {
      // opened on its own: no pulse
    }
    return null;
  }

  void _switch(int? id) {
    if (id == null || id == widget.childId) return;
    PaKids.maybeOf(context, listen: false)?.select(id);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => paRole(_carry(context, ParentChildPage(childId: id))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final own = _own;
    if (own != null) return ChangeNotifierProvider.value(value: own, child: Builder(builder: _build));
    return _build(context);
  }

  Widget _build(BuildContext context) {
    ParentLinkProvider? p;
    try {
      p = context.watch<ParentLinkProvider>();
    } on ProviderNotFoundException {
      p = null;
    }
    Map<String, dynamic>? row;
    for (final c in p?.children ?? const <Map<String, dynamic>>[]) {
      if ((c['id'] as num?)?.toInt() == widget.childId) row = c;
    }
    final name = '${row?['name'] ?? ''}';
    final body = row == null
        ? (p == null || p.isLoading || !p.loadedOnce
            ? const AppListSkeleton(items: 3)
            : AppEmpty(icon: Icons.person_off_outlined, title: 'pl_no_children'.tr))
        : _page(context, row, p!.profiles[widget.childId], p.profiles.containsKey(widget.childId), _overview(context, widget.childId));
    return BasePage(
      appBar: ScreenAppBar(title: name.split(' ').first),
      child: Column(children: [
        PaSwitcherBand(showAll: false, selectedId: widget.childId, onSelect: _switch),
        Expanded(child: body),
      ]),
    );
  }

  Widget _page(BuildContext context, Map<String, dynamic> row, DlProfile? pr, bool loaded, ParentChildOverview? ov) {
    final id = widget.childId;
    final name = '${row['name']}';
    final grade = '${row['grade_name'] ?? ''}';
    final linked = parentUtc(row['linked_at']);
    final pulse = ov?.pulse;
    final wide = paWide(context);
    final needsConsent = row['needs_consent'] == true;
    String pct(double? v) => v == null ? '—' : appDigits('${v.round()}%');

    final hero = AppHero(
      kicker: grade.isEmpty ? null : grade,
      title: name,
      subtitle: linked == null ? null : paFmt('pa_linked_since', {'date': AppTime.date(linked)}),
      leading: PaKidAvatar(id: id, name: name, size: AppHero.leadingSize(wide)),
      actions: [
        AppButton.hot(
          key: const ValueKey('pa.child.report'),
          label: 'pa_view_report'.tr,
          expand: !wide,
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ParentChildReportScreen(studentId: id, studentName: name))),
        ),
        if (ParentChildPage.onBook != null)
          AppButton.secondary(
            key: const ValueKey('pa.child.book'),
            label: 'pa_book_subject'.tr,
            expand: !wide,
            onPressed: () => ParentChildPage.onBook!(context, id),
          ),
      ],
      stats: [
        AppHeroStat(label: 'pa_courses'.tr, value: pr == null ? (ov == null ? '—' : appDigits('${ov.courses}')) : appDigits('${pr.courses.length}')),
        AppHeroStat(label: 'pa_progress'.tr, value: pct(pr?.progress)),
        AppHeroStat(label: 'pa_attendance'.tr, value: pct(pr?.attendance ?? ov?.attendancePct30d?.toDouble())),
        AppHeroStat(label: 'pa_exams'.tr, value: pct(pr?.examAvg)),
      ],
    );

    final overview = pulse == null && pr == null
        ? null
        : AppCard(
            title: 'pa_overview'.tr,
            action: pulse == null
                ? null
                : AppStatusBadge(label: pulseStatusLabel(pulse.status), tone: pulseStatusTone(pulse.status)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                pulse != null && pulse.insights.isNotEmpty
                    ? parentInsightText(pulse.insights.first, name)
                    : anInsightSentence(pr?.progress, pr?.attendance, pr?.examAvg, mine: false),
                style: AppType.body(context),
              ),
              if (pulse != null) ...[
                const SizedBox(height: AppSpace.sm),
                Row(children: [
                  Expanded(child: AppStatTile(icon: Icons.local_fire_department_rounded, label: 'pa_active_days'.tr, value: appDigits('${pulse.week.activeDays}'))),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AppStatTile(icon: Icons.event_busy_rounded, label: 'pa_missed'.tr, value: appDigits('${pulse.week.missed + pulse.week.homeworkMissing}'))),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AppStatTile(icon: Icons.assignment_outlined, label: 'pa_hw_soon'.tr, value: appDigits('${pulse.week.homeworkDueSoon}'))),
                ]),
              ],
            ]),
          );

    final courses = pr == null || pr.courses.isEmpty
        ? (loaded ? null : const AppListSkeleton(items: 2, padding: EdgeInsets.zero))
        : AppCard(
            title: 'pa_courses_title'.tr,
            action: Text('pa_courses_hint'.tr, style: AppType.meta(context)),
            child: PaStack(gap: AppSpace.sm, children: [
              for (final b in pr.courses)
                AppTile(
                  key: ValueKey('pa.child.course.${b.courseId}'),
                  icon: Icons.menu_book_rounded,
                  title: b.title,
                  subtitle: [
                    if (b.attendance != null) paFmt('pa_att_n', {'n': pct(b.attendance)}),
                    if (b.examAvg != null) paFmt('pa_exams_n', {'n': pct(b.examAvg)}),
                  ].join(paT('، ', ', ')),
                  trailing: AppProgressRing(value: (b.progress ?? 0) / 100, size: AppDashSize.ringSm),
                  onTap: () => paPush<void>(
                    context,
                    ParentChildCoursePage(childId: id, childName: name, course: b, subject: _subject(pulse, b.courseId), teachers: pulse?.teachers ?? const []),
                  ),
                ),
            ]),
          );

    final code = ParentChildPage.codeBlock?.call(context, row);
    return PaHeroPage(
      onRefresh: () async {
        try {
          await context.read<ParentLinkProvider>().loadAll();
        } on ProviderNotFoundException {
          // nothing to reload
        }
      },
      hero: hero,
      body: PaColumns(
        start: [
          if (needsConsent) ConsentNeededNotice(onGive: () => paGiveConsent(context, id, name, grade)),
          ?overview,
          ?courses,
        ],
        end: [
          AppCard(
            title: 'pa_more_about'.tr.replaceAll('{name}', name.split(' ').first),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ParentChildActions(id: id, name: name, needsConsent: needsConsent),
              const SizedBox(height: AppSpace.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.ghost(
                  key: ValueKey('pa.child.panel.$id'),
                  label: 'pa_as_child_sees'.tr,
                  icon: Icons.open_in_new_rounded,
                  onPressed: () => EntityNavigator.open(context, EntityRef(EntityKind.student, id, label: name)),
                ),
              ),
            ]),
          ),
          ?code,
        ],
      ),
    );
  }

  PulseSubject? _subject(ParentPulse? p, int courseId) {
    for (final s in p?.subjects ?? const <PulseSubject>[]) {
      if (s.courseId == courseId) return s;
    }
    return null;
  }
}

Widget _carry(BuildContext context, Widget page) {
  final providers = <ChangeNotifierProvider>[];
  void add<P extends ChangeNotifier>() {
    try {
      providers.add(ChangeNotifierProvider<P>.value(value: context.read<P>()));
    } on ProviderNotFoundException {
      // not there
    }
  }

  add<PaKids>();
  add<ParentLinkProvider>();
  add<ParentOverviewProvider>();
  return providers.isEmpty ? page : MultiProvider(providers: providers, child: page);
}

/// One course of the child (Pa2Kids `screen=course`).
class ParentChildCoursePage extends StatelessWidget {
  const ParentChildCoursePage({
    super.key,
    required this.childId,
    required this.childName,
    required this.course,
    this.subject,
    this.teachers = const [],
  });

  final int childId;
  final String childName;
  final DlCourseBlock course;

  /// The overview's line for this course (tone, teacher), when the server sent one.
  final PulseSubject? subject;
  final List<PulseTeacher> teachers;

  @override
  Widget build(BuildContext context) {
    final b = course;
    final first = childName.split(' ').first;
    final wide = paWide(context);
    final teacher = subject?.teacher;
    String pct(double? v) => v == null ? '—' : appDigits('${v.round()}%');
    final progress = b.progress ?? 0;
    final tone = progress >= 75 ? AppTone.success : (progress >= 50 ? AppTone.warning : AppTone.danger);
    final canMessage = parentMessageTeacherOn && teachers.any((t) => t.courseId == b.courseId);
    final hero = AppHero(
      kicker: paFmt('pa_course_of', {'name': childName}),
      title: b.title,
      subtitle: teacher == null ? null : paFmt('pa_with_teacher', {'name': teacher.name}),
      leading: PaKidAvatar(id: childId, name: childName, size: AppHero.leadingSize(wide)),
      actions: [
        if (canMessage)
          AppButton.secondary(
            label: 'pa_message_teacher'.tr,
            icon: Icons.chat_bubble_outline_rounded,
            expand: !wide,
            onPressed: () => showParentMessageTeacher(context, childId: childId, childName: childName, teachers: teachers, courseId: b.courseId),
          ),
      ],
      stats: [
        AppHeroStat(label: 'pa_progress'.tr, value: pct(b.progress)),
        AppHeroStat(label: 'pa_attendance'.tr, value: pct(b.attendance)),
        AppHeroStat(label: 'pa_exam_avg'.tr, value: pct(b.examAvg)),
        AppHeroStat(
          label: 'pa_sessions_attended'.tr,
          value: b.held == 0 ? '—' : paFmt('pa_n_of_m', {'n': appDigits('${b.attended}'), 'm': appDigits('${b.held}')}),
        ),
      ],
    );
    return BasePage(
      appBar: ScreenAppBar(title: 'pa_course'.tr),
      child: PaHeroPage(
        hero: hero,
        body: PaColumns(
          start: [
            AppCard(
              variant: AppCardVariant.tint,
              tone: context.colors.kit.ok,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AppProgressRing(value: progress / 100, size: AppDashSize.ring * 1.6, stroke: AppSpace.xs, semanticLabel: pct(b.progress)),
                const SizedBox(height: AppSpace.sm),
                AppStatusBadge(label: 'pa_course_tone_${tone.name}'.tr, tone: tone),
                const SizedBox(height: AppSpace.xs),
                Text(paFmt('pa_course_line', {'name': first, 'p': pct(b.progress), 'course': b.title}), style: AppType.section(context)),
              ]),
            ),
          ],
          end: [
            AppCard(
              title: 'pa_exams'.tr,
              child: b.exams.isEmpty
                  ? Text('pl_ov_no_marks'.tr, style: AppType.body(context))
                  : PaStack(gap: AppSpace.sm, children: [
                      for (final e in b.exams)
                        AppTile(
                          icon: e.passed == false ? Icons.close_rounded : Icons.check_rounded,
                          tone: e.passed == false ? context.colors.kit.live : context.colors.kit.ok,
                          title: e.name,
                          trailing: AppStatusBadge(label: pct(e.best), tone: e.passed == false ? AppTone.danger : AppTone.success),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

