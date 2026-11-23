// lib/features/games/admin/v4/hub_api.dart — the Games v4 admin hub, templates and subjects calls (CONTRACT §10).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes). Kill switch
// `admin.games_content` (the hub); `admin.games` stays the classic editor's.
//
//   GET  /api/v1/admin/games/v4/hub?days=7        {plays_today, players_today, completion_pct, avg_score_pct,
//                                                  pending_review, items_total, levels_published, by_day}
//   GET  /api/v1/admin/games/v4/templates          {items: [template]}
//   PUT  /api/v1/admin/games/v4/templates/{key}    {enabled?, defaults?, age_min?, age_max?, hidden_subject_ids?, sort?}
//   GET | POST /api/v1/admin/games/v4/subjects     {items: [subject]} · 201 subject
//   PUT | DELETE /api/v1/admin/games/v4/subjects/{id}
//
// Codes: 422 bad_template_settings | bad_subject (`field`) · 409 subject_key_taken | subject_in_use · 403 admin_required |
// feature_disabled.
library;

import 'package:flutter/widgets.dart' show BuildContext, IconData;
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;

const String kGamesContentFeatureKey = 'admin.games_content';

bool gamesContentOff() => AppConfig.disableList.contains(kGamesContentFeatureKey);

/// A link on the hub: the other admin pages (bank, review, levels, analytics, …) append theirs to
/// [kGamesHubExtraLinks] (each page's own file, at start-up) and the hub draws them after its own.
class GamesHubLink {
  const GamesHubLink({
    required this.id,
    required this.titleAr,
    required this.titleEn,
    required this.subAr,
    required this.subEn,
    required this.icon,
    required this.open,
    this.sort = 100,
    this.badge = 0,
  });
  final String id, titleAr, titleEn, subAr, subEn;
  final IconData icon;
  final void Function(BuildContext context) open;
  final int sort;
  final int badge;
}

/// Append-only registry of the hub's other pages.
final List<GamesHubLink> kGamesHubExtraLinks = [];

String gamesV4ErrorText(Object e) {
  final x = ApiException.from(e);
  switch (x.code) {
    case 'bad_template_settings':
      return t('إعدادات اللعبة غير صالحة، راجع الأرقام', 'The settings are not valid, check the numbers');
    case 'bad_subject':
      return t('بيانات المادة غير صالحة، راجع الاسم والمفتاح', 'The subject is not valid, check its name and key');
    case 'subject_key_taken':
      return t('هذا المفتاح مستخدم لمادة أخرى', 'Another subject already uses this key');
    case 'subject_in_use':
      return t('للمادة أسئلة أو مستويات: أوقفها بدل حذفها', 'This subject has questions or levels: switch it off instead of deleting it');
    case 'feature_disabled':
      return t('هذه الميزة متوقفة من الإعدادات', 'This feature is switched off in the settings');
  }
  return gamesErrorText(e);
}

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _s(Object? v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];
List<int> _ints(Object? v) => v is List ? [for (final x in v) _i(x)] : const [];

class GamesHub {
  const GamesHub({
    this.playsToday = 0,
    this.playersToday = 0,
    this.completionPct = 0,
    this.avgScorePct = 0,
    this.pendingReview = 0,
    this.itemsTotal = 0,
    this.levelsPublished = 0,
  });
  factory GamesHub.fromJson(Object? r) {
    final m = r is Map ? r : const {};
    return GamesHub(
      playsToday: _i(m['plays_today']),
      playersToday: _i(m['players_today']),
      completionPct: _d(m['completion_pct']),
      avgScorePct: _d(m['avg_score_pct']),
      pendingReview: _i(m['pending_review']),
      itemsTotal: _i(m['items_total']),
      levelsPublished: _i(m['levels_published']),
    );
  }
  final int playsToday, playersToday, pendingReview, itemsTotal, levelsPublished;
  final double completionPct, avgScorePct;
}

class GameTemplateRow {
  const GameTemplateRow({
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.enabled = true,
    this.sacredAllowed = true,
    this.defaults = const {},
    this.codeDefaults = const {},
    this.ageMin,
    this.ageMax,
    this.hiddenSubjectIds = const [],
    this.levels = 0,
  });
  factory GameTemplateRow.fromJson(Map<String, dynamic> m) => GameTemplateRow(
        key: _s(m['key']),
        nameAr: _s(m['name_ar']),
        nameEn: _s(m['name_en']),
        enabled: m['enabled'] != false,
        sacredAllowed: m['sacred_allowed'] != false,
        defaults: m['defaults'] is Map ? Map<String, dynamic>.from(m['defaults'] as Map) : const {},
        codeDefaults: m['code_defaults'] is Map ? Map<String, dynamic>.from(m['code_defaults'] as Map) : const {},
        ageMin: m['age_min'] is num ? (m['age_min'] as num).toInt() : null,
        ageMax: m['age_max'] is num ? (m['age_max'] as num).toInt() : null,
        hiddenSubjectIds: _ints(m['hidden_subject_ids']),
        levels: _i(m['levels']),
      );
  final String key, nameAr, nameEn;
  final bool enabled, sacredAllowed;
  final Map<String, dynamic> defaults, codeDefaults;
  final int? ageMin, ageMax;
  final List<int> hiddenSubjectIds;
  final int levels;
  String get name => AppConfig.lang == 'ar' ? nameAr : nameEn;

  /// The admin's value, else the code's.
  Object? setting(String k) => defaults.containsKey(k) ? defaults[k] : codeDefaults[k];

  /// A growing tree answers these whatever the admin sets (CONTRACT §2).
  bool get fixedSettings => key == 'growing_tree';
}

class GameSubjectRow {
  const GameSubjectRow({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.enabled = true,
    this.sacred = false,
    this.requiresReview = false,
    this.eduSubjectIds = const [],
    this.items = 0,
    this.levels = 0,
  });
  factory GameSubjectRow.fromJson(Map<String, dynamic> m) => GameSubjectRow(
        id: _i(m['id']),
        key: _s(m['key']),
        nameAr: _s(m['name_ar']),
        nameEn: _s(m['name_en']),
        enabled: m['enabled'] != false,
        sacred: m['sacred'] == true,
        requiresReview: m['requires_review'] == true,
        eduSubjectIds: _ints(m['edu_subject_ids']),
        items: _i(m['items']),
        levels: _i(m['levels']),
      );
  final int id, items, levels;
  final String key, nameAr, nameEn;
  final bool enabled, sacred, requiresReview;
  final List<int> eduSubjectIds;
  String get name => AppConfig.lang == 'ar' ? nameAr : nameEn;
}

class GamesV4AdminApi {
  GamesV4AdminApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<GamesHub> hub() async => GamesHub.fromJson(await _api.get('/api/v1/admin/games/v4/hub', queryParams: {'days': 7}));

  Future<List<GameTemplateRow>> templates() async {
    final r = await _api.get('/api/v1/admin/games/v4/templates');
    return [for (final m in _maps(r is Map ? r['items'] : null)) GameTemplateRow.fromJson(m)];
  }

  Future<GameTemplateRow> updateTemplate(String key, Map<String, dynamic> body) async {
    final r = await _api.put('/api/v1/admin/games/v4/templates/$key', body: body);
    return GameTemplateRow.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<List<GameSubjectRow>> subjects() async {
    final r = await _api.get('/api/v1/admin/games/v4/subjects');
    return [for (final m in _maps(r is Map ? r['items'] : null)) GameSubjectRow.fromJson(m)];
  }

  Future<GameSubjectRow> createSubject(Map<String, dynamic> body) async {
    final r = await _api.post('/api/v1/admin/games/v4/subjects', body: body);
    return GameSubjectRow.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<GameSubjectRow> updateSubject(int id, Map<String, dynamic> body) async {
    final r = await _api.put('/api/v1/admin/games/v4/subjects/$id', body: body);
    return GameSubjectRow.fromJson(r is Map ? Map<String, dynamic>.from(r) : const {});
  }

  Future<void> deleteSubject(int id) async {
    await _api.delete('/api/v1/admin/games/v4/subjects/$id');
  }
}
