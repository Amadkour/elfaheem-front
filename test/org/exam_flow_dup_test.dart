// Duplicate an exam from the Exam Hub (D-665): who gets the action, the reply, the texts.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/exam_all.dart';
import 'package:flutter_education_app/features/exams/exam_engine_api.dart' show EngineResult;
import 'package:flutter_education_app/features/exams/hub/hub_duplicate.dart';
import 'package:flutter_education_app/features/exams/hub/hub_logic.dart';
import 'package:flutter_test/flutter_test.dart';

AllExam _e(int id, {String status = 'published', String? run}) => AllExam({
      'id': id,
      'title': 'Exam $id',
      'status': status,
      'course_id': 10,
      'org_id': null,
      'question_count': 12,
      'attempts': {'total': 3},
      'grading': {'ended': false, 'state': 'waiting', 'has_degrees': false, 'run': ?run},
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('every exam but a grading run or an archived one can be duplicated', () {
    expect(hubCanDuplicate(_e(1)), isTrue);
    expect(hubCanDuplicate(_e(1, status: 'draft')), isTrue);
    expect(hubCanDuplicate(_e(1, status: 'closed')), isTrue);
    expect(hubCanDuplicate(_e(1, status: 'archived')), isFalse);
    expect(hubCanDuplicate(_e(1, run: 'essay')), isFalse);
    expect(hubCanDuplicate(_e(1, run: 'bubble')), isFalse);
  });

  test('the ⋯ menu of every exam offers Duplicate, except a grading run and the archive (D-701)', () {
    expect(hubMenuActions(_e(1)), contains(HubAction.duplicate));
    expect(hubMenuActions(_e(1, status: 'draft')), contains(HubAction.duplicate));
    expect(hubMenuActions(_e(1, status: 'closed')), contains(HubAction.duplicate));
    expect(hubMenuActions(_e(1, run: 'essay')), isNot(contains(HubAction.duplicate)));
    expect(hubMenuActions(_e(1, status: 'archived')), isNot(contains(HubAction.duplicate)));
    expect(hubActionLabel(HubAction.duplicate), 'Duplicate');
    AppConfig.lang = 'ar';
    expect(hubActionLabel(HubAction.duplicate), 'نسخ الاختبار');
  });

  test('the new id comes from the reply; a run refusal reads as such', () {
    expect(duplicatedExamId(EngineResult.ok({'id': 42, 'status': 'draft'})), 42);
    expect(duplicatedExamId(EngineResult.ok({})), isNull);
    final no = EngineResult.fail(409, 'run_not_duplicable', 'x');
    expect(duplicatedExamId(no), isNull);
    expect(duplicateErrorText(no), 'A grading run cannot be duplicated. Start a new run.');
  });
}
