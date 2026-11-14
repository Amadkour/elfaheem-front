// lib/features/certificates/issue/cert_issue_photo_logic.dart
//
// Pure part of the certificate photo step (D-386, unit-tested in test/org/cert_issue_photos_test.dart): the server's
// photo status, the people still needing a photo and matching a pile of picked files to them by file name (the
// person's identifier or name, the rule the bulk upload promises on screen).
library;

import 'package:flutter_education_app/features/certificates/issue/cert_issue_logic.dart';

Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) _map(x)] : const [];

/// One person of the photo step. [key] is the draft row's uid (standalone) or `c<student id>` (course mode).
class IssuePhotoPerson {
  const IssuePhotoPerson({required this.key, required this.name, this.studentId, this.identifiers = const [], this.studentImage});

  final String key;
  final String name;
  final int? studentId;

  /// Everything a file may be named after besides the name: student number, national id, e-mail, username.
  final List<String> identifiers;

  /// Their profile picture, when they have one (shown, not sent).
  final String? studentImage;
}

class IssuePhotoStatus {
  const IssuePhotoStatus({this.photo = 'none', this.total = 0, this.missing = const [], this.complete = true});

  factory IssuePhotoStatus.fromJson(Map<String, dynamic> j) => IssuePhotoStatus(
        photo: '${j['photo'] ?? 'none'}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        complete: j['complete'] != false,
        missing: [
          for (final m in _maps(j['missing']))
            (index: (m['index'] as num?)?.toInt() ?? 0, name: '${m['name'] ?? ''}', studentId: (m['student_id'] as num?)?.toInt()),
        ],
      );

  final String photo;
  final int total;
  final List<({int index, String name, int? studentId})> missing;
  final bool complete;
}

/// A name / number as a file name carries it: extension dropped, separators as spaces, Arabic forms unified.
String certNormalizeFileName(String file) {
  final base = file.split(RegExp(r'[\\/]')).last.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return certNormalizeName(base.replaceAll(RegExp(r'[_\-.,()+]+'), ' '));
}

/// The result of matching picked files to people.
class PhotoMatch {
  const PhotoMatch({this.byPerson = const {}, this.unmatched = const [], this.ambiguous = const [], this.duplicates = const []});

  /// person key → index of the file.
  final Map<String, int> byPerson;

  /// File names that named nobody.
  final List<String> unmatched;

  /// File names that fit several people (the same name twice): the issuer uploads those one by one.
  final List<String> ambiguous;

  /// File names of a person who already got an earlier file.
  final List<String> duplicates;

  int get matched => byPerson.length;
}

/// Each file goes to the person whose identifier (student number, national id, e-mail, username, or a part of the file
/// name separated by "_" or "-" equal to one) or whose full name is the file name. An identifier wins over a name; a
/// name that several people share never matches anyone.
PhotoMatch certMatchPhotoFiles(List<String> fileNames, List<IssuePhotoPerson> people) {
  final byId = <String, Set<String>>{}, byName = <String, Set<String>>{};
  for (final p in people) {
    for (final raw in p.identifiers) {
      final v = certNormalizeFileName(raw);
      if (v.isNotEmpty) byId.putIfAbsent(v, () => {}).add(p.key);
    }
    final n = certNormalizeFileName(p.name);
    if (n.isNotEmpty) byName.putIfAbsent(n, () => {}).add(p.key);
  }
  final byPerson = <String, int>{};
  final unmatched = <String>[], ambiguous = <String>[], duplicates = <String>[];
  for (var i = 0; i < fileNames.length; i++) {
    final name = fileNames[i];
    final whole = certNormalizeFileName(name);
    Set<String>? hit = byId[whole];
    if (hit == null) {
      for (final part in whole.split(' ')) {
        final h = byId[part];
        if (h != null) {
          hit = h;
          break;
        }
      }
    }
    hit ??= byName[whole];
    if (hit == null) {
      unmatched.add(name);
    } else if (hit.length > 1) {
      ambiguous.add(name);
    } else if (byPerson.containsKey(hit.first)) {
      duplicates.add(name);
    } else {
      byPerson[hit.first] = i;
    }
  }
  return PhotoMatch(byPerson: byPerson, unmatched: unmatched, ambiguous: ambiguous, duplicates: duplicates);
}

/// A draft row as a person of the photo step.
IssuePhotoPerson certPhotoPersonOfRow(RecipientRow r, List<IssueColumn> columns) {
  final ids = <String>[
    for (final c in columns)
      if (c.key != 'student_name' && c.key != 'email') r.values[c.key] ?? '',
    r.email,
    if (r.student?.username != null) r.student!.username!,
    if (r.line != null) '${r.line}',
  ].where((v) => v.trim().isNotEmpty).toList();
  return IssuePhotoPerson(key: r.uid, name: r.name, studentId: r.student?.id, identifiers: ids, studentImage: r.student?.imageUrl);
}

/// POST photo-status: the same recipients the batch would get.
Map<String, dynamic> certPhotoStatusBody({
  required int designId,
  required IssueMode mode,
  int? orgId,
  int? courseId,
  int? certificateId,
  bool replaceExisting = false,
  List<String>? langs,
  List<Map<String, dynamic>> rows = const [],
}) =>
    {
      'design_id': designId,
      'mode': issueModeWire(mode),
      'org_id': ?orgId,
      if (mode == IssueMode.course && courseId != null) 'course_id': courseId,
      if (mode == IssueMode.course && certificateId != null) 'certificate_id': certificateId,
      if (mode == IssueMode.course) 'replace_existing': replaceExisting,
      if (langs != null && langs.isNotEmpty) 'langs': langs,
      'rows': rows,
    };
