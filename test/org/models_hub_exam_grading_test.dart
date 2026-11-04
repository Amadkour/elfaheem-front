import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/models_hub/models_hub_api.dart';
import 'package:flutter_education_app/features/admin/models/models_hub_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('exam_grading role has names and a hint in both languages', () {
    expect(hubRoleName('exam_grading'), 'Exam grading');
    expect(hubRoleHint('exam_grading'), isNotEmpty);
    AppConfig.lang = 'ar';
    expect(hubRoleName('exam_grading'), 'تصحيح الاختبارات');
  });

  test('tasks are parsed and shown as a line', () {
    final ov = HubOverview.fromJson({
      'roles': [],
      'tasks': [
        {'task': 'exam_grading', 'roles': ['exam_grading', 'nli', 'embedding']},
      ],
    });
    expect(ov.task('exam_grading')!.roles, ['exam_grading', 'nli', 'embedding']);
    expect(hubTaskLine(ov.task('exam_grading')), 'Exam grading uses: Exam grading, NLI, Embedding');
  });

  test('an older server without tasks still works', () {
    final ov = HubOverview.fromJson({'roles': []});
    expect(ov.tasks, isEmpty);
    expect(ov.task('exam_grading'), isNull);
    expect(hubTaskLine(ov.task('exam_grading')), isNull);
  });
}
