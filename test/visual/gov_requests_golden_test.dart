// Visual review renders of the request pages of D-140 / D-141, compared by eye like the other test/visual files
// (NOT a CI suite):
//
//   flutter test test/visual/gov_requests_golden_test.dart --update-goldens [--plain-name submit]
//
// → test/visual/goldens/gov_requests_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   submit        a department's staff member files a request for someone outside the system: the "For" choice with
//                 the person's details (one field refused), the entity's approval steps, two attachments
//   submit_member the same form for a member picked from the list
//   detail        the item page for the person handling it: who it is for, the approval chain at step 2 of 3 after a
//                 resubmit (the first round folded), attachments, export
//   rejected      the requester's view of a rejected item: the reason and "Edit and resubmit"
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
import 'package:flutter_education_app/features/org/governance/gov_item_screen.dart';
import 'package:flutter_education_app/features/org/governance/gov_member_pages.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_request_parts.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/gov_filter_test.dart' show sampleEntityJson;
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
String _tr(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

Entity _entity() => Entity.fromJson({
      ...sampleEntityJson(kind: 'scientific'),
      'name_ar': 'قسم الفيزياء',
      'name_en': 'Physics Department',
      'description': null,
      'can_submit_for_others': true,
      'categories': [
        {'id': 3, 'dept_id': 5, 'key': 'letters', 'name_ar': 'إفادات وشهادات', 'name_en': 'Letters & certificates', 'kind': 'request', 'is_active': true, 'order': 1},
        {'id': 4, 'dept_id': 5, 'key': 'leave', 'name_ar': 'إجازات', 'name_en': 'Leave', 'kind': 'request', 'is_active': true, 'order': 2},
      ],
      'chain': [
        {'kind': 'manager', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
        {'kind': 'entity', 'dept_id': 2, 'label_ar': 'شؤون الطلاب', 'label_en': 'Student Affairs'},
        {'kind': 'council', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
      ],
    });

const _files = [
  GovAttachment(id: 31, name: 'birth certificate.pdf', ext: 'pdf', size: 182000, preview: true),
  GovAttachment(id: 32, name: 'national id.jpg', ext: 'jpg', size: 940000, preview: true),
];

Widget _submit({required String kind}) {
  final e = _entity();
  final ctl = GovForControllers()
    ..name.text = _tr('منى سعيد عبد الرحمن', 'Mona Saeed Abdelrahman')
    ..relation.text = _tr('ولية أمر', 'Parent')
    ..phone.text = '+20 100 123 4567'
    ..email.text = 'mona.saeed@example'
    ..nationalId.text = '29901011234567';
  final draft = BeneficiaryDraft(kind: 'external');
  ctl.fill(draft);
  return BasePage(
    useWebCard: true,
    maxWith: 760,
    enableFooterWidget: false,
    child: SafeArea(
      child: Column(children: [
        ScreenAppBar(title: _tr('معاملة جديدة', 'New request')),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: GovSubmitForm(
              entities: [e],
              entity: e,
              category: e.categories.first,
              type: 'request',
              title: TextEditingController(text: _tr('شهادة قيد لابنها الطالب أحمد', 'Enrolment letter for her son Ahmed')),
              body: TextEditingController(text: _tr('تحتاجها لتقديمها إلى السفارة قبل نهاية الشهر.', 'She needs it for the embassy before the end of the month.')),
              priority: 'high',
              anonymous: false,
              attachments: _files,
              onEntity: (_) {},
              onCategory: (_) {},
              onType: (_) {},
              onPriority: (_) {},
              onAnonymous: (_) {},
              onAddAttachment: () {},
              onRemoveAttachment: (_) {},
              onSubmit: () {},
              forOthers: true,
              forWho: GovForSection(
                kind: kind,
                member: kind == 'member' ? GovPerson(id: 9, name: _tr('سارة أحمد محمود', 'Sara Ahmed Mahmoud')) : null,
                controllers: ctl,
                errors: kind == 'external' ? draft.validate() : const {},
                onKind: (_) {},
                onPickMember: () {},
                onClearMember: () {},
              ),
            ),
          ),
        ),
      ]),
    ),
  );
}

Map<String, dynamic> _itemJson({bool rejected = false}) => {
      'id': 41,
      'org_id': 1,
      'ref': 'W-2026-000041',
      'type': 'request',
      'title': _tr('شهادة قيد لابنها الطالب أحمد', 'Enrolment letter for her son Ahmed'),
      'body': _tr('تحتاجها لتقديمها إلى السفارة قبل نهاية الشهر. أرفقت شهادة الميلاد وصورة الهوية.',
          'She needs it for the embassy before the end of the month. The birth certificate and the id are attached.'),
      'status': rejected ? 'rejected' : 'pending_approval',
      'priority': 'high',
      'category': {'id': 3, 'dept_id': 5, 'key': 'letters', 'name_ar': 'إفادات وشهادات', 'name_en': 'Letters & certificates', 'kind': 'request'},
      'source': {'dept': null, 'user': {'id': 7, 'name': _tr('د. عمر حسن', 'Dr. Omar Hassan')}, 'anonymous': false},
      'owner_dept': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs', 'kind': 'service'},
      'assignee': null,
      'due_at': '2026-11-03T10:00:00',
      'decided_at': rejected ? '2026-11-01T11:00:00' : null,
      'decision': rejected
          ? {'outcome': 'rejected', 'by': {'id': 12, 'name': _tr('أ. ليلى فؤاد', 'Ms. Laila Fouad')}, 'at': '2026-11-01T11:00:00',
              'note': _tr('ينقص توقيع ولي الأمر على النموذج', 'The parent\'s signature on the form is missing'), 'via': 'head'}
          : null,
      'attachments': [for (final a in _files) {'id': a.id, 'name': a.name, 'ext': a.ext, 'size': a.size, 'kind': 'file', 'preview': true}],
      'tags': [],
      'version': 4,
      'created_at': '2026-10-30T08:00:00',
      'updated_at': '2026-11-01T09:00:00',
      'overdue': false,
      'beneficiary': {
        'kind': 'external',
        'name': _tr('منى سعيد عبد الرحمن', 'Mona Saeed Abdelrahman'),
        'relation': _tr('ولية أمر', 'Parent'),
        'user': null,
        if (!rejected) ...{'phone': '+20 100 123 4567', 'email': 'mona.saeed@example.com', 'national_id': '29901011234567'},
      },
      'chain_step': {'index': 1, 'count': 3, 'kind': 'entity', 'round': 2},
      'chain': {
        'round': rejected ? 1 : 2,
        'current': 1,
        'steps': [
          {'kind': 'manager', 'status': 'approved', 'by': {'id': 11, 'name': _tr('أ.د. هدى السيد', 'Prof. Huda Elsayed')}, 'at': '2026-11-01T09:00:00',
           'note': _tr('مستوفٍ — يُحال لشؤون الطلاب', 'Complete — on to Student Affairs'), 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
          {'kind': 'entity', 'dept_id': 2, 'status': rejected ? 'rejected' : 'current', 'at': '2026-11-01T09:00:00',
           if (rejected) ...{'by': {'id': 12, 'name': _tr('أ. ليلى فؤاد', 'Ms. Laila Fouad')}, 'note': _tr('ينقص توقيع ولي الأمر على النموذج', 'The parent\'s signature on the form is missing')},
           'label_ar': 'شؤون الطلاب', 'label_en': 'Student Affairs'},
          {'kind': 'council', 'status': 'waiting', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
        ],
        'rounds': rejected
            ? []
            : [
                {
                  'round': 1,
                  'steps': [
                    {'kind': 'manager', 'status': 'approved', 'by': {'id': 11, 'name': 'Prof. Huda'}, 'at': '2026-10-30T10:00:00', 'label_ar': 'مدير الجهة', 'label_en': 'Manager'},
                    {'kind': 'entity', 'status': 'rejected', 'by': {'id': 12, 'name': 'Ms. Laila'}, 'at': '2026-10-31T10:00:00', 'note': 'Signature missing', 'label_ar': 'شؤون الطلاب', 'label_en': 'Student Affairs'},
                    {'kind': 'council', 'status': 'waiting', 'label_ar': 'مجلس القسم', 'label_en': 'Department council'},
                  ],
                },
              ],
      },
      'pending_route': null,
      'routes': [],
      'events': [
        {'id': 1, 'kind': 'created', 'actor': {'id': 7, 'name': _tr('د. عمر حسن', 'Dr. Omar Hassan')}, 'data': {'type': 'request', 'status': 'open'}, 'created_at': '2026-10-30T08:00:00'},
      ],
      'agenda': [],
      'can': rejected
          ? {'view': true, 'comment': true, 'resubmit': true}
          : {'view': true, 'route': true, 'decide': true, 'comment': true, 'edit': true, 'export': true},
    };

Widget _detail({bool rejected = false}) => BasePage(
      useWebCard: true,
      maxWith: 900,
      enableFooterWidget: false,
      child: SafeArea(
        child: Column(children: [
          const ScreenAppBar(title: 'W-2026-000041'),
          Expanded(
            child: GovItemBody(
              item: WorkItem.fromJson(_itemJson(rejected: rejected)),
              member: rejected,
              currentUserId: rejected ? 7 : 12,
              onDecide: rejected ? null : (_) {},
              onRoute: rejected ? null : () {},
              onStatus: rejected ? null : () {},
              onExport: rejected ? null : () {},
              onResubmit: rejected ? () {} : null,
              onOpenAttachment: (_) {},
            ),
          ),
        ]),
      ),
    );

Widget _host(Widget Function() child, {required bool dark}) {
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
      home: RepaintBoundary(key: _shot, child: Builder(builder: (_) => child())),
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
          await tester.pumpWidget(_host(build, dark: dark));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          for (var i = 0; i < 4; i++) {
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
            matchesGoldenFile('goldens/gov_requests_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

  testWidgets('submit', (t) => _render(t, 'submit', () => _submit(kind: 'external')));
  testWidgets('submit_member', (t) => _render(t, 'submit_member', () => _submit(kind: 'member')));
  testWidgets('detail', (t) => _render(t, 'detail', () => _detail()));
  testWidgets('rejected', (t) => _render(t, 'rejected', () => _detail(rejected: true)));
}
