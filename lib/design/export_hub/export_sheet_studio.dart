// lib/design/export_hub/export_sheet_studio.dart
//
// The Excel studio — table oriented: the live sheet on one side, the options on the other (stacked on a phone): a
// title band with {{variables}} and a logo, header colour / text colour / weight / size, striped rows, borders,
// number and date formats, column widths, a frozen header and the sheet direction (automatic for Arabic). Column
// order and names live in the flow's Fields step; conditional rules in "Highlight rules". Returns the edited
// XlsxSheetOptions (null when the person backs out).
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';

import '../../features/org/org_providers.dart' show orgBase;
import '../../features/shared/rag/app_assistant.dart' show AppAssistant;
import '../app_kit.dart';
import '../app_notice.dart';
import '../app_tokens.dart';
import '../export/export_studio_model.dart';
import '../studio/studio_props.dart';
import 'export_designer.dart' show exportColor, exportSwatches, rememberExportImage;
import 'export_flow_parts.dart' show ExportSheetPreview, xs;

Future<XlsxSheetOptions?> openExportSheetStudio(
  BuildContext context, {
  required AppTableExport export,
  required List<String> columns,
  required XlsxSheetOptions sheet,
  List<ExportRule> rules = const [],
  ExportNumerals numerals = ExportNumerals.western,
  int? orgId,
}) =>
    Navigator.of(context).push<XlsxSheetOptions>(MaterialPageRoute(
      builder: (_) => ExportSheetStudioPage(export: export, columns: columns, sheet: sheet, rules: rules, numerals: numerals, orgId: orgId),
    ));

class ExportSheetStudioPage extends StatefulWidget {
  const ExportSheetStudioPage({super.key, required this.export, required this.columns, required this.sheet, this.rules = const [], this.numerals = ExportNumerals.western, this.orgId});

  /// The table in the file's language (headers already resolved).
  final AppTableExport export;
  final List<String> columns;
  final XlsxSheetOptions sheet;
  final List<ExportRule> rules;
  final ExportNumerals numerals;
  final int? orgId;

  @override
  State<ExportSheetStudioPage> createState() => _ExportSheetStudioPageState();
}

class _ExportSheetStudioPageState extends State<ExportSheetStudioPage> {
  late final XlsxSheetOptions _s = widget.sheet.copy();
  late final _title = TextEditingController(text: _s.title);
  late final _logo = TextEditingController(text: _s.logoUrl);

  @override
  void initState() {
    super.initState();
    AppAssistant.hide(); // full screen: the floating assistant tab would cover the settings panel
  }

  @override
  void dispose() {
    _title.dispose();
    _logo.dispose();
    AppAssistant.release();
    super.dispose();
  }

  void _set(VoidCallback fn) => setState(fn);

  Future<void> _upload() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null || !mounted || widget.orgId == null) return;
    final Uint8List bytes = await f.readAsBytes();
    try {
      final r = await ApiClient().postMultipart('$orgBase/orgs/${widget.orgId}/uploads', fields: const {}, fileField: 'file', fileName: f.name, fileBytes: bytes);
      final url = r is Map ? '${r['url'] ?? ''}' : '';
      if (url.isEmpty || !mounted) return;
      rememberExportImage(url, bytes);
      _set(() => _s.logoUrl = _logo.text = url);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = ExportSheetPreview(export: widget.export, columns: widget.columns, sheet: _s, rules: widget.rules, numerals: widget.numerals, maxRows: 12);
    final done = AppPrimaryButton(label: xs('exs_use_settings', 'Use these settings', 'استخدام هذه الإعدادات'), icon: Icons.check_rounded, onPressed: () => Navigator.pop(context, _s));
    return BasePage(
      appBar: ScreenAppBar(title: xs('exs_sheet_studio', 'Excel studio', 'استوديو Excel')),
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final panel = _panel(context);
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(xs('exs_sheet_preview', 'Sheet preview', 'معاينة الورقة'), style: AppType.section(context)),
                  const SizedBox(height: AppSpace.xs),
                  Text(xs('exs_sheet_preview_hint', 'The first rows with your rules applied.', 'أول الصفوف مع تطبيق قواعدك.'), style: AppType.meta(context)),
                  const SizedBox(height: AppSpace.sm),
                  preview,
                ]),
              ),
            ),
            Container(
              width: 380,
              decoration: BoxDecoration(color: c.cardBg, border: BorderDirectional(start: BorderSide(color: c.divider))),
              child: Column(children: [
                Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.md), child: panel)),
                Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: c.divider))), padding: const EdgeInsets.all(AppSpace.md), child: done),
              ]),
            ),
          ]);
        }
        return Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md), children: [preview, const SizedBox(height: AppSpace.sm), panel]),
          ),
          Container(
            decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.sm),
            child: SafeArea(top: false, child: done),
          ),
        ]);
      }),
    );
  }

  Widget _panel(BuildContext context) {
    final cols = widget.export.resolve(widget.columns);
    final swatches = [for (final h in exportSwatches) exportColor(h)];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StudioPropSection(first: true, title: xs('exs_sheet_title', 'Title band', 'شريط العنوان'), children: [
        AppSwitchTile(title: xs('exs_sheet_title_row', 'Show a title above the table', 'عنوان فوق الجدول'), value: _s.titleRow, dense: true, onChanged: (v) => _set(() => _s.titleRow = v)),
        if (_s.titleRow) ...[
          TextField(
            controller: _title,
            maxLength: 200,
            decoration: InputDecoration(isDense: true, labelText: xs('exs_sheet_title_text', 'Title (empty = the page title)', 'العنوان (فارغ = عنوان الصفحة)'), hintText: '{{title}} · {{org_name}}', counterText: ''),
            onChanged: (v) => _set(() => _s.title = v),
          ),
          Wrap(spacing: AppSpace.xxs + 2, runSpacing: AppSpace.xxs + 2, children: [
            for (final k in const ['title', 'org_name', 'date', 'rows', 'exporter'])
              ActionChip(
                label: Text('{{$k}}', style: appText(12, c: context.colors.textDark)),
                onPressed: () => _set(() => _s.title = _title.text = '${_title.text}{{$k}}'),
              ),
          ]),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _logo,
              decoration: InputDecoration(isDense: true, labelText: xs('exs_sheet_logo', 'Logo image link', 'رابط صورة الشعار'), hintText: 'https://…'),
              onChanged: (v) => _set(() => _s.logoUrl = v.trim()),
            ),
          ),
          if (widget.orgId != null) Align(alignment: AlignmentDirectional.centerStart, child: AppPill(icon: Icons.upload_rounded, label: xs('exs_upload_logo', 'Upload a logo', 'رفع شعار'), onTap: _upload)),
        ],
      ]),
      StudioPropSection(title: xs('exs_sheet_header', 'Header row', 'صف العناوين'), children: [
        StudioColorField(label: xs('exs_sheet_header_color', 'Fill', 'التعبئة'), allowNone: true, swatches: swatches, value: _s.headerColor.isEmpty ? null : exportColor(_s.headerColor), onChanged: (v) => _set(() => _s.headerColor = v == null ? '' : studioHex(v))),
        StudioColorField(label: xs('exs_sheet_header_ink', 'Text colour (empty = automatic)', 'لون النص (فارغ = تلقائي)'), allowNone: true, swatches: swatches, value: _s.headerFontColor.isEmpty ? null : exportColor(_s.headerFontColor), onChanged: (v) => _set(() => _s.headerFontColor = v == null ? '' : studioHex(v))),
        AppSwitchTile(title: xs('exs_sheet_header_bold', 'Bold headers', 'عناوين عريضة'), value: _s.headerBold, dense: true, onChanged: (v) => _set(() => _s.headerBold = v)),
        StudioStepper(label: xs('exs_sheet_font_size', 'Font size', 'حجم الخط'), value: _s.fontSize, min: 7, max: 20, suffix: 'pt', onChanged: (v) => _set(() => _s.fontSize = v)),
        AppSwitchTile(title: xs('exs_sheet_freeze', 'Keep the header visible while scrolling', 'تثبيت صف العناوين عند التمرير'), value: _s.freezeHeader, dense: true, onChanged: (v) => _set(() => _s.freezeHeader = v)),
      ]),
      StudioPropSection(title: xs('exs_sheet_rows', 'Rows', 'الصفوف'), children: [
        AppSwitchTile(title: xs('exs_sheet_striping', 'Striped rows', 'صفوف متبادلة'), value: _s.striping, dense: true, onChanged: (v) => _set(() => _s.striping = v)),
        if (_s.striping)
          StudioColorField(
            label: xs('exs_sheet_stripe', 'Stripe colour', 'لون الشريط'),
            swatches: const [Color(0xFFF6F8FA), Color(0xFFEEF2FF), Color(0xFFECFDF5), Color(0xFFFFF7ED), Color(0xFFF5F3FF), Color(0xFFF1F5F9)],
            value: exportColor(_s.stripeColor),
            onChanged: (v) => _set(() => _s.stripeColor = v == null ? 'F6F8FA' : studioHex(v)),
          ),
        AppSwitchTile(title: xs('exs_sheet_borders', 'Cell borders', 'حدود الخلايا'), value: _s.borders, dense: true, onChanged: (v) => _set(() => _s.borders = v)),
        if (_s.borders)
          StudioColorField(label: xs('exs_sheet_border_color', 'Border colour', 'لون الحدود'), swatches: swatches, value: exportColor(_s.borderColor), onChanged: (v) => _set(() => _s.borderColor = v == null ? 'D7DDE3' : studioHex(v))),
      ]),
      StudioPropSection(title: xs('exs_sheet_formats', 'Number and date formats', 'تنسيق الأرقام والتواريخ'), children: [
        StudioPropField(
          label: xs('exs_sheet_numbers', 'Numbers', 'الأرقام'),
          child: StudioSegmented<String>(
            segments: [
              StudioSegment(value: 'auto', label: xs('exs_auto', 'Automatic', 'تلقائي')),
              const StudioSegment(value: '#,##0.00', label: '1,234.50'),
              const StudioSegment(value: '#,##0', label: '1,235'),
              const StudioSegment(value: '0.00', label: '1234.50'),
            ],
            value: _s.numberFormat,
            onChanged: (v) => _set(() => _s.numberFormat = v),
          ),
        ),
        StudioPropField(
          label: xs('exs_sheet_dates', 'Dates', 'التواريخ'),
          child: StudioSegmented<String>(
            segments: const [
              StudioSegment(value: 'yyyy-mm-dd', label: '2026-10-31'),
              StudioSegment(value: 'dd/mm/yyyy', label: '31/10/2026'),
              StudioSegment(value: 'd mmm yyyy', label: '31 Oct 2026'),
            ],
            value: _s.dateFormat,
            onChanged: (v) => _set(() => _s.dateFormat = v),
          ),
        ),
      ]),
      StudioPropSection(title: xs('exs_sheet_widths', 'Column widths', 'عرض الأعمدة'), children: [
        Text(xs('exs_sheet_widths_hint', '0 = fit the content.', '0 = حسب المحتوى.'), style: AppType.meta(context)),
        for (final col in cols)
          StudioStepper(
            label: col.label,
            value: _s.widths[col.id] ?? 0,
            max: 120,
            step: 2,
            onChanged: (v) => _set(() {
              if (v <= 0) {
                _s.widths.remove(col.id);
              } else {
                _s.widths[col.id] = v.clamp(4, 120).toDouble();
              }
            }),
          ),
      ]),
      StudioPropSection(title: xs('exs_sheet_direction', 'Sheet direction', 'اتجاه الورقة'), children: [
        StudioSegmented<String>(
          segments: [
            StudioSegment(value: 'auto', label: xs('exs_dir_auto', 'By language', 'حسب اللغة')),
            StudioSegment(value: 'rtl', label: xs('exs_dir_rtl', 'Right to left', 'من اليمين')),
            StudioSegment(value: 'ltr', label: xs('exs_dir_ltr', 'Left to right', 'من اليسار')),
          ],
          value: _s.rtl == null ? 'auto' : (_s.rtl! ? 'rtl' : 'ltr'),
          onChanged: (v) => _set(() => _s.rtl = v == 'auto' ? null : v == 'rtl'),
        ),
      ]),
    ]);
  }
}
