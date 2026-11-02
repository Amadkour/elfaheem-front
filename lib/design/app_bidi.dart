// Text that people wrote (a request title, a council item, a comment) keeps the language it was written in: an
// English title in the Arabic interface, or the other way round. Drawn in the page's direction, its punctuation and
// numbers land on the wrong side ("December 12–15 ,leave"), so such text takes its OWN direction from its first
// strong letter (the Unicode first-strong rule, as a browser's dir="auto").
//
//   contentDirection(text)  → TextDirection.rtl for Arabic / Hebrew / Syriac / Thaana script first, ltr for a Latin
//                             (or any other strong) letter first, null when there is no letter (digits, symbols, empty:
//                             keep the page's direction).
//   AutoDirText(text, …)     a Text with that direction and the alignment of the page's start edge, so rows still
//                             line up in either language.
//   autoDirOf(context, text) the same pair (direction, alignment) for a widget that is not a plain Text
//                             (SelectableText.rich, a Wrap of words).
//   ltrIsolate(text)         a figure that reads left to right in either language ("100%", never "%100").
//   bidiIsolate(text)        server / user text spliced INTO a translated sentence (an error after "فشل اختبار
//                             السلامة: "): wrapped in FIRST STRONG ISOLATE … POP DIRECTIONAL ISOLATE, so it keeps its own
//                             order ("3.7/s is below the floor of 5.0/s", not "s is below the floor of 5.0/s/3.7") and the
//                             sentence around it keeps the page's.
//
// Pure, unit-tested: test/ui/app_bidi_test.dart.
library;

import 'package:flutter/widgets.dart';

/// The direction of [text] by its first strong letter; null when it has none.
TextDirection? contentDirection(String text) {
  for (final r in text.runes) {
    if (_rtl(r)) return TextDirection.rtl;
    if (_strongLtr(r)) return TextDirection.ltr;
  }
  return null;
}

bool _rtl(int r) =>
    (r >= 0x0590 && r <= 0x08FF) || // Hebrew, Arabic, Syriac, Thaana, NKo, Samaritan, Arabic supplements
    (r >= 0xFB1D && r <= 0xFDFF) || // Hebrew / Arabic presentation forms A
    (r >= 0xFE70 && r <= 0xFEFF); //   Arabic presentation forms B

bool _strongLtr(int r) =>
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) || // Latin-1 letters + Latin Extended
    (r >= 0x370 && r <= 0x58F) || //                          Greek, Cyrillic, Armenian
    (r >= 0x0900 && r <= 0x1FFF) || //                        Indic … Latin Extended Additional
    (r >= 0x3040 && r <= 0x9FFF) || //                        Kana, CJK
    (r >= 0xAC00 && r <= 0xD7AF); //                          Hangul

/// [text] between U+2068 FIRST STRONG ISOLATE and U+2069 POP DIRECTIONAL ISOLATE (empty stays empty).
String bidiIsolate(String text) => text.isEmpty ? text : '${String.fromCharCode(0x2068)}$text${String.fromCharCode(0x2069)}';

/// [text] between U+2066 LEFT-TO-RIGHT ISOLATE and U+2069 POP DIRECTIONAL ISOLATE: a figure that reads left to right
/// in Arabic too ("100%", not "%100"), the app's percent form everywhere.
String ltrIsolate(String text) => text.isEmpty ? text : '${String.fromCharCode(0x2066)}$text${String.fromCharCode(0x2069)}';

/// The direction of [text] ([contentDirection], else the page's) and the alignment that puts it on the page's start
/// edge.
(TextDirection, TextAlign) autoDirOf(BuildContext context, String text) {
  final page = Directionality.of(context);
  final own = contentDirection(text) ?? page;
  return (own, own == page ? TextAlign.start : TextAlign.end);
}

/// A [Text] of user-written content: its own direction ([contentDirection]), aligned to the page's start edge.
class AutoDirText extends StatelessWidget {
  const AutoDirText(this.text, {super.key, this.style, this.maxLines, this.overflow});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    // the page's start edge in the text's own terms: an English title in Arabic sits on the right like the rest
    final (own, align) = autoDirOf(context, text);
    return Text(
      text,
      textDirection: own,
      textAlign: align,
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
  }
}
