/// features/attendance/attendance_widgets.dart
///
/// Drop-in UI for relay-based attendance:
///   Student : [AttendanceStudentButton]  -> bottom sheet with code entry, live progress, verified result
///   Student : an online phone helps nearby classmates automatically while its sheet is open
///   Teacher : [AttendanceTeacherButton]  -> bottom sheet with the rotating code + live present counter
///
/// Warm Editorial (D-610 – D-629): the sheets are paper with an editorial masthead ([AttSheetHeader]); how the
/// check-in travels (online, through a classmate, the classmates still needed, location) is ONE sky block; the code
/// is six input wells; the journey is a quiet step list; and the one moment the sheet exists for — "you are marked
/// present" — is an emerald block that slides in ([AppSlideIn]). The teacher's running code sits in its countdown
/// ring with the present count rolling in an emerald block.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/features/attendance/attendance_live_screen.dart';
import 'package:flutter_education_app/features/attendance/attendance_permissions.dart';
import 'package:flutter_education_app/features/attendance/attendance_qr_card.dart';
import 'package:flutter_education_app/features/attendance/attendance_radios.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart';
import 'package:flutter_education_app/features/attendance/relay_host_provider.dart';
import 'package:flutter_education_app/features/attendance/student_checkin_provider.dart';
import 'package:flutter_education_app/features/attendance/teacher_attendance_controller.dart';

// Status colours come from the LIVE theme (success / danger / warning), so the sheet follows the app theme
// and dark mode like every other screen — no fixed colours here.

// ════════════════════════════════════════════════════════════════════════════
//  STUDENT
// ════════════════════════════════════════════════════════════════════════════

/// Put this on a lesson card (e.g. inside the lessons / live tab item).
class AttendanceStudentButton extends StatelessWidget {
  const AttendanceStudentButton({super.key, this.sessionId, this.courseId, this.compact = false});
  final int? sessionId;
  final int? courseId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AppButton.tonal(
      size: compact ? AppButtonSize.sm : AppButtonSize.md,
      icon: CupertinoIcons.person_crop_circle_badge_checkmark,
      label: attT('att_btn_checkin'),
      onPressed: () => showStudentCheckInSheet(context, sessionId: sessionId, courseId: courseId),
    );
  }
}

/// Code-entry sheet. Give a lesson ([sessionId]) or a whole course ([courseId]).
Future<void> showStudentCheckInSheet(BuildContext context, {int? sessionId, int? courseId, String? title}) {
  RelayHostProvider? host;
  try {
    host = context.read<RelayHostProvider>();
  } catch (_) {}
  return showAppModalSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider(
      create: (_) =>
          StudentCheckInProvider(sessionId: sessionId, courseId: courseId, host: host)..warmUp(),
      child: StudentCheckInSheet(title: title),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.header, this.onRefresh});
  final Widget child;

  /// Pull-to-refresh on the sheet (the teacher's live counter). The child must not hold a scroll view of its own:
  /// AppRefresh makes every scrollable inside always-scrollable, and an inner one would steal the sheet's drags.
  final Future<void> Function()? onRefresh;

  /// The masthead ([AttSheetHeader]). Sits flush at the top of the sheet.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return _refreshable(SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ?header,
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.lg),
          child: child,
        ),
      ]),
    ));
  }

  Widget _refreshable(Widget scroll) => onRefresh == null ? scroll : AppRefresh(onRefresh: onRefresh!, child: scroll);
}

/// GPS / Wi-Fi / Bluetooth state. Tap an "off" tile to go and switch it on.
class _RadiosRow extends StatelessWidget {
  const _RadiosRow({required this.p});
  final StudentCheckInProvider p;

  @override
  Widget build(BuildContext context) {
    final r = p.radios;
    Widget tile(RadioKind kind, IconData icon, String label, bool? on, {required bool needed}) {
      final color = on == true ? context.colors.success : (needed ? context.colors.danger : context.colors.warning);
      return Expanded(
        child: _RadioTile(
          icon: icon,
          label: label,
          state: on == null ? '—' : attT(on ? 'att_radio_on' : 'att_radio_off'),
          color: color,
          onTap: on == true
              ? null
              : () async {
                  final opened = await AttendanceRadios.fix(kind);
                  if (!opened && context.mounted) {
                    showAppNotice(attT(AttendanceRadios.hintKey(kind)));
                  }
                  await p.refreshRadios();   // the Android Bluetooth dialog returns without a resume
                },
        ),
      );
    }

    return Column(children: [
      Row(children: [
        tile(RadioKind.gps, CupertinoIcons.location_solid, 'GPS', r.gps,
            needed: p.requiredRadios.contains(RadioKind.gps)),
        AppSpace.gapXs,
        tile(RadioKind.wifi, CupertinoIcons.wifi, 'Wi-Fi', r.wifi, needed: p.requiredRadios.contains(RadioKind.wifi)),
        AppSpace.gapXs,
        tile(RadioKind.bluetooth, CupertinoIcons.bluetooth, 'Bluetooth', r.bluetooth,
            needed: p.requiredRadios.contains(RadioKind.bluetooth)),
      ]),
      if (r.permissionsBlocked)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: AttNotice(icon: CupertinoIcons.lock_shield, text: attT('att_err_perm_settings'), color: context.colors.danger),
        ),
    ]);
  }
}

/// One radio: the tone's opaque tint, the icon, the name and its state, all in the tone's legible ink.
class _RadioTile extends StatelessWidget {
  const _RadioTile({required this.icon, required this.label, required this.state, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final String state;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = appTintOn(context, color);
    final ink = appInkOn(context, color, tint);
    return Semantics(
      button: onTap != null,
      label: '$label, $state',
      excludeSemantics: true,
      child: Material(
        color: tint,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.controlAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs, vertical: AppSpace.xs),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: ink, size: AppIconSize.md),
                const SizedBox(height: AppSpace.xxs),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(context).copyWith(color: ink, fontWeight: FontWeight.w600)),
                Text(state,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.meta(context).copyWith(color: ink)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Turn on Bluetooth" / "Turn on GPS" … — one big friendly button per switched-off radio. The sheet listens
/// for the app coming back and continues the check-in on its own once everything is on.
class _FixRadios extends StatelessWidget {
  const _FixRadios({required this.p, required this.kinds});
  final StudentCheckInProvider p;
  final List<RadioKind> kinds;

  static const _icons = {
    RadioKind.gps: CupertinoIcons.location_solid,
    RadioKind.wifi: CupertinoIcons.wifi,
    RadioKind.bluetooth: CupertinoIcons.bluetooth,
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final k in kinds)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.xs),
            child: AppButton.danger(
              dangerOutline: true,
              expand: true,
              icon: _icons[k],
              label: attT('att_turn_on_${k.name}'),
              onPressed: () async {
                final opened = await AttendanceRadios.fix(k);
                if (!opened && context.mounted) {
                  showAppNotice(attT(AttendanceRadios.hintKey(k)));
                }
                await p.refreshRadios();
              },
            ),
          ),
        Text(attT('att_fix_auto_continue'), textAlign: TextAlign.center, style: AppType.meta(context)),
      ]),
    );
  }
}

/// Six-well one-time-code input (a hidden TextField drives the wells). The wells share the width they are given
/// (never wider than 52), so the row fits a 320 px phone at any text size.
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.enabled, required this.onSubmit});
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  static const double _maxWell = 52;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return LayoutBuilder(builder: (context, box) {
      final w = ((box.maxWidth - AppSpace.xs * 5) / 6).clamp(AppSpace.xl, _maxWell).toDouble();
      return ListenableBuilder(
        listenable: controller,
        builder: (_, _) {
          final text = controller.text;
          return Stack(alignment: Alignment.center, children: [
            Directionality(
              // a code reads left to right in both languages
              textDirection: TextDirection.ltr,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) SizedBox(width: i == 3 ? AppSpace.sm : AppSpace.xxs),
                  AnimatedContainer(
                    duration: motion.fast,
                    curve: AppMotion.curve,
                    width: w,
                    height: w * 1.25,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i < text.length ? c.cardBg : c.inputBg,
                      borderRadius: AppRadius.controlAll,
                      border: Border.all(
                          color: enabled && i == text.length ? c.primary : c.divider,
                          width: enabled && i == text.length ? AppBorder.focus : AppBorder.hairline),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.xxs),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(i < text.length ? text[i] : '', style: AppType.figureLarge(context)),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0,
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  autofocus: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: onSubmit,
                ),
              ),
            ),
          ]);
        },
      );
    });
  }
}

/// The student's code sheet. Public so a layout / visual test can pump it over a [StudentCheckInProvider] it set up.
@visibleForTesting
class StudentCheckInSheet extends StatefulWidget {
  const StudentCheckInSheet({super.key, this.title});
  final String? title;
  @override
  State<StudentCheckInSheet> createState() => _StudentSheetState();
}

class _StudentSheetState extends State<StudentCheckInSheet> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();

  /// The last outcome shown, kept so the result panel can slide out with its content when a retry clears it.
  CheckInOutcome? _shown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl.dispose();
    super.dispose();
  }

  /// Back from the system settings (after switching GPS / Bluetooth on): re-read the radios.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<StudentCheckInProvider>().refreshRadios();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentCheckInProvider>();
    final o = p.outcome;
    if (o != null) _shown = o;
    final c = context.colors;
    final finished = o != null && o.kind != OutcomeKind.failed && o.kind != OutcomeKind.pending;
    final showRoute = p.online != null || p.witnessesNeeded > 0 || p.needsLocation;

    return _SheetFrame(
      header: AttSheetHeader(
        icon: CupertinoIcons.dot_radiowaves_left_right,
        title: widget.title ?? attT('att_sheet_title'),
        subtitle: attT(p.needsCode ? 'att_sheet_sub' : 'att_sheet_sub_mates'),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!finished) ...[
          _RadiosRow(p: p),
          AppSpace.gapSm,
        ],
        // How this check-in travels: straight to the server, or through a classmate's phone.
        if (showRoute)
          AppBlock(
            tone: AppBlockTone.sky,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p.online != null)
                AttRouteLine(
                  strong: true,
                  icon: p.online! ? CupertinoIcons.wifi : CupertinoIcons.antenna_radiowaves_left_right,
                  text: attT(p.online! ? 'att_online_direct' : 'att_offline_relay'),
                  color: p.online! ? c.success : c.warning,
                ),
              if (p.witnessesNeeded > 0)
                AttRouteLine(
                    icon: CupertinoIcons.person_2_fill,
                    text: attT('att_need_mates', args: {'n': '${p.witnessesNeeded}'}),
                    color: c.primary),
              // An online phone is visible to nearby classmates automatically while this sheet is open.
              if (p.online == true && p.host != null) _VisibleLine(host: p.host!),
              if (p.needsLocation)
                AttRouteLine(icon: CupertinoIcons.location_solid, text: attT('att_need_location'), color: c.primary),
            ]),
          ),
        if (!finished && p.needsCode) ...[
          AppSpace.gapLg,
          _CodeBoxes(controller: _ctrl, enabled: !p.busy, onSubmit: p.submit),
          AppSpace.gapXs,
          Text(attT('att_code_hint'), textAlign: TextAlign.center, style: AppType.meta(context)),
        ],
        if (p.busy || o != null) ...[
          AppSpace.gapMd,
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, s) in [for (final s in Stage.values) if (p.stages[s] != StageState.skipped) s].indexed)
                _StageRow(stage: s, state: p.stages[s]!, first: i == 0),
            ]),
          ),
        ],
        AppSlideIn(
          visible: o != null,
          child: _shown == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: _OutcomeCard(key: ValueKey(_shown!.kind), outcome: _shown!),
                ),
        ),
        if (o != null) ...[
          if (o.fix.isNotEmpty) _FixRadios(p: p, kinds: o.fix),
          if (o.needsSettings)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppButton.ghost(
                  icon: CupertinoIcons.lock_shield, label: attT('att_err_perm_settings'), onPressed: openSettings),
            ),
        ],
        AppSpace.gapLg,
        AppButton.primary(
          expand: true,
          size: AppButtonSize.lg,
          busy: p.busy,
          label: attT(finished ? 'att_done' : (o == null ? 'att_submit' : 'att_retry')),
          onPressed: p.busy
              ? null
              : finished
                  ? () => Navigator.of(context).maybePop()
                  : () => p.submit(_ctrl.text),
        ),
      ]),
    );
  }
}

/// One step of the check-in's journey: a mark (waiting ring, spinner, check, cross) on a thin rail that joins it to
/// the step before, and the step's name — strong while it runs, quiet before.
class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.state, required this.first});
  final Stage stage;
  final StageState state;
  final bool first;

  static const _labels = {
    Stage.network: 'att_stage_net',
    Stage.permissions: 'att_stage_perm',
    Stage.relay: 'att_stage_relay',
    Stage.witness: 'att_stage_witness',
    Stage.send: 'att_stage_send',
    Stage.server: 'att_stage_server',
  };

  String _text(BuildContext context) {
    if (stage == Stage.witness && state != StageState.waiting) {
      final p = context.read<StudentCheckInProvider>();
      return attT('att_witness_progress',
          args: {'x': '${p.witnessesFound}', 'n': '${p.witnessesNeeded}'});
    }
    return attT(_labels[stage]!);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final Widget mark = switch (state) {
      StageState.ok => Icon(CupertinoIcons.checkmark_circle_fill, color: c.success, size: AppIconSize.md),
      StageState.failed => Icon(CupertinoIcons.xmark_circle_fill, color: c.danger, size: AppIconSize.md),
      StageState.active => SizedBox(
          width: AppIconSize.sm,
          height: AppIconSize.sm,
          child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.primary)),
      _ => Icon(CupertinoIcons.circle, color: c.textLight, size: AppIconSize.md),
    };
    final style = switch (state) {
      StageState.active => AppType.row(context),
      StageState.failed => AppType.row(context).copyWith(color: appInkOn(context, c.danger, c.cardBg)),
      StageState.ok => AppType.body(context),
      _ => AppType.body(context).copyWith(color: c.textLight),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!first)
        Padding(
          padding: const EdgeInsetsDirectional.only(start: AppIconSize.md / 2 - AppBorder.hairline),
          child: Container(width: AppBorder.focus, height: AppSpace.xs, color: c.divider),
        ),
      Row(children: [
        SizedBox(width: AppIconSize.md, height: AppIconSize.md, child: Center(child: mark)),
        AppSpace.gapSm,
        Expanded(child: Text(_text(context), style: style)),
      ]),
    ]);
  }
}

/// The result. Accepted is the sheet's one moment: an emerald block, the seal settling in, the headline in the
/// editorial face. Anything else is a paper card with the tone's mark — rejected / failed in danger, pending in
/// warning — and says what happened.
class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({super.key, required this.outcome});
  final CheckInOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    late final Color color;
    late final IconData icon;
    late final String title;
    String? body;

    switch (outcome.kind) {
      case OutcomeKind.accepted:
        color = c.success;
        icon = CupertinoIcons.checkmark_seal_fill;
        title = attT('att_ok_title');
        final t = outcome.result?.confirmedLocal;
        final time = t == null
            ? ''
            : AppTime.time(t.toUtc());
        body = attT('att_ok_body', args: {'time': time}) +
            (outcome.viaRelay ? ' — ${attT('att_ok_via')}' : '');
      case OutcomeKind.rejected:
        color = c.danger;
        icon = CupertinoIcons.xmark_seal_fill;
        title = attT('att_rej_title');
        body = attT(outcome.messageKey ?? 'att_reason_wrong_code');
      case OutcomeKind.pending:
        color = c.warning;
        icon = CupertinoIcons.clock_fill;
        title = attT('att_pending_title');
        body = attT('att_pending_body');
      case OutcomeKind.failed:
        color = c.danger;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        title = attT(outcome.messageKey ?? 'att_err_generic');
    }

    final detail = outcome.detail != null && outcome.detail!.isNotEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: SelectableText(outcome.detail!, style: AppType.meta(context)),
          )
        : null;

    if (outcome.kind == OutcomeKind.accepted) {
      return AppBlock(
        tone: AppBlockTone.emerald,
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Column(children: [
            _Seal(icon: icon, color: c.primary),
            AppSpace.gapMd,
            Text(title, textAlign: TextAlign.center, style: AppType.headline(context).copyWith(color: b.ink)),
            AppSpace.gapXs,
            Text(body!, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: b.muted)),
            ?detail,
          ]);
        }),
      );
    }

    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AttIconWell(icon: icon, color: color),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppType.bodyStrong(context).copyWith(color: appInkOn(context, color, c.cardBg))),
            if (body != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Text(body, style: AppType.body(context)),
            ],
            ?detail,
          ]),
        ),
      ]),
    );
  }
}

/// The confirmation seal: a solid emerald disc that settles from 80 % with a small overshoot (instant under Reduce
/// motion).
class _Seal extends StatelessWidget {
  const _Seal({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = AppTouch.primary + AppSpace.xs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1),
      duration: AppMotion.of(context).off ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: appInkOnFill(context, color), size: AppIconSize.xl),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  RELAY HOST SWITCH (online student)
// ════════════════════════════════════════════════════════════════════════════

/// "Help classmates" switch. Put it on the lessons tab or profile screen.
/// Requires [RelayHostProvider] in the provider tree (see providers.dart).
class RelayHostTile extends StatelessWidget {
  const RelayHostTile({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<RelayHostProvider>();
    if (!p.supported) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AttIconWell(icon: CupertinoIcons.person_2_fill, color: c.primary),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(attT('att_relay_title'), style: AppType.bodyStrong(context)),
                const SizedBox(height: AppSpace.xxs / 2),
                Text(attT(p.enabled ? 'att_relay_on' : 'att_relay_sub'), style: AppType.meta(context)),
              ]),
            ),
            p.starting
                ? SizedBox(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.primary))
                : AppSwitch(value: p.enabled, onChanged: (v) => p.setEnabled(v), semanticLabel: attT('att_relay_title')),
          ]),
          if (p.enabled && p.helped > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AttNotice(
                  icon: CupertinoIcons.checkmark_circle_fill,
                  text: attT('att_relay_helped', args: {'n': '${p.helped}'}),
                  color: c.success),
            ),
          if (p.errorKey != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AttNotice(icon: CupertinoIcons.exclamationmark_circle, text: attT(p.errorKey!), color: c.danger),
            ),
          if (p.needsSettings)
            AppButton.ghost(icon: CupertinoIcons.lock_shield, label: attT('att_err_perm_settings'), onPressed: openSettings),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  TEACHER
// ════════════════════════════════════════════════════════════════════════════

/// Put this next to the lesson on the teacher's lessons list.
class AttendanceTeacherButton extends StatelessWidget {
  const AttendanceTeacherButton({super.key, required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context) {
    return AppButton.tonal(
      icon: CupertinoIcons.qrcode_viewfinder,
      label: attT('att_t_btn'),
      onPressed: () => showTeacherAttendanceSheet(context, sessionId),
    );
  }
}

Future<void> showTeacherAttendanceSheet(BuildContext context, int sessionId, {String? title, AttView view = AttView.code}) {
  attViewMode.value = view == AttView.manual ? AttView.code : view;
  RelayHostProvider? host;
  try {
    host = context.read<RelayHostProvider>();
  } catch (_) {}
  final ctl = TeacherAttendanceController.instance..prepare(sessionId, host, title: title);
  return showAppModalSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    // The window lives in the app-wide controller: closing the sheet leaves it running and the
    // global banner keeps the code visible while the teacher moves around the app.
    builder: (_) => ChangeNotifierProvider<TeacherAttendanceController>.value(
      value: ctl,
      child: TeacherAttendanceSheet(view: view == AttView.manual ? AttView.code : view),
    ),
  );
}

/// The teacher's sheet: the setup before starting, the running code after. Public so a layout / visual test can
/// pump it over the controller it set up.
@visibleForTesting
class TeacherAttendanceSheet extends StatelessWidget {
  const TeacherAttendanceSheet({super.key, this.view = AttView.code});

  /// How the open window is shown: the code in its ring, or a QR of the same code.
  final AttView view;

  Widget _label(BuildContext context, String key, {String? hint, bool first = false}) => Padding(
        padding: EdgeInsets.only(top: first ? 0 : AppSpace.md, bottom: AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(attT(key), style: AppType.bodyStrong(context)),
          if (hint != null) ...[
            const SizedBox(height: AppSpace.xxs / 2),
            Text(attT(hint), style: AppType.meta(context)),
          ],
        ]),
      );

  Widget _choices(List<Widget> chips) => Wrap(spacing: AppSpace.xs, children: chips);

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherAttendanceController>();
    final c = context.colors;
    final started = p.window != null;

    return _SheetFrame(
      header: AttSheetHeader(
        icon: view == AttView.qr ? CupertinoIcons.qrcode : Icons.desktop_windows_outlined,
        title: attT('att_t_title'),
        subtitle: p.lessonTitle,
      ),
      onRefresh: started ? p.refresh : null,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!started) ...[
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, 'att_t_duration', first: true),
                _choices([
                  for (final m in TeacherAttendanceController.options)
                    AttChoice(
                      label: attT('att_t_minutes', args: {'n': '$m'}),
                      selected: p.minutes == m,
                      onTap: () => p.setMinutes(m),
                    ),
                ]),
                _label(context, 'att_t_method', hint: 'att_t_method_hint'),
                _choices([
                  for (final m in TeacherAttendanceController.methods)
                    AttChoice(
                      label: attT('att_method_$m'),
                      selected: p.method == m,
                      onTap: () => p.setMethod(m),
                    ),
                ]),
                if (p.usesWitnesses) ...[
                  _label(context, 'att_t_witnesses', hint: 'att_t_witnesses_hint'),
                  _choices([
                    for (final n in TeacherAttendanceController.witnessOptions)
                      AttChoice(
                        label: '$n',
                        selected: p.requiredWitnesses == n,
                        onTap: () => p.setWitnesses(n),
                      ),
                  ]),
                ],
              ]),
            ),
            AppSpace.gapSm,
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(context, 'att_t_grace', hint: 'att_t_grace_hint', first: true),
                _choices([
                  for (final g in TeacherAttendanceController.graceOptions)
                    AttChoice(
                      label: attT('att_t_seconds', args: {'n': '$g'}),
                      selected: p.graceSeconds == g,
                      onTap: () => p.setGrace(g),
                    ),
                ]),
                AppSpace.gapXs,
                AppSwitchTile(
                  value: p.allowWeb,
                  onChanged: p.setAllowWeb,
                  title: attT('att_t_allow_web'),
                  subtitle: attT('att_t_allow_web_hint'),
                ),
                _LocationSetup(p: p),
              ]),
            ),
            AppSpace.gapLg,
            AppButton.primary(
              expand: true,
              size: AppButtonSize.lg,
              busy: p.loading,
              icon: CupertinoIcons.qrcode,
              label: attT('att_t_start'),
              onPressed: p.loading ? null : () => p.open(),
            ),
          ] else ...[
            if (view == AttView.qr && p.usesCode && p.code != null)
              AttQrCard(
                code: p.code!.code,
                secondsLeft: p.secondsLeft,
                registrationLeft: p.registrationLeft,
                lesson: p.lessonTitle,
                open: p.isOpen,
              )
            else
              _CodeDisplay(p: p),
            if (p.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Center(
                  child: AppButton.ghost(
                    icon: CupertinoIcons.fullscreen,
                    label: attT('att_t_fullscreen'),
                    onPressed: () {
                      final nav = Navigator.of(context);
                      nav.pop(); // close the sheet, then show the full-screen view
                      openAttendanceLiveOn(nav);
                    },
                  ),
                ),
              ),
            if (p.host != null && (p.isOpen || p.isClosing)) ...[
              AppSpace.gapSm,
              _TeacherRelayBanner(host: p.host!),
            ],
            AppSpace.gapMd,
            if (p.usesCode) Text(attT('att_t_show'), textAlign: TextAlign.center, style: AppType.meta(context)),
            if (p.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(attT('att_t_move_hint'), textAlign: TextAlign.center, style: AppType.meta(context)),
              ),
            AppSpace.gapMd,
            if (p.closed || !(p.code?.isOpen ?? true))
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AttNotice(
                    icon: CupertinoIcons.lock_fill,
                    text: p.isClosing
                        ? attT('att_t_closing', args: {'n': '${p.closingLeft}'})
                        : attT(p.closed ? 'att_t_closed' : 'att_t_expired'),
                    color: c.warning),
                if (!p.isClosing)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: AppButton.secondary(expand: true, label: attT('att_t_new'), onPressed: p.clear),
                  ),
              ])
            else
              AppButton.danger(
                dangerOutline: true,
                expand: true,
                icon: CupertinoIcons.lock,
                label: attT('att_t_close'),
                onPressed: p.loading ? null : p.close,
              ),
          ],
          if (p.error != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: AttNotice(
                  icon: CupertinoIcons.exclamationmark_circle,
                  text: p.error!.startsWith('att_') ? attT(p.error!) : p.error!,
                  color: c.danger),
            ),
          // The teacher's phone sets the classroom point: give the exact fix, not just an error line.
          if (p.error == 'att_err_gps_off')
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppButton.tonal(
                expand: true,
                icon: CupertinoIcons.location_solid,
                label: attT('att_turn_on_gps'),
                onPressed: () => AttendanceRadios.fix(RadioKind.gps),
              ),
            )
          else if (p.error == 'att_err_location_denied_forever')
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: AppButton.tonal(
                expand: true,
                icon: CupertinoIcons.lock_shield,
                label: attT('att_err_perm_settings'),
                onPressed: openSettings,
              ),
            ),
        ]),
    );
  }
}

/// Location check setup: on/off, allowed distance, and (web) where the classroom point comes from.
class _LocationSetup extends StatelessWidget {
  const _LocationSetup({required this.p});
  final TeacherAttendanceController p;

  Future<void> _toggle(BuildContext context, bool on) async {
    if (!on) return p.setUseLocation(false);
    if (!kIsWeb) return p.setUseLocation(true);
    // WEB: the browser's location is rough and Wi-Fi is unreadable, so ask where to take it from.
    final pick = await showAppDialog<String>(
      context,
      title: attT('att_t_web_loc_title'),
      icon: CupertinoIcons.location_solid,
      body: Text(attT('att_t_web_loc_body')),
      actions: [
        Builder(
            builder: (ctx) =>
                AppButton.ghost(label: attT('att_t_web_loc_browser'), onPressed: () => Navigator.pop(ctx, 'browser'))),
        Builder(
            builder: (ctx) =>
                AppButton.primary(label: attT('att_t_web_loc_mobile'), onPressed: () => Navigator.pop(ctx, 'mobile'))),
      ],
    );
    if (pick == null) return;
    p.setWebSource(pick);
    p.setUseLocation(true);
    if (pick == 'mobile' && !await p.checkSharedLocation()) {
      p.requestFromMobile(); // silent push to the phone; the sheet shows "waiting" meanwhile
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppSwitchTile(
        value: p.useLocation,
        onChanged: (v) => _toggle(context, v),
        title: attT('att_t_location'),
        subtitle: attT(kIsWeb ? 'att_t_location_hint_web' : 'att_t_location_hint'),
      ),
      if (p.useLocation) ...[
        AppSpace.gapXs,
        Row(children: [
          Expanded(child: Text(attT('att_t_distance'), style: AppType.bodyStrong(context))),
          AppSpace.gapXs,
          Text(attT('att_t_meters', args: {'n': '${p.radiusM}'}), style: AppType.figure(context)),
        ]),
        Slider(
          value: p.radiusM.toDouble(),
          min: TeacherAttendanceController.minRadius.toDouble(),
          max: TeacherAttendanceController.maxRadius.toDouble(),
          divisions: (TeacherAttendanceController.maxRadius - TeacherAttendanceController.minRadius) ~/ 10,
          label: '${p.radiusM} m',
          onChanged: (v) => p.setRadius((v / 10).round() * 10),
        ),
        Text(attT('att_t_distance_hint'), style: AppType.meta(context)),
        if (kIsWeb && p.webLocationSource == 'mobile')
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(children: [
              if (p.waitingMobile)
                SizedBox(
                    width: AppIconSize.sm,
                    height: AppIconSize.sm,
                    child: CircularProgressIndicator(strokeWidth: AppBorder.focus, color: c.primary))
              else
                Icon(p.sharedFromMobile ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.info,
                    size: AppIconSize.sm, color: p.sharedFromMobile ? c.success : c.warning),
              AppSpace.gapXs,
              Expanded(
                child: Text(
                    attT(p.waitingMobile
                        ? 'att_t_waiting_mobile'
                        : (p.sharedFromMobile ? 'att_t_shared_found' : 'att_t_shared_missing')),
                    style: AppType.meta(context)),
              ),
              AppButton.ghost(
                  size: AppButtonSize.sm,
                  label: attT('att_t_ask_phone'),
                  onPressed: p.waitingMobile ? null : p.requestFromMobile),
            ]),
          ),
        if (!kIsWeb)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: AppButton.ghost(
              icon: p.sharedFromMobile ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.share,
              label: attT('att_t_share_for_web'),
              onPressed: () async {
                final ok = await p.shareLocationForWeb();
                if (ok && context.mounted) {
                  showAppNotice(attT('att_t_shared_done'));
                }
              },
            ),
          ),
      ],
    ]);
  }
}

/// The running code: six digits in their countdown ring (the ring empties as the code's rotation runs out), and
/// under it the present count rolling in an emerald block.
class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.p});
  final TeacherAttendanceController p;

  static const double _ring = 200;
  static const double _ringStroke = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rot = p.window?.rotationSeconds ?? 45;
    final code = p.code?.code ?? '------';
    final grouped = p.usesCode ? '${code.substring(0, 3)} ${code.substring(3)}' : '';
    final active = p.isOpen;
    final present = p.code?.presentCount ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(
        child: SizedBox(
          width: _ring,
          height: _ring,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: active ? (p.secondsLeft / rot).clamp(0.0, 1.0) : 0,
                strokeWidth: _ringStroke,
                strokeCap: StrokeCap.round,
                color: c.primary,
                backgroundColor: c.inputBg,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (grouped.isEmpty)
                  Icon(CupertinoIcons.person_3_fill, size: AppIconSize.hero, color: active ? c.primary : c.textLight)
                else
                  FittedBox(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(grouped,
                          semanticsLabel: code.split('').join(' '),
                          style: AppType.figureLarge(context)
                              .copyWith(color: active ? c.textDark : c.textLight, letterSpacing: AppSpace.xxs / 2)),
                    ),
                  ),
                if (active) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(attT('att_t_next_code', args: {'n': '${p.secondsLeft}'}),
                      textAlign: TextAlign.center, maxLines: 2, style: AppType.meta(context)),
                ],
              ]),
            ),
          ]),
        ),
      ),
      AppSpace.gapMd,
      AppBlock(
        tone: AppBlockTone.emerald,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
        child: Builder(builder: (context) {
          final b = AppBlock.colorsOf(context);
          return Row(children: [
            Icon(CupertinoIcons.person_3_fill, color: b.accentInk(c.success), size: AppIconSize.lg),
            AppSpace.gapSm,
            Expanded(child: Text(attT('att_t_present'), style: AppType.row(context).copyWith(color: b.ink))),
            AppOdometer('$present',
                memoryKey: 'att.present.${p.window?.id}', style: AppType.figureLarge(context).copyWith(color: b.ink)),
          ]);
        }),
      ),
    ]);
  }
}


// ════════════════════════════════════════════════════════════════════════════
//  COURSE PROFILE BUTTON (student)
// ════════════════════════════════════════════════════════════════════════════

/// "Record attendance" button for the course profile. Opens the code sheet for the course's
/// currently open attendance window. Online students ask the server; the sheet then collects the
/// teacher-required number of classmate signals before submitting.
class AttendanceCourseButton extends StatelessWidget {
  const AttendanceCourseButton({super.key, required this.courseId, this.title});
  final int courseId;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return AppButton.tonal(
      expand: true,
      icon: CupertinoIcons.person_crop_circle_badge_checkmark,
      label: attT('att_btn_checkin'),
      onPressed: () => showStudentCheckInSheet(context, courseId: courseId, title: title),
    );
  }
}


/// Shows whether THIS phone is currently advertising to nearby classmates (a line of the route block).
class _VisibleLine extends StatelessWidget {
  const _VisibleLine({required this.host});
  final RelayHostProvider host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: host,
        builder: (_, _) {
          final on = host.running;
          return AttRouteLine(
            icon: on ? CupertinoIcons.dot_radiowaves_right : CupertinoIcons.eye_slash,
            text: on
                ? attT('att_visible_yes')
                : '${attT('att_visible_no')}${host.hostError == null ? '' : ' (${host.hostError})'}',
            color: on ? context.colors.success : context.colors.warning,
          );
        },
      );
}


/// Teacher side: shows that this phone is receiving check-ins from nearby offline students.
class _TeacherRelayBanner extends StatelessWidget {
  const _TeacherRelayBanner({required this.host});
  final RelayHostProvider host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: host,
        builder: (_, _) => AttNotice(
          icon: host.running ? CupertinoIcons.dot_radiowaves_right : CupertinoIcons.eye_slash,
          text: host.running
              ? '${attT('att_t_relay_on')}${host.helped > 0 ? ' • ${host.helped}' : ''}'
              : '${attT('att_t_relay_off')}${host.hostError == null ? '' : ' (${host.hostError})'}',
          color: host.running ? context.colors.success : context.colors.warning,
        ),
      );
}
