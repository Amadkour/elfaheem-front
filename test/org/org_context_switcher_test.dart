// Phase 3 — the Personal / Organizations switcher sits at the top for everyone: with no membership yet it still
// opens and offers "join another organization"; organizations under review are listed but not enterable.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/design/context_switcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/layout_harness.dart';

Widget _themed(Widget app) => ThemeConfigScope(provider: ThemeConfigProvider(api: ApiClient()), child: app);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: Center(child: ContextSwitcher())))));
  await tester.pump();
  expect(find.byKey(const ValueKey('ctx.pill')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('ctx.pill')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppConfig.orgsEnabled = true;
    AppConfig.disableList = const [];
    AppModeController.applyContext = (_) {};
  });

  testWidgets('no membership: the pill is shown and the sheet offers to join', (tester) async {
    AppModeController.instance.debugSet({'items': []}, mode: AppMode.individual);
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('ctx.sheet.empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx.sheet.join')), findsOneWidget);
  });

  testWidgets('a pending organization is listed, not enterable; live ones are', (tester) async {
    AppModeController.instance.debugSet({
      'items': [
        {'organization': {'id': 4, 'status': 'approved', 'name_en': 'Uni'}, 'manage': null},
        {'organization': {'id': 9, 'status': 'pending', 'name_en': 'Institute'}, 'manage': null},
      ],
      'default_org_id': 4,
    }, mode: AppMode.individual);
    await _openSheet(tester);
    expect(find.byKey(const ValueKey('ctx.sheet.org.4')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx.sheet.pending.9')), findsOneWidget);
    expect(find.byKey(const ValueKey('ctx.sheet.org.9')), findsNothing);
    expect(find.byKey(const ValueKey('ctx.sheet.join')), findsOneWidget);
  });

  testWidgets('the platform kill-switch still hides it', (tester) async {
    AppConfig.disableList = const ['home.org_tab'];
    AppModeController.instance.debugSet({'items': []}, mode: AppMode.individual);
    await tester.pumpWidget(_themed(const MaterialApp(home: Scaffold(body: ContextSwitcher()))));
    await tester.pump();
    expect(find.byKey(const ValueKey('ctx.pill')), findsNothing);
  });

  testWidgets('switcher layout holds on every size and language', (tester) async {
    AppModeController.instance.debugSet({
      'items': [
        {'organization': {'id': 4, 'status': 'approved', 'name_en': 'A very long organization name indeed', 'name_ar': 'اسم مؤسسة طويل جداً'}, 'manage': null},
      ],
      'default_org_id': 4,
    }, mode: AppMode.organization, orgId: 4);
    await expectNoLayoutErrors(tester, () => _themed(const ContextSwitcher()), scaffold: true);
  });

  test('coded auth errors have text in both languages, with the server\'s numbers', () {
    ApiException ex(String code, Map<String, dynamic> extra, {int status = 400}) => ApiException(
          statusCode: status,
          message: 'server text',
          type: status == 429 ? ApiErrorType.rateLimited : ApiErrorType.badRequest,
          code: code,
          body: {'detail': {'code': code, 'message': 'server text', ...extra}},
        );
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      expect(apiErrorText(ex('too_many_attempts', {'retry_after_minutes': 15}, status: 429)), contains('15'));
      expect(apiErrorText(ex('otp_cooldown', {'retry_after_seconds': 30}, status: 429)), contains('30'));
      expect(apiErrorText(ex('otp_invalid', {'attempts_left': 3})), contains('3'));
      expect(apiErrorText(ex('otp_locked', {})), isNot('server text'));
      expect(apiErrorText(ex('refresh_reuse', {}, status: 401)), isNot('server text'));
      expect(apiErrorText(ex('self_action', {}, status: 403)), isNot('server text'));
      expect(apiErrorText(ex('escalation', {}, status: 403)), isNot('server text'));
      expect(apiErrorText(ex('some_new_code', {})), 'server text');
    }
    expect(apiRetryAfter(ex('too_many_attempts', {'retry_after_minutes': 2})), const Duration(minutes: 2));
    expect(apiRetryAfter(ex('otp_invalid', {})), isNull);
  });
}
