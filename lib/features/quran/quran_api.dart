// lib/features/quran/quran_api.dart — the Quran memorization calls (Learning Hub Phase 6, D-1347). Every path is a
// literal `/api/v1/…` (test/contract/ checks each against the server's routes).
//
//   GET  /api/v1/quran/meta                                  surah names, ayah counts, juz starts (no auth)
//   GET  /api/v1/quran/teachers?gender&goal&session_type      the published teachers + their quran courses
//   GET  /api/v1/quran/teachers/{id}                         one teacher
//   GET|PUT /api/v1/me/quran/teacher-profile                 the teacher's own card
//   GET  /api/v1/me/quran/progress                           my progress (student)
//   GET  /api/v1/quran/students/{id}/progress                a student of mine (teacher)
//   GET  /api/v1/parent/children/{id}/quran/progress         a linked child (parent)
//   POST /api/v1/quran/progress                              one entry, idempotent by `client_id`
//   GET  /api/v1/module-settings/quran                       self_log, gender_matching, …
//   GET  /api/v1/courses/{id}/enrolled-students              the record sheet's student picker (the course's staff)
//
// Booking a teacher = the course page and its existing checkout (a quran program IS a course); the two booking
// refusals (403 `quran_gender_rule`, `quran_teacher_unverified`) are in apiErrorText, so the checkout shows them too.
//
// Kill switches: `student_tab_quran` (the tab, the list, my progress, a student's own log), `quran.teacher_apply`
// (the teacher's card editor).
//
// [QuranOutbox] keeps an entry the network lost (per user, SharedPreferences) and sends it again with the SAME
// `client_id`, so a retry never records it twice (the server answers `duplicate: true`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/storage_service.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter_education_app/features/quran/quran_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The student tab (and the teacher list / my progress on the server).
const String kQuranTabKey = 'student_tab_quran';

/// The teacher's card editor.
const String kQuranTeacherApplyKey = 'quran.teacher_apply';

bool quranOff() => AppConfig.disableList.contains(kQuranTabKey);

bool quranTeacherApplyOff() => AppConfig.disableList.contains(kQuranTeacherApplyKey);

/// One id per entry the sheet records (8–36 of `A-Za-z0-9_.:-`): a UUID v4.
String newQuranClientId() => const Uuid().v4();

/// A Quran code's bilingual text (null = not a Quran code; the two booking codes live in apiErrorText).
String? quranCodeText(String? code, [Map<String, dynamic> d = const {}]) => switch (code) {
      'quran_teacher_not_found' => _t('هذا المعلم غير متاح الآن', 'This teacher is not available now'),
      'quran_teacher_only' => _t('بطاقة معلم القرآن للمعلمين فقط', 'Only teachers can have a Quran teacher card'),
      'quran_bad_value' => _t('قيمة غير مقبولة في البطاقة. راجع الاختيارات.', 'A value on the card is not accepted. Check the choices.'),
      'quran_self_log_off' => _t('تسجيل الحفظ بنفسك متوقف. معلمك يسجّله لك.', 'Logging your own progress is off. Your teacher records it for you.'),
      'quran_progress_forbidden' => _t('لا يمكنك تسجيل تقدّم هذا الطالب', 'You cannot record progress for this student'),
      'quran_student_required' => _t('اختر الطالب أولاً', 'Choose the student first'),
      'quran_not_your_student' => _t('هذا الطالب ليس مسجلاً في إحدى دوراتك', 'This student is not enrolled in one of your courses'),
      'quran_student_not_found' => _t('لا يمكنك رؤية تقدّم هذا الطالب', 'You cannot see this student\'s progress'),
      'quran_bad_surah' => _t('اختر سورة صحيحة', 'Choose a valid surah'),
      'quran_bad_range' => d['ayahs'] != null
          ? _t('الآيات من 1 إلى ${d['ayahs']}، والبداية قبل النهاية', 'Ayahs run from 1 to ${d['ayahs']}, and the start comes before the end')
          : _t('نطاق الآيات غير صحيح', 'The ayah range is not valid'),
      'LINK_NOT_FOUND' => _t('هذا الطالب غير مرتبط بحسابك', 'This student is not linked to your account'),
      _ => null,
    };

/// What to show for a failed Quran call.
String quranErrorText(Object e) {
  if (e is TimeoutException) return ApiMessages.timeout;
  final x = ApiException.from(e);
  return quranCodeText(x.code, apiErrorDetail(x)) ?? apiErrorText(x);
}

/// True when the server answered (any status): the entry is settled and must not be sent again.
bool quranDefiniteAnswer(Object e) => e is ApiException && e.statusCode > 0;

/// One student on the teacher's record sheet.
typedef QuranStudentRef = ({int id, String name, String? imageUrl});

class QuranApi {
  QuranApi({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static QuranMeta? _meta;
  static Future<QuranMeta>? _metaInflight;

  /// Loaded once per app run (114 names + 30 starts: it never changes).
  Future<QuranMeta> meta() {
    final hit = _meta;
    if (hit != null) return Future.value(hit);
    return _metaInflight ??= _api.get('/api/v1/quran/meta', auth: false).then((r) => _meta = QuranMeta.fromJson(r)).whenComplete(() {
      _metaInflight = null;
    });
  }

  @visibleForTesting
  static void setMetaForTest(QuranMeta? m) => _meta = m;

  Future<QuranTeacherList> teachers(QuranFilters f) async =>
      QuranTeacherList.fromJson(await _api.get('/api/v1/quran/teachers', queryParams: f.toQuery()));

  Future<QuranTeacher> teacher(int id) async => QuranTeacher.fromJson(await _api.get('/api/v1/quran/teachers/$id'));

  /// The course page's check before Enroll on a Quran program (QA_PHASE6 4.5): the teacher list's `gender_ok` for
  /// the signed-in student — the same flag the teacher page reads. The bilingual refusal when the booking would be
  /// refused for the gender rule, else null (also on any failure: the server still answers the 403 at checkout).
  Future<String?> bookingRefusal(int teacherId) async {
    try {
      final l = await teachers(QuranFilters.empty);
      for (final t in l.items) {
        if (t.userId == teacherId && t.genderOk == false) {
          return apiErrorText(ApiException(statusCode: 403, message: '', code: 'quran_gender_rule', body: const {'detail': {'reason': 'gender_differs'}}));
        }
      }
    } catch (_) {}
    return null;
  }

  Future<QuranTeacher> myCard() async => QuranTeacher.fromJson(await _api.get('/api/v1/me/quran/teacher-profile'));

  /// Replaces the card. [publish] true → published (or pending while content review is on), false → draft.
  Future<QuranTeacher> saveCard({
    required String gender,
    required String bio,
    String? ijazah,
    required List<String> goals,
    required List<String> sessionTypes,
    String? countryCode,
    required bool publish,
  }) async =>
      QuranTeacher.fromJson(await _api.put('/api/v1/me/quran/teacher-profile', body: {
        'gender': gender,
        'bio': bio,
        'ijazah': (ijazah ?? '').trim().isEmpty ? null : ijazah!.trim(),
        'goals': goals,
        'session_types': sessionTypes,
        'country_code': (countryCode ?? '').isEmpty ? null : countryCode,
        'publish': publish,
      }));

  Future<QuranProgress> myProgress() async => QuranProgress.fromJson(await _api.get('/api/v1/me/quran/progress'));

  Future<QuranProgress> studentProgress(int studentId) async =>
      QuranProgress.fromJson(await _api.get('/api/v1/quran/students/$studentId/progress'));

  Future<QuranProgress> childProgress(int childId) async =>
      QuranProgress.fromJson(await _api.get('/api/v1/parent/children/$childId/quran/progress'));

  Future<QuranSettings> settings() async => QuranSettings.fromJson(await _api.get('/api/v1/module-settings/quran'));

  /// POST one entry ([body] already holds its `client_id`) → the entry and whether it was a duplicate.
  Future<({QuranEntry entry, bool duplicate})> record(Map<String, dynamic> body) async {
    final r = await _api.post('/api/v1/quran/progress', body: body);
    final m = r is Map ? Map<String, dynamic>.from(r) : const <String, dynamic>{};
    return (entry: QuranEntry.fromJson(m['entry']), duplicate: m['duplicate'] == true);
  }

  Future<List<QuranStudentRef>> courseStudents(int courseId) async {
    final r = await _api.get('/api/v1/courses/$courseId/enrolled-students');
    if (r is! List) return const [];
    return [
      for (final e in r)
        if (e is Map && e['student_id'] is num)
          (id: (e['student_id'] as num).toInt(), name: '${e['name'] ?? ''}', imageUrl: e['image_url'] is String ? e['image_url'] as String : null),
    ];
  }

  /// The countries the card's country field offers: `[(code, name)]`; empty when the call fails.
  Future<List<(String, String)>> countries() async {
    try {
      final r = await _api.get('/api/v1/edu/countries', auth: false);
      if (r is! List) return const [];
      return [
        for (final e in r)
          if (e is Map && '${e['code'] ?? ''}'.length == 2)
            ('${e['code']}'.toUpperCase(), AppConfig.lang == 'ar' ? '${e['name_ar'] ?? e['code']}' : '${e['name_en'] ?? e['code']}'),
      ];
    } catch (_) {
      return const [];
    }
  }
}

/// Entries the network lost, per user, sent again with the same `client_id`.
class QuranOutbox {
  QuranOutbox._();

  /// Test hooks.
  static Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance;
  static Future<String> Function() userId = _savedUserId;

  static Future<String> _savedUserId() async {
    try {
      final u = (await StorageService.getInstance()).savedUser;
      return '${u?['id'] ?? 'anon'}';
    } catch (_) {
      return 'anon';
    }
  }

  static Future<String> _key() async => 'quran_outbox_${await userId()}';

  static Future<List<Map<String, dynamic>>> pending() async {
    try {
      final raw = (await prefs()).getString(await _key());
      if (raw == null) return [];
      final l = jsonDecode(raw);
      return l is List ? [for (final e in l) if (e is Map) Map<String, dynamic>.from(e)] : [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<Map<String, dynamic>> items) async {
    try {
      final p = await prefs();
      final k = await _key();
      if (items.isEmpty) {
        await p.remove(k);
      } else {
        await p.setString(k, jsonEncode(items));
      }
    } catch (_) {}
  }

  static Future<void> add(Map<String, dynamic> body) async {
    final items = await pending();
    if (items.any((e) => e['client_id'] == body['client_id'])) return;
    await _write([...items, body]);
  }

  /// Sends what is waiting. An entry leaves the box once the server answered it (saved, a duplicate, or refused);
  /// a network failure keeps it. Returns how many were saved and the texts of the refusals.
  static Future<({int sent, List<String> refused})> flush(QuranApi api) async {
    final items = await pending();
    if (items.isEmpty) return (sent: 0, refused: const <String>[]);
    final keep = <Map<String, dynamic>>[];
    final refused = <String>[];
    var sent = 0;
    for (final b in items) {
      try {
        await api.record(b);
        sent++;
      } catch (e) {
        if (quranDefiniteAnswer(e)) {
          refused.add(quranErrorText(e));
        } else {
          keep.add(b);
        }
      }
    }
    await _write(keep);
    return (sent: sent, refused: refused);
  }
}
