// tool/studio_harness/main.dart — the REAL Studio page (RecordStudioPage, its real video player, timeline, panels and
// export panel) in a real browser, over a local stand-in source, so it can be driven with Playwright without the
// server's MinIO / Google Drive (D-900). Never part of the app build.
//
//   flutter build web --profile -t tool/studio_harness/main.dart -o build/studio_harness --base-href /
//   (then copy demo.mp4 + sprite.png into build/studio_harness/harness/ and serve the folder)
//   ?lang=ar · ?dark=1 · ?mode=material (drafts) · ?fail=render (the render call fails once) · ?slow=1 (slow project)
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/records/records_api.dart';
import 'package:flutter_education_app/features/records/records_share_api.dart';
import 'package:flutter_education_app/features/records/records_studio.dart';
import 'package:flutter_education_app/features/records/records_studio_parts.dart';
import 'package:flutter_education_app/features/records/studio_source.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;
import 'package:shared_preferences/shared_preferences.dart';

final _q = Uri.base.queryParameters;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  translation = json.decode(await rootBundle.loadString('assets/translation.json')) as Map<String, dynamic>;
  AppConfig.lang = _q['lang'] == 'ar' ? 'ar' : 'en';
  AppConfig.disableList = [];
  runApp(const _Harness());
}

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeConfigProvider(api: ApiClient());
    final ar = AppConfig.lang == 'ar';
    return ThemeConfigScope(
      provider: theme,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: displayTheme(theme.materialTheme(dark: false), const DisplayPrefs()),
        darkTheme: displayTheme(theme.materialTheme(dark: true), const DisplayPrefs()),
        themeMode: _q['dark'] == '1' ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => AppDisplayScope(child: Directionality(textDirection: ar ? TextDirection.rtl : TextDirection.ltr, child: w!)),
        home: const _Home(),
      ),
    );
  }
}

RecordItem _source() => RecordItem.fromJson({
      'recording_id': 1,
      'kind': 'meeting',
      'status': 'done',
      'quality': '720p',
      'destination': 'google_drive',
      'size': 48000000,
      'duration_seconds': 60.0,
      'created_at': '2026-11-13T09:00:00',
      'title': AppConfig.lang == 'ar' ? 'الدرس الثالث — الكسور والأعداد العشرية' : 'Lesson 3 — Fractions and decimals',
      'can_edit': true,
      'can_play': true,
    })!;

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => RecordStudioPage(item: _source(), source: _HarnessSource(), onPlay: (_, _) {});
}

/// A local source: the media from the harness folder, the project in memory (and the browser's own storage through
/// the Studio's device copy), jobs that run through their stages in about eight seconds.
class _HarnessSource with StudioAssetCalls implements StudioSource {
  // kept in the browser's storage like a server would keep them, so a reload finds the project and the jobs (D-905)
  static Map<String, dynamic>? _doc;
  static final _jobs = <int, ({DateTime at, String title, bool cancelled, Map<String, dynamic> params})>{};
  static bool _restored = false;

  static Future<void> _restore() async {
    if (_restored) return;
    _restored = true;
    final p = await SharedPreferences.getInstance();
    if (_q['fresh'] == '1') {
      await p.remove('harness.doc');
      await p.remove('harness.jobs');
      return;
    }
    final d = p.getString('harness.doc');
    if (d != null) _doc = json.decode(d) as Map<String, dynamic>;
    final j = p.getString('harness.jobs');
    if (j != null) {
      for (final e in (json.decode(j) as Map<String, dynamic>).entries) {
        final v = e.value as Map<String, dynamic>;
        _jobs[int.parse(e.key)] = (at: DateTime.fromMillisecondsSinceEpoch(v['at'] as int), title: '${v['title']}', cancelled: v['cancelled'] == true, params: Map<String, dynamic>.from(v['params'] as Map));
      }
    }
  }

  static Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    if (_doc == null) {
      await p.remove('harness.doc');
    } else {
      await p.setString('harness.doc', json.encode(_doc));
    }
    await p.setString('harness.jobs', json.encode({for (final e in _jobs.entries) '${e.key}': {'at': e.value.at.millisecondsSinceEpoch, 'title': e.value.title, 'cancelled': e.value.cancelled, 'params': e.value.params}}));
  }
  static var _failed = false;

  @override
  ApiClient get assetClient => ApiClient();

  @override
  List<StudioTool> get tools => _q['mode'] == 'material' ? const [StudioTool.edit, StudioTool.text, StudioTool.image, StudioTool.history, StudioTool.quality, StudioTool.split] : StudioTool.values;
  @override
  bool get drafts => _q['mode'] == 'material';
  @override
  String get jobEventKind => 'recording';
  @override
  String get framesEventKind => 'record_frames';

  Future<void> _wait([int ms = 250]) async {
    await _restore();
    await Future.delayed(Duration(milliseconds: _q['slow'] == '1' ? ms * 8 : ms));
  }

  @override
  Future<RecordPlay> play(int sourceId) async {
    await _wait();
    return RecordPlay(url: Uri.base.resolve('harness/demo.webm').toString());
  }

  @override
  Future<RecordFrames> frames(int sourceId) async {
    await _wait(400);
    final r = math.Random(3);
    final wave = Uint8List.fromList([for (var i = 0; i < 240; i++) (i % 8 < 1 ? 220 : 30 + r.nextInt(90))]);
    return RecordFrames(status: 'ready', url: Uri.base.resolve('harness/sprite.png').toString(), count: 25, waveform: wave);
  }

  @override
  Future<Map<String, dynamic>?> loadProject(int sourceId) async {
    await _wait(600);
    return _doc;
  }

  @override
  Future<void> saveProject(int sourceId, Map<String, dynamic>? doc, {int? base}) async {
    await _wait();
    _doc = doc;
    await _persist();
  }

  RecordItem _item(int id) {
    final j = _jobs[id]!;
    final s = DateTime.now().difference(j.at).inMilliseconds / 1000;
    if (j.cancelled) {
      return RecordItem.fromJson({'recording_id': id, 'kind': 'edit', 'status': 'failed', 'cancelled': true, 'error': 'stopped', 'title': j.title})!;
    }
    if (s >= 8) {
      return RecordItem.fromJson({'recording_id': id, 'kind': 'edit', 'status': 'done', 'has_project': true, 'can_play': true, 'title': j.title, 'duration_seconds': 50.0})!;
    }
    final stage = s < 1 ? 'queued' : (s < 2.5 ? 'downloading' : (s < 7 ? 'processing' : 'uploading'));
    return RecordItem.fromJson({
      'recording_id': id,
      'kind': 'edit',
      'status': 'assembling',
      'stage': stage,
      'progress': (s / 8 * 100).floor().clamp(0, 99),
      'title': j.title,
    })!;
  }

  @override
  Future<List<RecordItem>> render(int sourceId, Map<String, dynamic> params) async {
    await _wait(500);
    if (_q['fail'] == 'render' && !_failed) {
      _failed = true;
      throw const ApiException(statusCode: 0, type: ApiErrorType.network, message: 'No connection');
    }
    final id = 100 + _jobs.length;
    _jobs[id] = (at: DateTime.now(), title: '${params['title'] ?? 'Edit'}', cancelled: false, params: params);
    await _persist();
    return [_item(id)];
  }

  @override
  Future<RecordItem?> get(int jobId) async {
    await _wait(120);
    // the job runs from its start whatever happened to the page
    return _jobs.containsKey(jobId) ? _item(jobId) : null;
  }

  @override
  Future<RecordItem?> cancel(int jobId) async {
    final j = _jobs[jobId]!;
    _jobs[jobId] = (at: j.at, title: j.title, cancelled: true, params: j.params);
    await _persist();
    return _item(jobId);
  }

  @override
  Future<RecordItem?> retry(int jobId) async {
    final j = _jobs[jobId]!;
    _jobs[jobId] = (at: DateTime.now(), title: j.title, cancelled: false, params: j.params);
    await _persist();
    return _item(jobId);
  }

  @override
  Future<Map<String, dynamic>?> jobProject(int jobId) async => {'history': _jobs[jobId]?.params['history']};

  @override
  Future<StudioDownload> download(int sourceId) async => StudioDownload(url: Uri.base.resolve('harness/demo.webm').toString(), fileName: 'lesson.mp4');
  @override
  Future<StudioDownload> downloadJob(int jobId) => download(jobId);

  @override
  Future<StudioAsset> uploadAsset(Uint8List png, {String fileName = 'overlay.png'}) async {
    await _wait(200);
    final r = math.Random();
    return StudioAsset(id: [for (var i = 0; i < 32; i++) '0123456789abcdef'[r.nextInt(16)]].join());
  }

  @override
  Future<Map<String, String>> assetLinks(List<String> ids) async => const {};

  @override
  Future<List<RecordItem>> edit(int sourceId, RecordEdit edit) async => const [];
  @override
  Future<List<RecordItem>> merge(List<int> sourceIds, {String? title, bool deleteSources = false}) => render(sourceIds.first, {'title': title});
  @override
  Future<RecordItem?> setCover(int sourceId, Uint8List bytes, {String fileName = 'cover.jpg'}) async => _source();
  @override
  Future<RecordItem?> clearCover(int sourceId) async => _source();
}
