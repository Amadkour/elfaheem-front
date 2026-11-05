// The paper designer's host side (D-196): the "Do you have a template?" block of the print sheet, the starter gallery,
// the paper placeholders handed to the design engine as fields, the local pieces around a design (a start document, a
// letterhead background, the picture bytes the renderers need) and the 409 "Reload / Keep mine" dialog.
//
// Presentational widgets here take plain values (they are what test/org/exam_paper_designer_test.dart pumps); the
// sheet (exam_paper_sheet.dart) owns the state and the calls. The renderers' side (ExamPaperDoc.design / cover /
// assets, examPaperXlsx) is FD1's: every call into it goes through the two functions marked FD1-ADAPTER below.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../design/engine/design_engine.dart';
import '../../../design/export_layout/layout_api.dart';
import '../../../design/export_layout/layout_element_view.dart' show LayoutAssets;
import '../../../design/export_layout/layout_model.dart';
import '../../admin/admin_common.dart' show t;
import 'exam_paper.dart';
import 'exam_paper_design_api.dart';
import 'exam_paper_xlsx.dart';
import 'exam_versions.dart';

// ── the renderers' side (exam_paper.dart / exam_paper_xlsx.dart) ─────────────────────────────────────────────────

/// The paper with the stored design applied: [design] the page design, [cover] the cover page (null = no cover),
/// [assets] the bytes of every picture id they use.
ExamPaperDoc paperWithDesign(ExamPaperDoc d, {LayoutDocument? design, PaperCoverSpec? cover, Map<String, Uint8List> assets = const {}}) {
  return d.copyWith(
      design: design,
      dropDesign: design == null,
      cover: cover == null ? null : ExamCover(design: cover.design, university: cover.university, marksTable: cover.marksTable),
      dropCover: cover == null,
      assets: assets);
}

/// The Excel file of the paper (questions, answer key per version, marks grid).
Uint8List paperXlsxBytes(ExamPaperDoc d, {required ExamVersions versions, List<String> roster = const []}) {
  // one paper per version (its question / option order and key), the exam's own order when there are none
  return examPaperXlsx(d, versions: [for (final v in versions.items) applyVersion(d, v)], roster: roster);
}

// ── fields ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// The paper's placeholders: what a design can print (`{{key}}` in a text, or a field bound to the key).
List<LayoutField> paperFields({bool cover = false}) => [
      const LayoutField(key: 'institution', labelAr: 'المؤسسة', labelEn: 'Institution'),
      if (cover) const LayoutField(key: 'university', labelAr: 'الجامعة', labelEn: 'University'),
      const LayoutField(key: 'course', labelAr: 'المقرر', labelEn: 'Course'),
      const LayoutField(key: 'title', labelAr: 'عنوان الامتحان', labelEn: 'Exam title'),
      const LayoutField(key: 'date', labelAr: 'التاريخ', labelEn: 'Date'),
      const LayoutField(key: 'duration', labelAr: 'المدة', labelEn: 'Duration'),
      const LayoutField(key: 'total', labelAr: 'الدرجة الكلية', labelEn: 'Total marks'),
      const LayoutField(key: 'version', labelAr: 'النموذج', labelEn: 'Version'),
      const LayoutField(key: 'student_name', labelAr: 'اسم الطالب', labelEn: 'Student name'),
      const LayoutField(key: 'seat', labelAr: 'رقم الجلوس', labelEn: 'Seat number'),
      const LayoutField(key: 'instructions', labelAr: 'التعليمات', labelEn: 'Instructions'),
      const LayoutField(key: 'page', labelAr: 'رقم الصفحة', labelEn: 'Page'),
      const LayoutField(key: 'pages', labelAr: 'عدد الصفحات', labelEn: 'Pages'),
    ];

/// The sample row the designer's preview prints.
Map<String, Object?> paperSampleRow({required String institution, required String course, required String title, required String date,
        required String duration, required String total, required String instructions, String university = ''}) =>
    {
      'institution': institution,
      'university': university,
      'course': course,
      'title': title,
      'date': date,
      'duration': duration,
      'total': total,
      'version': 'A',
      'student_name': t('اسم الطالب', 'Student name'),
      'seat': '1024',
      'instructions': instructions,
      'page': '1',
      'pages': '2',
    };

// ── documents ────────────────────────────────────────────────────────────────────────────────────────────────────

/// A copy of [source] (a starter or a saved template) as a design of [purpose] in the app's language.
LayoutDocument paperDocFrom(LayoutDocument source, {required String purpose, String? lang}) {
  final d = LayoutDocument.fromJson(source.toJson(withSource: false));
  final l = lang ?? AppConfig.lang;
  d.purpose = purpose;
  d.format = 'pdf';
  d.languages
    ..clear()
    ..add(d.designs.containsKey(l) ? l : (d.designs.keys.isEmpty ? l : d.designs.keys.first));
  return d;
}

/// An empty page-mode design with [assetId] as the page background (the letterhead path without a starter).
LayoutDocument blankPaperDoc({required String purpose, String? assetId, String? lang}) {
  final l = lang ?? AppConfig.lang;
  return LayoutDocument(purpose: purpose, languages: [l], designs: {
    l: LayoutDesign(mode: 'page', page: LayoutPage(rtl: l == 'ar', backgroundImage: assetId)),
  });
}

/// Sets the background picture on every design of [doc].
void setPaperBackground(LayoutDocument doc, String? assetId) {
  for (final d in doc.designs.values) {
    d.page.backgroundImage = assetId;
  }
}

// ── picture bytes ────────────────────────────────────────────────────────────────────────────────────────────────

/// Every picture id [doc] uses: the page background and the image / signature elements of its bands and row.
Set<String> paperAssetIds(LayoutDocument? doc) {
  final out = <String>{};
  if (doc == null) return out;
  void band(LayoutBand? b) {
    for (final e in b?.elements ?? const <LayoutElement>[]) {
      if ((e.kind == 'image' || e.kind == 'signature') && '${e.value ?? ''}'.isNotEmpty && !'${e.value}'.startsWith('http')) out.add('${e.value}');
    }
  }

  for (final d in doc.designs.values) {
    final bg = d.page.backgroundImage;
    if (bg != null && bg.isNotEmpty && !bg.startsWith('http')) out.add(bg);
    band(d.header);
    band(d.footer);
    band(d.beforeItems);
    band(d.afterItems);
    for (final e in d.row.elements) {
      if ((e.kind == 'image' || e.kind == 'signature') && '${e.value ?? ''}'.isNotEmpty && !'${e.value}'.startsWith('http')) out.add('${e.value}');
    }
  }
  return out;
}

const _kAssetPrefix = 'exam_paper.asset.';
const _maxCachedAsset = 1500000;

/// The bytes of every picture the designs use, for the renderers (`ExamPaperDoc.assets`): from the designer's own
/// memory, else the copy kept on this device (the server has no route that serves a stored picture). Pictures found
/// are kept on the device for the next session; ids nobody can supply are left out (the paper prints without them).
Future<Map<String, Uint8List>> resolvePaperAssets(Iterable<LayoutDocument?> docs, {LayoutApi? api}) async {
  final ids = <String>{for (final d in docs) ...paperAssetIds(d)};
  final out = <String, Uint8List>{};
  if (ids.isEmpty) return out;
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}
  for (final id in ids) {
    var bytes = LayoutAssets.of(id);
    var fresh = bytes != null;
    if (bytes == null) {
      try {
        final s = prefs?.getString('$_kAssetPrefix$id');
        if (s != null) bytes = base64Decode(s);
      } catch (_) {}
    }
    if (bytes == null) {
      // another device made the design (or the cache was cleared): the server keeps every placed image
      final r = await (api ?? LayoutApi.instance).assetBytes(id);
      if (r.ok && r.data != null && r.data!.isNotEmpty) {
        bytes = r.data;
        fresh = true;
      }
    }
    if (bytes == null) continue;
    out[id] = bytes;
    if (LayoutAssets.of(id) == null) LayoutAssets.put(id, bytes);
    if (fresh && bytes.length <= _maxCachedAsset) {
      try {
        await prefs?.setString('$_kAssetPrefix$id', base64Encode(bytes));
      } catch (_) {}
    }
  }
  return out;
}

/// Uploads a letterhead / cover picture for the design (PNG / JPEG ≤ 2 MB or a PDF ≤ 10 MB, whose first page the
/// server keeps). The asset id, or null after a notice. An image's bytes are kept so the canvas and the paper can
/// draw it at once.
Future<String?> uploadPaperBackground(LayoutApi api, Uint8List bytes, String name) async {
  final pdf = name.toLowerCase().endsWith('.pdf');
  if (bytes.length > (pdf ? 10 : 2) * 1024 * 1024) {
    appToast(pdf ? t('ملف PDF أكبر من 10 ميجابايت', 'The PDF is larger than 10 MB') : t('الصورة أكبر من 2 ميجابايت', 'The image is larger than 2 MB'), error: true);
    return null;
  }
  final r = await api.uploadAssetInfo(bytes, name);
  if (!r.ok || r.data!.id.isEmpty) {
    appToast(r.error ?? t('تعذّر رفع الملف', 'Could not upload the file'), error: true);
    return null;
  }
  if (!pdf) LayoutAssets.put(r.data!.id, bytes);
  return r.data!.id;
}

// ── opening the designer ─────────────────────────────────────────────────────────────────────────────────────────

/// Opens the engine on [initial] (purpose exam_paper | exam_cover). The saved document, or null when the person left
/// without saving.
Future<LayoutDocument?> openPaperDesigner(
  BuildContext context, {
  required String purpose,
  required String title,
  required LayoutDocument initial,
  required Map<String, Object?> sample,
  int? orgId,
}) {
  final cover = purpose == DesignPurpose.examCover;
  return DesignEngine.open(
    context,
    DesignEngineRequest(
      purpose: purpose,
      title: title,
      fields: paperFields(cover: cover),
      rows: [sample],
      initialDocument: initial,
      templatesPageKey: cover ? 'exam.paper.cover' : 'exam.paper',
      orgId: orgId,
    ),
  );
}

// ── the 409 dialog ───────────────────────────────────────────────────────────────────────────────────────────────

enum PaperConflictChoice { reload, keepMine }

/// Someone saved a newer design while this one was open: take theirs, or save this one over it.
Future<PaperConflictChoice?> showPaperConflictDialog(BuildContext context) => showDialog<PaperConflictChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('paper.conflict'),
        title: Text(t('تغيّر التصميم', 'The design changed')),
        content: Text(t('حفظ شخص آخر تصميمًا أحدث لهذا الامتحان. أعد تحميله، أو احتفظ بتصميمك واستبدل الأحدث.',
            'Someone saved a newer design for this exam. Reload it, or keep yours and replace the newer one.')),
        actions: [
          TextButton(key: const ValueKey('paper.conflict.reload'), onPressed: () => Navigator.of(ctx).pop(PaperConflictChoice.reload), child: Text(t('إعادة التحميل', 'Reload'))),
          FilledButton(key: const ValueKey('paper.conflict.keep'), onPressed: () => Navigator.of(ctx).pop(PaperConflictChoice.keepMine), child: Text(t('احتفظ بتصميمي', 'Keep mine'))),
        ],
      ),
    );

// ── the starter gallery ──────────────────────────────────────────────────────────────────────────────────────────

/// One thing the gallery offers: a server starter or one of the person's saved templates.
class PaperStartChoice {
  const PaperStartChoice({required this.id, required this.name, this.description = '', required this.document, this.mine = false, this.recommended = false});
  final String id, name, description;
  final LayoutDocument document;
  final bool mine, recommended;
}

/// The choices for a purpose: the starters (the classic one recommended, first) then the saved templates.
List<PaperStartChoice> paperStartChoices(List<LayoutStarter> starters, List<LayoutTemplate> mine, {String purpose = DesignPurpose.examPaper}) {
  final lang = AppConfig.lang;
  final out = <PaperStartChoice>[
    for (final s in starters)
      if (s.document != null && (s.purpose == purpose || s.key.startsWith(purpose)))
        PaperStartChoice(id: s.key, name: s.name(lang), description: s.description(lang), document: s.document!, recommended: s.key.endsWith('_classic')),
  ]..sort((a, b) => a.recommended == b.recommended ? 0 : (a.recommended ? -1 : 1));
  for (final m in mine) {
    if (m.document != null) out.add(PaperStartChoice(id: 'mine:${m.id}', name: m.name, document: m.document!, mine: true));
  }
  return out;
}

class PaperStartGallery extends StatelessWidget {
  const PaperStartGallery({super.key, required this.choices, required this.title, required this.onPick, this.loading = false});
  final List<PaperStartChoice> choices;
  final String title;
  final bool loading;
  final ValueChanged<PaperStartChoice> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final starters = [for (final x in choices) if (!x.mine) x], mine = [for (final x in choices) if (x.mine) x];
    Widget tile(PaperStartChoice x) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: Material(
            color: c.cardBg,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: x.recommended ? c.primary : c.divider)),
            child: InkWell(
              key: ValueKey('paper.start.${x.id}'),
              borderRadius: AppRadius.cardAll,
              onTap: () => onPick(x),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(children: [
                  Icon(x.mine ? Icons.bookmark_rounded : Icons.article_rounded, color: c.primary),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14, w: FontWeight.w700, c: c.textDark)),
                      if (x.recommended || x.description.isNotEmpty)
                        Text(x.recommended ? '${t('الموصى به', 'Recommended')}${x.description.isEmpty ? '' : ' · ${x.description}'}' : x.description,
                            maxLines: 3, overflow: TextOverflow.ellipsis, style: appText(12.5, c: c.textMedium)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
    return AppSheetContent(title: title, children: [
      if (loading) const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (choices.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
          child: Text(t('لا توجد تصاميم جاهزة على هذا الخادم بعد.', 'There are no ready designs on this server yet.'), style: appText(13, c: c.textMedium)),
        ),
      for (final x in starters) tile(x),
      if (mine.isNotEmpty) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xs), child: Text(t('قوالبي', 'My templates'), style: appText(13.5, w: FontWeight.w700, c: c.textDark))),
        for (final x in mine) tile(x),
      ],
    ]);
  }
}

// ── the choice block ─────────────────────────────────────────────────────────────────────────────────────────────

/// "Do you have a template?": three ways to dress the paper, then (once a design is chosen) its actions and the cover.
class ExamPaperDesignBlock extends StatelessWidget {
  const ExamPaperDesignBlock({
    super.key,
    required this.hasDesign,
    required this.wordSelected,
    required this.onProfessional,
    required this.onWord,
    required this.onLetterhead,
    required this.onDesign,
    required this.onSaveTemplate,
    required this.onUseBuiltIn,
    required this.coverOn,
    required this.onCover,
    required this.university,
    required this.marksTable,
    required this.onMarksTable,
    required this.hasCoverDesign,
    required this.onCoverUpload,
    required this.onCoverDesign,
    this.busy,
    this.wordName,
  });

  final bool hasDesign, wordSelected, coverOn, marksTable, hasCoverDesign;
  final String? wordName;

  /// 'design' | 'template' | 'cover' | 'letterhead' while something runs (disables the actions).
  final String? busy;
  final VoidCallback onProfessional, onWord, onLetterhead, onDesign, onSaveTemplate, onUseBuiltIn, onCoverUpload, onCoverDesign;
  final ValueChanged<bool> onCover, onMarksTable;
  final TextEditingController university;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final off = busy != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('هل لديك قالب؟', 'Do you have a template?'), style: appText(14, w: FontWeight.w700, c: c.textDark)),
      const SizedBox(height: AppSpace.xs),
      LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 560;
        final w = wide ? (box.maxWidth - 2 * AppSpace.xs) / 3 : box.maxWidth;
        Widget card(Key k, IconData icon, String title, String sub, bool selected, VoidCallback onTap) => SizedBox(
              width: w,
              child: _SourceCard(key: k, icon: icon, title: title, subtitle: sub, selected: selected, onTap: off ? null : onTap),
            );
        return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          card(const ValueKey('paper.source.professional'), Icons.auto_awesome_rounded, t('تصميم احترافي جاهز', 'Professional default'),
              t('اختر تصميمًا جاهزًا وعدّله', 'Pick a ready design and adjust it'), hasDesign && !wordSelected, onProfessional),
          card(const ValueKey('paper.source.word'), Icons.description_rounded, t('قالب Word الخاص بي', 'My Word template'),
              wordName ?? t('ارفع ملف .docx', 'Upload a .docx file'), wordSelected, onWord),
          card(const ValueKey('paper.source.letterhead'), Icons.wallpaper_rounded, t('ورقة رسمية (صورة أو PDF)', 'Letterhead (image or PDF)'),
              t('تصبح خلفية الصفحة', 'Becomes the page background'), false, onLetterhead),
        ]);
      }),
      if (hasDesign && !wordSelected) ...[
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            key: const ValueKey('paper.design'),
            onPressed: off ? null : onDesign,
            icon: busy == 'design' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.brush_rounded, size: 18),
            label: Text(t('صمّم الورقة', 'Design the paper')),
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          ),
          OutlinedButton.icon(
            key: const ValueKey('paper.save_template'),
            onPressed: off ? null : onSaveTemplate,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(t('حفظ كقالب لي', 'Save as my template')),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          ),
          TextButton(
            key: const ValueKey('paper.use_builtin'),
            onPressed: off ? null : onUseBuiltIn,
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
            child: Text(t('استخدم التصاميم المدمجة', 'Use the built-in designs')),
          ),
        ]),
      ],
      AppSwitchTile(
        key: const ValueKey('paper.cover.toggle'),
        title: t('صفحة غلاف', 'Cover page'),
        subtitle: t('غلاف قبل الأسئلة بجدول الدرجات', 'A cover before the questions, with the marks grid'),
        value: coverOn,
        dense: true,
        onChanged: off ? (_) {} : onCover,
      ),
      if (coverOn) ...[
        AppField(key: const ValueKey('paper.cover.university'), controller: university, label: t('الجامعة / الجهة', 'University / body')),
        AppSwitchTile(
            key: const ValueKey('paper.cover.marks'), title: t('جدول درجات الأسئلة', 'Marks grid'), value: marksTable, dense: true, onChanged: off ? (_) {} : onMarksTable),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          OutlinedButton.icon(
            key: const ValueKey('paper.cover.upload'),
            onPressed: off ? null : onCoverUpload,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text(t('رفع غلاف (صورة أو PDF)', 'Upload a cover (image or PDF)')),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('paper.cover.design'),
            onPressed: off ? null : onCoverDesign,
            icon: busy == 'cover' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.brush_rounded, size: 18),
            label: Text(hasCoverDesign ? t('عدّل الغلاف', 'Edit the cover') : t('صمّم الغلاف', 'Design the cover')),
            style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min)),
          ),
        ]),
      ],
      const SizedBox(height: AppSpace.xs),
    ]);
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({super.key, required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: selected ? c.primary.withValues(alpha: .08) : c.cardBg,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll, side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.5 : 1)),
      child: InkWell(
        borderRadius: AppRadius.cardAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Row(children: [
            Icon(icon, color: c.primary),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(13.5, w: FontWeight.w700, c: c.textDark)),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(12, c: c.textMedium)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle_rounded, size: 18, color: c.primary),
          ]),
        ),
      ),
    );
  }
}
