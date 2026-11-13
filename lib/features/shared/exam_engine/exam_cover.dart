// Exam covers (D-730 - D-732): the designed cover (D-196), the teacher's own uploaded cover (an image, or a chosen page of a
// PDF), or none, for the question paper and, separately, for the answer side (the booklet here; the NB2 / bubble sheets
// the server prints, which carry an uploaded cover only, D-731). The choice is the paper design's `cover`
// (exam_paper_design_api.dart). Every cover becomes ONE LayoutDocument page the existing writers already draw (PDF and
// Word, exam_paper_bands.dart): an uploaded cover is a page whose background is the picture, with the optional
// details box and the cover code; so print, the per-student packs and email all carry it with no writer of their own.
// The cover is never part of the paper's page count, numbering or QR payloads (exam_paper_pdf.dart / _docx.dart).
//
// The cover code (`NBC:<exam>.<sig>`, from GET /paper-design) is a small QR in the bottom corner of every cover page of
// a paper exam: the scanner sets those pages aside instead of failing to find a sheet on them (D-732).
//
// Pure (models in, LayoutDocuments / text out): tested in test/org/exam_cover_test.dart.
library;

import 'dart:typed_data';

import '../../../design/export_layout/layout_api.dart';
import '../../../design/export_layout/layout_model.dart';
import '../../admin/admin_common.dart' show t;
import 'exam_paper.dart' show ExamCover;
import 'exam_paper_bands.dart' show paperCoverDesign;
import 'exam_paper_design_api.dart';

/// The upload limits (the layout asset store's, D-730): an image up to 2 MB, a PDF up to 10 MB.
const kCoverImageBytes = 2 * 1024 * 1024, kCoverPdfBytes = 10 * 1024 * 1024;
const kCoverExtensions = ['png', 'jpg', 'jpeg', 'pdf'];

/// The cover code's side on the page (mm).
const kCoverQrMm = 16.0;

/// Why a picked file cannot be a cover, before any upload; null = fine.
String? coverFileProblem(String name, int bytes) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (!kCoverExtensions.contains(ext)) return t('الغلاف صورة PNG أو JPG أو ملف PDF', 'A cover is a PNG or JPG picture, or a PDF');
  if (bytes <= 0) return t('الملف فارغ', 'The file is empty');
  final pdf = ext == 'pdf';
  if (bytes > (pdf ? kCoverPdfBytes : kCoverImageBytes)) {
    return pdf ? t('ملف PDF أكبر من 10 ميجابايت', 'The PDF is larger than 10 MB') : t('الصورة أكبر من 2 ميجابايت', 'The picture is larger than 2 MB');
  }
  return null;
}

/// A server refusal of an upload in words.
String coverUploadErrorText(String? code, {String? message, int? pages}) => switch (code) {
      'upload_too_big' => t('الملف أكبر من المسموح (صورة 2 ميجابايت، PDF 10 ميجابايت)', 'The file is too large (picture 2 MB, PDF 10 MB)'),
      'asset_type_invalid' => t('الملف تالف أو ليس صورة PNG / JPG أو PDF', 'The file is damaged, or not a PNG / JPG picture or a PDF'),
      'pdf_page_out_of_range' => pages == null ? t('هذه الصفحة غير موجودة في الملف', 'The PDF has no such page') : t('الملف فيه $pages صفحة فقط', 'The PDF has $pages pages only'),
      'asset_quota' => t('بلغت حد الصور المرفوعة. الصور غير المستخدمة تُحذف بعد 30 يومًا', 'You reached the uploaded pictures limit. Unused pictures expire after 30 days'),
      _ => (message == null || message.isEmpty) ? t('تعذّر رفع الغلاف', 'Could not upload the cover') : message,
    };

/// The outcome of [uploadCover]: the stored picture, or the reason in words.
class CoverUploadResult {
  const CoverUploadResult.ok(CoverUpload this.upload) : error = null;
  const CoverUploadResult.fail(String this.error) : upload = null;
  final CoverUpload? upload;
  final String? error;
}

/// Stores [bytes] as the cover picture ([page] of a PDF, 1-based). The bytes of an image are kept on this device too, so
/// the preview and the paper draw it at once.
Future<CoverUploadResult> uploadCover(LayoutApi api, Uint8List bytes, String name, {int page = 1}) async {
  final bad = coverFileProblem(name, bytes.length);
  if (bad != null) return CoverUploadResult.fail(bad);
  final r = await api.uploadAssetInfo(bytes, name, page: page);
  if (!r.ok || r.data == null || r.data!.id.isEmpty) {
    return CoverUploadResult.fail(coverUploadErrorText(r.code, message: r.error));
  }
  final x = r.data!;
  return CoverUploadResult.ok(CoverUpload(
      assetId: x.id, page: x.fromPdf ? x.page : 1, pages: x.fromPdf ? x.pages : 1, width: x.width, height: x.height, name: name));
}

// ── the cover as a page the writers draw ──────────────────────────────────────────────────────────────────────────

/// An uploaded cover as a page design: the picture fills the page (kept whole), the details box at [stamp]'s place when
/// it is on (the name, then the copy's printed identifiers), the cover code in the bottom corner when given.
LayoutDocument uploadedCoverDesign(String assetId, {required bool rtl, CoverStamp stamp = const CoverStamp(), String code = ''}) {
  final lang = rtl ? 'ar' : 'en';
  final page = LayoutPage(rtl: rtl, margins: LayoutMargins(top: 10, right: 10, bottom: 10, left: 10), backgroundImage: assetId, backgroundFit: 'contain');
  final design = LayoutDesign(page: page, mode: 'page');
  if (stamp.on) design.row.elements.addAll(coverStampElements(stamp.place, rtl: rtl, contentWidth: page.contentWidth, contentHeight: page.contentHeight));
  final doc = LayoutDocument(purpose: 'exam_cover', languages: [lang], designs: {lang: design});
  return code.isEmpty ? doc : withCoverCode(doc, code);
}

/// The details box (`{{student_name}}`, `{{identifiers}}`): white, ruled, 120 mm wide, centred at the top, the middle
/// or the bottom of the page (above the cover code).
List<LayoutElement> coverStampElements(CoverPlace place, {required bool rtl, required double contentWidth, required double contentHeight}) {
  const w = 120.0, h = 24.0;
  final x = (contentWidth - w) / 2;
  final y = switch (place) {
    CoverPlace.top => 6.0,
    CoverPlace.middle => (contentHeight - h) / 2,
    CoverPlace.bottom => contentHeight - h - kCoverQrMm - 6,
  };
  final name = rtl ? 'الاسم' : 'Name';
  return [
    LayoutElement(
        id: 'cover.stamp.box',
        kind: 'rect',
        x: x,
        y: y,
        w: w,
        h: h,
        style: LayoutStyle(bg: '#FFFFFF', radius: 2.5, border: LayoutBorder(width: .4, color: '#4B5563'))),
    LayoutElement(
        id: 'cover.stamp.name',
        kind: 'text',
        x: x + 4,
        y: y + 2,
        w: w - 8,
        h: 10,
        value: '$name: {{student_name}}',
        style: LayoutStyle(size: 13, weight: 700, color: '#111827', align: 'start', maxLines: 1, shrink: true)),
    LayoutElement(
        id: 'cover.stamp.ids',
        kind: 'text',
        x: x + 4,
        y: y + 12,
        w: w - 8,
        h: 10,
        value: '{{identifiers}}',
        style: LayoutStyle(size: 10.5, color: '#374151', align: 'start', maxLines: 1, shrink: true)),
  ];
}

/// [doc] (copied) with the cover code in the bottom corner of each language's page, on a white square so a busy picture
/// never hides it.
LayoutDocument withCoverCode(LayoutDocument doc, String code) {
  final out = LayoutDocument.fromJson(doc.toJson());
  for (final d in out.designs.values) {
    final y = d.page.contentHeight - kCoverQrMm;
    d.row.elements.removeWhere((e) => e.id == 'cover.code');
    d.row.elements.add(LayoutElement(id: 'cover.code', kind: 'qr', x: 0, y: y, w: kCoverQrMm, h: kCoverQrMm, value: code, style: LayoutStyle(bg: '#FFFFFF')));
  }
  return out;
}

/// The renderer's cover of one side of [spec] ([answer] false = the question paper), null when nothing prints. [code]
/// (a paper exam's cover code) adds the QR the scanner looks for.
ExamCover? examCoverOf(PaperCoverSpec? spec, {required bool answer, required bool rtl, String code = ''}) {
  if (spec == null) return null;
  final side = answer ? spec.answerSide : spec.paperSide;
  if (!side.on) return null;
  if (side.mode == CoverMode.uploaded) {
    return ExamCover(design: uploadedCoverDesign(side.upload!.assetId, rtl: rtl, stamp: side.stamp, code: code), university: spec.university, marksTable: false);
  }
  final design = spec.design ?? (code.isEmpty ? null : paperCoverDesign(rtl: rtl));
  return ExamCover(design: design == null || code.isEmpty ? design : withCoverCode(design, code), university: spec.university, marksTable: spec.marksTable);
}

/// The picture ids the covers of [spec] need resolved before printing (the designed cover's own pictures, each upload).
List<LayoutDocument?> coverAssetDocs(PaperCoverSpec? spec) => [
      spec?.design,
      for (final u in [spec?.upload, spec?.answer?.upload])
        if (u != null) LayoutDocument(purpose: 'exam_cover', languages: const ['ar'], designs: {'ar': LayoutDesign(mode: 'page', page: LayoutPage(backgroundImage: u.assetId))}),
    ];

/// One line for a cover choice ("Uploaded · page 2 of 5", "Designed", "None").
String coverSideText(CoverSide s, {bool same = false}) {
  if (same) return t('مثل ورقة الأسئلة', 'Same as the question paper');
  return switch (s.mode) {
    CoverMode.none => t('بدون غلاف', 'No cover'),
    CoverMode.designed => t('الغلاف المصمم', 'The designed cover'),
    CoverMode.uploaded => s.upload == null
        ? t('لم يُرفع ملف بعد', 'No file uploaded yet')
        : (s.upload!.pages > 1 ? t('ملف مرفوع · صفحة ${s.upload!.page} من ${s.upload!.pages}', 'Uploaded · page ${s.upload!.page} of ${s.upload!.pages}') : t('ملف مرفوع', 'Uploaded file')),
  };
}

/// The words of a place preset.
String coverPlaceText(CoverPlace p) => switch (p) {
      CoverPlace.top => t('أعلى', 'Top'),
      CoverPlace.middle => t('الوسط', 'Middle'),
      CoverPlace.bottom => t('أسفل', 'Bottom'),
    };

/// [spec] with one side changed, or null when nothing prints any more (saved as `cover: null`).
PaperCoverSpec? coverForSave(PaperCoverSpec spec) => spec.isNone && spec.design == null && spec.university.isEmpty ? null : spec;

/// The covers in one line for a summary row: "Questions: uploaded file · Answers: same as the question paper".
String coverSummaryText(PaperCoverSpec? spec, {bool answerSide = true}) {
  final s = spec ?? const PaperCoverSpec(mode: CoverMode.none);
  final paper = '${t('الأسئلة', 'Questions')}: ${coverSideText(s.paperSide)}';
  if (!answerSide) return paper;
  final same = s.answer?.same ?? false;
  return '$paper · ${t('الإجابة', 'Answers')}: ${coverSideText(s.answerSide, same: same)}';
}
