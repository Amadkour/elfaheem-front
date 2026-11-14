// Visual review renders of the Phase 4 advising pages (D-289, docs/advising/PHASE4.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_case_golden_test.dart --update-goldens [--plain-name workspace]
//
// → test/visual/goldens/adv_case_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   workspace          a director's workspace: risk-sorted cards, facets, urgent pills, categories
//   workspace_empty    an advisor with no students yet
//   workspace_select   Phase 9: a director selecting students (two chosen) with "Message 2 selected students"
//   filters            the filter sheet (a director: advisor, category, program, level)
//   student            the 360 (phone: header + Overview; wide: Overview + Academic beside Flags)
//   student_academic   the Academic section (GPA by term, terms with courses)
//   student_notes      the Notes section: composer offline with notes waiting and one refused, the notes
//   student_timeline   the Timeline section
//   student_no_record  the 360 of a student the registrar does not know, no advisor, no risk
//   flag_sheet         a new Accessibility flag with accommodations, urgent
//   status_sheet       resolving a flag with its outcome
//   categories         the categories, one switched off
//   category_sheet     the Accessibility category with its accommodations (built in)
//   setup_links        the advising page of a director who advises: Workspace with urgent / overdue counts
@Tags(['visual'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/display/display_settings.dart';
import 'package:flutter_education_app/design/app_display.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/org/advising/adv_categories_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_draft_store.dart' show AdvQueuedNote;
import 'package:flutter_education_app/features/org/advising/adv_flags.dart';
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_notes.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_workspace_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_case_models_test.dart';
import '../org/adv_models_test.dart' show sampleAdvStatusJson;
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
            matchesGoldenFile('goldens/adv_case_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

List<AdvCategory> get _cats => [for (final m in (sampleAdvCategoriesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvCategory.fromJson(m)];

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  AdvWorkspaceView workspace({bool manage = true, AdvPage<AdvCaseItem>? page, AdvSelection? selection}) => AdvWorkspaceView(
        load: AdvLoad.ready,
        manage: manage,
        query: const AdvWorkspaceQuery(),
        page: page ?? AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson),
        categoryNames: {for (final c in _cats) c.key: c.name},
        now: advCaseNow,
        onSearch: (_) {},
        onFilters: () {},
        onPage: (_) {},
        onOpen: (_) {},
        onRegistrationCases: () {},
        onCategories: manage ? () {} : null,
        selection: selection,
        onSelectStart: (_) {},
        onToggle: (_) {},
        onTogglePage: () {},
        onSelectDone: () {},
        onMessageSelected: () {},
      );

  AdvNoteComposer composer({bool offline = false, List<AdvQueuedNote> queued = const []}) => AdvNoteComposer(
        body: TextEditingController(text: AppConfig.lang == 'ar' ? 'اتفقنا على لقاء أسبوعي حتى الامتحانات النهائية.' : 'We agreed on a weekly meeting until the finals.'),
        draft: const AdvNoteDraft(contactMode: 'in_person'),
        categories: _cats,
        canSensitive: true,
        offline: offline,
        draftSaved: !offline,
        queued: queued,
        onVisibility: (_) {},
        onSensitive: (_) {},
        onCategory: (_) {},
        onContact: (_) {},
        onMode: (_) {},
        onPickContactDate: () {},
        onSubmit: () {},
        onDiscardQueued: (_) {},
        onReopenQueued: (_) {},
      );

  AdvStudentView student(String section, {Map<String, dynamic>? profile, Widget? notesComposer}) {
    final flags = AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson);
    final notes = AdvPage.fromJson(sampleAdvNotesJson(), AdvNote.fromJson);
    return AdvStudentView(
      load: AdvLoad.ready,
      profile: AdvCaseProfile.fromJson(profile ?? sampleAdvProfileJson()),
      section: section,
      now: advCaseNow,
      onSection: (_) {},
      onChangeAdvisor: () {},
      flags: AdvFlagsPane(
        load: AdvLoad.ready,
        page: flags,
        view: 'all',
        onView: (_) {},
        onAdd: () {},
        canChange: (_) => true,
        canEdit: (f) => !f.closed,
        onStatus: (_) {},
        onEdit: (_) {},
        onHistory: (_) {},
      ),
      notes: AdvNotesPane(
        load: AdvLoad.ready,
        composer: notesComposer ?? composer(),
        notes: notes.items,
        total: notes.total,
        restricted: notes.restricted,
        hasMore: true,
        onMore: () {},
        canEdit: (n) => n.mine,
        canDelete: (n) => n.mine,
        onEdit: (_) {},
        onDelete: (_) {},
      ),
      timeline: AdvTimelinePane(load: AdvLoad.ready, entries: AdvTimelinePage.fromJson(sampleAdvTimelineJson()).items, hasMore: true, onMore: () {}),
    );
  }

  testWidgets('workspace', (t) => _render(t, 'workspace', () => Scaffold(body: workspace())));
  testWidgets('workspace_select', (t) => _render(t, 'workspace_select', () {
        final items = AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson).items;
        return Scaffold(body: workspace(selection: const AdvSelection().toggle(items[0]).toggle(items[2])));
      }));
  testWidgets('workspace_empty', (t) => _render(t, 'workspace_empty', () => Scaffold(body: workspace(manage: false, page: const AdvPage()))));
  testWidgets('filters', (t) => _render(t, 'filters', () {
        return _sheet(AdvWorkspaceFilterForm(
          query: AdvWorkspaceQuery(sort: 'contact', flag: 'open', categoryId: 7, advisor: AdvRef(userId: 31, name: AppConfig.lang == 'ar' ? 'د. هدى سالم' : 'Dr. Huda Salem')),
          choices: AdvWorkspaceChoices.from(
            options: const AdvPolicyOptions(levels: ['Level 1', 'Level 2', 'Level 3', 'Level 4'], cohorts: ['2022', '2023', '2024'], programs: [AdvNamed(id: 11, nameAr: 'هندسة البرمجيات', nameEn: 'Software Engineering')]),
            seen: AdvPage.fromJson(sampleAdvWorkspaceJson(), AdvCaseItem.fromJson).items,
            categories: _cats,
          ),
          manage: true,
          onChanged: (_) {},
          onPickAdvisor: () {},
          onApply: () {},
        ));
      }));
  testWidgets('student', (t) => _render(t, 'student', () => Scaffold(body: student('overview'))));
  testWidgets('student_academic', (t) => _render(t, 'student_academic', () => Scaffold(body: student('academic'))));
  testWidgets('student_notes', (t) => _render(t, 'student_notes', () {
        const waiting = AdvQueuedNote(userId: 31, orgId: 3, memberId: 601, draft: AdvNoteDraft(body: 'x', clientId: 'n1'));
        final refused = AdvQueuedNote(
          userId: 31,
          orgId: 3,
          memberId: 601,
          draft: AdvNoteDraft(
              body: AppConfig.lang == 'ar' ? 'أرسلت للطالب نتيجة الفحص الطبي وما قاله الطبيب عن السماعة.' : 'Shared the medical report and what the doctor said about the hearing aid.',
              visibility: 'student',
              clientId: 'n2'),
          error: 'advising_bad_visibility',
          message: AppConfig.lang == 'ar' ? 'الملاحظة الحساسة لا تُعرض على الطالب — اختر «خاصة» أو «فريق الإرشاد»' : 'A sensitive note is never shown to the student — choose Private or Advising team',
        );
        return Scaffold(body: student('notes', notesComposer: composer(offline: true, queued: [waiting, refused])));
      }));
  testWidgets('student_timeline', (t) => _render(t, 'student_timeline', () => Scaffold(body: student('timeline'))));
  testWidgets('student_no_record', (t) => _render(t, 'student_no_record', () {
        final j = sampleAdvProfileJson(academic: false, manage: false);
        j['advisors'] = <Map<String, dynamic>>[];
        j['stats'] = {...(j['stats'] as Map<String, dynamic>), 'risk_score': 0, 'risk_reasons': <Map<String, dynamic>>[], 'cgpa': null, 'last_term_gpa': null, 'absence_max': null, 'failed_count': 0, 'open_flags': {}};
        j['counts'] = {'flags_open': 0, 'notes': 0, 'restricted': 0, 'handovers': 0};
        return Scaffold(body: student('academic', profile: j));
      }));
  testWidgets('flag_sheet', (t) => _render(t, 'flag_sheet', () {
        final acc = _cats.firstWhere((c) => c.key == 'accessibility');
        return _sheet(AdvFlagForm(
          categories: [for (final c in _cats) if (c.active) c],
          draft: AdvFlagDraft(categoryId: acc.id, priority: 'urgent', accommodations: const ['extra_time', 'front_seating'], reviewDueAt: DateTime.utc(2026, 11, 20, 12)),
          note: TextEditingController(text: AppConfig.lang == 'ar' ? 'السماعة في الصيانة حتى نهاية الشهر؛ يحتاج تسجيل المحاضرات.' : 'The hearing aid is being repaired until the end of the month; the lectures need recording.'),
          onCategory: (_) {},
          onPriority: (_) {},
          onPickDate: () {},
          onClearDate: () {},
          onAccommodation: (_) {},
          onSubmit: () {},
        ));
      }));
  testWidgets('status_sheet', (t) => _render(t, 'status_sheet', () {
        final f = AdvPage.fromJson(sampleAdvFlagsJson(), AdvFlag.fromJson).items.first;
        return _sheet(AdvFlagStatusForm(
          flag: f,
          outcome: TextEditingController(text: AppConfig.lang == 'ar' ? 'التقيت الطالب مرتين ونُقلت شعبة العملي إلى الصباح.' : 'Met the student twice; the lab section moved to the morning.'),
          chosen: 'resolved',
          onChoose: (_) {},
          onSubmit: () {},
        ));
      }));
  testWidgets('categories', (t) => _render(t, 'categories', () => Scaffold(body: AdvCategoriesView(load: AdvLoad.ready, categories: _cats, onAdd: () {}, onOpen: (_) {}))));
  testWidgets('category_sheet', (t) => _render(t, 'category_sheet', () {
        final acc = _cats.firstWhere((c) => c.key == 'accessibility');
        return _sheet(AdvCategoryForm(
          category: acc,
          nameAr: TextEditingController(text: acc.nameAr),
          nameEn: TextEditingController(text: acc.nameEn),
          sensitive: true,
          active: true,
          rows: [for (final a in acc.accommodations) AdvAccommodationRow.of(a)],
          onSensitive: (_) {},
          onActive: (_) {},
          onAddRow: () {},
          onRemoveRow: (_) {},
          onSubmit: () {},
          onDelete: () {},
        ));
      }));
  testWidgets('setup_links', (t) => _render(t, 'setup_links', () {
        return Scaffold(
          body: AdvSetupView(
            state: AdvSetupState.on,
            deptName: AppConfig.lang == 'ar' ? 'الإرشاد الأكاديمي' : 'Academic Advising',
            status: AdvStatus.fromJson({
              ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
              'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'handovers_pending': 3, 'flags_urgent': 2, 'flags_overdue': 5},
              'counts': {'students': 480, 'assigned': 402, 'unassigned': 78, 'advisors': 14, 'away': 22, 'over': 1},
            }),
            onOpen: (_) {},
            onDisable: () {},
          ),
        );
      }));
}
