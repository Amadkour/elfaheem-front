// The on-device background removal (image_background_engine.dart) on synthetic pictures: what the border says, a tap,
// a tap that brings back, brushes, the same colour inside a shape, gradients, edges without a fringe, a render at
// another resolution, an already transparent picture, and the point-to-pixel mapping under rotation.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_education_app/design/image_background_engine.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Pixel = (int r, int g, int b, int a);

BgWork _paint(int w, int h, Pixel Function(int x, int y) f) {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final (r, g, b, a) = f(x, y);
      final k = (y * w + x) * 4;
      rgba[k] = r;
      rgba[k + 1] = g;
      rgba[k + 2] = b;
      rgba[k + 3] = a;
    }
  }
  return BgWork(w, h, rgba);
}

const Pixel white = (255, 255, 255, 255);
const Pixel red = (200, 30, 30, 255);
const Pixel blue = (30, 60, 200, 255);

BgOutput _run(BgWork work, BgParams params, {BgRaster? display}) {
  final out = BgOutput();
  bgDrain(bgProcess(BgJob(work, params, display ?? work), out));
  return out;
}

/// Straight alpha at (x, y) of a premultiplied result.
int _alpha(BgOutput out, int x, int y) => out.rgba![(y * out.width + x) * 4 + 3];

BgParams _params(BgWork work, {List<BgOp> ops = const [], double softness = 0.2, double tolerance = kBgDefaultTolerance, bool holes = false}) =>
    BgParams(estimate: bgEstimateBackground(work), ops: ops, softness: softness, tolerance: tolerance, holes: holes);

void main() {
  test('a plain background goes and the subject stays', () {
    final work = _paint(200, 200, (x, y) => (x - 100).abs() < 40 && (y - 100).abs() < 50 ? red : white);
    final est = bgEstimateBackground(work);
    expect(est.clusters, hasLength(1));
    expect(est.confidence, greaterThan(0.9));
    final out = _run(work, BgParams(estimate: est));
    expect(_alpha(out, 5, 5), 0);
    expect(_alpha(out, 100, 100), 255);
    expect(out.fields!.coverage, closeTo(0.2, 0.05));
  });

  test('a shirt touching the bottom edge is not the background', () {
    // background above, a blue block from the bottom edge up and across most of the width
    final work = _paint(200, 200, (x, y) => y > 130 && x > 30 && x < 170 ? blue : white);
    final out = _run(work, _params(work));
    expect(_alpha(out, 100, 180), 255, reason: 'the shirt is kept');
    expect(_alpha(out, 100, 10), 0, reason: 'the wall is removed');
    expect(_alpha(out, 5, 180), 0, reason: 'the wall beside it too');
  });

  test('a busy border is left to the person', () {
    final rnd = math.Random(7);
    final work = _paint(160, 160, (x, y) => (rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256), 255));
    final est = bgEstimateBackground(work);
    expect(est.clusters, isEmpty);
    final out = _run(work, BgParams(estimate: est));
    expect(out.fields!.coverage, 1);
  });

  test('a mottled backdrop is left to the person', () {
    final rnd = math.Random(3);
    final work = _paint(200, 200, (x, y) {
      final big = ((x ~/ 14 + y ~/ 14) * 37) % 90;
      final v = 90 + big + rnd.nextInt(8);
      return (40, v, 150, 255);
    });
    expect(bgEstimateBackground(work).clusters, isEmpty);
  });

  test('the background enclosed by the subject goes in a photo, a small similar patch stays', () {
    final rnd = math.Random(5);
    // a textured subject (so not a graphic) with a large opening and a small white patch (the white of an eye)
    final work = _paint(640, 480, (x, y) {
      final inBody = (x - 320).abs() < 180 && (y - 240).abs() < 180;
      final opening = (x - 240).abs() < 30 && (y - 240).abs() < 40;
      final eye = (x - 400).abs() < 3 && (y - 180).abs() < 3;
      if (inBody && !opening && !eye) {
        return (90 + rnd.nextInt(120), 30 + rnd.nextInt(120), 50 + rnd.nextInt(120), 255);
      }
      return white;
    });
    final est = bgEstimateBackground(work);
    expect(est.graphic, isFalse);
    final out = _run(work, BgParams(estimate: est));
    expect(_alpha(out, 240, 240), 0, reason: 'the enclosed opening is background');
    expect(_alpha(out, 400, 180), 255, reason: 'a tiny patch of the same colour is kept');
    expect(_alpha(out, 300, 300), 255, reason: 'the subject stays');
  });

  test('a tap removes a connected colour, and a tap on it brings it back', () {
    // a blue disc on a red block on white: the border only explains the white
    final work = _paint(200, 200, (x, y) {
      final inDisc = math.sqrt((x - 100) * (x - 100) + (y - 100) * (y - 100)) < 30;
      if (inDisc) return blue;
      return (x - 100).abs() < 70 && (y - 100).abs() < 70 ? red : white;
    });
    final first = _run(work, _params(work));
    expect(_alpha(first, 100, 100), 255);
    final tapped = _run(work, _params(work, ops: const [BgOp.pick(100, 100)]));
    expect(_alpha(tapped, 100, 100), 0, reason: 'the disc goes');
    expect(_alpha(tapped, 50, 50), 255, reason: 'the red block stays');

    final back = _run(work, _params(work, ops: const [BgOp.pick(100, 100), BgOp.keep(100, 100)]));
    expect(_alpha(back, 100, 100), 255, reason: 'a tap on what was removed brings it back');
  });

  test('brushes paint over the mask', () {
    final work = _paint(200, 200, (x, y) => (x - 100).abs() < 40 && (y - 100).abs() < 50 ? red : white);
    final erased = _run(work, _params(work, ops: const [BgOp.stroke(BgOpKind.erase, [100, 100], 6)]));
    expect(_alpha(erased, 100, 100), 0);
    final restored = _run(work, _params(work, ops: const [BgOp.stroke(BgOpKind.restore, [10, 10, 10, 30], 6)]));
    expect(_alpha(restored, 10, 20), 255);
    expect(_alpha(restored, 40, 40), 0);
  });

  test('the same colour inside a shape: only with holes', () {
    // a square with a white window in it
    final work = _paint(200, 200, (x, y) {
      final outer = (x - 100).abs() < 60 && (y - 100).abs() < 60;
      final window = (x - 100).abs() < 20 && (y - 100).abs() < 20;
      return outer && !window ? red : white;
    });
    expect(bgEstimateBackground(work).graphic, isTrue);
    final plain = _run(work, _params(work));
    expect(_alpha(plain, 100, 100), 255, reason: 'the border does not reach the window');
    final holes = _run(work, _params(work, holes: true));
    expect(_alpha(holes, 100, 100), 0);
    expect(_alpha(holes, 60, 100), 255, reason: 'the frame itself stays');
  });

  test('a vignette-like gradient goes too', () {
    final work = _paint(200, 200, (x, y) {
      if ((x - 100).abs() < 40 && (y - 100).abs() < 50) return red;
      final v = 200 + (y * 50 ~/ 200);
      return (v, v, v, 255);
    });
    final out = _run(work, _params(work));
    expect(_alpha(out, 5, 5), 0);
    expect(_alpha(out, 5, 195), 0);
    expect(_alpha(out, 100, 100), 255);
  });

  test('edges carry no fringe of the old background', () {
    // a red disc with a soft edge on green, at the size the mask is made at
    const r0 = 150.0;
    final work = _paint(640, 640, (x, y) {
      final d = math.sqrt((x - 320) * (x - 320) + (y - 320) * (y - 320));
      final a = (r0 + 2 - d).clamp(0.0, 4.0) / 4.0;
      return ((30 + (200 - 30) * a).round(), (200 + (30 - 200) * a).round(), 30, 255);
    });
    final out = _run(work, _params(work, softness: 0.2));
    var partial = 0, greenish = 0;
    for (var i = 0; i < out.rgba!.length; i += 4) {
      final a = out.rgba![i + 3];
      if (a > 25 && a < 230) {
        partial++;
        final straightG = out.rgba![i + 1] * 255 / a;
        if (straightG > 90) greenish++;
      }
    }
    expect(partial, greaterThan(20), reason: 'the edge is soft');
    expect(greenish, lessThan(partial * 0.15), reason: 'no green left in the half-transparent edge pixels');
  });

  test('a render at another resolution follows the same mask', () {
    final work = _paint(160, 120, (x, y) => (x - 80).abs() < 30 && (y - 60).abs() < 30 ? red : white);
    final hi = _paint(640, 480, (x, y) => (x - 320).abs() < 120 && (y - 240).abs() < 120 ? red : white);
    final out = _run(work, _params(work), display: hi);
    expect(out.width, 640);
    expect(_alpha(out, 10, 10), 0);
    expect(_alpha(out, 320, 240), 255);
    expect(out.fields!.width, 160);
  });

  test('an already transparent picture stays as it is', () {
    final work = _paint(100, 100, (x, y) => (x - 50).abs() < 20 && (y - 50).abs() < 20 ? red : (0, 0, 0, 0));
    final est = bgEstimateBackground(work);
    expect(est.clusters, isEmpty);
    final out = _run(work, BgParams(estimate: est));
    expect(_alpha(out, 5, 5), 0);
    expect(_alpha(out, 50, 50), 255);
  });

  test('the guard for very large images keeps the proportions', () {
    expect(bgFitWithin(8000, 4000, kBgFullSide), (2400, 1200));
    expect(bgFitWithin(500, 300, kBgFullSide), (500, 300));
    expect(bgFitWithin(1, 9000, 640), (1, 640));
  });

  test('a point of the frame lands on the right pixel at every rotation', () {
    // a 100 x 200 picture covering a 300 x 300 frame: 3 frame px per picture px, cropped top and bottom
    (double, double)? map(double x, double y, int turns) => bgFramePointToSource(sceneX: x, sceneY: y, frameWidth: 300, frameHeight: 300, quarterTurns: turns, sourceWidth: 100, sourceHeight: 200);
    expect(map(150, 150, 0), (50.0, 100.0));
    expect(map(0, 0, 0), (0.0, 50.0));
    final t1 = map(150, 0, 1);
    expect(t1, isNotNull);
    expect(t1!.$1, closeTo(0, 0.01));
    final t2 = map(300, 300, 2);
    expect(t2, isNotNull);
    expect(t2!.$1, closeTo(0, 0.01));
    expect(t2.$2, closeTo(50, 0.01));
    final t3 = map(0, 300, 3);
    expect(t3, isNotNull);
    expect(t3!.$1, closeTo(0, 0.01));
    expect(bgFramePointToSource(sceneX: 150, sceneY: 500, frameWidth: 300, frameHeight: 300, quarterTurns: 0, sourceWidth: 100, sourceHeight: 200), isNull);
  });

  test('colours are suggested from what is left of the picture', () {
    final work = _paint(100, 100, (x, y) => (x - 50).abs() < 30 && (y - 50).abs() < 30 ? red : white);
    final out = _run(work, _params(work));
    final colours = bgSuggestColours(work, out.fields!.removed);
    expect(colours.length, greaterThanOrEqualTo(4));
    expect(colours.toSet().length, colours.length);
  });
}
