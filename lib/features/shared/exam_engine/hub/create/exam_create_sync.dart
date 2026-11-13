// The wizard's one exam on the server. `ensure` makes the draft the first time it is needed and afterwards brings that
// same draft up to date, so going Back and changing an answer never makes a second one. Every part remembers what it
// last sent and sends only a difference, and a failure leaves the record exact, so calling it again finishes the job.
//
// `PUT /exams/{id}` replaces `settings`, and the identifier step writes `settings.print_identifiers` through the setup
// route, so an update always merges into what the server holds.
library;

import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:flutter_education_app/core/api_client.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, asMapList, t;
import '../../exam_authoring.dart';
import '../../exam_engine_api.dart' show EngineResult, ExamEngineApi, engineCall;
import '../../exam_quick.dart';
import '../../exam_versions.dart' show ExamVersionsApi, versionBody, versionsErrorText;
import '../../paper/exam_setup.dart' show ExamSetupApi, setupErrorText;
import 'exam_create_logic.dart';
import 'offline_plan_api.dart';

class _Placed {
  _Placed(this.fingerprint, this.questionId, this.placementId);
  final String fingerprint;
  final int questionId, placementId;
}

class ExamCreateSync {
  ExamCreateSync({ExamAuthoringApi? api, ExamSetupApi? setup, ExamVersionsApi? versions, OfflinePlanApi? plans, Future<EngineResult> Function(int)? deleter})
      : api = api ?? ExamAuthoringApi(),
        _setupApi = setup ?? ExamSetupApi(),
        _versionsApi = versions ?? ExamVersionsApi(),
        _plansApi = plans ?? OfflinePlanApi(),
        _deleter = deleter;

  final ExamAuthoringApi api;
  final ExamSetupApi _setupApi;
  final ExamVersionsApi _versionsApi;
  final OfflinePlanApi _plansApi;
  final Future<EngineResult> Function(int)? _deleter;
  String? _planSent;

  int? examId;
  int? _sectionId;
  bool published = false;
  final List<_Placed> _placed = [];
  String? _examSent, _sectionSent, _setupSent, _fileSent, _orderSent;
  int _versionsMade = 0;
  bool _markersSet = false;

  Future<String?>? _ensuring;

  /// The draft exists and holds [p]: returns the error to show, or null. Calls overlapping one in flight share it, because
  /// until the first answers there is no exam id and each would create its own exam.
  Future<String?> ensure(ExamCreatePlan p) => _ensuring ??= _ensure(p).whenComplete(() => _ensuring = null);

  Future<String?> _ensure(ExamCreatePlan p) async {
    final q = p.exam;
    q.mode ??= QuickMode.online;
    if (q.orgId == null && q.courseId != null) q.orgId = (await api.resolveScope(q.courseId!)).orgId;
    return await _exam(p) ?? await _section(q) ?? await _questions(p) ?? await _file(q) ?? await _setup(p);
  }

  Future<String?> _exam(ExamCreatePlan p) async {
    final body = p.exam.toExamDraft().toBody();
    // the answer format and the booklet travel with the print plan (D-661)
    final planned = {...asMap(body['settings']), ...p.settingsJson};
    body['settings'] = planned;
    final sent = jsonEncode(body);
    if (sent == _examSent) return null;
    if (examId == null) {
      final r = await api.createExam(body);
      if (!r.ok) return authoringError(r);
      examId = asInt(r.map['id']);
    } else {
      final held = await api.exam(examId!);
      if (!held.ok) return authoringError(held);
      body['settings'] = {...asMap(held.map['settings']), ...planned};
      final r = await api.updateExam(examId!, body);
      if (!r.ok) return authoringError(r);
    }
    _examSent = sent;
    return null;
  }

  Future<String?> _section(QuickExam q) async {
    final body = q.toSection().toBody();
    final sent = jsonEncode(body);
    if (sent == _sectionSent && _sectionId != null) return null;
    final EngineResult r;
    if (_sectionId == null) {
      r = await api.addSection(examId!, body);
      if (r.ok) _sectionId = asInt(r.map['id']);
    } else {
      r = await api.updateSection(examId!, _sectionId!, body);
    }
    if (!r.ok) return authoringError(r);
    _sectionSent = sent;
    return null;
  }

  /// Keeps the questions that did not change, replaces those that did, then puts them in the teacher's order.
  Future<String?> _questions(ExamCreatePlan p) async {
    final q = p.exam;
    final drafts = q.questionDrafts();
    final prints = [for (final d in drafts) _fingerprint(d, q)];
    final spare = List<_Placed>.of(_placed);
    final kept = <_Placed?>[
      for (final f in prints)
        () {
          final i = spare.indexWhere((x) => x.fingerprint == f);
          return i < 0 ? null : spare.removeAt(i);
        }(),
    ];
    for (final old in spare) {
      final r = await api.unplace(examId!, old.placementId);
      if (!r.ok) return authoringError(r);
      _placed.remove(old);
      unawaited(api.archiveQuestion(old.questionId));   // only ever a question this wizard wrote a moment ago
    }
    for (var i = 0; i < drafts.length; i++) {
      if (kept[i] != null) continue;
      final d = drafts[i];
      final created = await api.createQuestion(d.toCreate(orgId: q.orgId, courseId: q.courseId));
      if (!created.ok) return authoringError(created);
      final placed = await api.place(examId!, _sectionId!, questionId: asInt(created.map['id']), points: d.points);
      if (!placed.ok) return authoringError(placed);
      kept[i] = _Placed(prints[i], asInt(created.map['id']), asInt(placed.map['placement_id']));
      _placed.add(kept[i]!);
    }
    _placed
      ..clear()
      ..addAll([for (final x in kept) x!]);
    // one order for the written and the held questions of this section (D-717): the server wants the whole set
    final want = q.isFile ? [for (final x in kept) x!.placementId] : questionOrder(p, [for (final x in kept) x!.placementId], _sectionId!);
    final sent = jsonEncode(want);
    if (want.length > 1 && sent != _orderSent) {
      final r = await api.reorderQuestions(examId!, _sectionId!, want);
      if (!r.ok) return authoringError(r);
    }
    _orderSent = sent;
    return null;
  }

  /// Takes a held question (an import) off the draft; the bank question stays the teacher's.
  Future<String?> removeHeld(HeldQuestion h) async {
    final id = examId;
    if (id == null) return null;
    final r = await api.unplace(id, h.placementId);
    if (!r.ok) return authoringError(r);
    _orderSent = null;
    return null;
  }

  String _fingerprint(QuestionDraft d, QuickExam q) => jsonEncode([d.toCreate(orgId: q.orgId, courseId: q.courseId), d.points]);

  Future<String?> _file(QuickExam q) async {
    final key = q.isFile && q.hasFile ? '${q.fileName}:${q.fileBytes?.length ?? q.filePath}' : null;
    if (key == _fileSent) return null;
    final r = key == null
        ? await api.removePaperFile(examId!)
        : await api.uploadPaperFile(examId!, fileName: q.fileName!, bytes: q.fileBytes, path: q.filePath);
    if (!r.ok) return authoringError(r);
    _fileSent = key;
    return null;
  }

  Future<String?> _setup(ExamCreatePlan p) async {
    final body = p.setupBody;
    if (body == null) return null;
    final sent = jsonEncode(body);
    if (sent == _setupSent) return null;
    final r = await _setupApi.putSetup(examId!, body);
    if (!r.ok) return setupErrorText(r);
    _setupSent = sent;
    _markersSet = false;
    return null;
  }

  /// Everything, then the printed versions and their marks, then Publish. Safe to call again after a failure.
  Future<String?> finish(ExamCreatePlan p) async {
    final e = await ensure(p);
    if (e != null) return e;
    if (p.isPaper) {
      final plan = await _offlinePlan(p);
      if (plan != null) return plan;
      final v = await _versions(p);
      if (v != null) return v;
    }
    if (published) return null;
    final r = await api.lifecycle(examId!, ExamAction.publish);
    if (!r.ok) return authoringError(r);
    published = true;
    return null;
  }

  /// The paper plan through `PUT /exams/{id}/offline-plan` (contract §2): the server checks it (the bubble form, the
  /// students' source, the attributes) and stores it normalised. An older server without the route keeps the plan the
  /// exam's settings already carry.
  Future<String?> _offlinePlan(ExamCreatePlan p) async {
    final plan = p.offlinePlan;
    if (plan == null) return null;
    final sent = jsonEncode(plan.toJson());
    if (sent == _planSent) return null;
    final r = await _plansApi.putPlan(examId!, plan);
    if (!r.ok && !r.unavailable) return offlinePlanErrorText(r);
    _planSent = sent;
    return null;
  }

  Future<String?> _versions(ExamCreatePlan p) async {
    final n = p.effectiveVersions;
    if (n <= 1 && _versionsMade <= 1) return null;
    if (n <= 1 && _markersSet) {
      final off = await _setupApi.putSetup(examId!, {'form_markers': const <String>[]});
      if (!off.ok) return setupErrorText(off);
      _markersSet = false;
    }
    final made = await _versionsApi.generate(
        examId!, versionBody(count: n, shuffleQuestions: p.shuffleQuestions && p.shuffleQuestionsAllowed, shuffleOptions: p.shuffleOptions && p.shuffleOptionsAllowed));
    if (!made.ok) return versionsErrorText(made);
    _versionsMade = n;
    if (n > 1) {
      final on = await _setupApi.putSetup(examId!, {'form_markers': kVersionMarkers});
      if (!on.ok) return setupErrorText(on);
      _markersSet = true;
    }
    return null;
  }

  /// What the server holds that this wizard did not place (read back after an import or the full editor), in the
  /// server's order. The wizard's own file question is not one of them.
  Future<List<HeldQuestion>?> imported() async {
    final id = examId;
    if (id == null) return null;
    final r = await api.exam(id);
    if (!r.ok) return null;
    _orderSent = null;
    return heldOf(r.map, {for (final x in _placed) x.placementId});
  }

  /// Removes the draft and the questions written for it.
  Future<String?> discard() async {
    final id = examId;
    if (id == null) return null;
    final r = await (_deleter?.call(id) ?? engineCall(() => ApiClient().delete('${ExamEngineApi.base}/exams/$id')));
    if (!r.ok) return r.message.isEmpty ? t('تعذّر حذف المسودة', 'Could not delete the draft') : authoringError(r);
    for (final x in _placed) {
      unawaited(api.archiveQuestion(x.questionId));
    }
    _placed.clear();
    examId = null;
    _sectionId = null;
    _examSent = _sectionSent = _setupSent = _fileSent = _planSent = _orderSent = null;
    return null;
  }
}

/// The held questions in a `GET /exams/{id}` answer: every placement not in [mine].
List<HeldQuestion> heldOf(Map<String, dynamic> exam, Set<int> mine) => [
      for (final s in asMapList(exam['sections']))
        for (final x in asMapList(s['questions']))
          if (!mine.contains(asInt(x['placement_id'])))
            HeldQuestion(
              placementId: asInt(x['placement_id']),
              sectionId: asInt(s['id']),
              type: '${x['type'] ?? ''}',
              prompt: '${asMap(x['body'])['prompt'] ?? ''}',
              points: x['points'] is num ? (x['points'] as num).toDouble() : 0,
            ),
    ];

/// The section's placements in the list's order (D-717): [written] are the wizard's own, in [QuickExam.questions]
/// order; held questions of another section keep their place there.
List<int> questionOrder(ExamCreatePlan p, List<int> written, int sectionId) {
  final out = <int>[];
  var i = 0;
  for (final e in p.entries) {
    if (e.local != null) {
      if (i < written.length) out.add(written[i++]);
    } else if (e.held!.sectionId == sectionId) {
      out.add(e.held!.placementId);
    }
  }
  while (i < written.length) {
    out.add(written[i++]);
  }
  return out;
}
