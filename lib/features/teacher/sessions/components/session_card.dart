import 'package:flutter/material.dart';
import '../../../../config/app_theme.dart';
import '../../../student/models.dart';
import '../../../student/sessions/components/recording_button.dart';

class SessionCard extends StatelessWidget {
  final TeacherSessionItem session;
  final VoidCallback onEdit, onDelete, onStartLive, onEndLive,
      onRecording, onAttend;

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

  bool get _isLive    => session.isLive;
  bool get _isRunning => session.isLiveActive;
  bool get _hasRec    => session.hasRecording ||
      session.recordingStatus == 'pending' ||
      session.recordingStatus == 'processing';

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: _isRunning
            ? [
          BoxShadow(
            color: AppTheme.danger.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ]
            : AppTheme.cardShadow,
        border: _isRunning
            ? Border.all(color: AppTheme.danger.withValues(alpha: 0.45), width: 1.5)
            : Border.all(color: AppTheme.divider, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header stripe with gradient ────────────────────────────────
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: _isLive ? AppTheme.dangerGradient : AppTheme.primaryGradient,
            ),
          ),

          // ── Main Content ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order badge
                _OrderBadge(order: session.order, isLive: _isLive),
                const SizedBox(width: 14),

                // Info column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title + LIVE badge row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              session.name,
                              style: AppTheme.h3.copyWith(fontSize: 15),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isRunning) ...[
                            const SizedBox(width: 8),
                            _LiveBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Meta tags
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _MetaChip(
                          icon: Icons.schedule_rounded,
                          label: '${session.durationMinutes} دقيقة',
                          color: const Color(0xFFE8881A),
                          bgColor: const Color(0xFFFFF3E0),
                        ),
                        if (session.scheduledAt != null)
                          _MetaChip(
                            icon: Icons.event_rounded,
                            label: session.scheduledLabel,
                            color: AppTheme.primary,
                            bgColor: AppTheme.primaryLight,
                          ),
                        _TypeChip(isLive: _isLive),
                      ]),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Action column
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoundIconBtn(
                      icon: Icons.edit_rounded,
                      color: AppTheme.primary,
                      onTap: onEdit,
                    ),
                    const SizedBox(height: 8),
                    _RoundIconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: AppTheme.danger,
                      onTap: onDelete,
                    ),
                    if (_isLive) ...[
                      const SizedBox(height: 8),
                      _RoundIconBtn(
                        icon: Icons.people_alt_rounded,
                        color: const Color(0xFF7B5FFF),
                        onTap: onAttend,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // ── Live controls ──────────────────────────────────────────────
          if (_isLive) ...[
            Container(height: 1, color: AppTheme.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (!_isRunning)
                  _GradientPill(
                    label: 'بدء الحصة المباشرة',
                    icon: Icons.play_circle_rounded,
                    gradient: AppTheme.primaryGradient,
                    onTap: onStartLive,
                  )
                else ...[
                  _GradientPill(
                    label: 'إنهاء الحصة',
                    icon: Icons.stop_circle_rounded,
                    gradient: AppTheme.dangerGradient,
                    onTap: onEndLive,
                  ),
                  _GradientPill(
                    label: 'الغرفة المباشرة',
                    icon: Icons.open_in_new_rounded,
                    gradient: AppTheme.tealGradient,
                    onTap: onStartLive,
                  ),
                ],
                if (_hasRec)
                  RecordingButton(
                    recordingUrl: session.recordingUrl,
                    compact: true,
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Order badge ───────────────────────────────────────────────────────────────
class _OrderBadge extends StatelessWidget {
  final int order;
  final bool isLive;
  const _OrderBadge({required this.order, required this.isLive});

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      gradient: isLive ? AppTheme.dangerGradient : AppTheme.primaryGradient,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: (isLive ? AppTheme.danger : AppTheme.primary)
              .withValues(alpha: 0.30),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: Text(
        order.toString().padLeft(2, '0'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          fontFamily: 'bahji',
        ),
      ),
    ),
  );
}

// ── Meta chip ─────────────────────────────────────────────────────────────────
class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bgColor;
  const _MetaChip(
      {required this.icon,
        required this.label,
        required this.color,
        required this.bgColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label,
          style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11)),
    ]),
  );
}

// ── Type chip ────────────────────────────────────────────────────────────────
class _TypeChip extends StatelessWidget {
  final bool isLive;
  const _TypeChip({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppTheme.danger : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            isLive ? Icons.sensors_rounded : Icons.play_arrow_rounded,
            size: 11,
            color: color),
        const SizedBox(width: 4),
        Text(
          isLive ? 'مباشر' : 'مسجّل',
          style: AppTheme.caption
              .copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11),
        ),
      ]),
    );
  }
}

// ── Live badge ────────────────────────────────────────────────────────────────
class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      gradient: AppTheme.dangerGradient,
      borderRadius: BorderRadius.circular(8),
      boxShadow: AppTheme.dangerShadow,
    ),
    child: const Text(
      '● LIVE',
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        fontFamily: 'bahji',
        letterSpacing: 0.8,
      ),
    ),
  );
}

// ── Round icon button ─────────────────────────────────────────────────────────
class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _RoundIconBtn(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 1),
      ),
      child: Icon(icon, color: color, size: 17),
    ),
  );
}

// ── Gradient pill button ──────────────────────────────────────────────────────
class _GradientPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;
  const _GradientPill(
      {required this.label,
        required this.icon,
        required this.gradient,
        required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.30),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 16),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            fontFamily: 'bahji',
          ),
        ),
      ]),
    ),
  );
}