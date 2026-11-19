// lib/features/org/workspace/ws_organization.dart — the admin workspace's Organization tab (D-1180).
//
// Profile = me; Organization = the organization; Management = its daily work. This tab is the organization:
//   OrgIdentityCard   its logo (or its initial on its brand colour), name, type and status, the about text and the
//                     official contact details, read-only, with Edit details (the org form) — prompts for a missing
//                     logo or about text
//   the groups        Joining & access · Structure · Policies · Records & billing (org_settings_groups.dart)
//   the danger zone   folded to one row until opened (OrgDangerFold)
// Only an organization admin gets the tab (wsShellItems); every row checks its own right. No request of its own: the
// card reads OrgSession.current. OrgIdentityCard is plain values (test/org/ws_organization_test.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_contrast.dart' show contrastRatio;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_common.dart' show orgTypeLabels;
import '../org_dashboard_settings.dart' show showOrgForm;
import '../org_providers.dart';
import '../org_settings_groups.dart';

/// One official detail on the card: its icon and its text (empty ones are left out by the caller).
typedef OrgDetail = (IconData, String);

/// The organization at a glance, read-only, with one way to change it.
class OrgIdentityCard extends StatelessWidget {
  const OrgIdentityCard({
    super.key,
    required this.name,
    this.type = '',
    this.status = '',
    this.logoUrl = '',
    this.color,
    this.about = '',
    this.details = const [],
    this.onEdit,
  });

  final String name, type, status, logoUrl, about;

  /// The organization's own brand colour (its initial sits on it when there is no logo); null = the theme's primary.
  final Color? color;
  final List<OrgDetail> details;

  /// Edit details; null = this person may not edit (the card stays read-only).
  final VoidCallback? onEdit;

  /// The logo tile's side.
  static const double logo = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brand = color ?? c.primary;
    final meta = [if (type.isNotEmpty) type, if (status.isNotEmpty) status].join(' · ');
    final mark = Container(
      width: logo,
      height: logo,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: brand, borderRadius: AppRadius.cardAll),
      child: logoUrl.isNotEmpty
          ? Image.network(logoUrl, width: logo, height: logo, fit: BoxFit.cover, errorBuilder: (_, _, _) => _initial(context, brand))
          : _initial(context, brand),
    );
    return Container(
      key: const ValueKey('org.identity'),
      padding: AppSpace.card,
      decoration: BoxDecoration(color: c.cardBg, borderRadius: AppRadius.cardAll, border: Border.all(color: c.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          mark,
          AppSpace.gapMd,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        if (about.isNotEmpty)
          Text(about, maxLines: 4, overflow: TextOverflow.ellipsis, style: AppType.body(context))
        else if (onEdit != null)
          _Prompt(
              icon: Icons.notes_rounded,
              text: t('أضف نبذة قصيرة تعرّف بالمؤسسة', 'Add a short description of the organization'),
              onTap: onEdit!),
        if (logoUrl.isEmpty && onEdit != null)
          _Prompt(icon: Icons.add_photo_alternate_rounded, text: t('أضف شعار المؤسسة', 'Add the organization logo'), onTap: onEdit!),
        if (details.isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          for (final d in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(d.$1, size: AppIconSize.sm, color: c.textMedium),
                AppSpace.gapSm,
                Expanded(child: Text(d.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context))),
              ]),
            ),
        ],
        if (onEdit != null) ...[
          const SizedBox(height: AppSpace.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppButton.secondary(
              key: const ValueKey('org.identity.edit'),
              label: t('تعديل البيانات', 'Edit details'),
              icon: Icons.edit_rounded,
              onPressed: onEdit,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _initial(BuildContext context, Color brand) {
    final c = context.colors;
    return Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: AppType.section(context)
            .copyWith(color: contrastRatio(c.onHero, brand) >= contrastRatio(c.textDark, brand) ? c.onHero : c.textDark));
  }
}

/// A gentle "add the missing part" line on the card.
class _Prompt extends StatelessWidget {
  const _Prompt({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.controlAll,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Row(children: [
          Icon(icon, size: AppIconSize.md, color: c.primary),
          AppSpace.gapSm,
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.primary))),
        ]),
      ),
    );
  }
}

/// `#1F6F5C` → the colour, or null.
Color? orgBrandColor(Object? hex) {
  final h = '${hex ?? ''}'.trim();
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(h)) return null;
  return Color(int.parse('FF${h.substring(1)}', radix: 16));
}

/// The status of an organization as its admin reads it (empty when approved: nothing to say).
String orgStatusLabel(Object? status) => switch ('${status ?? ''}') {
      'pending' => t('بانتظار اعتماد المنصة', 'Waiting for platform approval'),
      'rejected' => t('مرفوضة', 'Rejected'),
      'suspended' => t('موقوفة', 'Suspended'),
      _ => '',
    };

/// The organization's official details, in reading order, the empty ones left out.
List<OrgDetail> orgDetailsOf(Map<String, dynamic>? org) {
  String v(String k) => '${org?[k] ?? ''}'.trim();
  return [
    if (v('contact_email').isNotEmpty) (Icons.mail_outline_rounded, v('contact_email')),
    if (v('contact_phone').isNotEmpty) (Icons.phone_outlined, v('contact_phone')),
    if (v('website').isNotEmpty) (Icons.language_rounded, v('website')),
    if (v('address').isNotEmpty) (Icons.place_outlined, v('address')),
    if (v('license_no').isNotEmpty) (Icons.verified_outlined, '${t('رقم القرار / الترخيص', 'Licence no.')} ${v('license_no')}'),
  ];
}

class WsOrganizationTab extends StatelessWidget {
  const WsOrganizationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<OrgSession>();
    final org = s.current;
    return AppSettingsPage(
      gutter: AppSpace.md,
      searchThreshold: 40,
      columns: true,
      header: OrgIdentityCard(
        name: s.name,
        type: orgTypeLabels()['${org?['type'] ?? ''}'] ?? '',
        status: orgStatusLabel(org?['status']),
        logoUrl: '${org?['logo_url'] ?? ''}',
        color: orgBrandColor(org?['color']),
        about: '${org?['description'] ?? ''}'.trim(),
        details: orgDetailsOf(org),
        onEdit: s.isOrgAdmin || s.can('organization', 'update') ? () => showOrgForm(context, edit: s.current) : null,
      ),
      groups: orgOrganizationGroups(context, s),
      footer: const OrgDangerFold(),
    );
  }
}
