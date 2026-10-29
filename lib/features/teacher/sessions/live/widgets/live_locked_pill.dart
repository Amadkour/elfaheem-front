// lib/features/teacher/sessions/live/widgets/live_locked_pill.dart
//
// The host's "Room locked" pill in the room's top-end badge column (teacher_controls_wiring.md step 5): shown
// while LiveHostControlsController.locked is true, behind the `live.room_lock` feature key (room.dart decides).
// Plain values, so test/ui/live_locked_pill_layout_test.dart pumps it as it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

import 'live_palette.dart';

class LiveLockedPill extends StatelessWidget {
  const LiveLockedPill({super.key, this.onTap});

  /// Opens the participants panel (where the lock switch is); null = not tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = LivePalette.warning;
    final label = t('الغرفة مقفلة', 'Room locked');
    final pill = Container(
      key: const ValueKey('live_room.locked'),
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: LivePalette.shade(0.58),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_rounded, size: 12, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.family,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ]),
    );
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        button: onTap != null,
        excludeSemantics: true,
        child: onTap == null
            ? pill
            : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: pill),
      ),
    );
  }
}
