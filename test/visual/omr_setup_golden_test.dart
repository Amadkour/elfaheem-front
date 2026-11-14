// Visual review renders of the paper exam setup wizard and the student's identifier dialog (D-150, D-151), compared
// by eye like the other test/visual files (NOT a CI suite). The PNGs go OUTSIDE the repo:
//
//   OMR_RENDER_DIR=<dir> flutter test test/visual/omr_setup_golden_test.dart --update-goldens [--plain-name forms]
//
// → <dir>/omr_<scene>_<width>_<lang>_<light|dark>.png
//   identify   step 1 after choosing National ID: 34 ready, 6 missing, a duplicates card, the request sent
//   delivery   step 2 · coming     step 2 after Online ("Online exams are coming next")
//   format     step 3 · template   step 4 · forms   step 5 (two models, B open, markers, marking rules)
//   student    the student's dialog over the home · student_error   the same with the 409 sentence
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/paper/exam_setup.dart';
import 'package:flutter_education_app/features/exams/paper/exam_setup_wizard.dart';
import 'package:flutter_education_app/features/exams/identity/identity_request_gate.dart';
import 'package:flutter_education_app/features/exams/identity/identity_requests.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_screens_golden_test.dart' show pubspecFonts;

String _sdkFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return '$root/bin/cache/artifacts/material_fonts';
  final exe = File(Platform.resolvedExecutable).absolute.path.replaceAll('\\', '/');
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
  final cfg = jsonDecode(File('.dart_tool/package_config.json').readAsStringSync()) as Map<String, dynamic>;
  for (final p in (cfg['packages'] as List).cast<Map<String, dynamic>>()) {
    if (p['name'] != 'cupertino_icons') continue;
    final root = Uri.parse('${p['rootUri']}');
    final dir = root.isAbsolute ? root.toFilePath() : File('.dart_tool/${p['rootUri']}').absolute.path;
    final font = File('$dir/assets/CupertinoIcons.ttf');
    if (font.existsSync()) await load('packages/cupertino_icons/CupertinoIcons', [font.path]);
  }
}

final _shot = GlobalKey();
final _dir = (Platform.environment['OMR_RENDER_DIR'] ?? '${Directory.systemTemp.path}/omr_renders').replaceAll('\\', '/');

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(
        key: _shot,
        child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      ),
      home: child,
    ),
  );
}

Widget _page(Widget frame) => Builder(
      builder: (context) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(title: Text(t('إعداد الاختبار الورقي', 'Paper exam setup'))),
        body: frame,
      ),
    );

const _names = ['Sara Ahmed', 'Omar Khaled', 'Youssef Ali', 'Nour Hassan', 'Mariam Tarek', 'Hana Mostafa'];
const _namesAr = ['سارة أحمد', 'عمر خالد', 'يوسف علي', 'نور حسن', 'مريم طارق', 'هنا مصطفى'];

IdentifierReport _report() => IdentifierReport(
      source: 'national_id',
      labelAr: 'الرقم القومي',
      labelEn: 'National ID',
      kind: 'digits',
      collectable: true,
      total: 40,
      ready: 34,
      missing: [for (var i = 0; i < 6; i++) StudentRef(i, t(_namesAr[i], _names[i]))],
      duplicates: [
        [StudentRef(50, t('علي حسن', 'Ali Hassan')), StudentRef(51, t('منى عبد الرحمن', 'Mona Abdelrahman'))],
      ],
      pending: 6,
    );

final _fields = [
  const IdentityFieldDef(key: 'national_id', labelAr: 'الرقم القومي', labelEn: 'National ID', kind: 'digits', minLen: 14, maxLen: 14),
  const IdentityFieldDef(key: 'academic_id', labelAr: 'الرقم الأكاديمي', labelEn: 'Academic ID', maxLen: 32),
  const IdentityFieldDef(key: 'passport_no', labelAr: 'رقم الجواز', labelEn: 'Passport number', minLen: 6, maxLen: 9),
];

final _questions = [
  for (final (i, p) in const [
    'What is the main product of photosynthesis?',
    'Which organelle holds the cell\'s genetic material?',
    'Which gas do plants take in from the air?',
    'Water boils at 100 °C at sea level.',
  ].indexed)
    ObjectiveQuestion.fromPlaced({
      'id': i + 1,
      'type': i == 3 ? 'true_false' : 'mcq_single',
      'body': {'prompt': p, 'options': ['a', 'b', 'c', 'd']},
      'answer': {'correct': i == 3 ? true : ['b', 'a', 'c'][i]},
    })!,
];

Widget _frame(SetupStep step, int index, int total, String title, String? sub, Widget body, {String? primary}) => _page(SetupFrame(
      index: index,
      total: total,
      stepLabel: setupStepLabel(step),
      title: title,
      subtitle: sub,
      body: body,
      primaryLabel: primary ?? t('متابعة', 'Continue'),
      onPrimary: () {},
      backLabel: index == 0 ? t('إغلاق', 'Close') : t('رجوع', 'Back'),
      onBack: () {},
    ));

Future<void> _render(WidgetTester tester, String name, Widget Function() build) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900)]) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(), dark: dark));
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile(Uri.file('$_dir/omr_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png')),
          );
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => AppConfig.disableList = []);

  testWidgets('identify', (t0) => _render(t0, 'identify', () => _frame(
        SetupStep.identify,
        0,
        5,
        t('كيف نتعرف على كل طالب في هذا الاختبار؟', 'How do we identify each student in this exam?'),
        t('نطابق كل ورقة بصاحبها من خلال هذه القيمة', 'Each sheet is matched to its student by this value'),
        IdentifierStepBody(
          options: identifierOptions(_fields, dataLab: true, dataLabColumns: const [('seat', 'Seat number')]),
          selected: const IdentifierChoice('national_id'),
          onPick: (_) {},
          report: _report(),
          note: t('أُرسل الطلب إلى 6 طالب', 'Request sent to 6 students'),
          dueLabel: t('موعد الإدخال: يوم الاختبار، 1 ديسمبر 2026', 'Due: exam day, 1 Dec 2026'),
          onChangeDue: () {},
          onRequest: () {},
          onRemind: () {},
          live: true,
        ),
      )));

  testWidgets('delivery', (t0) => _render(t0, 'delivery', () => _frame(SetupStep.delivery, 1, 5,
      t('كيف سيُقدَّم الاختبار؟', 'How will students take this exam?'), null, DeliveryStepBody(value: 'paper', onPick: (_) {}))));

  testWidgets('coming', (t0) => _render(t0, 'coming', () => _frame(SetupStep.delivery, 1, 2, t('الاختبار الإلكتروني', 'Online exam'), null,
      OnlineComingNext(onPaper: () {}), primary: t('تم', 'Done'))));

  testWidgets('format', (t0) => _render(t0, 'format', () => _frame(SetupStep.format, 2, 5, t('ماذا سيُطبع؟', 'What will you print?'),
      t('يمكنك تغيير هذا لاحقًا', 'You can change this later'), PaperFormatStepBody(value: 'both', omrOn: true, onPick: (_) {}))));

  testWidgets('template', (t0) => _render(t0, 'template', () => _frame(
        SetupStep.template,
        3,
        5,
        t('اختر نوع ورقة التظليل', 'Choose the bubble-sheet type'),
        t('الأنواع المعتمدة على المنصة', 'The types approved on the platform'),
        TemplateStepBody(
          templates: const [
            OmrTemplateItem(id: 1, version: 1, name: 'Bubble 50', questions: 50, options: 4),
            OmrTemplateItem(id: 2, version: 2, name: 'Bubble 100', questions: 100, options: 5, description: 'Two columns'),
            OmrTemplateItem(id: 3, version: 1, name: 'Bubble 40', questions: 40),
          ],
          selectedId: 1,
          onPick: (_) {},
          onLearn: () {},
          onPaperOnly: () {},
        ),
      )));

  testWidgets('template_empty', (t0) => _render(t0, 'template_empty', () => _frame(
        SetupStep.template,
        3,
        5,
        t('اختر نوع ورقة التظليل', 'Choose the bubble-sheet type'),
        null,
        TemplateStepBody(templates: const [], selectedId: null, onPick: (_) {}, onPaperOnly: () {}),
      )));

  testWidgets('forms', (t0) => _render(t0, 'forms', () {
        final b = newForm('B', _questions)..key['1'] = 'c';
        return _frame(
          SetupStep.forms,
          4,
          5,
          t('نماذج الاختبار', 'Exam models'),
          t('لكل نموذج مفتاح إجابته', 'Each model has its own answer key'),
          FormsStepBody(
            forms: [newForm('A', _questions), b],
            questions: _questions,
            markers: const ['qr', 'bubble'],
            policy: const OmrPolicy(blank: 'zero'),
            bubble: true,
            onAdd: () {},
            onRemove: (_) {},
            onChoose: (_, _, _) {},
            onToggleMarker: (_) {},
            onPolicy: (_) {},
          ),
          primary: t('إنهاء الإعداد', 'Finish setup'),
        );
      }));

  final item = IdentityRequestItem(
    id: 1,
    field: const IdentityFieldDef(key: 'national_id', labelAr: 'الرقم القومي', labelEn: 'National ID', kind: 'digits', minLen: 14, maxLen: 14),
    examTitle: 'Physics midterm',
    paper: true,
    dueUtc: DateTime.utc(2026, 11, 20, 7),
    messageAr: 'يحتاج معلمك إلى الرقم القومي للاختبار القادم. يُرجى إدخاله قبل يوم الاختبار.',
    messageEn: 'Your teacher needs your National ID for the upcoming exam. Please enter it before exam day.',
  );

  Widget student({String? error, String text = ''}) => Builder(
        builder: (context) {
          final c = context.colors;
          return Scaffold(
            backgroundColor: c.background,
            body: Stack(children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        height: 120,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.divider)),
                      ),
                  ]),
                ),
              ),
              Positioned.fill(child: ModalBarrier(dismissible: false, color: c.textDark.withValues(alpha: 0.42))),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: IdentityRequestCard(
                    item: item,
                    controller: TextEditingController(text: text),
                    onSubmit: () {},
                    onLater: () {},
                    error: error,
                  ),
                ),
              ),
            ]),
          );
        },
      );

  testWidgets('student', (t0) => _render(t0, 'student', () => student()));
  testWidgets('student_error', (t0) => _render(t0, 'student_error', () => student(
        text: '29901010000005',
        error: t('هذا الرقم مستخدم بالفعل من طالب آخر. يرجى التحقق منه.', 'This number is already used by another student. Please check it.'),
      )));
}
