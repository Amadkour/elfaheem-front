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

import '../admin/admin_common.dart';
import '../admin/admin_list.dart';
import '../admin/admin_premium_widgets.dart';
import 'org_common.dart';
import 'org_courses_page.dart';
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

  List<DashboardItem> _items() => [
        DashboardItem(Icons.dashboard_outlined, Icons.dashboard_rounded, t('الرئيسية', 'Home'), null,
            const _OrgTab(title: 'org', child: OrgOverviewPage())),
        DashboardItem(Icons.groups_outlined, Icons.groups_rounded, t('الأعضاء', 'People'), null,
            _OrgTab(title: t('الأعضاء', 'People'), child: const OrgPeoplePage())),
        DashboardItem(Icons.menu_book_outlined, Icons.menu_book_rounded, t('الكورسات', 'Courses'), null,
            _OrgTab(title: t('الكورسات', 'Courses'), child: const OrgCoursesPage())),
        DashboardItem(Icons.calendar_month_outlined, Icons.calendar_month_rounded, t('الجدول', 'Timetable'), null,
            _OrgTab(title: t('الجدول الدراسي', 'Timetable'), child: const OrgSchedulePage())),
        DashboardItem(Icons.person_outline_rounded, Icons.person_rounded, t('حسابي', 'Account'), null,
            _OrgTab(title: t('حسابي', 'Account'), child: const _OrgAccountPage())),
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
              final items = _items();
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
          ? EmptyState(t('اختر مؤسسة', 'Choose an organization'), icon: Icons.domain_rounded)
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              _Stat(Icons.school_rounded, t('الطلاب', 'Students'), d['students'], c.primary),
              _Stat(Icons.person_pin_rounded, t('المدرسون', 'Teachers'), d['teachers'], AdminPalette.violet.last),
              _Stat(Icons.badge_rounded, t('الهيئة المعاونة', 'Staff'), d['staff'], AdminPalette.green.last),
              _Stat(Icons.menu_book_rounded, t('الكورسات', 'Courses'), d['courses'], AdminPalette.indigo.last),
              _Stat(Icons.how_to_reg_rounded, t('اشتراكات نشطة', 'Active enrollments'), d['active_enrollments'], c.success),
              _Stat(Icons.account_tree_rounded, t('مؤسسات فرعية', 'Sub-organizations'), d['sub_organizations'], AdminPalette.rose.last),
            ]),
          ),
          if (asInt(d['pending_requests']) > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: RowCard(
                accent: c.warning,
                onTap: () => context.read<_OrgTabs>().onChangeTab(1),
                child: Row(children: [
                  IconBadge(Icons.mark_email_unread_rounded, c.warning),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        t('${d['pending_requests']} طلب انضمام ينتظر موافقتك', '${d['pending_requests']} join requests are waiting for you'),
                        style: TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w700, color: c.textDark)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textLight),
                ]),
              ),
            ),
        ],
        if (s.isOrgAdmin)
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

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value, this.color);
  final IconData icon;
  final String label;
  final dynamic value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final w = (MediaQuery.sizeOf(context).width.clamp(0, 1100) - 32 - 12) / 2;
    return Container(
      width: w > 170 ? w : double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        IconBadge(icon, color, size: 42),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${asInt(value)}', style: TextStyle(fontFamily: 'bahji', fontSize: 22, fontWeight: FontWeight.w800, color: c.textDark)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'tajawal', fontSize: 12, color: c.textMedium)),
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
              if (o['id'] == s.currentId) Icon(Icons.check_circle_rounded, color: c.success),
            ]),
          ),
        ),
      if (s.isOrgAdmin || s.items.isEmpty)
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
