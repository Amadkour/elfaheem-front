// lib/features/admin/app_releases/app_releases_models.dart
//
// The plain classes of "App versions" (D-143, docs/release/APP_RELEASES.md): a release, its log lines and artifacts,
// the build server's status, and the draft the New version form sends. The readers are lenient on purpose (an id or a
// number may come as a string, the author as a name or a {id, name} object, the log as strings or {n, text} rows), so
// a small change of shape on the server never blanks the page.
library;

int? _int(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
bool _bool(Object? v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = '${v ?? ''}'.toLowerCase();
  if (s == 'true' || s == '1' || s == 'yes') return true;
  if (s == 'false' || s == '0' || s == 'no') return false;
  return fallback;
}

/// The server stores naive UTC (`2026-11-02T13:05:29.703829`): read it as UTC.
DateTime? releaseTime(Object? v) {
  final s = _str(v);
  if (s == null) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// The platforms in the order the page lists them.
const List<String> kReleasePlatformOrder = ['android', 'ios', 'web', 'linux', 'windows', 'macos'];

/// Built on the build server (the others are recorded only: iOS is the web app, Windows / macOS are not buildable on
/// Linux).
bool releasePlatformBuildable(String platform) => const {'android', 'web', 'linux'}.contains(platform);

/// Every status, in flow order (APP_RELEASES.md "Statuses").
const List<String> kReleaseStatuses = [
  'queued',
  'building',
  'testing',
  'uploading',
  'ready',
  'live',
  'failed',
  'canceled',
  'rolled_back',
];

/// The status of a live release that a newer one replaced (status `live`, `current: false`).
const String kReleaseReplaced = 'replaced';

/// A build still moving on the build server.
bool releaseStatusActive(String s) => const {'queued', 'building', 'testing', 'uploading'}.contains(s);

/// x.y.z — the version the form accepts.
final RegExp kReleaseVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');

/// The branch names the server accepts (it also checks the branch exists on origin).
final RegExp kReleaseBranchPattern = RegExp(r'^[A-Za-z0-9._/-]{1,100}$');

/// Compares x.y.z versions numerically (missing parts are 0; anything after + or - is ignored).
int compareReleaseVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[+-]')).first.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// The next patch version: 1.4.2 → 1.4.3 (anything unreadable → 1.0.0).
String nextPatchVersion(String? v) {
  if (v == null || !kReleaseVersionPattern.hasMatch(v.split(RegExp(r'[+-]')).first)) return '1.0.0';
  final p = v.split(RegExp(r'[+-]')).first.split('.').map(int.parse).toList();
  return '${p[0]}.${p[1]}.${p[2] + 1}';
}

class ReleaseLogLine {
  const ReleaseLogLine(this.n, this.text, {this.at});

  /// The line number (1-based, from the server; the reader numbers plain strings after the last one it knows).
  final int n;
  final String text;
  final DateTime? at;

  static List<ReleaseLogLine> listFrom(Object? raw, {int after = 0}) {
    final rows = raw is Map ? (raw['lines'] ?? raw['log'] ?? raw['items']) : raw;
    if (rows is! List) return const [];
    final out = <ReleaseLogLine>[];
    var n = after;
    for (final r in rows) {
      if (r is Map) {
        final m = Map<String, dynamic>.from(r);
        n = _int(m['n'] ?? m['line_no'] ?? m['no'] ?? m['seq']) ?? n + 1;
        out.add(ReleaseLogLine(n, '${m['text'] ?? m['line'] ?? m['message'] ?? ''}', at: releaseTime(m['at'] ?? m['ts'])));
      } else if (r != null) {
        n += 1;
        out.add(ReleaseLogLine(n, '$r'));
      }
    }
    return out;
  }
}

class ReleaseArtifact {
  const ReleaseArtifact({required this.name, this.size, this.sha256, this.kind, this.url});

  /// The file name, also the download path segment (`GET …/{id}/artifacts/{name}`).
  final String name;
  final int? size;
  final String? sha256;

  /// `apk`, `aab`, `web`, `deb`, `tar.gz`, …
  final String? kind;

  /// A public link when the file is already published (website releases).
  final String? url;

  factory ReleaseArtifact.fromJson(Map<String, dynamic> j) {
    final name = _str(j['name']) ?? _str(j['file']) ?? '';
    var kind = _str(j['kind']);
    if (kind == null && name.contains('.')) kind = name.endsWith('.tar.gz') ? 'tar.gz' : name.split('.').last;
    return ReleaseArtifact(name: name, size: _int(j['size'] ?? j['bytes']), sha256: _str(j['sha256']), kind: kind, url: _str(j['url']));
  }
}

/// What the buttons may do now — the server's `actions {cancel, retry, publish, rollback}` on every release.
class ReleaseActions {
  const ReleaseActions({this.cancel = false, this.retry = false, this.publish = false, this.rollback = false});

  final bool cancel, retry, publish, rollback;

  static ReleaseActions? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return ReleaseActions(
      cancel: _bool(raw['cancel']),
      retry: _bool(raw['retry']),
      publish: _bool(raw['publish']),
      rollback: _bool(raw['rollback']),
    );
  }
}

class AppRelease {
  const AppRelease({
    required this.id,
    required this.platform,
    required this.version,
    this.buildNumber,
    this.status = 'queued',
    this.policy = 'optional',
    this.minSupported,
    this.branch,
    this.commit,
    this.gate = 'test_first',
    this.source = 'website',
    this.storeUrl,
    this.autoPublish = true,
    this.notesAr = '',
    this.notesEn = '',
    this.progress,
    this.step,
    this.error,
    this.createdBy,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.liveAt,
    this.current = false,
    this.attempt,
    this.actions,
    this.downloadUrl,
    this.logCount,
    this.artifacts = const [],
    this.log = const [],
  });

  final int id;
  final String platform;
  final String version;
  final int? buildNumber;

  /// queued | building | testing | uploading | ready | live | failed | canceled | rolled_back. A release that was live
  /// and was replaced keeps `live` with [current] false.
  final String status;

  /// optional | recommended | must
  final String policy;
  final String? minSupported;
  final String? branch;
  final String? commit;

  /// test_first | direct
  final String gate;

  /// website | google_play | app_store | custom
  final String source;
  final String? storeUrl;
  final bool autoPublish;
  final String notesAr, notesEn;

  /// 0 – 100, null before the build server reports any.
  final double? progress;

  /// A step text, when a server sends one (the page shows the last log line otherwise).
  final String? step;

  /// The failure (a code such as `branch_not_found`, or the build agent's words).
  final String? error;

  /// The author's name, or `#<user id>` when the server sends the id only.
  final String? createdBy;
  final DateTime? createdAt, startedAt, finishedAt, liveAt;

  /// The release its platform serves now (one per platform).
  final bool current;

  /// The build attempt (retry adds one).
  final int? attempt;

  /// The server's own word on the buttons; null from a reply without it (they are derived from the status then).
  final ReleaseActions? actions;

  /// Where the app's update button sends people for this release.
  final String? downloadUrl;
  final int? logCount;
  final List<ReleaseArtifact> artifacts;
  final List<ReleaseLogLine> log;

  bool get active => releaseStatusActive(status);

  /// Live now — the one its platform serves.
  bool get isLive => current;

  /// The status to draw: a replaced live release reads "Replaced".
  String get shownStatus => status == 'live' && !current ? 'replaced' : status;

  bool get canCancel => actions?.cancel ?? const {'queued', 'building', 'testing'}.contains(status);
  bool get canRetry => actions?.retry ?? (const {'failed', 'canceled'}.contains(status) && releasePlatformBuildable(platform));
  bool get canPublish => actions?.publish ?? status == 'ready';
  bool get canRollback => actions?.rollback ?? current;

  /// "1.4.0 (52)"
  String get label => buildNumber == null ? version : '$version ($buildNumber)';

  String? get shortCommit => commit == null ? null : (commit!.length > 10 ? commit!.substring(0, 10) : commit);

  factory AppRelease.fromJson(Map<String, dynamic> j) {
    final by = j['created_by'];
    final p = j['progress'];
    final double? progress = p is num ? p.toDouble() : double.tryParse('${p ?? ''}');
    final status = _str(j['status']) ?? 'queued';
    final String? author = by is Map
        ? (_str(by['name']) ?? _str(by['username']) ?? _str(by['email']))
        : (_str(j['created_by_name']) ?? (by is num ? '#${by.toInt()}' : _str(by)));
    return AppRelease(
      id: _int(j['id']) ?? 0,
      platform: _str(j['platform']) ?? 'android',
      version: _str(j['version']) ?? '',
      buildNumber: _int(j['build_number'] ?? j['build']),
      status: status,
      policy: _str(j['policy']) ?? 'optional',
      minSupported: _str(j['min_supported'] ?? j['min_supported_version']),
      branch: _str(j['branch']),
      commit: _str(j['commit_sha'] ?? j['commit']),
      gate: _str(j['gate']) ?? 'test_first',
      source: _str(j['source']) ?? 'website',
      storeUrl: _str(j['store_url']),
      autoPublish: _bool(j['auto_publish'], fallback: true),
      notesAr: _str(j['notes_ar']) ?? _str(_map(j['notes'])['ar']) ?? '',
      notesEn: _str(j['notes_en']) ?? _str(_map(j['notes'])['en']) ?? '',
      progress: progress?.clamp(0, 100).toDouble(),
      step: _str(j['step'] ?? j['current_step']),
      error: _str(j['error']),
      createdBy: author,
      createdAt: releaseTime(j['created_at']),
      startedAt: releaseTime(j['started_at']),
      finishedAt: releaseTime(j['finished_at']),
      liveAt: releaseTime(j['live_at'] ?? j['published_at']),
      current: _bool(j['current'] ?? j['is_live']),
      attempt: _int(j['attempt']),
      actions: ReleaseActions.fromJson(j['actions']),
      downloadUrl: _str(j['download_url']),
      logCount: _int(j['log_count']),
      artifacts: [
        for (final a in (j['artifacts'] is List ? j['artifacts'] as List : const []))
          if (a is Map) ReleaseArtifact.fromJson(Map<String, dynamic>.from(a)),
      ],
      log: ReleaseLogLine.listFrom(j['log'] ?? j['log_lines']),
    );
  }

  AppRelease _copy({
    String? status,
    double? progress,
    String? step,
    String? error,
    String? commit,
    bool? current,
    ReleaseActions? actions,
    bool dropActions = false,
    List<ReleaseLogLine>? log,
  }) =>
      AppRelease(
        id: id,
        platform: platform,
        version: version,
        buildNumber: buildNumber,
        status: status ?? this.status,
        policy: policy,
        minSupported: minSupported,
        branch: branch,
        commit: commit ?? this.commit,
        gate: gate,
        source: source,
        storeUrl: storeUrl,
        autoPublish: autoPublish,
        notesAr: notesAr,
        notesEn: notesEn,
        progress: progress ?? this.progress,
        step: step ?? this.step,
        error: error ?? this.error,
        createdBy: createdBy,
        createdAt: createdAt,
        startedAt: startedAt,
        finishedAt: finishedAt,
        liveAt: liveAt,
        current: current ?? this.current,
        attempt: attempt,
        actions: dropActions ? null : (actions ?? this.actions),
        downloadUrl: downloadUrl,
        logCount: logCount,
        artifacts: artifacts,
        log: log ?? this.log,
      );

  /// This release with the fields of an `app_release_updated` event applied (`{id, platform, status, progress,
  /// current}`). A new status drops the server's [actions] until the release is fetched again (the status decides).
  AppRelease withEvent(Map<String, dynamic> e) {
    final p = e['progress'];
    final pr = p is num ? p.toDouble() : double.tryParse('${p ?? ''}');
    final st = _str(e['status']) ?? status;
    return _copy(
      status: st,
      progress: pr?.clamp(0, 100).toDouble(),
      step: _str(e['step']),
      error: _str(e['error']),
      commit: _str(e['commit_sha'] ?? e['commit']),
      current: e.containsKey('current') ? _bool(e['current']) : null,
      dropActions: st != status,
    );
  }

  /// [log] followed by [more], each line number once (the newest [keep] kept).
  AppRelease withLog(List<ReleaseLogLine> more, {int keep = 500}) {
    if (more.isEmpty) return this;
    final last = log.isEmpty ? 0 : log.last.n;
    final merged = [...log, for (final l in more) if (l.n > last) l];
    return _copy(log: merged.length > keep ? merged.sublist(merged.length - keep) : merged);
  }
}

class ReleasePage {
  const ReleasePage(this.items, {this.total = 0, this.live = const {}, this.nextBuild = const {}});

  final List<AppRelease> items;
  final int total;

  /// The version each platform serves now (`live {platform: version|null}`).
  final Map<String, String?> live;

  /// The form's default build number per platform (`next_build_number {platform: n}`).
  final Map<String, int> nextBuild;

  bool get hasMore => total > items.length;

  factory ReleasePage.fromJson(Object? raw) {
    final rows = raw is Map ? (raw['items'] ?? raw['releases'] ?? raw['data']) : raw;
    final items = [
      for (final r in (rows is List ? rows : const [])) if (r is Map) AppRelease.fromJson(Map<String, dynamic>.from(r)),
    ];
    final m = _map(raw);
    return ReleasePage(
      items,
      total: _int(m['total']) ?? items.length,
      live: {for (final e in _map(m['live']).entries) e.key: _str(e.value)},
      nextBuild: {for (final e in _map(m['next_build_number']).entries) if (_int(e.value) != null) e.key: _int(e.value)!},
    );
  }
}

class BuilderStatus {
  const BuilderStatus({
    this.online = false,
    this.lastSeen,
    this.version,
    this.busyRelease,
    this.busyPlatform,
    this.busyVersion,
    this.busyProgress,
    this.configured = true,
    this.tokenSet = true,
    this.tokenRotatedAt,
  });

  /// Seen in the last 120 s.
  final bool online;
  final DateTime? lastSeen;

  /// The build agent's own version.
  final String? version;

  /// The release it builds now (`busy_job.id`), null when idle.
  final int? busyRelease;
  final String? busyPlatform, busyVersion;
  final double? busyProgress;

  /// false: the server has no releases folder yet (web / android / linux answer 503 `releases_not_configured`).
  final bool configured;

  /// false: no build server token was ever created.
  final bool tokenSet;
  final DateTime? tokenRotatedAt;

  bool get busy => busyRelease != null || busyVersion != null;

  factory BuilderStatus.fromJson(Object? raw) {
    final j = _map(raw);
    final b = j['busy_job'];
    final m = b is Map ? Map<String, dynamic>.from(b) : const <String, dynamic>{};
    final p = m['progress'];
    return BuilderStatus(
      online: _bool(j['online']),
      lastSeen: releaseTime(j['last_seen']),
      version: _str(j['version']),
      busyRelease: b is Map ? _int(m['id'] ?? m['release_id']) : _int(b),
      busyPlatform: _str(m['platform']),
      busyVersion: _str(m['version']),
      busyProgress: p is num ? p.toDouble() : null,
      configured: _bool(j['configured'], fallback: true),
      tokenSet: _bool(j['token_set'], fallback: true),
      tokenRotatedAt: releaseTime(j['token_rotated_at']),
    );
  }
}

/// What the New version form sends (POST /api/v1/admin/app-releases, without the password).
class AppReleaseDraft {
  const AppReleaseDraft({
    required this.platform,
    required this.version,
    this.buildNumber,
    this.notesAr = '',
    this.notesEn = '',
    this.policy = 'optional',
    this.minSupported,
    this.branch = 'production',
    this.gate = 'test_first',
    this.source = 'website',
    this.storeUrl,
    this.autoPublish = true,
  });

  final String platform;
  final String version;
  final int? buildNumber;
  final String notesAr, notesEn;
  final String policy;
  final String? minSupported;
  final String branch;
  final String gate;
  final String source;
  final String? storeUrl;
  final bool autoPublish;

  /// The URL field is shown: a store / custom source, and every Windows / macOS record (their file lives elsewhere).
  static bool needsUrl(String platform, String source) =>
      source != 'website' || platform == 'windows' || platform == 'macos';

  /// The URL must be given (the server answers 422 `store_url_required` otherwise).
  static bool requiresUrl(String source) => source != 'website';

  Map<String, dynamic> toJson({required String password}) => {
        'platform': platform,
        'version': version,
        'build_number': ?buildNumber,
        'notes_ar': notesAr,
        'notes_en': notesEn,
        'policy': policy,
        if (minSupported != null && minSupported!.isNotEmpty) 'min_supported': minSupported,
        if (releasePlatformBuildable(platform)) 'branch': branch,
        'gate': releasePlatformBuildable(platform) ? gate : 'direct',
        'source': source,
        if (needsUrl(platform, source) && storeUrl != null && storeUrl!.isNotEmpty) 'store_url': storeUrl,
        'auto_publish': autoPublish,
        'password': password,
      };
}

/// The form's checks before anything is sent: field → error text key (see app_releases_text.dart `releaseFieldError`).
Map<String, String> validateReleaseDraft(AppReleaseDraft d) {
  final e = <String, String>{};
  if (!kReleaseVersionPattern.hasMatch(d.version)) e['version'] = 'version_format';
  if (d.buildNumber != null && d.buildNumber! < 1) e['build_number'] = 'build_number';
  final min = d.minSupported;
  if (min != null && min.isNotEmpty) {
    if (!kReleaseVersionPattern.hasMatch(min)) {
      e['min_supported'] = 'version_format';
    } else if (kReleaseVersionPattern.hasMatch(d.version) && compareReleaseVersions(min, d.version) > 0) {
      e['min_supported'] = 'min_above_version';
    }
  }
  if (releasePlatformBuildable(d.platform) && !kReleaseBranchPattern.hasMatch(d.branch)) e['branch'] = 'branch_invalid';
  final url = d.storeUrl ?? '';
  if (AppReleaseDraft.requiresUrl(d.source) || (AppReleaseDraft.needsUrl(d.platform, d.source) && url.isNotEmpty)) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) e['store_url'] = 'url_https';
  }
  return e;
}
