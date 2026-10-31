// lib/features/org/org_workspace.dart
//
// "My workspace" — the first thing an organization member sees after signing in: their role, the departments
// they work in (with a tap into each department's hub) and every area they may manage or view — computed from
// their real permissions, so it never shows a door they can't open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_academic_pages.dart' show OrgAcademicPage;
import 'org_access_page.dart' show OrgAccessPage, OrgActivityPage;
import 'org_department_dashboard.dart' show openDepartmentDashboard;
import 'org_departments_page.dart' show DeptLogo;
import 'org_page_header.dart' show OrgPushedPage;
import 'org_platform_settings_page.dart' show OrgPlatformSettingsPage;
import 'org_sharing_pages.dart' show OrgSharingPage;
import 'org_providers.dart';
import 'org_services_pages.dart' show OrgAnnouncementsPage, OrgComplaintsPage, OrgFormsPage, OrgMaterialsPage;
import 'org_terms_pages.dart' show OrgTermsAdminPage;
import 'org_ui.dart';
import 'package:flutter_education_app/features/admin/admin_datacenter_page.dart' show DataCenterPage;
import 'org_sections_page.dart';

class OrgWorkspace extends StatefulWidget {
  const OrgWorkspace({super.key});

  @override
  State<OrgWorkspace> createState() => _OrgWorkspaceState();
}

class _OrgWorkspaceState extends State<OrgWorkspace> {
  List<Map<String, dynamic>> _depts = const [];
  int? _loadedFor;

  Future<void> _load(OrgSession s) async {
    _loadedFor = s.currentId;
    final r = await OrgApi.i.getMap('${s.base}/departments');
    if (!mounted) return;
    final all = asMapList(r?['items']);
    setState(() => _depts = s.isOrgAdmin ? all : all.where((d) => s.myDeptIds.contains(asInt(d['id']))).toList());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final c = context.colors;
    if (_loadedFor != s.currentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(s));
    }
    void open(String title, Widget child) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
            // the dashboard's own header (Back · title · Refresh · calendar · bell · switcher)
            value: s, child: OrgPushedPage(title: title, maxWidth: 1000, child: child))));
    // every area this person may manage or view (role + personal grants, org-wide or in a department)
    final areas = <(String, IconData, Color, String, Widget)>[
      if (s.canAny('announcements')) ('announcements', Icons.campaign_rounded, c.primary, t('الإعلانات والأخبار', 'News & announcements'), const OrgAnnouncementsPage()),
      if (s.canAny('forms')) ('forms', Icons.assignment_rounded, c.purple, t('الطلبات والاستبيانات', 'Requests & questionnaires'), const OrgFormsPage()),
      if (s.canAny('complaints')) ('complaints', Icons.support_agent_rounded, c.danger, t('الشكاوى', 'Complaints'), const OrgComplaintsPage()),
      if (s.canAny('materials')) ('materials', Icons.folder_copy_rounded, c.accent2, t('المكتبة', 'Library'), const OrgMaterialsPage()),
      if (s.can('academic')) ('academic', Icons.school_rounded, c.primary, t('الهيكل الأكاديمي', 'Academic structure'), const OrgAcademicPage()),
      if (s.can('terms')) ('terms', Icons.gavel_rounded, c.warning, t('اللوائح', 'Regulations'), const OrgTermsAdminPage()),
      if (s.can('roles')) ('roles', Icons.admin_panel_settings_rounded, c.purple, t('الأدوار والصلاحيات', 'Roles & privileges'), const OrgAccessPage()),
      if (s.isOrgAdmin) ('platform', Icons.tune_rounded, c.primary, t('الوقت والميزات', 'Time & features'), const OrgPlatformSettingsPage()),
      if (s.canAny('sharing')) ('sharing', Icons.handshake_rounded, c.success, t('المشاركة مع المؤسسات', 'Sharing with organizations'), const OrgSharingPage()),
      if (s.can('audit')) ('audit', Icons.history_rounded, c.textMedium, t('سجل النشاط', 'Activity log'), const OrgActivityPage()),
      if (s.canAny('complaints') || s.canAny('forms'))
        ('datacenter', Icons.insights_rounded, c.primary, t('مركز البيانات', 'Data Center'), DataCenterPage(orgId: s.currentId, embedded: true)),
      if ('${s.current?['my_role'] ?? ''}' == 'teacher_assistant')
        ('sections', Icons.science_rounded, c.purple, t('سكاشني', 'My sections'), const OrgSectionsPage()),
    ];
    if (areas.isEmpty && _depts.isEmpty) return const SizedBox.shrink();
    final role = '${s.current?['my_role'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.divider),
          boxShadow: c.cardShadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.dashboard_customize_rounded, color: c.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(t('مساحة عملي', 'My workspace'), style: orgText(context, size: 16, w: FontWeight.w800))),
            if (role.isNotEmpty) OrgPill(memberRoleLabels()[role] ?? (role == 'org_admin' ? t('مدير المؤسسة', 'Organization admin') : role), icon: Icons.badge_rounded, color: c.primary),
          ]),
          if (_depts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(s.isOrgAdmin ? t('كل الإدارات', 'All departments') : t('إداراتي', 'My departments'),
                style: orgText(context, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _depts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final d = _depts[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => openDepartmentDashboard(context, unitType: 'dept', unitId: asInt(d['id']), seed: d),
                    child: Container(
                      width: 116,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: hexColor(d['color'], c.primary).withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: hexColor(d['color'], c.primary).withValues(alpha: 0.25)),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        DeptLogo(d: d, size: 36),
                        const SizedBox(height: 6),
                        Text(t('${d['name_ar'] ?? d['name_en']}', '${d['name_en'] ?? d['name_ar']}'), maxLines: 2, textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis, style: orgText(context, size: 11.5, w: FontWeight.w700)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ],
          if (areas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t('ما يمكنك إدارته', 'What you can manage'), style: orgText(context, size: 12.5, w: FontWeight.w700, color: c.textMedium)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in areas)
                ActionChip(
                  avatar: Icon(a.$2, size: 18, color: a.$3),
                  label: Text(a.$4, style: orgText(context, size: 12.5, w: FontWeight.w700)),
                  backgroundColor: a.$3.withValues(alpha: 0.08),
                  side: BorderSide(color: a.$3.withValues(alpha: 0.25)),
                  onPressed: () => open(a.$4, a.$5),
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}
