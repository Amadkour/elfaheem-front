// No overflow on any screen size (320×640 and 1400×900, Arabic and English, text ×1.3) for the bubble-sheet library
// and the learning flow (D-155), fed with REAL engine replies (test/fixtures/payloads/omr_templates/).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_template_learn.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_template_library.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_templates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'layout_harness.dart';

const _dir = 'test/fixtures/payloads/omr_templates';
Map<String, dynamic> _p(String name) =>
    Map<String, dynamic>.from((jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)['payload'] as Map);

List<OmrTemplateRow> _rows(String name) => [for (final m in (_p(name)['items'] as List).cast<Map>()) OmrTemplateRow.fromJson(Map<String, dynamic>.from(m))];

Widget _step(TemplateSteps s, int index, {bool editing = false, bool moveAll = false, bool published = false}) {
  final items = stepItems(s);
  final item = items[index];
  final draft = !editing
      ? null
      : switch (item) {
          QuestionItem(:final n) => s.question(n)!.bubbles,
          IdentifierItem() => s.identifier.columns.first,
          FormRowItem() => s.form.bubbles,
        };
  return StepThroughView(
    steps: s,
    items: items,
    index: index,
    blankImage: null,
    filledImage: null,
    showFilled: false,
    editing: editing,
    moveAll: moveAll,
    draft: draft,
    selected: editing ? 1 : null,
    idColumn: 0,
    identifierChecked: false,
    formChecked: false,
    canEdit: true,
    published: published,
    version: 2,
    busy: false,
    error: 'Could not reach the server — try again',
    onShowFilled: (_) {},
    onBack: () {},
    onNext: () {},
    onConfirm: () {},
    onConfirmClear: () {},
    onJump: (_) {},
    onEdit: () {},
    onCancelEdit: () {},
    onSaveEdit: () {},
    onMoveAll: (_) {},
    onSelect: (_) {},
    onDraft: (_) {},
    onIdColumn: (_) {},
    onNewVersion: published ? () {} : null,
    onFinish: () {},
  );
}

/// The harness, plus the index of the build that failed in the reason.
var _n = 0;
Future<void> _check(WidgetTester tester, Widget Function() build) async {
  final i = _n++;
  final prev = FlutterError.onError;
  final seen = <String>[];
  FlutterError.onError = (d) {
    final w = RegExp(r'\w+:file:///\S+\w+\.dart:\d+:\d+').allMatches(d.toString()).map((m) => m.group(0)).join(' | ');
    seen.add('#$i ${d.exceptionAsString()} $w');
    prev?.call(d);
  };
  try {
    await expectNoLayoutErrors(tester, build);
  } finally {
    FlutterError.onError = prev;
    if (seen.isNotEmpty) debugPrint('LAYOUT ${seen.first}');
  }
}

void main() {
  setUpAll(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('upload form (files picked, long names)', (tester) async {
    TextEditingController c(String v) => TextEditingController(text: v);
    await expectNoLayoutErrors(
      tester,
      () => LearnUploadBody(
        name: c('Ministry of Education unified answer sheet — 100 questions'),
        description: c(''),
        questions: c('100'),
        options: c('5'),
        perColumn: c('25'),
        idColumns: c('10'),
        forms: c('ABCD'),
        layout: 'columns',
        oneChoice: true,
        idKind: 'shaded',
        blankName: 'scan_of_the_blank_answer_sheet_from_the_school_printer_2026.pdf',
        blankBytes: 2400000,
        filledName: 'IMG_20261102_093512.jpg',
        filledBytes: 3100000,
        cameraAvailable: true,
        error: 'Enter the number of student ID columns (its digits)',
        onLayout: (_) {},
        onOneChoice: (_) {},
        onIdKind: (_) {},
        onPickBlank: ({required bool camera}) async {},
        onPickFilled: ({required bool camera}) async {},
        onClearFilled: () {},
        onLearn: () {},
        onBack: () {},
      ),
    );
  });

  testWidgets('start, waiting, result (learned / no marks), save, done', (tester) async {
    final done = TemplateSteps.fromJson(_p('e2e_steps_done'));
    final failed = TemplateSteps.fromJson(_p('steps_failed'));
    final invalid = TemplateValidation.fromJson((_p('e2e_submit_invalid_409')['detail'] as Map)['validation']);
    for (final build in <Widget Function()>[
      () => LearnStartBody(mine: _rows('library_teacher').where((r) => !r.isBuiltin).toList(), onOpen: (_) {}, onNew: () {}),
      () => LearnWaitingBody(name: 'School sheet 50', onBack: () {}),
      () => LearnResultBody(steps: done, image: null, published: true, version: 1, onCheck: () {}, onNewVersion: () {}, onBack: () {}),
      () => LearnResultBody(steps: failed, image: null, onReupload: () {}, onBack: () {}),
      () => LearnSaveBody(
          steps: done, validation: invalid, checking: false, isSuperAdmin: false, status: 'draft', version: 1,
          onBack: () {}, onOpenQuestion: (_) {}, onSubmit: () {}, onApprove: () {}, onReject: () {}),
      () => LearnSaveBody(
          steps: done, validation: failed.validation, checking: false, isSuperAdmin: true, readOnly: true, status: 'pending_approval', version: 3,
          onBack: () {}, onOpenQuestion: (_) {}, onSubmit: () {}, onApprove: () {}, onReject: () {}),
      () => LearnDoneBody(row: OmrTemplateRow.fromJson(_p('submit_teacher_pending')), onDone: () {}),
      () => LearnDoneBody(row: OmrTemplateRow.fromJson(_p('reject_ok')), onDone: () {}),
    ]) {
      await _check(tester, build);
    }
  });

  testWidgets('step-through: a question, the ID zone, the model row, fixing', (tester) async {
    final s = TemplateSteps.fromJson(_p('e2e_steps_done'));
    for (final build in <Widget Function()>[
      () => _step(s, 16),
      () => _step(s, 0, published: true),
      () => _step(s, 50),
      () => _step(s, 51),
      () => _step(s, 16, editing: true),
      () => _step(s, 16, editing: true, moveAll: true),
      () => _step(s, 50, editing: true),
    ]) {
      await _check(tester, build);
    }
  });

  testWidgets('accessibility: 48 × 48 targets, labelled, readable contrast (phone, ar + en)', (tester) async {
    final s = TemplateSteps.fromJson(_p('e2e_steps_done'));
    final rows = _rows('library_super');
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final handle = tester.ensureSemantics();
    for (final lang in const ['ar', 'en']) {
      for (final build in <Widget Function()>[
        () => _step(s, 16),
        () => _step(s, 16, editing: true),
        () => TemplateLibraryView(
            rows: rows, requireApproval: true, onFilter: (_) {}, onRetry: () {}, onNew: () {}, onFamily: (_) {}, onApprove: (_) {}, onReject: (_) {}, onReview: (_) {}, onApproval: (_) {}),
      ]) {
        AppConfig.lang = lang;
        await tester.pumpWidget(layoutHost(build(), scale: 1));
        await tester.pump(const Duration(milliseconds: 400));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      }
    }
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('library + a family sheet', (tester) async {
    final rows = _rows('library_super');
    final fam = groupFamilies(rows).firstWhere((f) => f.versions.length > 1);
    for (final build in <Widget Function()>[
      () => TemplateLibraryView(
            rows: rows,
            requireApproval: true,
            onFilter: (_) {},
            onRetry: () {},
            onNew: () {},
            onFamily: (_) {},
            onApprove: (_) {},
            onReject: (_) {},
            onReview: (_) {},
            onApproval: (_) {},
          ),
      () => TemplateLibraryView(
            rows: const [],
            onFilter: (_) {},
            onRetry: () {},
            onNew: () {},
            onFamily: (_) {},
            onApprove: (_) {},
            onReject: (_) {},
            onReview: (_) {},
          ),
      () => FamilySheet(family: fam, onAction: (_, _) {}),
      () => const RejectReasonSheet(),
    ]) {
      await _check(tester, build);
    }
  });
}
