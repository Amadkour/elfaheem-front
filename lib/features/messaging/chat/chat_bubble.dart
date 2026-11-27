// lib/features/messaging/chat/chat_bubble.dart — one message, drawn (D-541). Plain values only, like chat_widgets.dart.
//
//   ChatBubble         the row: the bubble, its reply / more buttons on hover, swipe-to-reply on touch, the failed actions
//   ChatMessageText    the words: links, the message's own direction, room left for the time on the last line
//   ChatQuote          the small block of the message a reply answers
//   ChatBubbleBorder   a rounded rectangle with a tail on the last bubble of a run
//   chatBubbleInk      the colours, from the theme, with a contrast floor (the palette comes from the server)
library;

import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_bidi.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import 'package:flutter_education_app/features/messaging/chat/chat_models.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_store.dart';
import 'package:flutter_education_app/features/messaging/chat/chat_widgets.dart';

double chatContrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [tone] made darker (a light [bg]) or lighter (a dark one) just enough to read on [bg]: the brand stays the brand.
Color chatBrandOn(Color bg, Color tone, {double min = 4.5}) {
  if (chatContrast(tone, bg) >= min) return tone;
  final towards = bg.computeLuminance() > 0.4 ? Colors.black : Colors.white;
  for (var t = 0.05; t < 1; t += 0.05) {
    final c = Color.lerp(tone, towards, t)!;
    if (chatContrast(c, bg) >= min) return c;
  }
  return towards;
}

/// [wanted] when it reads on [bg], else whichever of black and white reads best.
Color chatReadableOn(Color bg, Color wanted, {double min = 4.5}) {
  if (chatContrast(wanted, bg) >= min) return wanted;
  return chatContrast(Colors.white, bg) >= chatContrast(const Color(0xFF111418), bg) ? Colors.white : const Color(0xFF111418);
}

/// The background behind the messages: the warm canvas itself (D-610); paper bubbles stand off it by tone and a
/// warm hairline, never by a shadow.
Color chatThreadBg(ThemeConfigProvider c) => c.background;

class ChatBubbleInk {
  const ChatBubbleInk({required this.bg, required this.ink, required this.soft, required this.link, required this.read, required this.tint, this.edge});
  final Color bg, ink, soft, link, read, tint;

  /// The warm hairline around a paper bubble (null: a tinted bubble needs none).
  final Color? edge;
}

/// Own messages are the emerald block tint and the other side paper on a warm hairline (D-610): both carry long
/// reading text in charcoal ink, so neither is a solid block of colour. The ink is checked against the result because
/// the palette is server-driven.
ChatBubbleInk chatBubbleInk(ThemeConfigProvider c, {required bool mine, bool failed = false}) {
  final surface = c.cardBg;
  final bg = failed
      ? Color.alphaBlend(c.danger.withValues(alpha: c.isDark ? 0.28 : 0.11), surface)
      : mine
          ? c.blockEmerald
          : surface;
  final ink = chatReadableOn(bg, c.textDark, min: 7);
  return ChatBubbleInk(
    bg: bg,
    ink: ink,
    soft: ink.withValues(alpha: 0.64),
    link: chatBrandOn(bg, chatInk(c)),
    read: chatBrandOn(bg, chatInk(c), min: 3.2),
    tint: ink.withValues(alpha: c.isDark ? 0.10 : 0.06),
    edge: failed || mine ? null : c.divider,
  );
}

/// A rounded rectangle; [tailRight] (null = none) adds the small tail at that bottom corner.
class ChatBubbleBorder extends ShapeBorder {
  const ChatBubbleBorder({required this.radius, this.tailRight, this.side = BorderSide.none});
  final BorderRadius radius;
  final bool? tailRight;

  /// A hairline drawn along the outline, tail included (paper bubbles on the canvas).
  final BorderSide side;

  static const tail = 6.0;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path()..addRRect(radius.toRRect(rect));
    final right = tailRight;
    if (right == null) return path;
    final y = rect.bottom;
    if (right) {
      final x = rect.right;
      path
        ..moveTo(x, y - 12)
        ..quadraticBezierTo(x + 0.5, y - 3, x + tail, y - 0.5)
        ..quadraticBezierTo(x + tail + 0.8, y, x + tail - 1, y)
        ..lineTo(x - 12, y)
        ..close();
    } else {
      final x = rect.left;
      path
        ..moveTo(x, y - 12)
        ..quadraticBezierTo(x - 0.5, y - 3, x - tail, y - 0.5)
        ..quadraticBezierTo(x - tail - 0.8, y, x - tail + 1, y)
        ..lineTo(x + 12, y)
        ..close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    // the body and the tail as ONE outline, so the hairline runs round the tail instead of across it
    final outline = Path.combine(PathOperation.union, Path()..addRRect(radius.toRRect(rect)), getOuterPath(rect));
    canvas.drawPath(outline, side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) => other is ChatBubbleBorder && other.radius == radius && other.tailRight == tailRight && other.side == side;

  @override
  int get hashCode => Object.hash(radius, tailRight, side);
}

final _urlRe = RegExp(r'''(?:https?://|www\.)[^\s<>"']+''', caseSensitive: false);
const _urlTrail = '.,;:!?)]}،؛؟»';

/// Pure: [text] cut into plain parts (null url) and links, the trailing punctuation left out of a link.
List<({String text, String? url})> chatLinkify(String text) {
  final out = <({String text, String? url})>[];
  var at = 0;
  for (final m in _urlRe.allMatches(text)) {
    var raw = m.group(0)!;
    while (raw.isNotEmpty && _urlTrail.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.isEmpty) continue;
    if (m.start > at) out.add((text: text.substring(at, m.start), url: null));
    out.add((text: raw, url: raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw));
    at = m.start + raw.length;
  }
  if (at < text.length) out.add((text: text.substring(at), url: null));
  return out;
}

/// The words of a message. [reserve] is drawn invisibly after the last word, so a real time stamp laid over the bubble's
/// corner has its own place and the text flows around it (a time that does not fit drops to a line of its own).
class ChatMessageText extends StatefulWidget {
  const ChatMessageText({super.key, required this.text, required this.style, required this.linkColor, this.direction, this.onLink, this.reserve});
  final String text;
  final TextStyle style;
  final Color linkColor;
  final TextDirection? direction;
  final ValueChanged<String>? onLink;
  final Widget? reserve;

  @override
  State<ChatMessageText> createState() => _ChatMessageTextState();
}

class _ChatMessageTextState extends State<ChatMessageText> {
  final List<TapGestureRecognizer> _taps = [];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final link = widget.style.copyWith(color: widget.linkColor, decoration: TextDecoration.underline, decorationColor: widget.linkColor.withValues(alpha: 0.55));
    final spans = <InlineSpan>[
      for (final p in chatLinkify(widget.text))
        if (p.url == null)
          TextSpan(text: p.text)
        else
          TextSpan(
            text: ltrIsolate(p.text),
            style: link,
            mouseCursor: SystemMouseCursors.click,
            recognizer: widget.onLink == null ? null : (TapGestureRecognizer()..onTap = () => widget.onLink!(p.url!)).also(_taps.add),
          ),
      if (widget.reserve != null)
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: ExcludeSemantics(child: SelectionContainer.disabled(child: Visibility.maintain(visible: false, child: Padding(padding: const EdgeInsetsDirectional.only(start: AppSpace.xs), child: widget.reserve!)))),
        ),
    ];
    return Text.rich(TextSpan(style: widget.style, children: spans), textDirection: widget.direction, textAlign: TextAlign.start);
  }
}

extension _Also<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}

/// One line for a message that has no words of its own.
String chatReplyPreview(ChatReplyRef r) {
  if (r.hidden) return 'ow_chat_hidden_quote'.tr;
  if (r.deleted) return 'chat_deleted'.tr;
  if (r.body.trim().isNotEmpty) return r.body.replaceAll('\n', ' ');
  return r.kind == 'image' ? 'chat_photo'.tr : 'chat_file'.tr;
}

/// The small block of what a reply answers. Inside a bubble, and above the composer.
class ChatQuote extends StatelessWidget {
  const ChatQuote({super.key, required this.reply, required this.bar, required this.ink, required this.soft, required this.fill, this.you = false, this.onTap});
  final ChatReplyRef reply;
  final Color bar, ink, soft, fill;
  final bool you;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final who = you ? 'chat_you'.tr : (reply.hidden ? 'ow_a_student'.tr : (reply.senderName ?? ''));
    final preview = chatReplyPreview(reply);
    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(AppRadius.chip - 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 3, color: bar),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xs, 5, AppSpace.sm, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (who.isNotEmpty) Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12, w: FontWeight.w600, c: bar)),
                  Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: contentDirection(preview), style: appText(12.5, w: FontWeight.w400, c: reply.deleted ? soft : ink.withValues(alpha: 0.78))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

const _senderTones = <Color Function(ThemeConfigProvider c)>[_tone0, _tone1, _tone2, _tone3, _tone4];
Color _tone0(ThemeConfigProvider c) => chatInk(c);
Color _tone1(ThemeConfigProvider c) => c.accent2;
Color _tone2(ThemeConfigProvider c) => c.purple;
Color _tone3(ThemeConfigProvider c) => c.success;
Color _tone4(ThemeConfigProvider c) => c.warning;

/// A sender's own colour in a group: stable per person, readable on the bubble.
Color chatSenderTone(ThemeConfigProvider c, int? senderId, Color bg) => chatBrandOn(bg, _senderTones[(senderId ?? 0) % _senderTones.length](c));

/// One message. [showSender] draws the name (groups, the first of a run); [runStart] / [runEnd] say where it sits in a
/// run from one person: a run reads as one block, and its last bubble carries the tail.
class ChatBubble extends StatefulWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.mine,
    this.tick,
    this.showSender = false,
    this.runStart = true,
    this.runEnd = true,
    this.maxWidth = kChatBubbleMaxWidth,
    this.myId,
    this.pointerFirst = false,
    this.highlight = false,
    this.imageOf,
    this.onOpenAttachment,
    this.onReply,
    this.onActions,
    this.onQuoteTap,
    this.onLink,
    this.onRetry,
    this.onDiscard,
  });

  final ChatMessage message;
  final bool mine, showSender, runStart, runEnd;
  final ChatTick? tick;
  final double maxWidth;

  /// Whose quote says "You".
  final int? myId;

  /// A mouse and a keyboard: hover buttons and selectable words, instead of swipe and long press.
  final bool pointerFirst;

  /// A quoted message the person just jumped to.
  final bool highlight;
  final Future<String> Function(ChatAttachment a)? imageOf;
  final void Function(ChatAttachment a)? onOpenAttachment;
  final VoidCallback? onReply;

  /// The message's menu: a rectangle to open it at (a mouse), or null for a sheet (a long press).
  final void Function(Rect? anchor)? onActions;
  final VoidCallback? onQuoteTap;
  final ValueChanged<String>? onLink;
  final VoidCallback? onRetry, onDiscard;

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _hover = false;
  double _drag = 0;
  bool _dragging = false;
  bool _armed = false;

  double get _slot => widget.maxWidth > 500 ? 80.0 : 40.0;
  static const _swipeAt = 58.0;

  void _dragUpdate(DragUpdateDetails d, bool rtl) {
    final next = (_drag + d.delta.dx * (rtl ? -1 : 1)).clamp(0.0, 76.0);
    final armed = next >= _swipeAt;
    if (armed && !_armed) HapticFeedback.selectionClick();
    setState(() {
      _dragging = true;
      _drag = next;
      _armed = armed;
    });
  }

  void _dragEnd() {
    if (_armed) widget.onReply?.call();
    setState(() {
      _dragging = false;
      _drag = 0;
      _armed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = widget.message;
    final mine = widget.mine;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final failed = m.sendState == ChatSendState.failed;
    final colors = chatBubbleInk(c, mine: mine, failed: failed);
    final text = m.deleted ? '' : (m.body ?? '').trim();

    const big = Radius.circular(AppRadius.card - 1);
    const tight = Radius.circular(5);
    const tailCorner = Radius.circular(3);
    final outerTop = widget.runStart ? big : tight;
    final outerBottom = widget.runEnd ? tailCorner : tight;
    final radius = BorderRadiusDirectional.only(
      topStart: mine ? big : outerTop,
      bottomStart: mine ? big : outerBottom,
      topEnd: mine ? outerTop : big,
      bottomEnd: mine ? outerBottom : big,
    ).resolve(Directionality.of(context));
    final tailRight = widget.runEnd ? mine != rtl : null;

    final images = m.deleted ? const <ChatAttachment>[] : m.attachments.where((x) => x.image).toList();
    final files = m.deleted ? const <ChatAttachment>[] : m.attachments.where((x) => !x.image).toList();
    final localImages = m.local.where((f) => f.isImage && f.bytes != null).toList();
    final localFiles = m.local.where((f) => !(f.isImage && f.bytes != null)).toList();
    final hasMedia = images.isNotEmpty || localImages.isNotEmpty;
    final hasFiles = files.isNotEmpty || localFiles.isNotEmpty;

    final meta = _Meta(time: AppTime.time(m.createdAt), soft: colors.soft, read: failed ? c.danger : colors.read, tick: mine ? widget.tick : null);
    final maxW = widget.maxWidth;
    final mediaW = math.min(maxW - 6, 340.0);

    Widget? quote;
    if (m.replyTo != null) {
      quote = ChatQuote(
        reply: m.replyTo!,
        you: widget.myId != null && m.replyTo!.senderId == widget.myId,
        bar: chatSenderTone(c, m.replyTo!.senderId, colors.bg),
        ink: colors.ink,
        soft: colors.soft,
        fill: colors.tint,
        onTap: widget.onQuoteTap,
      );
    }
    Widget? sender;
    if (widget.showSender && !mine) {
      sender = Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(m.senderName ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(12.5, w: FontWeight.w600, c: chatSenderTone(c, m.senderId, colors.bg)))),
        if (m.senderIsTeacher) ...[
          const SizedBox(width: AppSpace.xxs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xxs + 2, vertical: 1),
            decoration: BoxDecoration(color: c.blockSky, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text('chat_teacher'.tr, style: appText(10, w: FontWeight.w600, c: c.blockMuted(c.blockSky))),
          ),
        ],
      ]);
    }

    final textStyle = appText(14.5, w: FontWeight.w400, c: colors.ink, h: 1.38);
    final dir = contentDirection(text) ?? Directionality.of(context);
    Widget words(Widget? reserve) {
      Widget w = ChatMessageText(text: text, style: textStyle, linkColor: colors.link, direction: dir, onLink: widget.onLink, reserve: reserve);
      if (widget.pointerFirst) w = SelectionArea(child: w);
      return w;
    }

    // Time on the side the text ends: a right-to-left message in an English screen ends on the left.
    final textWithMeta = Stack(fit: StackFit.passthrough, children: [
      words(meta),
      Positioned(bottom: 1, left: dir == TextDirection.rtl ? 0 : null, right: dir == TextDirection.rtl ? null : 0, child: meta),
    ]);

    final inset = const EdgeInsets.symmetric(horizontal: 10);
    final List<Widget> rows = [];
    final captionless = hasMedia && text.isEmpty && !hasFiles && quote == null && sender == null;
    if (sender != null) rows.add(Padding(padding: const EdgeInsets.fromLTRB(10, 7, 10, 2), child: sender));
    if (quote != null) rows.add(Padding(padding: EdgeInsets.fromLTRB(5, sender == null ? 5 : 2, 5, hasMedia || hasFiles ? 4 : 1), child: quote));
    if (hasMedia) {
      rows.add(Padding(
        padding: const EdgeInsets.all(3),
        child: Stack(children: [
          _MediaGrid(width: mediaW, attachments: images, local: localImages, busy: m.sendState == ChatSendState.sending, resolve: widget.imageOf, onTap: widget.onOpenAttachment),
          if (captionless)
            PositionedDirectional(
              end: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: _Meta(time: AppTime.time(m.createdAt), soft: Colors.white, read: Colors.white, tick: mine ? widget.tick : null),
              ),
            ),
        ]),
      ));
    }
    if (hasFiles) {
      rows.add(Padding(
        padding: EdgeInsets.fromLTRB(4, quote == null && !hasMedia && sender == null ? 4 : 0, 4, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          for (final a in files) _FilePart(name: a.name, ext: a.ext, size: a.size, colors: colors, onTap: () => widget.onOpenAttachment?.call(a)),
          for (final f in localFiles) _FilePart(name: f.name, ext: f.name.contains('.') ? f.name.split('.').last : '', size: f.size, colors: colors),
        ]),
      ));
    }
    if (m.deleted) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block_rounded, size: AppIconSize.xs, color: colors.soft),
          const SizedBox(width: 5),
          Flexible(child: Text('chat_deleted'.tr, style: appText(13.5, w: FontWeight.w400, c: colors.soft).copyWith(fontStyle: FontStyle.italic))),
          const SizedBox(width: AppSpace.xs),
          meta,
        ]),
      ));
    } else if (text.isNotEmpty) {
      rows.add(Padding(padding: inset.copyWith(top: sender != null || quote != null || hasMedia || hasFiles ? 3 : 6, bottom: 5), child: textWithMeta));
    } else if (!captionless) {
      rows.add(Padding(padding: const EdgeInsets.fromLTRB(10, 2, 10, 5), child: Align(alignment: AlignmentDirectional.centerEnd, widthFactor: 1, child: meta)));
    }

    final hasWideBlock = quote != null || sender != null || hasFiles;
    Widget content = Column(crossAxisAlignment: hasWideBlock || hasMedia ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: rows);
    if (hasMedia) {
      content = SizedBox(width: mediaW + 6, child: content);
    } else if (hasWideBlock) {
      // the quote and a file row take the bubble's width, set by whatever is widest
      content = IntrinsicWidth(child: content);
    }

    final bubble = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.bg,
          shape: ChatBubbleBorder(
            radius: radius,
            tailRight: tailRight,
            side: colors.edge == null ? BorderSide.none : BorderSide(color: colors.edge!, width: AppBorder.hairline),
          ),
        ),
        child: content,
      ),
    );

    final hoverSlot = widget.pointerFirst && (widget.onReply != null || widget.onActions != null)
        ? SizedBox(
            width: _slot,
            child: IgnorePointer(
              ignoring: !_hover,
              child: AnimatedOpacity(
                duration: AppMotion.of(context).fast,
                opacity: _hover ? 1 : 0,
                child: Row(mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  if (widget.onReply != null && widget.maxWidth > 500) _HoverAction(icon: Icons.reply_rounded, tooltip: 'chat_reply'.tr, onTap: (_) => widget.onReply!()),
                  if (widget.onActions != null) _HoverAction(icon: Icons.more_horiz_rounded, tooltip: 'chat_more'.tr, onTap: widget.onActions!),
                ]),
              ),
            ),
          )
        : null;

    // the tail needs its width on the outer side, always, so the run's edge stays straight
    final row = Padding(
      padding: EdgeInsetsDirectional.only(start: mine ? 0 : ChatBubbleBorder.tail, end: mine ? ChatBubbleBorder.tail : 0),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (mine) ?hoverSlot,
        Flexible(child: bubble),
        if (!mine) ?hoverSlot,
      ]),
    );

    Widget swiped = row;
    if (!widget.pointerFirst && widget.onReply != null) {
      final motion = AppMotion.of(context).fast;
      swiped = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => _dragUpdate(d, rtl),
        onHorizontalDragEnd: (_) => _dragEnd(),
        onHorizontalDragCancel: _dragEnd,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: _drag),
          duration: _dragging ? Duration.zero : motion,
          curve: AppMotion.curve,
          builder: (_, dx, child) => Stack(clipBehavior: Clip.none, alignment: AlignmentDirectional.centerStart, children: [
            Transform.translate(offset: Offset(rtl ? -dx : dx, 0), child: child),
            if (dx > 8)
              PositionedDirectional(
                start: -AppSpace.xs,
                child: Opacity(
                  opacity: (dx / _swipeAt).clamp(0.0, 1.0),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(color: _armed ? c.primaryTint : c.cardBg, shape: BoxShape.circle),
                    child: Icon(Icons.reply_rounded, size: AppIconSize.sm, color: chatInk(c)),
                  ),
                ),
              ),
          ]),
          child: row,
        ),
      );
    }

    Widget tap = swiped;
    if (widget.onRetry != null) {
      tap = InkWell(borderRadius: BorderRadius.circular(AppRadius.card), onTap: widget.onRetry, child: swiped);
    } else if (!widget.pointerFirst && widget.onActions != null) {
      tap = GestureDetector(onLongPress: () => widget.onActions!(null), child: swiped);
    }

    final body = Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      tap,
      if (m.sendState == ChatSendState.queued)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('chat_queued_note'.tr, style: appText(11, w: FontWeight.w500, c: c.textMedium)),
        ),
      if (failed && widget.onRetry != null) _FailedActions(error: m.error, onRetry: widget.onRetry!, onDiscard: widget.onDiscard),
    ]);

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Padding(
        padding: EdgeInsets.only(top: widget.runStart ? AppSpace.xs : 2),
        child: AnimatedContainer(
          duration: AppMotion.of(context).slow,
          curve: AppMotion.curve,
          decoration: BoxDecoration(color: widget.highlight ? c.primaryTint : Colors.transparent, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: widget.pointerFirst
              ? MouseRegion(onEnter: (_) => setState(() => _hover = true), onExit: (_) => setState(() => _hover = false), child: body)
              : body,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.time, required this.soft, required this.read, this.tick});
  final String time;
  final Color soft, read;
  final ChatTick? tick;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(time, style: appText(10.5, w: FontWeight.w500, c: soft, h: 1.2)),
      if (tick != null) ...[
        const SizedBox(width: 3),
        ChatTickIcon(tick: tick!, size: 14, muted: soft, read: read),
      ],
    ]);
  }
}

class _HoverAction extends StatelessWidget {
  const _HoverAction({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final void Function(Rect? anchor) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Builder(
      builder: (context) => IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: AppIconSize.md, color: c.textMedium),
        onPressed: () {
          final box = context.findRenderObject() as RenderBox?;
          onTap(box == null ? null : box.localToGlobal(Offset.zero) & box.size);
        },
      ),
    );
  }
}

class _FailedActions extends StatelessWidget {
  const _FailedActions({this.error, required this.onRetry, this.onDiscard});
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lost = error == ChatMessage.lostFileError;
    final words = lost ? 'chat_attachment_lost'.tr : (error ?? 'chat_not_sent'.tr);
    return Padding(
      padding: const EdgeInsets.only(top: 2, right: ChatBubbleBorder.tail, left: ChatBubbleBorder.tail),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline_rounded, size: AppIconSize.xs, color: c.danger),
        const SizedBox(width: AppSpace.xxs),
        Flexible(child: Text(words, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(11.5, w: FontWeight.w600, c: c.danger))),
        if (!lost) ...[
          const SizedBox(width: AppSpace.xxs),
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, AppTouch.min), padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs), foregroundColor: c.danger),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: AppIconSize.xs),
            label: Text('chat_retry'.tr, style: appText(12, w: FontWeight.w600, c: c.danger)),
          ),
        ],
        if (onDiscard != null)
          IconButton(
            tooltip: 'chat_delete_unsent'.tr,
            constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.delete_outline_rounded, size: AppIconSize.sm, color: c.textMedium),
            onPressed: onDiscard,
          ),
      ]),
    );
  }
}

/// Pictures of one message: one at its own shape, several as a tidy grid (a fourth tile says how many more).
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.width, required this.attachments, required this.local, required this.busy, this.resolve, this.onTap});
  final double width;
  final List<ChatAttachment> attachments;
  final List<ChatLocalFile> local;
  final bool busy;
  final Future<String> Function(ChatAttachment a)? resolve;
  final void Function(ChatAttachment a)? onTap;

  @override
  Widget build(BuildContext context) {
    final count = attachments.length + local.length;
    Widget tile(int i) {
      if (i < attachments.length) {
        final a = attachments[i];
        return _ImagePart(key: ValueKey('att-${a.id}'), attachment: a, resolve: resolve, onTap: () => onTap?.call(a));
      }
      return _LocalImagePart(bytes: local[i - attachments.length].bytes!, busy: busy);
    }

    final radius = BorderRadius.circular(AppRadius.card - 4);
    if (count == 1) {
      var ratio = 4 / 3;
      if (attachments.isNotEmpty && attachments.first.width != null && attachments.first.height != null && attachments.first.height! > 0) {
        ratio = (attachments.first.width! / attachments.first.height!).clamp(0.62, 1.9);
      }
      return ClipRRect(borderRadius: radius, child: SizedBox(width: width, height: width / ratio, child: tile(0)));
    }
    const gap = 2.0;
    final side = (width - gap) / 2;
    final shown = math.min(count, 4);
    return ClipRRect(
      borderRadius: radius,
      child: Wrap(spacing: gap, runSpacing: gap, children: [
        for (var i = 0; i < shown; i++)
          SizedBox(
            width: shown == 3 && i == 0 ? width : side,
            height: shown == 3 && i == 0 ? side * 0.9 : side,
            child: i == 3 && count > 4
                ? Stack(fit: StackFit.expand, children: [
                    tile(i),
                    ColoredBox(color: Colors.black.withValues(alpha: 0.5), child: Center(child: Text('+${count - 3}', style: appText(22, w: FontWeight.w700, c: Colors.white)))),
                  ])
                : tile(i),
          ),
      ]),
    );
  }
}

/// A picked image still going out: its own bytes, dimmed while it uploads.
class _LocalImagePart extends StatelessWidget {
  const _LocalImagePart({required this.bytes, required this.busy});
  final Uint8List bytes;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Stack(fit: StackFit.expand, alignment: Alignment.center, children: [
      Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => ColoredBox(color: c.inputBg, child: const SizedBox(width: 120, height: 90))),
      if (busy) ColoredBox(color: c.background.withValues(alpha: 0.35)),
      if (busy) const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
    ]);
  }
}

class _ImagePart extends StatefulWidget {
  const _ImagePart({super.key, required this.attachment, this.resolve, this.onTap});
  final ChatAttachment attachment;
  final Future<String> Function(ChatAttachment a)? resolve;
  final VoidCallback? onTap;

  @override
  State<_ImagePart> createState() => _ImagePartState();
}

class _ImagePartState extends State<_ImagePart> {
  Future<String>? _url;

  @override
  void initState() {
    super.initState();
    _url = widget.resolve?.call(widget.attachment);
  }

  @override
  void didUpdateWidget(_ImagePart old) {
    super.didUpdateWidget(old);
    if (old.attachment.id != widget.attachment.id) _url = widget.resolve?.call(widget.attachment);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = widget.attachment;
    final fallback = ColoredBox(color: c.inputBg, child: Center(child: Icon(Icons.broken_image_outlined, color: c.textLight)));
    return Semantics(
      button: true,
      label: a.name,
      child: InkWell(
        onTap: widget.onTap,
        child: _url == null
            ? fallback
            : FutureBuilder<String>(
                future: _url,
                builder: (_, s) => s.hasError
                    ? fallback
                    : s.data == null
                        ? ColoredBox(color: c.inputBg, child: const AppSkeletonBox())
                        : CachedNetworkImage(
                            imageUrl: s.data!,
                            cacheKey: 'chat-attachment-${a.id}', // the link is signed and short-lived; the picture is not
                            fit: BoxFit.cover,
                            fadeInDuration: AppMotion.of(context).fast,
                            placeholder: (_, _) => ColoredBox(color: c.inputBg),
                            errorWidget: (_, _, _) => fallback,
                          ),
              ),
      ),
    );
  }
}

class _FilePart extends StatelessWidget {
  const _FilePart({required this.name, required this.ext, required this.size, required this.colors, this.onTap});
  final String name, ext;
  final int size;
  final ChatBubbleInk colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (IconData icon, Color tone) = switch (ext.toLowerCase()) {
      'pdf' => (Icons.picture_as_pdf_rounded, c.danger),
      'doc' || 'docx' => (Icons.description_rounded, c.accent),
      'xls' || 'xlsx' || 'csv' => (Icons.table_chart_rounded, c.success),
      'ppt' || 'pptx' => (Icons.slideshow_rounded, c.warning),
      'zip' || 'rar' || '7z' => (Icons.folder_zip_rounded, c.accent2),
      'mp3' || 'wav' || 'm4a' || 'ogg' => (Icons.audiotrack_rounded, c.purple),
      'mp4' || 'mov' || 'webm' || 'mkv' => (Icons.movie_rounded, c.purple),
      _ => (Icons.insert_drive_file_rounded, chatInk(c)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: colors.tint,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xs),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tone.withValues(alpha: c.isDark ? 0.28 : 0.14), borderRadius: BorderRadius.circular(AppRadius.chip)),
                child: Icon(icon, size: AppIconSize.lg - 2, color: chatReadableOn(colors.bg, tone, min: 3)),
              ),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                fit: FlexFit.tight,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(13, w: FontWeight.w600, c: colors.ink)),
                  Text(ltrIsolate([if (ext.isNotEmpty) ext.toUpperCase(), if (size > 0) fileSizeLabel(size)].join(' · ')), maxLines: 1, overflow: TextOverflow.ellipsis, style: appText(11, w: FontWeight.w400, c: colors.soft)),
                ]),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpace.xxs),
                Icon(kIsWeb ? Icons.file_download_outlined : Icons.open_in_new_rounded, size: AppIconSize.md, color: colors.soft),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
