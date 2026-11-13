// The stored design of one exam's printed paper (D-196): `GET|PUT /api/v1/exam/exams/{id}/paper-design`.
//
//   GET  → {"document": {…}|null, "cover": {…}|null, "version": n, "cover_code": "NBC:…"}
//   PUT  {"document", "cover", "version"} → the same; a stale version answers 409 `design_conflict`.
//
// The document is an engine LayoutDocument (purpose exam_paper), the cover is
// `{mode, design: LayoutDocument|null, university, marks_table, upload, stamp, answer}` (D-730, exam_cover.dart). Pure parts (the models, the body) are tested without a
// network in test/org/exam_paper_designer_test.dart.
import 'package:flutter_education_app/core/api_client.dart';

import '../../../design/export_layout/layout_model.dart';
import '../../admin/admin_common.dart' show asMap, t;
import 'exam_engine_api.dart';

/// Which cover a document starts with (D-730): the designed one (D-196), the teacher's own uploaded file, or none.
enum CoverMode { none, designed, uploaded }

/// Where the student's details box sits on an uploaded cover.
enum CoverPlace { top, middle, bottom }

CoverMode _mode(Object? v, CoverMode fallback) => CoverMode.values.firstWhere((x) => x.name == v, orElse: () => fallback);

/// The teacher's own cover: ONE picture in the layout asset store (an image, or the chosen page of a PDF made PNG by the
/// server), with what the picker shows about it.
class CoverUpload {
  const CoverUpload({required this.assetId, this.page = 1, this.pages = 1, this.width = 0, this.height = 0, this.name = ''});
  final String assetId;

  /// The PDF page used (1-based) and the PDF's page count; 1 / 1 for an image.
  final int page, pages;
  final int width, height;
  final String name;
  bool get fromPdf => pages > 1 || name.toLowerCase().endsWith('.pdf');

  Map<String, dynamic> toJson() => {'asset_id': assetId, 'page': page, 'pages': pages, 'w': width, 'h': height, 'name': name};

  static CoverUpload? fromJson(Object? j) {
    if (j is! Map || '${j['asset_id'] ?? ''}'.isEmpty) return null;
    int n(Object? v, int d) => v is num ? v.toInt() : d;
    return CoverUpload(
        assetId: '${j['asset_id']}', page: n(j['page'], 1), pages: n(j['pages'], 1), width: n(j['w'], 0), height: n(j['h'], 0), name: '${j['name'] ?? ''}');
  }
}

/// The per-student details box on an uploaded cover: off by default (D-716 copies may turn it on).
class CoverStamp {
  const CoverStamp({this.on = false, this.place = CoverPlace.top});
  final bool on;
  final CoverPlace place;
  CoverStamp copyWith({bool? on, CoverPlace? place}) => CoverStamp(on: on ?? this.on, place: place ?? this.place);
  Map<String, dynamic> toJson() => {'on': on, 'place': place.name};
  static CoverStamp fromJson(Object? j) => j is Map
      ? CoverStamp(on: j['on'] == true, place: CoverPlace.values.firstWhere((x) => x.name == j['place'], orElse: () => CoverPlace.top))
      : const CoverStamp();
}

/// One document's cover choice, resolved: what the renderers and the picker read.
class CoverSide {
  const CoverSide({this.mode = CoverMode.none, this.upload, this.stamp = const CoverStamp()});
  final CoverMode mode;
  final CoverUpload? upload;
  final CoverStamp stamp;

  /// A cover page prints (an uploaded choice without its file prints nothing).
  bool get on => mode == CoverMode.designed || (mode == CoverMode.uploaded && upload != null);
}

/// The answer side (the booklet, the NB2 / bubble sheets): none, its own uploaded file, or the question paper's cover.
class AnswerCoverSpec {
  const AnswerCoverSpec({this.same = false, this.mode = CoverMode.none, this.upload, this.stamp = const CoverStamp()});
  final bool same;

  /// none | uploaded (a designed answer cover is the paper's, through [same]).
  final CoverMode mode;
  final CoverUpload? upload;
  final CoverStamp stamp;

  AnswerCoverSpec copyWith({bool? same, CoverMode? mode, CoverUpload? upload, bool clearUpload = false, CoverStamp? stamp}) => AnswerCoverSpec(
      same: same ?? this.same, mode: mode ?? this.mode, upload: clearUpload ? null : (upload ?? this.upload), stamp: stamp ?? this.stamp);

  Map<String, dynamic> toJson() => {'same': same, 'mode': mode.name, if (upload != null) 'upload': upload!.toJson(), 'stamp': stamp.toJson()};

  static AnswerCoverSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = _mode(j['mode'], CoverMode.none);
    return AnswerCoverSpec(
        same: j['same'] == true,
        mode: m == CoverMode.designed ? CoverMode.none : m,
        upload: CoverUpload.fromJson(j['upload']),
        stamp: CoverStamp.fromJson(j['stamp']));
  }
}

/// The cover pages of the exam (D-196, D-730): the question paper's ([mode]: its own [design] (null = the built-in
/// cover), the university line and the per-question marks grid; or an uploaded file; or none) and the answer side's
/// [answer]. Pure parts are tested in test/org/exam_cover_test.dart.
class PaperCoverSpec {
  const PaperCoverSpec(
      {this.design, this.university = '', this.marksTable = true, this.mode = CoverMode.designed, this.upload, this.stamp = const CoverStamp(), this.answer});
  final LayoutDocument? design;
  final String university;
  final bool marksTable;
  final CoverMode mode;
  final CoverUpload? upload;
  final CoverStamp stamp;
  final AnswerCoverSpec? answer;

  PaperCoverSpec copyWith(
          {LayoutDocument? design,
          bool clearDesign = false,
          String? university,
          bool? marksTable,
          CoverMode? mode,
          CoverUpload? upload,
          bool clearUpload = false,
          CoverStamp? stamp,
          AnswerCoverSpec? answer}) =>
      PaperCoverSpec(
        design: clearDesign ? null : (design ?? this.design),
        university: university ?? this.university,
        marksTable: marksTable ?? this.marksTable,
        mode: mode ?? this.mode,
        upload: clearUpload ? null : (upload ?? this.upload),
        stamp: stamp ?? this.stamp,
        answer: answer ?? this.answer,
      );

  /// The question paper's cover, resolved.
  CoverSide get paperSide => CoverSide(mode: mode, upload: upload, stamp: stamp);

  /// The answer side's cover, resolved ("same" = the paper's).
  CoverSide get answerSide {
    final a = answer;
    if (a == null) return const CoverSide();
    if (a.same) return paperSide;
    return CoverSide(mode: a.mode, upload: a.upload, stamp: a.stamp);
  }

  /// Nothing would print: saved as no cover at all (`cover: null`).
  bool get isNone => !paperSide.on && !answerSide.on;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'design': design?.toJson(withSource: false),
        'university': university,
        'marks_table': marksTable,
        if (upload != null) 'upload': upload!.toJson(),
        'stamp': stamp.toJson(),
        if (answer != null) 'answer': answer!.toJson(),
      };

  static PaperCoverSpec? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = asMap(j);
    return PaperCoverSpec(
      design: _doc(m['design']),
      university: '${m['university'] ?? ''}',
      marksTable: m['marks_table'] != false,
      // a cover saved before D-730 is the designed one
      mode: _mode(m['mode'], CoverMode.designed),
      upload: CoverUpload.fromJson(m['upload']),
      stamp: CoverStamp.fromJson(m['stamp']),
      answer: AnswerCoverSpec.fromJson(m['answer']),
    );
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
  const PaperDesignState({this.document, this.cover, this.version = 0, this.coverCode = ''});
  final LayoutDocument? document;
  final PaperCoverSpec? cover;
  final int version;

  /// The signed QR payload every printed cover page carries, so the scanner sets cover pages aside (D-732); '' on an
  /// older server (covers then print without it).
  final String coverCode;

  bool get isEmpty => document == null && cover == null;

  factory PaperDesignState.fromJson(Map<String, dynamic> j) =>
      PaperDesignState(
          document: _doc(j['document']),
          cover: PaperCoverSpec.fromJson(j['cover']),
          version: j['version'] is num ? (j['version'] as num).toInt() : 0,
          coverCode: '${j['cover_code'] ?? ''}');
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
      'design_too_large' || 'design_too_big' || 'payload_too_large' => t('التصميم أكبر من المسموح (512 كيلوبايت)', 'The design is too large to save (512 KB)'),
      'cover_file_missing' => t('ارفع ملف الغلاف أولًا', 'Upload the cover file first'),
      'cover_invalid' => t('اختيار الغلاف غير صالح', 'The cover choice is not valid'),
      'forbidden' || 'not_manager' => t('لا تملك صلاحية تعديل تصميم هذا الامتحان', 'You may not change this exam\'s paper design'),
      _ => r.unavailable ? t('هذه الميزة تحتاج تحديث الخادم', 'This needs a server update') : (r.message.isEmpty ? t('تعذّر حفظ التصميم', 'Could not save the design') : r.message),
    };
