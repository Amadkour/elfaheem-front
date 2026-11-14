// lib/features/data_lab/data_lab_requests.dart
// Teacher side of "ask the students": a FORM of one or more questions, shown to every student on ONE screen
// (blocking, see data_lab_gate.dart) until they answer.
//   • each question: text · list of choices · number — its answers go straight into the sheet, in a new column or
//     an existing one (a student who already has a value there is not asked — it counts as answered)
//   • every question can be switched off and on again; switching on asks again the students who did not answer
//   • "Remind" nudges the students who still have something to answer
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, showAdminSheet, SheetHeader;

import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_api.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_models.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_provider.dart';
import 'package:flutter_education_app/features/data_lab/data_lab_widgets.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppNumberField;

String _tr(String key, String fallback) => dlTr(key, fallback);

Future<void> showRequestsSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _RequestsSheet(p: p));

/// One question being written.
class _Draft {
  final title = TextEditingController();
  final options = TextEditingController();
  final max = TextEditingController(text: '100');
  String type = 'text'; // text | dropdown | number
  String? columnKey; // null = a new column

  List<String> get optionList => options.text.split(RegExp('[,،\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  void dispose() {
    title.dispose();
    options.dispose();
    max.dispose();
  }
}

class _RequestsSheet extends StatefulWidget {
  const _RequestsSheet({required this.p});

  final DataLabProvider p;

  @override
  State<_RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends State<_RequestsSheet> {
  final _api = DataLabApi();
  final _formTitle = TextEditingController();
  final List<_Draft> _drafts = [_Draft()];
  bool _busy = false, _loading = true, _composing = false;
  List<DlRequestForm> _forms = [];
  final Set<String> _working = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _formTitle.dispose();
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.requests(widget.p.courseId);
      if (mounted) {
        setState(() {
          _forms = DlRequestForm.group(r);
          if (_forms.isEmpty) _composing = true;
        });
      }
    } catch (_) {
      // the list is optional, creating still works
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final qs = <Map<String, dynamic>>[];
    for (var i = 0; i < _drafts.length; i++) {
      final d = _drafts[i];
      final t = d.title.text.trim();
      if (t.isEmpty) return toast('${_tr('dl_q_need_text', 'Write question')} ${i + 1}', error: true);
      if (d.type == 'dropdown' && d.optionList.length < 2) return toast('${'dl_err_options'.tr} (${i + 1})', error: true);
      qs.add({
        'title': t,
        'input_type': d.type,
        if (d.type == 'dropdown') 'options': d.optionList,
        'column_key': ?d.columnKey,
        if (d.type == 'number' && d.columnKey == null) 'max_value': double.tryParse(d.max.text.replaceAll(',', '.')) ?? 100,
      });
    }
    setState(() => _busy = true);
    try {
      await _api.createForm(widget.p.courseId, title: _formTitle.text.trim(), questions: qs);
      if (!mounted) return;
      _formTitle.clear();
      for (final d in _drafts) {
        d.dispose();
      }
      setState(() {
        _drafts
          ..clear()
          ..add(_Draft());
        _composing = false;
      });
      toast('dl_req_sent'.tr);
      await widget.p.load(silent: true, keep: true); // the new answer columns appear in the sheet
      await _load();
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(DlRequestForm form, DlRequestInfo q, bool on) async {
    setState(() => _working.add('q${q.id}'));
    try {
      await _api.setRequestActive(widget.p.courseId, q.id, on);
      toast(on ? _tr('dl_q_on', 'Question switched on — students who did not answer are asked again') : _tr('dl_q_off', 'Question switched off'));
      await _load();
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _working.remove('q${q.id}'));
    }
  }

  Future<void> _remind(DlRequestForm form) async {
    setState(() => _working.add(form.key));
    try {
      final n = await _api.remindForm(widget.p.courseId, form.key);
      toast(n == 0 ? dlTr('dl_req_all_answered', 'Everyone has already answered 🎉') : '$n ${dlTr('dl_req_reminded', 'students reminded')}');
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _working.remove(form.key));
    }
  }

  Future<void> _closeAll(DlRequestForm form) async {
    if (!await confirm(context, message: 'dl_req_close_q'.tr)) return;
    setState(() => _working.add(form.key));
    try {
      for (final q in form.questions.where((q) => q.isActive)) {
        await _api.setRequestActive(widget.p.courseId, q.id, false);
      }
      await _load();
    } catch (e) {
      toast(apiErrorText(ApiException.from(e)), error: true);
    } finally {
      if (mounted) setState(() => _working.remove(form.key));
    }
  }

  /// Columns a question can write into, for its type.
  List<DlColumn> _targets(String type) => widget.p.columns.where((c) {
    if (c.isLocked) return false;
    if (type == 'number') return c.isNumber && (c.isCustom || c.isBuiltin);
    return c.isCustom && !c.isNumber;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_ask_students'.tr),
      Flexible(
        child: AppRefresh(
          onRefresh: _load,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, AppSpace.lg, 24),
            children: [
              Text(_tr('dl_req_explain2', 'Students see your questions on one screen and cannot continue until they answer. Their answers go straight into the sheet.'),
                  style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.sm),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: _composing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
                    ),
                    onPressed: () => setState(() => _composing = true),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_tr('dl_form_new', 'New form'), style: AppType.bodyStrong(context).copyWith(color: c.onHero)),
                  ),
                ),
                secondChild: _composer(c),
              ),
              DlSectionTitle('dl_req_list'.tr),
              if (_loading)
                const AppListSkeleton(items: 3)
              else if (_forms.isEmpty)
                Padding(padding: const EdgeInsets.all(AppSpace.sm), child: Text('dl_req_none'.tr, style: AppType.meta(context).copyWith(color: c.textMedium)))
              else
                for (final f in _forms) _formCard(c, f),
            ],
          ),
        ),
      ),
    ]);
  }

  // ── writing a form ──────────────────────────────────────────────────────────
  Widget _composer(ThemeConfigProvider c) => DlCard(
    padding: const EdgeInsets.all(AppSpace.md),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.dynamic_form_rounded, color: c.primary),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(_tr('dl_form_new', 'New form'), style: AppType.bodyStrong(context).copyWith(color: c.textDark))),
        if (_forms.isNotEmpty)
          IconButton(visualDensity: VisualDensity.compact, tooltip: AppConfig.lang == 'ar' ? 'إغلاق' : 'Close', icon: Icon(Icons.close_rounded, color: c.textMedium), onPressed: () => setState(() => _composing = false)),
      ]),
      const SizedBox(height: AppSpace.sm),
      DlField(controller: _formTitle, label: _tr('dl_form_title', 'Form title (optional)'), hint: _tr('dl_form_title_hint', 'e.g. A few details for the exam')),
      for (var i = 0; i < _drafts.length; i++) _draftCard(c, i),
      const SizedBox(height: AppSpace.xxs),
      TextButton.icon(
        onPressed: _drafts.length >= 20 ? null : () => setState(() => _drafts.add(_Draft())),
        icon: const Icon(Icons.add_circle_outline_rounded),
        label: Text(_tr('dl_q_add', 'Add a question')),
      ),
      const SizedBox(height: AppSpace.xs),
      DlPrimaryButton(
        label: '${'dl_req_send'.tr}${_drafts.length > 1 ? ' (${_drafts.length})' : ''}',
        icon: Icons.campaign_rounded,
        busy: _busy,
        onPressed: _send,
      ),
    ]),
  );

  Widget _draftCard(ThemeConfigProvider c, int i) {
    final d = _drafts[i];
    final targets = _targets(d.type);
    if (d.columnKey != null && !targets.any((t) => t.key == d.columnKey)) d.columnKey = null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsetsDirectional.fromSTEB(12, AppSpace.sm, AppSpace.xs, 12),
      decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: Text('${i + 1}', style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: context.colors.onHero)),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(_tr('dl_q_n', 'Question'), style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark))),
          if (_drafts.length > 1)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: AppConfig.lang == 'ar' ? 'حذف السؤال' : 'Delete question',
              icon: Icon(Icons.delete_outline_rounded, size: 19, color: c.danger),
              onPressed: () => setState(() => _drafts.removeAt(i).dispose()),
            ),
        ]),
        const SizedBox(height: AppSpace.xs),
        DlField(controller: d.title, label: 'dl_req_title'.tr, hint: 'dl_req_title_hint'.tr),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          DlChoiceChip(label: 'dl_ask_text'.tr, icon: Icons.text_fields_rounded, selected: d.type == 'text', onTap: () => setState(() => d.type = 'text')),
          DlChoiceChip(label: 'dl_ask_dropdown'.tr, icon: Icons.list_alt_rounded, selected: d.type == 'dropdown', onTap: () => setState(() => d.type = 'dropdown')),
          DlChoiceChip(label: _tr('dl_ask_number', 'Number'), icon: Icons.pin_rounded, selected: d.type == 'number', onTap: () => setState(() => d.type = 'number')),
        ]),
        if (d.type == 'dropdown') ...[
          const SizedBox(height: AppSpace.sm),
          DlField(controller: d.options, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
        ],
        const SizedBox(height: AppSpace.sm),
        Text(_tr('dl_q_save_in', 'Save the answers in'), style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: c.textMedium)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          DlChoiceChip(label: _tr('dl_q_new_col', 'A new column'), icon: Icons.add_chart_rounded, selected: d.columnKey == null, onTap: () => setState(() => d.columnKey = null)),
          for (final t in targets)
            DlChoiceChip(label: t.label, icon: Icons.view_column_rounded, selected: d.columnKey == t.key, onTap: () => setState(() => d.columnKey = t.key)),
        ]),
        if (d.type == 'number' && d.columnKey == null) ...[
          const SizedBox(height: AppSpace.sm),
          AppNumberField(controller: d.max, label: 'dl_max_value'.tr, min: 0, decimals: 2),
        ],
        if (d.columnKey != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: c.success),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(_tr('dl_q_existing_note', 'Students who already have a value in this column are not asked.'),
                    style: AppType.meta(context).copyWith(color: c.textMedium)),
              ),
            ]),
          ),
      ]),
    );
  }

  // ── a sent form ──────────────────────────────────────────────────────────────
  Widget _formCard(ThemeConfigProvider c, DlRequestForm f) {
    final active = f.activeCount;
    final busy = _working.contains(f.key);
    return DlCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: (active > 0 ? c.warning : c.textLight).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(Icons.dynamic_form_rounded, size: 19, color: active > 0 ? c.warning : c.textLight),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
              Text(
                [
                  if (f.createdAt != null) dlAgo(f.createdAt),
                  '${f.questions.length} ${_tr('dl_q_count', 'questions')}',
                  if (f.isMergeKey) dlTr('dl_req_merge', 'links imported lines'),
                ].join(' · '),
                style: AppType.meta(context).copyWith(color: c.textLight),
              ),
            ]),
          ),
          if (active == 0) DlTag('dl_req_closed'.tr, c.textLight),
        ]),
        const SizedBox(height: AppSpace.xs),
        for (final q in f.questions) _questionRow(c, f, q),
        if (active > 0) ...[
          const SizedBox(height: AppSpace.xxs),
          Row(children: [
            Expanded(
              child: Text(
                f.waiting > 0 ? '${f.waiting} ${dlTr('dl_req_waiting', 'still waiting')}' : dlTr('dl_req_all_answered', 'Everyone has already answered 🎉'),
                style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: f.waiting > 0 ? c.warning : c.success),
              ),
            ),
            if (busy)
              const Padding(padding: EdgeInsets.all(AppSpace.xs), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              if (f.waiting > 0)
                TextButton.icon(onPressed: () => _remind(f), icon: const Icon(Icons.notifications_active_rounded, size: 16), label: Text(dlTr('dl_req_remind', 'Remind'))),
              TextButton(
                onPressed: () => _closeAll(f),
                style: TextButton.styleFrom(foregroundColor: c.danger),
                child: Text(_tr('dl_q_close_all', 'Close all')),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _questionRow(ThemeConfigProvider c, DlRequestForm f, DlRequestInfo q) {
    final busy = _working.contains('q${q.id}');
    final pct = q.total == 0 ? 0.0 : q.answered / q.total * 100;
    return Opacity(
      opacity: q.isActive ? 1 : 0.55,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Icon(q.inputType == 'dropdown' ? Icons.list_alt_rounded : (q.inputType == 'number' ? Icons.pin_rounded : Icons.text_fields_rounded),
              size: 16, color: c.textMedium),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(q.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600, color: c.textDark)),
              const SizedBox(height: 3),
              DlBar(value: pct, height: 5, color: q.answered >= q.total && q.total > 0 ? c.success : c.primary),
              Text(
                '${q.answered} / ${q.total} ${'dl_req_answered'.tr}${q.columnLabel != null ? ' · → ${q.columnLabel}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.overline(context).copyWith(color: c.textLight),
              ),
            ]),
          ),
          const SizedBox(width: AppSpace.xs),
          if (busy)
            const SizedBox(width: 40, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
          else
            Tooltip(
              message: q.isActive ? _tr('dl_q_switch_off', 'Switch this question off') : _tr('dl_q_switch_on', 'Ask it again'),
              child: AppSwitch(value: q.isActive, activeColor: c.success, onChanged: (v) => _toggle(f, q, v)),
            ),
        ]),
      ),
    );
  }
}
