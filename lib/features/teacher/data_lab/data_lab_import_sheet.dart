// lib/features/teacher/data_lab/data_lab_import_sheet.dart
// Import wizard — four steps with a fixed Back / Next bar (the step dots go back too):
//  1. file        .xlsx / .csv (header line + data lines)
//  2. columns     every sheet column is matched to: a student detail (name / e-mail / phone / ID), ANY column of the
//                 sheet (custom, built-in or formula number columns, hidden ones too), a new column — or skipped.
//                 Then the column that identifies the student (or: ask the students to fill it in).
//  3. students    what happens to the lines that are not in the course:
//                   keep in the sheet only · add them to the course · ignore
//                 "Add them to the course": platform users are enrolled and notified; new students get an account
//                 (invitation e-mail when there is an e-mail, the teacher hands over the login when there is only a
//                 phone). Lines with neither are listed here: add an e-mail / phone, keep in the sheet only, or
//                 ignore — every other line is imported meanwhile.
//  4. done        summary, the logins of the new accounts, lines that need a look.
library;

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, showAdminSheet, SheetHeader;
import 'package:share_plus/share_plus.dart';

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/app_kit.dart' show showAppSideSheet;
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;

String _tr(String key, String fallback) => dlTr(key, fallback);

Future<void> showImportWizard(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _ImportWizard(p: p));

const _identity = ['name', 'email', 'phone', 'identifier'];

/// The teacher's decision for one line that has neither e-mail nor phone.
class _Fix {
  _Fix(Map<String, dynamic> line)
      : row = (line['row'] as num).toInt(),
        name = '${line['name'] ?? ''}',
        identifier = '${line['identifier'] ?? ''}',
        email = TextEditingController(text: '${line['email'] ?? ''}'),
        phone = TextEditingController(text: '${line['phone'] ?? ''}');

  final int row;
  final String name, identifier;
  final TextEditingController email, phone;
  String? action; // add | sheet_only | skip

  bool get hasContact => email.text.trim().isNotEmpty || phone.text.trim().isNotEmpty;
  bool get decided => action == 'sheet_only' || action == 'skip' || (action == 'add' && hasContact);

  Map<String, dynamic>? toJson() => switch (action) {
    'add' when hasContact => {
      'action': 'add',
      if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
      if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
    },
    'sheet_only' || 'skip' => {'action': action},
    _ => null,
  };

  void dispose() {
    email.dispose();
    phone.dispose();
  }
}

class _ImportWizard extends StatefulWidget {
  const _ImportWizard({required this.p});

  final DataLabProvider p;

  @override
  State<_ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends State<_ImportWizard> {
  final _api = DataLabApi();
  int _step = 0, _reached = 0;
  bool _busy = false;
  DlImportPreview? _pv;
  String _mergeOn = '';
  String _policy = 'temporary';
  DlImportPlan? _plan;
  DlImportPlan? _result;
  final Map<String, TextEditingController> _fills = {};
  final Map<int, _Fix> _fixes = {};
  Timer? _recheck;
  // "ask the students" settings
  String? _reqHeader;
  final _reqLabel = TextEditingController();
  String _reqType = 'text';
  final _reqOptions = TextEditingController();

  bool get _ask => _mergeOn == 'request';

  TextEditingController _fill(String k) => _fills.putIfAbsent(k, () => TextEditingController());

  @override
  void dispose() {
    _recheck?.cancel();
    for (final c in _fills.values) {
      c.dispose();
    }
    for (final f in _fixes.values) {
      f.dispose();
    }
    _reqLabel.dispose();
    _reqOptions.dispose();
    super.dispose();
  }

  String _err(Object e) => apiErrorText(ApiException.from(e));

  void _goTo(int step) => setState(() {
    _step = step;
    if (step > _reached) _reached = step;
  });

  // ── step 1: the file ───────────────────────────────────────────────────────
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
        _plan = null;
        _reached = 1;
        for (final f in _fixes.values) {
          f.dispose();
        }
        _fixes.clear();
      });
      _goTo(1);
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
      if (!_ask && _policy == 'create_accounts')
        'fixes': {for (final f in _fixes.values) if (f.toJson() != null) '${f.row}': f.toJson()},
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

  // ── step 2 → 3 ─────────────────────────────────────────────────────────────
  bool _validateMapping() {
    final pv = _pv!;
    if (pv.headers.every((h) => h.target == 'skip') && !_ask) {
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
    if (_pv == null) return;
    setState(() => _busy = true);
    try {
      final plan = await _api.importCommit(widget.p.courseId, _body(dry: true));
      if (!mounted) return;
      setState(() {
        _plan = plan;
        // keep what the teacher already typed / chose for the lines without a contact
        for (final line in plan.needsContactLines) {
          final row = (line['row'] as num).toInt();
          _fixes.putIfAbsent(row, () => _Fix(line));
        }
      });
    } catch (e) {
      toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _checkSoon() {
    _recheck?.cancel();
    _recheck = Timer(const Duration(milliseconds: 800), _check);
  }

  void _setPolicy(String v) {
    if (_policy == v) return;
    setState(() => _policy = v);
    _check();
  }

  /// Lines without a contact that the teacher did not decide on yet.
  List<_Fix> get _undecided {
    final open = {for (final l in _plan?.needsContactLines ?? const <Map<String, dynamic>>[]) (l['row'] as num).toInt()};
    return _fixes.values.where((f) => !f.decided && (open.contains(f.row) || f.action == 'add')).toList();
  }

  Future<void> _commit() async {
    if (!_ask && _policy == 'create_accounts' && _undecided.isNotEmpty) {
      final go = await confirm(context,
          message: '${_undecided.length} ${_tr('dl_fix_undecided_q', 'lines without e-mail or phone have no decision yet. They will be left out — continue?')}');
      if (!go || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final res = await _api.importCommit(widget.p.courseId, _body(dry: false));
      if (!mounted) return;
      await widget.p.load(silent: true);
      setState(() => _result = res);
      _goTo(3);
    } catch (e) {
      toast(_err(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── navigation ─────────────────────────────────────────────────────────────
  Future<void> _next() async {
    switch (_step) {
      case 0:
        if (_pv == null) return _pick();
        _goTo(1);
      case 1:
        if (!_validateMapping()) return;
        _goTo(2);
        await _check();
      case 2:
        await _commit();
      default:
        Navigator.pop(context);
    }
  }

  void _back() {
    if (_step > 0 && _step < 3) _goTo(_step - 1);
  }

  bool get _canNext => switch (_step) {
    0 => !_busy,
    1 => !_busy,
    2 => !_busy && _plan != null && !(_policy == 'create_accounts' && !_ask && (_plan?.missingFields.isNotEmpty ?? false) && _fills['name']?.text.trim().isEmpty != false),
    _ => true,
  };

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titles = ['dl_imp_step_file'.tr, 'dl_imp_step_columns'.tr, 'dl_imp_step_students'.tr, 'dl_imp_step_done'.tr];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_import'.tr),
      // step dots: tap a step already reached to go back to it
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, AppSpace.lg, 8),
        child: Row(children: [
          for (var i = 0; i < 4; i++) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: (i <= _reached && i != _step && _step != 3 && i < 3 && (i == 0 || _pv != null)) ? () => _goTo(i) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 5,
                      decoration: BoxDecoration(
                        color: i <= _step ? c.primary : (i <= _reached ? c.primary.withValues(alpha: 0.35) : c.divider),
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                    ),
                    const SizedBox(height: AppSpace.xxs),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (i < _step || (i < _reached && i != _step))
                        Padding(padding: const EdgeInsetsDirectional.only(end: 3), child: Icon(Icons.check_rounded, size: 12, color: c.primary)),
                      Flexible(
                        child: Text(titles[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.overline(context).copyWith(color: i == _step ? c.primary : c.textLight)),
                      ),
                    ]),
                  ]),
                ),
              ),
            ),
            if (i < 3) const SizedBox(width: AppSpace.xs),
          ],
        ]),
      ),
      Flexible(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: ListView(
            key: ValueKey(_step),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, AppSpace.xs, AppSpace.lg, 16),
            children: switch (_step) {
              0 => _stepFile(c),
              1 => _stepColumns(c),
              2 => _stepStudents(c),
              _ => _stepDone(c),
            },
          ),
        ),
      ),
      _navBar(c),
    ]);
  }

  Widget _navBar(ThemeConfigProvider c) {
    final label = switch (_step) {
      0 => _pv == null ? 'dl_choose_file'.tr : 'dl_next'.tr,
      1 => 'dl_next'.tr,
      2 => 'dl_import_now'.tr,
      _ => 'dl_done'.tr,
    };
    final icon = switch (_step) {
      0 => _pv == null ? Icons.folder_open_rounded : Icons.arrow_forward_rounded,
      1 => Icons.arrow_forward_rounded,
      2 => Icons.download_done_rounded,
      _ => Icons.check_rounded,
    };
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
      child: Row(children: [
        if (_step > 0 && _step < 3) ...[
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.divider),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
              ),
              onPressed: _busy ? null : _back,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),   // auto-mirrored in RTL
              label: Text('dl_back'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
        if (_step == 2)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: SizedBox(
              height: 50,
              width: 50,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: c.divider),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                ),
                onPressed: _busy ? null : _check,
                child: Tooltip(message: 'dl_check_again'.tr, child: Icon(Icons.refresh_rounded, color: c.textMedium)),
              ),
            ),
          ),
        Expanded(child: DlPrimaryButton(label: label, icon: icon, busy: _busy, onPressed: _canNext ? _next : null)),
      ]),
    );
  }

  // ── step 1 ─────────────────────────────────────────────────────────────────
  List<Widget> _stepFile(ThemeConfigProvider c) => [
    DlCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      onTap: _busy ? null : _pick,
      child: Column(children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(shape: BoxShape.circle, color: (_pv == null ? c.primary : c.success).withValues(alpha: 0.10)),
          child: Icon(_pv == null ? Icons.upload_file_rounded : Icons.task_rounded, size: 36, color: _pv == null ? c.primary : c.success),
        ),
        const SizedBox(height: AppSpace.md),
        Text(_pv == null ? 'dl_imp_file_title'.tr : _pv!.filename,
            textAlign: TextAlign.center, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Text(_pv == null ? 'dl_imp_file_sub'.tr : '${_pv!.rows} ${'dl_imp_rows'.tr} · ${_pv!.headers.length} ${_tr('dl_imp_cols', 'columns')}',
            textAlign: TextAlign.center, style: AppType.meta(context).copyWith(color: c.textMedium)),
        if (_pv != null) ...[
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.swap_horiz_rounded, size: 18), label: Text(_tr('dl_imp_other_file', 'Choose another file'))),
        ],
      ]),
    ),
    const SizedBox(height: AppSpace.sm),
    _Tip(Icons.lightbulb_outline_rounded, '${'dl_imp_limit'.tr} ${widget.p.config.maxImportRows}'),
    _Tip(Icons.table_rows_rounded, 'dl_imp_header_tip'.tr),
  ];

  // ── step 2 ─────────────────────────────────────────────────────────────────
  String _targetLabel(String t) {
    final pv = _pv!;
    if (t == 'skip') return 'dl_t_skip'.tr;
    if (_identity.contains(t)) return 'dl_t_$t'.tr;
    if (t == 'new:number') return 'dl_t_new_number'.tr;
    if (t == 'new:text') return 'dl_t_new_text'.tr;
    if (t.startsWith('col:')) {
      final k = t.substring(4);
      return pv.existingColumns.where((c) => c.key == k).firstOrNull?.label ?? k;
    }
    return t;
  }

  Future<void> _chooseTarget(DlImportHeader h) async {
    final c = context.colors;
    final pv = _pv!;
    final cols = pv.existingColumns;
    final picked = await showAppSideSheet<String>(
      context,
      withCloseBar: true,
      builder: (ctx) {
        Widget item(String value, IconData icon, String label, {String? sub, Color? color, bool enabled = true}) {
          final on = h.target == value;
          return ListTile(
            enabled: enabled,
            dense: true,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            selected: on,
            selectedTileColor: c.primaryWash,
            leading: Icon(icon, color: enabled ? (color ?? c.primary) : c.textLight, size: 20),
            title: Text(label, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: enabled ? c.textDark : c.textLight)),
            subtitle: sub == null ? null : Text(sub, style: AppType.meta(context).copyWith(color: c.textLight)),
            trailing: on ? Icon(Icons.check_circle_rounded, color: c.primary) : null,
            onTap: () => Navigator.pop(ctx, value),
          );
        }

        Widget group(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(12, AppSpace.sm, AppSpace.sm, 4),
          child: Text(t, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
        );

        return Directionality(
          textDirection: pageDirection,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: Material(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(AppRadius.block),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, AppSpace.sm, AppSpace.xs, 12), children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, AppSpace.sm, 6),
                      child: Text('“${h.header}” →', style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                    ),
                    item('skip', Icons.block_rounded, 'dl_t_skip'.tr, color: c.textMedium),
                    group(_tr('dl_t_group_student', 'Student details')),
                    item('name', Icons.person_rounded, 'dl_t_name'.tr),
                    item('email', Icons.alternate_email_rounded, 'dl_t_email'.tr),
                    item('phone', Icons.phone_rounded, 'dl_t_phone'.tr),
                    item('identifier', Icons.badge_rounded, 'dl_t_identifier'.tr),
                    if (cols.isNotEmpty) group(_tr('dl_t_group_columns', 'Columns of the sheet')),
                    for (final col in cols)
                      item(
                        'col:${col.key}',
                        col.isCalculated ? Icons.functions_rounded : (col.isBuiltin ? Icons.auto_awesome_rounded : Icons.view_column_rounded),
                        col.label,
                        color: col.isCalculated ? c.purple : (col.isBuiltin ? c.accent2 : c.primary),
                        enabled: !col.isLocked,
                        sub: [
                          if (!col.isCustom) _tr('dl_t_override', 'replaces the automatic value'),
                          if (col.isHidden) _tr('dl_t_hidden', 'hidden'),
                          if (col.isLocked) _tr('dl_locked', 'Locked'),
                          if (col.isNumber) '${_tr('dl_full_mark', 'Full mark')} ${dlFmt(col.maxValue)}',
                        ].join(' · ').let((s) => s.isEmpty ? null : s),
                      ),
                    group(_tr('dl_t_group_new', 'New column')),
                    item('new:number', Icons.pin_rounded, 'dl_t_new_number'.tr, color: c.success),
                    item('new:text', Icons.text_fields_rounded, 'dl_t_new_text'.tr, color: c.success),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      h.target = picked;
      if (_mergeOn.isNotEmpty && _mergeOn != 'request' && !pv.headers.any((x) => x.target == _mergeOn)) _mergeOn = '';
      _plan = null;
    });
  }

  List<Widget> _stepColumns(ThemeConfigProvider c) {
    final pv = _pv!;
    final keyHeaders = pv.headers.where((h) => _identity.contains(h.target) || h.target.startsWith('col:')).toList();
    final newCols = pv.headers.where((h) => h.target.startsWith('new:')).length;
    return [
      Row(children: [
        Expanded(child: Text('${pv.filename} · ${pv.rows} ${'dl_imp_rows'.tr}', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium))),
        if (newCols > 0) DlTag('+$newCols ${_tr('dl_imp_new_cols', 'new columns')}', c.success, icon: Icons.add_chart_rounded),
      ]),
      if (pv.shared.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          Text('${'dl_imp_shared'.tr}:', style: AppType.meta(context).copyWith(color: c.textMedium)),
          for (final s in pv.shared) DlTag(s, c.success, icon: Icons.link_rounded),
        ]),
      ],
      const SizedBox(height: AppSpace.sm),
      for (final h in pv.headers)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsetsDirectional.fromSTEB(14, AppSpace.sm, AppSpace.xs, 10),
          decoration: BoxDecoration(
            color: h.target == 'skip' ? c.inputBg : c.primaryWash,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: h.target == 'skip' ? c.divider : c.primary.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(h.header, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                if (h.sample.isNotEmpty)
                  Text(h.sample.join('  ·  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textLight)),
              ]),
            ),
            Icon(Icons.arrow_forward_rounded, size: 16, color: c.textLight),   // auto-mirrored in RTL
            const SizedBox(width: AppSpace.xs),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: () => _chooseTarget(h),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 8),
                decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.divider)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(_targetLabel(h.target),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: h.target == 'skip' ? c.textMedium : c.primary)),
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: c.textMedium),
                ]),
              ),
            ),
          ]),
        ),
      DlSectionTitle('dl_merge_title'.tr, subtitle: 'dl_merge_sub'.tr),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final h in keyHeaders)
          DlChoiceChip(label: h.header, icon: Icons.key_rounded, selected: _mergeOn == h.target, onTap: () => setState(() => _mergeOn = h.target)),
        if (pv.allowStudentRequests)
          DlChoiceChip(label: 'dl_merge_unknown'.tr, icon: Icons.help_outline_rounded, selected: _ask, onTap: () => setState(() => _mergeOn = 'request')),
      ]),
      if (keyHeaders.isEmpty && !_ask) Padding(padding: const EdgeInsets.only(top: 8), child: _Tip(Icons.info_outline_rounded, 'dl_merge_none'.tr)),
      if (_ask) ..._askForm(c, pv),
    ];
  }

  List<Widget> _askForm(ThemeConfigProvider c, DlImportPreview pv) => [
    const SizedBox(height: AppSpace.sm),
    DlCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mark_chat_unread_rounded, color: c.warning, size: 20),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text('dl_ask_explain'.tr, style: AppType.meta(context).copyWith(color: c.textMedium))),
        ]),
        const SizedBox(height: AppSpace.sm),
        Text('dl_ask_which_column'.tr, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          for (final h in pv.headers)
            DlChoiceChip(label: h.header, selected: _reqHeader == h.header, onTap: () => setState(() {
              _reqHeader = h.header;
              if (_reqLabel.text.isEmpty) _reqLabel.text = h.header;
            })),
        ]),
        const SizedBox(height: AppSpace.sm),
        DlField(controller: _reqLabel, label: 'dl_ask_label'.tr),
        Wrap(spacing: AppSpace.xs, children: [
          DlChoiceChip(label: 'dl_ask_text'.tr, icon: Icons.text_fields_rounded, selected: _reqType == 'text', onTap: () => setState(() => _reqType = 'text')),
          DlChoiceChip(label: 'dl_ask_dropdown'.tr, icon: Icons.list_alt_rounded, selected: _reqType == 'dropdown', onTap: () => setState(() => _reqType = 'dropdown')),
        ]),
        if (_reqType == 'dropdown') ...[
          const SizedBox(height: AppSpace.sm),
          DlField(controller: _reqOptions, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
        ],
      ]),
    ),
  ];

  // ── step 3 ─────────────────────────────────────────────────────────────────
  List<Widget> _stepStudents(ThemeConfigProvider c) {
    final pv = _pv!;
    final pl = _plan;
    final mapped = pv.headers.where((h) => h.target != 'skip' && !_identity.contains(h.target)).toList();
    final accounts = _policy == 'create_accounts' && !_ask;
    return [
      if (pl == null)
        const AppListSkeleton(items: 3, withAvatar: false)
      else ...[
        Row(children: [
          Expanded(child: _Count(Icons.check_circle_rounded, c.success, '${pl.matched}', 'dl_plan_matched'.tr)),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: _Count(Icons.person_search_rounded, c.warning, '${pl.unmatched}', 'dl_plan_unmatched'.tr)),
        ]),
        if (pl.newColumns.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${'dl_plan_new_columns'.tr}:', style: AppType.meta(context).copyWith(color: c.textMedium)),
              for (final n in pl.newColumnsDetail)
                DlTag(n['max'] == null ? '${n['label']}' : '${n['label']} · /${dlFmt(n['max'])}', c.purple,
                    icon: n['type'] == 'number' ? Icons.pin_rounded : Icons.text_fields_rounded),
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
        _PolicyTile(icon: Icons.hourglass_bottom_rounded, title: 'dl_policy_temp'.tr, sub: 'dl_policy_temp_sub'.tr, selected: _policy == 'temporary', onTap: () => _setPolicy('temporary')),
        if (pv.allowCreateAccounts)
          _PolicyTile(
            icon: Icons.person_add_alt_1_rounded,
            title: _tr('dl_policy_add', 'Add them to the course'),
            sub: _tr('dl_policy_add_sub', 'Platform users are enrolled and notified. New students get an account — an invitation e-mail when there is an e-mail.'),
            selected: _policy == 'create_accounts',
            onTap: () => _setPolicy('create_accounts'),
          ),
        _PolicyTile(icon: Icons.block_rounded, title: 'dl_policy_skip'.tr, sub: 'dl_policy_skip_sub'.tr, selected: _policy == 'skip', onTap: () => _setPolicy('skip')),
      ] else
        Padding(padding: const EdgeInsets.only(top: 12), child: _Tip(Icons.mark_chat_unread_rounded, 'dl_policy_request_note'.tr, color: c.warning)),
      // ── what "add them to the course" will do ──
      if (accounts && pl != null) ...[
        const SizedBox(height: AppSpace.xs),
        DlCard(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(children: [
            _PlanLine(Icons.how_to_reg_rounded, c.success, pl.willEnrollExisting, _tr('dl_plan_enroll', 'already on the platform — enrolled + notified')),
            _PlanLine(Icons.forward_to_inbox_rounded, c.primary, pl.willInviteEmail, _tr('dl_plan_invite', 'new accounts — invitation e-mail with their login')),
            _PlanLine(Icons.phone_iphone_rounded, c.accent2, pl.willPhoneOnly, _tr('dl_plan_phone', 'new accounts with a phone only — you hand over the login')),
            _PlanLine(Icons.contact_page_rounded, c.warning, pl.rowsMissingContact, _tr('dl_plan_no_contact', 'without e-mail or phone — decide below')),
            if (pl.willSheetOnly > 0) _PlanLine(Icons.table_rows_rounded, c.textMedium, pl.willSheetOnly, _tr('dl_plan_sheet_only', 'kept in the sheet only')),
          ]),
        ),
        const SizedBox(height: AppSpace.xs),
        _Tip(Icons.verified_user_rounded, _tr('dl_plan_setup_note', 'At their first sign-in, new students complete their details and choose their own password; an e-mail they add is verified by a code.')),
      ],
      if (accounts && pl != null && pl.needsName) ...[
        DlSectionTitle('dl_missing_title'.tr, subtitle: 'dl_missing_sub'.tr),
        DlField(controller: _fill('name'), label: 'dl_fill_name'.tr, hint: 'dl_fill_name_hint'.tr, onChanged: (_) => setState(() {})),
      ],
      // ── lines with neither e-mail nor phone ──
      if (accounts && _fixes.isNotEmpty && pl != null) ..._contactResolver(c),
      if (mapped.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('dl_fill_cells'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
            subtitle: Text('dl_fill_cells_sub'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)),
            children: [
              const SizedBox(height: AppSpace.xs),
              for (final h in mapped) DlField(controller: _fill(h.header), label: h.header, hint: 'dl_fill_value'.tr),
            ],
          ),
        ),
    ];
  }

  List<Widget> _contactResolver(ThemeConfigProvider c) {
    final open = {for (final l in _plan!.needsContactLines) (l['row'] as num).toInt()};
    final lines = _fixes.values.where((f) => open.contains(f.row) || f.action != null).toList()..sort((a, b) => a.row.compareTo(b.row));
    if (lines.isEmpty) return const [];
    final undecided = _undecided.length;
    void all(String a) {
      setState(() {
        for (final f in lines) {
          if (!f.decided) f.action = a;
        }
      });
      _checkSoon();
    }

    return [
      DlSectionTitle(
        _tr('dl_fix_title', 'Students without e-mail or phone'),
        subtitle: _tr('dl_fix_sub', 'Add at least one, keep them in the sheet only, or ignore them. The other students are imported anyway.'),
        trailing: undecided > 0 ? DlTag('$undecided', c.warning, icon: Icons.pending_rounded) : Icon(Icons.check_circle_rounded, color: c.success),
      ),
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        ActionChip(
          avatar: Icon(Icons.table_rows_rounded, size: 16, color: c.textMedium),
          label: Text(_tr('dl_fix_all_sheet', 'Rest: sheet only'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          backgroundColor: c.inputBg,
          side: BorderSide(color: c.divider),
          onPressed: undecided == 0 ? null : () => all('sheet_only'),
        ),
        ActionChip(
          avatar: Icon(Icons.block_rounded, size: 16, color: c.textMedium),
          label: Text(_tr('dl_fix_all_skip', 'Rest: ignore'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          backgroundColor: c.inputBg,
          side: BorderSide(color: c.divider),
          onPressed: undecided == 0 ? null : () => all('skip'),
        ),
      ]),
      const SizedBox(height: AppSpace.sm),
      for (final f in lines) _FixCard(fix: f, onChanged: () {
        setState(() {});
        _checkSoon();
      }),
    ];
  }

  // ── step 4 ─────────────────────────────────────────────────────────────────
  List<Widget> _stepDone(ThemeConfigProvider c) {
    final r = _result!;
    final creds = r.credentials;
    return [
      Center(
        child: Container(
          width: 84,
          height: 84,
          margin: const EdgeInsets.only(top: AppSpace.xs, bottom: 10),
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.success.withValues(alpha: 0.12)),
          child: Icon(Icons.celebration_rounded, size: 40, color: c.success),
        ),
      ),
      Text('dl_done_title'.tr, textAlign: TextAlign.center, style: AppType.section(context).copyWith(color: c.textDark)),
      const SizedBox(height: AppSpace.md),
      Row(children: [
        Expanded(child: _Count(Icons.check_circle_rounded, c.success, '${r.matched}', 'dl_plan_matched'.tr)),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: _Count(Icons.task_alt_rounded, c.primary, '${r.cellsWritten}', _tr('dl_done_values', 'values written'))),
      ]),
      if (r.result.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        DlCard(
          padding: const EdgeInsets.all(AppSpace.sm),
          child: Column(children: [
            _PlanLine(Icons.how_to_reg_rounded, c.success, r.resultOf('enrolled_existing'), _tr('dl_res_enrolled', 'enrolled in the course and notified')),
            _PlanLine(Icons.forward_to_inbox_rounded, c.primary, r.resultOf('invited'), _tr('dl_res_invited', 'invited by e-mail')),
            _PlanLine(Icons.phone_iphone_rounded, c.accent2, r.resultOf('phone_only'), _tr('dl_res_phone', 'accounts with a phone only — give them their login')),
            _PlanLine(Icons.table_rows_rounded, c.textMedium, r.resultOf('sheet_only'), _tr('dl_plan_sheet_only', 'kept in the sheet only')),
            _PlanLine(Icons.block_rounded, c.danger, r.resultOf('left_out'), _tr('dl_res_left_out', 'left out')),
          ]),
        ),
      ],
      if (r.raw['will_stage'] != null && r.willStage > 0)
        Padding(padding: const EdgeInsets.only(top: 12), child: _Tip(Icons.mark_chat_unread_rounded, 'dl_done_request_sent'.tr, color: c.warning)),
      if (creds.isNotEmpty) ...[
        DlSectionTitle('dl_done_accounts'.tr, subtitle: _tr('dl_done_accounts_sub2', 'Students with an e-mail received their login. Hand the others theirs — they choose their own password at the first sign-in.'),
            trailing: TextButton.icon(
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
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.control), border: Border.all(color: c.divider)),
            child: Row(children: [
              Icon(cr['emailed'] == true ? Icons.mark_email_read_rounded : Icons.phone_iphone_rounded,
                  size: 20, color: cr['emailed'] == true ? c.success : c.accent2),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${cr['name']}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                  Text('${cr['login']}', style: AppType.meta(context).copyWith(color: c.textMedium), textDirection: TextDirection.ltr),
                ]),
              ),
              SelectableText('${cr['password']}', style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.primary), textDirection: TextDirection.ltr),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _tr('dl_file_share', 'Share'),
                icon: Icon(Icons.share_rounded, size: 18, color: c.primary),
                // WhatsApp / SMS / … — mainly for students with a phone only (they get no e-mail)
                onPressed: () => SharePlus.instance.share(ShareParams(
                  text: dlLoginMessage(
                    name: '${cr['name']}',
                    login: '${cr['login']}',
                    password: '${cr['password']}',
                    link: '${cr['link'] ?? 'https://nextbrain.site/'}',
                    course: widget.p.grid?.title ?? '',
                  ),
                )),
              ),
            ]),
          ),
      ],
      if (r.errors.isNotEmpty) ...[
        DlSectionTitle(
          dlTr('dl_done_problems', 'Lines that need a look'),
          subtitle: r.rejectedCells > 0 ? '${r.rejectedCells} ${dlTr('dl_done_refused', 'values were refused (not a number, out of range, not a listed choice …)')}' : null,
        ),
        for (final e in r.errors.take(12))
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 8),
            decoration: BoxDecoration(color: c.warning.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Row(children: [
              if ((e['row'] as num? ?? 0) > 0) ...[
                DlTag('${dlTr('dl_line', 'Line')} ${e['row']}', c.warning),
                const SizedBox(width: AppSpace.xs),
              ],
              Expanded(child: Text('${e['message']}', style: AppType.meta(context).copyWith(color: c.textDark))),
            ]),
          ),
      ],
    ];
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// One line without e-mail / phone: add a contact, keep in the sheet only, or ignore.
class _FixCard extends StatelessWidget {
  const _FixCard({required this.fix, required this.onChanged});

  final _Fix fix;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final f = fix;
    final col = f.decided ? c.success : c.warning;
    OutlineInputBorder b(Color x) => OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.control), borderSide: BorderSide(color: x));
    Widget field(TextEditingController ctrl, String label, IconData icon, TextInputType kb) => Expanded(
      child: TextField(
        controller: ctrl,
        keyboardType: kb,
        textDirection: TextDirection.ltr,
        onChanged: (_) {
          f.action = f.hasContact ? 'add' : null;
          onChanged();
        },
        style: AppType.label(context).copyWith(color: c.textDark),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          labelStyle: AppType.meta(context).copyWith(color: c.textMedium),
          prefixIcon: Icon(icon, size: 17, color: c.textMedium),
          filled: true,
          fillColor: c.cardBg,
          border: b(c.divider),
          enabledBorder: b(c.divider),
          focusedBorder: b(c.primary),
        ),
      ),
    );
    Widget choice(String a, IconData icon, String label) {
      final on = f.action == a;
      return ChoiceChip(
        selected: on,
        showCheckmark: false,
        avatar: Icon(icon, size: 15, color: on ? c.onHero : c.textMedium),
        label: Text(label, style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: on ? c.onHero : c.textDark)),
        selectedColor: a == 'skip' ? c.danger : c.textMedium,
        backgroundColor: c.cardBg,
        side: BorderSide(color: on ? Colors.transparent : c.divider),
        onSelected: (_) {
          f.action = on ? (f.hasContact ? 'add' : null) : a;
          onChanged();
        },
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: col.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DlTag('${dlTr('dl_line', 'Line')} ${f.row}', c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(f.name.isEmpty ? (f.identifier.isEmpty ? '—' : f.identifier) : f.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
          ),
          if (f.identifier.isNotEmpty && f.name.isNotEmpty) Text(f.identifier, style: AppType.meta(context).copyWith(color: c.textLight)),
          const SizedBox(width: AppSpace.xs),
          Icon(f.decided ? Icons.check_circle_rounded : Icons.pending_rounded, size: 18, color: col),
        ]),
        if (f.action != 'sheet_only' && f.action != 'skip') ...[
          const SizedBox(height: AppSpace.sm),
          Row(children: [
            field(f.email, 'dl_t_email'.tr, Icons.alternate_email_rounded, TextInputType.emailAddress),
            const SizedBox(width: AppSpace.xs),
            field(f.phone, 'dl_t_phone'.tr, Icons.phone_rounded, TextInputType.phone),
          ]),
        ],
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          choice('sheet_only', Icons.table_rows_rounded, _tr('dl_fix_sheet', 'Sheet only')),
          choice('skip', Icons.block_rounded, _tr('dl_fix_skip', 'Ignore')),
        ]),
      ]),
    );
  }
}

class _PlanLine extends StatelessWidget {
  const _PlanLine(this.icon, this.color, this.n, this.text);

  final IconData icon;
  final Color color;
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Opacity(
      opacity: n == 0 ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.chip)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: AppSpace.sm),
          Text('$n', style: AppType.bodyStrong(context).copyWith(color: color)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, style: AppType.meta(context).copyWith(color: c.textDark))),
        ]),
      ),
    );
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
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: AppType.meta(context).copyWith(color: col))),
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
    padding: const EdgeInsets.all(AppSpace.md),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: AppType.pageTitle(context).copyWith(color: color)),
          Text(label, maxLines: 2, style: AppType.meta(context).copyWith(color: context.colors.textMedium)),
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
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(AppSpace.sm),
          decoration: BoxDecoration(
            color: selected ? c.primaryWash : c.inputBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? c.primary : c.textMedium),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
                Text(sub, style: AppType.meta(context).copyWith(color: c.textMedium)),
              ]),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: c.primary),
          ]),
        ),
      ),
    );
  }
}
