// lib/features/org/org_people_page.dart — students · teachers · staff of the selected organization.
// Manual add, Excel import (+ template), Excel export, join requests, and the admin-assistant permission matrix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import 'org_common.dart';
import 'org_providers.dart';
import 'org_ui.dart';
import 'org_member_form.dart';
import 'org_v3.dart';
import '../admin/admin_table_export.dart' show exportPagedList, orgMembersExport;

class OrgPeoplePage extends StatelessWidget {
  const OrgPeoplePage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    final tabs = <(String, String, String, String)>[
      if (s.can('students')) ('student', t('الطلاب', 'Students'), 'students', 'students'),
      if (s.can('teachers')) ('teacher', t('المدرسون', 'Teachers'), 'teachers', 'teachers'),
      if (s.can('staff')) ('teacher_assistant,admin_assistant,org_admin', t('الهيئة المعاونة والإدارة', 'Staff & admins'), 'staff', 'staff'),
    ];
    if (tabs.isEmpty) return OrgEmpty(icon: Icons.lock_rounded, title: t('لا تملك صلاحية عرض الأعضاء', 'You cannot view members'));
    return DefaultTabController(
      length: tabs.length,
      child: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16)),
          child: TabBar(
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(14)),
            labelColor: c.onHero,
            unselectedLabelColor: c.textMedium,
            labelStyle: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800),
            tabs: [for (final x in tabs) Tab(text: x.$2, height: 40)],
          ),
        ),
        Expanded(
          child: TabBarView(children: [
            for (final x in tabs) _MembersTab(key: ValueKey(x.$1), roles: x.$1, module: x.$3, kind: x.$4),
          ]),
        ),
      ]),
    );
  }
}

class _MembersTab extends StatelessWidget {
  const _MembersTab({super.key, required this.roles, required this.module, required this.kind});
  final String roles, module, kind;

  @override
  Widget build(BuildContext context) {
    final s = context.read<OrgSession>();
    return ChangeNotifierProvider(
      create: (_) => OrgMembersProvider(s, roles)..refresh(),
      child: _MembersView(module: module, kind: kind, roles: roles),
    );
  }
}

class _MembersView extends StatelessWidget {
  const _MembersView({required this.module, required this.kind, required this.roles});
  final String module, kind, roles;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<OrgMembersProvider>();
    final s = context.watch<OrgSession>();
    final c = context.colors;

    final header = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: SearchBox(hint: t('بحث بالاسم أو البريد أو الهاتف', 'Search name, email or phone'), onChanged: p.setSearch),
      ),
      FilterChips<String>(
          value: p.status,
          options: {
            'active': t('نشط', 'Active'),
            if (kind != 'staff') 'pending': t('طلبات الانضمام', 'Join requests'),
            'scheduled': membershipStatusLabels()['scheduled']!,
            'expired': membershipStatusLabels()['expired']!,
            'suspended': membershipStatusLabels()['suspended']!,
            if (kind != 'staff') 'rejected': t('مرفوض', 'Rejected'),
          },
          onChanged: p.setStatusFilter,
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          if (s.can(module, 'insert')) ...[
            _Act(Icons.upload_file_rounded, t('استيراد Excel', 'Import Excel'), c.primary, () async {
              if (await importExcelFlow(context, kind) && context.mounted) p.refresh();
            }),
            _Act(Icons.description_outlined, t('نموذج الملف', 'Template'), c.textMedium, () => downloadExcel(context, 'template/$kind')),
          ],
          if (s.can(module, 'export')) _Act(Icons.ios_share_rounded, t('تصدير Excel · Word · PDF', 'Export Excel · Word · PDF'), c.success, () => exportPagedList(context, p, (rows) => orgMembersExport(kind, rows, orgName: s.name))),
        ]),
      ),
    ]);

    return Stack(children: [
      PagedList<OrgMembersProvider>(
        header: header,
        emptyText: p.status == 'pending' ? t('لا توجد طلبات', 'No requests') : t('لا يوجد أعضاء بعد', 'No members yet'),
        itemBuilder: (ctx, row) => _MemberTile(row: row, module: module),
      ),
      if (s.can(module, 'insert'))
        PositionedDirectional(
          bottom: 16,
          end: 16,
          child: FloatingActionButton.extended(
            heroTag: 'org_add_$kind',
            backgroundColor: c.primary,
            onPressed: () async {
              final r = await showOrgMemberForm(context,
                  roles: kind == 'students' ? const ['student'] : kind == 'teachers' ? const ['teacher'] : const ['teacher_assistant', 'admin_assistant', 'org_admin']);
              if (r != null) p.refresh();
            },
            icon: Icon(Icons.person_add_alt_1_rounded, color: c.onHero),
            label: Text(t('إضافة', 'Add'), style: TextStyle(fontFamily: 'tajawal', color: c.onHero)),
          ),
        ),
    ]);
  }
}

class _Act extends StatelessWidget {
  const _Act(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: color, fontWeight: FontWeight.w700)),
        onPressed: onTap,
        side: BorderSide(color: color.withValues(alpha: 0.35)),
        backgroundColor: color.withValues(alpha: 0.08),
      );
}

String _roleLabel(String r) => {
      'student': t('طالب', 'Student'),
      'teacher': t('مدرس', 'Teacher'),
      'teacher_assistant': t('معيد', 'Teaching assistant'),
      'admin_assistant': t('مساعد إداري', 'Admin assistant'),
    }[r] ??
    r;

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.row, required this.module});
  final Map<String, dynamic> row;
  final String module;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.read<OrgMembersProvider>();
    final u = Map<String, dynamic>.from(row['user'] as Map);
    final role = '${row['role']}';
    final eff = '${row['effective_status'] ?? row['status']}';
    final pending = row['status'] == 'pending';
    final ended = eff == 'expired' || eff == 'suspended';
    final id = asInt(row['id']);
    final depts = asMapList(row['departments']);
    return OrgMemberRowView(
      name: '${u['name']}',
      email: '${u['email']}',
      imageUrl: u['image_url'] as String?,
      accent: pending ? c.warning : (ended ? c.danger : null),
      period: pending ? null : membershipPeriodText(row),
      periodEnded: ended,
      chips: [
                StatusChip(_roleLabel(role), c.primary),
                if (eff != 'active') StatusChip(membershipStatusLabels()[eff] ?? eff, statusColor(context, eff == 'scheduled' ? 'pending' : eff)),
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
              itemBuilder: (_) => [
                if (s.can(module, 'update')) PopupMenuItem(value: 'edit', child: Text(t('بيانات العضوية', 'Membership details'))),
                if (s.can(module, 'update'))
                  PopupMenuItem(value: 'extend', child: Text(ended ? t('تمديد / إعادة تفعيل', 'Extend / reactivate') : t('تمديد العضوية', 'Extend membership'))),
                if (s.can(module, 'update') && !ended) PopupMenuItem(value: 'suspend', child: Text(t('إيقاف العضوية', 'Suspend membership'))),
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
    this.imageUrl,
    this.accent,
    this.chips = const [],
    this.period,
    this.periodEnded = false,
    this.trailing = const [],
  });

  final String name, email;
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: RowCard(
        accent: accent,
        child: Row(children: [
          AdminAvatar(name: name, url: imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
              Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: chips),
              ],
              if (period != null && period!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(period!, style: TextStyle(fontFamily: 'tajawal', fontSize: 11.5, color: periodEnded ? c.danger : c.textLight)),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(t('صلاحيات ${(row['user'] as Map)['name']}', 'Permissions · ${(row['user'] as Map)['name']}')),
            Text(t('اختر ما يستطيع المساعد الإداري فعله في كل قسم. "عرض" يُضاف تلقائياً مع أي صلاحية أخرى.', 'Choose what this assistant can do in each module. "View" is added automatically with any other right.'),
                style: TextStyle(fontFamily: 'tajawal', fontSize: 12.5, color: c.textMedium)),
            const SizedBox(height: 10),
            for (final m in _modules)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.inputBg, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(modLabel[m]!, style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    for (final a in _actions)
                      FilterChip(
                        label: Text(actLabel[a]!, style: const TextStyle(fontFamily: 'tajawal', fontSize: 12.5)),
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
            PrimaryButton(
              isLoading: busy,
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
