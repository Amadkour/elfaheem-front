/// utils/widget/count_badge.dart
/// Wraps any widget (tab icon) with a small count badge. Hidden when 0.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_badges.dart';

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: child,
  );
}

/// Overlays a count pill on a settings tile, at its trailing side (before the
/// chevron). Works with any tile without changing it. Hidden when count is 0.
class TileCountOverlay extends StatelessWidget {
  const TileCountOverlay({
    super.key,
    required this.count,
    required this.child,
    this.endOffset = 44,
  });

  final int count;
  final Widget child;

  /// Distance from the tile's end edge (leave room for the chevron).
  final double endOffset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (count > 0)
          PositionedDirectional(
            end: endOffset,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Center(child: AppCountBadge(count: count)),
            ),
          ),
      ],
    );
  }
}
