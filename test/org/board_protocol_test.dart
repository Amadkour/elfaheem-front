// The live whiteboard's wire format (D-087): lib/features/live/room/whiteboard/board_protocol.dart.
import 'dart:convert';

import 'package:flutter_education_app/features/live/room/annotation/annotation_protocol.dart';
import 'package:flutter_education_app/features/live/room/whiteboard/board_protocol.dart';
import 'package:flutter_education_app/features/live/room/widgets/live_data_route.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _raw(Map<String, Object?> m) => utf8.encode(jsonEncode(m));

void main() {
  test('every message survives encode → decode', () {
    const shape = BoardShape(
        id: 'a1', author: 't', page: 'p0', rev: 2, kind: BoardShapeKind.arrow, x1: 0.1, y1: 0.2, x2: 0.5, y2: 0.6, color: 0xFF112233, width: 0.005);
    const text = BoardText(
        id: 'a2', author: 't', page: 'p0', rev: 1, x: 0.3, y: 0.4, boxWidth: 0.3, size: 0.025, color: 0xFF000000, text: 'مرحبا\nHello');
    final msgs = <BoardMsg>[
      const BoardState(background: BoardBackground.grid, pages: ['p0', 'p1'], page: 'p1'),
      const BoardOff(),
      const BoardInkStart(id: 'k1', page: 'p0', ink: AnnotInk.pen, color: 0xFFE53935, width: 0.004, pressured: true),
      const BoardInkPoints(id: 'k1', points: [AnnotPoint(0.1, 0.2, 0.5), AnnotPoint(0.12345, 0.25, 0.7)]),
      const BoardInkEnd('k1'),
      const BoardPut(shape),
      const BoardPut(text),
      const BoardDelete(['a1', 'a2']),
      const BoardClearPage('p0'),
      const BoardSnapshotRequest(),
      const BoardLaser(x: 0.5, y: 0.25),
    ];
    for (final m in msgs) {
      final back = BoardCodec.decode(BoardCodec.encode(m), topic: m.topic);
      expect(back, isNotNull, reason: m.runtimeType.toString());
      expect(back!.body(), m.body(), reason: m.runtimeType.toString());
    }
  });

  test('the board travels on its own topics, never on the annotation ones', () {
    expect(const BoardLaser(x: 0, y: 0).topic, kBoardLaserTopic);
    expect(const BoardLaser(x: 0, y: 0).reliable, isFalse);
    expect(const BoardOff().topic, kBoardTopic);
    expect(kBoardTopic, isNot(kAnnotTopic));
    // A laser packet on the reliable topic (or the other way round) is not taken.
    expect(BoardCodec.decode(BoardCodec.encode(const BoardLaser(x: 0.1, y: 0.1))), isNull);
    expect(BoardCodec.decode(BoardCodec.encode(const BoardOff()), topic: kBoardLaserTopic), isNull);
    // The room routes them (an older app, which lacks the route, drops them as unknown topics).
    expect(liveDataRoute(kBoardTopic), LiveDataRoute.board);
    expect(liveDataRoute(kBoardLaserTopic), LiveDataRoute.board);
  });

  test('malformed, unknown or oversized packets decode to null', () {
    expect(BoardCodec.decode(const []), isNull);
    expect(BoardCodec.decode(utf8.encode('not json')), isNull);
    expect(BoardCodec.decode(_raw({'v': 2, 't': 'off'})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'zz'})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'on', 'pages': [], 'pg': 'p0'})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'on', 'pages': ['p0'], 'pg': 'p9'})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'on', 'pages': ['p0', 'p0'], 'pg': 'p0'})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'del', 'ids': []})), isNull);
    expect(BoardCodec.decode(_raw({'v': 1, 't': 'put', 'el': {'k': 'zz', 'id': 'a', 'pg': 'p', 'a': 'x'}})), isNull);
    // Ink never comes as a put (it is streamed).
    expect(
        BoardCodec.decode(_raw({
          'v': 1,
          't': 'put',
          'el': {'k': 'in', 'id': 'a', 'a': 't', 'pg': 'p', 'tl': 'p', 'c': 1, 'w': 0.004, 'p': []},
        })),
        isNull);
    expect(
        BoardCodec.decode(_raw({
          'v': 1,
          't': 'put',
          'el': {'k': 'tx', 'id': 'a', 'a': 't', 'pg': 'p', 'x': 0, 'y': 0, 'bw': 0.3, 'fs': 0.02, 'c': 1, 'tx': 'x' * (kBoardMaxText + 1)},
        })),
        isNull);
  });

  test('a newer board: unknown background draws white, a higher feature version is kept for "update the app"', () {
    final m = BoardCodec.decode(_raw({'v': 1, 't': 'on', 'bv': 7, 'bg': 'pdf', 'pages': ['p0'], 'pg': 'p0', 'extra': 1}))
        as BoardState;
    expect(m.background, BoardBackground.white);
    expect(m.featureVersion, 7);
    // A snapshot keeps the items it knows and skips the kinds it does not.
    final snap = BoardCodec.decode(_raw({
      'v': 1,
      't': 'snap',
      'sid': 's',
      'i': 0,
      'n': 1,
      'els': [
        {'k': 'img', 'id': 'z', 'a': 't', 'pg': 'p0'},
        const BoardShape(id: 'a', author: 't', page: 'p0', kind: BoardShapeKind.rect, x1: 0, y1: 0, x2: 1, y2: 1, color: 1, width: 0.004)
            .toJson(),
      ],
    })) as BoardSnapshotChunk;
    expect(snap.items.map((i) => i.id), ['a']);
  });

  test('every background has a code and round-trips', () {
    for (final b in BoardBackground.values) {
      expect(boardBackgroundOf(boardBackgroundCode(b)), b);
    }
    expect(boardIsDark(BoardBackground.blackboard), isTrue);
    expect(boardIsDark(BoardBackground.grid), isFalse);
  });

  test('snapshot chunks stay under the limit; a long ink is split and put back together', () {
    final long = BoardInk(
      id: 'big',
      author: 't',
      page: 'p0',
      ink: AnnotInk.pen,
      color: 0xFF000000,
      width: 0.004,
      points: [for (var i = 0; i < 3000; i++) AnnotPoint.wire(i / 3000, (i % 97) / 97, 0.5)],
      open: false,
    );
    final items = <BoardItem>[
      long,
      for (var i = 0; i < 40; i++)
        BoardText(id: 't$i', author: 's', page: 'p1', x: 0.1, y: 0.1, boxWidth: 0.3, size: 0.025, color: 1, text: 'سطر $i ' * 20),
    ];
    final chunks = BoardCodec.snapshotChunks(items, sid: 'x1');
    expect(chunks.length, greaterThan(2));
    for (final c in chunks) {
      expect(c.length, lessThanOrEqualTo(kAnnotMaxReliableBytes));
    }
    final asm = BoardSnapshotAssembler();
    List<BoardItem>? out;
    for (final c in chunks.reversed) {
      out = asm.add('t', BoardCodec.decode(c) as BoardSnapshotChunk);
    }
    expect(out, isNotNull);
    final ink = out!.whereType<BoardInk>().single;
    expect(ink.points, long.points);
    expect(out.whereType<BoardText>().length, 40);
    // An empty board is one chunk with nothing in it.
    final empty = BoardCodec.snapshotChunks(const [], sid: 'e');
    expect(empty.length, 1);
    expect((BoardCodec.decode(empty.single) as BoardSnapshotChunk).items, isEmpty);
  });

  test('text direction follows the first strong character', () {
    expect(boardTextIsRtl('مرحبا Hello', fallbackRtl: false), isTrue);
    expect(boardTextIsRtl('Hello مرحبا', fallbackRtl: true), isFalse);
    expect(boardTextIsRtl('123 - ', fallbackRtl: true), isTrue);
    expect(boardTextIsRtl('', fallbackRtl: false), isFalse);
    expect(boardTextIsRtl('  (٣) قانون', fallbackRtl: false), isTrue);
  });

  test('shape geometry: moved, clamped, tiny', () {
    const s = BoardShape(id: 'a', author: 't', page: 'p', kind: BoardShapeKind.line, x1: 0.9, y1: 0.1, x2: 0.95, y2: 0.2, color: 1, width: 0.004);
    final m = s.moved(0.2, -0.2);
    expect(m.x2, 1.0);
    expect(m.y1, 0.0);
    expect(s.isTiny, isFalse);
    expect(s.copyWith(x2: 0.9, y2: 0.1).isTiny, isTrue);
  });
}
