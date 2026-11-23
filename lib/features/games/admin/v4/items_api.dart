// lib/features/games/admin/v4/items_api.dart — the question bank's admin calls (Games v4 T65, CONTRACT §3, §9, §10).
// Every path is a literal `/api/v1/…` (test/contract/ checks each against the server's routes). Items stay plain
// maps: the server is the validator and answers 422 `bad_game_item {field, why}`.
//
//   GET    /api/v1/admin/games/v4/items?subject_id&topic&type&status&difficulty&q&skip&limit  {items, total, has_more}
//   POST   /api/v1/admin/games/v4/items            → the item + `resolved`        POST …/items/check → {resolved}
//   GET | PUT | DELETE /api/v1/admin/games/v4/items/{id}
//   POST   /api/v1/admin/games/v4/items/bulk       {ids, set?, delete?} → {changed, skipped}
//   GET    /api/v1/admin/games/v4/subjects         subjects (id, key, name_ar, name_en, sacred)
//   GET    /api/v1/admin/games/v4/quran/surahs · …/quran/ayat?surah&from&to&reciter
//   GET    /api/v1/admin/games/v4/hadith?collection&number&q&max_words&skip&limit · PUT …/hadith/{id}/matn
//   GET    /api/v1/admin/games/v4/reciters · PUT …/reciters/{key}
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;

typedef Json = Map<String, dynamic>;

/// The nine item types (CONTRACT §3).
const List<String> kItemTypes = [
  'mcq',
  'true_false',
  'select_all',
  'sequence',
  'classify',
  'pair',
  'fraction',
  'program',
  'combine',
];

const List<String> kItemStatuses = ['draft', 'pending_review', 'approved', 'rejected'];

String itemTypeName(String k) => switch (k) {
      'mcq' => t('اختيار من متعدد', 'Multiple choice'),
      'true_false' => t('صح أو خطأ', 'True or false'),
      'select_all' => t('اختر كل الإجابات', 'Select all that apply'),
      'sequence' => t('ترتيب', 'Put in order'),
      'classify' => t('تصنيف', 'Sort into groups'),
      'pair' => t('مطابقة', 'Match pairs'),
      'fraction' => t('كسور', 'Fractions'),
      'program' => t('برمجة', 'Code the robot'),
      'combine' => t('تركيب', 'Combine'),
      _ => k,
    };

String itemStatusName(String k) => switch (k) {
      'draft' => t('مسودة', 'Draft'),
      'pending_review' => t('بانتظار المراجعة', 'Waiting for review'),
      'approved' => t('معتمد', 'Approved'),
      'rejected' => t('مرفوض', 'Rejected'),
      _ => k,
    };

/// A difficulty 1..5 in words (the number stays, so it matches the filters and the files).
String itemDifficultyName(int d) => switch (d) {
      1 => t('1 · سهل جداً', '1 · very easy'),
      2 => t('2 · سهل', '2 · easy'),
      3 => t('3 · متوسط', '3 · medium'),
      4 => t('4 · صعب', '4 · hard'),
      5 => t('5 · صعب جداً', '5 · very hard'),
      _ => '$d',
    };

/// The server's reason code (`why`) for a bad item or an import row, in words.
String itemWhyText(String why) => switch (why) {
      'empty' => t('فارغ', 'is empty'),
      'too_long' => t('أطول من الحد', 'is too long'),
      'count_2_6' => t('العدد خارج الحد المسموح', 'has too few or too many entries'),
      'duplicate' => t('مكرر', 'is repeated'),
      'out_of_range' => t('خارج المدى', 'is out of range'),
      'ref' => t('المرجع غير موجود', 'points to nothing'),
      'too_long_for_order' => t('أطول من أن يُرتَّب كلمة كلمة', 'is too long to put in order word by word'),
      'sacred_text' => t('النص الشريف يُختار ولا يُكتب', 'Sacred text is picked, never typed'),
      'missing' => t('ناقص', 'is missing'),
      'unknown_type' => t('نوع سؤال غير معروف', 'is not a known question type'),
      _ => t('غير صالح', 'is not valid'),
    };

/// The server's field path (`body.options`, `prompt.ar`, …) as the admin knows it.
String itemFieldName(String field) {
  final f = field.replaceAll(RegExp(r'\[\d+\]'), '');
  return switch (f) {
    'prompt' || 'prompt.ar' || 'prompt.en' => t('نص السؤال', 'The question'),
    'explain' || 'explain.ar' || 'explain.en' => t('شرح الإجابة', 'The explanation'),
    'type' => t('نوع السؤال', 'Question type'),
    'topic' => t('الموضوع', 'Topic'),
    'difficulty' => t('الصعوبة', 'Difficulty'),
    'age_min' || 'age_max' => t('العمر', 'Age'),
    'subject_id' => t('المادة', 'Subject'),
    'body.options' => t('الخيارات', 'The options'),
    'body.answer' || 'body.answers' => t('الإجابة الصحيحة', 'The correct answer'),
    'body.tokens' => t('الكلمات', 'The words'),
    'body.pairs' => t('الأزواج', 'The pairs'),
    'body.buckets' => t('المجموعات', 'The groups'),
    'body.ingredients' => t('المكوّنات', 'The ingredients'),
    'source' || 'source.ref' => t('المصدر', 'The source'),
    _ => field,
  };
}

/// The server's `bad_game_item` answer as one readable line naming the field.
String itemErrorText(Object e) {
  final x = ApiException.from(e);
  if (x.code == 'bad_game_item') {
    final raw = x.body;
    final d = raw is Map ? (raw['detail'] is Map ? raw['detail'] as Map : raw) : null;
    final field = d == null ? '' : '${d['field'] ?? ''}';
    final why = d == null ? '' : '${d['why'] ?? ''}';
    final reason = itemWhyText(why);
    return field.isEmpty ? reason : '${itemFieldName(field)}: $reason';
  }
  switch (x.code) {
    case 'reciter_not_verified':
      return t('لا يمكن تفعيل قارئ قبل التحقق من إذنه', 'A reciter cannot be switched on before the permission is verified');
    case 'default_required':
      return t('القارئ الافتراضي لا يُوقَف', 'The default reciter cannot be switched off');
    case 'review_required':
      return t('تحتاج صلاحية المراجعة', 'You need the review permission');
    case 'bad_matn':
      return t('حدود المتن غير صالحة', 'The matn limits are not valid');
  }
  return gamesErrorText(e);
}

class ItemsPage {
  const ItemsPage(this.items, this.total, this.hasMore);
  final List<Json> items;
  final int total;
  final bool hasMore;
}

List<Json> _list(dynamic j, [String key = 'items']) {
  final raw = j is Map ? j[key] : j;
  return raw is List ? [for (final x in raw) if (x is Map) Map<String, dynamic>.from(x)] : <Json>[];
}

class ItemsV4Api {
  ItemsV4Api({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  Future<List<Json>> subjects() async => _list(await _api.get('/api/v1/admin/games/v4/subjects'));

  Future<ItemsPage> items({
    int? subjectId,
    String? topic,
    String? type,
    String? status,
    int? difficulty,
    String? q,
    int skip = 0,
    int limit = 50,
  }) async {
    final j = await _api.get('/api/v1/admin/games/v4/items', queryParams: {
      if (subjectId != null) 'subject_id': subjectId,
      if (topic != null && topic.isNotEmpty) 'topic': topic,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (difficulty != null) 'difficulty': difficulty,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'skip': skip,
      'limit': limit,
    });
    final m = j is Map ? j : const {};
    final list = _list(j);
    return ItemsPage(list, (m['total'] as num?)?.toInt() ?? list.length, m['has_more'] == true);
  }

  Future<Json> item(int id) async => Map<String, dynamic>.from(await _api.get('/api/v1/admin/games/v4/items/$id') as Map);

  Future<Json> create(Json body) async =>
      Map<String, dynamic>.from(await _api.post('/api/v1/admin/games/v4/items', body: body) as Map);

  Future<Json> update(int id, Json body) async =>
      Map<String, dynamic>.from(await _api.put('/api/v1/admin/games/v4/items/$id', body: body) as Map);

  Future<void> delete(int id) async => _api.delete('/api/v1/admin/games/v4/items/$id');

  /// The live preview: the item in its snapshot form without saving; null when the draft is not valid yet.
  Future<Json?> check(Json body) async {
    final j = await _api.post('/api/v1/admin/games/v4/items/check', body: body);
    final r = j is Map ? j['resolved'] : null;
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Future<Json> bulk(List<int> ids, {Json? set, bool delete = false}) async => Map<String, dynamic>.from(await _api
      .post('/api/v1/admin/games/v4/items/bulk', body: {'ids': ids, if (set != null) 'set': set, if (delete) 'delete': true}) as Map);

  Future<List<Json>> surahs() async => _list(await _api.get('/api/v1/admin/games/v4/quran/surahs'));

  Future<List<Json>> ayat(int surah, int from, int to, {String? reciter}) async => _list(await _api.get(
      '/api/v1/admin/games/v4/quran/ayat',
      queryParams: {'surah': surah, 'from': from, 'to': to, if (reciter != null) 'reciter': reciter}));

  Future<ItemsPage> hadith({String? collection, int? number, String? q, int skip = 0, int limit = 30}) async {
    final j = await _api.get('/api/v1/admin/games/v4/hadith', queryParams: {
      if (collection != null) 'collection': collection,
      if (number != null) 'number': number,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'skip': skip,
      'limit': limit,
    });
    final list = _list(j);
    final total = (j is Map ? (j['total'] as num?)?.toInt() : null) ?? list.length;
    return ItemsPage(list, total, skip + list.length < total);
  }

  Future<Json> setMatn(int id, int? from, int? to) async => Map<String, dynamic>.from(
      await _api.put('/api/v1/admin/games/v4/hadith/$id/matn', body: {'matn_from': from, 'matn_to': to}) as Map);

  Future<List<Json>> reciters() async => _list(await _api.get('/api/v1/admin/games/v4/reciters'));

  Future<Json> putReciter(String key, Json body) async =>
      Map<String, dynamic>.from(await _api.put('/api/v1/admin/games/v4/reciters/$key', body: body) as Map);
}
