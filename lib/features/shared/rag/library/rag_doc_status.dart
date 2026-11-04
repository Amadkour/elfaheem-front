// What a document card says about its reading: progress, skipped pages, excluded parts, a readable failure, and the
// hint next to the upload button. Pure texts + small presentational widgets (layout-harness tested).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../../admin/admin_common.dart' show asInt, asMapList, asStr, t;

/// A server warning: `{code: "partially_scanned", pages: [3, 7], ar, en}`.
class RagWarning {
  const RagWarning({required this.code, this.pages = const [], this.ar = '', this.en = ''});
  final String code;
  final List<int> pages;
  final String ar, en;

  factory RagWarning.fromJson(Map<String, dynamic> j) =>
      RagWarning(code: asStr(j['code']), pages: _pages(j['pages']), ar: asStr(j['ar']), en: asStr(j['en']));

  /// The server's sentence in the app language; ours when an older text is missing.
  String get text {
    final s = AppConfig.lang == 'ar' ? ar : en;
    if (s.isNotEmpty) return s;
    return code == 'partially_scanned' ? t('تم تخطي بعض الصفحات (ممسوحة ضوئياً)', 'Some pages were skipped (scanned)') : code;
  }

  /// "Some pages were skipped (scanned): 3, 7"
  String get line => pages.isEmpty ? text : '$text: ${pages.join(', ')}';
}

/// A part of the file the reader left out on purpose: `{kind: cover|publisher|toc|references|index, pages}`.
class RagExcluded {
  const RagExcluded(this.kind, [this.pages = const []]);
  final String kind;
  final List<int> pages;
  factory RagExcluded.fromJson(Map<String, dynamic> j) => RagExcluded(asStr(j['kind']), _pages(j['pages']));
}

List<int> _pages(Object? v) => v is List ? [for (final x in v) asInt(x)] : const [];

List<RagWarning> ragParseWarnings(Object? v) => v is List ? [for (final m in asMapList(v)) RagWarning.fromJson(m)] : const [];

List<RagExcluded> ragParseExcluded(Object? v) => v is List ? [for (final m in asMapList(v)) RagExcluded.fromJson(m)] : const [];

List<int> ragParsePages(Object? v) => _pages(v);

String ragExcludedKindText(String k) => switch (k) {
      'cover' => t('الغلاف', 'cover'),
      'publisher' => t('بيانات الناشر', 'publisher page'),
      'toc' => t('فهرس المحتويات', 'table of contents'),
      'references' => t('المراجع', 'references'),
      'index' => t('الفهرس الأبجدي', 'index'),
      _ => k,
    };

/// "Skipped: table of contents, references, index" · '' when nothing was left out.
String ragExcludedLine(List<RagExcluded> ex) {
  final names = <String>[];
  for (final e in ex) {
    final n = ragExcludedKindText(e.kind);
    if (!names.contains(n)) names.add(n);
  }
  if (names.isEmpty) return '';
  return t('تم تخطي: ${names.join('، ')}', 'Skipped: ${names.join(', ')}');
}

/// "12 / 80 pages" · ''. Only while the worker is reading and the server knows the total.
String ragProgressText(int done, int total) {
  if (total <= 0) return '';
  final d = done.clamp(0, total);
  return t('$d / $total صفحة', '$d / $total pages');
}

/// 0–1 share for the bar; null when there is no total (the bar then stays indeterminate).
double? ragProgressValue(int done, int total) => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

/// A failed document's error as a sentence. The server's text starts with the code (`no_readable_text: …`).
String ragDocErrorText(String? error) {
  final e = (error ?? '').trim();
  if (e.isEmpty) return '';
  final code = e.split(RegExp(r'[:\s]')).first;
  return switch (code) {
    'no_readable_text' || 'no_text' => t('هذا الملف لا يحتوي على نص مقروء', 'This file has no readable text'),
    'images_not_accepted' => t('الصور غير مقبولة الآن — ارفع Word أو PDF نصياً', 'Photos are not accepted right now — upload Word or a text PDF'),
    _ => e,
  };
}

/// The hint next to the upload button. [ocrScanned]: reading scanned pages is on (null = not known to the app).
/// [maxMb]: the server's limit when it is known (from a `too_large` answer); otherwise the sentence is left out.
String ragUploadHint({bool? ocrScanned, int? maxMb}) {
  final parts = <String>[
    t('ارفع ملف Word أو PDF نصياً. الصور داخل الملفات تُتجاهل.', 'Upload Word or a text PDF. Images inside files are ignored.'),
    if (ocrScanned == true)
      t('الصفحات الممسوحة تُقرأ تلقائياً وقد تفقد بعض الكلمات.', 'Scanned pages are read automatically and may lose words.')
    else
      t('ملف PDF ممسوح بالكامل يُرفض.', 'A fully scanned PDF is refused.'),
    if (maxMb != null) t('الحد الأقصى $maxMb م.ب.', 'Maximum size $maxMb MB.'),
  ];
  return parts.join(' ');
}

/// The hint line under the upload button.
class RagUploadHint extends StatelessWidget {
  const RagUploadHint({super.key, this.ocrScanned, this.maxMb});
  final bool? ocrScanned;
  final int? maxMb;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 15, color: c.textLight),
        const SizedBox(width: 6),
        Expanded(child: Text(ragUploadHint(ocrScanned: ocrScanned, maxMb: maxMb), style: appText(11.5, c: c.textLight))),
      ]),
    );
  }
}

/// "12 / 80 pages" with a bar (a plain bar while the total is unknown).
class RagProgressRow extends StatelessWidget {
  const RagProgressRow({super.key, required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = ragProgressText(done, total);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (text.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: appText(12, w: FontWeight.w700, c: c.textMedium))),
        ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(minHeight: 4, value: ragProgressValue(done, total))),
      ]),
    );
  }
}

/// The warnings of a document as one chip each (wraps; never overflows).
class RagWarningChips extends StatelessWidget {
  const RagWarningChips({super.key, required this.warnings});
  final List<RagWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final w in warnings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: appInk(context, c.warning)),
                const SizedBox(width: 6),
                Expanded(child: Text(w.line, style: appText(12, c: c.textDark))),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// The muted "Skipped: …" line.
class RagExcludedText extends StatelessWidget {
  const RagExcludedText({super.key, required this.excluded});
  final List<RagExcluded> excluded;

  @override
  Widget build(BuildContext context) {
    final line = ragExcludedLine(excluded);
    if (line.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(line, style: appText(11.5, c: context.colors.textLight)));
  }
}
