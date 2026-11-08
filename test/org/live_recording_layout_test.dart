// D-306: what a device recording draws (live_recording_layout.dart), when a room starts recording by itself, full
// view's system UI and turn hint, and the touch scrollbar's numbers.
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_education_app/features/shared/live/live_recording_layout.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_scrollbar.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_view.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/widgets/live_focus_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

RecSource _cam(String id, {bool speaking = false}) =>
    RecSource(label: 'rcam_$id', kind: RecSourceKind.camera, name: 'Person $id', speaking: speaking);

final _canvas = Offset.zero & kRecCanvas;

void main() {
  group('recordingLayout', () {
    test('nothing on: no tiles (the compositor draws its placeholder)', () {
      final l = recordingLayout();
      expect(l.isEmpty, isTrue);
      expect(jsonDecode(l.toJson())['tiles'], isEmpty);
    });

    test('one camera fills the canvas', () {
      final l = recordingLayout(cameras: [_cam('a')]);
      expect(l.tiles, hasLength(1));
      expect(l.tiles.single.rect, _canvas);
      expect(l.tiles.single.main, isTrue);
      expect(l.tiles.single.fit, 'auto');
    });

    test('cameras alone: a centred 16:9 grid of the right shape, inside the canvas, never overlapping', () {
      for (final n in [2, 3, 4, 5, 6, 7, 9]) {
        final l = recordingLayout(cameras: [for (var i = 0; i < n; i++) _cam('$i')]);
        expect(l.tiles, hasLength(n), reason: '$n cameras');
        for (final t in l.tiles) {
          expect(t.rect.width / t.rect.height, closeTo(16 / 9, 1e-6));
          expect(_canvas.inflate(0.5).contains(t.rect.topLeft) && _canvas.inflate(0.5).contains(t.rect.bottomRight), isTrue);
        }
        for (var i = 0; i < n; i++) {
          for (var j = i + 1; j < n; j++) {
            expect(l.tiles[i].rect.overlaps(l.tiles[j].rect), isFalse, reason: '$n cameras: $i and $j overlap');
          }
        }
      }
      expect(recordingGridShape(2), (2, 1));
      expect(recordingGridShape(3), (2, 2));
      expect(recordingGridShape(6), (3, 2));
      expect(recordingGridShape(8), (3, 3));
    });

    test('three cameras: the short last row is centred', () {
      final l = recordingLayout(cameras: [_cam('a'), _cam('b'), _cam('c')]);
      final last = l.tiles[2].rect;
      expect(last.center.dx, closeTo(kRecCanvas.width / 2, 0.5));
    });

    test('more than nine cameras: nine tiles and "+N"', () {
      final l = recordingLayout(cameras: [for (var i = 0; i < 12; i++) _cam('$i')]);
      expect(l.tiles, hasLength(9));
      expect(l.more, 3);
      expect(jsonDecode(l.toJson())['more'], 3);
    });

    test('a shared stage fills the canvas alone, letterboxed in its shape', () {
      const board = RecSource(label: 'board', kind: RecSourceKind.board);
      final l = recordingLayout(stage: board);
      expect(l.tiles.single.rect, _canvas);
      expect(l.tiles.single.fit, 'contain');
    });

    test('a stage with cameras: the stage first, the cameras in a column on the end side (left in Arabic)', () {
      const screen = RecSource(label: 'rscreen_x', kind: RecSourceKind.screen, name: 'Mona');
      final cams = [for (var i = 0; i < 6; i++) _cam('$i', speaking: i == 0)];
      final ltr = recordingLayout(stage: screen, cameras: cams);
      expect(ltr.tiles.first.label, 'rscreen_x');
      expect(ltr.tiles.first.main, isTrue);
      expect(ltr.tiles, hasLength(1 + kRecMaxThumbs));
      expect(ltr.more, 6 - kRecMaxThumbs);
      final stage = ltr.tiles.first.rect;
      for (final t in ltr.tiles.skip(1)) {
        expect(t.rect.left, greaterThanOrEqualTo(stage.right), reason: 'right of the stage');
        expect(t.rect.overlaps(stage), isFalse);
      }
      expect(ltr.tiles[1].speaking, isTrue);
      final rtl = recordingLayout(stage: screen, cameras: cams, rtl: true);
      for (final t in rtl.tiles.skip(1)) {
        expect(t.rect.right, lessThanOrEqualTo(rtl.tiles.first.rect.left), reason: 'left of the stage in Arabic');
      }
      expect(rtl.labels, containsAll(['rscreen_x', 'rcam_0']));
      expect(rtl.labels.contains('rcam_5'), isFalse, reason: 'a camera past the thumbnails is not attached');
    });

    test('Arabic grid: the first camera on the right', () {
      final l = recordingLayout(cameras: [_cam('a'), _cam('b')], rtl: true);
      expect(l.tiles[0].rect.left, greaterThan(l.tiles[1].rect.left));
    });

    test('the JSON names every field the compositor reads', () {
      const screen = RecSource(label: 'screen', kind: RecSourceKind.screen);
      final m = jsonDecode(recordingLayout(stage: screen, cameras: [_cam('a', speaking: true)]).toJson()) as Map;
      expect(m['v'], 1);
      expect(m['cw'], 1920);
      expect(m['ch'], 1080);
      final tiles = (m['tiles'] as List).cast<Map>();
      expect(tiles.first, containsPair('l', 'screen'));
      expect(tiles.first, containsPair('m', true));
      expect(tiles.first.keys, containsAll(['l', 'k', 'x', 'y', 'w', 'h', 'f']));
      expect(tiles.last, containsPair('s', true));
      expect(tiles.last, containsPair('n', 'Person a'));
    });
  });

  group('liveRecordsAtStart', () {
    test('a meeting never records by itself, a teacher\'s course session does (when its switch is on)', () {
      expect(liveRecordsAtStart(isMeeting: true, isTeacher: true, recordingEnabled: true, deviceRecorder: true), isFalse);
      expect(liveRecordsAtStart(isMeeting: true, isTeacher: false, recordingEnabled: true, deviceRecorder: true), isFalse);
      expect(liveRecordsAtStart(isMeeting: false, isTeacher: true, recordingEnabled: true, deviceRecorder: true), isTrue);
      expect(liveRecordsAtStart(isMeeting: false, isTeacher: true, recordingEnabled: false, deviceRecorder: true), isFalse);
      expect(liveRecordsAtStart(isMeeting: false, isTeacher: true, recordingEnabled: true, deviceRecorder: false), isFalse);
      expect(liveRecordsAtStart(isMeeting: false, isTeacher: false, recordingEnabled: true, deviceRecorder: true), isFalse);
    });
  });

  group('full view', () {
    test('a phone hides the system bars and turns; leaving gives them back; the web asks nothing', () {
      final on = liveFullViewSystemUi(on: true, mobile: true)!;
      expect(on.mode, SystemUiMode.immersiveSticky);
      expect(on.orientations, containsAll(DeviceOrientation.values));
      expect(liveFullViewSystemUi(on: false, mobile: true)!.mode, SystemUiMode.edgeToEdge);
      expect(liveFullViewSystemUi(on: true, mobile: false), isNull);
    });

    test('the turn hint: a wide page on an upright phone, never on a continuous page or a matching screen', () {
      const upright = Size(390, 844), sideways = Size(844, 390);
      bool hint({bool full = true, bool cont = false, double aspect = 16 / 9, Size box = upright, bool mobile = true}) =>
          boardFullViewTurnHint(fullView: full, continuous: cont, aspect: aspect, box: box, mobile: mobile);
      expect(hint(), isTrue);
      expect(hint(box: sideways), isFalse);
      expect(hint(cont: true), isFalse);
      expect(hint(full: false), isFalse);
      expect(hint(mobile: false), isFalse);
      expect(hint(aspect: 9 / 16, box: sideways), isTrue, reason: 'an upright page on a phone held sideways');
      expect(hint(aspect: 1.05, box: const Size(800, 760)), isFalse, reason: 'shapes that nearly match');
    });
  });

  group('touch scrollbar', () {
    test('a finger gets a longer, wider-held thumb than the mouse', () {
      const touch = BoardRailLook.touch, mouse = BoardRailLook.mouse;
      expect(touch.minThumb, greaterThanOrEqualTo(48));
      expect(touch.hit, greaterThanOrEqualTo(48));
      expect(touch.thumbGrabbed, greaterThan(mouse.thumbGrabbed));
      expect(touch.box, greaterThanOrEqualTo(touch.thumbGrabbed));
      expect(BoardRailLook.of(touch: true), same(touch));
      final m = BoardRailMetrics(track: 400, lo: 0, hi: 20, start: 0, length: 1, minThumb: touch.minThumb, hit: touch.hit);
      expect(m.thumbLength, touch.minThumb);
      final (a, b) = m.thumbHit();
      expect(b - a, greaterThanOrEqualTo(touch.hit));
      final box = BoardRailBox(rect: const Rect.fromLTWH(100, 0, 6, 400), vertical: true, metrics: m);
      expect(box.thumbHitRect.width, touch.hit);
      expect(boardRailHitStrip(const Rect.fromLTWH(100, 0, 6, 400), hit: touch.hit).width, touch.hit);
    });
  });
}
