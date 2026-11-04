// The cache card and the D-190 settings: parsing, the PUT bodies, the card's actions, the lora-disabled stats.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/rag/admin/rag_cache_card.dart';
import 'package:flutter_education_app/features/shared/rag/admin/rag_console_settings.dart';
import 'package:flutter_education_app/features/shared/rag/rag_learning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';
import 'rag_admin_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  test('cache stats parse (fraction or percent hit rate, org rows, the settings)', () {
    final s = RagCacheStats.fromJson(cacheStatsJson());
    expect(s.entries, 1240);
    expect(s.hitRate, closeTo(0.42, 0.001));
    expect(s.perOrg.length, 2);
    expect(s.perOrg.first.orgId, isNull);
    expect(s.perOrg.last.orgId, 5);
    expect(s.enabled, isTrue);
    expect(s.maxEntries, 20000);
    expect(s.semanticMin, 0.95);
    expect(RagCacheStats.fromJson({'hit_rate': 42}).hitRate, closeTo(0.42, 0.001));
    expect(RagCacheStats.fromJson({}).hitRate, isNull);
    expect(cacheBytesText(5242880), '5.0 MB');
  });

  test('the cache PUT body has exactly the four keys', () {
    expect(cacheSettingsBody(enabled: false, semantic: true, maxEntries: 100, orgMaxEntries: 10),
        {'cache.enabled': false, 'cache.semantic': true, 'cache.max_entries': 100, 'cache.org_max_entries': 10});
  });

  testWidgets('the card saves its switches and numbers, and clears after a confirm', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? saved;
    var clearedAll = 0;
    final clearedOrgs = <int>[];
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: RagCacheCard(
        stats: RagCacheStats.fromJson(cacheStatsJson()),
        onSave: (b) => saved = b,
        onClearAll: () => clearedAll++,
        onClearOrg: clearedOrgs.add,
      ),
    )));
    await _settle(tester);
    expect(find.text('1240'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);

    await tester.tap(find.text('Semantic matching'));
    await tester.enterText(find.byType(TextField).first, '5000');
    await tester.tap(find.byKey(const ValueKey('cache_save')));
    await _settle(tester);
    expect(saved, {'cache.enabled': true, 'cache.semantic': false, 'cache.max_entries': 5000, 'cache.org_max_entries': 0});

    await tester.tap(find.byKey(const ValueKey('cache_clear_all')));
    await _settle(tester);
    expect(clearedAll, 0); // not before the confirm
    await tester.tap(find.text('Clear all').last);
    await _settle(tester);
    expect(clearedAll, 1);

    await tester.tap(find.byKey(const ValueKey('cache_clear_org_5')));
    await _settle(tester);
    await tester.tap(find.text('Clear').last);
    await _settle(tester);
    expect(clearedOrgs, [5]);

    // "Clear for an organization" asks for the id first
    await tester.tap(find.byKey(const ValueKey('cache_clear_org')));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, '12');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    await tester.tap(find.text('Clear').last);
    await _settle(tester);
    expect(clearedOrgs, [5, 12]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  test('the D-190 settings parse, bound and detect an older server', () {
    final x = RagExtraSettings.fromJson({
      'answer_mode': 'retrieval',
      'ocr_scanned': true,
      'max_doc_mb': 900,
      'learning.embedder_auto': true,
      'learning.embedder_min_new': 3,
    });
    expect(x.present, isTrue);
    expect(x.answerMode, 'retrieval');
    expect(x.maxDocMb, 500);
    expect(x.embedderMinNew, 10);
    expect(x.toJson().keys, containsAll(['answer_mode', 'ocr_scanned', 'max_doc_mb', 'learning.embedder_auto', 'learning.embedder_min_new']));
    expect(RagExtraSettings.fromJson({'generator': 'llm'}).present, isFalse);
    expect(RagExtraSettings.fromJson({'answer_mode': 'weird'}).answerMode, 'generate');
  });

  testWidgets('the settings card saves, validates the bounds and trains on demand', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Map<String, dynamic>? saved;
    var trained = 0;
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
      child: RagExtraSettingsCard(
        settings: const RagExtraSettings(present: true),
        onSave: (b) => saved = b,
        onTrain: () => trained++,
        job: const EmbedderJob(state: 'done', detail: ''),
      ),
    )));
    await _settle(tester);
    expect(find.byKey(const ValueKey('embedder_job')), findsOneWidget);
    await tester.tap(find.text('Read scanned pages (OCR)'));
    await tester.enterText(find.byType(TextField).first, '600');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(saved, isNull);
    expect(find.textContaining('between 1 and 500'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(saved!['ocr_scanned'], true);
    expect(saved!['max_doc_mb'], 80);
    expect(saved!['answer_mode'], 'generate');
    await tester.tap(find.byKey(const ValueKey('train_embedder')));
    expect(trained, 1);
    await tester.pumpWidget(const SizedBox());
  });

  test('a running training job disables nothing it should not, and reads its state', () {
    expect(EmbedderJob.fromJson({'state': 'running'})!.running, isTrue);
    expect(EmbedderJob.fromJson({'status': 'done', 'finished_at': '2026-11-03T10:00:00Z'})!.running, isFalse);
    expect(EmbedderJob.fromJson({}), isNull);
    expect(embedderJobText(const EmbedderJob(state: 'failed', detail: 'oom')), contains('oom'));
  });

  test('learning stats: lora {disabled: true} hides the readiness and flags it', () {
    final off = LearningStats.fromJson({'lora': {'disabled': true}});
    expect(off.loraDisabled, isTrue);
    expect(off.lora, isNull);
    final on = LearningStats.fromJson({
      'lora': {
        'writer': {'ready': 10, 'needed': 300},
      }
    });
    expect(on.loraDisabled, isFalse);
    expect(on.lora, isNotNull);
    expect(learningCodeText('llm_finetune_disabled', ''), contains('switched off'));
  });
}
