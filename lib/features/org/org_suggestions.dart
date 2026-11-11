// lib/features/org/org_suggestions.dart
//
// AUTO-CREATE WITH ADMIN APPROVAL (back: services/organization/auto_create.py, routers/attention_router.py).
// The server derives what is missing and keeps each as a DRAFT decision. Nothing real exists until a person decides:
// Approve → created · Edit → the draft form, then created · Reject (never proposed again).
//   missing_term       a term of the year (First, Second, Summer)      → create_term {year_label, kind, dates}
//   missing_offerings  the courses of a term with none (plan / hours)  → open_offerings {term_id, course_ids}
//   missing_periods    the day's periods of an org with none           → create_periods {periods: [...]}
//
//   OrgTermSuggestions(orgBase: s.base, onChanged: reload, onCreateManually: openForm, editDraft: termForm)
//     "Auto-generate" · "Create manually" + every open draft with Approve / Edit / Reject.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../../core/api_client.dart';
import '../../design/app_kit.dart';
import '../admin/admin_common.dart' show t, asInt, asMap, asMapList, toast, shortDate;
import 'org_v3.dart' show orgCall;

/// What a term draft carries: {year_label, kind, start_date, end_date}.
typedef TermDraftEditor = Future<Map<String, dynamic>?> Function(Map<String, dynamic> draft);

const _kinds = {'missing_term', 'missing_offerings', 'missing_periods'};

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
  Map<String, dynamic> _courses = const {};
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

  void _take(Map<String, dynamic> m) {
    _items = asMapList(m['items']).where((d) => _kinds.contains(d['kind'])).toList();
    _courses = asMap(m['courses']);
  }

  Future<void> _load() async {
    final r = await orgCall(() => ApiClient().get('${widget.orgBase}/suggestions'), quiet: true);
    if (!mounted || !r.ok) return;
    setState(() => _take(r.map));
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final r = await orgCall(() => ApiClient().post('${widget.orgBase}/suggestions/all/generate'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r.ok) _take(r.map);
    });
    if (!r.ok) return;
    toast(_items.isEmpty
        ? t('لا ينقص شيء — كل ما يمكن اشتقاقه موجود', 'Nothing is missing — everything derivable exists')
        : t('${_items.length} مسودة جاهزة للمراجعة', '${_items.length} drafts ready to review'));
    AttentionService.instance.refresh();
  }

  Future<void> _decide(Map<String, dynamic> d, String verdict, [Map<String, dynamic>? params]) async {
    final action = '${asMap(d['recommendation'])['action']}';
    final body = <String, dynamic>{
      if (params != null) 'action': {'action': action, 'params': params},
    };
    final r = await orgCall(() => ApiClient().post('${widget.orgBase}/registrar/decisions/${d['id']}/$verdict', body: body),
        ok: verdict == 'reject' ? t('رُفض الاقتراح', 'Suggestion rejected') : t('تم الإنشاء', 'Created'));
    if (!mounted) return;
    if (r.ok) widget.onChanged();
    _load();
    AttentionService.instance.refresh();
  }

  Future<void> _edit(Map<String, dynamic> d) async {
    final draft = Map<String, dynamic>.from(asMap(asMap(d['recommendation'])['params']));
    final edited = switch ('${d['kind']}') {
      'missing_term' => await widget.editDraft(draft),
      'missing_offerings' => await _editCourses(draft),
      _ => await _editPeriods(draft),
    };
    if (edited != null && mounted) await _decide(d, 'edit', edited);
  }

  String _course(dynamic id) {
    final c = asMap(_courses['$id']);
    final name = t('${c['name_ar'] ?? c['name_en'] ?? '#$id'}', '${c['name_en'] ?? c['name_ar'] ?? '#$id'}');
    return (c['code'] ?? '').toString().isEmpty ? name : '${c['code']} · $name';
  }

  Future<Map<String, dynamic>?> _editCourses(Map<String, dynamic> draft) async {
    final all = [for (final c in (draft['course_ids'] as List? ?? const [])) asInt(c)];
    final sel = {...all};
    final ok = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('المقررات المطروحة', 'Courses to offer'), subtitle: t('اختر ما يُطرح في هذا الفصل', 'Pick what this term offers')),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              for (final id in all)
                FilterChip(
                  label: Text(_course(id), style: AppType.label(ctx).copyWith(color: ctx.colors.textDark)),
                  selected: sel.contains(id),
                  onSelected: (on) => set(() => on ? sel.add(id) : sel.remove(id)),
                ),
            ]),
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(label: t('اعتماد بعد التعديل', 'Approve with changes'), onPressed: () {
              if (sel.isEmpty) return toast(t('اختر مقرراً واحداً على الأقل', 'Pick at least one course'), error: true);
              Navigator.pop(ctx, true);
            }),
          ]),
        )));
    if (ok != true) return null;
    return {...draft, 'course_ids': [for (final id in all) if (sel.contains(id)) id]};
  }

  Future<Map<String, dynamic>?> _editPeriods(Map<String, dynamic> draft) async {
    final rows = [
      for (final p in asMapList(draft['periods']))
        [TextEditingController(text: '${p['label']}'), TextEditingController(text: '${p['start_time']}'),
          TextEditingController(text: '${p['end_time']}')],
    ];
    final ok = await showAppSheet<bool>(context, (ctx) => StatefulBuilder(builder: (ctx, set) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppSectionTitle(t('فترات اليوم الدراسي', 'Periods of the day'), subtitle: t('الوقت بصيغة 24 ساعة HH:MM', 'Times as 24h HH:MM')),
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Row(children: [
                  Expanded(child: AppField(controller: rows[i][0], label: t('الاسم', 'Name'))),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AppField(controller: rows[i][1], label: t('من', 'From'), ltr: true)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: AppField(controller: rows[i][2], label: t('إلى', 'To'), ltr: true)),
                  IconButton(
                    tooltip: t('حذف', 'Remove'),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                    onPressed: rows.length < 2 ? null : () => set(() => rows.removeAt(i)),
                  ),
                ]),
              ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppPill(icon: Icons.add_rounded, label: t('فترة', 'Period'),
                  onTap: () => set(() => rows.add([TextEditingController(text: '${rows.length + 1}'), TextEditingController(), TextEditingController()]))),
            ),
            const SizedBox(height: AppSpace.sm),
            AppPrimaryButton(label: t('اعتماد بعد التعديل', 'Approve with changes'), onPressed: () => Navigator.pop(ctx, true)),
          ]),
        )));
    if (ok != true) return null;
    return {
      'periods': [
        for (final r in rows) {'label': r[0].text.trim(), 'start_time': r[1].text.trim(), 'end_time': r[2].text.trim()},
      ],
    };
  }

  String _kind(String k) => widget.kindLabel?.call(k) ?? k;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        AppPill(icon: Icons.auto_fix_high_rounded, label: _busy ? t('جارٍ…', 'Working…') : t('توليد تلقائي', 'Auto-generate'),
            color: c.primary, onTap: _busy ? null : _generate),
        AppPill(icon: Icons.edit_calendar_rounded, label: t('إنشاء يدوي', 'Create manually'), onTap: widget.onCreateManually),
      ]),
      if (_items.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        AppBanner(icon: Icons.lightbulb_rounded,
            text: t('مسودات اشتقها النظام — لا يُنشأ شيء قبل موافقتك', 'Drafts the system derived — nothing is created before you approve')),
        const SizedBox(height: AppSpace.xs),
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
      'template' => t('من القالب في الإعدادات', 'From the template in settings'),
      'parent_org' => t('من فترات المؤسسة الأم', 'From the parent organization'),
      'program_plan' => t('من خطة البرامج والساعات المعتمدة', 'From the program plan and credit hours'),
      _ => t('من القالب الافتراضي', 'From the default template'),
    };
    final (IconData icon, String title, List<String> lines) = switch ('${d['kind']}') {
      'missing_term' => (Icons.event_note_rounded, '${_kind('${p['kind']}')} · ${p['year_label']}',
          ['${shortDate('${p['start_date']}')} → ${shortDate('${p['end_date']}')}']),
      'missing_offerings' => (Icons.menu_book_rounded, t('${d['title']}', '${d['description'] ?? d['title']}'), [
          (p['course_ids'] as List? ?? const []).map(_course).join(' · '),
          if ((rec['blocked'] as List? ?? const []).isNotEmpty)
            t('بانتظار أرشفة نسخة سابقة: ', 'Waiting for a previous run to be archived: ') +
                (rec['blocked'] as List).map(_course).join(' · '),
        ]),
      _ => (Icons.schedule_rounded, t('فترات اليوم الدراسي', 'Periods of the day'),
          [asMapList(p['periods']).map((x) => '${x['label']} ${AppTime.clockRange('${x['start_time']}', '${x['end_time']}')}').join(' · ')]),
    };
    return AppCard(
      margin: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: c.primary, size: AppIconSize.md),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(title, style: AppType.bodyStrong(context), maxLines: 2, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpace.xs),
          AppBadgePill(t('مسودة', 'Draft'), color: c.warning),
        ]),
        const SizedBox(height: AppSpace.xxs),
        for (final l in lines)
          if (l.isNotEmpty) Text(l, style: AppType.meta(context).copyWith(color: c.textMedium), maxLines: 4, overflow: TextOverflow.ellipsis),
        Text('${t('ناقص', 'Missing')} · $why', style: AppType.meta(context).copyWith(color: c.textLight)),
        const SizedBox(height: AppSpace.xs),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
          AppPill(icon: Icons.check_rounded, label: t('اعتماد', 'Approve'), color: c.success, onTap: () => _decide(d, 'accept')),
          AppPill(icon: Icons.edit_rounded, label: t('تعديل', 'Edit'), onTap: () => _edit(d)),
          AppPill(icon: Icons.close_rounded, label: t('رفض', 'Reject'), color: c.danger, onTap: () => _decide(d, 'reject')),
        ]),
      ]),
    );
  }
}
