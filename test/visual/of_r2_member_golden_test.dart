// VISUAL review renders for the organization flow overhaul, agent r2: the member home (OrgMemberHomeBody inside the
// standalone page frame), the member space (news · departments · requests · complaints), the older "today" agenda,
// the student / teacher "My organization" tab and the parent's organization view, drawn with the app's real fonts and
// theme at 390x844 and 1440x900, Arabic and English, light and dark. PNGs go to R2_RENDERS (default: the session
// scratchpad `renders/r2`), NEVER into the repo's goldens. Not a CI suite; compared by eye.
//
//   flutter test test/visual/of_r2_member_golden_test.dart [--plain-name member]
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart' show RequestOptions;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/org/org_home_tab.dart';
import 'package:flutter_education_app/features/org/org_member_dashboard.dart';
import 'package:flutter_education_app/features/org/org_member_space.dart';
import 'package:flutter_education_app/features/org/org_member_today.dart';
import 'package:flutter_education_app/features/org/org_providers.dart';
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_education_app/features/messaging/notification/notifications_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import 'home_screens_golden_test.dart' show pubspecFonts;

const _defaultOut = 'C:/Users/ahmed/AppData/Local/Temp/claude/d--platform-nextbrain-nextbrain-front/0e859cae-9c6d-4a5f-88c5-2a467763d516/scratchpad/renders/r2';

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

final _shot = GlobalKey();
String tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Widget _host(Widget child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>(create: (_) => NotificationsProvider()),
        ChangeNotifierProvider<OrgSession>(create: (_) => OrgSession()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.materialTheme(dark: false),
        darkTheme: theme.materialTheme(dark: true),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, w) => Directionality(textDirection: rtl ? TextDirection.rtl : TextDirection.ltr, child: w!),
        home: RepaintBoundary(
          key: _shot,
          child: Builder(builder: (context) => Scaffold(backgroundColor: context.colors.background, body: child)),
        ),
      ),
    ),
  );
}

Future<void> _frames(WidgetTester tester, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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

Future<void> _savePng(WidgetTester tester, String file) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final out = File('${Platform.environment['R2_RENDERS'] ?? _defaultOut}/$file');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _render(WidgetTester tester, String name, Widget Function(Size size) build,
    {List<Size> sizes = const [Size(390, 844), Size(1440, 900)], Future<void> Function(WidgetTester)? after}) async {
  final prevLang = AppConfig.lang;
  debugDisableShadows = false;
  try {
    for (final size in sizes) {
      for (final lang in const ['ar', 'en']) {
        for (final dark in const [false, true]) {
          AppConfig.lang = lang;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_host(build(size), dark: dark));
          await _frames(tester);
          if (after != null) await after(tester);
          for (var i = 0; i < 4; i++) {
            final extra = _hiddenExtent(tester);
            if (extra < 1) break;
            final h = math.min(5000.0, tester.view.physicalSize.height + extra);
            if (h <= tester.view.physicalSize.height) break;
            tester.view.physicalSize = Size(size.width, h);
            await _frames(tester, 6);
          }
          final e = tester.takeException();
          expect(e, isNull, reason: '$name ${size.width.toInt()} $lang ${dark ? 'dark' : 'light'}: $e');
          await _savePng(tester, '${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png');
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

// ── sample data ──────────────────────────────────────────────────────────────

final _now = DateTime.utc(2026, 11, 4, 7, 0); // 09:00 in Cairo
String _iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', '');

Map<String, dynamic> _org() => {
      'id': 4,
      'status': 'approved',
      'type': 'university',
      'name_ar': 'جامعة النيل الأهلية',
      'name_en': 'Nile National University',
      'color': '#2563EB',
    };

Map<String, dynamic> _teacherEntry() => {
      'organization': _org(),
      'roles': ['teacher'],
      'manage': {
        'is_admin': false,
        'permissions': {},
        'departments': [
          {'id': 1, 'name_ar': 'قسم علوم الحاسب', 'name_en': 'Computer science department', 'via': 'dept', 'modules': {'forms': ['view', 'approve'], 'complaints': ['view']}},
        ],
        'sub_orgs': [],
      },
      'todo': {'total': 4, 'overdue': 1, 'due_soon': 2},
      'approvals': {'total': 6, 'form_responses': 3, 'complaints': 2, 'overdue_complaints': 1, 'assigned_to_me': 1, 'join_requests': 0, 'unit_requests': 0},
      'news': 2,
    };

Map<String, dynamic> _studentEntry() => {
      'organization': _org(),
      'roles': ['student'],
      'manage': null,
      'todo': {'total': 2, 'overdue': 0, 'due_soon': 1},
      'approvals': {'total': 0},
      'news': 3,
    };

Map<String, dynamic> _event(String id, Duration from, Duration to, String ar, String en, {String source = 'timetable', String? kind, String? loc}) => {
      'id': id,
      'source': source,
      'title': tr(ar, en),
      'starts_at': _iso(_now.add(from)),
      'ends_at': _iso(_now.add(to)),
      'org_id': 4,
      'org': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
      'kind': kind,
      'location': loc,
    };

Map<String, dynamic> _inboxRow(String key, String ar, String en, {String segment = 'todo', bool mandatory = false}) => {
      'key': key,
      'kind': 'form',
      'segment': segment,
      'title': tr(ar, en),
      'org_id': 4,
      'organization': {'id': 4, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
      'due_at': _iso(_now.add(const Duration(hours: 20))),
      'created_at': _iso(_now.subtract(const Duration(hours: 3))),
      'mandatory': mandatory,
    };

MeHome _me() => MeHome.fromJson({
      'today': [
        _event('a', const Duration(hours: -1, minutes: -30), const Duration(minutes: -15), 'تراكيب البيانات', 'Data structures', loc: tr('قاعة 12', 'Hall 12')),
        _event('b', const Duration(minutes: -10), const Duration(minutes: 50), 'معمل الشبكات', 'Networks lab', kind: 'lab', loc: tr('معمل 3', 'Lab 3')),
        _event('c', const Duration(hours: 3), const Duration(hours: 4), 'اختبار قصير: الإحصاء', 'Quiz: Statistics', source: 'exam'),
      ],
      'inbox_preview': [
        _inboxRow('f1', 'اعتماد درجات أعمال السنة', 'Approve coursework marks', mandatory: true),
        _inboxRow('f2', 'نموذج توزيع المعامل', 'Lab allocation form'),
        _inboxRow('n1', 'اجتماع مجلس القسم الأحد', 'Department council on Sunday', segment: 'news'),
      ],
    });

Widget _memberHome(Map<String, dynamic> entry, {bool empty = false, bool standalone = true}) {
  final me = _me();
  return SingleChildScrollView(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (standalone)
            AppPageHeader(
              title: tr('جامعة النيل الأهلية', 'Nile National University'),
              subtitle: orgRolesLine(entry),
              icon: Icons.apartment_rounded,
              bottom: const Row(children: [Expanded(child: SizedBox(height: 44)), SizedBox(width: 8)]),
            ),
          OrgMemberHomeBody(
            entry: entry,
            showPicker: !standalone,
            today: empty ? const [] : me.todayOf(4),
            inbox: empty ? const [] : me.inboxPreviewOf(4),
            now: _now,
            onPick: () {},
            onOpenEvent: (_) {},
            onInboxClosed: () {},
            news: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(child: Text(tr('جدول الفصل الدراسي الثاني منشور الآن', 'The second-term timetable is now published'))),
            ),
          ),
        ]),
      ),
    ),
  );
}

Object? _schedule(RequestOptions _) => {
      'items': [
        {
          'items': [
            {'slot_id': 1, 'day': 'wednesday', 'start_time': '09:00', 'end_time': '10:30', 'course': tr('تراكيب البيانات', 'Data structures'), 'room': tr('قاعة 12', 'Hall 12'), 'teacher': tr('د. منى عادل', 'Dr. Mona Adel'), 'kind': 'lecture'},
            {'slot_id': 2, 'day': 'wednesday', 'start_time': '11:00', 'end_time': '12:30', 'course': tr('معمل الشبكات', 'Networks lab'), 'room': tr('معمل 3', 'Lab 3'), 'kind': 'lab'},
            {'slot_id': 3, 'day': 'thursday', 'start_time': '10:00', 'end_time': '11:30', 'course': tr('الإحصاء', 'Statistics'), 'room': tr('قاعة 4', 'Hall 4')},
          ],
          'extras': [],
        }
      ]
    };

Map<String, dynamic> _mix() => {
      'org_weight': 70,
      'organizations': [_org(), {..._org(), 'id': 5, 'name_ar': 'كلية الهندسة', 'name_en': 'Faculty of Engineering'}],
      'required': [
        {'kind': 'form', 'id': 9, 'org_id': 4, 'title': tr('نموذج تحديث البيانات', 'Update your details form')},
      ],
    };

List<Map<String, dynamic>> _departments() => [
      {'id': 1, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs', 'color': '#2563EB', 'description': tr('خدمات الطلاب والأنشطة', 'Student services and activities'), 'location': tr('المبنى الرئيسي - الدور الأرضي', 'Main building, ground floor'), 'office_hours': tr('الأحد–الخميس 9–3', 'Sun–Thu 9:00–15:00'), 'email': 'students@nile.edu.eg', 'phone': '+20 2 5555 1234', 'accepts_complaints': true, 'features': ['forms', 'complaints']},
      {'id': 2, 'name_ar': 'الدراسات العليا', 'name_en': 'Graduate studies', 'color': '#7C3AED', 'location': tr('مبنى ب', 'Building B'), 'features': ['forms', 'announcements']},
      {'id': 3, 'name_ar': 'المكتبة', 'name_en': 'Library', 'color': '#059669', 'features': ['materials']},
    ];

ParentOrgView _parentView() => ParentOrgView.parse({
      'org': {'id': 9, 'name_ar': 'جامعة النيل الأهلية', 'name_en': 'Nile National University'},
      'student': {'id': 1, 'name': tr('سارة أحمد', 'Sara Ahmed')},
      'today': [
        {'title': tr('الجبر المتقدم', 'Advanced algebra'), 'course_name': tr('الرياضيات', 'Mathematics'), 'starts_at': '2026-11-04T07:00:00', 'ends_at': '2026-11-04T08:30:00', 'room': tr('قاعة 12', 'Hall 12'), 'status': 'scheduled'},
        {'title': tr('الفيزياء', 'Physics'), 'starts_at': '2026-11-04T09:00:00', 'ends_at': '2026-11-04T10:00:00', 'mode': 'online', 'status': 'changed'},
        {'title': tr('الكيمياء العضوية', 'Organic chemistry'), 'starts_at': '2026-11-04T10:30:00', 'status': 'cancelled'},
      ],
      'week': [
        {'title': tr('معمل الكيمياء', 'Chemistry lab'), 'course_name': tr('الكيمياء', 'Chemistry'), 'starts_at': '2026-11-05T08:00:00', 'ends_at': '2026-11-05T09:00:00', 'status': 'scheduled'},
        {'title': tr('الإحصاء', 'Statistics'), 'starts_at': '2026-11-05T10:00:00', 'ends_at': '2026-11-05T11:30:00', 'room': tr('قاعة 4', 'Hall 4'), 'status': 'scheduled'},
        {'title': tr('الجبر المتقدم', 'Advanced algebra'), 'starts_at': '2026-11-08T07:00:00', 'ends_at': '2026-11-08T08:30:00', 'status': 'scheduled'},
      ],
      'announcements': [
        {'id': 3, 'title': tr('موعد الاختبارات النصفية', 'Midterm exam dates'), 'body': tr('تبدأ الاختبارات النصفية يوم الأحد 15 نوفمبر، والجدول التفصيلي على بوابة الطالب.', 'Midterms start on Sunday 15 November; the detailed schedule is on the student portal.'), 'published_at': '2026-11-03T10:00:00'},
      ],
      'grades': [
        {'course_name': tr('الرياضيات', 'Mathematics'), 'grade': 'A', 'points': 3.7, 'term_label': tr('الخريف 2026', 'Fall 2026'), 'published_at': '2026-11-01T10:00:00'},
        {'course_name': tr('الفيزياء', 'Physics'), 'grade': 'B+', 'points': 3.3, 'term_label': tr('الخريف 2026', 'Fall 2026'), 'published_at': '2026-11-01T10:00:00'},
      ],
      'attendance': {'present': 38, 'absent': 3, 'late': 4},
    });

void main() {
  late FakeApi fake;

  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockRequestPlugins();
    AppConfig.setOrgsEnabled(true);
    AppModeController.applyContext = (_) {};
    fake = FakeApi({
      'GET /api/v1/home/mix': (_) => _mix(),
      'GET /api/v1/org/public/schedule/me': _schedule,
      'GET /api/v1/org/public/4/departments': (_) => {'items': _departments()},
      'GET /api/v1/org/public/5/departments': (_) => {'items': _departments()},
      'GET /api/v1/org/public/me/forms': (_) => {
            'items': [
              {'id': 1, 'title': tr('طلب إفادة قيد', 'Enrollment certificate request'), 'can_answer': true, 'closes_at': '2026-11-30T00:00:00', 'department': {'name_ar': 'شؤون الطلاب', 'name_en': 'Student affairs'}},
              {'id': 2, 'title': tr('استبيان جودة المقرر', 'Course quality survey'), 'can_answer': false},
            ]
          },
      'GET /api/v1/org/public/me/form-responses': (_) => {
            'items': [
              {'org_id': 4, 'form_title': tr('طلب تأجيل', 'Deferral request'), 'ref': 'REQ-0042', 'status': 'submitted', 'created_at': '2026-11-02T08:00:00'},
              {'org_id': 4, 'form_title': tr('إفادة قيد', 'Enrollment letter'), 'ref': 'REQ-0039', 'status': 'approved', 'created_at': '2026-10-28T08:00:00', 'reviewer_note': tr('جاهزة للاستلام', 'Ready for pickup')},
            ]
          },
      'GET /api/v1/org/public/me/complaints': (_) => {
            'items': [
              {'id': 1, 'org_id': 4, 'subject': tr('تعطل التكييف في قاعة 12', 'Air conditioning broken in Hall 12'), 'ref': 'CMP-0007', 'status': 'in_progress', 'unread': true, 'updated_at': '2026-11-03T08:00:00'},
            ]
          },
    }, latency: Duration.zero, fallback: (_) => {'items': const [], 'total': 0});
    fake.install();
  });

  tearDown(() => fake.uninstall());

  testWidgets('member home: teacher with a manage scope', (tester) async {
    await _render(tester, 'member_home_teacher', (_) => _memberHome(_teacherEntry()));
  });

  testWidgets('member home: student', (tester) async {
    await _render(tester, 'member_home_student', (_) => _memberHome(_studentEntry()), sizes: const [Size(390, 844)]);
  });

  testWidgets('member home: student with a free day', (tester) async {
    await _render(tester, 'member_home_empty', (_) => _memberHome({..._studentEntry(), 'todo': {'total': 0}, 'news': 0}, empty: true),
        sizes: const [Size(390, 844)]);
  });

  testWidgets('member home: embedded (hero)', (tester) async {
    await _render(tester, 'member_home_embedded', (_) => _memberHome(_studentEntry(), standalone: false), sizes: const [Size(390, 844)]);
  });

  for (final (tab, name) in [(0, 'news'), (1, 'depts'), (2, 'requests'), (3, 'complaints')]) {
    testWidgets('member space: $name', (tester) async {
      await _render(tester, 'member_space_$name', (_) => OrgMemberSpace(org: _org(), initialTab: tab));
    });
  }

  testWidgets('member today agenda (older server)', (tester) async {
    await _render(tester, 'member_today', (_) => const SingleChildScrollView(child: Padding(padding: EdgeInsets.only(top: 16), child: OrgTodayAgenda(orgId: 4))),
        sizes: const [Size(390, 844)]);
  });

  testWidgets('org tab of the home', (tester) async {
    await _render(tester, 'org_home_tab', (_) => const SingleChildScrollView(child: OrgHomeTab()));
  });

  testWidgets('parent org view', (tester) async {
    await _render(tester, 'parent_org', (_) => ParentOrgScreen(studentId: 1, studentName: tr('سارة أحمد', 'Sara Ahmed'), org: const ParentOrgRef(id: 9, nameAr: 'جامعة النيل الأهلية', nameEn: 'Nile National University'), loader: (_, _) async => _parentView()));
  });

  testWidgets('parent org list card', (tester) async {
    await _render(
        tester,
        'parent_org_list',
        (_) => SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ParentOrgChildrenList(
                  children: [
                    ParentChildOrgs(studentId: 1, name: tr('سارة أحمد', 'Sara Ahmed'), orgs: const [ParentOrgRef(id: 9, nameAr: 'جامعة النيل الأهلية', nameEn: 'Nile National University'), ParentOrgRef(id: 10, nameAr: 'أكاديمية المستقبل', nameEn: 'Future Academy', status: 'pending')]),
                    ParentChildOrgs(studentId: 2, name: tr('عمر أحمد', 'Omar Ahmed'), orgs: const [ParentOrgRef(id: 11, nameAr: 'مدرسة الأمل', nameEn: 'Hope School')]),
                  ],
                  onOpen: (_, _) {},
                ),
              ),
            ),
        sizes: const [Size(390, 844)]);
  });
}
