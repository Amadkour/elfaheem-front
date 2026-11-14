// QA sweep fixes in the profile · auth · notifications · org-member area (screenshots/ISSUES.md M2, M10, M23, L2,
// L9, L10): the pure helpers, and the shared primary button's disabled look at every size.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show notOpenEntries;
import 'package:flutter_education_app/features/attendance/teacher_attendance_launcher.dart';
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart' show approvalCountText;
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_screen.dart'
    show NotificationTile, notificationPlainText;
import 'package:flutter_education_app/features/profile/compalints/complaint_model.dart';
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart'
    show complaintCategoryFor, kComplaintKinds;
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _entry(int id, String name, String status) => {
      'organization': {'id': id, 'name': name, 'name_ar': name, 'name_en': name, 'status': status},
    };

void main() {
  setUp(() => AppConfig.lang = 'ar');

  test('L2: Arabic and English plural forms', () {
    expect(arabicPluralForm(1), 'one');
    expect(arabicPluralForm(2), 'two');
    expect(arabicPluralForm(3), 'few');
    expect(arabicPluralForm(10), 'few');
    expect(arabicPluralForm(11), 'many');
    expect(arabicPluralForm(103), 'few');
    expect(daysText(3, lang: 'ar'), '3 أيام');
    expect(daysText(1, lang: 'ar'), 'يوم واحد');
    expect(daysText(14, lang: 'ar'), '14 يومًا');
    expect(daysText(1, lang: 'en'), '1 day');
    expect(daysText(3, lang: 'en'), '3 days');
    expect(approvalCountText('forms', 1, lang: 'ar'), 'طلب واحد ينتظر مراجعتك');
    expect(approvalCountText('forms', 1, lang: 'en'), '1 request waiting for your review');
    expect(approvalCountText('forms', 4, lang: 'ar'), '4 طلبات تنتظر مراجعتك');
    expect(approvalCountText('complaints', 2, lang: 'en'), '2 open complaints in your area');
  });

  test('M2: emoji are stripped from notification text', () {
    expect(notificationPlainText('⏹ انتهت الحصة'), 'انتهت الحصة');
    expect(notificationPlainText('Live 🎥 now'), 'Live now');
    expect(notificationPlainText('plain'), 'plain');
  });

  test('M10: an organization is listed once in the workspace sheet', () {
    final live = [_entry(1, 'NextBrain University', 'approved')];
    final all = [
      ...live,
      _entry(2, 'NextBrain University', 'pending'), // a request for the same university
      _entry(1, 'NextBrain University', 'pending'), // the same id again
      _entry(3, 'Other College', 'pending'),
      _entry(3, 'Other College', 'pending'),
    ];
    final rest = notOpenEntries(all, live);
    expect(rest.length, 1);
    expect((rest.single['organization'] as Map)['id'], 3);
  });

  test('M23: the kind picker leaves who-it-is-about to the target picker', () {
    expect(kComplaintKinds.contains(ComplaintCategory.teacher), isFalse);
    expect(kComplaintKinds.contains(ComplaintCategory.student), isFalse);
    expect(complaintCategoryFor(ComplaintCategory.general, 'teacher'), ComplaintCategory.teacher);
    expect(complaintCategoryFor(ComplaintCategory.general, 'student'), ComplaintCategory.student);
    expect(complaintCategoryFor(ComplaintCategory.payment, 'teacher'), ComplaintCategory.payment);
    expect(complaintCategoryFor(ComplaintCategory.general, 'course'), ComplaintCategory.general);
  });

  test("L9: today's lesson first, then newest first", () {
    final now = DateTime.utc(2026, 10, 30, 9);
    final sessions = [
      LauncherSession(id: 1, number: 1, name: 'one', date: DateTime.utc(2026, 10, 1, 9)),
      LauncherSession(id: 2, number: 2, name: 'two', date: DateTime.utc(2026, 10, 30, 10)),
      LauncherSession(id: 3, number: 3, name: 'three', date: DateTime.utc(2026, 11, 6, 9)),
      const LauncherSession(id: 4, number: 4, name: 'four'),
    ];
    // N13: today's, then upcoming soonest first, then past newest first, then undated.
    expect(launcherOrder(sessions, nowUtc: now).map((s) => s.id).toList(), [2, 3, 1, 4]);
    expect(launcherFocusId(sessions, nowUtc: now), 2, reason: "today's lesson is marked");
    final noToday = [sessions[0], sessions[2], sessions[3],
      LauncherSession(id: 5, number: 5, name: 'five', date: DateTime.utc(2026, 11, 2, 9))];
    expect(launcherOrder(noToday, nowUtc: now).map((s) => s.id).toList(), [5, 3, 1, 4]);
    expect(launcherFocusId(noToday, nowUtc: now), 5, reason: 'else the next one');
    expect(launcherFocusId([sessions[0], sessions[3]], nowUtc: now), isNull, reason: 'only past / undated: no mark');
    expect(launcherIsToday(sessions[1], nowUtc: now), isTrue);
    expect(launcherIsToday(sessions[3], nowUtc: now), isFalse);
  });

  testWidgets('L10: PrimaryButton enabled / disabled / busy fit every size', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          PrimaryButton(isLoading: false, label: 'Save the changes to the account', onPressed: () {}),
          const SizedBox(height: 8),
          const PrimaryButton(isLoading: false, label: 'Save the changes to the account', icon: Icons.send_rounded),
          const SizedBox(height: 8),
          const PrimaryButton(isLoading: true, label: 'Busy'),
        ]),
      ),
    );
  });

  testWidgets('M2: calm notification rows fit every size', (tester) async {
    NotificationModel n(String id, String title, bool read, String icon) => NotificationModel(
        id: id,
        title: title,
        body: 'انضم الآن إلى حصة أساسيات الخط العربي مع المعلم وشاهد التسجيل لاحقاً إن فاتتك',
        group: NotifGroup.today,
        isRead: read,
        iconAsset: icon,
        sourceId: 0);
    await expectNoLayoutErrors(
      tester,
      () => ListView(padding: const EdgeInsets.all(16), children: [
        NotificationTile(notif: n('1', '🎥 بدأت حصة مباشرة في مقرر طويل الاسم جداً للتجربة', false, 'new')),
        NotificationTile(notif: n('2', 'Payment received', true, 'payment')),
      ]),
    );
  });
}
