/// features/attendance/attendance_widgets.dart
///
/// Drop-in UI for relay-based attendance:
///   Student : [AttendanceStudentButton]  -> bottom sheet with code entry, live progress, verified result
///   Student : [RelayHostTile]            -> "Help classmates" switch (online phones act as relay)
///   Teacher : [AttendanceTeacherButton]  -> bottom sheet with the rotating code + live present counter
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import 'attendance_permissions.dart';
import 'attendance_strings.dart';
import 'relay_host_provider.dart';
import 'student_checkin_provider.dart';
import 'teacher_attendance_provider.dart';

const _ok = Color(0xFF2E9E6B);
const _bad = Color(0xFFD64545);
const _warn = Color(0xFFE0A030);

// ════════════════════════════════════════════════════════════════════════════
//  STUDENT
// ════════════════════════════════════════════════════════════════════════════

/// Put this on a lesson card (e.g. inside the lessons / live tab item).
class AttendanceStudentButton extends StatelessWidget {
  const AttendanceStudentButton({super.key, required this.sessionId, this.compact = false});
  final int sessionId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors.primary;
    return TextButton.icon(
      onPressed: () => showStudentCheckInSheet(context, sessionId),
      style: TextButton.styleFrom(
        foregroundColor: c,
        backgroundColor: c.withValues(alpha: 0.10),
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: compact ? 6 : 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      icon: const Icon(CupertinoIcons.person_crop_circle_badge_checkmark, size: 18),
      label: Text(attT('att_btn_checkin'),
          style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

Future<void> showStudentCheckInSheet(BuildContext context, int sessionId) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => StudentCheckInProvider(sessionId: sessionId)..warmUp(),
      child: const _StudentSheet(),
    ),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2))),
              child,
            ]),
          ),
        ),
      );
}

class _StudentSheet extends StatefulWidget {
  const _StudentSheet();
  @override
  State<_StudentSheet> createState() => _StudentSheetState();
}

class _StudentSheetState extends State<_StudentSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentCheckInProvider>();
    final o = p.outcome;
    final primary = context.colors.primary;
    final finished = o != null && o.kind != OutcomeKind.failed && o.kind != OutcomeKind.pending;

    return _SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(CupertinoIcons.dot_radiowaves_left_right, size: 34, color: primary),
        const SizedBox(height: 8),
        Text(attT('att_sheet_title'),
            style: const TextStyle(fontFamily: 'tajawal', fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(attT('att_sheet_sub'),
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        if (p.online != null)
          _Banner(
            icon: p.online! ? CupertinoIcons.wifi : CupertinoIcons.antenna_radiowaves_left_right,
            text: attT(p.online! ? 'att_online_direct' : 'att_offline_relay'),
            color: p.online! ? _ok : _warn,
          ),
        if (p.online == true && !p.busy && o == null) const RelayHostTile(),
        if (!finished) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            enabled: !p.busy,
            autofocus: true,
            maxLength: 6,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 30, letterSpacing: 10, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              labelText: attT('att_code_hint'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onSubmitted: (v) => p.submit(v),
          ),
        ],
        if (p.busy || o != null) ...[
          const SizedBox(height: 12),
          for (final s in Stage.values)
            if (p.stages[s] != StageState.skipped) _StageRow(stage: s, state: p.stages[s]!),
        ],
        if (o != null) ...[
          const SizedBox(height: 14),
          _OutcomeCard(outcome: o),
          if (o.needsSettings)
            TextButton(onPressed: openSettings, child: Text(attT('att_err_perm_settings'))),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: p.busy
                ? null
                : finished
                    ? () => Navigator.of(context).maybePop()
                    : () => p.submit(_ctrl.text),
            child: p.busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(attT(finished ? 'att_done' : (o == null ? 'att_submit' : 'att_retry')),
                    style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 15)),
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
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: color, fontWeight: FontWeight.w700))),
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
    Stage.send: 'att_stage_send',
    Stage.server: 'att_stage_server',
  };

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (state) {
      StageState.ok => const Icon(CupertinoIcons.checkmark_circle_fill, color: _ok, size: 20),
      StageState.failed => const Icon(CupertinoIcons.xmark_circle_fill, color: _bad, size: 20),
      StageState.active => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
      _ => Icon(CupertinoIcons.circle, color: Colors.grey.shade400, size: 20),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        icon,
        const SizedBox(width: 10),
        Text(attT(_labels[stage]!),
            style: TextStyle(
                fontFamily: 'tajawal',
                fontSize: 13,
                color: state == StageState.waiting ? Colors.grey.shade500 : null)),
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
        color = _ok;
        icon = CupertinoIcons.checkmark_seal_fill;
        title = attT('att_ok_title');
        final t = outcome.result?.confirmedLocal;
        final time = t == null
            ? ''
            : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        body = attT('att_ok_body', args: {'time': time}) +
            (outcome.viaRelay ? ' — ${attT('att_ok_via')}' : '');
      case OutcomeKind.rejected:
        color = _bad;
        icon = CupertinoIcons.xmark_seal_fill;
        title = attT('att_rej_title');
        body = attT(outcome.messageKey ?? 'att_reason_wrong_code');
      case OutcomeKind.pending:
        color = _warn;
        icon = CupertinoIcons.clock_fill;
        title = attT('att_pending_title');
        body = attT('att_pending_body');
      case OutcomeKind.failed:
        color = _bad;
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
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 14.5, color: color)),
            if (body != null) ...[
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5, height: 1.45)),
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
                  style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(attT(p.enabled ? 'att_relay_on' : 'att_relay_sub'),
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: Colors.grey.shade600)),
            ]),
          ),
          p.starting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2))
              : Switch.adaptive(value: p.enabled, onChanged: (v) => p.setEnabled(v)),
        ]),
        if (p.enabled && p.helped > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(attT('att_relay_helped', args: {'n': '${p.helped}'}),
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 12, color: _ok, fontWeight: FontWeight.w700)),
            ),
          ),
        if (p.errorKey != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(attT(p.errorKey!),
                  style: const TextStyle(fontFamily: 'tajawal', fontSize: 12, color: _bad)),
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
          style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

Future<void> showTeacherAttendanceSheet(BuildContext context, int sessionId) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false, // closing the sheet must not silently leave the window open
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider(
        create: (_) => TeacherAttendanceProvider(sessionId: sessionId),
        child: const _TeacherSheet(),
      ),
    );

class _TeacherSheet extends StatelessWidget {
  const _TeacherSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherAttendanceProvider>();
    final primary = context.colors.primary;
    final started = p.window != null;

    return _SheetFrame(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text(attT('att_t_title'),
                style: const TextStyle(fontFamily: 'tajawal', fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(CupertinoIcons.xmark_circle_fill, color: Colors.grey)),
        ]),
        if (!started) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(attT('att_t_duration'),
                style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final m in TeacherAttendanceProvider.options)
              ChoiceChip(
                label: Text(attT('att_t_minutes', args: {'n': '$m'})),
                selected: p.minutes == m,
                onSelected: (_) => p.setMinutes(m),
              ),
          ]),
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
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(attT('att_t_start'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          _CodeDisplay(p: p),
          const SizedBox(height: 14),
          Text(attT('att_t_show'),
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          if (p.closed || !(p.code?.isOpen ?? true))
            _Banner(
                icon: CupertinoIcons.lock_fill,
                text: attT(p.closed ? 'att_t_closed' : 'att_t_expired'),
                color: _warn)
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: _bad,
                    side: const BorderSide(color: _bad),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: p.loading ? null : p.close,
                icon: const Icon(CupertinoIcons.lock),
                label: Text(attT('att_t_close'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800)),
              ),
            ),
        ],
        if (p.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(p.error!, style: const TextStyle(color: _bad, fontFamily: 'tajawal', fontSize: 12)),
          ),
      ]),
    );
  }
}

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.p});
  final TeacherAttendanceProvider p;

  @override
  Widget build(BuildContext context) {
    final primary = context.colors.primary;
    final rot = p.window?.rotationSeconds ?? 45;
    final code = p.code?.code ?? '------';
    final grouped = '${code.substring(0, 3)} ${code.substring(3)}';
    final active = p.isOpen;

    return Column(children: [
      SizedBox(
        width: 190,
        height: 190,
        child: Stack(alignment: Alignment.center, children: [
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
            Text(grouped,
                style: TextStyle(
                    fontSize: 38,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: active ? null : Colors.grey)),
            const SizedBox(height: 4),
            if (active)
              Text(attT('att_t_next_code', args: {'n': '${p.secondsLeft}'}),
                  style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: Colors.grey.shade600)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(color: _ok.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(CupertinoIcons.person_3_fill, color: _ok, size: 20),
          const SizedBox(width: 10),
          Text('${attT('att_t_present')}: ${p.code?.presentCount ?? 0}',
              style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 16, color: _ok)),
        ]),
      ),
    ]);
  }
}
