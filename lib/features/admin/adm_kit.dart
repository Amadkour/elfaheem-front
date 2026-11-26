// lib/features/admin/adm_kit.dart
//
// The admin pieces of the redesign (group A1, the reference's `Adm*` screens). Admin pages use the Super Admin frame
// (`sup/sup_kit.dart`: SupPage, SupCard, SupTabStack) with the signed-in person's role accent, so both admin areas
// look alike; this file adds what the admin screens draw beside it:
//
//   admRole(context)                    the role accent of the signed-in admin (admin, or super admin's gold)
//   AdmQueueRow(icon:, tone:, title:, count:, onTap:)   one line of "What waits for your decision" (the
//                                       reference's `.k-tile` with the count and a quiet "Review" button)
//   AdmHeroPanel(title:, child:)        a glass card on the hero ("Activity and health", the jobs list)
//   AdmGlassFigure(value:, label:)      a small glass figure inside an AdmHeroPanel
//   AdmServiceTile(service)             one tile of a hub's service grid (icon, count, name, one line)
//   AdmServiceGrid(services:, title:)   the hub card: its name, how many services, a search, the tiles
//   AdmField(label:, value:)            a label over a value (detail pages)
//
// Motion: admin pages use only M9 (press), M10 (figures), M13 (tabs) and M14 (sheets); nothing here loops.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppPressScale;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';

import '../auth/auth_provider.dart' show MyAuthProvider;
import 'admin_recents.dart';
import 'admin_services_hub.dart' show AdminService;

/// The role accent of the signed-in admin: a super admin or developer gets the super admin's accent, anyone else
/// (admin, an organization admin looking in) the admin accent. No auth provider above (a preview): admin.
AppRoleAccent admRole(BuildContext context) {
  String? role;
  try {
    role = Provider.of<MyAuthProvider>(context, listen: false).currentUser?.role;
  } catch (_) {}
  final r = appRoleAccentFor(role);
  return r == AppRoleAccent.superAdmin ? r! : AppRoleAccent.admin;
}

/// One line of the decision queue: a tinted glyph box, the title and one line, an optional tag ("Urgent", "Older
/// than 3 days"), the count, and a quiet "Review" button when [review] is on. The whole row opens [onTap].
class AdmQueueRow extends StatelessWidget {
  const AdmQueueRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.count,
    this.tone,
    this.tag,
    this.tagTone = AppTone.danger,
    this.onTap,
    this.review = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final int? count;
  final KitTone? tone;
  final String? tag;
  final AppTone tagTone;
  final VoidCallback? onTap;

  /// Draw the "Review" button at the end (a one-column list); off in a two-column grid.
  final bool review;

  @override
  Widget build(BuildContext context) {
    final n = count ?? 0;
    final sub = subtitle;
    final t = tag;
    return Semantics(
      label: [title, if (n > 0) '$n', ?sub, ?t].join('. '),
      excludeSemantics: true,
      button: onTap != null,
      onTap: onTap,
      child: AppTile(
        icon: icon,
        tone: tone,
        title: title,
        subtitle: [?sub, if (t != null && (sub == null || sub.isEmpty)) t].join(),
        onTap: onTap,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (t != null && sub != null && sub.isNotEmpty) ...[
            Flexible(child: AppStatusBadge(label: t, tone: tagTone, dense: true)),
            const SizedBox(width: AppSpace.sm),
          ],
          if (n > 0) Text(appCompactNumber(n), style: AppType.figure(context)),
          if (review && onTap != null) ...[
            const SizedBox(width: AppSpace.sm),
            AppButton.secondary(label: 'a1_review'.tr, size: AppButtonSize.sm, onPressed: onTap),
          ],
        ]),
      ),
    );
  }
}

/// A glass card on a hero: a small heading with an optional live dot, then [child].
class AdmHeroPanel extends StatelessWidget {
  const AdmHeroPanel({super.key, required this.title, required this.child, this.dot = false, this.trailing});

  final String title;
  final Widget child;
  final bool dot;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.heroGlass,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.heroGlassBorder, width: AppBorder.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (dot) ...[
            Container(
              width: AppSpace.xs,
              height: AppSpace.xs,
              decoration: BoxDecoration(color: c.kit.live.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: c.onHero, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ]),
        const SizedBox(height: AppSpace.sm),
        child,
      ]),
    );
  }
}

/// A small figure inside an [AdmHeroPanel]: the value, the label under it; [warn] draws the value in the live tone.
class AdmGlassFigure extends StatelessWidget {
  const AdmGlassFigure({super.key, required this.value, required this.label, this.onTap, this.warn = false});

  final String value, label;
  final VoidCallback? onTap;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.tile);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      button: onTap != null,
      onTap: onTap,
      child: Material(
        color: c.heroGlass,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.sm),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.figure(context).copyWith(color: warn ? c.kit.live.color : c.onHero)),
              const SizedBox(height: AppSpace.xxs),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context).copyWith(color: c.onHeroMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Figures two per row (a panel's grid).
class AdmFigureGrid extends StatelessWidget {
  const AdmFigureGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < children.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpace.xs),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: children[i]),
              const SizedBox(width: AppSpace.xs),
              Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
            ]),
          ),
        ],
      ]);
}

/// The colour of a service: the kit tone that matches the service's palette end (warm, live, ok, accent or role).
KitTone admServiceTone(BuildContext context, AdminService s) {
  final kit = context.colors.kit;
  final tones = [
    AppAreaScope.of(context).tone,
    kit.accent(AppAccent.sky),
    kit.ok,
    kit.warmTone,
    kit.accent(AppAccent.grape),
    kit.live,
  ];
  return tones[s.labelKey.hashCode.abs() % tones.length];
}

/// Opens a service and remembers it for "Recently opened".
void admOpenService(AdminService s) {
  AdminRecents.instance.record(s.labelKey);
  s.onTap();
}

/// One tile of a hub: the glyph box at the reading start, the count at the end, the name and one line under them.
class AdmServiceTile extends StatelessWidget {
  const AdmServiceTile(this.service, {super.key});

  final AdminService service;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = service;
    final n = s.badge ?? 0;
    final radius = BorderRadius.circular(AppRadius.tile);
    Widget tile = Semantics(
      button: true,
      container: true,
      label: '${s.labelText}. ${s.descText}${n > 0 ? '. $n' : ''}',
      excludeSemantics: true,
      onTap: () => admOpenService(s),
      child: AppPressScale(
        enabled: true,
        child: Material(
          color: c.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: c.kit.line, width: AppBorder.strong),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => admOpenService(s),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppIconBox(icon: s.icon, tone: admServiceTone(context, s)),
                  const Spacer(),
                  if (n > 0) AppCountBadge(count: n),
                ]),
                const SizedBox(height: AppSpace.sm),
                Text(s.labelText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
                const SizedBox(height: AppSpace.xxs),
                Text(s.descText, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ]),
            ),
          ),
        ),
      ),
    );
    final key = s.featureKey;
    if (key != null) tile = ParentComponent(featureKey: key, child: tile);
    return tile;
  }
}

/// The services whose name or description holds every word of [q].
List<AdminService> admFilterServices(List<AdminService> items, String q) {
  final words = q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return items;
  return [
    for (final s in items)
      if (words.every('${s.labelText} ${s.descText}'.toLowerCase().contains)) s,
  ];
}

/// A hub's service card: "<title>" with "N services" at the end, a search over the names and descriptions, then
/// the tiles in a grid (1 column under 440 px, up to 4).
class AdmServiceGrid extends StatefulWidget {
  const AdmServiceGrid({super.key, required this.title, required this.services, this.searchHint});

  final String title;
  final List<AdminService> services;
  final String? searchHint;

  static int columnsFor(double width) => width >= 900 ? 4 : (width >= 640 ? 3 : (width >= 400 ? 2 : 1));

  @override
  State<AdmServiceGrid> createState() => _AdmServiceGridState();
}

class _AdmServiceGridState extends State<AdmServiceGrid> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final s in widget.services)
        if (s.featureKey == null || !AppConfig.disableList.contains(s.featureKey)) s,
    ];
    final items = admFilterServices(all, _q);
    return SupCardLike(
      title: widget.title,
      trailing: Text(
        countText(all.length, ar1: 'خدمة وحدة', ar2: 'خدمتين', arFew: '{n} خدمات', arMany: '{n} خدمة', en1: '1 service', en: '{n} services'),
        style: AppType.meta(context),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppSearchField(hint: widget.searchHint ?? 'a1_hub_search'.tr.replaceAll('{x}', widget.title), onChanged: (v) => setState(() => _q = v)),
        const SizedBox(height: AppSpace.md),
        if (items.isEmpty)
          AppEmpty(icon: Icons.search_off_rounded, title: 'a1_no_service'.tr, message: 'a1_try_other_word'.tr)
        else
          LayoutBuilder(builder: (context, box) {
            final cols = AdmServiceGrid.columnsFor(box.maxWidth);
            final rows = (items.length / cols).ceil();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: AppSpace.sm),
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < cols; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpace.sm),
                      Expanded(child: r * cols + i < items.length ? AdmServiceTile(items[r * cols + i]) : const SizedBox.shrink()),
                    ],
                  ]),
                ),
              ],
            ]);
          }),
      ]),
    );
  }
}

/// A plain card with a section title and something at its end (the Sup card without the glyph box).
class SupCardLike extends StatelessWidget {
  const SupCardLike({super.key, required this.title, required this.child, this.trailing, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: AppType.section(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(subtitle!, style: AppType.meta(context)),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: AppSpace.sm), trailing!],
          ]),
          const SizedBox(height: AppSpace.md),
          child,
        ]),
      );
}

/// A label over its value (the detail pages' facts).
class AdmField extends StatelessWidget {
  const AdmField({super.key, required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppType.meta(context)),
        const SizedBox(height: AppSpace.xxs),
        Text(value.isEmpty ? '—' : value, style: AppType.row(context), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]);
}
