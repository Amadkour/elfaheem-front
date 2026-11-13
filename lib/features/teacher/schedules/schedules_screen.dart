// lib/features/teacher/schedules/schedules_screen.dart — a course's weekly appointments (the teacher's course studio).
//
//   header   "Appointments <course>" · Add (the one action)
//   week     the sky block: the seven days in the week's order, a filled day for each that holds an appointment
//            (its start time under it) and the "repeats every week" note — the screen's one memorable element
//   list     one paper card per appointment (day · time · delete), in the week's order
//   empty    "No appointments" with Add; loading: the warm skeleton
//   add      AddScheduleSheet: day chips · start / end wells · Add (a same-day appointment asks first)
//
// TeacherSchedulesView draws all of it from plain values (layout harness, renders); the screen wires the provider.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show ensureContrast;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale, AppReveal;
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse, CourseSchedule;
import 'package:provider/provider.dart';

import '../../../config/app_config.dart' as helpers;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../admin/admin_common.dart' show trp;
import 'schedules_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  TeacherSchedulesScreen
// ══════════════════════════════════════════════════════════════════════════════

class TeacherSchedulesScreen extends StatefulWidget {
  final TeacherCourse course;
  const TeacherSchedulesScreen({super.key, required this.course});
  static void openAddScheduleScreenSheet(BuildContext context,) => showAppSideSheet<void>(
    context, mode: AppSheetMode.side,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<TeacherSchedulesProvider>(),
      child: const AddScheduleSheet(),
    ),
  );
  @override
  State<TeacherSchedulesScreen> createState() =>
      _TeacherSchedulesScreenState();
}

class _TeacherSchedulesScreenState extends State<TeacherSchedulesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context
            .read<TeacherSchedulesProvider>()
            .fetchSchedules(widget.course));
  }

  Future<void> _confirmDelete(CourseSchedule s) async {
    final ok = await showAppDialog<bool>(
      context,
      title: 'appointment-delete'.tr,
      icon: Icons.delete_outline_rounded,
      danger: true,
      body: Text(trp('appointment_delete_confirm', {'day': s.dayLabel, 'time': AppTime.clock(s.startTime)}), style: AppType.body(context)),
      actions: [
        AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context, false)),
        AppButton.danger(label: 'delete'.tr, onPressed: () => Navigator.pop(context, true)),
      ],
    );
    if (ok == true && mounted) {
      context.read<TeacherSchedulesProvider>().removeSchedule(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherSchedulesProvider>();
    void add() => TeacherSchedulesScreen.openAddScheduleScreenSheet(context);
    return BasePage(
      key: const ValueKey('teacher_schedules'),
      useWebCard: true,
      width: AppWidth.content,
      appBar: AppHeader(
        title: '${'appointment'.tr} ${helpers.AppConfig.lang=='ar'?widget.course.titleAr:widget.course.titleEn}',
        actions: [AppIconButton(icon: Icons.add_rounded, tooltip: 'add_schedule'.tr, variant: AppIconButtonVariant.tonal, onPressed: add)],
      ),
      child: SafeArea(
        top: false,
        child: TeacherSchedulesView(
          schedules: provider.schedules,
          loading: provider.isLoading && provider.schedules.isEmpty,
          onAdd: add,
          onDelete: _confirmDelete,
        ),
      ),
    );
  }
}

/// The page's body from plain values.
class TeacherSchedulesView extends StatelessWidget {
  const TeacherSchedulesView({super.key, required this.schedules, this.loading = false, this.onAdd, this.onDelete});

  final List<CourseSchedule> schedules;
  final bool loading;
  final VoidCallback? onAdd;
  final ValueChanged<CourseSchedule>? onDelete;

  /// In the week's order, then by start time.
  static List<CourseSchedule> sorted(List<CourseSchedule> all) => [...all]..sort((a, b) {
        final di = slotDayOrder(a.day).compareTo(slotDayOrder(b.day));
        return di != 0 ? di : a.startTime.compareTo(b.startTime);
      });

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final gutter = AppSpace.gutter(box.maxWidth);
        if (loading) {
          return Padding(
            padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.md),
            child: const AppListSkeleton(items: 4, withAvatar: true, padding: EdgeInsets.zero),
          );
        }
        if (schedules.isEmpty) {
          return AppEmpty(
            icon: Icons.calendar_month_rounded,
            tone: AppBlockTone.sky,
            title: 'no-appointment'.tr,
            message: 'add-weekly-appointment-for-student'.tr,
            actionLabel: onAdd == null ? null : 'add-weekly-appointment'.tr,
            onAction: onAdd,
          );
        }
        final list = sorted(schedules);
        return ListView(
          padding: EdgeInsets.fromLTRB(gutter, AppSpace.md, gutter, AppSpace.xl),
          children: [
            // ONE entrance: the week leads, the list follows it as one piece
            AppReveal(index: 0, group: 'schedules', child: TeacherWeekBlock(schedules: list)),
            const SizedBox(height: AppSpace.lg),
            AppReveal(
              index: 1,
              group: 'schedules',
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpace.xs),
                  _AppointmentCard(schedule: list[i], onDelete: onDelete == null ? null : () => onDelete!(list[i])),
                ],
              ]),
            ),
          ],
        );
      });
}

/// The week at a glance on the sky block: every day in the week's order, filled where an appointment falls (its
/// start under it), then the one line that says the appointments repeat every week.
class TeacherWeekBlock extends StatelessWidget {
  const TeacherWeekBlock({super.key, required this.schedules});
  final List<CourseSchedule> schedules;

  @override
  Widget build(BuildContext context) {
    final byDay = <String, List<CourseSchedule>>{};
    for (final s in schedules) {
      (byDay[s.day.toLowerCase()] ??= []).add(s);
    }
    return AppBlock(
      tone: AppBlockTone.sky,
      child: Builder(builder: (context) {
        final ink = AppBlock.colorsOf(context);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final d in kDayOrder) Expanded(child: _DayCell(day: d, slots: byDay[d] ?? const [])),
          ]),
          const SizedBox(height: AppSpace.md),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.repeat_rounded, size: AppIconSize.sm, color: ink.muted),
            const SizedBox(width: AppSpace.xs),
            Expanded(child: Text('appointment-repeat'.tr, style: AppType.meta(context).copyWith(color: ink.muted, height: 1.45))),
          ]),
        ]);
      }),
    );
  }
}

/// A day's column in the week: its short name, a disc (filled emerald when the day holds an appointment, a faint
/// ring when it is free) and the first start time.
class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.slots});
  final String day;
  final List<CourseSchedule> slots;

  static const double _disc = AppSpace.xl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = AppBlock.colorsOf(context);
    final on = slots.isNotEmpty;
    final full = 'day_$day'.tr;
    final short = helpers.AppConfig.lang == 'ar' || full.length <= 3 ? full : full.substring(0, 3);
    final fill = ensureContrast(c.primary, [c.onHero]); // the emerald that carries white ink
    final label = on ? '$full · ${slots.map((s) => AppTime.clock(s.startTime)).join('، ')}' : full;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(short, maxLines: 1, style: AppType.meta(context).copyWith(color: on ? ink.ink : ink.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
        ),
        const SizedBox(height: AppSpace.xs),
        Container(
          width: _disc,
          height: _disc,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? fill : null,
            border: on ? null : Border.all(color: ink.faint.withValues(alpha: 0.5), width: AppBorder.hairline),
          ),
          child: on
              ? (slots.length > 1
                  ? Text('${slots.length}', style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w600))
                  : Icon(Icons.check_rounded, size: AppIconSize.sm, color: c.onHero))
              : null,
        ),
        const SizedBox(height: AppSpace.xxs),
        SizedBox(
          height: AppIconSize.md,
          child: on
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(AppTime.clock(slots.first.startTime),
                      maxLines: 1, style: AppType.meta(context).copyWith(color: ink.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                )
              : null,
        ),
      ]),
    );
  }
}

/// One weekly appointment: the day on its sky chip, the day's name (editorial), the time, Delete.
class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.schedule, this.onDelete});
  final CourseSchedule schedule;
  final VoidCallback? onDelete;

  static const double _chip = AppTouch.min;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sky = AppBlockColors.of(context, AppBlockTone.sky);
    final day = schedule.dayLabel;
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      child: Row(children: [
        Container(
          width: _chip,
          height: _chip,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(AppSpace.xxs),
          decoration: BoxDecoration(color: sky.surface, borderRadius: AppRadius.controlAll),
          child: Icon(Icons.event_repeat_rounded, size: AppIconSize.md, color: sky.ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(day, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            const SizedBox(height: AppSpace.xxs / 2),
            Row(children: [
              Icon(Icons.schedule_rounded, size: AppIconSize.xs, color: c.textLight),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(
                  '${AppTime.clock(schedule.startTime)} – ${AppTime.clock(schedule.endTime)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row(context).copyWith(color: c.textMedium, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ]),
          ]),
        ),
        if (onDelete != null) AppIconButton(icon: Icons.delete_outline_rounded, tooltip: 'delete'.tr, onPressed: onDelete),
      ]),
    );
  }
}

// ── Add Schedule Sheet ────────────────────────────────────────────────────────

class AddScheduleSheet extends StatefulWidget {
  const AddScheduleSheet({super.key});
  @override
  State<AddScheduleSheet> createState() => _AddScheduleSheetState();
}

class _AddScheduleSheetState extends State<AddScheduleSheet> {
  static const _days = [
    ('monday',    'day_monday'),
    ('tuesday',   'day_tuesday'),
    ('wednesday', 'day_wednesday'),
    ('thursday',  'day_thursday'),
    ('friday',    'day_friday'),
    ('saturday',  'day_saturday'),
    ('sunday',    'day_sunday'),
  ];
  String    _day   = 'monday';
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end   = const TimeOfDay(hour: 12, minute: 0);

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _valid =>
      _end.hour * 60 + _end.minute > _start.hour * 60 + _start.minute;

  Future<void> _pick(bool isStart) async {
    final p = await showTimePicker(
        context: context, initialTime: isStart ? _start : _end);
    if (p == null || !mounted) return;
    if(mounted) setState(() => isStart ? _start = p : _end = p);
  }

  Future<void> _submit() async {
    if (!_valid) return;
    final existing =
        context.read<TeacherSchedulesProvider>().schedules;
    final conflict = existing.any((s) => s.day == _day);
    if (conflict) {
      final ok = await showAppDialog<bool>(
        context,
        title: 'duplicate-schedule'.tr,
        icon: Icons.event_busy_rounded,
        body: Text('same-day-schedule-exists'.tr, style: AppType.body(context)),
        actions: [
          AppButton.secondary(label: 'cancel'.tr, onPressed: () => Navigator.pop(context, false)),
          AppButton.primary(label: 'add'.tr, onPressed: () => Navigator.pop(context, true)),
        ],
      );
      if (ok != true || !mounted) return;
    }

    final r = await context
        .read<TeacherSchedulesProvider>()
        .addSchedule(
        day: _day,
        startTime: _fmt(_start),
        endTime: _fmt(_end));
    if (mounted) {
      Navigator.pop(context);
      // the notice tells which way it went (it was drawn as an error even when the appointment was added)
      showAppNotice(r != null ? 'appointment-added-successfully'.tr : 'something-went-wrong'.tr, error: r == null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        context.watch<TeacherSchedulesProvider>().isLoading;
    return Directionality(
      textDirection: helpers.pageDirection,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('add-weekly-appointment'.tr, style: AppType.headline(context))),
            const SizedBox(height: AppSpace.lg),

            // Day chips
            AppFieldLabel('today'.tr),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final (v, lKey) in _days)
                  AppChoiceChip(label: lKey.tr, selected: _day == v, onTap: () { if (mounted) setState(() => _day = v); }),
              ],
            ),
            const SizedBox(height: AppSpace.lg),

            // Time pickers
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: _TimePicker(
                      label: 'start-time'.tr,
                      time: _start,
                      onTap: () => _pick(true))),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                  child: _TimePicker(
                      label: 'end-time'.tr,
                      time: _end,
                      onTap: () => _pick(false),
                      hasError: !_valid)),
            ]),
            if (!_valid) ...[
              const SizedBox(height: AppSpace.xs),
              Text('end-time-must-be-after-start-time'.tr,
                  style: AppType.meta(context).copyWith(color: context.colors.danger, fontWeight: FontWeight.w500)),
            ],
            const SizedBox(height: AppSpace.lg),
            AppButton.primary(
                label: 'add-appointment'.tr,
                expand: true,
                busy: loading,
                onPressed: _valid ? _submit : null),
          ],
        ),
      ),
    );
  }
}

/// A time well (the field language: label above, the warm input well, the danger hairline on an error).
class _TimePicker extends StatelessWidget {
  final String    label;
  final TimeOfDay time;
  final VoidCallback onTap;
  final bool      hasError;
  const _TimePicker(
      {required this.label,
        required this.time,
        required this.onTap,
        this.hasError = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = AppTime.clockMinutes(time.hour * 60 + time.minute);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppFieldLabel(label),
      Semantics(
        button: true,
        label: '$label $value',
        excludeSemantics: true,
        child: AppPressScale(
          child: Material(
            color: c.inputBg,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.controlAll,
              side: BorderSide(color: hasError ? c.danger : c.divider, width: hasError ? AppBorder.strong : AppBorder.hairline),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.min),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  child: Row(children: [
                    Icon(Icons.access_time_rounded, size: AppIconSize.md, color: hasError ? c.danger : c.textLight),
                    const SizedBox(width: AppSpace.xs),
                    Flexible(
                      child: Text(value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appFieldTextStyle(context).copyWith(fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
