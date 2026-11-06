// lib/design/master_detail/student_detail.dart — what is particular to a student's detail (D-290, phase 4).
//
//   StudentOverviewCard      "2 of 6 courses completed", the states as one bar, last activity, average, money
//   StudentCourseRow         a row of the student's courses (a link to the course) that unfolds into the facts of the
//                            enrollment and its full timeline, with the manager's actions on that course
//   StudentInCourseBlock     the same history on a course opened from a student: that student stays the context
//   EntityFactGrid           label + value pairs, in two columns where they fit
//   StudentManage            what a manager (`can.manage`) gets; features/admin/admin_student_manage.dart implements
//                            it and is a part of its own, so a learner's or a teacher's app never downloads it
//
// The rest of the detail is the shared one (entity_detail_view.dart): the header, the sub-list around these rows, the
// payments and the subscription history.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/entities/entities_api.dart';
import 'package:flutter_education_app/core/entities/entity_models.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show loadDeferred;

import '../../features/admin/admin_student_manage.dart' deferred as student_manage;
import '../app_kit.dart';
import 'entity_chip.dart';
import 'entity_detail_view.dart';
import 'entity_specs.dart';
import 'entity_timeline.dart';

// ── Management ───────────────────────────────────────────────────────────────

/// What a manager can do on the student on screen. Notifies when its own data changed.
abstract class StudentManage extends ChangeNotifier {
  /// The quick actions under the header.
  List<EntityPanelAction> headerActions(BuildContext context);

  /// The action at the top of the courses section (Enrol).
  Widget? coursesAction(BuildContext context);

  /// What can be done on one of the student's courses.
  List<EntityPanelAction> courseActions(BuildContext context, EnrollmentRow row);

  /// The sections under the student's own data: subscription, account, devices, controls.
  List<Widget> sections(BuildContext context);
}

/// Loads the management part and makes a [StudentManage] for [student]. [onChanged] runs after a change on the server,
/// [onDeleted] once the student is gone.
Future<StudentManage> loadStudentManage(EntityRef student,
    {required VoidCallback onChanged, required VoidCallback onDeleted}) async {
  await loadDeferred('student_manage', student_manage.loadLibrary);
  return student_manage.createStudentManage(student, onChanged: onChanged, onDeleted: onDeleted);
}

// ── Facts ────────────────────────────────────────────────────────────────────

/// One label + value of an [EntityFactGrid].
class EntityFact {
  const EntityFact(this.label, this.value);

  final String label;
  final String value;
}

/// Label + value pairs, two columns where they fit.
class EntityFactGrid extends StatelessWidget {
  const EntityFactGrid(this.facts, {super.key});

  /// Below two of these a pair takes the whole row.
  static const double _column = 140;

  final List<EntityFact> facts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final two = box.maxWidth >= _column * 2 + AppSpace.sm;
        final width = two ? (box.maxWidth - AppSpace.sm) / 2 : box.maxWidth;
        return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          for (final f in facts)
            SizedBox(
              width: width,
              child: MergeSemantics(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(f.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  Text(f.value, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                ]),
              ),
            ),
        ]);
      });
}

// ── Overview ─────────────────────────────────────────────────────────────────

/// "1 of 6 courses completed".
String studentCompletionText(int completed, int total) {
  if (total == 0) return 'md_p4_no_courses'.tr;
  return countText(total,
          ar1: '{c} من دورة واحدة مكتملة',
          ar2: '{c} من دورتين مكتملة',
          arFew: '{c} من {n} دورات مكتملة',
          arMany: '{c} من {n} دورة مكتملة',
          en1: '{c} of 1 course completed',
          en: '{c} of {n} courses completed')
      .replaceAll('{c}', '$completed');
}

/// The student's courses at a glance: one sentence, the states as one bar with their counts, then the other figures.
class StudentOverviewCard extends StatelessWidget {
  const StudentOverviewCard({super.key, required this.summary});

  final EntitySummary summary;

  /// The bar's segments, in reading order.
  static const List<String> _states = ['completed', 'in_progress', 'withdrawn', 'expired', 'pending'];

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final total = (s.stat('enrolled') ?? 0).toInt();
    final byState = {for (final k in _states) k: (s.stat(k) ?? 0).toInt()};
    final stats = {for (final t in statSpecsOf(s)) t.key: t};
    final facts = [
      for (final k in const ['avg_progress', 'last_activity_at', 'paid'])
        if (stats[k] != null) EntityFact(stats[k]!.label, stats[k]!.value),
    ];
    final present = [
      for (final k in _states)
        if (byState[k]! > 0) k,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            header: true,
            child: Text(studentCompletionText(byState['completed']!, total), style: AppType.section(context)),
          ),
          if (present.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            ExcludeSemantics(child: _StateBar(counts: [for (final k in present) (k, byState[k]!)])),
            const SizedBox(height: AppSpace.sm),
            Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xxs, children: [
              for (final k in present) _StateCount(state: k, count: byState[k]!),
            ]),
          ],
          if (facts.isNotEmpty) ...[
            Divider(height: AppSpace.lg, thickness: AppBorder.hairline, color: context.colors.divider),
            EntityFactGrid(facts),
          ],
        ]),
      ),
    );
  }
}

class _StateBar extends StatelessWidget {
  const _StateBar({required this.counts});

  final List<(String, int)> counts;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: AppRadius.chipAll,
        child: SizedBox(
          height: AppSpace.xs,
          child: Row(children: [
            for (var i = 0; i < counts.length; i++) ...[
              if (i > 0) const SizedBox(width: AppBorder.strong),
              Expanded(
                flex: counts[i].$2,
                child: ColoredBox(color: appToneColor(context, mdStateTone(counts[i].$1))),
              ),
            ],
          ]),
        ),
      );
}

class _StateCount extends StatelessWidget {
  const _StateCount({required this.state, required this.count});

  final String state;
  final int count;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: AppSpace.xs,
          height: AppSpace.xs,
          decoration: BoxDecoration(color: appToneColor(context, mdStateTone(state)), shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpace.xxs),
        Text('$count', style: AppType.label(context).copyWith(color: context.colors.textDark)),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(mdStateLabel(state), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
      ]);
}

// ── A course of the student ──────────────────────────────────────────────────

/// "2 exams · average 71%".
String studentExamsText(EntityExams ex) {
  final head = countText(ex.count,
      ar1: 'اختبار واحد', ar2: 'اختباران', arFew: '{n} اختبارات', arMany: '{n} اختباراً', en1: '1 exam', en: '{n} exams');
  return ex.avgPercentage == null ? head : '$head · ${mdText('md_p4_exam_avg', {'p': mdPercent(ex.avgPercentage)})}';
}

/// What the student said about the course and how their exams went, as small pills (null: nothing to show).
Widget? _signals(EntityEnrollment e) {
  final ex = e.exams;
  final pills = <Widget>[
    if (e.favorited)
      AppStatusBadge(label: 'md_p4_liked'.tr, tone: AppTone.danger, icon: Icons.favorite_rounded, dense: true),
    if (e.rating != null)
      AppStatusBadge(
          label: mdText('md_tl_rated', {'v': '${e.rating!.value}'}),
          tone: AppTone.warning,
          icon: Icons.star_rounded,
          dense: true),
    if (ex != null && ex.count > 0)
      AppStatusBadge(label: studentExamsText(ex), tone: AppTone.neutral, icon: Icons.quiz_outlined, dense: true),
  ];
  return pills.isEmpty ? null : Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: pills);
}

/// The facts of an enrollment, opened under its row.
List<EntityFact> enrollmentFacts(EntityEnrollment e) {
  String when(DateTime? t) => t == null ? 'md_p4_not_yet'.tr : mdDate(t);
  final ex = e.exams;
  return [
    EntityFact('md_p4_fact_enrolled'.tr, mdDate(e.enrolledAt)),
    EntityFact('md_p4_fact_expected_end'.tr, mdDate(e.expectedEndAt)),
    EntityFact('md_p4_fact_first_visit'.tr, when(e.firstActivityAt)),
    EntityFact('md_p4_fact_last_activity'.tr, when(e.lastActivityAt)),
    if (e.state != 'withdrawn') EntityFact('md_p4_fact_completed'.tr, when(e.completedAt)),
    EntityFact('md_p4_fact_liked'.tr, e.favorited ? 'md_p4_yes'.tr : 'md_p4_no'.tr),
    EntityFact('md_p4_fact_rating'.tr,
        e.rating == null ? 'md_p4_not_rated'.tr : mdText('md_tl_rated', {'v': '${e.rating!.value}'})),
    if (ex != null && ex.count > 0)
      EntityFact('md_p4_fact_exams'.tr,
          '${studentExamsText(ex)} · ${mdText('md_p4_exam_passed', {'n': '${ex.passed}', 'total': '${ex.count}'})}'),
  ];
}

/// The enrollment's facts, the student's review and their timeline; then what a manager can do on it.
class _CourseHistory extends StatelessWidget {
  const _CourseHistory({
    required this.studentId,
    required this.courseId,
    required this.enrollment,
    this.actions = const [],
  });

  final int studentId;
  final int courseId;
  final EntityEnrollment enrollment;
  final List<EntityPanelAction> actions;

  @override
  Widget build(BuildContext context) {
    final review = enrollment.rating?.review;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EntityFactGrid(enrollmentFacts(enrollment)),
      if (review != null) ...[
        const SizedBox(height: AppSpace.sm),
        Text('“$review”', maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
      ],
      const SizedBox(height: AppSpace.md),
      Semantics(header: true, child: Text('md_p4_full_history'.tr, style: AppType.label(context))),
      const SizedBox(height: AppSpace.xs),
      EntityTimelineList(studentId: studentId, courseId: courseId, pageSize: 10),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final a in actions)
            a.danger
                ? AppButton.danger(
                    key: a.key,
                    dangerOutline: true,
                    label: a.label,
                    icon: a.icon,
                    size: AppButtonSize.sm,
                    onPressed: a.onPressed)
                : AppButton.tonal(key: a.key, label: a.label, icon: a.icon, size: AppButtonSize.sm, onPressed: a.onPressed),
        ]),
      ],
    ]);
  }
}

/// The History button of an enrollment: unfolds or folds what is under it.
class _HistoryToggle extends StatelessWidget {
  const _HistoryToggle({required this.buttonKey, required this.open, required this.onPressed});

  final Key buttonKey;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Semantics(
          expanded: open,
          child: AppButton.ghost(
            key: buttonKey,
            label: 'md_history'.tr,
            icon: open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: AppButtonSize.sm,
            onPressed: onPressed,
          ),
        ),
      );
}

/// A row of the student's courses: the course (a link), its state, progress and dates, why they left; History unfolds
/// the facts and the timeline in place. A [focused] course (the one the detail was opened from) starts open and
/// scrolls into view.
class StudentCourseRow extends StatefulWidget {
  const StudentCourseRow({
    super.key,
    required this.studentId,
    required this.row,
    this.focused = false,
    this.actions = const [],
  });

  final int studentId;
  final EnrollmentRow row;
  final bool focused;
  final List<EntityPanelAction> actions;

  @override
  State<StudentCourseRow> createState() => _StudentCourseRowState();
}

class _StudentCourseRowState extends State<StudentCourseRow> {
  late bool _open = widget.focused;
  late bool _built = widget.focused; // the timeline is fetched on the first open, then kept

  @override
  void initState() {
    super.initState();
    if (widget.focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            alignment: 0.05, duration: AppMotion.of(context).slow, curve: AppMotion.emphasized);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final e = r.enrollment;
    final sub = [r.course?.teacher?.name, r.course?.category?.name]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      EntityRowFrame(
        ref: r.subject,
        title: r.subject.name.isEmpty ? '#${r.subject.id}' : r.subject.name,
        subtitle: sub,
        highlight: widget.focused,
        trailing: AppStatusBadge(label: mdStateLabel(e.state), tone: mdStateTone(e.state), dense: true),
        body: [
          if (e.state != 'pending') EntityProgress(e.progress),
          ...enrollmentMeta(context, e),
          ?_signals(e),
        ],
      ),
      _HistoryToggle(
        buttonKey: ValueKey('md.student.history.${r.subject.id}'),
        open: _open,
        onPressed: () => setState(() {
          _open = !_open;
          _built = true;
        }),
      ),
      AnimatedSize(
        duration: AppMotion.of(context).base,
        curve: AppMotion.curve,
        alignment: AlignmentDirectional.topCenter,
        child: !_built
            ? const SizedBox(width: double.infinity)
            : Visibility(
                visible: _open,
                maintainState: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.sm),
                  child: _CourseHistory(
                      studentId: widget.studentId, courseId: r.subject.id, enrollment: e, actions: widget.actions),
                ),
              ),
      ),
    ]);
  }
}

/// A course opened from a student: that student stays the context, with their place in this course and their history
/// (nothing for a student who is not in it).
class StudentInCourseBlock extends StatefulWidget {
  const StudentInCourseBlock({super.key, required this.student, required this.courseId});

  final EntityRef student;
  final int courseId;

  @override
  State<StudentInCourseBlock> createState() => _StudentInCourseBlockState();
}

class _StudentInCourseBlockState extends State<StudentInCourseBlock> {
  EnrollmentRow? _row;
  Object? _error;
  bool _loading = true;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await EntitiesApi.instance.studentCourse(widget.student.id, widget.courseId);
      if (mounted) {
        setState(() {
          _row = r;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = _row?.enrollment;
    if (e == null && !_loading && _error == null) return const SizedBox.shrink();
    final student = widget.student;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          EntityLink(
            student,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Row(children: [
                EntityThumb(student),
                AppSpace.gapSm,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(student.name.isEmpty ? '#${student.id}' : student.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                    Text('md_p4_in_this_course'.tr,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                  ]),
                ),
                if (e != null) ...[
                  AppSpace.gapXs,
                  AppStatusBadge(label: mdStateLabel(e.state), tone: mdStateTone(e.state), dense: true),
                ],
              ]),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          if (_error != null)
            AppErrorState(message: entityErrorText(_error), onRetry: _load, compact: true)
          else if (e == null)
            const AppListSkeleton(items: 2, padding: EdgeInsets.zero)
          else ...[
            if (e.state != 'pending') EntityProgress(e.progress),
            for (final w in enrollmentMeta(context, e)) ...[const SizedBox(height: AppSpace.xxs), w],
            _HistoryToggle(
              buttonKey: const ValueKey('md.student.context_history'),
              open: _open,
              onPressed: () => setState(() => _open = !_open),
            ),
            if (_open) _CourseHistory(studentId: student.id, courseId: widget.courseId, enrollment: e),
          ],
        ]),
      ),
    );
  }
}
