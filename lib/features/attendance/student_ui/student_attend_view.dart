// lib/features/attendance/student_ui/student_attend_view.dart
//
// The student's "حضوري" page (Stu1Learn screen=attend), plain values: the learn hero ("<subject>، <grade>" + حضوري),
// the mint card while attendance is open ("الحين، <lesson> مع <teacher>", "الحضور مفتوح، يقفل بعد ٨ دقايق", the white
// "سجّل حضوري"), and "سجل حضوري" with the student's OWN rows only (حضرت / متأخر / غبت) and the "حضرت ٨٧٪" pill.
//
// Privacy (DESIGN_SYSTEM §1.2, O-6): no classmate, no count, no "through a classmate", no system words.
// Motion (live / attendance area): M8 on the open card's dot only.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/attendance/analysis/teacher/attendance_model.dart' show FullAttendance;

/// `'key'.tr` with `{name}` placeholders filled.
String sbAttTr(String key, [Map<String, String> args = const {}]) {
  var s = key.tr;
  args.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

/// How a past class went for the student.
enum StudentAttendStatus { present, late, absent }

/// One row of "سجل حضوري".
class StudentAttendRow {
  const StudentAttendRow({required this.lesson, required this.status, this.at});

  final String lesson;
  final DateTime? at;
  final StudentAttendStatus status;
}

/// The open attendance of the class happening now.
class StudentAttendOpen {
  const StudentAttendOpen({this.lesson, this.teacherName, this.minutesLeft});

  final String? lesson;
  final String? teacherName;

  /// Whole minutes until it closes; null when not known.
  final int? minutesLeft;
}

/// The share of past classes attended, 0..100 (late counts as attended); null with no rows.
int? studentAttendPercent(List<StudentAttendRow> rows) {
  if (rows.isEmpty) return null;
  final ok = rows.where((r) => r.status != StudentAttendStatus.absent).length;
  return (ok * 100 / rows.length).round();
}

/// A check-in this many minutes after the class started reads "متأخر".
const int kStudentLateAfterMinutes = 10;

/// The student's rows from `course_attendance/me`, newest first.
List<StudentAttendRow> studentAttendRows(List<FullAttendance> list, {DateTime? now}) {
  final at = (now ?? DateTime.now()).toUtc();
  final rows = <(DateTime?, StudentAttendRow)>[];
  for (final f in list) {
    final when = f.sessions.scheduledAt?.toUtc();
    if (when != null && when.isAfter(at)) continue; // a class still to come is not a row yet
    final me = f.attendance.isEmpty ? null : f.attendance.first;
    final present = me?.isPresent ?? false;
    final late = present &&
        when != null &&
        me?.checkIn != null &&
        me!.checkIn!.toUtc().difference(when).inMinutes > kStudentLateAfterMinutes;
    rows.add((
      when,
      StudentAttendRow(
        lesson: f.sessions.name,
        at: when,
        status: !present ? StudentAttendStatus.absent : (late ? StudentAttendStatus.late : StudentAttendStatus.present),
      ),
    ));
  }
  rows.sort((a, b) => (b.$1 ?? DateTime(0)).compareTo(a.$1 ?? DateTime(0)));
  return [for (final r in rows) r.$2];
}

class StudentAttendView extends StatelessWidget {
  const StudentAttendView({
    super.key,
    required this.rows,
    this.kicker,
    this.open,
    this.onCheckIn,
    this.checkedIn = false,
    this.loading = false,
    this.error,
    this.onRetry,
    this.onBack,
    this.onRefresh,
  });

  /// "الرياضيات، ثاني ثانوي".
  final String? kicker;
  final StudentAttendOpen? open;
  final VoidCallback? onCheckIn;

  /// The student already checked in to the open class.
  final bool checkedIn;
  final List<StudentAttendRow> rows;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => AppAreaScope(
        area: AppArea.learn,
        child: LayoutBuilder(builder: (context, box) {
          final gutter = AppSpace.gutter(box.maxWidth);
          final body = Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.reading.max),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (open != null) ...[
                      StudentAttendOpenCard(open: open!, onCheckIn: onCheckIn, checkedIn: checkedIn),
                      const SizedBox(height: AppSpace.md),
                    ],
                    _RecordCard(rows: rows, loading: loading, error: error, onRetry: onRetry),
                    const SizedBox(height: AppSpace.xl),
                  ],
                ),
              ),
            ),
          );
          final list = ListView(
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              AppHeroOverlap(
                hero: AppHero(
                  kicker: kicker,
                  title: 'sb_att_title'.tr,
                  wipe: false,
                  leading: onBack == null ? null : AppBackButton(onHero: true, onPressed: onBack),
                  overlap: open != null,
                ),
                body: body,
              ),
            ],
          );
          return onRefresh == null ? list : AppRefresh(onRefresh: onRefresh!, child: list);
        }),
      );
}

/// The mint card while attendance is open. Public: tests pump it alone.
class StudentAttendOpenCard extends StatelessWidget {
  const StudentAttendOpenCard({super.key, required this.open, this.onCheckIn, this.checkedIn = false});

  final StudentAttendOpen open;
  final VoidCallback? onCheckIn;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ok = c.kit.accent(AppAccent.mint);
    final lesson = (open.lesson ?? '').trim();
    final teacher = (open.teacherName ?? '').trim();
    final now = lesson.isEmpty
        ? 'sb_att_now'.tr
        : teacher.isEmpty
            ? sbAttTr('sb_att_now_lesson', {'lesson': lesson})
            : sbAttTr('sb_att_now_lesson_with', {'lesson': lesson, 'teacher': teacher});
    final left = open.minutesLeft;
    final title = checkedIn
        ? 'sb_att_done_title'.tr
        : left == null || left < 1
            ? 'sb_att_open'.tr
            : sbAttTr('sb_att_open_closes', {'n': appDigits('$left')});
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.block),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [ok.color, ok.ink],
        ),
        boxShadow: AppShadow.button(context, ok.ink),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBreathe(
                color: c.onHero,
                active: !checkedIn,
                child: Container(
                  width: AppIconSize.md,
                  height: AppIconSize.md,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.onHero,
                    border: Border.all(color: c.heroGlassBorder, width: AppBorder.focus),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(now,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: c.onHeroMuted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(title, style: AppType.headline(context).copyWith(color: c.onHero)),
          if (!checkedIn && onCheckIn != null) ...[
            const SizedBox(height: AppSpace.md),
            AppJelly(
              wide: true,
              child: Material(
                color: c.cardBg,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onCheckIn,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppTouch.primary),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, color: ok.ink, size: AppIconSize.lg),
                        const SizedBox(width: AppSpace.xs),
                        Flexible(
                          child: Text('sb_att_check_in'.tr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.section(context).copyWith(color: ok.ink)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.rows, required this.loading, this.error, this.onRetry});

  final List<StudentAttendRow> rows;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final pct = studentAttendPercent(rows);
    final Widget child;
    if (loading && rows.isEmpty) {
      child = const AppListSkeleton(items: 4);
    } else if (error != null && rows.isEmpty) {
      child = AppErrorState(message: error, onRetry: onRetry);
    } else if (rows.isEmpty) {
      child = AppEmpty(icon: Icons.event_available_rounded, title: 'sb_att_empty'.tr, message: 'sb_att_empty_msg'.tr);
    } else {
      child = Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) Divider(height: AppBorder.hairline, color: context.colors.kit.line),
            _Row(row: r),
          ],
        ],
      );
    }
    return AppCard(
      title: 'sb_att_record'.tr,
      action: pct == null
          ? null
          : AppStatusBadge(label: sbAttTr('sb_att_percent', {'n': appDigits('$pct')}), tone: AppTone.success),
      child: child,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.row});

  final StudentAttendRow row;

  @override
  Widget build(BuildContext context) {
    final at = row.at;
    final (String label, AppTone tone) = switch (row.status) {
      StudentAttendStatus.present => ('sb_att_present'.tr, AppTone.success),
      StudentAttendStatus.late => ('sb_att_late'.tr, AppTone.warning),
      StudentAttendStatus.absent => ('sb_att_absent'.tr, AppTone.danger),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTouch.primary),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(
          children: [
            if (at != null) ...[
              Text(AppTime.date(at, pattern: 'EEEE d MMM'), style: AppType.bodyStrong(context)),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Text(row.lesson,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(context)),
            ),
            const SizedBox(width: AppSpace.sm),
            AppStatusBadge(label: label, tone: tone),
          ],
        ),
      ),
    );
  }
}
