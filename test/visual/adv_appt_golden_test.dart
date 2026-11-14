// Visual review renders of the Phase 5 advising screens (D-289, docs/advising/PHASE5.md), compared by eye like the
// other test/visual files (NOT a CI suite):
//
//   flutter test test/visual/adv_appt_golden_test.dart --update-goldens [--plain-name hub]
//
// → test/visual/goldens/adv_appt_<scene>_<width>_<lang>_<light|dark>.png at 390×844 and 1440×900.
//   booking        the booking sheet: two advisors, the day strip, free times, one chosen, the reason
//   appointments   the cards: upcoming in person, a video one about to start, held, cancelled late (staff actions)
//   hub            the student hub: survey, advisor card with office hours, messages, meetings, shared notes
//   hub_no_hours   the hub when the advisor set no office hours yet
//   threads        an advisor's conversation list (overdue, complaint, escalated, closed)
//   thread         a conversation: messages with attachments, one waiting offline, the composer
//   new_thread     a student's complaint about the advisor (the privacy note)
//   availability   the office-hours editor: windows per weekday, a day off, unsaved changes
//   rule_sheet     one window: day, times, length, ways to meet, link, validity
//   templates      the templates by kind (built-in, switched off)
//   template_sheet a built-in template with placeholder chips
//   survey         the anonymous survey sheet
//   feedback       the ratings (average, distribution, comments by month)
//   cancel         a student cancelling late
//   setup_links    the advising page's Work tiles with the Phase 5 entries and counts
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
import 'package:flutter_education_app/features/org/advising/adv_appointments.dart';
import 'package:flutter_education_app/features/org/advising/adv_appt_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_availability_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_message_store.dart' show AdvQueuedMessage;
import 'package:flutter_education_app/features/org/advising/adv_models.dart';
import 'package:flutter_education_app/features/org/advising/adv_parts.dart';
import 'package:flutter_education_app/features/org/advising/adv_setup_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_student_hub.dart';
import 'package:flutter_education_app/features/org/advising/adv_survey_sheet.dart';
import 'package:flutter_education_app/features/org/advising/adv_templates_page.dart';
import 'package:flutter_education_app/features/org/advising/adv_threads.dart';
import 'package:flutter_test/flutter_test.dart';

import '../org/adv_appt_models_test.dart';
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
            matchesGoldenFile('goldens/adv_appt_${name}_${size.width.toInt()}_${lang}_${dark ? 'dark' : 'light'}.png'),
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

AdvAppointment _appt(Map<String, dynamic> j) => AdvAppointment.fromJson(j);
List<AdvTemplate> get _templates => [for (final m in (sampleAdvTemplatesJson()['items'] as List).cast<Map<String, dynamic>>()) AdvTemplate.fromJson(m)];
final _actions = AdvApptActions(onJoin: (_) {}, onCalendar: (_) {}, onReschedule: (_) {}, onCancel: (_) {}, onComplete: (_) {}, onNoShow: (_) {}, onNote: (_) {}, onChat: (_) {}, onOpenStudent: (_) {});

void main() {
  setUpAll(() async {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
    await _loadFonts();
  });
  setUp(() => AppConfig.disableList = []);

  AdvHubView hub(Map<String, dynamic> j) => AdvHubView(
        load: AdvLoad.ready,
        hub: AdvHub.fromJson(j),
        now: advApptNow,
        onBook: (_) {},
        onMessage: (_) {},
        onThreads: () {},
        onSurvey: (_) {},
        onAllAppointments: () {},
        apptActions: _actions,
      );

  testWidgets('booking', (t) => _render(t, 'booking', () {
        final s = AdvSlots.fromJson(sampleAdvSlotsJson());
        final by = s.byDay(mode: 'in_person');
        final list = by['2026-11-10'] ?? const <AdvSlot>[];
        return _sheet(AdvBookingForm(
          advisors: const [(12, 'د. منى خليل'), (13, 'Dr Omar Saleh')],
          advisorUserId: 12,
          days: [for (var i = 0; i < 14; i++) DateTime(2026, 11, 9 + i)],
          counts: {for (final e in by.entries) e.key: e.value.length},
          slots: list,
          modes: s.modes,
          reason: TextEditingController(text: 'أريد مناقشة خطة الفصل القادم'),
          day: DateTime(2026, 11, 10),
          slot: list[1],
          mode: 'in_person',
          onAdvisor: (_) {},
          onDay: (_) {},
          onNext: () {},
          onSlot: (_) {},
          onMode: (_) {},
          onSubmit: () {},
        ));
      }));
  testWidgets('appointments', (t) => _render(t, 'appointments', () => _sheet(Column(children: [
            AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(staff: true)), actions: _actions, staff: true, now: advApptNow),
            AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 2, mode: 'video', dayOffset: 0, hour: 8, reason: null, staff: true)), actions: _actions, staff: true, now: advApptNow.add(const Duration(minutes: 1))),
            AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 3, past: true, staff: true, reason: null)), actions: _actions, staff: true, now: advApptNow),
            AdvAppointmentCard(appointment: _appt(sampleAdvAppointmentJson(id: 4, past: true, status: 'cancelled', cancelledBy: 'student', late: true, cancelReason: 'ظرف عائلي طارئ', reason: null)), staff: true, now: advApptNow),
          ]))));
  testWidgets('hub', (t) => _render(t, 'hub', () => Scaffold(body: hub(sampleAdvHubJson()))));
  testWidgets('hub_no_hours', (t) => _render(t, 'hub_no_hours', () => Scaffold(body: hub(sampleAdvHubJson(noHours: true)))));
  testWidgets('threads', (t) => _render(t, 'threads', () => Scaffold(
        body: AdvThreadsView(
          load: AdvLoad.ready,
          query: const AdvThreadQuery(),
          threads: AdvThreadList.fromJson(sampleAdvThreadsJson()).page.items,
          unreadTotal: 3,
          onSearch: (_) {},
          onFilter: (_) {},
          onOpen: (_) {},
        ),
      )));
  testWidgets('thread', (t) => _render(t, 'thread', () {
        final d = AdvThreadDetail.fromJson(sampleAdvThreadDetailJson());
        return Scaffold(
          body: AdvThreadView(
            load: AdvLoad.ready,
            thread: d.thread,
            messages: d.messages,
            queued: const [AdvQueuedMessage(userId: 1, orgId: 1, threadId: 5, student: false, draft: AdvMessageDraft(body: 'سأتابع مع شؤون الطلاب وأعود إليكِ غداً.', clientId: 'a'))],
            hasOlder: true,
            onOlder: () {},
            onOpenAttachment: (_) {},
            composer: AdvMessageComposer(
              body: TextEditingController(),
              attachments: const [AdvAttachment(id: 7, name: 'plan-2026.pdf', size: 248000)],
              draftSaved: true,
              onAttach: () {},
              onRemoveAttachment: (_) {},
              onTemplate: () {},
              onSend: () {},
            ),
          ),
        );
      }));
  testWidgets('new_thread', (t) => _render(t, 'new_thread', () => _sheet(AdvNewThreadForm(
            draft: const AdvThreadDraft(kind: 'complaint', about: 'advisor', priority: 'high'),
            subject: TextEditingController(text: 'لم يرد المرشد على طلبي'),
            body: TextEditingController(text: 'أرسلت طلب تعديل الخطة منذ أسبوعين ولم يصلني رد.'),
            advisors: const [(12, 'د. منى خليل')],
            onKind: (_) {},
            onAbout: (_) {},
            onPriority: (_) {},
            onAttach: () {},
            onSubmit: () {},
          ))));
  testWidgets('availability', (t) => _render(t, 'availability', () {
        final a = AdvAvailability.fromJson(sampleAdvAvailabilityJson());
        return Scaffold(
          body: AdvAvailabilityView(
            load: AdvLoad.ready,
            rules: a.rules,
            off: a.off,
            timezone: a.timezone,
            dirty: true,
            onAdd: (_) {},
            onEdit: (_) {},
            onRemove: (_) {},
            onSave: () {},
            onAddOff: () {},
            onRemoveOff: (_) {},
          ),
        );
      }));
  testWidgets('rule_sheet', (t) => _render(t, 'rule_sheet', () {
        final r = AdvAvailability.fromJson(sampleAdvAvailabilityJson()).rules.first.copyWith(modes: ['in_person', 'video']);
        return _sheet(AdvRuleForm(
          rule: r,
          location: TextEditingController(text: r.location),
          link: TextEditingController(),
          editing: true,
          onWeekday: (_) {},
          onStart: () {},
          onEnd: () {},
          onSlot: (_) {},
          onMode: (_) {},
          onValidFrom: () {},
          onValidTo: () {},
          onSubmit: () {},
        ));
      }));
  testWidgets('templates', (t) => _render(t, 'templates', () => Scaffold(body: AdvTemplatesView(load: AdvLoad.ready, templates: _templates, manage: true, onKind: (_) {}, onAdd: () {}, onEdit: (_) {}))));
  testWidgets('template_sheet', (t) => _render(t, 'template_sheet', () {
        final x = _templates.first;
        return _sheet(AdvTemplateForm(
          draft: AdvTemplateDraft.of(x),
          nameAr: TextEditingController(text: x.nameAr),
          nameEn: TextEditingController(text: x.nameEn),
          bodyAr: TextEditingController(text: x.bodyAr),
          bodyEn: TextEditingController(text: x.bodyEn),
          system: true,
          creating: false,
          onActive: (_) {},
          onPlaceholder: (_, _) {},
          onSubmit: () {},
        ));
      }));
  testWidgets('survey', (t) => _render(t, 'survey', () => _sheet(AdvSurveyForm(
            info: AdvSurveyInfo.fromJson({'advisor_name': 'د. منى خليل', 'date': '2026-11-03'}),
            rating: 4,
            comment: TextEditingController(),
            onRating: (_) {},
            onSubmit: () {},
          ))));
  testWidgets('feedback', (t) => _render(t, 'feedback', () => _sheet(AdvFeedbackView(feedback: AdvFeedback.fromJson(sampleAdvFeedbackJson())))));
  testWidgets('cancel', (t) => _render(t, 'cancel', () => _sheet(AdvCancelForm(appointment: _appt(sampleAdvAppointmentJson()), reason: TextEditingController(), late: true, onSubmit: () {}))));
  testWidgets('setup_links', (t) => _render(t, 'setup_links', () {
        return Scaffold(
          body: AdvSetupView(
            state: AdvSetupState.on,
            deptName: AppConfig.lang == 'ar' ? 'الإرشاد الأكاديمي' : 'Academic Advising',
            status: AdvStatus.fromJson({
              ...sampleAdvStatusJson(admin: false, director: true, advisor: true),
              'me': {'admin': false, 'director': true, 'advisor': true, 'advisees': 12, 'handovers_pending': 0, 'flags_urgent': 0, 'flags_overdue': 0, 'threads_unread': 4, 'appointments_today': 2, 'surveys_pending': 0},
              'counts': {'students': 480, 'assigned': 402, 'unassigned': 0, 'advisors': 14, 'away': 0, 'over': 0},
            }),
            onOpen: (_) {},
            onDisable: () {},
          ),
        );
      }));
}
