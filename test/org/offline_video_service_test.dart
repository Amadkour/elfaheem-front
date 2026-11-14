// OfflineVideoService (lib/core/offline/offline_video_service.dart): a video is encrypted while it downloads
// (AES-256-CTR, no plain copy on disk) and played back through a loopback server that checks a random token and
// answers HTTP Range requests. Everything runs on a temp folder and an in-memory key store
// (OfflineVideoService.test), against a real local HTTP server standing in for the media host.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_education_app/core/offline/offline_video_service.dart';
import 'package:flutter_education_app/features/sessions/material/session_material_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late HttpServer media;
  late Uint8List plain;
  late Map<String, String> keys;
  late OfflineVideoService svc;
  var mediaStatus = 200;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ovs_test_');
    final r = Random(7);
    // not a multiple of 16, so the last CTR block is partial
    plain = Uint8List.fromList(List<int>.generate(100003, (_) => r.nextInt(256)));
    mediaStatus = 200;
    media = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    media.listen((req) async {
      if (req.uri.path == '/v.vtt') {
        req.response.write('WEBVTT\n\n00:00.000 --> 00:01.000\nhi\n');
      } else {
        req.response.statusCode = mediaStatus;
        if (mediaStatus == 200) req.response.add(plain);
      }
      await req.response.close();
    });
    keys = <String, String>{};
    svc = OfflineVideoService.test(dir: dir, keys: keys);
  });

  tearDown(() async {
    await svc.debugCloseServer();
    await media.close(force: true);
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  MaterialVariant variant() =>
      MaterialVariant(url: 'http://127.0.0.1:${media.port}/v.mp4', tier: QualityTier.low, isAudio: false);

  Future<void> downloadOne({Duration validFor = const Duration(days: 30)}) => svc.download(
        sessionId: 3,
        materialId: 9,
        title: 'Lecture',
        courseId: 42,
        variant: variant(),
        captionsUrl: 'http://127.0.0.1:${media.port}/v.vtt',
        validFor: validFor,
      );

  Future<(int, Map<String, String>, Uint8List)> fetch(String url, {String? range, String method = 'GET'}) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl(method, Uri.parse(url));
      if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
      final res = await req.close();
      final body = BytesBuilder(copy: false);
      await for (final c in res) {
        body.add(c);
      }
      final h = <String, String>{};
      res.headers.forEach((k, v) => h[k] = v.join(','));
      return (res.statusCode, h, body.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  Future<String> playUrl() async => (await svc.localVariant(3, 9))!.url!;

  test('download encrypts on the way in and the loopback server decrypts it back byte for byte', () async {
    await downloadOne();

    final enc = File('${dir.path}/3_9.enc');
    expect(await enc.exists(), isTrue);
    expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    final raw = await enc.readAsBytes();
    expect(raw.length, plain.length + 12); // "EFV1" + nonce(8) + ciphertext
    expect(raw.sublist(0, 4), [0x45, 0x46, 0x56, 0x31]);
    // the ciphertext is not the plain file (CTR keeps the length)
    var same = 0;
    for (var i = 0; i < plain.length; i++) {
      if (raw[12 + i] == plain[i]) same++;
    }
    expect(same, lessThan(plain.length ~/ 100));
    expect(keys.keys, ['offline_key_3_9']);

    expect(await svc.isDownloaded(3, 9), isTrue);
    expect(await svc.courseIdOf(3, 9), 42);
    expect(await svc.localCaptions(3, 9), startsWith('WEBVTT'));
    final items = await svc.listItems();
    expect(items.single.title, 'Lecture');
    expect(items.single.sizeBytes, plain.length);

    final url = await playUrl();
    expect(url, startsWith('http://127.0.0.1:'));
    final (status, headers, body) = await fetch(url);
    expect(status, 200);
    expect(headers['accept-ranges'], 'bytes');
    expect(body, plain);
  });

  test('the loopback server refuses a wrong or missing token, and an unknown id is 404', () async {
    await downloadOne();
    final url = Uri.parse(await playUrl());
    final base = 'http://127.0.0.1:${url.port}';
    final token = url.pathSegments.first;
    expect(token.length, greaterThanOrEqualTo(20));

    expect((await fetch('$base/3_9.mp4')).$1, HttpStatus.forbidden); // no token
    expect((await fetch('$base/wrong-token/3_9.mp4')).$1, HttpStatus.forbidden);
    expect((await fetch('$base/${token}x/3_9.mp4')).$1, HttpStatus.forbidden);
    expect((await fetch('$base/$token/extra/3_9.mp4')).$1, HttpStatus.forbidden);
    final refused = await fetch('$base/wrong-token/3_9.mp4');
    expect(refused.$3, isEmpty); // nothing of the video leaks
    expect((await fetch('$base/$token/1_1.mp4')).$1, HttpStatus.notFound);
    expect((await fetch('$base/$token/..%2Findex.mp4')).$1, HttpStatus.notFound);
  });

  test('range requests: unaligned, suffix, open-ended, clamped, unsatisfiable, HEAD', () async {
    await downloadOne();
    final url = await playUrl();
    final n = plain.length;

    Future<void> expectRange(String range, int start, int end) async {
      final (status, h, body) = await fetch(url, range: range);
      expect(status, HttpStatus.partialContent, reason: range);
      expect(h['content-range'], 'bytes $start-$end/$n', reason: range);
      expect(body, plain.sublist(start, end + 1), reason: range);
    }

    await expectRange('bytes=0-0', 0, 0);
    await expectRange('bytes=17-50000', 17, 50000); // starts inside a CTR block
    await expectRange('bytes=65530-65560', 65530, 65560); // crosses the 64 KiB read chunk
    await expectRange('bytes=99990-', 99990, n - 1);
    await expectRange('bytes=-100', n - 100, n - 1);
    await expectRange('bytes=100000-999999', 100000, n - 1); // end past the file is clamped
    await expectRange('bytes=-999999', 0, n - 1); // suffix longer than the file

    final bad = await fetch(url, range: 'bytes=$n-');
    expect(bad.$1, HttpStatus.requestedRangeNotSatisfiable);
    expect(bad.$2['content-range'], 'bytes */$n');
    expect((await fetch(url, range: 'bytes=500-100')).$1, HttpStatus.requestedRangeNotSatisfiable);
    // a start too long for an int was a FormatException → an empty 200; now it is unsatisfiable
    expect((await fetch(url, range: 'bytes=99999999999999999999-')).$1, HttpStatus.requestedRangeNotSatisfiable);
    await expectRange('bytes=10-99999999999999999999', 10, n - 1);

    final head = await fetch(url, method: 'HEAD');
    expect(head.$1, 200);
    expect(head.$2['content-length'], '$n');
    expect(head.$3, isEmpty);
  });

  test('a failed download leaves nothing behind; an expired copy is purged with its key', () async {
    mediaStatus = 403;
    await expectLater(downloadOne(), throwsA(isA<HttpException>()));
    expect(dir.listSync().where((f) => f.path.endsWith('.part') || f.path.endsWith('.enc')), isEmpty);
    expect(keys, isEmpty);
    expect(await svc.isDownloaded(3, 9), isFalse);

    mediaStatus = 200;
    await downloadOne(validFor: const Duration(milliseconds: -1));
    expect(await svc.isDownloaded(3, 9), isFalse);
    expect(await svc.localVariant(3, 9), isNull);
    expect(File('${dir.path}/3_9.enc').existsSync(), isFalse);
    expect(keys, isEmpty);
  });

  test('deleteAll removes every copy and key (sign-out)', () async {
    await downloadOne();
    await svc.deleteAll();
    expect(await svc.listItems(), isEmpty);
    expect(keys, isEmpty);
    expect(svc.downloadedIds.value, isEmpty);
  });

  test('on the web the /downloads route sends the person home (main.dart router)', () {
    // kDownloadsAvailable is a const (!kIsWeb), so the VM can't take the web branch; pin the guard in the router.
    final src = File('lib/main.dart').readAsStringSync();
    final i = src.indexOf("case '/downloads':");
    expect(i, greaterThan(0));
    final body = src.substring(i, src.indexOf('case ', i + 10));
    expect(body, contains('if (!kDownloadsAvailable) return _fade(const _Guard(child: _RedirectHome()), settings);'));
    expect(body.indexOf('kDownloadsAvailable'), lessThan(body.indexOf('DownloadsScreen')));
  });
}
