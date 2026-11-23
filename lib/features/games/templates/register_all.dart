// lib/features/games/templates/register_all.dart — the one place that registers the Games v4 templates (T48).
// A new template adds ONE line to [kReadyTemplates]; GamePlayPage and the games bus call [registerGameTemplates].
library;

import 'package:flutter_education_app/features/games/core/game_template.dart';
import 'package:flutter_education_app/features/games/templates/balloon_pop/balloon_pop.dart';
import 'package:flutter_education_app/features/games/templates/car_race/car_race.dart';
import 'package:flutter_education_app/features/games/templates/map_adventure/map_adventure.dart';
import 'package:flutter_education_app/features/games/templates/challenge_quiz/challenge_quiz.dart';
import 'package:flutter_education_app/features/games/templates/constellation/constellation.dart';
import 'package:flutter_education_app/features/games/templates/ghost_duel/ghost_duel.dart';
import 'package:flutter_education_app/features/games/templates/fractions_farm/fractions_farm.dart';
import 'package:flutter_education_app/features/games/templates/growing_tree/growing_tree.dart';
import 'package:flutter_education_app/features/games/templates/irab_hunter/irab_hunter.dart';
import 'package:flutter_education_app/features/games/templates/drag_place/drag_place.dart';
import 'package:flutter_education_app/features/games/templates/platform_jumper/platform_jumper.dart';
import 'package:flutter_education_app/features/games/templates/robot_coding/robot_coding.dart';
import 'package:flutter_education_app/features/games/templates/space_rocket/space_rocket.dart';
import 'package:flutter_education_app/features/games/templates/science_lab/science_lab.dart';
import 'package:flutter_education_app/features/games/templates/verse_builder/verse_builder.dart';
import 'package:flutter_education_app/features/games/templates/word_fishing/word_fishing.dart';
import 'package:flutter_education_app/features/games/templates/word_train/word_train.dart';

/// The templates this app plays.
final List<GameTemplate> kReadyTemplates = [
  const ChallengeQuizTemplate(),
  const VerseBuilderTemplate(),
  const CarRaceTemplate(),
  const BalloonPopTemplate(),
  const WordFishingTemplate(),
  const WordTrainTemplate(),
  const SpaceRocketTemplate(),
  const DragPlaceTemplate(),
  const IrabHunterTemplate(),
  const MapAdventureTemplate(),
  const GrowingTreeTemplate(),
  const ConstellationTemplate(),
  const FractionsFarmTemplate(),
  const ScienceLabTemplate(),
  const PlatformJumperTemplate(),
  const RobotCodingTemplate(),
  const GhostDuelTemplate(),
];

/// Registers every ready template (idempotent).
void registerGameTemplates() {
  for (final t in kReadyTemplates) {
    if (!kGameTemplates.containsKey(t.key)) registerGameTemplate(t);
  }
}
