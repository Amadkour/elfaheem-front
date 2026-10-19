// lib/features/shared/data_lab/data_lab_import_sheet.dart
// Import wizard: pick file → match columns → decide what happens to students who are not in the course.
//
//  1. file        .xlsx / .csv (header line + data lines). One column is enough.
//  2. columns     every sheet column is mapped (name / e-mail / phone / ID / an existing column / a new one).
//                 The teacher picks the column that identifies the student ("merge column"). If he does not know
//                 it, he can ask the students to fill it in (a blocking screen on their side).
//  3. unmatched   keep as temporary students, or insert in the system (the missing required values are shown and
//                 can be filled with a constant), or skip.
//  4. done        summary + the temporary passwords of newly created accounts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, showAdminSheet, SheetHeader;

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

Future<void> showImportWizard(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _ImportWizard(p: p));

const _identity = ['name', 'email', 'phone', 'identifier'];

class _ImportWizard extends StatefulWidget {
  const _ImportWizard({required this.p});

  final DataLabProvider p;

  @override
  State<_ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends State<_ImportWizard> {
  final _api = DataLabApi();
  int _step = 0;
  bool _busy = false;
  DlImportPreview? _pv;
  String _mergeOn = '';
  String _policy = 'skip';
  DlImportPlan? _plan;
  DlImportPlan? _result;
  final Map<String, TextEditingController> _fills = {};
  // "ask the students" settings
  String? _reqHeader;
  final _reqLabel = TextEditingController();
  String _reqType = 'text';
  final _reqOptions = TextEditingController();

  bool get _ask => _mergeOn == 'request';

  TextEditingController _fill(String k) => _fills.putIfAbsent(k, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _fills.values) {
      c.dispose();
    }
    _reqLabel.dispose();
    _reqOptions.dispose();
    super.dispose();
  }

  String _err(Object e) => e is ApiException ? e.message : '$e';

  // ── step 0 ────────────────────────────────────────────────────────────────
  Future<void> _pick() async {
    final file = await pickSheetFile();
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final pv = await _api.importPreview(widget.p.courseId, file);
      if (!mounted) return;
      setState(() {
        _pv = pv;
        _mergeOn = pv.suggestedMerge ?? '';
        _step = 1;
      });
    } catch (e) {
      toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── body sent to the server ───────────────────────────────────────────────
  Map<String, dynamic> _body({required bool dry}) {
    final pv = _pv!;
    final mapping = {for (final h in pv.headers) h.header: (_ask && h.header == _reqHeader) ? 'skip' : h.target};
    final fills = <String, dynamic>{};
    _fills.forEach((k, c) {
      if (c.text.trim().isNotEmpty) fills[k] = c.text.trim();
    });
    return {
      'import_id': pv.importId,
      'mapping': mapping,
      'merge_on': _mergeOn,
      'unmatched': _ask ? 'request' : _policy,
      'fills': fills,
      if (_ask)
        'request': {
          'header': _reqHeader,
          'label': _reqLabel.text.trim().isEmpty ? _reqHeader : _reqLabel.text.trim(),
          'input_type': _reqType,
          if (_reqType == 'dropdown')
            'options': _reqOptions.text.split(RegExp('[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        },
      'dry_run': dry,
    };
  }

  // ── step 1 → 2 ────────────────────────────────────────────────────────────
  bool _validateMapping() {
    final pv = _pv!;
    if (pv.headers.every((h) => h.target == 'skip')) {
      toast('dl_err_map_one'.tr, error: true);
      return false;
    }
    if (_mergeOn.isEmpty) {
      toast('dl_err_merge'.tr, error: true);
      return false;
    }
    if (_ask) {
      if (_reqHeader == null) {
        toast('dl_err_request_header'.tr, error: true);
        return false;
      }
      if (_reqType == 'dropdown' && _reqOptions.text.split(RegExp('[,،]')).where((e) => e.trim().isNotEmpty).length < 2) {
        toast('dl_err_options'.tr, error: true);
        return false;
      }
    }
    return true;
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final plan = await _api.importCommit(widget.p.courseId, _body(dry: true));
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (e) {
      toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _goCheck() async {
    if (!_validateMapping()) return;
    setState(() => _step = 2);
    await _check();
  }

  // ── step 2 → 3 ────────────────────────────────────────────────────────────
  bool get _canImport {
    final pl = _plan;
    if (pl == null || _busy) return false;
    if (_policy == 'create_accounts' && !_ask) return pl.missingFields.isEmpty && pl.rowsMissingContact == 0;
    return true;
  }

  Future<void> _commit() async {
    setState(() => _busy = true);
    try {
      final res = await _api.importCommit(widget.p.courseId, _body(dry: false));
      if (!mounted) return;
      await widget.p.load(silent: true);
      setState(() {
        _result = res;
        _step = 3;
      });
    } catch (e) {
      toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titles = ['dl_imp_step_file'.tr, 'dl_imp_step_columns'.tr, 'dl_imp_step_students'.tr, 'dl_imp_step_done'.tr];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_import'.tr),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 5,
                  decoration: BoxDecoration(color: i <= _step ? c.primary : c.divider, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 5),
                Text(titles[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dlText(10.5, w: i == _step ? FontWeight.w800 : FontWeight.w500, c: i == _step ? c.primary : c.textLight)),
              ]),
            ),
            if (i < 3) const SizedBox(width: 6),
          ],
        ]),
      ),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: switch (_step) {
            0 => _stepFile(c),
            1 => _stepColumns(c),
            2 => _stepStudents(c),
            _ => _stepDone(c),
          },
        ),
      ),
    ]);
  }

  // ── step 0 ────────────────────────────────────────────────────────────────
  List<Widget> _stepFile(ThemeConfigProvider c) => [
    DlCard(
      padding: const EdgeInsets.all(22),
      child: Column(children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary.withValues(alpha: 0.10)),
          child: Icon(Icons.upload_file_rounded, size: 36, color: c.primary),
        ),
        const SizedBox(height: 14),
        Text('dl_imp_file_title'.tr, textAlign: TextAlign.center, style: dlText(16, w: FontWeight.w800, c: c.textDark)),
        const SizedBox(height: 6),
        Text('dl_imp_file_sub'.tr, textAlign: TextAlign.center, style: dlText(12.5, c: c.textMedium, h: 1.55)),
        const SizedBox(height: 16),
        DlPrimaryButton(label: 'dl_choose_file'.tr, icon: Icons.folder_open_rounded, busy: _busy, onPressed: _pick),
      ]),
    ),
    const SizedBox(height: 12),
    _Tip(Icons.lightbulb_outline_rounded, '${'dl_imp_limit'.tr} ${widget.p.config.maxImportRows}'),
    _Tip(Icons.table_rows_rounded, 'dl_imp_header_tip'.tr),
  ];

  // ── step 1 ────────────────────────────────────────────────────────────────
  List<Widget> _stepColumns(ThemeConfigProvider c) {
    final pv = _pv!;
    final targets = <String, String>{
      'skip': 'dl_t_skip'.tr,
      'name': 'dl_t_name'.tr,
      'email': 'dl_t_email'.tr,
      'phone': 'dl_t_phone'.tr,
      'identifier': 'dl_t_identifier'.tr,
      for (final col in pv.existingColumns) 'col:${col.key}': col.label,
      'new:number': 'dl_t_new_number'.tr,
      'new:text': 'dl_t_new_text'.tr,
    };
    final keyHeaders = pv.headers.where((h) => _identity.contains(h.target) || h.target.startsWith('col:')).toList();
    return [
      Text('${pv.filename} · ${pv.rows} ${'dl_imp_rows'.tr}', style: dlText(12.5, w: FontWeight.w700, c: c.textMedium)),
      if (pv.shared.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          Text('${'dl_imp_shared'.tr}:', style: dlText(12, c: c.textMedium)),
          for (final s in pv.shared) DlTag(s, c.success, icon: Icons.link_rounded),
        ]),
      ],
      const SizedBox(height: 10),
      for (final h in pv.headers)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: h.target == 'skip' ? c.inputBg : c.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: h.target == 'skip' ? c.divider : c.primary.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.header, maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(13.5, w: FontWeight.w800, c: c.textDark)),
                if (h.sample.isNotEmpty)
                  Text(h.sample.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(11, c: c.textLight)),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: '',
              onSelected: (v) => setState(() {
                h.target = v;
                if (_mergeOn.isNotEmpty && _mergeOn != 'request' && !pv.headers.any((x) => x.target == _mergeOn)) _mergeOn = '';
              }),
              itemBuilder: (_) => [
                for (final e in targets.entries)
                  PopupMenuItem(value: e.key, child: Text(e.value, style: dlText(13, w: e.key == h.target ? FontWeight.w800 : FontWeight.w500))),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.divider)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(targets[h.target] ?? h.target,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: dlText(12, w: FontWeight.w700, c: c.primary)),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textMedium),
                ]),
              ),
            ),
          ]),
        ),
      DlSectionTitle('dl_merge_title'.tr, subtitle: 'dl_merge_sub'.tr),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final h in keyHeaders)
          DlChoiceChip(
            label: h.header,
            icon: Icons.key_rounded,
            selected: _mergeOn == h.target,
            onTap: () => setState(() => _mergeOn = h.target),
          ),
        if (pv.allowStudentRequests)
          DlChoiceChip(
            label: 'dl_merge_unknown'.tr,
            icon: Icons.help_outline_rounded,
            selected: _ask,
            onTap: () => setState(() => _mergeOn = 'request'),
          ),
      ]),
      if (keyHeaders.isEmpty && !_ask) Padding(padding: const EdgeInsets.only(top: 8), child: _Tip(Icons.info_outline_rounded, 'dl_merge_none'.tr)),
      if (_ask) ..._askForm(c, pv),
      const SizedBox(height: 18),
      DlPrimaryButton(label: 'dl_next'.tr, icon: Icons.arrow_forward_rounded, onPressed: _goCheck),
    ];
  }

  List<Widget> _askForm(ThemeConfigProvider c, DlImportPreview pv) => [
    const SizedBox(height: 12),
    DlCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_chat_unread_rounded, color: c.warning, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('dl_ask_explain'.tr, style: dlText(12.5, c: c.textMedium, h: 1.5))),
        ]),
        const SizedBox(height: 12),
        Text('dl_ask_which_column'.tr, style: dlText(12.5, w: FontWeight.w700, c: c.textDark)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final h in pv.headers)
            DlChoiceChip(label: h.header, selected: _reqHeader == h.header, onTap: () => setState(() {
              _reqHeader = h.header;
              if (_reqLabel.text.isEmpty) _reqLabel.text = h.header;
            })),
        ]),
        const SizedBox(height: 12),
        DlField(controller: _reqLabel, label: 'dl_ask_label'.tr),
        Wrap(spacing: 8, children: [
          DlChoiceChip(label: 'dl_ask_text'.tr, icon: Icons.text_fields_rounded, selected: _reqType == 'text', onTap: () => setState(() => _reqType = 'text')),
          DlChoiceChip(label: 'dl_ask_dropdown'.tr, icon: Icons.list_alt_rounded, selected: _reqType == 'dropdown', onTap: () => setState(() => _reqType = 'dropdown')),
        ]),
        if (_reqType == 'dropdown') ...[
          const SizedBox(height: 12),
          DlField(controller: _reqOptions, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
        ],
      ]),
    ),
  ];

  // ── step 2 ────────────────────────────────────────────────────────────────
  List<Widget> _stepStudents(ThemeConfigProvider c) {
    final pv = _pv!;
    final pl = _plan;
    final mapped = pv.headers.where((h) => h.target != 'skip' && !_identity.contains(h.target)).toList();
    return [
      if (_busy && pl == null)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
      else if (pl != null) ...[
        Row(children: [
          Expanded(child: _Count(Icons.check_circle_rounded, c.success, '${pl.matched}', 'dl_plan_matched'.tr)),
          const SizedBox(width: 10),
          Expanded(child: _Count(Icons.person_search_rounded, c.warning, '${pl.unmatched}', 'dl_plan_unmatched'.tr)),
        ]),
        if (pl.newColumns.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            Text('${'dl_plan_new_columns'.tr}:', style: dlText(12, c: c.textMedium)),
            for (final n in pl.newColumns) DlTag(n, c.purple, icon: Icons.add_chart_rounded),
          ]),
        ),
        if (pl.emptyKey + pl.ambiguous > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _Tip(Icons.warning_amber_rounded, '${pl.emptyKey + pl.ambiguous} ${'dl_plan_skipped_rows'.tr}', color: c.warning),
          ),
      ],
      if (!_ask) ...[
        DlSectionTitle('dl_unmatched_title'.tr, subtitle: 'dl_unmatched_sub'.tr),
        _PolicyTile(
          icon: Icons.hourglass_bottom_rounded,
          title: 'dl_policy_temp'.tr,
          sub: 'dl_policy_temp_sub'.tr,
          selected: _policy == 'temporary',
          onTap: () => setState(() {
            _policy = 'temporary';
            _check();
          }),
        ),
        if (pv.allowCreateAccounts)
          _PolicyTile(
            icon: Icons.person_add_alt_1_rounded,
            title: 'dl_policy_accounts'.tr,
            sub: 'dl_policy_accounts_sub'.tr,
            selected: _policy == 'create_accounts',
            onTap: () => setState(() {
              _policy = 'create_accounts';
              _check();
            }),
          ),
        _PolicyTile(
          icon: Icons.block_rounded,
          title: 'dl_policy_skip'.tr,
          sub: 'dl_policy_skip_sub'.tr,
          selected: _policy == 'skip',
          onTap: () => setState(() {
            _policy = 'skip';
            _check();
          }),
        ),
      ] else
        Padding(padding: const EdgeInsets.only(top: 12), child: _Tip(Icons.mark_chat_unread_rounded, 'dl_policy_request_note'.tr, color: c.warning)),
      // ── what is missing to insert students in the system ──────────────────
      if (_policy == 'create_accounts' && !_ask && pl != null && (pl.missingFields.isNotEmpty || pl.rowsMissingContact > 0 || _fills.isNotEmpty)) ...[
        DlSectionTitle('dl_missing_title'.tr, subtitle: 'dl_missing_sub'.tr),
        if (pl.needsName) DlField(controller: _fill('name'), label: 'dl_fill_name'.tr, hint: 'dl_fill_name_hint'.tr),
        if (pl.needsContact || pl.rowsMissingContact > 0)
          DlField(controller: _fill('identifier_prefix'), label: 'dl_fill_prefix'.tr, hint: 'dl_fill_prefix_hint'.tr, ltr: true),
        _Tip(Icons.info_outline_rounded, 'dl_login_note'.tr),
      ],
      if (mapped.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('dl_fill_cells'.tr, style: dlText(13, w: FontWeight.w800, c: c.textDark)),
            subtitle: Text('dl_fill_cells_sub'.tr, style: dlText(11, c: c.textMedium)),
            children: [
              const SizedBox(height: 6),
              for (final h in mapped) DlField(controller: _fill(h.header), label: h.header, hint: 'dl_fill_value'.tr),
            ],
          ),
        ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              side: BorderSide(color: c.divider),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _busy ? null : _check,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('dl_check_again'.tr, style: dlText(13, w: FontWeight.w700, c: c.textDark)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: DlPrimaryButton(label: 'dl_import_now'.tr, icon: Icons.download_done_rounded, busy: _busy, onPressed: _canImport ? _commit : null)),
      ]),
      TextButton(onPressed: () => setState(() => _step = 1), child: Text('dl_back'.tr)),
    ];
  }

  // ── step 3 ────────────────────────────────────────────────────────────────
  List<Widget> _stepDone(ThemeConfigProvider c) {
    final r = _result!;
    final creds = r.credentials;
    return [
      Center(
        child: Container(
          width: 84,
          height: 84,
          margin: const EdgeInsets.only(top: 6, bottom: 10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.success.withValues(alpha: 0.12)),
          child: Icon(Icons.celebration_rounded, size: 40, color: c.success),
        ),
      ),
      Text('dl_done_title'.tr, textAlign: TextAlign.center, style: dlText(18, w: FontWeight.w800, c: c.textDark)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _Count(Icons.check_circle_rounded, c.success, '${r.matched}', 'dl_plan_matched'.tr)),
        const SizedBox(width: 10),
        Expanded(
          child: _Count(Icons.person_add_alt_1_rounded, c.primary,
              '${r.willCreateAccounts + r.willCreateTemp + r.willStage}', 'dl_done_added'.tr),
        ),
      ]),
      if (r.raw['will_stage'] != null && r.willStage > 0)
        Padding(padding: const EdgeInsets.only(top: 12), child: _Tip(Icons.mark_chat_unread_rounded, 'dl_done_request_sent'.tr, color: c.warning)),
      if (creds.isNotEmpty) ...[
        DlSectionTitle('dl_done_accounts'.tr, subtitle: 'dl_done_accounts_sub'.tr, trailing: TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: creds.map((e) => '${e['name']}\t${e['login']}\t${e['password']}').join('\n')));
            toast('dl_copied'.tr);
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: Text('dl_copy_all'.tr),
        )),
        for (final cr in creds)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.divider)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${cr['name']}', style: dlText(13, w: FontWeight.w800, c: c.textDark)),
                  Text('${cr['login']}', style: dlText(11.5, c: c.textMedium), textDirection: TextDirection.ltr),
                ]),
              ),
              SelectableText('${cr['password']}', style: dlText(13, w: FontWeight.w800, c: c.primary), textDirection: TextDirection.ltr),
              const SizedBox(width: 8),
              if (cr['emailed'] == true) Icon(Icons.mark_email_read_rounded, size: 18, color: c.success),
            ]),
          ),
      ],
      const SizedBox(height: 14),
      DlPrimaryButton(label: 'dl_done'.tr, icon: Icons.check_rounded, onPressed: () => Navigator.pop(context)),
    ];
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text, {this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.textMedium;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: col),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: dlText(12, c: col, h: 1.5))),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.icon, this.color, this.value, this.label);

  final IconData icon;
  final Color color;
  final String value, label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: dlText(20, w: FontWeight.w800, c: color)),
          Text(label, maxLines: 2, style: dlText(11, c: context.colors.textMedium, h: 1.3)),
        ]),
      ),
    ]),
  );
}

class _PolicyTile extends StatelessWidget {
  const _PolicyTile({required this.icon, required this.title, required this.sub, required this.selected, required this.onTap});

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
