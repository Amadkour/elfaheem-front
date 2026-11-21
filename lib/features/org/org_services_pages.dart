// lib/features/org/org_services_pages.dart
//
// Department services — staff side. Every page works for the whole organization (deptId == null) or for ONE
// department (deptId set): same widgets, same look, rights checked with OrgSession.can(module, action, deptId).
//
//   OrgAnnouncementsPage   → org_announcements.dart (re-exported)
//   OrgFormsPage           requests / surveys / applications → OrgFormBuilderScreen · OrgFormResponsesScreen
//   OrgMaterialsPage       department library (files or links, team-only or for members)
//   OrgComplaintsPage      inbox with SLA → OrgComplaintThreadScreen (reply · internal note · assign · transfer)
//                          + the sender's student strip (GET /complaints/{id} `student`, student lifecycle §3.9):
//                          Open file · Request a meeting · Change status / flag (POST /complaints/{id}/status, a flag
//                          preselected, the reason names the complaint; ComplaintStudentStrip, ComplaintStatusApi)
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
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart' show EntityGuardedChip;
import '../admin/admin_list.dart';
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show showComplaintMeetingSheet;
import 'org_common.dart';
import 'org_reports/report_page.dart' show OrgComplaintReportPage;
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import 'org_page_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'governance/gov_api.dart' show GovApi;
import 'governance/gov_forms_assign.dart' show GovFormAssignmentsView, showGovFormAssignSheet;
import 'governance/gov_wiring.dart' show govEnabled;
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show ContextExitButton;
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppButton, AppCard;
import 'package:flutter_education_app/design/app_bidi.dart' show bidiIsolate, ltrIsolate;
import 'org_v3.dart' show OrgCall, orgCall;
import 'students/my_ask_page.dart' show myAsksEnabled;
import 'students/student_ask_sheet.dart' show showStudentAskSheet;
import 'students/student_status_models.dart' show StatusSource;
import 'students/student_status_sheet.dart' show showStudentStatusSheet;
import 'students/students_api.dart' show StudentsApi;
import 'students/students_models.dart' show StudentChip, StudentUser;
import 'students/students_parts.dart' show StudentAvatar, StudentStatusChip;
import 'students/students_wiring.dart' show openStudentFile;


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

/// A pushed page's readable column: the dashboard header keeps the page's full width (its one row needs the room),
/// the content stays as narrow as the older page was.
Widget _readable(double maxWidth, Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SizedBox.expand(child: child)),
    );

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
        return OrgPageBody(
          primary: s.can('forms', 'insert', deptId)
              ? OrgPrimaryAction(
                  id: 'new_form',
                  icon: Icons.add_rounded,
                  label: t('نموذج جديد', 'New form'),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgFormBuilderScreen(deptId: deptId))));
                    p.refresh();
                  },
                )
              : null,
          child: PagedList<OrgPaged>(
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
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
      child: RowCard(
        accent: waiting > 0 ? c.warning : null,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgFormResponsesScreen(form: row)))),
        child: Row(children: [
          IconBadge(Icons.assignment_rounded, c.primary, size: 42),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
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

  /// The dashboard header's Refresh must never rebuild the editor (it would lose the questions typed so far).
  final _refresh = OrgPageRefresh()..attach(() async {});

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _refresh.dispose();
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
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SheetHeader(index == null ? t('حقل جديد', 'New field') : t('تعديل الحقل', 'Edit field')),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                for (final e in fieldTypes().entries)
                  ChoiceChip(
                    avatar: Icon(fieldIcons[e.key], size: AppIconSize.sm, color: f['type'] == e.key ? c.onHero : c.textMedium),
                    label: Text(e.value, style: TextStyle(fontFamily: AppFonts.family, color: f['type'] == e.key ? c.onHero : c.textDark)),
                    selected: f['type'] == e.key,
                    selectedColor: c.primary,
                    showCheckmark: false,
                    onSelected: (_) => set(() => f['type'] = e.key),
                  ),
              ]),
              const SizedBox(height: AppSpace.md),
              Field(controller: label, label: t('السؤال / عنوان الحقل', 'Question / field label')),
              if (needsOptions)
                Field(controller: opts, label: t('الخيارات (خيار في كل سطر)', 'Options (one per line)'), maxLines: 5),
              Field(controller: help, label: t('توضيح يساعد المستخدم (اختياري)', 'Helper text (optional)')),
              OrgSwitchRow(title: t('إجباري', 'Required'), value: f['required'] == true, onChanged: (v) => set(() => f['required'] = v)),
              const SizedBox(height: AppSpace.xs),
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
    final title = widget.edit == null ? t('نموذج جديد', 'New form') : t('تعديل النموذج', 'Edit form');
    final body = _body(context);
    if (orgUsesDashboardHeader(context, null)) {
      final name = '${widget.edit?['title'] ?? ''}';
      return OrgPushedPage(
        title: title,
        subtitle: name.isEmpty ? null : name,
        refresh: _refresh,
        child: _readable(800, body),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 800,
      appBar: ScreenAppBar(title: title, actions: const [ContextExitButton()]),
      child: body,
    );
  }

  Widget _body(BuildContext context) {
    final c = context.colors;
    return ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.xxl), children: [
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
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Text(t('ابدأ بإضافة أول سؤال — الاسم والبريد معروفان لدينا تلقائياً', 'Add the first question — we already know the name and e-mail'),
                      textAlign: TextAlign.center, style: AppType.row(context).copyWith(color: c.textMedium)))
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
                      // a Material (not a coloured box) under the ListTile, so its ink shows
                      Padding(
                        key: ValueKey('f$i${_fields[i]['label']}'),
                        padding: const EdgeInsets.only(bottom: AppSpace.xs),
                        child: Material(
                        color: c.inputBg,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: ListTile(
                          leading: ReorderableDragStartListener(index: i, child: Icon(Icons.drag_indicator_rounded, color: c.textLight)),
                          title: Text('${_fields[i]['label']}', style: AppType.bodyStrong(context)),
                          subtitle: Text(
                              '${fieldTypes()[_fields[i]['type']] ?? ''}${_fields[i]['required'] == true ? ' · ${t('إجباري', 'required')}' : ''}',
                              style: AppType.meta(context).copyWith(color: c.textMedium)),
                          onTap: () => _editField(i),
                          trailing: IconButton(tooltip: t('حذف', 'Delete'), 
                              onPressed: () => setState(() => _fields.removeAt(i)),
                              icon: Icon(Icons.delete_outline_rounded, color: c.danger)),
                        ),
                        ),
                      ),
                  ],
                ),
        ),
        PrimaryButton(isLoading: _busy, label: t('حفظ وفتح للاستقبال', 'Save & open'), icon: Icons.rocket_launch_rounded,
            iconBefore: true, onPressed: () => _save(open: true)),
        const SizedBox(height: AppSpace.xs),
        OutlinedButton(
          onPressed: _busy ? null : () => _save(),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control))),
          child: Text(t('حفظ كمسودة', 'Save as draft'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
        ),
      ]);
  }
}

class OrgFormResponsesScreen extends StatelessWidget {
  const OrgFormResponsesScreen({super.key, required this.form});
  final Map<String, dynamic> form;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    if (orgUsesDashboardHeader(context, null)) return _dashboardPage(context, s);
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
            // governance (D-057): who MUST answer, who did, reminders
            if (govEnabled() && s.currentId != null && s.can('forms', 'update', dept))
              IconButton(
                  tooltip: t('إسناد النموذج لأشخاص', 'Assign the form'),
                  onPressed: () => showGovFormAssignSheet(context, GovApi(s.currentId!), asInt(form['id'])),
                  icon: const Icon(Icons.person_add_alt_1_rounded)),
            if (govEnabled() && s.currentId != null)
              IconButton(
                  tooltip: t('من أجاب ومن لم يجب', 'Assignments'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => BasePage(
                          useWebCard: true,
                          maxWith: 900,
                          appBar: ScreenAppBar(title: t('المكلّفون بالنموذج', 'Form assignments'), actions: const [ContextExitButton()]),
                          child: GovFormAssignmentsView(asInt(form['id']), orgId: s.currentId)))),
                  icon: const Icon(Icons.checklist_rounded)),
           const ContextExitButton()]),
          child: _list(p, dept),
        );
      }),
    );
  }

  Widget _list(OrgPaged p, int? dept) => Column(children: [
        const SizedBox(height: AppSpace.xs),
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
      ]);

  /// Staff in the organization's dashboard: its header (Back · the form · its answers); the export and
  /// governance actions in More. The list lives under the page's refresh scope, so Refresh reloads it.
  Widget _dashboardPage(BuildContext context, OrgSession s) {
    final dept = form['dept_id'] == null ? null : asInt(form['dept_id']);
    final more = <OrgMenuItem>[
      if (s.can('forms', 'export', dept))
        OrgMenuItem(
            icon: Icons.file_download_rounded,
            label: t('تصدير الردود', 'Export answers'),
            onTap: () => exportData(context, 'forms/${form['id']}/export')),
      // governance (D-057): who MUST answer, who did, reminders
      if (govEnabled() && s.currentId != null && s.can('forms', 'update', dept))
        OrgMenuItem(
            icon: Icons.person_add_alt_1_rounded,
            label: t('إسناد النموذج لأشخاص', 'Assign the form'),
            onTap: () => showGovFormAssignSheet(context, GovApi(s.currentId!), asInt(form['id']))),
      if (govEnabled() && s.currentId != null)
        OrgMenuItem(
            icon: Icons.checklist_rounded,
            label: t('من أجاب ومن لم يجب', 'Assignments'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OrgPushedPage(
                    title: t('المكلّفون بالنموذج', 'Form assignments'),
                    subtitle: '${form['title']}',
                    child: _readable(900, GovFormAssignmentsView(asInt(form['id']), orgId: s.currentId)))))),
    ];
    return OrgPushedPage(
      title: '${form['title']}',
      subtitle: t('الردود', 'Answers'),
      primaryAction: more.isEmpty ? null : OrgMoreMenu(items: more),
      child: _readable(
        900,
        ChangeNotifierProvider(
          create: (_) => OrgPaged('${s.base}/forms/${form['id']}/responses')..refresh(),
          child: Builder(builder: (context) => _list(context.watch<OrgPaged>(), dept)),
        ),
      ),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.xxs),
      child: RowCard(
        accent: st == 'submitted' ? c.warning : null,
        onTap: () => _openResponse(context, row, form, dept),
        child: Row(children: [
          AdminAvatar(name: '${u['name'] ?? '?'}', url: u['image_url'] as String?),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['name'] ?? ''}', style: AppType.bodyStrong(context)),
              Text('${row['ref'] ?? ''} · ${relTime(row['created_at'])}', textDirection: TextDirection.ltr,
                  style: AppType.meta(context).copyWith(color: c.textMedium)),
            ]),
          ),
          StatusChip(statusLabel(st), statusColor(context, st)),
        ]),
      ),
    );
  }
}

/// "From" on a form response / a complaint: a guarded chip when the server names the person a student or a teacher
/// (`person_kind`, D-290; a hidden identity has none), else the name. Whether the record opens is the server's answer.
class OrgPersonFrom extends StatelessWidget {
  const OrgPersonFrom(this.label, this.user, {super.key});
  final String label;
  final Map user;

  static EntityRef? refOf(Map u) {
    final kind = switch ('${u['person_kind']}') {
      'student' => EntityKind.student,
      'teacher' => EntityKind.teacher,
      _ => null,
    };
    final id = asInt(u['id']);
    if (kind == null || id <= 0) return null;
    return EntityRef(kind, id, label: '${u['name'] ?? ''}', imageUrl: u['image_url'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    final ref = refOf(user);
    if (ref == null) return KeyValue(label, '${user['name'] ?? ''}');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: AppType.meta(context))),
        Flexible(child: EntityGuardedChip(ref, maxWidth: 320)),
      ]),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SheetHeader('${row['ref'] ?? ''}'),
        OrgPersonFrom(t('مقدم الطلب', 'From'), asMap(row['user'])),
        KeyValue(t('التاريخ', 'Date'), shortDateTime('${row['created_at']}')),
        const Divider(height: 24),
        for (final f in fields) ...[
          Text('${f['label']}', style: AppType.meta(ctx).copyWith(color: c.textLight)),
          const SizedBox(height: AppSpace.xxs / 2),
          if (f['type'] == 'file')
            Wrap(spacing: AppSpace.xs, children: [
              for (final a in asMapList(answers[f['key']]))
                ActionChip(avatar: const Icon(Icons.attach_file_rounded, size: AppIconSize.sm), label: Text('${a['name']}'),
                    onPressed: () => openFileUrl('${a['url']}')),
            ])
          else
            Text(show(answers[f['key']]), style: AppType.bodyStrong(ctx)),
          const SizedBox(height: AppSpace.sm),
        ],
        if ('${row['reviewer_note'] ?? ''}'.isNotEmpty)
          KeyValue(t('ملاحظة المراجع', 'Reviewer note'), '${row['reviewer_note']}'),
        const SizedBox(height: AppSpace.sm),
        if (s.can('forms', 'approve', dept)) ...[
          Row(children: [
            Expanded(child: PrimaryButton(isLoading: false, background: c.success, label: t('موافقة', 'Approve'), onPressed: () => decide('approved'))),
            const SizedBox(width: AppSpace.sm),
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
        return OrgPageBody(
          primary: s.can('materials', 'insert', deptId)
              ? OrgPrimaryAction(
                  id: 'upload_material',
                  icon: Icons.upload_file_rounded,
                  label: t('رفع ملف', 'Upload'),
                  onTap: () => _addMaterial(context, deptId, folders, p.refresh),
                )
              : null,
          // ONE filter: the folder (only once there are folders)
          filter: folders.isEmpty
              ? null
              : OrgFilterButton<String>(
                  icon: Icons.folder_open_rounded,
                  label: t('المجلد', 'Folder'),
                  options: {'': t('كل المجلدات', 'All folders'), for (final f in folders) f: f},
                  value: '${p.filters['folder'] ?? ''}',
                  defaultValue: '',
                  onChanged: (v) => p.setFilter('folder', v),
                ),
          child: PagedList<OrgPaged>(
            emptyText: t('المكتبة فارغة — ارفع اللوائح والأدلة والنماذج', 'The library is empty — upload regulations, guides and templates'),
            itemBuilder: (context, row) => _MaterialTile(row: row),
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
      child: RowCard(
        onTap: () => openFileUrl('${row['file_url'] ?? row['link_url'] ?? ''}'),
        child: Row(children: [
          IconBadge(_icon('${row['file_name'] ?? ''}'), c.primary, size: 42),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, children: [
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
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xxs, AppSpace.lg, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('إضافة للمكتبة', 'Add to the library')),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
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
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  color: c.primaryWash,
                  border: Border.all(color: c.primary.withValues(alpha: 0.35), width: 1.4),
                ),
                child: Column(children: [
                  busy ? const AppLoadingIndicator(size: 36) : Icon(file == null ? Icons.cloud_upload_rounded : Icons.check_circle_rounded,
                      size: AppIconSize.hero, color: file == null ? c.primary : c.success),
                  const SizedBox(height: AppSpace.xs),
                  Text(file == null ? t('اختر ملفاً (حتى 20 ميجابايت)', 'Choose a file (up to 20 MB)') : '${file!['name']}',
                      style: AppType.bodyStrong(ctx)),
                ]),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            if (file == null) Field(controller: link, label: t('أو ضع رابطاً', 'or paste a link'), ltr: true),
            Field(controller: title, label: t('اسم واضح للملف', 'A clear title')),
            Field(controller: folder, label: t('المجلد (مثلاً: لوائح، نماذج)', 'Folder (e.g. Regulations, Templates)')),
            if (folders.isNotEmpty)
              Wrap(spacing: AppSpace.xs, children: [
                for (final f in folders) ActionChip(label: Text(f), onPressed: () => set(() => folder.text = f)),
              ]),
            OrgSwitchRow(
                title: t('مشاركة مع الأعضاء (الطلاب/المعلمين)', 'Share with members (students/teachers)'),
                subtitle: t('إن لم تفعّلها يبقى الملف لفريق الإدارة فقط', 'Off = only the department team sees it'),
                value: members,
                onChanged: (v) => set(() => members = v)),
            const SizedBox(height: AppSpace.xs),
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
        // the page anatomy (D-103): ONE status filter · More (⋯: the designed report, a quick export) · the cards.
        // No primary action: complaints come from members; the staff answer them.
        return OrgPageBody(
          filter: OrgFilterButton<String>(
            label: t('الحالة', 'Status'),
            defaultValue: 'active',
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
          more: [
            if (s.can('complaints', 'export', deptId)) ...[
              OrgMenuItem(
                icon: Icons.design_services_rounded,
                label: t('تقرير مصمَّم وإرسال', 'Designed report & send'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OrgComplaintReportPage(deptId: deptId))),
              ),
              OrgMenuItem(
                icon: Icons.file_download_rounded,
                label: t('تصدير سريع (Excel)', 'Quick export (Excel)'),
                onTap: () => exportData(context, 'complaints/export', {if (deptId != null) 'dept_id': deptId}),
              ),
            ],
          ],
          child: PagedList<OrgPaged>(
            emptyText: t('لا شكاوى هنا — هذا خبر جيد 🌿', 'Nothing here — good news 🌿'),
            itemBuilder: (context, row) => _ComplaintCard(row: row),
          ),
        );
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
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
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
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${row['subject']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              Text([ltrIsolate('${row['ref'] ?? ''}'), bidiIsolate('${asMap(row['user'])['name'] ?? ''}'), relTime(row['created_at'])].where((x) => x.isNotEmpty).join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: c.textMedium)),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
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
  /// [orgId] / [canAct]: opened from outside the organization (the profile's Complaints page, D-086) — that
  /// organization's routes and the right the server gave the row, instead of the open [OrgSession]'s.
  const OrgComplaintThreadScreen({super.key, required this.id, this.orgId, this.canAct});
  final int id;
  final int? orgId;
  final bool? canAct;

  @override
  State<OrgComplaintThreadScreen> createState() => _OrgComplaintThreadScreenState();
}

class _OrgComplaintThreadScreenState extends State<OrgComplaintThreadScreen> {
  Map<String, dynamic>? _d;
  bool _failed = false, _sending = false, _internal = false;
  final _msg = TextEditingController();

  String get _base => widget.orgId != null ? '$orgBase/orgs/${widget.orgId}' : context.read<OrgSession>().base;
  String get _url => '$_base/complaints/${widget.id}';

  /// The dashboard header's Refresh reloads the thread in place (a reply being typed stays).
  final _refresh = OrgPageRefresh();

  @override
  void initState() {
    super.initState();
    _refresh.attach(_load);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _msg.dispose();
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await OrgApi.i.getMap(_url);
    if (!mounted) return;
    setState(() {
      _d = r ?? _d;
      _failed = r == null && _d == null;
    });
    if (r != null) _refresh.markUpdated();
  }

  Future<void> _menu(String v) async {
    if (v.startsWith('st:')) return _patch({'status': v.substring(3)}, t('تم إبلاغ صاحب الشكوى', 'The person was notified'));
    if (v.startsWith('pr:')) return _patch({'priority': v.substring(3)}, t('تم', 'Done'));
    if (v == 'transfer') return _transfer();
    if (v == 'unassign') return _patch({'unassign': true}, t('تم', 'Done'));
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

  /// "Request a meeting" from the student strip: a meeting ask to the sender (D-1400; source = this complaint, the
  /// student accepts or declines it), or the calendar meeting with the sender when asks are switched off.
  Future<void> _meeting(OrgSession s, Map<String, dynamic> d) async {
    final orgId = widget.orgId ?? s.currentId!;
    final st = asMap(d['student']);
    if (myAsksEnabled() && asInt(st['id']) > 0) {
      final a = await showStudentAskSheet(context, orgId, asInt(st['id']),
          kind: 'meeting', source: StatusSource('complaint', widget.id), name: '${st['name'] ?? ''}', canFullscreen: s.can('student_status', 'update'));
      if (a != null && mounted) _load();
      return;
    }
    if (!mounted) return;
    if (await showComplaintMeetingSheet(context, orgId: widget.orgId ?? s.currentId!, complaintId: widget.id, subject: '${d['subject']}')) _load();
  }

  /// "Change status / flag": the status sheet on the sender, a flag preselected, sent through the complaint's route
  /// (source = this complaint; the thread gets an internal note).
  Future<void> _status(OrgSession s, Map<String, dynamic> d, Map<String, dynamic> st) async {
    final orgId = widget.orgId ?? s.currentId!;
    final r = await showStudentStatusSheet(
      context,
      orgId,
      asInt(st['id']),
      name: '${st['name'] ?? ''}',
      decision: 'flag.struggling',
      reason: t('بخصوص الشكوى ${d['ref']}', 'About complaint ${d['ref']}'),
      source: StatusSource('complaint', widget.id),
      api: ComplaintStatusApi(orgId, _url),
    );
    if (r != null && mounted) _load();
  }

  Future<void> _transfer() async {
    final r = await OrgApi.i.getMap('$_base/departments');
    if (r == null || !mounted) return;
    final depts = asMapList(r['items'])
        .where((d) => d['id'] != _d?['dept_id'] && ((d['features'] as List?) ?? const []).contains('complaints'))
        .toList();
    final picked = await showAdminSheet<int>(context, (ctx) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg), children: [
          SheetHeader(t('تحويل إلى إدارة', 'Transfer to a department')),
          for (final d in depts)
            ListTile(
              leading: IconBadge(deptIcon(d['icon']), hexColor(d['color'], ctx.colors.primary), size: 38),
              title: Text(orgNameOf(d), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, asInt(d['id'])),
            ),
        ]));
    if (picked != null) _patch({'dept_id': picked}, t('تم التحويل', 'Transferred'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final d = _d;
    final dept = d?['dept_id'] == null ? null : asInt(d?['dept_id']);
    final canAct = d != null && (widget.canAct ?? s.can('complaints', 'update', dept));
    final title = d == null ? t('الشكوى', 'Complaint') : ltrIsolate('${d['ref']}');
    if (orgUsesDashboardHeader(context, widget.orgId)) {
      return OrgPushedPage(
        title: title,
        subtitle: d == null ? null : '${d['subject'] ?? ''}',
        refresh: _refresh,
        primaryAction: canAct
            ? OrgMoreMenu(items: [
                for (final st in ['in_progress', 'waiting', 'resolved', 'closed'])
                  if (d['status'] != st)
                    OrgMenuItem(
                        icon: Icons.flag_rounded,
                        label: '${t('الحالة', 'Status')}: ${statusLabel(st)}',
                        onTap: () => _menu('st:$st')),
                for (final pr in ['low', 'medium', 'high', 'urgent'])
                  if (d['priority'] != pr)
                    OrgMenuItem(
                        icon: Icons.low_priority_rounded,
                        label: '${t('الأولوية', 'Priority')}: ${priorityLabel(pr)}',
                        onTap: () => _menu('pr:$pr')),
                OrgMenuItem(
                    icon: Icons.swap_horiz_rounded,
                    label: t('تحويل لإدارة أخرى', 'Transfer to another department'),
                    onTap: () => _menu('transfer')),
                if (d['assigned_to'] != null)
                  OrgMenuItem(icon: Icons.person_off_rounded, label: t('إلغاء الإسناد', 'Unassign'), onTap: () => _menu('unassign')),
              ])
            : null,
        child: _readable(820, _body(context, s, d, canAct)),
      );
    }
    return BasePage(
      useWebCard: true,
      maxWith: 820,
      appBar: ScreenAppBar(title: title, actions: [
        if (canAct)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _menu,
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
       const ContextExitButton()]),
      child: _body(context, s, d, canAct),
    );
  }

  Widget _body(BuildContext context, OrgSession s, Map<String, dynamic>? d, bool canAct) {
    final c = context.colors;
    return OrgAsync(
        loading: d == null && !_failed,
        failed: _failed,
        onRetry: _load,
        child: d == null
            ? const SizedBox.shrink()
            : Column(children: [
                Expanded(
                  child: AppRefresh(
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md), children: [
                      if (d['student'] is Map && d['is_anonymous'] != true) ...[
                        ComplaintStudentStrip(
                          student: asMap(d['student']),
                          onOpenFile: () => openStudentFile(context, widget.orgId ?? s.currentId!, asInt(asMap(d['student'])['id']), name: '${asMap(d['student'])['name'] ?? ''}'),
                          onMeeting: canAct && d['status'] != 'closed' ? () => _meeting(s, d) : null,
                          onStatus: canAct ? () => _status(s, d, asMap(d['student'])) : null,
                        ),
                        const SizedBox(height: AppSpace.sm),
                      ],
                      Section(
                        title: '${d['subject']}',
                        icon: Icons.support_agent_rounded,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                            StatusChip(statusLabel('${d['status']}'), statusColor(context, '${d['status']}')),
                            OrgPill(priorityLabel('${d['priority']}'), color: priorityColor(context, '${d['priority']}')),
                            if (d['overdue'] == true) OrgPill(t('تجاوزت المهلة', 'Overdue'), color: c.danger, icon: Icons.timer_off_rounded),
                            if (d['due_at'] != null && d['overdue'] != true)
                              OrgPill('${t('الرد قبل', 'Reply by')} ${shortDateTime('${d['due_at']}')}', color: c.textMedium, icon: Icons.timer_rounded),
                          ]),
                          const SizedBox(height: AppSpace.sm),
                          Text('${d['body']}', style: AppType.row(context)),
                          for (final a in asMapList(d['attachments']))
                            TextButton.icon(onPressed: () => openFileUrl('${a['url']}'), icon: const Icon(Icons.attach_file_rounded), label: Text('${a['name']}')),
                          const Divider(height: 22),
                          OrgPersonFrom(t('من', 'From'), asMap(d['user'])),
                          if (canAct && d['is_anonymous'] != true && d['status'] != 'closed')
                            Align(alignment: AlignmentDirectional.centerStart, child: TextButton.icon(onPressed: () async { if (await showComplaintMeetingSheet(context, orgId: widget.orgId ?? s.currentId!, complaintId: widget.id, subject: '${d['subject']}')) _load(); }, icon: const Icon(Icons.event_available_rounded), label: Text(t('تحويل إلى اجتماع', 'Turn into a meeting')))),
                          if (d['assigned_to'] != null) KeyValue(t('المسؤول', 'Handled by'), '${asMap(d['assigned_to'])['name']}'),
                          if (d['rating'] != null) KeyValue(t('التقييم', 'Rating'), '${'★' * asInt(d['rating'])} ${d['rating_note'] ?? ''}'),
                          if (canAct && asMapList(d['assignable']).isNotEmpty) ...[
                            const SizedBox(height: AppSpace.xs),
                            Text(t('إسناد إلى', 'Assign to'), style: AppType.meta(context).copyWith(color: c.textLight)),
                            const SizedBox(height: AppSpace.xxs),
                            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
                              for (final u in asMapList(d['assignable']))
                                ChoiceChip(
                                  label: Text('${u['name']}', style: TextStyle(fontFamily: AppFonts.family)),
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
                    padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.sm),
                    decoration: BoxDecoration(color: c.cardBg, border: Border(top: BorderSide(color: c.divider))),
                    child: Column(children: [
                      // a Wrap: on a narrow phone the second chip goes under the first instead of overflowing
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                        ChoiceChip(
                          label: Text(t('رد على صاحب الشكوى', 'Reply'), style: TextStyle(fontFamily: AppFonts.family)),
                          selected: !_internal,
                          onSelected: (_) => setState(() => _internal = false),
                        ),
                        ChoiceChip(
                          avatar: const Icon(Icons.lock_rounded, size: AppIconSize.xs),
                          label: Text(t('ملاحظة داخلية', 'Internal note'), style: TextStyle(fontFamily: AppFonts.family)),
                          selected: _internal,
                          onSelected: (_) => setState(() => _internal = true),
                        ),
                      ]),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _msg,
                            minLines: 1,
                            maxLines: 4,
                            style: TextStyle(fontFamily: AppFonts.family),
                            decoration: InputDecoration(
                              hintText: _internal ? t('لا يراها صاحب الشكوى', 'Not visible to the person') : t('اكتب رداً لطيفاً وواضحاً…', 'Write a kind, clear reply…'),
                              filled: true,
                              fillColor: _internal ? c.warning.withValues(alpha: 0.08) : c.inputBg,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.card), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.xs),
                        IconButton.filled(tooltip: t('إرسال', 'Send'), 
                          style: IconButton.styleFrom(backgroundColor: _internal ? c.warning : c.primary),
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
                              : Icon(Icons.send_rounded, color: c.onHero),
                        ),
                      ]),
                    ]),
                  ),
              ]),
    );
  }
}

/// The status sheet's calls sent through POST /complaints/{cid}/status (source = the complaint; the server writes the
/// thread's internal note). The answer `{mode, event, decision_id, messages}` reads as the sheet's StatusResult.
class ComplaintStatusApi extends StudentsApi {
  ComplaintStatusApi(int orgId, this.complaintUrl, [ApiClient? api]) : _client = api ?? ApiClient(), super(orgId, api);

  /// `…/orgs/{o}/complaints/{cid}`.
  final String complaintUrl;
  final ApiClient _client;

  Map<String, dynamic> _body(Map<String, dynamic> body, bool propose) => {...body, 'propose': propose}..remove('source');

  @override
  Future<OrgCall> changeStatus(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _client.post('$complaintUrl/status', body: _body(body, false)), quiet: quiet);

  @override
  Future<OrgCall> proposeStatus(int uid, Map<String, dynamic> body, {bool quiet = true}) =>
      orgCall(() => _client.post('$complaintUrl/status', body: _body(body, true)), quiet: quiet);
}

/// The complaint sender's strip: avatar, name, number, status chip and the three actions the server allows
/// (`can: {open_file, status, ask}`). Plain values.
class ComplaintStudentStrip extends StatelessWidget {
  const ComplaintStudentStrip({super.key, required this.student, this.onOpenFile, this.onMeeting, this.onStatus});

  final Map<String, dynamic> student;
  final VoidCallback? onOpenFile, onMeeting, onStatus;

  @override
  Widget build(BuildContext context) {
    final st = student;
    final can = asMap(st['can']);
    final code = '${st['student_code'] ?? ''}'.trim();
    final user = StudentUser.fromJson({'id': st['id'], 'name': st['name'], 'image_url': st['image_url']});
    return AppCard(
      key: const ValueKey('complaint.student'),
      padding: const EdgeInsets.all(AppSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          StudentAvatar(user: user),
          AppSpace.gapSm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${st['name'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
              const SizedBox(height: AppSpace.xxs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (st['chip'] is Map) StudentStatusChip(StudentChip.fromJson(st['chip'])),
                if (code.isNotEmpty) Text(code, style: AppType.meta(context)),
              ]),
            ]),
          ),
        ]),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (can['open_file'] == true && onOpenFile != null)
            AppButton.secondary(key: const ValueKey('complaint.student.file'), label: t('فتح الملف', 'Open file'), icon: Icons.folder_shared_rounded, onPressed: onOpenFile),
          if (can['ask'] == true && onMeeting != null)
            AppButton.tonal(key: const ValueKey('complaint.student.meeting'), label: t('طلب اجتماع', 'Request a meeting'), icon: Icons.event_available_rounded, onPressed: onMeeting),
          if (can['status'] == true && onStatus != null)
            AppButton.tonal(key: const ValueKey('complaint.student.status'), label: t('تغيير الحالة / علامة', 'Change status / flag'), icon: Icons.flag_rounded, onPressed: onStatus),
        ]),
      ]),
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
        margin: const EdgeInsets.only(bottom: AppSpace.xs),
        padding: const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xs),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: internal ? Border.all(color: c.warning.withValues(alpha: 0.4)) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (internal) ...[Icon(Icons.lock_rounded, size: AppIconSize.xs, color: c.warning), const SizedBox(width: AppSpace.xxs)],
            Flexible(child: Text(
                internal
                    ? t('ملاحظة داخلية', 'Internal note')
                    : fromStaff
                        ? (staffView ? '${sender['name'] ?? ''}' : t('فريق الإدارة', 'Department team'))
                        : (sender.isEmpty ? t('صاحب الشكوى', 'The person') : '${sender['name']}'),
                style: AppType.meta(context).copyWith(fontWeight: FontWeight.w600, color: internal ? c.warning : c.textMedium))),
          ]),
          const SizedBox(height: AppSpace.xxs),
          Text('${m['body']}', style: AppType.row(context)),
          for (final a in asMapList(m['attachments']))
            TextButton.icon(onPressed: () => openFileUrl('${a['url']}'), icon: const Icon(Icons.attach_file_rounded, size: AppIconSize.sm), label: Text('${a['name']}')),
          Text(relTime(m['created_at']), style: AppType.meta(context).copyWith(color: c.textLight)),
        ]),
      ),
    );
  }
}
