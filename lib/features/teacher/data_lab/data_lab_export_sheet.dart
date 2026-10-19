// lib/features/teacher/data_lab/data_lab_export_sheet.dart
// Export: choose the columns (all of them are listed), the file type, and where it goes —
//   • download            the file straight to this device (share sheet / browser download)
//   • e-mail me           summary in the mail body + the sheet attached (Excel or PDF …)
//   • e-mail students     every student receives his own line (only columns that are visible to students)
//   • students' profile   publish the chosen columns on the students' analytics profile + notify them
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

Future<void> showExportSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _ExportSheet(p: p));

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.p});

  final DataLabProvider p;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final _api = DataLabApi();
  final _emailTo = TextEditingController();
  final _note = TextEditingController();
  late final Set<String> _cols;
  late String _format;
  String _delivery = 'download';
  bool _busy = false;

  DataLabProvider get p => widget.p;

  @override
  void initState() {
    super.initState();
    _cols = p.columns.where((c) => !c.isHidden).map((c) => c.key).toSet();
    _format = p.config.exportFormats.contains('xlsx') ? 'xlsx' : p.config.exportFormats.first;
  }

  @override
  void dispose() {
    _emailTo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_cols.isEmpty) return toast('dl_err_pick_columns'.tr, error: true);
    setState(() => _busy = true);
    try {
      final ordered = p.columns.where((c) => _cols.contains(c.key)).map((c) => c.key).toList();
      final res = await _api.export(p.courseId, {
        'columns': ordered,
        'format': _format,
        'delivery': _delivery,
        if (p.selected.isNotEmpty) 'row_ids': p.selected.toList(),
        if (_delivery == 'email' && _emailTo.text.trim().isNotEmpty) 'email_to': _emailTo.text.trim(),
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
        'lang': AppConfig.lang,
        // the same lines, in the same order, as on screen
        if (p.search.trim().isNotEmpty) 'search': p.search.trim(),
        'sort': ?p.sort,
        'desc': p.desc,
      });
      if (!mounted) return;
      switch (_delivery) {
        case 'download':
          await _api.saveDownloaded(res);
          toast('dl_exp_downloaded'.tr);
        case 'email':
          toast('${'dl_exp_email_queued'.tr} ${res['to'] ?? ''}');
        case 'student_email':
          toast('${res['queued'] ?? 0} ${'dl_exp_students_queued'.tr}');
        default:
          toast('${res['students'] ?? 0} ${'dl_exp_published'.tr}');
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cfg = p.config;
    final all = p.columns.where((x) => !x.isHidden).toList();
    final forStudents = _delivery == 'student_email' || _delivery == 'student_profile';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_export'.tr),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            if (p.selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DlTag('${'dl_exp_only'.tr} ${p.selected.length}', c.primary, icon: Icons.checklist_rounded),
              )
            else if (p.search.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: DlBanner(
                  icon: Icons.filter_alt_rounded,
                  text: '${dlTr('dl_exp_filtered', 'Only the lines that match your search')}: “${p.search.trim()}”',
                ),
              ),
            DlSectionTitle('dl_exp_where'.tr),
            _Dest(Icons.download_rounded, 'dl_exp_download'.tr, 'dl_exp_download_sub'.tr, _delivery == 'download', () => setState(() => _delivery = 'download')),
            if (cfg.allowEmailExport)
              _Dest(Icons.forward_to_inbox_rounded, 'dl_exp_email'.tr, 'dl_exp_email_sub'.tr, _delivery == 'email', () => setState(() => _delivery = 'email')),
            if (cfg.allowEmailExport)
              _Dest(Icons.groups_rounded, 'dl_exp_students'.tr, 'dl_exp_students_sub'.tr, _delivery == 'student_email', () => setState(() => _delivery = 'student_email')),
            _Dest(Icons.badge_rounded, 'dl_exp_profile'.tr, 'dl_exp_profile_sub'.tr, _delivery == 'student_profile', () => setState(() => _delivery = 'student_profile')),
            if (_delivery == 'email') ...[
              const SizedBox(height: 8),
              DlField(controller: _emailTo, label: 'dl_exp_email_to'.tr, hint: 'dl_exp_email_to_hint'.tr, keyboard: TextInputType.emailAddress, ltr: true),
            ],
            if (_delivery != 'download')
              DlField(controller: _note, label: 'dl_exp_note'.tr, maxLines: 2),
            if (_delivery != 'student_profile') ...[
              DlSectionTitle('dl_exp_format'.tr),
              Wrap(spacing: 8, children: [
                for (final f in cfg.exportFormats)
                  DlChoiceChip(
                    label: f == 'xlsx' ? 'Excel' : f.toUpperCase(),
                    icon: f == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.table_view_rounded,
                    selected: _format == f,
                    onTap: () => setState(() => _format = f),
                  ),
              ]),
            ],
            DlSectionTitle('dl_exp_columns'.tr,
                subtitle: forStudents ? 'dl_exp_columns_students'.tr : null,
                trailing: TextButton(
                  onPressed: () => setState(() => _cols.length == all.length ? _cols.clear() : _cols.addAll(all.map((e) => e.key))),
                  child: Text(_cols.length == all.length ? 'dl_none'.tr : 'dl_all'.tr),
                )),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final col in all)
                DlChoiceChip(
                  label: col.label,
                  icon: col.isCalculated ? Icons.functions_rounded : null,
                  selected: _cols.contains(col.key),
                  onTap: () => setState(() => _cols.contains(col.key) ? _cols.remove(col.key) : _cols.add(col.key)),
                ),
            ]),
            const SizedBox(height: 20),
            DlPrimaryButton(
              label: switch (_delivery) {
                'download' => 'dl_exp_btn_download'.tr,
                'email' => 'dl_exp_btn_email'.tr,
                'student_email' => 'dl_exp_btn_students'.tr,
                _ => 'dl_exp_btn_publish'.tr,
              },
              icon: Icons.send_rounded,
              busy: _busy,
              onPressed: _go,
            ),
          ],
        ),
      ),
    ]);
  }
}

class _Dest extends StatelessWidget {
  const _Dest(this.icon, this.title, this.sub, this.selected, this.onTap);

  final IconData icon;
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? c.primary.withValues(alpha: 0.08) : c.inputBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? c.primary : c.textMedium),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
                Text(sub, style: dlText(11.5, c: c.textMedium, h: 1.4)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: c.primary),
          ]),
        ),
      ),
    );
  }
}
