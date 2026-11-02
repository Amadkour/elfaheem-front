// App versions (D-143) sample replies, shaped as docs/release/APP_RELEASES.md describes them (the server is built in
// parallel on feature/app-releases; regenerate from its e2e run once it lands). Shared by the layout test, the
// fake-backend test and the visual renders.
import 'package:flutter_education_app/features/admin/app_releases/app_releases_models.dart';

List<Map<String, dynamic>> sampleLog(int n, {int from = 1}) => [
      for (var i = from; i < from + n; i++)
        {
          'seq': i,
          'line': switch (i % 7) {
            0 => '[gate] flutter analyze --no-fatal-infos --fatal-warnings … 0 warnings, 0 errors',
            1 => '[git] checkout production @ 3f9c2ab1d4 (pinned)',
            2 => '[build] flutter build apk --release --split-per-abi --build-name=1.4.1 --build-number=53',
            3 => 'Running Gradle task \'assembleRelease\'…',
            4 => '✓ Built build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (48.7MB)',
            5 => '[test] 00:41 +812: test/org/org_dashboard_v3_test.dart: home loads once',
            _ => '[upload] NextBrain-1.4.1-53-arm64-v8a.apk 32 % (15.6 MB / 48.7 MB)',
          },
          'at': '2026-11-02T11:${(i % 60).toString().padLeft(2, '0')}:00',
        },
    ];

Map<String, dynamic> releaseJson({
  int id = 7,
  String platform = 'android',
  String version = '1.4.1',
  int build = 53,
  String status = 'building',
  String policy = 'recommended',
  String source = 'website',
  String? storeUrl,
  bool isLive = false,
  bool autoPublish = true,
  double? progress,
  String? step,
  String? error,
  List<Map<String, dynamic>> artifacts = const [],
  List<Map<String, dynamic>> log = const [],
  String gate = 'test_first',
}) =>
    {
      'id': id,
      'platform': platform,
      'version': version,
      'build_number': build,
      'status': status,
      'policy': policy,
      'min_supported': policy == 'must' ? '1.3.0' : null,
      'branch': 'production',
      'commit_sha': '3f9c2ab1d4e8a7c6b5d4e3f2a1b0c9d8e7f6a5b4',
      'gate': gate,
      'source': source,
      'store_url': storeUrl,
      'auto_publish': autoPublish,
      'notes_ar': 'تشغيل أسرع للدروس، إصلاح تنبيهات الحضور، ووضع ليلي أوضح.',
      'notes_en': 'Faster lessons, fixed attendance alerts and a clearer dark mode.',
      'progress': progress,
      'error': error,
      'created_by': 1,
      'created_at': '2026-11-02T10:58:12.120000',
      'started_at': status == 'queued' ? null : '2026-11-02T11:00:03',
      'finished_at': const {'ready', 'live', 'failed', 'canceled', 'rolled_back'}.contains(status) ? '2026-11-02T11:27:40' : null,
      'live_at': isLive ? '2026-11-02T11:28:02' : null,
      'current': isLive,
      'attempt': 1,
      'buildable': const {'android', 'web', 'linux'}.contains(platform),
      'actions': {
        'cancel': const {'queued', 'building', 'testing'}.contains(status),
        'retry': const {'failed', 'canceled'}.contains(status) && const {'android', 'web', 'linux'}.contains(platform),
        'publish': status == 'ready',
        'rollback': isLive,
      },
      'artifacts': artifacts,
      'log': log,
    };

const apkArtifacts = [
  {'name': 'NextBrain-1.4.0-52-arm64-v8a.apk', 'size': 48700000, 'sha256': '9b1c0d3e5f7a9b1c0d3e5f7a9b1c0d3e5f7a9b1c'},
  {'name': 'NextBrain-1.4.0-52-armeabi-v7a.apk', 'size': 44100000, 'sha256': 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2'},
  {'name': 'NextBrain-1.4.0-52-universal.apk', 'size': 96300000, 'sha256': 'f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1'},
];

/// The list page's reply: every platform, every kind of state.
Map<String, dynamic> releasesListJson() => {
      'items': [
        releaseJson(id: 9, progress: 46, step: 'flutter build apk --release (arm64-v8a)', log: sampleLog(40)),
        releaseJson(id: 6, version: '1.4.0', build: 52, status: 'live', isLive: true, progress: 100, artifacts: apkArtifacts),
        releaseJson(id: 4, version: '1.3.9', build: 51, status: 'live', policy: 'optional', progress: 100),
        releaseJson(id: 8, platform: 'ios', version: '1.4.0', build: 52, status: 'live', isLive: true, gate: 'direct'),
        releaseJson(id: 10, platform: 'web', version: '1.4.1', build: 53, status: 'ready', autoPublish: false, progress: 100, policy: 'must',
            artifacts: [{'name': 'web-1.4.1-53.tar.gz', 'size': 31400000}]),
        releaseJson(id: 5, platform: 'web', version: '1.4.0', build: 52, status: 'live', isLive: true, progress: 100),
        releaseJson(id: 11, platform: 'linux', version: '1.4.0', build: 52, status: 'failed', progress: 18,
            error: 'The gate failed: flutter analyze found 2 warnings (lib/features/org/org_ui.dart:118).'),
        releaseJson(id: 3, platform: 'windows', version: '1.3.0', build: 40, status: 'live', isLive: true, gate: 'direct',
            storeUrl: 'https://nextbrain.site/releases/NextBrain-1.3.0-setup.exe'),
      ],
      'total': 8,
      'page': 1,
      'page_size': 100,
      'live': {'android': '1.4.0', 'ios': '1.4.0', 'web': '1.4.0', 'linux': null, 'windows': '1.3.0', 'macos': null},
      'next_build_number': {'android': 54, 'ios': 53, 'web': 54, 'linux': 53, 'windows': 41, 'macos': 1},
    };

Map<String, dynamic> builderJson({bool online = true, bool busy = true}) => {
      'online': online,
      'last_seen': online ? DateTime.now().toUtc().subtract(const Duration(seconds: 40)).toIso8601String() : '2026-11-01T22:10:00',
      'version': '0.3.1',
      'busy_job': busy ? {'id': 9, 'platform': 'android', 'version': '1.4.1', 'status': 'building', 'progress': 46} : null,
      'token_set': true,
      'token_rotated_at': '2026-11-01T09:00:00',
      'configured': true,
    };

List<AppRelease> sampleReleases() => ReleasePage.fromJson(releasesListJson()).items;

// ── D-144 (Codemagic): the config answer, Codemagic releases and the public downloads, shaped as the backend's
// services/app_release_codemagic.py builds them (config_payload, the release dict, downloads()). ──

/// `GET /api/v1/admin/app-releases/config`. [notReady] maps a `platform:channel` to what it misses; [codemagic]
/// false makes every built channel miss the API token.
Map<String, dynamic> releaseConfigJson({
  bool codemagic = true,
  Map<String, List<String>> notReady = const {
    'android:store': ['package_name_example'],
    'ios:store': ['APP_STORE_APP_ID', 'IOS_BUNDLE_ID'],
  },
  String packageName = 'com.example.flutter_education_app',
}) {
  const pairs = {
    'android:store': true,
    'android:website': true,
    'ios:store': true,
    'ios:website': false,
    'web:website': true,
    'linux:website': true,
    'windows:website': true,
    'windows:store': false,
    'macos:store': false,
    'macos:website': false,
  };
  final cm = codemagic ? <String>[] : ['CODEMAGIC_API_TOKEN'];
  String reason(String m, bool ar) => ar ? 'سبب من الخادم: $m' : 'From the server: $m';
  Map<String, dynamic> channel(String key, bool built) {
    final missing = [if (built) ...cm, ...?notReady[key]];
    return {
      'ready': missing.isEmpty,
      'missing': missing,
      'reasons_ar': [for (final m in missing) reason(m, true)],
      'reasons_en': [for (final m in missing) reason(m, false)],
      'build': built ? 'codemagic' : 'record',
    };
  }

  return {
    'codemagic': {'ready': codemagic, 'missing': cm, 'app_id': '6544a1c2e8b4f0b7d1a9c3e2', 'build_url_base': null},
    'channels': {for (final e in pairs.entries) e.key: channel(e.key, e.value)},
    'platforms': {
      'android': ['store', 'website'],
      'ios': ['store', 'website'],
      'web': ['website'],
      'linux': ['website'],
      'windows': ['store', 'website'],
      'macos': ['store', 'website'],
    },
    'defaults': {
      'android': {
        'branch': 'production',
        'workflows': {'store': 'android-store', 'website': 'android-website'},
        'track': 'internal',
        'package_name': packageName,
        'store_url': 'https://play.google.com/store/apps/details?id=$packageName',
        'tracks': ['internal', 'alpha', 'beta', 'production'],
      },
      'ios': {'branch': 'production', 'workflows': {'store': 'ios-store'}, 'bundle_id': 'com.doubley.nextbrain', 'app_store_app_id': '', 'store_url': ''},
      'web': {'branch': 'production', 'workflows': {'website': 'web-website'}},
      'linux': {'branch': 'production', 'workflows': {'website': 'linux-website'}},
      'windows': {'branch': 'production', 'workflows': {'website': 'windows-website'}},
      'macos': {'branch': 'production', 'workflows': <String, String>{}},
    },
    'secrets': {
      'CODEMAGIC_API_TOKEN': {'set': codemagic},
      'APP_RELEASE_UPLOAD_SECRET': {'set': true},
    },
  };
}

/// A Codemagic release (the D-143 [releaseJson] plus channel / executor / build id / config).
Map<String, dynamic> codemagicReleaseJson({
  int id = 21,
  String platform = 'android',
  String channel = 'website',
  String status = 'building',
  bool isLive = false,
  double? progress,
  List<Map<String, dynamic>> artifacts = const [],
  List<Map<String, dynamic>> log = const [],
  Map<String, dynamic> config = const {},
}) =>
    {
      ...releaseJson(
        id: id,
        platform: platform,
        status: status,
        isLive: isLive,
        progress: progress,
        artifacts: artifacts,
        log: log,
        source: channel == 'store' ? (platform == 'android' ? 'google_play' : 'app_store') : 'website',
        storeUrl: channel == 'store' ? 'https://play.google.com/store/apps/details?id=com.doubley.nextbrain' : null,
      ),
      'channel': channel,
      'executor': 'codemagic',
      'actions': {
        ...(releaseJson(status: status, isLive: isLive)['actions'] as Map<String, dynamic>),
        'rollback': isLive && channel != 'store',
        'retry': const {'failed', 'canceled'}.contains(status),
      },
      'buildable': true,
      'codemagic_build_id': '6727c1f0a9b8c7d6e5f4a3b2',
      'codemagic_url': 'https://codemagic.io/app/6544a1c2e8b4f0b7d1a9c3e2/build/6727c1f0a9b8c7d6e5f4a3b2',
      'config': {'workflow': channel == 'store' ? 'android-store' : 'android-website', ...config},
      'upload_done': status == 'ready' || status == 'live',
    };

/// The website channel's files of an Android release (names as codemagic.yaml writes them).
const codemagicApkArtifacts = [
  {'name': 'NextBrain-1.4.1-53-arm64-v8a.apk', 'size': 48700000, 'sha256': '9b1c0d3e5f7a9b1c0d3e5f7a9b1c0d3e5f7a9b1c0d3e5f7a9b1c0d3e5f7a9b1c', 'kind': 'apk', 'abi': 'arm64-v8a'},
  {'name': 'NextBrain-1.4.1-53-armeabi-v7a.apk', 'size': 44100000, 'sha256': 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2', 'kind': 'apk', 'abi': 'armeabi-v7a'},
  {'name': 'NextBrain-1.4.1-53-universal.apk', 'size': 96300000, 'sha256': 'f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1', 'kind': 'apk', 'abi': 'universal'},
];

/// `GET /api/v1/app/downloads` (services/app_release_codemagic.py downloads()).
List<Map<String, dynamic>> downloadsJson({String androidVersion = '1.4.1', int androidBuild = 53}) {
  const base = 'https://nextbrain.site/api/api/v1/app/downloads';
  Map<String, dynamic> file(String platform, String name, int size, String kind, {String? abi, bool primary = false}) => {
        'name': name,
        'size': size,
        'sha256': 'f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1d2c3b4a5f0e1',
        'kind': kind,
        'url': '$base/$platform/$name',
        'primary': primary,
        'abi': ?abi,
      };
  return [
    {
      'platform': 'android',
      'version': androidVersion,
      'build_number': androidBuild,
      'notes_ar': 'تشغيل أسرع للدروس وإصلاح تنبيهات الحضور.',
      'notes_en': 'Faster lessons and fixed attendance alerts.',
      'policy': 'recommended',
      'released_at': '2026-11-02T11:28:02',
      'files': [
        file('android', 'NextBrain-$androidVersion-$androidBuild-arm64-v8a.apk', 48700000, 'apk', abi: 'arm64-v8a'),
        file('android', 'NextBrain-$androidVersion-$androidBuild-armeabi-v7a.apk', 44100000, 'apk', abi: 'armeabi-v7a'),
        file('android', 'NextBrain-$androidVersion-$androidBuild-universal.apk', 96300000, 'apk', abi: 'universal', primary: true),
      ],
    },
    {
      'platform': 'windows',
      'version': '1.4.1',
      'build_number': 53,
      'notes_ar': '',
      'notes_en': '',
      'policy': 'optional',
      'files': [file('windows', 'NextBrain-1.4.1-53-windows-x64.zip', 61200000, 'zip', primary: true)],
    },
    {
      'platform': 'linux',
      'version': '1.4.0',
      'build_number': 52,
      'notes_ar': '',
      'notes_en': '',
      'policy': 'optional',
      'files': [
        file('linux', 'NextBrain-1.4.0-52-x64.deb', 38800000, 'deb', primary: true),
        file('linux', 'NextBrain-1.4.0-52-x64.tar.gz', 40100000, 'tar'),
      ],
    },
  ];
}
