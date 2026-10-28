// ─────────────────────────────────────────────────────────────────────────────
// features/shared/about/about_and_terms_screen.dart  (v3 – premium, admin-driven)
//
// About Us + Terms & Conditions. Everything comes from what the admin edits in the
// dashboard's "App content" page (see admin_content_page.dart):
//   About  : hero (logo · name · tagline · version) · stats · mission · features · team · contacts
//            · "About this app" card (installed version, update available + release notes)
//   Terms  : hero (version · last update) · search · expand / collapse all · numbered sections
//
// Premium touches: gradient hero, stat tiles, team cards with tap-to-zoom photos,
// tap-to-open / long-press-to-copy contacts, update badge, searchable terms.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton, AppRefresh;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../student/courses/details/components/app_responsive.dart';
import 'about_terms_model.dart';
import 'about_terms_provider.dart';

// ── Icon resolver: backend icon_name → IconData ──────────────────────────────
// Includes every icon the admin can pick in the content page (kContentIcons).
IconData _icon(String? name) => _iconMap[name] ?? Icons.star_outline_rounded;

const _iconMap = <String, IconData>{
  // original names
  'play_circle_outline': Icons.play_circle_outline_rounded,
  'people_alt': Icons.people_alt_outlined,
  'person': Icons.person_outline_rounded,
  'payment': Icons.payment_outlined,
  'shield': Icons.shield_outlined,
  'block': Icons.block_outlined,
  'update': Icons.update_rounded,
  'book': Icons.book_outlined,
  'email': Icons.email_outlined,
  'phone': Icons.phone_outlined,
  'location_on': Icons.location_on_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'info': Icons.info_outline_rounded,
  'notifications': Icons.notifications_outlined,
  'help': Icons.help_outline_rounded,
  'bug_report': Icons.bug_report_outlined,
  // admin picker (same keys as kContentIcons)
  'star': Icons.star_rounded,
  'rocket_launch': Icons.rocket_launch_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  'school': Icons.school_rounded,
  'groups': Icons.groups_rounded,
  'verified': Icons.verified_rounded,
  'security': Icons.security_rounded,
  'support_agent': Icons.support_agent_rounded,
  'devices': Icons.devices_rounded,
  'speed': Icons.speed_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'favorite': Icons.favorite_rounded,
  'insights': Icons.insights_rounded,
  'language': Icons.language_rounded,
  'menu_book': Icons.menu_book_rounded,
  'quiz': Icons.quiz_rounded,
  'play_circle': Icons.play_circle_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'bolt': Icons.bolt_rounded,
  'public': Icons.public_rounded,
  'schedule': Icons.schedule_rounded,
  'payments': Icons.payments_rounded,
  'gavel': Icons.gavel_rounded,
  'description': Icons.description_rounded,
  'policy': Icons.policy_rounded,
  'privacy_tip': Icons.privacy_tip_rounded,
  'lock': Icons.lock_rounded,
  'handshake': Icons.handshake_rounded,
  'gpp_good': Icons.gpp_good_rounded,
  'flag': Icons.flag_rounded,
};

/// Accent cycle taken from the APP THEME (indigo · gold · green · purple · amber · soft indigo),
/// so a theme change in the dashboard recolours these screens too.
Color _accent(ThemeConfigProvider c, int i) {
  final list = [c.primary, c.accent2, c.success, c.purple, c.warning, c.primaryLight];
  return list[i.abs() % list.length];
}

/// translate + fill {placeholders}
String _tp(String key, Map<String, Object> params) =>
    params.entries.fold(key.tr, (t, e) => t.replaceAll('{${e.key}}', '${e.value}'));

/// Headings / body in the theme's own text styles (their fonts), only size / colour tuned.
TextStyle _h(BuildContext context, {double size = 17, Color? color}) =>
    context.colors.h3.copyWith(fontSize: size, fontWeight: FontWeight.w800, color: color);

TextStyle _b(BuildContext context, {double size = 14, Color? color, double? height, FontWeight? weight}) =>
    context.colors.body.copyWith(fontSize: size, color: color, height: height, fontWeight: weight);

// ── shared pieces ─────────────────────────────────────────────────────────────

/// Calm tinted square with a coloured icon — no gloss, no glow.
class _SoftIcon extends StatelessWidget {
  const _SoftIcon({required this.icon, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.isDark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(c.radiusMedium),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill(this.label, {this.icon, this.highlight = false});

  final String label;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = highlight ? c.charcoalDark : context.colors.onHero;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? c.accent : context.colors.onHero.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
        Text(label, style: _b(context, size: 12, color: fg, weight: FontWeight.w700)),
      ]),
    );
  }
}

/// The brand-gradient banner both screens open with.
class _Hero extends StatelessWidget {
  const _Hero({required this.leading, required this.title, this.subtitle, this.pills = const []});

  final Widget leading;
  final String title;
  final String? subtitle;
  final List<Widget> pills;

  Widget _blob(BuildContext context, double size, double alpha) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.onHero.withValues(alpha: alpha)),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(c.radiusXL),
        boxShadow: c.primaryShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(c.radiusXL),
        child: Stack(children: [
          PositionedDirectional(end: -50, top: -50, child: _blob(context, 170, 0.07)),
          PositionedDirectional(start: -40, bottom: -60, child: _blob(context, 140, 0.06)),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            child: Column(children: [
              leading,
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: c.h2.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: context.colors.onHero, height: 1.25)),
              if ((subtitle ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: _b(context, size: 14.5, height: 1.6, color: context.colors.onHero.withValues(alpha: 0.9))),
              ],
              if (pills.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: pills),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.sub});

  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 4,
        height: sub == null ? 22 : 40,
        margin: const EdgeInsetsDirectional.only(end: 10, top: 1),
        decoration: BoxDecoration(color: c.accent2, borderRadius: BorderRadius.circular(4)),
      ),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: _h(context, size: 18)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: _b(context, size: 12.5, color: c.textLight)),
          ],
        ]),
      ),
    ]);
  }
}

/// Plain bordered card — the one surface style used on both screens.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16), this.borderColor, this.radius});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(radius ?? c.radiusLarge),
        border: Border.all(color: borderColor ?? c.divider),
      ),
      child: child,
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _SoftIcon(icon: Icons.wifi_off_rounded, color: c.danger, size: 64),
          const SizedBox(height: 16),
          Text(message, style: _b(context, size: 14.5, color: c.textMedium, height: 1.6), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('about_retry'.tr),
            style: FilledButton.styleFrom(
              backgroundColor: c.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(c.radiusMedium)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  About Screen
// ══════════════════════════════════════════════════════════════════════════════

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AboutTermsProvider>().loadAbout(context);
      AppIdentity.instance.refresh(); // newest version info
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // re-translate when the language changes
    final p = context.watch<AboutTermsProvider>();
    final isWide = context.showSidebar;

    // The data on screen is in the other language → fetch it again.
    if (p.about != null && p.aboutLang != AppConfig.lang && !p.isLoadingAbout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) p.loadAbout(context);
      });
    }

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        key: const ValueKey('about'),
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'about_us'.tr),
            Expanded(child: _buildBody(p, isWide)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody(AboutTermsProvider p, bool isWide) {
    if (p.about == null && p.aboutError == null) {
      return const AppListSkeleton(items: 5, withAvatar: false);
    }
    if (p.aboutError != null && p.about == null) {
      return _ErrorState(
        message: p.aboutError!,
        onRetry: () => p.loadAbout(context, forceRefresh: true),
      );
    }

    final about = p.about!;

    Widget gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 30), child: w);

    return AppRefresh(
      onRefresh: () async {
        await p.loadAbout(context, forceRefresh: true);
        await AppIdentity.instance.refresh();
      },
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(children: [
                gap(ParentComponent(featureKey: 'about.hero', child: _AboutHero(info: about.info))),
                if (about.stats.isNotEmpty)
                  gap(ParentComponent(featureKey: 'about.stats', child: _StatsCard(stats: about.stats))),
                if ((about.info?.mission ?? '').isNotEmpty)
                  gap(ParentComponent(
                    featureKey: 'about.mission',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _SectionTitle(text: 'about_mission'.tr, sub: 'about_mission_sub'.tr),
                      const SizedBox(height: 14),
                      _MissionCard(mission: about.info!.mission!),
                    ]),
                  )),
                if (about.features.isNotEmpty)
                  gap(ParentComponent(
                    featureKey: 'about.features',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _SectionTitle(text: 'about_features'.tr, sub: 'about_features_sub'.tr),
                      const SizedBox(height: 16),
                      _FeaturesGrid(features: about.features, isWide: isWide),
                    ]),
                  )),
                if (about.team.isNotEmpty)
                  gap(ParentComponent(
                    featureKey: 'about.team',
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _SectionTitle(text: 'about_team'.tr, sub: 'about_team_sub'.tr),
                      const SizedBox(height: 16),
                      _TeamRow(team: about.team),
                    ]),
                  )),
                if (about.contacts.isNotEmpty)
                  gap(ParentComponent(
                    featureKey: 'about.contact',
                    child: _ContactCard(contacts: about.contacts),
                  )),
                const _AppVersionCard(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _AboutHero extends StatelessWidget {
  const _AboutHero({required this.info});

  final AppInfoModel? info;

  @override
  Widget build(BuildContext context) {
    final id = AppIdentity.instance;
    final c = context.colors;
    final logo = info?.logoUrl;

    return ListenableBuilder(
      listenable: id,
      builder: (context, _) => _Hero(
        leading: Container(
          width: 104,
          height: 104,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.onHero.withValues(alpha: 0.22),
            border: Border.all(color: c.accent.withValues(alpha: 0.9), width: 2),
          ),
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle, color: context.colors.onHero),
            child: logo != null && logo.isNotEmpty
                ? ClipOval(child: AppNetworkImage(url: logo, fit: BoxFit.cover))
                : Icon(Icons.school_rounded, size: 50, color: c.primary),
          ),
        ),
        title: (info?.name ?? '').isNotEmpty ? info!.name : id.name,
        subtitle: info?.tagline,
        pills: [
          if (id.installedVersion.isNotEmpty)
            _HeroPill('${'about_version'.tr} ${id.installedVersion}', icon: Icons.tag_rounded),
          if (id.updateAvailable)
            _HeroPill('about_update_available'.tr, icon: Icons.system_update_rounded, highlight: true),
        ],
      ),
    );
  }
}

// ── Stats: one card, numbers separated by hairlines ───────────────────────────

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final List<AppStatModel> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 640 ? stats.length.clamp(1, 4) : 2;
      final rows = <List<AppStatModel>>[];
      for (var i = 0; i < stats.length; i += cols) {
        rows.add(stats.skip(i).take(cols).toList());
      }

      Widget cell(AppStatModel st) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(st.value,
                  textDirection: TextDirection.ltr,
                  style: c.h1.copyWith(fontSize: 28, fontWeight: FontWeight.w900, color: c.primary)),
            ),
            const SizedBox(height: 4),
            Text(st.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _b(context, size: 12.5, color: c.textMedium, height: 1.35)),
          ]),
        ),
      );

      return _Card(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) Divider(height: 1, color: c.divider),
            IntrinsicHeight(
              child: Row(children: [
                for (var i = 0; i < cols; i++) ...[
                  if (i > 0) VerticalDivider(width: 1, color: c.divider),
                  if (i < rows[r].length) cell(rows[r][i]) else const Expanded(child: SizedBox()),
                ],
              ]),
            ),
          ],
        ]),
      );
    });
  }
}

// ── Mission: a pull-quote, not a card ─────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});

  final String mission;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: BorderDirectional(start: BorderSide(color: c.accent2, width: 4)),
      ),
      child: SelectableText(mission,
          style: _b(context, size: 15.5, color: c.textDark, height: 1.95, weight: FontWeight.w500)),
    );
  }
}

// ── Features ──────────────────────────────────────────────────────────────────

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid({required this.features, required this.isWide});

  final List<AppFeatureModel> features;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const gap = 12.0;
      final cols = isWide || box.maxWidth > 640 ? 3 : 2;
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < features.length; i++)
          SizedBox(width: w, child: _FeatureCard(feature: features[i], index: i)),
      ]);
    });
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.index});

  final AppFeatureModel feature;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Card(
      radius: c.radiusMedium,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SoftIcon(icon: _icon(feature.iconName), color: _accent(c, index), size: 42),
        const SizedBox(height: 12),
        Text(feature.title, style: _h(context, size: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
        if ((feature.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(feature.description!,
              style: _b(context, size: 12.5, color: c.textMedium, height: 1.6),
              maxLines: 4,
              overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

// ── Team ──────────────────────────────────────────────────────────────────────

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final List<TeamMemberModel> team;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 192,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: team.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _TeamCard(member: team[i], index: i),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.member, required this.index});

  final TeamMemberModel member;
  final int index;

  bool get _hasPhoto => (member.imageUrl ?? '').isNotEmpty;

  void _zoom(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(18),
        child: Stack(alignment: AlignmentDirectional.topEnd, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(ctx.colors.radiusLarge),
            child: InteractiveViewer(
              child: AppNetworkImage(url: member.imageUrl!, fit: BoxFit.contain),
            ),
          ),
          IconButton.filled(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            style: IconButton.styleFrom(backgroundColor: context.colors.heroShade.withValues(alpha: 0.54)),
            icon: Icon(Icons.close_rounded, color: context.colors.onHero),
            onPressed: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _accent(c, index);

    final avatar = Container(
      width: 82,
      height: 82,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: 2),
      ),
      child: ClipOval(
        child: _hasPhoto
            ? AppNetworkImage(url: member.imageUrl!, width: 76, height: 76, fit: BoxFit.cover)
            : Container(
          color: color.withValues(alpha: c.isDark ? 0.22 : 0.13),
          alignment: Alignment.center,
          child: (member.emoji ?? '').isNotEmpty
              ? Text(member.emoji!, style: const TextStyle(fontSize: 36))
              : Text(member.name.isNotEmpty ? member.name.characters.first.toUpperCase() : '?',
              style: c.h2.copyWith(fontSize: 30, color: color)),
        ),
      ),
    );

    return SizedBox(
      width: 148,
      child: _Card(
        radius: c.radiusMedium,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          GestureDetector(onTap: _hasPhoto ? () => _zoom(context) : null, child: avatar),
          const SizedBox(height: 12),
          Text(member.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _h(context, size: 13.5)),
          const SizedBox(height: 3),
          Text(member.role,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _b(context, size: 12, color: c.textLight, height: 1.35)),
        ]),
      ),
    );
  }
}

// ── Contacts ──────────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contacts});

  final List<ContactInfoModel> contacts;

  static const _icons = <String, IconData>{
    'email': Icons.email_rounded,
    'phone': Icons.phone_rounded,
    'address': Icons.location_on_rounded,
    'website': Icons.language_rounded,
    'whatsapp': Icons.chat_rounded,
    'telegram': Icons.send_rounded,
    'facebook': Icons.facebook_rounded,
    'instagram': Icons.camera_alt_rounded,
    'youtube': Icons.smart_display_rounded,
  };

  /// Colours come from the app theme (not brand colours of each network).
  static Color _color(ThemeConfigProvider c, String type) {
    switch (type) {
      case 'phone':
      case 'whatsapp':
        return c.success;
      case 'address':
        return c.warning;
      case 'website':
        return c.purple;
      case 'instagram':
      case 'youtube':
        return c.danger;
      default:
        return c.primary; // email · telegram · facebook · other
    }
  }

  /// What a tap opens (null = nothing to open, just copy).
  static Uri? _uri(ContactInfoModel k) {
    final v = k.value.trim();
    if (v.isEmpty) return null;
    bool isUrl() => v.startsWith('http://') || v.startsWith('https://');
    switch (k.type) {
      case 'email':
        return Uri(scheme: 'mailto', path: v);
      case 'phone':
        return Uri(scheme: 'tel', path: v.replaceAll(RegExp(r'\s'), ''));
      case 'whatsapp':
        return isUrl() ? Uri.tryParse(v) : Uri.tryParse('https://wa.me/${v.replaceAll(RegExp(r'\D'), '')}');
      case 'telegram':
        return isUrl() ? Uri.tryParse(v) : Uri.tryParse('https://t.me/${v.replaceFirst('@', '')}');
      case 'address':
        return Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': v});
      default:
        return isUrl() ? Uri.tryParse(v) : Uri.tryParse('https://$v');
    }
  }

  Future<void> _open(BuildContext context, ContactInfoModel k) async {
    final uri = _uri(k);
    try {
      if (uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* fall through → copy */}
    if (context.mounted) await _copy(context, k.value);
  }

  Future<void> _copy(BuildContext context, String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    Helpers.showMessage('about_copied'.tr, isError: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _Card(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionTitle(text: 'about_contact'.tr, sub: 'about_contact_hint'.tr),
        const SizedBox(height: 10),
        for (var i = 0; i < contacts.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.divider),
          Builder(builder: (context) {
            final k = contacts[i];
            final color = _color(c, k.type);
            final icon = _icons[k.type] ?? (k.iconName != null ? _icon(k.iconName) : Icons.link_rounded);
            final hasLabel = (k.label ?? '').isNotEmpty;
            return InkWell(
              borderRadius: BorderRadius.circular(c.radiusMedium),
              onTap: () => _open(context, k),
              onLongPress: () => _copy(context, k.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(children: [
                  _SoftIcon(icon: icon, color: color, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(hasLabel ? k.label! : 'about_type_${k.type}'.tr,
                          style: _b(context, size: 12, color: c.textLight)),
                      const SizedBox(height: 2),
                      Text(k.value,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: k.type == 'address' ? null : TextDirection.ltr,
                          style: _h(context, size: 14.5)),
                    ]),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'about_copy'.tr,
                    icon: Icon(Icons.copy_rounded, size: 19, color: c.textLight),
                    onPressed: () => _copy(context, k.value),
                  ),
                ]),
              ),
            );
          }),
        ],
      ]),
    );
  }
}

// ── About this app: installed version + update ───────────────────────────────

class _AppVersionCard extends StatelessWidget {
  const _AppVersionCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final id = AppIdentity.instance;

    return ListenableBuilder(
      listenable: id,
      builder: (context, _) {
        if (id.installedVersion.isEmpty && id.latest == null) return const SizedBox.shrink();
        final update = id.updateAvailable;
        final color = update ? c.warning : c.success;
        final notes = id.latest?.notes ?? '';

        return _Card(
          borderColor: update ? color.withValues(alpha: 0.55) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _SoftIcon(icon: update ? Icons.system_update_rounded : Icons.check_circle_rounded, color: color, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('about_this_app'.tr, style: _h(context, size: 15.5)),
                  const SizedBox(height: 2),
                  Text(update ? 'about_update_available_long'.tr : 'about_up_to_date'.tr,
                      style: _b(context, size: 13, color: c.textMedium, height: 1.4)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Divider(height: 1, color: c.divider),
            const SizedBox(height: 6),
            _VersionRow(label: 'about_installed_version'.tr, value: id.versionLabel),
            if (id.latest != null) _VersionRow(label: 'about_latest_version'.tr, value: id.latest!.version),
            if (update && notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: c.isDark ? 0.16 : 0.09),
                  borderRadius: BorderRadius.circular(c.radiusSmall + 2),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('about_whats_new'.tr, style: _h(context, size: 12.5, color: color)),
                  const SizedBox(height: 4),
                  Text(notes, style: _b(context, size: 12.5, color: c.textMedium, height: 1.65)),
                ]),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});

  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Text(label, style: _b(context, size: 13, color: c.textMedium)),
        const Spacer(),
        Text(value, textDirection: TextDirection.ltr, style: _h(context, size: 13.5)),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms & Conditions Screen
// ══════════════════════════════════════════════════════════════════════════════

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final Set<int> _expanded = {};
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AboutTermsProvider>().loadTerms(context);
      final sections = context.read<AboutTermsProvider>().terms?.sections ?? [];
      if (sections.isNotEmpty && mounted) {
        setState(() => _expanded.add(sections.first.id));
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(TermsSectionModel s) {
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return s.title.toLowerCase().contains(q) || s.body.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final p = context.watch<AboutTermsProvider>();

    if (p.terms != null && p.termsLang != AppConfig.lang && !p.isLoadingTerms) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) p.loadTerms(context);
      });
    }

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        key: const ValueKey('terms'),
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: 'terms_and_conditions'.tr),
            Expanded(child: _buildBody(p)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody(AboutTermsProvider p) {
    if (p.terms == null && p.termsError == null) {
      return const AppListSkeleton(items: 5, withAvatar: false);
    }
    if (p.termsError != null && p.terms == null) {
      return _ErrorState(
        message: p.termsError!,
        onRetry: () => p.loadTerms(context, forceRefresh: true),
      );
    }

    final terms = p.terms!;
    final c = context.colors;
    final visible = terms.sections.where(_matches).toList();
    final allOpen = visible.isNotEmpty && visible.every((s) => _expanded.contains(s.id));

    return AppRefresh(
      onRefresh: () => p.loadTerms(context, forceRefresh: true),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(children: [
                ParentComponent(
                    featureKey: 'terms.header',
                    child: _TermsHero(meta: terms.meta, count: terms.sections.length)),
                const SizedBox(height: 18),
                if (terms.sections.length > 3)
                  TextField(
                    controller: _search,
                    onChanged: (v) => setState(() {
                      _q = v.trim();
                      if (_q.isNotEmpty) _expanded.addAll(terms.sections.where(_matches).map((e) => e.id));
                    }),
                    style: _b(context, size: 14, color: c.textDark),
                    decoration: InputDecoration(
                      hintText: 'terms_search_hint'.tr,
                      hintStyle: _b(context, size: 13.5, color: c.textLight),
                      prefixIcon: Icon(Icons.search_rounded, color: c.textLight),
                      suffixIcon: _q.isEmpty
                          ? null
                          : IconButton(
                        tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                        icon: Icon(Icons.close_rounded, size: 18, color: c.textLight),
                        onPressed: () => setState(() {
                          _search.clear();
                          _q = '';
                        }),
                      ),
                      filled: true,
                      fillColor: c.inputBg,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(c.radiusMedium), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(c.radiusMedium),
                          borderSide: BorderSide(color: c.primary, width: 1.4)),
                    ),
                  ),
                if (visible.length > 1)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        if (allOpen) {
                          _expanded.removeAll(visible.map((e) => e.id));
                        } else {
                          _expanded.addAll(visible.map((e) => e.id));
                        }
                      }),
                      icon: Icon(allOpen ? Icons.unfold_less_rounded : Icons.unfold_more_rounded, size: 19),
                      label: Text(allOpen ? 'terms_collapse_all'.tr : 'terms_expand_all'.tr,
                          style: _b(context, size: 13, color: c.primary, weight: FontWeight.w700)),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                if (visible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(children: [
                      Icon(Icons.search_off_rounded, size: 48, color: c.textLight),
                      const SizedBox(height: 10),
                      Text(terms.sections.isEmpty ? 'terms_empty'.tr : 'terms_no_match'.tr,
                          textAlign: TextAlign.center,
                          style: _b(context, size: 14, color: c.textMedium, height: 1.6)),
                    ]),
                  ),
                for (final section in visible)
                  ParentComponent(
                    featureKey: 'terms.sections',
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TermsSection(
                        number: terms.sections.indexOf(section) + 1,
                        section: section,
                        isOpen: _expanded.contains(section.id),
                        onToggle: () => setState(() {
                          if (!_expanded.remove(section.id)) _expanded.add(section.id);
                        }),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                ParentComponent(featureKey: 'terms.footer', child: const _TermsFooter()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Terms hero ────────────────────────────────────────────────────────────────

class _TermsHero extends StatelessWidget {
  const _TermsHero({required this.meta, required this.count});

  final TermsMetaModel? meta;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final version = meta?.version ?? '';
    final updated = meta?.lastUpdated ?? '';
    return _Hero(
      leading: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: context.colors.onHero.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(c.radiusLarge),
          border: Border.all(color: c.accent.withValues(alpha: 0.85), width: 1.5),
        ),
        child: Icon(Icons.gavel_rounded, color: context.colors.onHero, size: 34),
      ),
      title: 'terms_and_conditions'.tr,
      subtitle: 'terms_intro'.tr,
      pills: [
        if (version.isNotEmpty) _HeroPill('${'about_version'.tr} $version', icon: Icons.tag_rounded),
        if (updated.isNotEmpty) _HeroPill('${'terms_last_updated'.tr} $updated', icon: Icons.update_rounded),
        if (count > 0) _HeroPill(_tp('terms_n_sections', {'n': count}), icon: Icons.view_agenda_rounded),
      ],
    );
  }
}

// ── Terms section accordion ───────────────────────────────────────────────────

class _TermsSection extends StatelessWidget {
  const _TermsSection({
    required this.number,
    required this.section,
    required this.isOpen,
    required this.onToggle,
  });

  final int number;
  final TermsSectionModel section;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = _accent(c, number - 1);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(
          color: isOpen ? c.primary.withValues(alpha: 0.5) : c.divider,
          width: isOpen ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(c.radiusMedium),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              _SoftIcon(icon: _icon(section.iconName), color: color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${'terms_section'.tr} $number', style: _b(context, size: 11.5, color: c.textLight)),
                  const SizedBox(height: 2),
                  Text(section.title,
                      style: _h(context, size: 14.5, color: isOpen ? c.primary : null)),
                ]),
              ),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down_rounded, color: isOpen ? c.primary : c.textLight),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(children: [
              Divider(color: c.divider, height: 1),
              const SizedBox(height: 14),
              SelectableText(section.body,
                  style: _b(context, size: 14, color: c.textMedium, height: 1.95)),
            ]),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

// ── Terms footer ──────────────────────────────────────────────────────────────

class _TermsFooter extends StatelessWidget {
  const _TermsFooter();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.favorite_rounded, color: c.success, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text('terms_footer'.tr, style: _b(context, size: 13, color: c.success, height: 1.75, weight: FontWeight.w600)),
        ),
      ]),
    );
  }
}
