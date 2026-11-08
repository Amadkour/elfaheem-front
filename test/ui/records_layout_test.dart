// Records (D-311): the plain-values widgets on every screen size and language (no overflow), and the library page's
// flow against a fake API — long-press selects, Merge opens the order sheet and sends the ids in order, Delete asks
// list-only vs. drive too, the kill switch hides the My-profile tile.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/records/records_api.dart';
import 'package:flutter_education_app/features/shared/records/records_page.dart';
import 'package:flutter_education_app/features/shared/records/records_parts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

RecordItem _item(int id,
        {String status = 'done', String quality = '720p', String? op, Map<String, dynamic>? params, int meeting = 7, int day = 8}) =>
    RecordItem.fromJson({
      'recording_id': id,
      'kind': op == null ? 'meeting' : 'edit',
      'status': status,
      'quality': quality,
      'destination': 'google_drive',
      'size': 734003200,
      'duration_seconds': 5400.0 + id,
      'remote_url': status == 'done' ? 'https://drive.google.com/file/d/$id/view' : null,
      'error': status == 'failed' ? 'cloud_reconnect_required: Google Drive refused the access — reconnect the account' : null,
      'retry_mode': status == 'failed' ? 'manual' : null,
      'created_at': '2026-11-0${day}T09:0$id:00',
      'title': 'Weekly planning sync with the whole department and guests #$id',
      'operation': op,
      'op_params': params,
      'source_ids': op == null ? <int>[] : [1],
      'stage': status == 'assembling' ? 'downloading' : null,
      'progress': status == 'assembling' ? 35 : null,
      'meeting': {'id': meeting, 'title': 'Weekly planning sync with the whole department', 'starts_at': '2026-11-0${day}T08:00:00'},
      'can_edit': status == 'done',
      'can_play': status == 'done',
    })!;

class _Api implements RecordsApi {
  _Api(this.items);
  List<RecordItem> items;
  final calls = <String>[];

  @override
  Future<List<RecordItem>> list() async {
    calls.add('list');
    return items;
  }

  @override
  Future<List<RecordItem>> merge(List<int> ids, {String? title, bool deleteSources = false}) async {
    calls.add('merge ${ids.join(',')} $deleteSources');
    return [_item(50, status: 'assembling', op: 'merge')];
  }

  @override
  Future<bool> delete(int id, {bool drive = false}) async {
    calls.add('delete $id $drive');
    return drive;
  }

  @override
  Future<RecordItem?> get(int id) async => null;
  @override
  Future<(RecordItem?, bool)> rename(int id, String title) async => (null, false);
  @override
  Future<RecordItem?> setCover(int id, Uint8List bytes, {String fileName = 'cover.jpg'}) async => null;
  @override
  Future<RecordItem?> clearCover(int id) async => null;
  @override
  Future<List<RecordItem>> edit(int id, RecordEdit edit) async => const [];
  @override
  Future<RecordItem?> retry(int id) async => null;
  @override
  Future<RecordPlay> play(int id) async => const RecordPlay(url: 'https://x.test/s');
}

Widget _editor(RecordOp op) => RecordEditorLayout(
      preview: const SizedBox.expand(),
      duration: 5400,
      position: 1200,
      op: op,
      start: 600,
      end: 3000,
      at: 2700,
      speed: 1.5,
      title: const TextField(decoration: InputDecoration(labelText: 'Name of the new recording')),
      deleteSource: op == RecordOp.cut,
      onPlayPause: () {},
      onSeek: (_) {},
      onOp: (_) {},
      onRange: (_, _) {},
      onAt: (_) {},
      onSpeed: (_) {},
      onDeleteSource: (_) {},
      onSave: () {},
    );

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });
  tearDown(() => AppConfig.disableList = []);

  group('layout', () {
    testWidgets('tiles in every state, selected and highlighted', (t) async {
      await expectNoLayoutErrors(t, () => SingleChildScrollView(child: Column(children: [
            for (final s in const ['recording', 'assembling', 'uploading', 'done', 'failed']) RecordTile(item: _item(1, status: s), onMore: () {}, onRetry: () {}, showImage: false),
            RecordTile(item: _item(2, quality: 'audio', op: 'speed', params: {'speed': 1.25}), selecting: true, selected: true, showImage: false),
            RecordTile(item: _item(3, op: 'split', params: {'part': 2}), highlighted: true, onMore: () {}, showImage: false),
          ])));
    });

    testWidgets('library: skeleton, error, empty, groups', (t) async {
      await expectNoLayoutErrors(t, () => const RecordsLayout(items: [], loading: true));
      await expectNoLayoutErrors(t, () => RecordsLayout(items: const [], error: 'Network down', onReload: () {}));
      await expectNoLayoutErrors(t, () => const RecordsLayout(items: []));
      await expectNoLayoutErrors(
          t,
          () => RecordsLayout(
                items: [_item(1), _item(2, meeting: 8, day: 7), _item(3, status: 'assembling', op: 'trim'), _item(4, status: 'failed')],
                selected: const {1},
                onTap: (_) {},
                onMore: (_) {},
                showImages: false,
              ));
    });

    testWidgets('selection bar', (t) async {
      await expectNoLayoutErrors(t, () => Align(alignment: Alignment.bottomCenter, child: RecordsSelectionBar(count: 12, canMerge: true, onMerge: () {}, onDelete: () {}, onCancel: () {})));
      await expectNoLayoutErrors(t, () => const Align(alignment: Alignment.bottomCenter, child: RecordsSelectionBar(count: 1)));
    });

    testWidgets('editor in every mode', (t) async {
      for (final op in const [RecordOp.trim, RecordOp.split, RecordOp.cut, RecordOp.speed]) {
        await expectNoLayoutErrors(t, () => SingleChildScrollView(child: _editor(op)));
      }
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: RecordEditorLayout(
                  preview: const SizedBox.expand(),
                  duration: 0,
                  position: 0,
                  op: RecordOp.trim,
                  start: 0,
                  end: 0,
                  at: 0,
                  speed: 1.5,
                  title: const SizedBox.shrink(),
                  busy: true,
                ),
              ));
    });

    testWidgets('merge order sheet body', (t) async {
      await expectNoLayoutErrors(
          t,
          () => SingleChildScrollView(
                child: MergeOrderLayout(
                  items: [_item(1), _item(2, quality: 'audio'), _item(3)],
                  title: const TextField(),
                  onMove: (_, _) {},
                  onDeleteSources: (_) {},
                  onMerge: () {},
                ),
              ));
    });
  });

  group('behaviour', () {
    testWidgets('the editor: Save is off while the period is invalid; the summary names what comes out', (t) async {
      await t.pumpWidget(layoutHost(SingleChildScrollView(child: _editor(RecordOp.split)), scale: 1));
      expect(find.text('Makes two recordings: 45:00 and 45:00'), findsOneWidget);
      await t.pumpWidget(layoutHost(
          SingleChildScrollView(
            child: RecordEditorLayout(
              preview: const SizedBox.expand(),
              duration: 120,
              position: 0,
              op: RecordOp.cut,
              start: 0,
              end: 120,
              at: 60,
              speed: 1.5,
              title: const SizedBox.shrink(),
              onSave: () => fail('saved an invalid edit'),
            ),
          ),
          scale: 1));
      expect(find.textContaining("can't cut the whole recording"), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('records.editor.save')), warnIfMissed: false);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('long-press selects, Merge sends the ids in the chosen order', (t) async {
      final api = _Api([_item(1, day: 6), _item(2, day: 7), _item(3, status: 'recording', day: 8)]);
      await t.pumpWidget(layoutHost(RecordsPage(api: api), scale: 1, scaffold: false));
      await t.pumpAndSettle();
      expect(api.calls, ['list']);
      expect(find.byKey(const ValueKey('records.select.merge')), findsNothing);
      await t.longPress(find.byKey(const ValueKey('records.tile.1')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('records.tile.2')));        // in selection, a tap toggles
      await t.pump();
      expect(find.text('Selected: 2 recordings'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('records.select.merge')));
      await t.pumpAndSettle();
      // oldest first by default; move the second up
      await t.tap(find.byKey(const ValueKey('records.merge.up.1')));
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('records.merge.go')));
      await t.tap(find.byKey(const ValueKey('records.merge.go')));
      await t.pumpAndSettle();
      expect(api.calls.last, 'merge 2,1 false');
      expect(find.byKey(const ValueKey('records.tile.50')), findsOneWidget);   // the new item is on top, selection cleared
      expect(find.byKey(const ValueKey('records.select.merge')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });

    testWidgets('delete asks list only vs. the drive too', (t) async {
      final api = _Api([_item(1)]);
      await t.pumpWidget(layoutHost(RecordsPage(api: api), scale: 1, scaffold: false));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('records.more.1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('records.sheet.delete')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('records.delete.list')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('records.delete.drive')));
      await t.pumpAndSettle();
      expect(api.calls.last, 'delete 1 true');
      expect(find.byKey(const ValueKey('records.tile.1')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 7));
    });

    testWidgets('the My-profile tile follows the kill switch', (t) async {
      await t.pumpWidget(layoutHost(RecordsSettingsTile(onOpen: () {}), scale: 1));
      expect(find.byKey(const ValueKey('records.entry')), findsOneWidget);
      AppConfig.disableList = [kRecordsFeatureKey];
      await t.pumpWidget(layoutHost(RecordsSettingsTile(onOpen: () {}), scale: 1));
      await t.pump();
      expect(find.byKey(const ValueKey('records.entry')), findsNothing);
    });
  });
}
