// The platform complaint form (Warm Editorial: sky hero block, paper section cards, pickers, attachments,
// suggested solution) on every screen size, both languages, text × 1.3. The form only: no request is made until
// it is sent.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    AppConfig.lang = 'en';
    SharedPreferences.setMockInitialValues({});
    storage = await StorageService.getInstance();
  });

  Widget form({String? course}) => MultiProvider(
        providers: [
          ChangeNotifierProvider<LangProvider>(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider<ComplaintProvider>(create: (_) => ComplaintProvider()),
        ],
        child: NewComplaintScreen(formOnly: true, courseTitle: course),
      );

  testWidgets('the complaint form never overflows', (tester) async {
    await expectNoLayoutErrors(tester, form, scaffold: false);
  });

  testWidgets('the form about a course, the suggested solution open', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => form(course: 'Organic chemistry for the final year, part two (revision and past papers)'),
      scaffold: false,
      act: (tester) async {
        final toggle = find.text('suggested_solution_label'.tr);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump(const Duration(milliseconds: 400));
      },
    );
  });
}
