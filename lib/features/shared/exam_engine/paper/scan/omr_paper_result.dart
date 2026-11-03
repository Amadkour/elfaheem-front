// What one paper gave (smart photos, `result` of a page): plain values in, drawn the same in the camera's result card
// (omr_scan_widgets.dart CaptureResultCard), the upload / batch progress (ScanProgressView) and the preview sheet.
//   OmrResultSummary   the tier's icon + "Read successfully" / "Read with 3 questions to review" / "Read in part" /
//                      "Couldn't read this paper", the server's reason, its tips, the retake suggestion
//   OmrPreviewThumb    a small picture of the improved image (tap: the preview)
//   OmrPreviewView     the improved image with the detected marks, what was improved, Retake / Close
//   OmrPaperRow        one paper of a batch (label, file, result, Preview)
//   OmrPaperResults    a batch's papers: the ones to look at first, the ones read successfully folded
// The screens load the image with the engine's signed-image call (OmrScanApi.image) and hand the bytes in.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';

import '../../../../admin/admin_common.dart' show t;
import 'omr_scan.dart';

/// The colour and icon of a tier.
(Color, IconData) omrTierLook(BuildContext context, OmrTier tier) {
  final c = context.colors;
  return switch (tier) {
    OmrTier.accept => (c.success, Icons.check_circle_rounded),
    OmrTier.flags => (c.primary, Icons.rate_review_rounded),
    OmrTier.retake => (c.warning, Icons.camera_enhance_rounded),
    OmrTier.reject => (c.danger, Icons.error_rounded),
  };
}

/// "12 read successfully" / "قُرئت 12 ورقة بنجاح".
String omrReadOkText(int n) => countText(n,
    ar1: 'قُرئت ورقة واحدة بنجاح',
    ar2: 'قُرئت ورقتان بنجاح',
    arFew: 'قُرئت {n} أوراق بنجاح',
    arMany: 'قُرئت {n} ورقة بنجاح',
    en1: '1 paper read successfully',
    en: '{n} papers read successfully');

/// The tier's title, the server's reason, the tips and (retake) the suggestion. [lead]: a line drawn under the title
/// before the rest (the camera's "Paper 12 of 40 captured").
class OmrResultSummary extends StatelessWidget {
  const OmrResultSummary({super.key, required this.result, this.lead, this.showIcon = true, this.compact = false});

  final OmrPageResult result;
  final String? lead;
  final bool showIcon;

  /// A row of a list: smaller type.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (tone, icon) = omrTierLook(context, result.tier);
    final ink = appInk(context, tone);
    // the server's sentence only where it adds something (a retake's / rejection's reason): the title already says
    // what a read paper gave, and the tips never repeat a line above them
    final msg = result.detail ?? '';
    final showMsg = msg.isNotEmpty && msg != lead;
    final tips = result.tier == OmrTier.accept ? const <String>[] : [for (final x in result.tipTexts) if (lead == null || omrTextKey(x) != omrTextKey(lead!)) x];
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(result.title,
          key: ValueKey('omr.result.title.${result.tier.name}'),
          style: appText(compact ? 14.5 : 17, w: FontWeight.w800, c: c.textDark, h: 1.3)),
      if (lead != null && lead!.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(lead!, style: appText(compact ? 12.5 : 13.5, w: FontWeight.w600, c: c.textMedium, h: 1.35)),
      ],
      if (showMsg) ...[
        const SizedBox(height: AppSpace.xxs),
        // the card's message reads before its tips: the body ink, the tips one step quieter (dark mode too)
        Text(msg, key: const ValueKey('omr.result.detail'), style: appText(compact ? 13 : 14, c: c.textDark, h: 1.4)),
      ],
      for (final tip in tips)
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xxs),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.lightbulb_outline_rounded, size: 16, color: ink)),
            const SizedBox(width: AppSpace.xxs),
            Expanded(child: Text(tip, style: appText(compact ? 12.5 : 13.5, c: c.textMedium, h: 1.4))),
          ]),
        ),
      if (result.tier == OmrTier.retake) ...[
        const SizedBox(height: AppSpace.xxs),
        Text(omrRetakeSuggestion(), key: const ValueKey('omr.result.suggest'), style: appText(compact ? 12.5 : 13.5, w: FontWeight.w600, c: ink, h: 1.4)),
      ],
    ]);
    if (!showIcon) return body;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: compact ? 36 : 44,
        height: compact ? 36 : 44,
        decoration: BoxDecoration(color: tone.withValues(alpha: .14), shape: BoxShape.circle),
        child: Icon(icon, color: ink, size: compact ? 20 : 26),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(child: body),
    ]);
  }
}

/// A small picture of the improved page (A4 portrait); a shimmer while it loads, an icon when it could not be read.
class OmrPreviewThumb extends StatelessWidget {
  const OmrPreviewThumb({super.key, this.bytes, this.loading = false, this.onTap, this.width = 56});

  final Uint8List? bytes;
  final bool loading;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = width * 297 / 210;
    final b = bytes;
    Widget inner;
    if (b != null) {
      inner = Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => Icon(Icons.image_not_supported_outlined, color: c.textLight));
    } else if (loading) {
      inner = AppSkeletonBox(width: width, height: h);
    } else {
      inner = Icon(Icons.image_outlined, color: c.textLight);
    }
    return Semantics(
      button: onTap != null,
      label: t('معاينة الصورة المحسّنة', 'Preview the improved photo'),
      child: Material(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('omr.preview.thumb'),
          onTap: onTap,
          child: Container(
            width: width,
            height: h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: c.textLight.withValues(alpha: .35)),
            ),
            alignment: Alignment.center,
            child: inner,
          ),
        ),
      ),
    );
  }
}

/// The preview: the improved photo with the marks the reader found, what was done to it, Retake / Close. Plain
/// values ([bytes] null + [loading] false = it could not be loaded).
class OmrPreviewView extends StatelessWidget {
  const OmrPreviewView({super.key, required this.result, this.bytes, this.loading = false, this.onRetake, this.retakeLabel, this.onClose});

  final OmrPageResult result;
  final Uint8List? bytes;
  final bool loading;
  final VoidCallback? onRetake;

  /// "Retake" (camera) / "Replace this page" (an uploaded page).
  final String? retakeLabel;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxH = (MediaQuery.sizeOf(context).height * .58).clamp(220.0, 760.0).toDouble();
    final b = bytes;
    final Widget picture;
    if (b != null) {
      picture = InteractiveViewer(
        maxScale: 5,
        child: Image.memory(b,
            key: const ValueKey('omr.preview.image'),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => _PreviewMissing(text: t('تعذّر عرض الصورة', 'The photo could not be shown'))),
      );
    } else if (loading) {
      picture = const AppSkeletonBox(width: double.infinity, height: double.infinity);
    } else {
      picture = _PreviewMissing(text: t('تعذّر تحميل الصورة المحسّنة — النتيجة أعلاه محفوظة', 'The improved photo could not be loaded — the result above is kept'));
    }
    final applied = result.appliedText;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      OmrResultSummary(result: result),
      const SizedBox(height: AppSpace.md),
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          height: maxH,
          color: c.isDark ? c.background : c.charcoalDark.withValues(alpha: .06),
          alignment: Alignment.center,
          child: picture,
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      Text(
        applied.isEmpty
            ? t('الإطار الملوّن يبيّن ما وجده القارئ على الورقة', 'The coloured marks show what the reader found on the page')
            : '$applied · ${t('الإطار الملوّن يبيّن ما وجده القارئ', 'the coloured marks show what the reader found')}',
        style: appText(12.5, c: c.textMedium, h: 1.4),
      ),
      const SizedBox(height: AppSpace.md),
      if (onRetake != null) ...[
        result.tier == OmrTier.reject
            ? AppPrimaryButton(key: const ValueKey('omr.preview.retake'), label: retakeLabel ?? t('إعادة التصوير', 'Retake'), icon: Icons.camera_alt_rounded, onPressed: onRetake)
            : FilledButton.tonalIcon(
                key: const ValueKey('omr.preview.retake'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
                onPressed: onRetake,
                icon: const Icon(Icons.camera_alt_rounded),
                label: Text(retakeLabel ?? t('إعادة التصوير', 'Retake')),
              ),
        const SizedBox(height: AppSpace.xs),
      ],
      if (onClose != null)
        OutlinedButton(
          key: const ValueKey('omr.preview.close'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppTouch.min)),
          onPressed: onClose,
          child: Text(result.graded ? t('الاحتفاظ بها', 'Keep it') : t('إغلاق', 'Close')),
        ),
    ]);
  }
}

class _PreviewMissing extends StatelessWidget {
  const _PreviewMissing({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.image_not_supported_outlined, size: 36, color: c.textLight),
        const SizedBox(height: AppSpace.xs),
        Text(text, textAlign: TextAlign.center, style: appText(13.5, c: c.textMedium, h: 1.4)),
      ]),
    );
  }
}

/// Opens the preview of [result] in a sheet; [bytes] when already loaded, else [load] fetches them. Resolves true
/// when the person chose [onRetake]'s button (the sheet closes first).
Future<bool> showOmrPreview(BuildContext context,
    {required OmrPageResult result, Uint8List? bytes, Future<Uint8List?> Function()? load, bool retake = false, String? retakeLabel}) async {
  final r = await showAppSheet<bool>(
      context,
      (ctx) => AppSheetContent(title: t('الصورة بعد التحسين', 'The improved photo'), children: [
            _PreviewLoader(
              result: result,
              bytes: bytes,
              load: load,
              onRetake: retake ? () => Navigator.of(ctx).pop(true) : null,
              retakeLabel: retakeLabel,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
          ]));
  return r == true;
}

class _PreviewLoader extends StatefulWidget {
  const _PreviewLoader({required this.result, this.bytes, this.load, this.onRetake, this.retakeLabel, this.onClose});
  final OmrPageResult result;
  final Uint8List? bytes;
  final Future<Uint8List?> Function()? load;
  final VoidCallback? onRetake;
  final String? retakeLabel;
  final VoidCallback? onClose;

  @override
  State<_PreviewLoader> createState() => _PreviewLoaderState();
}

class _PreviewLoaderState extends State<_PreviewLoader> {
  late Uint8List? _bytes = widget.bytes;
  late bool _loading = _bytes == null && widget.load != null;

  @override
  void initState() {
    super.initState();
    if (_loading) _fetch();
  }

  Future<void> _fetch() async {
    final b = await widget.load!();
    if (!mounted) return;
    setState(() {
      _bytes = b;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => OmrPreviewView(
        result: widget.result,
        bytes: _bytes,
        loading: _loading,
        onRetake: widget.onRetake,
        retakeLabel: widget.retakeLabel,
        onClose: widget.onClose,
      );
}

// ── a batch's papers ────────────────────────────────────────────────────────────────────────────────────────────

/// One paper of a batch (plain values).
class OmrPaperRow {
  const OmrPaperRow({required this.pageId, required this.label, required this.result, this.fileName, this.replacing = false});
  final int pageId;

  /// "Paper 3" (camera) / "Page 7" (an upload).
  final String label;
  final String? fileName;
  final OmrPageResult result;

  /// A clearer image of this page is being checked (Replace was tapped).
  final bool replacing;
}

/// [name] on one line; when it does not fit, the middle gives way ("scaled_10002…7462.jpg"), so the end that tells two
/// files apart stays in view. Always left to right (a file name), at the reading direction's start.
class OmrFileName extends StatelessWidget {
  const OmrFileName(this.name, {super.key, this.style});
  final String name;
  final TextStyle? style;

  /// The longest "head…tail" of [name] that fits [maxWidth] in [style] (the tail keeps a little more).
  static String fit(String name, TextStyle style, double maxWidth, TextScaler scaler) {
    double w(String s) =>
        (TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout()).width;
    if (maxWidth <= 0 || w(name) <= maxWidth) return name;
    var lo = 0, hi = name.length - 1;
    var best = name.length > 2 ? '${name[0]}…' : name;
    while (lo <= hi) {
      final keep = (lo + hi) ~/ 2;
      final tail = (keep * 3 / 5).ceil(), head = keep - tail;
      final s = '${name.substring(0, head)}…${name.substring(name.length - tail)}';
      if (w(s) <= maxWidth) {
        best = s;
        lo = keep + 1;
      } else {
        hi = keep - 1;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final st = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final shown = box.hasBoundedWidth ? fit(name, st, box.maxWidth, scaler) : name;
      return Semantics(
        label: name,
        excludeSemantics: true,
        child: Text(shown, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, textDirection: TextDirection.ltr, style: st),
      );
    });
  }
}

class OmrPaperTile extends StatelessWidget {
  const OmrPaperTile({super.key, required this.row, this.onPreview, this.onReplace});
  final OmrPaperRow row;
  final VoidCallback? onPreview;

  /// "Replace this page" — offered on a paper read in part (`retake`, where the server lets a clearer image supersede
  /// the partial read); never on a graded paper with questions to review (the server answers 409 page_not_rejected).
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = row.result;
    final (tone, _) = omrTierLook(context, r.tier);
    final replace = onReplace != null && r.tier == OmrTier.retake;
    return AppCard(
      key: ValueKey('omr.paper.${row.pageId}'),
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // "Paper 3 · wa24.jpg" together at the start (the file name used to float mid-card in Arabic)
        Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: AppSpace.xs),
          Text(row.label, maxLines: 1, style: appText(13, w: FontWeight.w700, c: c.textMedium)),
          if (row.fileName != null && row.fileName!.isNotEmpty) ...[
            Text('  ·  ', style: appText(12, c: c.textLight)),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OmrFileName(row.fileName!, key: ValueKey('omr.paper.file.${row.pageId}'), style: appText(12, c: c.textLight)),
              ),
            ),
          ],
        ]),
        const SizedBox(height: AppSpace.xs),
        OmrResultSummary(result: r, compact: true),
        if ((onPreview != null && r.previewUrl != null) || replace || row.replacing) ...[
          const SizedBox(height: AppSpace.xs),
          Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
            if (onPreview != null && r.previewUrl != null)
              TextButton.icon(
                key: ValueKey('omr.paper.preview.${row.pageId}'),
                style: TextButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: onPreview,
                icon: const Icon(Icons.image_search_rounded, size: 20),
                label: Text(t('معاينة', 'Preview')),
              ),
            if (row.replacing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: AppSpace.xs),
                  Flexible(child: Text(t('تُفحص الصورة الجديدة…', 'Checking the new image…'), style: appText(13, c: c.textMedium))),
                ]),
              )
            else if (replace)
              FilledButton.tonalIcon(
                key: ValueKey('omr.paper.replace.${row.pageId}'),
                style: FilledButton.styleFrom(minimumSize: const Size(AppTouch.min, AppTouch.min)),
                onPressed: onReplace,
                icon: const Icon(Icons.find_replace_rounded),
                label: Text(t('استبدال هذه الصفحة', 'Replace this page')),
              ),
          ]),
        ],
      ]),
    );
  }
}

/// A batch's papers that were read: the ones to look at (to review / a better photo suggested) first, those read
/// successfully folded under one line.
class OmrPaperResults extends StatefulWidget {
  const OmrPaperResults({super.key, required this.rows, this.onPreview, this.onReplace});
  final List<OmrPaperRow> rows;
  final ValueChanged<OmrPaperRow>? onPreview;

  /// "Replace this page" on the papers read in part.
  final ValueChanged<OmrPaperRow>? onReplace;

  @override
  State<OmrPaperResults> createState() => _OmrPaperResultsState();
}

class _OmrPaperResultsState extends State<OmrPaperResults> {
  bool _showOk = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final look = [for (final r in widget.rows) if (r.result.tier == OmrTier.retake || r.result.tier == OmrTier.flags) r]
      ..sort((a, b) => (a.result.tier == OmrTier.retake ? 0 : 1).compareTo(b.result.tier == OmrTier.retake ? 0 : 1));
    final ok = [for (final r in widget.rows) if (r.result.tier == OmrTier.accept) r];
    if (look.isEmpty && ok.isEmpty) return const SizedBox.shrink();
    Widget tile(OmrPaperRow r) => OmrPaperTile(
        row: r,
        onPreview: widget.onPreview == null ? null : () => widget.onPreview!(r),
        onReplace: widget.onReplace == null ? null : () => widget.onReplace!(r));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (look.isNotEmpty) ...[
        // "read", not "graded": a paper with a question or its student still to decide is not graded yet
        AppSectionTitle(t('أوراق تستحق نظرة', 'Papers worth a look'),
            subtitle: look.any((r) => r.result.tier == OmrTier.retake)
                ? t('قُرئت هذه الأوراق، وفي كل منها ما ينتظر قرارك أو صورة أوضح', 'These papers were read; each has something to decide, or a clearer photo would help')
                : t('قُرئت هذه الأوراق، وفي كل منها ما ينتظر قرارك', 'These papers were read; each has something waiting for your decision')),
        for (final r in look) tile(r),
      ],
      if (ok.isNotEmpty) ...[
        if (look.isNotEmpty) const SizedBox(height: AppSpace.xs),
        AppCard(
          key: const ValueKey('omr.papers.ok'),
          onTap: () => setState(() => _showOk = !_showOk),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.md),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: appInk(context, c.success)),
              const SizedBox(width: AppSpace.sm),
              Expanded(child: Text(omrReadOkText(ok.length), style: appText(14.5, w: FontWeight.w700, c: c.textDark))),
              Text(_showOk ? t('إخفاء', 'Hide') : t('عرض', 'Show'), style: appText(13, w: FontWeight.w700, c: appInk(context, c.primary))),
              Icon(_showOk ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.textMedium),
            ]),
          ),
        ),
        if (_showOk) ...[const SizedBox(height: AppSpace.xs), for (final r in ok) tile(r)],
      ],
    ]);
  }
}
