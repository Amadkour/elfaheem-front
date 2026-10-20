/// features/attendance/attendance_live_screen.dart
///
/// Full-screen view of the teacher's running attendance, made to be read from the back of the
/// room: huge rotating code, how long registration stays open, the live present counter.
///   • Minimize  → back to the app; the global bar (attendance_teacher_banner.dart) keeps the code
///                 and the countdown visible on every screen, tap it to come back here.
///   • Close registration → closes now; the server still accepts late relays for the grace time.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'attendance_strings.dart';
import 'teacher_attendance_controller.dart';

const kAttendanceLiveRoute = '/attendance-live';

/// [context] must be BELOW the Navigator (any screen, or the Navigator's overlay context).
Future<void> openAttendanceLive(BuildContext context) => openAttendanceLiveOn(Navigator.of(context));

Future<void> openAttendanceLiveOn(NavigatorState nav) {
  // Already on top? Do nothing.
  var onTop = false;
  nav.popUntil((r) {
    onTop = r.settings.name == kAttendanceLiveRoute;
    return true; // never pops: just peeks at the top route
  });
  if (onTop) return Future.value();
  return nav.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: kAttendanceLiveRoute),
    fullscreenDialog: true,
    builder: (_) => const AttendanceLiveScreen(),
  ));
}

String _mmss(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

class AttendanceLiveScreen extends StatefulWidget {
  const AttendanceLiveScreen({super.key});
  @override
  State<AttendanceLiveScreen> createState() => _AttendanceLiveScreenState();
}

class _AttendanceLiveScreenState extends State<AttendanceLiveScreen> {
  @override
  void initState() {
    super.initState();
    try {
      WakelockPlus.enable(); // keep the screen on while students read the code
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _confirmClose(TeacherAttendanceController t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(attT('att_t_close_confirm'), style: const TextStyle(fontFamily: 'tajawal')),
        content: Text(attT('att_t_close_confirm_body', args: {'n': '${t.graceSeconds}'}),
            style: const TextStyle(fontFamily: 'tajawal')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(attT('att_cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.colors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(attT('att_t_close'))),
        ],
      ),
    );
    if (ok == true) await t.close();
  }

  @override
  Widget build(BuildContext context) {
    final t = TeacherAttendanceController.instance;
    return Scaffold(
      // Projector mode: a deep shade of the app's OWN primary colour (follows the theme).
      backgroundColor: Color.alphaBlend(Colors.black.withValues(alpha: 0.82), context.colors.primary),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: t,
          builder: (_, _) {
            final closing = t.isClosing;
            final ended = !closing && (t.window == null || t.closed || !(t.code?.isOpen ?? true));
            final rot = (t.window?.rotationSeconds ?? 45).toDouble();
            final code = t.code?.code ?? '------';
            final grouped = code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
            final left = t.registrationLeft;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    tooltip: attT('att_t_minimize'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(CupertinoIcons.fullscreen_exit, color: Colors.white),
                  ),
                  const Spacer(),
                  _Pill(icon: CupertinoIcons.person_3_fill, text: '${t.code?.presentCount ?? 0}'),
                ]),
                const Spacer(),
                if (ended)
                  _Status(icon: CupertinoIcons.lock_fill, text: attT('att_t_closed'))
                else if (closing)
                  _Status(
                      icon: Icons.lock_clock,
                      text: attT('att_t_closing', args: {'n': '${t.closingLeft}'}))
                else ...[
                  if (t.usesCode) ...[
                    SizedBox(
                      width: 300,
                      height: 300,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox(
                          width: 300,
                          height: 300,
                          child: CircularProgressIndicator(
                            value: (t.secondsLeft / rot).clamp(0.0, 1.0),
                            strokeWidth: 8,
                            color: Color.lerp(context.colors.success, Colors.white, 0.25),
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        FittedBox(
                          child: Padding(
                            padding: const EdgeInsets.all(40),
                            child: Text(grouped,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 64,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 6)),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Text(attT('att_t_next_code', args: {'n': '${t.secondsLeft}'}),
                        style: const TextStyle(fontFamily: 'tajawal', color: Colors.white60)),
                  ] else
                    const Icon(CupertinoIcons.person_3_fill, size: 120, color: Colors.white70),
                  const SizedBox(height: 28),
                  Text(attT('att_t_reg_left'),
                      style: const TextStyle(fontFamily: 'tajawal', color: Colors.white70, fontSize: 14)),
                  Text(_mmss(left),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                ],
                const Spacer(),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(CupertinoIcons.fullscreen_exit),
                      label: Text(attT('att_t_minimize'), style: const TextStyle(fontFamily: 'tajawal')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: (ended || closing)
                        ? FilledButton(
                            style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            onPressed: closing ? null : () {
                              t.clear();
                              Navigator.of(context).maybePop();
                            },
                            child: Text(attT('att_done'), style: const TextStyle(fontFamily: 'tajawal')),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                                backgroundColor: context.colors.danger,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                            onPressed: t.loading ? null : () => _confirmClose(t),
                            icon: const Icon(CupertinoIcons.lock),
                            label: Text(attT('att_t_close'),
                                style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
                          ),
                  ),
                ]),
              ]),
            );
          },
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        ]),
      );
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, size: 90, color: Colors.white70),
        const SizedBox(height: 16),
        Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ]);
}
