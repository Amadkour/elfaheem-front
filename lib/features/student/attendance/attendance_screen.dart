/// attendance/attendance_screen.dart
/// Student attendance widget — shown inside session detail.
/// Shows check-in / check-out buttons and the student's own attendance record.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../models.dart';
import 'attendance_provider.dart';
import 'package:flutter_education_app/design/app_icons.dart';

class StudentAttendanceWidget extends StatelessWidget {
  final SessionModel session;

  const StudentAttendanceWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentAttendanceProvider>();
    final inSession = provider.isCheckedIn;
    final c = context.colors;

    // Warm Editorial: a paper block while you are out, the emerald block once you are in (present = done / right).
    return ParentComponent(
        featureKey: 'attendance',
        child: AppBlock(
          tone: inSession ? AppBlockTone.emerald : AppBlockTone.paper,
          padding: const EdgeInsets.all(AppSpace.md),
          child: Builder(builder: (context) {
            final b = AppBlock.colorsOf(context);
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(inSession ? Icons.how_to_reg_rounded : Icons.fact_check_rounded,
                    color: b.accentInk(c.primary), size: AppIconSize.md),
                AppSpace.gapXs,
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('att_title'.tr,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: b.ink)),
                  ),
                ),
              ]),
              // Record summary
              if (provider.activeRecord != null) ParentComponent(
                  featureKey: 'attendance.record',
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpace.sm),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _RecordRow('att_check_in_time'.tr, _fmt(provider.activeRecord!.checkInAt),
                          DirIcons.login, c.success),
                      if (provider.activeRecord!.checkOutAt != null) ...[
                        const SizedBox(height: AppSpace.xxs),
                        _RecordRow('att_check_out_time'.tr, _fmt(provider.activeRecord!.checkOutAt),
                            DirIcons.logout, c.danger),
                      ],
                    ]),
                  )),
              AppSpace.gapMd,
              // Action button
              ParentComponent(
                  featureKey: 'attendance.action',
                  child: inSession
                      ? AppButton.danger(
                          dangerOutline: true,
                          expand: true,
                          busy: provider.isLoading,
                          icon: DirIcons.logout,
                          label: 'att_check_out'.tr,
                          onPressed: () => _toggle(context, provider))
                      : AppButton.primary(
                          expand: true,
                          busy: provider.isLoading,
                          icon: DirIcons.login,
                          label: 'att_check_in'.tr,
                          onPressed: () => _toggle(context, provider))),
            ]);
          }),
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
  Widget build(BuildContext context) {
    final b = AppBlock.colorsOf(context);
    return Row(children: [
      Icon(icon, size: AppIconSize.sm, color: b.accentInk(color)),
      AppSpace.gapXs,
      Expanded(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: b.muted)),
      ),
      AppSpace.gapXs,
      Text(value, style: AppType.figure(context).copyWith(color: b.ink)),
    ]);
  }
}
