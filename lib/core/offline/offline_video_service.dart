/// lib/core/offline/offline_video_service.dart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import 'package:flutter_education_app/features/shared/session/material/session_material_model.dart';
import 'package:flutter_education_app/features/student/courses/security/device_id_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// OfflineVideoService
// ════════════════════════════════════════════════════════════════════════════
// • Downloads a video and encrypts it WHILE downloading (AES-256-CTR).
//   No plain copy ever exists on disk.
// • Encrypted file lives in the app-private folder and is useless without the
//   key. The random per-video key lives in Android Keystore / iOS Keychain
//   (device-only on iOS, so it can't be restored onto another phone).
// • Playback: a loopback-only HTTP server (127.0.0.1, random port, random
//   token) decrypts on the fly and supports HTTP Range (seeking works).
// • Every download expires (default 30 days).
//
// File format:  "EFV1"(4) | nonce(8) | AES-CTR ciphertext...
// Works for progressive files (mp4 / webm). Not HLS/DASH. No-op on web.
// ════════════════════════════════════════════════════════════════════════════

/// One downloaded video, as shown on the Downloads screen.
class OfflineItem {
  const OfflineItem({
    required this.id,
    required this.sessionId,
    required this.materialId,
    required this.title,
    required this.tier,
    required this.sizeBytes,
    required this.createdAt,
    required this.expiresAt,
    this.description,
    this.courseId,
  });

  final String id;

  /// The course the video belongs to (null for a copy made before this was stored: its access cannot be checked).
  final int? courseId;
  final int sessionId;
  final int materialId;
  final String title;
  final String? description;
  final QualityTier tier;
  final int sizeBytes;
  final DateTime createdAt;
  final DateTime expiresAt;
}

class OfflineVideoService {
  OfflineVideoService._();
  static final OfflineVideoService instance = OfflineVideoService._();

  static const _magic = <int>[0x45, 0x46, 0x56, 0x31]; // "EFV1"
  static const _headerLen = 12; // magic(4) + nonce(8)
  static const _defaultValidity = Duration(days: 30);

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    // iOS: the key never leaves this device (not in backups / new phones).
    iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  );

  /// id -> progress (0..1) for downloads in flight.
  final ValueNotifier<Map<String, double>> downloading =
      ValueNotifier<Map<String, double>>(const {});

  /// ids of every valid offline copy. A NEW set is published on every change,
  /// so listeners (tile badges, Downloads screen) always get notified.
  final ValueNotifier<Set<String>> downloadedIds =
      ValueNotifier<Set<String>>(const {});

  Directory? _dirCache;
  Map<String, dynamic>? _index;
  final Map<String, _Entry> _entries = {};

  HttpServer? _server;
  Future<void>? _serverStarting;
  String _token = '';

  String idOf(int sessionId, int materialId) => '${sessionId}_$materialId';

  // ───────────────────────────────────────────────────────────────────────
  // Public API
  // ───────────────────────────────────────────────────────────────────────

  /// Call once at app start (cheap). Purges expired / broken copies and
  /// leftover partial downloads, then publishes [downloadedIds] — which lets
  /// main.dart decide synchronously whether the offline start-page makes sense.
  Future<void> init() async {
    if (kIsWeb) return;
    try {
      final dir = await _dir();
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.part')) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      final index = await _loadIndex();
      for (final id in index.keys.toList()) {
        await _validMeta(id);
      }
    } catch (_) {}
    _publish();
  }

  Future<bool> isDownloaded(int sessionId, int materialId) async {
    if (kIsWeb) return false;
    return (await _validMeta(idOf(sessionId, materialId))) != null;
  }

  /// All valid downloads, newest first.
  Future<List<OfflineItem>> listItems() async {
    if (kIsWeb) return const [];
    final index = await _loadIndex();
    final out = <OfflineItem>[];
    for (final id in index.keys.toList()) {
      final meta = await _validMeta(id);
      if (meta == null) continue;
      out.add(OfflineItem(
        id: id,
        sessionId: (meta['sessionId'] as num?)?.toInt() ?? 0,
        materialId: (meta['materialId'] as num?)?.toInt() ?? 0,
        title: meta['title'] as String? ?? '',
        description: meta['description'] as String?,
        courseId: (meta['courseId'] as num?)?.toInt(),
        tier: _tierOf(meta['tier'] as String?),
        sizeBytes: (meta['size'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (meta['createdAt'] as num?)?.toInt() ?? 0),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
            (meta['expiresAt'] as num?)?.toInt() ?? 0),
      ));
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// The course id stored with the copy, or null when unknown (an old copy).
  Future<int?> courseIdOf(int sessionId, int materialId) async {
    if (kIsWeb) return null;
    final meta = await _validMeta(idOf(sessionId, materialId));
    return (meta?['courseId'] as num?)?.toInt();
  }

  /// Playable variant pointing at the local decrypting server, or null.
  Future<MaterialVariant?> localVariant(int sessionId, int materialId) async {
    if (kIsWeb) return null;
    final id = idOf(sessionId, materialId);
    final meta = await _validMeta(id);
    if (meta == null) return null;
    final entry = await _entry(id);
    if (entry == null) return null;
    await _ensureServer();
    return MaterialVariant(
      url: 'http://127.0.0.1:${_server!.port}/$_token/$id.mp4',
      tier: _tierOf(meta['tier'] as String?),
      isAudio: false,
    );
  }

  /// Downloads [variant] and stores it encrypted. Throws on failure.
  Future<void> download({
    required int sessionId,
    required int materialId,
    required String title,
    required MaterialVariant variant,
    String? description,
    String? captionsUrl,
    int? courseId,
    Duration validFor = _defaultValidity,
  }) async {
    if (kIsWeb) throw UnsupportedError('Offline downloads need Android/iOS');
    final url = variant.url;
    if (url == null || url.isEmpty) throw StateError('no url');

    final id = idOf(sessionId, materialId);
    if (downloading.value.containsKey(id)) return; // already running
    _setProgress(id, 0);

    final dir = await _dir();
    final part = File('${dir.path}/$id.part');
    final out = File('${dir.path}/$id.enc');
    HttpClient? client;
    IOSink? sink;

    try {
      final key = _randomBytes(32);
      final nonce = _randomBytes(8);
      final cipher = CTRStreamCipher(AESEngine())
        ..init(true, ParametersWithIV(KeyParameter(key), _iv(nonce, 0)));

      client = HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 20);
      final req = await client.getUrl(Uri.parse(url));
      final headers = await DeviceIdService.instance.headers();
      for (final e in headers.entries) {
        req.headers.set(e.key, e.value);
      }
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength; // -1 when unknown

      sink = part.openWrite();
      sink.add(Uint8List.fromList([..._magic, ...nonce]));

      var got = 0;
      await for (final chunk in res) {
        final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        sink.add(cipher.process(data));
        got += data.length;
        if (total > 0) _setProgress(id, got / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (await out.exists()) await out.delete();
      await part.rename(out.path);

      // Captions are small plain text; a failed fetch never fails the download.
      var hasCaptions = false;
      if (captionsUrl != null && captionsUrl.isNotEmpty) {
        try {
          final req = await client.getUrl(Uri.parse(captionsUrl));
          final res = await req.close();
          if (res.statusCode == 200) {
            await File('${dir.path}/$id.vtt').writeAsString(await utf8.decoder.bind(res).join());
            hasCaptions = true;
          }
        } catch (_) {}
      }

      await _storage.write(key: _keyName(id), value: base64Encode(key));
      final index = await _loadIndex();
      index[id] = {
        'sessionId': sessionId,
        'materialId': materialId,
        'title': title,
        'description': description,
        'courseId': courseId,
        'tier': variant.tier.name,
        'captions': hasCaptions,
        'size': got,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'expiresAt': DateTime.now().add(validFor).millisecondsSinceEpoch,
      };
      await _saveIndex();
      _entries.remove(id);
      _publish();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      if (await part.exists()) await part.delete();
      rethrow;
    } finally {
      client?.close(force: true);
      _clearProgress(id);
    }
  }

  /// WebVTT text saved with the download, or null when the material had none.
  Future<String?> localCaptions(int sessionId, int materialId) async {
    if (kIsWeb) return null;
    try {
      final f = File('${(await _dir()).path}/${idOf(sessionId, materialId)}.vtt');
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(int sessionId, int materialId) =>
      _deleteById(idOf(sessionId, materialId));

  Future<void> deleteById(String id) => _deleteById(id);

  /// Call on logout / account deletion so the next user of this phone can't
  /// use the copies.
  Future<void> deleteAll() async {
    if (kIsWeb) return;
    final index = await _loadIndex();
    for (final id in index.keys.toList()) {
      await _deleteById(id);
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Storage helpers
  // ───────────────────────────────────────────────────────────────────────

  String _keyName(String id) => 'offline_key_$id';

  QualityTier _tierOf(String? name) => QualityTier.values.firstWhere(
        (t) => t.name == name,
        orElse: () => QualityTier.low,
      );

  void _publish() {
    downloadedIds.value = Set<String>.from((_index ?? const {}).keys);
  }

  Future<Directory> _dir() async {
    if (_dirCache != null) return _dirCache!;
    // Application *support* dir = private, not user-visible, not in gallery.
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!await d.exists()) await d.create(recursive: true);
    return _dirCache = d;
  }

  Future<Map<String, dynamic>> _loadIndex() async {
    if (_index != null) return _index!;
    final f = File('${(await _dir()).path}/index.json');
    try {
      _index = await f.exists()
          ? Map<String, dynamic>.from(jsonDecode(await f.readAsString()) as Map)
          : <String, dynamic>{};
    } catch (_) {
      _index = <String, dynamic>{};
    }
    return _index!;
  }

  Future<void> _saveIndex() async {
    final f = File('${(await _dir()).path}/index.json');
    await f.writeAsString(jsonEncode(_index ?? {}));
  }

  /// Metadata if the copy exists, the file is there and it hasn't expired.
  Future<Map<String, dynamic>?> _validMeta(String id) async {
    final index = await _loadIndex();
    final raw = index[id];
    if (raw is! Map) return null;
    final meta = Map<String, dynamic>.from(raw);
    final expires = (meta['expiresAt'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch > expires) {
      await _deleteById(id);
      return null;
    }
    final f = File('${(await _dir()).path}/$id.enc');
    if (!await f.exists()) {
      await _deleteById(id);
      return null;
    }
    return meta;
  }

  Future<void> _deleteById(String id) async {
    _entries.remove(id);
    try {
      final f = File('${(await _dir()).path}/$id.enc');
      if (await f.exists()) await f.delete();
      final vtt = File('${(await _dir()).path}/$id.vtt');
      if (await vtt.exists()) await vtt.delete();
    } catch (_) {}
    try {
      await _storage.delete(key: _keyName(id));
    } catch (_) {}
    final index = await _loadIndex();
    if (index.remove(id) != null) await _saveIndex();
    _publish();
  }

  Future<_Entry?> _entry(String id) async {
    final cached = _entries[id];
    if (cached != null) return cached;
    try {
      final keyB64 = await _storage.read(key: _keyName(id));
      if (keyB64 == null) return null;
      final file = File('${(await _dir()).path}/$id.enc');
      if (!await file.exists()) return null;

      final raf = await file.open();
      Uint8List header;
      int length;
      try {
        header = await raf.read(_headerLen);
        length = await raf.length();
      } finally {
        await raf.close();
      }
      if (header.length < _headerLen) return null;
      for (var i = 0; i < _magic.length; i++) {
        if (header[i] != _magic[i]) return null;
      }
      final e = _Entry(
        path: file.path,
        key: base64Decode(keyB64),
        nonce: Uint8List.fromList(header.sublist(4, 12)),
        length: length - _headerLen,
      );
      return _entries[id] = e;
    } catch (_) {
      return null;
    }
  }

  void _setProgress(String id, double p) {
    downloading.value = {...downloading.value, id: p};
  }

  void _clearProgress(String id) {
    final m = {...downloading.value}..remove(id);
    downloading.value = m;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Crypto helpers
  // ───────────────────────────────────────────────────────────────────────

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  /// IV = nonce(8 bytes) | blockIndex(8 bytes, big-endian).
  static Uint8List _iv(Uint8List nonce8, int block) {
    final iv = Uint8List(16);
    iv.setRange(0, 8, nonce8);
    ByteData.sublistView(iv).setUint64(8, block, Endian.big);
    return iv;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Local decrypting server (loopback only, token protected, Range aware)
  // ───────────────────────────────────────────────────────────────────────

  Future<void> _ensureServer() {
    if (_server != null) return Future.value();
    return _serverStarting ??= () async {
      _token = base64UrlEncode(_randomBytes(18)).replaceAll('=', '');
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen(_handle, onError: (_) {});
      _server = s;
    }();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      if (seg.length != 2 || seg[0] != _token) {
        res.statusCode = HttpStatus.forbidden;
        await res.close();
        return;
      }
      final id = seg[1].replaceAll('.mp4', '');
      final e = await _entry(id);
      if (e == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }

      final total = e.length;
      var start = 0;
      var end = total - 1;
      var partial = false;

      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
        if (m != null) {
          final s = m.group(1) ?? '';
          final en = m.group(2) ?? '';
          if (s.isEmpty && en.isNotEmpty) {
            start = max(0, total - int.parse(en)); // suffix range
          } else {
            if (s.isNotEmpty) start = int.parse(s);
            if (en.isNotEmpty) end = min(int.parse(en), total - 1);
          }
          partial = true;
        }
      }

      if (total <= 0 || start > end || start >= total) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await res.close();
        return;
      }

      res.statusCode = partial ? HttpStatus.partialContent : HttpStatus.ok;
      res.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentType = ContentType('video', 'mp4')
        ..contentLength = end - start + 1;
      if (partial) {
        res.headers
            .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }

      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await _stream(e, res, start, end);
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _stream(_Entry e, HttpResponse res, int start, int end) async {
    // CTR works in 16-byte blocks: start at the block boundary, then drop the
    // first (start % 16) decrypted bytes.
    final aligned = start - (start % 16);
    var skip = start - aligned;
    final cipher = CTRStreamCipher(AESEngine())
      ..init(false,
          ParametersWithIV(KeyParameter(e.key), _iv(e.nonce, aligned ~/ 16)));

    final raf = await File(e.path).open();
    try {
      await raf.setPosition(_headerLen + aligned);
      var remaining = end - start + 1;
      while (remaining > 0) {
        final want = min(64 * 1024, remaining + skip);
        final buf = await raf.read(want);
        if (buf.isEmpty) break;
        var plain = cipher.process(buf);
        if (skip > 0) {
          plain = Uint8List.sublistView(plain, min(skip, plain.length));
          skip = 0;
        }
        if (plain.length > remaining) {
          plain = Uint8List.sublistView(plain, 0, remaining);
        }
        res.add(plain);
        remaining -= plain.length;
        await res.flush(); // back-pressure: waits for the player to consume
      }
    } finally {
      await raf.close();
      try {
        await res.close();
      } catch (_) {}
    }
  }
}

class _Entry {
  _Entry({
    required this.path,
    required this.key,
    required this.nonce,
    required this.length,
  });

  final String path;
  final Uint8List key;
  final Uint8List nonce;

  /// Plain (decrypted) length in bytes.
  final int length;
}
