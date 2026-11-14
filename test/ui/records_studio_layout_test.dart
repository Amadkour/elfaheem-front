// The Studio (D-312, redesigned D-820 … D-829) and sharing a record: the plain-values widgets on every screen size and
// language (no overflow, text scale 1.3), plus what they say and send — the top bar's Undo / Redo / Export, the action
// bars, the Export panel (Export off while there is a problem), the timeline's left-to-right time in Arabic, its
// tracks and drag-to-reorder, the share sheet's Save rule.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppButton;
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_share_api.dart';
import 'package:flutter_education_app/features/records/records_share_parts.dart';
import 'package:flutter_education_app/features/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/records/studio_export.dart';
import 'package:flutter_education_app/features/records/studio_panels.dart';
import 'package:flutter_education_app/features/records/studio_project.dart';
import 'package:flutter_education_app/features/records/studio_timeline.dart';
import 'package:flutter_education_app/features/sessions/video/vod_player_parts.dart' show VodAction, VodActionButton;
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

RecordItem _item(int id, {String quality = '720p', String? cover}) => RecordItem.fromJson({
      'recording_id': id,
      'kind': 'meeting',
      'status': 'done',
      'quality': quality,
      'destination': 'google_drive',
      'size': 734003200,
      'duration_seconds': 5400.0,
      'remote_url': 'https://drive.google.com/file/d/$id/view',
      'created_at': '2026-11-08T09:00:00',
      'title': 'Weekly planning sync with the whole department and guests #$id',
      'cover_url': cover,
      'meeting': {'id': 7, 'title': 'Weekly planning sync', 'starts_at': '2026-11-08T08:00:00'},
      'can_edit': true,
      'can_play': true,
    })!;

StudioEdit _edit() => StudioEdit.original(5400)
    .split(600)
    .remove(1200, 1500)
    .speedOn(1.5, clip: 0)
    .putOverlay(const StudioOverlay(id: 'o1', kind: StudioOverlayKind.text, start: 700, end: 760, text: 'مرحبا بكم في الدرس الأول'))
    .putOverlay(const StudioOverlay(id: 'o2', kind: StudioOverlayKind.image, start: 740, end: 900, asset: 'a1', aspect: 0.5));

StudioHistory _history() {
  var h = StudioHistory.start(5400, now: DateTime(2026, 11, 10, 9));
  h = h.commit(StudioStepKind.split, h.current.split(600), info: {'at': 600.0}, now: DateTime(2026, 11, 10, 9, 1));
  h = h.commit(StudioStepKind.remove, h.current.remove(1200, 1500), info: {'a': 1200.0, 'b': 1500.0}, now: DateTime(2026, 11, 10, 9, 2));
  h = h.commit(StudioStepKind.textAdd, _edit(), info: {'name': 'A rather long text that someone typed'}, now: DateTime(2026, 11, 10, 9, 3));
  return h.undo();
}

Widget _panel(StudioTool tool, RecordItem item, List<RecordItem> others) {
  final e = _edit();
  switch (tool) {
    case StudioTool.edit:
      return StudioEditPanel(edit: e, position: 1200, markIn: 300, markOut: 900, selectedClip: 1, onSplit: () {}, onSpeed: (_) {});
    case StudioTool.text:
      return StudioOverlayPanel(kind: StudioOverlayKind.text, edit: e, position: 720, selected: e.overlays.first, onChange: (_, {required commit, required kind}) {});
    case StudioTool.image:
      return StudioOverlayPanel(kind: StudioOverlayKind.image, edit: e, position: 720, onAdd: (_, {text, background, size}) {});
    case StudioTool.history:
      return StudioHistoryPanel(history: _history(), onRestore: (_) {}, onReset: () {}, clock: (at) => '09:0${at.minute}');
    default:
      return StudioToolPanel(
        tool: tool,
        item: item,
        duration: e.duration,
        height: 1080,
        level: StudioQualityLevel.best,
        merge: studioMergePicks(item, [item, ...others], [3]),
        showImages: false,
        onQuality: (_, _) {},
        onPickCover: () {},
        onToggleMerge: (_) {},
      );
  }
}

List<StudioAction> _acts() => [
      StudioAction(id: 'split', icon: Icons.content_cut_rounded, label: 'Split', onTap: () {}),
      StudioAction(id: 'speed', icon: Icons.speed_rounded, label: 'Speed', onTap: () {}),
      StudioAction(id: 'move_back', icon: Icons.keyboard_double_arrow_left_rounded, label: 'Earlier'),
      StudioAction(id: 'move_fwd', icon: Icons.keyboard_double_arrow_right_rounded, label: 'Later', onTap: () {}),
      StudioAction(id: 'delete_clip', icon: Icons.delete_outline_rounded, label: 'Delete', danger: true, onTap: () {}),
      StudioAction(id: 'history', icon: Icons.history_rounded, label: 'History', onTap: () {}),
    ];

Widget _studio(StudioTool tool, {bool panelOpen = false, double duration = 5400}) {
  final item = _item(1);
  final others = [_item(2), _item(3, quality: 'audio')];
  final e = duration > 0 ? _edit() : StudioEdit.original(0);
  return Scaffold(
    appBar: StudioTopBar(
        title: item.title,
        facts: item.facts(),
        saveState: StudioSaveState.local,
        canUndo: true,
        onUndo: () {},
        onRedo: () {},
        onCanvas: () {},
        onDownload: () {},
        onExport: () {},
        exporting: 42),
    body: RecordStudioLayout(
      tool: tool,
      tools: [for (final x in StudioTool.values) if (x.inRail) x],
      onTool: (_) {},
      preview: const SizedBox.expand(),
      transport: StudioTransport(
          position: 1200, duration: e.duration, playing: true, previewSpeed: 1.25, zoom: 4, maxZoom: 64, onPlayPause: () {}, onSkip: (_) {}, onPreviewSpeed: () {}, onZoom: (_) {}),
      timeline: StudioTimelineView(edit: e, position: 1200, sourceDuration: duration, zoom: 4, markIn: 300, markOut: 900, selectedClip: 1, selectedOverlay: 'o1', onScrub: (_) {}, onMoveClip: (_, _) {}),
      panel: _panel(tool, item, others),
      actions: _acts(),
      actionContext: StudioActionContext(label: 'Part 2 of 3 · a rather long part name 10:00.0', onClear: () {}),
      panelOpen: panelOpen,
      onClosePanel: () {},
      footer: const StudioKeysHint(),
    ),
  );
}

Widget _export({bool two = false, String? problem}) {
  final item = _item(1);
  return SingleChildScrollView(
    child: StudioExportSettings(
      item: item,
      duration: 4200,
      form: StudioSaveArea(title: const TextField(decoration: InputDecoration(labelText: 'Name of the new recording')), onReplace: (_) {}).form,
      height: 720,
      onQuality: (_, _) {},
      twoFiles: two,
      halves: (1200, 3000),
      onTwoFiles: (_) {},
      result: two ? [1200, 3000] : [4200],
      problem: problem,
      onExport: () {},
    ),
  );
}

RecordSharePerson _p(int id, {bool opened = false}) => RecordSharePerson.fromJson({
      'id': id,
      'name': 'A person with a rather long display name $id',
      'username': 'person_$id',
      'added_at': '2026-11-08T09:00:00',
      'opened_at': opened ? '2026-11-08T10:00:00' : null,
    })!;

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('studio layout', () {
    for (final tool in StudioTool.values) {
      testWidgets('tool ${tool.name}', (t) async {
        await expectNoLayoutErrors(t, () => _studio(tool));
      });
    }
    testWidgets("phones: a tool's panel in place of the timeline; a record without a length", (t) async {
      await expectNoLayoutErrors(t, () => _studio(StudioTool.text, panelOpen: true));
      await expectNoLayoutErrors(t, () => _studio(StudioTool.edit, duration: 0));
    });
    testWidgets('the Export panel: settings, two files, a problem, and the job it follows', (t) async {
      await expectNoLayoutErrors(t, () => _export());
      await expectNoLayoutErrors(t, () => _export(two: true, problem: 'Nothing has changed yet'));
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: StudioExportJob(
                  running: false,
                  card: StudioJobCard(
                    items: [
                      RecordItem.fromJson({'recording_id': 9, 'kind': 'edit', 'status': 'assembling', 'stage': 'processing', 'progress': 55, 'title': 'A long new title of the edit'})!,
                      RecordItem.fromJson({'recording_id': 10, 'kind': 'edit', 'status': 'failed', 'error': 'cloud_reconnect_required: reconnect the drive', 'title': 'Part 2'})!,
                      RecordItem.fromJson({'recording_id': 11, 'kind': 'edit', 'status': 'failed', 'cancelled': true, 'error': 'stopped', 'title': 'Part 3'})!,
                      RecordItem.fromJson({'recording_id': 12, 'kind': 'edit', 'status': 'done', 'has_project': true, 'can_play': true, 'title': 'Part 4'})!,
                    ],
                    eta: const {9: Duration(minutes: 3)},
                    downloading: const {12: 0.4},
                    onPlay: (_) {},
                    onRetry: (_) {},
                    onCancel: (_) {},
                    onDownload: (_) {},
                    onShare: (_) {},
                    onContinue: (_) {},
                    onLibrary: () {},
                  ),
                  onKeepEditing: () {},
                  onExportAgain: () {},
                ),
              ));
    });
    testWidgets("the player's caller buttons (Open in Studio · Share)", (t) async {
      final a = VodAction(id: 'studio', icon: Icons.auto_fix_high_rounded, label: 'Open in Studio', onTap: () {});
      await expectNoLayoutErrors(t, () => Row(children: [VodActionButton(action: a, showLabel: true), VodActionButton(action: a)]));
    });
    testWidgets('the preview: loading, a problem with Try again, the keys sheet (D-901, D-910)', (t) async {
      for (final h in [120.0, 220.0, 480.0]) {
        await expectNoLayoutErrors(t, () => SizedBox(height: h, child: const StudioPreviewProblem(detail: 'The link has expired — open it again from the list', onRetry: _noop)));
      }
      await expectNoLayoutErrors(t, () => const SizedBox(height: 200, child: StudioPreviewLoading()));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: StudioKeysHint(sheet: true)));
      var retried = 0;
      await t.pumpWidget(layoutHost(SizedBox(height: 300, child: StudioPreviewProblem(detail: 'x', onRetry: () => retried++)), scale: 1));
      await t.tap(find.byKey(const ValueKey('studio.preview.retry')));
      expect(retried, 1);
      expect(find.text("The video couldn't play here"), findsOneWidget);
    });

    testWidgets('the action bar and the timeline strip alone', (t) async {
      await expectNoLayoutErrors(t, () => Align(alignment: Alignment.bottomCenter, child: StudioActionBar(actions: _acts(), context: StudioActionContext(label: 'Text “a very long caption that goes on”', onClear: () {}))));
      await expectNoLayoutErrors(t, () => Align(alignment: Alignment.topCenter, child: StudioTimelineBar(actions: _acts(), context: const StudioActionContext(label: 'Marked 01:10.0 – 01:25.0'))));
    });
  });

  group('studio behaviour', () {
    testWidgets('the summary says the new length', (t) async {
      await t.pumpWidget(layoutHost(const StudioSummary(original: 5400, result: [2400]), scale: 1));
      expect(find.text('New length 40:00'), findsOneWidget);
      await t.pumpWidget(layoutHost(const StudioSummary(original: 5400, result: [2700, 2700]), scale: 1));
      expect(find.text('Makes two recordings: 45:00 and 45:00'), findsOneWidget);
      await t.pumpWidget(layoutHost(const StudioSummary(original: 120, result: [], problem: 'Nothing has changed yet'), scale: 1));
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
    });

    testWidgets('the top bar: Undo / Redo always there, Export shows the running percent', (t) async {
      var undone = 0, redone = 0, exported = 0;
      Widget bar({bool canUndo = true, bool canRedo = false, int? exporting}) => Scaffold(
            appBar: StudioTopBar(
              title: 'A recording',
              saveState: StudioSaveState.saved,
              canUndo: canUndo,
              canRedo: canRedo,
              onUndo: () => undone++,
              onRedo: () => redone++,
              onExport: () => exported++,
              exporting: exporting,
            ),
          );
      await t.pumpWidget(layoutHost(bar(), scale: 1));
      await t.tap(find.byKey(const ValueKey('studio.undo')));
      await t.tap(find.byKey(const ValueKey('studio.redo')), warnIfMissed: false);
      await t.tap(find.byKey(const ValueKey('studio.export')));
      expect((undone, redone, exported), (1, 0, 1));
      expect(find.text('Saved'), findsOneWidget);
      await t.pumpWidget(layoutHost(bar(canRedo: true, exporting: 37), scale: 1));
      await t.tap(find.byKey(const ValueKey('studio.redo')));
      expect(redone, 1);
      expect(find.text('37%'), findsOneWidget);
    });

    testWidgets('Export is off while there is a problem; two files says so on the button', (t) async {
      await t.pumpWidget(layoutHost(_export(problem: 'Nothing has changed yet'), scale: 1));
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
      final off = t.widget<AppButton>(find.byKey(const ValueKey('studio.export.go')));
      expect(off.onPressed, isNull);
      await t.pumpWidget(layoutHost(_export(two: true), scale: 1));
      expect(find.text('Export two files'), findsOneWidget);
      expect(find.text('Makes two recordings: 20:00 and 50:00'), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const ValueKey('studio.export.go'))).onPressed, isNotNull);
    });

    testWidgets('an action without onTap is drawn off and does nothing', (t) async {
      var cleared = 0;
      await t.pumpWidget(layoutHost(
          Align(
              alignment: Alignment.bottomCenter,
              child: StudioActionBar(actions: _acts(), context: StudioActionContext(label: 'Part 2', onClear: () => cleared++))),
          scale: 1));
      await t.tap(find.byKey(const ValueKey('studio.act.move_back')), warnIfMissed: false);
      await t.tap(find.byKey(const ValueKey('studio.act.clear')));
      expect(cleared, 1);
    });

    testWidgets('the job card: stages, percent, time left, Stop, Download, Continue', (t) async {
      final got = <String>[];
      final running = RecordItem.fromJson({'recording_id': 9, 'kind': 'edit', 'status': 'assembling', 'stage': 'processing', 'progress': 64, 'title': 'Edit one'})!;
      final done = RecordItem.fromJson({'recording_id': 12, 'kind': 'edit', 'status': 'done', 'has_project': true, 'title': 'Done one'})!;
      await t.pumpWidget(layoutHost(
          SingleChildScrollView(
            child: StudioJobCard(
              items: [running, done],
              eta: const {9: Duration(seconds: 150)},
              onCancel: (r) => got.add('cancel ${r.id}'),
              onDownload: (r) => got.add('download ${r.id}'),
              onShare: (r) => got.add('share ${r.id}'),
              onContinue: (r) => got.add('continue ${r.id}'),
            ),
          ),
          scale: 1));
      await t.pump(const Duration(seconds: 1));
      expect(find.text('64%'), findsOneWidget);
      expect(find.textContaining('About 3 min left'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('studio.job.cancel.9')));
      await t.tap(find.byKey(const ValueKey('studio.job.download.12')));
      await t.tap(find.byKey(const ValueKey('studio.job.share.12')));
      await t.tap(find.byKey(const ValueKey('studio.job.continue.12')));
      expect(got, ['cancel 9', 'download 12', 'share 12', 'continue 12']);
    });

    testWidgets('time runs left to right in Arabic too: a press near the left scrubs near the start', (t) async {
      AppConfig.lang = 'ar';
      double? sought;
      t.view.physicalSize = const Size(1000, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(layoutHost(
          Padding(
            padding: const EdgeInsets.all(20),
            child: StudioTimelineView(edit: StudioEdit.original(1000), position: 500, sourceDuration: 1000, onScrub: (s) => sought = s),
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      await t.tapAt(Offset(box.left + box.width * 0.1, box.top + 40));
      expect(sought, isNotNull);
      expect(sought!, lessThan(200));
    });

    testWidgets('a clip edge is grabbed where the finger goes down and moves by the distance dragged (no jump)', (t) async {
      t.view.physicalSize = const Size(1128, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final trims = <(bool, double)>[];
      double? committed;
      final e = StudioEdit.original(1000).split(500);
      await t.pumpWidget(layoutHost(
          StudioTimelineView(
            edit: e,
            position: 0,
            sourceDuration: 1000,
            selectedClip: 1,
            onTrim: (i, start, s) => trims.add((start, s)),
            onTrimEnd: (i, start, s) => committed = s,
            onScrub: (_) => fail('the playhead must not move'),
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      // 1 px = 1 s: the tracks are 1036 wide (after the 92 px names) with 18 px pads; clip 1 starts at x = 18 + 500
      final edge = Offset(box.left + 18 + 500 - 6, box.top + StudioLanes.ruler + 30);
      final g = await t.startGesture(edge);
      await g.moveBy(const Offset(10, 0));
      await g.moveBy(const Offset(30, 0));
      await g.up();
      expect(trims.isNotEmpty && trims.every((x) => x.$1), isTrue, reason: 'the start edge, not the end or the playhead');
      expect(committed, isNotNull);
      expect(committed!, closeTo(540, 3), reason: 'moved by the 40 px dragged, not to the finger');
    });

    testWidgets('an overlay on its lane: a tap selects it, a drag moves it in time', (t) async {
      t.view.physicalSize = const Size(1128, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      String? selected;
      (double, double)? span;
      final e = StudioEdit.original(1000).putOverlay(const StudioOverlay(id: 'x', kind: StudioOverlayKind.text, start: 100, end: 300, text: 'Hi'));
      await t.pumpWidget(layoutHost(
          StudioTimelineView(
            edit: e,
            position: 900,
            sourceDuration: 1000,
            onSelectOverlay: (id) => selected = id,
            onOverlaySpanEnd: (id, a, b) => span = (a!, b!),
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final y = box.top + StudioLanes.ruler + StudioLanes.clips + StudioLanes.gap + StudioLanes.row / 2;
      await t.tapAt(Offset(box.left + 18 + 200, y));
      expect(selected, 'x');
      await t.dragFrom(Offset(box.left + 18 + 200, y), const Offset(100, 0));
      expect(span, isNotNull);
      expect(span!.$1, closeTo(200, 4));
      expect(span!.$2 - span!.$1, closeTo(200, 1));
    });

    testWidgets('a selected part dragged by its body plays elsewhere; an unselected one only scrubs (D-823)', (t) async {
      t.view.physicalSize = const Size(1036, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      (int, int)? moved;
      final e = StudioEdit.original(1000).split(300).split(600);
      await t.pumpWidget(layoutHost(
          StudioTimelineView(edit: e, position: 0, sourceDuration: 1000, selectedClip: 0, onMoveClip: (a, b) => moved = (a, b), onScrub: (_) {}),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      final pps = (box.width - 2 * StudioLanes.pad) / 1000;
      final y = box.top + StudioLanes.ruler + StudioLanes.clips / 2;
      await t.dragFrom(Offset(box.left + StudioLanes.pad + 150 * pps, y), Offset(800 * pps, 0));
      expect(moved, (0, 2), reason: 'part 1 dragged past the last part’s middle');
    });

    testWidgets('the tracks are named: Video, Text, Pictures, Audio', (t) async {
      await t.pumpWidget(layoutHost(SizedBox(width: 900, child: StudioTimelineView(edit: StudioEdit.original(100), position: 0, sourceDuration: 100)), scale: 1));
      for (final name in ['Video', 'Text', 'Pictures', 'Audio']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    test('ruler steps keep labels apart; snapping', () {
      expect(studioRulerStep(10), 10); // 10 px a second → a label every 10 s
      expect(studioRulerStep(0.5), 300); // a long recording on a narrow screen
      expect(studioRulerStep(400), 0.2); // zoomed in: fifths of a second
      expect(studioSnap(10.04, [0, 10, 20], 0.1), 10);
      expect(studioSnap(10.4, [0, 10, 20], 0.1), isNull);
    });

    test('merge picks number the chosen ones after the open record', () {
      final a = _item(1), b = _item(2), c = _item(3);
      final picks = studioMergePicks(a, [a, b, c], [3]);
      expect(picks.map((p) => p.item.id), [2, 3]);
      expect(picks.map((p) => p.order), [null, 1]);
    });
  });

  group('share layout', () {
    testWidgets('people mode with people, link mode with the link, empty, error', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: RecordShareLayout(
                  mode: RecordShareMode.people,
                  people: [_p(1, opened: true), _p(2)],
                  link: 'https://nextbrain.site/s/record/abcdefghijklmnopqrstuvwx',
                  active: true,
                  views: 12,
                  dirty: true,
                  showImages: false,
                  onMode: (_) {},
                  onAdd: () {},
                  onRemove: (_) {},
                  onCopy: () {},
                  onSystemShare: () {},
                  onSave: () {},
                  onStop: () {},
                ),
              ));
      await expectNoLayoutErrors(
          t, () => const SingleChildScrollView(child: RecordShareLayout(mode: RecordShareMode.link, people: [], error: 'Something went wrong')));
    });

    testWidgets('people picker and the Shared-with-me list', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: SharePeopleLayout(
                    search: const TextField(), results: [_p(1), _p(2)], chosen: const {2}, showImages: false, onToggle: (_) {}, onDone: () {}),
              ));
      await expectNoLayoutErrors(t, () => const SingleChildScrollView(child: SharePeopleLayout(search: TextField(), results: [], chosen: {})));
      final items = sharedRecordsFrom({
        'items': [
          {'token': 'tok12345678', 'record_id': 4, 'title': 'A shared recording with a long name', 'duration_seconds': 3725, 'shared_at': '2026-11-08T10:00:00',
           'owner': {'id': 2, 'name': 'The owner'}},
          {'token': 'tok87654321', 'record_id': 5, 'title': 'Audio', 'media': 'audio', 'owner': {'id': 3, 'name': 'Someone'}},
        ]
      });
      await expectNoLayoutErrors(t, () => SharedRecordsLayout(items: items, showImages: false, onTap: (_) {}));
      await expectNoLayoutErrors(t, () => const SharedRecordsLayout(items: []));
      await expectNoLayoutErrors(t, () => const SharedRecordsLayout(items: [], loading: true));
    });

    testWidgets('Share is off in people mode with nobody chosen', (t) async {
      var saved = 0;
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: RecordShareLayout(mode: RecordShareMode.people, people: const [], onSave: () => saved++)), scale: 1));
      await t.tap(find.byKey(const ValueKey('records.share.save')), warnIfMissed: false);
      expect(saved, 0);
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: RecordShareLayout(mode: RecordShareMode.link, people: const [], onSave: () => saved++)), scale: 1));
      await t.tap(find.byKey(const ValueKey('records.share.save')));
      expect(saved, 1);
    });
  });
}

void _noop() {}
