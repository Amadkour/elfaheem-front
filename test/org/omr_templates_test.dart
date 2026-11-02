// Bubble-sheet types (D-155), the pure part, against REAL engine replies (test/fixtures/payloads/omr_templates/,
// `_source` says the route, the status and how each was recorded — back tests/exam_engine/e2e_omr_templates.py and
// the same fixture's set-up): the mm ↔ preview-pixel mapping (spec.py millimetres, the canonical preview at ppm px / mm,
// OpenCV's pixel-centre convention), drags and resizes in mm, the step-through reply, the library rows grouped by
// family, the shading description, and the server codes as text.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/painting.dart' show MatrixUtils, Offset, Size;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/shared/exam_engine/exam_engine_api.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/templates/omr_templates.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/fixtures/payloads/omr_templates';

Map<String, dynamic> _fx(String name) => Map<String, dynamic>.from(jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map);
Map<String, dynamic> _p(String name) => Map<String, dynamic>.from(_fx(name)['payload'] as Map);

/// width × height of a PNG (IHDR).
(int, int) _pngSize(Uint8List b) => (ByteData.sublistView(b).getUint32(16), ByteData.sublistView(b).getUint32(20));

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('SheetGeometry (mm ↔ preview px)', () {
    const g = SheetGeometry(ppm: 4, width: 840, height: 1188);

    test('a point maps to mm × ppm + ½ px and back exactly', () {
      expect(g.toPreview(0, 0), const Offset(0.5, 0.5));
      expect(g.toPreview(49.496, 103.99).dx, closeTo(198.484, 1e-9));
      for (final p in const [Offset(0, 0), Offset(12.5, 7.25), Offset(209.999, 296.999), Offset(105, 148.5)]) {
        final back = g.toMm(g.toPreview(p.dx, p.dy));
        expect(back.dx, closeTo(p.dx, 1e-12));
        expect(back.dy, closeTo(p.dy, 1e-12));
      }
      expect(g.lenToPreview(2.356), closeTo(9.424, 1e-12));
      expect(g.lenToMm(g.lenToPreview(2.356)), closeTo(2.356, 1e-12));
      expect(g.pageWmm, 210);
      expect(g.pageHmm, 297);
    });

    test("every learned bubble lands on the server's own px (its pixel index) + ½ px", () {
      final s = TemplateSteps.fromJson(_p('e2e_steps_done'));
      final raw = (_p('e2e_steps_done')['questions'] as List).cast<Map>();
      final geo = s.preview.geometry!;
      expect((geo.width, geo.height, geo.ppm), (840.0, 1188.0, 4.0));
      var n = 0;
      for (final q in raw) {
        for (final b in (q['bubbles'] as List).cast<Map>()) {
          final c = geo.toPreview((b['cx'] as num).toDouble(), (b['cy'] as num).toDouble());
          final px = b['px'] as Map;
          expect(c.dx - SheetGeometry.pixelCentre, closeTo((px['cx'] as num).toDouble(), 0.051)); // the server rounds px to 0.1
          expect(c.dy - SheetGeometry.pixelCentre, closeTo((px['cy'] as num).toDouble(), 0.051));
          expect(geo.lenToPreview((b['r'] as num).toDouble()), closeTo((px['r'] as num).toDouble(), 0.051));
          n++;
        }
      }
      expect(n, 200); // 50 questions × 4 options
    });

    test('the recorded previews are exactly w × h of the steps reply', () {
      final s = TemplateSteps.fromJson(_p('e2e_steps_done'));
      for (final f in ['blank_preview.png', 'filled_preview.png']) {
        expect(_pngSize(File('$_dir/$f').readAsBytesSync()), (s.preview.w, s.preview.h));
      }
    });

    test('a drag moves by Δpx / ppm mm, kept on the page; a resize follows the pointer within 0.5 – 10 mm', () {
      const b = OmrBubble(label: 'B', cx: 57, cy: 103.979, r: 2.356);
      final m = g.moved(b, const Offset(6, -2));
      expect(m.cx, closeTo(58.5, 1e-12));
      expect(m.cy, closeTo(103.479, 1e-12));
      expect(m.r, b.r);
      expect(g.moved(b, const Offset(-10000, 10000)).cx, 0);
      expect(g.moved(b, const Offset(-10000, 10000)).cy, 297);
      final all = g.movedAll(const [b, OmrBubble(label: 'C', cx: 64.5, cy: 103.979, r: 2.356)], const Offset(4, 0));
      expect([for (final x in all) x.cx], [closeTo(58, 1e-12), closeTo(65.5, 1e-12)]);
      // the pointer 3 mm right of the centre → r = 3 mm
      final p = g.centreOf(b) + Offset(g.lenToPreview(3), 0);
      expect(g.resizedTo(b, p).r, closeTo(3, 1e-9));
      expect(g.resizedTo(b, g.centreOf(b)).r, kBubbleMinR);
      expect(g.resizedTo(b, g.centreOf(b) + const Offset(400, 0)).r, kBubbleMaxR);
      expect(nudged(b, 0.1, -1, g).cx, closeTo(57.1, 1e-12));
      expect(nudged(b, 0.1, -1, g).cy, closeTo(102.979, 1e-12));
    });

    test('PUT …/boxes gets mm rounded like the server stores them, same labels', () {
      const b = OmrBubble(label: 'A', cx: 49.49612345, cy: 103.98999, r: 2.3564);
      expect(b.toJson(), {'label': 'A', 'cx': 49.496, 'cy': 103.99, 'r': 2.356});
      expect(sameBubbles(const [b], [b.copyWith(cx: 49.4962)]), isTrue);
      expect(sameBubbles(const [b], [b.copyWith(cx: 49.5)]), isFalse);
    });

    test('focus centres the step and never zooms out past the page', () {
      final rect = g.unionRect(const [OmrBubble(label: 'A', cx: 49.5, cy: 104, r: 2.4), OmrBubble(label: 'D', cx: 72, cy: 104, r: 2.4)])!;
      const vp = Size(390, 500);
      final m = g.focusOn(rect, vp, fill: 0.72, maxScale: 3.5);
      final s = m.getMaxScaleOnAxis();
      expect(s, greaterThanOrEqualTo(g.fitScale(vp)));
      expect(s, lessThanOrEqualTo(3.5));
      final c = MatrixUtils.transformPoint(m, rect.center);
      expect(c.dx, closeTo(vp.width / 2, 1e-6));
      expect(c.dy, closeTo(vp.height / 2, 1e-6));
      final fit = g.fit(vp);
      expect(fit.getMaxScaleOnAxis(), closeTo(g.fitScale(vp), 1e-12));
    });
  });

  group('GET …/steps (real replies)', () {
    test('learned: summary, every question, the ID zone, the model row (Example 3 wording)', () {
      final j = _p('e2e_steps_done');
      final s = TemplateSteps.fromJson(j);
      expect(s.learningState, 'done');
      expect(s.busy, isFalse);
      expect(s.summary, 'Detected 4 corner marks, 2 answer columns');
      expect(s.questions.length, 50);
      final q1 = s.question(1)!;
      expect(q1.filled, ['D']);
      expect(q1.state, 'clear');
      expect(q1.confirmed, isFalse);
      expect(q1.prompt, 'Question 1: detected 4 bubbles, filled: D. Correct?');
      expect(s.identifier.kind, 'shaded');
      expect(s.identifier.columns.length, 10);
      expect(s.identifier.columns.every((c) => c.length == 10), isTrue);
      expect(s.identifier.read, '2024001234');
      expect(s.identifier.prompt, 'Detected 10 columns × 10 digits. Student ID read from the filled sheet: 2024001234. Correct?');
      expect(s.identifier.zoneMm, isNotNull);
      expect(s.form.forms, ['A', 'B', 'C', 'D']);
      expect(s.form.bubbles.map((b) => b.label), ['A', 'B', 'C', 'D']);
      expect(s.form.readValue, 'A');
      expect(s.warnings.single.code, 'unassigned');
      expect(s.warnings.single.fix, isNotNull);
      expect(s.validation.ok, isFalse);
      expect(s.validation.errors.single.code, 'questions_unconfirmed');
      expect(s.validation.errors.single.numbers.length, 50);
      expect(s.unconfirmed, List.generate(50, (i) => i + 1));
      expect(s.clearUnconfirmed.length, 50);
      final items = stepItems(s);
      expect(items.length, 52);
      expect(items[50], isA<IdentifierItem>());
      expect(items[51], isA<FormRowItem>());
      AppConfig.lang = 'ar';
      expect(q1.prompt, 'السؤال 1: تم اكتشاف 4 فقاعات، المظلّل: D. هل هذا صحيح؟');
      expect(s.identifier.prompt, startsWith('تم اكتشاف 10 أعمدة'));
      expect(s.summary, startsWith('تم اكتشاف 4'));
    });

    test('queued while the job runs; learned from a page with no marks says why and has no preview', () {
      final q = TemplateSteps.fromJson(_p('steps_queued'));
      expect(q.learning, isTrue);
      expect(q.busy, isTrue);
      expect(q.questions, isEmpty);
      final f = TemplateSteps.fromJson(_p('steps_failed'));
      expect(f.learningState, 'done');
      expect(f.preview.available, isFalse);
      expect(f.preview.geometry, isNull);
      expect(f.questions, isEmpty);
      expect(f.identifier.present, isFalse);
      expect([for (final w in f.warnings) w.code], ['marks_missing', 'unassigned', 'questions_short', 'preview_unavailable']);
      expect(f.warnings.first.fix, contains('four corner marks'));
      expect([for (final e in f.validation.errors) e.code], ['marks', 'no_questions', 'question_count', 'id_columns', 'form_markers']);
    });

    test('a corrected box: recalibrating, that question unconfirmed; after the job it is measured again', () {
      final r = TemplateSteps.fromJson(_p('boxes_recalibrating'));
      expect(r.recalibrating, isTrue);
      expect(r.busy, isTrue);
      expect(r.validation.errors.map((e) => e.code), contains('not_calibrated'));
      final after = TemplateSteps.fromJson(_p('steps_after_fix'));
      expect(after.learningState, 'done');
      final req = (_fx('boxes_recalibrating')['_source'] as Map)['request'] as Map;
      final moved = [for (final b in (req['bubbles'] as List).cast<Map>()) OmrBubble.fromJson(Map<String, dynamic>.from(b))];
      expect(sameBubbles(after.question(17)!.bubbles, moved), isTrue);
    });

    test('confirm → the confirmed flags; validate ok; submit refused with the validation', () {
      final one = TemplateSteps.fromJson(_p('confirm_one'));
      expect(one.question(1)!.confirmed, isTrue);
      expect(one.question(2)!.confirmed, isFalse);
      final all = TemplateSteps.fromJson(_p('e2e_confirm_all'));
      expect(all.confirmedCount, 50);
      expect(all.unconfirmed, isEmpty);
      final v = TemplateValidation.fromJson(_p('validate_ok'));
      expect(v.ok, isTrue);
      expect(v.errors, isEmpty);
      final bad = _p('e2e_submit_invalid_409');
      final detail = Map<String, dynamic>.from(bad['detail'] as Map);
      final r = EngineResult.fail(409, '${detail['code']}', '${detail['message']}', detail);
      expect(TemplateValidation.fromJson(r.detail['validation']).errors.single.code, 'questions_unconfirmed');
      expect(omrTemplateErrorText(r), contains('confirm every question'));
    });
  });

  group('library (real replies)', () {
    test('rows carry what the cards draw; families group the versions', () {
      final j = _p('library_super');
      expect(j['require_approval'], isTrue);
      final rows = [for (final m in (j['items'] as List).cast<Map>()) OmrTemplateRow.fromJson(Map<String, dynamic>.from(m))];
      for (final m in (j['items'] as List).cast<Map>()) {
        for (final k in const ['id', 'family_id', 'version', 'name', 'status', 'owner_id', 'owner_role', 'questions', 'options', 'option_labels', 'id_kind', 'id_digits',
          'forms_on_sheet', 'builtin', 'printable', 'name_en', 'name_ar', 'learning_state', 'preview_url', 'validation_ok', 'review_note', 'approved_at', 'created_at']) {
          expect(m.containsKey(k), isTrue, reason: 'library row lacks "$k"');
        }
      }
      expect(rows.map((r) => r.status).toSet(), {'published', 'draft', 'pending_approval', 'rejected'});
      final b50 = rows.firstWhere((r) => r.builtin == 'mcq50_4' && r.idKind == 'shaded');
      expect(b50.shape, '50 questions × 4 options (A–D)');
      expect(b50.idLine, 'Shaded student ID · 10 digits');
      expect(b50.printable, isTrue);
      expect(b50.previewUrl, '/api/v1/exam/omr/templates/${b50.id}/image?kind=preview');
      AppConfig.lang = 'ar';
      expect(b50.displayName, startsWith('50 سؤالًا'));
      AppConfig.lang = 'en';
      final fams = groupFamilies(rows);
      expect(fams.first.hasPending, isTrue, reason: 'a family waiting for approval comes first');
      final ministry = fams.firstWhere((f) => f.current.name == 'Ministry sheet 50');
      expect([for (final v in ministry.versions) (v.version, v.status)], [(2, 'draft'), (1, 'published')]);
      expect(ministry.current.version, 1);
      expect(ministry.topVersion, 2);
      final rejected = rows.firstWhere((r) => r.status == 'rejected');
      expect(rejected.reviewNote, 'The corner marks are too close to the edge');
      expect(rejected.editable, isTrue);
      expect(libraryFilterMatches(LibraryFilter.pending, fams.first), isTrue);
      expect(fams.where((f) => libraryFilterMatches(LibraryFilter.rejected, f)).length, 1);
    });

    test('learn → the draft row; versions → n + 1 as a draft; submit → pending / published', () {
      final d = OmrTemplateRow.fromJson(_p('learn_super_202'));
      expect((d.status, d.learningState, d.version), ('draft', 'queued', 1));
      expect(d.learning, isTrue);
      final v2 = OmrTemplateRow.fromJson(_p('versions_201'));
      expect((v2.version, v2.status, v2.familyId), (2, 'draft', d.familyId));
      expect(OmrTemplateRow.fromJson(_p('submit_teacher_pending')).status, 'pending_approval');
      expect(OmrTemplateRow.fromJson(_p('submit_super_published')).status, 'published');
      expect(OmrTemplateRow.fromJson(_p('e2e_publish')).approvedAt, isNotNull);
      expect(OmrTemplateRow.fromJson(_p('reject_ok')).reviewNote, 'The corner marks are too close to the edge');
    });
  });

  group('shading description', () {
    test('only keys the server accepts; ranges said the way a person fixes them', () {
      const serverKeys = {'questions', 'options', 'per_column', 'layout', 'direction', 'option_direction', 'id_columns', 'id_kind', 'forms',
        'one_choice_per_question', 'page_mm', 'labels'};
      const h = LearnHints(questions: 50, options: 4, perColumn: 25, idKind: 'shaded', idColumns: 10, forms: 'abcd');
      expect(h.problem(), isNull);
      expect(h.toJson(), {'questions': 50, 'options': 4, 'per_column': 25, 'layout': 'columns', 'one_choice_per_question': true, 'id_kind': 'shaded', 'id_columns': 10, 'forms': 'ABCD'});
      expect(serverKeys.containsAll(h.toJson().keys), isTrue);
      // the e2e's own hints are what this form produces
      final sent = (_fx('e2e_learn_202')['_source'] as Map)['request'] as Map;
      expect(jsonDecode('${sent['hints']}'), {'questions': 50, 'options': 4, 'per_column': 25, 'layout': 'columns', 'id_columns': 10, 'id_kind': 'shaded', 'forms': 'ABCD', 'one_choice_per_question': true});
      expect(const LearnHints(options: 4).problem(), contains('number of questions'));
      expect(const LearnHints(questions: 301, options: 4).problem(), contains('between 1 and 300'));
      expect(const LearnHints(questions: 50, options: 9).problem(), contains('between 2 and 8'));
      expect(const LearnHints(questions: 50, options: 4, idKind: 'shaded').problem(), contains('student ID columns'));
      expect(const LearnHints(questions: 50, options: 4, idKind: 'qr').problem(), isNull);
      expect(const LearnHints(questions: 50, options: 4, idKind: 'qr', idColumns: 10).toJson().containsKey('id_columns'), isFalse);
      expect(const LearnHints(questions: 50, options: 4, idKind: 'none', forms: 'AAB').problem(), contains('each once'));
      expect(learnFileAccepted('Scan 1.JPG'), isTrue);
      expect(learnFileAccepted('sheet.pdf'), isTrue);
      expect(learnFileAccepted('notes.txt'), isFalse);
    });
  });

  group('server codes → text (real refusals)', () {
    EngineResult fail(String name) {
      final f = _fx(name);
      final d = Map<String, dynamic>.from((f['payload'] as Map)['detail'] as Map);
      return EngineResult.fail((f['_source'] as Map)['status'] as int, '${d['code']}', '${d['message']}', d);
    }

    test('every recorded refusal has a sentence in both languages', () {
      for (final (name, en) in const [
        ('e2e_learn_hints_unknown_422', 'The sheet description is not valid'),
        ('e2e_learn_unsupported_415', 'Upload a PNG, JPEG or WebP image or a PDF'),
        ('learn_hints_required', 'student ID columns'),
        ('e2e_boxes_bubble_labels_422', 'bubble letters must stay the same'),
        ('e2e_not_editable_409', 'create a new version'),
        ('reject_reason_required', 'reason for rejecting'),
        ('e2e_reject_422', 'reason for rejecting'),
      ]) {
        AppConfig.lang = 'en';
        expect(omrTemplateErrorText(fail(name)), contains(en), reason: name);
        AppConfig.lang = 'ar';
        expect(omrTemplateErrorText(fail(name)), isNot(contains(en)), reason: '$name in Arabic');
      }
    });

    test('every validation / warning code the engine sends that needs one has a fix', () {
      for (final c in const ['marks', 'marks_missing', 'no_questions', 'question_count', 'questions_short', 'overlap', 'spacing', 'id_columns', 'form_markers',
        'preview_unavailable', 'not_calibrated', 'questions_unconfirmed', 'sample_question', 'unassigned']) {
        expect(omrIssueFix(c), isNotNull, reason: c);
      }
    });
  });
}
