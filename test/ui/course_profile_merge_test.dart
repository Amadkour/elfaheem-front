// D-111: the course profile's parts as tabs of the one course page (CourseSpace) — which tabs each role gets, the
// old tab names mapped, the unread count, and every profile tab drawn at 320x640 / 1400x900, ar / en, textScaler 1.3
// with the profile preloaded (no network).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/shared/course_profile/course_profile_hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'course_profile_test.dart' show payload;
import 'layout_harness.dart';

List<String> _ids(List<CourseSpaceTab> tabs) => [for (final t in tabs) t.id];

List<CourseSpaceTab> _tabs(CourseProfileHub hub, {required bool staff, bool org = true, bool enrolled = true, String? forced}) =>
    courseProfileTabs(hub: hub, staff: staff, org: org, enrolled: enrolled, forced: forced, onOpenTab: (_) {});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('tabs before the profile is loaded follow the page (no request on open)', () {
    final hub = CourseProfileHub(7);
    expect(_ids(_tabs(hub, staff: false)), ['announcements', 'progress']);
    expect(_ids(_tabs(hub, staff: false, enrolled: false)), isEmpty);
    expect(_ids(_tabs(hub, staff: true)), ['announcements', 'class', 'team', 'archive']);
    expect(_ids(_tabs(hub, staff: true, org: false)), ['announcements', 'class']);
    // an old deep link to the archive always finds its tab
    expect(_ids(_tabs(hub, staff: false, enrolled: false, forced: 'archive')), ['archive']);
    expect(hub.profile, isNull);
  });

  test('tabs once the profile is known follow the server caps', () {
    expect(_ids(_tabs(CourseProfileHub(7, initial: payload('student')), staff: false)), ['announcements', 'progress']);
    expect(_ids(_tabs(CourseProfileHub(7, initial: payload('student', closed: true)), staff: false)),
        ['announcements', 'progress', 'archive']);
    expect(_ids(_tabs(CourseProfileHub(7, initial: payload('instructor')), staff: true)),
        ['announcements', 'class', 'team', 'archive']);
    // a TA: its own grant in Team, the course's versions in Archive
    expect(_ids(_tabs(CourseProfileHub(7, initial: payload('ta')), staff: true)), ['announcements', 'class', 'team', 'archive']);
  });

  test('old profile tab names land on the one page', () {
    expect(cpMergedTab('overview', staff: true), isNull);
    expect(cpMergedTab('lecture', staff: false), 'sessions');
    expect(cpMergedTab('attendance', staff: true), 'class');
    expect(cpMergedTab('attendance', staff: false), 'progress');
    expect(cpMergedTab('certificates', staff: false), 'progress');
    expect(cpMergedTab('archive', staff: false), 'archive');
    expect(cpMergedTab('team', staff: true), 'team');
  });

  test('unread announcements, smart landing tab', () async {
    final hub = CourseProfileHub(7, initial: payload('student'));
    expect(hub.unread, 2);
    expect(hub.smartTab(), 'announcements');
    hub.markSeen(hub.profile!.announcements);
    expect(hub.unread, 0);
    expect(hub.smartTab(), isNull);
    expect(CourseProfileHub(7, initial: payload('student', closed: true)).smartTab(), 'archive');
  });

  for (final role in ['student', 'instructor', 'ta']) {
    final staff = role != 'student';
    for (final tab in staff ? ['announcements', 'class', 'team', 'archive'] : ['announcements', 'progress', 'archive']) {
      testWidgets('one page: $role / $tab', (t) async {
        await expectNoLayoutErrors(t, () {
          final hub = CourseProfileHub(7, initial: payload(role, closed: tab == 'archive' && !staff));
          final tabs = _tabs(hub, staff: staff, forced: tab);
          return CourseSpace(
            hero: const CourseSpaceHeroData(title: 'مقدمة في هندسة البرمجيات'),
            spotlight: [CourseArchiveSpot(hub: hub, onOpenTab: (_) {})],
            tabs: [CourseSpaceTab(id: 'sessions', label: 'Sessions', icon: Icons.play_lesson_rounded, builder: (_) => const SizedBox()), ...tabs],
            activeTab: tab,
            onTab: (_) {},
          );
        });
      });
    }
  }
}
