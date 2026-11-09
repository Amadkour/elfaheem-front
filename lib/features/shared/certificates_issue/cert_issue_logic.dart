// lib/features/shared/certificates_issue/cert_issue_logic.dart
//
// Pure part of certificate issuing (no Flutter widgets, unit-tested in test/org/cert_issue_test.dart): the wire
// models of /api/v1/certificate-issuing (../back/routers/certificate_issue_router.py, service
// services/certificate_issue_service.py), the recipients being reviewed before a batch ([RecipientDraft]: rows from
// the paste / sheet check, from the student search or from a saved list; edit · remove · pick the right candidate ·
// manual recipients · duplicates · summary), the request bodies and the server codes in the reader's language.
//
// A row is READY when it has no problem and its person is resolved (matched, a chosen candidate, or an unmatched
// name issued as a manual recipient); NEEDS ATTENTION when a value is missing / wrong, it repeats an earlier row or
// several students carry the name; SKIPPED when it is an unmatched name and manual recipients are switched off.
// Only ready rows go into the batch.
library;

import '../../../config/app_config.dart';
import '../../../core/api_client.dart';
import '../../../core/api_error_text.dart';

String _t(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

const String kCertIssueBase = '/api/v1/certificate-issuing';
const String kCertVerifyBase = '/api/v1/public/certificates/verify';
const String kCertIssueFeature = 'certificates.standalone';
const String _emailKey = 'email';
const int kCertMaxValueLen = 300;

// ─────────────────────────────────────────────────────────────────────────────
// Small parsing helpers
// ─────────────────────────────────────────────────────────────────────────────

int _int(Object? v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? d;
int? _intOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
String? _str(Object? v) {
  final s = v?.toString().trim();
  return s == null || s.isEmpty ? null : s;
}

Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) => v is List ? [for (final x in v) if (x is Map) _map(x)] : const [];
List<String> _strings(Object? v) => v is List ? [for (final x in v) if (x != null) '$x'] : const [];

/// The server's naive-UTC ISO stamps (no offset = UTC) as a UTC instant, or null.
DateTime? certUtc(Object? v) {
  if (v is! String || v.trim().isEmpty) return null;
  final s = v.trim();
  final zoned = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false).hasMatch(s);
  return DateTime.tryParse(zoned ? s : '${s}Z')?.toUtc();
}

/// The normalised form the server compares names with (services/certificate_issue_service.normalize_ar):
/// Arabic diacritics / tatweel stripped, alef / ya / ta-marbuta forms unified, Arabic digits → ASCII, lower-cased,
/// whitespace collapsed. For COMPARISON only — never shown or sent.
String certNormalizeName(String? value) {
  final b = StringBuffer();
  for (final r in (value ?? '').runes) {
    if ((r >= 0x0610 && r < 0x061B) || (r >= 0x064B && r < 0x0660) || r == 0x0670 || (r >= 0x06D6 && r < 0x06EE) ||
        r == 0x0640) {
      continue;
    }
    var x = r;
    if (x == 0x0623 || x == 0x0625 || x == 0x0622 || x == 0x0671) {
      x = 0x0627;
    } else if (x == 0x0649) {
      x = 0x064A;
    } else if (x == 0x0629) {
      x = 0x0647;
    } else if (x >= 0x0660 && x <= 0x0669) {
      x = 0x30 + x - 0x0660;
    } else if (x >= 0x06F0 && x <= 0x06F9) {
      x = 0x30 + x - 0x06F0;
    }
    b.writeCharCode(x);
  }
  return b.toString().toLowerCase().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
}

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool certValidEmail(String v) => _emailRe.hasMatch(v.trim());

// ─────────────────────────────────────────────────────────────────────────────
// Template: the columns the issuer fills
// ─────────────────────────────────────────────────────────────────────────────

class IssueColumn {
  const IssueColumn({required this.key, required this.labelAr, required this.labelEn, this.required = true});

  factory IssueColumn.fromJson(Map<String, dynamic> j) {
    final key = '${j['key'] ?? ''}';
    return IssueColumn(
      key: key,
      labelAr: _str(j['label_ar']) ?? key,
      labelEn: _str(j['label_en']) ?? key,
      required: j['required'] != false && key != _emailKey,
    );
  }

  final String key;
  final String labelAr;
  final String labelEn;
  final bool required;

  String get label => AppConfig.lang == 'ar' ? labelAr : labelEn;

  Map<String, dynamic> toJson() => {'key': key, 'label_ar': labelAr, 'label_en': labelEn};
}

/// GET designs/{id}/columns → the columns, the design's languages and the limits.
class IssueTemplate {
  const IssueTemplate({required this.columns, required this.langs, this.maxRows = 5000, this.maxUploadBytes = 5242880, this.photo = 'none', this.printsTeacher = false, this.teacherDefault = ''});

  factory IssueTemplate.fromJson(Map<String, dynamic> j) => IssueTemplate(
        columns: [for (final c in _maps(j['columns'])) IssueColumn.fromJson(c)],
        langs: _strings(j['langs']).isEmpty ? const ['ar'] : _strings(j['langs']),
        maxRows: _int(j['max_rows'], 5000),
        maxUploadBytes: _int(j['max_upload_bytes'], 5242880),
        photo: _str(j['photo']) ?? 'none',
        printsTeacher: j['prints_teacher'] == true,
        teacherDefault: _str(j['teacher_default']) ?? '',
      );

  /// Does the design print the instructor's name (D-400); false from an older server.
  final bool printsTeacher;

  /// What the instructor field starts with: the issuer's own name when they issue for themselves.
  final String teacherDefault;

  /// Does the design hold a student photo: `required` · `optional` · `none` (D-386).
  final String photo;

  final List<IssueColumn> columns;
  final List<String> langs;
  final int maxRows;
  final int maxUploadBytes;

  /// The columns other than the recipient's name (and e-mail) — what course mode fills once for everyone.
  List<IssueColumn> get extraColumns => [for (final c in columns) if (c.key != 'student_name' && c.key != _emailKey) c];
}

/// D-400: does this batch need an instructor's name typed in? A recipient with no platform account has no course to take
/// it from, so a standalone batch that prints the name needs it for every such person without their own value.
bool certTeacherRequired({required bool standalone, required IssueTemplate? template, required Iterable<Map<String, dynamic>> rows}) {
  if (!standalone || template == null || !template.printsTeacher) return false;
  return rows.any((r) {
    if (r['student_id'] != null) return false;
    final v = r['values'];
    final own = v is Map ? '${v['teacher_name'] ?? ''}' : '';
    return own.trim().isEmpty;
  });
}

/// The server's code of a failed issuing call (empty when it has none).
String certIssueErrorCode(Object error) {
  final e = ApiException.from(error);
  return e.code ?? '${apiErrorDetail(e)['code'] ?? ''}';
}

/// One example line in the expected order (shown above the paste box).
String certExampleLine(List<IssueColumn> columns) {
  const ar = {'student_name': 'محمد أحمد علي', 'course_name': 'أساسيات البرمجة', 'grade': 'ممتاز', 'score': '95',
      'rank': '1', 'hours': '30', _emailKey: 'student@example.com'};
  const en = {'student_name': 'Mohamed Ahmed Ali', 'course_name': 'Programming Fundamentals', 'grade': 'Excellent',
      'score': '95', 'rank': '1', 'hours': '30', _emailKey: 'student@example.com'};
  final ex = AppConfig.lang == 'ar' ? ar : en;
  return [for (final c in columns) ex[c.key] ?? c.label].join(', ');
}

// ─────────────────────────────────────────────────────────────────────────────
// People and rows
// ─────────────────────────────────────────────────────────────────────────────

class StudentBrief {
  const StudentBrief({required this.id, required this.name, this.username, this.emailHint, this.imageUrl});

  factory StudentBrief.fromJson(Map<String, dynamic> j) => StudentBrief(
        id: _int(j['id']),
        name: _str(j['name']) ?? '',
        username: _str(j['username']),
        emailHint: _str(j['email_hint']) ?? _str(j['email']) ?? _str(j['gmail']),
        imageUrl: _str(j['image_url']),
      );

  final int id;
  final String name;
  final String? username;
  final String? emailHint;
  final String? imageUrl;

  /// "@sara · s***@mail.com" — what tells two people of the same name apart.
  String get hint => [if (username != null) '@$username', ?emailHint].join(' · ');
}

/// One problem on a row, from the server's check or found here after an edit.
class RowIssue {
  const RowIssue({required this.code, this.messageAr, this.messageEn, this.column, this.ofLine});

  factory RowIssue.fromJson(Map<String, dynamic> j) => RowIssue(
        code: '${j['code'] ?? ''}',
        messageAr: _str(j['message_ar']),
        messageEn: _str(j['message_en']),
        column: _str(j['column']),
        ofLine: _intOrNull(j['of_line']),
      );

  final String code;
  final String? messageAr;
  final String? messageEn;
  final String? column;
  final int? ofLine;

  /// The sentence shown under the row ("Empty value: Grade", "Duplicate of line 3").
  String text(List<IssueColumn> columns) {
    final col = column == null ? null : columns.where((c) => c.key == column).map((c) => c.label).firstOrNull;
    final base = switch (code) {
      'too_few_values' => _t('قيم أقل من الأعمدة المطلوبة', 'Fewer values than the expected columns'),
      'too_many_values' => _t('قيم أكثر من الأعمدة المطلوبة', 'More values than the expected columns'),
      'empty_value' => _t('قيمة فارغة', 'Empty value'),
      'duplicate' => ofLine == null ? _t('مكرر', 'Duplicate') : _t('مكرر للسطر $ofLine', 'Duplicate of line $ofLine'),
      'bad_email' => _t('بريد إلكتروني غير صحيح', 'Invalid email'),
      'too_long' => _t('القيمة أطول من المسموح', 'Value is too long'),
      _ => (AppConfig.lang == 'ar' ? messageAr : messageEn) ?? messageEn ?? messageAr ?? code,
    };
    return col == null || code == 'duplicate' ? base : '$base: $col';
  }
}

enum MatchState { matched, ambiguous, unmatched }

MatchState _matchOf(String? s) => switch (s) {
      'matched' => MatchState.matched,
      'ambiguous' => MatchState.ambiguous,
      _ => MatchState.unmatched,
    };

/// Where a row came from.
enum RowSource { paste, file, search, list, manual }

/// How a row stands in the review.
enum RowState { ready, attention, skipped }

class RecipientRow {
  const RecipientRow({
    required this.uid,
    required this.values,
    required this.source,
    this.line,
    this.structural = const [],
    this.match = MatchState.unmatched,
    this.student,
    this.candidates = const [],
    this.manual,
    this.photoUrl,
  });

  /// The photo uploaded for this certificate (a non-user, or nobody on file), sent as `photo_url`.
  final String? photoUrl;

  /// Local id (stable across edits).
  final String uid;

  /// The line in the pasted text / sheet (null for a searched student).
  final int? line;
  final Map<String, String> values;
  final RowSource source;

  /// Count problems from the server's check (too few / too many values) — cleared by the first edit.
  final List<RowIssue> structural;
  final MatchState match;
  final StudentBrief? student;
  final List<StudentBrief> candidates;

  /// Issue an unmatched name as a manual recipient: null = follow [RecipientDraft.manualDefault].
  final bool? manual;

  String get name => values['student_name']?.trim() ?? '';
  String get email => values[_emailKey]?.trim() ?? '';

  RecipientRow copyWith({
    Map<String, String>? values,
    List<RowIssue>? structural,
    MatchState? match,
    StudentBrief? student,
    bool clearStudent = false,
    List<StudentBrief>? candidates,
    bool? manual,
    String? photoUrl,
  }) =>
      RecipientRow(
        uid: uid,
        line: line,
        source: source,
        values: values ?? this.values,
        structural: structural ?? this.structural,
        match: match ?? this.match,
        student: clearStudent ? null : (student ?? this.student),
        candidates: candidates ?? this.candidates,
        manual: manual ?? this.manual,
        photoUrl: photoUrl ?? this.photoUrl,
      );
}

/// The review's counters.
class IssueSummary {
  const IssueSummary({
    this.total = 0,
    this.ready = 0,
    this.attention = 0,
    this.skipped = 0,
    this.matched = 0,
    this.ambiguous = 0,
    this.unmatched = 0,
    this.duplicates = 0,
  });

  final int total, ready, attention, skipped, matched, ambiguous, unmatched, duplicates;

  /// "12 ready · 3 need attention"
  String get label {
    final parts = [
      _t('$ready جاهز', '$ready ready'),
      if (attention > 0) _t('$attention تحتاج مراجعة', '$attention need attention'),
      if (skipped > 0) _t('$skipped لن تُصدر', '$skipped skipped'),
    ];
    return parts.join(' · ');
  }
}

/// The recipients being reviewed before a standalone batch. Plain mutable state: the screen calls a method and
/// rebuilds. Rows of the same [RowSource.paste] / [RowSource.file] are replaced by the next check of that source,
/// searched students and list rows stay until removed.
class RecipientDraft {
  RecipientDraft({List<IssueColumn> columns = const [], this.manualDefault = true}) : _columns = List.of(columns);

  List<IssueColumn> _columns;
  final List<RecipientRow> _rows = [];
  int _seq = 0;

  /// Issue unmatched names as manual recipients unless a row says otherwise.
  bool manualDefault;

  List<IssueColumn> get columns => List.unmodifiable(_columns);
  List<RecipientRow> get rows => List.unmodifiable(_rows);
  bool get isEmpty => _rows.isEmpty;

  set columns(List<IssueColumn> cols) {
    _columns = List.of(cols);
  }

  String _uid() => 'r${++_seq}';

  RecipientRow? byUid(String uid) => _rows.where((r) => r.uid == uid).firstOrNull;

  int _index(String uid) => _rows.indexWhere((r) => r.uid == uid);

  // ── filling ────────────────────────────────────────────────────────────────

  /// Rows from a POST check / check-file answer. With [replace] the earlier rows of the same [source] go first
  /// (a live paste re-check replaces its own rows, never the searched students).
  int addChecked(Map<String, dynamic> json, {RowSource source = RowSource.paste, bool replace = true}) {
    final cols = _maps(json['columns']);
    if (cols.isNotEmpty) _columns = [for (final c in cols) IssueColumn.fromJson(c)];
    if (replace) _rows.removeWhere((r) => r.source == source);
    var n = 0;
    for (final r in _maps(json['rows'])) {
      final values = <String, String>{for (final e in _map(r['values']).entries) e.key: '${e.value ?? ''}'};
      final issues = [for (final i in _maps(r['issues'])) RowIssue.fromJson(i)];
      final m = _map(r['match']);
      final state = _matchOf(_str(m['status']));
      final st = _map(m['student']);
      _rows.add(RecipientRow(
        uid: _uid(),
        line: _intOrNull(r['line']),
        source: source,
        values: values,
        structural: [for (final i in issues) if (i.code == 'too_few_values' || i.code == 'too_many_values') i],
        match: state,
        student: state == MatchState.matched && st.isNotEmpty ? StudentBrief.fromJson(st) : null,
        candidates: [for (final c in _maps(m['candidates'])) StudentBrief.fromJson(c)],
      ));
      n++;
    }
    return n;
  }

  /// Students picked in the search tab (already matched). One row per student: a student already in the list is
  /// not added twice. Returns how many were added.
  int addStudents(Iterable<StudentBrief> students) {
    final have = {for (final r in _rows) if (r.student != null) r.student!.id};
    var n = 0;
    for (final s in students) {
      if (!have.add(s.id)) continue;
      _rows.add(RecipientRow(
        uid: _uid(),
        source: RowSource.search,
        values: {'student_name': s.name},
        match: MatchState.matched,
        student: s,
      ));
      n++;
    }
    return n;
  }

  /// The student's row goes (unticked in the search tab). The tick shows "this person is in the list", so it also
  /// removes a row of a pasted list / sheet / saved list that matched them — otherwise a student matched from a
  /// pasted row would show ticked and could never be unticked.
  void removeStudent(int studentId) => _rows.removeWhere((r) => r.student?.id == studentId);

  bool hasStudent(int studentId) => _rows.any((r) => r.student?.id == studentId);

  /// Rows of a saved list ({values, email?, student_id?}): a row with a student id counts as matched.
  int addListRows(List<Map<String, dynamic>> items) {
    var n = 0;
    for (final r in items) {
      final values = <String, String>{for (final e in _map(r['values']).entries) e.key: '${e.value ?? ''}'};
      final email = _str(r['email']);
      if (email != null && !values.containsKey(_emailKey) && _columns.any((c) => c.key == _emailKey)) {
        values[_emailKey] = email;
      }
      final sid = _intOrNull(r['student_id']);
      _rows.add(RecipientRow(
        uid: _uid(),
        source: RowSource.list,
        photoUrl: _str(r['photo_url']),
        values: values,
        match: sid != null ? MatchState.matched : MatchState.unmatched,
        student: sid != null ? StudentBrief(id: sid, name: values['student_name'] ?? '') : null,
      ));
      n++;
    }
    return n;
  }

  /// One person typed by hand (an unmatched manual recipient).
  RecipientRow addManual(Map<String, String> values) {
    final row = RecipientRow(uid: _uid(), source: RowSource.manual, values: Map.of(values), manual: true);
    _rows.add(row);
    return row;
  }

  // ── editing ────────────────────────────────────────────────────────────────

  /// A value changed in the review table. The count problems of the original line no longer apply.
  void edit(String uid, String key, String value) {
    final i = _index(uid);
    if (i < 0) return;
    final r = _rows[i];
    final values = Map<String, String>.of(r.values)..[key] = value;
    for (final c in _columns) {
      values.putIfAbsent(c.key, () => '');
    }
    var next = r.copyWith(values: values, structural: const []);
    // A new name breaks the link to the student it matched (a searched / chosen student keeps their account).
    if (key == 'student_name' && r.student != null && certNormalizeName(value) != certNormalizeName(r.student!.name)) {
      next = next.copyWith(match: MatchState.unmatched, clearStudent: true, candidates: const []);
    }
    // A row with several people of the old name and none picked: those candidates belong to the old name — keeping
    // them would leave the row in "needs attention" (and out of the batch) for good.
    if (key == 'student_name' && r.student == null && (r.match != MatchState.unmatched || r.candidates.isNotEmpty) &&
        certNormalizeName(value) != certNormalizeName(r.values['student_name'])) {
      next = next.copyWith(match: MatchState.unmatched, candidates: const []);
    }
    _rows[i] = next;
  }

  /// The row [uid] matched again after a rename, from the students [found] by a search for its name: one with
  /// exactly that (normalised) name → matched, several → pick one, none → still unmatched. Ignored when the row is
  /// gone, already linked to a student, or renamed again since the search ([name] = the name searched for).
  void rematch(String uid, String name, List<StudentBrief> found) {
    final i = _index(uid);
    if (i < 0) return;
    final r = _rows[i];
    final want = certNormalizeName(name);
    if (r.student != null || want.isEmpty || certNormalizeName(r.name) != want) return;
    final same = [for (final s in found) if (certNormalizeName(s.name) == want) s];
    _rows[i] = switch (same.length) {
      0 => r.copyWith(match: MatchState.unmatched, candidates: const []),
      1 => r.copyWith(match: MatchState.matched, student: same.single, candidates: const []),
      _ => r.copyWith(match: MatchState.ambiguous, candidates: same),
    };
  }

  void remove(String uid) => _rows.removeWhere((r) => r.uid == uid);

  void clear() => _rows.clear();

  /// The right person among several with the same name.
  void pickCandidate(String uid, StudentBrief s) {
    final i = _index(uid);
    if (i < 0) return;
    _rows[i] = _rows[i].copyWith(match: MatchState.matched, student: s);
  }

  /// The photo uploaded for this person.
  void setPhoto(String uid, String url) {
    final i = _index(uid);
    if (i >= 0) _rows[i] = _rows[i].copyWith(photoUrl: url);
  }

  /// Issue (or not) this unmatched name as a manual recipient.
  void setManual(String uid, bool on) {
    final i = _index(uid);
    if (i < 0) return;
    _rows[i] = _rows[i].copyWith(manual: on);
  }

  /// Removes every row that repeats an earlier one (the first stays). Returns how many went.
  int removeDuplicates() {
    final dup = _duplicates();
    final before = _rows.length;
    _rows.removeWhere((r) => dup.containsKey(r.uid));
    return before - _rows.length;
  }

  // ── reading ────────────────────────────────────────────────────────────────

  bool manualOf(RecipientRow r) => r.manual ?? manualDefault;

  /// uid → the line (or position) of the earlier row it repeats. A matched student repeats by account; any other
  /// row by normalised name + e-mail (the server's rule).
  Map<String, int> _duplicates() {
    final seen = <String, int>{};
    final out = <String, int>{};
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      if (r.name.isEmpty && r.student == null) continue;
      final key = r.student != null ? 's:${r.student!.id}' : 'n:${certNormalizeName(r.name)}|${r.email.toLowerCase()}';
      final first = seen[key];
      if (first != null) {
        out[r.uid] = first;
      } else {
        seen[key] = r.line ?? i + 1;
      }
    }
    return out;
  }

  /// Every problem of [r]: the server's count problems + empty required values, bad e-mail, too long, duplicate.
  List<RowIssue> issuesOf(RecipientRow r, [Map<String, int>? dups]) {
    final out = <RowIssue>[...r.structural];
    final countIssue = r.structural.isNotEmpty;
    for (final c in _columns) {
      final v = (r.values[c.key] ?? '').trim();
      if (c.required && v.isEmpty && !countIssue) {
        if (c.key == 'student_name' || r.student == null || r.source != RowSource.search) {
          out.add(RowIssue(code: 'empty_value', column: c.key));
        }
      }
      if (v.length > kCertMaxValueLen) out.add(RowIssue(code: 'too_long', column: c.key));
    }
    if (r.email.isNotEmpty && !certValidEmail(r.email)) out.add(const RowIssue(code: 'bad_email', column: _emailKey));
    final of = (dups ?? _duplicates())[r.uid];
    if (of != null) out.add(RowIssue(code: 'duplicate', ofLine: of));
    return out;
  }

  RowState stateOf(RecipientRow r, [Map<String, int>? dups]) {
    if (issuesOf(r, dups).isNotEmpty) return RowState.attention;
    if (r.match == MatchState.ambiguous && r.student == null) return RowState.attention;
    if (r.match == MatchState.unmatched && !manualOf(r)) return RowState.skipped;
    return RowState.ready;
  }

  /// Each row with its state and problems, computed once (what the review table draws).
  List<({RecipientRow row, RowState state, List<RowIssue> issues})> review() {
    final dups = _duplicates();
    return [for (final r in _rows) (row: r, state: stateOf(r, dups), issues: issuesOf(r, dups))];
  }

  IssueSummary get summary {
    final dups = _duplicates();
    var ready = 0, attention = 0, skipped = 0, matched = 0, ambiguous = 0, unmatched = 0;
    for (final r in _rows) {
      switch (stateOf(r, dups)) {
        case RowState.ready:
          ready++;
        case RowState.attention:
          attention++;
        case RowState.skipped:
          skipped++;
      }
      if (r.match == MatchState.matched || r.student != null) {
        matched++;
      } else if (r.match == MatchState.ambiguous) {
        ambiguous++;
      } else {
        unmatched++;
      }
    }
    return IssueSummary(
      total: _rows.length,
      ready: ready,
      attention: attention,
      skipped: skipped,
      matched: matched,
      ambiguous: ambiguous,
      unmatched: unmatched,
      duplicates: dups.length,
    );
  }

  RecipientRow? get firstReady {
    final dups = _duplicates();
    return _rows.where((r) => stateOf(r, dups) == RowState.ready).firstOrNull;
  }

  Map<String, dynamic> _wire(RecipientRow r, {required bool forList}) {
    final values = <String, String>{
      for (final e in r.values.entries)
        if (e.key != _emailKey && (e.value.trim().isNotEmpty || e.key == 'student_name')) e.key: e.value.trim(),
    };
    if ((values['student_name'] ?? '').isEmpty && r.student != null) values['student_name'] = r.student!.name;
    return {
      'values': values,
      if (!forList) 'name': values['student_name'] ?? r.name,
      if (r.email.isNotEmpty) 'email': r.email,
      if (r.student != null) 'student_id': r.student!.id,
      if (r.photoUrl != null) 'photo_url': r.photoUrl,
    };
  }

  /// The uids of [batchRows], in the same order (a `photo-status` answer indexes them).
  List<String> batchUids() {
    final dups = _duplicates();
    return [for (final r in _rows) if (stateOf(r, dups) == RowState.ready) r.uid];
  }

  /// The ready rows as the batch's `rows` ({values, name, email?, student_id?}); the e-mail travels in `email`.
  List<Map<String, dynamic>> batchRows() {
    final dups = _duplicates();
    return [for (final r in _rows) if (stateOf(r, dups) == RowState.ready) _wire(r, forList: false)];
  }

  /// Every row that has a name, for saving as a list (problems included — the list is a draft).
  List<Map<String, dynamic>> listRows() =>
      [for (final r in _rows) if (r.name.isNotEmpty || r.student != null) _wire(r, forList: true)];
}

// ─────────────────────────────────────────────────────────────────────────────
// Request bodies
// ─────────────────────────────────────────────────────────────────────────────

enum IssueMode { standalone, course }

String issueModeWire(IssueMode m) => m == IssueMode.course ? 'course' : 'standalone';

Map<String, String> _cleanConstants(Map<String, String>? c) => {
      for (final e in (c ?? const <String, String>{}).entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };

/// POST batches. Standalone sends the ready [rows]; course mode sends the course (the server issues to its active
/// students) and no rows, plus the course's certificate ([certificateId]: without it the server records no course
/// issuance, notifies nobody and a second run issues everyone again) and [replaceExisting] (also re-issue to the
/// students who already hold it; off = they are skipped).
Map<String, dynamic> certBatchBody({
  required int designId,
  required IssueMode mode,
  int? orgId,
  int? courseId,
  int? certificateId,
  bool replaceExisting = false,
  List<String>? langs,
  bool email = false,
  Map<String, String>? constants,
  String? title,
  List<Map<String, dynamic>> rows = const [],
}) {
  final cons = _cleanConstants(constants);
  final ttl = title?.trim() ?? '';
  return {
    'design_id': designId,
    'mode': issueModeWire(mode),
    'org_id': ?orgId,
    if (mode == IssueMode.course && courseId != null) 'course_id': courseId,
    if (mode == IssueMode.course && courseId != null && certificateId != null) 'certificate_id': certificateId,
    if (mode == IssueMode.course) 'replace_existing': replaceExisting,
    if (langs != null && langs.isNotEmpty) 'langs': langs,
    'email': email,
    if (cons.isNotEmpty) 'constants': cons,
    if (ttl.isNotEmpty) 'title': ttl,
    if (mode == IssueMode.standalone || rows.isNotEmpty) 'rows': rows,
  };
}

/// POST preview: the first recipient's values (or the sample name the server picks when there are none).
Map<String, dynamic> certPreviewBody({
  required int designId,
  required IssueMode mode,
  int? orgId,
  int? courseId,
  Map<String, String>? values,
  Map<String, String>? constants,
  List<String>? langs,
  String? photoUrl,
  int? studentId,
}) {
  final vals = {
    for (final e in (values ?? const <String, String>{}).entries)
      if (e.key != _emailKey && e.value.trim().isNotEmpty) e.key: e.value.trim(),
  };
  final cons = _cleanConstants(constants);
  return {
    'design_id': designId,
    'mode': issueModeWire(mode),
    'org_id': ?orgId,
    if (mode == IssueMode.course && courseId != null) 'course_id': courseId,
    if (vals.isNotEmpty) 'values': vals,
    if (cons.isNotEmpty) 'constants': cons,
    if (langs != null && langs.isNotEmpty) 'langs': langs,
    'photo_url': ?photoUrl,
    'student_id': ?studentId,
  };
}

/// POST check: the pasted text.
Map<String, dynamic> certCheckBody({required int designId, int? orgId, IssueMode mode = IssueMode.standalone,
    bool withEmail = false, required String text}) =>
    {
      'design_id': designId,
      'org_id': ?orgId,
      'mode': issueModeWire(mode),
      'with_email': withEmail,
      'text': text,
    };

/// POST lists: a named list of the current recipients.
Map<String, dynamic> certListBody({required String name, int? orgId, int? designId, required List<IssueColumn> columns,
    required List<Map<String, dynamic>> rows}) =>
    {
      'name': name.trim(),
      'org_id': ?orgId,
      'design_id': ?designId,
      'columns': [for (final c in columns) c.toJson()],
      'rows': rows,
    };

/// POST lists/{id}/people: one new person, issued at once when [issue].
Map<String, dynamic> certPersonBody({required Map<String, String> values, String? email, int? studentId,
    bool issue = false, int? designId, List<String>? langs, bool sendEmail = false, String? photoUrl}) {
  final vals = {
    for (final e in values.entries)
      if (e.key != _emailKey && e.value.trim().isNotEmpty) e.key: e.value.trim(),
  };
  final mail = (email ?? values[_emailKey] ?? '').trim();
  return {
    'values': vals,
    if (vals['student_name'] != null) 'name': vals['student_name'],
    if (mail.isNotEmpty) 'email': mail,
    'student_id': ?studentId,
    'photo_url': ?photoUrl,
    'issue': issue,
    if (issue && designId != null) 'design_id': designId,
    if (issue && langs != null && langs.isNotEmpty) 'langs': langs,
    if (issue) 'send_email': sendEmail,
  };
}

/// POST issued/{id}/reissue: only what changed.
Map<String, dynamic> certReissueBody({required Map<String, String> before, required Map<String, String> after,
    String? email, String? emailBefore, bool sendEmail = false, String? reason, String? photoUrl}) {
  final changed = {
    for (final e in after.entries)
      if (e.key != _emailKey && (before[e.key] ?? '') != e.value.trim()) e.key: e.value.trim(),
  };
  final mail = email?.trim();
  return {
    if (changed.isNotEmpty) 'values': changed,
    if (changed['student_name'] != null) 'name': changed['student_name'],
    if (mail != null && mail != (emailBefore ?? '')) 'email': mail,
    'send_email': sendEmail,
    if ((reason ?? '').trim().isNotEmpty) 'reason': reason!.trim(),
    'photo_url': ?photoUrl,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Batches, issued certificates, lists, verification
// ─────────────────────────────────────────────────────────────────────────────

class IssueBatch {
  const IssueBatch({
    required this.id,
    this.mode = 'standalone',
    this.orgId,
    this.designId,
    this.courseId,
    this.title,
    this.langs = const [],
    this.status = 'queued',
    this.total = 0,
    this.done = 0,
    this.failed = 0,
    this.emailed = 0,
    this.emailFailed = 0,
    this.email = false,
    this.hasZip = false,
    this.hasPdf = false,
    this.createdBy,
    this.createdAt,
    this.finishedAt,
    this.error,
  });

  factory IssueBatch.fromJson(Map<String, dynamic> j) {
    final b = j['batch'] is Map ? _map(j['batch']) : j;
    return IssueBatch(
      id: _int(b['id']),
      mode: _str(b['mode']) ?? 'standalone',
      orgId: _intOrNull(b['org_id']),
      designId: _intOrNull(b['design_id']),
      courseId: _intOrNull(b['course_id']),
      title: _str(b['title']),
      langs: _strings(b['langs']),
      status: _str(b['status']) ?? 'queued',
      total: _int(b['total']),
      done: _int(b['done']),
      failed: _int(b['failed']),
      emailed: _int(b['emailed']),
      emailFailed: _int(b['email_failed']),
      email: b['email'] == true,
      hasZip: b['has_zip'] == true,
      hasPdf: b['has_pdf'] == true,
      createdBy: _intOrNull(b['created_by']),
      createdAt: certUtc(b['created_at']),
      finishedAt: certUtc(b['finished_at']),
      error: _str(b['error']),
    );
  }

  final int id;
  final String mode;
  final int? orgId, designId, courseId;
  final String? title;
  final List<String> langs;
  final String status;
  final int total, done, failed, emailed, emailFailed;
  final bool email, hasZip, hasPdf;
  final int? createdBy;
  final DateTime? createdAt, finishedAt;
  final String? error;

  bool get finished => status == 'done' || status == 'failed';
  bool get isCourse => mode == 'course';

  /// 0..1 of the recipients handled (issued or failed).
  double get progress => total <= 0 ? (finished ? 1 : 0) : ((done + failed) / total).clamp(0.0, 1.0);
}

String certBatchStatusLabel(String status) => switch (status) {
      'queued' => _t('في الانتظار', 'Queued'),
      'running' => _t('جارٍ الإصدار', 'Issuing'),
      'done' => _t('اكتمل', 'Done'),
      'failed' => _t('فشل', 'Failed'),
      _ => status,
    };

String certModeLabel(String mode) => mode == 'course' ? _t('مرتبطة بدورة', 'Linked to a course') : _t('مستقلة', 'Standalone');

class IssuedCert {
  const IssuedCert({
    required this.id,
    required this.serial,
    required this.recipientName,
    this.batchId,
    this.studentId,
    this.status = 'issued',
    this.urlAr,
    this.urlEn,
    this.verifyUrl,
    this.createdAt,
    this.revokedAt,
    this.revokedReason,
    this.reissuedFromId,
    this.emailed = false,
    this.recipientEmail,
    this.values = const {},
  });

  factory IssuedCert.fromJson(Map<String, dynamic> j) => IssuedCert(
        id: _int(j['id']),
        batchId: _intOrNull(j['batch_id']),
        serial: _str(j['serial']) ?? '',
        recipientName: _str(j['recipient_name']) ?? '',
        studentId: _intOrNull(j['student_id']),
        status: _str(j['status']) ?? 'issued',
        urlAr: _str(j['url_ar']),
        urlEn: _str(j['url_en']),
        verifyUrl: _str(j['verify_url']),
        createdAt: certUtc(j['created_at']),
        revokedAt: certUtc(j['revoked_at']),
        revokedReason: _str(j['revoked_reason']),
        reissuedFromId: _intOrNull(j['reissued_from_id']),
        emailed: j['emailed'] == true,
        recipientEmail: _str(j['recipient_email']),
        values: {for (final e in _map(j['values']).entries) e.key: '${e.value ?? ''}'},
      );

  final int id;
  final int? batchId;
  final String serial;
  final String recipientName;
  final int? studentId;
  final String status;
  final String? urlAr, urlEn, verifyUrl;
  final DateTime? createdAt, revokedAt;
  final String? revokedReason;
  final int? reissuedFromId;
  final bool emailed;
  final String? recipientEmail;
  final Map<String, String> values;

  bool get revoked => status == 'revoked';

  /// The image in the reader's language, else the other one.
  String? get imageUrl => AppConfig.lang == 'ar' ? (urlAr ?? urlEn) : (urlEn ?? urlAr);
}

class RecipientListInfo {
  const RecipientListInfo({
    required this.id,
    required this.name,
    this.orgId,
    this.designId,
    this.columns = const [],
    this.count = 0,
    this.updatedAt,
    this.rows = const [],
  });

  factory RecipientListInfo.fromJson(Map<String, dynamic> j) {
    final l = j['list'] is Map ? _map(j['list']) : j;
    final rows = _maps(l['rows']);
    return RecipientListInfo(
      id: _int(l['id']),
      name: _str(l['name']) ?? '',
      orgId: _intOrNull(l['org_id']),
      designId: _intOrNull(l['design_id']),
      columns: [for (final c in _maps(l['columns'])) IssueColumn.fromJson(c)],
      count: l.containsKey('count') ? _int(l['count']) : rows.length,
      updatedAt: certUtc(l['updated_at']),
      rows: rows,
    );
  }

  final int id;
  final String name;
  final int? orgId, designId;
  final List<IssueColumn> columns;
  final int count;
  final DateTime? updatedAt;
  final List<Map<String, dynamic>> rows;
}

/// GET /public/certificates/verify/{token}.
class VerifyResult {
  const VerifyResult({
    required this.valid,
    required this.status,
    this.serial = '',
    this.recipientName = '',
    this.title,
    this.issuer,
    this.issuedAt,
    this.revokedAt,
    this.langs = const [],
    this.images = const {},
  });

  factory VerifyResult.fromJson(Map<String, dynamic> j) => VerifyResult(
        valid: j['valid'] == true,
        status: _str(j['status']) ?? (j['valid'] == true ? 'issued' : 'revoked'),
        serial: _str(j['serial']) ?? '',
        recipientName: _str(j['recipient_name']) ?? '',
        title: _str(j['title']),
        issuer: _str(j['issuer']),
        issuedAt: certUtc(j['issued_at']),
        revokedAt: certUtc(j['revoked_at']),
        langs: _strings(j['langs']),
        images: {for (final e in _map(j['images']).entries) if (_str(e.value) != null) e.key: _str(e.value)!},
      );

  final bool valid;
  final String status;
  final String serial;
  final String recipientName;
  final String? title, issuer;
  final DateTime? issuedAt, revokedAt;
  final List<String> langs;
  final Map<String, String> images;

  bool get revoked => status == 'revoked';

  /// The languages that carry an image, the reader's first.
  List<String> get imageLangs {
    final have = [for (final l in (langs.isEmpty ? images.keys : langs)) if (images[l] != null) l];
    have.sort((a, b) => (a == AppConfig.lang ? 0 : 1).compareTo(b == AppConfig.lang ? 0 : 1));
    return have;
  }
}

/// `/verify/<token>` (web path, app link) → the token, else null.
String? certVerifyTokenFromRoute(String? routeName) {
  if (routeName == null || routeName.isEmpty) return null;
  final uri = Uri.tryParse(routeName);
  if (uri == null) return null;
  final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  // pathSegments are decoded already: decoding again would turn "%25" into a lone "%" and throw
  if (seg.length == 2 && seg[0] == 'verify' && seg[1].trim().isNotEmpty && seg[1].length <= 64) return seg[1].trim();
  return null;
}

/// One certificate of a course (`GET /api/v1/courses/{id}/certificates`): what course issuances are recorded under.
class IssueCourseCertificate {
  const IssueCourseCertificate({required this.id, this.title = '', this.designId});

  factory IssueCourseCertificate.fromJson(Map<String, dynamic> j) =>
      IssueCourseCertificate(id: _int(j['id']), title: _str(j['title']) ?? '', designId: _intOrNull(j['design_id']));

  final int id;
  final String title;
  final int? designId;
}

/// The course certificate a course batch of [designId] belongs to: the one using that design, else the course's
/// only certificate; null when the course has none (or several, none with this design).
int? certCourseCertificateFor(List<IssueCourseCertificate> certs, int designId) {
  final same = certs.where((c) => c.designId == designId && c.id > 0).firstOrNull;
  if (same != null) return same.id;
  return certs.length == 1 && certs.single.id > 0 ? certs.single.id : null;
}

/// A page of {items, total, page}.
({List<T> items, int total, int page}) certPage<T>(Object? json, T Function(Map<String, dynamic>) parse) {
  final m = _map(json);
  final items = [for (final x in _maps(m['items'])) parse(x)];
  return (items: items, total: _int(m['total'], items.length), page: _int(m['page'], 1));
}

String certLangLabel(String lang) => lang == 'ar' ? _t('العربية', 'Arabic') : _t('الإنجليزية', 'English');

// ─────────────────────────────────────────────────────────────────────────────
// Server codes → text
// ─────────────────────────────────────────────────────────────────────────────

/// The issuing routes' codes in the reader's language; unknown codes fall back to the server's own sentence
/// (`message_en` in English) and then to [apiErrorText].
String _photoCountText(int? n) => n == null || n <= 0
    ? _t('بعض المستلمين يحتاجون إلى صورة قبل الإصدار', 'Some recipients still need a photo before issuing')
    : _t('يحتاج $n من المستلمين إلى صورة قبل الإصدار', '$n recipient${n == 1 ? '' : 's'} still need a photo before issuing');

String certIssueErrorText(Object error) {
  final e = ApiException.from(error);
  final d = apiErrorDetail(e);
  final maxRows = _intOrNull(d['max_rows']);
  final text = switch (e.code ?? '${d['code'] ?? ''}') {
    'not_authenticated' => _t('سجّل الدخول للمتابعة', 'Sign in to continue'),
    'cert_issue_forbidden' => _t('لا تملك صلاحية إصدار الشهادات', 'You are not allowed to issue certificates'),
    'org_not_found' => _t('المؤسسة غير موجودة', 'Organization not found'),
    'org_forbidden' => _t('لا يمكنك إصدار شهادات لهذه المؤسسة', 'You cannot issue certificates for this organization'),
    'design_not_found' => _t('التصميم غير موجود', 'Design not found'),
    'design_not_allowed' => _t('لا يمكنك استخدام هذا التصميم هنا', 'You cannot use this design here'),
    'org_required' => _t('اختر المؤسسة التي تصدر لها', 'Choose the organization you issue for'),
    'course_required' => _t('اختر الدورة', 'Choose a course'),
    'course_not_found' => _t('الدورة غير موجودة', 'Course not found'),
    'course_forbidden' => _t('لا يمكنك إصدار شهادات لهذه الدورة', 'You cannot issue certificates for this course'),
    'course_not_allowed' => _t('الإصدار المستقل لا يرتبط بدورة', 'A standalone batch takes no course'),
    'certificate_mismatch' => _t('هذه الشهادة لا تتبع هذه الدورة', 'This certificate does not belong to the course'),
    'too_many_rows' => maxRows == null
        ? _t('عدد المستلمين أكبر من المسموح', 'Too many recipients')
        : _t('الحد الأقصى $maxRows مستلم في المرة الواحدة', 'At most $maxRows recipients at a time'),
    'file_too_large' => _t('الملف أكبر من 5 ميجابايت', 'The file must be smaller than 5 MB'),
    'bad_encoding' => _t('تعذّرت قراءة ترميز الملف — احفظه بترميز UTF-8', 'Could not read the file — save it as UTF-8'),
    'unsupported_file' => _t('ارفع ملف ‎.xlsx أو ‎.csv', 'Upload an .xlsx or .csv file'),
    'bad_file' => _t('هذا الملف ليس ملف Excel صالحًا', 'This file is not a valid Excel (.xlsx) file'),
    'bad_lang' => _t('التصميم لا يدعم هذه اللغة', 'The design does not issue this language'),
    'teacher_name_required' => _t('اكتب اسم المدرّس: لا يمكن تعبئته تلقائيًا لمستلم ليس له حساب على المنصة', "Enter the instructor's name: it cannot be filled in for a recipient without an account"),
    'no_recipients' => (_intOrNull(d['skipped']) ?? 0) > 0
        ? _t('كل الطلاب النشطين لديهم هذه الشهادة — فعّل «استبدال الشهادات الحالية» لإصدارها من جديد',
            'Every active student already holds this certificate — turn on “Replace existing certificates” to issue it again')
        : _t('أضف مستلمًا واحدًا على الأقل', 'Add at least one recipient'),
    'recipient_out_of_scope' => _t('أحد المستلمين ليس من طلابك', 'One of the recipients is not one of your students'),
    'invalid_rows' => _t('بعض المستلمين بلا اسم أو ببريد غير صحيح', 'Some recipients have no name or an invalid email'),
    'bad_mode' => _t('نوع الإصدار غير صحيح', 'Unknown issuing mode'),
    'batch_not_found' => _t('الدفعة غير موجودة', 'Batch not found'),
    'batch_forbidden' => _t('لا يمكنك فتح هذه الدفعة', 'You cannot open this batch'),
    'bad_kind' => _t('نوع الملف غير صحيح', 'Unknown file kind'),
    'not_ready' => _t('الملف غير جاهز بعد — انتظر انتهاء الإصدار', 'The file is not ready yet — wait for the batch to finish'),
    'issued_not_found' => _t('الشهادة غير موجودة', 'Certificate not found'),
    'reason_required' => _t('اذكر السبب', 'Give a reason'),
    'already_revoked' => _t('هذه الشهادة ملغاة بالفعل', 'This certificate is already revoked'),
    'design_deleted' => _t('تم حذف تصميم هذه الشهادة', 'The design of this certificate was deleted'),
    'list_not_found' => _t('القائمة غير موجودة', 'List not found'),
    'list_forbidden' => _t('لا يمكنك فتح هذه القائمة', 'You cannot open this list'),
    'name_required' => _t('اكتب الاسم', 'Give it a name'),
    'too_many_lists' => _t('عدد القوائم المحفوظة كبير جدًا — احذف قائمة قديمة', 'Too many saved lists — delete an old one'),
    'design_required' => _t('اختر التصميم', 'Choose a design'),
    'certificate_not_found' => _t('لا توجد شهادة بهذا الرابط', 'No certificate matches this link'),
    'photos_required' => _photoCountText(_intOrNull(d['count'])),
    'bad_photo' => _t('هذا الملف ليس صورة صالحة', 'This file is not a readable photo'),
    _ => null,
  };
  if (text != null) return text;
  if (AppConfig.lang != 'ar' && d['message_en'] is String) return d['message_en'] as String;
  return apiErrorText(e);
}
