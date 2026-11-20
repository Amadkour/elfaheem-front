import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/admin/modules/admin_modules_page.dart';
import 'package:flutter_education_app/features/admin/modules/module_settings_api.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

Map<String, dynamic> _payload(String module, String scope, {String key = '', Map<String, dynamic> values = const {}}) {
  final defaults = switch (module) {
    'store' => {'download_daily_limit': 10, 'points_enabled': false, 'teacher_items': false, 'review_required': false},
    'games' => {'points_rewards': false, 'points_daily_cap': 20},
    _ => {'teacher_verification_required': false, 'content_review_required': false, 'gender_matching': 'off', 'self_log': true},
  };
  return {
    'module': module,
    'scope': scope,
    'scope_key': key,
    'values': values,
    'effective': {...defaults, ...values},
    'defaults': defaults,
    'fields': [
      for (final e in defaults.entries)
        {
          'key': e.key,
          'type': e.value is bool ? 'bool' : (e.value is int ? 'int' : 'str'),
          'default': e.value,
          if (e.key == 'gender_matching') 'choices': ['off', 'same', 'prefer'],
        },
    ],
    'rows': [
      {'scope': 'platform', 'scope_key': '', 'values': module == 'store' ? {'teacher_items': true} : <String, dynamic>{}},
      {'scope': 'country', 'scope_key': 'SA', 'values': {'points_enabled': true}},
    ],
  };
}

class _FakeApi extends ModuleSettingsApi {
  const _FakeApi();

  @override
  Future<ModuleResult<ModuleView>> load(String module, String scope, String? scopeKey) async =>
      ModuleResult(ModuleView.from(_payload(module, scope, key: scopeKey ?? '')));

  @override
  Future<ModuleResult<List<ModuleCountry>>> countries() async => const ModuleResult([
        ModuleCountry(code: 'EG', nameAr: 'مصر', nameEn: 'Egypt'),
        ModuleCountry(code: 'SA', nameAr: 'المملكة العربية السعودية', nameEn: 'Saudi Arabia', disabled: ['student_tab_games']),
      ]);
}

void main() {
  test('source and inherited value per scope', () {
    final country = ModuleView.from(_payload('store', 'country', key: 'SA', values: {'points_enabled': true}));
    expect(country.sourceOf('points_enabled', country.values), ModuleSource.here);
    expect(country.sourceOf('teacher_items', country.values), ModuleSource.platform);
    expect(country.inherited('teacher_items'), true);
    expect(country.sourceOf('download_daily_limit', country.values), ModuleSource.defaults);
    expect(country.shown('download_daily_limit', const {}), 10);
    final platform = ModuleView.from(_payload('store', 'platform'));
    expect(platform.overrideCount, 1);
    expect(platform.inherited('teacher_items'), false, reason: 'the platform scope inherits the defaults only');
    expect([for (final f in orderedFields(platform)) f.key],
        ['points_enabled', 'teacher_items', 'review_required', 'download_daily_limit']);
    expect(sameValues({'a': 1}, {'a': 1}), isTrue);
    expect(sameValues({'a': 1}, {}), isFalse);
  });

  for (final module in kModuleKeys) {
    testWidgets('module card $module: no layout errors', (tester) async {
      final view = ModuleView.from(_payload(module, 'country', key: 'SA', values: module == 'quran' ? {'gender_matching': 'same'} : {}));
      await expectNoLayoutErrors(
        tester,
        () => SingleChildScrollView(child: ModuleSettingsCard(view: view, draft: view.values, onChanged: (_) {})),
      );
    });
  }

  testWidgets('country tabs card: no layout errors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: CountryTabsCard(
          countryName: 'المملكة العربية السعودية',
          disabled: const ['student_tab_games', 'other.key'],
          onChanged: (_) {},
        ),
      ),
    );
  });

  testWidgets('the page on the platform scope: no layout errors', (tester) async {
    await expectNoLayoutErrors(tester, () => const AdminModulesPage(api: _FakeApi()));
  });

  testWidgets('the page on a country scope, with its student tabs: no layout errors', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => const AdminModulesPage(api: _FakeApi(), initialCountry: 'SA'),
      act: (tester) async {
        expect(find.byKey(const ValueKey('modules.tab.student_tab_nahw'), skipOffstage: false), findsOneWidget);
      },
    );
  });
}
