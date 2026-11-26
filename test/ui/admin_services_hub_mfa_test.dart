// The admin "Support & security" group offers two-step verification (A07's AdminMfaPage): the tile is there, in
// both languages, opens the page, and the hub lays out on every screen size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/admin/admin_mfa_page.dart';
import 'package:flutter_education_app/features/admin/admin_providers.dart' show AdminPendingPayoutsProvider;
import 'package:flutter_education_app/features/admin/admin_services_hub.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
    AppConfig.lang = 'ar';
  });

  Widget withProviders(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => MyAuthProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider(create: (_) => AdminPendingPayoutsProvider()),
          ChangeNotifierProvider(create: (_) => TeacherTransfersProvider()),
          ChangeNotifierProvider(create: (_) => ComplaintProvider()),
        ],
        child: child,
      );

  Widget hub() => withProviders(const AdminServicesHub(groupId: 'support'));

  testWidgets('support group lists the MFA tile in both languages', (tester) async {
    for (final lang in ['ar', 'en']) {
      AppConfig.lang = lang;
      await tester.pumpWidget(layoutHost(hub(), scale: 1));
      await tester.pump();
      expect(find.text(mfaEntryLabel()), findsOneWidget, reason: lang);
    }
    AppConfig.lang = 'en';
    expect(mfaEntryLabel(), 'Two-step verification');
  });

  testWidgets('the tile opens the MFA page', (tester) async {
    AppConfig.lang = 'en';
    // Providers above the navigator, as in the app (the pushed page reads MyAuthProvider).
    await tester.pumpWidget(withProviders(layoutHost(const AdminServicesHub(groupId: 'support'), scale: 1)));
    await tester.pump();
    await tester.ensureVisible(find.text(mfaEntryLabel()));
    await tester.pump();
    await tester.tap(find.text(mfaEntryLabel()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AdminMfaPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('support hub with the MFA tile: no overflow on any screen size', (tester) async {
    await expectNoLayoutErrors(tester, hub);
  });
}
