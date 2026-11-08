// The Studio (D-312) and sharing a record: the plain-values widgets on every screen size and language (no overflow,
// text scale 1.3), plus what they say and send — the live summary, Save off for an invalid selection, the timeline's
// left-to-right time in Arabic, the share sheet's Save rule.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'package:flutter_education_app/features/shared/records/records_share_api.dart';
import 'package:flutter_education_app/features/shared/records/records_share_parts.dart';
import 'package:flutter_education_app/features/shared/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/shared/session/video/vod_player_parts.dart' show VodAction, VodActionButton;
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

Widget _studio(StudioTool tool, {bool job = false, double duration = 5400}) {
  final item = _item(1);
  final others = [_item(2), _item(3, quality: 'audio')];
  final edit = studioEdit(tool, start: 600, end: 3000, at: 2700, speed: 1.5);
  return RecordStudioLayout(
    tool: tool,
    onTool: (_) {},
    preview: const SizedBox.expand(),
    transport: StudioTransport(position: 1200, duration: duration, playing: true, previewSpeed: 1.25, zoom: 4, onPlayPause: () {}, onSkip: (_) {}, onPreviewSpeed: () {}, onZoom: (_) {}),
    timeline: StudioTimeline(
        duration: duration, position: 1200, tool: tool, start: 600, end: 3000, at: 2700, zoom: 4, onSeek: (_) {}, onRange: (_, _) {}, onAt: (_) {}),
    panel: StudioToolPanel(
      tool: tool,
      item: item,
      duration: duration,
      position: 1200,
      start: 600,
      end: 3000,
      at: 2700,
      height: 1080,
      level: StudioQualityLevel.best,
      merge: studioMergePicks(item, [item, ...others], [3]),
      showImages: false,
      onRange: (_, _) {},
      onAt: (_) {},
      onSpeed: (_) {},
      onQuality: (_, _) {},
      onPickCover: () {},
      onToggleMerge: (_) {},
    ),
    summary: StudioSummary(
      original: duration,
      result: tool == StudioTool.merge ? [mergedDuration([item, others[1]])] : (edit == null ? const [] : editResultDurations(edit, duration)),
      problem: edit == null ? null : editProblem(edit, duration),
    ),
    save: tool == StudioTool.cover
        ? null
        : StudioSaveArea(
            title: const TextField(decoration: InputDecoration(labelText: 'Name of the new recording')),
            merge: tool == StudioTool.merge,
            replace: tool == StudioTool.cut,
            canSave: true,
            canUndo: true,
            onReplace: (_) {},
            onUndo: () {},
            onReset: () {},
            onSave: () {},
          ),
    job: job
        ? StudioJobCard(items: [
            RecordItem.fromJson({'recording_id': 9, 'kind': 'edit', 'status': 'assembling', 'stage': 'processing', 'progress': 55, 'title': 'A long new title of the edit'})!,
            RecordItem.fromJson({'recording_id': 10, 'kind': 'edit', 'status': 'failed', 'error': 'cloud_reconnect_required: reconnect the drive', 'title': 'Part 2'})!,
          ], onPlay: (_) {}, onRetry: (_) {}, onAgain: () {}, onLibrary: () {})
        : null,
    footer: const StudioKeysHint(),
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
    testWidgets('a saved job inline, and a record without a length', (t) async {
      await expectNoLayoutErrors(t, () => _studio(StudioTool.split, job: true));
      await expectNoLayoutErrors(t, () => _studio(StudioTool.trim, duration: 0));
    });
    testWidgets("the player's caller buttons (Open in Studio · Share)", (t) async {
      final a = VodAction(id: 'studio', icon: Icons.auto_fix_high_rounded, label: 'Open in Studio', onTap: () {});
      await expectNoLayoutErrors(t, () => Row(children: [VodActionButton(action: a, showLabel: true), VodActionButton(action: a)]));
    });
    testWidgets('the phone tool bar alone', (t) async {
      await expectNoLayoutErrors(t, () => Align(alignment: Alignment.bottomCenter, child: StudioToolBar(tool: StudioTool.merge, onTool: (_) {})));
    });
  });

  group('studio behaviour', () {
    testWidgets('the summary says the new length; an invalid cut says why', (t) async {
      await t.pumpWidget(layoutHost(_studio(StudioTool.trim), scale: 1));
      expect(find.text('New length 40:00'), findsOneWidget);
      await t.pumpWidget(layoutHost(_studio(StudioTool.split), scale: 1));
      expect(find.text('Makes two recordings: 45:00 and 45:00'), findsOneWidget);
      await t.pumpWidget(layoutHost(const StudioSummary(original: 120, result: [], problem: "You can't cut the whole recording"), scale: 1));
      expect(find.textContaining("can't cut"), findsOneWidget);
    });

    testWidgets('Save is off while the selection is invalid', (t) async {
      var saved = 0;
      await t.pumpWidget(layoutHost(
          StudioSaveArea(title: const SizedBox.shrink(), canSave: false, onSave: () => saved++), scale: 1));
      await t.tap(find.byKey(const ValueKey('studio.save')), warnIfMissed: false);
      expect(saved, 0);
      await t.pumpWidget(layoutHost(StudioSaveArea(title: const SizedBox.shrink(), canSave: true, replace: true, onSave: () => saved++), scale: 1));
      expect(find.text('Save and replace'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('studio.save')));
      expect(saved, 1);
    });

    testWidgets('time runs left to right in Arabic too: a tap near the left seeks near the start', (t) async {
      AppConfig.lang = 'ar';
      double? sought;
      t.view.physicalSize = const Size(1000, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(layoutHost(
          Padding(
            padding: const EdgeInsets.all(20),
            child: StudioTimeline(duration: 1000, position: 0, tool: StudioTool.trim, start: 0, end: 1000, onSeek: (s) => sought = s),
          ),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      await t.tapAt(Offset(box.left + box.width * 0.1, box.center.dy));
      expect(sought, isNotNull);
      expect(sought!, lessThan(200));
    });

    test('the stage says when the playhead stands in a part that goes', () {
      String? note(StudioTool tool, double pos, {double start = 10, double end = 20}) =>
          studioStageNote(tool, position: pos, start: start, end: end, duration: 100);
      expect(note(StudioTool.trim, 5), isNotNull); // before what stays
      expect(note(StudioTool.trim, 15), isNull);
      expect(note(StudioTool.cut, 15), isNotNull); // inside what goes
      expect(note(StudioTool.cut, 5), isNull);
      expect(note(StudioTool.cut, 50, start: 0, end: 100), isNull); // Cut just opened: nothing is chosen yet
      expect(note(StudioTool.speed, 5), isNull);
    });

    testWidgets('a handle at the very start and end of the track is on screen and can be dragged', (t) async {
      t.view.physicalSize = const Size(1000, 400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      (double, double)? range;
      await t.pumpWidget(layoutHost(
          StudioTimeline(duration: 1000, position: 500, tool: StudioTool.trim, start: 0, end: 1000, onRange: (a, b) => range = (a, b)),
          scale: 1));
      final box = t.getRect(find.byKey(const ValueKey('studio.timeline')));
      await t.dragFrom(Offset(box.left + 8, box.center.dy), const Offset(120, 0));
      expect(range, isNotNull);
      expect(range!.$1, greaterThan(50));
      expect(range!.$2, 1000);
    });

    test('ruler steps keep labels apart', () {
      expect(studioRulerStep(10), 10);      // 10 px a second → a label every 10 s
      expect(studioRulerStep(0.5), 300);    // a long recording on a narrow screen
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
