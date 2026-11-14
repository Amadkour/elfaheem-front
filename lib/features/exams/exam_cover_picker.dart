// The cover picker (D-730 - D-732): ONE card per document — the question paper, then the answer side (booklet and
// answer sheets) — each choosing No cover · Designed · Upload, with a page-shaped thumbnail, Replace / Remove, the PDF
// page to use, and the per-student details box (off by default; top / middle / bottom). "Same cover for both" copies
// the question paper's choice to the answer side in one tap.
//
// `ExamCoverPickerBody` takes plain values (the layout harness and the goldens pump it); `ExamCoverEditor` owns the calls
// (load, upload, save with the 409 "Reload / Keep mine") and is what the wizard's paper-design step, the print sheet and
// the prepare page's print card show. Pure parts: exam_cover.dart.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/design/engine/design_engine.dart' show DesignPurpose;
import 'package:flutter_education_app/design/export_layout/layout_api.dart' show LayoutApi;
import 'package:flutter_education_app/design/export_layout/layout_element_view.dart' show LayoutAssets;
import 'package:flutter_education_app/design/export_layout/layout_model.dart' show LayoutDocument;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/exam_cover.dart';
import 'package:flutter_education_app/features/exams/exam_paper_design_api.dart';
import 'package:flutter_education_app/features/exams/exam_paper_designer.dart' show openPaperDesigner, paperDocFrom, paperStartChoices, resolvePaperAssets, showPaperConflictDialog, PaperConflictChoice;

/// What the picker is busy with: 'paper' / 'answer' (an upload on that side), 'design' (the designer is open), 'save'.
typedef CoverBusy = String?;

// ═══════════════════════════════════════ plain-value body ════════════════════════════════════════════════════════

class ExamCoverPickerBody extends StatelessWidget {
  const ExamCoverPickerBody({
    super.key,
    required this.spec,
    this.pictures = const {},
    this.answerSide = true,
    this.busy,
    this.error,
    this.university,
    this.onMode,
    this.onUpload,
    this.onRemove,
    this.onPage,
    this.onStamp,
    this.onSame,
    this.onDesign,
    this.onMarksTable,
  });

  final PaperCoverSpec spec;

  /// The bytes of the uploaded pictures, by asset id (missing = a placeholder thumbnail).
  final Map<String, Uint8List> pictures;

  /// Show the answer side (a paper exam: a booklet or answer sheets can be printed).
  final bool answerSide;
  final CoverBusy busy;

  /// The last refusal (an upload, a save) in words.
  final String? error;

  /// The designed cover's university line.
  final TextEditingController? university;
  final void Function(bool answer, CoverMode mode)? onMode;
  final void Function(bool answer)? onUpload, onRemove;
  final void Function(bool answer, int page)? onPage;
  final void Function(bool answer, CoverStamp stamp)? onStamp;
  final ValueChanged<bool>? onSame;
  final VoidCallback? onDesign;
  final ValueChanged<bool>? onMarksTable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final same = spec.answer?.same ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _CoverSideCard(
        key: const ValueKey('cover.paper'),
        answer: false,
        title: t('غلاف ورقة الأسئلة', 'Question paper cover'),
        side: spec.paperSide,
        modes: const [CoverMode.none, CoverMode.designed, CoverMode.uploaded],
        pictures: pictures,
        busy: busy,
        university: university,
        marksTable: spec.marksTable,
        onMode: onMode,
        onUpload: onUpload,
        onRemove: onRemove,
        onPage: onPage,
        onStamp: onStamp,
        onDesign: onDesign,
        onMarksTable: onMarksTable,
      ),
      if (answerSide) ...[
        const SizedBox(height: AppSpace.sm),
        AppCard(
          key: const ValueKey('cover.answer'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('غلاف ورقة الإجابة', 'Answer paper cover'), style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
            const SizedBox(height: AppSpace.xxs),
            Text(t('يُطبع قبل كراسة الإجابة وأوراق الإجابة وورقة التظليل', 'Printed before the answer booklet, the answer sheets and the bubble sheet'),
                style: AppType.meta(context)),
            AppSwitchTile(
              key: const ValueKey('cover.same'),
              title: t('نفس غلاف ورقة الأسئلة', 'Same cover as the question paper'),
              value: same,
              dense: true,
              onChanged: (v) => onSame?.call(v),
            ),
            if (same)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: Text(coverSideText(spec.paperSide), key: const ValueKey('cover.answer.same_text'), style: AppType.label(context).copyWith(color: c.textMedium)),
              )
            else
              _CoverSideBody(
                answer: true,
                side: spec.answerSide,
                modes: const [CoverMode.none, CoverMode.uploaded],
                pictures: pictures,
                busy: busy,
                onMode: onMode,
                onUpload: onUpload,
                onRemove: onRemove,
                onPage: onPage,
                onStamp: onStamp,
              ),
            if (spec.answerSide.mode == CoverMode.designed)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: AppBanner(
                    icon: Icons.info_outline_rounded,
                    color: c.primary,
                    text: t('الغلاف المصمم يُطبع قبل كراسة الإجابة. أوراق الإجابة وورقة التظليل تأخذ غلافًا مرفوعًا فقط.',
                        'The designed cover prints before the answer booklet. The answer sheets and the bubble sheet take an uploaded cover only.')),
              ),
          ]),
        ),
      ],
      if (error != null) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(key: const ValueKey('cover.error'), icon: Icons.error_outline_rounded, color: c.danger, text: error!),
      ],
      const SizedBox(height: AppSpace.xs),
      Text(t('ترقيم الصفحات يبدأ بعد الغلاف، والماسح يتخطى صفحات الغلاف.', 'Page numbers start after the cover, and the scanner skips cover pages.'),
          key: const ValueKey('cover.note'), style: AppType.meta(context)),
    ]);
  }
}

class _CoverSideCard extends StatelessWidget {
  const _CoverSideCard({
    super.key,
    required this.answer,
    required this.title,
    required this.side,
    required this.modes,
    required this.pictures,
    this.busy,
    this.university,
    this.marksTable = true,
    this.onMode,
    this.onUpload,
    this.onRemove,
    this.onPage,
    this.onStamp,
    this.onDesign,
    this.onMarksTable,
  });
  final bool answer;
  final String title;
  final CoverSide side;
  final List<CoverMode> modes;
  final Map<String, Uint8List> pictures;
  final CoverBusy busy;
  final TextEditingController? university;
  final bool marksTable;
  final void Function(bool answer, CoverMode mode)? onMode;
  final void Function(bool answer)? onUpload, onRemove;
  final void Function(bool answer, int page)? onPage;
  final void Function(bool answer, CoverStamp stamp)? onStamp;
  final VoidCallback? onDesign;
  final ValueChanged<bool>? onMarksTable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        _CoverSideBody(
          answer: answer,
          side: side,
          modes: modes,
          pictures: pictures,
          busy: busy,
          university: university,
          marksTable: marksTable,
          onMode: onMode,
          onUpload: onUpload,
          onRemove: onRemove,
          onPage: onPage,
          onStamp: onStamp,
          onDesign: onDesign,
          onMarksTable: onMarksTable,
        ),
      ]),
    );
  }
}

String _modeLabel(CoverMode m) => switch (m) {
      CoverMode.none => t('بدون غلاف', 'No cover'),
      CoverMode.designed => t('مصمم', 'Designed'),
      CoverMode.uploaded => t('رفع ملف', 'Upload'),
    };

IconData _modeIcon(CoverMode m) => switch (m) {
      CoverMode.none => Icons.block_rounded,
      CoverMode.designed => Icons.brush_outlined,
      CoverMode.uploaded => Icons.upload_file_rounded,
    };

class _CoverSideBody extends StatelessWidget {
  const _CoverSideBody({
    required this.answer,
    required this.side,
    required this.modes,
    required this.pictures,
    this.busy,
    this.university,
    this.marksTable = true,
    this.onMode,
    this.onUpload,
    this.onRemove,
    this.onPage,
    this.onStamp,
    this.onDesign,
    this.onMarksTable,
  });
  final bool answer;
  final CoverSide side;
  final List<CoverMode> modes;
  final Map<String, Uint8List> pictures;
  final CoverBusy busy;
  final TextEditingController? university;
  final bool marksTable;
  final void Function(bool answer, CoverMode mode)? onMode;
  final void Function(bool answer)? onUpload, onRemove;
  final void Function(bool answer, int page)? onPage;
  final void Function(bool answer, CoverStamp stamp)? onStamp;
  final VoidCallback? onDesign;
  final ValueChanged<bool>? onMarksTable;

  String get _k => answer ? 'answer' : 'paper';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = busy != null;
    final up = side.upload;
    final uploading = busy == _k;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in modes)
          AppChoiceChip(
            key: ValueKey('cover.$_k.mode.${m.name}'),
            icon: _modeIcon(m),
            label: _modeLabel(m),
            selected: side.mode == m,
            onTap: () {
              if (!off) onMode?.call(answer, m);
            },
          ),
      ]),
      if (side.mode != CoverMode.none) const SizedBox(height: AppSpace.sm),
      if (side.mode == CoverMode.designed)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CoverThumb(designed: true),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('العنوان والمقرر واسم الطالب وجدول الدرجات', 'The title, the course, the student\'s name and the marks grid'), style: AppType.meta(context)),
              if (university != null) ...[
                const SizedBox(height: AppSpace.xs),
                AppField(key: ValueKey('cover.$_k.university'), controller: university!, label: t('الجامعة / الجهة', 'University / body')),
              ],
              AppSwitchTile(
                  key: ValueKey('cover.$_k.marks'),
                  title: t('جدول درجات الأسئلة', 'Marks grid'),
                  value: marksTable,
                  dense: true,
                  onChanged: (v) {
                    if (!off) onMarksTable?.call(v);
                  }),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton.secondary(
                  key: ValueKey('cover.$_k.design'),
                  label: t('عدّل الغلاف', 'Edit the cover'),
                  icon: Icons.brush_outlined,
                  size: AppButtonSize.sm,
                  busy: busy == 'design',
                  onPressed: off || onDesign == null ? null : onDesign,
                ),
              ),
            ]),
          ),
        ]),
      if (side.mode == CoverMode.uploaded && up == null)
        _UploadArea(key: ValueKey('cover.$_k.drop'), busy: uploading, onTap: off ? null : () => onUpload?.call(answer)),
      if (side.mode == CoverMode.uploaded && up != null)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverThumb(key: ValueKey('cover.$_k.thumb'), picture: pictures[up.assetId], stamp: side.stamp.on ? side.stamp.place : null, busy: uploading),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(up.name.isEmpty ? t('ملف الغلاف', 'Cover file') : up.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
              if (up.pages > 1) ...[
                const SizedBox(height: AppSpace.xxs),
                Row(children: [
                  AppIconButton(
                    key: ValueKey('cover.$_k.page.prev'),
                    icon: Icons.chevron_left_rounded,
                    tooltip: t('الصفحة السابقة', 'Previous page'),
                    onPressed: off || up.page <= 1 ? null : () => onPage?.call(answer, up.page - 1),
                  ),
                  Flexible(
                    child: Text(t('صفحة ${up.page} من ${up.pages}', 'Page ${up.page} of ${up.pages}'),
                        key: ValueKey('cover.$_k.page'), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context)),
                  ),
                  AppIconButton(
                    key: ValueKey('cover.$_k.page.next'),
                    icon: Icons.chevron_right_rounded,
                    tooltip: t('الصفحة التالية', 'Next page'),
                    onPressed: off || up.page >= up.pages ? null : () => onPage?.call(answer, up.page + 1),
                  ),
                ]),
              ],
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                AppButton.secondary(
                    key: ValueKey('cover.$_k.replace'),
                    label: t('استبدال', 'Replace'),
                    icon: Icons.swap_horiz_rounded,
                    size: AppButtonSize.sm,
                    onPressed: off ? null : () => onUpload?.call(answer)),
                AppButton.ghost(
                    key: ValueKey('cover.$_k.remove'),
                    label: t('إزالة', 'Remove'),
                    icon: Icons.delete_outline_rounded,
                    size: AppButtonSize.sm,
                    onPressed: off ? null : () => onRemove?.call(answer)),
              ]),
              AppSwitchTile(
                key: ValueKey('cover.$_k.stamp'),
                title: t('اطبع بيانات الطالب على الغلاف', 'Print the student\'s details on the cover'),
                subtitle: t('الاسم والبيانات المختارة لكل نسخة', 'The name and the chosen details of each copy'),
                value: side.stamp.on,
                dense: true,
                onChanged: (v) {
                  if (!off) onStamp?.call(answer, side.stamp.copyWith(on: v));
                },
              ),
              if (side.stamp.on)
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                  for (final p in CoverPlace.values)
                    AppChoiceChip(
                      key: ValueKey('cover.$_k.place.${p.name}'),
                      label: coverPlaceText(p),
                      selected: side.stamp.place == p,
                      onTap: () {
                        if (!off) onStamp?.call(answer, side.stamp.copyWith(place: p));
                      },
                    ),
                ]),
            ]),
          ),
        ]),
    ]);
  }
}

class _UploadArea extends StatelessWidget {
  const _UploadArea({super.key, required this.onTap, this.busy = false});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.primaryWash,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: c.primary.withValues(alpha: .45), width: AppBorder.hairline)),
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: busy ? null : onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min * 2),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              busy
                  ? SizedBox(width: AppIconSize.lg, height: AppIconSize.lg, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                  : Icon(Icons.upload_file_rounded, color: c.primary, size: AppIconSize.lg),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(busy ? t('جارٍ الرفع ...', 'Uploading ...') : t('ارفع صورة أو PDF', 'Upload a picture or a PDF'),
                      style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w700)),
                  Text(t('PNG أو JPG حتى 2 ميجابايت · PDF حتى 10 ميجابايت', 'PNG or JPG up to 2 MB · PDF up to 10 MB'), style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A page-shaped preview (A4 proportions): the uploaded picture, or a drawn sketch of the designed cover; the details box
/// drawn where it will print.
class CoverThumb extends StatelessWidget {
  const CoverThumb({super.key, this.picture, this.designed = false, this.stamp, this.busy = false, this.width = 88});
  final Uint8List? picture;
  final bool designed, busy;
  final CoverPlace? stamp;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = width * 297 / 210;
    Widget sketch() => Padding(
          padding: EdgeInsets.all(width * .12),
          child: Column(children: [
            for (final (w, top) in [(.7, .0), (.5, .04), (.85, .12), (.6, .03)])
              Padding(
                padding: EdgeInsets.only(top: h * top),
                child: FractionallySizedBox(widthFactor: w, child: Container(height: h * .025, color: c.divider)),
              ),
            const Spacer(),
            Container(height: h * .22, decoration: BoxDecoration(border: Border.all(color: c.divider))),
          ]),
        );
    return Semantics(
      label: t('معاينة الغلاف', 'Cover preview'),
      image: true,
      child: Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
            // the paper itself: always white, like the printed page
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            border: Border.all(color: c.divider),
            boxShadow: AppShadow.card(context)),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (picture != null)
            Image.memory(picture!, fit: BoxFit.contain, gaplessPlayback: true)
          else if (designed)
            sketch()
          else
            Center(child: Icon(Icons.image_outlined, color: c.textLight, size: AppIconSize.lg)),
          if (stamp != null)
            Align(
              alignment: switch (stamp!) { CoverPlace.top => const Alignment(0, -.82), CoverPlace.middle => Alignment.center, CoverPlace.bottom => const Alignment(0, .7) },
              child: Container(
                key: const ValueKey('cover.thumb.stamp'),
                width: width * .58,
                height: h * .085,
                decoration: BoxDecoration(color: const Color(0xFFFFFFFF), borderRadius: BorderRadius.circular(2), border: Border.all(color: c.primary, width: 1.2)),
              ),
            ),
          if (busy) ColoredBox(color: c.cardBg.withValues(alpha: .6), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════ the editor (owns the calls) ═════════════════════════════════════════════

/// Loads the exam's cover choice, uploads files, saves each change. [onSaved] hears every stored state (the print sheet
/// keeps its own design version in step with it).
class ExamCoverEditor extends StatefulWidget {
  const ExamCoverEditor({
    super.key,
    required this.examId,
    this.answerSide = true,
    this.initial,
    this.currentDocument,
    this.currentVersion,
    this.onSaved,
    this.designApi,
    this.layoutApi,
    this.title = '',
    this.sample = const {},
    this.orgId,
  });
  final int examId;
  final bool answerSide;

  /// The state already loaded by the host (no second GET).
  final PaperDesignState? initial;

  /// A host that also saves the paper's design (the print sheet): its document and version are the current ones.
  final LayoutDocument? Function()? currentDocument;
  final int Function()? currentVersion;
  final ValueChanged<PaperDesignState>? onSaved;
  final ExamPaperDesignApi? designApi;
  final LayoutApi? layoutApi;

  /// For "Edit the cover" (the design engine): the exam's title, its sample values and organization.
  final String title;
  final Map<String, Object?> sample;
  final int? orgId;

  @override
  State<ExamCoverEditor> createState() => _ExamCoverEditorState();
}

class _ExamCoverEditorState extends State<ExamCoverEditor> {
  late final ExamPaperDesignApi _api = widget.designApi ?? ExamPaperDesignApi();
  late final LayoutApi _lApi = widget.layoutApi ?? LayoutApi.instance;
  PaperDesignState? _state;
  PaperCoverSpec _spec = const PaperCoverSpec(mode: CoverMode.none);
  final Map<String, Uint8List> _pictures = {};

  /// The picked PDF of each side, kept for this session so another page needs no new pick.
  final Map<bool, (Uint8List, String)> _pdf = {};
  CoverBusy _busy;
  String? _error;
  bool _loading = true;
  late final _university = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = widget.initial;
    if (s != null) {
      _adopt(s);
      _loading = false;
      _resolve();
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _university.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _api.load(widget.examId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (s != null) _adopt(s);
    });
    _resolve();
  }

  void _adopt(PaperDesignState s) {
    _state = s;
    _spec = s.cover ?? const PaperCoverSpec(mode: CoverMode.none);
    _university.text = _spec.university;
  }

  /// The uploaded pictures' bytes for the thumbnails.
  Future<void> _resolve() async {
    final raw = await resolvePaperAssets(coverAssetDocs(_spec), api: _lApi);
    if (!mounted || raw.isEmpty) return;
    setState(() => _pictures.addAll(raw));
  }

  Future<void> _save(PaperCoverSpec next) async {
    final before = _spec;
    setState(() {
      _spec = next;
      _error = null;
    });
    final cur = _state;
    final doc = widget.currentDocument != null ? widget.currentDocument!() : cur?.document;
    final version = widget.currentVersion?.call() ?? cur?.version ?? 0;
    var r = await _api.save(widget.examId, document: doc, cover: coverForSave(next.copyWith(university: _university.text.trim())), version: version);
    if (!mounted) return;
    if (r.conflict) {
      final pick = await showPaperConflictDialog(context);
      if (!mounted) return;
      final fresh = await _api.load(widget.examId);
      if (!mounted) return;
      if (fresh == null || pick == null || pick == PaperConflictChoice.reload) {
        if (fresh != null) setState(() => _adopt(fresh));
        if (fresh != null) widget.onSaved?.call(fresh);
        return;
      }
      r = await _api.save(widget.examId, document: widget.currentDocument != null ? doc : fresh.document, cover: coverForSave(next), version: fresh.version);
      if (!mounted) return;
    }
    if (!r.ok) {
      setState(() {
        _spec = before;
        _error = r.error ?? t('تعذّر حفظ الغلاف', 'Could not save the cover');
      });
      return;
    }
    setState(() => _state = r.state);
    // the purge cannot read the engine's designs: keep the cover pictures alive (fire and forget)
    final ids = [for (final u in [next.upload, next.answer?.upload]) if (u != null) u.assetId];
    if (ids.isNotEmpty) _lApi.keepAssets(ids);
    widget.onSaved?.call(r.state!);
  }

  PaperCoverSpec _withSide(bool answer, {CoverMode? mode, CoverUpload? upload, bool clearUpload = false, CoverStamp? stamp}) {
    if (!answer) return _spec.copyWith(mode: mode, upload: upload, clearUpload: clearUpload, stamp: stamp);
    final a = _spec.answer ?? const AnswerCoverSpec();
    return _spec.copyWith(answer: a.copyWith(mode: mode, upload: upload, clearUpload: clearUpload, stamp: stamp));
  }

  Future<void> _mode(bool answer, CoverMode m) async {
    final side = answer ? _spec.answerSide : _spec.paperSide;
    await _save(_withSide(answer, mode: m));
    if (m == CoverMode.uploaded && side.upload == null && mounted) await _upload(answer);
  }

  Future<void> _upload(bool answer, {int page = 1, (Uint8List, String)? file}) async {
    var f = file;
    if (f == null) {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: kCoverExtensions);
      if (picked == null || !mounted) return;
      f = (await picked.readAsBytes(), picked.name);
    }
    final bad = coverFileProblem(f.$2, f.$1.length);
    if (bad != null) return setState(() => _error = bad);
    setState(() {
      _busy = answer ? 'answer' : 'paper';
      _error = null;
    });
    final r = await uploadCover(_lApi, f.$1, f.$2, page: page);
    if (!mounted) return;
    setState(() => _busy = null);
    final up = r.upload;
    if (up == null) return setState(() => _error = r.error);
    if (up.pages > 1) _pdf[answer] = f;
    if (!up.fromPdf) {
      _pictures[up.assetId] = f.$1;
      LayoutAssets.put(up.assetId, f.$1);
    }
    await _save(_withSide(answer, mode: CoverMode.uploaded, upload: up));
    if (up.fromPdf) await _resolve();
  }

  Future<void> _page(bool answer, int page) async {
    final f = _pdf[answer];
    if (f != null) return _upload(answer, page: page, file: f);
    // picked in another session: pick the same PDF again
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['pdf']);
    if (picked == null || !mounted) return;
    await _upload(answer, page: page, file: (await picked.readAsBytes(), picked.name));
  }

  Future<void> _remove(bool answer) => _save(_withSide(answer, mode: CoverMode.none, clearUpload: true, stamp: const CoverStamp()));

  Future<void> _same(bool v) {
    final a = _spec.answer ?? const AnswerCoverSpec();
    return _save(_spec.copyWith(answer: a.copyWith(same: v)));
  }

  Future<void> _design() async {
    setState(() => _busy = 'design');
    try {
      var doc = _spec.design;
      if (doc == null) {
        final r = await _lApi.starters(purpose: DesignPurpose.examCover);
        final cs = r.ok ? paperStartChoices(r.data!, const [], purpose: DesignPurpose.examCover) : const [];
        doc = cs.isEmpty ? null : paperDocFrom(cs.first.document, purpose: DesignPurpose.examCover);
      }
      if (!mounted) return;
      final LayoutDocument start = doc ?? LayoutDocument(purpose: DesignPurpose.examCover);
      start.purpose = DesignPurpose.examCover;
      final out = await openPaperDesigner(context,
          purpose: DesignPurpose.examCover, title: widget.title, initial: start, sample: {...widget.sample, 'university': _university.text.trim()}, orgId: widget.orgId);
      if (out == null || !mounted) return;
      await resolvePaperAssets([out], api: _lApi);
      setState(() => _busy = null);
      await _save(_spec.copyWith(design: out, mode: CoverMode.designed));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppListSkeleton(items: 2, withAvatar: false);
    return Focus(
      // the university line saves when the field is left
      onFocusChange: (has) {
        if (!has && _university.text.trim() != _spec.university && _spec.mode == CoverMode.designed) _save(_spec.copyWith(university: _university.text.trim()));
      },
      child: ExamCoverPickerBody(
        spec: _spec,
        pictures: _pictures,
        answerSide: widget.answerSide,
        busy: _busy,
        error: _error,
        university: _university,
        onMode: _mode,
        onUpload: (a) => _upload(a),
        onRemove: _remove,
        onPage: _page,
        onStamp: (a, s) => _save(_withSide(a, stamp: s)),
        onSame: _same,
        onDesign: _design,
        onMarksTable: (v) => _save(_spec.copyWith(marksTable: v)),
      ),
    );
  }
}

/// The cover picker in a sheet (the prepare page's print card). True when something was saved.
Future<bool> openExamCoverSheet(BuildContext context,
    {required int examId, bool answerSide = true, String title = '', Map<String, Object?> sample = const {}, int? orgId}) async {
  var saved = false;
  await showAppSheet<void>(
    context,
    (_) => AppSheetContent(
      icon: Icons.menu_book_outlined,
      title: t('صفحة الغلاف', 'Cover page'),
      subtitle: t('غلاف مصمم، أو ملفك أنت، أو بدون غلاف', 'A designed cover, your own file, or none'),
      children: [
        ExamCoverEditor(examId: examId, answerSide: answerSide, title: title, sample: sample, orgId: orgId, onSaved: (_) => saved = true),
      ],
    ),
  );
  return saved;
}
