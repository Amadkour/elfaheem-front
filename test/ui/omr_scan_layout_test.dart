// The scanner's presentational widgets at 320×640 and 1400×900, Arabic and English, text ×1.3: no overflow, no
// layout exception (CLAUDE.md "no overflow on any screen size"). Texts are the engine's recorded sentences; the
// smart-photos results / print modes are test/org/fixtures/omr_smart_payloads.json.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/shared/exam_engine/paper/review/omr_review.dart' show OmrStudent;
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_audience_picker.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_camera.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_paper_result.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_widgets.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_sheets_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Widget _camera(Widget child) => ColoredBox(color: const Color(0xFF3C4148), child: child);

final _smart = (jsonDecode(File('test/org/fixtures/omr_smart_payloads.json').readAsStringSync()) as Map)['payloads'] as Map;
Map<String, dynamic> _s(String name) => Map<String, dynamic>.from((_smart[name] as Map)['body'] as Map);
OmrCaptureResult _cap(String name) => OmrCaptureResult.fromJson(_s(name));

void main() {
  setUp(() => AppConfig.disableList = []);

  testWidgets('ScannerOverlay: a long hint, corners partly found, the steady run', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _camera(ScannerOverlay(
              message: t('الصورة ساطعة جدًا، تجنّب الضوء المباشر على الورقة.', 'Too bright, avoid direct light on the sheet.'),
              tone: OmrHintTone.warn,
              quarters: const [true, true, false, true],
              progress: .66,
            )));
  });

  testWidgets('ScannerTopBar + ScannerControls', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _camera(Column(children: [
              ScannerTopBar(
                  title: 'Physics mid-term — section B, morning group', onClose: () {}, countLabel: t('12 من 40', '12 of 40'), onCount: () {}, onTorch: () {}, torchOn: true),
              const Spacer(),
              ScannerControls(onShutter: () {}, onFinish: () {}, finishLabel: t('إنهاء (12)', 'Finish (12)'), onSwitch: () {}, onAuto: (_) {}),
            ])));
  });

  testWidgets('CaptureResultCard: accepted, duplicate, rejected with more issues', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _camera(ListView(padding: const EdgeInsets.all(16), children: [
              CaptureResultCard(accepted: true, title: t('تم التقاط الورقة 12 من 40', 'Paper 12 of 40 captured'), onDismiss: () {}),
              const SizedBox(height: 12),
              CaptureResultCard(accepted: true, duplicate: true, title: t('تم التقاط الورقة 2 من 40', 'Paper 2 of 40 captured'), onDismiss: () {}),
              const SizedBox(height: 12),
              CaptureResultCard(
                accepted: false,
                title: t('علامة الركن السفلي الأيسر غير ظاهرة.', 'Bottom-left corner mark is not visible.'),
                more: [t('الصورة غير واضحة، ثبّت الهاتف.', 'Too blurry, hold steady.')],
                onRetake: () {},
              ),
            ])));
  });

  testWidgets('CameraProblemView: every issue, web and phone', (tester) async {
    for (final issue in OmrCameraIssue.values) {
      for (final web in [true, false]) {
        await expectNoLayoutErrors(
            tester, () => CameraProblemView(issue: issue, web: web, onRetry: () {}, onSettings: web ? null : () {}, onUpload: () {}, onClose: () {}));
      }
    }
  });

  testWidgets('ScanProgressView: processing and done with rejected pages in every replacement state', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              ScanProgressView(
                headline: t('تمت معالجة 3 من 40 ورقة', '3 of 40 papers processed'),
                done: 3,
                total: 40,
                finished: false,
                graded: 3,
              ),
              const SizedBox(height: 16),
              ScanProgressView(
                headline: t('تمت معالجة 40 من 40 ورقة', '40 of 40 papers processed'),
                done: 40,
                total: 40,
                finished: true,
                graded: 33,
                review: 4,
                rejected: 3,
                failed: 1,
                duplicates: 2,
                rejectedPages: [
                  for (final (i, s) in const [null, 'uploading', 'processing', 'processed', 'review', 'rejected', 'failed'].indexed)
                    RejectedPageRow(
                      pageId: i,
                      text: t('الصفحة ${i + 7} غير واضحة (مهزوزة). يرجى رفع صورة أوضح لها.', 'Page ${i + 7} is too blurry. Please upload a clearer image of it.'),
                      instruction: t('الصورة غير واضحة، ثبّت الهاتف.', 'Too blurry, hold steady.'),
                      fileName: 'class-10B-morning-group-scans-batch-2026-11-02.pdf',
                      replacement: s,
                      replacementText: s == 'rejected' ? t('الصفحة 1 مقطوعة من الحافة. يرجى رفع صورة أوضح لها.', 'Page 1 is cut off at the edge. Please upload a clearer image of it.') : null,
                    ),
                ],
                onReplace: (_) {},
                onReview: () {},
                onResults: () {},
                onMore: () {},
              ),
            ]));
  });

  testWidgets('OmrToolsPanel and the sheets options', (tester) async {
    const info = OmrSheetsInfo(printable: true, questions: 6, sheetQuestions: 50, forms: ['A', 'B', 'C', 'D'], sheetForms: ['A', 'B', 'C', 'D'], idKind: 'shaded');
    final copies = TextEditingController(text: '30'), query = TextEditingController();
    addTearDown(copies.dispose);
    addTearDown(query.dispose);
    // the exam's audience as GET …/omr/students answers it (names, IDs masked except the last 4)
    final students = [
      for (var i = 0; i < 40; i++)
        OmrStudent(101 + i, i.isEven ? 'عبد الرحمن محمد عبد العزيز الشناوي $i' : 'Alexandra Konstantinopoulou-Smith $i', identifier: i % 3 == 0 ? null : '••••••${1000 + i}'),
    ];
    Widget picker() => OmrAudiencePickerBody(
          queryController: query,
          onQuery: (_) {},
          students: students,
          total: 120,
          selected: const {101, 102},
          onToggle: (_) {},
          onSelectAll: () {},
          onClear: () {},
          identifierLabel: t('الرقم الأكاديمي', 'Academic ID'),
        );
    for (final named in [false, true]) {
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                OmrToolsPanel(entries: [
                  OmrToolEntry(id: 'print', icon: Icons.print_outlined, title: t('طباعة أوراق التظليل', 'Print bubble sheets'), subtitle: 'PDF', onTap: () {}),
                  const OmrToolEntry(id: 'review', icon: Icons.rate_review_outlined, title: 'Review', subtitle: '', note: 'Available soon'),
                ], busy: 'print'),
                OmrSheetsOptionsView(
                  info: info,
                  mode: named ? OmrPrintMode.named : OmrPrintMode.blank,
                  onMode: (_) {},
                  forms: const {'A', 'B'},
                  onForm: (_) {},
                  copiesController: copies,
                  students: picker(),
                  onDownload: () {},
                  onShare: () {},
                  error: named ? t('طالب ليس من طلاب هذا الاختبار (#999)', 'Not a student of this exam (#999)') : null,
                ),
                OmrSheetsOptionsView(
                  info: const OmrSheetsInfo(printable: false, questions: 30, sheetQuestions: 100, idKind: 'handwritten'),
                  mode: OmrPrintMode.blank,
                  onMode: (_) {},
                  forms: const {},
                  onForm: (_) {},
                  copiesController: copies,
                  students: const SizedBox.shrink(),
                  onDownload: () {},
                  onShare: () {},
                ),
              ]));
    }
  });
  testWidgets('smart photos: the retake pill (the next photo replaces the earlier one · Cancel)', (tester) async {
    await expectNoLayoutErrors(tester, () => _camera(Align(alignment: Alignment.bottomCenter, child: RetakeTargetPill(onCancel: () {}))));
  });

  testWidgets('smart photos: the gentle hint', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _camera(ScannerOverlay(
              message: t('أضف قليلًا من الإضاءة — الورقة مقروءة لكن الصورة ستكون أوضح.', 'Add a little more light — the sheet is readable, the photo will be clearer.'),
              tone: OmrHintTone.gentle,
              quarters: const [true, true, true, true],
              progress: .33,
            )));
  });

  testWidgets('smart photos: the result card in every tier (thumbnail loading, tips, Retake)', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => _camera(ListView(padding: const EdgeInsets.all(16), children: [
              for (final n in ['capture_accept', 'capture_flags', 'capture_retake', 'capture_reject']) ...[
                Builder(builder: (_) {
                  final r = _cap(n);
                  return CaptureResultCard(
                    accepted: r.accepted,
                    title: r.text,
                    result: r.result,
                    more: r.accepted ? const [] : r.moreIssues,
                    previewLoading: r.result!.previewUrl != null,
                    onPreview: r.result!.previewUrl == null ? null : () {},
                    onRetake: () {},
                    onDismiss: () {},
                  );
                }),
                const SizedBox(height: 12),
              ],
            ])));
  });

  testWidgets('smart photos: the preview (loading, could not load) with Retake / Replace', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              OmrPreviewView(result: _cap('capture_retake').result!, loading: true, onRetake: () {}, onClose: () {}),
              const SizedBox(height: 16),
              OmrPreviewView(result: _cap('capture_reject').result!, onRetake: () {}, retakeLabel: t('استبدال هذه الصفحة', 'Replace this page'), onClose: () {}),
            ]));
  });

  testWidgets('smart photos: the batch with every tier, the read ones unfolded', (tester) async {
    final p = OmrBatchProgress.fromJson(_s('batch_smart'));
    await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
              ScanProgressView(
                headline: p.text,
                done: p.done,
                total: p.total,
                finished: p.finished,
                graded: p.graded,
                review: p.review,
                rejected: p.rejected,
                rejectedPages: [
                  for (final r in p.rejectedPages)
                    RejectedPageRow(pageId: r.pageId, text: r.text, instruction: r.instruction, fileName: r.fileName, result: r.result),
                ],
                papers: [
                  for (final (i, pg) in p.pages.indexed)
                    if (pg.result!.tier != OmrTier.reject)
                      OmrPaperRow(pageId: pg.pageId, label: t('الورقة ${i + 1}', 'Paper ${i + 1}'), fileName: 'class-10B-morning-group-scans-2026-11-03.pdf #${pg.label}', result: pg.result!),
                ],
                onReplace: (_) {},
                onPreview: (_, _) {},
                onReview: () {},
                onResults: () {},
                onMore: () {},
              ),
            ]),
        act: (tester) async {
          final ok = find.byKey(const ValueKey('omr.papers.ok'));
          await tester.ensureVisible(ok);
          await tester.pump();
          await tester.tap(ok, warnIfMissed: false);
        });
  });

  testWidgets('smart photos: the print modes, each selected, Pre-filled missing', (tester) async {
    final copies = TextEditingController(text: '30');
    addTearDown(copies.dispose);
    for (final (name, mode) in [
      ('sheets_info_modes', OmrPrintMode.prefilled),
      ('sheets_info_modes', OmrPrintMode.blank),
      ('sheets_info_no_prefilled', OmrPrintMode.named),
      ('sheets_info_modes_maps', OmrPrintMode.named),
    ]) {
      await expectNoLayoutErrors(
          tester,
          () => ListView(padding: const EdgeInsets.all(16), children: [
                OmrSheetsOptionsView(
                  info: OmrSheetsInfo.fromJson(_s(name)),
                  mode: mode,
                  onMode: (_) {},
                  order: OmrPrintOrder.identifier,
                  onOrder: (_) {},
                  index: true,
                  onIndex: (_) {},
                  forms: const {'A'},
                  onForm: (_) {},
                  copiesController: copies,
                  students: const SizedBox(height: 120),
                  onDownload: () {},
                  onShare: () {},
                ),
              ]));
    }
  });
}
