// Scanned answer sheets (Phase 6, brief §7.5): the original page side by side with what the OCR read, low-confidence
// words marked, the transcription corrected by the teacher (graded again), and the unmatched queue for pages whose
// QR code could not be read.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../admin/admin_common.dart' show asMapList, t;
import 'exam_engine_api.dart' show EngineResult;
import 'exam_paper_flow.dart';
import 'exam_review.dart';
import 'paper/exam_setup.dart' show ExamSetup, ExamSetupApi, kExamOmrFeatureKey;
import 'paper/scan/omr_scan_section.dart';

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
  const ScanPageScreen({super.key, required this.pageId, this.roster = const []});
  final int pageId;

  /// Students the exam knows (empty: the picker falls back to a typed id).
  final List<int> roster;

  @override
  State<ScanPageScreen> createState() => _ScanPageScreenState();
}

class _ScanPageScreenState extends State<ScanPageScreen> {
  final _api = ExamReviewApi();
  ScanPageInfo? _page;
  Uint8List? _image;
  final Map<int, TextEditingController> _text = {};
  final _student = TextEditingController();
  final _question = TextEditingController();
  int? _picked;
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
    _question.dispose();
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
    appToast(r.ok ? t('حُفظ النص وسيُعاد تصحيحه', 'Saved — it will be graded again') : paperFailText(r.code, r.message), error: !r.ok);
    if (r.ok) _load();
  }

  Future<void> _assign() async {
    final id = _picked ?? parseStudentIds(_student.text).firstOrNull;
    if (id == null) return appToast(t('اختر الطالب أو أدخل رقمه', 'Choose a student or enter the id'), error: true);
    final q = _question.text.trim().isEmpty ? null : int.tryParse(_question.text.trim());
    if (_question.text.trim().isNotEmpty && q == null) return appToast(t('رقم السؤال غير صالح', 'Invalid question id'), error: true);
    setState(() => _busy = true);
    final r = await _api.assign(widget.pageId, studentId: id, questionId: q);
    if (!mounted) return;
    setState(() => _busy = false);
    appToast(r.ok ? t('أُسندت الصفحة وستُقرأ', 'Assigned — the page will be read') : paperFailText(r.code, r.message), error: !r.ok);
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
          StudentPickView(roster: widget.roster, selected: _picked, idController: _student, onSelect: (id) => setState(() => _picked = id)),
          const SizedBox(height: 8),
          AppField(controller: _question, label: t('رقم السؤال (اختياري)', 'Question id (optional)'), keyboard: TextInputType.number, ltr: true),
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
  List<int> _roster = const [];
  List<int> _batches = const [];
  String? _busy; // sheets | upload | mapping | marks
  String? _summary;
  List<PaperProblem> _problems = const [];
  int? _lastBatch;

  /// The exam's paper format (D-151): bubble / both get the bubble-sheet tools (D-154 … D-159) first.
  ExamSetup? _setup;

  bool get _omr => (_setup?.isBubble ?? false) && !AppConfig.disableList.contains(kExamOmrFeatureKey);

  @override
  void initState() {
    super.initState();
    _load();
    _loadRoster();
    _loadSetup();
    if (widget.openPageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(widget.openPageId!));
    }
  }

  Future<void> _load() async {
    final r = await _api.scans(widget.examId);
    if (!mounted || !r.ok) return;
    final pages = [for (final p in asMapList(r.map['items'])) ScanPageInfo.fromJson(p)]..sort((a, b) => (b.unmatched ? 1 : 0) - (a.unmatched ? 1 : 0));
    setState(() {
      _pages = pages;
      _batches = batchIdsOf(r.map);
    });
  }

  Future<void> _loadSetup() async {
    final r = await ExamSetupApi().setup(widget.examId);
    if (mounted && r.ok) setState(() => _setup = ExamSetup.fromJson(r.map));
  }

  Future<void> _loadRoster() async {
    final r = await _api.attempts(widget.examId);
    if (mounted && r.ok) setState(() => _roster = rosterFromAttempts(r.map));
  }

  void _result(String summary, List<PaperProblem> problems) => setState(() {
        _summary = summary;
        _problems = problems;
      });

  void _fail(EngineResult r) {
    final problems = parseProblems(r.detail['problems']);
    final text = paperFailText(r.code, r.message);
    if (problems.isNotEmpty) {
      _result(text, problems);
    } else {
      setState(() => _summary = null);
    }
    appToast(text, error: true);
  }

  Future<Uint8List?> _readFile(PlatformFile f) async {
    try {
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<List<(String, Uint8List)>> _pick(List<String> ext, {bool many = false}) async {
    final picked = many
        ? await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ext)
        : [if (await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ext) case final f?) f];
    return [
      for (final f in picked)
        if (await _readFile(f) case final b?) (f.name, b)
    ];
  }

  Future<void> _upload() async {
    final files = await _pick(const ['png', 'jpg', 'jpeg', 'webp', 'pdf'], many: true);
    if (files.isEmpty || !mounted) return;
    if (files.length > 50) return appToast(paperCodeText('too_many_files'), error: true);
    setState(() => _busy = 'upload');
    final r = await _api.uploadScans(widget.examId, files);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _fail(r);
    final u = ScanUploadResult.fromJson(r.map);
    _lastBatch = u.batchId;
    _result(u.summary, const []);
    _load();
  }

  Future<void> _mapping() async {
    final batch = await showAppSheet<int>(context, (_) => _BatchSheet(batches: _batches, initial: _lastBatch));
    if (batch == null || !mounted) return;
    final files = await _pick(const ['csv', 'xlsx']);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = 'mapping');
    final r = await _api.scanMapping(widget.examId, files.first.$1, files.first.$2, batchId: batch);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _fail(r);
    final m = MappingResult.fromJson(r.map);
    _result(m.summary, m.problems);
    _load();
  }

  Future<void> _marks() async {
    final files = await _pick(const ['csv', 'xlsx']);
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = 'marks');
    final r = await _api.importMarks(widget.examId, files.first.$1, files.first.$2);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _fail(r);
    final m = MarksImportResult.fromJson(r.map);
    _result(m.summary, m.problems);
  }

  Future<void> _sheets() async {
    await showAppSheet<void>(context, (_) => _SheetsSheet(examId: widget.examId, roster: _roster, api: _api));
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanPageScreen(pageId: id, roster: _roster)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pages = _pages;
    return BasePage(
      key: const ValueKey('exam.scans'),
      appBar: AppBar(title: Text(t('الأوراق الممسوحة', 'Scanned pages'))),
      child: AppRefresh(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_omr) ...[
            OmrScanSection(examId: widget.examId, examTitle: widget.examTitle, roster: _roster, onChanged: _load),
            const SizedBox(height: 8),
            // the written-answer tools stay reachable (QR answer sheets, mapping, marks import), folded away
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const ValueKey('omr.other_tools'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(t('أدوات ورقية أخرى', 'Other paper tools'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
                subtitle: Text(t('أوراق الإجابة بالرمز، ملف الإسناد، استيراد الدرجات', 'QR answer sheets, mapping file, marks import'), style: appText(12, c: c.textMedium)),
                children: [PaperToolsPanel(busy: _busy, onSheets: _sheets, onUpload: _upload, onMapping: _mapping, onMarks: _marks)],
              ),
            ),
          ] else
            PaperToolsPanel(busy: _busy, onSheets: _sheets, onUpload: _upload, onMapping: _mapping, onMarks: _marks),
          if (_summary != null) ...[const SizedBox(height: 4), PaperResultView(summary: _summary!, problems: _problems), const SizedBox(height: 8)],
          const SizedBox(height: 8),
          AppSectionTitle(t('الصفحات الممسوحة', 'Scanned pages')),
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

/// Pick the batch a mapping file applies to (a batch id the uploads returned, or typed).
class _BatchSheet extends StatefulWidget {
  const _BatchSheet({required this.batches, this.initial});
  final List<int> batches;
  final int? initial;

  @override
  State<_BatchSheet> createState() => _BatchSheetState();
}

class _BatchSheetState extends State<_BatchSheet> {
  late final _ctl = TextEditingController(text: '${widget.initial ?? (widget.batches.isEmpty ? '' : widget.batches.first)}');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('ملف الإسناد', 'Mapping file')),
      AppBanner(icon: Icons.info_outline_rounded, text: t('الأعمدة: student_id, file_name وسؤال اختياري question_id', 'Columns: student_id, file_name and an optional question_id')),
      const SizedBox(height: 10),
      if (widget.batches.isNotEmpty)
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final b in widget.batches.take(12))
            AppChoiceChip(label: '#$b', selected: _ctl.text.trim() == '$b', onTap: () => setState(() => _ctl.text = '$b')),
        ]),
      const SizedBox(height: 10),
      AppField(controller: _ctl, label: t('رقم الدفعة', 'Batch id'), keyboard: TextInputType.number, ltr: true),
      const SizedBox(height: 12),
      AppPrimaryButton(
        label: t('اختيار الملف', 'Choose the file'),
        icon: Icons.attach_file_rounded,
        onPressed: () {
          final id = int.tryParse(_ctl.text.trim());
          if (id == null) return appToast(t('أدخل رقم الدفعة', 'Enter the batch id'), error: true);
          Navigator.pop(context, id);
        },
      ),
    ]);
  }
}

/// Answer sheets: roster chips + typed ids + blank count, then save or share the PDF.
class _SheetsSheet extends StatefulWidget {
  const _SheetsSheet({required this.examId, required this.roster, required this.api});
  final int examId;
  final List<int> roster;
  final ExamReviewApi api;

  @override
  State<_SheetsSheet> createState() => _SheetsSheetState();
}

class _SheetsSheetState extends State<_SheetsSheet> {
  final _ids = TextEditingController();
  final _blank = TextEditingController(text: '0');
  final Set<int> _selected = {};
  bool _busy = false;

  @override
  void dispose() {
    _ids.dispose();
    _blank.dispose();
    super.dispose();
  }

  Future<Uint8List?> _make() async {
    final ids = {..._selected, ...parseStudentIds(_ids.text)}.toList()..sort();
    final blank = int.tryParse(_blank.text.trim()) ?? 0;
    if (ids.isEmpty && blank <= 0) {
      appToast(paperCodeText('students_required'), error: true);
      return null;
    }
    setState(() => _busy = true);
    final bytes = await widget.api.sheetsPdf(widget.examId, studentIds: ids, blank: blank.clamp(0, 500));
    if (!mounted) return null;
    setState(() => _busy = false);
    if (bytes == null || bytes.isEmpty) {
      appToast(t('تعذر إنشاء الأوراق — تأكد من الطلاب والعدد', 'Could not create the sheets — check the students and the count'), error: true);
      return null;
    }
    return bytes;
  }

  String get _name => 'answer-sheets-${widget.examId}';

  Future<void> _download() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await FileSaver.instance.saveFile(name: _name, bytes: bytes, fileExtension: 'pdf', mimeType: MimeType.pdf);
      appToast(t('حُفظ الملف', 'File saved'));
      if (mounted) Navigator.pop(context);
    } catch (_) {
      appToast(t('تعذر حفظ الملف', 'Could not save the file'), error: true);
    }
  }

  Future<void> _share() async {
    final bytes = await _make();
    if (bytes == null) return;
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: '$_name.pdf')], fileNameOverrides: ['$_name.pdf']));
    } catch (_) {
      appToast(t('تعذرت المشاركة', 'Could not share'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(t('أوراق الإجابة', 'Answer sheets')),
      SheetsOptionsView(
        roster: widget.roster, selected: _selected, idsController: _ids, blankController: _blank, busy: _busy,
        onToggle: (id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id)),
        onSubmit: _download, onShare: _share,
      ),
    ]);
  }
}
