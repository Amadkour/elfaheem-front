// A bubble-sheet correction, from the choice of sheet to the marks (D-341 – D-343): start from the model answer alone
// (D-671: the sheet, the number of questions and the key are read off it) or pick a sheet and enter the key (a grid,
// or a marked sheet read back to you), then correct and review with the existing paper-exam sections
// (`OmrScanSection`, live progress with `EventOrPoll`), and send the marks to Data Lab with a before / after preview.
// The engine decides every mark; a wrong automatic mark is worse than asking.
library;

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';

import '../../../../admin/admin_common.dart' show asMap, t;
import '../exam_setup.dart' show OmrTemplateItem;
import '../../exam_engine_api.dart' show EngineResult;
import '../review/omr_review.dart' show OmrResults, OmrReviewApi, omrResultsExport;
import '../scan/omr_routes.dart' show openOmrReview, openOmrResults;
import '../scan/omr_scan_section.dart';
import '../scan/omr_scan.dart' show OmrScanApi;
import '../templates/own_sheet.dart' show OwnSheetPicker, defaultOwnSheetPicker;
import 'bubble_flow.dart';
import 'bubble_import_screen.dart';
import 'bubble_widgets.dart';

/// "Correct bubble sheets" for a course, or ([courseId] null, D-672) for students in no course.
class BubbleHomeScreen extends StatefulWidget {
  const BubbleHomeScreen({super.key, this.courseId, required this.courseTitle, this.orgId, this.api, this.picker});
  final int? courseId;
  final String courseTitle;
  final int? orgId;
  final BubbleApi? api;
  final OwnSheetPicker? picker;

  @override
  State<BubbleHomeScreen> createState() => _BubbleHomeScreenState();
}

class _BubbleHomeScreenState extends State<BubbleHomeScreen> {
  late final BubbleApi _api = widget.api ?? BubbleApi();
  List<OmrTemplateItem>? _sheets;
  List<Map<String, dynamic>> _drafts = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final r = await _api.templates(orgId: widget.orgId);
    final d = await _api.drafts(orgId: widget.orgId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        final items = r.map['items'] is List ? r.map['items'] as List : const [];
        _sheets = [for (final x in items) if (x is Map<String, dynamic> && x['status'] == 'published') OmrTemplateItem.fromJson(x)];
      } else {
        _error = bubbleErrorText(r);
      }
      if (d.ok) {
        final items = d.map['items'] is List ? d.map['items'] as List : const [];
        _drafts = [for (final x in items) if (x is Map<String, dynamic>) x];
      }
    });
  }

  Future<void> _import({int? resumeId}) async {
    final id = await openBubbleImport(context, orgId: widget.orgId, resumeId: resumeId, api: widget.api, picker: widget.picker);
    if (!mounted) return;
    await _load();
    if (id != null) {
      final item = _sheets?.where((s) => s.id == id).firstOrNull;
      if (item != null && mounted) await _startRun(item);
    }
  }

  /// The model answer alone: photographed or uploaded, it gives the sheet, the number of questions and the key.
  Future<void> _fromKey() async {
    final title = TextEditingController(text: t('تصحيح ${widget.courseTitle}', 'Correct ${widget.courseTitle}'));
    final phone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    var source = widget.courseId == null ? BubbleIdSource.fileName : BubbleIdSource.bubble;
    final camera = await showAppSheet<bool>(context, (ctx) => AppSheetContent(title: t('ابدأ من الإجابة النموذجية', 'Start from the model answer'), children: [
          Text(
            t('ظلّل الإجابات الصحيحة على نسخة من ورقة الطلاب نفسها، ثم صوّرها أو ارفعها صورةً أو PDF. نتعرّف على الورقة وعدد الأسئلة ومفتاح الإجابة تلقائيًا.',
                'Shade the right answers on a copy of the students\' own sheet, then photograph it or upload it as an image or a PDF. We find the sheet, the number of questions and the key for you.'),
            style: AppType.body(context),
          ),
          const SizedBox(height: AppSpace.md),
          AppField(controller: title, label: t('اسم التصحيح', 'Name of this correction')),
          const SizedBox(height: AppSpace.md),
          StatefulBuilder(
            builder: (context, set) => AppDropdown<BubbleIdSource>(
              key: const ValueKey('bubble.fromKey.idsrc'),
              value: source,
              decoration: InputDecoration(labelText: t('رقم الطالب يُؤخذ', "The student's ID comes")),
              items: [for (final x in BubbleIdSource.values) DropdownMenuItem(value: x, child: Text(bubbleIdSourceLabel(x), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => set(() => source = v ?? source),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          if (phone) ...[
            AppButton.primary(label: t('تصوير الإجابة النموذجية', 'Photograph the model answer'), icon: Icons.photo_camera_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
            const SizedBox(height: AppSpace.sm),
            AppButton.secondary(label: t('اختيار ملف (صورة أو PDF)', 'Choose a file (image or PDF)'), icon: Icons.upload_file_rounded, expand: true, onPressed: () => Navigator.pop(ctx, false)),
          ] else
            AppButton.primary(label: t('اختيار ملف (صورة أو PDF)', 'Choose a file (image or PDF)'), icon: Icons.upload_file_rounded, expand: true, onPressed: () => Navigator.pop(ctx, false)),
        ]));
    if (camera == null || !mounted) return;
    final f = await (widget.picker ?? defaultOwnSheetPicker)(camera: camera);
    if (f == null || !mounted) return;
    setState(() => _busy = true);
    final name = title.text.trim().isEmpty ? t('تصحيح ${widget.courseTitle}', 'Correct ${widget.courseTitle}') : title.text.trim();
    final r = await _api.createRunFromKey(courseId: widget.courseId, title: name, file: f, idSource: source);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      appToast(bubbleErrorText(r), error: true);
      return;
    }
    final run = BubbleRun.fromJson(r.map);
    final read = BubbleKeyRead.fromJson(asMap(r.map['key_read']));
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BubbleRunScreen(examId: run.id, initial: run, keyRead: read, api: widget.api, picker: widget.picker)));
    if (mounted) await _load();
  }

  Future<void> _startRun(OmrTemplateItem item) async {
    final title = TextEditingController(text: t('تصحيح ${item.name}', 'Correct ${item.name}'));
    final count = TextEditingController(text: '${item.questions}');
    final ok = await showAppSheet<bool>(context, (ctx) => AppSheetContent(title: t('تصحيح جديد', 'New correction'), children: [
          AppField(controller: title, label: t('الاسم', 'Name')),
          const SizedBox(height: AppSpace.sm),
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: count, label: t('عدد الأسئلة المستخدمة', 'Questions used'), min: 1)),
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(label: t('متابعة', 'Continue'), icon: Icons.arrow_forward_rounded, onPressed: () => Navigator.pop(ctx, true)),
        ]));
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.createRun(courseId: widget.courseId, templateId: item.id, title: title.text.trim().isEmpty ? item.name : title.text.trim(),
        questions: int.tryParse(count.text.trim()), idSource: widget.courseId == null ? BubbleIdSource.fileName : null);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      appToast(bubbleErrorText(r), error: true);
      return;
    }
    final run = BubbleRun.fromJson(r.map);
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BubbleRunScreen(examId: run.id, initial: run, api: widget.api, picker: widget.picker)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sheets = _sheets;
    final Widget body;
    if (sheets == null) {
      body = _error != null ? AppEmpty(icon: Icons.document_scanner_rounded, title: _error!) : const AppListSkeleton(items: 4, withAvatar: false);
    } else {
      final own = [for (final s in sheets) if (s.isOwnSheet) s];
      final ready = [for (final s in sheets) if (!s.isOwnSheet) s];
      body = LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 840;
        return ListView(padding: EdgeInsets.all(wide ? AppSpace.lg : AppSpace.md), children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                AppHero(
                  icon: Icons.grading_rounded,
                  title: t('تصحيح أوراق التظليل', 'Correct bubble sheets'),
                  subtitle: t('استخدم أي ورقة، ثم صحّح فصلًا كاملًا من الصور أو الملفات.', 'Use any sheet, then correct a whole class from photos or files.'),
                ),
                const SizedBox(height: AppSpace.md),
                ParentComponent(
                  featureKey: kBubbleFromKeyFeature,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: AppActionCard(
                      icon: Icons.auto_awesome_rounded,
                      color: c.primary,
                      title: t('ابدأ من الإجابة النموذجية', 'Start from the model answer'),
                      subtitle: t('بلا اختيار ورقة ولا كتابة مفتاح: نتعرّف على الورقة وعدد الأسئلة والمفتاح', 'No sheet to pick, no key to type: we find the sheet, the questions and the key'),
                      trailing: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                      onTap: _busy ? null : _fromKey,
                    ),
                  ),
                ),
                ParentComponent(
                  featureKey: kBubbleTeachFeature,
                  child: AppActionCard(
                    icon: Icons.add_a_photo_rounded,
                    title: t('استيراد ورقة جديدة', 'Import a new sheet'),
                    subtitle: t('علّم المنصة ورقة مدرستك في دقائق', 'Teach the platform your school\'s sheet in minutes'),
                    onTap: () => _import(),
                  ),
                ),
                if (_drafts.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  for (final d in _drafts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.xs),
                      child: AppBanner(
                        icon: Icons.pending_actions_rounded,
                        text: t('متابعة استيراد «${d['name'] ?? 'ورقة'}»', 'Continue importing "${d['name'] ?? 'a sheet'}"'),
                        action: TextButton(onPressed: () => _import(resumeId: d['id'] as int), child: Text(t('متابعة', 'Continue'))),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpace.md),
                if (own.isNotEmpty) ...[
                  AppSectionTitle(t('أوراقي المحفوظة', 'My saved sheets')),
                  const SizedBox(height: AppSpace.xs),
                  _SheetGrid(items: own, wide: wide, busy: _busy, onPick: _startRun),
                  const SizedBox(height: AppSpace.md),
                ],
                AppSectionTitle(t('أوراق المنصة الجاهزة', 'Ready platform sheets')),
                const SizedBox(height: AppSpace.xs),
                if (ready.isEmpty)
                  AppEmpty(icon: Icons.grid_on_rounded, title: t('لا توجد أوراق جاهزة بعد', 'No ready sheets yet'))
                else
                  _SheetGrid(items: ready, wide: wide, busy: _busy, onPick: _startRun),
                const SizedBox(height: AppSpace.xl),
                Text(widget.courseTitle, style: AppType.meta(context).copyWith(color: c.textLight), textAlign: TextAlign.center),
              ]),
            ),
          ),
        ]);
      });
    }
    return BasePage(key: const ValueKey(kBubbleFeature), appBar: ScreenAppBar(title: t('أوراق التظليل', 'Bubble sheets')), child: body);
  }
}

class _SheetGrid extends StatelessWidget {
  const _SheetGrid({required this.items, required this.wide, required this.busy, required this.onPick});
  final List<OmrTemplateItem> items;
  final bool wide, busy;
  final void Function(OmrTemplateItem) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
      for (final s in items)
        SizedBox(
          width: wide ? 320 : double.infinity,
          child: AppCard(
            onTap: busy ? null : () => onPick(s),
            padding: AppSpace.card,
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Icon(s.isOwnSheet ? Icons.draw_rounded : Icons.grid_on_rounded, color: c.primary),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                  Text('${s.questions} ${t('سؤال', 'questions')} · ${s.options ?? '?'} ${t('اختيارات', 'choices')}', style: AppType.meta(context)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textLight),
            ]),
          ),
        ),
    ]);
  }
}

/// One correction: the key, then correct and review, then where the marks go.
class BubbleRunScreen extends StatefulWidget {
  const BubbleRunScreen({super.key, required this.examId, this.initial, this.keyRead, this.api, this.picker});
  final int examId;
  final BubbleRun? initial;

  /// Set when the correction was just started from the model answer: what was read off it.
  final BubbleKeyRead? keyRead;
  final BubbleApi? api;
  final OwnSheetPicker? picker;

  @override
  State<BubbleRunScreen> createState() => _BubbleRunScreenState();
}

class _BubbleRunScreenState extends State<BubbleRunScreen> {
  late final BubbleApi _api = widget.api ?? BubbleApi();
  BubbleRun? _run;
  String? _error;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _run = widget.initial;
    if (_run == null) _load();
  }

  Future<void> _load() async {
    final r = await _api.run(widget.examId);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _run = BubbleRun.fromJson(r.map);
        _error = null;
      } else {
        _error = bubbleErrorText(r);
      }
    });
  }

  Future<void> _apply(EngineResult r) async {
    if (!mounted) return;
    if (!r.ok) {
      appToast(bubbleErrorText(r), error: true);
      return;
    }
    setState(() => _run = BubbleRun.fromJson(r.map));
  }

  /// Where the student's ID comes from (D-672); the written source asks for the name area right away.
  Future<void> _changeSource() async {
    final run = _run;
    if (run == null) return;
    final pick = await showAppSheet<BubbleIdSource>(context, (ctx) => AppSheetContent(title: t('من أين يُؤخذ رقم الطالب؟', "Where does the student's ID come from?"), children: [
          BubbleIdSourceChoice(selected: run.students.idSource, onPick: (x) => Navigator.pop(ctx, x)),
        ]));
    if (pick == null || !mounted || pick == run.students.idSource) return;
    await _apply(await _api.putIdentity(run.id, pick));
    if (pick == BubbleIdSource.image && mounted && _run?.idBox == null) await _markBox();
  }

  Future<void> _markBox() async {
    final run = _run;
    final tid = run?.templateId;
    if (run == null || tid == null) return;
    Uint8List? img;
    try {
      img = await _api.templateImage(tid);
    } catch (_) {
      img = null;
    }
    if (!mounted) return;
    if (img == null) {
      appToast(t('تعذر تحميل صورة الورقة', "Couldn't load the sheet's picture"), error: true);
      return;
    }
    final image = img;
    final box = await showAppSheet<List<double>>(context, (ctx) => AppSheetContent(title: t('مكان الاسم على الورقة', 'Where the name is on the sheet'), children: [
          BubbleBoxPicker(image: image, initial: run.idBox, onDone: (b) => Navigator.pop(ctx, b)),
        ]));
    if (box == null || !mounted) return;
    await _apply(await _api.putIdentity(run.id, BubbleIdSource.image, box: box));
  }

  Future<void> _pasteList() async {
    final run = _run;
    if (run == null) return;
    final text = TextEditingController();
    final ok = await showAppSheet<bool>(context, (ctx) => AppSheetContent(title: t('قائمة الطلاب', 'The class list'), children: [
          Text(t('طالب في كل سطر: الرقم والاسم بأي ترتيب، مثل «2041 علي حسن». يمكنك النسخ من Excel.', 'One student per line: the ID and the name in any order, like "2041 Ali Hassan". You can copy from Excel.'),
              style: AppType.body(context)),
          const SizedBox(height: AppSpace.sm),
          AppField(controller: text, label: t('الطلاب', 'Students'), maxLines: 8),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(label: t('إضافة', 'Add'), icon: Icons.group_add_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
        ]));
    final items = parseClassList(text.text);
    text.dispose();
    if (ok != true || items.isEmpty || !mounted) return;
    final r = await _api.addPeople(run.id, items);
    await _apply(r);
    if (r.ok) {
      final a = asMap(r.map['people_added']);
      appToast(t('أُضيف ${a['added'] ?? 0} وحُدّث ${a['updated'] ?? 0}', 'Added ${a['added'] ?? 0}, updated ${a['updated'] ?? 0}'));
    }
  }

  Future<void> _editPeople() async {
    final run = _run;
    if (run == null) return;
    final who = await showAppSheet<BubblePerson>(context, (ctx) => AppSheetContent(title: t('طلاب هذا التصحيح', 'Students of this correction'), children: [
          for (final p in run.students.people)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: p.code == null ? null : Text(p.code!, textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ]));
    if (who == null || !mounted) return;
    final name = TextEditingController(text: who.name ?? '');
    final code = TextEditingController(text: who.code ?? '');
    final ok = await showAppSheet<bool>(context, (ctx) => AppSheetContent(title: t('تعديل الطالب', 'Edit the student'), children: [
          AppField(controller: name, label: t('الاسم', 'Name')),
          const SizedBox(height: AppSpace.sm),
          AppField(controller: code, label: t('الرقم', 'ID')),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(label: t('حفظ', 'Save'), icon: Icons.check_rounded, expand: true, onPressed: () => Navigator.pop(ctx, true)),
        ]));
    final n = name.text.trim(), c = code.text.trim();
    name.dispose();
    code.dispose();
    if (ok != true || !mounted) return;
    await _apply(await _api.putPerson(run.id, who.id, name: n, code: c));
  }

  Future<void> _exportResults() async {
    final run = _run;
    if (run == null) return;
    final r = await OmrReviewApi().results(run.id);
    if (!mounted) return;
    if (!r.ok) {
      appToast(bubbleErrorText(r), error: true);
      return;
    }
    final res = OmrResults.fromJson(r.map);
    showAppExportSheet(context, bilingualExport(() => omrResultsExport(res)));
  }

  /// Every graded student's corrected sheet: a ZIP of images, or one PDF.
  Future<void> _corrected() async {
    final run = _run;
    if (run == null) return;
    final fmt = await showAppSheet<String>(context, (ctx) => AppSheetContent(title: t('الأوراق المصححة', 'Corrected sheets'), children: [
          Text(t('ورقة كل طالب: الصحيحة بالأخضر، والخاطئة بالأحمر، والمتروكة بالبرتقالي، مع الاسم والدرجة.', "Each student's sheet: right in green, wrong in red, left blank in orange, with the name and score."),
              style: AppType.body(context)),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(key: const ValueKey('bubble.corrected.zip'), label: t('صورة لكل طالب (ZIP)', 'An image per student (ZIP)'), icon: Icons.folder_zip_rounded, expand: true, onPressed: () => Navigator.pop(ctx, 'zip')),
          const SizedBox(height: AppSpace.sm),
          AppButton.secondary(key: const ValueKey('bubble.corrected.pdf'), label: t('ملف PDF واحد', 'One PDF'), icon: Icons.picture_as_pdf_rounded, expand: true, onPressed: () => Navigator.pop(ctx, 'pdf')),
        ]));
    if (fmt == null || !mounted) return;
    setState(() => _downloading = true);
    Uint8List? bytes;
    String? error;
    try {
      bytes = await _api.corrected(run.id, fmt);
    } catch (e) {
      error = ApiException.from(e).message;
    }
    if (!mounted) return;
    setState(() => _downloading = false);
    if (bytes == null) {
      appToast(error ?? t('تعذر التنزيل', 'Download failed'), error: true);
      return;
    }
    final name = '${run.title} - ${t('مصحح', 'corrected')}';
    final phone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final mime = fmt == 'zip' ? 'application/zip' : 'application/pdf';
    try {
      if (phone) {
        await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, mimeType: mime, name: '$name.$fmt')], fileNameOverrides: ['$name.$fmt']));
      } else {
        await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: fmt, mimeType: fmt == 'zip' ? MimeType.zip : MimeType.pdf);
        appToast(t('حُفظ الملف', 'File saved'));
      }
    } catch (_) {
      appToast(t('تعذر حفظ الملف', "Couldn't save the file"), error: true);
    }
  }

  Future<void> _openKey() async {
    final run = _run;
    if (run == null) return;
    final saved = await Navigator.of(context).push<BubbleRun>(MaterialPageRoute(builder: (_) => BubbleKeyScreen(run: run, api: widget.api, picker: widget.picker)));
    if (saved != null && mounted) setState(() => _run = saved);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final run = _run;
    final Widget body;
    if (run == null) {
      body = _error != null ? AppEmpty(icon: Icons.grading_rounded, title: _error!, actionLabel: t('إعادة', 'Retry'), onAction: _load) : const AppListSkeleton(items: 4, withAvatar: false);
    } else {
      body = ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppWidth.content.max),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppHero(icon: Icons.fact_check_rounded, title: run.title, subtitle: run.sheetName),
              const SizedBox(height: AppSpace.md),
              if (widget.keyRead != null) ...[
                BubbleKeyReadBanner(read: widget.keyRead!, onCheck: _openKey),
                const SizedBox(height: AppSpace.md),
              ],
              BubbleIdSourceCard(source: run.students.idSource, boxSet: run.idBox != null, onChange: _changeSource, onMarkBox: run.templateId == null ? null : _markBox),
              const SizedBox(height: AppSpace.md),
              if (run.students.open) ...[
                BubbleStudentsCard(students: run.students, onPaste: _pasteList, onEdit: _editPeople),
                const SizedBox(height: AppSpace.md),
              ],
              AppCard(
                padding: AppSpace.card,
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t('مفتاح الإجابة', 'Answer key'), style: AppType.section(context)),
                      Text(run.hasKey ? t('جاهز · يمكن تعديله في أي وقت', 'Ready · can be edited any time') : t('مطلوب قبل التصحيح', 'Required before correcting'), style: AppType.meta(context).copyWith(color: run.hasKey ? c.success : c.warning)),
                    ]),
                  ),
                  AppButton.primary(label: run.hasKey ? t('تعديل', 'Edit') : t('إدخال المفتاح', 'Enter the key'), icon: Icons.key_rounded, onPressed: _openKey),
                ]),
              ),
              const SizedBox(height: AppSpace.md),
              if (run.hasKey) ...[
                OmrScanSection(examId: run.id, examTitle: run.title, ownSheet: run.ownSheet, api: OmrScanApi(), onChanged: _load),
                const SizedBox(height: AppSpace.md),
                AppActionCard(
                  key: const ValueKey('bubble.export'),
                  icon: Icons.ios_share_rounded,
                  title: t('تصدير النتائج', 'Export the results'),
                  subtitle: t('Excel أو PDF أو Word: الطالب والدرجة والصحيحة والمُجابة', 'Excel, PDF or Word: student, score, right and answered'),
                  onTap: _exportResults,
                ),
                const SizedBox(height: AppSpace.sm),
                AppActionCard(
                  key: const ValueKey('bubble.corrected'),
                  icon: Icons.fact_check_rounded,
                  title: t('الأوراق المصححة', 'Corrected sheets'),
                  subtitle: t('ورقة كل طالب مصححة مع درجته: صور أو PDF', "Each student's corrected sheet with the score: images or PDF"),
                  trailing: _downloading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : null,
                  onTap: _downloading ? null : _corrected,
                ),
                const SizedBox(height: AppSpace.sm),
                if (run.courseId != null) ParentComponent(
                  featureKey: kBubbleDataLabFeature,
                  child: AppActionCard(
                    icon: Icons.table_chart_rounded,
                    title: t('كتابة الدرجات في Data Lab', 'Write the marks into Data Lab'),
                    subtitle: t('معاينة قبل وبعد، مع تأكيد قبل الكتابة فوق أي درجة', 'Before and after, confirmed before overwriting'),
                    onTap: () => showBubbleDataLab(context, run: run, api: _api),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                AppActionCard(
                  icon: Icons.insights_rounded,
                  title: t('النتائج والتحليلات', 'Results and analytics'),
                  subtitle: t('أصعب الأسئلة، أكثر خطأ، التوزيع، وExcel', 'Hardest questions, most-chosen wrong answer, distribution, Excel'),
                  onTap: () => openOmrResults(context, run.id),
                ),
              ] else
                AppEmpty(icon: Icons.key_rounded, title: t('أدخل مفتاح الإجابة أولًا', 'Enter the answer key first'), message: t('ثم ارفع صور أوراق الطلاب أو ملف PDF.', 'Then upload the students\' sheets as images or a PDF.')),
              if (run.learned > 0) ...[
                const SizedBox(height: AppSpace.sm),
                AppBanner(icon: Icons.auto_awesome_rounded, text: t('تحسّنت هذه الورقة من ${run.learned} تصحيحًا سابقًا.', 'This sheet improved from ${run.learned} earlier corrections.')),
              ],
              if (run.openItems > 0) ...[
                const SizedBox(height: AppSpace.sm),
                AppBanner(icon: Icons.fact_check_rounded, color: c.warning, text: t('${run.openItems} بانتظار مراجعتك', '${run.openItems} waiting for your review'), action: TextButton(onPressed: () => openOmrReview(context, run.id), child: Text(t('مراجعة', 'Review')))),
              ],
            ]),
          ),
        ),
      ]);
    }
    return BasePage(appBar: ScreenAppBar(title: t('تصحيح الأوراق', 'Correct the sheets')), child: body);
  }
}

// ── the key ──────────────────────────────────────────────────────────────────────────────────────────────────────

class BubbleKeyScreen extends StatefulWidget {
  const BubbleKeyScreen({super.key, required this.run, this.api, this.picker});
  final BubbleRun run;
  final BubbleApi? api;
  final OwnSheetPicker? picker;

  @override
  State<BubbleKeyScreen> createState() => _BubbleKeyScreenState();
}

class _BubbleKeyScreenState extends State<BubbleKeyScreen> {
  late final BubbleApi _api = widget.api ?? BubbleApi();
  late final List<BubbleKeyQuestion> _questions = widget.run.questions;
  late final List<BubbleKeyForm> _forms = widget.run.forms.isEmpty ? [BubbleKeyForm(code: 'A')] : widget.run.forms;
  int _form = 0;
  final Set<int> _flagged = {};
  bool _busy = false;
  String? _error;

  BubbleKeyForm get _cur => _forms[_form];

  void _toggle(BubbleKeyQuestion q, String letter) {
    setState(() {
      final list = _cur.key[q.n] ?? [];
      final next = q.options.length <= 2 || q.multiAll
          ? (list.contains(letter) ? (list..remove(letter)) : (list..add(letter)))
          : (list.contains(letter) && list.length == 1 ? <String>[] : <String>[letter]);
      if (q.options.length > 2 && !q.multiAll && list.length > 1) {
        next
          ..clear()
          ..add(letter);
      }
      if (next.isEmpty) {
        _cur.key.remove(q.n);
      } else {
        _cur.key[q.n] = next;
      }
      _flagged.remove(q.n);
    });
  }

  Future<void> _fromSheet() async {
    final f = await (widget.picker ?? defaultOwnSheetPicker)(camera: false);
    if (f == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.keySheet(widget.run.id, f);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = bubbleErrorText(r);
      });
      return;
    }
    final p = BubbleKeyProposal.fromJson(r.map);
    setState(() {
      _busy = false;
      if (!p.ok) {
        _error = p.issues.isEmpty ? t('تعذّرت قراءة الورقة', "That sheet couldn't be read") : p.issues.first.text;
        return;
      }
      for (final it in p.items) {
        if (it.letters.isNotEmpty) _cur.key[it.n] = it.letters;
        if (!it.clear) _flagged.add(it.n);
      }
    });
    if (p.ok) {
      appToast(t('قُرئت ${p.clear} من ${p.items.length}. راجع المظلّل ثم احفظ.', 'Read ${p.clear} of ${p.items.length}. Check the highlighted ones, then save.'));
    }
  }

  Future<void> _details(BubbleKeyQuestion q) async {
    final points = TextEditingController(text: bubbleNumText(q.points));
    var all = q.multiAll;
    final result = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, setS) => AppSheetContent(title: t('السؤال ${q.n}', 'Question ${q.n}'), children: [
          Padding(padding: const EdgeInsets.only(bottom: AppSpace.sm), child: AppNumberField(controller: points, label: t('درجة السؤال', 'Marks for this question'), min: 0, step: 0.5, decimals: 2)),
          const SizedBox(height: AppSpace.sm),
          AppSwitchRow(title: t('يجب تظليل كل الإجابات المحددة', 'The student must shade every chosen answer'), value: all, onChanged: (v) => setS(() => all = v)),
          const SizedBox(height: AppSpace.md),
          AppPrimaryButton(label: t('تم', 'Done'), onPressed: () => Navigator.pop(ctx, true)),
          if (widget.run.pages > 0) ...[
            const SizedBox(height: AppSpace.xs),
            AppButton.ghost(
              label: q.voided ? t('استعادة السؤال', 'Restore the question') : t('إلغاء السؤال', 'Cancel the question'),
              icon: q.voided ? Icons.undo_rounded : Icons.block_rounded,
              expand: true,
              onPressed: () async {
                final ok = await appConfirm(ctx, message: q.voided ? t('استعادة هذا السؤال وإعادة حساب النتائج؟', 'Restore this question and recalculate?') : t('إلغاء هذا السؤال وإعادة حساب نتائج الجميع؟', 'Cancel this question and recalculate everyone?'), danger: !q.voided);
                if (!ok || !ctx.mounted) return;
                final reason = t('إلغاء من مفتاح الإجابة', 'cancelled from the answer key');
                final r = q.voided ? await _api.restoreQuestion(widget.run.id, q.questionId, reason) : await _api.voidQuestion(widget.run.id, q.questionId, reason);
                if (!mounted) return;
                if (r.ok) {
                  setState(() => q.voided = !q.voided);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  appToast(bubbleErrorText(r), error: true);
                }
              },
            ),
          ],
        ])));
    if (result == true) {
      final p = double.tryParse(points.text.trim().replaceAll(',', '.'));
      setState(() {
        if (p != null && p > 0) q.points = p;
        q.multiAll = all;
      });
    }
  }

  Future<void> _save() async {
    final missing = [for (final q in _questions) if (!q.voided && !(_cur.key[q.n]?.isNotEmpty ?? false)) q.n];
    if (missing.isNotEmpty) {
      setState(() {
        _flagged
          ..clear()
          ..addAll(missing);
        _error = t('أدخل إجابة لـ${missing.length} سؤال متبقٍ.', 'Enter the answer of the ${missing.length} remaining questions.');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.putKey(widget.run.id, forms: _forms, points: {for (final q in _questions) q.n: q.points}, allModes: {for (final q in _questions) q.n: q.multiAll});
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = bubbleErrorText(r);
      });
      return;
    }
    appToast(t('تم حفظ المفتاح', 'The key was saved'));
    Navigator.of(context).pop(BubbleRun.fromJson(r.map));
  }

  void _addForm() {
    final next = String.fromCharCode('A'.codeUnitAt(0) + _forms.length);
    setState(() {
      _forms.add(BubbleKeyForm(code: next));
      _form = _forms.length - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final set = _questions.where((q) => (_cur.key[q.n]?.isNotEmpty ?? false)).length;
    return BasePage(
      appBar: ScreenAppBar(title: t('مفتاح الإجابة', 'Answer key')),
      child: LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 1100 ? 3 : (box.maxWidth >= 720 ? 2 : 1);
        return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: AppWidth.wide.max),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text('$set / ${_questions.length} ${t('مدخلة', 'entered')}', style: AppType.section(context))),
                  ParentComponent(
                    featureKey: kBubbleKeySheetFeature,
                    child: AppButton.ghost(label: t('من ورقة مظلّلة', 'From a marked sheet'), icon: Icons.document_scanner_rounded, onPressed: _busy ? null : _fromSheet),
                  ),
                ]),
                const SizedBox(height: AppSpace.xs),
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: AppSpace.xxs, children: [
                      for (final (i, f) in _forms.indexed) AppChoiceChip(label: '${t('نموذج', 'Version')} ${f.code}', selected: i == _form, onTap: () => setState(() => _form = i)),
                      ActionChip(label: Text(t('+ نموذج', '+ Version'), style: AppType.meta(context)), onPressed: _forms.length < 4 ? _addForm : null),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpace.sm),
                BubbleKeyGrid(questions: _questions, form: _cur, flagged: _flagged, columns: cols, onToggle: _toggle, onDetails: _details),
                const SizedBox(height: AppSpace.md),
                if (_error != null) ...[AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!), const SizedBox(height: AppSpace.sm)],
                AppPrimaryButton(label: widget.run.pages > 0 ? t('حفظ وإعادة التصحيح', 'Save and regrade') : t('حفظ المفتاح', 'Save the key'), icon: Icons.task_alt_rounded, busy: _busy, onPressed: _busy ? null : _save),
              ]),
            ),
          ),
        ]);
      }),
    );
  }
}

// ── Data Lab ─────────────────────────────────────────────────────────────────────────────────────────────────────

Future<void> showBubbleDataLab(BuildContext context, {required BubbleRun run, BubbleApi? api}) async {
  final bapi = api ?? BubbleApi();
  await showAppSheet<void>(context, (ctx) => _DataLabSheet(run: run, api: bapi));
}

class _DataLabSheet extends StatefulWidget {
  const _DataLabSheet({required this.run, required this.api});
  final BubbleRun run;
  final BubbleApi api;

  @override
  State<_DataLabSheet> createState() => _DataLabSheetState();
}

class _DataLabSheetState extends State<_DataLabSheet> {
  List<LabColumn>? _cols;
  LabColumn? _sel;
  LabPreview? _preview;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.labColumns(widget.run.id);
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        final list = r.map['columns'] is List ? r.map['columns'] as List : const [];
        _cols = [for (final x in list) if (x is Map<String, dynamic>) LabColumn.fromJson(x)];
      } else {
        _error = bubbleErrorText(r);
      }
    });
  }

  Future<void> _previewFor(LabColumn col) async {
    setState(() {
      _sel = col;
      _preview = null;
      _busy = true;
      _error = null;
    });
    final r = await widget.api.labPreview(widget.run.id, col.key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) {
        _preview = LabPreview.fromJson(r.map);
      } else {
        _error = bubbleErrorText(r);
      }
    });
  }

  Future<void> _apply() async {
    final p = _preview;
    final col = _sel;
    if (p == null || col == null) return;
    if (p.overwrites > 0) {
      final ok = await appConfirm(context, message: t('ستُستبدل ${p.overwrites} درجات موجودة في «${col.label}». متابعة؟', '${p.overwrites} existing marks in "${col.label}" will be replaced. Continue?'), danger: true, confirmLabel: t('استبدال', 'Replace'));
      if (!ok || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await widget.api.labApply(widget.run.id, col.key, p.expect, confirmOverwrite: p.overwrites > 0);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      setState(() => _error = bubbleErrorText(r));
      return;
    }
    final written = r.map['written'] as int? ?? 0;
    final changed = (r.map['changed_since'] is List ? r.map['changed_since'] as List : const []).length;
    appToast(changed == 0 ? t('كُتبت $written درجة', '$written marks written') : t('كُتبت $written، وتغيّرت $changed منذ المعاينة (لم تُكتب)', '$written written; $changed changed since the preview (left alone)'));
    Navigator.of(context).pop();
  }

  Future<void> _showSheet(LabRow row) async {
    final id = row.pageId;
    if (id == null) return;
    final scan = OmrScanApi();
    final r = await scan.page(widget.run.id, id);
    if (!mounted || !r.ok) return;
    final url = asMap(r.map)['image_url'] as String?;
    final Uint8List? bytes = url == null ? null : await scan.image(url);
    if (!mounted || bytes == null) return;
    await showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.memory(bytes))));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cols = _cols;
    final p = _preview;
    return AppSheetContent(title: t('كتابة في Data Lab', 'Write to Data Lab'), children: [
      if (cols == null) const AppListSkeleton(items: 3, withAvatar: false) else if (cols.isEmpty) AppEmpty(icon: Icons.table_chart_rounded, title: t('لا توجد أعمدة درجات في هذا المقرر', 'This course has no grade columns')),
      if (cols != null && cols.isNotEmpty) ...[
        Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
          for (final col in cols) AppChoiceChip(label: col.label, selected: _sel?.key == col.key, onTap: col.locked ? () {} : () => _previewFor(col)),
        ]),
        const SizedBox(height: AppSpace.sm),
      ],
      if (_busy && p == null) const AppListSkeleton(items: 2, withAvatar: false),
      if (p != null) ...[
        BubbleLabPreviewView(preview: p, onSheet: _showSheet),
        const SizedBox(height: AppSpace.sm),
      ],
      if (_error != null) AppBanner(icon: Icons.error_outline_rounded, color: c.danger, text: _error!),
      if (p != null && p.changes > 0) ...[
        const SizedBox(height: AppSpace.sm),
        AppPrimaryButton(label: t('تأكيد الكتابة', 'Confirm and write'), icon: Icons.save_rounded, busy: _busy, onPressed: _busy ? null : _apply),
      ],
    ]);
  }
}
