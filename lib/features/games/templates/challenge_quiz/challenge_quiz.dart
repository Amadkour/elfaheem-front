// lib/features/games/templates/challenge_quiz/challenge_quiz.dart — Challenge Quiz (Games v4 T37, CONTRACT §2): the
// reference template of QuestionStage. `mcq`, `true_false` and `select_all` items (sacred text allowed: a calm round
// with a quiet retry), a countdown from the settings (120 s by default, no time bonus for sacred text), the age
// theme's backdrop and tiles, a character who cheers or winces, and the recitation of an item that carries audio
// (it plays when the question appears; the speaker button replays it; the reciter switch changes the voice).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/games/bases/question_stage.dart';
import 'package:flutter_education_app/features/games/bases/stage_kit.dart';
import 'package:flutter_education_app/features/games/core/game_audio.dart';
import 'package:flutter_education_app/features/games/core/game_character.dart';
import 'package:flutter_education_app/features/games/core/game_items.dart';
import 'package:flutter_education_app/features/games/core/game_session.dart';
import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/core/age_theme.dart';

class ChallengeQuizTemplate extends GameTemplate {
  const ChallengeQuizTemplate();

  @override
  String get key => 'challenge_quiz';
  @override
  Set<MechanicKind> get kinds => const {MechanicKind.choose, MechanicKind.selectAll};
  @override
  Set<ItemType> get accepts => const {ItemType.mcq, ItemType.trueFalse, ItemType.selectAll};
  @override
  bool get sacredAllowed => true;
  @override
  String get nameAr => 'تحدّي الأسئلة';
  @override
  String get nameEn => 'Challenge Quiz';
  @override
  IconData get icon => Icons.quiz_rounded;

  @override
  Widget build(GameSession s) => ChallengeQuizGame(session: s);
}

const ChallengeQuizTemplate kChallengeQuiz = ChallengeQuizTemplate();

class ChallengeQuizGame extends StatefulWidget {
  const ChallengeQuizGame({super.key, required this.session, this.silent = false, this.reciters});
  final GameSession session;
  final bool silent;

  /// Tests replace the reciter list loader.
  final ReciterLoader? reciters;

  @override
  State<ChallengeQuizGame> createState() => _ChallengeQuizGameState();
}

class _ChallengeQuizGameState extends State<ChallengeQuizGame> {
  final QuestionStageController _stage = QuestionStageController();
  GameMood _mood = GameMood.idle;

  @override
  void dispose() {
    unawaited(GameAudio.instance.stopRecitation());
    super.dispose();
  }

  void _play(GameItem it) {
    final segs = stageSegments(it);
    if (segs.isEmpty) return;
    final r = widget.session.reciter?['key'];
    unawaited(GameAudio.instance.playRecitation(segs, reciter: r is String ? r : null).catchError((Object _) {}));
  }

  void _setMood(GameMood m) {
    if (mounted) setState(() => _mood = m);
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted && _mood == m) setState(() => _mood = GameMood.idle);
    });
  }

  Widget? _header(BuildContext context, GameItem it, StageSurface sf) {
    final audio = it.media.audio != null && it.media.audio!.isNotEmpty;
    final tall = MediaQuery.sizeOf(context).height >= 700;
    if (!audio && !tall) return null;
    return Row(children: [
      if (tall)
        SizedBox.square(
          dimension: 88,
          child: GameCharacter(theme: AgeThemeScope.of(context), mood: _mood, size: 88),
        ),
      const Spacer(),
      if (audio) StageReciterSwitch(surface: sf, loader: widget.reciters, currentKey: widget.session.reciter?['key'] as String?),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StageFrame(
      session: widget.session,
      kinds: kChallengeQuiz.kinds,
      silent: widget.silent,
      onHint: _stage.hint,
      child: QuestionStage(
        session: widget.session,
        controller: _stage,
        silent: widget.silent,
        header: _header,
        onItemShown: _play,
        onWrong: (it) {
          if (!widget.session.calm && !widget.session.sacred) _setMood(GameMood.sad);
          if (it.sacred) _play(it);
        },
        onRight: (_) => _setMood(GameMood.happy),
      ),
    );
  }
}
