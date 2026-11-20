// lib/features/store/store_vault_io.dart — a bought file kept encrypted on a phone or a desktop (D-1333), with the
// scheme of the offline videos (lib/core/offline/offline_video_service.dart):
//
//   • the file is encrypted WHILE it downloads (AES-256-CTR): no plain copy is ever written;
//   • file format "EFV1"(4) | nonce(8) | ciphertext, in the app's private support folder (`store_files/`);
//   • a random key per file in the Keystore / Keychain (device-only on iOS);
//   • the SHA-256 of the plain bytes is checked against the server's before the copy is kept;
//   • read() decrypts into memory for the reader, which shows it under ScreenSecurity.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

/// The server's SHA-256 did not match the bytes that arrived.
class StoreFileCorrupt implements Exception {
  const StoreFileCorrupt();

  /// The code storeErrorText knows.
  String get code => 'store_file_corrupt';

  @override
  String toString() => 'store_file_corrupt';
}

class StoreVault {
  StoreVault._()
      : _keys = const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
        ),
        _memKeys = null;

  /// Tests: a folder and an in-memory key map, no platform channel.
  @visibleForTesting
  StoreVault.test({required Directory dir, Map<String, String>? keys})
      : _dirCache = dir,
        _keys = null,
        _memKeys = keys ?? <String, String>{};

  static final StoreVault instance = StoreVault._();

  static const _magic = <int>[0x45, 0x46, 0x56, 0x31]; // "EFV1"
  static const _headerLen = 12;

  final FlutterSecureStorage? _keys;
  final Map<String, String>? _memKeys;
  Directory? _dirCache;

  bool get available => true;

  static String _keyName(int itemId) => 'store_file_key_$itemId';

  Future<String?> _readKey(int id) async => _memKeys != null ? _memKeys[_keyName(id)] : await _keys!.read(key: _keyName(id));

  Future<void> _writeKey(int id, String v) async {
    if (_memKeys != null) {
      _memKeys[_keyName(id)] = v;
    } else {
      await _keys!.write(key: _keyName(id), value: v);
    }
  }

  Future<void> _deleteKey(int id) async {
    if (_memKeys != null) {
      _memKeys.remove(_keyName(id));
    } else {
      await _keys!.delete(key: _keyName(id));
    }
  }

  Future<Directory> _dir() async {
    if (_dirCache != null) return _dirCache!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/store_files');
    if (!await d.exists()) await d.create(recursive: true);
    return _dirCache = d;
  }

  Future<File> _file(int itemId) async => File('${(await _dir()).path}/$itemId.enc');

  Future<bool> has(int itemId) async {
    try {
      return await (await _file(itemId)).exists() && await _readKey(itemId) != null;
    } catch (_) {
      return false;
    }
  }

  static Uint8List _random(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
  }

  static Uint8List _iv(Uint8List nonce8) {
    final iv = Uint8List(16);
    iv.setRange(0, 8, nonce8);
    return iv; // block counter 0 in the last 8 bytes
  }

  /// Fetches [url] (the short single-use link; it redirects to the signed file) and keeps it encrypted. A [sha256]
  /// from the server is checked against the plain bytes; a mismatch keeps nothing and throws [StoreFileCorrupt].
  Future<void> save(int itemId, Uri url, {String sha256 = '', void Function(double progress)? onProgress}) async {
    final dir = await _dir();
    final part = File('${dir.path}/$itemId.part');
    final out = await _file(itemId);
    final client = HttpClient()
      ..autoUncompress = false
      ..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      final key = _random(32);
      final nonce = _random(8);
      final cipher = CTRStreamCipher(AESEngine())..init(true, ParametersWithIV(KeyParameter(key), _iv(nonce)));
      final res = await (await client.getUrl(url)).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
      final total = res.contentLength;
      final digest = _DigestSink();
      final hasher = hash.sha256.startChunkedConversion(digest);
      sink = part.openWrite()..add(Uint8List.fromList([..._magic, ...nonce]));
      var got = 0;
      await for (final chunk in res) {
        final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        hasher.add(data);
        sink.add(cipher.process(data));
        got += data.length;
        if (total > 0) onProgress?.call(got / total);
      }
      hasher.close();
      await sink.flush();
      await sink.close();
      sink = null;
      if (sha256.isNotEmpty && digest.value?.toString() != sha256.toLowerCase()) throw const StoreFileCorrupt();
      if (await out.exists()) await out.delete();
      await part.rename(out.path);
      await _writeKey(itemId, base64Encode(key));
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      client.close(force: true);
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}
    }
  }

  /// The plain bytes, in memory only (for the reader).
  Future<Uint8List> read(int itemId) async {
    final f = await _file(itemId);
    final k = await _readKey(itemId);
    if (k == null || !await f.exists()) throw StateError('not kept');
    final raw = await f.readAsBytes();
    if (raw.length < _headerLen || !listEquals(raw.sublist(0, 4), _magic)) throw StateError('bad file');
    final nonce = Uint8List.sublistView(raw, 4, _headerLen);
    final cipher = CTRStreamCipher(AESEngine())..init(false, ParametersWithIV(KeyParameter(base64Decode(k)), _iv(Uint8List.fromList(nonce))));
    return cipher.process(Uint8List.sublistView(raw, _headerLen));
  }

  Future<void> remove(int itemId) async {
    try {
      final f = await _file(itemId);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    try {
      await _deleteKey(itemId);
    } catch (_) {}
  }

  /// Every kept file and key (a sign-out, Phase 7).
  Future<void> wipe() async {
    try {
      final d = await _dir();
      await for (final e in d.list()) {
        final name = e.uri.pathSegments.last;
        final id = int.tryParse(name.split('.').first);
        if (id != null) await remove(id);
      }
    } catch (_) {}
  }
}

class _DigestSink implements Sink<hash.Digest> {
  hash.Digest? value;

  @override
  void add(hash.Digest data) => value = data;

  @override
  void close() {}
}
