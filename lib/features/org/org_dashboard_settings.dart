// lib/features/org/org_dashboard_settings.dart
//
// The org-admin Settings section ("More" on phones, where it also carries the Services links) and the
// organization sheets:
//   OrgSettingsPage       AppSettingsPage: profile header → (phones) Communication & services with the live counts
//                         → Organization (switch · edit · join code · sub-organization · new) → Governance (roles,
//                         activity log, regulations, certificate designs) → Preferences → two-step verification →
//                         sign out. A search field appears past 8 tiles.
//   OrgFirstOrganization  the org admin who has none yet.
//   showOrgSwitcher · showOrgForm · showJoinCode   the sheets (also used by org_status_screen.dart).
// Every sub-page opens through orgPush (the session carried along, the exit button in its bar).
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/profile/legal/legal_links.dart' show legalSettingsGroup;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppSettingsGroup, AppSettingsPage, AppSettingsTile, AppSwitch, appRoleLabel, showAppNotice;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/calendar_entry.dart' show ChatEntryTile;
import 'package:flutter_education_app/design/context_switcher.dart' show showContextSwitcherSheet;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart' show MfaSettingsEntry;
import 'package:flutter_education_app/design/app_language_switch.dart' show AppLanguageTile;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import '../admin/admin_premium_widgets.dart' show AdminPalette;
import 'org_access_page.dart' show OrgAccessPage, OrgActivityPage;
import 'org_common.dart';
import 'org_creation_fee.dart' show OrgCreationFeePanel;
import 'org_danger_zone.dart';
import 'org_inst_notify.dart' show OrgNotifyPrefsPage;
import 'org_v3.dart' show orgCall, orgCodeText;
import 'org_dashboard_home.dart' show orgPush;
import 'org_dashboard_screen.dart' show OrgSub;
import 'package:flutter_education_app/features/exams/parent_grade_visibility.dart' show kParentVisibilityKey, openParentGradeVisibility;
import 'package:flutter_education_app/features/exams/hub/hub_entry.dart' show examHubTeachingRole, kExamHubFeatureKey;
import 'org_chat_settings_tile.dart';
import 'org_providers.dart';
import 'org_terms_pages.dart' show OrgTermsAdminPage;
import 'governance/gov_councils_setup.dart' show OrgCouncilsSetupPage, councilsSetupTitle;
import 'advising/adv_models.dart' show advOrgTypes;
import 'org_institution_wizard.dart' show institutionWizardTitle, openInstitutionWizard;
import 'org_institutions.dart' show OrgDeptCatalogPage, OrgStudySystemPage, orgInstitutionFeatureKey;
import 'org_ui.dart' show orgPickAndUpload;
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppTile;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;

// ═════════════════════════════════════════════════════════════════════════════
//  Settings ("More" on phones)
// ═════════════════════════════════════════════════════════════════════════════

class OrgSettingsPage extends StatefulWidget {
  const OrgSettingsPage({super.key, this.services = const []});

  /// The Services sub-pages, listed here on phones (where Services is not a tab).
  final List<OrgSub> services;

  @override
  State<OrgSettingsPage> createState() => _OrgSettingsPageState();
}

class _OrgSettingsPageState extends State<OrgSettingsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final c = context.colors;
    final s = context.watch<OrgSession>();
    final p = context.watch<ProfileProvider>();
    final dash = context.watch<OrgDashController>();
    Future<void> open(String title, Widget child) => orgPush(context, title, child);
    int badge(String key) => switch (key) {
          'forms' => dash.count('pending_forms'),
          'complaints' => dash.count('open_complaints'),
          _ => 0,
        };
    final governance = <Widget>[
      if (s.can('roles'))
        AppSettingsTile(
            icon: Icons.admin_panel_settings_rounded,
            label: t('الأدوار والصلاحيات', 'Roles & privileges'),
            subtitle: t('من يستطيع رؤية وتعديل كل جزء', 'Who can see and change each part'),
            onTap: () => open(t('الأدوار والصلاحيات', 'Roles & privileges'), const OrgAccessPage())),
      if (s.can('audit'))
        AppSettingsTile(
            icon: Icons.history_rounded,
            label: t('سجل النشاط', 'Activity log'),
            subtitle: t('من فعل ماذا ومتى', 'Who did what, and when'),
            onTap: () => open(t('سجل النشاط', 'Activity log'), const OrgActivityPage())),
      if (s.can('terms'))
        AppSettingsTile(
            icon: Icons.gavel_rounded,
            color: AdminPalette.orange.last,
            label: t('الشروط واللوائح', 'Terms & regulations'),
            onTap: () => open(t('الشروط واللوائح', 'Terms & regulations'), const OrgTermsAdminPage())),
      if (s.isOrgAdmin)
        AppSettingsTile(
            icon: Icons.family_restroom_rounded,
            featureKey: kParentVisibilityKey,
            label: t('رؤية أولياء الأمور للدرجات', 'What parents see of grades'),
            subtitle: t('اتبع إعداد المنصة أو حدّد قاعدة مؤسستك', 'Follow the platform setting or set your own rule'),
            onTap: () => openParentGradeVisibility(context, orgId: s.currentId)),
      if (s.canAny('certificates') || s.isOrgAdmin)
        AppSettingsTile(
            icon: Icons.workspace_premium_rounded,
            color: AdminPalette.orange.last,
            label: t('تصميمات الشهادات', 'Certificate designs'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCertificateDesigns(orgId: s.currentId)))),
      // Export Studio (D-130): scheduled exports and shared links; org admins also get the export log
      AppSettingsTile(
          icon: Icons.ios_share_rounded,
          featureKey: 'export.studio',
          label: t('التصدير', 'Exports'),
          subtitle: t('التصدير المجدول والروابط المشتركة وسجل التصدير', 'Scheduled exports, shared links and the export log'),
          onTap: () => Navigator.pushNamed(context, '/exports', arguments: s.isOrgAdmin)),
    ];
    // The Exam Hub (D-350), scoped to this organization: whoever manages its exams, and its teachers
    final showExams = s.currentId != null && (s.isOrgAdmin || s.can('exams', 'view') || examHubTeachingRole(s.memberRole));
    // D-103 page anatomy: a slim profile row (the big hero pushed the settings below the fold on phones), then the
    // groups, the organization's own entries first — edit · join code · sub-organization (they left the Home) —
    // each with one plain line saying what it does. No second search box: the header's search is right above.
    return AppSettingsPage(
      gutter: AppSpace.md,
      searchThreshold: 40,
      header: _ProfileRow(name: p.name, role: p.role, email: p.email, imageUrl: p.imageUrl),
      groups: [
        if (widget.services.isNotEmpty || showExams)
          AppSettingsGroup(title: t('التواصل والخدمات', 'Communication & services'), icon: Icons.forum_rounded, children: [
            if (showExams)
              AppSettingsTile(
                  icon: Icons.fact_check_rounded,
                  featureKey: kExamHubFeatureKey,
                  label: t('الاختبارات', 'Exams'),
                  subtitle: t('أنشئ وصحّح وانشر النتائج من مكان واحد', 'Create, correct and publish results in one place'),
                  keywords: 'exams correction results degrees اختبارات امتحانات تصحيح نتائج درجات',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredExamHub(orgId: s.currentId, orgName: s.name)))),
            for (final x in widget.services) AppSettingsTile(icon: x.$3, label: x.$2, badge: badge(x.$1), onTap: () => open(x.$2, x.$4)),
          ]),
        AppSettingsGroup(title: t('المؤسسة', 'Organization'), icon: Icons.domain_rounded, children: [
          if (s.isOrgAdmin) ...[
            const ChatEntryTile(),
            if (s.currentId != null) OrgChatSettingsTile(orgId: s.currentId!),
            AppSettingsTile(
                icon: Icons.edit_rounded,
                label: t('تعديل بيانات المؤسسة', 'Edit organization'),
                subtitle: t('الاسم والشعار وبيانات التواصل', 'Name, logo and contact details'),
                onTap: () => showOrgForm(context, edit: s.current)),
            AppSettingsTile(
                icon: Icons.vpn_key_rounded,
                label: t('كود الانضمام', 'Join code'),
                subtitle: t('شاركه ليطلب الناس الانضمام', 'Share it so people can ask to join'),
                keywords: 'code qr invite دعوة رمز',
                onTap: () => showJoinCode(context)),
            // C3: what students and staff pay, the creation fee and the payments — read-only
            AppSettingsTile(
                icon: Icons.receipt_long_rounded,
                featureKey: 'org.billing_view', // = orgBillingFeatureKey (the page itself is a deferred part)
                label: t('الفوترة والرسوم', 'Billing'),
                subtitle: t('ما يدفعه الطلاب والموظفون وإيصالات المؤسسة', "What students and staff pay, and the organization's receipts"),
                keywords: 'billing fees plans payments receipt رسوم اشتراك مدفوعات',
                onTap: () => open(t('الفوترة والرسوم', 'Billing'), deferredOrgBillingPage(orgId: s.currentId))),
          ],
          // Institutions S1 (D-960 – D-962): the study system and the department catalog
          if (s.can('organization', 'update'))
            AppSettingsTile(
                key: const ValueKey('settings.study_system'),
                icon: Icons.timer_outlined,
                featureKey: orgInstitutionFeatureKey,
                label: t('نظام الدراسة', 'Study system'),
                subtitle: t('تقليدي أو ساعات معتمدة', 'Traditional or credit hours'),
                keywords: 'study system credit hours traditional gpa نظام الدراسة ساعات معتمدة تقليدي',
                onTap: () => orgPush(context, t('نظام الدراسة', 'Study system'), const OrgStudySystemPage(), helpPageId: 'org.settings')),
          if (s.can('departments'))
            AppSettingsTile(
                key: const ValueKey('settings.dept_catalog'),
                icon: Icons.apartment_rounded,
                featureKey: orgInstitutionFeatureKey,
                label: t('دليل الإدارات', 'Department catalog'),
                subtitle: t('أنشئ الإدارات العلمية والخدمية وأنواع طلباتها بنقرة', 'Create academic and service departments and their request types in one go'),
                keywords: 'departments catalog template student affairs exam control إدارات أقسام شئون الطلاب كنترول',
                onTap: () => orgPush(context, t('دليل الإدارات', 'Department catalog'), const OrgDeptCatalogPage(), helpPageId: 'org.departments')),
          // Institutions v2 phase 3 (D-989 – D-990): faculty council, department councils, both or none
          if (s.isOrgAdmin)
            AppSettingsTile(
                key: const ValueKey('settings.councils_setup'),
                icon: Icons.account_balance_rounded,
                featureKey: orgInstitutionFeatureKey,
                label: councilsSetupTitle(),
                subtitle: t('مجلس الكلية، مجالس الأقسام، كلاهما أو بدون', 'Faculty council, department councils, both or none'),
                keywords: 'councils faculty council department council dean مجالس مجلس الكلية مجلس القسم',
                onTap: () => orgPush(context, councilsSetupTitle(), const OrgCouncilsSetupPage(), helpPageId: 'org.governance')),
          // Institutions v2 phase 4 (D-991 – D-993): the guided setup, resumable, for a university or a faculty
          if (s.isOrgAdmin && advOrgTypes.contains('${s.current?['type']}'))
            AppSettingsTile(
                key: const ValueKey('settings.institution_wizard'),
                icon: Icons.auto_fix_high_rounded,
                featureKey: orgInstitutionFeatureKey,
                label: institutionWizardTitle(),
                subtitle: t('الأساسيات، الإدارات، الرؤساء والمجالس خطوة بخطوة', 'Basics, departments, heads and councils, step by step'),
                keywords: 'setup wizard launch institution معالج إعداد إطلاق المؤسسة',
                onTap: () => openInstitutionWizard(context)),
          if (s.can('sub_orgs', 'insert') || s.isOrgAdmin)
            AppSettingsTile(
                icon: Icons.account_tree_rounded,
                label: t('مؤسسة فرعية جديدة', 'New sub-organization'),
                subtitle: t('كلية أو فرع أو معهد تابع', 'A faculty, branch or institute under this one'),
                onTap: () => showOrgForm(context, parentId: s.currentId)),
          AppSettingsTile(
              icon: Icons.swap_horiz_rounded,
              label: t('تبديل المؤسسة', 'Switch organization'),
              subtitle: t('أو العودة إلى حسابك الشخصي', 'Or go back to your personal account'),
              onTap: () => showOrgSwitcher(context)),
          if (s.canCreateRoot)
            AppSettingsTile(icon: Icons.add_business_rounded, label: t('مؤسسة جديدة', 'New organization'), onTap: () => showOrgForm(context)),
        ]),
        if (governance.isNotEmpty) AppSettingsGroup(title: t('الحوكمة', 'Governance'), icon: Icons.shield_rounded, children: governance),
        if (s.current != null) _dangerGroup(context, s),
        AppSettingsGroup(title: t('التفضيلات', 'Preferences'), icon: Icons.settings_rounded, children: [
          AppLanguageTile(color: AdminPalette.violet.last),
          // Institutions v2 phase 2: phone alerts for this organization's requests (all · important · off)
          if (s.currentId != null)
            AppSettingsTile(
                icon: Icons.notifications_active_rounded,
                color: c.primary,
                label: OrgNotifyPrefsPage.title(),
                subtitle: t('تنبيهات الهاتف لطلبات المؤسسة', 'Phone alerts for organization requests'),
                onTap: () => orgPush(context, OrgNotifyPrefsPage.title(), OrgNotifyPrefsPage(orgId: s.currentId!, embedded: true), maxWidth: AppWidth.form.max)),
          const DisplaySettingsTile(),
          const CertVerifyEntryTile(),
          if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
          const AppAssistantOpenTile(),
          const AppAssistantBubbleTile(),
          AppSettingsTile(
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(value: p.darkMode, onChanged: (b) async => p.changeMode(b))),
        ]),
        legalSettingsGroup(context), // privacy policy · terms of service (D-308)
      ],
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // two-step verification of the signed-in org admin / staff member (shown when the server allows it)
        const MfaSettingsEntry(),
        AppSettingsGroup(title: 'exit'.tr, icon: DirIcons.exitToApp, danger: true, children: [
          AppSettingsTile(
              icon: DirIcons.logout,
              color: c.danger,
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

/// Teacher assistants and admin assistants cannot leave on their own: the server refuses with `staff_cannot_leave`.
bool orgStaffCannotLeave(String? myRole) => myRole == 'teacher_assistant' || myRole == 'admin_assistant';

/// Danger zone: the org admin transfers the admin seat or closes the organization (typed-name confirmation); anyone
/// else can leave it. Every action names what it does and asks first.
AppSettingsGroup _dangerGroup(BuildContext context, OrgSession s) {
  final c = context.colors;
  return AppSettingsGroup(title: t('منطقة الخطر', 'Danger zone'), icon: Icons.warning_amber_rounded, danger: true, children: [
    if (s.isOrgAdmin) ...[
      AppSettingsTile(
          key: const ValueKey('danger.transfer'),
          icon: Icons.swap_horiz_rounded,
          color: c.danger,
          label: t('نقل إدارة المؤسسة', 'Transfer the admin seat'),
          subtitle: t('اختر عضواً ليصبح المدير الجديد', 'Pick a member to become the new admin'),
          onTap: () async {
            final id = s.currentId;
            if (id == null) return;
            final done = await showOrgTransferAdmin(context, orgId: id, orgName: s.name, platform: false);
            if (done) await s.load();
          }),
      AppSettingsTile(
          key: const ValueKey('danger.close'),
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          label: t('إغلاق / حذف المؤسسة', 'Close / delete the organization'),
          subtitle: t('يتطلب كتابة اسم المؤسسة', "You will type the organization's name to confirm"),
          onTap: () => _closeOrg(context, s)),
    ] else if (orgStaffCannotLeave('${s.current?['my_role']}'))
      // the server refuses (403 staff_cannot_leave): say so up front instead of after a confirmation
      AppSettingsTile(
          key: const ValueKey('danger.leave_blocked'),
          icon: DirIcons.logout,
          label: t('مغادرة المؤسسة', 'Leave the organization'),
          subtitle: orgCodeText('staff_cannot_leave'),
          onTap: () => showAppNotice(orgCodeText('staff_cannot_leave')))
    else
      AppSettingsTile(
          key: const ValueKey('danger.leave'),
          icon: DirIcons.logout,
          color: c.danger,
          label: t('مغادرة المؤسسة', 'Leave the organization'),
          subtitle: t('تفقد الوصول إلى لوحتها حتى تنضم مجدداً', 'You lose access to its dashboard until you join again'),
          onTap: () => _leaveOrg(context, s)),
  ]);
}

Future<void> _closeOrg(BuildContext context, OrgSession s) async {
  final org = s.current;
  if (org == null) return;
  final reason = await askTypedNameConfirm(context,
      org: org,
      askReason: false,
      title: t('إغلاق المؤسسة', 'Close the organization'),
      body: t('يجب ألا يكون لها فروع أو مقررات. لا يمكن التراجع عن هذا الإجراء.',
          'It must have no sub-organizations or courses. This cannot be undone.'),
      confirmLabel: t('إغلاق المؤسسة', 'Close the organization'));
  if (reason == null) return;
  await s.deleteOrg();
}

Future<void> _leaveOrg(BuildContext context, OrgSession s) async {
  final id = s.currentId;
  if (id == null) return;
  final ok = await confirm(context,
      message: t('هل تريد مغادرة «${s.name}»؟ ستفقد الوصول إلى لوحتها.', 'Leave "${s.name}"? You will lose access to its dashboard.'),
      danger: true,
      confirmLabel: t('مغادرة', 'Leave'));
  if (!ok) return;
  final r = await orgCall(() => ApiClient().delete('$orgBase/public/$id/leave'), ok: t('تمت المغادرة', 'You left the organization'));
  if (r.ok) await s.load(keepSelection: false);
}

/// The signed-in person in one slim card row: avatar · name · role and e-mail (D-102 language: card + hairline).
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.name, required this.role, required this.email, required this.imageUrl});
  final String name, role, email, imageUrl;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [if (role.isNotEmpty) appRoleLabel(role), if (email.isNotEmpty) email].join(' · ');
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: c.primary,
          foregroundImage: imageUrl.isEmpty ? null : NetworkImage(imageUrl),
          child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              style: AppType.section(context).copyWith(color: c.onHero)),
        ),
        AppSpace.gapSm,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  First organization (org admin who has none yet)
// ═════════════════════════════════════════════════════════════════════════════

class OrgFirstOrganization extends StatelessWidget {
  const OrgFirstOrganization({super.key});

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
              textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.family, color: c.textMedium)),
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
//  Switcher · create/edit · join code
// ═════════════════════════════════════════════════════════════════════════════

/// The organization switcher of the dashboard = THE shared context sheet (context_switcher.dart): Personal, my
/// organizations (switched in place), the ones where I study, join, and "New organization" when I may create one.
Future<void> showOrgSwitcher(BuildContext context) {
  final s = context.read<OrgSession>();
  return showContextSwitcherSheet(context, session: s, onCreateOrg: s.canCreateRoot ? () => showOrgForm(context) : null);
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
  // the organization's brand swatches (its own colour, not the theme's) — the hero gradient follows the pick
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
            Text(t('لون المؤسسة', 'Brand colour'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700, color: c.textDark)),
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
                      border: Border.all(color: color == h ? c.textDark : c.cardBg.withValues(alpha: 0), width: 2.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 14),
            // Logo: upload an image (cropped, resized, stored publicly) — or paste a URL.
            Row(children: [
              if (logo.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.network(logo.text.trim(), width: 52, height: 52, fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(width: 52, height: 52)),
                  ),
                ),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final r = await orgPickAndUpload('/api/v1/org/logo',
                        extensions: const ['png', 'jpg', 'jpeg', 'webp'], context: ctx, cropShape: CropShape.square);
                    if (r != null) set(() => logo.text = '${r['url']}');
                  },
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: Text(logo.text.trim().isEmpty ? t('رفع الشعار', 'Upload logo') : t('تغيير الشعار', 'Change logo')),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Field(controller: desc, label: t('نبذة (اختياري)', 'About (optional)'), maxLines: 3),
            if (official) ...[
              const SizedBox(height: 6),
              Text(t('بيانات رسمية — تساعد فريق المنصة على اعتماد مؤسستك بسرعة', 'Official details — they help the platform team approve you quickly'),
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700, color: c.textDark)),
              const SizedBox(height: 8),
              Field(controller: license, label: t('رقم القرار / الترخيص', 'Decree / licence number')),
              Field(controller: email, label: t('البريد الرسمي', 'Official e-mail'), ltr: true),
              PhoneInputField(controller: phone, label: t('هاتف التواصل', 'Contact phone')),
              Field(controller: website, label: t('الموقع الإلكتروني', 'Website'), ltr: true),
              Field(controller: address, label: t('العنوان', 'Address')),
            ],
            // platform creation fee: org admins pay once per new root organization request (server enforces it)
            if (edit == null && parentId == null && context.read<MyAuthProvider>().currentUser?.role == 'org-admin')
              OrgCreationFeePanel(loggedIn: true, onReady: (_, _) {}),
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
                  final typed = await askTypedNameConfirm(ctx,
                      org: edit,
                      askReason: false,
                      title: t('حذف المؤسسة', 'Delete the organization'),
                      body: t('يجب أن تكون بلا فروع أو مقررات. لا يمكن التراجع.', 'It must have no sub-organizations or courses. This cannot be undone.'),
                      confirmLabel: t('حذف المؤسسة', 'Delete the organization'));
                  if (typed != null && await s.deleteOrg() && ctx.mounted) Navigator.pop(ctx);
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
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SheetHeader(t('كود الانضمام', 'Join code')),
            Text(t('شارك هذا الكود مع الطلاب والمدرسين ليدخلوا مؤسستك مباشرة.', 'Share this code so students and teachers can join directly.'),
                textAlign: TextAlign.center, style: TextStyle(fontFamily: AppFonts.family, color: c.textMedium)),
            const SizedBox(height: 16),
            SelectableText(code, textDirection: TextDirection.ltr, style: TextStyle(fontFamily: AppFonts.display, fontSize: 34, letterSpacing: 6, fontWeight: FontWeight.w800, color: c.primary)),
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
