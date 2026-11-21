// lib/features/games/admin/game_config_draft.dart — the admin editor's typed config per engine (Learning Hub v2 §3,
// D-1590): what each engine's form asks for ([kGameEngineForms]), a draft the form edits ([GameConfigDraft]), the
// config it sends ([GameConfigDraft.toConfig], exactly the contract's shapes) and the same checks the server makes
// (400 `bad_game_config` with `{field}`) so Save is only offered when the game can be played. Pure Dart, no widgets:
// test/ui/games_v2_engines_test.dart checks every engine's output.
//
//   quiz        {shuffle, questions: [{prompt_ar, prompt_en, options: [str] (2..6), answer: int}]}   1..50
//   match       {prompt_ar, prompt_en, pairs: [{a, b}]}                                                2..12
//   memory      {prompt_ar, prompt_en, pairs: [{a, b}]}                                                2..10
//   order       {prompt_ar, prompt_en, items: [str]}                                                   2..12
//   fill_blank  {prompt_ar, prompt_en, items: [{text, answer, options: [str] | null}]}  one `___`       1..30
//   word_puzzle {prompt_ar, prompt_en, words: [{word, hint}]}                                          1..15
library;

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/engines/fill_blank_engine.dart' show kGameBlank;
import 'package:flutter_education_app/features/games/engines/game_text.dart';
import 'package:flutter_education_app/features/games/engines/word_puzzle_engine.dart';

/// One field of a row: a line of text, a longer text, or (quiz) the options with the right one marked.
enum GameFieldKind { text, multiline, choices, lines }

class GameRowField {
  const GameRowField(this.key, this.labelAr, this.labelEn, {this.kind = GameFieldKind.text, this.optional = false, this.helpAr, this.helpEn});

  final String key, labelAr, labelEn;
  final GameFieldKind kind;
  final bool optional;
  final String? helpAr, helpEn;

  String get label => t(labelAr, labelEn);
  String? get help => helpAr == null ? null : t(helpAr!, helpEn ?? helpAr!);
}

/// What one engine's form asks for.
class GameEngineForm {
  const GameEngineForm({
    required this.engine,
    required this.rowsKey,
    required this.minRows,
    required this.maxRows,
    required this.rowAr,
    required this.rowEn,
    required this.fields,
    this.prompt = true,
    this.shuffle = false,
  });

  final String engine, rowsKey, rowAr, rowEn;
  final int minRows, maxRows;
  final List<GameRowField> fields;

  /// The game-level prompt (prompt_ar / prompt_en); quiz has one per question instead.
  final bool prompt;

  /// The quiz's shuffle switch.
  final bool shuffle;

  String rowLabel(int i) => t('$rowAr ${i + 1}', '$rowEn ${i + 1}');
}

const _pairFields = [GameRowField('a', 'الطرف الأول', 'First side'), GameRowField('b', 'الطرف الثاني', 'Second side')];

/// The engines this editor knows (the server's `/admin/games/engines` names them; this says how to edit them).
const Map<String, GameEngineForm> kGameEngineForms = {
  'quiz': GameEngineForm(
    engine: 'quiz',
    rowsKey: 'questions',
    minRows: 1,
    maxRows: 50,
    rowAr: 'السؤال',
    rowEn: 'Question',
    prompt: false,
    shuffle: true,
    fields: [
      GameRowField('prompt_ar', 'السؤال بالعربية', 'Question in Arabic'),
      GameRowField('prompt_en', 'السؤال بالإنجليزية', 'Question in English', optional: true),
      GameRowField('options', 'الخيارات', 'Options', kind: GameFieldKind.choices, helpAr: 'من 2 إلى 6، علّم الصحيح', helpEn: '2 to 6; mark the right one'),
    ],
  ),
  'match': GameEngineForm(engine: 'match', rowsKey: 'pairs', minRows: 2, maxRows: 12, rowAr: 'الزوج', rowEn: 'Pair', fields: _pairFields),
  'memory': GameEngineForm(engine: 'memory', rowsKey: 'pairs', minRows: 2, maxRows: 10, rowAr: 'الزوج', rowEn: 'Pair', fields: _pairFields),
  'order': GameEngineForm(
    engine: 'order',
    rowsKey: 'items',
    minRows: 2,
    maxRows: 12,
    rowAr: 'العنصر',
    rowEn: 'Item',
    fields: [GameRowField('item', 'العنصر (بالترتيب الصحيح)', 'Item (in the right order)')],
  ),
  'fill_blank': GameEngineForm(
    engine: 'fill_blank',
    rowsKey: 'items',
    minRows: 1,
    maxRows: 30,
    rowAr: 'الجملة',
    rowEn: 'Sentence',
    fields: [
      GameRowField('text', 'الجملة', 'Sentence', kind: GameFieldKind.multiline, helpAr: 'ضع ___ مكان الكلمة الناقصة', helpEn: 'Put ___ where the missing word goes'),
      GameRowField('answer', 'الإجابة', 'Answer'),
      GameRowField('options', 'الخيارات (سطر لكل خيار)', 'Options (one per line)',
          kind: GameFieldKind.lines, optional: true, helpAr: 'اتركها فارغة ليكتب الطالب الإجابة', helpEn: 'Leave empty to let the student type it'),
    ],
  ),
  'word_puzzle': GameEngineForm(
    engine: 'word_puzzle',
    rowsKey: 'words',
    minRows: 1,
    maxRows: 15,
    rowAr: 'الكلمة',
    rowEn: 'Word',
    fields: [
      GameRowField('word', 'الكلمة', 'Word'),
      GameRowField('hint', 'التلميح', 'Clue', optional: true, helpAr: 'يظهر فوق الحروف', helpEn: 'Shown above the letters'),
    ],
  ),
};

String _s(Object? v) => v == null ? '' : '$v'.trim();

List<String> _strings(Object? v) => [if (v is List) for (final x in v) _s(x)];

/// One problem: the field the server would name, and the text.
typedef GameConfigProblem = ({String field, String message});

/// The form's state for one engine. Rows hold plain values (quiz: `options` a list of strings and `answer` an index;
/// fill_blank: `options` a list of lines); each row has a local `_id` so its fields keep their place on a removal.
class GameConfigDraft {
  GameConfigDraft({required this.engine, this.promptAr = '', this.promptEn = '', this.shuffle = true, List<Map<String, dynamic>>? rows})
      : rows = rows ?? [];

  final String engine;
  String promptAr, promptEn;
  bool shuffle;
  final List<Map<String, dynamic>> rows;
  static int _seq = 0;

  GameEngineForm? get form => kGameEngineForms[engine];

  /// A blank row for this engine.
  Map<String, dynamic> blankRow() => {
        '_id': ++_seq,
        if (engine == 'quiz') ...{'prompt_ar': '', 'prompt_en': '', 'options': <String>['', ''], 'answer': 0},
        if (engine == 'match' || engine == 'memory') ...{'a': '', 'b': ''},
        if (engine == 'order') 'item': '',
        if (engine == 'fill_blank') ...{'text': '', 'answer': '', 'options': <String>[]},
        if (engine == 'word_puzzle') ...{'word': '', 'hint': ''},
      };

  void addRow() => rows.add(blankRow());

  /// A new game: the engine's minimum of blank rows.
  factory GameConfigDraft.blank(String engine) {
    final d = GameConfigDraft(engine: engine);
    for (var i = 0; i < (d.form?.minRows ?? 1); i++) {
      d.addRow();
    }
    return d;
  }

  /// The draft of a stored [config].
  factory GameConfigDraft.fromConfig(String engine, Map<String, dynamic> config) {
    final d = GameConfigDraft(
      engine: engine,
      promptAr: _s(config['prompt_ar']),
      promptEn: _s(config['prompt_en']),
      shuffle: config['shuffle'] != false,
    );
    final key = d.form?.rowsKey;
    final raw = key == null ? null : config[key];
    for (final r in raw is List ? raw : const []) {
      final row = d.blankRow();
      if (engine == 'order') {
        row['item'] = _s(r);
      } else if (r is Map) {
        for (final f in d.form!.fields) {
          if (f.key == 'options') {
            row['options'] = _strings(r['options']);
          } else {
            row[f.key] = _s(r[f.key]);
          }
        }
        if (engine == 'quiz') {
          final opts = row['options'] as List<String>;
          while (opts.length < 2) {
            opts.add('');
          }
          row['answer'] = r['answer'] is num ? (r['answer'] as num).toInt() : 0;
        }
      }
      d.rows.add(row);
    }
    if (d.rows.isEmpty) {
      for (var i = 0; i < (d.form?.minRows ?? 1); i++) {
        d.addRow();
      }
    }
    return d;
  }

  /// Whether a row has nothing typed in it (dropped from the config).
  static bool rowBlank(Map<String, dynamic> row) => row.entries
      .where((e) => e.key != '_id' && e.key != 'answer')
      .every((e) => e.value is List ? (e.value as List).every((x) => _s(x).isEmpty) : _s(e.value).isEmpty);

  List<Map<String, dynamic>> get _filled => [for (final r in rows) if (!rowBlank(r)) r];

  /// The config to send, in the contract's shape (blank rows dropped, every text trimmed).
  Map<String, dynamic> toConfig() {
    final filled = _filled;
    final prompt = {'prompt_ar': promptAr.trim(), 'prompt_en': promptEn.trim()};
    switch (engine) {
      case 'quiz':
        return {
          'shuffle': shuffle,
          'questions': [
            for (final r in filled) _quizQuestion(r),
          ],
        };
      case 'match':
      case 'memory':
        return {
          ...prompt,
          'pairs': [for (final r in filled) {'a': _s(r['a']), 'b': _s(r['b'])}],
        };
      case 'order':
        return {
          ...prompt,
          'items': [for (final r in filled) _s(r['item'])],
        };
      case 'fill_blank':
        return {
          ...prompt,
          'items': [
            for (final r in filled)
              {
                'text': _s(r['text']),
                'answer': _s(r['answer']),
                'options': _optionLines(r).isEmpty ? null : _optionLines(r),
              },
          ],
        };
      case 'word_puzzle':
        return {
          ...prompt,
          'words': [for (final r in filled) {'word': _s(r['word']), 'hint': _s(r['hint'])}],
        };
    }
    return {};
  }

  /// A quiz question with its empty options dropped and the answer index moved with them.
  static Map<String, dynamic> _quizQuestion(Map<String, dynamic> r) {
    final opts = _strings(r['options']);
    final a = r['answer'] is num ? (r['answer'] as num).toInt() : 0;
    final kept = <String>[];
    var answer = -1;
    for (var i = 0; i < opts.length; i++) {
      if (opts[i].isEmpty) continue;
      if (i == a) answer = kept.length;
      kept.add(opts[i]);
    }
    return {'prompt_ar': _s(r['prompt_ar']), 'prompt_en': _s(r['prompt_en']), 'options': kept, 'answer': answer};
  }

  static List<String> _optionLines(Map<String, dynamic> r) => [for (final o in _strings(r['options'])) if (o.isNotEmpty) o];

  /// What keeps this draft from being saved (empty = it can be). `field` is the config path the server would name.
  List<GameConfigProblem> problems() {
    final f = form;
    if (f == null) return [(field: 'engine', message: t('هذا النوع غير مدعوم في هذا الإصدار', 'This app version cannot edit this game type'))];
    final out = <GameConfigProblem>[];
    final filled = _filled;
    if (filled.length < f.minRows || filled.length > f.maxRows) {
      out.add((
        field: f.rowsKey,
        message: t('عدد ${f.rowAr} بين ${f.minRows} و${f.maxRows}', 'Between ${f.minRows} and ${f.maxRows} rows (${f.rowEn.toLowerCase()})'),
      ));
    }
    for (var i = 0; i < filled.length; i++) {
      final r = filled[i];
      final at = '${f.rowsKey}[$i]';
      final row = f.rowLabel(i);
      void bad(String field, String ar, String en) => out.add((field: '$at.$field', message: '$row: ${t(ar, en)}'));
      switch (engine) {
        case 'quiz':
          final q = _quizQuestion(r);
          if (_s(r['prompt_ar']).isEmpty && _s(r['prompt_en']).isEmpty) bad('prompt_ar', 'اكتب السؤال', 'write the question');
          final n = (q['options'] as List).length;
          if (n < 2 || n > 6) bad('options', 'من خيارين إلى 6 خيارات', '2 to 6 options');
          if ((q['answer'] as int) < 0) bad('answer', 'علّم الإجابة الصحيحة', 'mark the right option');
        case 'match':
        case 'memory':
          if (_s(r['a']).isEmpty || _s(r['b']).isEmpty) bad('a', 'املأ الطرفين', 'fill both sides');
        case 'order':
          break;
        case 'fill_blank':
          final text = _s(r['text']);
          if (kGameBlank.allMatches(text).length != 1) bad('text', 'ضع ___ مرة واحدة', 'put ___ exactly once');
          final answer = _s(r['answer']);
          if (answer.isEmpty) bad('answer', 'اكتب الإجابة', 'write the answer');
          final opts = _optionLines(r);
          if (opts.length == 1) bad('options', 'خياران على الأقل أو اتركها فارغة', 'at least 2 options, or none');
          if (opts.isNotEmpty && answer.isNotEmpty && !opts.any((o) => gameSameAnswer(o, answer))) {
            bad('options', 'الإجابة ليست بين الخيارات', 'the answer is not one of the options');
          }
        case 'word_puzzle':
          if (WordPuzzleEngine.lettersOf(_s(r['word'])).length < 2) bad('word', 'كلمة من حرفين على الأقل', 'a word of 2 letters or more');
      }
    }
    return out;
  }
}

/// A game's top fields as the admin routes take them (POST creates, PATCH updates: the same body).
Map<String, dynamic> gameAdminBody({
  required String key,
  required String engine,
  required String titleAr,
  required String titleEn,
  required Map<String, dynamic> config,
  required String category,
  required String difficulty,
  required String theme,
  String? level,
  int pointsReward = 0,
  String? coverUrl,
  required String status,
}) =>
    {
      'key': key.trim(),
      'engine': engine,
      'title_ar': titleAr.trim(),
      'title_en': titleEn.trim(),
      'config': config,
      'category': category,
      'difficulty': difficulty,
      'theme': theme,
      'level': (level ?? '').trim().isEmpty ? null : level!.trim(),
      'points_reward': pointsReward,
      'cover_url': ?coverUrl,
      'status': status,
    };
