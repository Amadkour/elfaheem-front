/// features/attendance/attendance_premium.dart
///
/// The two attendance buttons that live in a lesson's action row (SessionMaterialCard).
/// Same 30 px height / 11 px radius as [SessionActionBtn], so they sit in the row naturally,
/// but with a gradient face, a soft shimmer and — when attendance is OPEN — a pulsing glow.
///
///   [AttendanceStudentAction]  green + pulse when a window is open, bluetooth icon when the
///                              phone is offline ("Check in via classmate")
///   [AttendanceTeacherAction]  opens the rotating-code sheet
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import 'package:flutter_education_app/core/offline/app_connectivity.dart';

import 'attendance_offline_sync.dart';
import 'attendance_store.dart';
import 'attendance_strings.dart';
import 'attendance_widgets.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Premium pill
// ════════════════════════════════════════════════════════════════════════════

class _PremiumPill extends StatefulWidget {
  const _PremiumPill({
    required this.icon,
    required this.label,
    required this.from,
    required this.to,
    required this.onTap,
    this.live = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final Color from;
  final Color to;
  final VoidCallback onTap;

  /// Pulsing glow + dot (attendance is open right now).
  final bool live;

  /// Tiny tag on the right (e.g. "OPEN").
  final String? badge;

  @override
  State<_PremiumPill> createState() => _PremiumPillState();
}

class _PremiumPillState extends State<_PremiumPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _pressed = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Respect "reduce motion": no shimmer / pulse.
    final still = MediaQuery.of(context).disableAnimations;
    if (still && _c.isAnimating) _c.stop();
    if (!still && !_c.isAnimating) _c.repeat();

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 110),
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            // 0..1..0 pulse
            final pulse = widget.live && !still ? (0.5 - 0.5 * math.cos(_c.value * 2 * math.pi)) : 0.0;
            return Container(
              height: 30,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [widget.from, widget.to],
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.to.withValues(alpha: 0.28 + 0.22 * pulse),
                    blurRadius: 10 + 8 * pulse,
                    spreadRadius: 1.5 * pulse,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  children: [
                    if (!still)
                      // shimmer band sweeping left → right
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment(-1.6 + 3.2 * _c.value, 0),
                          child: Transform.rotate(
                            angle: 0.35,
                            child: Container(
                              width: 14,
                              height: 60,
                              color: context.colors.onHero.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                      ),
                    child!,
                  ],
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.live) ...[
                  const _Dot(),
                  const SizedBox(width: 6),
                ],
                Icon(widget.icon, size: 15, color: context.colors.onHero),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: context.colors.onHero,
                    letterSpacing: 0.2,
                  ),
                ),
                if (widget.badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.colors.onHero.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.badge!,
                      style: TextStyle(
                          fontSize: 8.5, fontWeight: FontWeight.w900, color: context.colors.onHero, letterSpacing: 0.6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: context.colors.onHero, shape: BoxShape.circle),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  Student
// ════════════════════════════════════════════════════════════════════════════

class AttendanceStudentAction extends StatefulWidget {
  const AttendanceStudentAction({super.key, required this.sessionId});
  final int sessionId;

  @override
  State<AttendanceStudentAction> createState() => _AttendanceStudentActionState();
}

class _AttendanceStudentActionState extends State<AttendanceStudentAction> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    AppConnectivity.instance.online.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    AppConnectivity.instance.online.removeListener(_refresh);
    super.dispose();
  }

  /// Online: ask the server and STORE the answer (key + window) for later offline use.
  /// Offline: fall back to what was stored the last time we were online.
  Future<void> _refresh() async {
    bool open;
    if (AppConnectivity.instance.isOnline) {
      final w = await AttendanceOfflineSync.instance.warm(sessionId: widget.sessionId);
      open = w != null;
    } else {
      open = await AttendanceStore.instance.window(widget.sessionId) != null;
    }
    if (mounted && open != _open) setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<bool>(
      valueListenable: AppConnectivity.instance.online,
      builder: (_, online, _) {
        final String label = !online
            ? attT('att_btn_checkin_offline')
            : (_open ? attT('att_btn_checkin_now') : attT('att_btn_checkin'));
        return _PremiumPill(
          icon: online ? Icons.how_to_reg_rounded : Icons.bluetooth_searching_rounded,
          label: label,
          from: _open ? c.success : c.primary,
          to: _open ? c.success.withValues(alpha: 0.78) : c.primary.withValues(alpha: 0.72),
          live: _open,
          badge: _open ? attT('att_btn_live') : null,
          onTap: () async {
            await showStudentCheckInSheet(context, sessionId: widget.sessionId);
            if (mounted) _refresh();
          },
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Teacher
// ════════════════════════════════════════════════════════════════════════════

class AttendanceTeacherAction extends StatelessWidget {
  const AttendanceTeacherAction({super.key, required this.sessionId});
  final int sessionId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _PremiumPill(
      icon: Icons.sensors_rounded,
      label: attT('att_t_btn'),
      from: c.primary,
      to: c.heroEnd(c.primary), // M22: theme ink, not purple
      onTap: () => showTeacherAttendanceSheet(context, sessionId),
    );
  }
}
