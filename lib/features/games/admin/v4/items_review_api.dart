// lib/features/games/admin/v4/items_review_api.dart — Games v4 T66: the review queue and the import calls of the
// question bank (CONTRACT §10). Every path is a literal `/api/v1/…` (test/contract/ checks each).
//
//   GET  /api/v1/admin/games/v4/review?subject_id&skip&limit       {items, total, has_more}  (admin or can_review)
//   POST /api/v1/admin/games/v4/items/{id}/review                   {decision: approve|reject, note?} → the item
//   GET | PUT /api/v1/admin/games/v4/reviewers                      {user_ids} → {items: [{id, name, username}]}
//   GET  /api/v1/admin/games/v4/subjects                            {items: [subject]}
//   GET  /api/v1/admin/games/v4/import/template?type&format         the file
//   POST /api/v1/admin/games/v4/import?dry_run=                     multipart file + subject_id → ImportReport
//   GET  /api/v1/admin/users?search&size                            to find a reviewer
//
// Server codes: 403 review_required | admin_required | feature_disabled · 409 not_pending · 422 bad_reviewers |
// bad_import_file.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/games/games_api.dart' show gamesErrorText;

/// The nine item types a template can be downloaded for.
const List<String> kGameItemTypes = [
  'mcq', 'true_false', 'select_all', 'sequence', 'classify', 'pair', 'fraction', 'program', 'combine',
];

/// The plain name of an item type for a non-technical admin.
String gameItemTypeName(String type) => switch (type) {
      'mcq' => t('اختيار من متعدد', 'Multiple choice'),
      'true_false' => t('صح أم خطأ', 'True or false'),
      'select_all' => t('اختر كل الإجابات', 'Select all that apply'),
      'sequence' => t('ترتيب', 'Put in order'),
      'classify' => t('تصنيف', 'Sort into groups'),
      'pair' => t('مطابقة', 'Match pairs'),
      'fraction' => t('كسور', 'Fractions'),
      'program' => t('برمجة', 'Program the robot'),
      'combine' => t('تجربة وخلط', 'Combine and try'),
      _ => type,
    };

/// A subject of the question bank.
typedef GameSubjectRow = ({int id, String key, String nameAr, String nameEn, bool requiresReview});

String gameSubjectName(GameSubjectRow s) => t(s.nameAr.isEmpty ? s.key : s.nameAr, s.nameEn.isEmpty ? s.key : s.nameEn);

/// One item waiting for review, with just what the reviewer reads.
class ReviewItem {
  const ReviewItem({
    required this.id,
    required this.type,
    required this.topic,
    required this.promptAr,
    required this.promptEn,
    required this.subject,
    required this.sourceRef,
    required this.preview,
    this.sourceLabel = '',
  });

  final int id;
  final String type;
  final String topic;
  final String promptAr;
  final String promptEn;
  final String subject;
  final String sourceRef;

  /// The server's resolved source name (`سورة الإخلاص 1`, `صحيح البخاري 127`); empty when it has none.
  final String sourceLabel;

  /// The answer / reference in one short line (the body, trimmed).
  final String preview;

  String get prompt => t(promptAr.isNotEmpty ? promptAr : promptEn, promptEn.isNotEmpty ? promptEn : promptAr);

  factory ReviewItem.fromJson(Map<String, dynamic> j) {
    final p = j['prompt'] is Map ? Map<String, dynamic>.from(j['prompt'] as Map) : const <String, dynamic>{};
    final s = j['source'] is Map ? Map<String, dynamic>.from(j['source'] as Map) : const <String, dynamic>{};
    return ReviewItem(
      id: (j['id'] as num?)?.toInt() ?? 0,
      type: '${j['type'] ?? ''}',
      topic: '${j['topic'] ?? ''}',
      promptAr: '${p['ar'] ?? ''}',
      promptEn: '${p['en'] ?? ''}',
      subject: '${j['subject'] ?? ''}',
      sourceRef: '${s['ref'] ?? ''}',
      // the references (`@quran:112:1`, `@hadith:bukhari:127`) are shown as their text: the server resolves them
      sourceLabel: _resolvedLabel(j['resolved']),
      preview: reviewBodyPreview(_resolvedBody(j['resolved']) ?? j['body']),
    );
  }
}

Object? _resolvedBody(Object? resolved) => resolved is Map ? resolved['body'] : null;

String _resolvedLabel(Object? resolved) {
  final src = resolved is Map ? resolved['source'] : null;
  final l = src is Map ? src['label'] : null;
  if (l is! Map) return '';
  final ar = '${l['ar'] ?? ''}', en = '${l['en'] ?? ''}';
  return t(ar.isNotEmpty ? ar : en, en.isNotEmpty ? en : ar);
}

/// The body of an item as one short line: the options, the tokens or the reference.
String reviewBodyPreview(Object? body) {
  if (body is! Map) return '';
  final tokens = body['tokens'];
  if (tokens is String) return tokens;
  if (tokens is List) return tokens.map((e) => e is Map ? '${e['text'] ?? ''}' : '$e').join(' ');
  final opts = body['options'];
  if (opts is List) {
    return opts.map((e) => e is Map ? '${e['text'] ?? ''}' : '$e').where((s) => s.isNotEmpty).join(' · ');
  }
  final pairs = body['pairs'];
  if (pairs is List) return pairs.map((e) => e is Map ? '${e['a']} = ${e['b']}' : '$e').join(' · ');
  return '';
}

typedef ReviewQueuePage = ({List<ReviewItem> items, int total, bool hasMore});
typedef Reviewer = ({int id, String name, String username});
typedef ImportRowError = ({int row, String field, String why});

/// The answer of `POST /import`.
class ImportReport {
  const ImportReport({required this.rows, required this.ok, required this.errors, required this.created, required this.pending});

  final int rows;
  final int ok;
  final List<ImportRowError> errors;
  final int created;
  final int pending;

  factory ImportReport.fromJson(Object? r) {
    final j = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    final errs = j['errors'];
    return ImportReport(
      rows: n('rows'),
      ok: n('ok'),
      created: n('created'),
      pending: n('pending'),
      errors: [
        if (errs is List)
          for (final e in errs)
            if (e is Map) (row: (e['row'] as num?)?.toInt() ?? 0, field: '${e['field'] ?? ''}', why: '${e['why'] ?? ''}'),
      ],
    );
  }
}

/// A failed call's text.
String reviewErrorText(Object e) {
  final x = ApiException.from(e);
  switch (x.code) {
    case 'review_required':
      return t('المراجعة للمراجعين والمشرفين فقط', 'Only reviewers and admins can review');
    case 'not_pending':
      return t('هذا السؤال لم يعد بانتظار المراجعة', 'This question is no longer waiting for review');
    case 'bad_reviewers':
      return t('أحد المراجعين غير موجود', 'One of the reviewers does not exist');
    case 'bad_import_file':
      return t('الملف غير صالح: استخدم القالب (CSV أو XLSX أو JSON) بحجم أقل من 5 ميغابايت وحتى 2000 صف',
          'This file is not valid: use the template (CSV, XLSX or JSON), under 5 MB and up to 2000 rows');
  }
  return gamesErrorText(e);
}

class ItemsReviewApi {
  ItemsReviewApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Map<String, dynamic> _map(Object? r) => r is Map ? Map<String, dynamic>.from(r) : const {};

  Future<ReviewQueuePage> queue({int? subjectId, int skip = 0, int limit = 50}) async {
    final r = _map(await _api.get('/api/v1/admin/games/v4/review',
        queryParams: {if (subjectId != null) 'subject_id': subjectId, 'skip': skip, 'limit': limit}));
    final raw = r['items'];
    return (
      items: [
        if (raw is List)
          for (final e in raw)
            if (e is Map) ReviewItem.fromJson(Map<String, dynamic>.from(e)),
      ],
      total: (r['total'] as num?)?.toInt() ?? 0,
      hasMore: r['has_more'] == true,
    );
  }

  Future<void> decide(int id, {required bool approve, String? note}) => _api.post(
      '/api/v1/admin/games/v4/items/$id/review',
      body: {'decision': approve ? 'approve' : 'reject', if (note != null && note.trim().isNotEmpty) 'note': note.trim()});

  Future<List<Reviewer>> reviewers() async {
    final r = _map(await _api.get('/api/v1/admin/games/v4/reviewers'));
    return _reviewers(r['items']);
  }

  Future<List<Reviewer>> setReviewers(List<int> ids) async {
    final r = _map(await _api.put('/api/v1/admin/games/v4/reviewers', body: {'user_ids': ids}));
    return _reviewers(r['items']);
  }

  List<Reviewer> _reviewers(Object? raw) => [
        if (raw is List)
          for (final e in raw)
            if (e is Map) (id: (e['id'] as num?)?.toInt() ?? 0, name: '${e['name'] ?? ''}', username: '${e['username'] ?? ''}'),
      ];

  /// People to make reviewers: `GET /admin/users?search=`.
  Future<List<Reviewer>> findUsers(String search) async {
    final r = _map(await _api.get('/api/v1/admin/users', queryParams: {'search': search, 'size': 8}));
    return _reviewers(r['items']);
  }

  Future<List<GameSubjectRow>> subjects() async {
    final r = _map(await _api.get('/api/v1/admin/games/v4/subjects'));
    final raw = r['items'];
    return [
      if (raw is List)
        for (final e in raw)
          if (e is Map)
            (
              id: (e['id'] as num?)?.toInt() ?? 0,
              key: '${e['key'] ?? ''}',
              nameAr: '${e['name_ar'] ?? ''}',
              nameEn: '${e['name_en'] ?? ''}',
              requiresReview: e['requires_review'] == true,
            ),
    ];
  }

  Future<Uint8List> template({String? type, required String format}) => _api.getBytes(
      '/api/v1/admin/games/v4/import/template',
      queryParams: {if (type != null) 'type': type, 'format': format});

  Future<ImportReport> import(int subjectId, Uint8List bytes, String fileName, {required bool dryRun}) async {
    final r = await _api.postMultipart('/api/v1/admin/games/v4/import?dry_run=$dryRun',
        fields: {'subject_id': '$subjectId'}, fileField: 'file', fileName: fileName, fileBytes: bytes);
    return ImportReport.fromJson(r);
  }
}
