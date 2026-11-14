// Removing a picture (D-880): the "Remove picture" choice of the picker sheet asks first and only then calls the
// remover; it is offered only while a picture is shown; the reel controller deletes the stored reel at once and reads
// it back for the form; and what is drawn instead (the initial avatar, the default course cover) has no broken image.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_widgets.dart';
import 'package:flutter_education_app/features/courses/course_space/course_space_parts.dart';
import 'package:flutter_education_app/features/courses/teacher/course_reel_field.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
  });
  setUp(() => AppConfig.lang = 'en');

  Widget picker({String? url, required List<String> log, String? name}) => EditableImage(
        onChange: (_) async => log.add('change'),
        imageUrl: url,
        size: 120,
        isCircle: name != null,
        name: name,
        onRemove: () async => log.add('remove'),
        removeMessage: 'Remove the course cover? Course cards will show the default cover.',
      );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(EditableImage).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('EditableImage: Remove picture', () {
    testWidgets('asks with the given sentence, then removes', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(layoutHost(picker(url: 'https://cdn.test/c.png', log: log)));
      await openSheet(tester);
      expect(find.byKey(const ValueKey('image_remove')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('image_remove')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Remove the course cover? Course cards will show the default cover.'), findsOneWidget);
      expect(log, isEmpty, reason: 'nothing is removed before the confirm');
      await tester.tap(find.descendant(of: find.byType(AppConfirmDialog), matching: find.text('Remove')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(log, ['remove']);
    });

    testWidgets('cancelling the confirm keeps the picture', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(layoutHost(picker(url: 'https://cdn.test/c.png', log: log)));
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('image_remove')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final dialog = find.byType(AppConfirmDialog);
      expect(dialog, findsOneWidget);
      await tester.tap(find.descendant(of: dialog, matching: find.text('exam_cancel'.tr)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(log, isEmpty);
    });

    testWidgets('no picture: no Remove (the initial avatar, nothing to remove)', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(layoutHost(picker(log: log, name: 'Sara')));
      expect(find.text('S'), findsOneWidget);
      await openSheet(tester);
      expect(find.text('From the gallery'), findsOneWidget);
      expect(find.byKey(const ValueKey('image_remove')), findsNothing);
    });

    testWidgets('the sheet and the confirm fit every size, both languages', (tester) async {
      await expectNoLayoutErrors(tester, () => const ImageSourceSheet(canRemove: true));
      await expectNoLayoutErrors(
          tester,
          () => AppConfirmDialog(
              message: AppConfig.lang == 'ar'
                  ? 'إزالة العرض الأولي للكورس؟ ستعرض صفحة الكورس الغلاف بدلاً منه، دون معاينة.'
                  : 'Remove the course reel? The course page will show the cover instead, with no preview to watch.',
              danger: true,
              confirmLabel: AppConfig.lang == 'ar' ? 'حذف' : 'Remove'));
    });
  });

  group('fallbacks: no picture, no broken image', () {
    testWidgets('chat avatar without a url draws the initial', (tester) async {
      await tester.pumpWidget(layoutHost(const ChatAvatar(name: 'Omar', url: null)));
      expect(find.text('O'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(layoutHost(const ChatAvatar(name: 'Omar', url: '')));
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('course hero cover without an image is the default plate', (tester) async {
      await tester.pumpWidget(layoutHost(const SizedBox(width: 320, height: 200, child: CourseCover(imageUrl: ''))));
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.auto_stories_rounded), findsOneWidget);
      await expectNoLayoutErrors(tester, () => const SizedBox(height: 200, child: CourseCover(imageUrl: '')));
    });
  });

  group('CourseReelController', () {
    Future<FakeApi> backend(Map<String, FakeHandler> routes) async {
      final api = FakeApi(routes, latency: const Duration(milliseconds: 1))..install();
      addTearDown(api.uninstall);
      await ApiClient().primeSession();
      return api;
    }

    test('loads the stored reel of the course being edited', () async {
      await backend({'GET /api/v1/courses/5': (_) => {'id': 5, 'reel_url': 'https://cdn.test/r.mp4'}});
      final c = CourseReelController(courseId: 5);
      await c.loadExisting();
      expect(c.existingUrl, 'https://cdn.test/r.mp4');
    });

    test('removeNow deletes it at once and shows none', () async {
      final api = await backend({'DELETE /api/v1/courses/5/reel': (_) => {'course_id': 5, 'reel_url': null}});
      final c = CourseReelController(courseId: 5, initialUrl: 'https://cdn.test/r.mp4');
      await c.removeNow();
      expect(api.calls.map((x) => '${x.method} ${x.path}'), ['DELETE /api/v1/courses/5/reel']);
      expect(c.existingUrl, isNull);
      expect(c.hasChanges, isFalse, reason: 'nothing left for the save');
    });

    test('a new course has no id: Remove only marks it for the save', () async {
      final c = CourseReelController(initialUrl: 'https://cdn.test/r.mp4');
      await c.removeNow();
      expect(c.removeRequested, isTrue);
      expect(c.existingUrl, isNull);
    });
  });
}
