// lib/features/games/core/recitation_cache.dart — the file cache of the recitation audio (Games v4 T24, CONTRACT §9).
//
// One folder per reciter, one file per URL: an `ayah_files` reciter caches one small file per ayah, a `surah_files`
// reciter one file per surah (every ayah of the surah shares the URL, so it is the same file). Phone / desktop only:
// on the web there is no file system and the browser streams the file with range requests (see game_audio.dart).
// A download goes to `<name>.part` and is renamed when it is whole, so a half file is never played.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where the cache lives (tests pass a temp folder).
typedef CacheRoot = Future<Directory> Function();

/// Downloads [url] into [to] (tests pass a fake).
typedef CacheFetch = Future<void> Function(String url, File to);

class RecitationCache {
  RecitationCache({CacheRoot? root, CacheFetch? fetch})
      : _root = root ?? _defaultRoot,
        _fetch = fetch ?? _defaultFetch;

  static final RecitationCache instance = RecitationCache();

  final CacheRoot _root;
  final CacheFetch _fetch;
  final Map<String, Future<File?>> _running = {};

  static Future<Directory> _defaultRoot() async => Directory('${(await getTemporaryDirectory()).path}/games_recitation');

  static Future<void> _defaultFetch(String url, File to) async {
    await Dio().download(url, to.path);
  }

  /// The file name of [url]: its last path segment (`001002.mp3`, `112.mp3`), cleaned.
  static String fileName(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final last = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'audio';
    return last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  static String _folder(String reciter) => reciter.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<File> _file(String reciter, String url) async {
    final root = await _root();
    return File('${root.path}/${_folder(reciter)}/${fileName(url)}');
  }

  /// The cached file of [url] for [reciter], or null (always null on the web).
  Future<File?> cached(String reciter, String url) async {
    if (kIsWeb) return null;
    try {
      final f = await _file(reciter, url);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] if it is not cached yet; one download per file at a time. Null on the web or on a failure.
  Future<File?> ensure(String reciter, String url) {
    if (kIsWeb) return Future.value(null);
    return _running[url] ??= _download(reciter, url).whenComplete(() {
      _running.remove(url);
    });
  }

  Future<File?> _download(String reciter, String url) async {
    try {
      final f = await _file(reciter, url);
      if (await f.exists()) return f;
      await f.parent.create(recursive: true);
      final part = File('${f.path}.part');
      await _fetch(url, part);
      await part.rename(f.path);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Deletes every file of [reciter] (a reciter was disabled or the player cleans up).
  Future<void> clear(String reciter) async {
    try {
      final dir = Directory('${(await _root()).path}/${_folder(reciter)}');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
