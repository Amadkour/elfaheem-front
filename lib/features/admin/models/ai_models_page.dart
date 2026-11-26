// lib/features/admin/models/ai_models_page.dart
//
// The super admin's "AI Models" page (D-152, requirements 7.4 – 7.11): the model hub's library by role, downloads with
// progress, activation (checks → health test → confirm, with the embedding index warning of example 9), rollback,
// fallback, resource limits, add / delete, and the change log. Kill switch `models.admin` (services hub tile).
//
// Data: GET /api/v1/models (+ /alerts, /system once) on open and pull-to-refresh, again on `model_changed` /
// `model_alert` through EventOrPoll (3 s while an activation or a download runs and the stream is down, 20 s
// otherwise; 4-6 × that while the stream is up); live download progress from ModelDownloads.instance (the same rows
// the floating bar shows). History: GET /api/v1/models/audit, loaded when its tab opens. The drawing is
// ai_models_view.dart (plain values), the sheets ai_models_sheets.dart.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/live/event_wait.dart';
import '../../../core/models_hub/hub_activation.dart';
import '../../../core/models_hub/model_downloads.dart';
import '../../../core/models_hub/models_hub_api.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_notice.dart';
import '../../../design/app_tokens.dart';
import '../../../config/app_config.dart';
import '../../../utils/live_events.dart';
import '../../../utils/widget/base_page.dart';
import '../../auth/auth_provider.dart';
import '../admin_common.dart' show t;
import 'ai_models_bench.dart';
import 'ai_models_sheets.dart';
import 'ai_models_view.dart';
import 'models_hub_text.dart';
import '../sup/sup_kit.dart';

/// The model's name with its variant when another model of the role shares the name (models_hub_text.hubModelLabel).
String _modelName(HubModel? m, String fallback, [HubRole? r]) => hubModelLabel(m, role: r, ref: fallback);

/// The role's active model as the page names it (null when none is active).
String? _activeName(HubRole? r) => r?.active == null ? null : hubModelLabel(r!.activeModel, role: r, ref: r.active);

/// The signed-in user's id (null without the auth provider, e.g. a widget test of the page alone).
int? _me(BuildContext context) {
  try {
    return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
  } on ProviderNotFoundException {
    return null;
  }
}

class AiModelsPage extends StatefulWidget {
  const AiModelsPage({super.key, this.api = const ModelsHubApi(), this.downloads, this.stream});

  static const routeName = '/ai_models';

  final ModelsHubApi api;

  /// Defaults to [ModelDownloads.instance].
  final ModelDownloads? downloads;

  /// The live stream handle for the page's EventOrPoll (tests; the app's by default).
  final LiveStreamHandle? stream;

  @override
  State<AiModelsPage> createState() => AiModelsPageState();
}

class AiModelsPageState extends State<AiModelsPage> {
  HubOverview? _ov;
  HubSystem? _sys;
  bool _sysTried = false; // GET /system once per visit (an older hub without it is not asked again)
  List<HubAlert> _alerts = const [];
  List<HubAudit>? _audit;
  String? _error;
  int _tab = 0;
  String? _historyRole;
  final _busy = <int>{};
  final _prompted = <String>{};

  /// Models this person asked to activate in this visit: their "ready to confirm" opens the prompt by itself.
  final _requested = <int>{};

  /// Task activations in flight (model id -> role): the hub downloads, tests and switches by itself (202), so the page
  /// watches the overview until the role serves the model, then says so once.
  final _awaiting = <int, String>{};
  EventOrPoll? _poller;
  bool _fast = false;
  StreamSubscription<HubDownload>? _ended;
  bool _prompting = false;

  // Benchmarks tab (contract C, D-689): loaded when it opens; a live run is followed through EventOrPoll on the
  // hub's `model_benchmark` event (the timer only while the stream is down).
  HubBenchmarks? _bench;
  String? _benchError;
  final _benchBusy = <String>{};
  bool _benchStarting = false;
  bool _judgeBusy = false;
  EventOrPoll? _benchWatch;

  ModelsHubApi get _api => widget.api;
  ModelDownloads get _dl => widget.downloads ?? ModelDownloads.instance;

  @override
  void initState() {
    super.initState();
    _dl.addListener(_onDownloads);
    _dl.watch();
    _ended = _dl.ended.listen((_) => _load(silent: true));
    _restartPoller(fast: false);
    _load();
  }

  @override
  void dispose() {
    _dl.removeListener(_onDownloads);
    _ended?.cancel();
    _poller?.dispose();
    _benchWatch?.dispose();
    super.dispose();
  }

  void _onDownloads() {
    if (mounted) setState(() {});
  }

  void _restartPoller({required bool fast}) {
    _poller?.dispose();
    _fast = fast;
    _poller = EventOrPoll(
      poll: () => _load(silent: true),
      every: fast ? const Duration(seconds: 3) : const Duration(seconds: 20),
      fallbackEvery: fast ? const Duration(seconds: 15) : const Duration(minutes: 2),
      names: const {LiveEvents.modelChanged, LiveEvents.modelAlert},
      stream: widget.stream,
    )..start();
  }

  bool get _moving {
    final ov = _ov;
    if (_dl.live.isNotEmpty) return true;
    return ov != null && ov.roles.any((r) => const {'downloading', 'testing', 'reindexing'}.contains(r.pending?.stage));
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _error = null);
    try {
      final f = await Future.wait<Object?>([
        _api.overview(),
        _api.alerts().then<Object?>((a) => a, onError: (_) => _alerts),
        if (_sys == null && !_sysTried) _api.system().then<Object?>((s) => s, onError: (_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _ov = f[0] as HubOverview;
        _alerts = f[1] as List<HubAlert>;
        if (f.length > 2 && f[2] is HubSystem) _sys = f[2] as HubSystem;
        _sysTried = true;
        _error = null;
      });
      if (_tab == 1) unawaited(_loadAudit());
      if (_tab == 2) unawaited(_loadBench());
      if (_moving != _fast) _restartPoller(fast: _moving);
      _maybePrompt();
      _checkAwaiting();
    } catch (e) {
      if (!mounted) return;
      if (!silent || _ov == null) setState(() => _error = HubFailure.from(e).message);
    }
  }

  Future<void> _loadAudit() async {
    try {
      final a = await _api.audit(role: _historyRole, limit: 100);
      if (mounted) setState(() => _audit = a);
    } catch (e) {
      if (mounted) showAppNotice(HubFailure.from(e).message, error: true);
    }
  }

  bool get _benchOn => !AppConfig.disableList.contains(kModelsBenchFeatureKey);

  Future<void> _loadBench() async {
    try {
      final b = await _api.benchmarks();
      if (!mounted) return;
      setState(() {
        _bench = b;
        _benchError = null;
      });
      _followRun(b.run);
    } catch (e) {
      if (mounted) setState(() => _benchError = HubFailure.from(e).message);
    }
  }

  /// Follows a live run until it ends (then the results are read again); nothing to follow otherwise.
  void _followRun(HubBenchRun? run) {
    if (run == null || !run.live) {
      _benchWatch?.dispose();
      _benchWatch = null;
      return;
    }
    if (_benchWatch != null) return;
    _benchWatch = EventOrPoll(
      poll: () => _pollRun(run.id),
      every: const Duration(seconds: 4),
      fallbackEvery: const Duration(seconds: 30),
      names: const {LiveEvents.modelBenchmark},
      stream: widget.stream,
    )..start();
  }

  Future<void> _pollRun(int id) async {
    try {
      final r = await _api.benchmarkRun(id);
      if (!mounted || r == null) return;
      final b = _bench;
      setState(() => _bench = HubBenchmarks(roles: b?.roles ?? const [], runners: b?.runners ?? const [], run: r));
      if (!r.live) {
        _benchWatch?.dispose();
        _benchWatch = null;
        await _loadBench();
      }
    } catch (_) {
      // the next event or poll tries again
    }
  }

  Future<void> _runBench() async {
    final ok = await appConfirm(context,
        confirmLabel: t('ابدأ القياس', 'Start'),
        message: t('قياس كل نموذج منزّل لكل دور على هذا الخادم؟ يعمل في الخلفية ولا يغيّر أي نموذج مُفعّل.',
            'Benchmark every downloaded model of every role on this server? It runs in the background and changes no active model.'));
    if (!ok || !mounted) return;
    setState(() => _benchStarting = true);
    try {
      final run = await _api.runBenchmarks();
      if (!mounted) return;
      final b = _bench;
      setState(() => _bench = HubBenchmarks(roles: b?.roles ?? const [], runners: b?.runners ?? const [], run: run));
      _followRun(run);
    } catch (e) {
      final f = HubFailure.from(e);
      showAppNotice(f.message, error: true);
      if (f.code == 'benchmark_running') unawaited(_loadBench());
    } finally {
      if (mounted) setState(() => _benchStarting = false);
    }
  }

  String _benchName(HubBenchResult x) =>
      x.modelId == null ? hubRefLabel(x.name.isEmpty ? x.ref : x.name) : _modelName(_ov?.model(x.modelId), x.name.isEmpty ? x.ref : x.name);

  /// "Use this model" (C4): confirm, then the choice; its activation is the page's own (checks → test → confirm).
  Future<void> _choose(HubBenchRole r, HubBenchResult x) async {
    final id = x.modelId;
    if (id == null) return;
    final name = _benchName(x);
    final ok = await appConfirm(context,
        confirmLabel: t('استخدمه', 'Use it'),
        message: t('استخدام $name لدور ${hubRoleName(r.role)} بدلاً من التوصية؟ يُنزَّل إن لزم ويُختبر، ثم تؤكد التبديل.',
            'Use $name for ${hubRoleName(r.role)} instead of the recommendation? It is downloaded if needed and tested, then you confirm the switch.'));
    if (!ok || !mounted) return;
    await _sendChoice(r, id, name);
  }

  Future<void> _followDefault(HubBenchRole r) async {
    final ok = await appConfirm(context,
        confirmLabel: t('العودة إلى التوصية', 'Follow the recommendation'),
        message: t('إلغاء اختيارك لدور ${hubRoleName(r.role)} ليتبع النموذج الموصى به؟', 'Clear your choice for ${hubRoleName(r.role)} so it follows the recommended model?'));
    if (!ok || !mounted) return;
    await _sendChoice(r, null, t('النموذج الموصى به', 'The recommended model'));
  }

  Future<void> _sendChoice(HubBenchRole r, int? id, String name) async {
    setState(() => _benchBusy.add(r.role));
    try {
      final reply = await _api.chooseModel(r.role, id);
      final step = reply.activation;
      final target = step.pending?.modelId ?? id ?? reply.effectiveId;
      switch (step.stage) {
        case 'active':
          showAppNotice(t('$name يخدم الآن دور ${hubRoleName(r.role)}', '$name now serves ${hubRoleName(r.role)}'));
        case 'downloading':
          if (target != null) _requested.add(target);
          showAppNotice(t('يُنزَّل $name أولاً ثم يُختبر.', 'Downloading $name first, then it is tested.'));
          await _dl.refresh();
        default:
          // testing / ready_to_confirm: the page's own confirm prompt opens when the test passes (_maybePrompt)
          if (target != null) {
            _requested.add(target);
            _prompted.removeWhere((k) => k.startsWith('$target:'));
          }
      }
      await _load(silent: true);
      await _loadBench();
    } catch (e) {
      showAppNotice(HubFailure.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _benchBusy.remove(r.role));
    }
  }

  Future<void> _setJudge(bool on) async {
    setState(() => _judgeBusy = true);
    try {
      final now = await _api.setJudge(on);
      showAppNotice(now == 'off'
          ? t('أُوقف حَكَم الاستنتاج: الإجابات التي تحتاجه تذهب إلى المعلّم خلال دقيقة.', 'The inference judge is off: answers that need it go to the teacher within a minute.')
          : t('حَكَم الاستنتاج يعمل', 'The inference judge is on'));
      await _load(silent: true);
    } catch (e) {
      showAppNotice(HubFailure.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _judgeBusy = false);
    }
  }

  /// A step this person started reached "ready to confirm" (or failed): say so once.
  void _maybePrompt() {
    final ov = _ov;
    if (ov == null || _prompting) return;
    for (final r in ov.roles) {
      final p = r.pending;
      if (p == null || !_requested.contains(p.modelId) || _prompted.contains(p.stepKey)) continue;
      if (p.readyToConfirm) {
        _prompted.add(p.stepKey);
        unawaited(_review(r, p));
        return;
      }
      if (p.stage == 'failed') {
        _prompted.add(p.stepKey);
        _requested.remove(p.modelId);
        unawaited(_explain(r, p));
        return;
      }
    }
  }

  /// A task activation reached its end (the role serves the model, or the hub stopped it): say so once.
  void _checkAwaiting() {
    final ov = _ov;
    if (ov == null || _awaiting.isEmpty) return;
    final done = <int>[];
    _awaiting.forEach((id, role) {
      final st = hubActivationState(ov, {for (final d in _dl.live) d.modelId: d}, id, role);
      final r = ov.role(role);
      final name = _modelName(r?.byId(id), '', r);
      if (st.phase == ActivationPhase.active) {
        done.add(id);
        showAppNotice(t('$name يخدم الآن مهمة ${hubRoleName(role)}', '$name now serves ${hubRoleName(role)}'));
      } else if (st.phase == ActivationPhase.failed) {
        done.add(id);
      } else if (st.phase == ActivationPhase.idle && r?.pending == null && _dl.live.every((d) => d.modelId != id)) {
        done.add(id); // nothing is moving any more and it is not active: the hub dropped it (cancelled)
      }
    });
    _awaiting.removeWhere((id, _) => done.contains(id));
  }

  Future<void> _guard(int? modelId, Future<void> Function() f) async {
    if (modelId != null) setState(() => _busy.add(modelId));
    try {
      await f();
    } catch (e) {
      showAppNotice(HubFailure.from(e).message, error: true);
    } finally {
      if (modelId != null && mounted) setState(() => _busy.remove(modelId));
    }
  }

  // ── actions ───────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _download(HubModel m) => _guard(m.id, () async {
        _dl.track(await _api.download(m.id));
        showAppNotice(t('بدأ تنزيل ${m.name}', 'Downloading ${m.name}'));
        await _load(silent: true);
      });

  Future<void> _activate(HubModel m) => _activateFor(_ov?.role(m.role), m);

  /// Activates [m] for [r] (a task role sends its name: one model can serve several tasks).
  Future<void> _activateFor(HubRole? r, HubModel m) async {
    if (r == null) return;
    final current = _activeName(r);
    setState(() => _busy.add(m.id));
    try {
      _requested.add(m.id);
      _prompted.removeWhere((k) => k.startsWith('${m.id}:')); // a new request may prompt again
      final out = await hubActivate(_api, m.id, role: r.isTask ? r.role : null);
      if (!mounted) return;
      switch (out) {
        case ActivationActive():
          _requested.remove(m.id);
          showAppNotice(t('${m.name} يخدم الآن مهمة ${hubRoleName(r.role)}', '${m.name} now serves ${hubRoleName(r.role)}'));
        case ActivationDownloading():
          if (r.isTask) _awaiting[m.id] = r.role;
          showAppNotice(current == null
              ? t('يُنزَّل ${m.name} أولاً، ثم يُختبر ويُفعَّل تلقائياً.', 'Downloading ${m.name} first; it is tested and switched on automatically.')
              : t('يُنزَّل ${m.name} أولاً — $current يبقى مُفعّلاً حتى يجتاز الجديد الاختبار ثم يُبدَّل تلقائياً.',
                  'Downloading ${m.name} first — $current stays active until the new model passes its test, then it switches by itself.'));
          await _dl.refresh();
        case ActivationInProgress(:final step):
          if (r.isTask) _awaiting[m.id] = r.role;
          if (step.stage == 'testing') showAppNotice(t('يجري اختبار السلامة لـ ${m.name}…', 'Running the health test of ${m.name}…'));
        case ActivationFailed():
          _requested.remove(m.id);
        case ActivationBlocked(:final ram, :final failure):
          _requested.remove(m.id);
          if (ram != null) {
            await showAppSheet<void>(context, (_) => RamBudgetSheet(role: r.role, model: m.name, current: current, ram: ram));
          } else {
            await showAppSheet<void>(context, (_) => ActivateFailure(role: r.role, model: m.name, current: current, checks: failure.checks, message: failure.message));
          }
        case ActivationRoleMismatch(:final failure):
          _requested.remove(m.id);
          showAppNotice(failure.message, error: true);
        case ActivationError(:final failure):
          _requested.remove(m.id);
          showAppNotice(failure.message, error: true);
      }
      await _load(silent: true);
      // the test ran at once (a model already on disk): the prompt / the reason now, from the reply itself
      final p = switch (out) {
        ActivationInProgress(:final step) => step.pending,
        ActivationFailed(:final step) => step.pending,
        _ => null,
      };
      if (p != null && mounted && !_prompted.contains(p.stepKey) && (p.readyToConfirm || p.stage == 'failed')) {
        _prompted.add(p.stepKey);
        final role = _ov?.role(r.role) ?? r;
        if (mounted) setState(() => _busy.remove(m.id));
        if (p.readyToConfirm) {
          await _review(role, p);
        } else {
          _requested.remove(m.id);
          await _explain(role, p);
        }
      }
    } finally {
      if (mounted) setState(() => _busy.remove(m.id));
    }
  }

  /// "Use the recommended models": the hub activates its recommendation of every task.
  Future<void> _applyDefaults() async {
    final ok = await appConfirm(context,
        confirmLabel: t('استخدام الموصى به', 'Use recommended'),
        message: t('تفعيل النماذج الموصى بها للمحادثة وتوليد الامتحانات والتصحيح؟ يُنزَّل ما ينقص ويُبدَّل تلقائياً بعد الاختبار.',
            'Activate the recommended models for chat, exam generation and grading? What is missing is downloaded and switched on after its test.'));
    if (!ok || !mounted) return;
    await _guard(null, () async {
      await _api.applyDefaults();
      showAppNotice(t('بدأ تطبيق النماذج الموصى بها', 'Applying the recommended models'));
      await _dl.refresh();
      await _load(silent: true);
    });
  }

  /// The confirm prompt for a role's pending model ("ready to confirm"), then the switch. When the server still asks
  /// for the index choice (409 reindex_choice_required: documents the estimate did not count), the prompt comes back
  /// once with the server's numbers.
  Future<void> _review(HubRole r, HubPending? pending, {HubReindex? reindex}) async {
    final p = pending ?? r.pending;
    if (p == null || _prompting || !mounted) return;
    final m = r.byId(p.modelId);
    _prompting = true;
    try {
      var estimate = reindex ?? p.reindex;
      for (var round = 0; round < 2; round++) {
        if (!mounted) return;
        final choice = await showAppSheet<ActivateChoice>(
          context,
          (_) => ActivatePrompt(
            role: r.role,
            model: _modelName(m, p.ref, r),
            current: _activeName(r),
            test: p.test,
            reindex: estimate,
          ),
        );
        if (choice == null || choice == ActivateChoice.cancel || !mounted) return;
        _requested.remove(p.modelId);
        final again = await _confirm(r, p, switch (choice) {
          ActivateChoice.reindexNow => 'now',
          ActivateChoice.reindexLater => 'later',
          _ => null,
        });
        if (again == null) return;
        estimate = again;
      }
    } finally {
      _prompting = false;
    }
  }

  /// The switch; returns the server's estimate when it asks for the index choice first.
  Future<HubReindex?> _confirm(HubRole r, HubPending p, String? reindex) async {
    final name = _modelName(r.byId(p.modelId), p.ref, r);
    setState(() => _busy.add(p.modelId));
    try {
      final step = await _api.activate(p.modelId, confirm: true, reindex: reindex, role: r.isTask ? r.role : null);
      switch (step.stage) {
        case 'active':
          showAppNotice(r.active == null
              ? t('$name مُفعّل الآن لدور ${hubRoleName(r.role)}', '$name is now active for ${hubRoleName(r.role)}')
              : t('$name مُفعّل الآن لدور ${hubRoleName(r.role)} — ${_activeName(r)} محفوظ للرجوع.',
                  '$name is now active for ${hubRoleName(r.role)} — ${_activeName(r)} is kept for rollback.'));
        case 'reindexing':
          showAppNotice(t('تُبنى متجهات المستندات في الخلفية؛ يبقى البحث على النموذج الحالي حتى تكتمل.',
              'The document vectors are being rebuilt in the background; search keeps the current model until they are done.'));
        case 'reindex_later':
          showAppNotice(t('ينتظر التبديل إعادة بناء الفهرس — ابدأها من قسم التضمين متى شئت.',
              'The switch waits for the index rebuild — start it from the Embedding section when you are ready.'));
      }
    } catch (e) {
      final f = HubFailure.from(e);
      if (f.code == 'reindex_choice_required' && f.reindex != null) return f.reindex;
      showAppNotice(f.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(p.modelId));
    }
    await _load(silent: true);
    return null;
  }

  Future<void> _explain(HubRole r, HubPending p) async {
    if (!mounted) return;
    await showAppSheet<void>(
      context,
      (_) => ActivateFailure(
        role: r.role,
        model: _modelName(r.byId(p.modelId), p.ref, r),
        current: _activeName(r),
        test: p.test,
        checks: p.checks,
      ),
    );
  }

  Future<void> _delete(HubModel m) async {
    if (m.deletable) {
      final ok = await appConfirm(context,
          danger: true,
          confirmLabel: t('حذف', 'Delete'),
          message: t('حذف ${m.name}؟ تُحذف ملفاته (${hubBytes(m.diskBytes)}) من الخادم. لا يُحذف أي نموذج تلقائياً.',
              'Delete ${m.name}? Its files (${hubBytes(m.diskBytes)}) are removed from the server. Nothing is ever deleted automatically.'));
      if (!ok) return;
    }
    // a model in use is refused by the server with its own words ("This model is active. Activate another model first.")
    await _guard(m.id, () async {
      final r = await _api.delete(m.id);
      final freed = r['freed_bytes'] is num ? (r['freed_bytes'] as num).toInt() : 0;
      showAppNotice(t('حُذف ${m.name} (حُرّر ${hubBytes(freed)})', '${m.name} deleted (${hubBytes(freed)} freed)'));
      await _load(silent: true);
    });
  }

  Future<void> _fallback(HubRole r, HubModel m) => _guard(m.id, () async {
        final clear = m.isFallback;
        await _api.setFallback(r.role, clear ? null : m.id);
        showAppNotice(clear
            ? t('لا نموذج احتياطياً لدور ${hubRoleName(r.role)}', 'No fallback for ${hubRoleName(r.role)}')
            : t('${m.name} احتياطي لدور ${hubRoleName(r.role)}: يخدم إن تعذّر المُفعّل', '${m.name} is the ${hubRoleName(r.role)} fallback: it serves when the active model fails'));
        await _load(silent: true);
      });

  Future<void> _test(HubModel m) => _guard(m.id, () async {
        await _api.test(m.id);
        showAppNotice(t('بدأ اختبار السلامة لـ ${m.name}', 'Health test of ${m.name} started'));
        await _load(silent: true);
      });

  /// Back to the role's previous model, after a confirm that says what switches from → to and what it costs: an
  /// embedder goes back to the vectors the index kept for it (no rebuild; refused when they were dropped).
  Future<void> _rollback(HubRole r) async {
    final from = _activeName(r) ?? t('لا شيء', 'nothing');
    final to = hubModelLabel(r.previousModel, role: r, ref: r.previous);
    final cost = r.role == 'embedding'
        ? t('يعود فهرس المستندات فوراً إلى المتجهات المحفوظة لهذا النموذج، دون إعادة بناء. إن كانت متجهاته قد حُذفت يُرفض الرجوع، وعندها فعّله من جديد مع إعادة البناء.',
            'The document index switches back at once to the vectors it kept for that model — no rebuild. If its vectors were dropped, the rollback is refused; activate it again with a rebuild instead.')
        : t('لا تلزم إعادة بناء: يخدم النموذج السابق فوراً.', 'No rebuild is needed: the previous model serves at once.');
    final ok = await appConfirm(context,
        confirmLabel: t('رجوع', 'Roll back'),
        message: t('رجوع دور ${hubRoleName(r.role)} من $from إلى $to؟\n$cost', 'Roll ${hubRoleName(r.role)} back from $from to $to?\n$cost'));
    if (!ok || !mounted) return;
    await _guard(null, () async {
      final s = await _api.rollback(r.role);
      final now = s.active == null || s.active == r.previous ? to : hubRefLabel(s.active!);
      showAppNotice(t('عاد دور ${hubRoleName(r.role)} إلى $now', '${hubRoleName(r.role)} is back on $now'));
      await _load(silent: true);
    });
  }

  Future<void> _cancelPending(HubRole r) => _guard(null, () async {
        await _api.cancelPending(r.role);
        await _load(silent: true);
      });

  Future<void> _reindexNow(HubRole r) => _guard(null, () async {
        final step = await _api.reindexEmbedding();
        // `active`: RAG already answered with the model, or every vector of it was built (B6 round 2): no rebuild ran
        final name = _modelName(r.byId(r.pending?.modelId), step.active ?? r.pending?.ref ?? '');
        showAppNotice(step.stage == 'active'
            ? t('$name مُفعّل الآن لدور ${hubRoleName(r.role)} دون إعادة بناء.', '$name is now active for ${hubRoleName(r.role)} — no rebuild was needed.')
            : t('بدأت إعادة بناء فهرس المستندات في الخلفية', 'The document index rebuild started in the background'));
        await _load(silent: true);
      });

  Future<void> _limits(HubRole r) async {
    final body = await showAppSheet<Map<String, dynamic>>(context, (_) => LimitsSheet(role: r.role, limits: r.limits, cpuCount: _sys?.cpuCount));
    if (body == null) return;
    await _guard(null, () async {
      await _api.setLimits(r.role, body);
      showAppNotice(t('حُفظت موارد ${hubRoleName(r.role)}', '${hubRoleName(r.role)} limits saved'));
      await _load(silent: true);
    });
  }

  Future<void> _gradingMode(HubRole r, String mode) => _guard(null, () async {
        await _api.setGradingMode(mode);
        showAppNotice('${hubRoleName(r.role)}: ${hubGradingModeLabel(mode)}');
        await _load(silent: true);
      });

  Future<void> _addByName() => _add(source: 'ollama', role: 'generation.chat');

  Future<void> _add({String? source, String? role}) async {
    final roles = _ov?.roles.map((r) => r.role).toList();
    final list = roles == null || roles.isEmpty ? kHubRoles : roles;
    final body = await showAppSheet<Map<String, dynamic>>(
        context,
        (_) => AddModelSheet(
            roles: list, initialSource: source ?? 'registry', role: role != null && list.contains(role) ? role : (list.contains('generation') ? 'generation' : list.first)));
    if (body == null) return;
    await _guard(null, () async {
      final m = await _api.add(body);
      showAppNotice(t('أُضيف ${m.name} — نزّله أو فعّله من قسم ${hubRoleName(m.role)}', '${m.name} added — download or activate it from ${hubRoleName(m.role)}'));
      await _load(silent: true);
    });
  }

  Future<void> _downloadAction(HubDownload d, String action) => _guard(d.modelId, () async {
        if (action == 'cancel') {
          final ok = await appConfirm(context,
              danger: true,
              confirmLabel: t('إلغاء التنزيل', 'Cancel download'),
              message: t('إلغاء التنزيل؟ يُحذف الجزء الذي نُزّل.', 'Cancel the download? The part already downloaded is deleted.'));
          if (!ok) return;
          await _dl.cancel(d);
        } else {
          await (action == 'pause' ? _dl.pause(d) : _dl.resume(d));
        }
        await _load(silent: true);
      });

  // ── build ─────────────────────────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ov = _ov;
    final me = _me(context);
    final downloads = {for (final d in _dl.live) d.modelId: d};
    final actions = AiModelsActions(
      onDownload: _download,
      onActivate: _activate,
      onActivateRole: _activateFor,
      onApplyDefaults: _applyDefaults,
      onAddByName: _addByName,
      onFallback: _fallback,
      onTest: _test,
      onDelete: _delete,
      onPause: (d) => _downloadAction(d, 'pause'),
      onResume: (d) => _downloadAction(d, 'resume'),
      onCancelDownload: (d) => _downloadAction(d, 'cancel'),
      onRollback: _rollback,
      onLimits: _limits,
      onGradingMode: _gradingMode,
      onReview: (r) => _review(r, null),
      onCancelPending: _cancelPending,
      onReindexNow: _reindexNow,
      onAdd: _add,
    );
    return BasePage(
      key: const ValueKey(kModelsAdminFeatureKey),
      child: SupPage(
        title: t('نماذج الذكاء الاصطناعي', 'AI Models'),
        kicker: 'a2_ai_kicker'.tr,
        headline: 'a2_ai_head'.tr,
        line: 'a2_ai_line'.tr,
        helpPageId: 'admin.models',
        onRefresh: _load,
        actions: [
          SupHeroButton(key: const ValueKey('add_model'), label: 'a2_ai_add'.tr, icon: Icons.add_rounded, onTap: _add),
        ],
        body: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl * 2),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                    AppChoiceChip(
                      label: t('النماذج', 'Models'),
                      icon: Icons.view_list_rounded,
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    AppChoiceChip(
                      key: const ValueKey('tab_history'),
                      label: t('السجل', 'History'),
                      icon: Icons.history_rounded,
                      selected: _tab == 1,
                      onTap: () {
                        setState(() => _tab = 1);
                        _loadAudit();
                      },
                    ),
                    if (_benchOn)
                      AppChoiceChip(
                        key: const ValueKey('tab_benchmarks'),
                        label: t('القياس', 'Benchmarks'),
                        icon: Icons.speed_rounded,
                        selected: _tab == 2,
                        onTap: () {
                          setState(() => _tab = 2);
                          _loadBench();
                        },
                      ),
                  ]),
                  const SizedBox(height: AppSpace.md),
                  if (_error != null && ov == null)
                    AppEmpty(icon: Icons.cloud_off_rounded, title: _error!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _load)
                  else if (ov == null)
                    const AppListSkeleton(items: 5, withAvatar: false, padding: EdgeInsets.zero)
                  else if (_tab == 2 && _benchOn)
                    (_bench == null
                        ? (_benchError != null
                            ? AppEmpty(icon: Icons.cloud_off_rounded, title: _benchError!, actionLabel: t('إعادة المحاولة', 'Retry'), onAction: _loadBench)
                            : const AppListSkeleton(items: 4, withAvatar: false, padding: EdgeInsets.zero))
                        : HubBenchView(
                            data: _bench!,
                            judge: ov.role('nli')?.judge,
                            names: {
                              for (final r in _bench!.roles)
                                for (final x in r.results)
                                  if (x.modelId != null) x.modelId!: _benchName(x),
                            },
                            running: _benchStarting,
                            busy: _benchBusy,
                            judgeBusy: _judgeBusy,
                            onRun: _runBench,
                            onChoose: _choose,
                            onFollowDefault: _followDefault,
                            onJudge: _setJudge,
                          ))
                  else if (_tab == 0)
                    AiModelsView(overview: ov, downloads: downloads, alerts: _alerts, system: _sys, busy: _busy, actions: actions)
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.sm),
                      child: AppDropdown<String?>(
                        value: _historyRole,
                        decoration: InputDecoration(labelText: t('الدور', 'Role')),
                        items: [
                          DropdownMenuItem(value: null, child: Text(t('كل الأدوار', 'All roles'))),
                          for (final r in ov.roles) DropdownMenuItem(value: r.role, child: Text(hubRoleName(r.role))),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _historyRole = v;
                            _audit = null;
                          });
                          _loadAudit();
                        },
                      ),
                    ),
                    if (_audit == null)
                      const AppListSkeleton(items: 6, withAvatar: false, padding: EdgeInsets.zero)
                    else
                      AiModelsHistory(audit: _audit!, overview: ov, me: me),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
