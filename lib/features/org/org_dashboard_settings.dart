// lib/features/org/org_dashboard_settings.dart
//
// The org-admin Settings section ("More" on phones, where it also carries the Services links) and the
// organization sheets:
//   OrgSettingsPage       the D-103 Settings tab (the workspace kill switch's fallback): the profile card, then the
//                         SAME groups as the workspace's Organization and Profile tabs (org_settings_groups.dart,
//                         D-1180) — Communication & services · Organization (edit) · Joining & access · Structure ·
//                         Policies · Records & billing · Account · Preferences · Help & legal — and the footer:
//                         security, the folded danger zone, the exits. Two columns on a wide body; search past 40.
//   OrgFirstOrganization  the org admin who has none yet.
//   showOrgSwitcher · showOrgForm · showJoinCode   the sheets (also used by org_status_screen.dart).
// Every sub-page opens through orgPush (the session carried along, the exit button in its bar).
library;

import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppSettingsGroup, AppSettingsPage, AppSettingsTile, AppVersionLine, appRoleLabel;
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/context_switcher.dart' show showContextSwitcherSheet;
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/utils/widget/phone_field.dart';
import 'package:flutter_education_app/utils/widget/primary_button.dart';
import 'package:provider/provider.dart';

import '../admin/admin_common.dart';
import 'org_common.dart';
import 'org_creation_fee.dart' show OrgCreationFeePanel;
import 'org_dashboard_home.dart' show orgPush;
import 'org_dashboard_screen.dart' show OrgSub;
import 'package:flutter_education_app/features/exams/hub/hub_entry.dart' show examHubTeachingRole, kExamHubFeatureKey;
import 'org_providers.dart';
import 'org_settings_groups.dart';

// moved with the other rows (D-1180); kept importable from here
export 'org_settings_groups.dart' show orgStaffCannotLeave, orgDangerGroup, orgLeaveTile;
import 'org_ui.dart' show orgPickAndUpload;
import 'package:flutter_education_app/core/display/app_fonts.dart';

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
    final s = context.watch<OrgSession>();
    final p = context.watch<ProfileProvider>();
    final dash = context.watch<OrgDashController>();
    int badge(String key) => switch (key) {
          'forms' => dash.count('pending_forms'),
          'complaints' => dash.count('open_complaints'),
          _ => 0,
        };
    // The Exam Hub (D-350), scoped to this organization: whoever manages its exams, and its teachers
    final showExams = s.currentId != null && (s.isOrgAdmin || s.can('exams', 'view') || examHubTeachingRole(s.memberRole));
    // D-1180: the same groups as the workspace's Organization and Profile tabs (org_settings_groups.dart) — the
    // organization first, then me — so the kill switch's fallback holds exactly the same rows.
    return AppSettingsPage(
      gutter: AppSpace.md,
      searchThreshold: 40,
      columns: true,
      header: OrgProfileCard(
          name: p.name,
          role: p.role,
          email: p.email,
          imageUrl: p.imageUrl,
          org: s.current == null ? '' : s.name,
          onSwitch: () => showOrgSwitcher(context)),
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
            for (final x in widget.services)
              AppSettingsTile(icon: x.$3, label: x.$2, badge: badge(x.$1), onTap: () => orgPush(context, x.$2, x.$4)),
          ]),
        if (s.isOrgAdmin)
          AppSettingsGroup(title: t('المؤسسة', 'Organization'), icon: Icons.domain_rounded, children: [
            AppSettingsTile(
                key: const ValueKey('org.set.edit'),
                icon: Icons.edit_rounded,
                label: t('تعديل بيانات المؤسسة', 'Edit organization'),
                subtitle: t('الاسم والشعار وبيانات التواصل', 'Name, logo and contact details'),
                onTap: () => showOrgForm(context, edit: s.current)),
          ]),
        ...orgOrganizationGroups(context, s),
        AppSettingsGroup(title: t('الحساب', 'Account'), icon: Icons.person_rounded, children: orgAccountRows(context, s)),
        AppSettingsGroup(title: t('التفضيلات', 'Preferences'), icon: Icons.tune_rounded, children: orgPreferenceRows(context, s, p)),
        orgHelpGroup(context),
      ],
      footer: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        orgSecurityGroup(),
        if (s.current != null && s.isOrgAdmin) const OrgDangerFold(),
        orgExitGroup(context, s),
        const SizedBox(height: AppSpace.md),
        const AppVersionLine(),
      ]),
    );
  }
}

/// The signed-in person in one slim card row: avatar · name · role and e-mail (D-102 language: card + hairline).
class OrgProfileCard extends StatelessWidget {
  const OrgProfileCard({required this.name, required this.role, required this.email, required this.imageUrl, this.org = '', this.onSwitch});
  final String name, role, email, imageUrl;

  /// Profile E: the organization I am in, on a chip with Switch under the name; empty = no chip.
  final String org;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final meta = [if (role.isNotEmpty) appRoleLabel(role), if (email.isNotEmpty) email].join(' · ');
    return Container(
      padding: AppSpace.card,
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
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
      if (org.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        Material(
          color: c.primaryTint,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            key: const ValueKey('settings.org_chip'),
            borderRadius: BorderRadius.circular(AppRadius.control),
            onTap: onSwitch,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.min),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
                child: Row(children: [
                  Icon(Icons.apartment_rounded, size: AppIconSize.md, color: c.blockAccentInk(c.primary, c.cardBg)),
                  const SizedBox(width: AppSpace.xs),
                  Expanded(child: Text(org, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark))),
                  if (onSwitch != null) ...[
                    const SizedBox(width: AppSpace.xs),
                    Text(t('تبديل', 'Switch'),
                        style: AppType.label(context).copyWith(color: c.blockAccentInk(c.primary, c.cardBg), fontWeight: FontWeight.w600)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ],
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
            // how people join is its own setting once the organization exists (Organization › Joining & access, D-1180)
            if (edit == null) ...[
              ChoiceRow<String>(label: t('طريقة الانضمام', 'How people join'), options: joinModeLabels(), value: mode, onChanged: (v) => set(() => mode = v)),
              const SizedBox(height: 12),
            ],
            Text(t('لون المؤسسة', 'Brand colour'), style: AppType.label(ctx).copyWith(color: c.textDark)),
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
                  style: AppType.label(ctx).copyWith(color: c.textDark)),
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
                  if (edit == null) 'join_mode': mode,
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
