// "Test on one filled sheet": the teacher takes (or uploads) a photo of ONE filled sheet, the server reads it with the
// saved template (nothing is stored), and this page shows what was read per field (value, confidence colour, the
// crop it came from) and whether the parts add up to the written total. Wrong? Back to the editor, move the box.
import 'dart:convert' show base64Decode;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/exams/marks/mark_templates_api.dart';
import 'package:flutter_education_app/features/exams/marks/templates/mark_canvas.dart' show fieldCaption;
import 'package:flutter_education_app/features/exams/marks/templates/mark_template_common.dart';

class MarkTemplateTestPage extends StatefulWidget {
  const MarkTemplateTestPage({super.key, required this.template, required this.spec, this.blank, this.api, this.picker});

  final MarkTemplate template;
  final MarkSheetSpec spec;
  final Uint8List? blank;
  final MarkTemplatesApi? api;
  final MarkImagePicker? picker;

  @override
  State<MarkTemplateTestPage> createState() => _MarkTemplateTestPageState();
}

class _MarkTemplateTestPageState extends State<MarkTemplateTestPage> {
  late final MarkTemplatesApi _api = widget.api ?? MarkTemplatesApi();
  bool _busy = false;
  String? _error;
  MarkTestReading? _reading;
  Uint8List? _preview;

  Future<void> _run({required bool camera}) async {
    final img = await (widget.picker ?? defaultMarkImagePicker)(camera: camera);
    if (img == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.test(widget.template.id, img);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = markErrorText(r);
        _reading = null;
      });
      return;
    }
    final reading = MarkTestReading.fromJson(r.map);
    Uint8List? preview;
    if (reading.previewB64 != null) {
      try {
        final raw = reading.previewB64!;
        preview = base64Decode(raw.contains(',') ? raw.substring(raw.indexOf(',') + 1) : raw);
      } catch (_) {}
    }
    if (preview == null && reading.previewUrl != null) preview = await _api.imageAt(reading.previewUrl!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reading = reading;
      _preview = preview;
    });
    if (!reading.ok) showAppNotice(qualityCodeText(reading.qualityCode), error: true);
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kMarkTemplatesFeatureKey),
      appBar: ScreenAppBar(title: t('تجربة القالب', 'Test the template')),
      child: _busy
          ? const AppListSkeleton(items: 5)
          : _reading == null
              ? _Start(name: widget.template.name, error: _error, onCamera: () => _run(camera: true), onFile: () => _run(camera: false))
              : MarkTestResultView(
                  reading: _reading!,
                  spec: widget.spec,
                  image: _preview,
                  onAgain: () => setState(() => _reading = null),
                  onBack: () => Navigator.of(context).maybePop(),
                ),
    );
  }
}

class _Start extends StatelessWidget {
  const _Start({required this.name, required this.error, required this.onCamera, required this.onFile});
  final String name;
  final String? error;
  final VoidCallback onCamera;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: AppWidth.form.max),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(name, style: AppType.pageTitle(context)),
            AppSpace.gapXs,
            Text(t('صوّر ورقة واحدة معبأة بخط اليد، أو ارفع صورتها. لن يُحفظ شيء، ستعرف فقط ماذا قرأ النظام قبل أن تصحح الدفعة كلها.',
                'Photograph ONE filled sheet, or upload its picture. Nothing is saved; you just see what the system read before you scan the whole batch.'), style: AppType.meta(context)),
            AppSpace.gapMd,
            if (error != null) ...[AppBanner(icon: Icons.error_outline_rounded, text: error!, color: context.colors.danger), AppSpace.gapSm],
            if (canUseCamera) ...[
              AppPrimaryButton(label: t('تصوير الورقة', 'Take a photo'), icon: Icons.photo_camera_outlined, onPressed: onCamera),
              AppSpace.gapSm,
            ],
            canUseCamera
                ? OutlinedButton.icon(onPressed: onFile, icon: const Icon(Icons.upload_file_rounded), label: Text(t('رفع صورة', 'Upload a picture')))
                : AppPrimaryButton(label: t('رفع صورة الورقة', 'Upload the sheet picture'), icon: Icons.upload_file_rounded, onPressed: onFile),
          ]),
        ),
      ),
    ]);
  }
}

/// What was read, field by field (plain values in: the layout test pumps it alone).
class MarkTestResultView extends StatelessWidget {
  const MarkTestResultView({super.key, required this.reading, required this.spec, this.image, this.onAgain, this.onBack});

  final MarkTestReading reading;
  final MarkSheetSpec spec;

  /// The picture the server read (the straightened page), for the crops.
  final Uint8List? image;
  final VoidCallback? onAgain;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final problems = reading.fields.where((f) => !f.ok).length;
    return ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
      if (!reading.ok)
        AppBanner(icon: Icons.error_outline_rounded, text: qualityCodeText(reading.qualityCode), color: c.danger)
      else if (problems == 0)
        AppBanner(icon: Icons.check_circle_outline_rounded, text: t('قُرئت كل الحقول بثقة جيدة.', 'Every field was read with good confidence.'), color: c.success)
      else
        AppBanner(
            icon: Icons.warning_amber_rounded,
            text: t('$problems حقول تحتاج مراجعة. حرّك مربعاتها في المحرر ثم جرّب مرة أخرى.', '$problems fields need a look. Move their boxes in the editor, then test again.'),
            color: c.warning),
      AppSpace.gapSm,
      if (reading.identifierValue != null || reading.identifierMethod != null) ...[
        AppCard(
          child: Row(children: [
            Icon(Icons.badge_outlined, color: c.primary),
            AppSpace.gapSm,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('هوية الطالب', 'Student identifier'), style: AppType.meta(context)),
                Text(reading.identifierValue ?? '—', style: AppType.figure(context), textDirection: TextDirection.ltr),
                if (reading.identifierMethod != null) Text(reading.identifierMethod!, style: AppType.meta(context)),
              ]),
            ),
            if (reading.identifierConf != null) _ConfPill(conf: reading.identifierConf!, ok: reading.identifierValue != null),
          ]),
        ),
        AppSpace.gapSm,
      ],
      AppSectionTitle(t('ما قرأه النظام', 'What was read')),
      for (final f in reading.fields)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.xs),
          child: _FieldReadingCard(reading: f, spec: spec, image: image),
        ),
      if (reading.fields.isEmpty) Text(t('لم يُقرأ أي حقل.', 'No field was read.'), style: AppType.meta(context)),
      AppSpace.gapSm,
      _SumCheck(reading: reading),
      AppSpace.gapMd,
      Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, children: [
        if (onAgain != null) AppPrimaryButton(label: t('تجربة ورقة أخرى', 'Test another sheet'), icon: Icons.refresh_rounded, onPressed: onAgain),
        if (onBack != null) OutlinedButton.icon(onPressed: onBack, icon: const Icon(Icons.edit_outlined), label: Text(t('العودة للمحرر', 'Back to the editor'))),
      ]),
    ]);
  }
}

String statusText(FieldReading f) => switch (f.status) {
      'ok' => t('مقروء', 'Read'),
      'low' => t('ثقة منخفضة', 'Low confidence'),
      'blank' => t('فارغ', 'Empty'),
      'above_max' => t('أعلى من الدرجة العظمى', 'Above the maximum'),
      _ => t('غير مقروء', 'Unreadable'),
    };

class _ConfPill extends StatelessWidget {
  const _ConfPill({required this.conf, required this.ok});
  final double conf;
  final bool ok;

  @override
  Widget build(BuildContext context) => AppBadgePill(pct(conf), color: confColor(context, conf, ok: ok));
}

class _FieldReadingCard extends StatelessWidget {
  const _FieldReadingCard({required this.reading, required this.spec, required this.image});
  final FieldReading reading;
  final MarkSheetSpec spec;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = spec.field(reading.id);
    final box = reading.box ?? f?.box;
    final col = confColor(context, reading.conf, ok: reading.ok);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        if (image != null && box != null) ...[
          FieldCrop(image: image!, box: box, pageAspect: spec.aspect),
          AppSpace.gapSm,
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f == null ? reading.id : fieldCaption(f), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(reading.value == null || reading.value!.isEmpty ? '—' : reading.value!, style: AppType.figure(context).copyWith(color: col), textDirection: TextDirection.ltr, maxLines: 2, overflow: TextOverflow.ellipsis),
            Text(statusText(reading), style: AppType.meta(context).copyWith(color: reading.ok ? c.textMedium : col)),
            if (!reading.ok && reading.candidates.isNotEmpty)
              Text(t('احتمالات: ', 'Maybe: ') + reading.candidates.take(3).map((x) => '${x.$1} (${pct(x.$2)})').join('، '), style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        AppSpace.gapXs,
        _ConfPill(conf: reading.conf, ok: reading.ok),
      ]),
    );
  }
}

/// The part of the page picture a box covers, scaled to a small strip.
class FieldCrop extends StatelessWidget {
  const FieldCrop({super.key, required this.image, required this.box, required this.pageAspect, this.maxWidth = 96, this.maxHeight = 56});
  final Uint8List image;
  final Rect box;
  final double pageAspect;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final bw = box.width <= 0 ? 0.01 : box.width;
    final bh = box.height <= 0 ? 0.01 : box.height;
    final ratio = (bw * pageAspect) / bh;
    var w = maxWidth;
    var h = w / ratio;
    if (h > maxHeight) {
      h = maxHeight;
      w = h * ratio;
    }
    final fullW = w / bw;
    final fullH = h / bh;
    return Container(
      width: w,
      height: h,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(border: Border.all(color: context.colors.divider), borderRadius: AppRadius.chipAll),
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(
          left: -box.left * fullW,
          top: -box.top * fullH,
          width: fullW,
          height: fullH,
          child: Image.memory(image, fit: BoxFit.fill, gaplessPlayback: true, excludeFromSemantics: true, errorBuilder: (_, _, _) => const SizedBox()),
        ),
      ]),
    );
  }
}

class _SumCheck extends StatelessWidget {
  const _SumCheck({required this.reading});
  final MarkTestReading reading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (reading.computed == null && reading.written == null) return const SizedBox.shrink();
    final consistent = reading.consistent;
    final col = consistent == null ? c.textMedium : (consistent ? c.success : c.danger);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(consistent == false ? Icons.warning_amber_rounded : Icons.functions_rounded, color: col),
          AppSpace.gapXs,
          Expanded(child: Text(t('فحص المجموع', 'Sum check'), style: AppType.section(context))),
        ]),
        AppSpace.gapXs,
        Text(t('المجموع المكتوب: ${reading.written == null ? '—' : numText(reading.written!)}', 'Written total: ${reading.written == null ? '—' : numText(reading.written!)}'), style: AppType.row(context)),
        Text(t('مجموع الأجزاء المحسوب: ${reading.computed == null ? '—' : numText(reading.computed!)}${reading.partsRead == null ? '' : ' (${reading.partsRead} أجزاء)'}',
            'Computed from the parts: ${reading.computed == null ? '—' : numText(reading.computed!)}${reading.partsRead == null ? '' : ' (${reading.partsRead} parts)'}'), style: AppType.row(context)),
        AppSpace.gapXs,
        Text(
          consistent == null
              ? t('لا يمكن الفحص.', 'Cannot be checked.')
              : consistent
                  ? t('المجموع المكتوب يطابق مجموع الأجزاء.', 'The written total matches the parts.')
                  : t('المجموع المكتوب لا يطابق الأجزاء. سيستخدم النظام المجموع المحسوب.', 'The written total does not match the parts. The system will use the computed one.'),
          style: AppType.row(context).copyWith(color: col),
        ),
      ]),
    );
  }
}
