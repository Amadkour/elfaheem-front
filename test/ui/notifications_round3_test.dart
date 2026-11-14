// QA round 3: the bell badge reads the server's whole unread count (N11), one "Mark all read" and an icon per
// kind of notification (N12), and the teacher file's initials without a title (M22).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/shared/notification/notifications_screen.dart';
import 'package:flutter_education_app/features/home/student/models.dart' show TeacherProfileData;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

Map<String, dynamic> _row(int id, {bool read = false, String type = 'general', String? related}) => {
      'id': id,
      'title': 't$id',
      'message': 'm$id',
      'type': type,
      'related_type': related,
      'related_id': null,
      'is_read': read,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('N12: an icon per kind, from the type first, then related_type', () {
    expect(notificationKind('session_started', 'session'), NotifKind.live);
    expect(notificationKind('recording_ready', 'session'), NotifKind.recording);
    expect(notificationKind('session_reminder', 'session'), NotifKind.schedule);
    expect(notificationKind('exam_available', 'session'), NotifKind.exam);
    expect(notificationKind('payment_success', 'course'), NotifKind.payment);
    expect(notificationKind('general', 'org_complaint'), NotifKind.complaint);
    expect(notificationKind('general', 'org_announcement'), NotifKind.announcement);
    expect(notificationKind('general', 'org_timetable'), NotifKind.schedule);
    expect(notificationKind('general', 'org_work_item'), NotifKind.request);
    expect(notificationKind('general', 'org_department'), NotifKind.organization);
    expect(notificationKind('meeting', 'meeting'), NotifKind.live);
    expect(notificationKind('material_upload', 'course'), NotifKind.course);
    expect(notificationKind('general', ''), NotifKind.general);
    final icons = {for (final k in NotifKind.values) notificationIcon(k)};
    expect(icons.length, NotifKind.values.length, reason: 'every kind draws its own icon');
  });

  group('N11: the bell badge', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
    });

    test("the server's whole unread count, kept in step with marks; ONE PUT /read-all", () async {
      final fake = FakeApi({
        'GET /api/v1/notifications': (o) => {
              'items': [for (var i = 1; i <= 30; i++) _row(i)],
              'total': 35,
              'unread': 31,
            },
        'PUT /api/v1/notifications/*': (o) => {'message': 'ok'},
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = NotificationsProvider();
      await p.fetchNotifications();
      expect(p.allNotifs.length, 30);
      expect(p.unreadCount, 31, reason: 'not the page count (30)');
      await p.markAsRead('1');
      expect(p.unreadCount, 30);
      fake.reset();
      await p.markAllAsRead();
      expect(p.unreadCount, 0);
      expect(fake.calls.map((c) => c.key).toList(), ['PUT /api/v1/notifications/read-all']);
    });

    test('an older server without `unread`: the loaded rows are counted', () async {
      final fake = FakeApi({
        'GET /api/v1/notifications': (o) => {
              'items': [_row(1), _row(2, read: true), _row(3)],
              'total': 3,
            },
      }, latency: Duration.zero);
      fake.install();
      addTearDown(fake.uninstall);
      final p = NotificationsProvider();
      await p.fetchNotifications();
      expect(p.unreadCount, 2);
    });
  });

  testWidgets('N12: one "Mark all read" bar and typed rows fit every size', (tester) async {
    NotificationModel n(String id, String type, String related) => NotificationModel(
        id: id,
        title: 'بدأت الجلسة: أساسيات الخط العربي للمبتدئين مع المعلم',
        body: 'انضم الآن إلى حصة أساسيات الخط العربي',
        group: NotifGroup.today,
        sourceId: 0,
        type: type,
        relatedType: related);
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        NotificationsMarkAllBar(onPressed: () {}),
        NotificationTile(notif: n('1', 'session_started', 'session')),
        NotificationTile(notif: n('2', 'payment_success', 'course')),
        NotificationTile(notif: n('3', 'general', 'org_complaint')),
      ]),
    );
  });

  test('M22: initials skip a title ("Dr. Omar Hassan" → "OH")', () {
    TeacherProfileData t(String name) => TeacherProfileData(
        id: 1,
        name: name,
        gmail: 'x@y.z',
        role: 'teacher',
        isVerified: true,
        isActive: true,
        loginTimes: 0,
        registrationStep: 'complete',
        createdAt: DateTime.utc(2026));
    expect(t('Dr. Omar Hassan').initials, 'OH');
    expect(t('د. عمر حسن').initials, 'عح');
    expect(t('Mona').initials, 'M');
    expect(t('  ').initials, '?');
    expect(t('Dr.').initials, 'D');
  });
}
