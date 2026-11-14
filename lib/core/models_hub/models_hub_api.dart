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
//   PUT    /api/v1/models/roles/nli/judge {on}           the open-answer grader's NLI judge (D-675)
//   GET    /api/v1/models/benchmarks?role=               results per role, the choice, the default (D-683..D-685)
//   POST   /api/v1/models/benchmarks/run {roles?, model_ids?} · GET …/benchmarks/runs/{id}
//   PUT    /api/v1/models/benchmarks/roles/{role}/choice {model_id | null, confirm?, reindex?}
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
  'embedding', 'generation', 'reranker', 'nli', 'ocr_det', 'ocr_rec_ar', 'ocr_rec_en', 'handwriting_en', 'digits',
  'vision_language', 'exam_grading',
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
    this.mode,
    this.sharedFrom,
    this.sharedActive,
    this.effective,
    this.judge,
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
        // additive (D-252, the exam_grading row only): an older server sends none of these
        mode: _str(j['mode']),
        sharedFrom: _str(j['shared_from']),
        sharedActive: _str(j['shared_active']),
        effective: _str(j['effective']),
        // additive (D-675, the nli row only): "on" | "off"; null on an older hub and on every other role
        judge: _str(j['judge']),
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

  /// How the role gets its model (`shared` = follows the [sharedFrom] role's active model, `own` = its own, `off`); null
  /// for a role without the choice and for an older server.
  final String? mode, sharedFrom;

  /// The ref of [sharedFrom]'s active model, and the ref the role actually runs on now (null = none).
  final String? sharedActive, effective;

  /// The NLI judge of the open-answer grader (contract A7): "on" | "off"; null when the hub does not say.
  final String? judge;

  /// The judge is asked unless the hub says it is off.
  bool get judgeOn => judge != 'off';

  bool get hasMode => mode != null;

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

/// One task of the models list: the roles it uses.
class HubTask {
  const HubTask(this.task, this.roles);
  final String task;
  final List<String> roles;
}

/// `GET /api/v1/models`.
class HubOverview {
  const HubOverview(this.roles, {this.tasks = const []});

  factory HubOverview.fromJson(Object? v) => HubOverview(
        [for (final r in _maps(_map(v)['roles'])) HubRole.fromJson(r)],
        // additive: an older server sends no `tasks`
        tasks: [
          for (final t in _maps(_map(v)['tasks']))
            HubTask(_str(t['task']) ?? '', [for (final r in (t['roles'] is List ? t['roles'] as List : const [])) '$r']),
        ],
      );

  final List<HubRole> roles;

  /// The roles grouped by task (`tasks`: `{task: "exam_grading", roles: ["exam_grading", "nli", "embedding"]}`).
  final List<HubTask> tasks;

  HubTask? task(String task) {
    for (final t in tasks) {
      if (t.task == task) return t;
    }
    return null;
  }

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

// ── benchmarks per role and the Super Admin's choice (contract C, D-683..D-685; front D-689) ────────────────────

/// Why a benchmark row cannot be chosen (`reason: {code, en, ar}`).
class HubBenchReason {
  const HubBenchReason(this.code, this.en, this.ar);

  /// A map {code, en, ar} (results), or plain text (a runner that is not available says why in one sentence).
  static HubBenchReason? fromJson(Object? v) {
    if (v is String && v.trim().isNotEmpty) return HubBenchReason('', v.trim(), v.trim());
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    final code = _str(j['code']) ?? '';
    return HubBenchReason(code, _str(j['en']) ?? code, _str(j['ar']) ?? _str(j['en']) ?? code);
  }

  final String code, en, ar;
  String get text => AppConfig.lang == 'ar' ? ar : en;
}

/// One model's latest result for a role (`roles[].results[]`).
class HubBenchResult {
  const HubBenchResult({
    required this.id,
    this.modelId,
    this.ref = '',
    this.name = '',
    this.role = '',
    this.metric = '',
    this.accuracy,
    this.latencyAvgMs,
    this.latencyP95Ms,
    this.peakRamMb,
    this.sizeBytes = 0,
    this.dataset = '',
    this.n = 0,
    this.provisional = false,
    this.detail = const {},
    this.source = 'run',
    this.at,
    this.by,
    this.license,
    this.downloaded = false,
    this.isDefault = false,
    this.isChoice = false,
    this.isActive = false,
    this.selectable = true,
    this.reason,
  });

  factory HubBenchResult.fromJson(Map<String, dynamic> j) => HubBenchResult(
        id: _int(j['id']),
        modelId: _intOrNull(j['model_id']),
        ref: _str(j['ref']) ?? '',
        name: _str(j['name']) ?? _str(j['ref']) ?? '',
        role: _str(j['role']) ?? '',
        metric: _str(j['metric']) ?? '',
        accuracy: _dbl(j['accuracy']),
        latencyAvgMs: _dbl(j['latency_avg_ms']),
        latencyP95Ms: _dbl(j['latency_p95_ms']),
        peakRamMb: _intOrNull(j['peak_ram_mb']),
        sizeBytes: _int(j['size_bytes']),
        dataset: _str(j['dataset']) ?? '',
        n: _int(j['n']),
        provisional: j['provisional'] == true,
        detail: _map(j['detail']),
        source: _str(j['source']) ?? 'run',
        at: hubTime(j['at']),
        by: _intOrNull(j['by']),
        license: _str(j['license']),
        downloaded: j['downloaded'] == true,
        isDefault: j['is_default'] == true,
        isChoice: j['is_choice'] == true,
        isActive: j['is_active'] == true,
        selectable: j['selectable'] != false,
        reason: HubBenchReason.fromJson(j['reason']),
      );

  final int id;
  final int? modelId;
  final String ref, name, role, metric, dataset, source;

  /// On the metric's own scale (percent, or Spearman × 100); null = not measured.
  final double? accuracy, latencyAvgMs, latencyP95Ms;
  final int? peakRamMb, by;
  final int sizeBytes, n;
  final bool provisional, downloaded, isDefault, isChoice, isActive, selectable;
  final Map<String, dynamic> detail;
  final DateTime? at;
  final String? license;
  final HubBenchReason? reason;

  /// Seeded from the shipped results file, not measured on this server.
  bool get seeded => source == 'seed';
}

/// One benchmarked role (`roles[]`).
class HubBenchRole {
  const HubBenchRole({
    required this.role,
    this.metric = '',
    this.metricEn = '',
    this.metricAr = '',
    this.higherIsBetter = true,
    this.dataset = '',
    this.provisional = false,
    this.activeId,
    this.active,
    this.choiceId,
    this.choiceAt,
    this.defaultId,
    this.defaultRule,
    this.effectiveId,
    this.results = const [],
  });

  factory HubBenchRole.fromJson(Map<String, dynamic> j) {
    final label = _map(j['metric_label']);
    final choice = j['choice'] is Map ? _map(j['choice']) : null;
    final def = j['default'] is Map ? _map(j['default']) : null;
    return HubBenchRole(
      role: _str(j['role']) ?? '',
      metric: _str(j['metric']) ?? '',
      metricEn: _str(label['en']) ?? _str(j['metric']) ?? '',
      metricAr: _str(label['ar']) ?? _str(label['en']) ?? _str(j['metric']) ?? '',
      higherIsBetter: j['higher_is_better'] != false,
      dataset: _str(j['dataset']) ?? '',
      provisional: j['provisional'] == true,
      activeId: _intOrNull(j['active_id']),
      active: _str(j['active']),
      choiceId: choice == null ? null : _intOrNull(choice['model_id']),
      choiceAt: choice == null ? null : hubTime(choice['at']),
      defaultId: def == null ? null : _intOrNull(def['model_id']),
      defaultRule: def == null ? null : _str(def['rule']),
      effectiveId: _intOrNull(j['effective_id']),
      results: [for (final r in _maps(j['results'])) HubBenchResult.fromJson(r)],
    );
  }

  final String role, metric, metricEn, metricAr, dataset;
  final bool higherIsBetter, provisional;
  final int? activeId, choiceId, defaultId, effectiveId;
  final String? active, defaultRule;
  final DateTime? choiceAt;
  final List<HubBenchResult> results;

  String get metricLabel => AppConfig.lang == 'ar' ? metricAr : metricEn;

  /// The Super Admin picked a model by hand (else the role follows the recommendation).
  bool get hasChoice => choiceId != null;

  /// The rows of the headline dataset (the ones the recommendation is drawn from).
  List<HubBenchResult> get headline => [for (final r in results) if (dataset.isEmpty || r.dataset == dataset) r];

  /// Extra runners of the same role (e.g. character boxes), listed after the headline rows.
  List<HubBenchResult> get extra => [for (final r in results) if (dataset.isNotEmpty && r.dataset != dataset) r];
}

/// A runner the hub has for a role (`runners[]`).
class HubBenchRunner {
  const HubBenchRunner(this.role, this.dataset, this.available, this.reason);
  final String role, dataset;
  final bool available;
  final HubBenchReason? reason;
}

/// A benchmark run (C3): queued → running → done | failed.
class HubBenchRun {
  const HubBenchRun({
    required this.id,
    required this.status,
    this.roles = const [],
    this.modelIds = const [],
    this.done = 0,
    this.total = 0,
    this.current,
    this.errors = const [],
    this.createdAt,
    this.finishedAt,
  });

  static HubBenchRun? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    if (j['id'] == null) return null;
    return HubBenchRun(
      id: _int(j['id']),
      status: _str(j['status']) ?? 'queued',
      roles: [for (final r in (j['roles'] is List ? j['roles'] as List : const [])) '$r'],
      modelIds: [for (final m in (j['model_ids'] is List ? j['model_ids'] as List : const [])) _int(m)],
      done: _int(j['done']),
      total: _int(j['total']),
      current: _str(j['current']),
      errors: _maps(j['errors']),
      createdAt: hubTime(j['created_at']),
      finishedAt: hubTime(j['finished_at']),
    );
  }

  final int id, done, total;
  final String status;
  final List<String> roles;
  final List<int> modelIds;
  final String? current;
  final List<Map<String, dynamic>> errors;
  final DateTime? createdAt, finishedAt;

  bool get live => status == 'queued' || status == 'running';

  /// 0 … 1 (null before the hub knows the total).
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

/// `GET /api/v1/models/benchmarks`.
class HubBenchmarks {
  const HubBenchmarks({this.roles = const [], this.runners = const [], this.run});

  factory HubBenchmarks.fromJson(Object? v) {
    final j = _map(v);
    return HubBenchmarks(
      roles: [for (final r in _maps(j['roles'])) HubBenchRole.fromJson(r)],
      runners: [
        for (final r in _maps(j['runners']))
          HubBenchRunner(_str(r['role']) ?? '', _str(r['dataset']) ?? '', r['available'] == true, HubBenchReason.fromJson(r['reason'])),
      ],
      run: HubBenchRun.fromJson(j['run']),
    );
  }

  final List<HubBenchRole> roles;
  final List<HubBenchRunner> runners;

  /// The latest run (null: never run).
  final HubBenchRun? run;

  HubBenchRole? role(String role) {
    for (final r in roles) {
      if (r.role == role) return r;
    }
    return null;
  }
}

/// The reply of `PUT /benchmarks/roles/{role}/choice` (C4): the choice and the activation step it started.
class HubBenchChoice {
  const HubBenchChoice({required this.role, this.choiceId, this.effectiveId, this.activation = const HubStep()});

  factory HubBenchChoice.fromJson(Object? v) {
    final j = _map(v);
    final choice = j['choice'] is Map ? _map(j['choice']) : null;
    return HubBenchChoice(
      role: _str(j['role']) ?? '',
      choiceId: choice == null ? null : _intOrNull(choice['model_id']),
      effectiveId: _intOrNull(j['effective_id']),
      activation: HubStep.fromJson(j['activation']),
    );
  }

  final String role;
  final int? choiceId, effectiveId;
  final HubStep activation;
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

  /// D-252: Exam grading follows the generation model (`shared`), uses its own (`own`) or is `off`.
  Future<void> setGradingMode(String mode) async => _api.put('$base/roles/exam_grading/mode', body: {'mode': mode});

  Future<HubStep> reindexEmbedding() async => HubStep.fromJson(await _api.post('$base/roles/embedding/reindex'));

  // ── benchmarks (contract C) and the NLI judge (contract A7) ──

  Future<HubBenchmarks> benchmarks({String? role}) async => HubBenchmarks.fromJson(await _api.get('$base/benchmarks', queryParams: {'role': ?role}));

  /// 202 with the run; 409 `benchmark_running` while one is queued or running, 422 `nothing_to_run`.
  Future<HubBenchRun?> runBenchmarks({List<String>? roles, List<int>? modelIds}) async =>
      HubBenchRun.fromJson(await _api.post('$base/benchmarks/run', body: {'roles': ?roles, 'model_ids': ?modelIds}));

  Future<HubBenchRun?> benchmarkRun(int id) async => HubBenchRun.fromJson(await _api.get('$base/benchmarks/runs/$id'));

  /// [modelId] null = follow the recommendation again. Starts the page's activation of the chosen model (C4).
  Future<HubBenchChoice> chooseModel(String role, int? modelId, {bool confirm = false, String? reindex}) async => HubBenchChoice.fromJson(
      await _api.put('$base/benchmarks/roles/$role/choice', body: {'model_id': modelId, 'confirm': confirm, 'reindex': ?reindex}));

  /// The NLI judge of the open-answer grader on / off (A7) → the hub's new state ("on" | "off").
  Future<String> setJudge(bool on) async => _str(_map(await _api.put('$base/roles/nli/judge', body: {'on': on}))['judge']) ?? (on ? 'on' : 'off');
}
