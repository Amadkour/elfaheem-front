// Agent f4: no overflow on any size / language / text scale for the new parent organization widgets.
import 'package:flutter_education_app/features/parent/parent_org_view.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _org = ParentOrgRef(
    id: 9,
    nameAr: 'جامعة النور للعلوم والتكنولوجيا والدراسات العليا',
    nameEn: 'Noor University of Science, Technology and Graduate Studies',
    status: 'pending');

final _view = ParentOrgView.parse({
  'org': {'id': 9, 'name_ar': 'جامعة النور', 'name_en': 'Noor University'},
  'student': {'id': 1, 'name': 'Sara'},
  'today': [
    {
      'title': 'Advanced Algebra and Mathematical Analysis for Engineers',
      'course_name': 'Mathematics',
      'starts_at': '2026-11-04T08:00:00',
      'ends_at': '2026-11-04T09:30:00',
      'room': 'Building B, Hall 12, second floor',
      'mode': 'online',
      'status': 'changed'
    },
    {'title': 'Physics', 'starts_at': '2026-11-04T10:00:00', 'status': 'cancelled'},
  ],
  'week': [
    {'title': 'Chemistry lab', 'course_name': 'Chemistry', 'starts_at': '2026-11-05T10:00:00', 'ends_at': '2026-11-05T11:00:00', 'status': 'scheduled'},
  ],
  'announcements': [
    {
      'id': 3,
      'title': 'A very long announcement title that must wrap and not overflow the card at all',
      'body': List.filled(30, 'Body text').join(' '),
      'published_at': '2026-11-03T10:00:00'
    }
  ],
  'grades': [
    {'course_name': 'Mathematics and Analysis for Engineering Students', 'grade': 'A+', 'points': 3.7, 'term_label': 'Fall 2026', 'published_at': '2026-11-01T10:00:00'}
  ],
  'attendance': {'present': 80, 'absent': 12, 'late': 8},
});

void main() {
  testWidgets('ParentOrgChildrenList', (tester) async {
    await expectNoLayoutErrors(
        tester,
        () => ParentOrgChildrenList(
              children: const [
                ParentChildOrgs(studentId: 1, name: 'Sara with a really long full name that keeps going', orgs: [_org, ParentOrgRef(id: 10, nameEn: 'Second')]),
                ParentChildOrgs(studentId: 2, name: 'Omar', orgs: [_org]),
              ],
              onOpen: (_, _) {},
            ));
  });

  testWidgets('ParentOrgBody full', (tester) async {
    await expectNoLayoutErrors(tester, () => ParentOrgBody(view: _view, childName: 'Sara'));
  });

  testWidgets('ParentOrgBody empty', (tester) async {
    await expectNoLayoutErrors(tester, () => const ParentOrgBody(view: ParentOrgView(org: _org), childName: 'Sara'));
  });
}
