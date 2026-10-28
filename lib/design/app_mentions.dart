// lib/design/app_mentions.dart
//
// @mentions (D-075): typing "@" + a few letters in an organization announcement, a complaint (text / reply) or a
// meeting's notes suggests the people that item may reach; picking one inserts "@username ". The server parses the
// saved text and tells each newly mentioned person once (back/services/mentions.py); this file never notifies.
//
//   mentionQueryAt(text, caret)        the "@…" being typed at the caret (null when the caret is not in one; an
//                                      e-mail address never is)
//   insertMention(text, query, name)   the text with that "@…" replaced by "@name " and where the caret goes
//   mentionSegments(text)              plain / mention runs, the server's token rule (read views)
//   MentionApi.source(context, ref:, item:)   GET /api/v1/me/mentions/suggest, debounced by the field
//   MentionSuggestionList              the list (plain values: people, highlighted row, onPick) — layout-tested
//   Mentions(controller:, source:, child:)   wraps any existing text field: the list below (or [above]) it,
//                                      Up / Down / Enter / Tab / Esc while it is open (on the web through
//                                      AppKeyboard.keyClaim, so Enter picks instead of submitting the form)
//   MentionTextField                   a plain TextField inside [Mentions]
//   MentionText(text)                  the text with each "@name" highlighted; a tap opens that public profile
//                                      (AppNavigator.openProfile, D-074) unless `profile.public_link` is off
//
// Kill switch `mentions` (and `auth.username`): the fields are plain text fields and the text is plain text.
// Tests: test/ui/app_mentions_test.dart.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../config/theme/theme_config_provider.dart';
import '../core/api_client.dart';
import '../core/display/app_fonts.dart';
import '../features/auth/username.dart' show UsernameRules;
import '../utils/widget/app_navigator.dart' show AppNavigator;
import 'app_keyboard.dart' show AppKeyboard;

/// Kill switch of the whole feature (server: no parsing, empty suggestions).
const kMentionsFeatureKey = 'mentions';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Mentions are on: neither `mentions` nor the usernames themselves (`auth.username`) are switched off.
bool get mentionsEnabled =>
    !AppConfig.disableList.contains(kMentionsFeatureKey) && !AppConfig.disableList.contains('auth.username');

// ── Pure ──────────────────────────────────────────────────────────────────────

/// The longest query looked up (a username has at most 30 characters; a name search a bit more is pointless).
const kMentionQueryMax = 30;

/// The "@…" at the caret: [start] is the "@", [end] the end of the word (the caret may sit inside it), [query] what
/// was typed between the "@" and the caret.
class MentionQuery {
  const MentionQuery(this.start, this.end, this.query);

  final int start;
  final int end;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is MentionQuery && other.start == start && other.end == end && other.query == query;

  @override
  int get hashCode => Object.hash(start, end, query);

  @override
  String toString() => 'MentionQuery($start..$end "$query")';
}

// letters of any script (a name search: "@أحم"), digits, "." and "_"
final _queryChar = RegExp(r'[\p{L}\p{N}._]', unicode: true);
// what may not stand right before the "@" of a mention (then it is an e-mail address or "@@")
final _glued = RegExp(r'[A-Za-z0-9._@]');

/// The mention being typed when the caret is at [caret] in [text], else null.
MentionQuery? mentionQueryAt(String text, int caret) {
  if (caret < 1 || caret > text.length) return null;
  var i = caret;
  while (i > 0 && _queryChar.hasMatch(text[i - 1])) {
    i--;
    if (caret - i > kMentionQueryMax) return null;
  }
  if (i == 0 || text[i - 1] != '@') return null;
  final at = i - 1;
  if (at > 0 && _glued.hasMatch(text[at - 1])) return null;
  var end = caret;
  while (end < text.length && _queryChar.hasMatch(text[end])) {
    end++;
  }
  return MentionQuery(at, end, text.substring(i, caret));
}

/// [text] with [q] replaced by "@[username] " → (new text, caret after the space). An existing space after the word
/// is reused, never doubled.
(String, int) insertMention(String text, MentionQuery q, String username) {
  final name = UsernameRules.normalize(username);
  final before = text.substring(0, q.start);
  final after = text.substring(q.end.clamp(q.start, text.length));
  final token = '@$name';
  if (after.startsWith(' ')) return ('$before$token$after', before.length + token.length + 1);
  return ('$before$token $after', before.length + token.length + 1);
}

/// One run of a text: plain, or a mention of [username] (normalized, no "@") whose source is [text].
class MentionSegment {
  const MentionSegment(this.text, [this.username]);

  final String text;
  final String? username;

  bool get isMention => username != null;

  @override
  bool operator ==(Object other) => other is MentionSegment && other.text == text && other.username == username;

  @override
  int get hashCode => Object.hash(text, username);

  @override
  String toString() => isMention ? 'Mention($text)' : 'Text("$text")';
}

// the server's rule (services/mentions.py `_TOKEN`): not glued to a letter / digit / "." / "_" / "@" before it
final _token = RegExp(r'(?<![A-Za-z0-9._@])@([A-Za-z0-9._]{1,40})');

/// [text] split into plain and mention runs: "@name" with a valid username shape (a trailing "." stays plain text,
/// the end of a sentence). Adjacent plain runs are merged.
List<MentionSegment> mentionSegments(String text) {
  final out = <MentionSegment>[];
  void plain(String s) {
    if (s.isEmpty) return;
    if (out.isNotEmpty && !out.last.isMention) {
      out[out.length - 1] = MentionSegment(out.last.text + s);
    } else {
      out.add(MentionSegment(s));
    }
  }

  var last = 0;
  for (final m in _token.allMatches(text)) {
    final raw = m.group(1)!;
    var name = raw;
    while (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
    final lower = name.toLowerCase();
    if (name.isEmpty || !UsernameRules.isValid(lower)) continue;
    plain(text.substring(last, m.start));
    out.add(MentionSegment('@$name', lower));
    last = m.start + 1 + name.length;
  }
  plain(text.substring(last));
  return out;
}

// ── Data ──────────────────────────────────────────────────────────────────────

/// A person the field may suggest.
class MentionPerson {
  const MentionPerson({required this.id, required this.name, required this.username, this.imageUrl});

  final int id;
  final String name;
  final String username;
  final String? imageUrl;

  /// A row of GET /me/mentions/suggest; null without an id or a username.
  static MentionPerson? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = int.tryParse('${j['id'] ?? ''}');
    var u = j['username'] is String ? (j['username'] as String).trim() : '';
    if (u.startsWith('@')) u = u.substring(1);
    if (id == null || u.isEmpty) return null;
    final img = j['image_url'] is String && (j['image_url'] as String).trim().isNotEmpty ? j['image_url'] as String : null;
    final name = '${j['name'] ?? ''}'.trim();
    return MentionPerson(id: id, name: name.isEmpty ? u : name, username: u, imageUrl: img);
  }
}

/// Looks people up for a query (what was typed after "@").
typedef MentionSource = Future<List<MentionPerson>> Function(String query);

class MentionApi {
  MentionApi._();

  /// [context] announcement (ref = org id, item = announcement id) | complaint (ref = complaint id, none for a new
  /// one) | meeting (ref = meeting id, none for a new one; item = org id). A failure is an empty list.
  static MentionSource source(String context, {int? ref, int? item, ApiClient? api}) => (String q) async {
        try {
          final r = await (api ?? ApiClient()).get('/api/v1/me/mentions/suggest', queryParams: {
            'context': context,
            'ref': ?ref,
            'item': ?item,
            if (q.isNotEmpty) 'q': q,
          });
          final rows = r is Map ? r['people'] : null;
          if (rows is! List) return const <MentionPerson>[];
          return [for (final x in rows) ?MentionPerson.fromJson(x)];
        } catch (_) {
          return const <MentionPerson>[];
        }
      };
}

// ── The list ──────────────────────────────────────────────────────────────────

/// The suggestions under (or above) the field: avatar, name, "@username" (left to right). Plain values.
class MentionSuggestionList extends StatelessWidget {
  const MentionSuggestionList({
    super.key,
    required this.people,
    required this.onPick,
    this.highlighted = 0,
    this.maxHeight = 236,
  });

  final List<MentionPerson> people;
  final int highlighted;
  final ValueChanged<MentionPerson> onPick;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Semantics(
      container: true,
      label: _t('اقتراحات الإشارة', 'Mention suggestions'),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: c.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.divider),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.30 : 0.08), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            type: MaterialType.transparency,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: people.length,
              itemBuilder: (context, i) => _MentionRow(
                person: people[i],
                selected: i == highlighted,
                onTap: () => onPick(people[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MentionRow extends StatelessWidget {
  const _MentionRow({required this.person, required this.selected, required this.onTap});

  final MentionPerson person;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initial = person.name.isEmpty ? '@' : person.name.characters.first.toUpperCase();
    final img = person.imageUrl;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        color: selected ? c.primaryTint : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: c.primaryTint,
            foregroundImage: img != null ? NetworkImage(img) : null,
            onForegroundImageError: img != null ? (_, _) {} : null,
            child: Text(initial,
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w800, color: c.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppFonts.family, fontSize: 13.5, fontWeight: FontWeight.w700, color: c.textDark)),
              Text('@${person.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                      fontFamily: AppFonts.family,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c.isDark ? c.primaryLight : c.primary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── The field ─────────────────────────────────────────────────────────────────

/// Adds @mention suggestions to the text field [child] that edits [controller] (any field: TextField,
/// TextFormField, the app's MyTextField / Field / AppField). With the kill switch on it returns [child] as it is.
class Mentions extends StatefulWidget {
  const Mentions({
    super.key,
    required this.controller,
    required this.source,
    required this.child,
    this.above = false,
    this.debounce = const Duration(milliseconds: 250),
  });

  final TextEditingController controller;
  final MentionSource source;
  final Widget child;

  /// The list above the field (a reply bar at the bottom of the screen).
  final bool above;
  final Duration debounce;

  @override
  State<Mentions> createState() => _MentionsState();
}

class _MentionsState extends State<Mentions> {
  Timer? _timer;
  Timer? _blur;
  MentionQuery? _q;
  String? _asked;
  int _seq = 0;
  bool _focused = false;
  List<MentionPerson> _people = const [];
  int _hi = 0;

  bool get _open => _focused && _q != null && _people.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(Mentions old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _timer?.cancel();
    _blur?.cancel();
    _release();
    super.dispose();
  }

  void _changed() {
    if (!mentionsEnabled) return;
    final v = widget.controller.value;
    final sel = v.selection;
    final q = sel.isValid && sel.isCollapsed ? mentionQueryAt(v.text, sel.baseOffset) : null;
    if (q == null) {
      _close();
      return;
    }
    _q = q;
    if (q.query == _asked) {
      _sync();
      return;
    }
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => _fetch(q.query));
  }

  Future<void> _fetch(String query) async {
    final n = ++_seq;
    _asked = query;
    final people = await widget.source(query);
    if (!mounted || n != _seq || _q == null) return;
    setState(() {
      _people = people;
      _hi = 0;
    });
    _sync();
  }

  void _close() {
    _timer?.cancel();
    _seq++;
    _asked = null;
    final was = _q != null || _people.isNotEmpty;
    _q = null;
    _people = const [];
    _release();
    if (was && mounted) setState(() {});
  }

  /// While the list is open and the field focused, the app-wide keyboard layer hands us Enter / Esc first.
  void _sync() {
    if (_open) {
      AppKeyboard.keyClaim = _claim;
    } else {
      _release();
    }
  }

  void _release() {
    if (AppKeyboard.keyClaim == _claim) AppKeyboard.keyClaim = null;
  }

  bool _claim(KeyDownEvent e) => _key(e.logicalKey);

  /// Up / Down move, Enter / Tab pick, Esc closes. True = handled.
  bool _key(LogicalKeyboardKey k) {
    if (!_open) return false;
    if (k == LogicalKeyboardKey.arrowDown) {
      setState(() => _hi = (_hi + 1) % _people.length);
      return true;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      setState(() => _hi = (_hi - 1 + _people.length) % _people.length);
      return true;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter || k == LogicalKeyboardKey.tab) {
      _pick(_people[_hi.clamp(0, _people.length - 1)]);
      return true;
    }
    if (k == LogicalKeyboardKey.escape) {
      _close();
      return true;
    }
    return false;
  }

  void _pick(MentionPerson p) {
    final q = _q;
    if (q == null) return;
    final text = widget.controller.text;
    if (q.end > text.length) return _close();
    final (next, caret) = insertMention(text, q, p.username);
    _close();
    widget.controller.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: caret));
  }

  void _focus(bool has) {
    _blur?.cancel();
    if (has) {
      setState(() => _focused = true);
      _sync();
      return;
    }
    // a tap on the list must still land: close a moment later
    _blur = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _focused = false);
      _release();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!mentionsEnabled) return widget.child;
    final field = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _focus,
      onKeyEvent: (_, e) => (e is KeyDownEvent || e is KeyRepeatEvent) && _key(e.logicalKey)
          ? KeyEventResult.handled
          : KeyEventResult.ignored,
      child: widget.child,
    );
    final list = _open
        ? TextFieldTapRegion(child: MentionSuggestionList(people: _people, highlighted: _hi, onPick: _pick))
        : const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widget.above ? [list, field] : [field, list],
    );
  }
}

/// A TextField with @mention suggestions (see [Mentions]).
class MentionTextField extends StatelessWidget {
  const MentionTextField({
    super.key,
    required this.controller,
    required this.source,
    this.decoration = const InputDecoration(),
    this.minLines,
    this.maxLines = 1,
    this.style,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
    this.enabled = true,
    this.above = false,
  });

  final TextEditingController controller;
  final MentionSource source;
  final InputDecoration decoration;
  final int? minLines;
  final int? maxLines;
  final TextStyle? style;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool above;

  @override
  Widget build(BuildContext context) => Mentions(
        controller: controller,
        source: source,
        above: above,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: decoration,
          minLines: minLines,
          maxLines: maxLines,
          style: style,
          enabled: enabled,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
        ),
      );
}

// ── Read views ────────────────────────────────────────────────────────────────

/// [text] with every "@name" highlighted and tappable (opens that person's public profile, D-074). Plain [Text] /
/// [SelectableText] when mentions are switched off or the text mentions nobody.
class MentionText extends StatefulWidget {
  const MentionText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.selectable = false,
    this.onTap,
    this.mentionStyle,
  });

  final String text;
  final TextStyle? style;

  /// Merged over the mention ink (primary, bold): e.g. light ink inside a coloured chat bubble.
  final TextStyle? mentionStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool selectable;

  /// A tap on a mention (the username, no "@"); null = open the public profile when profile links are on.
  final ValueChanged<String>? onTap;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  void _clear() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _open(String username) {
    final tap = widget.onTap;
    if (tap != null) return tap(username);
    if (AppConfig.disableList.contains('profile.public_link')) return;
    unawaited(AppNavigator.openProfile(username));
  }

  @override
  Widget build(BuildContext context) {
    _clear();
    final segs = mentionsEnabled ? mentionSegments(widget.text) : const <MentionSegment>[];
    if (!segs.any((s) => s.isMention)) {
      return widget.selectable
          ? SelectableText(widget.text, style: widget.style, maxLines: widget.maxLines, textAlign: widget.textAlign)
          : Text(widget.text,
              style: widget.style, maxLines: widget.maxLines, overflow: widget.overflow, textAlign: widget.textAlign);
    }
    final c = context.colors;
    final base = widget.style ?? DefaultTextStyle.of(context).style;
    final hl = base
        .copyWith(color: c.isDark ? c.primaryLight : c.primary, fontWeight: FontWeight.w700)
        .merge(widget.mentionStyle);
    // a mention is kept left to right inside Arabic text (LRI … PDI), so "@ali_h" never reads "ali_h@"
    final lri = String.fromCharCode(0x2066), pdi = String.fromCharCode(0x2069);
    final spans = <InlineSpan>[
      for (final s in segs)
        if (!s.isMention)
          TextSpan(text: s.text)
        else
          TextSpan(
            text: '$lri${s.text}$pdi',
            style: hl,
            recognizer: (TapGestureRecognizer()..onTap = () => _open(s.username!)).also(_recognizers.add),
            mouseCursor: SystemMouseCursors.click,
          ),
    ];
    final span = TextSpan(style: base, children: spans);
    return widget.selectable
        ? SelectableText.rich(span, maxLines: widget.maxLines, textAlign: widget.textAlign)
        : Text.rich(span, maxLines: widget.maxLines, overflow: widget.overflow, textAlign: widget.textAlign);
  }
}

extension _Also<T> on T {
  T also(void Function(T) f) {
    f(this);
    return this;
  }
}
