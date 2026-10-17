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

import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'teacher_attendance_controller.dart';

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
    final color = closing ? const Color(0xFFB45309) : const Color(0xFF15803D);
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
              final id = t.sessionId;
              if (nav != null && id != null) showTeacherAttendanceSheet(nav, id);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(children: [
                Icon(closing ? Icons.lock_clock_rounded : Icons.sensors_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                if (!closing && t.usesCode && code.length == 6)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                    child: Text('${code.substring(0, 3)} ${code.substring(3)}',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
                  )
                else
                  Flexible(
                    child: Text(
                      closing ? attT('att_t_closing', args: {'n': '${t.closingLeft}'}) : attT('att_t_running'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'tajawal', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                const Spacer(),
                const Icon(Icons.people_alt_rounded, color: Colors.white, size: 17),
                const SizedBox(width: 4),
                Text('${t.code?.presentCount ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15)),
                if (!closing && t.usesCode) ...[
                  const SizedBox(width: 10),
                  Text('${t.secondsLeft}s',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.85))),
                ],
                if (!closing)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: attT('att_t_close'),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      t.close();
                    },
                    icon: const Icon(Icons.stop_circle_rounded, color: Colors.white, size: 24),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
