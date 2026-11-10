// lib/design/app_settings.dart — grouped settings for every More / Settings / Profile page (Track B.1).
//
//   AppSettingsPage(header:, groups: [...], footer:)
//       the page body: SafeArea + scroll + ContentBox in the kit's 8·16·24·32 rhythm, and a search field at the
//       top once the page holds more than `searchThreshold` (8) tiles — typing filters the rows by label /
//       subtitle / keywords, a group with no match disappears, "nothing matches" when nothing is left.
//   AppSettingsGroup(title:, icon:, children:, danger:)
//       a titled card of rows (hairline dividers, theme radius, soft shadow); `danger` tints it for sign-out.
//   AppSettingsTile(icon:, label:, subtitle:, color:, trailing:, onTap:, badge:, featureKey:, keywords:)
//       one row: tinted icon well (bg = color @ tint), label, optional subtitle, a count pill, a trailing widget
//       or the direction-aware chevron. `featureKey` hides it with the kill switch (ParentComponent).
//   AppSettingsHeader(name:, role:, email:, username:, imageUrl:, onEdit:)
//       the profile hero over plain values (kill switch `profile.header`; `appRoleLabel` names the role).
//   AppSettingsSearchable
//       implement it on a custom row (CalendarEntryTile does) so the search can see it; a row that is not
//       searchable is kept while the query is empty and left out while one is typed.
//
// The older SettingsGroup / SettingsTile / ProfileHeader (features/shared/profile/components, profile_screen)
// keep working; a More page adopts this file by swapping the names (`color:` instead of iconBg + iconColor, the
// header takes values instead of the provider). Layout test: test/ui/app_settings_layout_test.dart.
library;

import 'package:flutter_education_app/design/app_mesh.dart';
import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../utils/widget/app_network_image.dart';
import '../utils/widget/parent_component.dart';
import 'app_responsive.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

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

  /// Icon colour; the well is this colour at a tint. Default: primary.
  final Color? color;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A count pill before the chevron (null / 0 = none).
  final int? badge;

  /// Kill-switch id (AppConfig.disableList) — the row disappears when the feature is off.
  final String? featureKey;

  /// Extra words the search matches (synonyms, the other language).
  final String? keywords;

  @override
  String get searchText => '$label ${subtitle ?? ''} ${keywords ?? ''}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = color ?? c.primary;
    final n = badge ?? 0;
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: col.withValues(alpha: c.isDark ? 0.20 : 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: col.withValues(alpha: 0.12)),
            ),
            // dark: the icon lifted toward white — a primary-coloured glyph on a dark card failed WCAG contrast
            child: Icon(icon, size: 19, color: c.isDark ? Color.lerp(col, Colors.white, 0.55) : col),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: c.label.copyWith(color: c.textDark, fontSize: 14.5, fontWeight: FontWeight.w600)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.caption.copyWith(fontSize: 12)),
            ]),
          ),
          if (n > 0) ...[
            const SizedBox(width: 8),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.danger, borderRadius: BorderRadius.circular(11)),
              child: Text(n > 99 ? '99+' : '$n',
                  style: TextStyle(color: c.onHero, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.1)),
            ),
          ],
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ] else if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded, // matchTextDirection: Flutter mirrors it in RTL
              color: c.textLight,
              size: 22,
            ),
          ],
        ]),
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
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;

  /// Tints the card (sign out, delete account).
  final bool danger;

  AppSettingsGroup copyWith({List<Widget>? children}) =>
      AppSettingsGroup(key: key, title: title, subtitle: subtitle, icon: icon, danger: danger, children: children ?? this.children);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, color: c.divider.withValues(alpha: 0.6), indent: 64, endIndent: 16));
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 0, 4, 10),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: (danger ? c.danger : c.primary).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: danger ? c.danger : (c.isDark ? Color.lerp(c.primary, Colors.white, 0.55) : c.primary)),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: c.h3.copyWith(color: c.textMedium, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: c.caption.copyWith(fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: danger ? c.danger.withValues(alpha: c.isDark ? 0.16 : 0.10) : c.cardBg,
            borderRadius: BorderRadius.circular(c.radiusLarge),
            border: Border.all(color: c.divider.withValues(alpha: 0.7)),
            boxShadow: c.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: rows)),
          ),
        ),
      ],
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final avatar = Container(
      width: 104,
      height: 104,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [c.onHero, c.accent2.withValues(alpha: 0.9)]),
        boxShadow: [BoxShadow(color: c.heroShade.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipOval(
        child: imageUrl.isNotEmpty
            ? AppNetworkImage(url: imageUrl, heroTag: heroTag ?? 'profile-user-$name')
            : Container(
                color: c.onHero,
                alignment: Alignment.center,
                child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 40, fontWeight: FontWeight.w800, color: c.primary)),
              ),
      ),
    );
    Widget glass(IconData icon, String text, {bool ltr = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: c.heroGlass,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.heroGlassBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: c.onHero),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltr ? TextDirection.ltr : null,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, fontWeight: FontWeight.w600, color: c.onHero)),
            ),
          ]),
        );
    Widget bubble(double size, double a) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.onHero.withValues(alpha: a)),
        );
    return ParentComponent(
      featureKey: 'profile.header',
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(c.radiusLarge + 4),
          color: c.primary,
          boxShadow: [BoxShadow(color: c.primary.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 12))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          const Positioned.fill(child: RepaintBoundary(child: AppMeshSurface(seed: 9))),
          PositionedDirectional(top: -40, end: -30, child: bubble(150, 0.08)),
          PositionedDirectional(bottom: -50, start: -20, child: bubble(130, 0.06)),
          SizedBox(
            width: double.infinity, // a Stack child sizes to itself: without this the block sat left of the card's centre
            child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
            child: Column(children: [
              GestureDetector(
                onTap: onEdit,
                child: Stack(clipBehavior: Clip.none, children: [
                  avatar,
                  if (onEdit != null)
                    PositionedDirectional(
                      bottom: 2,
                      end: 2,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                            color: c.accent2, shape: BoxShape.circle, border: Border.all(color: c.onHero, width: 2.5)),
                        child: Icon(Icons.photo_camera_rounded, size: 15, color: c.onHero),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 21, fontWeight: FontWeight.w800, color: c.onHero)),
              const SizedBox(height: 8),
              Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
                if (role.isNotEmpty) glass(Icons.verified_user_rounded, appRoleLabel(role)),
                if (email.isNotEmpty) glass(Icons.alternate_email_rounded, email, ltr: true),
                if (username.isNotEmpty)
                  ParentComponent(featureKey: 'auth.username', child: glass(Icons.person_pin_rounded, '@$username', ltr: true)),
              ]),
            ]),
          ),
          ),
        ]),
      ),
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
    this.gutter = 20,
  });

  final Widget? header;
  final List<AppSettingsGroup> groups;
  final Widget? footer;

  /// A search field appears once the groups hold more tiles than this.
  final int searchThreshold;
  final double gutter;

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
    final side = EdgeInsets.symmetric(horizontal: widget.gutter);
    return SafeArea(
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _query,
        builder: (context, q, _) {
          final groups = _filtered(searchable ? q.text : '');
          final searching = searchable && q.text.trim().isNotEmpty;
          return SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ContentBox(
              child: Column(children: [
                const SizedBox(height: 24),
                if (widget.header != null && !searching) ...[
                  Padding(padding: side, child: widget.header),
                  const SizedBox(height: 24),
                ],
                if (searchable) ...[
                  Padding(
                    padding: side,
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'settings_search'.tr,
                        prefixIcon: Icon(Icons.search_rounded, color: c.textLight),
                        suffixIcon: q.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'clear'.tr,
                                icon: Icon(Icons.close_rounded, color: c.textLight, size: 20),
                                onPressed: _query.clear,
                              ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(children: [
                      Icon(Icons.search_off_rounded, size: 40, color: c.textLight),
                      const SizedBox(height: 10),
                      Text('settings_no_match'.tr, textAlign: TextAlign.center, style: c.body.copyWith(color: c.textMedium)),
                    ]),
                  ),
                for (var i = 0; i < groups.length; i++) ...[
                  Padding(padding: side, child: groups[i]),
                  SizedBox(height: i == groups.length - 1 ? 24 : 20),
                ],
                if (widget.footer != null && !searching) Padding(padding: side, child: widget.footer),
                const SizedBox(height: 24),
              ]),
            ),
          );
        },
      ),
    );
  }
}
