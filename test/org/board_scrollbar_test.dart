// The whiteboard's rails as scrollbars (D-109), pure: thumb size and position from the view, the thumb dragged back
// to a view start (proportional, clamped), a tap on the track moves a page, the 44 px hit targets, which rail a
// point is on.
import 'dart:ui';

import 'package:flutter_education_app/features/live/room/whiteboard/board_scrollbar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardRailMetrics', () {
    // A page 4 screens long on a 400 px track, the view a quarter of it.
    const m = BoardRailMetrics(track: 400, lo: 0, hi: 2, start: 0.5, length: 0.5);

    test('thumb length and start follow the view', () {
      expect(m.scrollable, isTrue);
      expect(m.thumbLength, 100);
      expect(m.travel, 300);
      expect(m.thumbStart, closeTo(100, 1e-9)); // 0.5 of the 1.5 free → a third of 300
      expect(m.thumbAt(0), 0);
      expect(m.thumbAt(1.5), closeTo(300, 1e-9));
      expect(m.thumbAt(9), closeTo(300, 1e-9), reason: 'clamped');
    });

    test('a short thumb keeps its minimum and the drag still reaches both ends', () {
      const tiny = BoardRailMetrics(track: 200, lo: 0, hi: 100, start: 0, length: 1);
      expect(tiny.thumbLength, kBoardThumbMin);
      expect(tiny.startForThumb(200 - kBoardThumbMin), closeTo(99, 1e-9));
      expect(tiny.startForThumb(0), 0);
    });

    test('dragging the thumb moves the view in proportion to the page, clamped', () {
      expect(m.dragged(0.5, 30), closeTo(0.65, 1e-9)); // 30 px of 300 → 0.15 of the 1.5 free
      expect(m.dragged(0.5, -30), closeTo(0.35, 1e-9));
      expect(m.dragged(0.5, 1000), closeTo(1.5, 1e-9));
      expect(m.dragged(0.5, -1000), 0);
      expect(m.dragged(0.5, double.nan), closeTo(0.5, 1e-9));
      // Round trip: thumb → start → thumb.
      for (final px in [0.0, 12.5, 150.0, 300.0]) {
        expect(m.thumbAt(m.startForThumb(px)), closeTo(px, 1e-9));
      }
    });

    test('a negative range (a page grown to the left) maps the same way', () {
      const side = BoardRailMetrics(track: 300, lo: -1.5, hi: 2.5, start: 0, length: 1);
      expect(side.thumbLength, 75);
      expect(side.thumbStart, closeTo(112.5, 1e-9)); // 1.5 of the 3 free → half of 225
      expect(side.startForThumb(0), -1.5);
      expect(side.startForThumb(225), closeTo(1.5, 1e-9));
    });

    test('a tap on the track moves a page towards it; nothing on the thumb', () {
      expect(m.paged(380), closeTo(0.5 + 0.5 * kBoardTrackPage, 1e-9));
      expect(m.paged(10), closeTo(0.5 - 0.5 * kBoardTrackPage, 1e-9));
      const near = BoardRailMetrics(track: 400, lo: 0, hi: 2, start: 0.2, length: 0.5);
      expect(near.paged(399), closeTo(0.65, 1e-9));
      expect(near.paged(20), 0, reason: 'a page up from 0.2 stops at the top');
      expect(m.paged(150), isNull, reason: 'on the thumb');
      const end = BoardRailMetrics(track: 400, lo: 0, hi: 2, start: 1.5, length: 0.5);
      expect(end.paged(5), closeTo(1.5 - 0.45, 1e-9));
      expect(end.paged(399), isNull, reason: 'the thumb is at the end');
    });

    test('the thumb hit target is at least 44 px, centred on a short thumb', () {
      const tiny = BoardRailMetrics(track: 200, lo: 0, hi: 100, start: 50, length: 1);
      final (a, b) = tiny.thumbHit();
      expect(b - a, kBoardThumbHit);
      expect((a + b) / 2, closeTo(tiny.thumbStart + kBoardThumbMin / 2, 1e-9));
      final (c, d) = m.thumbHit();
      expect((c, d), (m.thumbStart, m.thumbStart + 100), reason: 'a long thumb is its own target');
    });

    test('nothing to scroll: not scrollable, no page, the view kept', () {
      const all = BoardRailMetrics(track: 300, lo: 0, hi: 1, start: 0, length: 1);
      expect(all.scrollable, isFalse);
      expect(all.paged(250), isNull);
      expect(all.startForThumb(100), 0);
      const empty = BoardRailMetrics(track: 0, lo: 0, hi: 2, start: 0, length: 1);
      expect(empty.scrollable, isFalse);
    });
  });

  group('BoardRailBox', () {
    // A vertical rail 6 px wide at x 380, 400 px long; a horizontal one along the bottom.
    const v = BoardRailBox(
        rect: Rect.fromLTWH(380, 10, 6, 400), vertical: true, metrics: BoardRailMetrics(track: 400, lo: 0, hi: 2, start: 0, length: 0.5));
    const h = BoardRailBox(
        rect: Rect.fromLTWH(12, 430, 340, 6), vertical: false, metrics: BoardRailMetrics(track: 340, lo: -1, hi: 2, start: 1, length: 1));

    test('the thumb is hit 22 px each side of a 6 px rail; the track only close to it', () {
      expect(v.thumbHitRect.width, kBoardThumbHit);
      expect(v.hit(const Offset(383 - 21, 40)), BoardRailPart.thumb);
      expect(v.hit(const Offset(383 + 21, 40)), BoardRailPart.thumb);
      expect(v.hit(const Offset(383 - 30, 40)), isNull);
      expect(v.hit(const Offset(383 + 8, 300)), BoardRailPart.track);
      expect(v.hit(const Offset(383 + 20, 300)), isNull, reason: 'the track takes 12 px each side, not 22');
      expect(v.hit(const Offset(383, 420)), isNull, reason: 'past its end');
    });

    test('boardRailHit: the thumb wins over the other rail\'s track; null away from both', () {
      expect(boardRailHit([v, h], const Offset(383, 40))?.rail, same(v));
      final thumbH = h.thumbHitRect.center;
      expect(boardRailHit([v, h], thumbH)?.part, BoardRailPart.thumb);
      expect(boardRailHit([v, h], thumbH)?.rail, same(h));
      expect(boardRailHit([null, h], const Offset(20, 433))?.part, BoardRailPart.track);
      expect(boardRailHit([v, null], const Offset(200, 200)), isNull);
    });

    test('along / across', () {
      expect(v.along(const Offset(0, 110)), 100);
      expect(h.along(const Offset(112, 0)), 100);
      expect(v.across(const Offset(390, 0)), 7);
    });
  });
}
