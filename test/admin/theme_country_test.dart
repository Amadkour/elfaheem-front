// The country layer of the disable list reaches a guest (6.R #6, D-1341): signed out, the theme request carries the
// country the course filter bar remembered; signed in, it carries none (the server reads the study profile).
import 'dart:convert';

import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a guest sends the remembered country; a signed-in user sends none', () async {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    final api = FakeApi({'GET /api/v1/theme/*': (_) => <String, dynamic>{'colors': <String, dynamic>{}, 'disable_list': []}},
        latency: Duration.zero);
    api.install();
    addTearDown(api.uninstall);

    // nothing remembered: no country
    expect((await ThemeConfigProvider.requestScope()).query, isNull);

    await CourseFilterStore.save('guest', const CourseFilters(country: 'eg'));
    final guest = await ThemeConfigProvider.requestScope();
    expect(guest.user, 'guest');
    expect(guest.query, {'country': 'EG'});

    final theme = ThemeConfigProvider(api: ApiClient());
    await theme.silentRefresh();
    final call = api.calls.lastWhere((c) => c.path.startsWith('/api/v1/theme/'));
    expect(call.query['country'], 'EG');

    // signed in: the account's own flags, no country; the account change fetches the theme again
    await (await StorageService.getInstance()).saveUser({'id': 34, 'role': 'student'});
    expect((await ThemeConfigProvider.requestScope()).query, isNull);
    final before = api.calls.length;
    await ThemeConfigProvider.accountChanged();
    final again = api.calls.sublist(before).where((c) => c.path.startsWith('/api/v1/theme/')).toList();
    expect(again, hasLength(1));
    expect(again.single.query.containsKey('country'), isFalse);

    // the same account again: no request
    final n = api.calls.length;
    await ThemeConfigProvider.accountChanged();
    expect(api.calls.length, n);
    expect(jsonEncode(again.single.query), '{}');
  });
}
