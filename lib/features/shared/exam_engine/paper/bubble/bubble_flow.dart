// The premium bubble-sheet flow (D-340 – D-343), the pure part: what the server sent, in plain Dart. A teacher teaches
// any answer sheet in four checked pictures, confirms a detection drawn over the sheet, gives the key, and the marks
// go to Excel or a chosen Data Lab column. The screens only draw this; every verdict (what is final, what goes to
// review) is the engine's (`../back/exam_engine/services/omr_teach.py`, `bubble_runs.py`).
library;

import 'dart:typed_data';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';

import '../../../../admin/admin_common.dart' show asInt, asMap, t;
import '../../exam_engine_api.dart' show EngineResult, engineCall;

const kBubbleFeature = 'exam.bubble';
const kBubbleTeachFeature = 'exam.bubble.teach';
const kBubbleKeySheetFeature = 'exam.bubble.key_sheet';
const kBubbleDataLabFeature = 'exam.bubble.datalab';
const kBubbleFromKeyFeature = 'exam.bubble.from_key';

/// The wizard's pictures, in their required order.
enum BubbleStep { question, identifier, empty, filled }

extension BubbleStepName on BubbleStep {
  String get wire => name;
  String get title => switch (this) {
        BubbleStep.question => t('صورة لسؤال واحد', 'One question'),
        BubbleStep.identifier => t('منطقة رقم الطالب', 'The student ID area'),
        BubbleStep.empty => t('ورقة فارغة', 'An empty sheet'),
        BubbleStep.filled => t('ورقة مظلّلة', 'A filled sheet'),
      };
  String get shortTitle => switch (this) {
        BubbleStep.question => t('السؤال', 'Question'),
        BubbleStep.identifier => t('رقم الطالب', 'Student ID'),
        BubbleStep.empty => t('فارغة', 'Empty'),
        BubbleStep.filled => t('مظلّلة', 'Filled'),
      };
  String get help => switch (this) {
        BubbleStep.question => t('صوّر سؤالًا واحدًا بكل اختياراته — نقرأ منه شكل الفقاعات وعدد الاختيارات.', 'Show one question with all its choices. We learn the bubbles\' shape and how many choices it has.'),
        BubbleStep.identifier => t('صوّر الجزء الذي يدوّن فيه الطالب رقمه — شبكة أرقام مظلّلة أو خانات أو كود.', 'Show the part where the student gives their number: a shaded grid, boxes, or a code.'),
        BubbleStep.empty => t('ورقة كاملة بلا أي تظليل، مصوّرة من الأعلى وبإضاءة جيدة.', 'A whole sheet with nothing shaded, taken from above in good light.'),
        BubbleStep.filled => t('نفس الورقة بعد تظليل بعض الإجابات (أي إجابات) لتعلّم شكل الخطوط.', 'The same sheet with some answers shaded (any answers), to learn how the marks look.'),
      };
  String get doneHint => switch (this) {
        BubbleStep.question => t('صورة جيدة', 'A good picture'),
        BubbleStep.identifier => t('تم التعرف على المنطقة', 'The area was recognised'),
        BubbleStep.empty => t('الورقة واضحة وفارغة', 'A clear, empty sheet'),
        BubbleStep.filled => t('تطابق الورقة الفارغة', 'It matches the empty sheet'),
      };
}

class BubbleIssue {
  const BubbleIssue({required this.code, required this.ar, required this.en});
  final String code, ar, en;
  String get text => AppConfig.lang == 'ar' ? ar : en;

  factory BubbleIssue.fromJson(Object? v) {
    final m = asMap(v);
    return BubbleIssue(code: '${m['code'] ?? ''}', ar: '${m['ar'] ?? ''}', en: '${m['en'] ?? ''}');
  }
}

List<BubbleIssue> bubbleIssues(Object? v) => v is List ? [for (final x in v) BubbleIssue.fromJson(x)] : const [];

class BubbleStepResult {
  BubbleStepResult({required this.ok, this.issues = const [], this.options, this.shape, this.kind, this.digits, this.summary});
  final bool ok;
  final List<BubbleIssue> issues;
  final int? options;
  final String? shape, kind;
  final int? digits;
  final Map<String, dynamic>? summary;

  factory BubbleStepResult.fromJson(Object? v) {
    final m = asMap(v);
    return BubbleStepResult(
      ok: m['ok'] == true,
      issues: bubbleIssues(m['issues']),
      options: m['options'] is int ? m['options'] as int : null,
      shape: m['shape'] as String?,
      kind: m['kind'] as String?,
      digits: m['digits'] is int ? m['digits'] as int : null,
      summary: m['summary'] is Map<String, dynamic> ? m['summary'] as Map<String, dynamic> : null,
    );
  }
}

/// One numbered question as the engine ordered it (D-500): the app draws it, it never re-derives the numbering.
class BubbleQuestionMark {
  const BubbleQuestionMark({required this.n, required this.block, required this.cells, required this.labels});
  final int n, block;
  final List<List<double>> cells;
  final List<String> labels;

  factory BubbleQuestionMark.fromJson(Map<String, dynamic> m) => BubbleQuestionMark(
        n: asInt(m['n']),
        block: asInt(m['block']),
        cells: [for (final p in (m['cells'] is List ? m['cells'] as List : const [])) if (p is List && p.length == 2) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]],
        labels: [for (final l in (m['labels'] is List ? m['labels'] as List : const [])) '$l'],
      );
}

/// A region of the sheet with something to confirm.
class BubbleUnsure {
  const BubbleUnsure({required this.code, required this.ar, required this.en, this.box});
  final String code, ar, en;

  /// [x, y, w, h] as fractions of the sheet, null when it is about the whole sheet.
  final List<double>? box;
  String get text => AppConfig.lang == 'ar' ? ar : en;
}

class BubbleImport {
  BubbleImport({
    required this.id,
    required this.name,
    required this.status,
    required this.steps,
    required this.doneSteps,
    required this.nextStep,
    required this.layout,
    required this.summary,
    required this.unsure,
    required this.rounds,
    required this.understood,
    required this.templateId,
    this.imageW = 1240,
    this.imageH = 1754,
    this.onePhoto = false,
    this.issues = const [],
    this.marks = const [],
    this.direction = 'ltr',
    this.order = 'down',
  });

  final int id;
  final String? name;
  final String status;
  final Map<String, BubbleStepResult> steps;
  final List<String> doneSteps;
  final String? nextStep;
  final Map<String, dynamic>? layout;
  final Map<String, dynamic>? summary;
  final List<BubbleUnsure> unsure;
  final int rounds;
  final List<Map<String, dynamic>> understood;
  final int? templateId;
  final int imageW, imageH;

  /// Made from one picture (D-500), not the older four.
  final bool onePhoto;

  /// How to get a better picture (the sheet is cut off, too dark...).
  final List<BubbleIssue> issues;
  final List<BubbleQuestionMark> marks;
  final String direction;

  /// "down" each column, or "across" the rows.
  final String order;

  bool get isRtl => direction == 'rtl';
  bool get isAcross => order == 'across';

  /// "4", or "4–5" on a sheet whose questions differ.
  String get optionsText {
    final counts = {for (final q in marks) q.cells.length};
    if (counts.length < 2) return '$options';
    final s = counts.toList()..sort();
    return '${s.first}–${s.last}';
  }

  bool get allPictures => nextStep == null;
  bool get detected => layout != null;
  bool get confirmed => status == 'confirmed';
  int get questions => (summary?['questions'] as num?)?.toInt() ?? 0;
  int get options => (summary?['options'] as num?)?.toInt() ?? 0;
  int get idDigits => (summary?['id_digits'] as num?)?.toInt() ?? 0;
  String get idKind => '${summary?['id_kind'] ?? 'none'}';
  String get shape => '${summary?['shape'] ?? 'circle'}';

  List<BubbleBlock> get blocks => [
        for (final b in (layout?['blocks'] is List ? layout!['blocks'] as List : const []))
          if (b is Map<String, dynamic>) BubbleBlock.fromJson(b)
      ];

  factory BubbleImport.fromJson(Map<String, dynamic> j) {
    final steps = <String, BubbleStepResult>{};
    final sm = asMap(j['steps']);
    for (final e in sm.entries) {
      steps[e.key] = BubbleStepResult.fromJson(e.value);
    }
    final image = asMap(j['image']);
    List<BubbleUnsure> uns = const [];
    if (j['unsure'] is List) {
      uns = [
        for (final v in j['unsure'] as List)
          if (v is Map<String, dynamic>)
            BubbleUnsure(
                code: '${v['code'] ?? ''}',
                ar: '${v['ar'] ?? ''}',
                en: '${v['en'] ?? ''}',
                box: v['box'] is List && (v['box'] as List).length == 4 ? [for (final n in v['box'] as List) (n as num).toDouble()] : null)
      ];
    }
    return BubbleImport(
      id: asInt(j['id']),
      name: j['name'] as String?,
      status: '${j['status'] ?? 'draft'}',
      steps: steps,
      doneSteps: [for (final s in (j['done_steps'] is List ? j['done_steps'] as List : const [])) '$s'],
      nextStep: j['next_step'] as String?,
      layout: j['layout'] is Map<String, dynamic> ? j['layout'] as Map<String, dynamic> : null,
      summary: j['summary'] is Map<String, dynamic> ? j['summary'] as Map<String, dynamic> : null,
      unsure: uns,
      rounds: asInt(j['rounds']),
      understood: [for (final u in (j['understood'] is List ? j['understood'] as List : const [])) if (u is Map<String, dynamic>) u],
      templateId: j['template_id'] is int ? j['template_id'] as int : null,
      imageW: asInt(image['w'], 1240),
      imageH: asInt(image['h'], 1754),
      onePhoto: j['one_photo'] == true,
      issues: bubbleIssues(j['issues']),
      marks: [for (final q in (j['questions'] is List ? j['questions'] as List : const [])) if (q is Map<String, dynamic>) BubbleQuestionMark.fromJson(q)],
      direction: '${asMap(j['numbering'])['direction'] ?? 'ltr'}',
      order: '${asMap(j['numbering'])['order'] ?? 'down'}',
    );
  }
}

class BubbleBlock {
  const BubbleBlock({required this.id, required this.role, required this.box, required this.rows, required this.cols, required this.cells});
  final int id;
  final String role;
  final List<double> box;
  final int rows, cols;
  final List<List<List<double>>> cells;

  factory BubbleBlock.fromJson(Map<String, dynamic> m) {
    final b = m['box'] is List ? m['box'] as List : const [0, 0, 0, 0];
    return BubbleBlock(
      id: asInt(m['id']),
      role: '${m['role'] ?? 'answers'}',
      box: [for (final v in b) (v as num).toDouble()],
      rows: asInt(m['rows']),
      cols: asInt(m['cols']),
      cells: [
        for (final row in (m['cells'] is List ? m['cells'] as List : const []))
          if (row is List) [for (final p in row) if (p is List && p.length == 2) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]]
      ],
    );
  }
}

/// What a tap on the sheet means.
enum BubbleTapMode {
  wrongRegion,
  missingQuestion,
  extraBubble,
  setIdentifier,
  setVersion,
  addBubble,
  fixOptions,
  dragId;

  /// What the one-photo result offers.
  static const quickFixes = [fixOptions, missingQuestion, extraBubble, addBubble, dragId, setIdentifier, wrongRegion];

  /// What the older four-picture review offers.
  static const legacy = [wrongRegion, missingQuestion, extraBubble, setIdentifier, setVersion];
}

extension BubbleTapModeWire on BubbleTapMode {
  String get wire => switch (this) {
        BubbleTapMode.wrongRegion => 'wrong_region',
        BubbleTapMode.missingQuestion => 'missing_question',
        BubbleTapMode.extraBubble => 'extra_bubble',
        BubbleTapMode.setIdentifier => 'set_role',
        BubbleTapMode.setVersion => 'set_role',
        BubbleTapMode.addBubble => 'add_bubble',
        BubbleTapMode.fixOptions => '',
        BubbleTapMode.dragId => '',
      };

  /// What to do next, shown under the tools.
  String get hint => switch (this) {
        BubbleTapMode.wrongRegion => t('انقر على منطقة ليست أسئلة', 'Tap a region that is not questions'),
        BubbleTapMode.missingQuestion => t('انقر حيث يوجد السؤال الناقص', 'Tap where the missing question is'),
        BubbleTapMode.extraBubble => t('انقر على الفقاعة الزائدة', 'Tap the extra bubble'),
        BubbleTapMode.setIdentifier => t('انقر على منطقة رقم الطالب', 'Tap the student ID area'),
        BubbleTapMode.setVersion => t('انقر على صف النموذج', 'Tap the version row'),
        BubbleTapMode.addBubble => t('انقر حيث توجد الفقاعة الناقصة', 'Tap where the missing bubble is'),
        BubbleTapMode.fixOptions => t('انقر على مجموعة أسئلة، ثم غيّر العدد', 'Tap a group of questions, then change the count'),
        BubbleTapMode.dragId => t('اسحب مربعًا حول منطقة رقم الطالب', 'Drag a box around the student ID area'),
      };
  String get label => switch (this) {
        BubbleTapMode.wrongRegion => t('منطقة خاطئة', 'Wrong region'),
        BubbleTapMode.missingQuestion => t('سؤال ناقص', 'Missing question'),
        BubbleTapMode.extraBubble => t('فقاعة زائدة', 'Extra bubble'),
        BubbleTapMode.setIdentifier => t('هذه منطقة الرقم', 'This is the ID area'),
        BubbleTapMode.setVersion => t('صف النموذج', 'Version row'),
        BubbleTapMode.addBubble => t('فقاعة ناقصة', 'Missing bubble'),
        BubbleTapMode.fixOptions => t('عدد الاختيارات', 'Number of choices'),
        BubbleTapMode.dragId => t('اسحب منطقة الرقم', 'Drag the ID box'),
      };
}

class BubbleTap {
  const BubbleTap(this.mode, this.x, this.y);
  final BubbleTapMode mode;
  final double x, y;
  Map<String, dynamic> toJson() => {
        'action': mode.wire,
        'x': double.parse(x.toStringAsFixed(4)),
        'y': double.parse(y.toStringAsFixed(4)),
        if (mode == BubbleTapMode.setIdentifier) 'role': 'identifier',
        if (mode == BubbleTapMode.setVersion) 'role': 'version',
      };
}

// ── a run: the key ────────────────────────────────────────────────────────────────────────────────────────────────

class BubbleKeyQuestion {
  BubbleKeyQuestion({required this.n, required this.questionId, required this.options, required this.points, required this.multiAll, required this.voided});
  final int n, questionId;
  final List<String> options;
  double points;

  /// Mode "all" (shade exactly these): false = any one listed choice earns the mark.
  bool multiAll;
  bool voided;

  factory BubbleKeyQuestion.fromJson(Map<String, dynamic> m) => BubbleKeyQuestion(
        n: asInt(m['n']),
        questionId: asInt(m['question_id']),
        options: [for (final o in (m['options'] is List ? m['options'] as List : const [])) '$o'],
        points: (m['points'] as num?)?.toDouble() ?? 1,
        multiAll: m['mode'] == 'all',
        voided: m['voided'] == true,
      );
}

class BubbleRun {
  BubbleRun({
    required this.id,
    required this.title,
    required this.courseId,
    required this.orgId,
    required this.sheetName,
    required this.ownSheet,
    required this.questions,
    required this.forms,
    required this.hasKey,
    required this.pages,
    required this.openItems,
    required this.learned,
  });

  final int id;
  final String title;
  final int? courseId, orgId;
  final String sheetName;
  final bool ownSheet;
  final List<BubbleKeyQuestion> questions;
  final List<BubbleKeyForm> forms;
  final bool hasKey;
  final int pages, openItems, learned;

  factory BubbleRun.fromJson(Map<String, dynamic> j) {
    final s = asMap(j['sheet']);
    final k = asMap(j['key']);
    return BubbleRun(
      id: asInt(j['id']),
      title: '${j['title'] ?? ''}',
      courseId: j['course_id'] is int ? j['course_id'] as int : null,
      orgId: j['org_id'] is int ? j['org_id'] as int : null,
      sheetName: '${s['name'] ?? ''}',
      ownSheet: s['kind'] == 'auto_bubble',
      learned: asInt(s['learned']),
      questions: [for (final q in (k['questions'] is List ? k['questions'] as List : const [])) if (q is Map<String, dynamic>) BubbleKeyQuestion.fromJson(q)],
      forms: [for (final f in (k['forms'] is List ? k['forms'] as List : const [])) if (f is Map<String, dynamic>) BubbleKeyForm.fromJson(f)],
      hasKey: j['has_key'] == true,
      pages: asInt(j['pages']),
      openItems: asInt(j['open_items']),
    );
  }
}

class BubbleKeyForm {
  BubbleKeyForm({required this.code, this.label, Map<int, List<String>>? key}) : key = key ?? {};
  String code;
  String? label;
  final Map<int, List<String>> key;

  factory BubbleKeyForm.fromJson(Map<String, dynamic> m) {
    final raw = asMap(m['key']);
    final key = <int, List<String>>{};
    for (final e in raw.entries) {
      final n = int.tryParse(e.key);
      if (n == null) continue;
      key[n] = [for (final v in (e.value is List ? e.value as List : [e.value])) '$v'];
    }
    return BubbleKeyForm(code: '${m['code'] ?? 'A'}', label: m['label'] as String?, key: key);
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        if (label != null) 'label': label,
        'key': {for (final e in key.entries) '${e.key}': e.value},
      };
}

/// A sheet marked with the correct answers, read for the teacher to check (nothing is saved).
class BubbleKeyProposal {
  BubbleKeyProposal({required this.ok, required this.items, required this.issues, required this.clear});
  final bool ok;
  final List<({int n, List<String> letters, bool clear, String state})> items;
  final List<BubbleIssue> issues;
  final int clear;

  factory BubbleKeyProposal.fromJson(Map<String, dynamic> j) => BubbleKeyProposal(
        ok: j['ok'] == true,
        issues: bubbleIssues(j['issues']),
        clear: asInt(j['clear']),
        items: [
          for (final it in (j['items'] is List ? j['items'] as List : const []))
            if (it is Map<String, dynamic>)
              (
                n: asInt(it['n']),
                letters: [for (final l in (it['letters'] is List ? it['letters'] as List : const [])) '$l'],
                clear: it['ok'] == true,
                state: '${it['state'] ?? ''}',
              )
        ],
      );
}

// ── Data Lab ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// What the model answer gave when a correction starts from it (D-671): how many questions it marks, how many the sheet
/// prints, how many got a key, and the rows the teacher should check (two marks, a faint one, none).
class BubbleKeyRead {
  BubbleKeyRead({required this.questions, required this.printed, required this.keyed, required this.check});

  final int questions, printed, keyed;
  final List<BubbleKeyCheck> check;

  factory BubbleKeyRead.fromJson(Map<String, dynamic> j) => BubbleKeyRead(
        questions: asInt(j['questions']),
        printed: asInt(j['printed']),
        keyed: asInt(j['keyed']),
        check: [for (final x in (j['check'] is List ? j['check'] as List : const [])) if (x is Map<String, dynamic>) BubbleKeyCheck.fromJson(x)],
      );
}

class BubbleKeyCheck {
  BubbleKeyCheck({required this.n, required this.state, required this.letters});

  final int n;
  final String state;
  final List<String> letters;

  factory BubbleKeyCheck.fromJson(Map<String, dynamic> j) => BubbleKeyCheck(
        n: asInt(j['n']),
        state: '${j['state'] ?? ''}',
        letters: [for (final x in (j['letters'] is List ? j['letters'] as List : const [])) '$x'],
      );
}

class LabColumn {
  const LabColumn({required this.key, required this.label, this.maxValue, this.locked = false});
  final String key, label;
  final double? maxValue;
  final bool locked;

  factory LabColumn.fromJson(Map<String, dynamic> m) => LabColumn(
        key: '${m['key'] ?? ''}',
        label: '${m['label'] ?? m['key'] ?? ''}',
        maxValue: (m['max_value'] as num?)?.toDouble(),
        locked: m['is_locked'] == true || m['editable'] == false,
      );
}

class LabRow {
  LabRow({required this.studentId, required this.name, required this.score, required this.maxScore, required this.oldValue, required this.newValue, required this.changed, required this.overwrites, required this.blocked, required this.pageId});
  final int studentId;
  final String? name;
  final double? score, maxScore, oldValue, newValue;
  final bool changed, overwrites;
  final String? blocked;
  final int? pageId;

  factory LabRow.fromJson(Map<String, dynamic> m) => LabRow(
        studentId: asInt(m['student_id']),
        name: m['name'] as String?,
        score: (m['score'] as num?)?.toDouble(),
        maxScore: (m['max_score'] as num?)?.toDouble(),
        oldValue: (m['old'] as num?)?.toDouble(),
        newValue: (m['new'] as num?)?.toDouble(),
        changed: m['changed'] == true,
        overwrites: m['overwrites'] == true,
        blocked: m['blocked'] as String?,
        pageId: m['scan_page_id'] is int ? m['scan_page_id'] as int : null,
      );
}

class LabPreview {
  LabPreview({required this.columnKey, required this.columnLabel, required this.columnMax, required this.rows, required this.changes, required this.overwrites, required this.blocked});
  final String columnKey, columnLabel;
  final double columnMax;
  final List<LabRow> rows;
  final int changes, overwrites, blocked;

  factory LabPreview.fromJson(Map<String, dynamic> j) {
    final col = asMap(j['column']);
    final s = asMap(j['summary']);
    return LabPreview(
      columnKey: '${col['key'] ?? ''}',
      columnLabel: '${col['label'] ?? ''}',
      columnMax: (col['max_value'] as num?)?.toDouble() ?? 0,
      changes: asInt(s['changes']),
      overwrites: asInt(s['overwrites']),
      blocked: asInt(s['blocked']),
      rows: [for (final r in (j['rows'] is List ? j['rows'] as List : const [])) if (r is Map<String, dynamic>) LabRow.fromJson(r)],
    );
  }

  /// `expect` for the write: the old value each student was shown.
  Map<String, double?> get expect => {for (final r in rows) '${r.studentId}': r.oldValue};
}

/// A score, tidy: no trailing ".0" (never localised digits).
String bubbleNumText(num? v) {
  if (v == null) return '—';
  final d = v.toDouble();
  return d == d.roundToDouble() ? '${d.toInt()}' : d.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

/// The server's code in the app's language.
String bubbleErrorText(EngineResult r) {
  switch (r.code) {
    case 'feature_disabled':
      return t('هذه الميزة متوقفة حاليًا من إدارة المنصة.', 'This feature is switched off by the platform admin.');
    case 'step_order':
      return t('أكمل الخطوات بالترتيب.', 'Please finish the steps in order.');
    case 'note_not_understood':
      return t('لم نفهم الملاحظة. جرّب: «50 سؤال، 4 اختيارات» أو انقر مكان المشكلة على الورقة.', 'We couldn\'t understand this note. Try "50 questions, 4 choices", or tap the problem on the sheet.');
    case 'column_locked':
      return t('هذا العمود مقفل في Data Lab.', 'This column is locked in the Data Lab.');
    case 'column_not_found':
      return t('هذا العمود لم يعد موجودًا.', 'This column no longer exists.');
    case 'overwrite_confirmation_required':
      return t('بعض الدرجات موجودة بالفعل، أكّد الكتابة فوقها.', 'Some marks already exist. Confirm before overwriting them.');
    case 'server_busy':
      return t('الخادم مشغول، حاول بعد لحظات.', 'The server is busy. Try again in a moment.');
  }
  final en = r.detail['message_en'];
  if (en != null && AppConfig.lang == 'en') return '$en';
  return r.message.isNotEmpty && r.message != 'Not Found' ? r.message : t('تعذّر ذلك، أعد المحاولة.', "That didn't work. Try again.");
}

// ── API ──────────────────────────────────────────────────────────────────────────────────────────────────────────

class BubbleApi {
  BubbleApi([ApiClient? api]) : _api = api ?? ApiClient();
  final ApiClient _api;
  static const _b = '/api/v1/exam';

  Future<EngineResult> createImport({int? orgId, String? name}) =>
      engineCall(() => _api.post('$_b/omr/sheet-imports', body: {'org_id': ?orgId, 'name': ?name}));
  Future<EngineResult> getImport(int id) => engineCall(() => _api.get('$_b/omr/sheet-imports/$id'));
  Future<EngineResult> drafts({int? orgId}) => engineCall(() => _api.get('$_b/omr/sheet-imports', queryParams: orgId == null ? null : {'org_id': orgId}));
  Future<EngineResult> deleteImport(int id) => engineCall(() => _api.delete('$_b/omr/sheet-imports/$id'));
  Future<EngineResult> sendStep(int id, BubbleStep step, (String, Uint8List) file) =>
      engineCall(() => _api.postFiles('$_b/omr/sheet-imports/$id/steps/${step.wire}', files: [file], field: 'image'));
  /// D-500: one picture of the sheet, detected at once.
  Future<EngineResult> sendSheet(int id, (String, Uint8List) file) => engineCall(() => _api.postFiles('$_b/omr/sheet-imports/$id/sheet', files: [file], field: 'image'));

  /// A one-tap fix on the result: `set` (rotate, direction, id_box, block_options) and / or taps.
  Future<EngineResult> quickFix(int id, {List<BubbleTap> taps = const [], Map<String, dynamic>? set}) =>
      engineCall(() => _api.post('$_b/omr/sheet-imports/$id/feedback', body: {'taps': [for (final x in taps) x.toJson()], if (set != null) 'set': set}));
  Future<EngineResult> detect(int id) => engineCall(() => _api.post('$_b/omr/sheet-imports/$id/detect'));
  Future<EngineResult> feedback(int id, {List<BubbleTap> taps = const [], String? note, String? shape}) => engineCall(() => _api.post('$_b/omr/sheet-imports/$id/feedback', body: {
        if (taps.isNotEmpty) 'taps': [for (final x in taps) x.toJson()],
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        if (shape != null) 'set': {'shape': shape},
      }));
  Future<EngineResult> undo(int id) => engineCall(() => _api.post('$_b/omr/sheet-imports/$id/undo'));
  Future<EngineResult> confirm(int id, String name) => engineCall(() => _api.post('$_b/omr/sheet-imports/$id/confirm', body: {'name': name}));
  Future<Uint8List?> sheetImage(int id, String name) async {
    try {
      return await _api.getBytes('$_b/omr/sheet-imports/$id/image/$name');
    } catch (_) {
      return null;
    }
  }

  Future<EngineResult> createRun({required int courseId, required int templateId, required String title, int? questions}) =>
      engineCall(() => _api.post('$_b/bubble/runs', body: {'course_id': courseId, 'template_id': templateId, 'title': title, 'questions': ?questions}));
  /// A correction from the model answer alone: the sheet, the number of questions and the key are read off it (D-671).
  Future<EngineResult> createRunFromKey({required int courseId, required String title, required (String, Uint8List) file}) =>
      engineCall(() => _api.postFiles('$_b/bubble/runs/from-key', files: [file], field: 'image', fields: {'course_id': courseId, 'title': title}));
  Future<EngineResult> run(int id) => engineCall(() => _api.get('$_b/bubble/runs/$id'));
  Future<EngineResult> putKey(int id, {required List<BubbleKeyForm> forms, Map<int, double>? points, Map<int, bool>? allModes}) =>
      engineCall(() => _api.put('$_b/bubble/runs/$id/key', body: {
            'forms': [for (final f in forms) f.toJson()],
            if (points != null && points.isNotEmpty) 'points': {for (final e in points.entries) '${e.key}': e.value},
            if (allModes != null && allModes.isNotEmpty) 'modes': {for (final e in allModes.entries) '${e.key}': e.value ? 'all' : 'any'},
          }));
  Future<EngineResult> keySheet(int id, (String, Uint8List) file) => engineCall(() => _api.postFiles('$_b/bubble/runs/$id/key/sheet', files: [file], field: 'image'));
  Future<EngineResult> voidQuestion(int examId, int questionId, String reason) => engineCall(() => _api.post('$_b/exams/$examId/questions/$questionId/void', body: {'reason': reason, 'mode': 'remove'}));
  Future<EngineResult> restoreQuestion(int examId, int questionId, String reason) =>
      engineCall(() => _api.post('$_b/exams/$examId/questions/$questionId/void/restore', body: {'reason': reason}));

  Future<EngineResult> labColumns(int id) => engineCall(() => _api.get('$_b/bubble/runs/$id/datalab/columns'));
  Future<EngineResult> labPreview(int id, String columnKey) => engineCall(() => _api.post('$_b/bubble/runs/$id/datalab/preview', body: {'column_key': columnKey}));
  Future<EngineResult> labApply(int id, String columnKey, Map<String, double?> expect, {bool confirmOverwrite = false}) =>
      engineCall(() => _api.post('$_b/bubble/runs/$id/datalab/apply', body: {'column_key': columnKey, 'expect': expect, 'confirm_overwrite': confirmOverwrite}));
  Future<EngineResult> templates({int? orgId}) => engineCall(() => _api.get('$_b/omr/templates', queryParams: orgId == null ? null : {'org_id': orgId}));
}
