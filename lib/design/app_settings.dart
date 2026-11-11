// lib/design/app_settings.dart — grouped settings for every More / Settings / Profile page (Track B.1, D-612).
//
//   AppSettingsPage(header:, groups: [...], footer:)
//       the page body: SafeArea + scroll + ContentBox in the editorial rhythm (a group heading has more room above
//       it than below), and a search field at the top once the page holds more than `searchThreshold` (8) tiles —
//       typing filters the rows by label / subtitle / keywords, a group with no match disappears, "nothing matches"
//       when nothing is left.
//   AppSettingsGroup(title:, icon:, children:, danger:)
//       an editorial group heading (the section face in ink, an optional quiet glyph) over a paper card of rows
//       (the white card, one soft shadow, hairline dividers, D-632); `danger` tints the card for sign-out.
//   AppSettingsTile(icon:, label:, subtitle:, color:, trailing:, onTap:, badge:, featureKey:, keywords:)
//       one 48 px (or taller) row: a faint icon well in the row's colour, label, optional subtitle, a count pill, a
//       trailing widget or the direction-aware chevron. `featureKey` hides it with the kill switch (ParentComponent).
//   AppSettingsHeader(name:, role:, email:, username:, imageUrl:, onEdit:)
//       the profile hero: the page's one tinted block (peach) over plain values (kill switch `profile.header`;
//       `appRoleLabel` names the role).
//   AppSettingsSearchable
//       implement it on a custom row (CalendarEntryTile does) so the search can see it; a row that is not
//       searchable is kept while the query is empty and left out while one is typed.
//
// The older SettingsGroup / SettingsTile / ProfileHeader (features/shared/profile/components, profile_screen)
// keep working; a More page adopts this file by swapping the names (`color:` instead of iconBg + iconColor, the
// header takes values instead of the provider). Layout test: test/ui/app_settings_layout_test.dart.
library;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../utils/widget/app_network_image.dart';
import '../utils/widget/parent_component.dart';
import 'app_blocks.dart';
import 'app_responsive.dart';
import 'app_tokens.dart';

/// A row the settings search can read.
abstract class AppSettingsSearchable {
  String get searchText;
}

/// Role id (server) → translated label; an unknown id is shown as is.
String appRoleLabel(String role) =>
    const {
      'student': 'role_student',
      'teacher': 'role_teacher',
      'parent': 'role_parent',
      'admin': 'role_admin',
      'super-admin': 'role_super_admin',
      'super_admin': 'role_super_admin',
      'org-admin': 'role_org_admin',
      'org_admin': 'role_org_admin',
      'org-staff': 'role_org_staff',
      'org_staff': 'role_org_staff',
      'developer': 'role_developer',
    }[role]?.tr ??
    role;

// ─────────────────────────────────────────────────────────────────────────────
// Tile
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsTile extends StatelessWidget implements AppSettingsSearchable {
  const AppSettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.color,
    this.trailing,
    this.onTap,
    this.badge,
    this.featureKey,
    this.keywords,
  });

  final IconData icon;
  final String label;
  final String? subtitle;

  /// Icon colour; the well is this colour at a faint tint. Default: primary.
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A count pill before the chevron (null / 0 = none).
  final int? badge;

  /// Kill-switch id (AppConfig.disableList) — the row disappears when the feature is off.
  final String? featureKey;

  /// Extra words the search matches (synonyms, the other language).
  final String? keywords;

  /// The icon well's side.
  static const double well = AppIconSize.xl + AppSpace.xxs;

  /// Where a row's text starts (the group's dividers line up with it).
  static const double textStart = AppSpace.md + well + AppSpace.sm;

  @override
  String get searchText => '$label ${subtitle ?? ''} ${keywords ?? ''}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final n = badge ?? 0;
    final sub = subtitle;
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.xs),
          child: Row(children: [
            Container(
              width: well,
              height: well,
              decoration: BoxDecoration(
                color: col.withValues(alpha: c.isDark ? 0.18 : 0.10),
                borderRadius: AppRadius.chipAll,
              ),
              // the glyph darkened (lifted in dark mode) until it reads on the card
              child: Icon(icon, size: AppIconSize.md, color: c.blockAccentInk(col, c.cardBg)),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
                if (sub != null && sub.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs / 2),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
                ],
              ]),
            ),
            if (n > 0) ...[
              const SizedBox(width: AppSpace.xs),
              Container(
                constraints: const BoxConstraints(minWidth: AppIconSize.md, minHeight: AppIconSize.md),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(n > 99 ? '99+' : '$n',
                    maxLines: 1, style: AppType.overline(context).copyWith(color: c.onHero, height: 1.2, letterSpacing: 0)),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: AppSpace.sm),
              trailing!,
            ] else if (onTap != null) ...[
              const SizedBox(width: AppSpace.xs),
              Icon(
                Icons.chevron_right_rounded, // matchTextDirection: Flutter mirrors it in RTL
                color: c.textLight,
                size: AppIconSize.lg,
              ),
            ],
          ]),
        ),
      ),
    );
    return featureKey == null ? row : ParentComponent(featureKey: featureKey, child: row);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsGroup extends StatelessWidget {
  const AppSettingsGroup({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.subtitle,
    this.danger = false,
    this.spaceAbove = true,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  /// Tints the card (sign out, delete account).
  final bool danger;

  /// The editorial 32 above the heading; false for a group that starts its surface.
  final bool spaceAbove;

  AppSettingsGroup copyWith({List<Widget>? children}) => AppSettingsGroup(
      key: key, title: title, subtitle: subtitle, icon: icon, danger: danger, spaceAbove: spaceAbove, children: children ?? this.children);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sub = subtitle;
    final headInk = danger ? c.blockAccentInk(c.danger, c.background) : c.textDark;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(
          height: AppBorder.hairline,
          thickness: AppBorder.hairline,
          color: c.divider,
          indent: AppSettingsTile.textStart,
          endIndent: AppSpace.md,
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsetsDirectional.fromSTEB(AppSpace.xxs, spaceAbove ? AppSpace.sectionHead.top : 0, AppSpace.xxs, AppSpace.sectionHead.bottom),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xxs / 2),
              child: Icon(icon, size: AppIconSize.md, color: danger ? headInk : c.textMedium),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Semantics(
                header: true,
                child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context).copyWith(color: headInk)),
              ),
              if (sub != null && sub.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs / 2),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
            ]),
          ),
        ]),
      ),
      // the white card on the tinted page (D-632); the sign-out group keeps its flat danger tint
      _lifted(danger, Material(
        color: danger ? c.dangerTint : c.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: danger
              ? BorderSide(color: c.danger.withValues(alpha: 0.35), width: AppBorder.hairline)
              : AppShadow.cardEdge(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpace.xxs), child: Column(children: rows)),
      )),
    ]);
  }

  static Widget _lifted(bool danger, Widget card) => danger ? card : AppLift(child: card);
}

// ─────────────────────────────────────────────────────────────────────────────
// Header (profile hero)
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsHeader extends StatelessWidget {
  const AppSettingsHeader({
    super.key,
    required this.name,
    this.role = '',
    this.email = '',
    this.imageUrl = '',
    this.onEdit,
    this.heroTag,
    this.username = '',
  });

  final String name, role, email, imageUrl;

  /// The @username without the "@" ('' = none); hidden by the kill switch `auth.username`.
  final String username;
  final VoidCallback? onEdit;
  final String? heroTag;

  /// The avatar's side and its paper ring.
  static const double avatar = 96;
  static const double ring = AppSpace.xxs;

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: 'profile.header',
        child: AppBlock(
          tone: AppBlockTone.peach,
          hero: true,
          child: Builder(builder: _body),
        ),
      );

  Widget _body(BuildContext context) {
    final c = context.colors;
    final b = AppBlock.colorsOf(context);
    final avatarBox = Container(
      width: avatar,
      height: avatar,
      padding: const EdgeInsets.all(ring),
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.cardBg),
      child: ClipOval(
        child: imageUrl.isNotEmpty
            ? AppNetworkImage(url: imageUrl, heroTag: heroTag ?? 'profile-user-$name')
            : ColoredBox(
                color: b.surface,
                child: Center(
                  child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                      style: AppType.display(context).copyWith(color: b.accentInk(c.primary))),
                ),
              ),
      ),
    );
    Widget chip(IconData icon, String text, {bool ltr = false}) => Container(
          constraints: const BoxConstraints(minHeight: AppIconSize.xl),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: c.divider, width: AppBorder.hairline),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: AppIconSize.sm, color: c.textMedium),
            const SizedBox(width: AppSpace.xs),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltr ? TextDirection.ltr : null,
                  style: AppType.label(context).copyWith(color: c.textDark)),
            ),
          ]),
        );
    return SizedBox(
      width: double.infinity,
      child: Column(children: [
        Semantics(
          button: onEdit != null,
          label: onEdit == null ? null : 'update_account'.tr,
          child: GestureDetector(
            onTap: onEdit,
            child: Stack(clipBehavior: Clip.none, children: [
              avatarBox,
              if (onEdit != null)
                PositionedDirectional(
                  bottom: 0,
                  end: 0,
                  child: Container(
                    width: AppIconSize.xl,
                    height: AppIconSize.xl,
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.cardBg, width: AppBorder.focus),
                    ),
                    child: Icon(Icons.photo_camera_rounded, size: AppIconSize.sm, color: c.onHero),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Text(name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.headline(context).copyWith(color: b.ink)),
        const SizedBox(height: AppSpace.sm),
        Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (role.isNotEmpty) chip(Icons.verified_user_rounded, appRoleLabel(role)),
          if (email.isNotEmpty) chip(Icons.alternate_email_rounded, email, ltr: true),
          if (username.isNotEmpty)
            ParentComponent(featureKey: 'auth.username', child: chip(Icons.person_pin_rounded, '@$username', ltr: true)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({
    super.key,
    this.header,
    required this.groups,
    this.footer,
    this.searchThreshold = 8,
    this.gutter,
  });

  final Widget? header;
  final List<AppSettingsGroup> groups;
  final Widget? footer;

  /// A search field appears once the groups hold more tiles than this.
  final int searchThreshold;

  /// The side gutter; null follows the page gutter (16 on phones, 24 above).
  final double? gutter;

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  int get _tileCount => widget.groups.fold(0, (n, g) => n + g.children.length);

  /// Groups that match [q] (every group when the query is empty).
  List<AppSettingsGroup> _filtered(String q) {
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return widget.groups;
    final out = <AppSettingsGroup>[];
    for (final g in widget.groups) {
      final kept = [
        for (final w in g.children)
          if (w is AppSettingsSearchable && (w as AppSettingsSearchable).searchText.toLowerCase().contains(needle)) w,
      ];
      if (kept.isNotEmpty) out.add(g.copyWith(children: kept));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final searchable = _tileCount > widget.searchThreshold;
    final side = EdgeInsets.symmetric(horizontal: widget.gutter ?? AppSpace.gutter(MediaQuery.sizeOf(context).width));
    return SafeArea(
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _query,
        builder: (context, q, _) {
          final groups = _filtered(searchable ? q.text : '');
          final searching = searchable && q.text.trim().isNotEmpty;
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ContentBox(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: AppSpace.lg),
                if (widget.header != null && !searching) Padding(padding: side, child: widget.header),
                if (searchable) ...[
                  if (widget.header != null && !searching) const SizedBox(height: AppSpace.lg),
                  Padding(
                    padding: side,
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'settings_search'.tr,
                        prefixIcon: Icon(Icons.search_rounded, size: AppIconSize.md, color: c.textLight),
                        suffixIcon: q.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'clear'.tr,
                                constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                                icon: Icon(Icons.close_rounded, color: c.textLight, size: AppIconSize.md),
                                onPressed: _query.clear,
                              ),
                      ),
                    ),
                  ),
                ],
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                    child: Column(children: [
                      Icon(Icons.search_off_rounded, size: AppIconSize.hero, color: c.textLight),
                      const SizedBox(height: AppSpace.sm),
                      Text('settings_no_match'.tr, textAlign: TextAlign.center, style: AppType.body(context)),
                    ]),
                  ),
                // every group brings its own 32 above its heading (the editorial rhythm): nothing between them
                for (final g in groups) Padding(padding: side, child: g),
                if (widget.footer != null && !searching) ...[
                  const SizedBox(height: AppSpace.lg),
                  Padding(padding: side, child: widget.footer),
                ],
                const SizedBox(height: AppSpace.xl),
              ]),
            ),
          );
        },
      ),
    );
  }
}
