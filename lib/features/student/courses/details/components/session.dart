import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../config/app_theme.dart';
import '../../../../auth/auth_provider.dart';
import '../../../../teacher/sessions/live/prejoin.dart';
import '../../../models.dart';
import '../../../sessions/sessions_provider.dart';
import '../course_detail_provider.dart';

// ── Sessions tab ──────────────────────────────────────────────────────────────

class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider  = context.watch<CourseDetailProvider>();
    final sessions  = provider.course.sessions;
    final completed = sessions.where((s) => s.isCompleted).length;
    final total     = sessions.length;

    if (provider.isLoadingSession) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppTheme.primary),
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.video_library_outlined,
                    size: 36, color: AppTheme.primary),
              ),
              const SizedBox(height: 14),
              const Text('لا توجد دروس بعد', style: AppTheme.body),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Progress summary banner
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: _ProgressBanner(
              completed: completed,
              total: total,
              progress: total > 0 ? completed / total : 0.0),
        ),

        ListView.builder(
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: sessions.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: StudentSessionCard(
              session: sessions[i],
              isCheckedIn: false,
              onCheckIn: () {},
              onCheckOut: () {},
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  final int completed, total;
  final double progress;

  const _ProgressBanner({
    required this.completed,
    required this.total,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
    decoration: BoxDecoration(
      gradient: AppTheme.primaryGradient,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primary.withOpacity(0.32),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      children: [
        // Circular progress
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 54,
              height: 54,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 5,
                backgroundColor: Colors.white.withOpacity(0.25),
                valueColor:
                const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'تقدمك في الكورس',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'أكملت $completed من $total محاضرة',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withOpacity(0.25),
                  valueColor:
                  const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ── Student session card ──────────────────────────────────────────────────────

class StudentSessionCard extends StatelessWidget {
  final SessionModel session;
  final bool isCheckedIn;
  final VoidCallback onCheckIn, onCheckOut;

  const StudentSessionCard({
    super.key,
    required this.session,
    required this.isCheckedIn,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    final isDone = session.isCompleted;
    final isLive = session.isLive;

    Color? borderColor;
    if (isDone) {
      borderColor = AppTheme.accent2.withOpacity(0.35);
    } else if (isLive && isCheckedIn) {
      borderColor = AppTheme.danger.withOpacity(0.4);
    }

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppTheme.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(session: session),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: AppTheme.h3.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _MetaRow(session: session),
                    const SizedBox(height: 8),
                    _PillRow(
                      isLive: isLive,
                      isCompleted: isDone,
                      hasRecording: session.hasRecording,
                      isCheckedIn: isCheckedIn,
                    ),
                    if (isLive && !isDone) ...[
                      const SizedBox(height: 10),
                      _AttendanceRow(
                        isCheckedIn: isCheckedIn,
                        onCheckIn: onCheckIn,
                        onCheckOut: onCheckOut,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    final provider = context.read<StudentSessionsProvider>();
    if (session.isLive) {
      final resp = await provider.joinLive(session.id);
      if (resp == null || !context.mounted) return;
      _snack(context, 'جاري فتح الحصة المباشرة…',
          const Color(0xFF185FA5));
      final user = context.read<AuthProvider>().currentUser;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreJoinPage(
            args: JoinArgs(
              isTeacher: user!.isTeacher,
              userId: user.id,
              userName: user.name,
              sessionId: session.id,
              courseId: session.courseId,
              onEnd: () async => await context
                  .read<StudentSessionsProvider>()
                  .checkOut(session.id),
              onStart: () async => await context
                  .read<StudentSessionsProvider>()
                  .joinLive(session.id),
            ),
          ),
        ),
      );
      return;
    }
    await provider.trackView(session.id);
    if (session.hasRecording && context.mounted) {
      _snack(context, 'فتح التسجيل…', AppTheme.primary);
      return;
    }
    if (!session.isCompleted && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _MarkCompleteDialog(sessionName: session.name),
      );
      if (ok == true && context.mounted) {
        await provider.markComplete(session.id);
        _snack(context, 'تم تحديد الدرس كمكتمل ✓', AppTheme.accent2);
      }
    }
  }

  void _snack(BuildContext ctx, String msg, Color color) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final SessionModel session;
  const _Thumbnail({required this.session});

  @override
  Widget build(BuildContext context) {
    final isLive = session.isLive;
    final isDone = session.isCompleted;
    final gradient = isLive
        ? const LinearGradient(
      colors: [Color(0xFF7A1010), Color(0xFFC43030)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    )
        : const LinearGradient(
      colors: [Color(0xFF1E1B5E), Color(0xFF3B3399)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    final badgeBg =
    isLive ? const Color(0xFFD85A30) : AppTheme.primary;

    return SizedBox(
      width: 92,
      height: 98,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            child: Container(
              width: 92,
              height: 98,
              decoration: BoxDecoration(gradient: gradient),
              child: Center(
                child: Opacity(
                  opacity: 0.22,
                  child: Icon(
                    isLive
                        ? Icons.sensors_rounded
                        : Icons.play_circle_fill_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Order badge
          Positioned(
            top: 9,
            right: 9,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: badgeBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: badgeBg.withOpacity(0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  session.order.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Cairo',
                    height: 1,
                  ),
                ),
              ),
            ),
          ),

          // Done check
          if (isDone)
            Positioned(
              bottom: 9,
              right: 9,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.accent2,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent2.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Meta row ──────────────────────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final SessionModel session;
  const _MetaRow({required this.session});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 4,
    children: [
      _MetaItem(
        icon: Icons.access_time_rounded,
        label: '${session.durationMinutes} دقيقة',
        bg: const Color(0xFFFAEEDA),
        color: const Color(0xFFBA7517),
      ),
      if ((session.scheduledAt ?? '').isNotEmpty)
        _MetaItem(
          icon: Icons.calendar_month_rounded,
          label: session.scheduledLabel,
          bg: const Color(0xFFE6F1FB),
          color: const Color(0xFF185FA5),
        ),
    ],
  );
}

class _MetaItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg, color;
  const _MetaItem(
      {required this.icon,
        required this.label,
        required this.bg,
        required this.color});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 18,
        decoration:
        BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Icon(icon, size: 11, color: color),
      ),
      const SizedBox(width: 5),
      Text(label, style: AppTheme.caption.copyWith(fontSize: 11)),
    ],
  );
}

// ── Pill row ──────────────────────────────────────────────────────────────────

class _PillRow extends StatelessWidget {
  final bool isLive, isCompleted, hasRecording, isCheckedIn;
  const _PillRow({
    required this.isLive,
    required this.isCompleted,
    required this.hasRecording,
    required this.isCheckedIn,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 5,
    children: [
      _Pill(
        icon: isLive ? Icons.sensors_rounded : Icons.play_arrow_rounded,
        label: isLive ? 'مباشر' : 'مسجّل',
        bg: isLive
            ? const Color(0xFFFAECE7)
            : const Color(0xFFE6F1FB),
        fg: isLive
            ? const Color(0xFF993C1D)
            : const Color(0xFF185FA5),
      ),
      if (isCompleted)
        const _Pill(
          icon: Icons.check_circle_rounded,
          label: 'مكتمل',
          bg: Color(0xFFEAF3DE),
          fg: Color(0xFF3B6D11),
        ),
      if (isLive && isCheckedIn && !isCompleted)
        const _Pill(
          icon: Icons.circle,
          label: 'حضور',
          bg: Color(0xFFFAECE7),
          fg: Color(0xFF993C1D),
        ),
      if (hasRecording && !isCompleted)
        const _Pill(
          icon: Icons.fiber_manual_record_rounded,
          label: 'تسجيل متاح',
          bg: Color(0xFFFAEEDA),
          fg: Color(0xFF854F0B),
        ),
    ],
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg, fg;
  const _Pill(
      {required this.icon,
        required this.label,
        required this.bg,
        required this.fg});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(8)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: fg,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    ),
  );
}

// ── Attendance row ────────────────────────────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  final bool isCheckedIn;
  final VoidCallback onCheckIn, onCheckOut;
  const _AttendanceRow({
    required this.isCheckedIn,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) => isCheckedIn
      ? _AttendBtn(
    label: 'تسجيل المغادرة',
    icon: Icons.logout_rounded,
    fg: AppTheme.danger,
    bg: AppTheme.danger.withOpacity(0.09),
    border: AppTheme.danger.withOpacity(0.35),
    onTap: onCheckOut,
  )
      : _AttendBtn(
    label: 'تسجيل الحضور',
    icon: Icons.login_rounded,
    fg: AppTheme.accent2,
    bg: AppTheme.accent2.withOpacity(0.09),
    border: AppTheme.accent2.withOpacity(0.35),
    onTap: onCheckIn,
  );
}

class _AttendBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color fg, bg, border;
  final VoidCallback onTap;
  const _AttendBtn({
    required this.label,
    required this.icon,
    required this.fg,
    required this.bg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Mark complete dialog ──────────────────────────────────────────────────────

class _MarkCompleteDialog extends StatelessWidget {
  final String sessionName;
  const _MarkCompleteDialog({required this.sessionName});

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      backgroundColor: AppTheme.cardBg,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22)),
      title: const Text(
        'هل شاهدت هذا الدرس؟',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: FontWeight.w800,
          color: AppTheme.textDark,
        ),
      ),
      content: Text(
        'هل تريد تحديد "$sessionName" كمكتمل؟',
        style: const TextStyle(
            fontFamily: 'Cairo', color: AppTheme.textMedium),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('لاحقاً',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  color: AppTheme.textLight)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.accent2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'نعم، مكتمل ✓',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}