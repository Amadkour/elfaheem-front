// The card a tap on an "@name" opens (MentionCardBody, D-075) at 320x640 and 1400x900, Arabic + English, textScaler
// 1.3: a teacher (long name, specialization, courses, "Open profile"), loading, a person without a public page,
// profile links off and a failed load with Retry; plus what each state says and that the buttons call back.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/public_profile/mention_card.dart';
import 'package:flutter_education_app/features/shared/public_profile/public_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/profile_link_test.dart' show teacherJson;
import 'layout_harness.dart';

const longName = 'عبد الرحمن محمد عبد العزيز الشريف Abdulrahman Mohammed Abdulaziz Alsharif';

PublicProfileResult teacher() => PublicProfileResult(
      PublicProfileStatus.found,
      profile: PublicProfile.fromJson(teacherJson()
        ..['name'] = longName
        ..['image_url'] = null
        ..['username'] = 'abdulrahman.mohammed_alsharif'
        ..['courses_count'] = 12),
    );

void main() {
  Future<void> pump(WidgetTester tester, PublicProfileResult? r, {String name = 'sara'}) => expectNoLayoutErrors(
        tester,
        () => MentionCardBody(username: name, result: r, onRetry: () {}, onOpenProfile: () {}),
      );

  testWidgets('teacher', (tester) => pump(tester, teacher(), name: 'abdulrahman.mohammed_alsharif'));
  testWidgets('loading', (tester) => pump(tester, null));
  testWidgets('no public page', (tester) => pump(tester, const PublicProfileResult(PublicProfileStatus.notFound)));
  testWidgets('profile links off', (tester) => pump(tester, const PublicProfileResult(PublicProfileStatus.disabled)));
  testWidgets('failed', (tester) =>
      pump(tester, const PublicProfileResult(PublicProfileStatus.failed, message: 'Network error, try again later')));

  group('content (en)', () {
    late String prev;
    setUp(() {
      prev = AppConfig.lang;
      AppConfig.lang = 'en';
    });
    tearDown(() => AppConfig.lang = prev);

    Future<void> show(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(layoutHost(w, scale: 1));
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('a teacher: name, @username, courses, Open profile calls back', (tester) async {
      var opened = 0;
      await show(tester,
          MentionCardBody(username: '@Abdulrahman.Mohammed_Alsharif', result: teacher(), onOpenProfile: () => opened++));
      expect(find.textContaining(longName), findsOneWidget);
      expect(find.textContaining('@abdulrahman.mohammed_alsharif'), findsOneWidget); // the profile's own spelling
      expect(find.text('12 courses'), findsOneWidget);
      await tester.tap(find.text('Open profile'));
      expect(opened, 1);
    });

    testWidgets('anyone else: the handle and "no public page", no Open profile', (tester) async {
      await show(tester,
          MentionCardBody(username: 'Sara', result: const PublicProfileResult(PublicProfileStatus.notFound), onOpenProfile: () {}));
      expect(find.textContaining('@sara'), findsOneWidget);
      expect(find.text('No public page. Only teachers have one.'), findsOneWidget);
      expect(find.text('Open profile'), findsNothing);
    });

    testWidgets('a failure shows its message and Retry calls back', (tester) async {
      var retried = 0;
      await show(
          tester,
          MentionCardBody(
              username: 'sara',
              result: const PublicProfileResult(PublicProfileStatus.failed, message: 'Offline'),
              onRetry: () => retried++));
      expect(find.text('Offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('links off: says so, no retry', (tester) async {
      await show(tester,
          MentionCardBody(username: 'sara', result: const PublicProfileResult(PublicProfileStatus.disabled), onRetry: () {}));
      expect(find.text('Profile links are off right now.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });
  });
}
