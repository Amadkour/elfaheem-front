// lib/features/org/org_services_pages.dart
//
// Department services — staff side. Every page works for the whole organization (deptId == null) or for ONE
// department (deptId set): same widgets, same look, rights checked with OrgSession.can(module, action, deptId).
//
//   OrgAnnouncementsPage   → org_announcements.dart (re-exported)
//   OrgFormsPage           requests / surveys / applications → OrgFormBuilderScreen · OrgFormResponsesScreen
//   OrgMaterialsPage       department library (files or links, team-only or for members)
//   OrgComplaintsPage      inbox with SLA → OrgComplaintThreadScreen (reply · internal note · assign · transfer)
library;

// Announcements moved to org_announcements.dart (point 17); re-exported so existing imports keep working.
export 'org_announcements.dart' show OrgAnnouncementsPage, showAnnouncementEditor, showCreateAnnouncementSheet;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';


/// Shared FAB style.
Widget _fab(BuildContext context, String tag, String label, IconData icon, VoidCallback onTap) {
  final c = context.colors;
  return FloatingActionButton.extended(
    heroTag: tag,
    backgroundColor: c.primary,
    onPressed: onTap,
    icon: Icon(icon, color: Colors.white),
    label: Text(label, style: const TextStyle(fontFamily: 'tajawal', color: Colors.white, fontWeight: FontWeight.w700)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Forms
// ═════════════════════════════════════════════════════════════════════════════

Map<String, String> _formKinds() => {
      'request': t('طلب (يُراجع)', 'Request (reviewed)'),
      'application': t('تقديم', 'Application'),
      'survey': t('استبيان', 'Survey'),
    };

Map<String, String> fieldTypes() => {
      'text': t('نص قصير', 'Short text'),
      'textarea': t('نص طويل', 'Long text'),
      'number': t('رقم', 'Number'),
      'date': t('تاريخ', 'Date'),
      'select': t('اختيار واحد', 'One choice'),
      'multiselect': t('اختيارات متعددة', 'Multiple choice'),
      'checkbox': t('موافقة / إقرار', 'Checkbox'),
      'file': t('مرفق', 'Attachment'),
      'email': t('بريد إلكتروني', 'E-mail'),
      'phone': t('هاتف', 'Phone'),
    };

const fieldIcons = {
  'text': Icons.short_text_rounded,
  'textarea': Icons.notes_rounded,
  'number': Icons.pin_rounded,
  'date': Icons.event_rounded,
  'select': Icons.radio_button_checked_rounded,
  'multiselect': Icons.checklist_rounded,
  'checkbox': Icons.check_box_rounded,
  'file': Icons.attach_file_rounded,
  'email': Icons.alternate_email_rounded,
  'phone': Icons.phone_rounded,
};

class OrgFormsPage extends StatelessWidget {
  const OrgFormsPage({super.key, this.deptId});
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/forms', {'dept_id': deptId})..refresh(),
      child: Builder(builder: (context) {
        final p = context.read<OrgPaged>();
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: s.can('forms', 'insert', deptId)
              ? _fab(context, 'form_new', t('نموذج جديد', 'New form'), Icons.add_rounded, () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgFormBuilderScreen(deptId: deptId))));
                  p.refresh();
                })
              : null,
          body: PagedList<OrgPaged>(
            emptyText: t('لا نماذج بعد — حوّل الطلبات الورقية لنماذج إلكترونية', 'No forms yet — turn paper requests into online forms'),
            itemBuilder: (context, row) => _FormCard(row: row),
          ),
        );
      }),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final p = context.read<OrgPaged>();
    final dept = row['dept_id'] == null ? null : asInt(row['dept_id']);
    final counts = asMap(row['counts']);
    final waiting = asInt(counts['submitted']) + asInt(counts['in_review']);
    final url = '${s.base}/forms/${row['id']}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: RowCard(
        accent: waiting > 0 ? c.warning : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgFormResponsesScreen(form: row)))),
        child: Row(children: [
          IconBadge(Icons.assignment_rounded, c.primary, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              const SizedBox(height: 5),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusChip(statusLabel('${row['status']}'), statusColor(context, '${row['status']}')),
                OrgPill(_formKinds()[row['kind']] ?? '${row['kind']}'),
                OrgPill(t('${asInt(counts['total'])} رد', '${asInt(counts['total'])} responses'), color: c.textMedium),
                if (waiting > 0) OrgPill(t('$waiting بانتظارك', '$waiting waiting'), color: c.warning),
              ]),
            ]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'edit':
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgFormBuilderScreen(deptId: dept, edit: row))));
                  p.refresh();
                case 'open' || 'closed':
                  final r = await OrgApi.i.put(url, {'status': v}, v == 'open' ? t('النموذج مفتوح الآن ✅', 'The form is open ✅') : t('أُغلق النموذج', 'Form closed'));
                  if (r is Map) p.replaceRow(Map<String, dynamic>.from(r));
                case 'export':
                  await exportData(context, 'forms/${row['id']}/export');
                case 'delete':
                  if (!await confirm(context, message: t('حذف النموذج؟ إن كان له ردود سيُغلق فقط حفاظاً عليها.', 'Delete the form? If it has answers it is only closed, to keep them.'), danger: true)) return;
                  if (await OrgApi.i.del(url, t('تم', 'Done')) != null) p.refresh();
              }
            },
            itemBuilder: (_) => [
              if (s.can('forms', 'update', dept)) PopupMenuItem(value: 'edit', child: Text(t('تعديل الحقول', 'Edit fields'))),
              if (s.can('forms', 'update', dept) && row['status'] != 'open') PopupMenuItem(value: 'open', child: Text(t('فتح لاستقبال الردود', 'Open for answers'))),
              if (s.can('forms', 'update', dept) && row['status'] == 'open') PopupMenuItem(value: 'closed', child: Text(t('إغلاق', 'Close'))),
              if (s.can('forms', 'export', dept)) PopupMenuItem(value: 'export', child: Text(t('تصدير الردود (Excel / PDF / Word)', 'Export answers (Excel / PDF / Word)'))),
              if (s.can('forms', 'delete', dept)) PopupMenuItem(value: 'delete', child: Text(t('حذف', 'Delete'), style: TextStyle(color: c.danger))),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Drag to reorder · tap to edit · the first field type picked from a friendly grid.
class OrgFormBuilderScreen extends StatefulWidget {
  const OrgFormBuilderScreen({super.key, this.deptId, this.edit});
  final int? deptId;
  final Map<String, dynamic>? edit;

  @override
  State<OrgFormBuilderScreen> createState() => _OrgFormBuilderScreenState();
}

class _OrgFormBuilderScreenState extends State<OrgFormBuilderScreen> {
  late final _title = TextEditingController(text: '${widget.edit?['title'] ?? ''}');
  late final _desc = TextEditingController(text: '${widget.edit?['description'] ?? ''}');
  late String _kind = '${widget.edit?['kind'] ?? 'request'}';
  late bool _review = widget.edit?['requires_review'] != false;
  late bool _multiple = widget.edit?['allow_multiple'] == true;
  late bool _mandatory = widget.edit?['mandatory'] == true;
  late Map<String, dynamic> _audience = asMap(widget.edit?['audience']).isEmpty
      ? {'roles': ['student'], 'sub_orgs': true}
      : asMap(widget.edit?['audience']);
  late final List<Map<String, dynamic>> _fields = asMapList(widget.edit?['fields']);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _editField([int? index]) async {
    final f = index == null ? <String, dynamic>{'type': 'text', 'required': false} : {..._fields[index]};
    final label = TextEditingController(text: '${f['label'] ?? ''}');
    final help = TextEditingController(text: '${f['help'] ?? ''}');
    final opts = TextEditingController(text: ((f['options'] as List?) ?? const []).join('\n'));
    await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
          final c = ctx.colors;
          final needsOptions = f['type'] == 'select' || f['type'] == 'multiselect';
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(index == null ? t('حقل جديد', 'New field') : t('تعديل الحقل', 'Edit field')),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in fieldTypes().entries)
                  ChoiceChip(
                    avatar: Icon(fieldIcons[e.key], size: 16, color: f['type'] == e.key ? Colors.white : c.textMedium),
                    label: Text(e.value, style: TextStyle(fontFamily: 'tajawal', color: f['type'] == e.key ? Colors.white : c.textDark)),
                    selected: f['type'] == e.key,
                    selectedColor: c.primary,
                    showCheckmark: false,
                    onSelected: (_) => set(() => f['type'] = e.key),
                  ),
              ]),
              const SizedBox(height: 14),
              Field(controller: label, label: t('السؤال / عنوان الحقل', 'Question / field label')),
              if (needsOptions)
                Field(controller: opts, label: t('الخيارات (خيار في كل سطر)', 'Options (one per line)'), maxLines: 5),
              Field(controller: help, label: t('توضيح يساعد المستخدم (اختياري)', 'Helper text (optional)')),
              OrgSwitchRow(title: t('إجباري', 'Required'), value: f['required'] == true, onChanged: (v) => set(() => f['required'] = v)),
              const SizedBox(height: 8),
              PrimaryButton(
                isLoading: false,
                label: t('تم', 'Done'),
                onPressed: () {
                  if (label.text.trim().isEmpty) {
                    toast(t('اكتب السؤال', 'Write the question'), error: true);
                    return;
                  }
                  final options = opts.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  if (needsOptions && options.isEmpty) {
                    toast(t('أضف خياراً واحداً على الأقل', 'Add at least one option'), error: true);
                    return;
                  }
                  f['label'] = label.text.trim();
                  f['help'] = help.text.trim().isEmpty ? null : help.text.trim();
                  f['options'] = needsOptions ? options : <String>[];
                  setState(() => index == null ? _fields.add(f) : _fields[index] = f);
                  Navigator.pop(ctx);
                },
              ),
            ]),
          );
        }));
  }

  Future<void> _save({bool open = false}) async {
    if (_title.text.trim().length < 2) {
      toast(t('اكتب عنوان النموذج', 'Write the form title'), error: true);
      return;
    }
    if (open && _fields.isEmpty) {
      toast(t('أضف سؤالاً واحداً على الأقل', 'Add at least one question'), error: true);
      return;
    }
    final s = context.read<OrgSession>();
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'kind': _kind,
      'fields': _fields,
      'audience': _audience,
      'requires_review': _kind == 'survey' ? false : _review,
      'allow_multiple': _multiple,
      'mandatory': _mandatory,
      if (widget.edit == null) 'dept_id': widget.deptId,
    };
    var r = widget.edit == null
        ? await OrgApi.i.post('${s.base}/forms', body)
        : await OrgApi.i.put('${s.base}/forms/${widget.edit!['id']}', body);
    if (r is Map && open) {
      r = await OrgApi.i.put('${s.base}/forms/${r['id']}', {'status': 'open'});
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) {
      toast(open ? t('النموذج مفتوح الآن ويصل للجمهور ✅', 'The form is live ✅') : t('تم الحفظ', 'Saved'));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return BasePage(
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: widget.edit == null ? t('نموذج جديد', 'New form') : t('تعديل النموذج', 'Edit form')),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
        Section(
          title: t('عن النموذج', 'About the form'),
          icon: Icons.assignment_rounded,
          child: Column(children: [
            Field(controller: _title, label: t('العنوان — مثلاً: طلب إفادة قيد', 'Title — e.g. Enrollment certificate request')),
            Field(controller: _desc, label: t('ماذا يحتاج المتقدم أن يعرف؟', 'What should people know first?'), maxLines: 3),
            ChoiceRow<String>(options: _formKinds(), value: _kind, onChanged: (v) => setState(() => _kind = v)),
            if (_kind != 'survey')
              OrgSwitchRow(
                  title: t('يحتاج مراجعة واعتماد', 'Needs review & approval'),
                  subtitle: t('يحصل المتقدم على رقم متابعة ويُبلغ بالنتيجة', 'People get a tracking number and are told the result'),
                  value: _review,
                  onChanged: (v) => setState(() => _review = v)),
            OrgSwitchRow(
                title: t('إلزامي — يفتح على الرئيسية حتى يُرسَل', 'Mandatory — opens on the home screen until sent'),
                subtitle: t('للبيانات التي يجب على كل عضو إرسالها (تحديث بيانات، إقرار …)', 'For data every member must send (profile update, declaration …)'),
                value: _mandatory,
                onChanged: (v) => setState(() => _mandatory = v)),
            OrgSwitchRow(title: t('السماح بأكثر من رد للشخص', 'Allow more than one answer per person'),
                value: _multiple, onChanged: (v) => setState(() => _multiple = v)),
            OrgAudiencePicker(value: _audience, onChanged: (v) => setState(() => _audience = v)),
          ]),
        ),
        Section(
          title: t('الأسئلة (${_fields.length})', 'Questions (${_fields.length})'),
          icon: Icons.list_alt_rounded,
          trailing: TextButton.icon(onPressed: () => _editField(), icon: const Icon(Icons.add_rounded), label: Text(t('سؤال', 'Question'))),
          child: _fields.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t('ابدأ بإضافة أول سؤال — الاسم والبريد معروفان لدينا تلقائياً', 'Add the first question — we already know the name and e-mail'),
                      textAlign: TextAlign.center, style: orgText(context, color: c.textMedium)))
              : ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (a, b) => setState(() {
                    final f = _fields.removeAt(a);
                    _fields.insert(b > a ? b - 1 : b, f);
                  }),
                  children: [
                    for (var i = 0; i < _fields.length; i++)
                      Container(
                        key: ValueKey('f$i${_fields[i]['label']}'),
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          leading: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: c.textLight)),
                          title: Text('${_fields[i]['label']}', style: orgText(context, w: FontWeight.w700)),
                          subtitle: Text(
                              '${fieldTypes()[_fields[i]['type']] ?? ''}${_fields[i]['required'] == true ? ' · ${t('إجباري', 'required')}' : ''}',
                              style: orgText(context, size: 12, color: c.textMedium)),
                          onTap: () => _editField(i),
                          trailing: IconButton(
                              onPressed: () => setState(() => _fields.removeAt(i)),
                              icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
                        ),
                      ),
                  ],
                ),
        ),
        PrimaryButton(isLoading: _busy, label: t('حفظ وفتح للاستقبال', 'Save & open'), icon: Icons.rocket_launch_rounded,
            iconBefore: true, onPressed: () => _save(open: true)),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _save(),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: Text(t('حفظ كمسودة', 'Save as draft'), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class OrgFormResponsesScreen extends StatelessWidget {
  const OrgFormResponsesScreen({super.key, required this.form});
  final Map<String, dynamic> form;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/forms/${form['id']}/responses')..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final dept = form['dept_id'] == null ? null : asInt(form['dept_id']);
        return BasePage(
          useWebCard: true,
          maxWith: 900,
          appBar: ScreenAppBar(title: '${form['title']}', actions: [
            if (s.can('forms', 'export', dept))
              IconButton(
                  tooltip: t('تصدير Excel', 'Export Excel'),
                  onPressed: () => exportData(context, 'forms/${form['id']}/export'),
                  icon: const Icon(Icons.file_download_rounded)),
          ]),
          child: Column(children: [
            const SizedBox(height: 8),
            FilterChips<String>(
              options: {
                '': t('الكل', 'All'),
                'submitted': statusLabel('submitted'),
                'in_review': statusLabel('in_review'),
                'approved': t('موافق عليه', 'Approved'),
                'rejected': t('مرفوض', 'Rejected'),
              },
              value: '${p.filters['status'] ?? ''}',
              onChanged: (v) => p.setFilter('status', v),
            ),
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: t('لم تصل ردود بعد', 'No answers yet'),
                itemBuilder: (context, row) => _ResponseTile(row: row, form: form, dept: dept),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

class _ResponseTile extends StatelessWidget {
  const _ResponseTile({required this.row, required this.form, this.dept});
  final Map<String, dynamic> row, form;
  final int? dept;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = asMap(row['user']);
    final st = '${row['status']}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: RowCard(
        accent: st == 'submitted' ? c.warning : null,
        onTap: () => _openResponse(context, row, form, dept),
        child: Row(children: [
          AdminAvatar(name: '${u['name'] ?? '?'}', url: u['image_url'] as String?),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['name'] ?? ''}', style: orgText(context, w: FontWeight.w800)),
              Text('${row['ref'] ?? ''} · ${relTime(row['created_at'])}', textDirection: TextDirection.ltr,
                  style: orgText(context, size: 12, color: c.textMedium)),
            ]),
          ),
          StatusChip(statusLabel(st), statusColor(context, st)),
        ]),
      ),
    );
  }
}

Future<void> _openResponse(BuildContext context, Map<String, dynamic> row, Map<String, dynamic> form, int? dept) async {
  final s = context.read<OrgSession>();
  final p = context.read<OrgPaged>();
  final answers = asMap(row['answers']);
  final fields = asMapList(form['fields']);
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    Future<void> decide(String status) async {
      String? note;
      if (status == 'rejected' || status == 'approved') {
        note = await askText(ctx,
            title: status == 'rejected' ? t('ما المطلوب من صاحب الطلب؟', 'What should the person do?') : t('رسالة لصاحب الطلب (اختياري)', 'Message to the person (optional)'),
            multiline: true);
        if (note == null) return;
      }
      final r = await OrgApi.i.put('${s.base}/form-responses/${row['id']}', {'status': status, 'note': note},
          t('تم إبلاغ صاحب الطلب', 'The person was notified'));
      if (r is Map) {
        p.replaceRow(Map<String, dynamic>.from(r));
        if (ctx.mounted) Navigator.pop(ctx);
      }
    }

    String show(dynamic v) => v is List
        ? v.map((e) => e is Map ? '${e['name']}' : '$e').join('، ')
        : v is bool
            ? (v ? '✓' : '—')
            : '${v ?? '—'}';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader('${row['ref'] ?? ''}'),
        KeyValue(t('مقدم الطلب', 'From'), '${asMap(row['user'])['name'] ?? ''}'),
        KeyValue(t('التاريخ', 'Date'), shortDateTime('${row['created_at']}')),
        const Divider(height: 24),
        for (final f in fields) ...[
          Text('${f['label']}', style: orgText(ctx, size: 12, color: c.textLight)),
          const SizedBox(height: 2),
          if (f['type'] == 'file')
            Wrap(spacing: 6, children: [
              for (final a in asMapList(answers[f['key']]))
                ActionChip(avatar: const Icon(Icons.attach_file_rounded, size: 16), label: Text('${a['name']}'),
                    onPressed: () => openFileUrl('${a['url']}')),
            ])
          else
            Text(show(answers[f['key']]), style: orgText(ctx, w: FontWeight.w700)),
          const SizedBox(height: 12),
        ],
        if ('${row['reviewer_note'] ?? ''}'.isNotEmpty)
          KeyValue(t('ملاحظة المراجع', 'Reviewer note'), '${row['reviewer_note']}'),
        const SizedBox(height: 10),
        if (s.can('forms', 'approve', dept)) ...[
          Row(children: [
            Expanded(child: PrimaryButton(isLoading: false, background: c.success, label: t('موافقة', 'Approve'), onPressed: () => decide('approved'))),
            const SizedBox(width: 10),
            Expanded(child: PrimaryButton(isLoading: false, background: c.danger, label: t('رفض مع سبب', 'Decline'), onPressed: () => decide('rejected'))),
          ]),
        ],
        if (s.can('forms', 'update', dept) && row['status'] == 'submitted')
          TextButton.icon(onPressed: () => decide('in_review'), icon: const Icon(Icons.visibility_rounded),
              label: Text(t('تعليم كـ"قيد المراجعة"', 'Mark as in review'))),
      ]),
    );
  });
}

// ═════════════════════════════════════════════════════════════════════════════
//  Materials
// ═════════════════════════════════════════════════════════════════════════════

class OrgMaterialsPage extends StatelessWidget {
  const OrgMaterialsPage({super.key, this.deptId});
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/materials', {'dept_id': deptId})..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final folders = [for (final f in (p.extra['folders'] as List?) ?? const []) '$f'];
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: s.can('materials', 'insert', deptId)
              ? _fab(context, 'mat_new', t('رفع ملف', 'Upload'), Icons.upload_file_rounded,
                  () => _addMaterial(context, deptId, folders, p.refresh))
              : null,
          body: Column(children: [
            if (folders.isNotEmpty) ...[
              const SizedBox(height: 8),
              FilterChips<String>(
                options: {'': t('كل المجلدات', 'All folders'), for (final f in folders) f: f},
                value: '${p.filters['folder'] ?? ''}',
                onChanged: (v) => p.setFilter('folder', v),
              ),
            ],
            Expanded(
              child: PagedList<OrgPaged>(
                emptyText: t('المكتبة فارغة — ارفع اللوائح والأدلة والنماذج', 'The library is empty — upload regulations, guides and templates'),
                itemBuilder: (context, row) => _MaterialTile(row: row),
              ),
            ),
          ]),
        );
      }),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({required this.row});
  final Map<String, dynamic> row;

  IconData _icon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'png' || 'jpg' || 'jpeg' || 'webp' => Icons.image_rounded,
      'xls' || 'xlsx' || 'csv' => Icons.table_chart_rounded,
      'ppt' || 'pptx' => Icons.slideshow_rounded,
      'doc' || 'docx' => Icons.description_rounded,
      _ => Icons.link_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final p = context.read<OrgPaged>();
    final dept = row['dept_id'] == null ? null : asInt(row['dept_id']);
    final members = row['visibility'] == 'members';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: RowCard(
        onTap: () => openFileUrl('${row['file_url'] ?? row['link_url'] ?? ''}'),
        child: Row(children: [
          IconBadge(_icon('${row['file_name'] ?? ''}'), c.primary, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: [
                OrgPill(members ? t('للأعضاء', 'Members') : t('للفريق فقط', 'Team only'),
                    color: members ? c.success : c.textMedium, icon: members ? Icons.public_rounded : Icons.lock_rounded),
                if ('${row['folder'] ?? ''}'.isNotEmpty) OrgPill('${row['folder']}', icon: Icons.folder_rounded),
                if (fileSizeLabel(row['file_size']).isNotEmpty) OrgPill(fileSizeLabel(row['file_size']), color: c.textLight),
              ]),
            ]),
          ),
          if (s.can('materials', 'update', dept) || s.can('materials', 'delete', dept))
            PopupMenuButton<String>(
              onSelected: (v) async {
                final url = '${s.base}/materials/${row['id']}';
                if (v == 'vis') {
                  final r = await OrgApi.i.put(url, {'visibility': members ? 'team' : 'members'}, t('تم', 'Done'));
                  if (r is Map) p.replaceRow(Map<String, dynamic>.from(r));
                } else if (await confirm(context, message: t('حذف الملف؟', 'Delete this file?'), danger: true)) {
                  if (await OrgApi.i.del(url, t('تم الحذف', 'Deleted')) != null) p.refresh();
                }
              },
              itemBuilder: (_) => [
                if (s.can('materials', 'update', dept))
                  PopupMenuItem(value: 'vis', child: Text(members ? t('إخفاء عن الأعضاء', 'Team only') : t('مشاركة مع الأعضاء', 'Share with members'))),
                if (s.can('materials', 'delete', dept))
                  PopupMenuItem(value: 'del', child: Text(t('حذف', 'Delete'), style: TextStyle(color: c.danger))),
              ],
            ),
        ]),
      ),
    );
  }
}

Future<void> _addMaterial(BuildContext context, int? deptId, List<String> folders, VoidCallback onSaved) async {
  final s = context.read<OrgSession>();
  final title = TextEditingController();
  final folder = TextEditingController();
  final link = TextEditingController();
  Map<String, dynamic>? file;
  bool members = false, busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('إضافة للمكتبة', 'Add to the library')),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () async {
                set(() => busy = true);
                final f = await orgPickAndUpload('${s.base}/uploads');
                set(() {
                  busy = false;
                  if (f != null) {
                    file = f;
                    if (title.text.isEmpty) title.text = '${f['name']}'.replaceAll(RegExp(r'\.[^.]+$'), '');
                  }
                });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: c.primary.withValues(alpha: 0.06),
                  border: Border.all(color: c.primary.withValues(alpha: 0.35), width: 1.4),
                ),
                child: Column(children: [
                  busy ? const AppLoadingIndicator(size: 36) : Icon(file == null ? Icons.cloud_upload_rounded : Icons.check_circle_rounded,
                      size: 36, color: file == null ? c.primary : c.success),
                  const SizedBox(height: 8),
                  Text(file == null ? t('اختر ملفاً (حتى 20 ميجابايت)', 'Choose a file (up to 20 MB)') : '${file!['name']}',
                      style: orgText(ctx, w: FontWeight.w700)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            if (file == null) Field(controller: link, label: t('أو ضع رابطاً', 'or paste a link'), ltr: true),
            Field(controller: title, label: t('اسم واضح للملف', 'A clear title')),
            Field(controller: folder, label: t('المجلد (مثلاً: لوائح، نماذج)', 'Folder (e.g. Regulations, Templates)')),
            if (folders.isNotEmpty)
              Wrap(spacing: 6, children: [
                for (final f in folders) ActionChip(label: Text(f), onPressed: () => set(() => folder.text = f)),
              ]),
            OrgSwitchRow(
                title: t('مشاركة مع الأعضاء (الطلاب/المعلمين)', 'Share with members (students/teachers)'),
                subtitle: t('إن لم تفعّلها يبقى الملف لفريق الإدارة فقط', 'Off = only the department team sees it'),
                value: members,
                onChanged: (v) => set(() => members = v)),
            const SizedBox(height: 8),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (file == null && link.text.trim().isEmpty) {
                  toast(t('اختر ملفاً أو ضع رابطاً', 'Choose a file or paste a link'), error: true);
                  return;
                }
                set(() => busy = true);
                final r = await OrgApi.i.post('${s.base}/materials', {
                  'dept_id': deptId,
                  'title': title.text.trim().isEmpty ? '${file?['name'] ?? link.text}' : title.text.trim(),
                  'folder': folder.text.trim(),
                  'file_url': file?['url'],
                  'file_name': file?['name'],
                  'file_type': file?['type'],
                  'file_size': file?['size'],
                  'link_url': file == null ? link.text.trim() : null,
                  'visibility': members ? 'members' : 'team',
                }, t('أُضيف للمكتبة', 'Added to the library'));
                if (!ctx.mounted) return;
                set(() => busy = false);
                if (r != null) {
                  onSaved();
                  Navigator.pop(ctx);
                }
              },
            ),
          ]),
        );
      }));
}

// ═════════════════════════════════════════════════════════════════════════════
//  Complaints
// ═════════════════════════════════════════════════════════════════════════════

class OrgComplaintsPage extends StatelessWidget {
  const OrgComplaintsPage({super.key, this.deptId});
  final int? deptId;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgPaged('${s.base}/complaints', {'dept_id': deptId, 'status': 'active'})..refresh(),
      child: Builder(builder: (context) {
        final p = context.watch<OrgPaged>();
        final key = p.filters['overdue'] == true
            ? 'overdue'
            : p.filters['mine'] == true
                ? 'mine'
                : '${p.filters['status'] ?? ''}';
        return Column(children: [
          const SizedBox(height: 8),
          FilterChips<String>(
            options: {
              'active': t('المفتوحة', 'Open'),
              'overdue': t('متأخرة', 'Overdue'),
              'mine': t('المسندة لي', 'Assigned to me'),
              'resolved': t('تم حلها', 'Resolved'),
              'closed': t('مغلقة', 'Closed'),
            },
            value: key,
            onChanged: (v) async {
              p.filters
                ..remove('overdue')
                ..remove('mine');
              if (v == 'overdue' || v == 'mine') {
                p.filters[v] = true;
                await p.setFilter('status', 'active');
              } else {
                await p.setFilter('status', v);
              }
            },
          ),
          if (s.can('complaints', 'export', deptId))
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: () => exportData(context, 'complaints/export', {if (deptId != null) 'dept_id': deptId}),
                icon: const Icon(Icons.file_download_rounded, size: 18),
                label: Text(t('تصدير التقرير', 'Export report'), style: const TextStyle(fontFamily: 'tajawal')),
              ),
            ),
          Expanded(
            child: PagedList<OrgPaged>(
              emptyText: t('لا شكاوى هنا — هذا خبر جيد 🌿', 'Nothing here — good news 🌿'),
              itemBuilder: (context, row) => _ComplaintCard(row: row),
            ),
          ),
        ]);
      }),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    final p = context.read<OrgPaged>();
    final st = '${row['status']}';
    final overdue = row['overdue'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: RowCard(
        accent: overdue ? c.danger : (row['unread'] == true ? c.primary : null),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgComplaintThreadScreen(id: asInt(row['id'])))));
          p.refresh();
        },
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            IconBadge(Icons.support_agent_rounded, priorityColor(context, '${row['priority']}'), size: 42),
            if (row['unread'] == true)
              PositionedDirectional(top: 0, end: 0,
                  child: Container(width: 10, height: 10, decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle))),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, w: FontWeight.w800)),
              Text('${row['ref']} · ${asMap(row['user'])['name'] ?? ''} · ${relTime(row['created_at'])}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: orgText(context, size: 12, color: c.textMedium)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                StatusChip(statusLabel(st), statusColor(context, st)),
                OrgPill(priorityLabel('${row['priority']}'), color: priorityColor(context, '${row['priority']}')),
                if (overdue) OrgPill(t('تجاوزت المهلة', 'Overdue'), color: c.danger, icon: Icons.timer_off_rounded),
                if (row['is_anonymous'] == true) OrgPill(t('هوية محجوبة', 'Anonymous'), color: c.textMedium, icon: Icons.visibility_off_rounded),
                if (row['assigned_to'] != null) OrgPill('${asMap(row['assigned_to'])['name']}', icon: Icons.person_rounded, color: c.textMedium),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class OrgComplaintThreadScreen extends StatefulWidget {
  const OrgComplaintThreadScreen({super.key, required this.id});
  final int id;

  @override
  State<OrgComplaintThreadScreen> createState() => _OrgComplaintThreadScreenState();
}

class _OrgComplaintThreadScreenState extends State<OrgComplaintThreadScreen> {
  Map<String, dynamic>? _d;
  bool _failed = false, _sending = false, _internal = false;
  final _msg = TextEditingController();

  String get _url => '${context.read<OrgSession>().base}/complaints/${widget.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (!mounted) return;
    setState(() {
      _d = r ?? _d;
      _failed = r == null && _d == null;
    });
  }

  Future<void> _patch(Map<String, dynamic> body, String ok) async {
    final r = await OrgApi.i.put(_url, body, ok);
    if (r != null) _load();
  }

  Future<void> _send() async {
    if (_msg.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final r = await OrgApi.i.post('$_url/messages', {'body': _msg.text.trim(), 'internal': _internal});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r != null) {
      _msg.clear();
      _load();
    }
  }

  Future<void> _transfer() async {
    final s = context.read<OrgSession>();
    final r = await OrgApi.i.getMap('${s.base}/departments');
    if (r == null || !mounted) return;
    final depts = asMapList(r['items'])
        .where((d) => d['id'] != _d?['dept_id'] && ((d['features'] as List?) ?? const []).contains('complaints'))
        .toList();
    final picked = await showAdminSheet<int>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SheetHeader(t('تحويل إلى إدارة', 'Transfer to a department')),
          for (final d in depts)
            ListTile(
              leading: IconBadge(deptIcon(d['icon']), hexColor(d['color'], ctx.colors.primary), size: 38),
              title: Text(orgNameOf(d), style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700)),
              onTap: () => Navigator.pop(ctx, asInt(d['id'])),
            ),
        ]));
    if (picked != null) _patch({'dept_id': picked}, t('تم التحويل', 'Transferred'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final d = _d;
    final dept = d?['dept_id'] == null ? null : asInt(d?['dept_id']);
    final canAct = d != null && s.can('complaints', 'update', dept);
    return BasePage(
      useWebCard: true,
      maxWith: 820,
      appBar: ScreenAppBar(title: d == null ? t('الشكوى', 'Complaint') : '${d['ref']}', actions: [
        if (canAct)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              if (v.startsWith('st:')) return _patch({'status': v.substring(3)}, t('تم إبلاغ صاحب الشكوى', 'The person was notified'));
              if (v.startsWith('pr:')) return _patch({'priority': v.substring(3)}, t('تم', 'Done'));
              if (v == 'transfer') return _transfer();
              if (v == 'unassign') return _patch({'unassign': true}, t('تم', 'Done'));
            },
            itemBuilder: (_) => [
              for (final st in ['in_progress', 'waiting', 'resolved', 'closed'])
                if (d['status'] != st) PopupMenuItem(value: 'st:$st', child: Text('${t('الحالة', 'Status')}: ${statusLabel(st)}')),
              const PopupMenuDivider(),
              for (final pr in ['low', 'medium', 'high', 'urgent'])
                if (d['priority'] != pr) PopupMenuItem(value: 'pr:$pr', child: Text('${t('الأولوية', 'Priority')}: ${priorityLabel(pr)}')),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'transfer', child: Text(t('تحويل لإدارة أخرى', 'Transfer to another department'))),
              if (d['assigned_to'] != null) PopupMenuItem(value: 'unassign', child: Text(t('إلغاء الإسناد', 'Unassign'))),
            ],
          ),
      ]),
      child: OrgAsync(
        loading: d == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: d == null
            ? const SizedBox.shrink()
            : Column(children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
                      Section(
                        title: '${d['subject']}',
                        icon: Icons.support_agent_rounded,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            StatusChip(statusLabel('${d['status']}'), statusColor(context, '${d['status']}')),
                            OrgPill(priorityLabel('${d['priority']}'), color: priorityColor(context, '${d['priority']}')),
                            if (d['overdue'] == true) OrgPill(t('تجاوزت المهلة', 'Overdue'), color: c.danger, icon: Icons.timer_off_rounded),
                            if (d['due_at'] != null && d['overdue'] != true)
                              OrgPill('${t('الرد قبل', 'Reply by')} ${shortDateTime('${d['due_at']}')}', color: c.textMedium, icon: Icons.timer_rounded),
                          ]),
                          const SizedBox(height: 10),
                          Text('${d['body']}', style: orgText(context)),
                          for (final a in asMapList(d['attachments']))
                            TextButton.icon(onPressed: () => openFileUrl('${a['url']}'), icon: const Icon(Icons.attach_file_rounded), label: Text('${a['name']}')),
                          const Divider(height: 22),
                          KeyValue(t('من', 'From'), '${asMap(d['user'])['name'] ?? ''}'),
                          if (d['assigned_to'] != null) KeyValue(t('المسؤول', 'Handled by'), '${asMap(d['assigned_to'])['name']}'),
                          if (d['rating'] != null) KeyValue(t('التقييم', 'Rating'), '${'★' * asInt(d['rating'])} ${d['rating_note'] ?? ''}'),
                          if (canAct && asMapList(d['assignable']).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(t('إسناد إلى', 'Assign to'), style: orgText(context, size: 12, color: c.textLight)),
                            const SizedBox(height: 4),
                            Wrap(spacing: 6, runSpacing: 6, children: [
                              for (final u in asMapList(d['assignable']))
                                ChoiceChip(
                                  label: Text('${u['name']}', style: const TextStyle(fontFamily: 'tajawal')),
                                  selected: asMap(d['assigned_to'])['id'] == u['id'],
                                  onSelected: (_) => _patch({'assigned_to': u['id']}, t('تم الإسناد', 'Assigned')),
                                ),
                            ]),
                          ],
                        ]),
                      ),
                      for (final m in asMapList(d['messages'])) _Bubble(m: m),
                    ]),
                  ),
                ),
                if (canAct && d['status'] != 'closed')
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                    child: Column(children: [
                      Row(children: [
                        ChoiceChip(
                          label: Text(t('رد على صاحب الشكوى', 'Reply'), style: const TextStyle(fontFamily: 'tajawal')),
                          selected: !_internal,
                          onSelected: (_) => setState(() => _internal = false),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.lock_rounded, size: 15),
                          label: Text(t('ملاحظة داخلية', 'Internal note'), style: const TextStyle(fontFamily: 'tajawal')),
                          selected: _internal,
                          onSelected: (_) => setState(() => _internal = true),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _msg,
                            minLines: 1,
                            maxLines: 4,
                            style: const TextStyle(fontFamily: 'tajawal'),
                            decoration: InputDecoration(
                              hintText: _internal ? t('لا يراها صاحب الشكوى', 'Not visible to the person') : t('اكتب رداً لطيفاً وواضحاً…', 'Write a kind, clear reply…'),
                              filled: true,
                              fillColor: _internal ? c.warning.withValues(alpha: 0.08) : c.inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(backgroundColor: _internal ? c.warning : c.primary),
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ]),
                    ]),
                  ),
              ]),
      ),
    );
  }
}

/// One message of a complaint thread (staff side and member side share it).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.m});
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) => ComplaintBubble(m: m, staffView: true);
}

class ComplaintBubble extends StatelessWidget {
  const ComplaintBubble({super.key, required this.m, required this.staffView});
  final Map<String, dynamic> m;
  final bool staffView;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fromStaff = m['from_staff'] == true;
    final internal = m['is_internal'] == true;
    final mineSide = staffView ? fromStaff : !fromStaff;
    final bg = internal ? c.warning.withValues(alpha: 0.12) : mineSide ? c.primary.withValues(alpha: 0.10) : c.inputBg;
    final sender = asMap(m['sender']);
    return Align(
      alignment: mineSide ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: internal ? Border.all(color: c.warning.withValues(alpha: 0.4)) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (internal) ...[Icon(Icons.lock_rounded, size: 13, color: c.warning), const SizedBox(width: 4)],
            Text(
                internal
                    ? t('ملاحظة داخلية', 'Internal note')
                    : fromStaff
                        ? (staffView ? '${sender['name'] ?? ''}' : t('فريق الإدارة', 'Department team'))
                        : (sender.isEmpty ? t('صاحب الشكوى', 'The person') : '${sender['name']}'),
                style: orgText(context, size: 11.5, w: FontWeight.w800, color: internal ? c.warning : c.textMedium)),
          ]),
          const SizedBox(height: 3),
          Text('${m['body']}', style: orgText(context)),
          for (final a in asMapList(m['attachments']))
            TextButton.icon(onPressed: () => openFileUrl('${a['url']}'), icon: const Icon(Icons.attach_file_rounded, size: 16), label: Text('${a['name']}')),
          Text(relTime(m['created_at']), style: orgText(context, size: 10.5, color: c.textLight)),
        ]),
      ),
    );
  }
}
