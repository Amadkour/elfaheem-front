import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';
import '../../../student/models.dart';
import '../../../student/sessions/components/recording_button.dart';

class SessionCard extends StatelessWidget {
  final TeacherSessionItem session;
  final VoidCallback onEdit,
      onDelete,
      onStartLive,
      onEndLive,
      onRecording,
      onAttend;

  const SessionCard({
    super.key,
    required this.session,
    required this.onEdit,
    required this.onDelete,
    required this.onStartLive,
    required this.onEndLive,
    required this.onRecording,
    required this.onAttend,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = session.isLive;
    final isRunning = session.isLiveActive;
    final hasRec = session.hasRecording ||
        session.recordingStatus == 'pending' ||
        session.recordingStatus == 'processing';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.cardShadow,
        border: isRunning
            ? Border.all(
                color: AppTheme.danger.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Column(children: [
        // ── Main info row ─────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Order badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  gradient: isLive
                      ? const LinearGradient(
                          colors: [Colors.redAccent, Color(0xFFFF6B6B)])
                      : AppTheme.primaryGradient,
                  shape: BoxShape.circle),
              child: Center(
                  child: Text(session.order.toString().padLeft(2, '0'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Cairo'))),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(session.name,
                      style: AppTheme.h3,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Wrap(spacing: 12, runSpacing: 4, children: [
                    _Meta(Icons.access_time_rounded,
                        '${session.durationMinutes} دقيقه'),
                    if (session.scheduledAt != null)
                      _Meta(
                          Icons.calendar_month_rounded, session.scheduledLabel),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    _TypeBadge(isLive: isLive),
                    if (isRunning) ...[const SizedBox(width: 8), _LiveBadge()],
                  ]),
                ])),
            // Action icons
            Column(children: [
              _IconBtn(
                  icon: Icons.edit_rounded,
                  color: AppTheme.primary,
                  bg: AppTheme.primary.withValues(alpha: 0.1),
                  onTap: onEdit),
              const SizedBox(height: 8),
              _IconBtn(
                  icon: Icons.delete_rounded,
                  color: AppTheme.danger,
                  bg: AppTheme.danger.withValues(alpha: 0.1),
                  onTap: onDelete),
              if (isLive) ...[
                const SizedBox(height: 8),
                _IconBtn(
                    icon: Icons.people_rounded,
                    color: AppTheme.primary,
                    bg: AppTheme.primary.withValues(alpha: 0.1),
                    onTap: onAttend),
              ],
            ]),
          ]),
        ),

        // ── Live controls ─────────────────────────────────────────────────
        if (isLive)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              if (!isRunning)
                _ActionBtn(
                    label: 'بدء الحصة المباشرة',
                    icon: Icons.play_circle_rounded,
                    gradient: AppTheme.primaryGradient,
                    onTap: onStartLive)
              else ...[
                _ActionBtn(
                    label: 'إنهاء الحصة',
                    icon: Icons.stop_circle_rounded,
                    gradient: const LinearGradient(
                        colors: [AppTheme.danger, Color(0xFFFF6B6B)]),
                    onTap: onEndLive),
                _ActionBtn(
                    label: 'الغرفة المباشرة',
                    icon: Icons.open_in_new_rounded,
                    gradient: const LinearGradient(
                        colors: [Color(0xFF43B97F), Color(0xFF2ECC71)]),
                    onTap: onStartLive), // re-uses roomUrl from provider
              ],
              if (hasRec)
                RecordingButton(recordingUrl: session.recordingUrl, compact: true)
                // _ActionBtn(
                //     label: session.hasRecording
                //         ? 'مشاهدة التسجيل'
                //         : 'جاري التسجيل...',
                //     icon: session.hasRecording
                //         ? Icons.play_circle_filled_rounded
                //         : Icons.hourglass_top_rounded,
                //     gradient: const LinearGradient(
                //         colors: [Color(0xFF8B6FFF), Color(0xFF5B8FFF)]),
                //     onTap: onRecording),
            ]),
          ),
      ]),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta(this.icon, this.label);

  @override
  Widget build(BuildContext ctx) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppTheme.textLight),
        const SizedBox(width: 4),
        Text(label, style: AppTheme.caption)
      ]);
}

class _TypeBadge extends StatelessWidget {
  final bool isLive;

  const _TypeBadge({required this.isLive});

  @override
  Widget build(BuildContext ctx) {
    final c = isLive ? AppTheme.danger : AppTheme.primary;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6)),
        child: Text(isLive ? '🔴 مباشر' : '▶ مسجّل',
            style: AppTheme.caption
                .copyWith(color: c, fontWeight: FontWeight.w700)));
  }
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext ctx) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: AppTheme.danger, borderRadius: BorderRadius.circular(6)),
      child: const Text('● ON AIR',
          style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFamily: 'Cairo',
              letterSpacing: 0.5)));
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color, bg;
  final VoidCallback onTap;

  const _IconBtn(
      {required this.icon,
      required this.color,
      required this.bg,
      required this.onTap});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 34,
          height: 34,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18)));
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.gradient,
      required this.onTap});

  @override
  Widget build(BuildContext ctx) => GestureDetector(
      onTap: onTap,
      child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
              gradient: gradient, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Cairo'))
          ])));
}
