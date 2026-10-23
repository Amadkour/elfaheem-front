/// attendance/attendance_screen.dart
/// Student attendance widget — shown inside session detail.
/// Shows check-in / check-out buttons and the student's own attendance record.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../models.dart';
import 'attendance_provider.dart';
import 'package:flutter_education_app/design/app_notice.dart';

class StudentAttendanceWidget extends StatelessWidget {
  final SessionModel session;

  const StudentAttendanceWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentAttendanceProvider>();
    final inSession = provider.isCheckedIn;

    return ParentComponent(
        featureKey: 'attendance',
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: inSession
                ? context.colors.danger.withValues(alpha: 0.06)
                : context.colors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(context.colors.radiusMedium),
            border: Border.all(
                color: (inSession ? context.colors.danger : context.colors.primary)
                    .withValues(alpha: 0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.fact_check_rounded,
                  color: inSession ? context.colors.danger : context.colors.primary,
                  size: 20),
              const SizedBox(width: 8),
              Text('att_title'.tr,
                  style: context.colors.h3.copyWith(
                      color: inSession
                          ? context.colors.danger
                          : context.colors.primary)),
            ]),
            const SizedBox(height: 12),
            // Record summary
            if (provider.activeRecord != null) ParentComponent(
                featureKey: 'attendance.record',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _RecordRow('att_check_in_time'.tr, _fmt(provider.activeRecord!.checkInAt),
                      Icons.login_rounded, context.colors.success),
                  if (provider.activeRecord!.checkOutAt != null) ...[
                    const SizedBox(height: 6),
                    _RecordRow('att_check_out_time'.tr, _fmt(provider.activeRecord!.checkOutAt),
                        Icons.logout_rounded, context.colors.danger),
                  ],
                  const SizedBox(height: 12),
                ])),
            // Action button
            ParentComponent(
                featureKey: 'attendance.action',
                child: GestureDetector(
                  onTap: () => _toggle(context, provider),
                  child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                          gradient: inSession
                              ? LinearGradient(
                              colors: [context.colors.danger, Color(0xFFFF6B6B)])
                              : context.colors.primaryGradient,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: inSession ? [] : context.colors.primaryShadow),
                      child: provider.isLoading
                          ? const Center(
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2)))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                            inSession
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                            color: Colors.white,
                            size: 18),
                        const SizedBox(width: 8),
                        Text(inSession ? 'att_check_out'.tr : 'att_check_in'.tr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                fontFamily: 'bahji'))
                      ])),
                )),
          ]),
        ));
  }

  Future<void> _toggle(
      BuildContext context, StudentAttendanceProvider p) async {
    bool ok;
    if (p.isCheckedIn) {
      ok = await p.checkOut(session.id);
    } else {
      ok = await p.checkIn(session.id);
    }
    if (context.mounted) {
      showAppNotice(ok
                  ? (p.isCheckedIn ? 'att_checked_out_msg'.tr : 'att_checked_in_msg'.tr)
                  : 'att_error'.tr, error: true);
    }
  }

  String _fmt(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = (iso).toLocalSaTime;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _RecordRow extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _RecordRow(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: color),
    const SizedBox(width: 6),
    Text('$label: ', style: context.colors.caption),
    Text(value,
        style: context.colors.caption.copyWith(
            color: context.colors.textDark, fontWeight: FontWeight.w700))
  ]);
}