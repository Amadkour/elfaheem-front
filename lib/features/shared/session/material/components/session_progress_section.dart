// shared/session/components/session_progress_section.dart
//
// Student-facing progress panel shown inside each SessionMaterialCard.
// Hidden for teachers (isTeacher == true) and when there are no materials.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public entry — the whole progress block
// ─────────────────────────────────────────────────────────────────────────────

class SessionProgressSection extends StatelessWidget {
  final int totalMaterial;
  final int completeMaterial;
  final bool isTeacher;

  const SessionProgressSection({
    super.key,
    required this.totalMaterial,
    required this.completeMaterial,
    required this.isTeacher,
  });

  @override
  Widget build(BuildContext context) {
    if (totalMaterial == 0 || isTeacher) return const SizedBox.shrink();

    final done = completeMaterial;
    final total = totalMaterial;
    final ratio = (done / total).clamp(0.0, 1.0);
    final isFinished = done == total;

    final Color fillStart =
        isFinished ? const Color(0xFF00C48C) : const Color(0xFF4DA6FF);
    final Color fillEnd =
        isFinished ? const Color(0xFF00E5A0) : const Color(0xFF845EF7);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              fillStart.withValues(alpha: 0.06),
              fillEnd.withValues(alpha: 0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: fillStart.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LabelRow(
              done: done,
              total: total,
              ratio: ratio,
              isFinished: isFinished,
              fillStart: fillStart,
              fillEnd: fillEnd,
            ),
            const SizedBox(height: 8),
            SegmentedProgressBar(
              total: total,
              done: done,
              fillStart: fillStart,
              fillEnd: fillEnd,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Label row (badge + fraction + percentage pill)
// ─────────────────────────────────────────────────────────────────────────────

class _LabelRow extends StatelessWidget {
  final int done;
  final int total;
  final double ratio;
  final bool isFinished;
  final Color fillStart;
  final Color fillEnd;

  const _LabelRow({
    required this.done,
    required this.total,
    required this.ratio,
    required this.isFinished,
    required this.fillStart,
    required this.fillEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Status badge (completed vs in-progress)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: anim,
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: isFinished
              ? _CompletedBadgePill(key: const ValueKey('done'))
              : _InProgressBadgePill(
                  key: const ValueKey('progress'), fillStart: fillStart),
        ),
        const Spacer(),
        // Fraction counter
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$done',
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: fillStart,
                ),
              ),
              TextSpan(
                text: ' / $total',
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textLight,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Percentage pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [fillStart, fillEnd]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${(ratio * 100).toInt()}%',
            style: const TextStyle(
              fontFamily: 'bahji',
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompletedBadgePill extends StatelessWidget {
  const _CompletedBadgePill({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF00C48C), Color(0xFF00E5A0)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00C48C).withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'completed'.tr,
              style: const TextStyle(
                fontFamily: 'bahji',
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

class _InProgressBadgePill extends StatelessWidget {
  final Color fillStart;

  const _InProgressBadgePill({super.key, required this.fillStart});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: fillStart.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fillStart.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, size: 11, color: fillStart),
            const SizedBox(width: 4),
            Text(
              'you_progress'.tr,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fillStart,
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Segmented / smooth progress bar (public so _MaterialGrid can import it too)
// ─────────────────────────────────────────────────────────────────────────────

class SegmentedProgressBar extends StatelessWidget {
  final int total;
  final int done;
  final Color fillStart;
  final Color fillEnd;

  const SegmentedProgressBar({
    super.key,
    required this.total,
    required this.done,
    required this.fillStart,
    required this.fillEnd,
  });

  @override
  Widget build(BuildContext context) {
    // For small counts show individual segments, otherwise a smooth bar
    if (total <= 12) {
      return Row(
        children: List.generate(total, (i) {
          final filled = i < done;
          final isLast = i == total - 1;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: isLast ? 0 : 3),
              height: 7,
              decoration: BoxDecoration(
                gradient: filled
                    ? LinearGradient(
                        colors: [fillStart, fillEnd],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      )
                    : null,
                color: filled
                    ? null
                    : context.colors.textLight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                boxShadow: filled
                    ? [
                        BoxShadow(
                          color: fillStart.withValues(alpha: 0.30),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),
      );
    }

    // Smooth gradient bar for large material counts
    final ratio = (done / total).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (_, constraints) {
      return Stack(
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: context.colors.textLight.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            height: 8,
            width: constraints.maxWidth * ratio,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [fillStart, fillEnd],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: fillStart.withValues(alpha: 0.40),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }
}
