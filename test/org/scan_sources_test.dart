// Where the answer sheets come from (scan_sources.dart, scan_files.dart, scan_prepare.dart, scan_upload_view.dart):
//   • the source sheet offers only what works on the device (camera on the bubble path; gallery on phones; folder
//     on a computer's browser, the desktop apps and the Android app; the iOS app and phones' browsers say what to do
//     instead) and starts the picker inside the tap
//   • a folder: hidden / system files dropped, unsupported ones listed with the reason, natural file order across
//     sub-folders (page2 before page10), the dart:io walk of a real folder
//   • the parts: ≤ 8 MB / 20 files each, the later parts carry the first part's batch_id, a part refused for one
//     file is sent again file by file, a network failure does not stop the rest, a stop failure does, Retry sends
//     only what failed into the same batch
//   • a gallery photo is scaled down and turned upright from its EXIF orientation; files are sent untouched; a HEIC
//     this device cannot open / a TIFF's pages
//   • the bubble-sheet progress screen: summary → "Upload 3 files" → parts → one batch tracked; the written-answer
//     upload page: a failed file, Retry; no layout errors at 320×640 and 1400×900 in ar / en
import 'dart:io';

import 'package:dio/dio.dart' show FormData, RequestOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/paper/scan/omr_upload_screen.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_files.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_folder_io.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_prepare.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_sources.dart';
import 'package:flutter_education_app/features/exams/paper/scan/scan_upload_view.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

ScanSourceFile _f(String path, {int size = 1000, bool photo = false}) {
  final name = path.split('/').last;
  return ScanSourceFile(
      name: name, path: path.contains('/') ? path : '', size: size, photo: photo, read: () async => _pdfBytes(size));
}

Uint8List _pdfBytes(int n) {
  final b = Uint8List(n < 8 ? 8 : n);
  b.setAll(0, '%PDF-1.4'.codeUnits);
  return b;
}

/// A part as one string (a record holding a list never equals another: CLAUDE.md).
String _part(List<String> names, Object? batch) => '${names.join(',')}|${batch ?? '-'}';

EngineResult _ok(int batch, int pages, [int dup = 0]) =>
    EngineResult.ok({'batch_id': batch, 'pages': [for (var i = 0; i < pages; i++) 100 + i], 'duplicates': dup, 'omr': true});

const _android = ScanPlatform(web: false, os: TargetPlatform.android);
const _ios = ScanPlatform(web: false, os: TargetPlatform.iOS);
const _androidWeb = ScanPlatform(web: true, os: TargetPlatform.android);
const _iosWeb = ScanPlatform(web: true, os: TargetPlatform.iOS);
const _desktopWeb = ScanPlatform(web: true, os: TargetPlatform.windows);
const _macWeb = ScanPlatform(web: true, os: TargetPlatform.macOS);
const _windows = ScanPlatform(web: false, os: TargetPlatform.windows);
const _macos = ScanPlatform(web: false, os: TargetPlatform.macOS);
const _linux = ScanPlatform(web: false, os: TargetPlatform.linux);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('sources per platform', () {
    test('which options each device gets', () {
      List<String> names(ScanPlatform p, {bool camera = true, bool single = false}) =>
          [for (final s in scanSourcesFor(p, camera: camera, single: single)) s.name];
      expect(names(_android), ['camera', 'gallery', 'files', 'folder']);
      expect(names(_ios), ['camera', 'gallery', 'files'], reason: 'no folder access on iOS');
      expect(names(_androidWeb), ['camera', 'gallery', 'files'], reason: "phones' browsers ignore webkitdirectory");
      expect(names(_iosWeb), ['camera', 'gallery', 'files']);
      expect(names(_desktopWeb), ['camera', 'files', 'folder']);
      expect(names(_macWeb), ['camera', 'files', 'folder']);
      for (final p in [_windows, _macos, _linux]) {
        expect(names(p), ['camera', 'files', 'folder'], reason: '${p.os}');
      }
      expect(names(_android, camera: false), ['gallery', 'files', 'folder'], reason: 'the written-answer path has no live camera');
      expect(names(_android, single: true), ['gallery', 'files'], reason: 'one replacement page');
      expect(names(_desktopWeb, single: true), ['files']);
      expect(const ScanPlatform(web: false, os: TargetPlatform.android, folderBuild: false).folder, isFalse);
      expect(_ios.folderHint, contains('Files'));
      expect(_androidWeb.folderHint, contains('computer'));
      expect(_android.folderHint, isNull);
      expect(_desktopWeb.folderHint, isNull);
    });

    for (final (label, p, shown, hidden, hint) in [
      ('Android app', _android, ['camera', 'gallery', 'files', 'folder'], <String>[], false),
      ('iOS app', _ios, ['camera', 'gallery', 'files'], ['folder'], true),
      ('phone browser', _iosWeb, ['camera', 'gallery', 'files'], ['folder'], true),
      ('computer browser', _desktopWeb, ['camera', 'files', 'folder'], ['gallery'], false),
      ('desktop app', _windows, ['camera', 'files', 'folder'], ['gallery'], false),
    ]) {
      testWidgets('sheet on $label: ${shown.join(', ')}', (tester) async {
        await tester.pumpWidget(layoutHost(ScanSourceSheet(platform: p, picker: (s, {bool single = false}) async => null, camera: true), scale: 1));
        for (final s in shown) {
          expect(find.byKey(ValueKey('scan.src.$s')), findsOneWidget, reason: s);
        }
        for (final s in hidden) {
          expect(find.byKey(ValueKey('scan.src.$s')), findsNothing, reason: s);
        }
        expect(find.byKey(const ValueKey('scan.src.hint')), hint ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('a tap starts the picker inside the tap, the sheet closes, the pick comes back', (tester) async {
      final calls = <String>[];
      ScanPick? got;
      await tester.pumpWidget(layoutHost(Builder(
          builder: (context) => Center(
                child: TextButton(
                  onPressed: () async => got = await showScanSourceSheet(context, platform: _android, picker: (s, {bool single = false}) {
                    calls.add('${s.name}:$single'); // synchronous: still inside the tap
                    return Future.value(ScanPick(s, [_f('Scans/p1.pdf')], folder: 'Scans'));
                  }),
                  child: const Text('open'),
                ),
              )), scale: 1));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scan.src.folder')));
      expect(calls, ['folder:false'], reason: 'called in the tap itself');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('scan.src.folder')), findsNothing, reason: 'the sheet closed');
      expect(got?.source, ScanSource.folder);
      expect(got?.folder, 'Scans');
    });

    testWidgets('the camera choice comes back as camera, no picker', (tester) async {
      ScanPick? got;
      var picked = false;
      await tester.pumpWidget(layoutHost(Builder(
          builder: (context) => TextButton(
                onPressed: () async => got = await showScanSourceSheet(context, camera: true, platform: _android, picker: (s, {bool single = false}) {
                  picked = true;
                  return Future.value(null);
                }),
                child: const Text('open'),
              )), scale: 1));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('scan.src.camera')));
      await tester.pumpAndSettle();
      expect(got?.source, ScanSource.camera);
      expect(picked, isFalse);
    });
  });

  group('folder plan', () {
    test('natural order: page2 before page10, folders in order, a folder\'s own pages first', () {
      expect(naturalCompare('page2.jpg', 'page10.jpg'), lessThan(0));
      expect(naturalCompare('Page10', 'page9'), greaterThan(0));
      expect(naturalCompare('scan_001.pdf', 'scan_01.pdf'), greaterThan(0), reason: 'same value: shorter first, stable');
      expect(naturalCompare('a99999999999999999999', 'a100000000000000000000'), lessThan(0), reason: 'no int overflow');
      final paths = ['Class B/page1.jpg', 'Class A/page10.jpg', 'cover.pdf', 'Class A/page2.jpg', 'Class A/sub/page1.jpg', 'Class A/page1.jpg'];
      paths.sort(naturalPathCompare);
      expect(paths, ['cover.pdf', 'Class A/page1.jpg', 'Class A/page2.jpg', 'Class A/page10.jpg', 'Class A/sub/page1.jpg', 'Class B/page1.jpg']);
    });

    test('hidden and system files are dropped, the rest counted with the reason', () {
      final plan = planScanFiles([
        _f('Exam/page10.JPG'),
        _f('Exam/page2.jpeg'),
        _f('Exam/batch.pdf'),
        _f('Exam/.DS_Store'),
        _f('Exam/._page2.jpeg'),
        _f('Exam/Thumbs.db'),
        _f('Exam/desktop.ini'),
        _f('Exam/.thumbnails/page1.jpg'),
        _f('__MACOSX/Exam/page1.jpg'),
        _f('Exam/notes.txt'),
        _f('Exam/scan.HEIC'),
        _f('Exam/scan3.tif'),
        _f('Exam/empty.png', size: 0),
        _f('Exam/huge.pdf', size: kScanMaxFileBytes + 1),
        _f('Exam/huge.jpg', size: kScanMaxFileBytes + 1),
      ], folder: 'Exam');
      expect([for (final f in plan.files) f.label],
          ['Exam/batch.pdf', 'Exam/huge.jpg', 'Exam/page2.jpeg', 'Exam/page10.JPG', 'Exam/scan.HEIC', 'Exam/scan3.tif']);
      expect(plan.images, 5);
      expect(plan.pdfs, 1);
      expect(plan.hidden, 6);
      expect({for (final s in plan.skipped) s.label: s.reason}, {
        'Exam/empty.png': ScanSkipReason.empty,
        'Exam/huge.pdf': ScanSkipReason.tooLarge,
        'Exam/notes.txt': ScanSkipReason.unsupported,
      });
      expect(plan.folder, 'Exam');
    });

    test('a gallery keeps the order the photos were chosen in; too many files is refused whole', () {
      final g = ScanPick(ScanSource.gallery, [_f('IMG_9.jpg'), _f('IMG_10.jpg'), _f('IMG_1.jpg')]).plan();
      expect([for (final f in g.files) f.name], ['IMG_9.jpg', 'IMG_10.jpg', 'IMG_1.jpg']);
      final many = planScanFiles([for (var i = 0; i <= kScanMaxPick; i++) _f('p$i.jpg')]);
      expect(many.tooMany, isTrue);
      expect(many.files, isEmpty);
    });

    test('the parts: ≤ 8 MB and ≤ 20 files each, a big file alone', () {
      const mb = 1024 * 1024;
      expect(scanParts([3 * mb, 3 * mb, 3 * mb, 1 * mb]), [
        [0, 1],
        [2, 3]
      ]);
      expect(scanParts([20 * mb, 1 * mb, 1 * mb]), [
        [0],
        [1, 2]
      ]);
      expect(scanParts(List.filled(45, 1000)).map((p) => p.length).toList(), [20, 20, 5]);
    });

    test('a real folder walked with dart:io: sub-folders, relative paths', () async {
      final root = Directory.systemTemp.createTempSync('scan_folder_');
      addTearDown(() => root.deleteSync(recursive: true));
      void put(String rel, List<int> b) => (File('${root.path}/$rel')..createSync(recursive: true)).writeAsBytesSync(b);
      put('page10.jpg', [0xFF, 0xD8, 0xFF, 1]);
      put('page2.jpg', [0xFF, 0xD8, 0xFF, 2]);
      put('Class B/batch.pdf', _pdfBytes(20));
      put('.hidden/x.jpg', [1]);
      put('.DS_Store', [0]);
      put('readme.txt', [65]);
      final folder = await listScanFolder(root);
      expect(folder.name, root.path.split(RegExp(r'[\\/]')).last);
      expect(folder.files.map((f) => f.path).toSet(), {'page10.jpg', 'page2.jpg', 'Class B/batch.pdf', '.hidden/x.jpg', '.DS_Store', 'readme.txt'});
      final plan = ScanPick(ScanSource.folder, folder.files, folder: folder.name).plan();
      expect([for (final f in plan.files) f.label], ['page2.jpg', 'page10.jpg', 'Class B/batch.pdf']);
      expect(plan.skipped.single.label, 'readme.txt');
      expect(plan.hidden, 2);
      expect(await plan.files.first.read(), [0xFF, 0xD8, 0xFF, 2]);
    });
  });

  group('sending in parts', () {
    const mb = 1024 * 1024;
    Future<List<(String, Uint8List)>> asIs(ScanSourceFile f) async => [(f.name, await f.read())];

    ScanUploader up(List<ScanSourceFile> files, Future<EngineResult> Function(List<(String, Uint8List)>, int?) send) => ScanUploader(
          files: files,
          prepare: asIs,
          send: send,
          errorText: (r) => 'E:${r.code ?? r.status}',
          prepareErrorText: (c) => 'P:$c',
        );

    test('parts of ≤ 8 MB; the later parts carry the first part\'s batch; duplicates summed', () async {
      final sent = <String>[];
      final u = up([for (var i = 1; i <= 5; i++) _f('p$i.pdf', size: 3 * mb)], (files, batch) async {
        sent.add(_part([for (final f in files) f.$1], batch));
        return _ok(41, files.length, 1);
      });
      await u.run();
      expect(sent, ['p1.pdf,p2.pdf|-', 'p3.pdf,p4.pdf|41', 'p5.pdf|41']);
      expect(u.batchId, 41);
      expect(u.pages, 5);
      expect(u.duplicates, 3);
      expect(u.failures, isEmpty);
      expect(u.finished, 5);
    });

    test('one bad file spoils a part: the part is sent again file by file, only that file fails', () async {
      final calls = <List<String>>[];
      final u = up([_f('a.pdf'), _f('b.pdf'), _f('c.pdf')], (files, batch) async {
        calls.add([for (final f in files) f.$1]);
        if (files.any((f) => f.$1 == 'b.pdf')) return EngineResult.fail(422, 'bad_pdf', 'x');
        return _ok(7, files.length);
      });
      await u.run();
      expect([for (final c in calls) c.join(',')], ['a.pdf,b.pdf,c.pdf', 'a.pdf', 'b.pdf', 'c.pdf']);
      expect([for (final f in u.failures) '${f.file.name}: ${f.reason}'], ['b.pdf: E:bad_pdf']);
      expect(u.sent.map((f) => f.name).toSet(), {'a.pdf', 'c.pdf'});
      expect(u.batchId, 7);
    });

    test('a network failure fails its part only: the next parts still go; Retry sends just those, same batch', () async {
      var down = true;
      final sent = <String>[];
      final u = up([_f('p1.pdf', size: 5 * mb), _f('p2.pdf', size: 5 * mb), _f('p3.pdf', size: 5 * mb)], (files, batch) async {
        final names = [for (final f in files) f.$1];
        sent.add(_part(names, batch));
        if (names.contains('p2.pdf') && down) return EngineResult.fail(0, null, 'No connection');
        return _ok(9, files.length);
      });
      await u.run();
      expect([for (final f in u.failures) f.file.name], ['p2.pdf']);
      expect(sent.last, 'p3.pdf|9', reason: 'kept going past the failed part');
      down = false;
      await u.retry();
      expect(sent.last, 'p2.pdf|9', reason: 'only the failed file, into the same batch');
      expect(u.failures, isEmpty);
      expect(u.sent.length, 3);
    });

    test('a stop failure (no rights, setup) ends the run: the rest is listed, not sent', () async {
      var calls = 0;
      final u = up([_f('p1.pdf', size: 5 * mb), _f('p2.pdf', size: 5 * mb), _f('p3.pdf', size: 5 * mb)], (files, batch) async {
        calls++;
        return EngineResult.fail(422, 'exam_not_bubble', 'x');
      });
      await u.run();
      expect(calls, 1);
      expect(u.failures.length, 3);
      expect(u.stopped, 'E:exam_not_bubble');
      expect(u.anySent, isFalse);
    });

    test('a file that cannot be prepared fails with its reason; the others go', () async {
      final u = ScanUploader(
        files: [_f('a.heic'), _f('b.pdf')],
        prepare: (f) async => f.name.endsWith('.heic') ? throw const ScanPrepareError('heic') : [(f.name, await f.read())],
        send: (files, batch) async => _ok(3, files.length),
        errorText: (r) => 'E',
        prepareErrorText: scanPrepareErrorText,
      );
      await u.run();
      expect(u.failures.single.reason, 'A HEIC photo this device cannot open — save it as JPEG');
      expect(u.sent.single.name, 'b.pdf');
    });
  });

  group('preparing a file', () {
    test('bytes are sniffed, not names', () {
      expect(sniffScanBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), ScanBytesKind.jpeg);
      expect(sniffScanBytes(Uint8List.fromList('%PDF-1.7'.codeUnits)), ScanBytesKind.pdf);
      expect(sniffScanBytes(Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits])), ScanBytesKind.heic);
      expect(sniffScanBytes(Uint8List.fromList([0x49, 0x49, 0x2A, 0])), ScanBytesKind.tiff);
      expect(sniffScanBytes(Uint8List.fromList([1, 2, 3])), ScanBytesKind.unknown);
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 31, height: 17)));
      expect(scanImageSize(png), (31, 17));
      final jpg = Uint8List.fromList(img.encodeJpg(img.Image(width: 640, height: 480)));
      expect(scanImageSize(jpg), (640, 480));
    });

    testWidgets('a large gallery photo turned sideways in EXIF: scaled to 3000 px and upright', (tester) async {
      await tester.runAsync(() async {
        // 4000 × 2000 stored landscape with orientation 6 (the phone held upright): a black square top-left
        final im = img.Image(width: 4000, height: 2000);
        img.fill(im, color: img.ColorRgb8(255, 255, 255));
        img.fillRect(im, x1: 0, y1: 0, x2: 399, y2: 399, color: img.ColorRgb8(0, 0, 0));
        im.exif.imageIfd.orientation = 6;
        final jpg = Uint8List.fromList(img.encodeJpg(im, quality: 90));
        final out = await prepareScanFile(ScanSourceFile.bytes('IMG_0001.HEIC', jpg, photo: true));
        expect(out.single.$1, 'IMG_0001.jpg');
        final back = img.decodeJpg(out.single.$2)!;
        expect((back.width, back.height), (1500, 3000), reason: 'upright (portrait), long side 3000');
        expect(img.decodeJpgExif(out.single.$2)?.imageIfd.orientation, anyOf(isNull, 1), reason: 'no orientation left to apply');
        // orientation 6 = turned 90° clockwise: the top-left square is now top-right
        expect(back.getPixel(back.width - 20, 20).r, lessThan(60));
        expect(back.getPixel(20, 20).r, greaterThan(200));
        expect(back.getPixel(back.width - 20, back.height - 20).r, greaterThan(200));
      });
    });

    test('files go untouched: a scanner JPEG with its EXIF, a PDF', () async {
      final im = img.Image(width: 2480, height: 3508);
      im.exif.imageIfd.orientation = 3;
      final jpg = Uint8List.fromList(img.encodeJpg(im, quality: 60));
      final out = await prepareScanFile(ScanSourceFile.bytes('page2.jpeg', jpg));
      expect(identical(out.single.$2, jpg), isTrue, reason: 'the server turns it (OpenCV reads the EXIF orientation)');
      expect(out.single.$1, 'page2.jpg');
      final pdf = _pdfBytes(100);
      expect((await prepareScanFile(ScanSourceFile.bytes('batch.PDF', pdf))).single, ('batch.pdf', pdf));
    });

    testWidgets('a HEIC this device cannot open fails with "save it as JPEG"; a two-page TIFF gives two JPEGs', (tester) async {
      await tester.runAsync(() async {
        final heic = Uint8List.fromList([0, 0, 0, 0x18, ...'ftypheic'.codeUnits, ...List.filled(64, 0)]);
        await expectLater(prepareScanFile(ScanSourceFile.bytes('IMG_1.heic', heic)), throwsA(isA<ScanPrepareError>().having((e) => e.code, 'code', 'heic')));
        // two pages, 40 × 60 and 60 × 40 (written by Pillow: package:image writes one page only)
        final tif = File('test/org/fixtures/scan_two_pages.tif').readAsBytesSync();
        final out = await prepareScanFile(ScanSourceFile.bytes('scan.tif', tif));
        expect([for (final x in out) x.$1], ['scan-p1.jpg', 'scan-p2.jpg']);
        expect(sniffScanBytes(out[1].$2), ScanBytesKind.jpeg);
        await expectLater(prepareScanFile(ScanSourceFile.bytes('notes.jpg', Uint8List.fromList('hello'.codeUnits))),
            throwsA(isA<ScanPrepareError>().having((e) => e.code, 'code', 'unsupported')));
      });
    });
  });

  group('screens', () {
    final connected = ValueNotifier<bool>(true);
    final stream = LiveStreamHandle(connected: connected, bind: () {}, release: () {});

    testWidgets('bubble sheets: the pick\'s summary → Upload → parts into ONE batch → its progress', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final uploads = <String>[];
      final gets = <String>[];
      final fake = FakeApi({
        'POST /api/v1/exam/exams/1/scans': (RequestOptions o) {
          final form = o.data as FormData;
          final batch = form.fields.where((f) => f.key == 'batch_id').map((f) => f.value).firstOrNull;
          uploads.add(_part([for (final f in form.files) f.value.filename ?? ''], batch));
          return {'batch_id': 55, 'pages': [for (var i = 0; i < form.files.length; i++) i + 1], 'duplicates': uploads.length == 2 ? 1 : 0, 'omr': true};
        },
        'GET /api/v1/exam/exams/1/omr/batches/*': (RequestOptions o) {
          gets.add(o.uri.pathSegments.last);
          return {'batch_id': 55, 'exam_id': 1, 'kind': 'omr', 'total': 3, 'done': 1, 'graded': 1, 'review': 0, 'rejected': 0, 'failed': 0,
            'pending': 2, 'status': 'processing', 'rejected_pages': [], 'en': '1 of 3 papers processed', 'ar': 'عولجت ورقة من 3'};
        },
      }, latency: const Duration(milliseconds: 10))
        ..install();
      addTearDown(fake.uninstall);
      final pick = ScanPick(ScanSource.folder, [
        _f('Exam/page10.pdf', size: 5 * 1024 * 1024),
        _f('Exam/page2.pdf', size: 5 * 1024 * 1024),
        _f('Exam/page1.pdf', size: 5 * 1024 * 1024),
        _f('Exam/notes.txt'),
        _f('Exam/.DS_Store'),
      ], folder: 'Exam');
      await tester.pumpWidget(layoutHost(OmrScanProgressScreen(examId: 1, picked: pick, liveBus: LiveEvents.instance, liveStream: stream), scale: 1, scaffold: false));
      await tester.pump();
      expect(find.text('3 files found'), findsOneWidget);
      expect(find.text('From the folder “Exam”'), findsOneWidget);
      expect(find.text('Exam/notes.txt'), findsOneWidget);
      expect(find.text('Not an image or a PDF'), findsOneWidget);
      expect(uploads, isEmpty, reason: 'nothing is sent before "Upload"');
      await tester.tap(find.byKey(const ValueKey('scan.upload')));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(uploads, ['page1.pdf|-', 'page2.pdf|55', 'page10.pdf|55'], reason: 'natural order, 5 MB each = one per part, the later parts join batch 55');
      expect(gets, isNotEmpty);
      expect(gets.toSet(), {'55'}, reason: 'one batch followed');
      expect(find.text('1 of 3 papers processed'), findsOneWidget);
      expect(find.textContaining('already uploaded and skipped'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
    });

    testWidgets('written answers: a file that fails is listed with Retry; Retry sends it into the same batch and closes', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      var fail = true;
      final sent = <String>[];
      ScanUploadOutcome? out;
      await tester.pumpWidget(layoutHost(
          Builder(
              builder: (context) => TextButton(
                    onPressed: () async => out = await Navigator.of(context).push<ScanUploadOutcome>(MaterialPageRoute(
                        builder: (_) => ScanUploadPage(
                              pick: ScanPick(ScanSource.files, [_f('a.pdf'), _f('b.pdf')]),
                              send: (files, batch) async {
                                final names = [for (final f in files) f.$1];
                                sent.add(_part(names, batch));
                                if (fail && names.contains('b.pdf')) return EngineResult.fail(503, 'grading_busy', 'busy');
                                return _ok(12, files.length);
                              },
                            ))),
                    child: const Text('go'),
                  )),
          scale: 1));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('2 files found'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('scan.upload')));
      await tester.pumpAndSettle();
      expect(sent.first, 'a.pdf,b.pdf|-');
      expect(find.text('2 files were not uploaded'), findsOneWidget, reason: 'the whole part failed on a busy server');
      expect(find.byKey(const ValueKey('scan.retry')), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('scan.retry')));
      await tester.pumpAndSettle();
      expect(sent.last, 'a.pdf,b.pdf|-', reason: 'nothing went the first time: no batch yet');
      expect(out?.batchId, 12);
      expect(out?.pages, 2);
      expect(find.byKey(const ValueKey('scan.retry')), findsNothing, reason: 'closed once everything went');
    });
  });

  group('layout', () {
    final plan = planScanFiles([
      for (var i = 1; i <= 9; i++) _f('Scanner output — Class 3A, Tuesday/page$i.jpg'),
      for (var i = 1; i <= 3; i++) _f('Scanner output — Class 3A, Tuesday/batch $i.pdf'),
      _f('Scanner output — Class 3A, Tuesday/a very long file name from the scanner that keeps going.docx'),
      _f('Scanner output — Class 3A, Tuesday/empty.png', size: 0),
    ], folder: 'Scanner output — Class 3A, Tuesday');
    final failures = [
      ScanFailure(_f('a very long file name from the phone gallery IMG_20261103_101112.jpg'), 'Too large for the server in one request — split the file or lower its resolution'),
      ScanFailure(_f('IMG_2.heic'), 'A HEIC photo this device cannot open — save it as JPEG'),
    ];
    for (final (name, p) in [('android', _android), ('ios', _ios), ('desktop web', _desktopWeb)]) {
      testWidgets('the source sheet ($name)', (tester) async {
        await expectNoLayoutErrors(tester, () => ScanSourceSheet(platform: p, picker: (s, {bool single = false}) async => null, camera: true));
      });
    }
    testWidgets('the summary, the progress, the failures', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                ScanPickSummary(plan: plan, source: ScanSource.folder, onUpload: () {}, onChooseAgain: () {}),
                const SizedBox(height: 16),
                const ScanUploadProgress(done: 3, total: 12, current: 'Scanner output — Class 3A, Tuesday/a very long page name 0003.jpg'),
                const SizedBox(height: 16),
                ScanUploadFailures(failures: failures, onRetry: () {}),
              ]));
    });
    testWidgets('an empty folder, too many files', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                ScanPickSummary(plan: planScanFiles([_f('x/notes.txt')], folder: 'x'), source: ScanSource.folder, onUpload: () {}, onChooseAgain: () {}),
                ScanPickSummary(plan: const ScanPlan(files: [], skipped: [], tooMany: true, folder: 'C:'), onUpload: () {}, onChooseAgain: () {}),
              ]));
    });
  });
}
