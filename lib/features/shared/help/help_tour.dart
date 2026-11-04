// The guided tour (workstream f3): a light overlay that highlights the widgets wrapped in [HelpTourTarget] whose `id`
// matches the help entry's `tour[].target`. A target that is not on screen is skipped; "Skip" is always there; the
// overlay is static (no animation), so Reduce motion needs nothing more.
//
//   HelpTourTarget(pageId: 'home.student', id: 'search', child: SearchBar())
//
// Wired so far (the rest is listed in the f3 report): student home, the course page, the app assistant.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_tokens.dart';
import '../../../design/app_kit.dart' show appText;
import 'help_models.dart';

/// Marks a widget as a stop of the guided tour.
class HelpTourTarget extends StatefulWidget {
  const HelpTourTarget({super.key, required this.id, required this.child, this.pageId});

  /// Matches `tour[].target` of the help entry.
  final String id;

  /// The page it belongs to (a lazy tab can keep another page's `search` alive): null = any page.
  final String? pageId;
  final Widget child;

  /// The render box of the visible target ([id] on [pageId]), or null when it is not on screen.
  static Rect? rectOf(String id, {String? pageId}) {
    for (final s in _live) {
      if (s.widget.id != id) continue;
      if (pageId != null && s.widget.pageId != null && s.widget.pageId != pageId) continue;
      final r = s._rect();
      if (r != null) return r;
    }
    return null;
  }

  /// How many of [ids] are on screen now.
  static int visibleCount(Iterable<String> ids, {String? pageId}) =>
      ids.where((i) => rectOf(i, pageId: pageId) != null).length;

  static final List<_HelpTourTargetState> _live = [];

  @override
  State<HelpTourTarget> createState() => _HelpTourTargetState();
}

class _HelpTourTargetState extends State<HelpTourTarget> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    HelpTourTarget._live.add(this);
  }

  @override
  void dispose() {
    HelpTourTarget._live.remove(this);
    super.dispose();
  }

  Rect? _rect() {
    final ctx = _key.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    // a tab kept alive but hidden (IndexedStack) has a stopped ticker mode
    if (!TickerMode.valuesOf(ctx).enabled) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) return null;
    final r = box.localToGlobal(Offset.zero) & box.size;
    final view = View.maybeOf(ctx);
    if (view != null) {
      final screen = view.physicalSize / view.devicePixelRatio;
      if (!r.overlaps(Offset.zero & screen)) return null;
    }
    return r;
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

/// The steps of [entry] whose target is on screen.
List<HelpTourStep> helpTourStepsOn(List<HelpTourStep> tour, {String? pageId}) =>
    [for (final s in tour) if (HelpTourTarget.rectOf(s.target, pageId: pageId) != null) s];

/// Runs the tour of [steps] over the root overlay. Resolves when the person finishes or skips.
Future<void> runHelpTour(BuildContext context, List<HelpTourStep> steps, {String? pageId}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final live = helpTourStepsOn(steps, pageId: pageId);
  if (overlay == null || live.isEmpty) return Future.value();
  final done = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => HelpTourOverlay(
      steps: live,
      pageId: pageId,
      onClose: () {
        entry.remove();
        done.complete();
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

/// The overlay: a scrim with a hole around the current target, a card with the step's text, Next / Back / Skip.
class HelpTourOverlay extends StatefulWidget {
  const HelpTourOverlay({super.key, required this.steps, required this.onClose, this.pageId});
  final List<HelpTourStep> steps;
  final String? pageId;
  final VoidCallback onClose;

  @override
  State<HelpTourOverlay> createState() => _HelpTourOverlayState();
}

class _HelpTourOverlayState extends State<HelpTourOverlay> {
  int _i = 0;

  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  void _next() {
    if (_i >= widget.steps.length - 1) {
      widget.onClose();
    } else {
      setState(() => _i++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);
    final step = widget.steps[_i];
    final target = HelpTourTarget.rectOf(step.target, pageId: widget.pageId);
    final hole = target?.inflate(6);
    final last = _i == widget.steps.length - 1;
    final cardW = math.min(360.0, size.width - 2 * AppSpace.md);
    // the card goes under the target when there is room, else above it
    final below = hole == null || hole.bottom + 190 < size.height;
    final top = hole == null ? size.height / 2 - 80 : (below ? hole.bottom + AppSpace.sm : math.max(AppSpace.md, hole.top - 190));
    final left = hole == null
        ? (size.width - cardW) / 2
        : (hole.center.dx - cardW / 2).clamp(AppSpace.md, math.max(AppSpace.md, size.width - cardW - AppSpace.md));
    return Material(
      type: MaterialType.transparency,
      child: Directionality(
        textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: CustomPaint(painter: _ScrimPainter(hole, Colors.black.withValues(alpha: 0.62), c.primary)),
            ),
          ),
          Positioned(
            top: top.toDouble(),
            left: left.toDouble(),
            width: cardW,
            child: Semantics(
              container: true,
              liveRegion: true,
              label: _t('جولة تعريفية', 'Guided tour'),
              child: Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.cardBg,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  boxShadow: c.cardShadow,
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.text.of(AppConfig.lang), style: appText(15, c: c.textDark, h: 1.5)),
                  AppSpace.gapSm,
                  Wrap(
                    spacing: AppSpace.xs,
                    runSpacing: AppSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('${_i + 1} / ${widget.steps.length}', style: appText(12, c: c.textLight)),
                      TextButton(
                        style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                        onPressed: widget.onClose,
                        child: Text(_t('تخطي', 'Skip')),
                      ),
                      if (_i > 0)
                        TextButton(
                          style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                          onPressed: () => setState(() => _i--),
                          child: Text(_t('السابق', 'Back')),
                        ),
                      FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                        onPressed: _next,
                        child: Text(last ? _t('تم', 'Done') : _t('التالي', 'Next')),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole, this.scrim, this.ring);
  final Rect? hole;
  final Color scrim, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(full, Paint()..color = scrim);
      return;
    }
    final rr = RRect.fromRectAndRadius(hole!, const Radius.circular(AppRadius.card));
    canvas.drawPath(Path.combine(PathOperation.difference, full, Path()..addRRect(rr)), Paint()..color = scrim);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.scrim != scrim || old.ring != ring;
}
