// VISUAL review renders of the S-D screens (redesign phase 2): the student's account page, the store, the teachers
// list, Nahw, the parent link code and the rewards, with the CAST.md demo data, at 390x844 and 1360x900, Arabic and
// English, light, Reduce motion ON. Into test/visual/redesign/sd/goldens/; compared by eye with
// D:/platform/redesign-ref/ref/student/*Stu2*.
//
//   flutter test test/visual/redesign/sd/sd_screens_golden_test.dart --update-goldens [--plain-name store]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/courses/course_filters.dart';
import 'package:flutter_education_app/features/nahw/nahw_models.dart';
import 'package:flutter_education_app/features/nahw/nahw_tab.dart';
import 'package:flutter_education_app/features/parent/student_link_code_screen.dart';
import 'package:flutter_education_app/features/profile/sd_area.dart';
import 'package:flutter_education_app/features/profile/student_profile_view.dart';
import 'package:flutter_education_app/features/rewards/my_rewards_page.dart';
import 'package:flutter_education_app/features/rewards/rewards_models.dart';
import 'package:flutter_education_app/features/store/store_models.dart';
import 'package:flutter_education_app/features/store/store_item_page.dart';
import 'package:flutter_education_app/features/payments/enrollment/enrollment_widgets.dart' show PaymentResultView, ResultKind;
import 'package:flutter_education_app/features/store/store_tab.dart';
import 'package:flutter_education_app/features/teachers/teacher_discovery.dart';
import 'package:flutter_education_app/features/teachers/teachers_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../kit_golden_harness.dart';
import 'sd_demo.dart';

Widget _row(IconData icon, String ar, String en, {String? subAr, String? subEn, AppAccent? accent}) {
  final tile = AppSettingsTile(icon: icon, label: sdT(ar, en), subtitle: subAr == null ? null : sdT(subAr, subEn!), onTap: () {});
  return accent == null ? tile : SdAccentRow(accent: accent, child: tile);
}

StoreItem _item(int id, String kind, String ar, String en, num gross, int points, int pages) => StoreItem.fromJson({
      'id': id,
      'kind': kind,
      'title_ar': ar,
      'title_en': en,
      'price': {'net': gross, 'vat': 0, 'gross': gross, 'currency': 'SAR'},
      'points_price': points,
      'pages': pages,
    });

void main() {
  late StorageService storage;
  setUpAll(() async => storage = await kitGoldenSetUp());

  testWidgets('profile', (tester) async {
    await kitRender(
      tester,
      'sd_profile',
      () => SdArea(
        area: AppArea.me,
        child: StudentProfileView(
          hero: StudentProfileHero(name: sdT('فيصل العنزي', 'Faisal Alanazi'), username: 'faisal.alanazi', onEdit: () {}),
          shortcuts: [
            SdShortcut(id: 'g', accent: AppAccent.sun, icon: Icons.workspace_premium_outlined, title: sdT('درجاتي وشهاداتي', 'Marks and certificates'), meta: sdT('شهادتين، ١٨ درجة', '2 certificates, 18 marks'), onTap: () {}),
            SdShortcut(id: 'w', accent: AppAccent.mint, icon: Icons.account_balance_wallet_outlined, title: sdT('محفظتي', 'My wallet'), meta: sdT('١٬٢٤٠ نقطة', '1,240 points'), onTap: () {}),
            SdShortcut(id: 'p', accent: AppAccent.sky, icon: Icons.receipt_long_outlined, title: sdT('المدفوعات', 'Payments'), meta: sdT('آخر دفعة ٢٤ نوفمبر', 'Last paid 24 Nov'), onTap: () {}),
            SdShortcut(id: 'f', accent: AppAccent.pink, icon: Icons.favorite_border_rounded, title: sdT('المفضلة', 'Favourites'), meta: sdT('٧ دورات ومعلمين', '7 courses and teachers'), onTap: () {}),
          ],
          menuA: [
            _row(Icons.public_rounded, 'ملفي العام', 'My public profile', accent: AppAccent.sky),
            _row(Icons.download_rounded, 'التحميلات', 'Downloads', subAr: '١٢ درس على جوالك', subEn: '12 lessons on your phone', accent: AppAccent.mint),
            _row(Icons.card_giftcard_rounded, 'مكافآتي', 'My rewards', accent: AppAccent.sun),
            _row(Icons.link_rounded, 'ربط ولي الأمر', 'Link a parent', subAr: 'أبوك وأمك مربوطين', subEn: 'Both parents linked', accent: AppAccent.grape),
          ],
          menuB: [
            _row(Icons.notifications_none_rounded, 'الإشعارات', 'Notifications', subAr: 'الحصص والاختبارات والرسائل', subEn: 'Classes, exams and messages', accent: AppAccent.pink),
            _row(Icons.text_fields_rounded, 'العرض والقراءة', 'Display and reading', accent: AppAccent.sky),
            _row(Icons.verified_user_outlined, 'الأمان والأجهزة', 'Security and devices', accent: AppAccent.mint),
            _row(Icons.support_agent_rounded, 'المساعدة والدعم', 'Help and support', accent: AppAccent.pink),
          ],
          advanced: [_row(Icons.school_outlined, 'بياناتي الدراسية', 'Study details'), _row(Icons.translate_rounded, 'اللغة', 'Language')],
          exits: [AppSettingsTile(icon: Icons.logout_rounded, label: sdT('تسجيل الخروج', 'Sign out'), danger: true, onTap: () {})],
        ),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('store', (tester) async {
    final items = [
      _item(1, 'summary', 'ملخص الرياضيات ٢ ث، الفصل الأول', 'Maths 2 summary, first term', 45, 450, 86),
      _item(2, 'notes', 'مذكرة الفيزياء: الحركة والقوى', 'Physics notes: motion and forces', 60, 600, 120),
      _item(3, 'ebook', 'كتاب القدرات الكمي', 'Quantitative aptitude book', 89, 890, 240),
      _item(4, 'ebook', 'English grammar in use', 'English grammar in use', 70, 700, 180),
    ];
    await kitRender(
      tester,
      'sd_store',
      () => SdArea(
        area: AppArea.store,
        child: StoreBrowseView(
          filters: CourseFilters.empty,
          onFilters: (_) {},
          items: items,
          total: 8,
          categories: [(id: 1, name: sdT('ملخصات', 'Summaries')), (id: 2, name: sdT('مذكرات', 'Notes')), (id: 3, name: sdT('كتب', 'Books'))],
          cartIds: const {1},
          cartCount: 1,
          onAdd: (_) {},
          onOpen: (_) {},
        ),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('teachers', (tester) async {
    TeacherProfile tp(int id, String ar, String en, String g, List<String> subs, List<String> del, double r, int n) => TeacherProfile.fromJson({
          'user_id': id,
          'name': sdT(ar, en),
          'gender': g,
          'subjects': subs,
          'delivery': del,
          'session_types': ['group', 'individual'],
          'rating': r,
          'reviews_count': n,
        });
    await kitRender(
      tester,
      'sd_teachers',
      () => SdArea(
        area: AppArea.learn,
        child: TeachersBrowseView(
          filters: TeacherFilters.none,
          onFilters: (_) {},
          total: 3,
          items: [
            tp(1, 'أ. ماجد الشهري', 'Mr Majed Alshehri', 'male', ['quran', 'tajweed'], ['online'], 4.9, 213),
            tp(2, 'أ. فهد المطيري', 'Mr Fahad Almutairi', 'male', ['fiqh'], ['online', 'offline'], 4.8, 140),
            tp(3, 'أ. خالد العتيبي', 'Mr Khalid Alotaibi', 'male', ['nahw'], ['online'], 5.0, 98),
          ],
        ),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('nahw', (tester) async {
    NahwLessonRef l(int id, String ar, String en, {int? best, bool done = false}) => NahwLessonRef(
        id: id,
        levelId: 1,
        titleAr: ar,
        titleEn: en,
        progress: best == null ? null : NahwProgress(lessonId: id, bestScore: best, maxScore: 10, completed: done));
    await kitRender(
      tester,
      'sd_nahw',
      () => SdArea(
        area: AppArea.nahw,
        child: NahwLevelsView(
          hero: true,
          mine: true,
          onMine: (_) {},
          onOpen: (_) {},
          levels: [
            NahwLevel(id: 1, key: 'b', titleAr: 'المبتدئ', titleEn: 'Beginner', total: 5, completed: 3, lessons: [
              l(1, 'الكلمة وأقسامها', 'The word and its kinds', best: 10, done: true),
              l(2, 'الجملة الاسمية', 'The nominal sentence', best: 9, done: true),
              l(3, 'الجملة الفعلية', 'The verbal sentence', best: 8, done: true),
              l(4, 'الفاعل', 'The subject'),
              l(5, 'المفعول به', 'The object'),
            ]),
          ],
        ),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('parent link', (tester) async {
    await kitRender(
      tester,
      'sd_parent_link',
      () => SdArea(
        area: AppArea.me,
        child: StudentLinkCodeView(
          code: '482071',
          secondsLeft: 9 * 60 + 42,
          parents: [(id: 1, name: sdT('سعد العنزي', 'Saad Alanazi')), (id: 2, name: sdT('نوال الشمري', 'Nawal Alshammari'))],
          onGenerate: () {},
          onShare: () {},
          onCopy: () {},
          onUnlink: (_) {},
        ),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('rewards', (tester) async {
    final data = MyRewards.fromJson({
      'coupons': [
        {'id': 1, 'code': 'CHAMP15', 'kind': 'percent', 'value': 15, 'applies_to': 'any', 'source': 'champion', 'expires_at': sdIso(DateTime.utc(2026, 11, 30))},
        {'id': 2, 'code': 'FRIEND50', 'kind': 'amount', 'value': 50, 'currency': 'SAR', 'applies_to': 'store', 'source': 'referral', 'expires_at': sdIso(DateTime.utc(2026, 12, 15))},
      ],
    });
    await kitRender(
      tester,
      'sd_rewards',
      () => SdArea(
        area: AppArea.money,
        child: MyRewardsView(data: data, tab: 0, now: sdNow, fixedClock: true, onUse: (_) {}),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  testWidgets('store item', (tester) async {
    await kitRender(
      tester,
      'sd_store_item',
      () => SdArea(
        area: AppArea.store,
        child: StoreItemView(item: _item(1, 'summary', 'ملخص الرياضيات ٢ ث، الفصل الأول', 'Maths 2 summary, first term', 45, 450, 86), inCart: true, onBuy: () {}, onToggleCart: () {}),
      ),
      storage: storage,
      modes: const [false],
    );
  });

  for (final kind in ResultKind.values) {
    testWidgets('payment result ${kind.name}', (tester) async {
      await kitRender(
        tester,
        'sd_pay_${kind.name}',
        () => SdArea(
          area: AppArea.money,
          child: PaymentResultView(
            kind: kind,
            title: sdT(['الدورة صارت لك', 'نراجع التحويل', 'ما اكتمل الدفع'][kind.index], ['The course is yours', 'We are checking the transfer', 'The payment did not go through'][kind.index]),
            message: sdT('الرياضيات ٢ ث مع أ. ماجد الشهري', 'Maths 2 with Mr Majed Alshehri'),
            primaryLabel: sdT(['ابدأ التعلّم', 'تمام', 'جرّب مرة ثانية'][kind.index], ['Start learning', 'OK', 'Try again'][kind.index]),
            onPrimary: () {},
            secondaryLabel: kind == ResultKind.failed ? sdT('الرئيسية', 'Home') : null,
            onSecondary: () {},
          ),
        ),
        storage: storage,
        modes: const [false],
        grow: false,
        langs: const ['ar'],
      );
    });
  }
}
