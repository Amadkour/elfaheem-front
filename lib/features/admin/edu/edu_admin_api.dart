// lib/features/admin/edu/edu_admin_api.dart
//
// The super admin's education-levels API (CONTRACT §2.3, `/api/v1/admin/edu`) with its own minimal models, so this page
// does not depend on the public catalog client. Every call goes through orgCall (never throws, toasts the error).
library;

import 'package:flutter_education_app/core/api_client.dart';

import '../../org/org_v3.dart';
import '../admin_common.dart' show asMapList;

const kAdminEduPath = '/api/v1/admin/edu';

/// One row of any level (stage, grade, subject, area): ids, names and the soft-delete state.
class EduRow {
  const EduRow({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    this.active = true,
    this.parentId,
    this.level,
    this.countryCode,
    this.children = const [],
    this.subjectIds = const [],
    this.hasGrades = true,
    this.kind = 'school',
  });

  final int id;
  final String key;
  final String nameAr;
  final String nameEn;
  final bool active;
  final int? parentId;
  final int? level;
  final String? countryCode;

  /// Grades of a stage.
  final List<EduRow> children;

  /// Subjects of a grade.
  final List<int> subjectIds;
  final bool hasGrades;
  final String kind;

  String name(bool ar) => (ar ? nameAr : nameEn).isNotEmpty ? (ar ? nameAr : nameEn) : (nameAr.isNotEmpty ? nameAr : nameEn);

  static EduRow from(Map<String, dynamic> m, {List<EduRow> children = const []}) => EduRow(
        id: (m['id'] as num?)?.toInt() ?? 0,
        key: '${m['key'] ?? ''}',
        nameAr: '${m['name_ar'] ?? ''}',
        nameEn: '${m['name_en'] ?? ''}',
        active: m['active'] != false,
        parentId: (m['parent_id'] as num?)?.toInt(),
        level: (m['level'] as num?)?.toInt(),
        countryCode: m['country_code'] as String?,
        children: children,
        subjectIds: [for (final x in (m['subject_ids'] as List? ?? const [])) (x as num).toInt()],
        hasGrades: m['has_grades'] != false,
        kind: '${m['kind'] ?? 'school'}',
      );
}

class EduCountryRow {
  const EduCountryRow({
    required this.code,
    required this.nameAr,
    required this.nameEn,
    this.active = true,
    this.labels = const {},
    this.currency,
    this.vatPercent = 0,
    this.pricesIncludeVat = false,
  });

  final String code;
  final String nameAr;
  final String nameEn;
  final bool active;

  /// Money in this country (learning hub phase 5, D-1336): the store's default currency and its VAT rule.
  final String? currency;
  final double vatPercent;
  final bool pricesIncludeVat;

  /// `{ '1': (ar, en), '2': (ar, en) }`: what the two area levels are called in this country.
  final Map<String, (String, String)> labels;

  String name(bool ar) => ar ? nameAr : nameEn;

  static EduCountryRow from(Map<String, dynamic> m) {
    final g = m['geo_labels'];
    final labels = <String, (String, String)>{};
    if (g is Map) {
      g.forEach((k, v) {
        if (v is Map) labels['$k'] = ('${v['ar'] ?? ''}', '${v['en'] ?? ''}');
      });
    }
    return EduCountryRow(
      code: '${m['code']}',
      nameAr: '${m['name_ar'] ?? m['code']}',
      nameEn: '${m['name_en'] ?? m['code']}',
      active: m['active'] != false,
      labels: labels,
      currency: '${m['currency'] ?? ''}'.trim().isEmpty ? null : '${m['currency']}'.trim(),
      vatPercent: (m['vat_percent'] as num?)?.toDouble() ?? 0,
      pricesIncludeVat: m['prices_include_vat'] == true,
    );
  }
}

/// The editor's tree for one country: stages (with grades), subjects and the area rows (both levels, flat).
class EduTree {
  const EduTree({required this.country, this.stages = const [], this.subjects = const [], this.areas = const []});

  final EduCountryRow country;
  final List<EduRow> stages;
  final List<EduRow> subjects;
  final List<EduRow> areas;

  List<EduRow> get roots => [for (final a in areas) if (a.parentId == null) a];
  List<EduRow> childrenOf(int id) => [for (final a in areas) if (a.parentId == id) a];

  static EduTree from(Map<String, dynamic> m) => EduTree(
        country: EduCountryRow.from(Map<String, dynamic>.from(m['country'] as Map? ?? const {})),
        stages: [
          for (final s in asMapList(m['stages'])) EduRow.from(s, children: [for (final g in asMapList(s['grades'])) EduRow.from(g)]),
        ],
        subjects: [for (final s in asMapList(m['subjects'])) EduRow.from(s)],
        areas: [for (final a in asMapList(m['areas'])) EduRow.from(a)],
      );
}

/// A mutation's answer: the row was deleted, or soft-deleted because it is in use.
class EduWrite {
  const EduWrite(this.call);
  final OrgCall call;
  bool get ok => call.ok;
  bool get deactivated => call.map['deactivated'] == true;
  int get inUse => (call.map['in_use'] as num?)?.toInt() ?? 0;
}

class EduAdminApi {
  const EduAdminApi();

  Future<List<EduCountryRow>?> countries() async {
    final r = await orgCall(() => ApiClient().get('$kAdminEduPath/countries'), quiet: true);
    if (!r.ok) return null;
    return [for (final c in asMapList(r.data)) EduCountryRow.from(c)];
  }

  Future<EduTree?> tree(String country) async {
    final r = await orgCall(() => ApiClient().get('$kAdminEduPath/catalog', queryParams: {'country': country}));
    return r.ok ? EduTree.from(r.map) : null;
  }

  Future<EduWrite> addCountry(Map<String, dynamic> body, String ok) async =>
      EduWrite(await orgCall(() => ApiClient().post('$kAdminEduPath/countries', body: body), ok: ok));

  Future<EduWrite> editCountry(String code, Map<String, dynamic> body, String ok) async =>
      EduWrite(await orgCall(() => ApiClient().patch('$kAdminEduPath/countries/$code', body: body), ok: ok));

  Future<EduWrite> add(String entity, Map<String, dynamic> body, String ok) async =>
      EduWrite(await orgCall(() => ApiClient().post('$kAdminEduPath/$entity', body: body), ok: ok));

  Future<EduWrite> edit(String entity, int id, Map<String, dynamic> body, String ok) async =>
      EduWrite(await orgCall(() => ApiClient().patch('$kAdminEduPath/$entity/$id', body: body), ok: ok));

  Future<EduWrite> remove(String entity, int id) async => EduWrite(await orgCall(() => ApiClient().delete('$kAdminEduPath/$entity/$id')));

  Future<EduWrite> setGradeSubjects(int gradeId, List<int> ids, String ok) async =>
      EduWrite(await orgCall(() => ApiClient().put('$kAdminEduPath/grades/$gradeId/subjects', body: {'subject_ids': ids}), ok: ok));

  Future<EduWrite> reorder(String entity, List<int> ids) async =>
      EduWrite(await orgCall(() => ApiClient().put('$kAdminEduPath/order', body: {'entity': entity, 'ids': ids})));
}
