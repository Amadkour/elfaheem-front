// lib/features/parent/pa_more_page.dart — the parent's "More" tab (Pa2More `screen=more`, phase 4).
//
//   hero      the parent: avatar · name · "Parent" · e-mail · phone (LTR) · Edit account
//   tiles     Link a child (pending requests) · Book for your child · Payments and invoices
//   my kids   the linked children with their consent state; a row opens the child's page
//   settings  every setting the old More page had, in the kit's settings groups (account, calendar and messages,
//             language, display, the app, the assistant, dark mode, complaints and support, legal, sign out, delete)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_icons.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_language_switch.dart' show AppLanguageTile;
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/design/calendar_entry.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart';
import 'package:flutter_education_app/features/auth/reauth_sheet.dart';
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show CertVerifyEntryTile;
import 'package:flutter_education_app/features/get_app/get_app_banner.dart' show GetAppTile;
import 'package:flutter_education_app/features/profile/change_password_widget.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_page.dart';
import 'package:flutter_education_app/features/profile/display/display_settings_page.dart' show DisplaySettingsTile;
import 'package:flutter_education_app/features/profile/legal/legal_links.dart' show legalSettingsGroup;
import 'package:flutter_education_app/features/profile/profile_provider.dart';
import 'package:flutter_education_app/features/profile/update_account_widget.dart';
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistantOpenTile, AppAssistantBubbleTile;
import 'package:flutter_education_app/utils/helpers.dart';

import 'pa_child_pages.dart';
import 'pa_kit.dart';
import 'parent_link_providers.dart';

class ParentMorePage extends StatefulWidget {
  const ParentMorePage({super.key, required this.onOpenLink, this.onBook, this.onPayments});

  final VoidCallback onOpenLink;

  /// "Book for your child"; null = not offered (booking switched off).
  final VoidCallback? onBook;

  /// "Payments and invoices"; null = not offered.
  final VoidCallback? onPayments;

  @override
  State<ParentMorePage> createState() => _ParentMorePageState();
}

class _ParentMorePageState extends State<ParentMorePage> {
  Future<void> _push(Widget s) async => await Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
    });
  }

  Future<void> _edit() async {
    await _push(const EditAccountScreen(isTeacher: false));
    if (mounted) context.read<ProfileProvider>().initData(context.read<MyAuthProvider>().currentUser);
  }

  Widget _header(BuildContext context, ProfileProvider p) {
    final c = context.colors;
    ParentLinkProvider? link;
    try {
      link = context.watch<ParentLinkProvider>();
    } on ProviderNotFoundException {
      link = null;
    }
    final pending = link?.pendingCount ?? 0;
    final kids = [for (final ch in link?.children ?? const <Map<String, dynamic>>[]) if (ch['id'] is num) ch];
    final wide = paWide(context);
    final name = p.name.trim();
    final hero = AppHeroSurface(
      borderRadius: BorderRadius.circular(AppRadius.cardFor(MediaQuery.sizeOf(context).width)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppAvatar(name: name, url: p.imageUrl.isEmpty ? null : p.imageUrl, size: AppHero.leadingSize(wide)),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(name, style: AppType.headline(context).copyWith(color: c.onHero)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs),
                  decoration: BoxDecoration(color: c.heroGlass, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('role_parent'.tr, style: AppType.meta(context).copyWith(color: c.onHero)),
                ),
              ]),
              if (p.email.isNotEmpty)
                Text(p.email, textDirection: TextDirection.ltr, style: AppType.body(context).copyWith(color: c.onHeroMuted)),
              if (p.phone.isNotEmpty)
                Text(p.phone, textDirection: TextDirection.ltr, style: AppType.body(context).copyWith(color: c.onHeroMuted)),
              const SizedBox(height: AppSpace.sm),
              AppButton.secondary(key: const ValueKey('pa.more.edit'), label: 'update_account'.tr, icon: Icons.edit_outlined, onPressed: _edit),
            ]),
          ),
        ]),
      ),
    );
    final grape = c.kit.accent(AppAccent.grape), sky = c.kit.accent(AppAccent.sky), sun = c.kit.accent(AppAccent.sun);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: PaStack(children: [
        hero,
        AppTile(
          key: const ValueKey('pa.more.link'),
          icon: Icons.link_rounded,
          tone: grape,
          title: 'pa_link_child'.tr,
          subtitle: pending > 0 ? paFmt('pa_link_pending', {'n': appDigits('$pending')}) : 'pa_link_sub'.tr,
          trailing: pending > 0 ? AppCountBadge(count: pending) : const Icon(Icons.chevron_right_rounded),
          onTap: widget.onOpenLink,
        ),
        if (widget.onBook != null)
          AppTile(
            key: const ValueKey('pa.more.book'),
            icon: Icons.edit_calendar_outlined,
            tone: sky,
            title: 'pa_book_for_child'.tr,
            subtitle: 'pa_book_for_child_sub'.tr,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onBook,
          ),
        if (widget.onPayments != null)
          AppTile(
            key: const ValueKey('pa.more.pay'),
            icon: Icons.receipt_long_outlined,
            tone: sun,
            title: 'pa_payments'.tr,
            subtitle: 'pa_payments_sub'.tr,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: widget.onPayments,
          ),
        if (kids.isNotEmpty)
          AppCard(
            title: 'pa_my_linked_kids'.tr,
            action: AppButton.ghost(label: 'pa_link_child'.tr, size: AppButtonSize.sm, onPressed: widget.onOpenLink),
            child: PaStack(gap: AppSpace.xs, children: [
              for (final ch in kids)
                AppTile(
                  dense: true,
                  leading: PaKidAvatar(id: (ch['id'] as num).toInt(), name: '${ch['name']}', size: AppDashSize.glyph),
                  title: '${ch['name']}',
                  subtitle: '${ch['grade_name'] ?? ''}'.isEmpty ? null : '${ch['grade_name']}',
                  trailing: AppStatusBadge(
                    label: ch['needs_consent'] == true ? 'pa_waiting_consent'.tr : 'pa_consent_done'.tr,
                    tone: ch['needs_consent'] == true ? AppTone.warning : AppTone.success,
                  ),
                  onTap: () => paPush<void>(context, ParentChildPage(childId: (ch['id'] as num).toInt())),
                ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = context.watch<ProfileProvider>();
    return AppSettingsPage(
      header: _header(context, p),
      groups: [
        AppSettingsGroup(
          title: 'account'.tr,
          icon: Icons.account_circle_rounded,
          children: [
            const CertVerifyEntryTile(),
            AppSettingsTile(icon: Icons.manage_accounts_rounded, color: c.primary, label: 'update_account'.tr, onTap: _edit),
            AppSettingsTile(
              icon: Icons.lock_reset_rounded,
              color: c.accent2,
              label: 'change_password'.tr,
              onTap: () => _push(const ChangePasswordScreen()),
            ),
            const CalendarEntryTile(),
            const ChatEntryTile(),
          ],
        ),
        AppSettingsGroup(
          title: 'settings'.tr,
          icon: Icons.settings_rounded,
          children: [
            const AppLanguageTile(),
            const DisplaySettingsTile(),
            if (GetAppTile.available) const GetAppTile(), // web: the store / installer for this device
            const AppAssistantOpenTile(),
            const AppAssistantBubbleTile(),
            AppSettingsTile(
              icon: Icons.dark_mode_rounded,
              color: c.textDark,
              label: 'dark_mode'.tr,
              trailing: AppSwitch(value: p.darkMode, onChanged: (b) async => await p.changeMode(b), semanticLabel: 'dark_mode'.tr),
            ),
            AppSettingsTile(
              icon: Icons.support_agent_rounded,
              color: c.primary,
              label: 'complaints_and_support'.tr,
              onTap: () => _push(const ComplaintsHubPage()), // D-086: New complaint + My complaints
            ),
          ],
        ),
        legalSettingsGroup(context), // privacy policy · terms of service (D-308)
        AppSettingsGroup(
          title: 'exit'.tr,
          icon: DirIcons.exitToApp,
          danger: true,
          children: [
            AppSettingsTile(
              icon: DirIcons.logout,
              color: c.danger,
              label: 'logout'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context);
                if (ok == true && context.mounted) await context.read<ProfileProvider>().logout(context);
              },
            ),
            AppSettingsTile(
              icon: Icons.delete_forever_rounded,
              color: c.danger,
              label: 'delete_account_title'.tr,
              onTap: () async {
                final ok = await Helpers.confirmDialog(context, title: 'are_you_sure_to_delete_account'.tr, confirm: 'delete'.tr);
                if (ok != true || !context.mounted) return;
                final re = await askReauth(context); // current password (+ two-step code), S9
                if (re == null || !context.mounted) return;
                final p = context.read<ProfileProvider>();
                final after = await p.deleteAccount(context, password: re.password, mfaCode: re.mfaCode);
                if (after == null) {
                  Helpers.showMessage(p.errorMessage ?? 'generic_error'.tr, isError: true);
                  return;
                }
                Helpers.showMessage('your_account_will_deleted_successfully_through_14_days'.tr);
              },
            ),
          ],
        ),
      ],
    );
  }
}

