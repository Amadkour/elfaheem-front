import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'live_palette.dart';

// Live-room palette
final _cyan   = LivePalette.accent;
const _glass  = Color(0x1AFFFFFF);
const _bdr    = Color(0x30FFFFFF);

class NoVideoWidget extends StatelessWidget {
  const NoVideoWidget({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: LivePalette.bg,
    alignment: Alignment.center,
    child: LayoutBuilder(
      builder: (ctx, constraints) {
        final size =
            math.min(constraints.maxHeight, constraints.maxWidth) * 0.28;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size * 1.4,
              height: size * 1.4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _glass,
                border: Border.all(color: _bdr, width: 1),
              ),
              child: Icon(
                Icons.videocam_off_rounded,
                color: _cyan.withValues(alpha: 0.5),
                size: size * 0.65,
              ),
            ),
            SizedBox(height: size * 0.2),
            Text(
              'Camera off',
              style: TextStyle(
                color: Colors.white38,
                fontSize: math.min(size * 0.28, 13),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    ),
  );
}