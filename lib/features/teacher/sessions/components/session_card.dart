import 'package:flutter/material.dart';
import '../../../../config/app_config.dart';
import '../../../../config/app_theme.dart';
import '../../../student/models.dart';
import '../../../student/sessions/components/recording_button.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  SessionCard
// ═══════════════════════════════════════════════════════════════════════════════

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

  Color get _accent =>
      _isLive ? AppTheme.danger : AppTheme.primary;

  LinearGradient get _gradient =>
      _isLive ? AppTheme.dangerGradient : AppTheme.primaryGradient;

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
            color: AppTheme.danger.withValues(alpha: 0.20),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ]
            : AppTheme.cardShadow,
        border: Border.all(
          color: _isRunning
              ? AppTheme.danger.withValues(alpha: 0.45)
              : AppTheme.divider,
          width: _isRunning ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Coloured top stripe ──────────────────────────────────────
          Container(
            height: 4,
            decoration: BoxDecoration(gradient: _gradient),
          ),

          // ── Header: badge + title + type + actions ───────────────────
          _CardHeader(
            session: session,
            isLive: _isLive,
            isRunning: _isRunning,
            accent: _accent,
            gradient: _gradient,
            onEdit: onEdit,
            onDelete: onDelete,
            onAttend: onAttend,
          ),

          // ── Meta chips ───────────────────────────────────────────────
          _MetaRow(session: session),

          // ── Live controls ────────────────────────────────────────────
          if (_isLive) ...[
            Divider(height: 1, color: AppTheme.divider),
            _LiveControls(
              isRunning: _isRunning,
              hasRec: _hasRec,
              session: session,
              onStartLive: onStartLive,
              onEndLive: onEndLive,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Card header
// ═══════════════════════════════════════════════════════════════════════════════

class _CardHeader extends StatelessWidget {
  final TeacherSessionItem session;
  final bool isLive, isRunning;
  final Color accent;
  final LinearGradient gradient;
  final VoidCallback onEdit, onDelete, onAttend;

  const _CardHeader({
    required this.session,
    required this.isLive,
    required this.isRunning,
    required this.accent,
    required this.gradient,
    required this.onEdit,
    required this.onDelete,
    required this.onAttend,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Order badge ────────────────────────────────────────────
        _OrderBadge(
          order: session.order,
          gradient: gradient,
          accent: accent,
        ),

        const SizedBox(width: 14),

        // ── Title area ─────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated pulse banner while running
              if (isRunning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: _PulseBanner(),
                ),

              // Title + LIVE compact badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      session.name,
                      style: AppTheme.h3.copyWith(fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isRunning) ...[
                    const SizedBox(width: 8),
                    _LiveBadge(),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // Session type pill
              _TypeChip(isLive: isLive),
            ],
          ),
        ),

        const SizedBox(width: 10),

        // ── Action buttons ─────────────────────────────────────────
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundIconBtn(
              icon: Icons.edit_rounded,
              color: AppTheme.primary,
              onTap: onEdit,
              tooltip: 'edit_session'.tr,
            ),
            const SizedBox(height: 8),
            _RoundIconBtn(
              icon: Icons.delete_outline_rounded,
              color: AppTheme.danger,
              onTap: onDelete,
              tooltip: 'delete_session'.tr,
            ),
            if (isLive) ...[
              const SizedBox(height: 8),
              _RoundIconBtn(
                icon: Icons.people_alt_rounded,
                color: const Color(0xFF7B5FFF),
                onTap: onAttend,
                tooltip: 'attendees'.tr,
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Meta row
// ═══════════════════════════════════════════════════════════════════════════════

class _MetaRow extends StatelessWidget {
  final TeacherSessionItem session;
  const _MetaRow({required this.session});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: '${session.durationMinutes} ${'minutes'.tr}',
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
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Live controls panel
//  Layout:
//   • Not running → single full-width "Start" button
//   • Running     → two equal-width pills side by side (End | Enter Room)
//   • Has rec     → RecordingButton below, always full-width
// ═══════════════════════════════════════════════════════════════════════════════

class _LiveControls extends StatelessWidget {
  final bool isRunning, hasRec;
  final TeacherSessionItem session;
  final VoidCallback onStartLive, onEndLive;

  const _LiveControls({
    required this.isRunning,
    required this.hasRec,
    required this.session,
    required this.onStartLive,
    required this.onEndLive,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isRunning)
          _GradientPill(
            label: 'start_live_session'.tr,
            icon: Icons.play_circle_rounded,
            gradient: AppTheme.primaryGradient,
            onTap: onStartLive,
            fullWidth: true,
          )
        else
        // Two equal pills in a Row — Expanded handles width
          Row(
            children: [
              Expanded(
                child: _GradientPill(
                  label: 'end_session'.tr,
                  icon: Icons.stop_circle_rounded,
                  gradient: AppTheme.dangerGradient,
                  onTap: onEndLive,
                  fullWidth: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GradientPill(
                  label: 'live_room'.tr,
                  icon: Icons.open_in_new_rounded,
                  gradient: AppTheme.tealGradient,
                  onTap: onStartLive,
                  fullWidth: true,
                ),
              ),
            ],
          ),

        if (hasRec) ...[
          const SizedBox(height: 10),
          RecordingButton(
            recordingUrl: session.recordingUrl,
            compact: false,
          ),
        ],
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Order badge
// ═══════════════════════════════════════════════════════════════════════════════

class _OrderBadge extends StatelessWidget {
  final int order;
  final LinearGradient gradient;
  final Color accent;

  const _OrderBadge({
    required this.order,
    required this.gradient,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      gradient: gradient,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.30),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Center(
      child: Text(
        order.toString().padLeft(2, '0'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w900,
          fontFamily: 'bahji',
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Pulse banner — animated "session is live" indicator
// ═══════════════════════════════════════════════════════════════════════════════

class _PulseBanner extends StatefulWidget {
  @override
  State<_PulseBanner> createState() => _PulseBannerState();
}

class _PulseBannerState extends State<_PulseBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.danger.withValues(alpha: 0.28),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: AppTheme.danger,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'session_is_live'.tr,
            style: AppTheme.caption.copyWith(
              color: AppTheme.danger,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Live badge (compact pill, shown next to title)
// ═══════════════════════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════════════════════
//  Type chip (live / recorded)
// ═══════════════════════════════════════════════════════════════════════════════

class _TypeChip extends StatelessWidget {
  final bool isLive;
  const _TypeChip({required this.isLive});

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppTheme.danger : AppTheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLive ? Icons.sensors_rounded : Icons.play_arrow_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isLive ? 'session_type_live'.tr : 'session_type_recorded'.tr,
            style: AppTheme.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Meta chip
// ═══════════════════════════════════════════════════════════════════════════════

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bgColor;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Round icon button
// ═══════════════════════════════════════════════════════════════════════════════

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _RoundIconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withValues(alpha: 0.18), width: 1),
        ),
        child: Icon(icon, color: color, size: 17),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Gradient pill button
//  fullWidth=true → fills its parent (use inside Expanded)
//  fullWidth=false → shrink-wraps content
// ═══════════════════════════════════════════════════════════════════════════════

class _GradientPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final bool fullWidth;

  const _GradientPill({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 42,
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withValues(alpha: 0.28),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize:
        fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'bahji',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}