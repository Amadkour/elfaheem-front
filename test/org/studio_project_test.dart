// The Studio's edit list and history (D-590 … D-593): splits, removes, trims and speed on the clips; overlays anchored
// to the source; undo / redo / restore; the saved doc; the render params; the preview's animation curves; moving a part
// (D-823) and which saved copy opens the Studio (D-826).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/records/studio_autosave.dart';
import 'package:flutter_education_app/features/records/studio_project.dart';
import 'package:flutter_test/flutter_test.dart';

StudioOverlay _text(double a, double b, {String text = 'Hello', StudioAnim inA = StudioAnim.fade, StudioAnim outA = StudioAnim.fade}) =>
    StudioOverlay(id: 'o1', kind: StudioOverlayKind.text, start: a, end: b, text: text, inAnim: inA, outAnim: outA);

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('clips', () {
    test('split cuts the clip under the playhead; near an edge it does nothing', () {
      final e = StudioEdit.original(100).split(40);
      expect(e.clips.map((c) => (c.start, c.end)).toList(), [(0.0, 40.0), (40.0, 100.0)]);
      expect(identical(e.split(40.05), e), isTrue, reason: 'a split 0.05 s from a cut is ignored');
      expect(e.duration, 100);
    });

    test('remove closes the gap; the parts on both sides stay', () {
      final e = StudioEdit.original(100).remove(10, 25);
      expect(e.duration, closeTo(85, 1e-9));
      expect(e.clips.map((c) => (c.start, c.end)).toList(), [(0.0, 10.0), (25.0, 100.0)]);
      // output time 10 is now source 25
      expect(e.hit(10)!.source, closeTo(25, 1e-9));
      expect(e.outputOf(30), closeTo(15, 1e-9));
      expect(e.outputOf(20), isNull, reason: 'that moment was removed');
      expect(identical(e.remove(0, e.duration), e), isTrue, reason: 'never removes everything');
    });

    test('keep only, delete a part', () {
      final e = StudioEdit.original(60).keepOnly(20, 30);
      expect(e.clips.single.start, 20);
      expect(e.duration, closeTo(10, 1e-9));
      final d = StudioEdit.original(60).split(20).split(40).deleteClip(1);
      expect(d.duration, closeTo(40, 1e-9));
      expect(StudioEdit.original(60).deleteClip(0).clips.length, 1, reason: 'the last part stays');
    });

    test('trims stay inside the neighbours and the source', () {
      final e = StudioEdit.original(100).split(50).remove(40, 60); // [0,40] [60,100]
      expect(e.trimEnd(0, 70, 100).clips[0].end, 60, reason: 'not into the next part');
      expect(e.trimStart(1, 10).clips[1].start, 40, reason: 'not over the previous part');
      expect(e.trimStart(1, 99.95).clips[1].start, closeTo(100 - studioMinClip, 1e-9));
      expect(e.trimEnd(1, 130, 100).clips[1].end, 100);
    });

    test('speed on a marked period splits at its ends; a clip speed halves its length', () {
      final e = StudioEdit.original(100).speedOn(2, a: 20, b: 40);
      expect(e.clips.length, 3);
      expect(e.clips[1].speed, 2);
      expect(e.duration, closeTo(90, 1e-9));
      final c = StudioEdit.original(100).speedOn(0.5, clip: 0);
      expect(c.duration, 200);
      expect(c.hit(100)!.source, closeTo(50, 1e-9));
    });
  });

  group('overlays', () {
    test('an overlay sticks to what it was put on (D-592)', () {
      final e = StudioEdit.original(100).putOverlay(_text(50, 55));
      expect(e.overlayOut(e.overlays.first), (50.0, 55.0));
      final cut = e.remove(10, 20);
      expect(cut.overlayOut(cut.overlays.first), (40.0, 45.0), reason: 'moved along with its content');
      final gone = e.remove(49, 56);
      expect(gone.overlayOut(gone.overlays.first), isNull, reason: 'everything it covered was removed');
      final half = e.remove(52, 70);
      final s = half.overlayOut(half.overlays.first)!;
      expect(s.$2 - s.$1, closeTo(2, 1e-9), reason: 'a removed part under it shortens it');
    });

    test('anchoring an output range back to the source', () {
      final e = StudioEdit.original(100).remove(10, 20); // output 10 = source 20
      expect(e.anchor(10), closeTo(20, 1e-9));
      expect(e.anchor(10, end: true), closeTo(10, 1e-9), reason: 'an end on a cut belongs to the part before');
    });

    test('render params: output times, text width, RTL and the letters to type', () {
      final e = StudioEdit.original(100).remove(0, 10).putOverlay(_text(20, 30, text: 'مرحبا بكم', inA: StudioAnim.typewriter));
      final p = studioRenderParams(e, assets: {'o1': 'a' * 32}, textWidths: {'o1': 0.42}, title: ' New ');
      final o = (p['overlays'] as List).single as Map;
      expect([o['start'], o['end']], [10.0, 20.0]);
      expect(o['w'], 0.42);
      expect(o['rtl'], isTrue);
      expect(o['chars'], 8);
      expect((o['in'] as Map)['type'], 'typewriter');
      expect(p['title'], 'New');
      expect((p['clips'] as List).single, {'start': 10.0, 'end': 100.0, 'speed': 1.0});
      final none = studioRenderParams(e, assets: const {});
      expect(none['overlays'], isEmpty, reason: 'an overlay without its PNG is left out');
    });

    test('the look follows the same curves as the render', () {
      final o = _text(0, 10, inA: StudioAnim.fade, outA: StudioAnim.slideDown);
      expect(studioOverlayLook(o, 0, 10, -1), isNull);
      expect(studioOverlayLook(o, 0, 10, 0.25)!.opacity, closeTo(0.5, 1e-9), reason: 'linear fade over 0.5 s');
      expect(studioOverlayLook(o, 0, 10, 5)!.opacity, 1);
      final leaving = studioOverlayLook(o, 0, 10, 9.9)!;
      expect(leaving.dy, greaterThan(0), reason: 'slides down on its way out');
      final pop = studioOverlayLook(_text(0, 10, inA: StudioAnim.pop), 0, 10, 0)!;
      expect(pop.scale, closeTo(0.6, 1e-9));
      final tw = studioOverlayLook(_text(0, 10, text: 'abcd', inA: StudioAnim.typewriter), 0, 10, 0.26)!;
      expect(tw.reveal, 0.5, reason: 'two of four letters after half the time');
    });
  });

  group('history', () {
    test('undo, redo, restore and a new step after undo', () {
      var h = StudioHistory.start(100);
      h = h.commit(StudioStepKind.split, h.current.split(30), info: {'at': 30});
      h = h.commit(StudioStepKind.remove, h.current.remove(10, 20), info: {'a': 10, 'b': 20});
      expect(h.steps.length, 3);
      expect(h.current.duration, 90);
      h = h.undo();
      expect(h.current.duration, 100);
      expect(h.canRedo, isTrue);
      h = h.redo();
      expect(h.current.duration, 90);
      h = h.restore(0);
      expect(h.undone, 2);
      h = h.commit(StudioStepKind.speed, h.current.speedOn(2, clip: 0), info: {'speed': 2.0, 'a': 0, 'b': 100});
      expect(h.steps.length, 2, reason: 'the undone steps go');
      expect(identical(h.commit(StudioStepKind.speed, h.current), h), isTrue, reason: 'nothing changed: no step');
    });

    test('the saved doc round-trips and refuses another source', () {
      var h = StudioHistory.start(100);
      h = h.commit(StudioStepKind.textAdd, h.current.putOverlay(_text(5, 9)), info: {'name': 'Hello'});
      final j = h.toJson(100);
      final back = StudioHistory.fromJson(j, duration: 100)!;
      expect(back.steps.length, 2);
      expect(back.current.overlays.single.text, 'Hello');
      expect(StudioHistory.fromJson(j, duration: 300), isNull);
      expect(studioStepLabel(back.steps.last), 'Added the text “Hello”');
    });

    test('the history keeps the original first when it is full', () {
      var h = StudioHistory.start(1000);
      for (var i = 1; i < studioMaxSteps + 10; i++) {
        h = h.commit(StudioStepKind.split, h.current.split(i * 5.0), info: {'at': i * 5.0});
      }
      expect(h.steps.length, studioMaxSteps);
      expect(h.steps.first.kind, StudioStepKind.open);
    });

    test('two files split the edit at the playhead', () {
      final e = StudioEdit.original(100).remove(10, 20);
      final (a, b) = studioHalves(e, 40)!;
      expect(a.duration, closeTo(40, 1e-9));
      expect(b.duration, closeTo(50, 1e-9));
      expect(studioHalves(e, 0.2), isNull);
    });
    test('a part moves to another place; its edges stop at its SOURCE neighbours, not its play neighbours (D-823)', () {
      final e = StudioEdit.original(90).split(30).split(60); // [0-30][30-60][60-90]
      final m = e.moveClip(2, 0); // [60-90][0-30][30-60]
      expect([for (final c in m.clips) c.start], [60, 0, 30]);
      expect(m.duration, closeTo(90, 1e-9));
      expect(m.reordered, isTrue);
      expect(identical(e.moveClip(1, 1), e), isTrue);
      // the first-played part [60-90]: its start may not go back over [30-60], which lies before it in the source
      expect(m.startBounds(0).$1, 60);
      // [0-30] (played second) may grow to 30, where [30-60] begins — not to 60
      expect(m.endBounds(1, 90).$2, 30);
      // an overlay anchored in the source follows its part to the front
      final o = m.putOverlay(const StudioOverlay(id: 'x', kind: StudioOverlayKind.text, start: 65, end: 70, text: 'Hi'));
      expect(o.overlayOut(o.overlays.single), (5.0, 10.0));
      final h = StudioHistory.start(90).commit(StudioStepKind.moveClip, m, info: {'to': 1});
      expect(studioStepLabel(h.steps.last), 'Moved a part to place 1');
    });

    test('which saved copy opens: unsent work on the device wins unless the server moved on (D-826)', () {
      final server = {'rev': 4, 'v': 1};
      final mine = StudioLocalCopy(doc: const {'rev': 5, 'v': 1, 'mine': true}, dirty: true, base: 4);
      expect(studioPickProject(server: server, local: mine).$2, isTrue, reason: 'made from rev 4, the server still has 4');
      expect(studioPickProject(server: {'rev': 6}, local: mine).$2, isFalse, reason: 'another device saved since');
      expect(studioPickProject(server: null, local: mine, serverFailed: true).$2, isTrue, reason: 'offline');
      expect(studioPickProject(server: server, local: const StudioLocalCopy(doc: {'rev': 3}, dirty: false)).$1, server);
      expect(studioPickProject().$1, isNull);
      expect(studioDocRev({'rev': '7'}), 7);
    });

    test('unsent work here that another device saved past is a choice, not a silent server win (D-831)', () {
      final mine = StudioLocalCopy(doc: const {'rev': 5, 'v': 1}, dirty: true, base: 4);
      expect(studioProjectConflict(server: {'rev': 9}, local: mine), isTrue);
      expect(studioProjectConflict(server: {'rev': 4}, local: mine), isFalse, reason: 'the server did not move: mine opens');
      expect(studioProjectConflict(server: {'rev': 9}, local: mine, serverFailed: true), isFalse);
      expect(studioProjectConflict(server: {'rev': 9}, local: const StudioLocalCopy(doc: {'rev': 5}, dirty: false, base: 4)), isFalse);
      expect(studioProjectConflict(server: null, local: mine), isFalse);
    });

    test('Trim start / Trim end cut the part under the playhead at the playhead (D-904)', () {
      final e = StudioEdit.original(90).split(30); // [0-30][30-90]
      final (a, i, src) = studioTrimAt(e, 40, start: true, sourceDuration: 90)!;
      expect((i, src), (1, 40.0));
      expect([a.clips[1].start, a.clips[1].end], [40, 90]);
      expect(a.duration, closeTo(80, 1e-9));
      final (b, j, _) = studioTrimAt(e, 10, start: false, sourceDuration: 90)!;
      expect((j, b.clips[0].end), (0, 10.0));
      expect(studioTrimAt(e, 0, start: true, sourceDuration: 90), isNull, reason: 'already the start: nothing to cut');
      // at ×2 the playhead's output second maps to the source at twice the pace
      final f = StudioEdit.original(90).speedOn(2, clip: 0);
      expect(studioTrimAt(f, 10, start: false, sourceDuration: 90)!.$3, 20);
      // the selected part wins when the playhead sits on the edge it shares with the next one
      expect(studioTrimAt(e, 30, start: false, selected: 0, sourceDuration: 90), isNull);
      expect(studioTrimAt(e, 30, start: false, sourceDuration: 90)!.$2, 1);
    });

    test('an export a project remembers is followed again after a reload (D-905)', () {
      expect(studioDocJobs({'export': {'jobs': [12, '13', 'x']}}), [12, 13]);
      expect(studioDocJobs({'export': {'height': 720}}), isEmpty);
      expect(studioDocJobs(null), isEmpty);
    });

    test('a 409 body is read as a Map or a JSON string; an unreadable one gives no revision (D-832)', () {
      final asMap = studioConflictOf({'detail': {'code': 'project_conflict', 'doc': {'rev': 9, 'v': 1}}});
      expect((asMap.rev, asMap.doc?['v']), (9, 1));
      final asString = studioConflictOf('{"detail":{"code":"project_conflict","doc":{"rev":9,"v":1}}}');
      expect(asString.rev, 9, reason: 'ApiException.body can be the raw JSON text');
      final broken = studioConflictOf('<html>gateway</html>');
      expect((broken.doc, broken.rev), (null, null), reason: 'never 0: that re-sent base 0 and looped a 409');
      expect(studioConflictOf({'detail': {'code': 'project_conflict'}}).rev, isNull);
    });
  });
}
