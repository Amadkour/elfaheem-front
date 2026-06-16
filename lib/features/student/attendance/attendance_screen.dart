/// attendance/attendance_screen.dart
/// Student attendance widget — shown inside session detail.
/// Shows check-in / check-out buttons and the student's own attendance record.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';
import '../../../config/theme/app_theme.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../models.dart';
import 'attendance_provider.dart';

class StudentAttendanceWidget extends StatelessWidget {
  final SessionModel session;

  const StudentAttendanceWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentAttendanceProvider>();
    final inSession = provider.isCheckedIn;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: inSession
            ? context.themeConfig.danger.withValues(alpha: 0.06)
            : context.themeConfig.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(context.colors.radiusMedium),
        border: Border.all(
            color: (inSession ? context.themeConfig.danger : context.themeConfig.primary)
                .withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.fact_check_rounded,
              color: inSession ? context.themeConfig.danger : context.themeConfig.primary,
              size: 20),
          const SizedBox(width: 8),
          Text('سجل الحضور',
              style: context.colors.h3.copyWith(
                  color: inSession
                      ? context.themeConfig.danger
                      : context.themeConfig.primary)),
        ]),
        const SizedBox(height: 12),
        // Record summary
        if (provider.activeRecord != null) ...[
          _RecordRow('وقت الدخول', _fmt(provider.activeRecord!.checkInAt),
              Icons.login_rounded, context.themeConfig.success),
          if (provider.activeRecord!.checkOutAt != null) ...[
            const SizedBox(height: 6),
            _RecordRow('وقت الخروج', _fmt(provider.activeRecord!.checkOutAt),
                Icons.logout_rounded, context.themeConfig.danger),
          ],
          const SizedBox(height: 12),
        ],
        // Action button
        GestureDetector(
          onTap: () => _toggle(context, provider),
          child: Container(
              height: 44,
              decoration: BoxDecoration(
                  gradient: inSession
                      ? LinearGradient(
                          colors: [context.themeConfig.danger, Color(0xFFFF6B6B)])
                      : context.themeConfig.linearPrimary,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: inSession ? [] : context.themeConfig.primaryShadow(isDark:context.colors.isDark)),
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
                      Text(inSession ? 'تسجيل المغادرة' : 'تسجيل الحضور',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              fontFamily: 'bahji'))
                    ])),
        ),
      ]),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ok
                  ? (p.isCheckedIn ? 'تم تسجيل مغادرتك' : 'تم تسجيل حضورك ✓')
                  : 'حدث خطأ',
              style: TextStyle(fontFamily: 'bahji', color: Colors.white)),
          backgroundColor: ok ? context.themeConfig.success : context.themeConfig.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
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
                color: context.themeConfig.textDark, fontWeight: FontWeight.w700))
      ]);
}
