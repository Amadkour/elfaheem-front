// D-111: the course profile's parts as tabs of the one course page (CourseSpace) — which tabs each role gets, the
// old tab names mapped, the unread count, and every profile tab drawn at 320x640 / 1400x900, ar / en, textScaler 1.3
// with the profile preloaded (no network).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/course/course_space/course_space.dart';
import 'package:flutter_education_app/features/shared/course_profile/course_profile_hub.dart';
import 'package:flutter_education_app/features/shared/course_profile/course_profile_models.dart' show CoursePageState;
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

  test('course payload state: closed + announcements_unread parsed, absent on an older server', () {
    final s = CoursePageState.fromJson({'id': 7, 'closed': true, 'announcements_unread': 3});
    expect((s.closed, s.unread, s.known), (true, 3, true));
    final old = CoursePageState.fromJson({'id': 7, 'name_en': 'x'});
    expect((old.closed, old.unread, old.known), (null, null, false));
    expect(CoursePageState.fromJson(null).known, isFalse);
    // a guest gets `closed` only; wrong types are ignored, a negative count is 0
    expect(CoursePageState.fromJson({'closed': false}).unread, isNull);
    final odd = CoursePageState.fromJson({'closed': 'yes', 'announcements_unread': '2'});
    expect((odd.closed, odd.unread), (null, null));
    expect(CoursePageState.fromJson({'announcements_unread': -4}).unread, 0);
    expect(CoursePageState.fromJson({'announcements_unread': 2.0}).unread, 2);
  });

  test("the server's count: badge and opening tab on open with no profile, seen told to the server", () {
    final posted = <(int, int)>[];
    final hub = CourseProfileHub(7, postSeen: (c, id) async => posted.add((c, id)));
    expect(hub.openingTab(), isNull); // no payload yet
    final s = const CoursePageState(closed: false, unread: 4);
    hub.seed(s);
    expect(hub.profile, isNull); // nothing else was loaded
    expect(hub.unread, 4);
    expect(hub.closed, isFalse);
    expect(hub.openingTab(), 'announcements');
    expect(_tabs(hub, staff: false).first.count, 4);
    // the tab shows the profile's announcements (ids 1, 2): the server hears the newest, the badge clears
    final withProfile = CourseProfileHub(7, initial: payload('student'), postSeen: (c, id) async => posted.add((c, id)))
      ..seed(s);
    expect(withProfile.unread, 4); // the server's count wins over the device's
    withProfile.markSeen(withProfile.profile!.announcements);
    expect(posted, [(7, 2)]);
    expect(withProfile.unread, 0);
    expect(withProfile.openingTab(), '');
    withProfile.seed(s); // the same payload again changes nothing
    expect(withProfile.unread, 0);
    withProfile.markSeen(withProfile.profile!.announcements); // nothing new: no second request
    expect(posted, [(7, 2)]);
    withProfile.seed(const CoursePageState(closed: false, unread: 1)); // a refresh reads the server again
    expect(withProfile.unread, 1);
    // nothing to read: the page keeps its first tab
    expect((CourseProfileHub(7)..seed(const CoursePageState(closed: false, unread: 0))).openingTab(), '');
  });

  test('a closed course from the payload opens on Archive once the profile tells the archive state', () {
    final hub = CourseProfileHub(7, initial: payload('student', closed: true))
      ..seed(const CoursePageState(closed: true, unread: 0));
    expect(hub.closed, isTrue);
    expect(hub.openingTab(), 'archive');
    final staff = CourseProfileHub(7, initial: payload('instructor'))..seed(const CoursePageState(closed: false, unread: 2));
    expect(staff.openingTab(), 'announcements');
  });

  test('older server: no state → the page keeps its tab, unread counted on the device, nothing posted', () {
    final posted = <(int, int)>[];
    final bare = CourseProfileHub(7, postSeen: (c, id) async => posted.add((c, id)))..seed(CoursePageState.fromJson({}));
    expect(bare.openingTab(), isNull);
    expect(bare.unread, 0);
    expect(bare.closed, isFalse);
    final hub = CourseProfileHub(7, initial: payload('student'), postSeen: (c, id) async => posted.add((c, id)))
      ..seed(CoursePageState.fromJson({'id': 7}));
    expect(hub.serverUnread, isFalse);
    expect(hub.unread, 2);
    expect(hub.smartTab(), 'announcements'); // an old entry point (CoursePageLoader) still lands there
    hub.markSeen(hub.profile!.announcements);
    expect(hub.unread, 0);
    expect(posted, isEmpty);
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
