// Kill-switch drift guard: every feature key the app checks must be in the backend's feature catalog
// (`test/contract/feature_keys.json`, written by ../back/scripts/contract/export_api_paths.py --front), otherwise the
// super admin's Features page never lists it and nobody can switch it off. 30 keys had slipped through before this
// test (profile.mfa, profile.downloads, rag.assistant, data_lab.entry …).
//
// Scanned in lib/: `featureKey: '…'`, `ParentComponent(key: [const] ValueKey('…')`, `disableList.contains('…')`, string
// constants named `k…Feature` / `k…FeatureKey` / `…FeatureKey`, and AppConfig.orgEntryKeys. Keys built at run time
// (`'student_tab_${e.label}'`) are not checked.
//
// When the app gets a new key: add it to `_BASE_FEATURES` in ../back/services/feature_catalog.py and regenerate the
// snapshot. A key that must stay out of the catalog ON PURPOSE goes in [notInCatalog] with the reason.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

const notInCatalog = <String, String>{
  'calendar.recurring': 'lands with feature/lh2-cal',
  // Learning Hub v2 games (CONTRACT §3 + C9): the catalog entries land with the server half
  'admin.games': 'lands with feature/lh2-learn',
  'games.leaderboard': 'lands with feature/lh2-learn',
  // self-learning (Learning Hub v2 §5): the catalog entries come with the back's branch
  'admin.self_learning': 'lands with feature/lh2-learn',
  'student_tab_self_learning': 'lands with feature/lh2-learn',
  // Learning Hub v2 teachers and packages (CONTRACT.md §1 / §2): the back stream adds them to feature_catalog.py
  'teacher_onboarding': 'lands with feature/lh2-core',
  'teacher_discovery': 'lands with feature/lh2-core',
  'packages': 'lands with feature/lh2-core',
};

final _patterns = [
  RegExp(r"featureKey:\s*'([^'$]+)'"),
  // the widget key is the feature key only when the call has no featureKey: (which wins)
  RegExp(r"ParentComponent\(\s*key:\s*(?:const\s+)?ValueKey\('([^'$]+)'\)(?![^\n]*featureKey:)"),
  RegExp(r"disableList\.contains\('([^'$]+)'\)"),
  RegExp(r"(?:k\w*Feature|\w*FeatureKey)\s*=\s*'([^'$]+)'"),
];

/// Every literal feature key in [sources] (file path → Dart source) → the files that use it.
Map<String, Set<String>> scanFeatureKeys(Map<String, String> sources) {
  final out = <String, Set<String>>{};
  for (final e in sources.entries) {
    final code = e.value.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    for (final rx in _patterns) {
      for (final m in rx.allMatches(code)) {
        out.putIfAbsent(m.group(1)!, () => {}).add(e.key);
      }
    }
  }
  return out;
}

void main() {
  test('the scan finds every way the app names a feature key', () {
    final keys = scanFeatureKeys({
      'a.dart': "ParentComponent(featureKey: 'a.one', child: x); const ParentComponent(key: ValueKey('a.two'), child: y);\n"
          "ParentComponent(key: const ValueKey('tab'), featureKey: 'a.six', child: z)\n/// `ParentComponent(key: ValueKey('doc'))`",
      'b.dart': "if (AppConfig.disableList.contains('b.three')) {} const String kThingFeature = 'b.four'; "
          "const appAssistantFeatureKey = 'b.five'; featureKey: 'student_tab_\${e.label}'",
    });
    expect(keys.keys.toSet(), {'a.one', 'a.two', 'a.six', 'b.three', 'b.four', 'b.five'});
  });

  test('every feature key the app checks is in the backend catalog', () {
    final catalog = (jsonDecode(File('test/contract/feature_keys.json').readAsStringSync()) as List).cast<String>().toSet();
    expect(catalog.length, greaterThan(250), reason: 'snapshot from the export script');
    final sources = {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')))
        f.path.replaceAll(r'\', '/'): f.readAsStringSync(),
    };
    final used = scanFeatureKeys(sources);
    for (final k in AppConfig.orgEntryKeys) {
      used.putIfAbsent(k, () => {}).add('AppConfig.orgEntryKeys');
    }
    final missing = {
      for (final e in used.entries)
        if (!catalog.contains(e.key) && !notInCatalog.containsKey(e.key)) e.key: e.value,
    };
    expect(missing, isEmpty,
        reason: 'feature keys the super admin cannot switch: add them to ../back/services/feature_catalog.py and run '
            '`python scripts/contract/export_api_paths.py --front ../nextbrain-front` there:\n'
            '${missing.entries.map((e) => '  ${e.key}  (${e.value.join(', ')})').join('\n')}');
    final stale = notInCatalog.keys.where((k) => catalog.contains(k) || !used.containsKey(k)).toList();
    expect(stale, isEmpty, reason: 'notInCatalog entries no longer needed');
  });
}
