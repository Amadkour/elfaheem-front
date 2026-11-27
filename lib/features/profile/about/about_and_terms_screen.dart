// ─────────────────────────────────────────────────────────────────────────────
// features/profile/about/about_and_terms_screen.dart  (v4 – reading pages, D-088)
//
// About · Terms & conditions · Privacy & terms. Everything comes from what the admin edits on the dashboard's
// "App content" page (admin_content_page.dart): GET /api/v1/app-content/about | /terms?lang=.
//
//   Terms / Privacy : redesign Stu1Public?screen=legal (S-A2): the area hero, then ONE card with the الخصوصية /
//                     الشروط segment (the other document opens in place), the intro and facts, and every section
//                     as a row (its glyph, title, text) between hairlines; a sticky table of contents — section chips
//                     pinned on a phone for a long document (6+ sections), an "On this page"
//                     column on a wide window — that follows the scroll and jumps to a section; a closing note.
//                     The app assistant is one tap away (kill switch rag.app_assistant): the bot button in the app
//                     bar and a floating "Ask about this page" pill (phone) or a card under the table of contents
//                     (wide) open it with a question about the page already typed ([AppAssistant.ask]).
//   About           : hero (logo · name · tagline · version), figures, mission, features, team, Contact & support
//                     (contacts, the assistant, the app version + release notes).
//
// The parts take plain values (about_terms_parts.dart). Loading draws the page's shape (ReadingSkeleton), an error
// or an empty page is a calm AppEmpty with a retry.
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/features/guest/sa_hero_page.dart';
import 'package:flutter_education_app/design/app_area.dart' show AppArea;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_identity.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppBorder, AppCard, AppEmpty, AppIconBox, AppRefresh, AppSpace, AppTabItem, AppTabs, AppType, appText;
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/features/rag/app_assistant.dart' show AppAssistant;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_model.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_parts.dart';
import 'package:flutter_education_app/features/profile/about/about_terms_provider.dart';

/// Width of the reading column (≈ 70 characters a line at 16 px).
const _readingMax = 760.0;

/// From here the table of contents is a column beside the text.
const _tocBreakpoint = 1000.0;
const _tocWidth = 240.0;
const _tocGap = 48.0;

/// Height of the phone's pinned section chips.
const _chipsHeight = 56.0;

/// Whether the app assistant can be offered here (signed in, not a guest, not switched off). Never throws: a page
/// pushed outside the app's providers just doesn't offer it.
bool _assistantAvailable(BuildContext context) {
  try {
    return AppAssistant.availableFor(context);
  } catch (_) {
    return false;
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Terms & conditions · Privacy & terms
// ══════════════════════════════════════════════════════════════════════════════

class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key, this.privacy = false, this.canAsk});

  /// The privacy policy instead of the terms of service (D-308: its own document, GET /app-content/legal/privacy).
  final bool privacy;

  /// Offer the assistant (null = decide from the session and the kill switch).
  final bool? canAsk;

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  /// Which document is open: the route's, then the segment's.
  late bool _privacy = widget.privacy;
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  final _keys = <GlobalKey>[];
  int _active = 0;
  bool _chipOpen = true;
  double _pinned = 0; // what sits over the top of the scroll view (the chips), for the scroll spy and jumps

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_queueSpy);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load(context.read<AboutTermsProvider>());
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  RenderBox? _box(GlobalKey k) {
    final r = k.currentContext?.findRenderObject();
    return r is RenderBox && r.attached && r.hasSize ? r : null;
  }

  /// The section whose top has passed the reading line is the current one (the last one at the very end).
  void _spy() {
    final vp = _box(_viewport);
    if (vp == null || _keys.isEmpty || !_scroll.hasClients) return;
    var a = 0;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 4) {
      a = _keys.length - 1;
    } else {
      final line = vp.localToGlobal(Offset.zero).dy + _pinned + 32;
      for (var i = 0; i < _keys.length; i++) {
        final b = _box(_keys[i]);
        if (b != null && b.localToGlobal(Offset.zero).dy <= line) a = i;
      }
    }
    if (a != _active) setState(() => _active = a);
  }

  bool _spyQueued = false;

  /// The scroll listener fires before the new offset is laid out: read the positions after the frame.
  void _queueSpy() {
    if (_spyQueued) return;
    _spyQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _spyQueued = false;
      if (mounted) _spy();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _jump(int i) {
    final vp = _box(_viewport);
    final b = i < _keys.length ? _box(_keys[i]) : null;
    if (vp == null || b == null || !_scroll.hasClients) return;
    final dy = b.localToGlobal(Offset.zero).dy - vp.localToGlobal(Offset.zero).dy;
    final target = (_scroll.offset + dy - _pinned - 16).clamp(0.0, _scroll.position.maxScrollExtent);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() => _active = i);
    if (reduce) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    }
  }

  void _ask() => AppAssistant.ask(_privacy ? 'assistant_q_privacy'.tr : 'assistant_q_terms'.tr);

  Future<void> _load(AboutTermsProvider p, {bool force = false}) =>
      _privacy ? p.loadPrivacy(context, forceRefresh: force) : p.loadTerms(context, forceRefresh: force);

  TermsPageModel? _doc(AboutTermsProvider p) => _privacy ? p.privacy : p.terms;

  /// The other document, in place (the segment on the card, S-A2): back to its first section.
  void _switchDoc(bool privacy) {
    if (privacy == _privacy) return;
    setState(() {
      _privacy = privacy;
      _active = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _load(context.read<AboutTermsProvider>());
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    showAppNotice('legal_link_copied'.tr);
  }

  Future<void> _email(String to) async {
    final uri = Uri(scheme: 'mailto', path: to);
    if (await openExternalLink(uri.toString(), allowMail: true, quiet: true)) return;
    await Clipboard.setData(ClipboardData(text: to));
    showAppNotice('legal_email_copied'.tr);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>();
    final p = context.watch<AboutTermsProvider>();
    final doc = _doc(p);
    final docLang = _privacy ? p.privacyLang : p.termsLang;
    final busy = _privacy ? p.isLoadingPrivacy : p.isLoadingTerms;
    if (doc != null && docLang != AppConfig.lang && !busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(p);
      });
    }
    final canAsk = widget.canAsk ?? _assistantAvailable(context);
    final title = _privacy ? 'privacy_policy'.tr : 'terms_of_service'.tr;
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        key: ValueKey(_privacy ? 'terms.privacy' : 'terms'),
        appBar: ScreenAppBar(
          title: title,
          showBack: Navigator.of(context).canPop(), // the public /terms and /privacy links open with nothing behind them
          actions: canAsk && doc != null ? [AskAboutPageAction(onTap: _ask)] : null,
        ),
        child: SafeArea(child: SaHeroPage(area: AppArea.me, kicker: 'sa_legal_kicker'.tr, title: title, child: _body(p, canAsk))),
      ),
    );
  }

  Widget _body(AboutTermsProvider p, bool canAsk) {
    final doc = _doc(p);
    final error = _privacy ? p.privacyError : p.termsError;
    if (doc == null && error == null) return const ReadingSkeleton();
    if (doc == null) {
      return AppEmpty(
        icon: Icons.wifi_off_rounded,
        title: 'reading_error_title'.tr,
        message: error,
        actionLabel: 'about_retry'.tr,
        onAction: () => _load(p, force: true),
      );
    }
    final terms = doc;
    if (terms.sections.isEmpty) {
      return AppEmpty(icon: Icons.description_outlined, title: 'reading_empty_title'.tr, message: 'terms_empty'.tr);
    }
    while (_keys.length < terms.sections.length) {
      _keys.add(GlobalKey());
    }
    return LayoutBuilder(builder: (context, box) => _page(p, terms, box.maxWidth, canAsk));
  }

  /// The privacy / terms segment (redesign Stu1Public?screen=legal): the other document opens in place.
  Widget _docTabs() => AppTabs(
        key: const ValueKey('terms.tabs'),
        expand: true,
        items: [AppTabItem('sa_legal_privacy'.tr), AppTabItem('sa_legal_terms'.tr)],
        index: _privacy ? 0 : 1,
        onChanged: (i) => _switchDoc(i == 0),
      );

  Widget _page(AboutTermsProvider p, TermsPageModel terms, double width, bool canAsk) {
    final c = context.colors;
    final wide = width >= _tocBreakpoint;
    final sections = terms.sections;
    final titles = [for (final s in sections) s.title];
    final showChips = !wide && sections.length >= 6; // a short document reads straight down (S-A2)
    _pinned = showChips ? _chipsHeight : 0;

    // the reading column: centred; on a wide window it shares the centred group with the table of contents
    final group = wide ? math.min(width - 64, _tocWidth + _tocGap + _readingMax) : 0.0;
    final gutter = wide ? (width - group) / 2 : 0.0;
    final side = wide ? 0.0 : math.max(16.0, (width - _readingMax) / 2);
    final padStart = wide ? gutter + _tocWidth + _tocGap : side;
    final padEnd = wide ? gutter : side;

    final meta = terms.meta;
    final updated = meta?.lastUpdated ?? '';
    final version = meta?.version ?? '';
    final minutes = readingMinutes([for (final s in sections) '${s.title} ${s.body}']);
    final intro = terms.intro.isNotEmpty ? terms.intro : (_privacy ? 'privacy_intro'.tr : 'terms_intro'.tr);

    // redesign (S-A2): the intro and the facts in one quiet block under the segment
    final head = ParentComponent(
      featureKey: 'terms.header',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(intro, style: AppType.body(context).copyWith(color: c.textMedium)),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (updated.isNotEmpty) ReadingMetaPill(icon: Icons.update_rounded, label: '${'legal_effective'.tr} $updated'),
          if (version.isNotEmpty) ReadingMetaPill(icon: Icons.tag_rounded, label: '${'about_version'.tr} $version'),
          ReadingMetaPill(icon: Icons.schedule_rounded, label: readingTr('reading_minutes', {'n': minutes})),
        ]),
      ]),
    );

    // every section a row on ONE card: its glyph in the area tint, the title, the text; a hairline between rows
    final rows = ParentComponent(
      featureKey: 'terms.sections',
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _docTabs(),
          AppSpace.gapMd,
          head,
          for (var i = 0; i < sections.length; i++) ...[
            Divider(height: AppSpace.xl, thickness: AppBorder.hairline, color: c.kit.line),
            KeyedSubtree(
              key: _keys[i],
              child: _LegalRow(icon: contentIcon(sections[i].iconName), title: sections[i].title, body: sections[i].body),
            ),
          ],
        ]),
      ),
    );

    final highlights = terms.highlights.isEmpty
        ? null
        : ReadingHighlights(title: 'legal_at_a_glance'.tr, items: terms.highlights);

    final email = terms.contactEmail;
    final footer = ParentComponent(
      featureKey: 'terms.footer',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ReadingNote(
          icon: Icons.verified_user_outlined,
          text: _privacy ? 'privacy_footer'.tr : 'terms_footer'.tr,
          caption: [
            if (updated.isNotEmpty) '${'legal_effective'.tr} $updated',
            if (version.isNotEmpty) '${'about_version'.tr} $version',
          ].join('،  '),
        ),
        const SizedBox(height: 16),
        ReadingLegalActions(
          otherLabel: _privacy ? 'legal_read_terms'.tr : 'legal_read_privacy'.tr,
          otherIcon: _privacy ? Icons.gavel_rounded : Icons.privacy_tip_outlined,
          onOther: () => _switchDoc(!_privacy),
          email: email.isEmpty ? null : email,
          onEmail: email.isEmpty ? null : () => _email(email),
          onCopyLink: terms.url.isEmpty ? null : () => _copyLink(terms.url),
        ),
      ]),
    );

    Widget padded(Widget child, {double top = 0, double bottom = 0}) => SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(padStart, top, padEnd, bottom),
          sliver: SliverToBoxAdapter(child: child),
        );

    final scroll = NotificationListener<UserScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false; // the chips row scrolls sideways
        final open = n.direction != ScrollDirection.reverse;
        if (n.direction != ScrollDirection.idle && open != _chipOpen) setState(() => _chipOpen = open);
        return false;
      },
      child: AppRefresh(
        onRefresh: () => _load(p, force: true),
        edgeOffset: _pinned,
        child: CustomScrollView(
          key: _viewport,
          controller: _scroll,
          slivers: [
            if (showChips)
              SliverPersistentHeader(
                pinned: true,
                delegate: _ChipsHeader(
                  background: c.pinnedBackground,
                  line: c.divider,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: side - 16, end: side - 16),
                    child: ReadingTocChips(titles: titles, active: _active, onTap: _jump),
                  ),
                ),
              ),
            padded(rows, top: AppSpace.md),
            if (highlights != null) padded(highlights, top: AppSpace.lg),
            padded(footer, top: 24, bottom: canAsk && !wide ? 104 : 40),
          ],
        ),
      ),
    );

    if (wide) {
      return Stack(children: [
        Positioned.fill(child: scroll),
        PositionedDirectional(
          start: gutter,
          top: 0,
          bottom: 0,
          width: _tocWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.lg),
            // the side card: the section index
            child: AppCard(
              padding: const EdgeInsets.all(AppSpace.sm),
              child: ReadingTocList(
                titles: titles,
                active: _active,
                onTap: _jump,
                footer: canAsk ? ReadingAskCard(onAsk: _ask, compact: true) : null,
              ),
            ),
          ),
        ),
      ]);
    }
    if (!canAsk) return scroll;
    return Stack(children: [
      Positioned.fill(child: scroll),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: AskAboutPageChip(onTap: _ask, expanded: _chipOpen),
      ),
    ]);
  }
}

/// One section of a legal document: its glyph in the area tint, the title and the text (reading typography).
class _LegalRow extends StatelessWidget {
  const _LegalRow({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title, body;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppIconBox(icon: icon),
      const SizedBox(width: AppSpace.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: AppType.section(context))),
          if (body.trim().isNotEmpty) ...[
            AppSpace.gapXs,
            ReadingBody(text: body),
          ],
        ]),
      ),
    ]);
  }
}

class _ChipsHeader extends SliverPersistentHeaderDelegate {
  _ChipsHeader({required this.child, required this.background, required this.line});

  final Widget child;
  final Color background;
  final Color line;

  @override
  double get minExtent => _chipsHeight;

  @override
  double get maxExtent => _chipsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          border: overlapsContent || shrinkOffset > 0 ? Border(bottom: BorderSide(color: line)) : null,
        ),
        child: child,
      );

  @override
  bool shouldRebuild(covariant _ChipsHeader old) => true;
}

// ══════════════════════════════════════════════════════════════════════════════
//  About
// ══════════════════════════════════════════════════════════════════════════════

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key, this.canAsk});

  /// Offer the assistant in Contact & support (null = decide from the session and the kill switch).
  final bool? canAsk;

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AboutTermsProvider>().loadAbout(context);
      AppIdentity.instance.refresh(); // newest version info
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LangProvider>(); // re-translate when the language changes
    final p = context.watch<AboutTermsProvider>();
    if (p.about != null && p.aboutLang != AppConfig.lang && !p.isLoadingAbout) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) p.loadAbout(context);
      });
    }
    return Directionality(
      textDirection: Helpers.pageDirection,
      child: BasePage(
        key: const ValueKey('about'),
        appBar: ScreenAppBar(title: 'about_us'.tr, showBack: Navigator.of(context).canPop()),
        child: SafeArea(child: _body(p)),
      ),
    );
  }

  Widget _body(AboutTermsProvider p) {
    if (p.about == null && p.aboutError == null) return const ReadingSkeleton(chips: false);
    if (p.about == null) {
      return AppEmpty(
        icon: Icons.wifi_off_rounded,
        title: 'reading_error_title'.tr,
        message: p.aboutError,
        actionLabel: 'about_retry'.tr,
        onAction: () => p.loadAbout(context, forceRefresh: true),
      );
    }
    final about = p.about!;
    final canAsk = widget.canAsk ?? _assistantAvailable(context);
    final c = context.colors;

    Widget block(String key, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: ParentComponent(featureKey: key, child: child),
        );
    Widget titled(String title, String sub, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [AboutSectionTitle(title: title, sub: sub), const SizedBox(height: 16), child],
        );

    return AppRefresh(
      onRefresh: () async {
        await p.loadAbout(context, forceRefresh: true);
        await AppIdentity.instance.refresh();
      },
      child: ListenableBuilder(
        listenable: AppIdentity.instance,
        builder: (context, _) {
          final id = AppIdentity.instance;
          final info = about.info;
          final name = (info?.name ?? '').isNotEmpty ? info!.name : id.name;
          return LayoutBuilder(builder: (context, box) {
            final side = math.max(16.0, (box.maxWidth - _readingMax) / 2);
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 8, side, 40),
              children: [
                block(
                  'about.hero',
                  AboutHeroCard(
                    name: name,
                    tagline: info?.tagline,
                    logoUrl: info?.logoUrl,
                    version: id.installedVersion,
                    updateAvailable: id.updateAvailable,
                  ),
                ),
                if (about.stats.isNotEmpty) block('about.stats', AboutStatsCard(stats: about.stats)),
                if ((info?.mission ?? '').isNotEmpty)
                  block('about.mission',
                      titled('about_mission'.tr, 'about_mission_sub'.tr, AboutMissionQuote(mission: info!.mission!))),
                if (about.features.isNotEmpty)
                  block('about.features',
                      titled('about_features'.tr, 'about_features_sub'.tr, AboutFeatureGrid(features: about.features))),
                if (about.team.isNotEmpty)
                  block('about.team',
                      titled('about_team'.tr, 'about_team_sub'.tr, AboutTeamRow(team: about.team, onZoom: _zoom))),
                block(
                  'about.contact',
                  AboutSupportCard(
                    contacts: about.contacts,
                    onOpen: _open,
                    onCopy: (k) => _copy(k.value),
                    onAsk: canAsk ? AppAssistant.openPanel : null,
                    version: id.versionLabel,
                    latest: id.latest?.version,
                    updateAvailable: id.updateAvailable,
                    notes: id.latest?.notes ?? '',
                  ),
                ),
                if (name.isNotEmpty)
                  Text('© ${DateTime.now().year} $name',
                      textAlign: TextAlign.center, style: appText(12.5, w: FontWeight.w500, c: c.textLight, h: 1.4)),
                // D-145: the developer, under the copyright line
                Text('about_developed_by'.tr,
                    key: const ValueKey('about.developer'),
                    textAlign: TextAlign.center, style: appText(12.5, w: FontWeight.w500, c: c.textLight, h: 1.4)),
              ],
            );
          });
        },
      ),
    );
  }

  /// What a tap on a contact opens (null = nothing to open, just copy).
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

  Future<void> _open(ContactInfoModel k) async {
    final uri = _uri(k);
    // email and phone contacts open the mail / phone app; anything refused or unopened falls through → copy
    if (uri != null && await openExternalLink(uri.toString(), allowMail: true, allowTel: true, quiet: true)) return;
    await _copy(k.value);
  }

  Future<void> _copy(String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    showAppNotice('about_copied'.tr);
  }

  void _zoom(TeamMemberModel m) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(alignment: AlignmentDirectional.topEnd, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(ctx.colors.radiusLarge),
            child: InteractiveViewer(child: AppNetworkImage(url: m.imageUrl!, fit: BoxFit.contain)),
          ),
          IconButton.filled(
            tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
            style: IconButton.styleFrom(backgroundColor: ctx.colors.heroShade.withValues(alpha: 0.54)),
            icon: Icon(Icons.close_rounded, color: ctx.colors.onHero),
            onPressed: () => Navigator.pop(ctx),
          ),
        ]),
      ),
    );
  }
}
