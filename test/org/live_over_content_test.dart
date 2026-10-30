// D-105: while a screen share fills the stage, the presenter's camera (viewers) and the presenter's own self-view
// float over the shared PICTURE, not in the empty bars beside / under it (lib/features/shared/live/live_self_view.dart:
// shareContentRect, selfViewOverContent).
import 'package:flutter/painting.dart';
import 'package:flutter_education_app/features/shared/live/live_self_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keep = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 12, 12, 84));

  group('shareContentRect', () {
    test('a phone\'s portrait screen is a centred column on a laptop stage', () {
      const stage = Size(1280, 660);
      final r = shareContentRect(stage, 540 / 1170)!;
      final area = kShareVideoInsets.deflateRect(Offset.zero & stage);
      expect(r.height, closeTo(area.height, 0.01));
      expect(r.width, closeTo(area.height * 540 / 1170, 0.01));
      expect(r.center.dx, closeTo(area.center.dx, 0.01));
    });

    test('a laptop\'s 16:9 screen is a band across a phone stage', () {
      const stage = Size(390, 732);
      final r = shareContentRect(stage, 16 / 9)!;
      final area = kShareVideoInsets.deflateRect(Offset.zero & stage);
      expect(r.width, closeTo(area.width, 0.01));
      expect(r.height, closeTo(area.width * 9 / 16, 0.01));
      expect(r.center.dy, closeTo(area.center.dy, 0.01));
    });

    test('no aspect or no room: null', () {
      expect(shareContentRect(const Size(800, 600), null), isNull);
      expect(shareContentRect(const Size(800, 600), 0), isNull);
      expect(shareContentRect(const Size(800, 600), double.nan), isNull);
      expect(shareContentRect(const Size(20, 60), 1.0), isNull);
    });
  });

  group('selfViewOverContent', () {
    Rect boxAt(Size stage, ({Size box, SelfViewKeepOut keepOut}) o, SelfViewSide side, double y) =>
        selfViewOffset(stage: stage, box: o.box, keepOut: o.keepOut, side: side, y: y) & o.box;

    test('laptop viewer, portrait phone share: the box sits on the picture, never in the side bars', () {
      const stage = Size(1280, 660);
      final content = shareContentRect(stage, 540 / 1170)!;
      final box = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.small, stage: stage);
      final o = selfViewOverContent(stage: stage, box: box, keepOut: keep, content: content)!;
      for (final side in SelfViewSide.values) {
        for (final y in [0.0, 0.5, 1.0]) {
          final r = boxAt(stage, o, side, y);
          expect(content.deflate(kOverContentInset - 0.01).contains(r.topLeft), isTrue, reason: '$side $y');
          expect(content.deflate(kOverContentInset - 0.01).contains(r.bottomRight), isTrue, reason: '$side $y');
        }
      }
      // Scaled to the narrow picture, still big enough to see a face.
      expect(o.box.width, lessThanOrEqualTo((content.width - 2 * kOverContentInset) * kOverContentMaxWidth + 0.01));
      expect(o.box.shortestSide, greaterThanOrEqualTo(kOverContentMinSide));
      expect(o.box.aspectRatio, closeTo(box.aspectRatio, 0.001));
    });

    test('phone viewer, laptop share: the box is on the band (smaller), not under it', () {
      const stage = Size(390, 732);
      final content = shareContentRect(stage, 16 / 9)!;
      final box = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.small, stage: stage);
      final o = selfViewOverContent(stage: stage, box: box, keepOut: keep, content: content)!;
      final r = boxAt(stage, o, SelfViewSide.left, 1);
      expect(r.bottom, lessThanOrEqualTo(content.bottom - kOverContentInset + 0.01));
      expect(r.top, greaterThanOrEqualTo(content.top + kOverContentInset - 0.01));
      expect(o.box.height, lessThan(box.height));
      expect(o.box.height, lessThanOrEqualTo((content.height - 2 * kOverContentInset) * kOverContentMaxHeight + 0.01));
    });

    test('a big picture keeps the full-size box, in its corner', () {
      const stage = Size(1280, 660);
      final content = shareContentRect(stage, 16 / 9)!;
      final box = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.small, stage: stage);
      final o = selfViewOverContent(stage: stage, box: box, keepOut: keep, content: content)!;
      expect(o.box, box);
      final r = boxAt(stage, o, SelfViewSide.right, 1);
      expect(r.right, closeTo(content.right - kOverContentInset, 0.01));
      expect(r.bottom, lessThanOrEqualTo(content.bottom - kOverContentInset + 0.01));
    });

    test('never past the stage\'s own keep-outs (the share\'s bottom bar, the badges)', () {
      const stage = Size(1280, 660);
      const tall = SelfViewKeepOut(base: EdgeInsets.fromLTRB(12, 64, 12, 140));
      final content = shareContentRect(stage, 16 / 9)!;
      final box = selfViewBoxSize(shape: SelfViewShape.circle, size: SelfViewSize.small, stage: stage);
      final o = selfViewOverContent(stage: stage, box: box, keepOut: tall, content: content)!;
      expect(o.keepOut.base.top, greaterThanOrEqualTo(64));
      expect(o.keepOut.base.bottom, greaterThanOrEqualTo(140));
    });

    test('unknown or tiny picture: null (the stage placement stays)', () {
      const stage = Size(390, 732);
      final box = selfViewBoxSize(shape: SelfViewShape.box, size: SelfViewSize.small, stage: stage);
      expect(selfViewOverContent(stage: stage, box: box, keepOut: keep, content: null), isNull);
      expect(selfViewOverContent(stage: stage, box: box, keepOut: keep, content: const Rect.fromLTWH(100, 300, 90, 60)),
          isNull);
      expect(selfViewOverContent(stage: stage, box: box, keepOut: keep, content: Rect.zero), isNull);
    });
  });
}
