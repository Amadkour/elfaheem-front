// lib/features/quran/quran_models.dart — Quran memorization (Learning Hub Phase 6, D-1347): the wire models and
// their bilingual labels. No Quran text anywhere: surah names, ayah counts and juz boundaries only (D-1345).
//
//   QuranMeta           GET /quran/meta: 114 surahs (names + ayah counts) and the 30 juz starts
//   QuranTeacher        a published teacher card with their quran courses (`gender_ok` on the list only)
//   QuranTeacherList    GET /quran/teachers: items + the platform's `gender_matching`
//   QuranFilters        the list's gender / goal / session-type filters ↔ the query params
//   QuranEntry          one progress entry (POST /quran/progress answers it)
//   QuranProgress       GET /me/quran/progress (and the teacher's / parent's copies): per surah, per juz, recent
//   QuranSettings       GET /module-settings/quran values (self_log, gender_matching, …)
library;

import 'package:flutter_education_app/config/app_config.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

String _str(Object? v) => v is String ? v : (v == null ? '' : '$v');

String? _strOrNull(Object? v) {
  final s = _str(v).trim();
  return s.isEmpty ? null : s;
}

List<String> _strs(Object? v) => v is List ? [for (final e in v) if (e != null) '$e'] : const [];

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : const [];

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

// ═════════════════════════════════════════════════════════════════════════════
//  Labels
// ═════════════════════════════════════════════════════════════════════════════

const quranGoals = ['memorization', 'tajweed', 'revision'];
const quranSessionTypes = ['individual', 'group'];
const quranGenders = ['m', 'f'];

/// The kinds of a progress entry are the goals.
const quranKinds = quranGoals;

String quranGoalLabel(String g) => switch (g) {
      'memorization' => _t('حفظ', 'Memorization'),
      'tajweed' => _t('تجويد', 'Tajweed'),
      'revision' => _t('مراجعة', 'Revision'),
      _ => g,
    };

String quranSessionLabel(String s) => switch (s) {
      'individual' => _t('فردي', 'One to one'),
      'group' => _t('حلقة جماعية', 'Group circle'),
      _ => s,
    };

/// A teacher's gender as the list says it: "Male teacher" / "Female teacher".
String quranGenderLabel(String? g) => switch (g) {
      'm' => _t('معلم', 'Male teacher'),
      'f' => _t('معلمة', 'Female teacher'),
      _ => _t('غير محدد', 'Not set'),
    };

/// Grades 1–5.
String quranGradeLabel(int g) => switch (g) {
      1 => _t('ضعيف', 'Weak'),
      2 => _t('مقبول', 'Fair'),
      3 => _t('جيد', 'Good'),
      4 => _t('جيد جداً', 'Very good'),
      5 => _t('ممتاز', 'Excellent'),
      _ => '$g',
    };

// ═════════════════════════════════════════════════════════════════════════════
//  Meta
// ═════════════════════════════════════════════════════════════════════════════

class QuranSurah {
  const QuranSurah({required this.number, required this.nameAr, required this.nameEn, required this.ayahs});

  factory QuranSurah.fromJson(Map<String, dynamic> j) =>
      QuranSurah(number: _int(j['number']) ?? 0, nameAr: _str(j['name_ar']), nameEn: _str(j['name_en']), ayahs: _int(j['ayahs']) ?? 0);

  final int number;
  final String nameAr, nameEn;
  final int ayahs;

  String get name => AppConfig.lang == 'ar' ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
}

/// Where a juz starts.
class QuranJuzStart {
  const QuranJuzStart({required this.juz, required this.surah, required this.ayah});

  factory QuranJuzStart.fromJson(Map<String, dynamic> j) {
    final s = _map(j['start']);
    return QuranJuzStart(juz: _int(j['juz']) ?? 0, surah: _int(s['surah']) ?? 1, ayah: _int(s['ayah']) ?? 1);
  }

  final int juz, surah, ayah;
}

int _pos(int surah, int ayah) => surah * 1000 + ayah;

class QuranMeta {
  QuranMeta({required this.surahs, required this.juz, required this.totalAyahs});

  factory QuranMeta.fromJson(Object? body) {
    final j = _map(body);
    final surahs = [for (final s in _maps(j['surahs'])) QuranSurah.fromJson(s)]..sort((a, b) => a.number.compareTo(b.number));
    final juz = [for (final s in _maps(j['juz'])) QuranJuzStart.fromJson(s)]..sort((a, b) => a.juz.compareTo(b.juz));
    return QuranMeta(
      surahs: surahs,
      juz: juz,
      totalAyahs: _int(j['total_ayahs']) ?? surahs.fold<int>(0, (a, s) => a + s.ayahs),
    );
  }

  final List<QuranSurah> surahs;
  final List<QuranJuzStart> juz;
  final int totalAyahs;

  QuranSurah? surah(int? n) {
    if (n == null || n < 1 || n > surahs.length) return null;
    final s = surahs[n - 1];
    return s.number == n ? s : surahs.where((e) => e.number == n).firstOrNull;
  }

  String surahName(int n) => surah(n)?.name ?? '$n';

  /// The surahs that have at least one ayah inside juz [j].
  List<QuranSurah> surahsInJuz(int j) {
    final i = juz.indexWhere((e) => e.juz == j);
    if (i < 0) return const [];
    final from = _pos(juz[i].surah, juz[i].ayah);
    final to = i + 1 < juz.length ? _pos(juz[i + 1].surah, juz[i + 1].ayah) : 1 << 30; // exclusive
    return [
      for (final s in surahs)
        if (_pos(s.number, 1) < to && _pos(s.number, s.ayahs) >= from) s,
    ];
  }

  /// The juz that ayah [ayah] of surah [surah] sits in.
  int juzOf(int surah, int ayah) {
    final p = _pos(surah, ayah);
    var j = 1;
    for (final e in juz) {
      if (_pos(e.surah, e.ayah) <= p) j = e.juz;
    }
    return j;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Teachers
// ═════════════════════════════════════════════════════════════════════════════

/// A quran program (it IS a course): booking goes through the course page and its checkout.
class QuranCourse {
  const QuranCourse({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.fees = 0,
    this.currency,
    this.imageUrl,
    this.deliveryMode,
    this.countryCode,
  });

  factory QuranCourse.fromJson(Map<String, dynamic> j) => QuranCourse(
        id: _int(j['id']) ?? 0,
        nameAr: _str(j['name_ar']),
        nameEn: _str(j['name_en']),
        fees: _dbl(j['fees']),
        currency: _strOrNull(j['currency']),
        imageUrl: _strOrNull(j['image_url']),
        deliveryMode: _strOrNull(j['delivery_mode']),
        countryCode: _strOrNull(j['country_code']),
      );

  final int id;
  final String nameAr, nameEn;
  final double fees;
  final String? currency, imageUrl, deliveryMode, countryCode;

  String get name => AppConfig.lang == 'ar' ? (nameAr.isNotEmpty ? nameAr : nameEn) : (nameEn.isNotEmpty ? nameEn : nameAr);
}

class QuranTeacher {
  const QuranTeacher({
    required this.userId,
    this.name = '',
    this.avatarUrl,
    this.gender,
    this.bio = '',
    this.ijazah,
    this.goals = const [],
    this.sessionTypes = const [],
    this.countryCode,
    this.verified = false,
    this.courses = const [],
    this.genderOk,
    this.status,
  });

  factory QuranTeacher.fromJson(Object? body) {
    final j = _map(body);
    return QuranTeacher(
      userId: _int(j['user_id']) ?? 0,
      name: _str(j['name']),
      avatarUrl: _strOrNull(j['avatar_url']),
      gender: _strOrNull(j['gender']),
      bio: _str(j['bio']),
      ijazah: _strOrNull(j['ijazah']),
      goals: _strs(j['goals']),
      sessionTypes: _strs(j['session_types']),
      countryCode: _strOrNull(j['country_code']),
      verified: j['verified'] == true,
      courses: [for (final c in _maps(j['courses'])) QuranCourse.fromJson(c)],
      genderOk: j['gender_ok'] is bool ? j['gender_ok'] as bool : null,
      status: _strOrNull(j['status']),
    );
  }

  final int userId;
  final String name;
  final String? avatarUrl, gender;
  final String bio;
  final String? ijazah;
  final List<String> goals, sessionTypes;
  final String? countryCode;
  final bool verified;
  final List<QuranCourse> courses;

  /// The list's answer: false = booking will be refused (`gender_matching = same`). Null on a single card.
  final bool? genderOk;

  /// The teacher's own card only: null before the first save, then draft | pending | published.
  final String? status;
}

class QuranTeacherList {
  const QuranTeacherList({required this.items, required this.total, this.genderMatching = 'off'});

  factory QuranTeacherList.fromJson(Object? body) {
    final j = _map(body);
    final items = [for (final t in _maps(j['items'])) QuranTeacher.fromJson(t)];
    return QuranTeacherList(items: items, total: _int(j['total']) ?? items.length, genderMatching: _strOrNull(j['gender_matching']) ?? 'off');
  }

  final List<QuranTeacher> items;
  final int total;

  /// off | same | prefer.
  final String genderMatching;
}

class QuranFilters {
  const QuranFilters({this.gender, this.goal, this.sessionType});

  static const empty = QuranFilters();

  final String? gender, goal, sessionType;

  bool get isEmpty => gender == null && goal == null && sessionType == null;

  int get activeCount => [gender, goal, sessionType].where((e) => e != null).length;

  QuranFilters withGender(String? v) => QuranFilters(gender: v, goal: goal, sessionType: sessionType);

  QuranFilters withGoal(String? v) => QuranFilters(gender: gender, goal: v, sessionType: sessionType);

  QuranFilters withSession(String? v) => QuranFilters(gender: gender, goal: goal, sessionType: v);

  Map<String, dynamic> toQuery() => {'gender': ?gender, 'goal': ?goal, 'session_type': ?sessionType};

  @override
  bool operator ==(Object other) =>
      other is QuranFilters && other.gender == gender && other.goal == goal && other.sessionType == sessionType;

  @override
  int get hashCode => Object.hash(gender, goal, sessionType);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Progress
// ═════════════════════════════════════════════════════════════════════════════

class QuranEntry {
  const QuranEntry({
    required this.id,
    required this.surah,
    required this.fromAyah,
    required this.toAyah,
    required this.kind,
    this.studentId,
    this.teacherId,
    this.courseId,
    this.grade,
    this.note,
    this.clientId,
    this.recordedBy,
    this.recordedAt,
  });

  factory QuranEntry.fromJson(Object? body) {
    final j = _map(body);
    return QuranEntry(
      id: _int(j['id']) ?? 0,
      studentId: _int(j['student_id']),
      teacherId: _int(j['teacher_id']),
      courseId: _int(j['course_id']),
      surah: _int(j['surah']) ?? 1,
      fromAyah: _int(j['from_ayah']) ?? 1,
      toAyah: _int(j['to_ayah']) ?? 1,
      kind: _str(j['kind']),
      grade: _int(j['grade']),
      note: _strOrNull(j['note']),
      clientId: _strOrNull(j['client_id']),
      recordedBy: _int(j['recorded_by']),
      recordedAt: _strOrNull(j['recorded_at']),
    );
  }

  final int id;
  final int? studentId, teacherId, courseId;
  final int surah, fromAyah, toAyah;
  final String kind;
  final int? grade;
  final String? note, clientId;
  final int? recordedBy;

  /// ISO instant (UTC); drawn with AppTime.
  final String? recordedAt;

  int get ayahCount => toAyah - fromAyah + 1;
}

class QuranSurahProgress {
  const QuranSurahProgress({required this.surah, required this.memorized, required this.total});

  final int surah, memorized, total;

  double get fraction => total <= 0 ? 0 : (memorized / total).clamp(0.0, 1.0);
}

class QuranProgress {
  const QuranProgress({
    this.surahs = const {},
    this.juz = const {},
    this.recent = const [],
    this.memorizedTotal = 0,
    this.totalAyahs = 6236,
  });

  factory QuranProgress.fromJson(Object? body) {
    final j = _map(body);
    final surahs = <int, QuranSurahProgress>{};
    for (final s in _maps(j['surahs'])) {
      final n = _int(s['surah']);
      if (n == null) continue;
      surahs[n] = QuranSurahProgress(surah: n, memorized: _int(s['memorized_ayahs']) ?? 0, total: _int(s['total_ayahs']) ?? 0);
    }
    final juz = <int, double>{};
    for (final e in _maps(j['juz'])) {
      final n = _int(e['juz']);
      if (n != null) juz[n] = _dbl(e['percent']).clamp(0.0, 100.0);
    }
    return QuranProgress(
      surahs: surahs,
      juz: juz,
      recent: [for (final e in _maps(j['recent'])) QuranEntry.fromJson(e)],
      memorizedTotal: _int(j['memorized_total']) ?? 0,
      totalAyahs: _int(j['total_ayahs']) ?? 6236,
    );
  }

  /// Surahs with any memorized ayah.
  final Map<int, QuranSurahProgress> surahs;

  /// Juz 1–30 → percent memorized (0–100).
  final Map<int, double> juz;
  final List<QuranEntry> recent;
  final int memorizedTotal, totalAyahs;

  /// 0–100.
  double get percent => totalAyahs <= 0 ? 0 : (memorizedTotal * 100 / totalAyahs).clamp(0.0, 100.0);

  int get juzDone => juz.values.where((p) => p >= 100).length;

  int get surahsDone => surahs.values.where((s) => s.total > 0 && s.memorized >= s.total).length;

  bool get isEmpty => memorizedTotal == 0 && recent.isEmpty;
}

class QuranSettings {
  const QuranSettings({this.selfLog = true, this.genderMatching = 'off', this.verificationRequired = false, this.reviewRequired = false});

  factory QuranSettings.fromJson(Object? body) {
    final v = _map(_map(body)['values']);
    return QuranSettings(
      selfLog: v['self_log'] is bool ? v['self_log'] as bool : true,
      genderMatching: _strOrNull(v['gender_matching']) ?? 'off',
      verificationRequired: v['teacher_verification_required'] == true,
      reviewRequired: v['content_review_required'] == true,
    );
  }

  final bool selfLog;
  final String genderMatching;
  final bool verificationRequired, reviewRequired;
}
