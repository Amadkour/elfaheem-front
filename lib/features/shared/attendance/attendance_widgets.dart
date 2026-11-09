/// features/attendance/attendance_widgets.dart
///
/// Drop-in UI for relay-based attendance:
///   Student : [AttendanceStudentButton]  -> bottom sheet with code entry, live progress, verified result
///   Student : an online phone helps nearby classmates automatically while its sheet is open
///   Teacher : [AttendanceTeacherButton]  -> bottom sheet with the rotating code + live present counter
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'attendance_live_screen.dart';
import 'attendance_permissions.dart';
import 'attendance_radios.dart';
import 'attendance_strings.dart';
import 'relay_host_provider.dart';
import 'student_checkin_provider.dart';
import 'teacher_attendance_controller.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/design/app_gradients.dart';

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
    final c = context.colors.primary;
    return TextButton.icon(
      onPressed: () => showStudentCheckInSheet(context, sessionId: sessionId, courseId: courseId),
      style: TextButton.styleFrom(
        foregroundColor: c,
        backgroundColor: c.withValues(alpha: 0.10),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 6 : 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark, size: 18),
      label: Text(attT('att_btn_checkin'),
          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700, fontSize: 13)),
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
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider(
      create: (_) =>
          StudentCheckInProvider(sessionId: sessionId, courseId: courseId, host: host)..warmUp(),
      child: _StudentSheet(title: title),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child, this.header, this.onRefresh});
  final Widget child;

  /// Pull-to-refresh on the sheet (the teacher's live counter). The child must not hold a scroll view of its own:
  /// AppRefresh makes every scrollable inside always-scrollable, and an inner one would steal the sheet's drags.
  final Future<void> Function()? onRefresh;

  /// Premium gradient header (icon, title, subtitle). Sits flush at the top of the sheet.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return _refreshable(SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ?header,
        Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), child: child),
      ]),
    ));
  }

  Widget _refreshable(Widget scroll) => onRefresh == null ? scroll : AppRefresh(onRefresh: onRefresh!, child: scroll);
}

/// Gradient header shared by the student and teacher sheets.
class _PremiumHeader extends StatelessWidget {
  const _PremiumHeader({required this.icon, required this.title, this.subtitle, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppMeshSurface(
      child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      child: Column(children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: context.colors.onHero.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.heroGlassBorder)),
            child: Icon(icon, color: context.colors.onHero, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppFonts.family, fontSize: 17, fontWeight: FontWeight.w800, color: context.colors.onHero)),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: context.colors.onHero.withValues(alpha: 0.85))),
              ],
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      ]),
      ),
    );
  }
}

/// Soft rounded group used to organise the settings / status blocks.
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.colors.primary.withValues(alpha: 0.12)),
        ),
        child: child,
      );
}

/// GPS / Wi-Fi / Bluetooth state. Tap an "off" chip to go and switch it on.
class _RadiosRow extends StatelessWidget {
  const _RadiosRow({required this.p});
  final StudentCheckInProvider p;

  @override
  Widget build(BuildContext context) {
    final r = p.radios;
    Widget chip(RadioKind kind, IconData icon, String label, bool? on, {required bool needed}) {
      final color = on == true ? context.colors.success : (needed ? context.colors.danger : context.colors.warning);
      return Expanded(
        child: GestureDetector(
          onTap: on == true
              ? null
              : () async {
                  final opened = await AttendanceRadios.fix(kind);
                  if (!opened && context.mounted) {
                    showAppNotice(attT(AttendanceRadios.hintKey(kind)));
                  }
                  await p.refreshRadios();   // the Android Bluetooth dialog returns without a resume
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Column(children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
              Text(on == null ? '—' : attT(on ? 'att_radio_on' : 'att_radio_off'),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 10.5, color: color)),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      Row(children: [
        chip(RadioKind.gps, CupertinoIcons.location_solid, 'GPS', r.gps,
            needed: p.requiredRadios.contains(RadioKind.gps)),
        const SizedBox(width: 8),
        chip(RadioKind.wifi, CupertinoIcons.wifi, 'Wi-Fi', r.wifi, needed: p.requiredRadios.contains(RadioKind.wifi)),
        const SizedBox(width: 8),
        chip(RadioKind.bluetooth, CupertinoIcons.bluetooth, 'Bluetooth', r.bluetooth,
            needed: p.requiredRadios.contains(RadioKind.bluetooth)),
      ]),
      if (r.permissionsBlocked)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _Banner(icon: CupertinoIcons.lock_shield, text: attT('att_err_perm_settings'), color: context.colors.danger),
        ),
    ]);
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
      padding: const EdgeInsets.only(top: 10),
      child: Column(children: [
        for (final k in kinds)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.danger,
                  side: BorderSide(color: context.colors.danger.withValues(alpha: 0.5), width: 1.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  final opened = await AttendanceRadios.fix(k);
                  if (!opened && context.mounted) {
                    showAppNotice(attT(AttendanceRadios.hintKey(k)));
                  }
                  await p.refreshRadios();
                },
                icon: Icon(_icons[k]),
                label: Text(attT('att_turn_on_${k.name}'),
                    style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        Text(attT('att_fix_auto_continue'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
      ]),
    );
  }
}

/// Six-box one-time-code input (a hidden TextField drives the boxes).
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({required this.controller, required this.enabled, required this.onSubmit});
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    return ListenableBuilder(
      listenable: controller,
      builder: (_, _) {
        final text = controller.text;
        return Stack(alignment: Alignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44,
                height: 56,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: i < text.length ? 0.12 : 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: i == text.length ? primary : primary.withValues(alpha: 0.2),
                      width: i == text.length ? 2 : 1),
                ),
                child: Text(i < text.length ? text[i] : '',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              ),
          ]),
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
  }
}

class _StudentSheet extends StatefulWidget {
  const _StudentSheet({this.title});
  final String? title;
  @override
  State<_StudentSheet> createState() => _StudentSheetState();
}

class _StudentSheetState extends State<_StudentSheet> with WidgetsBindingObserver {
  final _ctrl = TextEditingController();

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
    final primary = context.colors.primary;
    final finished = o != null && o.kind != OutcomeKind.failed && o.kind != OutcomeKind.pending;

    return _SheetFrame(
      header: _PremiumHeader(
        icon: CupertinoIcons.dot_radiowaves_left_right,
        title: widget.title ?? attT('att_sheet_title'),
        subtitle: attT(p.needsCode ? 'att_sheet_sub' : 'att_sheet_sub_mates'),
        trailing: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: Icon(CupertinoIcons.xmark_circle_fill, color: context.colors.onHeroMuted),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!finished) ...[
          _RadiosRow(p: p),
          const SizedBox(height: 12),
        ],
        if (p.online != null)
          _Banner(
            icon: p.online! ? CupertinoIcons.wifi : CupertinoIcons.antenna_radiowaves_left_right,
            text: attT(p.online! ? 'att_online_direct' : 'att_offline_relay'),
            color: p.online! ? context.colors.success : context.colors.warning,
          ),
        if (p.witnessesNeeded > 0) ...[
          const SizedBox(height: 8),
          _Banner(
              icon: CupertinoIcons.person_2_fill,
              text: attT('att_need_mates', args: {'n': '${p.witnessesNeeded}'}),
              color: primary),
        ],
        // An online phone is visible to nearby classmates automatically while this sheet is open.
        if (p.online == true && p.host != null) _VisibleBanner(host: p.host!),
        if (p.needsLocation) ...[
          const SizedBox(height: 8),
          _Banner(icon: CupertinoIcons.location_solid, text: attT('att_need_location'), color: primary),
        ],
        if (!finished && p.needsCode) ...[
          const SizedBox(height: 20),
          _CodeBoxes(controller: _ctrl, enabled: !p.busy, onSubmit: p.submit),
          const SizedBox(height: 4),
          Text(attT('att_code_hint'),
              style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
        ],
        if (p.busy || o != null) ...[
          const SizedBox(height: 14),
          _Card(
            child: Column(children: [
              for (final s in Stage.values)
                if (p.stages[s] != StageState.skipped) _StageRow(stage: s, state: p.stages[s]!),
            ]),
          ),
        ],
        if (o != null) ...[
          const SizedBox(height: 6),
          _OutcomeCard(outcome: o),
          if (o.fix.isNotEmpty) _FixRadios(p: p, kinds: o.fix),
          if (o.needsSettings)
            TextButton(onPressed: openSettings, child: Text(attT('att_err_perm_settings'))),
        ],
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: p.busy ? null : AppGradients.blend(context, color: primary),
              color: p.busy ? context.colors.divider : null,
              borderRadius: BorderRadius.circular(18),
              boxShadow: p.busy
                  ? null
                  : [BoxShadow(color: primary.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: p.busy
                  ? null
                  : finished
                      ? () => Navigator.of(context).maybePop()
                      : () => p.submit(_ctrl.text),
              child: p.busy
                  ? SizedBox(
                      width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: context.colors.onHero))
                  : Text(attT(finished ? 'att_done' : (o == null ? 'att_submit' : 'att_retry')),
                      style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: color, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _StageRow extends StatelessWidget {
  const _StageRow({required this.stage, required this.state});
  final Stage stage;
  final StageState state;

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
    final Widget icon = switch (state) {
      StageState.ok => Icon(CupertinoIcons.checkmark_circle_fill, color: context.colors.success, size: 20),
      StageState.failed => Icon(CupertinoIcons.xmark_circle_fill, color: context.colors.danger, size: 20),
      StageState.active => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
      _ => Icon(CupertinoIcons.circle, color: context.colors.textLight, size: 20),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        icon,
        const SizedBox(width: 10),
        Text(_text(context),
            style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize: 13,
                color: state == StageState.waiting ? context.colors.textLight : null)),
      ]),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome});
  final CheckInOutcome outcome;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    late final String title;
    String? body;

    switch (outcome.kind) {
      case OutcomeKind.accepted:
        color = context.colors.success;
        icon = CupertinoIcons.checkmark_seal_fill;
        title = attT('att_ok_title');
        final t = outcome.result?.confirmedLocal;
        final time = t == null
            ? ''
            : AppTime.time(t.toUtc());
        body = attT('att_ok_body', args: {'time': time}) +
            (outcome.viaRelay ? ' — ${attT('att_ok_via')}' : '');
      case OutcomeKind.rejected:
        color = context.colors.danger;
        icon = CupertinoIcons.xmark_seal_fill;
        title = attT('att_rej_title');
        body = attT(outcome.messageKey ?? 'att_reason_wrong_code');
      case OutcomeKind.pending:
        color = context.colors.warning;
        icon = CupertinoIcons.clock_fill;
        title = attT('att_pending_title');
        body = attT('att_pending_body');
      case OutcomeKind.failed:
        color = context.colors.danger;
        icon = CupertinoIcons.exclamationmark_triangle_fill;
        title = attT(outcome.messageKey ?? 'att_err_generic');
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.4, end: 1),
          duration: const Duration(milliseconds: 450),
          curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 26),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 14.5, color: color)),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(body, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, height: 1.45)),
            ],
            if (outcome.detail != null && outcome.detail!.isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText(outcome.detail!,
                  style: TextStyle(fontSize: 10.5, color: context.colors.textMedium)),
            ],
          ]),
        ),
      ]),
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
    final primary = context.colors.primary;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: [
        Row(children: [
          Icon(CupertinoIcons.person_2_fill, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(attT('att_relay_title'),
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(attT(p.enabled ? 'att_relay_on' : 'att_relay_sub'),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
            ]),
          ),
          p.starting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
              : AppSwitch(value: p.enabled, onChanged: (v) => p.setEnabled(v)),
        ]),
        if (p.enabled && p.helped > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(attT('att_relay_helped', args: {'n': '${p.helped}'}),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: context.colors.success, fontWeight: FontWeight.w700)),
            ),
          ),
        if (p.errorKey != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(attT(p.errorKey!),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: context.colors.danger)),
            ),
          ),
        if (p.needsSettings)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: openSettings, child: Text(attT('att_err_perm_settings'))),
          ),
      ]),
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
    final c = context.colors.primary;
    return TextButton.icon(
      onPressed: () => showTeacherAttendanceSheet(context, sessionId),
      style: TextButton.styleFrom(
        foregroundColor: c,
        backgroundColor: c.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(CupertinoIcons.qrcode_viewfinder, size: 18),
      label: Text(attT('att_t_btn'),
          style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

Future<void> showTeacherAttendanceSheet(BuildContext context, int sessionId, {String? title}) {
  RelayHostProvider? host;
  try {
    host = context.read<RelayHostProvider>();
  } catch (_) {}
  final ctl = TeacherAttendanceController.instance..prepare(sessionId, host, title: title);
  return showAppModalSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // The window lives in the app-wide controller: closing the sheet leaves it running and the
    // global banner keeps the code visible while the teacher moves around the app.
    builder: (_) => ChangeNotifierProvider<TeacherAttendanceController>.value(
      value: ctl,
      child: const _TeacherSheet(),
    ),
  );
}

class _TeacherSheet extends StatelessWidget {
  const _TeacherSheet();

  Widget _label(BuildContext context, String key, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(attT(key), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
            if (hint != null)
              Text(attT(hint),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherAttendanceController>();
    final primary = context.colors.primary;
    final started = p.window != null;

    return _SheetFrame(
      header: _PremiumHeader(
        icon: CupertinoIcons.qrcode,
        title: attT('att_t_title'),
        subtitle: p.lessonTitle,
        trailing: IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(CupertinoIcons.xmark_circle_fill, color: context.colors.onHeroMuted)),
      ),
      onRefresh: started ? p.refresh : null,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!started) ...[
            _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(context, 'att_t_duration'),
            Wrap(spacing: 8, children: [
              for (final m in TeacherAttendanceController.options)
                ChoiceChip(
                  label: Text(attT('att_t_minutes', args: {'n': '$m'})),
                  selected: p.minutes == m,
                  onSelected: (_) => p.setMinutes(m),
                ),
            ]),
            _label(context, 'att_t_method', hint: 'att_t_method_hint'),
            Wrap(spacing: 8, children: [
              for (final m in TeacherAttendanceController.methods)
                ChoiceChip(
                  label: Text(attT('att_method_$m')),
                  selected: p.method == m,
                  onSelected: (_) => p.setMethod(m),
                ),
            ]),
            if (p.usesWitnesses) ...[
              _label(context, 'att_t_witnesses', hint: 'att_t_witnesses_hint'),
              Wrap(spacing: 8, children: [
                for (final n in TeacherAttendanceController.witnessOptions)
                  ChoiceChip(
                    label: Text('$n'),
                    selected: p.requiredWitnesses == n,
                    onSelected: (_) => p.setWitnesses(n),
                  ),
              ]),
            ],
            ])),
            _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(context, 'att_t_grace', hint: 'att_t_grace_hint'),
            Wrap(spacing: 8, children: [
              for (final g in TeacherAttendanceController.graceOptions)
                ChoiceChip(
                  label: Text(attT('att_t_seconds', args: {'n': '$g'})),
                  selected: p.graceSeconds == g,
                  onSelected: (_) => p.setGrace(g),
                ),
            ]),
            const SizedBox(height: 6),
            AppSwitchTile(
              value: p.allowWeb,
              onChanged: p.setAllowWeb,
              title: attT('att_t_allow_web'),
              subtitle: attT('att_t_allow_web_hint'),
            ),
            _LocationSetup(p: p),
            ])),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: p.loading ? null : () => p.open(),
                child: p.loading
                    ? SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: context.colors.onHero))
                    : Text(attT('att_t_start'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            _CodeDisplay(p: p),
            if (p.isOpen)
              TextButton.icon(
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop(); // close the sheet, then show the full-screen view
                  openAttendanceLiveOn(nav);
                },
                icon: const Icon(CupertinoIcons.fullscreen),
                label: Text(attT('att_t_fullscreen'), style: TextStyle(fontFamily: AppFonts.family)),
              ),
            if (p.host != null && (p.isOpen || p.isClosing)) ...[
              const SizedBox(height: 12),
              _TeacherRelayBanner(host: p.host!),
            ],
            const SizedBox(height: 14),
            if (p.usesCode)
              Text(attT('att_t_show'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: context.colors.textMedium)),
            if (p.isOpen)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(attT('att_t_move_hint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
              ),
            const SizedBox(height: 16),
            if (p.closed || !(p.code?.isOpen ?? true))
              Column(children: [
                _Banner(
                    icon: CupertinoIcons.lock_fill,
                    text: p.isClosing
                        ? attT('att_t_closing', args: {'n': '${p.closingLeft}'})
                        : attT(p.closed ? 'att_t_closed' : 'att_t_expired'),
                    color: context.colors.warning),
                if (!p.isClosing)
                  TextButton(
                      onPressed: p.clear,
                      child: Text(attT('att_t_new'), style: TextStyle(fontFamily: AppFonts.family))),
              ])
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.danger,
                      side: BorderSide(color: context.colors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: p.loading ? null : p.close,
                  icon: const Icon(CupertinoIcons.lock),
                  label: Text(attT('att_t_close'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
                ),
              ),
          ],
          if (p.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(p.error!.startsWith('att_') ? attT(p.error!) : p.error!,
                  style: TextStyle(color: context.colors.danger, fontFamily: AppFonts.family, fontSize: 12)),
            ),
          // The teacher's phone sets the classroom point: give the exact fix, not just an error line.
          if (p.error == 'att_err_gps_off')
            TextButton.icon(
              onPressed: () => AttendanceRadios.fix(RadioKind.gps),
              icon: const Icon(CupertinoIcons.location_solid, size: 18),
              label: Text(attT('att_turn_on_gps'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
            )
          else if (p.error == 'att_err_location_denied_forever')
            TextButton.icon(
              onPressed: openSettings,
              icon: const Icon(CupertinoIcons.lock_shield, size: 18),
              label: Text(attT('att_err_perm_settings'), style: TextStyle(fontFamily: AppFonts.family)),
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
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(attT('att_t_web_loc_title'), style: TextStyle(fontFamily: AppFonts.family)),
        content: Text(attT('att_t_web_loc_body'), style: TextStyle(fontFamily: AppFonts.family)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'browser'),
              child: Text(attT('att_t_web_loc_browser'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'mobile'),
              child: Text(attT('att_t_web_loc_mobile'))),
        ],
      ),
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
    final grey = TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppSwitchTile(
        value: p.useLocation,
        onChanged: (v) => _toggle(context, v),
        title: attT('att_t_location'),
        subtitle: attT(kIsWeb ? 'att_t_location_hint_web' : 'att_t_location_hint'),
      ),
      if (p.useLocation) ...[
        Row(children: [
          Expanded(
            child: Text(attT('att_t_distance'),
                style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
          ),
          Text(attT('att_t_meters', args: {'n': '${p.radiusM}'}),
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
        Slider(
          value: p.radiusM.toDouble(),
          min: TeacherAttendanceController.minRadius.toDouble(),
          max: TeacherAttendanceController.maxRadius.toDouble(),
          divisions: (TeacherAttendanceController.maxRadius - TeacherAttendanceController.minRadius) ~/ 10,
          label: '${p.radiusM} m',
          onChanged: (v) => p.setRadius((v / 10).round() * 10),
        ),
        Text(attT('att_t_distance_hint'), style: grey),
        if (kIsWeb && p.webLocationSource == 'mobile')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              if (p.waitingMobile)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(p.sharedFromMobile ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.info,
                    size: 18, color: p.sharedFromMobile ? context.colors.success : context.colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    attT(p.waitingMobile
                        ? 'att_t_waiting_mobile'
                        : (p.sharedFromMobile ? 'att_t_shared_found' : 'att_t_shared_missing')),
                    style: grey),
              ),
              TextButton(
                  onPressed: p.waitingMobile ? null : p.requestFromMobile,
                  child: Text(attT('att_t_ask_phone'))),
            ]),
          ),
        if (!kIsWeb)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () async {
                final ok = await p.shareLocationForWeb();
                if (ok && context.mounted) {
                  showAppNotice(attT('att_t_shared_done'));
                }
              },
              icon: Icon(p.sharedFromMobile ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.share, size: 18),
              label: Text(attT('att_t_share_for_web'), style: TextStyle(fontFamily: AppFonts.family)),
            ),
          ),
      ],
    ]);
  }
}

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.p});
  final TeacherAttendanceController p;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final rot = p.window?.rotationSeconds ?? 45;
    final code = p.code?.code ?? '------';
    final grouped = p.usesCode ? '${code.substring(0, 3)} ${code.substring(3)}' : '';
    final active = p.isOpen;

    return Column(children: [
      SizedBox(
        width: 190,
        height: 190,
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          PositionedDirectional(
            top: -6,
            end: -6,
            child: Container(
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: context.colors.success, shape: BoxShape.circle),
              child: Text('${p.code?.presentCount ?? 0}',
                  style: TextStyle(
                      color: context.colors.onHero, fontWeight: FontWeight.w900, fontSize: 17)),
            ),
          ),
          SizedBox(
            width: 190,
            height: 190,
            child: CircularProgressIndicator(
              value: active ? (p.secondsLeft / rot).clamp(0.0, 1.0) : 0,
              strokeWidth: 7,
              color: primary,
              backgroundColor: primary.withValues(alpha: 0.12),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (grouped.isEmpty)
              Icon(CupertinoIcons.person_3_fill, size: 54, color: active ? primary : context.colors.textLight)
            else
            Text(grouped,
                style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: active ? null : context.colors.textLight)),
            const SizedBox(height: 4),
            if (active)
              Text(attT('att_t_next_code', args: {'n': '${p.secondsLeft}'}),
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 11.5, color: context.colors.textMedium)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: context.colors.success.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.person_3_fill, color: context.colors.success, size: 20),
          const SizedBox(width: 10),
          Text('${attT('att_t_present')}: ${p.code?.presentCount ?? 0}',
              style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 16, color: context.colors.success)),
        ]),
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
    final c = context.colors.primary;
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () => showStudentCheckInSheet(context, courseId: courseId, title: title),
        style: TextButton.styleFrom(
          foregroundColor: c,
          backgroundColor: c.withValues(alpha: 0.10),
          padding: const EdgeInsets.symmetric(vertical: 11),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark, size: 18),
        label: Text(attT('att_btn_checkin'),
            style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800, fontSize: 13.5)),
      ),
    );
  }
}


/// Shows whether THIS phone is currently advertising to nearby classmates.
class _VisibleBanner extends StatelessWidget {
  const _VisibleBanner({required this.host});
  final RelayHostProvider host;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: host,
        builder: (_, _) {
          final on = host.running;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Banner(
              icon: on ? CupertinoIcons.dot_radiowaves_right : CupertinoIcons.eye_slash,
              text: on
                  ? attT('att_visible_yes')
                  : '${attT('att_visible_no')}${host.hostError == null ? '' : ' (${host.hostError})'}',
              color: on ? context.colors.success : context.colors.warning,
            ),
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
        builder: (_, _) => _Banner(
          icon: host.running ? CupertinoIcons.dot_radiowaves_right : CupertinoIcons.eye_slash,
          text: host.running
              ? '${attT('att_t_relay_on')}${host.helped > 0 ? ' • ${host.helped}' : ''}'
              : '${attT('att_t_relay_off')}${host.hostError == null ? '' : ' (${host.hostError})'}',
          color: host.running ? context.colors.success : context.colors.warning,
        ),
      );
}
