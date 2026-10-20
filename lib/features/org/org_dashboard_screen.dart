// lib/features/org/org_dashboard_screen.dart
//
// The organization-admin shell (role `org-admin`, and `org-staff` = admin assistants).
// Same shells as the admin dashboard (sidebar / rail / bottom bar) — five tabs:
//   Overview · People · Courses · Timetable · Settings(account)
// The organization switcher sits in the hero of every tab; changing it bumps OrgSession.epoch so every tab reloads
// with the new organization's data ONLY.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/features/shared/profile/change_language_screen.dart';
import 'package:flutter_education_app/features/shared/profile/profile_provider.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_group.dart';
import 'package:flutter_education_app/features/shared/profile/components/setting_title.dart' show SettingsTile;
import 'package:flutter_education_app/features/shared/profile/profile_screen.dart' show ProfileHeader;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/student/dashboard/dashboard_screen.dart' show WideShell, RailShell, MobileShell;
import 'package:flutter_education_app/features/teacher/dashboard/teacher_dashboard_screen.dart' show DashboardItem;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/features/teacher/certificates/designer/certificate_designs_screen.dart';

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import '../admin/admin_premium_widgets.dart';
import 'org_common.dart';
import 'org_access_page.dart';
import 'org_courses_page.dart';
import 'org_departments_page.dart';
import 'org_services_pages.dart';
import 'org_status_screen.dart';
import 'org_ui.dart';
import 'org_people_page.dart';
import 'org_providers.dart';
import 'org_schedule_pages.dart';

class _OrgTabs extends ChangeNotifier {
  int currentTab = 0;
  void onChangeTab(int i) {
    if (i == currentTab) return;
    currentTab = i;
    notifyListeners();
  }
}

class OrgDashboardScreen extends StatefulWidget {
  const OrgDashboardScreen({super.key});

  @override
  State<OrgDashboardScreen> createState() => _OrgDashboardScreenState();
}

class _OrgDashboardScreenState extends State<OrgDashboardScreen> {
  final _tabs = _OrgTabs();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<OrgSession>().load();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Tabs follow MY rights: an admin assistant sees People/Courses/Timetable, a department clerk sees
  /// Departments (only theirs), the org admin sees everything.
  List<DashboardItem> _items(OrgSession s) => [
        DashboardItem(Icons.dashboard_outlined, Icons.dashboard_rounded, t('الرئيسية', 'Home'), null,
            const _OrgTab(title: 'org', child: OrgOverviewPage())),
        if (s.can('students') || s.can('teachers') || s.can('staff') || s.can('requests'))
          DashboardItem(Icons.groups_outlined, Icons.groups_rounded, t('الأعضاء', 'People'), null,
              _OrgTab(title: t('الأعضاء', 'People'), child: const OrgPeoplePage())),
        if (s.can('departments') || s.myDeptIds.isNotEmpty)
          DashboardItem(Icons.apartment_outlined, Icons.apartment_rounded, t('الإدارات', 'Departments'), null,
              _OrgTab(title: t('الإدارات', 'Departments'), child: const OrgDepartmentsPage())),
        if (s.canAny('courses'))
          DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, t('المقررات', 'Courses'), null,
              _OrgTab(title: t('المقررات', 'Courses'), child: const OrgCoursesPage())),
        if (s.can('schedule'))
          DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, t('الجدول', 'Timetable'), null,
              _OrgTab(title: t('الجدول الدراسي', 'Timetable'), child: const OrgSchedulePage())),
        DashboardItem(Icons.widgets_outlined, Icons.widgets_rounded, t('المزيد', 'More'), null,
            _OrgTab(title: t('المزيد', 'More'), child: const _OrgAccountPage())),
      ];

  @override
  Widget build(BuildContext context) {
    AdminPalette.attach(context);
    context.watch<LangProvider>();
    final session = context.watch<OrgSession>();
    if (!session.loaded) {
      return const BasePage(child: Center(child: AppLoadingIndicator()));
    }
    if (session.loaded && session.items.isEmpty) {
      return BasePage(child: _FirstOrganization());
    }
    if (session.currentId != null && !session.approved) {
      // pending / rejected / suspended → a calm status page instead of 423 errors on every tab
      return const BasePage(useWebCard: true, maxWith: 760, child: OrgStatusScreen());
    }
    return ChangeNotifierProvider<_OrgTabs>.value(
      value: _tabs,
      builder: (context, _) {
        final tabs = context.watch<_OrgTabs>();
        return PopScope(
          canPop: tabs.currentTab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) tabs.onChangeTab(0);
          },
          child: Directionality(
            textDirection: dir,
            child: LayoutBuilder(builder: (context, constraints) {
              final w = constraints.maxWidth;
              final isWide = w >= 1000;
              final isRail = kIsWeb && w >= 600;
              final items = _items(session);
              final current = tabs.currentTab.clamp(0, items.length - 1);
              void onTap(int i) => tabs.onChangeTab(i);
              if (isWide) {
                return WideShell(currentIndex: current, onTap: onTap, dashboardItems: items, unreadCount: 0);
              }
              if (isRail) {
                return RailShell(currentIndex: current, onTap: onTap, dashboardItems: items, unreadCount: 0);
              }
              return MobileShell(currentIndex: current, onTap: onTap, dashboardItems: items);
            }),
          ),
        );
      },
    );
  }
}

/// Page frame + live reload when the organization changes.
class _OrgTab extends StatelessWidget {
  const _OrgTab({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    return BasePage(
      useWebCard: true,
      maxWith: 1100,
      appBar: title == 'org' ? null : ScreenAppBar(title: title, showBack: false),
      child: s.currentId == null
          ? OrgEmpty(icon: Icons.domain_rounded, title: t('اختر مؤسسة', 'Choose an organization'))
          : ValueListenableBuilder<int>(
              valueListenable: s.epoch,
              builder: (_, e, _) => KeyedSubtree(key: ValueKey('${s.currentId}-$e'), child: child),
            ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  First organization (org admin who has none yet)
// ═════════════════════════════════════════════════════════════════════════════

class _FirstOrganization extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.domain_add_rounded, size: 72, color: c.primary),
          const SizedBox(height: 14),
          Text(t('لنبدأ بإنشاء مؤسستك', "Let's create your organization"), style: c.h2, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(t('جامعة أو كلية أو معهد — ويمكنك إضافة أقسام داخلها لاحقاً.',
              'A university, faculty or institute — you can nest departments inside it later.'),
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
          const SizedBox(height: 20),
          SizedBox(
            width: 240,
            child: PrimaryButton(
                isLoading: false,
                label: t('إنشاء مؤسسة', 'Create organization'),
                icon: Icons.add_rounded,
                iconBefore: true,
                onPressed: () => showOrgForm(context)),
          ),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Overview
// ═════════════════════════════════════════════════════════════════════════════

class OrgOverviewPage extends StatefulWidget {
  const OrgOverviewPage({super.key});

  @override
  State<OrgOverviewPage> createState() => _OrgOverviewPageState();
}

class _OrgOverviewPageState extends State<OrgOverviewPage> {
  Map<String, dynamic>? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await context.read<OrgSession>().overview();
    if (!mounted) return;
    setState(() {
      _data = d;
      _failed = d == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final org = s.current!;
    final c = context.colors;
    final d = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
        OrgHero(
          org: org,
          subtitle: '${orgTypeLabels()[org['type']] ?? ''} · ${s.items.length > 1 ? t('${s.items.length} مؤسسات', '${s.items.length} organizations') : t('مؤسسة واحدة', '1 organization')}',
          trailing: IconButton(
            tooltip: t('تبديل المؤسسة', 'Switch organization'),
            onPressed: () => showOrgSwitcher(context),
            icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
          ),
        ),
        if (_failed)
          SizedBox(height: 260, child: ErrorRetry(message: t('تعذّر تحميل البيانات', 'Could not load data'), onRetry: _load))
        else if (d == null)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: AppLoadingIndicator(size: 56)))
        else ...[
          OrgGrid(children: [
            OrgStatTile(icon: Icons.school_rounded, label: t('الطلاب', 'Students'), value: d['students'], color: c.primary),
            OrgStatTile(icon: Icons.person_pin_rounded, label: t('هيئة التدريس', 'Teaching staff'), value: d['teachers'], color: c.purple),
            OrgStatTile(icon: Icons.badge_rounded, label: t('الهيئة المعاونة', 'Assistants & staff'), value: d['staff'], color: c.accent2),
            OrgStatTile(icon: Icons.menu_book_rounded, label: t('المقررات', 'Courses'), value: d['courses'], color: c.accent),
            OrgStatTile(icon: Icons.how_to_reg_rounded, label: t('تسجيلات نشطة', 'Active enrollments'), value: d['active_enrollments'], color: c.success),
            OrgStatTile(icon: Icons.account_tree_rounded, label: t('مؤسسات فرعية', 'Sub-organizations'), value: d['sub_organizations'], color: c.warning),
          ]),
          _Attention(a: asMap(d['attention'])),
          if (asMapList(d['departments']).isNotEmpty) ...[
            OrgSectionTitle(t('الإدارات', 'Departments'),
                action: TextButton(
                    onPressed: () => _goTab(context, t('الإدارات', 'Departments')),
                    child: Text(t('عرض الكل', 'See all'), style: const TextStyle(fontFamily: 'tajawal')))),
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final dep in asMapList(d['departments']))
                  Container(
                    width: 104,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ChangeNotifierProvider.value(value: s, child: OrgDepartmentHub(dept: dep)))),
                      child: Column(children: [
                        IconBadge(deptIcon(dep['icon']), hexColor(dep['color'], c.primary), size: 52),
                        const SizedBox(height: 6),
                        Text(orgNameOf(dep), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                            style: TextStyle(fontFamily: 'tajawal', fontSize: 12, fontWeight: FontWeight.w700, color: c.textDark)),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
          if (asMapList(d['recent_activity']).isNotEmpty) ...[
            OrgSectionTitle(t('آخر النشاط', 'Recent activity')),
            for (final a in asMapList(d['recent_activity']).take(5))
              ListTile(
                dense: true,
                leading: Icon(Icons.history_rounded, color: c.textLight),
                title: Text('${a['summary']}', style: TextStyle(fontFamily: 'tajawal', fontSize: 13, color: c.textDark)),
                trailing: Text(relTime(a['created_at']), style: TextStyle(fontFamily: 'tajawal', fontSize: 11, color: c.textLight)),
              ),
          ],
        ],
        if (s.can('sub_orgs', 'insert') || s.isOrgAdmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Row(children: [
              Expanded(
                  child: PrimaryButton(
                      isLoading: false,
                      label: t('مؤسسة فرعية', 'Sub-organization'),
                      icon: Icons.account_tree_rounded,
                      iconBefore: true,
                      onPressed: () => showOrgForm(context, parentId: s.currentId))),
              const SizedBox(width: 10),
              Expanded(
                  child: PrimaryButton(
                      isLoading: false,
                      background: c.success,
                      label: t('كود الانضمام', 'Join code'),
                      icon: Icons.vpn_key_rounded,
                      iconBefore: true,
                      onPressed: () => showJoinCode(context))),
            ]),
          ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Account / settings tab
// ═════════════════════════════════════════════════════════════════════════════

class _OrgAccountPage extends StatelessWidget {
  const _OrgAccountPage();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.watch<ProfileProvider>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(children: [
        ProfileHeader(provider: p),
        const SizedBox(height: 24),
        _OrgServicesGroup(s: s),
        const SizedBox(height: 20),
        if (s.isOrgAdmin) ...[
          SettingsGroup(title: t('المؤسسة', 'Organization'), icon: Icons.domain_rounded, children: [
            SettingsTile(
                icon: Icons.swap_horiz_rounded,
                iconBg: c.primary.withAlpha(38),
                iconColor: c.primary,
                label: t('تبديل المؤسسة', 'Switch organization'),
                onTap: () => showOrgSwitcher(context)),
            SettingsTile(
                icon: Icons.edit_rounded,
                iconBg: AdminPalette.indigo.last.withAlpha(38),
                iconColor: AdminPalette.indigo.last,
                label: t('تعديل بيانات المؤسسة', 'Edit organization'),
                onTap: () => showOrgForm(context, edit: s.current)),
            if (s.canCreateRoot)
              SettingsTile(
                  icon: Icons.add_business_rounded,
                  iconBg: AdminPalette.green.last.withAlpha(38),
                  iconColor: AdminPalette.green.last,
                  label: t('مؤسسة جديدة', 'New organization'),
                  onTap: () => showOrgForm(context)),
            SettingsTile(
                icon: Icons.vpn_key_rounded,
                iconBg: AdminPalette.violet.last.withAlpha(38),
                iconColor: AdminPalette.violet.last,
                label: t('كود الانضمام', 'Join code'),
                onTap: () => showJoinCode(context)),
          ]),
          const SizedBox(height: 20),
        ],
        SettingsGroup(title: t('الإعدادات', 'Settings'), icon: Icons.settings_rounded, children: [
          SettingsTile(
              icon: Icons.translate_rounded,
              iconBg: AdminPalette.violet.last.withAlpha(38),
              iconColor: AdminPalette.violet.last,
              label: 'change_language'.tr,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangeLanguageScreen()))),
          SettingsTile(
              icon: Icons.dark_mode_rounded,
              iconBg: c.darkIconBg,
              iconColor: c.textDark,
              label: 'dark_mode'.tr,
              trailing: Switch.adaptive(value: p.darkMode, onChanged: (b) async => p.changeMode(b), activeThumbColor: c.primary)),
        ]),
        const SizedBox(height: 20),
        SettingsGroup(title: 'exit'.tr, icon: Icons.exit_to_app_rounded, itemBackground: c.danger.withAlpha(30), children: [
          SettingsTile(
              icon: Icons.logout_rounded,
              iconBg: c.dangerTint,
              iconColor: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) await context.read<ProfileProvider>().logout(context);
              }),
        ]),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Switcher · create/edit · join code
// ═════════════════════════════════════════════════════════════════════════════

Future<void> showOrgSwitcher(BuildContext context) async {
  final s = context.read<OrgSession>();
  await showAdminSheet<void>(context, (ctx) {
    final c = ctx.colors;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
      SheetHeader(t('مؤسساتي', 'My organizations')),
      for (final o in s.items)
        Padding(
          padding: EdgeInsetsDirectional.only(start: 16.0 * (asInt(o['depth']).clamp(0, 5)), bottom: 8),
          child: RowCard(
            accent: o['id'] == s.currentId ? orgColor(ctx, o) : null,
            onTap: () {
              s.select(asInt(o['id']));
              Navigator.pop(ctx);
            },
            child: Row(children: [
              IconBadge(orgTypeIcons[o['type']] ?? Icons.domain_rounded, orgColor(ctx, o), size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(OrgSession.nameOf(o), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, color: c.textDark)),
                  Text(orgTypeLabels()[o['type']] ?? '', style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
                ]),
              ),
              if ('${o['status'] ?? 'approved'}' != 'approved')
                StatusChip(statusLabel('${o['status']}'), statusColor(ctx, '${o['status']}')),
              if (o['id'] == s.currentId) Icon(Icons.check_circle_rounded, color: c.success),
            ]),
          ),
        ),
      if (s.canCreateRoot)
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            showOrgForm(context);
          },
          icon: const Icon(Icons.add_rounded),
          label: Text(t('مؤسسة جديدة', 'New organization')),
        ),
    ]);
  });
}

Future<void> showOrgForm(BuildContext context, {int? parentId, Map<String, dynamic>? edit}) async {
  final s = context.read<OrgSession>();
  final ar = TextEditingController(text: '${edit?['name_ar'] ?? ''}');
  final en = TextEditingController(text: '${edit?['name_en'] ?? ''}');
  final desc = TextEditingController(text: '${edit?['description'] ?? ''}');
  final logo = TextEditingController(text: '${edit?['logo_url'] ?? ''}');
  final license = TextEditingController(text: '${edit?['license_no'] ?? ''}');
  final email = TextEditingController(text: '${edit?['contact_email'] ?? ''}');
  final phone = TextEditingController(text: '${edit?['contact_phone'] ?? ''}');
  final website = TextEditingController(text: '${edit?['website'] ?? ''}');
  final address = TextEditingController(text: '${edit?['address'] ?? ''}');
  final official = parentId == null && (edit == null || edit['parent_id'] == null);
  String type = '${edit?['type'] ?? (parentId == null ? 'university' : 'faculty')}';
  String mode = '${edit?['join_mode'] ?? 'approval'}';
  String color = '${edit?['color'] ?? ''}';
  bool busy = false;
  const palette = ['#1F6F5C', '#2563EB', '#7C3AED', '#DB2777', '#EA580C', '#0891B2', '#475569'];

  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SheetHeader(edit != null
                ? t('تعديل المؤسسة', 'Edit organization')
                : parentId != null
                    ? t('مؤسسة فرعية جديدة', 'New sub-organization')
                    : t('مؤسسة جديدة', 'New organization')),
            Field(controller: ar, label: t('الاسم بالعربية', 'Arabic name')),
            Field(controller: en, label: t('الاسم بالإنجليزية', 'English name'), ltr: true),
            ChoiceRow<String>(label: t('النوع', 'Type'), options: orgTypeLabels(), value: type, onChanged: (v) => set(() => type = v)),
            const SizedBox(height: 10),
            ChoiceRow<String>(label: t('طريقة الانضمام', 'How people join'), options: joinModeLabels(), value: mode, onChanged: (v) => set(() => mode = v)),
            const SizedBox(height: 12),
            Text(t('لون المؤسسة', 'Brand colour'), style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [
              for (final h in palette)
                GestureDetector(
                  onTap: () => set(() => color = h),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${h.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(color: color == h ? c.textDark : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            Field(controller: logo, label: t('رابط الشعار (اختياري)', 'Logo URL (optional)'), ltr: true),
            Field(controller: desc, label: t('نبذة (اختياري)', 'About (optional)'), maxLines: 3),
            if (official) ...[
              const SizedBox(height: 6),
              Text(t('بيانات رسمية — تساعد فريق المنصة على اعتماد مؤسستك بسرعة', 'Official details — they help the platform team approve you quickly'),
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
              const SizedBox(height: 8),
              Field(controller: license, label: t('رقم القرار / الترخيص', 'Decree / licence number')),
              Field(controller: email, label: t('البريد الرسمي', 'Official e-mail'), ltr: true),
              Field(controller: phone, label: t('هاتف التواصل', 'Contact phone'), ltr: true),
              Field(controller: website, label: t('الموقع الإلكتروني', 'Website'), ltr: true),
              Field(controller: address, label: t('العنوان', 'Address')),
            ],
            const SizedBox(height: 6),
            PrimaryButton(
              isLoading: busy,
              label: t('حفظ', 'Save'),
              onPressed: () async {
                if (ar.text.trim().isEmpty && en.text.trim().isEmpty) {
                  toast(t('اكتب اسم المؤسسة', 'Enter a name'), error: true);
                  return;
                }
                set(() => busy = true);
                final body = {
                  'name_ar': ar.text.trim(),
                  'name_en': en.text.trim(),
                  'type': type,
                  'join_mode': mode,
                  if (color.isNotEmpty) 'color': color,
                  if (logo.text.trim().isNotEmpty) 'logo_url': logo.text.trim(),
                  if (desc.text.trim().isNotEmpty) 'description': desc.text.trim(),
                  if (edit == null && parentId != null) 'parent_id': parentId,
                  if (official) ...{
                    'license_no': license.text.trim(),
                    'contact_email': email.text.trim(),
                    'contact_phone': phone.text.trim(),
                    'website': website.text.trim(),
                    'address': address.text.trim(),
                  },
                };
                final ok = edit != null ? await s.updateOrg(body) : await s.createOrg(body);
                if (ctx.mounted) {
                  set(() => busy = false);
                  if (ok) Navigator.pop(ctx);
                }
              },
            ),
            if (edit != null) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () async {
                  if (await confirm(ctx, message: t('حذف المؤسسة نهائياً؟ (يجب أن تكون بلا فروع أو كورسات)', 'Delete this organization? (it must have no sub-organizations or courses)'), danger: true)) {
                    if (await s.deleteOrg() && ctx.mounted) Navigator.pop(ctx);
                  }
                },
                icon: Icon(Icons.delete_outline_rounded, color: c.danger),
                label: Text(t('حذف المؤسسة', 'Delete organization'), style: TextStyle(color: c.danger)),
              ),
            ],
          ]),
        );
      }));
}

Future<void> showJoinCode(BuildContext context) async {
  final s = context.read<OrgSession>();
  await showAdminSheet<void>(context, (ctx) => StatefulBuilder(builder: (ctx, set) {
        final c = ctx.colors;
        final code = '${s.current?['join_code'] ?? '—'}';
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كود الانضمام', 'Join code')),
            Text(t('شارك هذا الكود مع الطلاب والمدرسين ليدخلوا مؤسستك مباشرة.', 'Share this code so students and teachers can join directly.'),
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'tajawal', color: c.textMedium)),
            const SizedBox(height: 16),
            SelectableText(code, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: 'bahji', fontSize: 34, letterSpacing: 6, fontWeight: FontWeight.w800, color: c.primary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                if (await confirm(ctx, message: t('سيتوقف الكود القديم عن العمل. متابعة؟', 'The old code will stop working. Continue?'))) {
                  await s.regenerateCode();
                  set(() {});
                }
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('كود جديد', 'New code')),
            ),
          ]),
        );
      }));
}


/// Jumps to a dashboard tab by its label (tabs differ per person, so indexes are not fixed).
void _goTab(BuildContext context, String label) {
  final shell = context.findAncestorStateOfType<_OrgDashboardScreenState>();
  if (shell == null) return;
  final items = shell._items(context.read<OrgSession>());
  final i = items.indexWhere((e) => e.label == label);
  if (i >= 0) shell._tabs.onChangeTab(i);
}

/// "Needs your attention": only what is waiting, in plain words, one tap away.
class _Attention extends StatelessWidget {
  const _Attention({required this.a});
  final Map<String, dynamic> a;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = context.read<OrgSession>();
    Widget page(String title, Widget child) => ChangeNotifierProvider.value(
        value: s, child: BasePage(useWebCard: true, maxWith: 1000, appBar: ScreenAppBar(title: title), child: child));
    final cards = <Widget>[
      if (asInt(a['join_requests']) > 0)
        OrgActionCard(
          icon: Icons.mark_email_unread_rounded,
          color: c.warning,
          badge: asInt(a['join_requests']),
          title: t('طلبات انضمام', 'Join requests'),
          subtitle: t('أشخاص ينتظرون قبولك', 'People waiting for you to let them in'),
          onTap: () => _goTab(context, t('الأعضاء', 'People')),
        ),
      if (asInt(a['open_complaints']) > 0)
        OrgActionCard(
          icon: Icons.support_agent_rounded,
          color: asInt(a['overdue_complaints']) > 0 ? c.danger : c.primary,
          badge: asInt(a['open_complaints']),
          title: t('شكاوى مفتوحة', 'Open complaints'),
          subtitle: asInt(a['overdue_complaints']) > 0
              ? t('${a['overdue_complaints']} تجاوزت مهلة الرد', '${a['overdue_complaints']} past their reply time')
              : t('كلها ضمن المهلة 👍', 'All within their reply time 👍'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => page(t('الشكاوى', 'Complaints'), const OrgComplaintsPage()))),
        ),
      if (asInt(a['pending_forms']) > 0)
        OrgActionCard(
          icon: Icons.assignment_late_rounded,
          color: c.purple,
          badge: asInt(a['pending_forms']),
          title: t('طلبات تنتظر المراجعة', 'Requests to review'),
          subtitle: t('نماذج أرسلها الطلاب والموظفون', 'Forms sent by students and staff'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => page(t('النماذج', 'Forms'), const OrgFormsPage()))),
        ),
      if (asInt(a['pending_sub_orgs']) > 0)
        OrgActionCard(
          icon: Icons.account_tree_rounded,
          color: c.accent,
          badge: asInt(a['pending_sub_orgs']),
          title: t('مؤسسات فرعية قيد المراجعة', 'Sub-organizations in review'),
          subtitle: t('بانتظار اعتماد إدارة المنصة', 'Waiting for the platform team'),
          onTap: () => showOrgSwitcher(context),
        ),
    ];
    if (cards.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: RowCard(
          accent: c.success,
          child: Row(children: [
            IconBadge(Icons.spa_rounded, c.success),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t('لا شيء ينتظرك الآن — كل شيء على ما يرام 🌿', 'Nothing is waiting for you — all good 🌿'),
                  style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
            ),
          ]),
        ),
      );
    }
    return Column(children: [
      OrgSectionTitle(t('يحتاج انتباهك', 'Needs your attention')),
      OrgGrid(minTile: 300, children: cards),
    ]);
  }
}

/// Organization-wide services, roles and activity — shown on the "More" tab according to my rights.
class _OrgServicesGroup extends StatelessWidget {
  const _OrgServicesGroup({required this.s});
  final OrgSession s;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    void open(String title, Widget child) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
            value: s, child: BasePage(useWebCard: true, maxWith: 1000, appBar: ScreenAppBar(title: title), child: child))));
    Widget tile(IconData icon, Color col, String label, VoidCallback onTap) =>
        SettingsTile(icon: icon, iconBg: col.withAlpha(38), iconColor: col, label: label, onTap: onTap);
    final tiles = <Widget>[
      if (s.can('announcements'))
        tile(Icons.campaign_rounded, c.primary, t('إعلانات المؤسسة', 'Organization news'),
            () => open(t('الإعلانات', 'Announcements'), const OrgAnnouncementsPage())),
      if (s.can('forms'))
        tile(Icons.assignment_rounded, AdminPalette.violet.last, t('النماذج العامة', 'Organization forms'),
            () => open(t('النماذج', 'Forms'), const OrgFormsPage())),
      if (s.can('complaints'))
        tile(Icons.support_agent_rounded, AdminPalette.rose.last, t('كل الشكاوى', 'All complaints'),
            () => open(t('الشكاوى', 'Complaints'), const OrgComplaintsPage())),
      if (s.can('materials'))
        tile(Icons.folder_copy_rounded, AdminPalette.teal.last, t('مكتبة المؤسسة', 'Organization library'),
            () => open(t('المكتبة', 'Library'), const OrgMaterialsPage())),
      if (s.canAny('certificates') || s.isOrgAdmin)
        tile(Icons.workspace_premium_rounded, AdminPalette.orange.last, t('تصميمات الشهادات', 'Certificate designs'),
            () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CertificateDesignsScreen(orgId: s.currentId)))),
      if (s.can('roles'))
        tile(Icons.admin_panel_settings_rounded, AdminPalette.indigo.last, t('الأدوار والصلاحيات', 'Roles & privileges'),
            () => open(t('الأدوار والصلاحيات', 'Roles & privileges'), const OrgAccessPage())),
      if (s.can('audit'))
        tile(Icons.history_rounded, AdminPalette.slate.last, t('سجل النشاط', 'Activity log'),
            () => open(t('سجل النشاط', 'Activity log'), const OrgActivityPage())),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return SettingsGroup(title: t('خدمات المؤسسة', 'Organization services'), icon: Icons.widgets_rounded, children: tiles);
  }
}
