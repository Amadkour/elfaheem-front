// Review renders of the S-A2 bodies (categories, journey, recommendations, guest search, guest live, legal) with the
// CAST demo data (Faisal, الثاني ثانوي; maths with أ. ماجد الشهري), 390x844 and 1360x900, next to
// D:/platform/redesign-ref/ref/student/003_*, 030_* … 040_*. Not a CI suite.
//
//   flutter test test/visual/redesign/sa2 --update-goldens [--plain-name categories]
@Tags(['visual'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/courses/category/categories_provider.dart';
import 'package:flutter_education_app/features/courses/category/categories_screen.dart';
import 'package:flutter_education_app/features/courses/roadmap/journey_page.dart';
import 'package:flutter_education_app/features/courses/roadmap/recommendations.dart';
import 'package:flutter_education_app/features/courses/roadmap/roadmap_api.dart';
import 'package:flutter_education_app/features/onboarding/guest_search_screen.dart';
import 'package:flutter_education_app/features/onboarding/landing_api.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart';
import 'package:flutter_education_app/core/edu/edu_countries.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppArea, AppCard;
import 'package:flutter_education_app/features/profile/study_profile/study_profile_form.dart';
import 'package:flutter_education_app/features/profile/study_profile/study_profile_model.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/guest/guest_live_page.dart';
import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'package:flutter_education_app/features/live/live_room.dart' show LiveRoomKind;
import 'package:flutter_education_app/features/profile/about/about_and_terms_screen.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../../support/fake_api.dart';
import '../kit_golden_harness.dart';

late StorageService _storage;

const _light = [false];

List<Map<String, dynamic>> _mathCourses() => [
      for (final (id, ar, teacher, lessons, price) in const [
        (1, 'الرياضيات ٢ ثانوي، الفصل الأول', 'أ. ماجد الشهري', 24, 199),
        (2, 'التفاضل والتكامل للمبتدئين', 'أ. عبدالله الغامدي', 16, 179),
        (3, 'مراجعة نهائية: الرياضيات ٢', 'أ. ماجد الشهري', 8, 99),
        (4, 'الهندسة التحليلية', 'أ. سلمان الحربي', 12, 169),
      ])
        {
          'id': id,
          'name': ar,
          'name_ar': ar,
          'name_en': ar,
          'teacher': {'id': id, 'name': teacher},
          'materials_total': lessons,
          'category_id': 1,
          'image_url': '',
          'fees': price,
          'final_price': price,
          'rating': 4.8,
          'teacher_name': teacher,
          'lectures_count': lessons,
        },
    ];

Journey _journey() {
  Map<String, dynamic> step(int id, String ar, String en, String teacher, String state, double progress, {bool current = false}) => {
        'id': id,
        'name_ar': ar,
        'name_en': en,
        'teacher': {'name': teacher},
        'state': state,
        'progress': progress,
        'current': current,
      };
  final steps = [
    step(1, 'الرياضيات: الدوال', 'Maths: functions', 'أ. ماجد الشهري', 'completed', 100),
    step(2, 'الكيمياء: أساسيات المادة', 'Chemistry: basics', 'أ. ماهر السبيعي', 'completed', 100),
    step(3, 'الفيزياء: قوانين نيوتن', "Physics: Newton's laws", 'أ. فهد المطيري', 'in_progress', 64, current: true),
    step(4, 'الأحياء: الخلية', 'Biology: the cell', 'أ. فهد العتيبي', 'not_started', 0),
    step(5, 'القدرات: الكمي', 'Qudurat: quantitative', 'أ. خالد المطيري', 'not_started', 0),
    step(6, 'اختبار تجريبي للتحصيلي', 'Tahsili mock exam', 'أ. ماجد الشهري', 'not_started', 0),
  ];
  return Journey.fromJson({
    'source': 'roadmap',
    'field': {'id': 9, 'name_ar': 'التحصيلي', 'name_en': 'Tahsili'},
    'next': {...steps[2], 'kind': 'continue'},
    'done': 2,
    'total': 6,
    'steps': steps,
  })!;
}

Map<String, dynamic> _recs() => {
      'total': 5,
      'items': [
        for (final (id, ar, en, teacher, field, price, reason) in const [
          (11, 'القدرات الكمي: تأسيس كامل', 'Qudurat quantitative: the basics', 'أ. خالد المطيري', 'القدرات', 249, 'لأنك تبي القدرات'),
          (12, 'الفيزياء: الكهرباء والمغناطيسية', 'Physics: electricity and magnetism', 'أ. فهد المطيري', 'الفيزياء', 199, 'بعد دورتك الحالية'),
          (13, 'البرمجة بلغة Python للمبتدئين', 'Python for beginners', 'أ. ريان الحربي', 'البرمجة', 149, 'من اهتماماتك'),
          (14, 'الأحياء: الخلية والوراثة', 'Biology: cells and genetics', 'أ. فهد العتيبي', 'الأحياء', 179, 'ضمن مسارك'),
          (15, 'لغتي: الكتابة الإبداعية', 'Arabic: creative writing', 'أ. ناصر الشمري', 'لغتي', 129, 'يناسب صفّك'),
        ])
          {
            'reason': 'matches_interest',
            'reason_ar': reason,
            'reason_en': 'Picked for you',
            'course': {
              'id': id,
              'name_ar': ar,
              'name_en': en,
              'teacher': {'name': teacher},
              'category': {'id': id, 'name_ar': field, 'name_en': field},
              'final_price': price,
              'currency': 'SAR',
            },
          },
      ],
    };

const _subjects = [
  LandingSubject(id: 1, nameAr: 'الرياضيات', nameEn: 'Mathematics', courses: 24, levels: [
    LandingLevel(id: 11, nameAr: 'الثاني ثانوي', nameEn: 'Grade 11'),
    LandingLevel(id: 12, nameAr: 'الثالث ثانوي', nameEn: 'Grade 12'),
  ]),
  LandingSubject(id: 2, nameAr: 'الفيزياء', nameEn: 'Physics'),
  LandingSubject(id: 3, nameAr: 'الإنجليزي', nameEn: 'English'),
  LandingSubject(id: 4, nameAr: 'الكيمياء', nameEn: 'Chemistry'),
  LandingSubject(id: 5, nameAr: 'الأحياء', nameEn: 'Biology'),
  LandingSubject(id: 6, nameAr: 'القدرات', nameEn: 'Qudurat'),
  LandingSubject(id: 7, nameAr: 'البرمجة', nameEn: 'Coding'),
  LandingSubject(id: 8, nameAr: 'القرآن الكريم', nameEn: 'Quran'),
];

Widget _guestSearch() => GuestSearchScreen(
      loadOptions: () async => _subjects,
      loadMatch: ({subject, level, required mode}) async => const LandingCount(courses: 24, teachers: 9),
      onShow: (_, _) {},
      onLogin: () {},
      onRegister: () {},
    );

Widget _guestLive({bool after = false}) => SaHeroPage(
      area: AppArea.sched,
      kicker: 'sa_live_kicker'.tr,
      title: 'sa_live_title'.tr,
      squiggle: 'sa_live_squiggle'.tr,
      child: GuestLiveContent(
        loading: false,
        info: GuestLiveInfo.fromJson({
          'session_id': 0,
          'meeting_id': 5,
          'kind': 'meeting',
          'title': AppConfig.lang == 'ar' ? 'مراجعة القدرات' : 'Qudurat review',
          'host_name': AppConfig.lang == 'ar' ? 'فيصل العنزي' : 'Faisal Al-Anazi',
          'is_live': true,
          'requires_pin': true,
          'recording_enabled': true,
          'guest_admission': 'auto',
        }),
        error: null,
        joining: false,
        consent: true,
        nameController: TextEditingController(text: AppConfig.lang == 'ar' ? 'سلطان الدوسري' : 'Sultan Al-Dosari'),
        pinController: TextEditingController(text: '4729'),
        onJoin: () {},
        onRetry: () {},
        onSignIn: () {},
        afterRoom: after ? GuestLiveAfterCard(kind: LiveRoomKind.meeting, onRegister: () {}, onSignIn: () {}, onLater: () {}) : null,
      ),
    );

Map<String, dynamic> _privacyDoc(String lang) {
  final ar = lang == 'ar';
  Map<String, dynamic> s(int id, String icon, String tAr, String tEn, String bAr, String bEn) =>
      {'id': id, 'icon_name': icon, 'title': ar ? tAr : tEn, 'body': ar ? bAr : bEn, 'order': id, 'is_active': true};
  return {
    'meta': {'id': 1, 'last_updated': ar ? '١ نوفمبر ٢٠٢٦' : '1 November 2026'},
    'intro': ar ? 'مكتوبة بكلام واضح.' : 'Written in plain words.',
    'sections': [
      s(1, 'person', 'وش نحفظ عنك', 'What we keep', 'اسمك وجوالك وصفّك، وتقدّمك في الدورات.', 'Your name, phone, grade and course progress.'),
      s(2, 'insights', 'ليش نحفظها', 'Why we keep it', 'نرتّب لك الدورات والجدول، ونذكّرك بحصصك.', 'To order your courses and schedule and remind you of classes.'),
      s(3, 'visibility', 'مين يشوفها', 'Who sees it', 'معلمينك وولي أمرك المربوط بحسابك بس. ما نبيعها لأحد.', 'Only your teachers and the parent linked to your account. We never sell it.'),
      s(4, 'security', 'كيف نحميها', 'How we protect it', 'نشفّرها، ونحمي الدروس من التصوير.', 'We encrypt it and protect lessons from screen capture.'),
      s(5, 'sentiment_satisfied', 'حقوقك', 'Your rights', 'تقدر تعدّل بياناتك أو تحذف حسابك من الإعدادات.', 'You can edit your data or delete your account in Settings.'),
    ],
  };
}

Widget _study() => SaHeroPage(
      area: AppArea.home,
      kicker: AppConfig.lang == 'ar' ? 'خطوة صغيرة' : 'One small step',
      title: AppConfig.lang == 'ar' ? 'خلّنا نعرفك أكثر' : 'Let us get to know you',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AppCard(
          child: StudyProfileForm(
            value: const StudyProfile(countryCode: 'SA', stageId: 2, gradeId: 22, track: 'cs'),
            compact: true,
            edu: StudyEduData(
              countries: const [EduCountry(code: 'SA', nameAr: 'السعودية', nameEn: 'Saudi Arabia')],
              country: 'SA',
              stages: [
                EduStage(id: 2, key: 'secondary', nameAr: 'الثانوي', nameEn: 'Secondary', grades: [
                  EduGrade(id: 22, key: 's2', nameAr: 'الثاني ثانوي', nameEn: 'Grade 11', number: 2, tracks: [
                    for (final (k, ar, en) in const [
                      ('general', 'المسار العام', 'General'),
                      ('cs', 'علوم الحاسب والهندسة', 'Computer science and engineering'),
                      ('health', 'الصحة والحياة', 'Health and life'),
                      ('business', 'إدارة الأعمال', 'Business'),
                      ('sharia', 'الشرعي', 'Sharia'),
                    ])
                      EduTrack(key: k, nameAr: ar, nameEn: en),
                  ]),
                ]),
              ],
              loadAreas: (_) async => const [],
            ),
            onChanged: (_) {},
          ),
        ),
      ),
    );

void main() {
  late FakeApi fake;

  setUpAll(() async => _storage = await kitGoldenSetUp());

  setUp(() {
    mockRequestPlugins();
    fake = FakeApi({
      'GET /api/v1/categories': (_) => [
            for (final (id, ar, en) in const [
              (1, 'الرياضيات', 'Mathematics'),
              (2, 'الفيزياء', 'Physics'),
              (3, 'الكيمياء', 'Chemistry'),
              (4, 'الإنجليزي', 'English'),
            ])
              {'id': id, 'name_ar': ar, 'name_en': en, 'description': '', 'image_url': null},
          ],
      'GET /api/v1/courses': (_) => {'items': _mathCourses(), 'total': 24},
      'GET /api/v1/me/recommendations*': (_) => _recs(),
      'POST /api/v1/me/recommendations/events': (_) => <String, dynamic>{},
      'GET /api/v1/app-content/legal/privacy*': (o) => _privacyDoc(o.uri.queryParameters['lang'] ?? 'ar'),
    }, latency: Duration.zero);
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('categories', (t) async {
    await kitRender(
      t,
      'sa2_category',
      () => ChangeNotifierProvider(create: (_) => CategoriesProvider(), child: const CategoriesScreen(selectedId: '1')),
      storage: _storage,
      modes: _light,
      scaffold: false,
    );
    await t.pump(const Duration(seconds: 2));
  });

  testWidgets('journey', (t) async {
    await kitRender(t, 'sa2_journey', () => JourneyPage(initial: _journey()), storage: _storage, modes: _light, scaffold: false);
  });

  testWidgets('recommendations', (t) async {
    await kitRender(t, 'sa2_recs', () => const RecommendationsPage(), storage: _storage, modes: _light, scaffold: false);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('guest search', (t) async {
    await kitRender(t, 'sa2_guestsearch', _guestSearch, storage: _storage, modes: _light, scaffold: false);
  });

  testWidgets('guest live', (t) async {
    await kitRender(t, 'sa2_guestlive', _guestLive, storage: _storage, modes: _light, scaffold: true);
    await kitRender(t, 'sa2_guestlive_after', () => _guestLive(after: true), storage: _storage, modes: _light, scaffold: true);
  });

  testWidgets('legal', (t) async {
    await kitRender(
      t,
      'sa2_legal',
      () => ChangeNotifierProvider(create: (_) => AboutTermsProvider(), child: const TermsScreen(privacy: true, canAsk: false)),
      storage: _storage,
      modes: _light,
      scaffold: false,
    );
  });

  testWidgets('study', (t) async {
    await kitRender(t, 'sa2_study', _study, storage: _storage, modes: _light, sizes: const [Size(390, 844)]);
  });
}
