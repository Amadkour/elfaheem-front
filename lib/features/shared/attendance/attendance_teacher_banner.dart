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

import 'attendance_strings.dart';
import 'attendance_live_screen.dart';
import 'teacher_attendance_controller.dart';

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
              if (nav != null) openAttendanceLive(nav);
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
                if (t.lessonTitle != null && t.lessonTitle!.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(t.lessonTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: 'tajawal', fontSize: 12, color: Colors.white.withValues(alpha: 0.9))),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.people_alt_rounded, color: Colors.white, size: 17),
                const SizedBox(width: 4),
                Text('${t.code?.presentCount ?? 0}',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15)),
                if (!closing) ...[
                  const SizedBox(width: 10),
                  const Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                  const SizedBox(width: 3),
                  Text(_mmss(t.registrationLeft),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                ],
                if (!closing)
                  IconButton(
                    visualDensity: VisualDensity.compact,
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
