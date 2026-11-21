// lib/features/games/engines/game_text.dart — how a typed or rebuilt answer is compared (D-1583): the tashkeel
// (harakat, tanween, shadda, sukun, the dagger alef, Quranic marks) and the tatweel are dropped, the alef forms
// (alef with hamza above / below, madda, wasla) become a bare alef, Latin letters are lower-cased and the spaces
// collapse. Nothing else is folded (taa marbuta and haa stay different: they are different words).
library;

bool _isMark(int c) =>
    (c >= 0x0610 && c <= 0x061A) ||
    (c >= 0x064B && c <= 0x065F) ||
    c == 0x0670 ||
    (c >= 0x06D6 && c <= 0x06DC) ||
    (c >= 0x06DF && c <= 0x06E8) ||
    (c >= 0x06EA && c <= 0x06ED) ||
    c == 0x0640; // tatweel

bool _isAlefForm(int c) => c == 0x0622 || c == 0x0623 || c == 0x0625 || c == 0x0671 || c == 0x0672 || c == 0x0673;

/// [s] in the comparable form described above.
String gameNormalize(String s) {
  final out = StringBuffer();
  var space = false;
  for (final c in s.trim().toLowerCase().runes) {
    if (_isMark(c)) continue;
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0) {
      space = true;
      continue;
    }
    if (space && out.isNotEmpty) out.write(' ');
    space = false;
    out.writeCharCode(_isAlefForm(c) ? 0x0627 : c);
  }
  return out.toString();
}

/// True when [given] and [expected] are the same answer once normalized (an empty answer is never right).
bool gameSameAnswer(String given, String expected) {
  final g = gameNormalize(given);
  return g.isNotEmpty && g == gameNormalize(expected);
}
