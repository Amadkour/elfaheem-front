// lib/features/games/core/game_items.dart — the item models of a Games v4 draw (Games v4 T12, CONTRACT §3–§4).
//
//   ItemType    the nine item types, with their wire names
//   GameItem    one item in snapshot form: `body` is the resolved JSON body exactly as the draw answered it (canonical
//               order, `show` is only the screen order), so every index in a trace points into these arrays
//   GameMedia   image + audio playlist of an item
library;

/// The item types of CONTRACT §3.
enum ItemType {
  mcq('mcq'),
  trueFalse('true_false'),
  selectAll('select_all'),
  sequence('sequence'),
  classify('classify'),
  pair('pair'),
  fraction('fraction'),
  program('program'),
  combine('combine');

  const ItemType(this.wire);
  final String wire;

  /// Sequence, classify and pair score per unit (slot / token / pair), so their par time scales with `max`.
  bool get perUnit => this == sequence || this == classify || this == pair;

  static ItemType? parse(Object? s) {
    for (final t in values) {
      if (t.wire == s) return t;
    }
    return null;
  }
}

/// A bilingual text (`{ar, en}`); either side may be null.
class GameText {
  const GameText(this.ar, this.en);
  final String? ar, en;

  static GameText from(Object? j) => j is Map ? GameText(j['ar'] as String?, j['en'] as String?) : const GameText(null, null);

  /// The text in [lang] (`ar` / `en`), falling back to the other side.
  String of(String lang) => isolateMath((lang == 'ar' ? (ar ?? en) : (en ?? ar)) ?? '');
}

/// One audio entry of an item's playlist (one per ayah of a Quran reference).
class GameAudioEntry {
  const GameAudioEntry({required this.ref, required this.url, required this.startMs, this.endMs, this.reciter});
  final String? ref, reciter;
  final String url;
  final int startMs;

  /// null = to the end of the file.
  final int? endMs;

  factory GameAudioEntry.fromJson(Map j) => GameAudioEntry(
    ref: j['ref'] as String?,
    url: (j['url'] ?? '') as String,
    startMs: (j['start_ms'] as num?)?.toInt() ?? 0,
    endMs: (j['end_ms'] as num?)?.toInt(),
    reciter: j['reciter'] as String?,
  );
}

class GameMedia {
  const GameMedia({this.image, this.audio});
  final String? image;

  /// null = no audio.
  final List<GameAudioEntry>? audio;

  static const none = GameMedia();

  factory GameMedia.fromJson(Object? j) {
    if (j is! Map) return none;
    final a = j['audio'];
    return GameMedia(
      image: j['image'] as String?,
      audio: a is List ? [for (final e in a) if (e is Map) GameAudioEntry.fromJson(e)] : null,
    );
  }
}

/// One item of a draw (CONTRACT §4 "The snapshot item").
class GameItem {
  const GameItem({
    required this.n,
    required this.type,
    required this.body,
    this.id = 0,
    this.rev = 1,
    this.sacred = false,
    this.status,
    this.prompt = const GameText(null, null),
    this.media = GameMedia.none,
    this.explain = const GameText(null, null),
    this.sourceKind,
    this.sourceRef,
    this.sourceLabel = const GameText(null, null),
    int? max,
  }) : _max = max;

  /// Position in the draw = the trace's `i`.
  final int n;
  final int id, rev;
  final ItemType type;
  final bool sacred;

  /// Present only in a preview.
  final String? status;
  final GameText prompt, explain, sourceLabel;
  final GameMedia media;
  final String? sourceKind, sourceRef;

  /// The resolved body, exactly as the snapshot answered it.
  final Map<String, dynamic> body;
  final int? _max;

  /// Points available: the draw's own `max` when given, else computed from the body (CONTRACT §4).
  int get max => _max ?? maxOf(type, body);

  /// Parses one snapshot item; null when the type is unknown (a newer server).
  static GameItem? fromJson(Map j, {int? n}) {
    final type = ItemType.parse(j['type']);
    final body = j['body'];
    if (type == null || body is! Map) return null;
    final src = j['source'];
    return GameItem(
      n: n ?? (j['n'] as num?)?.toInt() ?? 0,
      id: (j['id'] as num?)?.toInt() ?? 0,
      rev: (j['rev'] as num?)?.toInt() ?? 1,
      type: type,
      sacred: j['sacred'] == true,
      status: j['status'] as String?,
      prompt: GameText.from(j['prompt']),
      media: GameMedia.fromJson(j['media']),
      explain: GameText.from(j['explain']),
      sourceKind: src is Map ? src['kind'] as String? : null,
      sourceRef: src is Map ? src['ref'] as String? : null,
      sourceLabel: src is Map ? GameText.from(src['label']) : const GameText(null, null),
      body: Map<String, dynamic>.from(body),
      max: (j['max'] as num?)?.toInt(),
    );
  }

  /// `max` per type (CONTRACT §4).
  static int maxOf(ItemType type, Map<String, dynamic> b) {
    switch (type) {
      case ItemType.selectAll:
        return _len(b['answers']);
      case ItemType.sequence:
        return _len(b['blanks']);
      case ItemType.classify:
        final tokens = b['tokens'];
        final withCase = tokens is List ? tokens.where((x) => x is Map && x['case'] != null).length : 0;
        return _len(tokens) + withCase;
      case ItemType.pair:
        return _len(b['pairs']);
      case ItemType.program:
        return 2;
      default:
        return 1;
    }
  }

  /// Par seconds of the item (CONTRACT §7).
  int get parSeconds => kParSeconds[type]! * (type.perUnit ? max : 1);

  /// An int list of the body (`answers`, `blanks`, `eq`, …); empty when absent.
  List<int> intList(String key) => [for (final v in (body[key] as List? ?? const [])) (v as num).toInt()];

  /// The order to draw the choices in (`show`), or the canonical order when the snapshot has none.
  List<int> get show {
    final s = body['show'];
    return s is List ? [for (final v in s) (v as num).toInt()] : [for (var i = 0; i < _choiceCount; i++) i];
  }

  int get _choiceCount {
    switch (type) {
      case ItemType.mcq:
      case ItemType.selectAll:
        return _len(body['options']);
      case ItemType.sequence:
        return _len(body['tokens']) + _len(body['extra']);
      case ItemType.classify:
        return _len(body['tokens']);
      case ItemType.combine:
        return _len(body['ingredients']);
      default:
        return 0;
    }
  }
}

int _len(Object? v) => v is List ? v.length : 0;

/// Par seconds per item type (CONTRACT §7).
const Map<ItemType, int> kParSeconds = {
  ItemType.mcq: 12,
  ItemType.trueFalse: 8,
  ItemType.selectAll: 15,
  ItemType.sequence: 4,
  ItemType.classify: 5,
  ItemType.pair: 6,
  ItemType.fraction: 20,
  ItemType.program: 45,
  ItemType.combine: 15,
};

/// Parses a draw's `items` list (position = `n`), skipping entries of an unknown type; the caller compares the length
/// with the raw list to show "needs a newer version" when one was skipped.
List<GameItem> parseGameItems(Object? list) {
  final out = <GameItem>[];
  if (list is! List) return out;
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    if (e is! Map) continue;
    final it = GameItem.fromJson(e, n: i);
    if (it != null) out.add(it);
  }
  return out;
}

final RegExp _mathOnly = RegExp(r'^[\d٠-٩۰-۹\s+\-−×÷*/=<>≤≥≠%.,:^()√²³½¼¾π]+$');

/// A math or number expression ("20 ÷ 4") keeps its left-to-right order inside right-to-left Arabic text: it is
/// wrapped in a Unicode LTR isolate (LRI ... PDI). Any text with a letter is returned unchanged.
String isolateMath(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty || !RegExp(r'[\d٠-٩۰-۹]').hasMatch(trimmed) || !_mathOnly.hasMatch(trimmed)) return s;
  return '${String.fromCharCode(0x2066)}$trimmed${String.fromCharCode(0x2069)}';
}
