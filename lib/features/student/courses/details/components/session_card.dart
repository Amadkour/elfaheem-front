import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_theme.dart';
import 'package:provider/provider.dart';
import '../../../../auth/auth_provider.dart';
import '../../../../teacher/sessions/live/prejoin.dart';
import '../../../../teacher/sessions/model/live_response_model.dart';
import '../../../models.dart';
import '../../../sessions/sessions_provider.dart';
import '../course_detail_provider.dart';

class StudentSessionCard extends StatelessWidget {
  final SessionModel session;

  /// Injected by the provider — true when student has checked in
  final bool isCheckedIn;

  /// Called when the user taps check-in
  final VoidCallback onCheckIn;

  /// Called when the user taps check-out
  final VoidCallback onCheckOut;

  const StudentSessionCard({
    super.key,
    required this.session,
    required this.isCheckedIn,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  // ── Colors ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Border colour
    Color borderColor =
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5);
    double borderWidth = 0.5;
    if (session.isCompleted) {
      borderColor = context.colors.success;
      borderWidth = 1.0;
    } else if (session.isLive && isCheckedIn) {
      borderColor = context.colors.danger;
      borderWidth = 1.0;
    }

    return GestureDetector(
      onTap: () => _handleTap(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail (right in RTL) ──────────────────────────────────
            _Thumbnail(
              session: session,
              isLive: session.isLive,
              isComplete: session.isCompleted,
            ),

            // ── Info (left in RTL) ────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      session.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),

                    // Duration + scheduled date
                    _MetaRow(session: session),
                    const SizedBox(height: 7),

                    // Type + status pills
                    _PillRow(
                      isLive: session.isLive,
                      isCompleted: session.isCompleted,
                      hasRecording: session.hasRecording,
                      isCheckedIn: isCheckedIn,
                    ),

                    // Attendance buttons (live only, while not completed)
                    if (session.isLive && !session.isCompleted) ...[
                      const SizedBox(height: 8),
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

  // ── Tap handling ─────────────────────────────────────────────────────────────

  Future<void> _handleTap(BuildContext context) async {
    final provider = context.read<StudentSessionsProvider>();

    if (session.isLive) {
      final LiveResponseModel? liveResponseModel =
          await provider.joinLive(session.id);
      if (liveResponseModel == null || !context.mounted) return;
      _snack(context, 'جاري فتح الحصة المباشرة…', const Color(0xFF185FA5));
      UserModel? user = context.read<AuthProvider>().currentUser;

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

    // Recorded — track view every tap
    await provider.trackView(session.id);

    if (session.hasRecording && context.mounted) {
      _snack(context, 'فتح التسجيل…', const Color(0xFF185FA5));
      return;
    }

    if (!session.isCompleted && context.mounted) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => _MarkCompleteDialog(sessionName: session.name),
      );
      if (ok == true && context.mounted) {
        await provider.markComplete(session.id);
        _snack(context, 'تم تحديد الدرس كمكتمل ✓', context.colors.accent);
      }
    }
  }

  void _snack(BuildContext ctx, String msg, Color color) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ── Thumbnail ─────────────────────────────────────────────────────────────────

class _Thumbnail extends StatelessWidget {
  final SessionModel session;
  final bool isLive;
  final bool isComplete;

  const _Thumbnail({
    required this.session,
    required this.isLive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isLive ? const Color(0xFF7A1010) : const Color(0xFF1E1B5E);
    final badgeBg = isLive ? const Color(0xFFD85A30) : const Color(0xFF185FA5);
    final icon =
        isLive ? Icons.sensors_rounded : Icons.play_circle_fill_rounded;

    return SizedBox(
      width: 96,
      height: 100,
      child: Stack(children: [
        // Background
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
          child: Container(
            width: 96,
            height: 100,
            color: bg,
            child: Center(
              child: Opacity(
                opacity: 0.22,
                child: Icon(icon, size: 48, color: Colors.white),
              ),
            ),
          ),
        ),

        // Number badge — top right
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: badgeBg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 4,
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
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Cairo',
                  height: 1,
                ),
              ),
            ),
          ),
        ),

        // Completed check — bottom right
        if (isComplete)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFF1D9E75),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Colors.white,
                size: 13,
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Meta row (duration + scheduled date) ──────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final SessionModel session;

  const _MetaRow({required this.session});

  @override
  Widget build(BuildContext context) {
    final secondary =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        _MetaChip(
          icon: Icons.access_time_rounded,
          label: '${session.durationMinutes} دقيقه',
          color: secondary,
        ),
        if ((session.scheduledAt ?? '').isNotEmpty)
          _MetaChip(
            icon: Icons.calendar_month_rounded,
            label: session.scheduledLabel,
            color: secondary,
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: color, fontFamily: 'Cairo')),
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
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [
      // Type pill
      _Pill(
        label: isLive ? '🔴 مباشر' : '▶ مسجّل',
        bg: isLive ? const Color(0xFFFAECE7) : const Color(0xFFE6F1FB),
        fg: isLive ? const Color(0xFF993C1D) : const Color(0xFF185FA5),
      ),
      // Completed
      if (isCompleted)
        const _Pill(
            label: 'مكتمل', bg: Color(0xFFEAF3DE), fg: Color(0xFF3B6D11)),
      // On-air
      if (isLive && isCheckedIn && !isCompleted)
        const _Pill(
            label: '● حضور', bg: Color(0xFFFAECE7), fg: Color(0xFF993C1D)),
      // Recording available
      if (hasRecording && !isCompleted)
        const _Pill(
            label: 'تسجيل متاح', bg: Color(0xFFFAEEDA), fg: Color(0xFF854F0B)),
    ]);
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg, fg;

  const _Pill({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              fontFamily: 'Cairo',
            )),
      );
}

// ── Attendance row ────────────────────────────────────────────────────────────

class _AttendanceRow extends StatelessWidget {
  final bool isCheckedIn;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  const _AttendanceRow({
    required this.isCheckedIn,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  @override
  Widget build(BuildContext context) {
    if (isCheckedIn) {
      return _AttendBtn(
        label: 'تسجيل المغادرة',
        fg: const Color(0xFFD85A30),
        border: const Color(0xFFD85A30),
        onTap: onCheckOut,
      );
    }
    return _AttendBtn(
      label: 'تسجيل الحضور',
      fg: const Color(0xFF1D9E75),
      border: const Color(0xFF639922),
      onTap: onCheckIn,
    );
  }
}

class _AttendBtn extends StatelessWidget {
  final String label;
  final Color fg, border;
  final VoidCallback onTap;

  const _AttendBtn({
    required this.label,
    required this.fg,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: border.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              label.contains('مغادرة')
                  ? Icons.logout_rounded
                  : Icons.login_rounded,
              size: 13,
              color: fg,
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontFamily: 'Cairo',
                )),
          ]),
        ),
      );
}

// ── Mark complete dialog ──────────────────────────────────────────────────────

class _MarkCompleteDialog extends StatelessWidget {
  final String sessionName;

  const _MarkCompleteDialog({required this.sessionName});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('هل شاهدت هذا الدرس؟',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        content: Text(
          'هل تريد تحديد "$sessionName" كمكتمل؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لاحقاً',
                style:
                    TextStyle(fontFamily: 'Cairo', color: Color(0xFF888780))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D9E75),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، مكتمل',
                style: TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CourseDetailProvider>();
    final sessions = provider.course.sessions;
    if (provider.isLoadingSession) {
      return  Padding(
          padding: EdgeInsets.all(40),
          child: Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(context.colors.primary))));
    }
    if (sessions.isEmpty) {
      return  Padding(
          padding: EdgeInsets.all(40),
          child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.video_library_outlined,
                size: 64, color: context.colors.textLight),
            SizedBox(height: 12),
            Text('لا توجد دروس بعد', style: context.colors.body)
          ])));
    }
    return Column(children: [
      // Filter hint
      ...List.generate(
          sessions.length,
          (i) => Padding(
                padding: const EdgeInsets.all(8.0),
                child: StudentSessionCard(
                  session: sessions[i],
                  isCheckedIn: false,
                  onCheckIn: () {},
                  onCheckOut: () {},
                ),
              ))
      // ...List.generate( sessions.length,(i) => _SessionTile(session: sessions[i])),
    ]);
  }
}
