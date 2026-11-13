// Visual review renders of the exam cover picker and the printed cover (D-730 - D-732). NOT a CI suite:
//
//   flutter test test/visual/exam_cover_golden_test.dart --update-goldens [--plain-name picker]
//
// → test/visual/goldens/exam_cover_<scene>_<width>_<lang>_<light|dark>.png at 390×844, 1440×900 and 391×2000 (the whole picker):
//   picker     the question paper on an uploaded PDF (page 2 of 4, details box at the bottom) and the answers on their own picture
//   designed   the question paper on the designed cover (university, marks grid, Edit), the answers "same as the question paper"
//   empty      Upload chosen, no file yet (the drop area with the limits), an upload refused (the error banner)
//   print      the prepare page's print card with its "Cover page" row
//   pdf        the REAL printed copy: the uploaded cover (picture, Mariam's details box, the cover code) then page 1 of the paper
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/exam_cover.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_cover_picker.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_bands.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_design_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_designer.dart' show paperWithDesign;
import 'package:flutter_education_app/features/shared/exam_engine/exam_paper_pdf.dart';
import 'package:flutter_education_app/features/shared/exam_engine/hub/deliver/deliver_logic.dart' show DeliverScope;
import 'package:flutter_education_app/features/shared/exam_engine/hub/deliver/exam_deliver_screen.dart' show DeliverPrintCard;
import 'package:flutter_education_app/features/shared/exam_engine/hub/deliver/paper_page_replay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

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
}

/// A school's cover as a teacher would upload it: a coloured band with a crest, framed, title rules.
Uint8List _schoolCover({int hue = 0}) {
  final w = 620, h = 877;
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorUint8.rgb(250, 248, 242));
  final band = hue == 0 ? img.ColorUint8.rgb(22, 74, 120) : img.ColorUint8.rgb(122, 40, 64);
  img.fillRect(im, x1: 0, y1: 0, x2: w, y2: 170, color: band);
  img.fillCircle(im, x: w ~/ 2, y: 85, radius: 52, color: img.ColorUint8.rgb(236, 196, 92));
  img.fillCircle(im, x: w ~/ 2, y: 85, radius: 36, color: band);
  img.drawRect(im, x1: 24, y1: 194, x2: w - 24, y2: h - 24, color: band, thickness: 4);
  for (final (y, ww) in [(260, 380), (300, 260), (360, 440), (400, 300)]) {
    img.fillRect(im, x1: (w - ww) ~/ 2, y1: y, x2: (w + ww) ~/ 2, y2: y + 16, color: img.ColorUint8.rgb(60, 66, 80));
  }
  img.fillRect(im, x1: 0, y1: h - 60, x2: w, y2: h, color: band);
  return Uint8List.fromList(img.encodePng(im));
}

const _a1 = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1', _a2 = 'b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2';
final _pics = {_a1: _schoolCover(), _a2: _schoolCover(hue: 1)};

PaperCoverSpec _spec(String scene) => switch (scene) {
      'designed' => PaperCoverSpec(university: t('جامعة القاهرة', 'Cairo University'), answer: const AnswerCoverSpec(same: true)),
      'empty' => const PaperCoverSpec(mode: CoverMode.uploaded),
      _ => PaperCoverSpec(
          mode: CoverMode.uploaded,
          upload: const CoverUpload(assetId: _a1, page: 2, pages: 4, width: 1240, height: 1754, name: 'midterm-cover-2026.pdf'),
          stamp: const CoverStamp(on: true, place: CoverPlace.bottom),
          answer: const AnswerCoverSpec(mode: CoverMode.uploaded, upload: CoverUpload(assetId: _a2, name: 'answer-booklet-cover.png'))),
    };

class _Picker extends StatefulWidget {
  const _Picker(this.scene);
  final String scene;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  late PaperCoverSpec _s = _spec(widget.scene);
  late final _uni = TextEditingController(text: _s.university);

  @override
  Widget build(BuildContext context) => ExamCoverPickerBody(
        spec: _s,
        pictures: _pics,
        university: _uni,
        error: widget.scene == 'empty' ? t('الصورة أكبر من 2 ميجابايت', 'The picture is larger than 2 MB') : null,
        onDesign: () {},
        onSame: (v) => setState(() => _s = _s.copyWith(answer: (_s.answer ?? const AnswerCoverSpec()).copyWith(same: v))),
      );
}

final _shot = GlobalKey();

/// The real printed copy: cover + page 1, replayed from the PDF the app writes.
List<ReplayedPage>? _pages;

Future<List<ReplayedPage>> _printed() async {
  final rtl = AppConfig.lang == 'ar';
  final d = ExamPaperCopy.of(
      ExamPaperDoc(
        institution: rtl ? 'مدرسة النور الثانوية' : 'Al Noor High School',
        course: rtl ? 'الأحياء' : 'Biology',
        title: rtl ? 'اختبار منتصف الفصل' : 'Midterm exam',
        dateText: '1/12/2026',
        durationText: rtl ? '90 دقيقة' : '90 minutes',
        total: 10,
        sections: [
          PaperSection(title: '', instructions: '', questions: [
            PaperQuestion(number: 1, type: 'mcq_single', prompt: rtl ? 'أي غاز تمتصه النباتات؟' : 'Which gas do plants take in?', points: 2, options: ['CO2', 'O2', 'N2'], correct: {0}),
            PaperQuestion(number: 2, type: 'short_answer', prompt: rtl ? 'عرّف البناء الضوئي.' : 'Define photosynthesis.', points: 8),
          ]),
        ],
        instructions: [rtl ? 'اكتب اسمك.' : 'Write your name.'],
        rtl: rtl,
        studentName: rtl ? 'مريم حسن' : 'Mariam Hassan',
        qrPages: const ['NB1:SAMPLE.CODE'],
      ),
      [PaperPrintedId(labelAr: 'الرقم الأكاديمي', labelEn: 'Academic number', value: '2024000451'), PaperPrintedId(labelAr: 'الفصل', labelEn: 'Class', value: '3/B')]);
  final covered = paperWithDesign(d, cover: _spec('picker'), assets: _pics, coverCode: 'NBC:5.ABCDEFGHIJ');
  final s = PaperStyle.of(PaperTemplate.modern);
  Future<ByteData> f(String p) async => ByteData.sublistView(File(p).readAsBytesSync());
  final out = await examPaperPdfMany([covered], PaperTemplate.modern, regular: await f(s.regular), bold: await f(s.bold));
  return (await replayPdfPages(out.document!)).take(2).toList();
}

Widget _body(String scene, BuildContext context) {
  if (scene == 'print') {
    return AppCard(
      child: DeliverPrintCard(
        scope: DeliverScope.students,
        onScope: (_) {},
        word: false,
        onWord: (_) {},
        studentCount: 32,
        versionCount: 2,
        showStudents: true,
        blank: 30,
        onBlank: (_) {},
        onPrint: () {},
        onMore: () {},
        coverText: coverSummaryText(_spec('picker')),
        onCover: () {},
      ),
    );
  }
  if (scene == 'pdf') {
    final pages = _pages ?? const [];
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 700;
      final views = [for (final p in pages) SizedBox(width: wide ? 380 : box.maxWidth, child: ReplayedPageView(page: p))];
      return wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final v in views) Padding(padding: const EdgeInsets.all(AppSpace.sm), child: v),
            ])
          : Column(children: [for (final v in views) Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: v)]);
    });
  }
  return _Picker(scene);
}

Widget _host({required bool dark, required String scene}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.materialTheme(dark: false),
      darkTheme: theme.materialTheme(dark: true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => RepaintBoundary(key: _shot, child: Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!)),
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: context.colors.background,
          appBar: AppHeader(title: scene == 'print' ? t('تجهيز الاختبار وتسليمه', 'Print and deliver') : t('صفحة الغلاف', 'Cover page')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
            child: AppWidthBox(width: scene == 'pdf' ? AppWidth.wide : AppWidth.form, child: _body(scene, context)),
          ),
        ),
      ),
    ),
  );
}

Future<void> _render(WidgetTester tester, String name) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in const [Size(390, 844), Size(1440, 900), Size(391, 2000)]) {
      for (final lang in const ['ar', 'en']) {
        AppConfig.lang = lang;
        if (name == 'pdf') _pages = await tester.runAsync(_printed);
        for (final dark in const [false, true]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(dark: dark, scene: name));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (name != 'pdf') await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));   // Image.memory decodes
          await tester.pump();
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(find.byKey(_shot), matchesGoldenFile('goldens/exam_cover_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'));
        }
      }
    }
  } finally {
    AppConfig.lang = prevLang;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }
}

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    SharedPreferences.setMockInitialValues({});
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('picker', (t) => _render(t, 'picker'));
  testWidgets('designed', (t) => _render(t, 'designed'));
  testWidgets('empty', (t) => _render(t, 'empty'));
  testWidgets('print', (t) => _render(t, 'print'));
  testWidgets('pdf', (t) => _render(t, 'pdf'));
}
