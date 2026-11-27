// lib/features/attendance/student_ui/student_checkin_view.dart
//
// The student's check-in sheet (Stu1Learn sheet=checkin, state=done) over the SAME StudentCheckInProvider as before
// (the code, the location, the offline queue, the invisible relay all stay): the code when the teacher asks for one,
// then the ring "نسجّل حضورك..." with "خلك في الصفحة ثواني بس" and إلغاء, then the drawn tick (M2) with the burst
// (M11 attendanceDone). The stages behind it (network, relay, witnesses …) are never named to the student (O-6,
// DESIGN_SYSTEM §1.1 rule 4).
//
// Owner 2026-11-27: two more ways in, under the code — "scan the QR" (phones: the same camera scanner as the
// organization join, mobile_scanner; the QR carries the window's 6-digit code, so it goes the same check-in route) and
// "with a classmate's help" (the nearby relay, forced; the classmate is never named).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/features/attendance/attendance_permissions.dart' show relayLinkSupported;
import 'package:flutter_education_app/features/attendance/attendance_strings.dart' show attT;
import 'package:flutter_education_app/features/org/org_join_scan.dart' show joinScannerAvailable, openQrScanner;
import 'package:flutter_education_app/features/attendance/relay_host_provider.dart';
import 'package:flutter_education_app/features/attendance/student_checkin_provider.dart';

/// Where the check-in is.
enum StudentCheckInPhase { code, running, done, failed }

/// The ring's size.
const double _kRing = 112;

/// The provider's failure keys that name the relay, the witnesses or Bluetooth → neutral texts that only say what to
/// do (the privacy contract: a student never reads about classmates; O-6).
const Map<String, String> kStudentCheckInNeutralErrors = {
  'att_err_no_relay': 'sb_att_no_relay',
  'att_err_witnesses': 'sb_att_witnesses',
  'att_err_bluetooth_off': 'sb_att_bluetooth_off',
};

/// The text of a failed check-in for the student (null key → the generic failure).
String studentCheckInErrorText(String? messageKey) {
  final key = messageKey ?? 'att_err_generic';
  return attT(kStudentCheckInNeutralErrors[key] ?? key);
}

/// The 6-digit attendance code inside a scanned QR (the teacher's projector / phone QR is the bare code; a link with
/// `?code=` is read too), or null to keep scanning.
String? parseAttendanceQr(String? raw) {
  final s = (raw ?? '').trim();
  if (RegExp(r'^\d{6}$').hasMatch(s)) return s;
  final uri = s.contains('://') ? Uri.tryParse(s) : null;
  final q = uri?.queryParameters['code'] ?? uri?.queryParameters['att_code'];
  return q != null && RegExp(r'^\d{6}$').hasMatch(q.trim()) ? q.trim() : null;
}

/// The sheet (kit sheet: a bottom sheet on phones, a dialog on wide windows). Resolves when it closes.
Future<void> showStudentAttendCheckIn(BuildContext context, {int? sessionId, int? courseId, String? title}) {
  RelayHostProvider? host;
  try {
    host = context.read<RelayHostProvider>();
  } catch (_) {}
  return showAppSheet<void>(
    context,
    (_) => AppAreaScope(
      area: AppArea.learn,
      budget: false,
      child: ChangeNotifierProvider(
        create: (_) => StudentCheckInProvider(sessionId: sessionId, courseId: courseId, host: host),
        child: const _CheckInHost(),
      ),
    ),
  );
}

class _CheckInHost extends StatefulWidget {
  const _CheckInHost();

  @override
  State<_CheckInHost> createState() => _CheckInHostState();
}

class _CheckInHostState extends State<_CheckInHost> {
  final _code = TextEditingController();
  bool _ready = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<StudentCheckInProvider>();
    p.warmUp().whenComplete(() {
      if (!mounted) return;
      setState(() => _ready = true);
      // no code to type: one tap already asked for it, go
      if (!p.needsCode) _submit();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit({bool viaClassmate = false}) {
    setState(() => _started = true);
    context.read<StudentCheckInProvider>().submit(_code.text, viaClassmate: viaClassmate);
  }

  Future<void> _scan() async {
    final code = await openQrScanner(
      context,
      parse: parseAttendanceQr,
      title: 'ow_att_scan_title'.tr,
      prompt: 'ow_att_scan_prompt'.tr,
      rejected: 'ow_att_scan_rejected'.tr,
    );
    if (code == null || !mounted) return;
    _code.text = code;
    _submit();
  }

  void _viaClassmate() {
    context.read<StudentCheckInProvider>().reset();
    _submit(viaClassmate: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<StudentCheckInProvider>();
    final o = p.outcome;
    final StudentCheckInPhase phase;
    if (o != null && (o.kind == OutcomeKind.accepted || o.kind == OutcomeKind.pending)) {
      phase = StudentCheckInPhase.done;
    } else if (o != null) {
      phase = StudentCheckInPhase.failed;
    } else if (p.busy || !_ready || _started) {
      phase = StudentCheckInPhase.running;
    } else {
      phase = StudentCheckInPhase.code;
    }
    return StudentCheckInView(
      phase: phase,
      pending: o?.kind == OutcomeKind.pending,
      doneAt: phase == StudentCheckInPhase.done ? AppTime.time(DateTime.now().toUtc()) : null,
      error: phase == StudentCheckInPhase.failed ? studentCheckInErrorText(o?.messageKey) : null,
      code: _code,
      onSubmit: _submit,
      onScan: joinScannerAvailable ? _scan : null,
      onViaClassmate: relayLinkSupported ? _viaClassmate : null,
      onRetry: () {
        p.reset();
        setState(() => _started = false);
        if (!p.needsCode) _submit();
      },
      onClose: () => Navigator.of(context).maybePop(),
    );
  }
}

/// The sheet's body for a [phase], plain values (pumped by the tests and goldens).
class StudentCheckInView extends StatelessWidget {
  const StudentCheckInView({
    super.key,
    required this.phase,
    required this.onClose,
    this.code,
    this.onSubmit,
    this.onRetry,
    this.onScan,
    this.onViaClassmate,
    this.error,
    this.pending = false,
    this.doneAt,
  });

  final StudentCheckInPhase phase;
  final TextEditingController? code;
  final VoidCallback? onSubmit;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  /// Scan the teacher's QR (null on the web: no camera scanner there).
  final VoidCallback? onScan;

  /// Check in with a classmate's help: the nearby relay (null where the relay can't run).
  final VoidCallback? onViaClassmate;
  final String? error;

  /// Saved on the phone, sent when the internet is back: still "done" for the student.
  final bool pending;

  /// The check-in's time ("٧:٣٢ م"), under the tick.
  final String? doneAt;

  @override
  Widget build(BuildContext context) => AppSheetContent(
        title: 'sb_att_sheet_title'.tr,
        icon: Icons.how_to_reg_rounded,
        tone: AppTone.success,
        children: [
          AnimatedSwitcher(
            duration: AppMotion.of(context).base,
            child: KeyedSubtree(key: ValueKey(phase), child: _body(context)),
          ),
        ],
      );

  Widget _body(BuildContext context) {
    final c = context.colors;
    final ok = c.kit.ok;
    switch (phase) {
      case StudentCheckInPhase.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppField(
              controller: code ?? TextEditingController(),
              label: 'sb_att_code_label'.tr,
              hint: '••••••',
              icon: Icons.pin_rounded,
              keyboard: TextInputType.number,
              ltr: true,
              maxLength: 6,
              onSubmitted: (_) => onSubmit?.call(),
            ),
            const SizedBox(height: AppSpace.md),
            AppButton.hot(label: 'sb_att_check_in'.tr, icon: Icons.check_rounded, expand: true, onPressed: onSubmit),
            if (onScan != null) ...[
              const SizedBox(height: AppSpace.sm),
              AppButton.secondary(
                key: const ValueKey('att.scan_qr'),
                label: 'ow_att_scan_qr'.tr,
                icon: Icons.qr_code_scanner_rounded,
                expand: true,
                onPressed: onScan,
              ),
            ],
            if (onViaClassmate != null) _ClassmateOption(onTap: onViaClassmate!),
          ],
        );
      case StudentCheckInPhase.running:
        return Column(
          children: [
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: _kRing,
              height: _kRing,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CircularProgressIndicator(
                      strokeWidth: AppSpace.xs,
                      color: ok.color,
                      backgroundColor: ok.tint,
                      strokeCap: StrokeCap.round,
                      semanticsLabel: 'sb_att_running'.tr,
                    ),
                  ),
                  Icon(Icons.person_outline_rounded, size: AppIconSize.hero, color: ok.ink),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text('sb_att_running'.tr, textAlign: TextAlign.center, style: AppType.pageTitle(context)),
            const SizedBox(height: AppSpace.xs),
            Text('sb_att_stay'.tr, textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
            const SizedBox(height: AppSpace.lg),
            AppButton.secondary(label: 'cancel'.tr, expand: true, onPressed: onClose),
          ],
        );
      case StudentCheckInPhase.done:
        return Padding(
          padding: const EdgeInsets.only(top: AppSpace.md),
          child: AppSuccess(
            title: 'sb_att_done_title'.tr,
            message: pending ? 'sb_att_done_pending'.tr : (doneAt == null ? null : 'sb_att_done_at'.tr.replaceAll('{time}', doneAt!)),
            actionLabel: 'sb_att_done_ok'.tr,
            onAction: onClose,
            burst: BurstMoment.attendanceDone,
          ),
        );
      case StudentCheckInPhase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppErrorState(title: 'sb_att_failed'.tr, message: error, onRetry: onRetry, compact: true),
            if (onViaClassmate != null) _ClassmateOption(onTap: onViaClassmate!),
          ],
        );
    }
  }
}

/// The second way in: a classmate's phone carries the check-in (no internet needed). Never names who.
class _ClassmateOption extends StatelessWidget {
  const _ClassmateOption({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppButton.tonal(
            key: const ValueKey('att.via_classmate'),
            label: 'ow_att_via_classmate'.tr,
            icon: Icons.people_alt_outlined,
            expand: true,
            onPressed: onTap,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'ow_att_via_classmate_hint'.tr,
            textAlign: TextAlign.center,
            style: AppType.meta(context),
          ),
        ]),
      );
}
