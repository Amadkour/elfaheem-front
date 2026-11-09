library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/teacher/home/teacher_models.dart' show TeacherCourse, CourseSchedule;
import 'package:provider/provider.dart';
import '../../../config/app_config.dart' as Helpers;
import '../../../config/theme/theme_config_provider.dart';
import '../../../utils/widget/base_page.dart';
import '../../../utils/widget/primary_button.dart';
import '../../admin/admin_common.dart';
import 'schedules_provider.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppHeader, AppTime;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_tokens.dart' show AppWidth;
// ══════════════════════════════════════════════════════════════════════════════
//  TeacherSchedulesScreen
// ══════════════════════════════════════════════════════════════════════════════

class TeacherSchedulesScreen extends StatefulWidget {
  final TeacherCourse course;
  const TeacherSchedulesScreen({super.key, required this.course});
  static void openAddScheduleScreenSheet(BuildContext context,) => showAppSideSheet<void>(
    context,
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



  @override
  Widget build(BuildContext context) {

    final provider = context.watch<TeacherSchedulesProvider>();
    return BasePage(
      key: const ValueKey('teacher_schedules'),
      useWebCard: true,
      width: AppWidth.content,
      appBar: AppHeader(
        title: '${'appointment'.tr} ${Helpers.AppConfig.lang=='ar'?widget.course.titleAr:widget.course.titleEn}',
        actions: [_AddBtn(onTap:()=> TeacherSchedulesScreen.openAddScheduleScreenSheet(context))],
      ),
      child:
      SafeArea(top: false, child: Column(children: [
        // Info banner
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: context.colors.primary.withValues(alpha: 0.15))),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child:  Icon(Icons.repeat_rounded,
                    color: context.colors.primary, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'appointment-repeat'.tr,
                  style: context.colors.caption.copyWith(
                      color: context.colors.primary, height: 1.5),
                ),
              ),
            ]),
          ),
        ),

        Expanded(
          child: provider.isLoading && provider.schedules.isEmpty
              ?  Center(
              child: AppLoadingIndicator())
              : provider.schedules.isEmpty
              ? _ManageEmptyState(onAdd: ()=>TeacherSchedulesScreen.openAddScheduleScreenSheet(context))
              : _ManageList(schedules: provider.schedules),
        ),
      ])),
    );
  }
}

class _ManageList extends StatelessWidget {
  final List<CourseSchedule> schedules;
  const _ManageList({required this.schedules});

  List<CourseSchedule> get _sorted => [...schedules]..sort((a, b) {
    final di =
    slotDayOrder(a.day).compareTo(slotDayOrder(b.day));
    if (di != 0) return di;
    return a.startTime.compareTo(b.startTime);
  });

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    physics: const BouncingScrollPhysics(),
    itemCount: _sorted.length,
    separatorBuilder: (_, _) => const SizedBox(height: 10),
    itemBuilder: (ctx, i) => _ManageCard(schedule: _sorted[i]),
  );
}

class _ManageCard extends StatelessWidget {
  final CourseSchedule schedule;
  const _ManageCard({required this.schedule});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
        color: context.colors.cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: context.colors.cardShadow),
    child: Row(children: [
      // Day badge
      Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
            gradient: context.colors.primaryGradient,
            borderRadius: BorderRadius.circular(14)),
        child: Center(
          child: Text(
            slotDayShort(schedule.day),
            style: TextStyle(
                color: context.colors.onHero,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: AppFonts.display),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(slotDayLabel(schedule.day),
                  style: context.colors.h3.copyWith(fontSize: 15)),
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.access_time_filled_rounded,
                    size: 14, color: context.colors.primary),
                const SizedBox(width: 5),
                Text(
                    '${AppTime.clock(schedule.startTime)}  —  ${AppTime.clock(schedule.endTime)}',
                    style: context.colors.label.copyWith(
                        color: context.colors.textDark, fontSize: 13)),
              ]),
            ]),
      ),
      // Delete
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _confirmDelete(context, schedule),
        child: Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: context.colors.danger.withValues(alpha: 0.2))),
            child:  Icon(Icons.delete_outline_rounded,
                color: context.colors.danger, size: 18, semanticLabel: 'delete'.tr)),
      ),
    ]),
  );

  Future<void> _confirmDelete(
      BuildContext ctx, CourseSchedule s) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (BuildContext context) => Directionality(
          textDirection: Helpers.pageDirection,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title:  Text('appointment-delete'.tr,
                style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w700)),
            content: Text(
                trp('appointment_delete_confirm', {'day': slotDayLabel(s.day), 'time': AppTime.clock(s.startTime)}),

                style: TextStyle(fontFamily: AppFonts.display)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child:  Text('cancel'.tr,
                      style: TextStyle(
                          fontFamily: AppFonts.display,
                          color: context.colors.textMedium))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.danger,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () => Navigator.pop(ctx, true),
                child:  Text('delete'.tr,
                    style: TextStyle(
                        fontFamily: AppFonts.display,
                        color: context.colors.onHero,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          )),
    );
    if (ok == true && ctx.mounted) {
      ctx.read<TeacherSchedulesProvider>().removeSchedule(s.id);
    }
  }
}

class _ManageEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _ManageEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) =>
      Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                shape: BoxShape.circle,
                boxShadow: context.colors.primaryShadow),
            child: Icon(Icons.calendar_month_rounded,
                color: context.colors.onHero, size: 44)),
        const SizedBox(height: 20),
        Text('no-appointment'.tr, style: context.colors.h3),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'add-weekly-appointment-for-student'.tr,
            style: context.colors.caption,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
                gradient: context.colors.primaryGradient,
                borderRadius: BorderRadius.circular(26),
                boxShadow: context.colors.primaryShadow),
            child:  Text('add-weekly-appointment'.tr,
                style: TextStyle(
                    color: context.colors.onHero,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.display,
                    fontSize: 14)),
          ),
        ),
      ]));
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
      final ok = await showDialog<bool>(
          context: context,
          builder: (_) => Directionality(
              textDirection: Helpers.pageDirection,
              child: AlertDialog(
                title:  Text('duplicate-schedule'.tr,
                    style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontWeight: FontWeight.w700)),
                content:  Text(
                    'same-day-schedule-exists'.tr,
                    style: TextStyle(fontFamily: AppFonts.display)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child:  Text('cancel'.tr,
                          style: TextStyle(
                              fontFamily: AppFonts.display,
                              color: context.colors.textMedium))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: context.colors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10))),
                    onPressed: () => Navigator.pop(context, true),
                    child:  Text('add'.tr,
                        style: TextStyle(
                            fontFamily: AppFonts.display,
                            color: context.colors.onHero,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              )));
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
      showAppNotice(r != null ? 'appointment-added-successfully'.tr : 'something-went-wrong'.tr, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        context.watch<TeacherSchedulesProvider>().isLoading;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('add-weekly-appointment'.tr, style: context.colors.h2),
            const SizedBox(height: 20),

            // Day chips
            Text('today'.tr,
                style: context.colors.label.copyWith(
                    color: context.colors.textDark,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final (v, lKey) = _days[i];
                  final l = lKey.tr;
                  final sel = _day == v;
                  return GestureDetector(
                    onTap: () { if(mounted) setState(() => _day = v);},
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient:
                        sel ? context.colors.primaryGradient : null,
                        color:
                        sel ? null : context.colors.background,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: sel
                                ? Colors.transparent
                                : context.colors.divider),
                        boxShadow:
                        sel ? context.colors.primaryShadow : null,
                      ),
                      child: Text(l,
                          style: context.colors.label.copyWith(
                              color: sel
                                  ? context.colors.onHero
                                  : context.colors.textMedium,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Time pickers
            Row(children: [
              Expanded(
                  child: _TimePicker(
                      label: 'start-time'.tr,
                      time: _start,
                      onTap: () => _pick(true))),
              const SizedBox(width: 12),
              Expanded(
                  child: _TimePicker(
                      label: 'end-time'.tr,
                      time: _end,
                      onTap: () => _pick(false),
                      hasError: !_valid)),
            ]),
            if (!_valid) ...[
              const SizedBox(height: 6),
              Text('end-time-must-be-after-start-time'.tr,
                  style: context.colors.caption
                      .copyWith(color: context.colors.danger)),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
                label: 'add-appointment'.tr,
                isLoading: loading,
                onPressed: _valid ? _submit : null),
          ],
        ),
      ),
    );
  }
}

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
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: context.colors.label.copyWith(
                color: context.colors.textDark,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius:
                BorderRadius.circular(context.colors.radiusMedium),
                border: Border.all(
                    color: hasError
                        ? context.colors.danger
                        : context.colors.divider,
                    width: hasError ? 1.5 : 1)),
            child: Row(children: [
              Icon(Icons.access_time_rounded,
                  size: 18,
                  color:
                  hasError ? context.colors.danger : context.colors.primary),
              const SizedBox(width: 8),
              Text(
                  AppTime.clockMinutes(time.hour * 60 + time.minute),
                  style: context.colors.h3.copyWith(fontSize: 18)),
            ]),
          ),
        ),
      ]);
}

class _AddBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _AddBtn({required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'add_schedule'.tr,
    onPressed: onTap,
    icon: Icon(Icons.add_rounded, color: context.colors.primary, size: 24),
  );
}
