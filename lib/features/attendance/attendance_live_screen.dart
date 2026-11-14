/// features/attendance/attendance_live_screen.dart
///
/// Full-screen view of the teacher's running attendance, made to be read from the back of the
/// room: huge rotating code, how long registration stays open, the live present counter.
///   • Minimize  → back to the app; the global bar (attendance_teacher_banner.dart) keeps the code
///                 and the countdown visible on every screen, tap it to come back here.
///   • Close registration → closes now; the server still accepts late relays for the grace time.
///
/// Warm Editorial (D-610 – D-629): the projector surface stays the deep shade of the primary (the on-hero roles), the
/// one memorable thing is the code in its countdown ring, the present count rolls ([AppOdometer]), and the sizes come
/// from the space the screen has, so a 320 px phone and a projector both read it.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_education_app/features/help/help_info_button.dart' show HelpInfoButton;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_controller.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer;

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
        title: Text(attT('att_t_close_confirm')),
        content: Text(attT('att_t_close_confirm_body', args: {'n': '${t.graceSeconds}'})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(attT('att_cancel'))),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.colors.dangerBase),
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
      backgroundColor: Color.alphaBlend(context.colors.heroShade.withValues(alpha: 0.82), context.colors.primary),
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

            final c = context.colors;
            final onHero = c.onHero;
            final bigButton = OutlinedButton.styleFrom(
                foregroundColor: onHero,
                minimumSize: const Size.fromHeight(AppTouch.primary),
                side: BorderSide(color: c.heroGlassBorder, width: AppBorder.hairline),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll));

            return Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.lg),
              child: Column(children: [
                Row(children: [
                  IconButton(
                    tooltip: attT('att_t_minimize'),
                    constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(CupertinoIcons.fullscreen_exit, color: onHero),
                  ),
                  const Spacer(),
                  const HelpInfoButton(pageId: 'attendance.checkin'),
                  AppSpace.gapXs,
                  _Pill(icon: CupertinoIcons.person_3_fill, value: t.code?.presentCount ?? 0),
                ]),
                Expanded(
                  child: LayoutBuilder(builder: (context, box) {
                    // The ring takes what the screen gives it: the narrow side, never more than ~half the height.
                    final ring = (box.maxWidth < box.maxHeight * 0.55 ? box.maxWidth : box.maxHeight * 0.55)
                        .clamp(AppSpace.xxxl * 2, AppSpace.xxxl * 6)
                        .toDouble();
                    return Center(
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          if (ended)
                            _Status(icon: CupertinoIcons.lock_fill, text: attT('att_t_closed'), size: ring / 3)
                          else if (closing)
                            _Status(
                                icon: Icons.lock_clock_rounded,
                                text: attT('att_t_closing', args: {'n': '${t.closingLeft}'}),
                                size: ring / 3)
                          else ...[
                            if (t.usesCode) ...[
                              SizedBox.square(
                                dimension: ring,
                                child: Stack(alignment: Alignment.center, children: [
                                  SizedBox.square(
                                    dimension: ring,
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(end: (t.secondsLeft / rot).clamp(0.0, 1.0)),
                                      duration: AppMotion.of(context).slow,
                                      curve: AppMotion.curve,
                                      builder: (_, v, _) => CircularProgressIndicator(
                                        value: v,
                                        strokeWidth: AppSpace.xs,
                                        strokeCap: StrokeCap.round,
                                        color: Color.lerp(c.success, onHero, 0.25),
                                        backgroundColor: c.heroGlass,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.all(ring / 7),
                                    child: FittedBox(
                                      child: Semantics(
                                        label: attT('att_code_hint'),
                                        value: code,
                                        excludeSemantics: true,
                                        child: Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: Text(grouped,
                                              style: AppType.figureLarge(context)
                                                  .copyWith(color: onHero, letterSpacing: AppSpace.xxs)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                              AppSpace.gapSm,
                              Text(attT('att_t_next_code', args: {'n': '${t.secondsLeft}'}),
                                  textAlign: TextAlign.center,
                                  style: AppType.label(context).copyWith(color: c.onHeroMuted)),
                            ] else
                              Icon(CupertinoIcons.person_3_fill, size: ring / 2.5, color: c.onHeroMuted),
                            AppSpace.gapXl,
                            Text(attT('att_t_reg_left'),
                                textAlign: TextAlign.center, style: AppType.row(context).copyWith(color: c.onHeroMuted)),
                            AppSpace.gapXs,
                            SizedBox(
                              height: ring / 5,
                              child: FittedBox(
                                child: Text(_mmss(left),
                                    style: AppType.figureLarge(context).copyWith(color: onHero)),
                              ),
                            ),
                          ],
                        ]),
                      ),
                    );
                  }),
                ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: bigButton,
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(CupertinoIcons.fullscreen_exit, size: AppIconSize.md),
                      label: Text(attT('att_t_minimize'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  AppSpace.gapSm,
                  Expanded(
                    child: (ended || closing)
                        ? FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(AppTouch.primary),
                                backgroundColor: onHero,
                                foregroundColor: c.primary,
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll)),
                            onPressed: closing ? null : () {
                              t.clear();
                              Navigator.of(context).maybePop();
                            },
                            child: Text(attT('att_done'), maxLines: 1, overflow: TextOverflow.ellipsis),
                          )
                        : FilledButton.icon(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(AppTouch.primary),
                                backgroundColor: c.dangerBase,
                                foregroundColor: appInkOnFill(context, c.dangerBase),
                                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                                shape: RoundedRectangleBorder(borderRadius: AppRadius.controlAll)),
                            onPressed: t.loading ? null : () => _confirmClose(t),
                            icon: const Icon(CupertinoIcons.lock, size: AppIconSize.md),
                            label: Text(attT('att_t_close'), maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// The present count in a glass pill; the digits roll when a student checks in.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.value});
  final IconData icon;
  final int value;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '${attT('att_t_present')}: $value',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(
            color: c.heroGlass,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: c.onHero, size: AppIconSize.md),
          AppSpace.gapXs,
          AppOdometer('$value', memoryKey: 'att_live_present', style: AppType.figure(context).copyWith(color: c.onHero)),
        ]),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.icon, required this.text, required this.size});
  final IconData icon;
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: size, color: context.colors.onHeroMuted),
        AppSpace.gapMd,
        Text(text, textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: context.colors.onHero)),
      ]);
}
