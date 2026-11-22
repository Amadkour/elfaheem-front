// lib/features/org/org_settings_groups.dart — the organization's settings as reusable groups (D-1180).
//
// Profile = me; Organization = the organization; Management = its daily work. The rows that used to share one long
// Settings page live here, built once and composed in two places:
//   the workspace's Organization tab (ws_organization.dart)   orgOrganizationGroups + orgDangerFold
//   the workspace's Profile tab (ws_profile.dart)             orgAccountRows · orgPreferenceRows · orgHelpGroup · orgExitGroup
//   the D-103 Settings tab (OrgSettingsPage, the kill switch's fallback)   all of them, the organization first
// Every row keeps its own right check (OrgSession.can …) and kill-switch key (featureKey); a group with no row left
// is not drawn.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/app_mode.dart' show AppModeController;
import 'package:flutter_education_app/core/personal_access.dart' show PersonalAccess;
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppSettingsGroup, AppSettingsTile, AppSheetContent, AppSwitch, showAppNotice, showAppSheet;
import 'package:flutter_education_app/design/app_language_switch.dart' show AppLanguageTile;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/calendar_entry.dart' show ChatEntryTile;
import 'package:flutter_education_app/design/context_switcher.dart' show showContextSwitcherSheet;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/mfa_entry.dart' show MfaSettingsEntry;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
import 'package:flutter_education_app/features/exams/parent_grade_visibility.dart' show kParentVisibilityKey, openParentGradeVisibility;
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppTile;
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart' show DisplaySettingsPage;
import 'package:flutter_education_app/features/profile/legal/legal_links.dart' show legalSettingsGroup;
import 'package:flutter_education_app/features/profile/personal_account_tile.dart' show PersonalAccountTile;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart' show t, confirm;
import '../admin/admin_premium_widgets.dart' show AdminPalette;
import 'advising/adv_models.dart' show advOrgTypes;
import 'governance/gov_councils_setup.dart' show OrgCouncilsSetupPage, councilsSetupTitle;
import 'org_access_page.dart' show OrgAccessPage, OrgActivityPage;
import 'org_chat_settings_tile.dart';
import 'org_common.dart' show joinModeLabels;
import 'org_danger_zone.dart' show askTypedNameConfirm, showOrgTransferAdmin;
import 'org_dashboard_home.dart' show orgPush;
import 'org_dashboard_settings.dart' show showJoinCode, showOrgForm;
import 'org_exam_policy_page.dart' show OrgExamPolicyPage;
import 'org_inst_notify.dart' show OrgNotifyPrefsPage;
import 'org_institution_wizard.dart' show institutionWizardTitle, openInstitutionWizard;
import 'org_institutions.dart' show OrgDeptCatalogPage, OrgStudySystemPage, orgInstitutionFeatureKey;
import 'org_providers.dart';
import 'org_terms_pages.dart' show OrgTermsAdminPage;
import 'org_v3.dart' show orgCall, orgCodeText;

Future<void> _open(BuildContext context, String title, Widget child, {String? helpPageId}) =>
    orgPush(context, title, child, helpPageId: helpPageId);

// ═════════════════════════════════════════════════════════════════════════════
//  The organization (Organization tab)
// ═════════════════════════════════════════════════════════════════════════════

/// Joining & access: the join code, how people join, who may do what.
List<Widget> orgAccessRows(BuildContext context, OrgSession s) => [
      if (s.isOrgAdmin) ...[
        AppSettingsTile(
            key: const ValueKey('org.set.join_code'),
            icon: Icons.vpn_key_rounded,
            label: t('كود الانضمام', 'Join code'),
            subtitle: t('شاركه ليطلب الناس الانضمام', 'Share it so people can ask to join'),
            keywords: 'code qr invite دعوة رمز',
            onTap: () => showJoinCode(context)),
        AppSettingsTile(
            key: const ValueKey('org.set.join_mode'),
            icon: Icons.how_to_reg_rounded,
            label: t('طريقة الانضمام', 'How people join'),
            subtitle: joinModeLabels()['${s.current?['join_mode'] ?? 'approval'}'] ?? '',
            keywords: 'join mode open approval code closed انضمام موافقة مفتوح مغلق',
            onTap: () => showOrgJoinModeSheet(context)),
      ],
      if (s.can('roles'))
        AppSettingsTile(
            key: const ValueKey('org.set.roles'),
            icon: Icons.admin_panel_settings_rounded,
            label: t('الأدوار والصلاحيات', 'Roles & privileges'),
            subtitle: t('من يستطيع رؤية وتعديل كل جزء', 'Who can see and change each part'),
            onTap: () => _open(context, t('الأدوار والصلاحيات', 'Roles & privileges'), const OrgAccessPage())),
    ];

/// Structure: the guided setup, the study system, the department catalog, councils, sub-organizations.
List<Widget> orgStructureRows(BuildContext context, OrgSession s) => [
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
      // Institutions S1 (D-960 – D-962): the study system and the department catalog
      if (s.can('organization', 'update'))
        AppSettingsTile(
            key: const ValueKey('settings.study_system'),
            icon: Icons.timer_outlined,
            featureKey: orgInstitutionFeatureKey,
            label: t('نظام الدراسة', 'Study system'),
            subtitle: t('تقليدي أو ساعات معتمدة', 'Traditional or credit hours'),
            keywords: 'study system credit hours traditional gpa نظام الدراسة ساعات معتمدة تقليدي',
            onTap: () => _open(context, t('نظام الدراسة', 'Study system'), const OrgStudySystemPage(), helpPageId: 'org.settings')),
      if (s.can('departments'))
        AppSettingsTile(
            key: const ValueKey('settings.dept_catalog'),
            icon: Icons.apartment_rounded,
            featureKey: orgInstitutionFeatureKey,
            label: t('دليل الإدارات', 'Department catalog'),
            subtitle: t('أنشئ الإدارات العلمية والخدمية وأنواع طلباتها بنقرة', 'Create academic and service departments and their request types in one go'),
            keywords: 'departments catalog template student affairs exam control إدارات أقسام شئون الطلاب كنترول',
            onTap: () => _open(context, t('دليل الإدارات', 'Department catalog'), const OrgDeptCatalogPage(), helpPageId: 'org.departments')),
      // Institutions v2 phase 3 (D-989 – D-990): faculty council, department councils, both or none
      if (s.isOrgAdmin)
        AppSettingsTile(
            key: const ValueKey('settings.councils_setup'),
            icon: Icons.account_balance_rounded,
            featureKey: orgInstitutionFeatureKey,
            label: councilsSetupTitle(),
            subtitle: t('مجلس الكلية، مجالس الأقسام، كلاهما أو بدون', 'Faculty council, department councils, both or none'),
            keywords: 'councils faculty council department council dean مجالس مجلس الكلية مجلس القسم',
            onTap: () => _open(context, councilsSetupTitle(), const OrgCouncilsSetupPage(), helpPageId: 'org.governance')),
      if (s.can('sub_orgs', 'insert') || s.isOrgAdmin)
        AppSettingsTile(
            key: const ValueKey('org.set.sub_org'),
            icon: Icons.account_tree_rounded,
            label: t('مؤسسة فرعية جديدة', 'New sub-organization'),
            subtitle: t('كلية أو فرع أو معهد تابع', 'A faculty, branch or institute under this one'),
            onTap: () => showOrgForm(context, parentId: s.currentId)),
    ];

/// Policies: terms, exam policy, what parents see, chat rules.
List<Widget> orgPolicyRows(BuildContext context, OrgSession s) => [
      if (s.can('terms'))
        AppSettingsTile(
            key: const ValueKey('org.set.terms'),
            icon: Icons.gavel_rounded,
            color: AdminPalette.orange.last,
            label: t('الشروط واللوائح', 'Terms & regulations'),
            onTap: () => _open(context, t('الشروط واللوائح', 'Terms & regulations'), const OrgTermsAdminPage())),
      // D-1133: the organization's exam limits and methods, which only tighten the platform's
      if (s.isOrgAdmin && s.currentId != null)
        AppSettingsTile(
            key: const ValueKey('org.set.exam_policy'),
            icon: Icons.policy_rounded,
            label: t('سياسة الاختبارات', 'Exam policy'),
            subtitle: t('حدود الاختبارات وطرقها في مؤسستك', 'Exam limits and methods in your organization'),
            onTap: () => _open(context, t('سياسة الاختبارات', 'Exam policy'), OrgExamPolicyPage(orgId: s.currentId!))),
      if (s.isOrgAdmin)
        AppSettingsTile(
            key: const ValueKey('org.set.parents'),
            icon: Icons.family_restroom_rounded,
            featureKey: kParentVisibilityKey,
            label: t('رؤية أولياء الأمور للدرجات', 'What parents see of grades'),
            subtitle: t('اتبع إعداد المنصة أو حدّد قاعدة مؤسستك', 'Follow the platform setting or set your own rule'),
            onTap: () => openParentGradeVisibility(context, orgId: s.currentId)),
      if (s.isOrgAdmin && s.currentId != null) OrgChatSettingsTile(orgId: s.currentId!),
    ];

/// Records & billing: what is paid, who did what, exports, certificate designs.
List<Widget> orgRecordRows(BuildContext context, OrgSession s) => [
      // C3: what students and staff pay, the creation fee and the payments — read-only
      if (s.isOrgAdmin)
        AppSettingsTile(
            key: const ValueKey('org.set.billing'),
            icon: Icons.receipt_long_rounded,
            featureKey: 'org.billing_view', // = orgBillingFeatureKey (the page itself is a deferred part)
            label: t('الفوترة والرسوم', 'Billing'),
            subtitle: t('ما يدفعه الطلاب والموظفون وإيصالات المؤسسة', "What students and staff pay, and the organization's receipts"),
            keywords: 'billing fees plans payments receipt رسوم اشتراك مدفوعات',
            onTap: () => _open(context, t('الفوترة والرسوم', 'Billing'), deferredOrgBillingPage(orgId: s.currentId))),
      if (s.can('audit'))
        AppSettingsTile(
            key: const ValueKey('org.set.activity'),
            icon: Icons.history_rounded,
            label: t('سجل النشاط', 'Activity log'),
            subtitle: t('من فعل ماذا ومتى', 'Who did what, and when'),
            onTap: () => _open(context, t('سجل النشاط', 'Activity log'), const OrgActivityPage())),
      // Export Studio (D-130): scheduled exports and shared links; org admins also get the export log
      AppSettingsTile(
          key: const ValueKey('org.set.exports'),
          icon: Icons.ios_share_rounded,
          featureKey: 'export.studio',
          label: t('التصدير', 'Exports'),
          subtitle: t('التصدير المجدول والروابط المشتركة وسجل التصدير', 'Scheduled exports, shared links and the export log'),
          onTap: () => Navigator.pushNamed(context, '/exports', arguments: s.isOrgAdmin)),
      if (s.canAny('certificates') || s.isOrgAdmin)
        AppSettingsTile(
            key: const ValueKey('org.set.certificates'),
            icon: Icons.workspace_premium_rounded,
            label: t('الشهادات', 'Certificates'),
            subtitle: t('تصميمات الشهادات', 'Certificate designs'),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => deferredCertificateDesigns(orgId: s.currentId)))),
    ];

/// The organization's groups, in the Organization tab's order; an empty group is left out.
List<AppSettingsGroup> orgOrganizationGroups(BuildContext context, OrgSession s) {
  AppSettingsGroup? group(String ar, String en, IconData icon, List<Widget> rows) =>
      rows.isEmpty ? null : AppSettingsGroup(title: t(ar, en), icon: icon, children: rows);
  return [
    ?group('الانضمام والصلاحيات', 'Joining & access', Icons.key_rounded, orgAccessRows(context, s)),
    ?group('الهيكل', 'Structure', Icons.account_tree_rounded, orgStructureRows(context, s)),
    ?group('السياسات', 'Policies', Icons.shield_rounded, orgPolicyRows(context, s)),
    ?group('السجلات والفوترة', 'Records & billing', Icons.folder_open_rounded, orgRecordRows(context, s)),
  ];
}

/// How people join this organization: one choice, saved at once (the update sends only `join_mode`; the server
/// changes only the fields it is sent).
Future<void> showOrgJoinModeSheet(BuildContext context) {
  final s = context.read<OrgSession>();
  return showAppSheet<void>(context, (ctx) {
    var mode = '${s.current?['join_mode'] ?? 'approval'}';
    var busy = false;
    return StatefulBuilder(
      builder: (ctx, set) => AppSheetContent(
        title: t('طريقة الانضمام', 'How people join'),
        subtitle: t('تنطبق على من يطلب الانضمام إلى المؤسسة نفسها', 'Applies to people who ask to join the organization itself'),
        icon: Icons.how_to_reg_rounded,
        children: [
          RadioGroup<String>(
            groupValue: mode,
            onChanged: (v) async {
              if (v == null || v == mode || busy) return;
              final before = mode;
              set(() {
                mode = v;
                busy = true;
              });
              final ok = await s.updateOrg({'join_mode': v});
              if (!ctx.mounted) return;
              set(() {
                busy = false;
                if (!ok) mode = before;
              });
            },
            child: Column(children: [
              for (final e in joinModeLabels().entries)
                RadioListTile<String>(
                  key: ValueKey('org.join_mode.${e.key}'),
                  value: e.key,
                  enabled: !busy,
                  title: Text(e.value, style: AppType.row(ctx)),
                ),
            ]),
          ),
        ],
      ),
    );
  });
}

// ── Danger zone ──────────────────────────────────────────────────────────────

/// Danger zone: the org admin transfers the admin seat or closes the organization (typed-name confirmation); anyone
/// else can leave it. Every action names what it does and asks first.
AppSettingsGroup orgDangerGroup(BuildContext context, OrgSession s) {
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
    ] else
      orgLeaveTile(context, s),
  ]);
}

/// The danger zone folded to one row until opened (progressive disclosure: it never sits open at the end of a
/// page an admin scrolls every day).
class OrgDangerFold extends StatefulWidget {
  const OrgDangerFold({super.key});

  @override
  State<OrgDangerFold> createState() => _OrgDangerFoldState();
}

class _OrgDangerFoldState extends State<OrgDangerFold> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    if (s.current == null || !s.isOrgAdmin) return const SizedBox.shrink();
    if (_open) return orgDangerGroup(context, s);
    final c = context.colors;
    return AppSettingsGroup(title: t('منطقة الخطر', 'Danger zone'), icon: Icons.warning_amber_rounded, danger: true, children: [
      AppSettingsTile(
          key: const ValueKey('danger.open'),
          icon: Icons.expand_more_rounded,
          color: c.danger,
          label: t('عرض الإجراءات الخطرة', 'Show the dangerous actions'),
          subtitle: t('نقل إدارة المؤسسة أو إغلاقها', 'Transfer the admin seat or close the organization'),
          onTap: () => setState(() => _open = true)),
    ]);
  }
}

/// Teacher assistants and admin assistants cannot leave on their own: the server refuses with `staff_cannot_leave`.
bool orgStaffCannotLeave(String? myRole) => myRole == 'teacher_assistant' || myRole == 'admin_assistant';

/// Leave the organization: a quiet red exit row, or — for the staff the server keeps (403 staff_cannot_leave) — a
/// plain row that says so up front instead of after a confirmation.
Widget orgLeaveTile(BuildContext context, OrgSession s) => orgStaffCannotLeave('${s.current?['my_role']}')
    ? AppSettingsTile(
        key: const ValueKey('danger.leave_blocked'),
        icon: DirIcons.logout,
        label: t('مغادرة المؤسسة', 'Leave the organization'),
        subtitle: orgCodeText('staff_cannot_leave'),
        onTap: () => showAppNotice(orgCodeText('staff_cannot_leave')))
    : AppSettingsTile(
        key: const ValueKey('danger.leave'),
        icon: DirIcons.logout,
        danger: true,
        label: t('مغادرة المؤسسة', 'Leave the organization'),
        subtitle: t('تفقد الوصول إلى لوحتها حتى تنضم مجدداً', 'You lose access to its dashboard until you join again'),
        onTap: () => _leaveOrg(context, s));

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
  if (!r.ok || !context.mounted) return;
  // the last membership gone: the server may restore the role (org-staff -> teacher / student) and turns the
  // personal account back on, so the user is re-read and a role without the organization dashboard goes home
  final auth = context.read<MyAuthProvider>();
  final before = auth.currentUser?.role;
  await auth.getMe();
  final after = auth.currentUser?.role;
  if (context.mounted && after != null && after != before && !PersonalAccess.isOrgRole(after)) {
    await AppModeController.instance.refresh();
    if (context.mounted) Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(auth.homeRoute, (_) => false);
    return;
  }
  await s.load(keepSelection: false);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Me (Profile tab)
// ═════════════════════════════════════════════════════════════════════════════

/// Account: the one switcher, the personal account, my messages, a new organization of my own.
List<Widget> orgAccountRows(BuildContext context, OrgSession s) => [
      AppSettingsTile(
          key: const ValueKey('ws.profile.switch'),
          icon: Icons.swap_horiz_rounded,
          label: t('تبديل الحساب', 'Switch account'),
          subtitle: t('حسابك الشخصي وحسابات مؤسساتك', 'Your personal account and your organization accounts'),
          keywords: 'switch account organization تبديل حساب مؤسسة',
          onTap: () => showContextSwitcherSheet(context, session: s)),
      const PersonalAccountTile(inOrg: true),
      const ChatEntryTile(),
      if (s.canCreateRoot)
        AppSettingsTile(
            key: const ValueKey('org.set.new_org'),
            icon: Icons.add_business_rounded,
            label: t('إنشاء مؤسسة أخرى', 'Create another organization'),
            onTap: () => showOrgForm(context)),
    ];

/// My preferences: this organization's phone alerts, display & reading, language, assistant, dark mode.
List<Widget> orgPreferenceRows(BuildContext context, OrgSession s, ProfileProvider p) => [
      // Institutions v2 phase 2: phone alerts for this organization's requests (all · important · off)
      if (s.currentId != null)
        AppSettingsTile(
            key: const ValueKey('org.set.notifications'),
            icon: Icons.notifications_active_rounded,
            label: t('الإشعارات', 'Notifications'),
            subtitle: t('تنبيهات الهاتف لطلبات المؤسسة', 'Phone alerts for organization requests'),
            onTap: () => orgPush(context, OrgNotifyPrefsPage.title(), OrgNotifyPrefsPage(orgId: s.currentId!, embedded: true),
                maxWidth: AppWidth.form.max)),
      AppSettingsTile(
          key: const ValueKey('org.set.display'),
          icon: Icons.text_fields_rounded,
          featureKey: 'profile.display',
          label: t('العرض والقراءة', 'Display & reading'),
          subtitle: t('الخط، حجم النص، التباين، الحركة', 'Font, text size, contrast, motion'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DisplaySettingsPage()))),
      const AppLanguageTile(),
      AppSettingsTile(
          icon: Icons.dark_mode_rounded,
          label: 'dark_mode'.tr,
          trailing: AppSwitch(value: p.darkMode, onChanged: (b) async => p.changeMode(b))),
      const AppAssistantOpenTile(),
      const AppAssistantBubbleTile(),
    ];

/// Security: two-step verification (shown when the server allows it).
AppSettingsGroup orgSecurityGroup() => AppSettingsGroup(
    title: t('الأمان', 'Security'), icon: Icons.lock_rounded, children: const [MfaSettingsEntry()]);

/// Help & legal: verify a certificate, get the app, privacy, terms.
AppSettingsGroup orgHelpGroup(BuildContext context) => AppSettingsGroup(
      title: t('المساعدة والشروط', 'Help & legal'),
      icon: Icons.policy_rounded,
      children: [
        const CertVerifyEntryTile(),
        if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
        ...legalSettingsGroup(context).children,
      ],
    );

/// The exits: leaving this organization (not its admin, who has the danger zone) and signing out.
AppSettingsGroup orgExitGroup(BuildContext context, OrgSession s) =>
    AppSettingsGroup(title: 'exit'.tr, icon: DirIcons.exitToApp, children: [
      if (s.current != null && !s.isOrgAdmin) orgLeaveTile(context, s),
      AppSettingsTile(
          key: const ValueKey('settings.logout'),
          icon: DirIcons.logout,
          danger: true,
          label: 'logout'.tr,
          onTap: () async {
            final ok = await Helpers.confirmDialog(context);
            if (ok == true && context.mounted) await context.read<ProfileProvider>().logout(context);
          }),
    ]);
