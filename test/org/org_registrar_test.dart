// Registrar: the cart (co-requisites travel together), load after the cart, and the record view's layout.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/org_registrar.dart';
import 'package:flutter_education_app/features/org/org_registrar_member.dart' show RecordView, weekByDay;
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

  test('week grouped by day in week order, sorted by time', () {
    final w = weekByDay([
      {'day': 'monday', 'start': '10:00'}, {'day': 'saturday', 'start': '12:00'}, {'day': 'monday', 'start': '08:00'},
    ]);
    expect(w.map((e) => e.$1).toList(), ['saturday', 'monday']);
    expect(w[1].$2.map((e) => e['start']).toList(), ['08:00', '10:00']);
  });

  test('load after the cart', () {
    final l = loadAfter(12, 9, {'min': 12, 'max': 18});
    expect((l.load, l.over, l.under), (21.0, true, false));
    expect(loadAfter(3, 3, {'min': 12, 'max': 18}).under, true);
  });

  test('queue-first helpers: status text, result lines, idempotency keys', () {
    AppConfig.lang = 'en';
    expect(regRequestDone('done'), isTrue);
    expect(regRequestDone('queued'), isFalse);
    expect(regQueueText('queued', depth: 5), contains('4'));
    expect(regQueueText('processing'), isNot(''));
    String name(int id) => 'C$id';
    final cart = regResultLines({'ok': true, 'results': {'7': {'status': 'registered'}, '8': {'status': 'rejected', 'blocks': [{'code': 'section_full', 'message': 'full'}]}}}, name);
    expect(cart.length, 2);
    expect(cart.first, startsWith('C7:'));
    final single = regResultLines({'status': 'waitlisted', 'registration': {'course_id': 9}}, name);
    expect(single, ['C9: ${regStatusText('waitlisted')}']);
    expect(regResultLines({}, name), isEmpty);
    expect(newIdempotencyKey(), isNot(newIdempotencyKey()));
    expect(regPollAfterMs(null), 1500);
    expect(regQueueBusy(null, 503), isTrue);
    expect(regQueueBusy('too_many_attempts', 429), isTrue);
    expect(regQueueBusy('window_closed', 409), isFalse);
    expect(regQueueBusy(null, 0), isTrue);
    expect(regPollAfterMs(0), 1500);
    expect(regPollAfterMs(2500), 2500);
    expect(regPollAfterMs(200), 1000);
    expect(regPollAfterMs(60000), 10000);
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
