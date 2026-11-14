// lib/features/admin/landing/landing_admin_api.dart
//
// Super admin → "Landing page": the rate limit of the public numbers and the real reviews shown as testimonials.
// Contract: back docs/landing/CONTRACT.md ("Super admin").
//   GET  /api/v1/admin/landing                      → {rate_limit, limits, testimonials}
//   PUT  /api/v1/admin/landing/rate-limit           {enabled, per_minute} (FULL object)
//   GET  /api/v1/admin/landing/review-candidates    q, min_stars, kind, page, page_size
//   PUT  /api/v1/admin/landing/testimonials         {ids}
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../admin_common.dart' show t;

const kLandingAdminFeatureKey = 'admin.landing';
const kLandingMaxTestimonials = 12;

const _base = '/api/v1/admin/landing';

int _int(dynamic v, int fallback) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);
String? _str(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class LandingRateLimit {
  const LandingRateLimit({this.enabled = true, this.perMinute = 60});

  final bool enabled;
  final int perMinute;

  factory LandingRateLimit.fromJson(dynamic json) {
    final j = _map(json);
    return LandingRateLimit(enabled: j['enabled'] != false, perMinute: _int(j['per_minute'], 60));
  }

  Map<String, dynamic> toJson() => {'enabled': enabled, 'per_minute': perMinute};

  LandingRateLimit copyWith({bool? enabled, int? perMinute}) =>
      LandingRateLimit(enabled: enabled ?? this.enabled, perMinute: perMinute ?? this.perMinute);

  @override
  bool operator ==(Object other) => other is LandingRateLimit && other.enabled == enabled && other.perMinute == perMinute;

  @override
  int get hashCode => Object.hash(enabled, perMinute);
}

/// A review that can be (or is) featured: [studentName] is the full name (admin only), [displayName] what visitors see.
class LandingReview {
  const LandingReview({
    required this.id,
    this.studentName = '',
    this.displayName = '',
    this.stars = 0,
    this.text = '',
    this.kind = 'course',
    this.course,
    this.teacher,
    this.createdAt,
    this.featured = false,
  });

  final int id;
  final String studentName;
  final String displayName;
  final int stars;
  final String text;

  /// 'course' | 'teacher'
  final String kind;
  final String? course;
  final String? teacher;
  final DateTime? createdAt;
  final bool featured;

  /// What the chip under the review says: the course for a course review, else the teacher.
  String? get subject => kind == 'teacher' ? (teacher ?? course) : (course ?? teacher);

  factory LandingReview.fromJson(dynamic json) {
    final j = _map(json);
    return LandingReview(
      id: _int(j['id'], 0),
      studentName: _str(j['student_name']) ?? '',
      displayName: _str(j['display_name']) ?? '',
      stars: _int(j['stars'], 0).clamp(0, 5),
      text: _str(j['text']) ?? '',
      kind: _str(j['kind']) == 'teacher' ? 'teacher' : 'course',
      course: _str(j['course']),
      teacher: _str(j['teacher']),
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      featured: j['featured'] == true,
    );
  }
}

class LandingOverview {
  const LandingOverview({
    this.rateLimit = const LandingRateLimit(),
    this.minPerMinute = 10,
    this.maxPerMinute = 600,
    this.testimonials = const [],
  });

  final LandingRateLimit rateLimit;
  final int minPerMinute;
  final int maxPerMinute;
  final List<LandingReview> testimonials;

  factory LandingOverview.fromJson(dynamic json) {
    final j = _map(json);
    final lim = _map(j['limits']);
    final lo = _int(lim['min'], 10);
    final hi = _int(lim['max'], 600);
    return LandingOverview(
      rateLimit: LandingRateLimit.fromJson(j['rate_limit']),
      minPerMinute: lo,
      maxPerMinute: hi > lo ? hi : lo + 1,
      testimonials: [for (final x in (j['testimonials'] is List ? j['testimonials'] as List : const [])) LandingReview.fromJson(x)],
    );
  }
}

class LandingCandidatesPage {
  const LandingCandidatesPage({this.items = const [], this.total = 0, this.page = 1, this.pageSize = 20});

  final List<LandingReview> items;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory LandingCandidatesPage.fromJson(dynamic json) {
    final j = _map(json);
    final items = [for (final x in (j['items'] is List ? j['items'] as List : const [])) LandingReview.fromJson(x)];
    return LandingCandidatesPage(
      items: items,
      total: _int(j['total'], items.length),
      page: _int(j['page'], 1),
      pageSize: _int(j['page_size'], 20),
    );
  }
}

class LandingAdminApi {
  LandingAdminApi._();

  static Future<LandingOverview> load() async => LandingOverview.fromJson(await ApiClient().get(_base));

  static Future<LandingOverview> saveRateLimit(LandingRateLimit v) async =>
      LandingOverview.fromJson(await ApiClient().put('$_base/rate-limit', body: v.toJson()));

  static Future<LandingCandidatesPage> candidates({
    String q = '',
    int minStars = 4,
    String? kind,
    int page = 1,
    int pageSize = 20,
  }) async =>
      LandingCandidatesPage.fromJson(await ApiClient().get('$_base/review-candidates', queryParams: {
        if (q.trim().isNotEmpty) 'q': q.trim(),
        'min_stars': minStars,
        'kind': ?kind,
        'page': page,
        'page_size': pageSize,
      }));

  static Future<LandingOverview> saveTestimonials(List<int> ids) async =>
      LandingOverview.fromJson(await ApiClient().put('$_base/testimonials', body: {'ids': ids}));
}

/// The text to show for a failed call: the landing codes get their own bilingual sentence, anything else the
/// exception's own safe message.
String landingErrorText(Object error) {
  final e = ApiException.from(error);
  switch (e.code) {
    case 'bad_rate_limit':
      return t('قيمة الحد غير صالحة. اختر رقماً بين 10 و600 في الدقيقة.', 'That limit is not valid. Pick a number between 10 and 600 per minute.');
    case 'too_many_testimonials':
      return t('يمكن عرض $kLandingMaxTestimonials تقييماً كحد أقصى في الصفحة الرئيسية.',
          'At most $kLandingMaxTestimonials reviews can be shown on the landing page.');
    case 'not_a_candidate':
      return t('أحد التقييمات المختارة لم يعد صالحاً للعرض (قد يكون حُذف أو قصر نصه). حدّث القائمة وأعد المحاولة.',
          'One of the chosen reviews can no longer be shown (it may have been removed or is too short). Refresh the list and try again.');
    case 'rate_limited':
      return t('طلبات كثيرة في وقت قصير. انتظر قليلاً ثم أعد المحاولة.', 'Too many requests in a short time. Wait a moment and try again.');
  }
  return e.message;
}
