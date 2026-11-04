// lib/core/models_hub/models_hub_api.dart
//
// The model hub's super admin API (D-152, ../back modelhub/routers/admin.py, docs/omr/MODELHUB_API.md) and the
// plain classes its replies are read into. One service behind nginx at `/api/v1/models/…`; super admins only (403
// `super_admin_required` for anyone else). Errors are `{"detail": {code, message (ar), message_en, …extra}}`:
// [HubFailure.from] reads them, with the extra fields (`checks`, the re-index estimate of
// `reindex_choice_required`, …).
//
//   GET    /api/v1/models                         roles → active / previous / fallback / pending / limits / models
//   GET    /api/v1/models/system                  cpu_count, ram, disk, loaded, queue, providers
//   GET    /api/v1/models/downloads?limit=        newest first
//   POST   /api/v1/models/downloads/{id}/{pause|resume|cancel}
//   GET    /api/v1/models/audit?role=&limit=      the change log
//   GET    /api/v1/models/alerts?state=
//   POST   /api/v1/models                         add {source: registry | hf | ollama | url, role, …}
//   POST   /api/v1/models/{id}/download | test | activate {confirm?, reindex?}
//   DELETE /api/v1/models/{id}
//   POST   /api/v1/models/roles/{role}/rollback | cancel
//   PUT    /api/v1/models/roles/{role}/fallback {model_id | null} · limits {threads?, ram_mb?, …}
//   POST   /api/v1/models/roles/embedding/reindex
//
// The parsers are checked against replies recorded from the hub's own e2e run (test/fixtures/payloads/models_hub/).
library;

import '../../config/app_config.dart';
import '../api_client.dart';

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
int? _intOrNull(Object? v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double? _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String? _str(Object? v) => v == null ? null : '$v';
Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

/// The hub stores naive UTC (`2026-11-02T03:05:29.703829`): read it as UTC.
DateTime? hubTime(Object? v) {
  final s = _str(v);
  if (s == null || s.isEmpty) return null;
  final zoned = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// The roles in the order the server lists them (mlkit/providers.ROLES).
const kHubRoles = [
  'embedding', 'generation', 'generation.chat', 'generation.exam', 'grading', 'reranker', 'nli', 'ocr_det', 'ocr_rec_ar', 'ocr_rec_en', 'handwriting_en', 'digits',
  'vision_language',
];

/// A role's resource limits (`limits`).
class HubLimits {
  const HubLimits({this.threads = 1, this.maxConcurrency = 1, this.priority = 'interactive', this.idleUnloadS = 0, this.ramMb = 0});

  factory HubLimits.fromJson(Map<String, dynamic> j) => HubLimits(
        threads: _int(j['threads']),
        maxConcurrency: _int(j['max_concurrency']),
        priority: _str(j['priority']) ?? 'interactive',
        idleUnloadS: _int(j['idle_unload_s']),
        ramMb: _int(j['ram_mb']),
      );

  final int threads, maxConcurrency, idleUnloadS, ramMb;
  final String priority;

  Map<String, dynamic> toJson() =>
      {'threads': threads, 'max_concurrency': maxConcurrency, 'priority': priority, 'idle_unload_s': idleUnloadS, 'ram_mb': ramMb};
}

/// One check of a health test or of the pre-activation checks: `{name, ok, …}` (the rest varies by check).
class HubCheck {
  const HubCheck(this.name, this.ok, this.raw);

  factory HubCheck.fromJson(Map<String, dynamic> j) => HubCheck(_str(j['name']) ?? '', j['ok'] != false, j);

  final String name;
  final bool ok;
  final Map<String, dynamic> raw;

  String? get reason => _str(raw['reason']);
}

/// A model's last health test (`last_test`, also `pending.test`).
class HubTest {
  const HubTest({required this.ok, this.at, this.checks = const [], this.speed, this.loadMs, this.rssMb, this.dim, this.stage, this.error});

  static HubTest? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return HubTest(
      ok: j['ok'] == true,
      at: hubTime(j['at']),
      checks: [for (final c in _maps(j['checks'])) HubCheck.fromJson(c)],
      speed: _dbl(j['speed']),
      loadMs: _intOrNull(j['load_ms']),
      rssMb: _intOrNull(j['rss_mb']),
      dim: _intOrNull(j['dim']),
      stage: _str(j['stage']),
      error: _str(j['error']),
    );
  }

  final bool ok;
  final DateTime? at;
  final List<HubCheck> checks;

  /// Answers (or passages) per second the test measured.
  final double? speed;
  final int? loadMs, rssMb, dim;

  /// Where a failed test stopped: answer | speed | load | timeout | crash.
  final String? stage;
  final String? error;
}

/// The embedding switch's estimate (`pending.reindex`, and the extra fields of 409 `reindex_choice_required`).
///
/// `missing_chunks` / `missing_qa` are what the new model's vectors still lack in the RAG index (a model the index used
/// before kept its vectors), [items] their sum; `vectors_ready` = every vector is already built, so the switch is a
/// plain one (B6 round 2). An older hub without them: everything counts as missing.
class HubReindex {
  const HubReindex({
    this.known = true,
    this.current,
    this.required = false,
    this.chunks = 0,
    this.qa = 0,
    int? missingChunks,
    int? missingQa,
    this.vectorsReady = false,
    this.ratePerS,
    this.estimatedSeconds,
    this.estimate,
    this.done,
    this.total,
    this.progressStatus,
    this.error,
  })  : missingChunks = missingChunks ?? chunks,
        missingQa = missingQa ?? qa;

  static HubReindex? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final p = _map(j['progress']);
    return HubReindex(
      known: j['known'] != false,
      current: _str(j['current']),
      required: j['reindex_required'] == true,
      chunks: _int(j['chunks']),
      qa: _int(j['qa']),
      missingChunks: _intOrNull(j['missing_chunks']),
      missingQa: _intOrNull(j['missing_qa']),
      vectorsReady: j['vectors_ready'] == true,
      ratePerS: _dbl(j['rate_per_s']),
      estimatedSeconds: _intOrNull(j['estimated_seconds']),
      estimate: HubEstimate.fromJson(j['estimate']),
      done: _intOrNull(p['done']),
      total: _intOrNull(p['total']),
      progressStatus: _str(p['status']),
      error: _str(j['error']),
    );
  }

  final bool known;
  final String? current;
  final bool required;
  final int chunks, qa;

  /// What a rebuild still has to embed.
  final int missingChunks, missingQa;
  int get items => missingChunks + missingQa;

  /// Documents are indexed and every vector of the new model is already there: activating switches at once.
  final bool vectorsReady;

  /// The health test's speed (short sentences — not a rebuild speed; never shown as a time).
  final double? ratePerS;

  /// Set only when this model's own rebuild was measured on this server.
  final int? estimatedSeconds;
  final HubEstimate? estimate;
  final int? done, total;
  final String? progressStatus;
  final String? error;
}

/// How long a rebuild takes, from MEASURED rebuilds only (`pending.reindex.estimate`): basis `this_model` gives
/// [seconds]; `other_models` a range [lowSeconds]..[highSeconds] (other embedders measured here, [models]); `none` no
/// number; `nothing_to_build` 0.
class HubEstimate {
  const HubEstimate({
    required this.basis,
    this.seconds,
    this.lowSeconds,
    this.highSeconds,
    this.models = const [],
    this.measuredItems,
    this.measuredSeconds,
  });

  static HubEstimate? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final m = _map(j['measured']);
    final models = j['models'];
    return HubEstimate(
      basis: _str(j['basis']) ?? 'none',
      seconds: _intOrNull(j['seconds']),
      lowSeconds: _intOrNull(j['low_seconds']),
      highSeconds: _intOrNull(j['high_seconds']),
      models: models is List ? [for (final x in models) '$x'] : const [],
      measuredItems: _intOrNull(m['items']),
      measuredSeconds: _dbl(m['seconds']),
    );
  }

  final String basis;
  final int? seconds, lowSeconds, highSeconds;
  final List<String> models;

  /// This model's last measured rebuild (basis `this_model`).
  final int? measuredItems;
  final double? measuredSeconds;
}

/// An activation in progress (`pending`): downloading → testing → ready_to_confirm | failed; embedding only:
/// reindex_later, reindexing, reindex_failed.
class HubPending {
  const HubPending({
    required this.modelId,
    required this.ref,
    required this.stage,
    this.at,
    this.checks = const [],
    this.test,
    this.downloadId,
    this.reindex,
    this.reason,
  });

  static HubPending? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return HubPending(
      modelId: _int(j['model_id']),
      ref: _str(j['ref']) ?? '',
      stage: _str(j['stage']) ?? '',
      at: hubTime(j['at']),
      checks: [for (final c in _maps(j['checks'])) HubCheck.fromJson(c)],
      test: HubTest.fromJson(j['test']),
      downloadId: _intOrNull(j['download_id']),
      reindex: HubReindex.fromJson(j['reindex']),
      reason: _str(j['reason']),
    );
  }

  final int modelId;
  final String ref;
  final String stage;
  final DateTime? at;
  final List<HubCheck> checks;
  final HubTest? test;
  final int? downloadId;
  final HubReindex? reindex;

  /// checks_failed | health_test_failed | health_test_crashed (stage `failed`).
  final String? reason;

  bool get readyToConfirm => stage == 'ready_to_confirm';
  bool get failed => stage == 'failed' || stage == 'reindex_failed';

  /// The identity of this step (a prompt is shown once per step; a new activation request clears it).
  String get stepKey => '$modelId:$stage';
}

/// A model's measured quality for one role (`accuracy[role]`): `{metric, score 0..1, n, dataset, details, at}`.
class HubAccuracy {
  const HubAccuracy({this.metric = '', this.score, this.n = 0, this.dataset = '', this.at});

  static HubAccuracy? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return HubAccuracy(metric: _str(j['metric']) ?? '', score: _dbl(j['score']), n: _int(j['n']), dataset: _str(j['dataset']) ?? '', at: hubTime(j['at']));
  }

  final String metric, dataset;

  /// 0..1; null = not measured.
  final double? score;
  final int n;
  final DateTime? at;

  /// The score as a whole percent (null when not measured).
  int? get percent => score == null ? null : (score! * 100).round().clamp(0, 100);
}

/// A model's speed on this server (`speed`): `{value, unit: "tok/s", ttft_ms, load_ms, rss_mb, at, ok}`.
class HubSpeed {
  const HubSpeed({this.value, this.unit = 'tok/s', this.ttftMs, this.loadMs, this.rssMb, this.at, this.ok = true});

  static HubSpeed? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return HubSpeed(
      value: _dbl(j['value']),
      unit: _str(j['unit']) ?? 'tok/s',
      ttftMs: _intOrNull(j['ttft_ms']),
      loadMs: _intOrNull(j['load_ms']),
      rssMb: _intOrNull(j['rss_mb']),
      at: hubTime(j['at']),
      ok: j['ok'] != false,
    );
  }

  final double? value;
  final String unit;
  final int? ttftMs, loadMs, rssMb;
  final DateTime? at;
  final bool ok;

  bool get measured => ok && value != null;
}

/// One library row (`ModelRow`).
class HubModel {
  const HubModel({
    required this.id,
    required this.role,
    required this.name,
    required this.version,
    required this.ref,
    required this.provider,
    required this.source,
    required this.status,
    this.repo,
    this.revision,
    this.license,
    this.sizeBytes = 0,
    this.diskBytes = 0,
    this.ramMb = 0,
    this.error,
    this.lastTest,
    this.usedAs = const [],
    this.pinned = false,
    this.quantization,
    this.dim,
    this.addedBy,
    this.addedAt,
    this.deletable = false,
    this.roles = const [],
    this.usedIn = const {},
    this.accuracy = const {},
    this.speed,
    this.context,
    this.paramsB,
    this.recommendedFor = const [],
  });

  factory HubModel.fromJson(Map<String, dynamic> j) => HubModel(
        id: _int(j['id']),
        role: _str(j['role']) ?? '',
        name: _str(j['name']) ?? '',
        version: _str(j['version']) ?? '',
        ref: _str(j['ref']) ?? '',
        provider: _str(j['provider']) ?? '',
        source: _str(j['source']) ?? '',
        status: _str(j['status']) ?? 'not_downloaded',
        repo: _str(j['repo']),
        revision: _str(j['revision']),
        license: _str(j['license']),
        sizeBytes: _int(j['size_bytes']),
        diskBytes: _int(j['disk_bytes']),
        ramMb: _int(j['ram_mb']),
        error: _str(j['error']),
        lastTest: HubTest.fromJson(j['last_test']),
        usedAs: [for (final u in (j['used_as'] is List ? j['used_as'] as List : const [])) '$u'],
        pinned: j['pinned'] == true,
        quantization: _str(j['quantization']),
        dim: _intOrNull(j['dim']),
        addedBy: _intOrNull(j['added_by']),
        addedAt: hubTime(j['added_at']),
        deletable: j['deletable'] == true,
        roles: [for (final r in (j['roles'] is List ? j['roles'] as List : const [])) '$r'],
        usedIn: {
          for (final e in _map(j['used_in']).entries) e.key: [for (final u in (e.value is List ? e.value as List : const [])) '$u'],
        },
        accuracy: {
          for (final e in _map(j['accuracy']).entries)
            if (HubAccuracy.fromJson(e.value) != null) e.key: HubAccuracy.fromJson(e.value)!,
        },
        speed: HubSpeed.fromJson(j['speed']),
        context: _intOrNull(j['context']),
        paramsB: _dbl(j['params_b']),
        recommendedFor: [for (final r in (j['recommended_for'] is List ? j['recommended_for'] as List : const [])) '$r'],
      );

  final int id;
  final String role, name, version, ref, provider, source;

  /// not_downloaded | downloading | paused | ready | active | failed.
  final String status;
  final String? repo, revision, license;
  final int sizeBytes, diskBytes;

  /// The estimate until a health test measured it.
  final int ramMb;
  final String? error;
  final HubTest? lastTest;

  /// active | previous | fallback | pending.
  final List<String> usedAs;

  /// The exam grader's calibrated embedder / NLI model (never deletable).
  final bool pinned;
  final String? quantization;
  final int? dim;
  final int? addedBy;
  final DateTime? addedAt;
  final bool deletable;

  /// The roles this model can serve (empty on an older server: only [role]).
  final List<String> roles;

  /// role -> how it is used there (`active`, `previous`, `fallback`, `pending`).
  final Map<String, List<String>> usedIn;

  /// role -> its measured quality there.
  final Map<String, HubAccuracy> accuracy;
  final HubSpeed? speed;
  final int? context;
  final double? paramsB;
  final List<String> recommendedFor;

  bool get isActive => status == 'active';
  bool get isFallback => usedAs.contains('fallback');
  bool get isPrevious => usedAs.contains('previous');
  bool get onDisk => diskBytes > 0 || status == 'ready' || status == 'active';
}

/// One role with its models (`roles[]`).
class HubRole {
  const HubRole({
    required this.role,
    required this.models,
    this.active,
    this.activeId,
    this.previous,
    this.previousId,
    this.fallback,
    this.fallbackId,
    this.pending,
    this.limits = const HubLimits(),
    this.task,
    this.recommended,
  });

  factory HubRole.fromJson(Map<String, dynamic> j) => HubRole(
        role: _str(j['role']) ?? '',
        task: _str(j['task']),
        recommended: _str(j['recommended']),
        active: _str(j['active']),
        activeId: _intOrNull(j['active_id']),
        previous: _str(j['previous']),
        previousId: _intOrNull(j['previous_id']),
        fallback: _str(j['fallback']),
        fallbackId: _intOrNull(j['fallback_id']),
        pending: HubPending.fromJson(j['pending']),
        limits: HubLimits.fromJson(_map(j['limits'])),
        models: [for (final m in _maps(j['models'])) HubModel.fromJson(m)],
      );

  final String role;
  final String? active, previous, fallback;
  final int? activeId, previousId, fallbackId;
  final HubPending? pending;
  final HubLimits limits;
  final List<HubModel> models;

  /// `chat` | `exam` | `grading` for the per-task generation roles (null on every other role and on an older server).
  final String? task;

  /// The ref the server recommends for this role (`ollama:qwen3:4b`).
  final String? recommended;

  bool get isTask => task != null;

  /// Is [m] the model this role serves now? A model shared by several roles has one global `status`, so a task role
  /// reads its own `active_id`.
  bool isActiveHere(HubModel m) => isTask ? activeId == m.id : m.isActive;

  bool isRecommended(HubModel m) => recommended != null && (m.ref == recommended || recommended == '${m.provider}:${m.ref}');

  /// [m]'s status as this role shows it (a task model active for another task is just downloaded here).
  String statusOf(HubModel m) => isTask && m.status == 'active' && !isActiveHere(m) ? 'ready' : m.status;

  HubModel? byId(int? id) {
    if (id == null) return null;
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  HubModel? get activeModel => byId(activeId);
  HubModel? get previousModel => byId(previousId);
  HubModel? get pendingModel => byId(pending?.modelId);
}

/// `GET /api/v1/models`.
class HubOverview {
  const HubOverview(this.roles);

  factory HubOverview.fromJson(Object? v) => HubOverview([for (final r in _maps(_map(v)['roles'])) HubRole.fromJson(r)]);

  final List<HubRole> roles;

  HubRole? role(String role) {
    for (final r in roles) {
      if (r.role == role) return r;
    }
    return null;
  }

  HubModel? model(int? id) {
    if (id == null) return null;
    for (final r in roles) {
      final m = r.byId(id);
      if (m != null) return m;
    }
    return null;
  }
}

/// One download (`GET /downloads`, the `model_download` live event, the download / pause / resume / cancel replies).
class HubDownload {
  const HubDownload({
    required this.id,
    required this.modelId,
    required this.status,
    this.ref,
    this.role,
    this.bytesDone = 0,
    this.bytesTotal = 0,
    this.percent,
    this.speedBps = 0,
    this.etaS,
    this.error,
    this.activateAfter = false,
    this.createdAt,
    this.finishedAt,
  });

  static HubDownload? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final id = _intOrNull(j['id']);
    if (id == null) return null;
    return HubDownload(
      id: id,
      modelId: _int(j['model_id']),
      status: _str(j['status']) ?? '',
      ref: _str(j['ref']),
      role: _str(j['role']),
      bytesDone: _int(j['bytes_done']),
      bytesTotal: _int(j['bytes_total']),
      percent: _dbl(j['percent']),
      speedBps: _dbl(j['speed_bps']) ?? 0,
      etaS: _intOrNull(j['eta_s']),
      error: _str(j['error']),
      activateAfter: j['activate_after'] == true,
      createdAt: hubTime(j['created_at']),
      finishedAt: hubTime(j['finished_at']),
    );
  }

  final int id, modelId;

  /// queued | running | paused | cancelled | done | failed.
  final String status;
  final String? ref, role;
  final int bytesDone, bytesTotal;
  final double? percent;
  final double speedBps;
  final int? etaS;
  final String? error;

  /// Started by an activation: the health test follows it.
  final bool activateAfter;
  final DateTime? createdAt, finishedAt;

  /// Queued, running or paused: the floating bar shows it.
  bool get live => status == 'queued' || status == 'running' || status == 'paused';
  bool get running => status == 'running' || status == 'queued';
  bool get paused => status == 'paused';

  /// 0..1 (null while the size is unknown).
  double? get fraction {
    final p = percent;
    if (p != null) return (p / 100).clamp(0.0, 1.0);
    if (bytesTotal > 0) return (bytesDone / bytesTotal).clamp(0.0, 1.0);
    return null;
  }
}

/// One audit row (`GET /audit`): actor null = the hub itself.
class HubAudit {
  const HubAudit({required this.id, required this.action, this.actor, this.role, this.modelId, this.old, this.next, this.detail, this.at});

  factory HubAudit.fromJson(Map<String, dynamic> j) => HubAudit(
        id: _int(j['id']),
        action: _str(j['action']) ?? '',
        actor: _intOrNull(j['actor']),
        role: _str(j['role']),
        modelId: _intOrNull(j['model_id']),
        old: j['old'] is Map ? Map<String, dynamic>.from(j['old'] as Map) : null,
        next: j['new'] is Map ? Map<String, dynamic>.from(j['new'] as Map) : null,
        detail: _str(j['detail']),
        at: hubTime(j['at']),
      );

  final int id;
  final String action;
  final int? actor;
  final String? role;
  final int? modelId;
  final Map<String, dynamic>? old, next;
  final String? detail;
  final DateTime? at;
}

/// One alert (`GET /alerts`): `model_fallback.<role>`, `health_failed.<role>`, `download_failed.<model id>`.
class HubAlert {
  const HubAlert({required this.id, required this.key, this.role, this.detail = const {}, this.openedAt});

  factory HubAlert.fromJson(Map<String, dynamic> j) => HubAlert(
        id: _int(j['id']),
        key: _str(j['key']) ?? '',
        role: _str(j['role']),
        detail: _map(j['detail']),
        openedAt: hubTime(j['opened_at']),
      );

  final int id;
  final String key;
  final String? role;
  final Map<String, dynamic> detail;
  final DateTime? openedAt;

  String get kind => key.split('.').first;
}

/// `GET /api/v1/models/system` (the parts the page shows).
class HubSystem {
  const HubSystem({this.cpuCount, this.diskFreeMb, this.diskTotalMb, this.ramAvailableMb, this.ramTotalMb, this.providers = const {}});

  factory HubSystem.fromJson(Object? v) {
    final j = _map(v);
    final disk = _map(j['disk']);
    final ram = _map(j['ram']);
    return HubSystem(
      cpuCount: _intOrNull(j['cpu_count']),
      diskFreeMb: _intOrNull(disk['free_mb']),
      diskTotalMb: _intOrNull(disk['total_mb']),
      ramAvailableMb: _intOrNull(ram['available_mb']),
      ramTotalMb: _intOrNull(ram['total_mb']),
      providers: {for (final e in _map(j['providers']).entries) e.key: '${e.value}'},
    );
  }

  final int? cpuCount, diskFreeMb, diskTotalMb, ramAvailableMb, ramTotalMb;

  /// provider → "available" or why it is off.
  final Map<String, String> providers;
}

/// The reply of `POST /{id}/activate` (both steps) and of rollback / re-index.
class HubStep {
  const HubStep({this.stage, this.pending, this.downloadId, this.active, this.reindex, this.rolledBackFrom});

  factory HubStep.fromJson(Object? v) {
    final j = _map(v);
    return HubStep(
      stage: _str(j['stage']),
      pending: HubPending.fromJson(j['pending']),
      downloadId: _intOrNull(j['download_id']),
      active: _str(j['active']),
      reindex: j.containsKey('reindex_required') ? HubReindex.fromJson(j) : null,
      rolledBackFrom: _intOrNull(j['rolled_back_from']),
    );
  }

  /// downloading | testing | ready_to_confirm | failed | active | reindex_later | reindexing.
  final String? stage;
  final HubPending? pending;
  final int? downloadId;
  final String? active;
  final HubReindex? reindex;
  final int? rolledBackFrom;
}

/// A hub error: `{"detail": {code, message (ar), message_en, …extra}}`.
class HubFailure {
  const HubFailure({required this.status, this.code, required this.messageAr, required this.messageEn, this.extra = const {}});

  factory HubFailure.from(Object error) {
    final e = ApiException.from(error);
    final body = ApiException.asMap(e.body);
    final d = body != null && body['detail'] is Map ? Map<String, dynamic>.from(body['detail'] as Map) : <String, dynamic>{};
    final ar = _str(d['message']);
    final en = _str(d['message_en']);
    return HubFailure(
      status: e.statusCode,
      code: _str(d['code']) ?? e.code,
      messageAr: ar ?? en ?? e.message,
      messageEn: en ?? ar ?? e.message,
      extra: {for (final x in d.entries) if (!const {'code', 'message', 'message_en'}.contains(x.key)) x.key: x.value},
    );
  }

  final int status;
  final String? code;
  final String messageAr, messageEn;
  final Map<String, dynamic> extra;

  /// The server's own text in the app's language.
  String get message => AppConfig.lang == 'ar' ? messageAr : messageEn;

  List<HubCheck> get checks => [for (final c in _maps(extra['checks'])) HubCheck.fromJson(c)];
  HubReindex? get reindex => code == 'reindex_choice_required' ? HubReindex.fromJson(extra) : null;

  @override
  String toString() => 'HubFailure($status $code: $messageEn)';
}

/// The calls. Every method throws what [ApiClient] throws (read it with [HubFailure.from]).
class ModelsHubApi {
  const ModelsHubApi();

  static const base = '/api/v1/models';

  ApiClient get _api => ApiClient.instance;

  Future<HubOverview> overview() async => HubOverview.fromJson(await _api.get('/api/v1/models'));

  Future<HubSystem> system() async => HubSystem.fromJson(await _api.get('$base/system'));

  Future<List<HubDownload>> downloads({int limit = 50}) async {
    final r = await _api.get('$base/downloads', queryParams: {'limit': limit});
    return [for (final d in _maps(_map(r)['downloads'])) ?HubDownload.fromJson(d)];
  }

  Future<HubDownload?> downloadAction(int downloadId, String action) async =>
      HubDownload.fromJson(await _api.post('$base/downloads/$downloadId/$action'));

  Future<List<HubAudit>> audit({String? role, int limit = 100}) async {
    final r = await _api.get('$base/audit', queryParams: {'limit': limit, 'role': ?role});
    return [for (final a in _maps(_map(r)['audit'])) HubAudit.fromJson(a)];
  }

  Future<List<HubAlert>> alerts({String state = 'open'}) async {
    final r = await _api.get('$base/alerts', queryParams: {'state': state});
    return [for (final a in _maps(_map(r)['alerts'])) HubAlert.fromJson(a)];
  }

  Future<HubModel> add(Map<String, dynamic> body) async => HubModel.fromJson(_map(await _api.post('/api/v1/models', body: body)));

  Future<HubDownload?> download(int modelId) async => HubDownload.fromJson(await _api.post('$base/$modelId/download'));

  Future<void> test(int modelId) async => _api.post('$base/$modelId/test');

  Future<HubStep> activate(int modelId, {bool confirm = false, String? reindex, String? role}) async => HubStep.fromJson(
      await _api.post('$base/$modelId/activate', body: {if (confirm) 'confirm': true, 'reindex': ?reindex, 'role': ?role}));

  /// "Use the recommended models": activates the server's recommendation of every task.
  Future<Map<String, dynamic>> applyDefaults() async => _map(await _api.post('$base/defaults/apply'));

  Future<Map<String, dynamic>> delete(int modelId) async => _map(await _api.delete('$base/$modelId'));

  Future<HubStep> rollback(String role) async => HubStep.fromJson(await _api.post('$base/roles/$role/rollback'));

  Future<void> cancelPending(String role) async => _api.post('$base/roles/$role/cancel');

  Future<void> setFallback(String role, int? modelId) async =>
      _api.put('$base/roles/$role/fallback', body: {'model_id': modelId});

  Future<HubLimits> setLimits(String role, Map<String, dynamic> body) async =>
      HubLimits.fromJson(_map(_map(await _api.put('$base/roles/$role/limits', body: body))['limits']));

  Future<HubStep> reindexEmbedding() async => HubStep.fromJson(await _api.post('$base/roles/embedding/reindex'));
}
