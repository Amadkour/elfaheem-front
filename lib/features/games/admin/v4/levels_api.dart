// lib/features/games/admin/v4/levels_api.dart — the Games v4 levels' admin calls (T67, CONTRACT §10).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET    /api/v1/admin/games/v4/levels?template&game_subject_id&status   {items: [level + item_source,
//                                                                          template_settings, stats]}
//   POST   /api/v1/admin/games/v4/levels/auto-split                        {created: [level], skipped}
//   POST   /api/v1/admin/games                                             a new level (201)
//   PUT | DELETE /api/v1/admin/games/{id}                                  edit / remove a level
//   POST   /api/v1/admin/games/reorder                                     {ids} (also rewrites `level_no`)
//   POST   /api/v1/games/{id}/draw {mode: "preview"}                       admins only: the level's round, nothing saved
//
// Codes: 422 bad_item_source | template_not_sacred | bad_template_settings · 409 no_items (publish with nothing
// approved to draw) · 403 admin_required | feature_disabled.
library;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/admin/v4/hub_api.dart' show gamesV4ErrorText;

typedef LevelJson = Map<String, dynamic>;

int _i(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;
LevelJson _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String levelsErrorText(Object e) {
  final x = ApiException.from(e);
  switch (x.code) {
    case 'bad_item_source':
      return t('اختيار الأسئلة غير صالح: راجع الأسئلة أو شروط السحب', 'The questions chosen are not valid: check the questions or the pool rule');
    case 'template_not_sacred':
      return t('هذه اللعبة لا تقبل نصوص القرآن والحديث: اختر مادة أخرى', 'This game never takes Quran or Hadith texts: choose another subject');
    case 'no_items':
      return t('لا توجد أسئلة معتمدة تكفي لهذا المستوى. اعتمد أسئلة أولاً.', 'There are no approved questions for this level yet. Approve some first.');
  }
  return gamesV4ErrorText(e);
}

/// One level as the admin list answers it.
class LevelRow {
  const LevelRow(this.raw);
  final LevelJson raw;

  int get id => _i(raw['id']);
  String get template => '${raw['template'] ?? raw['engine'] ?? ''}';
  String get titleAr => '${raw['title_ar'] ?? ''}';
  String get titleEn => '${raw['title_en'] ?? ''}';
  String get title => AppConfig.lang == 'ar' ? titleAr : titleEn;
  String get status => '${raw['status'] ?? 'draft'}';
  bool get published => status == 'published';
  int get levelNo => _i(raw['level_no']);
  int? get subjectId => raw['game_subject_id'] is num ? _i(raw['game_subject_id']) : null;
  String get topic => '${raw['topic'] ?? ''}';
  int get ageMin => _i(raw['age_min'], 6);
  int get ageMax => _i(raw['age_max'], 99);
  int get coins => _i(raw['coins_reward']);
  bool get sacred => raw['sacred'] == true;
  LevelJson get itemSource => _m(raw['item_source']);
  LevelJson get settings => _m(raw['template_settings']);
  LevelJson get unlock => _m(raw['unlock']);
  LevelJson get stats => _m(raw['stats']);
  int get starts => _i(stats['starts']);
  num get avgScorePct => stats['avg_score_pct'] is num ? stats['avg_score_pct'] as num : 0;
}

class LevelsAdminApi {
  LevelsAdminApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<List<LevelRow>> levels({String? template, int? subjectId, String? status}) async {
    final r = await _api.get('/api/v1/admin/games/v4/levels', queryParams: {
      if (template != null) 'template': template,
      if (subjectId != null) 'game_subject_id': subjectId,
      if (status != null) 'status': status,
    });
    final l = r is Map ? r['items'] : r;
    return [if (l is List) for (final x in l) if (x is Map) LevelRow(Map<String, dynamic>.from(x))];
  }

  Future<LevelRow> create(LevelJson body) async => LevelRow(_m(await _api.post('/api/v1/admin/games', body: body)));

  Future<LevelRow> update(int id, LevelJson body) async => LevelRow(_m(await _api.put('/api/v1/admin/games/$id', body: body)));

  Future<void> delete(int id) async {
    await _api.delete('/api/v1/admin/games/$id');
  }

  Future<void> reorder(List<int> ids) async {
    await _api.post('/api/v1/admin/games/reorder', body: {'ids': ids});
  }

  /// `{created: [level], skipped}`.
  Future<({List<LevelRow> created, int skipped})> autoSplit(LevelJson body) async {
    final r = _m(await _api.post('/api/v1/admin/games/v4/levels/auto-split', body: body));
    final c = r['created'];
    final sk = r['skipped'];
    return (
      created: [if (c is List) for (final x in c) if (x is Map) LevelRow(Map<String, dynamic>.from(x))],
      skipped: sk is List ? sk.length : _i(sk),
    );
  }

  /// The level's round for the admin's preview: unapproved items included (each carries `status`), nothing saved.
  Future<LevelJson> preview(int id) async => _m(await _api.post('/api/v1/games/$id/draw', body: {'mode': 'preview'}));
}
