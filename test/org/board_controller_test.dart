// The live whiteboard's state machine (D-087): lib/features/teacher/sessions/live/whiteboard/board_controller.dart.
// A tiny "room" passes every packet one device sends to the others, with the REAL sender identity.
import 'dart:convert';

import 'package:flutter_education_app/features/teacher/sessions/live/annotation/annotation_protocol.dart' show AnnotInk;
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_controller.dart';
import 'package:flutter_education_app/features/teacher/sessions/live/whiteboard/board_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class _Room {
  final Map<String, BoardController> peers = {};
  final List<(String from, Map<String, Object?> msg, List<String>? to)> log = [];
  final Set<String> hosts = {'teacher_1'};
  final Set<String> drawers = {};
  final Set<String> presenters = {'teacher_1', 'student_9'};

  BoardController join(String id) {
    final c = BoardController(
      localIdentity: id,
      autoFlush: false,
      idPrefix: '${id[0]}${peers.length}',
      isHost: hosts.contains,
      mayPresent: presenters.contains,
      studentMayDraw: drawers.contains,
    );
    c.send = (topic, bytes, reliable, {to}) async {
      log.add((id, jsonDecode(utf8.decode(bytes)) as Map<String, Object?>, to));
      for (final e in peers.entries) {
        if (e.key == id || (to != null && !to.contains(e.key))) continue;
        e.value.receive(topic, bytes, sender: id);
      }
    };
    peers[id] = c;
    return c;
  }

  int count(String type) => log.where((l) => l.$2['t'] == type).length;
}

void main() {
  late _Room room;
  late BoardController teacher;
  late BoardController student;

  setUp(() {
    room = _Room();
    teacher = room.join('teacher_1');
    student = room.join('student_2');
  });

  test('presenting: everyone sees the board, its background and the page; stopping drops it for viewers only', () {
    teacher.startPresenting(background: BoardBackground.grid);
    expect(teacher.isLocalPresenting, isTrue);
    expect(student.presenter, 'teacher_1');
    expect(student.background, BoardBackground.grid);
    expect(student.pageCount, 1);

    teacher.beginInk(0.1, 0.1);
    teacher.moveInk(0.2, 0.3);
    teacher.endInk();
    expect(student.scene.visibleItems.single, isA<BoardInk>());
    expect((student.scene.visibleItems.single as BoardInk).points.length, 2);

    teacher.stopPresenting();
    expect(student.active, isFalse);
    expect(student.scene.itemCount, 0);
    // The presenter finds the board again when presenting again (a switch to a screen share and back).
    teacher.startPresenting(background: BoardBackground.blackboard);
    expect(teacher.scene.itemCount, 1);
    expect(student.background, BoardBackground.blackboard);
  });

  test('a late joiner gets the state and every item through the snapshot', () {
    teacher.startPresenting(background: BoardBackground.lined);
    teacher.beginInk(0.1, 0.1);
    teacher.moveInk(0.3, 0.3);
    teacher.endInk();
    teacher.setTool(BoardTool.rect);
    teacher.beginShape(BoardShapeKind.rect, 0.2, 0.2);
    teacher.moveShape(0.5, 0.6);
    teacher.endShape();
    final id = teacher.createText(0.6, 0.1)!;
    teacher.updateText(id, text: 'قانون نيوتن الثاني');
    teacher.endEdit(id);
    teacher.addPage();
    teacher.flush();

    final joiner = room.join('student_3');
    joiner.requestSnapshot();
    expect(joiner.presenter, 'teacher_1');
    expect(joiner.background, BoardBackground.lined);
    expect(joiner.pageCount, 2);
    expect(joiner.pageIndex, 1);
    expect(joiner.scene.itemCount, 3);
    expect(joiner.scene.items.whereType<BoardText>().single.text, 'قانون نيوتن الثاني');
    // Only the presenter answered.
    expect(room.log.where((l) => l.$2['t'] == 'snap').every((l) => l.$1 == 'teacher_1'), isTrue);
  });

  test('students draw only when allowed; a student edits only their own items', () {
    teacher.startPresenting();
    expect(student.canDrawLocal, isFalse);
    expect(student.beginInk(0.5, 0.5), isFalse);

    room.drawers.add('student_2');
    student.permissionsChanged();
    expect(student.canDrawLocal, isTrue);
    student.beginInk(0.5, 0.5);
    student.moveInk(0.6, 0.6);
    student.endInk();
    expect(teacher.scene.itemCount, 1);

    // The teacher's text: the student may not move or erase it.
    final id = teacher.createText(0.1, 0.1)!;
    teacher.updateText(id, text: 'Title');
    teacher.endEdit(id);
    student.moveItem(id, 0.2, 0.2);
    expect((teacher.scene.item(id) as BoardText).x, 0.1);
    student.setTool(BoardTool.eraser);
    student.eraseAt(0.15, 0.12);
    student.endErase();
    expect(teacher.scene.item(id), isNotNull);

    // A forged packet from a student who may not draw is dropped.
    room.drawers.clear();
    final intruder = room.join('student_4');
    intruder.send!(kBoardTopic,
        BoardCodec.encode(const BoardInkStart(id: 'zz', page: 'x', ink: AnnotInk.pen, color: 1, width: 0.004)), true);
    expect(teacher.scene.item('zz'), isNull);
  });

  test('only someone allowed to present can take the stage', () {
    final other = room.join('student_5'); // not a presenter
    other.startPresenting();
    expect(student.active, isFalse);
    expect(teacher.active, isFalse);
  });

  test('undo / redo of ink, shapes, text edits and erases, for everyone', () {
    teacher.startPresenting();
    teacher.beginInk(0.1, 0.1);
    teacher.moveInk(0.4, 0.4);
    teacher.endInk();
    teacher.beginShape(BoardShapeKind.ellipse, 0.5, 0.5);
    teacher.moveShape(0.7, 0.8);
    teacher.endShape();
    final id = teacher.createText(0.1, 0.6)!;
    teacher.updateText(id, text: 'v1');
    teacher.endEdit(id);
    teacher.beginEdit(id);
    teacher.updateText(id, text: 'v2');
    teacher.endEdit(id);
    expect((student.scene.item(id) as BoardText).text, 'v2');

    teacher.undo(); // the edit
    teacher.flush();
    expect((student.scene.item(id) as BoardText).text, 'v1');
    teacher.redo();
    expect((student.scene.item(id) as BoardText).text, 'v2');
    teacher.undo();
    teacher.undo(); // the text box itself
    expect(student.scene.item(id), isNull);
    teacher.undo(); // the ellipse
    expect(student.scene.items.whereType<BoardShape>(), isEmpty);
    teacher.redo(); // the ellipse is back, same id
    expect(student.scene.items.whereType<BoardShape>().length, 1);

    // Erase, then undo the erase: the ink comes back with all its points.
    final ink = teacher.scene.items.whereType<BoardInk>().single;
    teacher.setTool(BoardTool.eraser);
    teacher.eraseAt(0.25, 0.25);
    teacher.endErase();
    expect(student.scene.items.whereType<BoardInk>(), isEmpty);
    teacher.undo();
    final back = student.scene.items.whereType<BoardInk>().single;
    expect(back.id, ink.id);
    expect(back.points, ink.points);
    expect(back.open, isFalse);
    expect(teacher.canRedo, isTrue);
  });

  test('a fresh text box goes out only once it has text; an emptied one is removed', () {
    teacher.startPresenting();
    final id = teacher.createText(0.3, 0.3)!;
    teacher.flush();
    expect(room.count('put'), 0);
    teacher.endEdit(id);
    expect(teacher.scene.item(id), isNull); // nothing typed: gone, no undo step
    expect(teacher.canUndo, isFalse);

    final id2 = teacher.createText(0.3, 0.3)!;
    teacher.updateText(id2, text: 'Hi');
    teacher.flush();
    expect(student.scene.item(id2), isNotNull);
    teacher.beginEdit(id2);
    teacher.updateText(id2, text: '  ');
    teacher.endEdit(id2);
    expect(student.scene.item(id2), isNull);
  });

  test('moving, restyling and resizing a text box', () {
    teacher.startPresenting();
    final id = teacher.createText(0.2, 0.2)!;
    teacher.updateText(id, text: 'Box');
    teacher.endEdit(id);
    teacher.setTool(BoardTool.select);
    teacher.select(id);
    teacher.setFontStep(3);
    teacher.setColor(0xFF0000FF);
    teacher.moveItem(id, 0.1, 0.05);
    teacher.updateText(id, boxWidth: 0.5);
    teacher.endEdit(id);
    final t = student.scene.item(id) as BoardText;
    expect(t.size, kBoardFontSizes[3]);
    expect(t.color, 0xFF0000FF);
    expect(t.x, closeTo(0.3, 1e-9));
    expect(t.boxWidth, 0.5);
    teacher.undo(); // move + resize
    expect((student.scene.item(id) as BoardText).x, closeTo(0.2, 1e-9));
    teacher.deleteSelected();
    expect(student.scene.item(id), isNull);
  });

  test('pages: add, move, delete; viewers follow the presenter', () {
    teacher.startPresenting();
    teacher.beginInk(0.1, 0.1);
    teacher.endInk();
    teacher.addPage();
    expect(student.pageIndex, 1);
    expect(student.scene.pageEmpty, isTrue);
    teacher.previousPage();
    expect(student.pageIndex, 0);
    expect(student.scene.pageEmpty, isFalse);
    teacher.deletePage();
    expect(student.pageCount, 1);
    expect(student.scene.itemCount, 0);
  });

  test('clear page is for leads and leaves other pages alone', () {
    room.drawers.add('student_2');
    teacher.startPresenting();
    teacher.beginInk(0.1, 0.1);
    teacher.endInk();
    teacher.addPage();
    teacher.beginInk(0.2, 0.2);
    teacher.endInk();
    student.clearPage();
    expect(teacher.scene.itemCount, 2);
    teacher.clearPage();
    expect(student.scene.itemCount, 1);
    teacher.undo();
    expect(student.scene.itemCount, 2);
  });

  test('a host who presents takes over: the student presenter keeps their board locally', () {
    final presenter = room.join('student_9');
    presenter.startPresenting();
    presenter.beginInk(0.1, 0.1);
    presenter.endInk();
    expect(teacher.presenter, 'student_9');
    teacher.startPresenting(background: BoardBackground.blackboard);
    expect(presenter.presenter, 'teacher_1');
    expect(presenter.isLocalPresenting, isFalse);
    expect(presenter.scene.itemCount, 0);
    expect(student.background, BoardBackground.blackboard);
  });

  test('the presenter leaving ends the board for everyone', () {
    teacher.startPresenting();
    student.participantLeft('teacher_1');
    expect(student.active, isFalse);
  });

  test('a newer presenter: "update the app"', () {
    student.receive(
        kBoardTopic, utf8.encode(jsonEncode({'v': 1, 't': 'on', 'bv': 9, 'bg': 'w', 'pages': ['p'], 'pg': 'p'})),
        sender: 'teacher_1');
    expect(student.active, isTrue);
    expect(student.needsUpdate, isTrue);
  });

  test('shape hit tests and the laser', () {
    teacher.startPresenting();
    teacher.beginShape(BoardShapeKind.rect, 0.2, 0.2);
    teacher.moveShape(0.4, 0.4);
    teacher.endShape();
    expect(teacher.hitTest(0.3, 0.2), isNotEmpty); // on the top edge
    expect(teacher.hitTest(0.3, 0.3), isEmpty); // inside, not on the outline
    expect(teacher.selectableAt(0.4, 0.3), isNotNull);
    teacher.pointLaser(0.5, 0.5);
    expect(student.scene.lasers.single.x, 0.5);
    // A click with a shape tool makes nothing.
    teacher.beginShape(BoardShapeKind.line, 0.6, 0.6);
    teacher.endShape();
    expect(student.scene.items.whereType<BoardShape>().length, 1);
  });
}
