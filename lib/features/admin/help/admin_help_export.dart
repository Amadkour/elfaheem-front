// Export sheet of the help catalogue: what (this page | a flow | all flows of a role | everything), the format (Word user
// guide | video script as Word or JSON) and the language (ar | en | both) -> POST /api/v1/admin/help/export, then the
// file is saved / shared through the same helper the other admin exports use (p8SaveBytes).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../design/app_kit.dart';
import '../../../core/api_client.dart';
import '../../shared/help/help_models.dart';
import '../admin_money_p8.dart' show p8SaveBytes;
import 'admin_help_api.dart';

typedef HelpFileSaver = Future<void> Function(Uint8List bytes, String name, String mime);

Future<void> _defaultSave(Uint8List bytes, String name, String mime) => p8SaveBytes(bytes, name, mime: mime);

/// Opens the export sheet. [pageId]/[role] preselect "this page"; [flows] feed the "a flow" picker.
Future<void> showHelpExportSheet(BuildContext context,
    {AdminHelpApi api = const AdminHelpApi(),
    String? pageId,
    String? role,
    List<HelpFlow> flows = const [],
    HelpFileSaver save = _defaultSave}) {
  return showAppSheet<void>(context, (_) => HelpExportSheet(api: api, pageId: pageId, role: role, flows: flows, save: save));
}

class HelpExportSheet extends StatefulWidget {
  const HelpExportSheet({super.key, required this.api, this.pageId, this.role, this.flows = const [], this.save = _defaultSave});
  final AdminHelpApi api;
  final String? pageId, role;
  final List<HelpFlow> flows;
  final HelpFileSaver save;

  @override
  State<HelpExportSheet> createState() => _HelpExportSheetState();
}

class _HelpExportSheetState extends State<HelpExportSheet> {
  late String _what = widget.pageId != null ? 'page' : 'all';
  late String _role = widget.role ?? 'student';
  String? _flowKey;
  String _format = 'docx', _lang = 'ar';
  bool _json = false, _busy = false;

  bool get _ar => AppConfig.lang == 'ar';
  String _t(String ar, String en) => _ar ? ar : en;

  List<HelpFlow> get _roleFlows => [for (final f in widget.flows) if (f.role == _role) f];

  Widget _chips<T>(List<(T, String)> opts, T value, ValueChanged<T> on) => Wrap(
        spacing: AppSpace.xs,
        runSpacing: AppSpace.xs,
        children: [for (final o in opts) AppChoiceChip(label: o.$2, selected: o.$1 == value, onTap: () => on(o.$1))],
      );

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: AppSpace.sm, bottom: AppSpace.xs),
        child: Text(s, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.textMedium)),
      );

  HelpExportRequest? _request() {
    switch (_what) {
      case 'page':
        if (widget.pageId == null) return null;
        return HelpExportRequest(what: 'page', ids: [widget.pageId!], role: widget.role ?? _role, format: _format, lang: _lang, asJson: _json);
      case 'flow':
        if (_flowKey == null) return null;
        return HelpExportRequest(what: 'flow', ids: [_flowKey!], role: _role, format: _format, lang: _lang, asJson: _json);
      case 'role':
        return HelpExportRequest(what: 'role', role: _role, format: _format, lang: _lang, asJson: _json);
      default:
        return HelpExportRequest(what: 'all', format: _format, lang: _lang, asJson: _json);
    }
  }

  Future<void> _export() async {
    final req = _request();
    if (req == null) {
      showAppNotice(_t('اختر ما تريد تصديره', 'Choose what to export'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await widget.api.export(req);
      final stamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final base = req.format == 'video_script' ? 'help_video_script' : 'help_guide';
      await widget.save(bytes, '${base}_${req.what}_$stamp.${req.extension}',
          req.extension == 'json' ? 'application/json' : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      if (!mounted) return;
      showAppNotice(_t('تم تجهيز الملف', 'The file is ready'));
      Navigator.pop(context);
    } catch (e) {
      showAppNotice(ApiException.from(e).message, error: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleOpts = [for (final r in helpRoles) (r, helpRoleLabel(r, _ar))];
    return AppSheetContent(
      title: _t('تصدير المساعدة', 'Export help'),
      children: [
        _label(_t('ماذا تصدّر؟', 'What to export')),
        _chips<String>([
          if (widget.pageId != null) ('page', _t('هذه الصفحة', 'This page')),
          ('flow', _t('مسار', 'A flow')),
          ('role', _t('كل مسارات دور', 'All flows of a role')),
          ('all', _t('كل شيء', 'Everything')),
        ], _what, (v) => setState(() => _what = v)),
        if (_what == 'flow' || _what == 'role') ...[
          _label(_t('الدور', 'Role')),
          _chips<String>(roleOpts, _role, (v) => setState(() {
                _role = v;
                _flowKey = null;
              })),
        ],
        if (_what == 'flow') ...[
          _label(_t('المسار', 'Flow')),
          if (_roleFlows.isEmpty)
            Text(_t('لا مسارات لهذا الدور', 'No flows for this role'), style: AppType.body(context).copyWith(color: context.colors.textLight))
          else
            _chips<String?>([for (final f in _roleFlows) (f.key, f.title.of(AppConfig.lang))], _flowKey, (v) => setState(() => _flowKey = v)),
        ],
        _label(_t('الصيغة', 'Format')),
        _chips<String>([('docx', _t('دليل مستخدم (Word)', 'User guide (Word)')), ('video_script', _t('سيناريو فيديو', 'Video script'))], _format,
            (v) => setState(() => _format = v)),
        if (_format == 'video_script') ...[
          _label(_t('ملف السيناريو', 'Script file')),
          _chips<bool>([(false, 'Word'), (true, 'JSON')], _json, (v) => setState(() => _json = v)),
        ],
        _label(_t('اللغة', 'Language')),
        _chips<String>([('ar', 'العربية'), ('en', 'English'), ('both', _t('الاثنتان', 'Both'))], _lang, (v) => setState(() => _lang = v)),
        AppSpace.gapLg,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton.primary(label: _t('تصدير', 'Export'), icon: Icons.download_rounded, busy: _busy, onPressed: _busy ? null : _export),
        ),
      ],
    );
  }
}
