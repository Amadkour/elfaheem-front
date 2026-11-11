// Does the exam's identifier fit the bubble sheet's student-ID zone? (B9 of the paper-exam e2e: a 14-digit national ID
// on a 10-column shaded grid gave "No student has this ID" on every sheet and nothing said so before printing.)
//   • the real replies (recorded from the backend's tests/exam_engine/e2e_omr_id_fit.py,
//     test/org/fixtures/omr_id_fit_payloads.json) parse: the setup's `identifier_fit`, the pinned template's zone, the
//     report's lengths, the library rows' zones, the print refusal;
//   • `identifierZoneFit` (the wizard's check of a sheet type before it is saved) gives the server's answer on the same
//     data, and every rule branch;
//   • the words: the card's title / body / fixes and the 409 in plain words, Arabic + English;
//   • the wizard over the fake backend: the card on the Students step (sheet already pinned), under the chosen sheet
//     type, and on the last step; nothing when the identifier fits.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/live/event_wait.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/exam_setup_wizard.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_api.dart';
import '../ui/layout_harness.dart';

Map<String, dynamic> _p(String name) =>
    ((jsonDecode(File('test/org/fixtures/omr_id_fit_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)[name] as Map<String, dynamic>;

Map<String, dynamic> _fields() =>
    ((jsonDecode(File('test/org/fixtures/omr_setup_payloads.json').readAsStringSync()) as Map)['payloads'] as Map)['fields_all'] as Map<String, dynamic>;

List<OmrTemplateItem> _templates() => [for (final m in (_p('templates')['items'] as List).cast<Map<String, dynamic>>()) OmrTemplateItem.fromJson(m)];

/// The server's numbers, without the labels the app does not need.
List<Object?> _shape(IdZoneFit f) => [f.status, f.reason, f.zoneKind, f.zoneDigits, f.kind, f.minLen, f.maxLen, f.tooLong, f.nonDigit, f.missing, f.longest];

void main() {
  setUp(() {
    AppConfig.lang = 'en';
    AppConfig.disableList = [];
  });

  group('real replies', () {
    test('setup: a 14-digit national ID on the 10-column shaded sheet → block, with the warning', () {
      final s = ExamSetup.fromJson(_p('setup_block'));
      expect(s.template!.idZone, const IdZone('shaded', 10));
      final f = s.identifierFit!;
      expect(f.blocks, isTrue);
      expect(_shape(f), ['block', 'too_long', 'shaded', 10, 'digits', 14, 14, 5, 0, 1, 14]);
      expect(s.warnings, contains('identifier_zone_mismatch'));
      expect(ExamSetup.fromJson(_p('setup_warn')).identifierFit!.warns, isTrue);
      expect(ExamSetup.fromJson(_p('setup_ok')).identifierFit!.status, 'ok');
    });

    test('report: the field\'s lengths and the holders\' value lengths (counts, never a value)', () {
      final r = IdentifierReport.fromJson(_p('identifiers_nid'));
      expect((r.minLen, r.maxLen, r.nonDigit), (14, 14, 0));
      expect(r.valueLengths, {14: 5});
      expect(IdentifierReport.fromJson(_p('identifiers_academic')).valueLengths, {7: 6});
    });

    test('library rows carry the zone', () {
      final items = _templates();
      expect(items.map((x) => x.idZone), everyElement(isNotNull));
      expect({for (final x in items) x.idZone!.kind}, {'shaded', 'handwritten'});
      expect(items.every((x) => x.idZone!.digits == 10), isTrue);
      expect(idZoneLabel(const IdZone('shaded', 10)), 'Student ID: 10 shaded digits');
    });

    test('the app\'s check gives the server\'s answer on the same data', () {
      final block = ExamSetup.fromJson(_p('setup_block'));
      expect(_shape(reportZoneFit(IdentifierReport.fromJson(_p('identifiers_nid')), block.template!.idZone)!), _shape(block.identifierFit!));
      final ok = ExamSetup.fromJson(_p('setup_ok'));
      expect(_shape(reportZoneFit(IdentifierReport.fromJson(_p('identifiers_academic')), ok.template!.idZone)!), _shape(ok.identifierFit!));
    });

    test('printing blank sheets: 409 identifier_zone_mismatch in plain words with the fixes', () {
      final d = Map<String, dynamic>.from(_p('sheets_409')['detail'] as Map);
      expect(d['code'], 'identifier_zone_mismatch');
      final r = EngineResult.fail(409, d['code'] as String, '${d['message']}', d);
      expect(omrErrorText(r), startsWith('National ID has 14 digits but this sheet\'s ID zone has 10'), reason: 'the server\'s own English');
      expect(omrCodeText('identifier_zone_mismatch', d),
          'The student identifier (14 digits) is longer than the sheet\'s ID zone (10 digits) — choose a sheet type with at least 14 ID digits, or a shorter identifier, or print a named sheet per student (its QR identifies the student)');
      expect(setupCodeText('identifier_zone_mismatch', d), omrCodeText('identifier_zone_mismatch', d));
      AppConfig.lang = 'ar';
      expect(omrErrorText(r), startsWith('الرقم القومي من 14 رقمًا'));
      expect(omrCodeText('identifier_zone_mismatch', d), contains('اطبع ورقة باسم كل طالب'));
      expect(setupCodeText('identifier_zone_mismatch', {...d, 'reason': 'not_digits'}), contains('ليس رقمًا'));
    });
  });

  group('the rule (every branch)', () {
    const grid = IdZone('shaded', 10);
    IdZoneFit? fit(String source, String kind, {int? lo, int? hi, Map<int, int> lengths = const {}, int nonDigit = 0, int missing = 0, IdZone zone = grid}) =>
        identifierZoneFit(source: source, kind: kind, minLen: lo, maxLen: hi, lengths: lengths, nonDigit: nonDigit, missing: missing, zone: zone);

    test('block: shortest allowed value longer than the zone; a name or an e-mail', () {
      expect(fit('national_id', 'digits', lo: 14, hi: 14)!.reason, 'too_long');
      expect(fit('national_id', 'digits', lo: 14, hi: 14, zone: const IdZone('handwritten', 10))!.blocks, isTrue);
      expect(fit('name', 'text', lo: 1, hi: 255)!.reason, 'not_digits');
      expect(fit('email', 'email', lo: 3, hi: 254)!.reason, 'not_digits');
    });

    test('warn: values that do not fit; missing students who may type one', () {
      expect(fit('academic_id', 'text', lo: 1, hi: 32, lengths: {7: 3, 12: 1})!.reason, 'values');
      expect(fit('academic_id', 'text', lo: 1, hi: 32, lengths: {7: 3}, nonDigit: 1)!.reason, 'values');
      expect(fit('academic_id', 'text', lo: 1, hi: 32, lengths: {7: 3}, missing: 2)!.reason, 'missing_may_not_fit');
      expect(fit('custom', 'digits', lo: 6, hi: 12, lengths: {8: 3}, missing: 1)!.reason, 'missing_may_not_fit');
    });

    test('ok: everything fits (shorter values are fine); a digits field that can never be longer', () {
      expect(fit('academic_id', 'text', lo: 1, hi: 32, lengths: {7: 3})!.status, 'ok');
      expect(fit('custom', 'digits', lo: 6, hi: 8, lengths: {8: 3}, missing: 4)!.status, 'ok');
      expect(fit('national_id', 'digits', lo: 14, hi: 14, zone: const IdZone('shaded', 14))!.status, 'ok');
    });

    test('printed / QR / no zone: not checked', () {
      expect(fit('national_id', 'digits', lo: 14, hi: 14, zone: const IdZone('qr', 0)), isNull);
      expect(fit('national_id', 'digits', lo: 14, hi: 14, zone: const IdZone('printed', 0)), isNull);
      expect(fit('national_id', 'digits', lo: 14, hi: 14, zone: const IdZone('none', 0)), isNull);
      expect(reportZoneFit(null, grid), isNull);
    });
  });

  group('the card\'s words', () {
    test('block: what is wrong and the three fixes, Arabic + English', () {
      final f = ExamSetup.fromJson(_p('setup_block')).identifierFit!;
      final en = idZoneFitTexts(f, 'National ID');
      expect(en.title, 'National ID does not fit this sheet');
      expect(en.body, contains('has 14 digits'));
      expect(en.body, contains('Blank sheets will not print'));
      expect(en.fixes, [
        'Choose a sheet type with at least 14 ID digits',
        'Identify students by a shorter value (back to the Students step)',
        'Print a named sheet per student — its QR code identifies the student, nothing to shade',
      ]);
      AppConfig.lang = 'ar';
      final ar = idZoneFitTexts(f, 'الرقم القومي');
      expect(ar.title, 'الرقم القومي لا يتسع في هذه الورقة');
      // 11+ takes the singular accusative (countText): "14 رقمًا", never "14 أرقام"
      expect(ar.fixes.first, 'اختر نوع ورقة بمنطقة 14 رقمًا على الأقل');
      expect(ar.fixes.last, contains('اطبع ورقة باسم كل طالب'));
    });

    test('warn: the counts', () {
      final f = ExamSetup.fromJson(_p('setup_warn')).identifierFit!;
      final en = idZoneFitTexts(f, 'Academic ID');
      expect(en.title, 'Academic ID may not fit this sheet');
      expect(en.body, contains('2 students have values longer than 10 digits or with letters'));
      expect(en.fixes.first, 'Choose a sheet type with at least 12 ID digits');
    });
  });

  group('the wizard', () {
    final connected = ValueNotifier<bool>(true);
    final stream = LiveStreamHandle(connected: connected, bind: () {}, release: () {});

    Future<void> frames(WidgetTester tester, [int n = 8]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester, {required Map<String, dynamic> setup, required Map<String, dynamic> report}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final fake = FakeApi({
        'GET /api/v1/exam/exams/1/setup': (_) => setup,
        'GET /api/v1/exam/exams/1': (_) => const {'id': 1, 'org_id': 1, 'course_id': 100, 'title': 'National ID midterm', 'starts_at': '2026-12-01T08:00:00', 'sections': []},
        'GET /api/v1/identity-fields': (_) => _fields(),
        'GET /api/v1/data-lab/courses/100/grid': (_) => const {'columns': [], 'rows': []},
        'GET /api/v1/exam/exams/1/identifiers': (_) => report,
        'PUT /api/v1/exam/exams/1/setup': (_) => setup,
        'GET /api/v1/exam/exams/1/forms': (_) => const {'items': [], 'form_markers': [], 'warnings': []},
        'GET /api/v1/exam/omr/templates': (_) => _p('templates'),
      }, latency: const Duration(milliseconds: 20))
        ..install();
      addTearDown(fake.uninstall);
      await tester.pumpWidget(layoutHost(ExamSetupWizard(examId: 1, liveStream: stream, liveBus: LiveEvents.instance), scale: 1));
      await frames(tester, 10);
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('setup.primary')));
      await frames(tester);
    }

    Future<void> done(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockRequestPlugins();
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('national ID on the 10-column sheet: the card on Students, under the chosen sheet, on the last step ($lang)', (tester) async {
        AppConfig.lang = lang;
        await open(tester, setup: _p('setup_block'), report: _p('identifiers_nid'));
        final title = lang == 'en' ? 'National ID does not fit this sheet' : 'الرقم القومي لا يتسع في هذه الورقة';
        final named = lang == 'en' ? 'Print a named sheet per student — its QR code identifies the student, nothing to shade' : 'اطبع ورقة باسم كل طالب — رمز QR عليها يحدد الطالب، فلا يحتاج إلى التظليل';
        // 1 · Students: the sheet is already pinned
        expect(find.byType(IdZoneFitCard), findsOneWidget);
        await tester.ensureVisible(find.text(title));
        expect(find.text(title), findsOneWidget);
        expect(find.text(named), findsOneWidget);
        await next(tester); // → type
        await next(tester); // → paper
        await next(tester); // → sheet
        expect(find.byKey(const ValueKey('setup.idfit')), findsOneWidget, reason: 'under the chosen sheet type');
        expect(find.textContaining(lang == 'en' ? 'Student ID: 10 shaded digits' : 'رقم الطالب: 10 أرقام بالتظليل'), findsWidgets);
        expect(find.textContaining(lang == 'en' ? 'too short for National ID' : 'لا يتسع لـالرقم القومي'), findsWidgets);
        await next(tester); // → models (the setup is saved: a named sheet per student is a valid way)
        expect(find.byType(IdZoneFitCard), findsOneWidget, reason: 'still said on the last step');
        expect(find.text(title), findsOneWidget);
        await done(tester);
      });
    }

    testWidgets('academic IDs that fit: no card anywhere', (tester) async {
      await open(tester, setup: _p('setup_ok'), report: _p('identifiers_academic'));
      expect(find.byType(IdZoneFitCard), findsNothing);
      await next(tester);
      await next(tester);
      await next(tester);
      expect(find.byKey(const ValueKey('setup.template.1')), findsOneWidget);
      expect(find.byType(IdZoneFitCard), findsNothing);
      await done(tester);
    });

    testWidgets('no overflow: the card (block / warn) and the sheet list with it, ar / en, 320 → 1400', (tester) async {
      final block = ExamSetup.fromJson(_p('setup_block')).identifierFit!;
      final warn = ExamSetup.fromJson(_p('setup_warn')).identifierFit!;
      await expectNoLayoutErrors(tester, () => SingleChildScrollView(
            child: Column(children: [
              IdZoneFitCard(fit: block, label: AppConfig.lang == 'ar' ? 'الرقم القومي' : 'National ID'),
              IdZoneFitCard(fit: warn, label: AppConfig.lang == 'ar' ? 'رقم جواز السفر للطلاب الوافدين' : 'Passport number of international students'),
              TemplateStepBody(
                templates: _templates(),
                selectedId: 1,
                fits: {for (final x in _templates()) x.id: block},
                identifierLabel: 'National ID',
                onPick: (_) {},
                onLearn: () {},
                onPaperOnly: () {},
              ),
            ]),
          ));
    });
  });
}
