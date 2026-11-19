// "Your application" on the personal homes (D-1210): parsing of /me/home's `onboarding[]` and the card's layout.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/home/me_home.dart';
import 'package:flutter_education_app/features/home/home_application_card.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

Map<String, dynamic> _row(int id, {String status = 'draft', bool action = false, int missing = 0, String? due}) => {
      'case_id': id,
      'org_id': 4,
      'org_name': 'جامعة المنصورة الأهلية للعلوم والتكنولوجيا',
      'org_logo': '',
      'type_key': 'student_new',
      'type_label_ar': 'طالب مستجد',
      'type_label_en': 'New student',
      'status': status,
      'conditional': false,
      'missing_count': missing,
      'due_at': due,
      'needs_action': action,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('MeHome.fromJson reads onboarding[] and tolerates its absence', () {
    final h = MeHome.fromJson({
      'onboarding': [_row(1, status: 'needs_correction', action: true, missing: 2, due: '2026-12-01T10:00:00'), 'junk', {'case_id': 0}],
    });
    expect(h.onboarding.length, 1);
    expect(h.onboarding.first.caseId, 1);
    expect(h.onboarding.first.missingCount, 2);
    expect(h.onboarding.first.needsAction, isTrue);
    expect(h.onboarding.first.dueAt, isNotNull);
    expect(h.onboarding.first.typeLabel, 'New student');
    expect(MeHome.fromJson(const {}).onboarding, isEmpty);
    expect(homeApplicationNeedsAction(h.onboarding), isTrue);
  });

  testWidgets('the card: no layout error on any size', (tester) async {
    final items = [
      for (final r in [_row(1, status: 'needs_correction', action: true, missing: 3, due: '2026-12-01T10:00:00'), _row(2, status: 'submitted')])
        MeOnboardingItem.fromJson(r)!,
    ];
    await expectNoLayoutErrors(tester, () => HomeApplicationCard(items: items, onOpen: (_) {}));
    await expectNoLayoutErrors(tester, () => const HomeApplicationCard(items: []));
  });
}
