// VISUAL review renders of the super admin's Games v4 pages (review gate G3): the hub, templates, subjects, the
// question bank and one item editor with its live preview, the review queue, the import wizard after a dry run, levels
// and one wizard step, analytics, breaks, outfits, the seed console and the reciters. Each page is the REAL page over
// a fake server (FakeApi), at 390x844 in Arabic and 1400x900 in English, grown to show the whole page, into
// test/visual/goldens/games_admin_v4_*.png. Not a CI suite; compared by eye.
//
//   flutter test test/visual/games_admin_v4_golden_test.dart --update-goldens [--plain-name bank]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppWidth;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/admin/admin_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/analytics_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/bank_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/breaks_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/cosmetics_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/editors/item_editor.dart';
import 'package:flutter_education_app/features/games/admin/v4/hub_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/import_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/items_review_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/level_wizard.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_api.dart';
import 'package:flutter_education_app/features/games/admin/v4/levels_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/reciters_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/review_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/seed_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/subjects_page.dart';
import 'package:flutter_education_app/features/games/admin/v4/templates_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll(String.fromCharCode(92), '/');
  return '${exe.substring(0, exe.indexOf('/bin/cache/'))}/bin/cache/artifacts/material_fonts';
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await loader.load();
  }

  for (final (family, assets) in pubspecFonts(File('pubspec.yaml').readAsStringSync())) {
    await load(family, assets);
  }
  final sdk = _sdkFonts();
  await load('Roboto', [for (final w in ['regular', 'medium', 'bold']) '$sdk/roboto-$w.ttf']);
  await load('MaterialIcons', ['$sdk/materialicons-regular.otf']);
}

final _shot = GlobalKey();
final _prodColors =
    jsonDecode(File('test/visual/fixtures/theme_production.json').readAsStringSync()) as Map<String, dynamic>;

// ── the fake server ──────────────────────────────────────────────────────────

const _subjects = [
  {'id': 1, 'key': 'quran', 'name_ar': 'القرآن الكريم', 'name_en': 'The Holy Quran', 'sacred': true, 'requires_review': true, 'items': 420, 'levels': 18, 'enabled': true},
  {'id': 2, 'key': 'hadith', 'name_ar': 'الحديث الشريف', 'name_en': 'Hadith', 'sacred': true, 'requires_review': true, 'items': 96, 'levels': 6, 'enabled': true},
  {'id': 3, 'key': 'math', 'name_ar': 'الرياضيات', 'name_en': 'Mathematics', 'items': 1240, 'levels': 32, 'enabled': true},
  {'id': 4, 'key': 'arabic', 'name_ar': 'اللغة العربية', 'name_en': 'Arabic language', 'items': 610, 'levels': 21, 'enabled': true},
  {'id': 5, 'key': 'science', 'name_ar': 'العلوم', 'name_en': 'Science', 'items': 0, 'levels': 0, 'enabled': false},
];

const _codeDefaults = {'timer_s': 60, 'lives': 3, 'speed': 3, 'penalty': 'soft', 'theme': 'auto', 'music': true};

final _templates = [
  for (final (k, ar, en, sacred, on, lv) in const [
    ('car_race', 'سباق السيارات', 'Car race', true, true, 14),
    ('balloon_pop', 'فرقعة البالونات', 'Balloon pop', false, true, 9),
    ('growing_tree', 'الشجرة النامية', 'Growing tree', true, true, 22),
    ('word_train', 'قطار الكلمات', 'Word train', true, true, 11),
    ('space_rocket', 'صاروخ الفضاء', 'Space rocket', false, true, 6),
    ('robot_coding', 'برمجة الروبوت', 'Code the robot', false, false, 0),
  ])
    {'key': k, 'name_ar': ar, 'name_en': en, 'sacred_allowed': sacred, 'enabled': on, 'levels': lv, 'code_defaults': _codeDefaults},
];

Map<String, dynamic> _item(int id, String type, int subject, String ar, String en, String status, int diff, String topic, Map<String, dynamic> body) => {
      ...defaultItem(type, subjectId: subject),
      'id': id,
      'prompt': {'ar': ar, 'en': en},
      'status': status,
      'difficulty': diff,
      'topic': topic,
      'body': body,
    };

final _items = [
  _item(7, 'mcq', 3, 'كم يساوي ٣ × ٤؟', 'What is 3 × 4?', 'approved', 1, 'الضرب', {
    'options': [{'text': '12'}, {'text': '7'}, {'text': '9'}, {'text': '14'}],
    'answer': 0,
  }),
  _item(8, 'true_false', 4, 'الفاعل في الجملة الفعلية مرفوع دائماً', 'The subject of a verbal sentence is always nominative', 'draft', 2, 'النحو', {'answer': true}),
  _item(9, 'sequence', 1, 'رتّب كلمات الآية', 'Put the words of the ayah in order', 'pending_review', 2, 'juz_30/112',
      {'mode': 'order', 'unit': 'word', 'tokens': '@quran:112:1', 'distractors': 2}),
  _item(10, 'pair', 4, 'صِل كل كلمة بضدها', 'Match each word with its opposite', 'approved', 1, 'الأضداد', {
    'pairs': [{'a': 'كبير', 'b': 'صغير'}, {'a': 'طويل', 'b': 'قصير'}, {'a': 'سريع', 'b': 'بطيء'}],
  }),
  _item(11, 'fraction', 3, 'لوّن ثلاثة أرباع البيتزا', 'Colour three quarters of the pizza', 'rejected', 3, 'الكسور', {'shape': 'pizza', 'n': 3, 'd': 4}),
  _item(12, 'classify', 3, 'صنّف الأعداد إلى زوجية وفردية', 'Sort the numbers into even and odd', 'approved', 2, 'الأعداد', {
    'buckets': [{'key': 'g1', 'label': {'ar': 'زوجي', 'en': 'Even'}}, {'key': 'g2', 'label': {'ar': 'فردي', 'en': 'Odd'}}],
    'tokens': [{'text': '4', 'bucket': 'g1'}, {'text': '7', 'bucket': 'g2'}, {'text': '10', 'bucket': 'g1'}, {'text': '13', 'bucket': 'g2'}],
  }),
];

Map<String, dynamic> _level(int id, String engine, int subject, String ar, String en, String status, int starts, int score, {bool sacred = false}) => {
      'id': id,
      'engine': engine,
      'game_subject_id': subject,
      'title_ar': ar,
      'title_en': en,
      'status': status,
      'level_no': id,
      'age_min': 6,
      'age_max': 12,
      'sacred': sacred,
      'coins_reward': 20,
      'topic': sacred ? 'juz_30/112' : '',
      'item_source': {'mode': 'pool', 'topic': sacred ? 'juz_30/112' : '', 'difficulty': [1, 3], 'count': 8},
      'template_settings': {'timer_s': 60, 'lives': 3, 'speed': 3, 'penalty': 'soft', 'theme': 'auto', 'music': true},
      'unlock': {'mode': 'prev', 'min_stars': 1},
      'stats': {'starts': starts, 'avg_score_pct': score},
    };

final _levels = [
  _level(1, 'car_race', 3, 'جدول الضرب: ٢ و٣', 'Times tables: 2 and 3', 'published', 1840, 82),
  _level(2, 'car_race', 3, 'جدول الضرب: ٤ و٥', 'Times tables: 4 and 5', 'published', 1210, 74),
  _level(3, 'word_train', 1, 'سورة الإخلاص', 'Surat Al-Ikhlas', 'published', 960, 91, sacred: true),
  _level(4, 'balloon_pop', 4, 'الأضداد', 'Opposites', 'draft', 0, 0),
  _level(5, 'growing_tree', 3, 'الكسور: النصف والربع', 'Fractions: halves and quarters', 'draft', 0, 0),
];

FakeApi _server() => FakeApi({
      'GET /api/v1/admin/games/v4/hub': (_) => {
            'plays_today': 1284,
            'players_today': 356,
            'completion_pct': 71.4,
            'avg_score_pct': 83,
            'pending_review': 14,
            'items_total': 2366,
            'levels_published': 64,
          },
      'GET /api/v1/admin/games/v4/templates': (_) => {'items': _templates},
      'GET /api/v1/admin/games/v4/subjects': (_) => {'items': _subjects},
      'GET /api/v1/admin/games/v4/items': (_) => {'items': _items, 'total': 2366, 'has_more': true},
      'GET /api/v1/admin/games/v4/items/7': (_) => {
            ..._items.first,
            'resolved': {'body': _items.first['body']},
          },
      'POST /api/v1/admin/games/v4/items/check': (_) => {'resolved': {'body': _items.first['body']}},
      'GET /api/v1/admin/games/v4/review': (_) => {
            'items': [
              {
                'id': 9,
                'type': 'sequence',
                'topic': 'juz_30/112',
                'subject': 'القرآن الكريم',
                'prompt': {'ar': 'رتّب كلمات الآية الأولى من سورة الإخلاص', 'en': 'Put the words of the first ayah of Al-Ikhlas in order'},
                'source': {'kind': 'quran', 'ref': '112:1'},
                'body': {'tokens': ['قُلْ', 'هُوَ', 'ٱللَّهُ', 'أَحَدٌ']},
              },
              {
                'id': 21,
                'type': 'mcq',
                'topic': 'الطهارة',
                'subject': 'الحديث الشريف',
                'prompt': {'ar': 'من راوي حديث «إنما الأعمال بالنيات»؟', 'en': 'Who narrated "Actions are by intentions"?'},
                'source': {'kind': 'hadith', 'ref': 'bukhari:1'},
                'body': {'options': [{'text': 'عمر بن الخطاب'}, {'text': 'أبو هريرة'}, {'text': 'أنس بن مالك'}], 'answer': 0},
              },
            ],
            'total': 14,
            'has_more': true,
          },
      'GET /api/v1/admin/games/v4/reviewers': (_) => {
            'items': [
              {'id': 31, 'name': 'الشيخ عبد الرحمن الأنصاري', 'username': 'a.ansari'},
              {'id': 44, 'name': 'أ. مريم يوسف', 'username': 'maryam.y'},
            ]
          },
      'GET /api/v1/admin/games/v4/levels': (_) => {'items': _levels},
      'GET /api/v1/admin/games/v4/analytics/overview': (_) => {
            'plays': 12840,
            'players': 931,
            'completion_pct': 71.4,
            'avg_score_pct': 83,
            'by_day': [
              for (var i = 1; i <= 30; i++)
                {'day': '2026-11-${i.toString().padLeft(2, '0')}', 'starts': 300 + (i * 37) % 180, 'finishes': 210 + (i * 29) % 140},
            ],
          },
      'GET /api/v1/admin/games/v4/analytics/levels': (_) => {
            'items': [
              for (final (i, l) in _levels.take(4).indexed)
                {
                  'game_id': l['id'],
                  'title_ar': l['title_ar'],
                  'title_en': l['title_en'],
                  'starts': 1840 - i * 410,
                  'finishes': 1400 - i * 330,
                  'completion_pct': 76 - i * 4,
                  'avg_score_pct': 82 - i * 3,
                  'avg_ms': 45000 + i * 12500,
                },
            ]
          },
      'GET /api/v1/admin/games/v4/analytics/items/hardest': (_) => {
            'items': [
              {'id': 11, 'type': 'fraction', 'prompt': 'لوّن ثلاثة أرباع البيتزا', 'subject': 'الرياضيات', 'topic': 'الكسور', 'shown': 412, 'correct_pct': 18},
              {'id': 8, 'type': 'true_false', 'prompt': 'الفاعل في الجملة الفعلية مرفوع دائماً', 'subject': 'اللغة العربية', 'topic': 'النحو', 'shown': 280, 'correct_pct': 27},
            ]
          },
      'GET /api/v1/admin/module-settings/games': (_) => {
            'module': 'games',
            'scope': 'platform',
            'values': {'play_now': true, 'break_reminders': true, 'study_minutes': 45, 'break_max_minutes': 10, 'parent_summary': true},
            'effective': {'play_now': true, 'break_reminders': true, 'study_minutes': 45, 'break_max_minutes': 10, 'parent_summary': true},
            'updated_at': '2026-11-20T10:00:00',
          },
      'GET /api/v1/admin/games/v4/cosmetics': (_) => {
            'items': [
              {'key': 'hat_crown', 'slot': 'hat', 'name_ar': 'تاج ذهبي', 'name_en': 'Golden crown', 'price_coins': 120, 'enabled': true},
              {'key': 'outfit_astro', 'slot': 'outfit', 'name_ar': 'بدلة رائد فضاء', 'name_en': 'Astronaut suit', 'unlock_rule': {'type': 'stars', 'count': 50}, 'enabled': true},
              {'key': 'car_red', 'slot': 'vehicle', 'name_ar': 'سيارة حمراء', 'name_en': 'Red car', 'price_coins': 0, 'enabled': true},
              {'key': 'trail_stars', 'slot': 'trail', 'name_ar': 'أثر النجوم', 'name_en': 'Star trail', 'unlock_rule': {'type': 'champion', 'count': 3}, 'enabled': false},
            ]
          },
      'GET /api/v1/admin/games/v4/seed': (_) => {
            'items': [
              for (final (k, ar, en, seeded, appr, pend, lv) in const [
                ('quran', 'القرآن الكريم', 'The Holy Quran', 420, 380, 40, 18),
                ('math', 'الرياضيات', 'Mathematics', 1240, 1240, 0, 32),
                ('arabic', 'اللغة العربية', 'Arabic language', 610, 598, 12, 21),
              ])
                {
                  'subject': {'name_ar': ar, 'name_en': en},
                  'key': k,
                  'seeded': seeded,
                  'approved': appr,
                  'pending': pend,
                  'levels': lv,
                  'last_run_at': '2026-11-20T10:00:00',
                },
            ],
            'datasets': [
              {'key': 'quran', 'ok': true},
            ],
          },
      'GET /api/v1/admin/games/v4/reciters': (_) => {
            'items': [
              {
                'key': 'alafasy', 'name_ar': 'مشاري العفاسي', 'name_en': 'Mishary Alafasy', 'riwayah': 'hafs', 'audience': 'all', 'enabled': true, 'is_default': true,
                'licence': 'Free for non-commercial use with credit', 'permission_status': 'verified', 'permission_note': 'Email from the publisher, 2026-11-01',
                'source_url': 'https://everyayah.com', 'coverage': {'surahs': 114, 'of': 114}, 'sample': {'url': 'https://x/1.mp3'},
              },
              {
                'key': 'husary_muallim', 'name_ar': 'محمود خليل الحصري (المعلّم)', 'name_en': 'Al-Husary (teaching)', 'riwayah': 'hafs', 'audience': 'kids', 'enabled': true, 'is_default': false,
                'licence': 'Public domain recording', 'permission_status': 'verified', 'coverage': {'surahs': 114, 'of': 114}, 'sample': {'url': 'https://x/2.mp3'},
              },
              {
                'key': 'mukhtar', 'name_ar': 'مختار الحاج', 'name_en': 'Mukhtar Al-Haj', 'audience': 'all', 'enabled': false, 'is_default': false,
                'licence': '', 'permission_status': 'pending', 'coverage': {'surahs': 37, 'of': 114},
              },
            ]
          },
    }, latency: const Duration(milliseconds: 10));

// ── the import wizard after a dry run (the file picker cannot run here) ──────

class _ImportDryRun extends StatelessWidget {
  const _ImportDryRun();

  @override
  Widget build(BuildContext context) => AdminPage(
        width: AppWidth.reading,
        title: t('استيراد أسئلة', 'Import questions'),
        subtitle: t('أضف عشرات الأسئلة دفعة واحدة من ملف.', 'Add many questions at once from a file.'),
        icon: Icons.upload_file_rounded,
        onRefresh: () {},
        body: ListView(padding: AdminPage.bodyPadding(context), children: [
          ImportWizardBody(
            subjects: const [
              (id: 1, key: 'quran', nameAr: 'القرآن الكريم', nameEn: 'The Holy Quran', requiresReview: true),
              (id: 3, key: 'math', nameAr: 'الرياضيات', nameEn: 'Mathematics', requiresReview: false),
            ],
            subjectId: 3,
            type: 'mcq',
            format: 'xlsx',
            fileName: 'math-grade-3-multiplication.xlsx',
            report: const ImportReport(rows: 48, ok: 45, created: 0, pending: 0, errors: [
              (row: 7, field: 'body.answer', why: 'out_of_range'),
              (row: 19, field: 'prompt', why: 'empty'),
              (row: 33, field: 'body.options', why: 'count_2_6'),
            ]),
            onSubject: (_) {},
            onType: (_) {},
            onFormat: (_) {},
            onDownload: () {},
            onPick: () {},
            onCommit: () {},
            onAgain: () {},
          ),
        ]),
      );
}

// ── rendering ────────────────────────────────────────────────────────────────

Widget _host(Widget child, StorageService storage) {
  final theme = ThemeConfigProvider(api: ApiClient())..debugUseColors(_prodColors);
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: ChangeNotifierProvider(create: (_) => LangProvider(storage: storage), child: child)),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// One page at the phone (ar) and desktop (en) size, the window grown to show the whole page.
Future<void> _shoot(WidgetTester tester, String name, Widget Function() build, {Future<void> Function(WidgetTester t)? act}) async {
  SharedPreferences.setMockInitialValues({});
  mockRequestPlugins();
  final storage = await StorageService.getInstance();
  final fake = _server()..install();
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final (size, lang, tag) in const [(Size(390, 844), 'ar', 'phone_ar'), (Size(1400, 900), 'en', 'desktop_en')]) {
      AppConfig.lang = lang;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(build(), storage));
      await _frames(tester);
      if (act != null) {
        await act(tester);
        await _frames(tester);
      }
      for (var i = 0; i < 4; i++) {
        var extra = 0.0;
        for (final e in find.byType(Scrollable).evaluate()) {
          final s = (e as StatefulElement).state as ScrollableState;
          if (s.position.axis == Axis.vertical && s.position.hasContentDimensions) extra = math.max(extra, s.position.maxScrollExtent);
        }
        if (extra < 1) break;
        tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
        await _frames(tester, 4);
      }
      expect(tester.takeException(), isNull, reason: '$name $tag');
      await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/games_admin_v4_${name}_$tag.png'));
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    debugDisableShadows = true;
    fake.uninstall();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('hub', (tester) => _shoot(tester, 'hub', () => const GamesHubPage()));
  testWidgets('templates', (tester) => _shoot(tester, 'templates', () => const GamesTemplatesPage()));
  testWidgets('subjects', (tester) => _shoot(tester, 'subjects', () => GamesSubjectsPage(courseSubjects: () async => const [])));
  testWidgets('bank', (tester) => _shoot(tester, 'bank', () => const BankPage()));
  testWidgets('item editor', (tester) => _shoot(tester, 'item_editor', () => const ItemEditorPage(itemId: 7)));
  testWidgets('review', (tester) => _shoot(tester, 'review', () => const GamesReviewPage()));
  testWidgets('import dry run', (tester) => _shoot(tester, 'import', () => const _ImportDryRun()));
  testWidgets('levels', (tester) => _shoot(tester, 'levels', () => const GamesLevelsPage()));
  testWidgets('level wizard, questions step', (tester) => _shoot(
        tester,
        'level_wizard',
        () => LevelWizardPage(level: LevelRow(_levels[2])),
        act: (t) async {
          await t.ensureVisible(find.byKey(const ValueKey('games.wiz.next')));
          await t.pump();
          await t.tap(find.byKey(const ValueKey('games.wiz.next')));
        },
      ));
  testWidgets('analytics', (tester) => _shoot(tester, 'analytics', () => const GamesAnalyticsPage()));
  testWidgets('breaks', (tester) => _shoot(tester, 'breaks', () => const GamesBreaksPage()));
  testWidgets('cosmetics', (tester) => _shoot(tester, 'cosmetics', () => const GamesCosmeticsPage()));
  testWidgets('seed', (tester) => _shoot(tester, 'seed', () => const GamesSeedPage()));
  testWidgets('reciters', (tester) => _shoot(tester, 'reciters', () => const RecitersPage()));
}
