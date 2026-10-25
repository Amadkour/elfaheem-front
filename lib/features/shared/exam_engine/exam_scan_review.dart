// Scanned answer sheets (Phase 6, brief §7.5): the original page side by side with what the OCR read, low-confidence
// words marked, the transcription corrected by the teacher (graded again), and the unmatched queue for pages whose
// QR code could not be read.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asMapList, t;
import 'exam_review.dart';
import 'exam_taking.dart' show examCodeText;

/// OCR words of one region; low-confidence ones are marked for the teacher (plain values, under the harness).
class OcrWordsView extends StatelessWidget {
  const OcrWordsView({super.key, required this.region});
  final OcrRegion region;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (region.words.isEmpty) return Text(region.text.isEmpty ? t('— لم يُقرأ نص —', '— no text read —') : region.text, style: appText(13.5, c: c.textMedium));
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final w in region.words)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: w.low ? BoxDecoration(color: c.danger.withValues(alpha: .12), borderRadius: BorderRadius.circular(4)) : null,
          child: Text(w.text, style: appText(13.5, c: w.low ? c.danger : c.textDark, w: w.low ? FontWeight.w700 : FontWeight.w500)),
        ),
    ]);
  }
}

/// The page image with the answer boxes outlined (normalised coordinates).
class ScanImageView extends StatelessWidget {
  const ScanImageView({super.key, required this.bytes, required this.regions});
  final Uint8List? bytes;
  final List<OcrRegion> regions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (bytes == null || bytes!.isEmpty) return const AppSkeletonBox(height: 280);
    return LayoutBuilder(builder: (_, box) {
      return InteractiveViewer(
        maxScale: 5,
        child: Stack(children: [
          Image.memory(bytes!, width: box.maxWidth, fit: BoxFit.fitWidth, gaplessPlayback: true),
          Positioned.fill(child: LayoutBuilder(builder: (_, b) => Stack(children: [
                for (final r in regions)
                  if (r.box.length == 4)
                    Positioned(left: r.box[0] * b.maxWidth, top: r.box[1] * b.maxHeight, width: r.box[2] * b.maxWidth, height: r.box[3] * b.maxHeight,
                        child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: c.primary, width: 2))))),
              ]))),
        ]),
      );
    });
  }
}

class ScanPageScreen extends StatefulWidget {
  const ScanPageScreen({super.key, required this.pageId});
  final int pageId;

  @override
  State<ScanPageScreen> createState() => _ScanPageScreenState();
}

class _ScanPageScreenState extends State<ScanPageScreen> {
  final _api = ExamReviewApi();
  ScanPageInfo? _page;
  Uint8List? _image;
  final Map<int, TextEditingController> _text = {};
  final _student = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _student.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await _api.scan(widget.pageId);
    final img = _image ?? await _api.scanImage(widget.pageId);
    if (!mounted) return;
    setState(() {
      _image = img;
      if (!r.ok) return;
      _page = ScanPageInfo.fromJson(r.map);
      for (final reg in _page!.regions) {
        final q = reg.questionId;
        if (q == null) continue;
        _text.putIfAbsent(q, () => TextEditingController()).text = _page!.corrected['$q'] ?? reg.text;
      }
    });
  }

  Future<void> _save(int questionId) async {
    setState(() => _busy = true);
    final r = await _api.correct(widget.pageId, questionId: questionId, text: _text[questionId]!.text);
    if (!mounted) return;
    setState(() => _busy = false);
    appToast(r.ok ? t('حُفظ النص وسيُعاد تصحيحه', 'Saved — it will be graded again') : examCodeText(r.code ?? r.message), error: !r.ok);
    if (r.ok) _load();
  }

  Future<void> _assign() async {
    final id = int.tryParse(_student.text.trim());
    if (id == null) return appToast(t('أدخل رقم الطالب', 'Enter the student id'), error: true);
    setState(() => _busy = true);
    final r = await _api.assign(widget.pageId, studentId: id);
    if (!mounted) return;
    setState(() => _busy = false);
    appToast(r.ok ? t('أُسندت الصفحة وستُقرأ', 'Assigned — the page will be read') : examCodeText(r.code ?? r.message), error: !r.ok);
    if (r.ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final c = context.colors;
    final wide = MediaQuery.of(context).size.width >= 900;
    final image = ScanImageView(bytes: _image, regions: p?.regions ?? const []);
    final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (p == null) const AppListSkeleton(items: 2),
      if (p != null) ...[
        Wrap(spacing: 8, runSpacing: 6, children: [
          AppBadgePill(scanStatusText(p.status), color: p.unmatched ? c.warning : c.primary),
          for (final w in p.warnings) AppBadgePill(qualityWarningText(w), color: c.danger, icon: Icons.warning_amber_rounded),
        ]),
        const SizedBox(height: 10),
        if (p.unmatched) ...[
          AppBanner(icon: Icons.qr_code_2_rounded, text: t('لم يُقرأ رمز الورقة — حدد الطالب', 'The sheet code could not be read — choose the student')),
          const SizedBox(height: 8),
          AppField(controller: _student, label: t('رقم الطالب', 'Student id'), keyboard: TextInputType.number, ltr: true),
          const SizedBox(height: 8),
          AppPrimaryButton(label: t('إسناد', 'Assign'), onPressed: _busy ? null : _assign, busy: _busy, icon: Icons.person_add_alt_1_rounded),
        ],
        for (final reg in p.regions)
          AppCard(
            margin: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(reg.questionId == null ? t('الصفحة', 'Page') : t('السؤال #${reg.questionId}', 'Question #${reg.questionId}'),
                  style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
              const SizedBox(height: 6),
              OcrWordsView(region: reg),
              if (reg.questionId != null && !p.unmatched) ...[
                const SizedBox(height: 8),
                AppField(controller: _text[reg.questionId]!, label: t('النص بعد التصحيح', 'Corrected text'), maxLines: 4),
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(onPressed: _busy ? null : () => _save(reg.questionId!), child: Text(t('حفظ النص', 'Save text')))),
              ],
            ]),
          ),
      ],
    ]);
    return BasePage(
      key: const ValueKey('exam.scan'),
      appBar: AppBar(title: Text(t('الورقة الممسوحة', 'Scanned page'))),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: image)),
              Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: side)),
            ])
          : ListView(padding: const EdgeInsets.all(16), children: [image, const SizedBox(height: 12), side]),
    );
  }
}

/// The exam's scanned pages, unmatched first.
class ExamScansScreen extends StatefulWidget {
  const ExamScansScreen({super.key, required this.examId, required this.examTitle, this.openPageId});
  final int examId;
  final String examTitle;
  final int? openPageId;

  @override
  State<ExamScansScreen> createState() => _ExamScansScreenState();
}

class _ExamScansScreenState extends State<ExamScansScreen> {
  final _api = ExamReviewApi();
  List<ScanPageInfo>? _pages;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.openPageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.openPageId!));
    }
  }

  Future<void> _load() async {
    final r = await _api.scans(widget.examId);
    if (!mounted || !r.ok) return;
    final pages = [for (final p in asMapList(r.map['items'])) ScanPageInfo.fromJson(p)]..sort((a, b) => (b.unmatched ? 1 : 0) - (a.unmatched ? 1 : 0));
    setState(() => _pages = pages);
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanPageScreen(pageId: id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = _pages;
    return BasePage(
      key: const ValueKey('exam.scans'),
      appBar: AppBar(title: Text(t('الأوراق الممسوحة', 'Scanned pages'))),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (pages == null) const AppListSkeleton(items: 4),
          if (pages != null && pages.isEmpty) AppEmpty(icon: Icons.document_scanner_outlined, title: t('لا توجد أوراق ممسوحة بعد', 'No scanned pages yet')),
          for (final p in pages ?? const <ScanPageInfo>[])
            AppCard(
              margin: const EdgeInsets.only(bottom: 10),
              onTap: () => _open(p.id),
              child: Row(children: [
                Icon(p.unmatched ? Icons.help_outline_rounded : Icons.description_outlined, color: p.unmatched ? c.warning : c.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(p.fileName ?? '#${p.id}', style: appText(13.5, w: FontWeight.w700, c: c.textDark), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                AppBadgePill(scanStatusText(p.status), color: p.unmatched ? c.warning : c.textMedium),
              ]),
            ),
        ]),
      ),
    );
  }
}
