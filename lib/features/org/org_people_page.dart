// lib/features/org/org_people_page.dart — students · teachers · staff of the selected organization.
// Manual add, Excel import (+ template), Excel export, join requests, and the admin-assistant permission matrix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_navigator.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';
import 'package:flutter_education_app/design/app_buttons.dart' show AppButton;
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_member_form.dart';
import 'onboarding/onboarding_entry.dart';
import 'org_access_page.dart' show OrgPersonAccess;
import 'org_invitations.dart' show invitationsFeatureKey;
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredOrgInvitationsPage, showDeferredOrgInviteSheet;
import 'package:flutter_education_app/config/app_config.dart';
import 'org_v3.dart';
import 'org_page_kit.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import '../admin/admin_table_export.dart' show exportPagedList, orgMembersExport;
import 'package:flutter_education_app/design/app_username.dart';

/// Members of the organization (D-103 page anatomy, org_page_kit.dart): the kind as ONE segmented control
/// (Students · Teachers · Staff, only the kinds I may view) · search · ONE status filter ("Active ▾") · More (⋯:
/// import from Excel, the Excel template, export) · ONE primary action "Add …" (FAB on phones, button when wide).
class OrgPeoplePage extends StatefulWidget {
  const OrgPeoplePage({super.key});

  @override
  State<OrgPeoplePage> createState() => _OrgPeoplePageState();
}

class _OrgPeoplePageState extends State<OrgPeoplePage> {
  int _kind = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final tabs = <(String, String, String, String)>[
      if (s.can('students')) ('student', t('الطلاب', 'Students'), 'students', 'students'),
      if (s.can('teachers')) ('teacher', t('المدرسون', 'Teachers'), 'teachers', 'teachers'),
      if (s.can('staff')) ('teacher_assistant,admin_assistant,org_admin', t('فريق العمل', 'Staff'), 'staff', 'staff'),
    ];
    if (tabs.isEmpty) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الأعضاء', 'You cannot view members'));
    final i = _kind.clamp(0, tabs.length - 1);
    final x = tabs[i];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (tabs.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, 0),
          child: OrgSegmented<int>(
            value: i,
            options: [for (var k = 0; k < tabs.length; k++) (k, tabs[k].$2)],
            onChanged: (k) => setState(() => _kind = k),
          ),
        ),
      // a new kind = a fresh list (the old TabBarView rebuilt an off-screen tab the same way)
      Expanded(child: _MembersTab(key: ValueKey(x.$1), roles: x.$1, module: x.$3, kind: x.$4)),
    ]);
  }
}

class _MembersTab extends StatefulWidget {
  const _MembersTab({super.key, required this.roles, required this.module, required this.kind});
  final String roles, module, kind;

  @override
  State<_MembersTab> createState() => _MembersTabState();
}

/// A student or teacher opens their connected panel (D-290): what THIS organization's rights show of them, decided by
/// the server. Staff have no such detail; their row keeps its menu only.
class _MembersTabState extends State<_MembersTab> {
  late final _panel = EntityPanelController(rowKind: _kind);

  EntityKind? get _kind => switch (widget.kind) {
        'students' => EntityKind.student,
        'teachers' => EntityKind.teacher,
        _ => null,
      };

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    final view = ChangeNotifierProvider(
      create: (_) => OrgMembersProvider(s, widget.roles)..refresh(),
      child: _MembersView(module: widget.module, kind: widget.kind, roles: widget.roles, entityKind: _kind),
    );
    if (_kind == null) return view;
    return MasterDetailScaffold(controller: _panel, rootLabel: t('الأعضاء', 'Members'), list: view);
  }
}

class _MembersView extends StatelessWidget {
  const _MembersView({required this.module, required this.kind, required this.roles, this.entityKind});
  final String module, kind, roles;
  final EntityKind? entityKind;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembersProvider>();
    final s = context.watch<OrgSession>();
    final status = {
      'active': t('نشط', 'Active'),
      if (kind != 'staff') 'pending': t('طلبات الانضمام', 'Join requests'),
      'scheduled': membershipStatusLabels()['scheduled']!,
      'expired': membershipStatusLabels()['expired']!,
      'suspended': membershipStatusLabels()['suspended']!,
      'removed': _memberStatusLabel('removed'),
      if (kind != 'staff') 'rejected': t('مرفوض', 'Rejected'),
    };
    final addLabel = switch (kind) {
      'students' => t('إضافة طالب', 'Add student'),
      'teachers' => t('إضافة مدرس', 'Add teacher'),
      _ => t('إضافة عضو', 'Add member'),
    };
    return OrgPageBody(
      primary: s.can(module, 'insert')
          ? OrgPrimaryAction(
              id: 'add_member',
              icon: Icons.person_add_alt_1_rounded,
              label: addLabel,
              onTap: () async {
                // the one front door (D-1208): the onboarding wizard; null = not available, so the legacy form below
                final viaOnb = await openOnboardingAdd(context, module: module);
                if (viaOnb != null) {
                  if (viaOnb) p.refresh();
                  return;
                }
                final r = await showOrgMemberForm(context,
                    roles: kind == 'students' ? const ['student'] : kind == 'teachers' ? const ['teacher'] : const ['teacher_assistant', 'admin_assistant', 'org_admin']);
                if (r != null) p.refresh();
              },
            )
          : null,
      search: OrgSearchField(hint: t('بحث بالاسم أو البريد أو الهاتف أو @اسم المستخدم', 'Name, e-mail, phone or @username'), onChanged: p.setSearch),
      filter: OrgFilterButton<String>(
        value: p.status,
        options: status,
        defaultValue: 'active',
        label: t('الحالة', 'Status'),
        onChanged: p.setStatusFilter,
      ),
      more: [
        if (s.can(module, 'insert') && !AppConfig.disableList.contains(invitationsFeatureKey)) ...[
          OrgMenuItem(
            icon: Icons.mail_outline_rounded,
            label: t('دعوة بالبريد أو الهاتف', 'Invite by e-mail or phone'),
            onTap: () => showDeferredOrgInviteSheet(context, orgId: s.currentId ?? 0, orgName: s.name, initialRole: kind == 'students' ? 'student' : kind == 'teachers' ? 'teacher' : 'staff'),
          ),
          OrgMenuItem(
            icon: Icons.mark_email_unread_outlined,
            label: t('الدعوات المرسلة', 'Sent invitations'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(value: s, child: deferredOrgInvitationsPage(orgId: s.currentId ?? 0, orgName: s.name)))), // ROUTE: org.invitations
          ),
        ],
        if (s.can(module, 'insert')) ...[
          OrgMenuItem(
            icon: Icons.upload_file_rounded,
            label: t('استيراد من Excel', 'Import from Excel'),
            onTap: () async {
              final viaOnb = await openOnboardingImport(context, module: module);
              if (viaOnb != null) {
                if (viaOnb && context.mounted) p.refresh();
                return;
              }
              if (await importExcelFlow(context, kind) && context.mounted) p.refresh();
            },
          ),
          OrgMenuItem(
            icon: Icons.description_outlined,
            label: t('تنزيل نموذج Excel', 'Download the Excel template'),
            onTap: () => downloadExcel(context, 'template/$kind'),
          ),
        ],
        if (s.can(module, 'export'))
          OrgMenuItem(
            icon: Icons.ios_share_rounded,
            label: t('تصدير (Excel · Word · PDF)', 'Export (Excel · Word · PDF)'),
            onTap: () => exportPagedList(context, p, (rows) => orgMembersExport(kind, rows, orgName: s.name, orgId: s.currentId, roles: roles, status: p.status)),
          ),
      ],
      child: PagedList<OrgMembersProvider>(
        emptyText: p.status == 'pending'
            ? t('لا توجد طلبات انضمام الآن', 'No join requests right now')
            : p.status == 'active'
                ? t('لا يوجد أعضاء بعد — أضف أول عضو أو استورد قائمة من Excel', 'No members yet — add the first one or import a list from Excel')
                : t('لا أحد بهذه الحالة', 'Nobody with this status'),
        minTileWidth: 520,
        itemBuilder: (ctx, row) => _MemberTile(row: row, module: module, entityKind: entityKind),
      ),
    );
  }
}

String _roleLabel(String r) => {
      'student': t('طالب', 'Student'),
      'teacher': t('مدرس', 'Teacher'),
      'teacher_assistant': t('معيد', 'Teaching assistant'),
      'admin_assistant': t('مساعد إداري', 'Admin assistant'),
    }[r] ??
    r;

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.row, required this.module, this.entityKind});
  final Map<String, dynamic> row;
  final String module;
  final EntityKind? entityKind;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.read<OrgMembersProvider>();
    final u = Map<String, dynamic>.from(row['user'] as Map);
    final role = '${row['role']}';
    final eff = '${row['effective_status'] ?? row['status']}';
    final pending = row['status'] == 'pending';
    final removed = eff == 'removed'; // the membership was ended by an admin (D-282); the row is kept
    final ended = eff == 'expired' || eff == 'suspended';
    final id = asInt(row['id']);
    final depts = asMapList(row['departments']);
    final kind = entityKind;
    return OrgMemberRowView(
      // a live member only: a join request or a removed member is out of this organization's scope
      onTap: kind == null || pending || removed
          ? null
          : () => EntityNavigator.open(
              context, EntityRef(kind, asInt(u['id']), label: '${u['name']}', imageUrl: u['image_url'] as String?)),
      name: '${u['name']}',
      email: '${u['email']}',
      username: usernameFrom(u),
      imageUrl: u['image_url'] as String?,
      accent: pending ? c.warning : (ended ? c.danger : null),
      period: pending ? null : membershipPeriodText(row),
      periodEnded: ended,
      chips: [
                // the role only where it differs between rows (the Staff list); Students / Teachers say it once, in the switcher
                if (module == 'staff') StatusChip(_roleLabel(role), c.primary),
                if (eff != 'active') StatusChip(_memberStatusLabel(eff), eff == 'removed' ? c.textMedium : statusColor(context, eff == 'scheduled' ? 'pending' : eff)),
                if ((row['student_code'] ?? '').toString().isNotEmpty) InfoChip(Icons.tag_rounded, '${row['student_code']}', c.textMedium),
                if (row['academic_level'] != null) InfoChip(Icons.stairs_rounded, '${row['academic_level']}', c.textMedium),
                if (row['cohort'] != null) InfoChip(Icons.group_rounded, memberCohortLabels()['${row['cohort']}'] ?? '${row['cohort']}', c.textMedium),
                for (final d in depts) InfoChip(Icons.apartment_rounded, '${d['title'] ?? ''}${d['is_head'] == true ? ' ★' : ''}'.trim().isEmpty ? '#${d['dept_id']}' : '${d['title'] ?? ''}${d['is_head'] == true ? ' ★' : ''}', c.textMedium),
                if (u['is_active'] == false) StatusChip(t('معطّل', 'Disabled'), c.danger),
      ],
      trailing: [
          if (pending && s.can('requests', 'update')) ...[
            IconButton(tooltip: t('موافقة', 'Approve'), onPressed: () => p.decide(id, true), icon: Icon(Icons.check_circle_rounded, color: c.success)),
            IconButton(tooltip: t('رفض', 'Reject'), onPressed: () => p.decide(id, false), icon: Icon(Icons.cancel_rounded, color: c.danger)),
          ] else
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'access':
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgPersonAccess(userId: asInt(u['id']))))); // ROUTE: org.person_access
                  case 'perm':
                    await _permissions(context, p, row);
                  case 'code':
                    await _editCode(context, p, row);
                  case 'edit':
                    if (await showOrgMemberForm(context, edit: row) != null) p.refresh();
                  case 'extend':
                    if (await showMembershipExtend(context, row) != null) p.refresh();
                  case 'suspend':
                    if (await confirm(context,
                        message: t('إيقاف عضويته في هذه المؤسسة؟ تتوقف صلاحياته فيها فقط، ويمكن إعادة تفعيلها.',
                            'Suspend their membership here? Only their access to this organization stops; it can be reactivated.'),
                        danger: true)) {
                      await p.update(id, {'status': 'suspended'});
                    }
                  case 'toggle':
                    await p.update(id, {'is_active': u['is_active'] == false});
                  case 'remove':
                    if (await confirm(context, message: t('إزالة العضو من المؤسسة؟ (حسابه لا يُحذف)', 'Remove from the organization? (the account stays)'), danger: true)) {
                      await p.remove(id);
                    }
                }
              },
              itemBuilder: (_) => removed
                  ? [
                      // nothing that only makes sense for a live member: re-admitting goes through the normal extend / reactivate flow
                      if (s.can(module, 'update')) PopupMenuItem(value: 'extend', child: Text(t('إعادة قبوله', 'Re-admit'))),
                    ]
                  : [
                if (s.can(module, 'update')) PopupMenuItem(value: 'edit', child: Text(t('بيانات العضوية', 'Membership details'))),
                if (s.can(module, 'update'))
                  PopupMenuItem(value: 'extend', child: Text(ended ? t('تمديد / إعادة تفعيل', 'Extend / reactivate') : t('تمديد العضوية', 'Extend membership'))),
                if (s.can(module, 'update') && !ended) PopupMenuItem(value: 'suspend', child: Text(t('إيقاف العضوية', 'Suspend membership'))),
                if (s.can('roles') && !pending) PopupMenuItem(value: 'access', child: Text(t('ما يستطيع فعله', 'Effective permissions'))),
                if (role == 'admin_assistant' && s.isOrgAdmin) PopupMenuItem(value: 'perm', child: Text(t('الصلاحيات', 'Permissions'))),
                if (role == 'student' && s.can(module, 'update')) PopupMenuItem(value: 'code', child: Text(t('الرقم الجامعي', 'Student number'))),
                if (s.can(module, 'update')) PopupMenuItem(value: 'toggle', child: Text(u['is_active'] == false ? t('تفعيل الحساب', 'Enable account') : t('تعطيل الحساب', 'Disable account'))),
                if (s.can(module, 'delete')) PopupMenuItem(value: 'remove', child: Text(t('إزالة من المؤسسة', 'Remove'), style: TextStyle(color: c.danger))),
              ],
            ),
      ],
    );
  }
}

/// One member row over plain values: avatar, name, e-mail (always LTR), the chips, the membership period and the
/// actions at the end. The layout harness pumps it (test/ui/polish_org_admin_layout_test.dart).
class OrgMemberRowView extends StatelessWidget {
  const OrgMemberRowView({
    super.key,
    required this.name,
    required this.email,
    this.username,
    this.imageUrl,
    this.accent,
    this.chips = const [],
    this.period,
    this.periodEnded = false,
    this.trailing = const [],
    this.onTap,
  });

  final String name, email;

  /// Opens the member's detail (null: the row opens nothing).
  final VoidCallback? onTap;

  /// The member's @username (without "@"), shown under the name; null = none.
  final String? username;
  final String? imageUrl;
  final Color? accent;
  final List<Widget> chips;

  /// "Member since … · ends …"; null hides the line (a pending request has no period yet).
  final String? period;
  final bool periodEnded;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: orgListInset, vertical: AppSpace.xxs),
      child: RowCard(
        accent: accent,
        onTap: onTap,
        child: Row(children: [
          AdminAvatar(name: name, url: imageUrl),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
              if (username != null) AppUsernameLine(username),
              Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.meta(context).copyWith(color: c.textMedium)),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: chips),
              ],
              if (period != null && period!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xxs),
                  child: Text(period!, style: AppType.meta(context).copyWith(color: periodEnded ? c.danger : c.textLight)),
                ),
            ]),
          ),
          ...trailing,
        ]),
      ),
    );
  }
}

Future<void> _editCode(BuildContext context, OrgMembersProvider p, Map<String, dynamic> row) async {
  final v = await askText(context, title: t('الرقم الجامعي', 'Student number'), hint: '${row['student_code'] ?? ''}');
  if (v != null) await p.update(asInt(row['id']), {'student_code': v.trim()});
}

// ── permission matrix (admin assistant) ─────────────────────────────────────

const _modules = ['courses', 'students', 'teachers', 'staff', 'schedule', 'requests'];
const _actions = ['view', 'insert', 'update', 'delete'];

Future<void> _permissions(BuildContext context, OrgMembersProvider p, Map<String, dynamic> row) async {
  final modLabel = {
    'courses': t('الكورسات', 'Courses'),
    'students': t('الطلاب', 'Students'),
    'teachers': t('المدرسون', 'Teachers'),
    'staff': t('الهيئة المعاونة', 'Staff'),
    'schedule': t('الجدول الدراسي', 'Timetable'),
    'requests': t('طلبات الانضمام', 'Join requests'),
  };
  final actLabel = {'view': t('عرض', 'View'), 'insert': t('إضافة', 'Insert'), 'update': t('تعديل', 'Update'), 'delete': t('حذف', 'Delete')};
  final cur = <String, Set<String>>{
    for (final m in _modules) m: {...(((row['permissions'] as Map?)?[m] as List?) ?? const []).map((e) => '$e')},
  };
  bool busy = false;
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xxs, AppSpace.md, AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('صلاحيات ${(row['user'] as Map)['name']}', 'Permissions · ${(row['user'] as Map)['name']}')),
            Text(t('اختر ما يستطيع المساعد الإداري فعله في كل قسم. "عرض" يُضاف تلقائياً مع أي صلاحية أخرى.', 'Choose what this assistant can do in each module. "View" is added automatically with any other right.'),
                style: AppType.label(ctx).copyWith(color: c.textMedium)),
            const SizedBox(height: AppSpace.sm),
            for (final m in _modules)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpace.xs),
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(AppRadius.card)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(modLabel[m]!, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(spacing: AppSpace.xs, children: [
                    for (final a in _actions)
                      FilterChip(
                        label: Text(actLabel[a]!, style: AppType.label(context).copyWith(color: context.colors.textDark)),
                        selected: cur[m]!.contains(a),
                        onSelected: (on) => set(() {
                          if (on) {
                            cur[m]!.add(a);
                            if (a != 'view') cur[m]!.add('view');
                          } else {
                            cur[m]!.remove(a);
                            if (a == 'view') cur[m]!.clear();
                          }
                        }),
                      ),
                  ]),
                ]),
              ),
            AppButton.primary(
              busy: busy,
              label: t('حفظ الصلاحيات', 'Save permissions'),
              onPressed: () async {
                set(() => busy = true);
                final ok = await p.setPermissions(asInt(row['id']), {for (final e in cur.entries) if (e.value.isNotEmpty) e.key: e.value.toList()});
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (ok) Navigator.pop(ctx);
                }
              },
            ),
          ]),
        );
      }));
}

/// A member's status text; "removed" (an admin ended the membership, D-282) is not in the shared table.
String _memberStatusLabel(String eff) => membershipStatusLabels()[eff] ?? eff;
