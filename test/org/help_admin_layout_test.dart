// Super Admin Help management (f3): editor / flows / export sheet layout, and the editor's validation (= the server's).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/help/admin_help_api.dart';
import 'package:flutter_education_app/features/admin/help/admin_help_editor.dart';
import 'package:flutter_education_app/features/admin/help/admin_help_export.dart';
import 'package:flutter_education_app/features/admin/help/admin_help_flows.dart';
import 'package:flutter_education_app/features/admin/help/admin_help_page.dart';
import 'package:flutter_education_app/features/help/help_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

class FakeAdminApi extends AdminHelpApi {
  FakeAdminApi();
  final entry = HelpEntry.fromJson(jsonDecode(File('test/fixtures/help_entry_home_student.json').readAsStringSync()));
  HelpExportRequest? exported;
  final flow = const HelpFlow(
    key: 'subscribe_course',
    role: 'student',
    title: HelpText('كيف تشترك', 'How to enroll'),
    steps: [HelpFlowStep(pageId: 'home.student', action: HelpText('a', 'a'), narration: HelpText('n', 'n'), durationS: 6)],
  );

  @override
  Future<List<HelpPageRow>> pages({String? role}) async => [
        HelpPageRow(pageId: 'home.student', role: 'student', title: entry.title),
        const HelpPageRow(pageId: 'course', role: 'teacher', title: HelpText('الكورس', 'Course')),
      ];
  @override
  Future<List<HelpFlow>> flows({String? role}) async => [flow];
  @override
  Future<HelpEntry> page(String pageId, String role) async => entry;
  @override
  Future<List<String>> pageIds() async => ['home.student', 'course', 'calendar'];
  @override
  Future<Uint8List> export(HelpExportRequest req) async {
    exported = req;
    return Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppConfig.lang = 'en');

  HelpEntry sample() => FakeAdminApi().entry;

  test('validation mirrors the server', () {
    final d = HelpDraft(sample());
    expect(d.validate(), isNull);
    d.title.en.text = '';
    expect(d.validate(), contains('Both Arabic and English'));
    d.title.en.text = 'Home';
    d.sections[1].key.text = d.sections[0].key.text; // duplicate key
    expect(d.validate(), contains('key must be unique'));
    d.sections[1].key.text = 'Bad Key';
    expect(d.validate(), contains('key'));
    d.sections[1].key.text = 'ok_key';
    d.tour.first.target.text = ' ';
    expect(d.validate(), contains('target'));
    d.tour.first.target.text = 'x';
    d.sections.first.items.first.text.ar.text = '';
    expect(d.validate(), contains('Both Arabic and English'));
  });

  test('draft round-trips the entry body', () {
    final e = sample();
    expect(jsonEncode(HelpDraft(e).toEntry().toBody()), jsonEncode(e.toBody()));
  });

  test('flow validation', () {
    final f = FlowDraft(FakeAdminApi().flow);
    expect(f.validate(), isNull);
    f.steps.first.pageId = null;
    expect(f.validate(), contains('pick a page'));
    f.steps.first.pageId = 'course';
    f.key.text = 'Bad Key';
    expect(f.validate(), contains('Flow key'));
  });

  testWidgets('entry editor form: no layout error', (tester) async {
    final draft = HelpDraft(sample());
    addTearDown(draft.dispose);
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: HelpEntryForm(draft: draft)));
  });

  testWidgets('flow editor form: no layout error', (tester) async {
    final draft = FlowDraft(FakeAdminApi().flow);
    addTearDown(draft.dispose);
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(padding: const EdgeInsets.all(16), child: HelpFlowForm(draft: draft, pageIds: const ['home.student', 'course'])));
  });

  testWidgets('management page: lists, flows tab, no layout error', (tester) async {
    await expectNoLayoutErrors(tester, () => AdminHelpPage(api: FakeAdminApi()), scaffold: false, act: (t) async {
      await t.tap(find.text(AppConfig.lang == 'ar' ? 'المسارات' : 'Flows'));
    });
  });

  testWidgets('export sheet: no layout error', (tester) async {
    await expectNoLayoutErrors(
        tester, () => SingleChildScrollView(child: HelpExportSheet(api: FakeAdminApi(), pageId: 'home.student', role: 'student', flows: [FakeAdminApi().flow])));
  });

  testWidgets('export sheet sends what / format / lang and saves the file', (tester) async {
    final api = FakeAdminApi();
    String? savedName;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
        child: HelpExportSheet(api: api, pageId: 'home.student', role: 'student', save: (b, n, m) async => savedName = n))));
    await tester.tap(find.text('Video script'));
    await tester.pump();
    await tester.tap(find.text('JSON'));
    await tester.pump();
    await tester.tap(find.text('Both'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Export'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(api.exported?.toBody(), {
      'what': 'page',
      'ids': ['home.student'],
      'role': 'student',
      'format': 'video_script',
      'lang': 'both',
      'as': 'json',
    });
    expect(savedName, endsWith('.json'));
  });
}
