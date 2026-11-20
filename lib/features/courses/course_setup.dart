// lib/features/courses/course_setup.dart — who a course is for and where it is held (Learning Hub phase 3, D-1314).
// Plain values parsed from the course response (`targets`, `subject`, `delivery_mode`, `country_code`, `area`,
// `address`); no widget and no provider here, so the form, the course page and the tests share one parse.
library;

import 'package:flutter_education_app/config/app_config.dart';

String _s(dynamic v) => v == null ? '' : '$v';
String _pick(String ar, String en) {
  final first = AppConfig.lang == 'ar' ? ar : en;
  return first.isNotEmpty ? first : (AppConfig.lang == 'ar' ? en : ar);
}

/// One audience of a course: a whole stage ([gradeId] null) or one grade of a stage.
class CourseTarget {
  const CourseTarget({
    required this.stageId,
    this.gradeId,
    this.stageAr = '',
    this.stageEn = '',
    this.gradeAr = '',
    this.gradeEn = '',
  });

  factory CourseTarget.fromJson(Map<String, dynamic> j) => CourseTarget(
        stageId: (j['stage_id'] as num?)?.toInt() ?? 0,
        gradeId: (j['grade_id'] as num?)?.toInt(),
        stageAr: _s(j['stage_ar']),
        stageEn: _s(j['stage_en']),
        gradeAr: _s(j['grade_ar']),
        gradeEn: _s(j['grade_en']),
      );

  final int stageId;
  final int? gradeId;
  final String stageAr, stageEn, gradeAr, gradeEn;

  bool get wholeStage => gradeId == null;
  String get stageName => _pick(stageAr, stageEn);
  String get gradeName => _pick(gradeAr, gradeEn);

  /// "Secondary - Grade 2", or the stage alone for a whole-stage target.
  String get label => wholeStage ? stageName : '$stageName - $gradeName';

  Map<String, dynamic> toJson() => {'stage_id': stageId, 'grade_id': gradeId};

  @override
  bool operator ==(Object other) => other is CourseTarget && other.stageId == stageId && other.gradeId == gradeId;
  @override
  int get hashCode => Object.hash(stageId, gradeId);
}

/// A named catalog row (a subject or an area).
class CourseNamed {
  const CourseNamed({required this.id, this.nameAr = '', this.nameEn = '', this.parent});

  static CourseNamed? from(dynamic j) {
    if (j is! Map || j['id'] == null) return null;
    return CourseNamed(
      id: (j['id'] as num).toInt(),
      nameAr: _s(j['name_ar']),
      nameEn: _s(j['name_en']),
      parent: CourseNamed.from(j['parent']),
    );
  }

  final int id;
  final String nameAr, nameEn;

  /// The level-1 area of a level-2 one.
  final CourseNamed? parent;
  String get name => _pick(nameAr, nameEn);
}

class CourseSetup {
  const CourseSetup({
    this.deliveryMode = 'online',
    this.countryCode,
    this.subject,
    this.area,
    this.address,
    this.targets = const [],
  });

  factory CourseSetup.fromJson(Map<String, dynamic> j) {
    final addr = (j['address'] as String?)?.trim();
    return CourseSetup(
      deliveryMode: const {'online', 'in_person', 'both'}.contains(j['delivery_mode']) ? '${j['delivery_mode']}' : 'online',
      countryCode: j['country_code'] as String?,
      subject: CourseNamed.from(j['subject']),
      area: CourseNamed.from(j['area']),
      address: addr == null || addr.isEmpty ? null : addr,
      targets: [
        for (final t in (j['targets'] as List? ?? const []))
          if (t is Map) CourseTarget.fromJson(Map<String, dynamic>.from(t)),
      ],
    );
  }

  /// online | in_person | both.
  final String deliveryMode;
  final String? countryCode;
  final CourseNamed? subject, area;

  /// Only for the teacher, admins and enrolled students (the server leaves it out otherwise).
  final String? address;
  final List<CourseTarget> targets;

  bool get inPerson => deliveryMode != 'online';

  /// Nothing to show: an older server, or a course that has none of it.
  bool get isEmpty => targets.isEmpty && subject == null && area == null && !inPerson;
}
