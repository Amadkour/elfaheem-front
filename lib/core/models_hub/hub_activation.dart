// lib/core/models_hub/hub_activation.dart
//
// The activation of a model for a task, as a small state machine over the hub's replies (FRONT_CONTRACTS "Models"):
//
//   POST /models/{id}/activate {"role": "generation.exam"}
//     202 {stage: "downloading", download_id, pending}  -> the model downloads, then the hub switches by itself
//     200 {stage: "testing" | "ready_to_confirm" | "active" | ...}
//     409 checks_failed  checks: [{name: "ram_all_roles", ok: false, need_mb, budget_mb, margin_mb, items: [{ref, roles, ram_mb}]}]
//     422 role_mismatch  (the model cannot serve that role)
//
// [hubActivate] makes the call and returns one [ActivationOutcome]; [hubActivationState] reads the overview + the live
// downloads and says where a requested activation is now (downloading with its progress -> active). No widget here:
// ai_models_page.dart drives the UI from these, test/org/ai_models_activation_test.dart pumps them over FakeApi.
library;

import 'models_hub_api.dart';

/// What an activation request came back with.
sealed class ActivationOutcome {
  const ActivationOutcome();
}

/// The model serves the role now.
class ActivationActive extends ActivationOutcome {
  const ActivationActive(this.step);
  final HubStep step;
}

/// Downloading first (HTTP 202); the hub activates by itself once the files are there and the checks pass.
class ActivationDownloading extends ActivationOutcome {
  const ActivationDownloading(this.step);
  final HubStep step;
  int? get downloadId => step.downloadId ?? step.pending?.downloadId;
}

/// In the health test, or waiting for the person's confirmation / the index choice (the embedding flow).
class ActivationInProgress extends ActivationOutcome {
  const ActivationInProgress(this.step);
  final HubStep step;
}

/// The hub stopped it (failed health test, ...): the old model keeps serving.
class ActivationFailed extends ActivationOutcome {
  const ActivationFailed(this.step);
  final HubStep step;
}

/// 409 `checks_failed` (or another refused pre-check): [checks] holds what did not pass, the RAM one first.
class ActivationBlocked extends ActivationOutcome {
  const ActivationBlocked(this.failure);
  final HubFailure failure;

  List<HubCheck> get checks => failure.checks;

  /// The RAM check of the roles together, when it is the one that failed.
  HubRamCheck? get ram {
    for (final c in checks) {
      if (c.name == 'ram_all_roles' && !c.ok) return HubRamCheck.fromCheck(c);
    }
    return null;
  }
}

/// 422 `role_mismatch`: the model does not fit the role asked for.
class ActivationRoleMismatch extends ActivationOutcome {
  const ActivationRoleMismatch(this.failure);
  final HubFailure failure;
}

/// Anything else (403, 409 reindex_choice_required, 404, a network error ...): the page decides from [failure].
class ActivationError extends ActivationOutcome {
  const ActivationError(this.failure);
  final HubFailure failure;
}

/// One model of the RAM budget table (`items[]` of the `ram_all_roles` check).
class HubRamItem {
  const HubRamItem({required this.ref, this.roles = const [], this.ramMb = 0});

  final String ref;
  final List<String> roles;
  final int ramMb;
}

/// The `ram_all_roles` check: every active model of every role must fit the budget together.
class HubRamCheck {
  const HubRamCheck({this.needMb = 0, this.budgetMb = 0, this.marginMb = 0, this.items = const [], this.reason});

  factory HubRamCheck.fromCheck(HubCheck c) {
    final j = c.raw;
    int n(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return HubRamCheck(
      needMb: n(j['need_mb']),
      budgetMb: n(j['budget_mb']),
      marginMb: n(j['margin_mb']),
      reason: j['reason'] == null ? null : '${j['reason']}',
      items: [
        for (final i in (j['items'] is List ? j['items'] as List : const []))
          if (i is Map)
            HubRamItem(
              ref: '${i['ref'] ?? ''}',
              roles: [for (final r in (i['roles'] is List ? i['roles'] as List : const [])) '$r'],
              ramMb: n(i['ram_mb']),
            ),
      ],
    );
  }

  final int needMb, budgetMb, marginMb;
  final List<HubRamItem> items;
  final String? reason;

  /// How much the models together exceed the budget (never negative).
  int get overMb => (needMb - budgetMb).clamp(0, 1 << 30);
}

/// Asks the hub to activate [modelId] for [role] and sorts the answer. Never throws.
Future<ActivationOutcome> hubActivate(ModelsHubApi api, int modelId, {String? role, bool confirm = false, String? reindex}) async {
  try {
    final step = await api.activate(modelId, role: role, confirm: confirm, reindex: reindex);
    return switch (step.stage) {
      'active' => ActivationActive(step),
      'downloading' => ActivationDownloading(step),
      'failed' => ActivationFailed(step),
      _ when step.pending?.stage == 'failed' => ActivationFailed(step),
      _ => ActivationInProgress(step),
    };
  } catch (e) {
    final f = HubFailure.from(e);
    if (f.code == 'role_mismatch' || (f.status == 422 && f.code == null)) return ActivationRoleMismatch(f);
    if (f.code == 'checks_failed' || f.code == 'embedding_dim_unsupported' || f.code == 'provider_unavailable') return ActivationBlocked(f);
    return ActivationError(f);
  }
}

enum ActivationPhase { idle, downloading, testing, awaitingConfirm, active, failed }

/// Where an activation of [modelId] for [role] stands, read from the overview and the live downloads.
class ActivationState {
  const ActivationState(this.phase, {this.fraction, this.speedBps, this.etaS, this.paused = false});

  final ActivationPhase phase;

  /// 0..1 while downloading (null = unknown).
  final double? fraction;
  final double? speedBps;
  final int? etaS;
  final bool paused;

  bool get busy => phase == ActivationPhase.downloading || phase == ActivationPhase.testing;
}

/// The state of an activation: active once the role serves the model; downloading while a live download of it
/// exists; testing / awaiting-confirm / failed from the role's `pending`.
ActivationState hubActivationState(HubOverview ov, Map<int, HubDownload> downloads, int modelId, String role) {
  final r = ov.role(role);
  if (r != null && r.activeId == modelId) return const ActivationState(ActivationPhase.active);
  final d = downloads[modelId];
  if (d != null && d.live) {
    return ActivationState(ActivationPhase.downloading, fraction: d.fraction, speedBps: d.speedBps, etaS: d.etaS, paused: d.paused);
  }
  final p = r?.pending;
  if (p != null && p.modelId == modelId) {
    if (p.failed) return const ActivationState(ActivationPhase.failed);
    if (p.readyToConfirm) return const ActivationState(ActivationPhase.awaitingConfirm);
    if (p.stage == 'downloading') return const ActivationState(ActivationPhase.downloading);
    return const ActivationState(ActivationPhase.testing);
  }
  return const ActivationState(ActivationPhase.idle);
}
