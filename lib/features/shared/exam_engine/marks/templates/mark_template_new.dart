// A new template: choose what the sheet is (cover · mark sheet · MCQ answer table), photograph (phone) or upload (web
// and fallback) a BLANK sheet, let the server propose the boxes (`/mark-templates/detect`), then open the editor.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../../../admin/admin_common.dart' show t;
import '../mark_templates_api.dart';
import 'mark_template_common.dart';
import 'mark_template_editor.dart';

class MarkTemplateNewPage extends StatefulWidget {
  const MarkTemplateNewPage({super.key, this.orgId, this.kind, this.api, this.picker});
  final int? orgId;

  /// Fixed by the caller (an exam needs an answer table): the choice step is skipped.
  final MarkKind? kind;
  final MarkTemplatesApi? api;
  final MarkImagePicker? picker;

  @override
  State<MarkTemplateNewPage> createState() => _MarkTemplateNewPageState();
}

class _MarkTemplateNewPageState extends State<MarkTemplateNewPage> {
  late final MarkTemplatesApi _api = widget.api ?? MarkTemplatesApi();
  late MarkKind? _kind = widget.kind;
  bool _busy = false;
  String? _error;

  Future<void> _capture({required bool camera}) async {
    final kind = _kind;
    if (kind == null) return;
    final img = await (widget.picker ?? defaultMarkImagePicker)(camera: camera);
    if (img == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _api.detect(img, orgId: widget.orgId);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _busy = false;
        _error = markErrorText(r);
      });
      return;
    }
    final det = MarkDetect.fromJson(r.map);
    final spec = MarkSheetSpec.fromDetect(r.map, kind);
    final Uint8List bytes = img.$2;
    setState(() => _busy = false);
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => MarkTemplateEditorPage(api: _api, picker: widget.picker, orgId: widget.orgId, kind: kind, spec: spec, image: bytes, blankKey: det.blankKey),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BasePage(
      key: const ValueKey(kMarkTemplatesFeatureKey),
      appBar: ScreenAppBar(title: t('قالب ورقة جديد', 'New sheet template')),
      child: _busy
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  AppSpace.gapMd,
                  Text(t('نبحث عن الخانات في الورقة…', 'Looking for the boxes on the sheet…'), style: AppType.row(context), textAlign: TextAlign.center),
                ]),
              ),
            )
          : ListView(padding: const EdgeInsets.all(AppSpace.md), children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _kind == null ? _kindStep(context) : _captureStep(context),
                ),
              ),
            ]),
    );
  }

  Widget _kindStep(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('ما نوع الورقة؟', 'What kind of sheet is it?'), style: AppType.pageTitle(context)),
      AppSpace.gapXs,
      Text(t('اختر ما يناسب ورقتك المطبوعة.', 'Pick what matches your printed sheet.'), style: AppType.meta(context)),
      AppSpace.gapMd,
      for (final k in MarkKind.values)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.sm),
          child: AppCard(
            onTap: () => setState(() => _kind = k),
            child: Row(children: [
              Icon(kindIcon(k), color: context.colors.primary, size: 28),
              AppSpace.gapSm,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k.label, style: AppType.section(context)),
                  Text(k.hint, style: AppType.meta(context)),
                ]),
              ),
            ]),
          ),
        ),
    ]);
  }

  Widget _captureStep(BuildContext context) {
    final kind = _kind!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(kindIcon(kind), color: context.colors.primary),
        AppSpace.gapXs,
        Expanded(child: Text(kind.label, style: AppType.pageTitle(context))),
        if (widget.kind == null) TextButton(onPressed: () => setState(() => _kind = null), child: Text(t('تغيير', 'Change'))),
      ]),
      AppSpace.gapSm,
      AppBanner(
        icon: Icons.lightbulb_outline_rounded,
        text: t('استخدم ورقة فارغة غير معبأة. ضعها على سطح مستوٍ في إضاءة جيدة وأظهرها كاملة.', 'Use a BLANK sheet, nothing filled in. Lay it flat in good light and show all of it.'),
      ),
      AppSpace.gapMd,
      if (_error != null) ...[AppBanner(icon: Icons.error_outline_rounded, text: _error!, color: context.colors.danger), AppSpace.gapSm],
      if (canUseCamera) ...[
        AppPrimaryButton(label: t('تصوير الورقة الفارغة', 'Photograph the blank sheet'), icon: Icons.photo_camera_outlined, onPressed: () => _capture(camera: true)),
        AppSpace.gapSm,
        OutlinedButton.icon(onPressed: () => _capture(camera: false), icon: const Icon(Icons.upload_file_rounded), label: Text(t('رفع صورة بدلًا من ذلك', 'Upload a picture instead'))),
      ] else
        AppPrimaryButton(label: t('رفع صورة الورقة الفارغة', 'Upload the blank sheet picture'), icon: Icons.upload_file_rounded, onPressed: () => _capture(camera: false)),
    ]);
  }
}
