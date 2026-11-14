// Visual review renders of the Phase 7 advising screens (D-289, docs/advising/PHASE7.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_support_golden_test.dart --update-goldens [--plain-name requests]
//
// → test/visual/goldens/adv_support_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   requests          a director's request list: queues with counts, a request waiting on information, drafts
//   composer          a new accommodation request: type, accommodations, until, template, files, the chain preview
//   referral          a new referral to Healthcare
//   request_council   a request at the department council: the tracker, the vote so far, the chain, the history
//   needs_info        a request the director returned for information (overdue, escalated)
//   decided           an approved request, closed with the advisor's follow-up and the accommodations granted
//   review_sheet      the director's review sheet, asking for information
//   chain_editor      the organization's chain with a Student Affairs step
//   plan              support plans: active (one item ticking, one overdue), completed with its result
//   plan_editor       the plan editor with four items
//   accommodations    the organization's accommodations
//   support_360       the 360's Support section
//   hub               the student's blocks: requests, plan, accommodations
//   student_request   the student's own request at the council (postponed)
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
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/features/org/advising/adv_accommodations.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_plan.dart';
import 'package:flutter_education_app/features/org/advising/adv_request_chain_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_request_composer.dart';
import 'package:flutter_education_app/features/org/advising/adv_requests.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_360.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_hub.dart';
import 'package:flutter_education_app/features/org/advising/adv_support_models.dart';
import 'package:flutter_education_app/features/org/governance/gov_models.dart' show GovAttachment;
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart' show advCaseNow, sampleAdvProfileJson;
import '../org/adv_support_models_test.dart';
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

final _shot = GlobalKey();

Widget _host(Widget Function() child, {required bool dark}) {
  final theme = ThemeConfigProvider(api: ApiClient());
  final rtl = AppConfig.lang == 'ar';
  return ThemeConfigScope(
    provider: theme,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: displayTheme(theme.materialTheme(dark: false), const DisplayPrefs()),
      darkTheme: displayTheme(theme.materialTheme(dark: true), const DisplayPrefs()),
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
            matchesGoldenFile('goldens/adv_support_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

/// A sheet's content as the sheet shows it: padded, at most 640 wide, scrolling.
Widget _sheet(Widget child) => Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

bool get _ar => AppConfig.lang == 'ar';

AdvRequestView _request(String stage, {String kind = 'support'}) =>
    AdvRequestView(load: AdvLoad.ready, request: AdvRequest.fromJson(sampleAdvRequestJson(stage: stage, kind: kind)), onAction: (_) {}, onOpenStudent: () {}, onOpenAttachment: (_) {});

AdvSupportPlan _plan([String status = 'active']) => AdvSupportPlan.fromJson(sampleAdvPlanJson(status: status));

AdvRequestForm _form(AdvRequestDraft draft) => AdvRequestForm(
      options: AdvRequestOptions.fromJson(sampleAdvRequestOptionsJson()),
      draft: draft,
      title: TextEditingController(text: draft.referral ? (_ar ? 'متابعة طبية لضعف السمع' : 'Medical follow-up for hearing loss') : (_ar ? 'تسهيلات امتحانات الفصل الأول' : 'First-term exam accommodations')),
      body: TextEditingController(
          text: _ar
              ? 'الطالبة تعاني ضعفاً في السمع منذ سبتمبر، والسماعة في الصيانة حتى نهاية الشهر. التقرير الطبي مرفق.'
              : 'The student has had hearing loss since September; the hearing aid is being repaired until the end of the month. The medical report is attached.'),
      studentName: 'ليلى أحمد',
      preview: AdvChainPreview.fromJson(sampleAdvChainPreviewJson()),
      savedOnDevice: true,
      onKind: (_) {},
      onType: (_) {},
      onTarget: (_) {},
      onCategory: (_) {},
      onPriority: (_) {},
      onAccommodation: (_) {},
      onPickUntil: () {},
      onClearUntil: () {},
      onTemplate: (_) {},
      onAttach: () {},
      onOpenAttachment: (_) {},
      onRemoveAttachment: (_) {},
      onSaveDraft: () {},
      onSubmit: () {},
    );

AdvSupportPane _pane() => AdvSupportPane(
      load: AdvLoad.ready,
      summary: AdvSupportSummary.fromJson(sampleAdvSupportJson()),
      plans: [_plan(), _plan('completed')],
      onNewRequest: () {},
      onRefer: () {},
      onNewPlan: () {},
      onGrant: () {},
      onOpenRequest: (_) {},
      onSeeAll: () {},
      onTickItem: (_, _) {},
      onEditPlan: (_) {},
      onPlanStatus: (_) {},
      onEndAccommodation: (_) {},
    );

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  testWidgets('requests', (t) => _render(t, 'requests', () {
        return Scaffold(
          body: AdvRequestsView(
            load: AdvLoad.ready,
            query: const AdvRequestQuery(),
            manage: true,
            page: AdvPage.fromJson(sampleAdvRequestsJson(), AdvRequest.fromJson),
            onQueue: (_) {},
            onFilter: (_) {},
            onSearch: (_) {},
            onPage: (_) {},
            onOpen: (_) {},
            onNew: () {},
          ),
        );
      }));
  testWidgets('composer', (t) => _render(t, 'composer', () {
        return _sheet(_form(AdvRequestDraft(
          supportType: 'accommodation',
          categoryId: 7,
          priority: 'high',
          accommodations: const ['extra_time', 'front_seating', 'recorded_lectures'],
          accommodationUntil: DateTime(2027, 1, 31),
          templateId: 5,
          attachments: const [
            GovAttachment(name: 'medical_report.pdf', id: 71, ext: 'pdf', size: 248000),
            GovAttachment(name: 'audiogram.png', id: 72, ext: 'png', size: 91000),
          ],
        )));
      }));
  testWidgets('referral', (t) => _render(t, 'referral', () => _sheet(_form(const AdvRequestDraft(kind: 'referral', targetDeptId: 41, priority: 'normal')))));
  testWidgets('request_council', (t) => _render(t, 'request_council', () => Scaffold(body: _request('at_department_council'))));
  testWidgets('needs_info', (t) => _render(t, 'needs_info', () => Scaffold(body: _request('needs_info'))));
  testWidgets('decided', (t) => _render(t, 'decided', () => Scaffold(body: _request('closed'))));
  testWidgets('review_sheet', (t) => _render(t, 'review_sheet', () {
        return _sheet(AdvReviewForm(
          request: AdvRequest.fromJson(sampleAdvRequestJson(stage: 'submitted')),
          note: TextEditingController(text: _ar ? 'أرفق التقرير الطبي الأحدث من المستشفى الجامعي.' : 'Attach the latest medical report from the university hospital.'),
          decision: 'needs_info',
          onDecision: (_) {},
          onSubmit: () {},
        ));
      }));
  testWidgets('chain_editor', (t) => _render(t, 'chain_editor', () {
        final c = AdvChainConfig.fromJson(sampleAdvChainJson());
        final org = AdvChainScopeChoice(type: 'org', label: _ar ? 'المؤسسة' : 'Organization');
        return Scaffold(
          body: AdvChainEditorView(
            config: c,
            scopes: [org, AdvChainScopeChoice(type: 'program', ref: '11', label: _ar ? 'برنامج: هندسة البرمجيات' : 'Program: Software Engineering')],
            scope: org,
            steps: c.orgSteps,
            dirty: true,
            onScope: (_) {},
            onAddScope: () {},
            onInherit: (_) {},
            onReset: () {},
            onAdd: (_) {},
            onMove: (_, _) {},
            onRemove: (_) {},
            onSave: () {},
            onPreview: () {},
          ),
        );
      }));
  testWidgets('plan', (t) => _render(t, 'plan', () {
        return _sheet(Column(children: [
          AdvPlanCard(plan: _plan(), canTick: (_) => true, ticking: const {3}, onTick: (_) {}, onEdit: () {}, onStatus: () {}, onReview: () {}),
          AdvPlanCard(plan: _plan('completed'), onStatus: () {}),
        ]));
      }));
  testWidgets('plan_editor', (t) => _render(t, 'plan_editor', () {
        final p = _plan();
        return _sheet(AdvPlanForm(
          title: TextEditingController(text: p.title),
          draft: AdvPlanDraft.of(p),
          target: TextEditingController(text: '2.30'),
          measureText: TextEditingController(),
          items: [for (final i in p.items) AdvPlanItemFields.of(i)],
          onMeasureKind: (_) {},
          onPickFollowUp: () {},
          onClearFollowUp: () {},
          onVisible: (_) {},
          onOwner: (_, _) {},
          onPickDue: (_) {},
          onClearDue: (_) {},
          onAddItem: () {},
          onRemoveItem: (_) {},
          onSaveDraft: () {},
          onSave: () {},
        ));
      }));
  testWidgets('accommodations', (t) => _render(t, 'accommodations', () {
        final items = [
          for (final m in sampleAdvAccommodationsJson()) AdvAccommodationGrant.fromJson(m),
          AdvAccommodationGrant.fromJson({
            ...sampleAdvAccommodationsJson().first,
            'id': 83,
            'member_id': 612,
            'student_name': 'Youssef Nabil',
            'key': 'recorded_lectures',
            'label_ar': 'محاضرات مسجّلة',
            'label_en': 'Recorded lectures',
            'ends_on': '2026-12-15',
          }),
        ];
        return Scaffold(body: AdvAccommodationsView(load: AdvLoad.ready, page: AdvPage(items: items, total: items.length), onStatus: (_) {}, onSearch: (_) {}, onOpen: (_) {}));
      }));
  testWidgets('support_360', (t) => _render(t, 'support_360', () {
        return Scaffold(
          body: AdvStudentView(
            load: AdvLoad.ready,
            profile: AdvCaseProfile.fromJson(sampleAdvProfileJson()),
            section: 'support',
            now: advCaseNow,
            onSection: (_) {},
            onChangeAdvisor: () {},
            support: _pane(),
          ),
        );
      }));
  testWidgets('hub', (t) => _render(t, 'hub', () {
        final m = AdvMemberSupport.fromJson(sampleAdvMemberSupportJson());
        return Scaffold(
          body: AdvPageFrame(maxWidth: 760, children: [
            AdvHubRequestsSection(requests: m.requests, onOpen: (_) {}, first: true),
            AdvHubPlansSection(plans: m.plans, onTick: (_, _) {}),
            AdvHubAccommodationsSection(accommodations: m.accommodations),
          ]),
        );
      }));
  testWidgets('student_request', (t) => _render(t, 'student_request', () {
        return Scaffold(body: AdvStudentRequestView(load: AdvLoad.ready, request: AdvStudentRequest.fromJson(sampleAdvStudentRequestJson())));
      }));
}
