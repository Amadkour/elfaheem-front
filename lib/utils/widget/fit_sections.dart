// lib/utils/widget/fit_sections.dart
//
// FitSections — "show only what fits" for read-only content.
//
// Plain widgets only (LayoutBuilder + Column + ClipRect). No custom render
// objects, so it is predictable and safe.
//
//   1. Text scale is clamped inside the widget (FitSectionsConfig.maxTextScale)
//      so sizes stay deterministic on phones with a big system font.
//   2. Every section declares its design height (at text scale 1.0).
//      If the sections don't fit the available height, the lowest-priority
//      sections are removed (priority 0 = never removed, higher = removed first).
//   3. ClipRect is the last safety net: if an estimate is a few pixels off,
//      the extra is clipped — no overflow stripes on screen.
//
// Global switches (e.g. in main()):


import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class FitSectionsConfig {
  const FitSectionsConfig._();

  static bool enabled = true;
  static double maxTextScale = 1.15;
  static bool logRemoved = kDebugMode;
}

class FitSection {
  const FitSection({
    required this.child,
    required this.height,
    this.priority = 0,
    this.label,
  });

  final Widget child;

  /// Height of this section at text scale 1.0 (logical px).
  final double height;

  /// 0 = required (never removed). Higher numbers are removed first.
  final int priority;

  /// Only used in debug logs.
  final String? label;
}

class FitSections extends StatelessWidget {
  const FitSections({super.key, required this.sections, this.minGap = 3});

  final List<FitSection> sections;

  /// Smallest gap kept between two visible sections.
  final double minGap;

  /// Effective text scale used for height estimates (1.0 … maxTextScale).
  static double textScale(BuildContext context) {
    final raw = MediaQuery.textScalerOf(context).scale(10) / 10;
    return raw.clamp(1.0, FitSectionsConfig.maxTextScale).toDouble();
  }

  static final Set<String> _logged = <String>{};

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final s = textScale(context);

    return MediaQuery(
      data: mq.copyWith(
        textScaler: mq.textScaler.clamp(maxScaleFactor: FitSectionsConfig.maxTextScale),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final avail = c.maxHeight;
          final kept = List<FitSection>.of(sections);
          final removed = <String>[];

          if (FitSectionsConfig.enabled && avail.isFinite) {
            double need() =>
                kept.fold<double>(0, (a, e) => a + e.height * s) +
                minGap * math.max(0, kept.length - 1);

            while (need() > avail + 0.5) {
              var victim = -1;
              var best = 0;
              for (var i = 0; i < kept.length; i++) {
                final p = kept[i].priority;
                if (p > 0 && p >= best) {
                  best = p;
                  victim = i; // ties: the last one goes first
                }
              }
              if (victim < 0) break; // only required sections left
              removed.add(kept[victim].label ?? 'section#$victim');
              kept.removeAt(victim);
            }
          }

          if (FitSectionsConfig.logRemoved && removed.isNotEmpty) {
            final key = '${removed.join(',')}@${avail.round()}';
            if (_logged.add(key)) {
              debugPrint('[FitSections] removed: ${removed.join(', ')} '
                  '(height available: ${avail.toStringAsFixed(1)})');
            }
          }

          return ClipRect(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final e in kept) e.child],
            ),
          );
        },
      ),
    );
  }
}
