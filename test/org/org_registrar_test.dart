// Registrar: the cart (co-requisites travel together), load after the cart, and the record view's layout.
import 'package:flutter_education_app/features/org/org_registrar.dart';
import 'package:flutter_education_app/features/org/org_registrar_member.dart' show RecordView;
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

void main() {
  test('cart: credits, JSON, missing co-requisites', () {
    final cart = RegCart()..put(1, 3, section: 10)..put(2, 4);
    expect(cart.credits, 7);
    expect(cart.toJson(), [
      {'course_id': 1, 'section_id': 10},
      {'course_id': 2},
    ]);
    final course = {
      'requisites': [
        {'course_id': 5, 'mode': 'coreq'},
        {'course_id': 6, 'mode': 'coreq'},
        {'course_id': 7, 'mode': 'passed'},
      ],
    };
    expect(RegCart.missingCoreqs(course, {1, 2}, {6}), [5]);
    cart.remove(1);
    expect(cart.credits, 4);
  });

  test('load after the cart', () {
    final l = loadAfter(12, 9, {'min': 12, 'max': 18});
    expect((l.load, l.over, l.under), (21.0, true, false));
    expect(loadAfter(3, 3, {'min': 12, 'max': 18}).under, true);
  });

  test('block texts carry the numbers', () {
    final s = blockText({'code': 'max_load', 'load': 15, 'credits': 6, 'limits': {'max': 18}});
    expect(s.contains('15 + 6 > 18'), true);
  });

  testWidgets('record view: long names, probation, audit, transcript', (tester) async {
    final data = {
      'cgpa': 1.87, 'earned': 54, 'standing': 'probation', 'level': '2',
      'program': {'code': 'CS', 'name_ar': 'قسم علوم الحاسب ونظم المعلومات والذكاء الاصطناعي', 'name_en': 'Computer Science, Information Systems and AI'},
      'audit': {
        'eligible': false, 'remaining_credits': 82,
        'groups': [
          {'key': 'university', 'label_ar': 'متطلبات الجامعة', 'label_en': 'University requirements', 'need': 12, 'have': 9, 'done': false, 'missing_required': [4, 5]},
          {'key': 'major', 'label_ar': 'متطلبات التخصص الإجبارية والاختيارية', 'label_en': 'Major requirements', 'need': 90, 'have': 30, 'done': false, 'missing_required': []},
        ],
      },
      'terms': [
        {
          'term': {'kind': 'term1', 'year_label': '2025/2026'},
          'term_gpa': 1.5,
          'courses': [
            {'code': 'CS101', 'name_ar': 'مقدمة في البرمجة الكائنية وهياكل البيانات المتقدمة', 'name_en': 'Introduction to object-oriented programming and advanced data structures', 'credits': 3, 'letter': 'F', 'counted': false, 'status': 'completed'},
            {'code': 'MA102', 'name_ar': 'تفاضل', 'name_en': 'Calculus', 'credits': 3, 'letter': null, 'status': 'withdrawn', 'denied': true},
          ],
        },
      ],
    };
    await expectNoLayoutErrors(tester, () => RecordView(data: data));
  });
}
