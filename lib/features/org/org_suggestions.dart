// lib/features/org/org_suggestions.dart
//
// AUTO-CREATE WITH ADMIN APPROVAL (back: services/organization/auto_create.py, routers/attention_router.py).
// The server derives what is missing (first: terms — First, Second, Summer) and keeps each as a DRAFT decision.
// Nothing real exists until a person decides:  Approve → created · Edit → the draft form, then created · Reject.
//
//   OrgTermSuggestions(orgBase: s.base, onChanged: reload, onCreateManually: openForm)
//     the two buttons "Auto-generate" · "Create manually" + the open term drafts with Approve / Edit / Reject.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../core/api_client.dart';
import '../../design/app_kit.dart';
import '../admin/admin_common.dart' show t, asMap, asMapList, toast, shortDate;
import 'org_v3.dart' show orgCall;

/// What a term draft carries: {year_label, kind, start_date, end_date}.
typedef TermDraftEditor = Future<Map<String, dynamic>?> Function(Map<String, dynamic> draft);

class OrgTermSuggestions extends StatefulWidget {
  const OrgTermSuggestions({super.key, required this.orgBase, required this.onChanged, required this.onCreateManually,
      required this.editDraft, this.kindLabel});

  /// `${OrgSession.base}` (= /api/v1/org/orgs/{id}).
  final String orgBase;
  final VoidCallback onChanged;
  final VoidCallback onCreateManually;
  /// Opens the term form pre-filled with the draft; returns the edited draft or null (cancelled).
  final TermDraftEditor editDraft;
  final String Function(String kind)? kindLabel;

  @override
  State<OrgTermSuggestions> createState() => _OrgTermSuggestionsState();
}

class _OrgTermSuggestionsState extends State<OrgTermSuggestions> {
  List<Map<String, dynamic>> _items = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant OrgTermSuggestions old) {
    super.didUpdateWidget(old);
    if (old.orgBase != widget.orgBase) _load();
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get('${widget.orgBase}/suggestions'), quiet: true);
    if (!mounted || !r.ok) return;
    setState(() => _items = asMapList(r.map['items']).where((d) => d['kind'] == 'missing_term').toList());
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final r = await orgCall(() => ApiClient().post('${widget.orgBase}/suggestions/terms/generate'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) return;
    final items = asMapList(r.map['items']).where((d) => d['kind'] == 'missing_term').toList();
    setState(() => _items = items);
    toast(items.isEmpty
        ? t('لا ينقص أي فصل — التقويم مكتمل', 'No term is missing — the calendar is complete')
        : t('${items.length} مسودة جاهزة للمراجعة', '${items.length} drafts ready to review'));
    AttentionService.instance.refresh();
  }

  Future<void> _decide(Map<String, dynamic> d, String verdict, [Map<String, dynamic>? params]) async {
    final body = <String, dynamic>{
      if (params != null) 'action': {'action': 'create_term', 'params': params},
    };
    final r = await orgCall(() => ApiClient().post('${widget.orgBase}/registrar/decisions/${d['id']}/$verdict', body: body),
        ok: verdict == 'reject' ? t('رُفض الاقتراح', 'Suggestion rejected') : t('أُنشئ الفصل', 'Term created'));
    if (!mounted) return;
    if (r.ok) widget.onChanged();
    _load();
    AttentionService.instance.refresh();
  }

  Future<void> _edit(Map<String, dynamic> d) async {
    final draft = Map<String, dynamic>.from(asMap(asMap(d['recommendation'])['params']));
    final edited = await widget.editDraft(draft);
    if (edited != null && mounted) await _decide(d, 'edit', edited);
  }

  String _kind(String k) => widget.kindLabel?.call(k) ?? k;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        AppPill(icon: Icons.auto_fix_high_rounded, label: _busy ? t('جارٍ…', 'Working…') : t('توليد تلقائي', 'Auto-generate'),
            color: c.primary, onTap: _busy ? null : _generate),
        AppPill(icon: Icons.edit_calendar_rounded, label: t('إنشاء يدوي', 'Create manually'), onTap: widget.onCreateManually),
      ]),
      if (_items.isNotEmpty) ...[
        const SizedBox(height: 10),
        AppBanner(icon: Icons.lightbulb_rounded,
            text: t('مسودات أنشأها النظام من التقويم — لا يُنشأ شيء قبل موافقتك', 'Drafts the system derived from the calendar — nothing is created before you approve')),
        const SizedBox(height: 8),
        for (final d in _items) _card(context, d),
      ],
    ]);
  }

  Widget _card(BuildContext context, Map<String, dynamic> d) {
    final c = context.colors;
    final rec = asMap(d['recommendation']);
    final p = asMap(rec['params']);
    final why = switch ('${rec['why']}') {
      'previous_year' => t('بنفس تواريخ العام السابق', 'Same dates as last year'),
      'template' => t('من قالب التقويم في الإعدادات', 'From the calendar template in settings'),
      _ => t('من التقويم الافتراضي', 'From the default calendar'),
    };
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: c.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${_kind('${p['kind']}')} · ${p['year_label']}',
                style: appText(14, w: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          AppBadgePill(t('مسودة', 'Draft'), color: c.warning),
        ]),
        const SizedBox(height: 4),
        Text('${shortDate('${p['start_date']}')} → ${shortDate('${p['end_date']}')}',
            style: appText(12, c: c.textMedium)),
        Text('${t('ناقص', 'Missing')} · $why', style: appText(12, c: c.textLight)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          AppPill(icon: Icons.check_rounded, label: t('اعتماد', 'Approve'), color: c.success, onTap: () => _decide(d, 'accept')),
          AppPill(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(d)),
          AppPill(icon: Icons.close_rounded, label: t('رفض', 'Reject'), color: c.danger, onTap: () => _decide(d, 'reject')),
        ]),
      ]),
    );
  }
}
