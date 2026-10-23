// lib/features/teacher/data_lab/data_lab_export_sheet.dart
// Export: where it goes, the file type, and the columns.
//   • download            the file to this device — a real "Save / Download" (browser download on the web, the
//                         Downloads folder on a computer, "Save to Files / device" on a phone) + Share
//   • e-mail me           summary in the mail body + the sheet attached
//   • e-mail students     every student receives his own line (only columns that are visible to students)
//   • students' profile   publish the chosen columns on the students' analytics profile + notify them
// The file looks like the sheet: pinned columns first (and always included), the same order, widths, colours,
// highlight rules, colour scale, averages band, alignment and the app theme.
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

String _tr(String key, String fallback) => dlTr(key, fallback);

Future<void> showExportSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _ExportSheet(p: p, outer: context));

String _hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.p, required this.outer});

  final DataLabProvider p;
  final BuildContext outer; // still alive after this sheet closes (for the "file ready" sheet)

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  final _api = DataLabApi();
  final _emailTo = TextEditingController();
  final _note = TextEditingController();
  late final Set<String> _cols;
  final Set<String> _identity = {};
  late String _format;
  String _delivery = 'download';
  bool _busy = false;

  DataLabProvider get p => widget.p;

  List<String> get _pinned => p.frozenKeys;

  @override
  void initState() {
    super.initState();
    final pinned = _pinned.toSet();
    _cols = p.columns.where((c) => !c.isHidden && !pinned.contains(c.key)).map((c) => c.key).toSet();
    _format = p.config.exportFormats.contains('xlsx') ? 'xlsx' : p.config.exportFormats.first;
  }

  @override
  void dispose() {
    _emailTo.dispose();
    _note.dispose();
    super.dispose();
  }

  Map<String, String> _theme(BuildContext context) {
    final c = context.colors;
    return {
      'primary': _hexOf(c.primary),
      'success': _hexOf(c.success),
      'warning': _hexOf(c.warning),
      'danger': _hexOf(c.danger),
      'purple': _hexOf(c.purple),
      'accent': _hexOf(c.accent),
      'accent2': _hexOf(c.accent2),
      // a file is printed / opened on white: always the light-mode text colours
      'text': '#1F2937',
      'muted': '#6B7280',
    };
  }

  Future<void> _go() async {
    final pinnedData = _pinned.where((k) => !DataLabProvider.isIdentity(k)).toList();
    if (_cols.isEmpty && pinnedData.isEmpty) return toast('dl_err_pick_columns'.tr, error: true);
    setState(() => _busy = true);
    try {
      final keys = [..._pinned, ...p.columns.where((c) => _cols.contains(c.key)).map((c) => c.key)];
      final res = await _api.export(p.courseId, {
        'columns': [...pinnedData, ...p.columns.where((c) => _cols.contains(c.key)).map((c) => c.key)],
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
        // the same LOOK as the sheet
        'pinned': _pinned,
        'identity': _identity.toList(),
        'theme': _theme(context),
        'widths': {for (final k in keys) k: p.widthOf(k)},
        'avg_place': p.avgPlace,
        'avg_highlight': p.avgHighlight,
        'align': p.sheetAlign,
        'font': ?p.sheetFont,
        'size': p.sheetSize,
      });
      if (!mounted) return;
      switch (_delivery) {
        case 'download':
          final file = _api.fileOf(res);
          final outer = widget.outer;
          Navigator.pop(context);
          if (outer.mounted) await showFileReadySheet(outer, file);
          return;
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
    final pinned = _pinned;
    final all = p.columns.where((x) => !x.isHidden && !pinned.contains(x.key)).toList();
    final forStudents = _delivery == 'student_email' || _delivery == 'student_profile';
    final extraIdentity = [
      for (final k in const [DataLabProvider.idIdentifier, DataLabProvider.idEmail, DataLabProvider.idPhone])
        if (!pinned.contains(k)) k,
    ];
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
            _Dest(Icons.download_rounded, 'dl_exp_download'.tr, _tr('dl_exp_download_sub2', 'Save the file on this device, or share it.'),
                _delivery == 'download', () => setState(() => _delivery = 'download')),
            if (cfg.allowEmailExport)
              _Dest(Icons.forward_to_inbox_rounded, 'dl_exp_email'.tr, 'dl_exp_email_sub'.tr, _delivery == 'email', () => setState(() => _delivery = 'email')),
            if (cfg.allowEmailExport)
              _Dest(Icons.groups_rounded, 'dl_exp_students'.tr, 'dl_exp_students_sub'.tr, _delivery == 'student_email', () => setState(() => _delivery = 'student_email')),
            _Dest(Icons.badge_rounded, 'dl_exp_profile'.tr, 'dl_exp_profile_sub'.tr, _delivery == 'student_profile', () => setState(() => _delivery = 'student_profile')),
            if (_delivery == 'email') ...[
              const SizedBox(height: 8),
              DlField(controller: _emailTo, label: 'dl_exp_email_to'.tr, hint: 'dl_exp_email_to_hint'.tr, keyboard: TextInputType.emailAddress, ltr: true),
            ],
            if (_delivery != 'download') DlField(controller: _note, label: 'dl_exp_note'.tr, maxLines: 2),
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
              if (_format != 'csv')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.palette_rounded, size: 15, color: c.accent2),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_tr('dl_exp_same_look', 'Same look as your sheet: colours, highlights, averages, widths and pinned columns.'),
                          style: dlText(11.5, c: c.textMedium, h: 1.4)),
                    ),
                  ]),
                ),
            ],
            // ── always included: the pinned columns ──
            if (!forStudents) ...[
              DlSectionTitle(_tr('dl_exp_pinned', 'Always included (pinned)'),
                  subtitle: _tr('dl_exp_pinned_sub', 'Pinned columns open the file, in their order.')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final k in pinned)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.primary.withValues(alpha: 0.35)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.push_pin_rounded, size: 14, color: c.primary),
                      const SizedBox(width: 6),
                      Text(p.frozenLabel(k, (x) => x.tr), style: dlText(12.5, w: FontWeight.w800, c: c.primary)),
                      const SizedBox(width: 6),
                      Icon(Icons.lock_rounded, size: 12, color: c.primary.withValues(alpha: 0.6)),
                    ]),
                  ),
              ]),
              if (extraIdentity.isNotEmpty) ...[
                DlSectionTitle(_tr('dl_exp_more_details', 'More student details')),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in extraIdentity)
                    DlChoiceChip(
                      label: p.frozenLabel(k, (x) => x.tr),
                      icon: k == DataLabProvider.idEmail
                          ? Icons.alternate_email_rounded
                          : (k == DataLabProvider.idPhone ? Icons.phone_rounded : Icons.badge_rounded),
                      selected: _identity.contains(k),
                      onTap: () => setState(() => _identity.contains(k) ? _identity.remove(k) : _identity.add(k)),
                    ),
                ]),
              ],
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
                'download' => _tr('dl_exp_btn_prepare', 'Prepare the file'),
                'email' => 'dl_exp_btn_email'.tr,
                'student_email' => 'dl_exp_btn_students'.tr,
                _ => 'dl_exp_btn_publish'.tr,
              },
              icon: _delivery == 'download' ? Icons.file_download_rounded : Icons.send_rounded,
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

// ─────────────────────────────────────────────────────────────────────────────
// File ready: Save / Download · Share · (desktop) Open · Show in folder
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showFileReadySheet(BuildContext context, DlExportFile file) => showModalBottomSheet<void>(
      useSafeArea: true,
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  constraints: const BoxConstraints(maxWidth: 520),
  builder: (_) => Directionality(textDirection: pageDirection, child: _FileReady(file: file)),
);

class _FileReady extends StatefulWidget {
  const _FileReady({required this.file});

  final DlExportFile file;

  @override
  State<_FileReady> createState() => _FileReadyState();
}

class _FileReadyState extends State<_FileReady> {
  bool _saving = false;
  String? _savedPath; // desktop: the full path · web: the file name

  DlExportFile get f => widget.file;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final path = await f.save();
      if (!mounted) return;
      setState(() => _savedPath = path);
      if (path != null) toast(_tr('dl_file_saved', 'Saved to your Downloads'));
    } catch (e) {
      toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, kind) = switch (f.extension) {
      'pdf' => (Icons.picture_as_pdf_rounded, c.danger, 'PDF'),
      'csv' => (Icons.description_rounded, c.accent2, 'CSV'),
      _ => (Icons.table_view_rounded, c.success, 'Excel'),
    };
    final direct = DlExportFile.canSaveDirectly;
    final desktopPath = _savedPath != null && (_savedPath!.contains('/') || _savedPath!.contains(r'\'));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: c.divider, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 18),
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(24)),
                child: Icon(_savedPath != null ? Icons.check_circle_rounded : icon, size: 40, color: _savedPath != null ? c.success : color),
              ),
              const SizedBox(height: 12),
              Text(_savedPath != null ? _tr('dl_file_saved_title', 'Saved') : _tr('dl_file_ready', 'Your file is ready'),
                  style: dlText(18, w: FontWeight.w800, c: c.textDark)),
              const SizedBox(height: 4),
              Text(f.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: dlText(13, w: FontWeight.w700, c: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(alignment: WrapAlignment.center, spacing: 6, children: [
                DlTag(kind, color),
                DlTag(f.sizeLabel, c.textMedium),
                if (f.rows > 0) DlTag('${f.rows} ${'dl_students'.tr}', c.primary),
              ]),
              if (desktopPath) ...[
                const SizedBox(height: 10),
                Text(_savedPath!, textAlign: TextAlign.center, textDirection: TextDirection.ltr, style: dlText(11, c: c.textLight)),
              ],
              const SizedBox(height: 18),
              DlPrimaryButton(
                label: direct
                    ? (_savedPath != null ? _tr('dl_file_save_again', 'Save again') : _tr('dl_file_save', 'Save / Download'))
                    : _tr('dl_file_save_phone', 'Save to device / Open with…'),
                icon: Icons.file_download_rounded,
                busy: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: BorderSide(color: c.divider),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => f.share().catchError((Object e) => toast('$e', error: true)),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(_tr('dl_file_share', 'Share'), style: dlText(13, w: FontWeight.w700, c: c.textDark)),
                  ),
                ),
                if (desktopPath) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(color: c.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => DlExportFile.open(_savedPath!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(_tr('dl_file_open', 'Open'), style: dlText(13, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(color: c.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => DlExportFile.reveal(_savedPath!),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(_tr('dl_file_folder', 'Folder'), style: dlText(13, w: FontWeight.w700, c: c.textDark)),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
