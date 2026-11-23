// lib/features/games/breaks/breaks_service.dart — Games v4 T75: the config, the suggestion and the break notice.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/features/games/content/games_v4_api.dart';
import 'package:flutter_education_app/features/games/game_play_page.dart';
import 'package:flutter_education_app/features/games/games_models.dart';
import 'package:flutter_education_app/features/messaging/notification/notification_service.dart';
import 'package:flutter_education_app/main.dart' show navigatorKey;

String breakText(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// Opens a suggested level in the game page. False when there is none.
Future<bool> openSuggestedGame(BuildContext context, {int? courseId, GamesV4Api? api}) async {
  final nav = Navigator.of(context);
  final level = await (api ?? GamesV4Api()).suggest(courseId: courseId);
  if (level == null) return false;
  await nav.push(MaterialPageRoute(builder: (_) => GamePlayPage(game: GameSummary.fromJson(level.raw), v4: api)));
  return true;
}

class BreaksService {
  BreaksService._();
  static final BreaksService instance = BreaksService._();

  V4BreaksConfig? _config;
  DateTime? _loadedAt;
  Future<V4BreaksConfig>? _loading;

  /// The module settings, cached for 10 minutes. All off when the call fails (kill switch, offline).
  Future<V4BreaksConfig> config({GamesV4Api? api}) {
    final at = _loadedAt;
    if (_config != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 10)) {
      return Future.value(_config!);
    }
    return _loading ??= () async {
      try {
        _config = await (api ?? GamesV4Api()).breaksConfig();
        _loadedAt = DateTime.now();
      } catch (_) {
        _config = const V4BreaksConfig();
      }
      _loading = null;
      return _config!;
    }();
  }

  /// The break suggestion: an in-app notice (web too) and, on phones, a local notification.
  Future<void> suggestBreak(int? courseId, V4BreaksConfig cfg) async {
    final mins = cfg.breakMaxMinutes;
    final title = breakText('وقت استراحة قصيرة', 'Time for a short break');
    final body = mins > 0
        ? breakText('العب لعبة سريعة من مادتك لمدة $mins دقيقة', 'Play a quick game of your subject for up to $mins min')
        : breakText('العب لعبة سريعة من مادتك', 'Play a quick game of your subject');
    showAppNotice(
      body,
      icon: Icons.sports_esports_rounded,
      duration: const Duration(seconds: 12),
      actionLabel: breakText('العب الآن', 'Play now'),
      onAction: () {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) openSuggestedGame(ctx, courseId: courseId);
      },
    );
    if (!kIsWeb) {
      try {
        await NotificationService.instance.show(id: 750075, title: title, body: body);
      } catch (_) {}
    }
  }
}
