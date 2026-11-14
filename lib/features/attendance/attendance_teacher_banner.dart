/// features/attendance/attendance_teacher_banner.dart
///
/// Global bar above EVERY screen while the teacher's attendance is running (same idea as the
/// offline flag): shows the rotating code, the present counter and the time left, so the teacher
/// can move around the app while students read the code. Tap = reopen the sheet; ✕ = close.
///
/// main.dart:  builder: (_, child) => AttendanceTeacherBanner(navigatorKey: navigatorKey, child: …)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_live_screen.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_controller.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

String _mmss(Duration d) =>
    '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

// NOTE: this bar lives ABOVE the Navigator (no Overlay): never use Tooltip / IconButton(tooltip:),
// PopupMenu, DropdownButton or showDialog(context) from here.
class AttendanceTeacherBanner extends StatelessWidget {
  const AttendanceTeacherBanner({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Same slot for [child] whether the bar is visible or not, so the Navigator is never rebuilt.
    return ListenableBuilder(
      listenable: TeacherAttendanceController.instance,
      builder: (ctx, _) {
        final t = TeacherAttendanceController.instance;
        final show = t.window != null && (t.isOpen || t.isClosing);
        return Column(children: [
          if (show) _bar(ctx, t),
          Expanded(child: child),
        ]);
      },
    );
  }

  Widget _bar(BuildContext context, TeacherAttendanceController t) {
    final closing = t.isClosing;
    final c = context.colors;
    // Warm Editorial: the deep emerald while it runs (attendance open = the success colour), the deep warning while
    // it closes; flat, no gradient.
    final color = closing ? c.heroEnd(c.warning) : c.heroEnd(c.success);
    final ink = c.onHero;
    final code = t.code?.code ?? '';
    return Directionality(
      textDirection: Directionality.of(context),
      child: Material(
        color: color,
        child: SafeArea(
          bottom: false,
          child: InkWell(
            onTap: () {
              final nav = navigatorKey.currentState?.overlay?.context; // a context BELOW the Navigator
              if (nav != null) openAttendanceLive(nav);
            },
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
              child: Row(children: [
                Icon(closing ? Icons.lock_clock_rounded : Icons.sensors_rounded, color: ink, size: AppIconSize.md),
                AppSpace.gapXs,
                if (!closing && t.usesCode && code.length == 6)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
                      decoration: BoxDecoration(
                          color: c.heroGlass,
                          borderRadius: AppRadius.chipAll,
                          border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline)),
                      child: Text('${code.substring(0, 3)} ${code.substring(3)}',
                          style: AppType.figure(context).copyWith(color: ink, letterSpacing: AppSpace.xxs / 2)),
                    ),
                  )
                else
                  Flexible(
                    child: Text(
                      closing ? attT('att_t_closing', args: {'n': '${t.closingLeft}'}) : attT('att_t_running'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (t.lessonTitle != null && t.lessonTitle!.isNotEmpty) ...[
                  AppSpace.gapXs,
                  Flexible(
                    child: Text(t.lessonTitle!,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
                  ),
                ],
                const Spacer(),
                Icon(Icons.people_alt_rounded, color: ink, size: AppIconSize.sm),
                const SizedBox(width: AppSpace.xxs),
                Text('${t.code?.presentCount ?? 0}', style: AppType.figure(context).copyWith(color: ink)),
                if (!closing) ...[
                  AppSpace.gapXs,
                  Icon(Icons.timer_outlined, color: ink, size: AppIconSize.sm),
                  const SizedBox(width: AppSpace.xxs),
                  Text(_mmss(t.registrationLeft), style: AppType.figure(context).copyWith(color: ink)),
                ],
                if (!closing)
                  // No tooltip here (no Overlay above the Navigator): the label goes to screen readers only.
                  Semantics(
                    button: true,
                    label: MaterialLocalizations.of(context).closeButtonTooltip,
                    excludeSemantics: true,
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        t.close();
                      },
                      icon: Icon(Icons.stop_circle_rounded, color: ink, size: AppIconSize.lg),
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
