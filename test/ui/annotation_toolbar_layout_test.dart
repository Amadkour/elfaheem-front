// The annotation toolbar (annotation_toolbar.dart, D-079): host / student / burned-in, wide and compact (with
// the style row open), every size, both languages, text 1.3x — no overflow; 48 px labelled targets; the
// callbacks; the controller-bound toolbar; the web / desktop keyboard shortcuts.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_controller.dart';
import 'package:flutter_education_app/features/live/room/annotation/annotation_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _colors = <Color>[
  Color(0xFFE53935),
  Color(0xFFFFB300),
  Color(0xFF43A047),
  Color(0xFF00ACC1),
  Color(0xFF64B5F6),
  Color(0xFF8E24AA),
  Color(0xFFFFFFFF),
  Color(0xFF212121),
];

Widget _bar({
  bool host = true,
  bool? compact,
  bool styleOpen = false,
  bool burnedIn = false,
  Color color = const Color(0xFFE53935),
  AnnotTool tool = AnnotTool.pen,
  void Function(String)? log,
}) =>
    AnnotationToolbar(
      tool: tool,
      color: color,
      colors: _colors,
      thickness: 1,
      canUndo: true,
      isHost: host,
      allowStudents: true,
      burnedIn: burnedIn,
      compact: compact,
      styleOpen: styleOpen,
      onTool: (t) => log?.call('tool:${t.name}'),
      onColor: (c) => log?.call('color:${c.toARGB32().toRadixString(16)}'),
      onThickness: (i) => log?.call('thickness:$i'),
      onUndo: () => log?.call('undo'),
      onClear: () => log?.call('clear'),
      onAllowStudents: (v) => log?.call('allow:$v'),
      onToggleStyle: () => log?.call('style'),
      onClose: () => log?.call('close'),
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  testWidgets('layout: host (auto width), compact with the style row, student, burned-in, a custom colour', (t) async {
    await expectNoLayoutErrors(
      t,
      () => SingleChildScrollView(
        child: Column(children: [
          _bar(),
          const SizedBox(height: 8),
          _bar(compact: true, styleOpen: true),
          const SizedBox(height: 8),
          _bar(host: false, compact: false),
          const SizedBox(height: 8),
          _bar(burnedIn: true, compact: false, color: const Color(0xFF123456)),
          const SizedBox(height: 8),
          Align(alignment: AlignmentDirectional.centerStart, child: SizedBox(width: 300, child: _bar(styleOpen: true))),
        ]),
      ),
    );
  });

  testWidgets('every control is a labelled 48 px target', (t) async {
    final handle = t.ensureSemantics();
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: false)), scale: 1));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await t.pumpWidget(layoutHost(Center(child: SizedBox(width: 320, child: _bar(styleOpen: true))), scale: 1));
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('compact folds colour + thickness into Style; wide shows them; students get no clear / switch', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: true)), scale: 1));
    expect(find.byKey(const ValueKey('annot.style')), findsOneWidget);
    expect(find.byKey(const ValueKey('annot.color.0')), findsNothing);
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: true, styleOpen: true)), scale: 1));
    expect(find.byKey(const ValueKey('annot.style_panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('annot.thickness.2')), findsOneWidget);
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: false)), scale: 1));
    expect(find.byKey(const ValueKey('annot.style')), findsNothing);
    expect(find.byKey(const ValueKey('annot.color.7')), findsOneWidget);
    expect(find.text('Allow students to draw'), findsOneWidget);
    await t.pumpWidget(layoutHost(Center(child: _bar(host: false, compact: false)), scale: 1));
    expect(find.byKey(const ValueKey('annot.clear')), findsNothing);
    expect(find.byKey(const ValueKey('annot.allow_students')), findsNothing);
    // A colour that is not a preset is shown first, as "Current colour".
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: false, color: const Color(0xFF123456))), scale: 1));
    expect(find.bySemanticsLabel('Current colour'), findsOneWidget);
  });

  testWidgets('callbacks', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final log = <String>[];
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: false, log: log.add)), scale: 1));
    await t.tap(find.byKey(const ValueKey('annot.tool.highlighter')));
    await t.tap(find.byKey(const ValueKey('annot.tool.laser')));
    await t.tap(find.byKey(const ValueKey('annot.undo')));
    await t.tap(find.byKey(const ValueKey('annot.clear')));
    await t.tap(find.byKey(const ValueKey('annot.color.2')));
    await t.tap(find.byKey(const ValueKey('annot.thickness.0')));
    await t.tap(find.byKey(const ValueKey('annot.allow_students')));
    await t.tap(find.byKey(const ValueKey('annot.close')));
    expect(log, ['tool:highlighter', 'tool:laser', 'undo', 'clear', 'color:ff43a047', 'thickness:0', 'allow:false', 'close']);

    // Burned in: the students switch is off and disabled.
    log.clear();
    await t.pumpWidget(layoutHost(Center(child: _bar(compact: false, burnedIn: true, log: log.add)), scale: 1));
    await t.tap(find.byKey(const ValueKey('annot.allow_students')));
    expect(log, isEmpty);
  });

  testWidgets('the controller-bound toolbar: a tool turns draw mode on, close turns it off', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = AnnotationController(localIdentity: 'teacher_1', autoFlush: false);
    addTearDown(c.dispose);
    c.setRoles(hosts: {'teacher_1'});
    var closed = 0;
    await t.pumpWidget(layoutHost(Center(child: AnnotationControllerToolbar(controller: c, compact: false, onClose: () => closed++)),
        scale: 1));
    expect(c.drawMode, isFalse);
    await t.tap(find.byKey(const ValueKey('annot.tool.highlighter')));
    await t.pump();
    expect(c.tool, AnnotTool.highlighter);
    expect(c.drawMode, isTrue);
    await t.tap(find.byKey(const ValueKey('annot.thickness.2')));
    await t.tap(find.byKey(const ValueKey('annot.allow_students')));
    await t.pump();
    expect(c.thickness, 2);
    expect(c.allowStudents, isTrue);
    await t.tap(find.byKey(const ValueKey('annot.close')));
    await t.pump();
    expect(c.drawMode, isFalse);
    expect(closed, 1);
  });

  testWidgets('keyboard shortcuts; ignored while typing in a field', (t) async {
    final log = <String>[];
    final field = FocusNode();
    addTearDown(field.dispose);
    await t.pumpWidget(layoutHost(
      AnnotationShortcuts(
        onTool: (tl) => log.add(tl.name),
        onThickness: (i) => log.add('t$i'),
        onUndo: () => log.add('undo'),
        onClose: () => log.add('close'),
        child: TextField(focusNode: field),
      ),
      scale: 1,
    ));
    await t.sendKeyEvent(LogicalKeyboardKey.keyH);
    await t.sendKeyEvent(LogicalKeyboardKey.keyE);
    await t.sendKeyEvent(LogicalKeyboardKey.digit3);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(log, ['highlighter', 'eraser', 't2', 'undo', 'close']);
    log.clear();
    field.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    expect(log, isEmpty);
  });
}
