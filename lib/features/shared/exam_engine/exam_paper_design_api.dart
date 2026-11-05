// The stored design of one exam's printed paper (D-196): `GET|PUT /api/v1/exam/exams/{id}/paper-design`.
//
//   GET  → {"document": {…}|null, "cover": {…}|null, "version": n}
//   PUT  {"document", "cover", "version"} → the same; a stale version answers 409 `design_conflict`.
//
// The document is an engine LayoutDocument (purpose exam_paper), the cover is
// `{design: LayoutDocument|null, university, marks_table}`. Pure parts (the models, the body) are tested without a
// network in test/org/exam_paper_designer_test.dart.
import 'package:flutter_education_app/core/api_client.dart';

import '../../../design/export_layout/layout_model.dart';
import '../../admin/admin_common.dart' show asMap, t;
import 'exam_engine_api.dart';

/// The cover page of the paper: its own design (null = the built-in cover), the university line and whether the
/// per-question marks grid is drawn.
class PaperCoverSpec {
  const PaperCoverSpec({this.design, this.university = '', this.marksTable = true});
  final LayoutDocument? design;
  final String university;
  final bool marksTable;

  PaperCoverSpec copyWith({LayoutDocument? design, bool clearDesign = false, String? university, bool? marksTable}) => PaperCoverSpec(
        design: clearDesign ? null : (design ?? this.design),
        university: university ?? this.university,
        marksTable: marksTable ?? this.marksTable,
      );

  Map<String, dynamic> toJson() => {
        'design': design?.toJson(withSource: false),
        'university': university,
        'marks_table': marksTable,
      };

  static PaperCoverSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return PaperCoverSpec(design: _doc(m['design']), university: '${m['university'] ?? ''}', marksTable: m['marks_table'] != false);
  }
}

LayoutDocument? _doc(Object? j) {
  if (j is! Map || j['designs'] is! Map) return null;
  try {
    return LayoutDocument.fromJson(asMap(j));
  } catch (_) {
    return null;
  }
}

/// What the server holds for an exam: no design yet = both null, version 0.
class PaperDesignState {
  const PaperDesignState({this.document, this.cover, this.version = 0});
  final LayoutDocument? document;
  final PaperCoverSpec? cover;
  final int version;

  bool get isEmpty => document == null && cover == null;

  factory PaperDesignState.fromJson(Map<String, dynamic> j) =>
      PaperDesignState(document: _doc(j['document']), cover: PaperCoverSpec.fromJson(j['cover']), version: j['version'] is num ? (j['version'] as num).toInt() : 0);
}

/// The PUT body.
Map<String, dynamic> paperDesignBody({LayoutDocument? document, PaperCoverSpec? cover, required int version}) => {
      'document': document?.toJson(withSource: false),
      'cover': cover?.toJson(),
      'version': version,
    };

/// The server's reply to a save.
class PaperDesignSave {
  const PaperDesignSave.ok(this.state)
      : conflict = false,
        error = null;
  const PaperDesignSave.conflict()
      : state = null,
        conflict = true,
        error = null;
  const PaperDesignSave.failed(this.error)
      : state = null,
        conflict = false;
  final PaperDesignState? state;

  /// 409 `design_conflict`: someone saved a newer design since this one was loaded.
  final bool conflict;
  final String? error;
  bool get ok => state != null;
}

class ExamPaperDesignApi {
  ExamPaperDesignApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  /// `null` when the engine route is missing (an older server) or the call failed: the sheet then works as before.
  Future<PaperDesignState?> load(int examId) async {
    final r = await engineCall(() => _api.get('$_b/exams/$examId/paper-design'));
    return r.ok ? PaperDesignState.fromJson(r.map) : null;
  }

  Future<PaperDesignSave> save(int examId, {LayoutDocument? document, PaperCoverSpec? cover, required int version}) async {
    final r = await engineCall(() => _api.put('$_b/exams/$examId/paper-design', body: paperDesignBody(document: document, cover: cover, version: version)));
    return paperDesignSaveOf(r);
  }
}

/// A PUT answer as a [PaperDesignSave] (409 → conflict, other failures → bilingual text).
PaperDesignSave paperDesignSaveOf(EngineResult r) {
  if (r.ok) return PaperDesignSave.ok(PaperDesignState.fromJson(r.map));
  if (r.status == 409 || r.code == 'design_conflict') return const PaperDesignSave.conflict();
  return PaperDesignSave.failed(paperDesignErrorText(r));
}

String paperDesignErrorText(EngineResult r) => switch (r.code) {
      'design_too_big' || 'payload_too_large' => t('التصميم أكبر من المسموح (512 كيلوبايت)', 'The design is too large to save (512 KB)'),
      'forbidden' || 'not_manager' => t('لا تملك صلاحية تعديل تصميم هذا الامتحان', 'You may not change this exam\'s paper design'),
      _ => r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This needs a server update') : (r.message.isEmpty ? t('تعذّر حفظ التصميم', 'Could not save the design') : r.message),
    };
