// lib/features/teacher/data_lab/data_lab_requests.dart
// Teacher side of "ask the students for a value": create a request and follow how many answered.
// Students get a notification and a blocking screen (see data_lab_gate.dart) until they answer.
// "Remind" nudges only the students who have not answered yet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show toast, confirm, showAdminSheet, SheetHeader;

import 'data_lab_api.dart';
import 'data_lab_models.dart';
import 'data_lab_provider.dart';
import 'data_lab_widgets.dart';

Future<void> showRequestsSheet(BuildContext context, DataLabProvider p) =>
    showAdminSheet(context, (_) => _RequestsSheet(p: p));

class _RequestsSheet extends StatefulWidget {
  const _RequestsSheet({required this.p});

  final DataLabProvider p;

  @override
  State<_RequestsSheet> createState() => _RequestsSheetState();
}

class _RequestsSheetState extends State<_RequestsSheet> {
  final _api = DataLabApi();
  final _title = TextEditingController();
  final _options = TextEditingController();
  String _type = 'text';
  bool _busy = false, _loading = true;
  List<DlRequestInfo> _items = [];
  final Set<int> _working = {}; // requests with a remind / close in progress

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _options.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await _api.requests(widget.p.courseId);
      if (mounted) setState(() => _items = r);
    } catch (_) {
      // the list is optional, creating still works
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remind(DlRequestInfo r) async {
    setState(() => _working.add(r.id));
    try {
      final n = await _api.remindRequest(widget.p.courseId, r.id);
      toast(n == 0 ? dlTr('dl_req_all_answered', 'Everyone has already answered 🎉') : '$n ${dlTr('dl_req_reminded', 'students reminded')}');
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _working.remove(r.id));
    }
  }

  Future<void> _close(DlRequestInfo r) async {
    if (!await confirm(context, message: 'dl_req_close_q'.tr)) return;
    setState(() => _working.add(r.id));
    try {
      await _api.closeRequest(widget.p.courseId, r.id);
      await _load();
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _working.remove(r.id));
    }
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) return toast('dl_err_label'.tr, error: true);
    final opts = _options.text.split(RegExp('[,،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (_type == 'dropdown' && opts.length < 2) return toast('dl_err_options'.tr, error: true);
    setState(() => _busy = true);
    try {
      await _api.createRequest(widget.p.courseId, title: title, inputType: _type, options: _type == 'dropdown' ? opts : null);
      _title.clear();
      _options.clear();
      toast('dl_req_sent'.tr);
      await widget.p.load(silent: true);
      await _load();
    } catch (e) {
      toast(e is ApiException ? e.message : '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SheetHeader('dl_ask_students'.tr),
      Flexible(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text('dl_req_explain'.tr, style: dlText(12.5, c: c.textMedium, h: 1.55)),
            const SizedBox(height: 14),
            DlField(controller: _title, label: 'dl_req_title'.tr, hint: 'dl_req_title_hint'.tr),
            Wrap(spacing: 8, children: [
              DlChoiceChip(label: 'dl_ask_text'.tr, icon: Icons.text_fields_rounded, selected: _type == 'text', onTap: () => setState(() => _type = 'text')),
              DlChoiceChip(label: 'dl_ask_dropdown'.tr, icon: Icons.list_alt_rounded, selected: _type == 'dropdown', onTap: () => setState(() => _type = 'dropdown')),
            ]),
            if (_type == 'dropdown') ...[
              const SizedBox(height: 12),
              DlField(controller: _options, label: 'dl_options'.tr, hint: 'dl_options_hint'.tr),
            ],
            const SizedBox(height: 12),
            DlPrimaryButton(label: 'dl_req_send'.tr, icon: Icons.campaign_rounded, busy: _busy, onPressed: _create),
            DlSectionTitle('dl_req_list'.tr),
            if (_loading)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
            else if (_items.isEmpty)
              Padding(padding: const EdgeInsets.all(10), child: Text('dl_req_none'.tr, style: dlText(12.5, c: c.textMedium)))
            else
              for (final r in _items)
                DlCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: (r.isActive ? c.warning : c.textLight).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(r.inputType == 'dropdown' ? Icons.list_alt_rounded : Icons.text_fields_rounded,
                            size: 18, color: r.isActive ? c.warning : c.textLight),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.title, style: dlText(14, w: FontWeight.w800, c: c.textDark)),
                          Text(
                            [
                              if (r.createdAt != null) dlAgo(r.createdAt),
                              if (r.isMergeKey) dlTr('dl_req_merge', 'links imported lines'),
                            ].join(' · '),
                            style: dlText(11, c: c.textLight),
                          ),
                        ]),
                      ),
                      if (!r.isActive) DlTag('dl_req_closed'.tr, c.textLight),
                    ]),
                    const SizedBox(height: 10),
                    DlBar(value: r.total == 0 ? 0 : r.answered / r.total * 100, color: r.answered >= r.total ? c.success : c.primary),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${r.answered} / ${r.total} ${'dl_req_answered'.tr}'
                          '${r.isActive && r.waiting > 0 ? ' · ${r.waiting} ${dlTr('dl_req_waiting', 'still waiting')}' : ''}',
                          style: dlText(11.5, c: c.textMedium),
                        ),
                      ),
                      if (r.isActive && _working.contains(r.id))
                        const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else if (r.isActive) ...[
                        if (r.waiting > 0)
                          TextButton.icon(
                            onPressed: () => _remind(r),
                            icon: const Icon(Icons.notifications_active_rounded, size: 16),
                            label: Text(dlTr('dl_req_remind', 'Remind')),
                          ),
                        TextButton(
                          onPressed: () => _close(r),
                          style: TextButton.styleFrom(foregroundColor: c.danger),
                          child: Text('dl_req_close'.tr),
                        ),
                      ],
                    ]),
                  ]),
                ),
          ],
        ),
      ),
    ]);
  }
}
