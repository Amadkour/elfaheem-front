// ─────────────────────────────────────────────────────────────────────────────
// features/shared/about/about_and_terms_screen.dart  (v2 – bilingual)
// About Us + Terms & Conditions — server-driven, dark/light, AR/EN adaptive
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:provider/provider.dart';

import '../../../../config/theme/app_theme.dart';
import '../../../../utils/helpers.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import '../../../student/courses/details/components/app_responsive.dart';
import 'about_terms_model.dart';
import 'about_terms_provider.dart';

// ── Icon resolver: maps backend icon_name string → Flutter IconData ───────────
IconData _icon(String name) => _iconMap[name] ?? Icons.circle_outlined;

const _iconMap = <String, IconData>{
  'play_circle_outline': Icons.play_circle_outline_rounded,
  'people_alt': Icons.people_alt_outlined,
  'quiz': Icons.quiz_outlined,
  'emoji_events': Icons.emoji_events_outlined,
  'support_agent': Icons.support_agent_rounded,
  'devices': Icons.devices_outlined,
  'school': Icons.school_outlined,
  'book': Icons.book_outlined,
  'star': Icons.star_outline_rounded,
  'gavel': Icons.gavel_rounded,
  'person': Icons.person_outline_rounded,
  'payment': Icons.payment_outlined,
  'shield': Icons.shield_outlined,
  'block': Icons.block_outlined,
  'update': Icons.update_rounded,
  'description': Icons.description_outlined,
  'email': Icons.email_outlined,
  'phone': Icons.phone_outlined,
  'location_on': Icons.location_on_outlined,
  'language': Icons.language_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'info': Icons.info_outline_rounded,
  'verified': Icons.verified_outlined,
  'lock': Icons.lock_outline_rounded,
  'notifications': Icons.notifications_outlined,
  'help': Icons.help_outline_rounded,
  'workspace_premium': Icons.workspace_premium_outlined,
  'bug_report': Icons.bug_report_outlined,
};

// ── Localised label helper (for UI strings not coming from the server) ─────────
String _l(BuildContext ctx, String ar, String en) {
  final code = Localizations.localeOf(ctx).languageCode;
  return code == 'en' ? en : ar;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AboutTermsProvider>();
    final c = context.colors;
    final isWide = context.showSidebar;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(title: _l(context, 'من نحن', 'About Us')),
            Expanded(child: _buildBody(p, c, isWide)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody(AboutTermsProvider p, AppColors c, bool isWide) {
    if (p.isLoadingAbout) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.aboutError != null) {
      return _ErrorState(
        message: p.aboutError!,
        onRetry: () => p.loadAbout(context, forceRefresh: true),
      );
    }
    if (p.about == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final about = p.about!;

    return RefreshIndicator(
      onRefresh: () => p.loadAbout(context, forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Column(children: [
                _HeroBanner(info: about.info),
                const SizedBox(height: 32),
                if ((about.info?.mission ?? '').isNotEmpty) ...[
                  _SectionTitle(text: _l(context, 'رسالتنا', 'Our Mission')),
                  const SizedBox(height: 12),
                  _MissionCard(mission: about.info!.mission!),
                  const SizedBox(height: 32),
                ],
                if (about.stats.isNotEmpty) ...[
                  _StatsRow(stats: about.stats),
                  const SizedBox(height: 32),
                ],
                if (about.features.isNotEmpty) ...[
                  _SectionTitle(
                      text:
                          _l(context, 'ما يميّزنا', 'What Makes Us Different')),
                  const SizedBox(height: 16),
                  _FeaturesGrid(features: about.features, isWide: isWide),
                  const SizedBox(height: 32),
                ],
                if (about.team.isNotEmpty) ...[
                  _SectionTitle(text: _l(context, 'فريقنا', 'Our Team')),
                  const SizedBox(height: 16),
                  _TeamRow(team: about.team),
                  const SizedBox(height: 32),
                ],
                if (about.contacts.isNotEmpty)
                  _ContactCard(
                    contacts: about.contacts,
                    title: _l(context, 'تواصل معنا', 'Contact Us'),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero Banner ───────────────────────────────────────────────────────────────

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({required this.info});

  final AppInfoModel? info;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        gradient: c.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: c.primaryShadow,
      ),
      child: Column(children: [
        // Logo — real MinIO image or fallback icon
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.15),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.4), width: 2),
          ),
          child: info?.logoUrl != null
              ? ClipOval(
                  child: AppNetworkImage(
                    url: info!.logoUrl!,
                    fit: BoxFit.cover,
                  ),
                )
              : const Icon(Icons.school_rounded, size: 52, color: Colors.white),
        ),
        const SizedBox(height: 20),
        Text(
          info?.name ?? 'ElFaheem',
          style: const TextStyle(
              fontFamily: 'bahji',
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5),
        ),
        if ((info?.tagline ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            info!.tagline!,
            style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.85)),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(children: [
      Container(
        width: 4,
        height: 22,
        decoration: BoxDecoration(
            color: c.primary, borderRadius: BorderRadius.circular(4)),
      ),
      const SizedBox(width: 10),
      Text(text, style: c.h2.copyWith(fontSize: 18)),
    ]);
  }
}

// ── Mission Card ──────────────────────────────────────────────────────────────

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});

  final String mission;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(children: [
        Icon(Icons.format_quote_rounded, color: c.primary, size: 32),
        const SizedBox(height: 12),
        Text(
          mission,
          style: c.body
              .copyWith(height: 1.9, fontSize: 15, fontStyle: FontStyle.italic),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});

  final List<AppStatModel> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: stats.take(4).map((s) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Text(s.value,
                style: TextStyle(
                    fontFamily: 'bahji',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: c.primary)),
            const SizedBox(height: 4),
            Text(s.label,
                style: TextStyle(
                    fontFamily: 'bahji', fontSize: 11, color: c.textMedium)),
          ]);
        }).toList(),
      ),
    );
  }
}

// ── Features Grid ─────────────────────────────────────────────────────────────

class _FeaturesGrid extends StatelessWidget {
  const _FeaturesGrid({required this.features, required this.isWide});

  final List<AppFeatureModel> features;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final cols = isWide ? 3 : 2;
    final rows = <Widget>[];
    for (int i = 0; i < features.length; i += cols) {
      final slice = features.skip(i).take(cols).toList();
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int j = 0; j < slice.length; j++) ...[
            Expanded(child: _FeatureCard(feature: slice[j])),
            if (j < slice.length - 1) const SizedBox(width: 12),
          ],
          for (int k = slice.length; k < cols; k++) ...[
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ],
      ));
      if (i + cols < features.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final AppFeatureModel feature;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_icon(feature.iconName), color: Colors.white, size: 22),
        ),
        const SizedBox(height: 12),
        Text(feature.title,
            style: c.h3.copyWith(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if ((feature.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(feature.description!,
              style: c.caption.copyWith(height: 1.5, fontSize: 11),
              maxLines: 3),
        ],
      ]),
    );
  }
}

// ── Team Row ──────────────────────────────────────────────────────────────────

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.team});

  final List<TeamMemberModel> team;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: team.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final m = team[i];
          return Container(
            width: 130,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.cardBg,
              borderRadius: BorderRadius.circular(c.radiusMedium),
              boxShadow: c.cardShadow,
            ),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              // MinIO image, emoji fallback, or default avatar
              m.imageUrl != null
                  ? CircleAvatar(
                      radius: 28,
                      backgroundColor: c.primaryTint,
                      child: ClipOval(
                        child: AppNetworkImage(
                          url: m.imageUrl!,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : m.emoji != null
                      ? Text(m.emoji!, style: const TextStyle(fontSize: 36))
                      : CircleAvatar(
                          radius: 28,
                          backgroundColor: c.primaryTint,
                          child: Icon(Icons.person_rounded,
                              size: 30, color: c.primary),
                        ),
              const SizedBox(height: 8),
              Text(m.name,
                  style: c.h3.copyWith(fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(m.role,
                  style: c.caption.copyWith(fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2),
            ]),
          );
        },
      ),
    );
  }
}

// ── Contact Card ──────────────────────────────────────────────────────────────

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contacts, required this.title});

  final List<ContactInfoModel> contacts;
  final String title;

  static const _typeConfig = <String, (IconData, Color)>{
    'email': (Icons.email_outlined, Color(0xFF3B82F6)),
    'phone': (Icons.phone_outlined, Color(0xFF10B981)),
    'address': (Icons.location_on_outlined, Color(0xFFF59E0B)),
    'website': (Icons.language_outlined, Color(0xFF8B5CF6)),
    'whatsapp': (Icons.chat_bubble_outline_rounded, Color(0xFF25D366)),
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
        border: Border.all(color: c.divider),
      ),
      child: Column(children: [
        Text(title, style: c.h2.copyWith(fontSize: 16)),
        const SizedBox(height: 16),
        ...contacts.asMap().entries.map((entry) {
          final contact = entry.value;
          final cfg = _typeConfig[contact.type];
          final icon = cfg?.$1 ??
              (contact.iconName != null
                  ? _icon(contact.iconName!)
                  : Icons.contact_support_outlined);
          final color = cfg?.$2 ?? c.primary;
          // Display the label if provided, otherwise the raw value
          final display = contact.label?.isNotEmpty == true
              ? contact.label!
              : contact.value;
          return Padding(
            padding: EdgeInsets.only(
                bottom: entry.key < contacts.length - 1 ? 12 : 0),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (contact.label?.isNotEmpty == true)
                      Text(contact.label!,
                          style: c.caption
                              .copyWith(fontSize: 10, color: c.textLight)),
                    Text(contact.value,
                        style: c.body.copyWith(fontSize: 14),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Shared Error State ────────────────────────────────────────────────────────

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
          Icon(Icons.wifi_off_rounded, size: 56, color: c.textLight),
          const SizedBox(height: 16),
          Text(message,
              style: c.body.copyWith(color: c.textMedium),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(_l(context, 'إعادة المحاولة', 'Try Again'),
                style: const TextStyle(fontFamily: 'bahji')),
          ),
        ]),
      ),
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
  Widget build(BuildContext context) {
    final p = context.watch<AboutTermsProvider>();
    final c = context.colors;

    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        useWebCard: true,
        child: SafeArea(
          child: Column(children: [
            ScreenAppBar(
                title: _l(context, 'الشروط والأحكام', 'Terms & Conditions')),
            Expanded(child: _buildBody(p, c)),
          ]),
        ),
      ),
    );
  }

  Widget _buildBody(AboutTermsProvider p, AppColors c) {
    if (p.isLoadingTerms) {
      return const Center(child: CircularProgressIndicator());
    }
    if (p.termsError != null) {
      return _ErrorState(
        message: p.termsError!,
        onRetry: () => p.loadTerms(context, forceRefresh: true),
      );
    }
    if (p.terms == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final terms = p.terms!;

    return RefreshIndicator(
      onRefresh: () => p.loadTerms(context, forceRefresh: true),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Breakpoints.contentMax),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              child: Column(children: [
                _TermsHeader(meta: terms.meta),
                const SizedBox(height: 20),
                ...terms.sections.map((section) {
                  final isOpen = _expanded.contains(section.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TermsSection(
                      section: section,
                      isOpen: isOpen,
                      onToggle: () => setState(() {
                        if (isOpen) {
                          _expanded.remove(section.id);
                        } else {
                          _expanded.add(section.id);
                        }
                      }),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                _TermsFooter(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Terms Header ──────────────────────────────────────────────────────────────

class _TermsHeader extends StatelessWidget {
  const _TermsHeader({required this.meta});

  final TermsMetaModel? meta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            c.primary.withValues(alpha: 0.08),
            c.accent.withValues(alpha: 0.05),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: c.primaryGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: c.primaryShadow,
          ),
          child: const Icon(Icons.description_outlined,
              color: Colors.white, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _l(context, 'الشروط والأحكام', 'Terms & Conditions'),
              style: c.h2.copyWith(fontSize: 16),
            ),
            if (meta != null) ...[
              const SizedBox(height: 4),
              Text(
                _l(context, 'آخر تحديث:', 'Last updated:') +
                    ' ${meta!.lastUpdated}',
                style: c.caption.copyWith(fontSize: 12),
              ),
              if ((meta!.version ?? '').isNotEmpty)
                Text(
                  _l(context, 'الإصدار', 'Version') + ' ${meta!.version}',
                  style: c.caption.copyWith(fontSize: 11, color: c.textLight),
                ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Terms Section Accordion ───────────────────────────────────────────────────

class _TermsSection extends StatelessWidget {
  const _TermsSection({
    required this.section,
    required this.isOpen,
    required this.onToggle,
  });

  final TermsSectionModel section;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(c.radiusMedium),
        boxShadow: c.cardShadow,
        border: isOpen
            ? Border.all(color: c.primary.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: Column(children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isOpen ? c.primary : c.primaryTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_icon(section.iconName),
                    size: 18, color: isOpen ? Colors.white : c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  section.title,
                  style: c.h3.copyWith(
                    fontSize: 14,
                    color: isOpen ? c.primary : c.textDark,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    color: isOpen ? c.primary : c.textLight),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState:
              isOpen ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(children: [
              Divider(color: c.divider, height: 1),
              const SizedBox(height: 14),
              Text(section.body,
                  style: c.body.copyWith(height: 1.85, fontSize: 14)),
            ]),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

// ── Terms Footer ──────────────────────────────────────────────────────────────

class _TermsFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.success.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.verified_outlined, color: c.success, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _l(
              context,
              'باستمرارك في استخدام المنصة، فأنت تقر بأنك قرأت وفهمت ووافقت على جميع الشروط والأحكام.',
              'By continuing to use the platform, you confirm that you have read, understood, and agreed to all Terms & Conditions.',
            ),
            style: TextStyle(
              fontFamily: 'bahji',
              fontSize: 13,
              height: 1.7,
              color: c.success.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ]),
    );
  }
}
