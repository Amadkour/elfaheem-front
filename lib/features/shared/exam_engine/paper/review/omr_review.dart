// Scanned bubble sheets — review queue and results (brief Part 4: 4.3 – 4.6, S.1; D-156, D-158): the pure part.
// Models parsed from the engine's replies, the API, the server codes in plain words and the export of the results.
// The screens are omr_review_page.dart (the queue, one-click fixes, the full paper view) and omr_results_page.dart
// (grades, per-question statistics, the score distribution, export, publish); their plain-value widgets are in
// omr_review_parts.dart / omr_results_parts.dart.
//
// Server (Exam Engine, the exam's managers + platform admins; students and parents get 403):
//   GET  /api/v1/exam/exams/{id}/review-items?status=open|resolved&kind=     {items, total, open_by_kind}
//   GET  /api/v1/exam/exams/{id}/review-items/{item}                         + system_reading, question, page
//   POST /api/v1/exam/exams/{id}/review-items/{item}/resolve {action, …}     {item, page_status, open_items_on_page,
//                                                                              attempt | null, next_item_id}
//   GET  /api/v1/exam/exams/{id}/omr/pages/{page}                             the page: signed image URL + overlay
//   GET  /api/v1/exam/exams/{id}/omr/changes                                  the append-only manual changes
//   GET  /api/v1/exam/exams/{id}/omr/results · POST …/omr/results/publish {graded_only?}
//   GET  /api/v1/exam/omr/images/{crop|page}/{id}?exp=&sig=                   the image (token + signature, audited)
// Rules: exam_engine/services/omr_review.py, omr_results.py, omr_scan.page_view (the code wins over the notes).
// Every reply above is recorded from the real engine in test/fixtures/payloads/omr_review/.
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/design/app_table_export.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../exam_engine_api.dart';

/// The live event the engine sends the uploader after every scanned page: `job_updated {kind: omr_scan, exam_id, …}`.
const kOmrScanEventKind = 'omr_scan';

// ── small parsers ───────────────────────────────────────────────────────────────────────────────────────────────

/// The engine stores naive UTC (`2026-11-02T05:29:37.033859`): read it as UTC; null when absent / unreadable.
DateTime? omrUtc(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toUtc();
}

double? _dbl(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
int? _intOrNull(Object? v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
List<String> _strs(Object? v) => v is List ? [for (final x in v) '$x'] : const [];

/// [s] as one left-to-right run inside Arabic text ("5 / 11 · 45%" keeps its order); unchanged in English.
String omrLtr(String s) => AppConfig.lang == 'ar' ? '${String.fromCharCode(0x2066)}$s${String.fromCharCode(0x2069)}' : s;

/// "5" for 5.0, "4.5" for 4.5.
String omrNum(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(d * 10 == (d * 10).roundToDouble() ? 1 : 2);
}

// ── review items ────────────────────────────────────────────────────────────────────────────────────────────────

/// The kinds of the queue, in the order the filter shows them (`handwriting` arrives with the handwriting wave).
const kOmrKinds = ['identifier', 'form', 'bubble', 'handwriting', 'quality'];

String omrKindLabel(String kind) => switch (kind) {
      'identifier' => t('رقم الطالب', 'Student ID'),
      'form' => t('النموذج', 'Form'),
      'bubble' => t('الإجابات', 'Answers'),
      'handwriting' => t('الكتابة اليدوية', 'Handwriting'),
      'quality' => t('جودة الصورة', 'Image quality'),
      _ => kind,
    };

/// One digit of a handwritten identifier as the digits model read it (Example 7).
class OmrDigit {
  const OmrDigit(this.index, this.digit, this.confidence, {this.low = false});
  final int index;
  final String digit;
  final double? confidence;

  /// Below the model's threshold: the reason the item is here.
  final bool low;
}

/// A student the item may belong to (a duplicate value's candidates, a search hit).
class OmrStudent {
  const OmrStudent(this.id, this.name, {this.email});
  final int id;
  final String name;
  final String? email;

  String get label => name.trim().isEmpty ? '#$id' : name;
}

/// `question {n, question_id, type, points, letters}` of a bubble item's detail.
class OmrQuestionRef {
  const OmrQuestionRef({required this.n, required this.questionId, required this.type, required this.points, required this.letters});
  final int n;
  final int questionId;
  final String type;
  final double points;
  final List<String> letters;

  static OmrQuestionRef? fromJson(Object? v) {
    final m = asMap(v);
    if (m.isEmpty) return null;
    return OmrQuestionRef(
        n: asInt(m['n']), questionId: asInt(m['question_id']), type: '${m['type'] ?? ''}', points: _dbl(m['points']) ?? 0, letters: _strs(m['letters']));
  }
}

/// A review item (list row or detail). [reading] is what the system read, [en] / [ar] why the item is here.
class OmrReviewItem {
  const OmrReviewItem({
    required this.id,
    required this.kind,
    required this.code,
    required this.status,
    this.scanPageId,
    this.attemptId,
    this.questionId,
    this.reading = const {},
    this.resolution = const {},
    this.resolvedBy,
    this.resolvedAt,
    this.createdAt,
    this.actions = const [],
    this.hasCrop = false,
    this.cropUrl,
    this.en = '',
    this.ar = '',
    this.systemReading = const {},
    this.question,
    this.pageLabel,
    this.pageStatus,
  });

  final int id;
  final String kind;
  final String code;
  final String status;
  final int? scanPageId;
  final int? attemptId;
  final int? questionId;
  final Map<String, dynamic> reading;
  final Map<String, dynamic> resolution;
  final int? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime? createdAt;
  final List<String> actions;
  final bool hasCrop;
  final String? cropUrl;
  final String en;
  final String ar;

  /// Detail only: the original reading's part (`answer` / `identifier` / `form` / `quality`).
  final Map<String, dynamic> systemReading;
  final OmrQuestionRef? question;
  final String? pageLabel;
  final String? pageStatus;

  factory OmrReviewItem.fromJson(Map<String, dynamic> m) {
    final page = asMap(m['page']);
    return OmrReviewItem(
      id: asInt(m['id']),
      kind: '${m['kind'] ?? ''}',
      code: '${m['code'] ?? ''}',
      status: '${m['status'] ?? 'open'}',
      scanPageId: _intOrNull(m['scan_page_id']),
      attemptId: _intOrNull(m['attempt_id']),
      questionId: _intOrNull(m['question_id']),
      reading: asMap(m['reading']),
      resolution: asMap(m['resolution']),
      resolvedBy: _intOrNull(m['resolved_by']),
      resolvedAt: omrUtc(m['resolved_at']),
      createdAt: omrUtc(m['created_at']),
      actions: _strs(m['actions']),
      hasCrop: m['has_crop'] == true,
      cropUrl: m['crop_url']?.toString(),
      en: '${m['en'] ?? ''}',
      ar: '${m['ar'] ?? ''}',
      systemReading: asMap(m['system_reading']),
      question: OmrQuestionRef.fromJson(m['question']),
      pageLabel: page['page_label']?.toString(),
      pageStatus: page['status']?.toString(),
    );
  }

  bool get open => status == 'open';

  /// Why the item is here, in the app's language (the server's own sentence).
  String get reason {
    final s = AppConfig.lang == 'ar' ? ar : en;
    return s.isNotEmpty ? s : omrCodeText(code);
  }

  bool can(String action) => actions.contains(action);

  // bubble
  int? get n => question?.n ?? _intOrNull(reading['n']);
  String get questionType => question?.type ?? '${reading['type'] ?? ''}';
  bool get multi => questionType == 'mcq_multi';
  Map<String, double> get fills {
    final f = asMap(reading['fills']);
    return {for (final e in f.entries) e.key: _dbl(e.value) ?? 0};
  }

  List<String> get selected => _strs(reading['selected']);

  /// The letters to choose from: the detail's (the question's own options), else the shaded sheet's.
  List<String> get letters {
    final q = question?.letters ?? const [];
    if (q.isNotEmpty) return q;
    final f = fills.keys.toList()..sort();
    return f;
  }

  // identifier
  String get readValue => '${reading['value'] ?? ''}';
  String get idKind => '${reading['kind'] ?? ''}';
  List<OmrDigit> get digits {
    final low = {for (final x in (reading['low'] is List ? reading['low'] as List : const [])) asInt(x)};
    final rows = asMapList(reading['digits']);
    if (rows.isNotEmpty) {
      return [for (final d in rows) OmrDigit(asInt(d['index']), '${d['digit'] ?? ''}', _dbl(d['confidence']), low: low.contains(asInt(d['index'])))];
    }
    final v = readValue;
    return [for (var i = 0; i < v.length; i++) OmrDigit(i, v[i], null, low: low.contains(i))];
  }

  List<OmrStudent> get candidates => [for (final c in asMapList(reading['candidates'])) OmrStudent(asInt(c['user_id']), '${c['name'] ?? ''}')];

  // form
  /// The exam's forms as the reading lists them (`forms: ["A", "B"]`).
  List<String> get forms => _strs(reading['forms']);

  /// marker → the form it read (`{qr: B, printed: A}`).
  Map<String, String> get markersRead {
    final r = asMap(reading['read']).isNotEmpty ? asMap(reading['read']) : asMap(reading['markers']);
    return {for (final e in r.entries) if (e.value != null) e.key: '${e.value}'};
  }

  /// What the person decided, in words ("A", "Blank", "Student #106", "Form B", "Set aside").
  String get resolutionText {
    final r = resolution;
    final a = '${r['action'] ?? ''}';
    return switch (a) {
      'choose' => _strs(r['options']).join(', '),
      'blank' => t('بلا إجابة', 'No answer'),
      'assign' || 'accept' || 'fix' => r['value'] != null ? t('الرقم ${r['value']}', 'ID ${r['value']}') : t('الطالب #${r['student_id']}', 'Student #${r['student_id']}'),
      'replace' => t('استُبدلت الورقة المصححة', 'Replaced the graded sheet'),
      'confirm' => t('النموذج ${r['form']}', 'Form ${r['form']}'),
      'dismiss' => t('نُحّيت الورقة', 'Set aside'),
      _ => a,
    };
  }
}

/// `GET …/review-items`.
class OmrReviewList {
  const OmrReviewList({this.items = const [], this.total = 0, this.openByKind = const {}});
  final List<OmrReviewItem> items;
  final int total;
  final Map<String, int> openByKind;

  factory OmrReviewList.fromJson(Map<String, dynamic> m) => OmrReviewList(
        items: [for (final x in asMapList(m['items'])) OmrReviewItem.fromJson(x)],
        total: asInt(m['total']),
        openByKind: {for (final e in asMap(m['open_by_kind']).entries) e.key: asInt(e.value)},
      );

  int get openTotal => openByKind.values.fold(0, (a, b) => a + b);

  /// The kinds to offer as filters: the known ones that have open items, then any new kind the server sends.
  List<String> get kinds => [
        for (final k in kOmrKinds) if ((openByKind[k] ?? 0) > 0) k,
        for (final k in openByKind.keys) if (!kOmrKinds.contains(k) && (openByKind[k] ?? 0) > 0) k,
      ];
}

/// The attempt after a decision: `{id, state, score, max_score, percentage, passed}`.
class OmrAttemptScore {
  const OmrAttemptScore({required this.id, required this.state, this.score, this.maxScore, this.percentage, this.passed});
  final int id;
  final String state;
  final double? score;
  final double? maxScore;
  final double? percentage;
  final bool? passed;

  bool get graded => state == 'graded' && score != null;

  static OmrAttemptScore? fromJson(Object? v) {
    final m = asMap(v);
    if (m.isEmpty) return null;
    return OmrAttemptScore(
        id: asInt(m['id']),
        state: '${m['state'] ?? ''}',
        score: _dbl(m['score']),
        maxScore: _dbl(m['max_score']),
        percentage: _dbl(m['percentage']),
        passed: m['passed'] is bool ? m['passed'] as bool : null);
  }
}

/// `POST …/resolve`: the item, the page's state, the regraded attempt and the next open item.
class OmrResolveReply {
  const OmrResolveReply({required this.item, this.pageStatus, this.openOnPage = 0, this.attempt, this.nextItemId});
  final OmrReviewItem item;
  final String? pageStatus;
  final int openOnPage;
  final OmrAttemptScore? attempt;
  final int? nextItemId;

  factory OmrResolveReply.fromJson(Map<String, dynamic> m) => OmrResolveReply(
        item: OmrReviewItem.fromJson(asMap(m['item'])),
        pageStatus: m['page_status']?.toString(),
        openOnPage: asInt(m['open_items_on_page']),
        attempt: OmrAttemptScore.fromJson(m['attempt']),
        nextItemId: _intOrNull(m['next_item_id']),
      );

  /// The one line shown after the fix: the new score, or what still waits on this paper.
  String get summary {
    final a = attempt;
    if (a != null && a.graded) {
      final pct = a.percentage == null ? '' : ' · ${omrNum(a.percentage)}%';
      final v = omrLtr('${omrNum(a.score)} / ${omrNum(a.maxScore)}$pct');
      return t('الدرجة الجديدة $v', 'New score $v');
    }
    if (openOnPage > 0) {
      return t('حُفظ · بقي $openOnPage على هذه الورقة قبل حساب الدرجة', 'Saved · $openOnPage more on this paper before it is scored');
    }
    if (pageStatus == 'dismissed') return t('حُفظ · نُحّيت الورقة', 'Saved · the paper was set aside');
    return t('حُفظ', 'Saved');
  }
}

/// The body of a decision (only the keys the action takes).
Map<String, dynamic> omrResolveBody(String action, {int? studentId, String? value, String? form, List<String>? options, String? reason}) => {
      'action': action,
      'student_id': ?studentId,
      'value': ?value,
      'form': ?form,
      'options': ?options,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };

// ── the full page ───────────────────────────────────────────────────────────────────────────────────────────────

/// One detected bubble of the page (source pixels): an answer bubble (`n`, `state`) or an ID / form bubble.
class OmrMark {
  const OmrMark({required this.label, required this.cx, required this.cy, required this.r, this.n, this.idColumn, this.form, this.mark, this.state});
  final String label;
  final double cx, cy, r;
  final int? n;
  final int? idColumn;
  final String? form;
  final String? mark;
  final String? state;

  /// Clear answers vs the ones that wait for a person (multiple / uncertain / blank).
  bool get flagged => state != null && state != 'clear';
  bool get isAnswer => n != null;

  factory OmrMark.fromJson(Map<String, dynamic> m) => OmrMark(
        label: '${m['label'] ?? ''}',
        cx: _dbl(m['cx']) ?? 0,
        cy: _dbl(m['cy']) ?? 0,
        r: _dbl(m['r']) ?? 0,
        n: _intOrNull(m['n']),
        idColumn: _intOrNull(m['id_column']),
        form: m['form']?.toString(),
        mark: m['mark']?.toString(),
        state: m['state']?.toString(),
      );
}

/// One question as read on the page.
class OmrAnswerMark {
  const OmrAnswerMark({required this.questionId, required this.n, required this.state, this.selected = const [], this.box, this.finalScore, this.reviewState});
  final int questionId;
  final int n;
  final String state;
  final List<String> selected;

  /// `[x, y, w, h]` (source px) — present for the flagged rows.
  final List<double>? box;
  final double? finalScore;
  final String? reviewState;

  bool get flagged => state != 'clear';

  factory OmrAnswerMark.fromJson(Map<String, dynamic> m) {
    final b = m['box'] is List ? [for (final x in m['box'] as List) _dbl(x) ?? 0] : null;
    return OmrAnswerMark(
      questionId: asInt(m['question_id']),
      n: asInt(m['n']),
      state: '${m['state'] ?? ''}',
      selected: _strs(m['selected']),
      box: b != null && b.length == 4 ? b : null,
      finalScore: _dbl(m['final_score']),
      reviewState: m['review_state']?.toString(),
    );
  }
}

/// `GET …/omr/pages/{id}`.
class OmrPageView {
  const OmrPageView({
    required this.id,
    this.label,
    this.status = '',
    this.studentId,
    this.attemptId,
    this.fileName,
    this.imageUrl,
    this.width,
    this.height,
    this.marks = const [],
    this.answers = const [],
    this.identifierBox,
    this.identifierValue,
    this.formValue,
    this.items = const [],
    this.problem = '',
  });

  final int id;
  final String? label;
  final String status;
  final int? studentId;
  final int? attemptId;
  final String? fileName;
  final String? imageUrl;
  final double? width, height;
  final List<OmrMark> marks;
  final List<OmrAnswerMark> answers;
  final List<double>? identifierBox;
  final String? identifierValue;
  final String? formValue;

  /// The page's review items: (id, kind, code, status).
  final List<({int id, String kind, String code, int? questionId, String status})> items;

  /// The page's quality sentence (a rejected page), in the app's language.
  final String problem;

  factory OmrPageView.fromJson(Map<String, dynamic> m) {
    final p = asMap(m['page']);
    final size = m['size'] is List ? [for (final x in m['size'] as List) _dbl(x) ?? 0] : const <double>[];
    final ident = asMap(m['identifier']);
    final ib = ident['box'] is List ? [for (final x in ident['box'] as List) _dbl(x) ?? 0] : null;
    return OmrPageView(
      id: asInt(p['id']),
      label: p['page_label']?.toString(),
      status: '${p['status'] ?? ''}',
      studentId: _intOrNull(p['student_id']),
      attemptId: _intOrNull(p['attempt_id']),
      fileName: p['file_name']?.toString(),
      imageUrl: m['image_url']?.toString(),
      width: size.length == 2 ? size[0] : null,
      height: size.length == 2 ? size[1] : null,
      marks: [for (final o in asMapList(m['overlay'])) OmrMark.fromJson(o)],
      answers: [for (final a in asMapList(m['answers'])) OmrAnswerMark.fromJson(a)],
      identifierBox: ib != null && ib.length == 4 ? ib : null,
      identifierValue: ident['value']?.toString(),
      formValue: asMap(m['form'])['value']?.toString(),
      items: [
        for (final i in asMapList(m['items']))
          (id: asInt(i['id']), kind: '${i['kind'] ?? ''}', code: '${i['code'] ?? ''}', questionId: _intOrNull(i['question_id']), status: '${i['status'] ?? ''}'),
      ],
      problem: '${(AppConfig.lang == 'ar' ? p['ar'] : p['en']) ?? ''}',
    );
  }
}

// ── the manual-change trail (D-158) ─────────────────────────────────────────────────────────────────────────────

class OmrChange {
  const OmrChange({required this.id, required this.entity, this.entityId, required this.field, this.old, this.next, this.actorId, this.reason, this.at});
  final int id;
  final String entity;
  final int? entityId;
  final String field;
  final Object? old;
  final Object? next;
  final int? actorId;
  final String? reason;
  final DateTime? at;

  factory OmrChange.fromJson(Map<String, dynamic> m) => OmrChange(
        id: asInt(m['id']),
        entity: '${m['entity'] ?? ''}',
        entityId: _intOrNull(m['entity_id']),
        field: '${m['field'] ?? ''}',
        old: m['old'],
        next: m['new'],
        actorId: _intOrNull(m['actor_id']),
        reason: m['reason']?.toString(),
        at: omrUtc(m['at']),
      );

  /// "Question 5: unclear → A", "Student ID: 9999999999 → student #106", "Form: QR B · printed A → B".
  String get summary {
    final o = asMap(old), n = asMap(next);
    switch (entity) {
      case 'answer':
        final was = '${o['state'] ?? ''}';
        final now = n['blank'] == true ? t('بلا إجابة', 'no answer') : _strs(n['options']).join(', ');
        return t('السؤال ${o['n'] ?? ''}: ${omrStateText(was)} ← $now', 'Question ${o['n'] ?? ''}: ${omrStateText(was)} → $now');
      case 'identifier':
        final was = o['value'] ?? '—';
        final now = n['action'] == 'dismiss' ? t('نُحّيت', 'set aside') : (n['student_id'] != null ? t('الطالب #${n['student_id']}', 'student #${n['student_id']}') : '${n['action'] ?? ''}');
        return t('رقم الطالب: $was ← $now', 'Student ID: $was → $now');
      case 'form':
        final m = asMap(o['markers']);
        final was = m.isEmpty ? '—' : m.entries.map((e) => '${omrMarkerText(e.key)} ${e.value ?? '—'}').join(' · ');
        final now = n['action'] == 'dismiss' ? t('نُحّيت', 'set aside') : '${n['form'] ?? ''}';
        return t('النموذج: $was ← $now', 'Form: $was → $now');
      default:
        return t('${omrCodeText('${o['code'] ?? ''}')}: نُحّيت', '${omrCodeText('${o['code'] ?? ''}')}: set aside');
    }
  }
}

/// "Changed by you · 10:42" (the server's audited actor and time, D-158).
String omrChangedBy(int? actorId, DateTime? at, {int? meId}) {
  final who = actorId != null && actorId == meId ? t('بواسطتك', 'by you') : (actorId == null ? '' : t('بواسطة #$actorId', 'by #$actorId'));
  final when = at == null ? '' : ' · ${_sameDay(at) ? AppTime.time(at) : AppTime.dateTime(at)}';
  return t('عُدّل $who$when', 'Changed $who$when');
}

bool _sameDay(DateTime utc) {
  final a = AppTime.toZone(utc), b = AppTime.toZone(DateTime.now().toUtc());
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── results ─────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrStudentResult {
  const OmrStudentResult({
    required this.attemptId,
    this.studentId,
    this.studentCode,
    this.name,
    required this.state,
    this.score,
    this.maxScore,
    this.percentage,
    this.passed,
    this.forms = const [],
    this.openReview = 0,
    this.graded = false,
    this.correct = 0,
    this.answered = 0,
  });

  final int attemptId;
  final int? studentId;
  final String? studentCode;
  final String? name;
  final String state;
  final double? score, maxScore, percentage;
  final bool? passed;
  final List<String> forms;
  final int openReview;
  final bool graded;
  final int correct, answered;

  /// The name, else the anonymous code, else the id.
  String get who {
    if ((name ?? '').trim().isNotEmpty) return name!.trim();
    if ((studentCode ?? '').isNotEmpty) return studentCode!;
    return studentId == null ? '—' : t('طالب #$studentId', 'Student #$studentId');
  }

  String get formText => forms.isEmpty ? '—' : forms.join(', ');

  factory OmrStudentResult.fromJson(Map<String, dynamic> m) {
    final f = m['form'];
    return OmrStudentResult(
      attemptId: asInt(m['attempt_id']),
      studentId: _intOrNull(m['student_id']),
      studentCode: m['student_code']?.toString(),
      name: m['name']?.toString(),
      state: '${m['state'] ?? ''}',
      score: _dbl(m['score']),
      maxScore: _dbl(m['max_score']),
      percentage: _dbl(m['percentage']),
      passed: m['passed'] is bool ? m['passed'] as bool : null,
      forms: f is List ? _strs(f) : (f == null ? const [] : ['$f']),
      openReview: asInt(m['open_review']),
      graded: m['graded'] == true,
      correct: asInt(m['correct']),
      answered: asInt(m['answered']),
    );
  }
}

class OmrQuestionStat {
  const OmrQuestionStat({
    required this.n,
    required this.questionId,
    required this.type,
    required this.points,
    this.scored = 0,
    this.correct = 0,
    this.difficulty,
    this.mostChosenWrong,
    this.mostChosenWrongCount = 0,
    this.distribution = const {},
  });

  final int n;
  final int questionId;
  final String type;
  final double points;
  final int scored, correct;

  /// Share of the scored answers that are right (0–1); null before anything is scored.
  final double? difficulty;
  final String? mostChosenWrong;
  final int mostChosenWrongCount;

  /// letter | blank | multiple | pending → count.
  final Map<String, int> distribution;

  /// The option letters in the order of the sheet (the buckets that are not blank / multiple / pending).
  List<String> get letters => [for (final k in distribution.keys) if (!const {'blank', 'multiple', 'pending'}.contains(k)) k];

  factory OmrQuestionStat.fromJson(Map<String, dynamic> m) => OmrQuestionStat(
        n: asInt(m['n']),
        questionId: asInt(m['question_id']),
        type: '${m['type'] ?? ''}',
        points: _dbl(m['points']) ?? 0,
        scored: asInt(m['scored']),
        correct: asInt(m['correct']),
        difficulty: _dbl(m['difficulty']),
        mostChosenWrong: m['most_chosen_wrong']?.toString(),
        mostChosenWrongCount: asInt(m['most_chosen_wrong_count']),
        distribution: {for (final e in asMap(m['distribution']).entries) e.key: asInt(e.value)},
      );
}

class OmrResults {
  const OmrResults({
    required this.examId,
    this.title = '',
    this.students = const [],
    this.questions = const [],
    this.bins = const [],
    this.studentsTotal = 0,
    this.graded = 0,
    this.openReviewItems = 0,
    this.mean,
    this.max,
    this.min,
    this.passed = 0,
    this.publishedAt,
    this.anonymous = false,
  });

  final int examId;
  final String title;
  final List<OmrStudentResult> students;
  final List<OmrQuestionStat> questions;

  /// Percent bins `(from, to, count)`.
  final List<({int from, int to, int count})> bins;
  final int studentsTotal, graded, openReviewItems, passed;
  final double? mean, max, min;
  final DateTime? publishedAt;
  final bool anonymous;

  factory OmrResults.fromJson(Map<String, dynamic> m) {
    final s = asMap(m['summary']);
    return OmrResults(
      examId: asInt(m['exam_id']),
      title: '${m['title'] ?? ''}',
      students: [for (final x in asMapList(m['students'])) OmrStudentResult.fromJson(x)],
      questions: [for (final x in asMapList(m['questions'])) OmrQuestionStat.fromJson(x)],
      bins: [for (final b in asMapList(m['distribution'])) (from: asInt(b['from']), to: asInt(b['to']), count: asInt(b['count']))],
      studentsTotal: asInt(s['students']),
      graded: asInt(s['graded']),
      openReviewItems: asInt(s['open_review_items']),
      mean: _dbl(s['mean_percentage']),
      max: _dbl(s['max_percentage']),
      min: _dbl(s['min_percentage']),
      passed: asInt(s['passed']),
      publishedAt: omrUtc(m['published_at']),
      anonymous: m['anonymous'] == true,
    );
  }

  int get inReview => students.where((s) => !s.graded).length;
  int get failed => students.where((s) => s.graded && s.passed == false).length;
}

/// `POST …/omr/results/publish`.
class OmrPublishReply {
  const OmrPublishReply({this.publishedAt, this.gradedOnly = false, this.visibleAttempts = 0, this.openReviewItems = 0});
  final DateTime? publishedAt;
  final bool gradedOnly;
  final int visibleAttempts;
  final int openReviewItems;

  factory OmrPublishReply.fromJson(Map<String, dynamic> m) => OmrPublishReply(
        publishedAt: omrUtc(m['published_at']),
        gradedOnly: m['graded_only'] == true,
        visibleAttempts: asInt(m['visible_attempts']),
        openReviewItems: asInt(m['open_review_items']),
      );
}

// ── codes in plain words ────────────────────────────────────────────────────────────────────────────────────────

String omrStateText(String state) => switch (state) {
      'clear' => t('واضحة', 'clear'),
      'blank' => t('فارغة', 'blank'),
      'multiple' => t('أكثر من إجابة', 'multiple'),
      'uncertain' => t('غير واضحة', 'unclear'),
      _ => state,
    };

String omrMarkerText(String marker) => switch (marker) {
      'qr' => 'QR',
      'printed' => t('الحرف المطبوع', 'printed'),
      'bubble' => t('التظليل', 'shaded'),
      _ => marker,
    };

/// The server's review codes (omr_common.REVIEW_TEXT) — used only when an item carries no sentence of its own.
String omrCodeText(String code) => switch (code) {
      'identifier_no_match' => t('لا يوجد طالب بهذا الرقم', 'No student has this ID'),
      'identifier_duplicate' => t('أكثر من طالب لديهم هذا الرقم', 'More than one student has this ID'),
      'identifier_unclear' => t('تعذّرت قراءة رقم الطالب بثقة', 'The student ID could not be read with confidence'),
      'identifier_blank' => t('رقم الطالب فارغ', 'The student ID is empty'),
      'identifier_missing' => t('هذه الورقة لا تحمل رقم طالب', 'This sheet carries no student ID'),
      'identifier_not_set' => t('لم يُحدَّد معرّف الطالب للاختبار: اختر الطالب', 'The exam has no student identifier: choose the student'),
      'identifier_conflict' => t('رمز QR ورقم الطالب المظلّل يشيران إلى طالبين مختلفين', 'The QR code and the shaded ID name different students'),
      'student_not_in_exam' => t('هذا الطالب ليس من طلاب الاختبار', "This student is not in the exam's audience"),
      'student_already_scanned' => t('لهذا الطالب ورقة مصححة بالفعل', 'This student already has a graded sheet'),
      'attempt_in_progress' => t('للطالب محاولة جارية على الإنترنت', 'The student has an online attempt in progress'),
      'form_unconfirmed' => t('تعذّر تأكيد النموذج', 'Model could not be confirmed'),
      'form_unknown' => t('الورقة تحمل نموذجًا غير موجود في هذا الاختبار', 'The sheet names a form this exam does not have'),
      'qr_forged' => t('رمز QR في الورقة ليس رمزًا صالحًا لهذا الاختبار', "The sheet's QR code is not a valid code of this exam"),
      'uncertain' => t('التظليل غير واضح', 'The mark is unclear'),
      'blank' => t('لم تُظلَّل أي إجابة', 'No answer was shaded'),
      'multiple' => t('ظُلِّلت أكثر من إجابة', 'More than one answer was shaded'),
      'option_not_in_question' => t('الخيار المظلّل غير موجود في هذا السؤال', 'The shaded option does not exist in this question'),
      _ => code,
    };

/// The text of a failed call: the server's sentence in the app's language, else a mapped code, else a generic line.
String omrErrorText(EngineResult r) {
  final en = r.detail['message_en'];
  if (AppConfig.lang == 'en' && en != null && '$en'.isNotEmpty) return '$en';
  if (AppConfig.lang == 'ar' && r.message.isNotEmpty && r.code != null) return r.message;
  final mapped = switch (r.code) {
    'review_item_resolved' => t('تمت مراجعة هذا العنصر بالفعل', 'This item was already resolved.'),
    'page_gone' => t('الصفحة الممسوحة لم تعد متاحة', 'The scanned page is no longer available.'),
    'not_a_student' => t('طالب ليس من طلاب هذا الاختبار', 'This student is not in the exam.'),
    'review_items_open' => t('ما زالت هناك عناصر تنتظر المراجعة', 'Some items still need review.'),
    'forbidden' || 'org_forbidden' => t('ليست لديك صلاحية على هذا الاختبار', 'You do not have access to this exam.'),
    _ => '',
  };
  if (mapped.isNotEmpty) return mapped;
  if (r.code != null && omrCodeText(r.code!) != r.code) return omrCodeText(r.code!);
  if (r.status == 0) return t('لا يوجد اتصال — أعد المحاولة', 'No connection — try again');
  return t('تعذّر الحفظ — أعد المحاولة', 'Could not save — try again');
}

// ── API ─────────────────────────────────────────────────────────────────────────────────────────────────────────

class OmrReviewApi {
  OmrReviewApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> items(int examId, {String status = 'open', String? kind}) =>
      engineCall(() => _api.get('$_b/exams/$examId/review-items', queryParams: {'status': status, 'kind': ?kind, 'limit': 500}));
  Future<EngineResult> item(int examId, int itemId) => engineCall(() => _api.get('$_b/exams/$examId/review-items/$itemId'));
  Future<EngineResult> resolve(int examId, int itemId, Map<String, dynamic> body) =>
      engineCall(() => _api.post('$_b/exams/$examId/review-items/$itemId/resolve', body: body));
  Future<EngineResult> page(int examId, int pageId) => engineCall(() => _api.get('$_b/exams/$examId/omr/pages/$pageId'));
  Future<EngineResult> changes(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/changes'));
  Future<EngineResult> results(int examId) => engineCall(() => _api.get('$_b/exams/$examId/omr/results'));
  Future<EngineResult> publish(int examId, {bool gradedOnly = false}) =>
      engineCall(() => _api.post('$_b/exams/$examId/omr/results/publish', body: {'graded_only': gradedOnly}));

  /// The exam (title, course) for the student search.
  Future<EngineResult> exam(int examId) => engineCall(() => _api.get('$_b/exams/$examId'));

  /// The course's students matching [search] (the core; the course's teacher and admins).
  Future<EngineResult> students(int courseId, String search) =>
      engineCall(() => _api.get('/api/v1/courses/$courseId/students', queryParams: {'search': search, 'limit': 20}));

  /// A signed crop / page image (`/api/v1/exam/omr/images/{crop|page}/{id}?exp=&sig=`); null when it cannot be read.
  Future<Uint8List?> image(String? signedUrl) async {
    final u = Uri.tryParse(signedUrl ?? '');
    final seg = u?.pathSegments ?? const [];
    final i = seg.indexOf('images');
    if (u == null || i < 0 || seg.length < i + 3) return null;
    final what = seg[i + 1], id = seg[i + 2];
    try {
      return await _api.getBytes('$_b/omr/images/$what/$id', queryParams: u.queryParameters);
    } catch (_) {
      return null;
    }
  }
}

/// Students from `GET /api/v1/courses/{id}/students` (`{items: [{id, name, gmail}]}`).
List<OmrStudent> omrStudentsFrom(Map<String, dynamic> m) {
  final rows = m['items'] is List ? asMapList(m['items']) : asMapList(m['value']);
  return [for (final s in rows) OmrStudent(asInt(s['id']), '${s['name'] ?? ''}', email: s['gmail']?.toString())];
}

// ── export (Export Studio) ──────────────────────────────────────────────────────────────────────────────────────

/// The grades table for the Export Studio; call inside `bilingualExport(() => …)` so the other language's headers
/// come along.
AppTableExport omrResultsExport(OmrResults r) => AppTableExport(
      id: 'exam.omr.results',
      title: r.title.isEmpty ? t('نتائج الاختبار الورقي', 'Paper exam results') : r.title,
      subtitle: t('نتائج أوراق التظليل', 'Bubble-sheet results'),
      meta: [
        t('الطلاب: ${r.studentsTotal} · مصحّح: ${r.graded}', 'Students: ${r.studentsTotal} · graded: ${r.graded}'),
        if (r.mean != null) t('المتوسط: ${omrNum(r.mean)}%', 'Mean: ${omrNum(r.mean)}%'),
      ],
      columns: [
        AppExportColumn('student', r.anonymous ? t('الرمز', 'Code') : t('الطالب', 'Student'), locked: true),
        AppExportColumn('form', t('النموذج', 'Form')),
        AppExportColumn('score', t('الدرجة', 'Score'), type: AppColType.number, decimals: 2),
        AppExportColumn('max', t('من', 'Out of'), type: AppColType.number, decimals: 2),
        AppExportColumn('percentage', t('النسبة', 'Percent'), type: AppColType.percent, total: AppTotal.average),
        AppExportColumn('correct', t('صحيحة', 'Correct'), type: AppColType.integer),
        AppExportColumn('answered', t('مُجابة', 'Answered'), type: AppColType.integer),
        AppExportColumn('status', t('الحالة', 'Status'), type: AppColType.status, statusLabels: {
          'passed': t('ناجح', 'Passed'),
          'failed': t('لم ينجح', 'Not passed'),
          'review': t('قيد المراجعة', 'In review'),
          'graded': t('مصحّح', 'Graded'),
        }, statusTones: const {
          'passed': AppStatusTone.good,
          'failed': AppStatusTone.bad,
          'review': AppStatusTone.warn,
          'graded': AppStatusTone.neutral,
        }),
      ],
      rows: [
        for (final s in r.students)
          {
            'student': s.who,
            'form': s.formText,
            'score': s.score,
            'max': s.maxScore,
            'percentage': s.percentage,
            'correct': s.correct,
            'answered': s.answered,
            'status': !s.graded ? 'review' : (s.passed == true ? 'passed' : (s.passed == false ? 'failed' : 'graded')),
          },
      ],
    );
