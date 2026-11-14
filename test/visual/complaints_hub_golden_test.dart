// Visual review renders of the profile's Complaints page (D-086), compared by eye like the other test/visual
// files (NOT a CI suite):
//
//   flutter test test/visual/complaints_hub_golden_test.dart --update-goldens [--plain-name staff]
//
// → test/visual/goldens/complaints_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   student   a student's My complaints: a new reply, an organization complaint waiting for them, closed ones
//   staff     a teacher who is also department staff, on To resolve: overdue, due soon, a course complaint
//   empty     a new account: nothing filed yet
//   where     the "Where should it go?" sheet of a member of two organizations
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_widgets.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_provider.dart';
import 'package:flutter_education_app/features/profile/compalints/new_complaint_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
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
  // the app bar's back arrow is CupertinoIcons.back (package font)
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// 09:00 in Cairo on a Wednesday.
final _now = DateTime.utc(2026, 10, 28, 7, 0);
DateTime _ago({int d = 0, int h = 0, int m = 0}) => _now.subtract(Duration(days: d, hours: h, minutes: m));

const _cairo = HubName('جامعة القاهرة', 'Cairo University');
const _affairs = HubName('شؤون الطلاب', 'Student Affairs');
const _it = HubName('الدعم التقني', 'IT Support');

List<HubRow> _studentRows() => [
      HubRow(
        source: HubSource.platform,
        id: 41,
        title: _tr('الفيديو يتوقف في المحاضرة الرابعة', 'Lecture 4 video keeps stopping'),
        snippet: _tr('يتوقف الفيديو عند الدقيقة 12 على الهاتف والكمبيوتر، جربت تحميله ولم ينجح.',
            'The video freezes at minute 12 on both my phone and laptop. Downloading it did not help.'),
        status: HubStatus.inProgress,
        category: 'technical',
        about: _tr('أساسيات بايثون', 'Python Fundamentals'),
        createdAt: _ago(d: 1, h: 3),
        updatedAt: _ago(m: 25),
        unread: true,
        replies: 2,
      ),
      HubRow(
        source: HubSource.org,
        id: 7,
        ref: 'C-000007',
        title: _tr('تأخر إصدار إفادة القيد', 'My enrolment letter is late'),
        snippet: _tr('طلبت الإفادة منذ أسبوع ولم تصلني حتى الآن، وأحتاجها للسفارة يوم الأحد.',
            'I requested it a week ago and still have nothing — I need it for the embassy on Sunday.'),
        status: HubStatus.waiting,
        priority: 'high',
        category: 'administrative',
        org: _cairo,
        department: _affairs,
        orgId: 3,
        createdAt: _ago(d: 2),
        updatedAt: _ago(h: 3),
        replies: 1,
      ),
      HubRow(
        source: HubSource.platform,
        id: 33,
        title: _tr('تم خصم المبلغ مرتين', 'I was charged twice'),
        snippet: _tr('دفعت اشتراك الشهر مرة واحدة لكن ظهر خصمان في كشف الحساب.',
            'I paid the monthly plan once, but my bank statement shows two charges.'),
        status: HubStatus.resolved,
        category: 'payment',
        createdAt: _ago(d: 9),
        updatedAt: _ago(d: 6),
        replies: 3,
        attachments: 1,
      ),
      HubRow(
        source: HubSource.org,
        id: 5,
        ref: 'C-000005',
        title: _tr('التكييف لا يعمل في القاعة 3', 'The air conditioning in hall 3 is broken'),
        snippet: _tr('القاعة حارة جداً في محاضرات الظهيرة.', 'The hall is very hot in the afternoon lectures.'),
        status: HubStatus.closed,
        priority: 'low',
        category: 'facilities',
        org: _cairo,
        department: _it,
        orgId: 3,
        createdAt: _ago(d: 20),
        updatedAt: _ago(d: 14),
        replies: 2,
      ),
    ];

List<HubRow> _staffMine() => [
      HubRow(
        source: HubSource.platform,
        id: 52,
        title: _tr('لم يصل تحويل أرباح أكتوبر', 'My October payout has not arrived'),
        snippet: _tr('الحالة "تم التحويل" منذ 5 أيام.', 'It has said "sent" for five days.'),
        status: HubStatus.open,
        category: 'payment',
        createdAt: _ago(d: 1),
        updatedAt: _ago(d: 1),
      ),
    ];

List<HubRow> _staffResolve() => [
      HubRow(
        source: HubSource.org,
        id: 11,
        ref: 'C-000011',
        title: _tr('لم تُرصد درجة أعمال السنة', 'My coursework grade is missing'),
        snippet: _tr('درجة أعمال السنة في مقرر قواعد البيانات غير ظاهرة، والامتحان النهائي الأسبوع القادم.',
            'The coursework grade for Databases is not showing and the final exam is next week.'),
        status: HubStatus.open,
        priority: 'urgent',
        category: 'academic',
        org: _cairo,
        department: _affairs,
        orgId: 3,
        sender: _tr('مريم عادل', 'Mariam Adel'),
        createdAt: _ago(d: 1, h: 3),
        updatedAt: _ago(d: 1, h: 3),
        dueAt: _ago(h: 3),
        unread: true,
        canAct: true,
        mine: false,
      ),
      HubRow(
        source: HubSource.org,
        id: 12,
        ref: 'C-000012',
        title: _tr('تأخر إصدار إفادة القيد', 'Enrolment letter is late'),
        snippet: _tr('طلبت الإفادة منذ أسبوع ولم تصلني حتى الآن.', 'I requested it a week ago and still have nothing.'),
        status: HubStatus.inProgress,
        priority: 'high',
        category: 'administrative',
        org: _cairo,
        department: _affairs,
        orgId: 3,
        anonymous: true,
        createdAt: _ago(d: 1, h: 18),
        updatedAt: _ago(h: 2),
        dueAt: _now.add(const Duration(hours: 5)),
        replies: 1,
        canAct: true,
        mine: false,
      ),
      HubRow(
        source: HubSource.platform,
        id: 61,
        title: _tr('الشرح سريع في درس الدوال', 'The functions lesson goes too fast'),
        snippet: _tr('أتمنى إضافة أمثلة محلولة أكثر قبل الواجب.', 'Could you add a few more worked examples before the homework?'),
        status: HubStatus.open,
        priority: 'medium',
        category: 'course_content',
        about: _tr('أساسيات بايثون', 'Python Fundamentals'),
        sender: _tr('يوسف حسن', 'Youssef Hassan'),
        createdAt: _ago(h: 6),
        updatedAt: _ago(h: 6),
        unread: true,
        canAct: true,
        mine: false,
      ),
      HubRow(
        source: HubSource.org,
        id: 9,
        ref: 'C-000009',
        title: _tr('مشكلة في بطاقة المكتبة', 'Library card does not work'),
        snippet: _tr('البطاقة لا تفتح البوابة منذ التجديد.', 'The card has not opened the gate since it was renewed.'),
        status: HubStatus.resolved,
        priority: 'low',
        category: 'facilities',
        org: _cairo,
        department: _affairs,
        orgId: 3,
        sender: _tr('سارة محمود', 'Sara Mahmoud'),
        createdAt: _ago(d: 4),
        updatedAt: _ago(d: 1),
        canAct: true,
        mine: false,
      ),
    ];

Widget _page(Widget body) => BasePage(
      useWebCard: true,
      maxWith: 1000,
      enableFooterWidget: false,
      child: SafeArea(child: Column(children: [ScreenAppBar(title: 'chub_title'.tr), Expanded(child: body)])),
    );

Widget _view({
  required HubSegment segment,
  required bool showToResolve,
  required List<HubRow> mine,
  required List<HubRow> toResolve,
  required TextEditingController search,
}) =>
    ComplaintsHubView(
      segment: segment,
      showToResolve: showToResolve,
      mine: mine,
      toResolve: toResolve,
      filter: defaultFilter(segment),
      query: '',
      now: _now,
      searchController: search,
      onSegment: (_) {},
      onFilter: (_) {},
      onNew: () {},
      onOpen: (_) {},
      onAction: (_, _) {},
      onRefresh: () async {},
      onClearFilters: () {},
    );

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
      builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
      home: RepaintBoundary(key: _shot, child: child),
    ),
  );
}

double _hiddenExtent(WidgetTester tester) {
  var extra = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis != Axis.vertical || !s.position.hasContentDimensions) continue;
    extra = math.max(extra, s.position.maxScrollExtent);
  }
  return extra;
}

Future<void> _render(WidgetTester tester, String name, Widget Function() build, {bool grow = true}) async {
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
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; grow && i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            tester.view.physicalSize = Size(size.width, math.min(4000, tester.view.physicalSize.height + extra));
            for (var j = 0; j < 4; j++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await expectLater(
            find.byKey(_shot),
            matchesGoldenFile('goldens/complaints_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  // the platform complaint form (New complaint → the app team), about a course
  testWidgets('form', (t) async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.getInstance();
    await _render(
      t,
      'form',
      () => MultiProvider(
        providers: [
          ChangeNotifierProvider<LangProvider>(create: (_) => LangProvider(storage: storage)),
          ChangeNotifierProvider<ComplaintProvider>(create: (_) => ComplaintProvider()),
        ],
        child: const NewComplaintScreen(formOnly: true, courseTitle: 'Python Fundamentals'),
      ),
    );
  });

  testWidgets('student', (t) {
    final search = TextEditingController();
    return _render(t, 'student', () => _page(_view(
        segment: HubSegment.mine, showToResolve: false, mine: _studentRows(), toResolve: const [], search: search)));
  });

  testWidgets('staff', (t) {
    final search = TextEditingController();
    return _render(t, 'staff', () => _page(_view(
        segment: HubSegment.toResolve, showToResolve: true, mine: _staffMine(), toResolve: _staffResolve(), search: search)));
  });

  testWidgets('empty', (t) {
    final search = TextEditingController();
    return _render(t, 'empty', () => _page(_view(
        segment: HubSegment.mine, showToResolve: false, mine: const [], toResolve: const [], search: search)), grow: false);
  });

  testWidgets('where', (t) => _render(
      t,
      'where',
      () => Builder(
            builder: (context) => Scaffold(
              backgroundColor: Colors.black54,
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Material(
                    color: context.colors.background,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: HubDestinationSheet(
                        orgs: const [(3, _cairo, null), (8, HubName('معهد النيل للغات', 'Nile Language Institute'), null)],
                        onApp: () {},
                        onOrg: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      grow: false));
}
