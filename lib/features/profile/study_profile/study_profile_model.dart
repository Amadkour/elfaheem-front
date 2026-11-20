// lib/features/profile/study_profile/study_profile_model.dart
//
// A personal student's study data (D-790 – D-796): the values, their bilingual labels, the super admin's settings and
// the calls. Plain Dart (no widgets) so the form, the sign-up step, the home card, the admin pages and the tests share
// one source.
//
//   GET  /api/v1/me/study-profile              → StudyProfileView (profile, complete, missing, settings)
//   PUT  /api/v1/me/study-profile              the WHOLE profile (a missing field is cleared, dob included)
//   POST /api/v1/me/study-profile/dismiss      hide the home card for 30 days
//   GET|PUT /api/v1/admin/study-profile/settings   super admin
//   GET  /api/v1/auth/policy → `study_profile`  the same settings before sign-in (the sign-up step)
//   POST /api/v1/auth/register  `study_profile`  the sign-up step's values (stage + grade required)
library;

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/edu/edu_catalog.dart' show EduStage;

import 'package:flutter_education_app/features/admin/admin_common.dart' show t;

/// Kill switch of every study-data surface (the sign-up step, the profile row, the home card, the admin page).
const kStudyProfileFeatureKey = 'profile.study';

/// The educational stages, in the order they are offered.
const kStudyStages = ['primary', 'preparatory', 'secondary', 'university', 'graduate', 'other'];

/// How many grades / years a stage has (0 = no grade: a graduate or another learner).
int studyGradeCount(String? stage) => switch (stage) {
      'primary' => 6,
      'preparatory' || 'secondary' => 3,
      'university' => 7,
      _ => 0,
    };

const kStudyTracks = ['science', 'math', 'literary'];

/// The secondary track (science / math / literary) is asked from secondary 2 on.
bool studyTrackApplies(String? stage, int? grade) => stage == 'secondary' && grade != null && grade >= 2;

/// The fields the super admin may make required (stage + grade always are).
const kStudyOptionalFields = ['track', 'school_name', 'governorate', 'dob', 'parent_phone'];

/// Egypt's 27 governorates (code → Arabic, English) and `other` (outside Egypt / not listed: a city is typed then).
const kGovernorates = <String, (String, String)>{
  'cairo': ('القاهرة', 'Cairo'),
  'giza': ('الجيزة', 'Giza'),
  'alexandria': ('الإسكندرية', 'Alexandria'),
  'qalyubia': ('القليوبية', 'Qalyubia'),
  'sharqia': ('الشرقية', 'Sharqia'),
  'dakahlia': ('الدقهلية', 'Dakahlia'),
  'gharbia': ('الغربية', 'Gharbia'),
  'monufia': ('المنوفية', 'Monufia'),
  'beheira': ('البحيرة', 'Beheira'),
  'kafr_el_sheikh': ('كفر الشيخ', 'Kafr El Sheikh'),
  'damietta': ('دمياط', 'Damietta'),
  'port_said': ('بورسعيد', 'Port Said'),
  'ismailia': ('الإسماعيلية', 'Ismailia'),
  'suez': ('السويس', 'Suez'),
  'faiyum': ('الفيوم', 'Faiyum'),
  'beni_suef': ('بني سويف', 'Beni Suef'),
  'minya': ('المنيا', 'Minya'),
  'asyut': ('أسيوط', 'Asyut'),
  'sohag': ('سوهاج', 'Sohag'),
  'qena': ('قنا', 'Qena'),
  'luxor': ('الأقصر', 'Luxor'),
  'aswan': ('أسوان', 'Aswan'),
  'red_sea': ('البحر الأحمر', 'Red Sea'),
  'new_valley': ('الوادي الجديد', 'New Valley'),
  'matrouh': ('مطروح', 'Matrouh'),
  'north_sinai': ('شمال سيناء', 'North Sinai'),
  'south_sinai': ('جنوب سيناء', 'South Sinai'),
  'other': ('خارج مصر / أخرى', 'Outside Egypt / other'),
};

String studyStageLabel(String stage) => switch (stage) {
      'primary' => t('ابتدائي', 'Primary'),
      'preparatory' => t('إعدادي', 'Preparatory'),
      'secondary' => t('ثانوي', 'Secondary'),
      'university' => t('جامعة', 'University'),
      'graduate' => t('خرّيج', 'Graduate'),
      _ => t('أخرى', 'Other'),
    };

const _ordM = ['الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع'];
const _ordF = ['الأولى', 'الثانية', 'الثالثة', 'الرابعة', 'الخامسة', 'السادسة', 'السابعة'];

/// A grade chip's short label: "الثاني" / "Grade 2"; a university year: "الثانية" / "Year 2".
String studyGradeShort(String stage, int grade) {
  final i = (grade - 1).clamp(0, 6);
  return stage == 'university' ? t(_ordF[i], 'Year $grade') : t(_ordM[i], 'Grade $grade');
}

/// The full grade: "الصف الثاني الثانوي" / "Secondary, grade 2"; "الفرقة الرابعة" / "University, year 4".
String studyGradeLong(String stage, int grade) {
  final i = (grade - 1).clamp(0, 6);
  return switch (stage) {
    'primary' => t('الصف ${_ordM[i]} الابتدائي', 'Primary, grade $grade'),
    'preparatory' => t('الصف ${_ordM[i]} الإعدادي', 'Preparatory, grade $grade'),
    'secondary' => t('الصف ${_ordM[i]} الثانوي', 'Secondary, grade $grade'),
    'university' => t('الفرقة ${_ordF[i]}', 'University, year $grade'),
    _ => studyStageLabel(stage),
  };
}

String studyTrackLabel(String track) => switch (track) {
      'science' => t('علمي علوم', 'Science'),
      'math' => t('علمي رياضة', 'Mathematics'),
      _ => t('أدبي', 'Literary'),
    };

String studyGovernorateLabel(String code) {
  final g = kGovernorates[code];
  return g == null ? code : t(g.$1, g.$2);
}

String studyFieldLabel(String field) => switch (field) {
      'stage' => t('المرحلة الدراسية', 'Stage'),
      'grade' => t('الصف أو الفرقة', 'Grade or year'),
      'track' => t('الشعبة', 'Track'),
      'school_name' => t('المدرسة أو الجامعة', 'School or university'),
      'governorate' => t('المحافظة', 'Governorate'),
      'dob' => t('تاريخ الميلاد', 'Date of birth'),
      'parent_phone' => t('رقم ولي الأمر', "Parent's phone"),
      _ => field,
    };

/// One profile, as the server stores it. Immutable; [copyWith] keeps the dependent fields honest (a stage change
/// drops a grade it does not have and a track that no longer applies).
class StudyProfile {
  const StudyProfile({
    this.stage,
    this.grade,
    this.track,
    this.schoolName,
    this.governorate,
    this.city,
    this.parentPhone,
    this.dob,
    this.countryCode,
    this.stageId,
    this.gradeId,
    this.areaId,
    this.gender,
  });

  final String? stage;
  final int? grade;
  final String? track;
  final String? schoolName;
  final String? governorate;
  final String? city;
  final String? parentPhone;

  /// YYYY-MM-DD (users.dob).
  final String? dob;

  /// The catalog ids (Learning Hub, CONTRACT §3): the country, the stage and grade rows, the area (a governorate or a
  /// city) and `m` / `f`. Sent instead of the old keys when a stage id is set; the server writes the old keys itself.
  final String? countryCode;
  final int? stageId, gradeId, areaId;
  final String? gender;

  static const empty = StudyProfile();

  static String? _s(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  factory StudyProfile.fromJson(Map<String, dynamic>? j) {
    if (j == null) return empty;
    final g = j['grade'];
    return StudyProfile(
      stage: _s(j['stage']),
      grade: g is int ? g : int.tryParse('${g ?? ''}'),
      track: _s(j['track']),
      schoolName: _s(j['school_name']),
      governorate: _s(j['governorate']),
      city: _s(j['city']),
      parentPhone: _s(j['parent_phone']),
      dob: _s(j['dob']),
      countryCode: _s(j['country_code']),
      stageId: _n(j['stage_id']),
      gradeId: _n(j['grade_id']),
      areaId: _n(j['area_id']),
      gender: _s(j['gender']),
    );
  }

  static int? _n(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  /// The body of PUT /me/study-profile (every field: null clears it). [withDob] false for the sign-up, whose form
  /// sends the date of birth itself.
  Map<String, dynamic> toJson({bool withDob = true}) {
    final byIds = stageId != null;
    return {
      if (byIds) ...{
        'country_code': countryCode,
        'stage_id': stageId,
        'grade_id': gradeId,
        'area_id': areaId,
        'gender': gender,
        'track': track,
      } else ...{
        'stage': stage,
        'grade': grade,
        'track': studyTrackApplies(stage, grade) ? track : null,
        'governorate': governorate,
        'city': governorate == 'other' ? city : null,
        if (gender != null) 'gender': gender,
      },
      'school_name': schoolName,
      'parent_phone': parentPhone,
      if (withDob) 'dob': dob,
    };
  }

  /// The catalog choice (country, stage, grade, track, area, gender) replaced as one; the old keys follow the ids.
  StudyProfile withEdu({
    String? countryCode,
    int? stageId,
    int? gradeId,
    String? track,
    int? areaId,
    String? gender,
    String? stageKey,
    int? gradeNumber,
  }) =>
      StudyProfile(
        stage: stageKey ?? stage,
        grade: gradeNumber,
        track: track,
        schoolName: schoolName,
        governorate: governorate,
        city: city,
        parentPhone: parentPhone,
        dob: dob,
        countryCode: countryCode,
        stageId: stageId,
        gradeId: gradeId,
        areaId: areaId,
        gender: gender,
      );

  /// What is still missing when the stage and grade come from the catalog [stages] (ids), else the old rule.
  List<String> missingIn(List<EduStage>? stages, List<String> required) {
    if (stages == null || stages.isEmpty) return missing(required);
    EduStage? st;
    for (final s in stages) {
      if (s.id == stageId) st = s;
    }
    if (st == null) return const ['stage', 'grade'];
    return [
      if (st.hasGrades && st.grades.isNotEmpty && gradeId == null) 'grade',
      for (final f in required)
        if (f == 'governorate' ? areaId == null : (f == 'track' ? false : valueOf(f) == null)) f,
    ];
  }

  StudyProfile copyWith({
    String? stage,
    int? grade,
    String? track,
    String? schoolName,
    String? governorate,
    String? city,
    String? parentPhone,
    String? dob,
    bool clearTrack = false,
  }) {
    final st = stage ?? this.stage;
    var gr = grade ?? this.grade;
    if (stage != null && stage != this.stage) {
      final n = studyGradeCount(st);
      if (gr != null && (n == 0 || gr > n)) gr = null;
    }
    var tr = clearTrack ? null : (track ?? this.track);
    if (!studyTrackApplies(st, gr)) tr = null;
    return StudyProfile(
      stage: st,
      grade: gr,
      track: tr,
      schoolName: schoolName ?? this.schoolName,
      governorate: governorate ?? this.governorate,
      city: city ?? this.city,
      parentPhone: parentPhone ?? this.parentPhone,
      dob: dob ?? this.dob,
      countryCode: countryCode,
      stageId: stageId,
      gradeId: gradeId,
      areaId: areaId,
      gender: gender,
    );
  }

  /// A text field cleared by the person (copyWith cannot tell "unchanged" from "cleared").
  StudyProfile withText(String field, String value) {
    final v = value.trim().isEmpty ? null : value.trim();
    return StudyProfile(
      stage: stage,
      grade: grade,
      track: track,
      schoolName: field == 'school_name' ? v : schoolName,
      governorate: governorate,
      city: field == 'city' ? v : city,
      parentPhone: field == 'parent_phone' ? v : parentPhone,
      dob: field == 'dob' ? v : dob,
      countryCode: countryCode,
      stageId: stageId,
      gradeId: gradeId,
      areaId: areaId,
      gender: gender,
    );
  }

  Object? valueOf(String field) => switch (field) {
        'stage' => stage,
        'grade' => grade,
        'track' => track,
        'school_name' => schoolName,
        'governorate' => governorate,
        'dob' => dob,
        'parent_phone' => parentPhone,
        _ => null,
      };

  /// The fields still missing for [required] (the super admin's list); stage + grade always count.
  List<String> missing(List<String> required) {
    if (stage == null || !kStudyStages.contains(stage)) return const ['stage', 'grade'];
    return [
      if (studyGradeCount(stage) > 0 && grade == null) 'grade',
      for (final f in required)
        if (!(f == 'track' && !studyTrackApplies(stage, grade)) && valueOf(f) == null) f,
    ];
  }

  /// "الصف الثاني الثانوي · علمي رياضة" / "Secondary, grade 2 · Mathematics"; '' without a stage.
  String get summary {
    final s = stage;
    if (s == null) return '';
    return [
      if (grade != null) studyGradeLong(s, grade!) else studyStageLabel(s),
      if (track != null && studyTrackApplies(s, grade)) studyTrackLabel(track!),
    ].join(' · ');
  }

  /// "School · Governorate" (or the city for `other`); '' when neither is set.
  String get place => [
        ?schoolName,
        if (governorate != null) governorate == 'other' ? (city ?? studyGovernorateLabel('other')) : studyGovernorateLabel(governorate!),
      ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is StudyProfile &&
      other.stage == stage &&
      other.grade == grade &&
      other.track == track &&
      other.schoolName == schoolName &&
      other.governorate == governorate &&
      other.city == city &&
      other.parentPhone == parentPhone &&
      other.dob == dob &&
      other.countryCode == countryCode &&
      other.stageId == stageId &&
      other.gradeId == gradeId &&
      other.areaId == areaId &&
      other.gender == gender;

  @override
  int get hashCode => Object.hash(stage, grade, track, schoolName, governorate, city, parentPhone, dob, countryCode, stageId, gradeId, areaId, gender);
}

/// The super admin's settings (also in the public auth policy).
class StudySettings {
  const StudySettings({this.signupStep = true, this.homePrompt = true, this.required = const []});

  final bool signupStep;
  final bool homePrompt;

  /// Optional fields made required (kStudyOptionalFields order).
  final List<String> required;

  /// An older server without the block: the step stays off (it would refuse nothing, but nothing is stored either).
  static const off = StudySettings(signupStep: false, homePrompt: false);

  factory StudySettings.fromJson(dynamic j) {
    if (j is! Map) return off;
    return StudySettings(
      signupStep: j['signup_step'] != false,
      homePrompt: j['home_prompt'] != false,
      required: [
        for (final f in (j['required'] is List ? j['required'] as List : const []))
          if (kStudyOptionalFields.contains('$f')) '$f',
      ],
    );
  }

  Map<String, dynamic> toJson() => {'signup_step': signupStep, 'home_prompt': homePrompt, 'required': required};

  StudySettings copyWith({bool? signupStep, bool? homePrompt, List<String>? required}) => StudySettings(
        signupStep: signupStep ?? this.signupStep,
        homePrompt: homePrompt ?? this.homePrompt,
        required: required ?? this.required,
      );
}

class StudyProfileView {
  const StudyProfileView({required this.profile, required this.settings, this.missing = const []});

  final StudyProfile profile;
  final StudySettings settings;
  final List<String> missing;

  bool get complete => missing.isEmpty;

  factory StudyProfileView.fromJson(Map<String, dynamic> j) => StudyProfileView(
        profile: StudyProfile.fromJson(j['profile'] is Map ? Map<String, dynamic>.from(j['profile'] as Map) : null),
        settings: StudySettings.fromJson(j['settings']),
        missing: [for (final f in (j['missing'] is List ? j['missing'] as List : const [])) '$f'],
      );
}

/// The server's `study_*` codes in the person's language (the server's own text is Arabic + `message_en`).
String studyErrorText(Object error) {
  final e = ApiException.from(error);
  final known = eduErrorText(e.code ?? e.detail['code']?.toString());
  if (known != null) return known;
  final body = e.body;
  final detail = body is Map && body['detail'] is Map ? body['detail'] as Map : null;
  final en = detail?['message_en']?.toString();
  final ar = detail?['message']?.toString();
  if (detail != null && ar != null && ar.isNotEmpty) return t(ar, (en == null || en.isEmpty) ? ar : en);
  return e.message;
}

/// The fields a 422 `study_field_required` names (empty for any other error).
List<String> studyErrorFields(Object error) {
  final body = ApiException.from(error).body;
  final detail = body is Map && body['detail'] is Map ? body['detail'] as Map : null;
  final f = detail?['fields'];
  return f is List ? [for (final x in f) '$x'] : const [];
}

class StudyProfileApi {
  StudyProfileApi([ApiClient? api]) : _api = api ?? ApiClient();

  final ApiClient _api;
  static const _me = '/api/v1/me/study-profile';
  static const _admin = '/api/v1/admin/study-profile/settings';

  Future<StudyProfileView> load() async => StudyProfileView.fromJson(_map(await _api.get(_me)));

  Future<StudyProfileView> save(StudyProfile p) async => StudyProfileView.fromJson(_map(await _api.put(_me, body: p.toJson())));

  Future<void> dismiss() => _api.post('$_me/dismiss');

  Future<StudySettings> loadSettings() async => StudySettings.fromJson(await _api.get(_admin));

  Future<StudySettings> saveSettings(StudySettings s) async => StudySettings.fromJson(await _api.put(_admin, body: s.toJson()));

  static Map<String, dynamic> _map(dynamic r) => r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
}

/// The Learning Hub's 422 codes on the study profile, the teaching levels and the parent link, in the person's
/// language (null for any other code).
String? eduErrorText(String? code) => switch (code) {
      'edu_grade_mismatch' => t('هذا الصف لا يتبع المرحلة المختارة', 'That grade does not belong to the chosen stage'),
      'edu_stage_invalid' => t('المرحلة المختارة غير متاحة', 'That stage is not available'),
      'edu_area_invalid' => t('المنطقة المختارة غير صحيحة', 'That area is not valid'),
      'study_grade_required' => t('اختر الصف أو الفرقة', 'Pick your grade or year'),
      'consent_required' => t('يلزم موافقة ولي الأمر على ربط هذا الحساب', "A parent's consent is needed to link this account"),
      'consent_version_required' => t('تعذّر تسجيل الموافقة، حاول مرة أخرى', 'The consent could not be recorded, try again'),
      _ => null,
    };
