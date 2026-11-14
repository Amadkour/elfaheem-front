// The editorial chat's small parts (Warm Editorial theme, .interface-design/system.md), presentational: plain values
// and callbacks, run under the layout harness.
//   [RagAssistantMark]   the assistant's mark: the sparkle in emerald ink on the emerald tint (or a paper disc on a block)
//   [RagPromptList]      questions to tap (the empty chat's starters, an answer's follow-ups): rows parted by warm
//                        hairlines, two lines each, the outward arrow at the reading end
//   [RagSources]         an answer's sources as paper chips under a hairline label; a chip opens its quote under the
//                        row (one at a time, the height glides on AppEase.out), with the page link when it has one
//   [RagAnswerArrival]   the checked answer settles in once when it takes the stage trail's place (never on history)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_icons.dart' show DirIcons;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart';
import 'package:flutter_education_app/utils/widget/app_navigator.dart';

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/rag/rag_chat.dart';

/// The assistant's mark: the sparkle in emerald ink inside a circle of [size] — the emerald tint on the canvas, a
/// paper disc with a hairline on a tinted block ([onBlock]). Decorative: excluded from semantics.
class RagAssistantMark extends StatelessWidget {
  const RagAssistantMark({super.key, this.size = AppIconSize.xl, this.onBlock = false});

  final double size;
  final bool onBlock;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final well = onBlock ? c.cardBg : Color.alphaBlend(c.primaryTint, c.background);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: well,
            shape: BoxShape.circle,
            border: onBlock ? Border.all(color: c.divider, width: AppBorder.hairline) : null,
          ),
          child: Icon(Icons.auto_awesome_rounded, size: size / 2, color: appInk(context, c.primary)),
        ),
      ),
    );
  }
}

/// Questions to tap. [card]: on one paper card (the empty chat's starters); else bare rows under an answer (its
/// follow-ups). Each row is a 48 px target with two lines of text; [icon] leads it (default: a speech bubble).
class RagPromptList extends StatelessWidget {
  const RagPromptList({super.key, required this.prompts, required this.onPick, this.card = true, this.icon});

  final List<String> prompts;
  final ValueChanged<String> onPick;
  final bool card;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (prompts.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[
      for (var i = 0; i < prompts.length; i++) ...[
        if (i > 0)
          Divider(
            height: AppBorder.hairline,
            thickness: AppBorder.hairline,
            indent: card ? AppSpace.md : 0,
            endIndent: card ? AppSpace.md : 0,
            color: c.divider,
          ),
        _PromptRow(text: prompts[i], icon: icon, inset: card, onTap: () => onPick(prompts[i])),
      ],
    ];
    final column = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
    if (!card) return column;
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: column,
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.text, required this.onTap, required this.inset, this.icon});

  final String text;
  final VoidCallback onTap;
  final bool inset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: inset ? null : AppRadius.chipAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTouch.min),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset ? AppSpace.md : AppSpace.xs, vertical: AppSpace.sm),
            child: Row(children: [
              Icon(icon ?? Icons.chat_bubble_outline_rounded, size: AppIconSize.sm, color: c.textLight),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.row(context)),
              ),
              const SizedBox(width: AppSpace.xs),
              Icon(DirIcons.arrowOutward, size: AppIconSize.sm, color: appInk(context, c.primary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A small label with a warm hairline running to the end of the line ("Sources").
class RagRuleLabel extends StatelessWidget {
  const RagRuleLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(children: [
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context))),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Divider(height: AppBorder.hairline, thickness: AppBorder.hairline, color: context.colors.divider)),
      ]),
    );
  }
}

/// The sources an answer quotes: paper chips (the number or the Q&A mark, the title, a chevron) and, under them, the
/// quote of the one opened. [onOpen] reports a chip opened (a learning signal); [onDeepLink] then [onNavigate] run
/// before a curated source opens its page.
class RagSources extends StatefulWidget {
  const RagSources({super.key, required this.citations, this.onNavigate, this.onOpen, this.onDeepLink});

  final List<RagCitation> citations;
  final VoidCallback? onNavigate;
  final ValueChanged<RagCitation>? onOpen;
  final ValueChanged<RagCitation>? onDeepLink;

  @override
  State<RagSources> createState() => _RagSourcesState();
}

class _RagSourcesState extends State<RagSources> {
  int? _open;

  void _toggle(int i) {
    final opening = _open != i;
    setState(() => _open = opening ? i : null);
    if (opening) widget.onOpen?.call(widget.citations[i]);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.citations;
    if (list.isEmpty) return const SizedBox.shrink();
    final open = _open != null && _open! < list.length ? list[_open!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RagRuleLabel(t('المصادر', 'Sources')),
      const SizedBox(height: AppSpace.xxs),
      Wrap(spacing: AppSpace.xs, children: [
        for (var i = 0; i < list.length; i++)
          RagSourceChip(key: ValueKey('rag.source.$i'), citation: list[i], open: _open == i, onTap: () => _toggle(i)),
      ]),
      AnimatedSize(
        duration: AppMotion.of(context).base,
        curve: AppEase.out,
        alignment: AlignmentDirectional.topStart,
        child: open == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: _QuotePanel(
                  key: ValueKey('rag.quote.$_open'),
                  citation: open,
                  onFollow: () {
                    widget.onDeepLink?.call(open);
                    widget.onNavigate?.call();
                  },
                ),
              ),
      ),
    ]);
  }
}

/// One source as a paper chip: a 48 px target around a 40 px chip; [open] draws it in the selection tone.
class RagSourceChip extends StatelessWidget {
  const RagSourceChip({super.key, required this.citation, required this.open, required this.onTap});

  final RagCitation citation;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = appInk(context, c.primary);
    final motion = AppMotion.of(context);
    final fill = open ? Color.alphaBlend(c.primaryTint, c.cardBg) : c.cardBg;
    final mark = AppType.meta(context).copyWith(
        color: ink, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]);
    return Semantics(
      button: true,
      expanded: open,
      label: '${t('المصدر ${citation.n}', 'Source ${citation.n}')}: ${citation.label}',
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTouch.min),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedContainer(
            duration: motion.fast,
            curve: AppEase.out,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AppRadius.chipAll,
              border: Border.all(color: open ? ink : c.divider, width: AppBorder.hairline),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: AppRadius.chipAll,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppTouch.min - AppSpace.xs),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.xs, AppSpace.xxs, AppSpace.xs, AppSpace.xxs),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox.square(
                        dimension: AppIconSize.md,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Color.alphaBlend(c.primaryTint, c.cardBg), shape: BoxShape.circle),
                          child: Center(
                            child: citation.isQa
                                ? Icon(Icons.question_answer_outlined, size: AppIconSize.xs, color: ink)
                                : FittedBox(child: Text('${citation.n}', style: mark)),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(
                        child: Text(citation.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label(context).copyWith(color: c.textDark)),
                      ),
                      const SizedBox(width: AppSpace.xxs),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: motion.fast,
                        curve: AppEase.out,
                        child: Icon(Icons.expand_more_rounded, size: AppIconSize.sm, color: c.textLight),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The opened source: its title, the quoted passage and, for a curated source with a page, the link to it.
class _QuotePanel extends StatelessWidget {
  const _QuotePanel({super.key, required this.citation, required this.onFollow});

  final RagCitation citation;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final module = citation.isQa ? ragDeepLinkModule(citation.deepLink) : null;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.cardAll),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.sm, AppSpace.sm, AppSpace.xs),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.format_quote_rounded, size: AppIconSize.md, color: c.textLight),
            const SizedBox(width: AppSpace.xs),
            Expanded(
              child: Text(citation.label,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: c.textDark, fontWeight: FontWeight.w600)),
            ),
          ]),
          if (citation.quote.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xxs),
            Text('«${citation.quote}»', style: AppType.body(context).copyWith(height: 1.6)),
          ],
          if (module != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton.ghost(
                label: 'rag_open_link'.tr,
                icon: Icons.open_in_new_rounded,
                size: AppButtonSize.sm,
                onPressed: () {
                  onFollow();
                  AppNavigator.openModule(module);
                },
              ),
            )
          else
            const SizedBox(height: AppSpace.xxs),
        ]),
      ),
    );
  }
}

/// The checked answer settles in (a fade and a 6 px rise, 260 ms on [AppEase.out]) when it takes the place of the
/// stage trail on screen — [done] turned true while mounted. An answer already done when it is built (the history)
/// is simply there; Reduce motion: no movement.
class RagAnswerArrival extends StatefulWidget {
  const RagAnswerArrival({super.key, required this.done, required this.child});

  final bool done;
  final Widget child;

  @override
  State<RagAnswerArrival> createState() => _RagAnswerArrivalState();
}

class _RagAnswerArrivalState extends State<RagAnswerArrival> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: 1, duration: const Duration(milliseconds: 260));
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: AppEase.out);

  /// How far the answer rises into place: a short settle, not a slide.
  static const double _rise = AppSpace.xs - AppSpace.xxs / 2;

  @override
  void didUpdateWidget(RagAnswerArrival old) {
    super.didUpdateWidget(old);
    if (!old.done && widget.done && !appMotionOff(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // the same two wrappers at rest and in motion (opacity 1, offset 0): the answer's own state (an open source)
    // survives the end of the entrance
    return FadeTransition(
      opacity: _t,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _rise * (1 - _t.value)), child: child),
      ),
    );
  }
}

/// Where the assistant reads from, one quiet line above the conversation (not a box: it is said once and stays).
class RagScopeNote extends StatelessWidget {
  const RagScopeNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsetsDirectional.only(top: AppSpace.xxs / 2, end: AppSpace.xs),
        child: Icon(Icons.menu_book_rounded, size: AppIconSize.sm, color: c.textLight),
      ),
      Expanded(child: Text(text, style: AppType.meta(context).copyWith(height: 1.5))),
    ]);
  }
}

/// The question box: the warm well with the hint inside, one to four lines as it grows, the send button inside its
/// end (the solid emerald square, a spinner while a question is on its way), on the canvas under a warm hairline.
/// Enter sends (Shift+Enter / Ctrl+Enter follow app_keyboard.dart's rules for a multi-line field).
class RagComposer extends StatelessWidget {
  const RagComposer({super.key, required this.controller, required this.onSend, this.sending = false, this.side = AppSpace.md});

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;

  /// The side padding: the chat column's gutter, so the box lines up with the answers.
  final double side;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = t('اسألني أي شيء…', 'Ask me anything…');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, AppSpace.sm, side, AppSpace.sm),
          child: EnterSubmits(
            onSubmit: onSend,
            child: Semantics(
              container: true,
              label: hint,
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                style: appFieldTextStyle(context),
                decoration: appFieldDecoration(
                  context,
                  hint: hint,
                  suffix: Padding(
                    padding: const EdgeInsetsDirectional.only(end: AppSpace.xxs),
                    child: AppIconButton(
                      icon: Icons.send_rounded,
                      tooltip: t('إرسال', 'Send'),
                      variant: AppIconButtonVariant.filled,
                      busy: sending,
                      onPressed: onSend,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
