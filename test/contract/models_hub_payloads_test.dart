// The model hub's parsers (lib/core/models_hub/models_hub_api.dart) against REAL replies of the hub (D-152), recorded
// from its own e2e run (../back tests/modelhub/e2e_modelhub.py, MODELHUB_MODE=test) by wrapping TestClient.request:
// test/fixtures/payloads/models_hub/*.json (`_source` says the route, the status and how; `payload` is the body).
// Every key a parser reads must be in the payload, so a renamed field fails here and not on the AI Models page.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/ai_models_sheets.dart';
import 'package:flutter_education_app/features/admin/models/models_hub_text.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';

Object? hub(String name) {
  final j = jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map<String, dynamic>;
  return j['payload'];
}

int hubStatus(String name) =>
    ((jsonDecode(File('test/fixtures/payloads/models_hub/$name.json').readAsStringSync()) as Map)['_source'] as Map)['status'] as int;

HubFailure failure(String name) => HubFailure.from(ApiException(statusCode: hubStatus(name), message: 'fallback', body: hub(name)));

const _modelKeys = [
  'id', 'role', 'name', 'version', 'ref', 'provider', 'source', 'repo', 'revision', 'license', 'size_bytes', 'disk_bytes',
  'ram_mb', 'status', 'error', 'last_test', 'used_as', 'pinned', 'quantization', 'dim', 'added_by', 'added_at', 'deletable',
];
const _roleKeys = ['role', 'active', 'active_id', 'previous', 'previous_id', 'fallback', 'fallback_id', 'pending', 'limits', 'models'];
const _limitKeys = ['threads', 'max_concurrency', 'priority', 'idle_unload_s', 'ram_mb'];
const _downloadKeys = [
  'id', 'model_id', 'ref', 'role', 'status', 'bytes_done', 'bytes_total', 'percent', 'speed_bps', 'eta_s', 'error',
  'activate_after', 'created_at', 'finished_at',
];

void main() {
  setUp(() => AppConfig.lang = 'en');

  final overviews = Directory('test/fixtures/payloads/models_hub')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .where((n) => n.startsWith('overview'))
      .toList()
    ..sort();

  test('every recorded overview has every key the parsers read, roles in the server order', () {
    expect(overviews.length, greaterThanOrEqualTo(8));
    for (final name in overviews) {
      final raw = hub(name) as Map<String, dynamic>;
      final roles = (raw['roles'] as List).cast<Map<String, dynamic>>();
      // a capture from before D-248 / D-252 has no exam_grading row (re-record with tests/modelhub/e2e_modelhub.py)
      final expected = [for (final k in kHubRoles) if (k != 'exam_grading' || roles.any((r) => r['role'] == k)) k];
      expect(roles.map((r) => r['role']).toList(), expected, reason: name);
      for (final r in roles) {
        for (final k in _roleKeys) {
          expect(r.containsKey(k), isTrue, reason: '$name: role ${r['role']} lacks "$k"');
        }
        for (final k in _limitKeys) {
          expect((r['limits'] as Map).containsKey(k), isTrue, reason: '$name: limits lack "$k"');
        }
        for (final m in (r['models'] as List).cast<Map<String, dynamic>>()) {
          for (final k in _modelKeys) {
            expect(m.containsKey(k), isTrue, reason: '$name: model ${m['ref']} lacks "$k"');
          }
        }
      }
      final ov = HubOverview.fromJson(raw);
      expect(ov.roles, hasLength(expected.length));
      for (final r in ov.roles) {
        if (r.activeId != null) expect(r.activeModel?.ref, r.active, reason: '$name ${r.role}');
      }
    }
  });

  test('the seeded registry: the environment\'s choices are the actives, sizes and RAM estimates read', () {
    final ov = HubOverview.fromJson(hub('overview_downloading'));
    final emb = ov.role('embedding')!;
    expect(emb.active, 'multilingual-e5-small@int8-761b726');
    expect(emb.activeModel!.status, 'active');
    expect(emb.activeModel!.isActive, isTrue);
    final base = emb.models.firstWhere((m) => m.ref == 'multilingual-e5-base@int8-1ec9243');
    expect(base.status, 'not_downloaded');
    expect(base.sizeBytes, 295730322);
    expect(base.ramMb, 691);
    expect(base.dim, 768);
    expect(base.source, 'registry');
    expect(base.deletable, isFalse);
    expect(hubBytes(base.sizeBytes), '296 MB');
    expect(emb.limits.threads, 1);
    expect(emb.limits.priority, 'interactive');
    final gen = ov.role('generation')!;
    expect(gen.pending!.stage, 'downloading');
    expect(gen.pending!.downloadId, 1);
    expect(gen.pendingModel!.status, 'downloading');
    expect(gen.pendingModel!.usedAs, ['pending']);
  });

  test('downloads: progress, speed and time left from a running download; paused; the live event is the same row', () {
    final running = [for (final d in (hub('downloads_running') as Map)['downloads'] as List) HubDownload.fromJson(d)!];
    final d = running.first;
    for (final k in _downloadKeys) {
      expect(((hub('downloads_running') as Map)['downloads'] as List).first.containsKey(k), isTrue, reason: k);
    }
    expect(d.status, 'running');
    expect(d.live, isTrue);
    expect(d.percent, 18.0);
    expect(d.fraction, closeTo(0.18, 1e-9));
    expect(d.speedBps, 258172.1);
    expect(d.etaS, 19);
    expect(d.activateAfter, isTrue);
    expect(hubDownloadLine(d), 'Downloading… 18% · 259 KB/s · 19 s left');
    AppConfig.lang = 'ar';
    String iso(String s) => '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}';
    expect(hubDownloadLine(d), 'جارٍ التنزيل… ${iso('18%')} · ${iso('259 KB/s')} · بقي 19 ث');
    AppConfig.lang = 'en';

    final paused = HubDownload.fromJson(((hub('downloads_paused') as Map)['downloads'] as List).first)!;
    expect(paused.paused, isTrue);
    expect(paused.etaS, isNull);
    expect(hubDownloadLine(paused), 'Paused · 18%');

    // the pause reply comes back before the worker stops (still "running"); the resume reply is "queued"
    expect(HubDownload.fromJson(hub('download_pause'))!.status, 'running');
    expect(HubDownload.fromJson(hub('download_resume'))!.status, 'queued');
    expect(HubDownload.fromJson(hub('download_cancel'))!.status, 'cancelled');

    final events = (hub('live_events') as List).cast<Map<String, dynamic>>();
    expect(events.map((e) => e['event']).toSet(), {LiveEvents.modelDownload, LiveEvents.modelChanged});
    for (final e in events) {
      expect(LiveEvents.serverTypes, contains(e['event']));
      if (e['event'] == LiveEvents.modelDownload) {
        final x = HubDownload.fromJson(LiveEvent.fieldsOf(LiveEvents.modelDownload, e['data'] as Map<String, dynamic>))!;
        expect(x.modelId, 23);
        for (final k in _downloadKeys) {
          expect((e['data'] as Map).containsKey(k), isTrue, reason: 'model_download lacks $k');
        }
      } else {
        expect(LiveEvent(e['event'] as String, e['data'] as Map<String, dynamic>).action, isNotNull);
      }
    }
  });

  test('activation: download first, ready to confirm with the health test, the switch, a failed test', () {
    final dl = HubStep.fromJson(hub('activate_downloading'));
    expect(dl.stage, 'downloading');
    expect(dl.downloadId, 1);
    expect(dl.pending!.stage, 'downloading');

    final ready = HubStep.fromJson(hub('activate_ready'));
    expect(ready.stage, 'ready_to_confirm');
    expect(ready.pending!.readyToConfirm, isTrue);
    expect(ready.pending!.test!.ok, isTrue);
    expect(ready.pending!.test!.speed, 500.0);
    expect(ready.pending!.test!.rssMb, 130);
    expect(ready.pending!.checks.map((c) => c.name), ['ram', 'cpu']);
    expect(ready.pending!.checks.every((c) => c.ok), isTrue);
    expect(hubTestLine(ready.pending!.test!), 'Passed · 500 / s · 130 MB');

    final done = HubStep.fromJson(hub('activate_confirm'));
    expect(done.stage, 'active');
    expect(done.active, 'gen-good@v1');

    final failed = HubStep.fromJson(hub('activate_failed'));
    expect(failed.stage, 'failed');
    expect(failed.pending!.failed, isTrue);
    expect(failed.pending!.reason, 'health_test_failed');
    expect(failed.pending!.test!.ok, isFalse);
    expect(failed.pending!.test!.stage, 'answer');
    expect(failed.pending!.test!.error, 'the model answered the known sample wrong');

    final rb = HubStep.fromJson(hub('rollback'));
    expect(rb.active, 'gen-good@v1');
    expect(rb.rolledBackFrom, 29);
  });

  test('embedding: the re-index estimate, 409 reindex_choice_required, later / now', () {
    final r = HubStep.fromJson(hub('embedding_activate_ready')).pending!.reindex!;
    expect(r.known, isTrue);
    expect(r.required, isTrue);
    expect(r.chunks, 1200);
    expect(r.qa, 30);
    expect(r.items, 1230);
    expect(r.vectorsReady, isFalse);
    // nothing measured on this server: no number (the health test's speed is no rebuild speed, B6 round 2)
    expect(r.estimatedSeconds, isNull);
    expect(r.estimate!.basis, 'none');
    expect(reindexEstimateText(r), '1230 items (1200 chunks + 30 saved answers) · time not known yet — measured on this model\'s first rebuild here');

    final f = failure('reindex_choice_required');
    expect(f.status, 409);
    expect(f.code, 'reindex_choice_required');
    expect(f.messageEn, 'Changing the embedding model re-builds the document index. Choose now or later.');
    expect(f.reindex!.chunks, 1200);
    expect(f.reindex!.required, isTrue);
    expect(f.extra['choices'], ['now', 'later']);

    final later = HubStep.fromJson(hub('reindex_later'));
    expect(later.stage, 'reindex_later');
    expect(later.reindex!.chunks, 1200);
    expect(HubStep.fromJson(hub('reindex_start')).stage, 'reindexing');

    final ov = HubOverview.fromJson(hub('overview_reindexing')).role('embedding')!;
    expect(ov.pending!.stage, 'reindexing');
    expect(ov.pending!.reindex!.total, 1230);
    expect(ov.pending!.reindex!.done, 0);
    expect(HubOverview.fromJson(hub('overview_reindex_later')).role('embedding')!.pending!.stage, 'reindex_later');
  });

  test('embedding (B6 round 2): vectors already built, partly built, and estimates only from measured rebuilds', () {
    final ready = HubStep.fromJson(hub('embedding_activate_vectors_ready')).pending!.reindex!;
    expect(ready.required, isFalse);
    expect(ready.vectorsReady, isTrue);
    expect(ready.items, 0);
    expect(vectorsReadyText(ready),
        'This model\'s vectors are already built for every document (1200 chunks + 30 saved answers), so activating switches the index at once — no rebuild.');
    expect(HubOverview.fromJson(hub('overview_vectors_ready')).role('embedding')!.pending!.reindex!.vectorsReady, isTrue);
    final done = HubStep.fromJson(hub('activate_vectors_ready_confirm'));
    expect(done.stage, 'active');
    expect(done.active, 'emb-kept@v1');

    final part = HubStep.fromJson(hub('embedding_activate_partial')).pending!.reindex!;
    expect((part.missingChunks, part.missingQa, part.items, part.required), (200, 0, 200, true));
    expect(reindexEstimateText(part),
        '200 items of 1230 still need vectors (200 chunks + 0 saved answers) · time not known yet — measured on this model\'s first rebuild here');
    final f = failure('reindex_choice_partial');
    expect(f.reindex!.items, 200);
    expect(f.reindex!.missingChunks, 200);

    final range = HubStep.fromJson(hub('embedding_activate_estimate_range')).pending!.reindex!;
    expect(range.estimate!.basis, 'other_models');
    expect(range.estimate!.models, ['emb-part@v1']);
    expect((range.estimate!.lowSeconds, range.estimate!.highSeconds, range.estimatedSeconds), (615, 615, null));
    expect(reindexTimeText(range), 'about 10 min (going by another model rebuilt here)'); // 615 s: to the nearest minute
    expect(reindexTimeText(HubReindex(estimate: const HubEstimate(basis: 'other_models', lowSeconds: 19, highSeconds: 145))),
        'between 20 s and 2 min (going by other models rebuilt here)');

    final measured = HubStep.fromJson(hub('embedding_activate_estimate_measured')).pending!.reindex!;
    expect(measured.estimate!.basis, 'this_model');
    expect((measured.estimatedSeconds, measured.estimate!.measuredItems, measured.estimate!.measuredSeconds), (615, 200, 100.0));
    expect(reindexEstimateText(measured), '1230 items (1200 chunks + 30 saved answers) · about 10 min (measured on this model\'s last rebuild here)');

    AppConfig.lang = 'ar';
    expect(reindexEstimateText(part), 'يلزم بناء 200 عنصرًا من أصل 1230 (200 مقطعًا + 0 إجابة محفوظة) · المدة غير معروفة بعد: تُقاس عند أول إعادة بناء بهذا النموذج هنا');
    expect(reindexTimeText(measured), 'نحو 10 د (حسب آخر إعادة بناء لهذا النموذج هنا)');
  });

  test('errors: the server\'s own words by language, and the extra fields', () {
    final active = failure('delete_active');
    expect(active.code, 'model_active');
    expect(active.message, 'This model is active. Activate another model first.');
    AppConfig.lang = 'ar';
    expect(active.message, 'هذا النموذج مُفعّل حالياً. فعّل نموذجاً آخر أولاً');
    AppConfig.lang = 'en';
    expect(failure('delete_in_use').code, 'model_in_use');
    expect(failure('forbidden').code, 'super_admin_required');
    expect(failure('forbidden').status, 403);
    expect(failure('bad_limit').message, 'threads must be 1..12.');
    expect(failure('dim_unsupported').code, 'embedding_dim_unsupported');
    expect(failure('switch_in_progress').code, 'switch_in_progress');
    expect(failure('not_ready_to_confirm').extra['stage'], 'failed');
  });

  test('audit, alerts, limits, fallback, delete, add', () {
    final audit = [for (final a in (hub('audit') as Map)['audit'] as List) HubAudit.fromJson(a as Map<String, dynamic>)];
    expect(audit, isNotEmpty);
    for (final a in [...audit, for (final a in (hub('audit_generation') as Map)['audit'] as List) HubAudit.fromJson(a as Map<String, dynamic>)]) {
      expect(hubAuditAction(a.action), isNot(a.action), reason: 'no words for the audit action "${a.action}"');
      expect(a.at, isNotNull);
    }
    expect(audit.first.action, 'health_test');
    expect(audit.first.actor, isNull);
    expect(hubActor(audit.first.actor, 1), 'The model server');
    expect(hubActor(1, 1), 'You');
    expect(audit.firstWhere((a) => a.action == 'download_resume').actor, 1);

    final alerts = [for (final a in (hub('alerts') as Map)['alerts'] as List) HubAlert.fromJson(a as Map<String, dynamic>)];
    final health = alerts.firstWhere((a) => a.kind == 'health_failed');
    expect(health.role, 'generation');
    expect(health.detail['error'], 'the model answered the known sample wrong');
    expect(alerts.map((a) => a.kind).toSet(), containsAll(['health_failed', 'download_failed']));

    final limits = HubLimits.fromJson(((hub('limits') as Map)['limits'] as Map).cast<String, dynamic>());
    expect(limits.threads, 1);
    expect(limits.maxConcurrency, 1);
    expect((hub('fallback') as Map)['fallback_id'], 29);
    expect((hub('delete_ok') as Map)['freed_bytes'], 600000);
    final added = HubModel.fromJson(hub('add_url') as Map<String, dynamic>);
    expect(added.status, 'not_downloaded');
    expect(added.source, 'url');
    expect(added.addedBy, 1);
  });

  test('system: cores, disk, RAM, providers; an empty alert list; a finished download is not live', () {
    final s = HubSystem.fromJson(hub('system'));
    expect(s.cpuCount, 12);
    expect(s.diskFreeMb, isNotNull);
    expect(s.ramAvailableMb, isNotNull);
    expect(s.providers['onnx'], 'available');
    expect(s.providers['ollama'], 'OLLAMA_URL is not set');
    expect((hub('alerts_none') as Map)['alerts'], isEmpty);
    final done = HubDownload.fromJson(((hub('downloads_done') as Map)['downloads'] as List).first)!;
    expect(done.status, 'done');
    expect(done.live, isFalse);
  });

  test('the hub\'s naive timestamps are UTC', () {
    final t = hubTime('2026-11-02T03:05:29.703829')!;
    expect(t.isUtc, isTrue);
    expect(t.hour, 3);
    expect(hubTime('2026-11-02T03:05:29Z')!.hour, 3);
    expect(hubTime('2026-11-02T05:05:29+02:00')!.hour, 3);
    expect(hubTime(null), isNull);
  });
}
