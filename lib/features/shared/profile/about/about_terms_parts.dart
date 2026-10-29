// The reading pages' parts (Terms · Privacy · About, D-084) — plain values only, so the layout harness can pump them
// (test/ui/reading_pages_layout_test.dart) and the visual renders draw them with realistic data
// (test/visual/reading_pages_golden_test.dart).
//
//   readingBlocks(body)      pure: a section body → paragraphs / bullets / numbered steps (unit-tested)
//   readingMinutes(texts)    pure: minutes to read (≈ 200 words a minute, at least 1)
//   ReadingHero              the calm page header: icon tile, title, intro, meta pills (updated · version · read time)
//   ReadingMetaPill          one meta pill
//   ReadingTocChips          the phone's sticky section chips (scroll-spy highlight)
//   ReadingTocList           the wide layout's "On this page" column
//   ReadingSectionCard       one numbered section: icon, title, body in reading typography
//   ReadingBody              the body blocks (respects DisplaySettings reading spacing through appText)
//   ReadingNote              the quiet closing note (agreement, last update)
//   ReadingAskCard           "Something unclear? Ask the assistant" card
//   AskAboutPageChip         the floating "Ask about this page" pill (collapses to the bot disc while scrolling down)
//   AskAboutPageAction       the app-bar bot button
//   ReadingSkeleton          the page's shape while it loads (hero + chips + section cards)
//   AboutHeroCard · AboutStatsCard · AboutMissionQuote · AboutFeatureGrid · AboutTeamRow · AboutSupportCard
//   contentIcon(name)        the admin's icon names → icons
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_charts.dart' show appInk;
import 'package:flutter_education_app/design/app_kit.dart' show appText, AppShimmer, AppSkeletonBox;
import 'package:flutter_education_app/utils/widget/app_network_image.dart';

import 'about_terms_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pure helpers
// ─────────────────────────────────────────────────────────────────────────────

enum ReadingBlockKind { paragraph, bullet, numbered }

/// One block of a section body.
@immutable
class ReadingBlock {
  const ReadingBlock(this.kind, this.text, {this.number});
  final ReadingBlockKind kind;
  final String text;

  /// The step's own label ("1", "٢") for [ReadingBlockKind.numbered].
  final String? number;

  @override
  bool operator ==(Object other) =>
      other is ReadingBlock && other.kind == kind && other.text == text && other.number == number;

  @override
  int get hashCode => Object.hash(kind, text, number);

  @override
  String toString() => '$kind${number == null ? '' : '($number)'}: $text';
}

final _bulletRe = RegExp(r'^[-•*·▪●–]\s+');
final _numberRe = RegExp(r'^([0-9٠-٩]{1,3})[.)\-:،]\s*');

/// A section body as the admin typed it → blocks: lines starting with "-", "•", "*" … are bullets, "1." / "١)" are
/// numbered steps, other lines run together into paragraphs (a blank line starts a new one; a single line break
/// inside a paragraph is kept).
List<ReadingBlock> readingBlocks(String body) {
  final out = <ReadingBlock>[];
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    out.add(ReadingBlock(ReadingBlockKind.paragraph, para.join('\n')));
    para.clear();
  }

  for (final raw in body.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      flush();
      continue;
    }
    final b = _bulletRe.firstMatch(line);
    if (b != null) {
      flush();
      final t = line.substring(b.end).trim();
      if (t.isNotEmpty) out.add(ReadingBlock(ReadingBlockKind.bullet, t));
      continue;
    }
    final n = _numberRe.firstMatch(line);
    if (n != null && line.length > n.end) {
      flush();
      out.add(ReadingBlock(ReadingBlockKind.numbered, line.substring(n.end).trim(), number: n.group(1)));
      continue;
    }
    para.add(line);
  }
  flush();
  return out;
}

/// Minutes to read [texts] at about 200 words a minute (at least 1).
int readingMinutes(Iterable<String> texts) {
  var words = 0;
  for (final t in texts) {
    words += t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return (words / 200).ceil().clamp(1, 999);
}

/// translate + fill {placeholders}
String readingTr(String key, Map<String, Object> params) =>
    params.entries.fold(key.tr, (t, e) => t.replaceAll('{${e.key}}', '${e.value}'));

/// "1" → "01" (latin digits; the number is a label, not a quantity).
String readingNumber(int n) => n < 10 ? '0$n' : '$n';

/// Backend `icon_name` → icon (every key of the admin's content-page picker, kContentIcons, plus older names).
IconData contentIcon(String? name) => _iconMap[name] ?? Icons.article_outlined;

const _iconMap = <String, IconData>{
  'play_circle_outline': Icons.play_circle_outline_rounded,
  'people_alt': Icons.people_alt_outlined,
  'person': Icons.person_outline_rounded,
  'payment': Icons.payments_outlined,
  'shield': Icons.shield_outlined,
  'block': Icons.block_outlined,
  'update': Icons.update_rounded,
  'book': Icons.menu_book_outlined,
  'email': Icons.email_outlined,
  'phone': Icons.phone_outlined,
  'location_on': Icons.location_on_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'info': Icons.info_outline_rounded,
  'notifications': Icons.notifications_outlined,
  'help': Icons.help_outline_rounded,
  'bug_report': Icons.bug_report_outlined,
  'copyright': Icons.copyright_rounded,
  'star': Icons.star_outline_rounded,
  'rocket_launch': Icons.rocket_launch_outlined,
  'lightbulb': Icons.lightbulb_outline_rounded,
  'school': Icons.school_outlined,
  'groups': Icons.groups_outlined,
  'verified': Icons.verified_outlined,
  'security': Icons.security_rounded,
  'support_agent': Icons.support_agent_rounded,
  'devices': Icons.devices_rounded,
  'speed': Icons.speed_rounded,
  'workspace_premium': Icons.workspace_premium_outlined,
  'favorite': Icons.favorite_outline_rounded,
  'insights': Icons.insights_rounded,
  'language': Icons.language_rounded,
  'website': Icons.language_rounded,
  'whatsapp': Icons.chat_outlined,
  'menu_book': Icons.menu_book_outlined,
  'quiz': Icons.quiz_outlined,
  'play_circle': Icons.play_circle_outline_rounded,
  'emoji_events': Icons.emoji_events_outlined,
  'bolt': Icons.bolt_rounded,
  'public': Icons.public_rounded,
  'schedule': Icons.schedule_rounded,
  'payments': Icons.payments_outlined,
  'gavel': Icons.gavel_rounded,
  'description': Icons.description_outlined,
  'policy': Icons.policy_outlined,
  'privacy_tip': Icons.privacy_tip_outlined,
  'lock': Icons.lock_outline_rounded,
  'handshake': Icons.handshake_outlined,
  'gpp_good': Icons.gpp_good_outlined,
  'flag': Icons.flag_outlined,
};

// ─────────────────────────────────────────────────────────────────────────────
// Shared surfaces
// ─────────────────────────────────────────────────────────────────────────────

/// The reading pages' card: card colour, theme radius, hairline, soft shadow.
class ReadingSurface extends StatelessWidget {
  const ReadingSurface({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.tint});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// A soft wash of this colour from the top-start corner (the hero).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = BorderRadius.circular(c.radiusLarge - 4);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: r,
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
        gradient: tint == null
            ? null
            : LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [Color.alphaBlend(tint!.withValues(alpha: c.isDark ? 0.16 : 0.07), c.cardBg), c.cardBg],
                stops: const [0, 0.75],
              ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A rounded tile with the brand gradient and an on-hero icon (the hero's mark).
class ReadingIconTile extends StatelessWidget {
  const ReadingIconTile({super.key, required this.icon, this.size = 52});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.heroEnd(c.primary, 0.3)],
        ),
        boxShadow: [
          BoxShadow(color: c.primary.withValues(alpha: c.isDark ? 0.30 : 0.24), blurRadius: 14, offset: const Offset(0, 6)),
        ],
      ),
      child: Icon(icon, color: c.onHero, size: size * 0.48),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero
// ─────────────────────────────────────────────────────────────────────────────

/// One fact under the hero title (updated · version · read time · sections).
class ReadingMetaPill extends StatelessWidget {
  const ReadingMetaPill({super.key, required this.icon, required this.label, this.tone});

  final IconData icon;
  final String label;

  /// A coloured pill (an update is available); default neutral.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final col = tone;
    final ink = col == null ? appInk(context, c.textMedium) : appInk(context, col);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: col == null ? c.inputBg : col.withValues(alpha: c.isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: col == null ? c.divider : col.withValues(alpha: 0.30)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: col == null ? c.primary : ink),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: ink, h: 1.2)),
        ),
      ]),
    );
  }
}

/// The calm page header: the mark (an icon tile, or [leading]), title, intro and meta pills on a softly tinted card.
class ReadingHero extends StatelessWidget {
  const ReadingHero({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.eyebrow,
    this.intro,
    this.meta = const [],
  });

  final String title;
  final IconData? icon;

  /// Replaces the icon tile (About: the app's logo).
  final Widget? leading;
  final String? eyebrow;
  final String? intro;
  final List<Widget> meta;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 560;
      return ReadingSurface(
        tint: c.primary,
        padding: EdgeInsets.all(roomy ? 32 : 24),
        child: Stack(clipBehavior: Clip.none, children: [
          // a faint watermark of the mark on the end side
          if (icon != null)
            PositionedDirectional(
              end: roomy ? -8 : -16,
              top: roomy ? -12 : -16,
              child: ExcludeSemantics(
                child: Icon(icon, size: roomy ? 132 : 104, color: c.primary.withValues(alpha: c.isDark ? 0.08 : 0.06)),
              ),
            ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading ?? ReadingIconTile(icon: icon ?? Icons.article_outlined),
            const SizedBox(height: 24),
            if ((eyebrow ?? '').isNotEmpty) ...[
              Text(eyebrow!,
                  style: appText(12.5, w: FontWeight.w700, c: appInk(context, c.primary), h: 1.3)),
              const SizedBox(height: 8),
            ],
            Text(title, style: appText(roomy ? 30 : 26, w: FontWeight.w800, c: c.textDark, h: 1.2)),
            if ((intro ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Text(intro!, style: appText(15, w: FontWeight.w400, c: c.textMedium, h: 1.6)),
              ),
            ],
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(spacing: 8, runSpacing: 8, children: meta),
            ],
          ]),
        ]),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table of contents
// ─────────────────────────────────────────────────────────────────────────────

/// The phone's section chips (pinned under the app bar): "01 Title", the current one filled.
class ReadingTocChips extends StatefulWidget {
  const ReadingTocChips({super.key, required this.titles, required this.active, required this.onTap});

  final List<String> titles;
  final int active;
  final ValueChanged<int> onTap;

  @override
  State<ReadingTocChips> createState() => _ReadingTocChipsState();
}

class _ReadingTocChipsState extends State<ReadingTocChips> {
  final _keys = <int, GlobalKey>{};
  final _row = ScrollController();

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ReadingTocChips old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      // centre the current chip in THIS row only (Scrollable.ensureVisible would also scroll the page under it)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ro = _keys[widget.active]?.currentContext?.findRenderObject();
        if (ro == null || !mounted || !_row.hasClients) return;
        final viewport = RenderAbstractViewport.maybeOf(ro);
        if (viewport == null) return;
        final target = viewport
            .getOffsetToReveal(ro, 0.5)
            .offset
            .clamp(_row.position.minScrollExtent, _row.position.maxScrollExtent);
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        if (reduce) {
          _row.jumpTo(target);
        } else {
          _row.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 56,
      child: ListView.separated(
        controller: _row,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: widget.titles.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = i == widget.active;
          final ink = on ? c.onHero : appInk(context, c.textMedium);
          return Semantics(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            button: true,
            selected: on,
            child: Material(
              color: on ? c.primary : c.cardBg,
              shape: StadiumBorder(side: BorderSide(color: on ? c.primary : c.divider)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => widget.onTap(i),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240, minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(readingNumber(i + 1),
                          textDirection: TextDirection.ltr,
                          style: appText(12, w: FontWeight.w800, c: on ? c.onHero.withValues(alpha: 0.8) : c.primary, h: 1.1)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(widget.titles[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appText(13, w: on ? FontWeight.w700 : FontWeight.w600, c: ink, h: 1.2)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The wide layout's "On this page" column: a hairline rail, the current entry lit in the primary.
class ReadingTocList extends StatelessWidget {
  const ReadingTocList({super.key, required this.titles, required this.active, required this.onTap, this.footer});

  final List<String> titles;
  final int active;
  final ValueChanged<int> onTap;

  /// Under the list (the "Ask the assistant" card).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(start: 16, bottom: 8),
        child: Text('reading_on_this_page'.tr, style: appText(12.5, w: FontWeight.w700, c: c.textLight, h: 1.3)),
      ),
      for (var i = 0; i < titles.length; i++)
        Semantics(
          button: true,
          selected: i == active,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onTap(i),
            child: Container(
              constraints: const BoxConstraints(minHeight: 40),
              padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: i == active ? c.primary : c.divider, width: i == active ? 2.5 : 1.5),
                ),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 28, // the label sits at the start of its box in both directions (digits read alike)
                  child: Text(readingNumber(i + 1),
                      style: appText(12, w: FontWeight.w800, c: i == active ? appInk(context, c.primary) : c.textLight, h: 1.55)),
                ),
                Expanded(
                  child: Text(titles[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13.5,
                          w: i == active ? FontWeight.w700 : FontWeight.w500,
                          c: i == active ? appInk(context, c.primary) : c.textMedium,
                          h: 1.45)),
                ),
              ]),
            ),
          ),
        ),
      if (footer != null) ...[const SizedBox(height: 24), footer!],
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sections
// ─────────────────────────────────────────────────────────────────────────────

/// A section body in reading typography: 16 px, tall lines (the person's reading spacing on top, via appText),
/// bullets with a primary dot, numbered steps with their label.
class ReadingBody extends StatelessWidget {
  const ReadingBody({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    final style = appText(16, w: FontWeight.w400, c: c.textDark.withValues(alpha: c.isDark ? 0.88 : 0.86), h: ar ? 1.85 : 1.7);
    final blocks = readingBlocks(text);
    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final prev = i == 0 ? null : blocks[i - 1];
      final tight = prev != null && prev.kind != ReadingBlockKind.paragraph && b.kind == prev.kind;
      if (i > 0) children.add(SizedBox(height: tight ? 8 : 16));
      switch (b.kind) {
        case ReadingBlockKind.paragraph:
          children.add(Text(b.text, style: style));
        case ReadingBlockKind.bullet:
          children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: (style.fontSize! * (style.height ?? 1.6)) / 2 - 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(b.text, style: style)),
          ]));
        case ReadingBlockKind.numbered:
          children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 24,
              child: Text('${b.number}.', style: style.copyWith(fontWeight: FontWeight.w700, color: appInk(context, c.primary))),
            ),
            const SizedBox(width: 4),
            Expanded(child: Text(b.text, style: style)),
          ]));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// One numbered section: icon well · "Section 01" · title, then the body.
class ReadingSectionCard extends StatelessWidget {
  const ReadingSectionCard({
    super.key,
    required this.number,
    required this.title,
    required this.body,
    this.icon = Icons.article_outlined,
  });

  final int number;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final roomy = box.maxWidth >= 560;
      return ReadingSurface(
        padding: EdgeInsets.fromLTRB(roomy ? 32 : 20, roomy ? 28 : 20, roomy ? 32 : 20, roomy ? 32 : 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: c.isDark ? 0.20 : 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: appInk(context, c.primary)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${'terms_section'.tr} ${readingNumber(number)}',
                    style: appText(12, w: FontWeight.w600, c: c.textLight, h: 1.3)),
                const SizedBox(height: 4),
                Semantics(
                  header: true,
                  child: Text(title, style: appText(roomy ? 19 : 17.5, w: FontWeight.w700, c: c.textDark, h: 1.35)),
                ),
              ]),
            ),
          ]),
          if (body.trim().isNotEmpty) ...[
            SizedBox(height: roomy ? 24 : 16),
            ReadingBody(text: body),
          ],
        ]),
      );
    });
  }
}

/// The quiet closing note: an icon and a line (the agreement), with an optional small caption under it.
class ReadingNote extends StatelessWidget {
  const ReadingNote({super.key, required this.icon, required this.text, this.caption});

  final IconData icon;
  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: c.isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.success.withValues(alpha: c.isDark ? 0.30 : 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: appInk(context, c.success), size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: appText(14, w: FontWeight.w500, c: c.textDark, h: 1.7)),
            if ((caption ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(caption!, style: appText(12.5, w: FontWeight.w500, c: c.textLight, h: 1.4)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The assistant on the page
// ─────────────────────────────────────────────────────────────────────────────

/// The bot's mark: a small brand-gradient disc with the robot.
class ReadingBotMark extends StatelessWidget {
  const ReadingBotMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [c.primary, c.heroEnd(c.primary, 0.3)],
        ),
      ),
      child: Icon(Icons.smart_toy_rounded, size: size * 0.56, color: c.onHero),
    );
  }
}

/// "Something unclear? Ask the assistant" — a card at the end of the page (and under the wide table of contents).
class ReadingAskCard extends StatelessWidget {
  const ReadingAskCard({super.key, required this.onAsk, this.compact = false});

  final VoidCallback onAsk;

  /// The narrow column beside the wide page: stacked, smaller type.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text('reading_ask_title'.tr, style: appText(compact ? 14 : 15.5, w: FontWeight.w700, c: c.textDark, h: 1.35)),
      const SizedBox(height: 4),
      Text('reading_ask_body'.tr, style: appText(compact ? 12.5 : 13.5, w: FontWeight.w400, c: c.textMedium, h: 1.55)),
    ]);
    final button = FilledButton.icon(
      onPressed: onAsk,
      icon: const Icon(Icons.smart_toy_rounded, size: 18),
      label: Text('assistant_ask_page'.tr, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onHero,
        minimumSize: const Size(48, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: appText(13.5, w: FontWeight.w700, h: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: c.isDark ? 0.14 : 0.05),
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: Border.all(color: c.primary.withValues(alpha: c.isDark ? 0.32 : 0.16)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        final stacked = compact || box.maxWidth < 520;
        if (stacked) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const ReadingBotMark(size: 36),
              const SizedBox(width: 12),
              Expanded(child: text),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: button),
          ]);
        }
        return Row(children: [
          const ReadingBotMark(size: 44),
          const SizedBox(width: 16),
          Expanded(child: text),
          const SizedBox(width: 16),
          button,
        ]);
      }),
    );
  }
}

/// The floating "Ask about this page" pill; [expanded] false shows only the bot disc (while scrolling down).
class AskAboutPageChip extends StatelessWidget {
  const AskAboutPageChip({super.key, required this.onTap, this.expanded = true});

  final VoidCallback onTap;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      button: true,
      label: 'assistant_ask_page_tip'.tr,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: c.primary.withValues(alpha: c.isDark ? 0.34 : 0.20), blurRadius: 20, offset: const Offset(0, 8)),
          ],
        ),
        child: Material(
          color: c.cardBg,
          shape: StadiumBorder(side: BorderSide(color: c.primary.withValues(alpha: c.isDark ? 0.45 : 0.22))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedSize(
                duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: AlignmentDirectional.centerStart,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const ReadingBotMark(size: 36),
                  if (expanded) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text('assistant_ask_page'.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appText(14, w: FontWeight.w700, c: c.textDark, h: 1.2)),
                    ),
                    const SizedBox(width: 10),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The app-bar bot button: opens the assistant about this page.
class AskAboutPageAction extends StatelessWidget {
  const AskAboutPageAction({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Tooltip(
        message: 'assistant_ask_page_tip'.tr,
        child: Semantics(
          button: true,
          label: 'assistant_ask_page_tip'.tr,
          excludeSemantics: true,
          child: Material(
            color: c.primary.withValues(alpha: c.isDark ? 0.20 : 0.09),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 44,
                child: Icon(Icons.smart_toy_rounded, size: 22, color: appInk(context, c.primary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Loading
// ─────────────────────────────────────────────────────────────────────────────

/// The page's shape while it loads: the hero, the chips and three section cards — the page does not jump.
class ReadingSkeleton extends StatelessWidget {
  const ReadingSkeleton({super.key, this.chips = true});

  final bool chips;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget card(double h, List<Widget> lines) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.cardBg,
            borderRadius: BorderRadius.circular(c.radiusLarge - 4),
            border: Border.all(color: c.divider),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
        );
    return AppShimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(children: [
              card(0, const [
                AppSkeletonBox(width: 52, height: 52, radius: 16),
                SizedBox(height: 24),
                AppSkeletonBox(width: 220, height: 22),
                SizedBox(height: 12),
                AppSkeletonBox(height: 12),
                SizedBox(height: 8),
                AppSkeletonBox(width: 200, height: 12),
                SizedBox(height: 24),
                Row(children: [
                  AppSkeletonBox(width: 110, height: 28, radius: 14),
                  SizedBox(width: 8),
                  AppSkeletonBox(width: 90, height: 28, radius: 14),
                ]),
              ]),
              if (chips) ...[
                const SizedBox(height: 16),
                const Row(children: [
                  AppSkeletonBox(width: 120, height: 36, radius: 18),
                  SizedBox(width: 8),
                  AppSkeletonBox(width: 96, height: 36, radius: 18),
                  SizedBox(width: 8),
                  Expanded(child: AppSkeletonBox(height: 36, radius: 18)),
                ]),
              ],
              for (var i = 0; i < 3; i++) ...[
                const SizedBox(height: 16),
                card(0, [
                  const Row(children: [
                    AppSkeletonBox(width: 40, height: 40, radius: 12),
                    SizedBox(width: 16),
                    AppSkeletonBox(width: 160, height: 16),
                  ]),
                  const SizedBox(height: 20),
                  const AppSkeletonBox(height: 12),
                  const SizedBox(height: 10),
                  const AppSkeletonBox(height: 12),
                  const SizedBox(height: 10),
                  AppSkeletonBox(width: 140.0 + i * 40, height: 12),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// About
// ─────────────────────────────────────────────────────────────────────────────

/// The app's logo on a light rounded tile (the About hero's mark).
class AboutLogoTile extends StatelessWidget {
  const AboutLogoTile({super.key, this.logoUrl, this.size = 64});

  final String? logoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final url = logoUrl ?? '';
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: c.onHero, // light in both modes: admins' logos are drawn for a light ground
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: c.divider),
        boxShadow: c.cardShadow,
      ),
      child: url.isEmpty
          ? Icon(Icons.school_rounded, size: size * 0.5, color: c.primary)
          : ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.16),
              child: AppNetworkImage(url: url, fit: BoxFit.contain),
            ),
    );
  }
}

/// The About hero: logo tile, the app's name, tagline, version (and "update available").
class AboutHeroCard extends StatelessWidget {
  const AboutHeroCard({
    super.key,
    required this.name,
    this.tagline,
    this.logoUrl,
    this.version = '',
    this.updateAvailable = false,
  });

  final String name;
  final String? tagline;
  final String? logoUrl;
  final String version;
  final bool updateAvailable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ReadingHero(
      leading: AboutLogoTile(logoUrl: logoUrl),
      eyebrow: 'about_us'.tr,
      title: name,
      intro: tagline,
      meta: [
        if (version.isNotEmpty) ReadingMetaPill(icon: Icons.tag_rounded, label: '${'about_version'.tr} $version'),
        if (updateAvailable)
          ReadingMetaPill(icon: Icons.system_update_rounded, label: 'about_update_available'.tr, tone: c.warning),
      ],
    );
  }
}

/// A section heading inside the About page.
class AboutSectionTitle extends StatelessWidget {
  const AboutSectionTitle({super.key, required this.title, this.sub});

  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      header: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: appText(19, w: FontWeight.w800, c: c.textDark, h: 1.3)),
        if ((sub ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(sub!, style: appText(13.5, w: FontWeight.w400, c: c.textMedium, h: 1.5)),
        ],
      ]),
    );
  }
}

/// The figures (students, courses …) in one card, separated by hairlines.
class AboutStatsCard extends StatelessWidget {
  const AboutStatsCard({super.key, required this.stats});

  final List<AppStatModel> stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 560 ? stats.length.clamp(1, 4) : 2;
      final rows = <List<AppStatModel>>[];
      for (var i = 0; i < stats.length; i += cols) {
        rows.add(stats.skip(i).take(cols).toList());
      }
      Widget cell(AppStatModel st) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(st.value,
                      style: appText(28, w: FontWeight.w800, c: appInk(context, c.primary), h: 1.15)),
                ),
                const SizedBox(height: 8),
                Text(st.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(13, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
              ]),
            ),
          );
      return ReadingSurface(
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

/// The mission as a pull quote: a primary rule on the start side, larger calm type.
class AboutMissionQuote extends StatelessWidget {
  const AboutMissionQuote({super.key, required this.mission});

  final String mission;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = AppConfig.lang == 'ar';
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: c.isDark ? 0.12 : 0.05),
        borderRadius: BorderRadius.circular(c.radiusMedium),
        border: BorderDirectional(start: BorderSide(color: c.primary, width: 3)),
      ),
      child: Text(mission, style: appText(17, w: FontWeight.w500, c: c.textDark, h: ar ? 1.85 : 1.6)),
    );
  }
}

/// The features as small cards in a grid (2 columns on a phone, 3 wide).
class AboutFeatureGrid extends StatelessWidget {
  const AboutFeatureGrid({super.key, required this.features});

  final List<AppFeatureModel> features;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, box) {
      const gap = 16.0;
      final cols = box.maxWidth > 560 ? 3 : (box.maxWidth < 300 ? 1 : 2);
      Widget card(AppFeatureModel f) => ReadingSurface(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: c.isDark ? 0.20 : 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(contentIcon(f.iconName), size: 20, color: appInk(context, c.primary)),
                ),
                const SizedBox(height: 16),
                Text(f.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(14.5, w: FontWeight.w700, c: c.textDark, h: 1.35)),
                if ((f.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(f.description!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.55)),
                ],
              ]),
            );
      // rows of equal-height cards; a last row that is not full keeps the column width
      return Column(children: [
        for (var i = 0; i < features.length; i += cols) ...[
          if (i > 0) const SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var j = 0; j < cols; j++) ...[
                if (j > 0) const SizedBox(width: gap),
                Expanded(child: i + j < features.length ? card(features[i + j]) : const SizedBox()),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}

/// The team as a horizontal row of cards (photo, emoji or initial).
class AboutTeamRow extends StatelessWidget {
  const AboutTeamRow({super.key, required this.team, this.onZoom});

  final List<TeamMemberModel> team;

  /// A tap on a photo (zoom); null = no zoom.
  final ValueChanged<TeamMemberModel>? onZoom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      // the avatar and padding are fixed, the two text lines grow with the text size
      height: 124 + MediaQuery.textScalerOf(context).scale(72),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: team.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, i) {
          final m = team[i];
          final photo = (m.imageUrl ?? '').isNotEmpty;
          final avatar = Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary.withValues(alpha: c.isDark ? 0.20 : 0.09),
              border: Border.all(color: c.divider),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: photo
                ? AppNetworkImage(url: m.imageUrl!, width: 76, height: 76, fit: BoxFit.cover)
                : (m.emoji ?? '').isNotEmpty
                    ? Text(m.emoji!, style: appText(34, h: 1.1))
                    : Text(m.name.isNotEmpty ? m.name.characters.first.toUpperCase() : '?',
                        style: appText(28, w: FontWeight.w700, c: appInk(context, c.primary), h: 1.1)),
          );
          return SizedBox(
            width: 152,
            child: ReadingSurface(
              padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                GestureDetector(onTap: photo && onZoom != null ? () => onZoom!(m) : null, child: avatar),
                const SizedBox(height: 16),
                Text(m.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appText(14, w: FontWeight.w700, c: c.textDark, h: 1.3)),
                const SizedBox(height: 4),
                Text(m.role,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: appText(12.5, w: FontWeight.w500, c: c.textMedium, h: 1.35)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Icon for a contact type.
IconData aboutContactIcon(ContactInfoModel k) =>
    const <String, IconData>{
      'email': Icons.email_outlined,
      'phone': Icons.phone_outlined,
      'address': Icons.location_on_outlined,
      'website': Icons.language_rounded,
      'whatsapp': Icons.chat_outlined,
      'telegram': Icons.send_rounded,
      'facebook': Icons.facebook_rounded,
      'instagram': Icons.camera_alt_outlined,
      'youtube': Icons.smart_display_outlined,
    }[k.type] ??
    (k.iconName != null ? contentIcon(k.iconName) : Icons.link_rounded);

/// Contact & support: the ways to reach the team, the assistant, and the app's version (with "update available"
/// and its release notes).
class AboutSupportCard extends StatelessWidget {
  const AboutSupportCard({
    super.key,
    required this.contacts,
    required this.onOpen,
    required this.onCopy,
    this.onAsk,
    this.version = '',
    this.latest,
    this.updateAvailable = false,
    this.notes = '',
  });

  final List<ContactInfoModel> contacts;
  final ValueChanged<ContactInfoModel> onOpen;
  final ValueChanged<ContactInfoModel> onCopy;

  /// Opens the app assistant (null = not available: guest, kill switch).
  final VoidCallback? onAsk;
  final String version;
  final String? latest;
  final bool updateAvailable;
  final String notes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget well(IconData icon, Color color) => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: c.isDark ? 0.20 : 0.09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: appInk(context, color)),
        );
    Widget row({required Widget lead, required String label, required String value, VoidCallback? onTap, VoidCallback? onLong, Widget? trailing, TextDirection? valueDir}) =>
        InkWell(
          onTap: onTap,
          onLongPress: onLong,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              lead,
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: appText(12.5, w: FontWeight.w500, c: c.textLight, h: 1.3)),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: valueDir,
                      style: appText(14.5, w: FontWeight.w600, c: c.textDark, h: 1.35)),
                ]),
              ),
              ?trailing,
            ]),
          ),
        );
    final versionColor = updateAvailable ? c.warning : c.success;
    final rows = <Widget>[
      for (final k in contacts)
        row(
          lead: well(aboutContactIcon(k), c.primary),
          label: (k.label ?? '').isNotEmpty ? k.label! : 'about_type_${k.type}'.tr,
          value: k.value,
          valueDir: k.type == 'address' ? null : TextDirection.ltr,
          onTap: () => onOpen(k),
          onLong: () => onCopy(k),
          trailing: IconButton(
            tooltip: 'about_copy'.tr,
            icon: Icon(Icons.copy_rounded, size: 18, color: c.textLight),
            onPressed: () => onCopy(k),
          ),
        ),
      if (onAsk != null)
        row(
          lead: const ReadingBotMark(size: 40),
          label: 'about_ask_assistant_sub'.tr,
          value: 'about_ask_assistant'.tr,
          onTap: onAsk,
          trailing: Icon(Icons.chevron_right_rounded, color: c.textLight),
        ),
      if (version.isNotEmpty || latest != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              well(updateAvailable ? Icons.system_update_rounded : Icons.verified_rounded, versionColor),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('about_this_app'.tr, style: appText(12.5, w: FontWeight.w500, c: c.textLight, h: 1.3)),
                  const SizedBox(height: 2),
                  Text(updateAvailable ? 'about_update_available_long'.tr : 'about_up_to_date'.tr,
                      style: appText(14, w: FontWeight.w600, c: c.textDark, h: 1.4)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 56),
              child: Column(children: [
                if (version.isNotEmpty) _VersionLine(label: 'about_installed_version'.tr, value: version),
                if (latest != null) _VersionLine(label: 'about_latest_version'.tr, value: latest!),
                if (updateAvailable && notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: versionColor.withValues(alpha: c.isDark ? 0.14 : 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('about_whats_new'.tr, style: appText(12.5, w: FontWeight.w700, c: appInk(context, versionColor), h: 1.3)),
                      const SizedBox(height: 4),
                      Text(notes, style: appText(13, w: FontWeight.w400, c: c.textMedium, h: 1.6)),
                    ]),
                  ),
                ],
              ]),
            ),
          ]),
        ),
    ];
    return ReadingSurface(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: AboutSectionTitle(title: 'about_support'.tr, sub: contacts.isEmpty ? null : 'about_contact_hint'.tr),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 76, endIndent: 20, color: c.divider),
          rows[i],
        ],
      ]),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: appText(13, w: FontWeight.w500, c: c.textMedium, h: 1.3))),
        Text(value, textDirection: TextDirection.ltr, style: appText(13.5, w: FontWeight.w700, c: c.textDark, h: 1.3)),
      ]),
    );
  }
}
