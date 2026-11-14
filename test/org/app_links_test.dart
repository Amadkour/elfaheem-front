// The one link scheme (D-307): lib/core/share/app_links.dart, the meeting links payload and filters
// (lib/features/live/meeting_links.dart).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/routing/app_routes.dart';
import 'package:flutter_education_app/core/share/app_links.dart';
import 'package:flutter_education_app/features/live/meeting_links.dart';
import 'package:flutter_education_app/features/share/share_link_page.dart' show sharePageAllowed;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('AppLink', () {
    test('builds the root-form links', () {
      expect(const AppLink.course(12, ref: 5).url(), 'https://alfheemacademy.com/c/12?ref=5');
      expect(const AppLink.course(12).route, '/c/12');
      expect(const AppLink.meeting(7).url(), 'https://alfheemacademy.com/s/meeting/7');
      expect(const AppLink.session(3).route, '/s/session/3');
      expect(const AppLink.material(9).route, '/s/material/9');
      expect(const AppLink.roadmap(4).route, '/s/roadmap/4');
      expect(const AppLink.teacher(2).route, '/s/teacher/2');
      expect(const AppLink.page('calendar').route, '/s/page/calendar');
      expect(const AppLink.page('course', {'courseId': '12'}).route, '/s/page/course?courseId=12');
      expect(const AppLink.meeting(7).url('http://localhost:5000/'), 'http://localhost:5000/s/meeting/7');
    });

    test('parses every form back (route, /app/ path, full URL)', () {
      for (final l in const [
        AppLink.course(12, ref: 5),
        AppLink.course(12),
        AppLink.meeting(7),
        AppLink.session(3),
        AppLink.material(9),
        AppLink.roadmap(4),
        AppLink.teacher(2),
        AppLink.page('calendar'),
        AppLink.page('course', {'courseId': '12'}),
      ]) {
        expect(AppLink.parse(l.route), l, reason: l.route);
        expect(AppLink.parse(l.url()), l, reason: l.url());
        expect(AppLink.parse('/app${l.route}'), l, reason: '/app${l.route}');
      }
      expect(AppLink.parse('/s/course/12?ref=5'), const AppLink.course(12, ref: 5));
    });

    test('refuses what is not a share link', () {
      for (final r in [null, '', '/', '/c/x', '/c/0', '/s/meeting', '/s/meeting/0', '/s/meeting/-1', '/s/user/5',
          '/s/page/Bad Id', '/s/meeting/7/extra', '/@ahmed', '/live/tok', '/calendar']) {
        expect(AppLink.parse(r), isNull, reason: r);
      }
    });

    test('the registry knows the share link and the page; page links never open a home or the sign-in', () {
      expect(AppRoutes.match('/s/meeting/7')?.id, 'link.share');
      expect(AppRoutes.match('/meeting-links')?.id, 'meetings.links');
      expect(sharePageAllowed('calendar'), isTrue);
      expect(sharePageAllowed('meetings.links'), isTrue);
      for (final id in ['home.teacher', 'auth.login', 'link.share', 'nope']) {
        expect(sharePageAllowed(id), isFalse, reason: id);
      }
    });
  });

  group('meeting links', () {
    final payload = {
      'items': [
        {'id': 'meeting:5', 'kind': 'meeting', 'ref_id': 5, 'title': 'Staff sync', 'status': 'live', 'is_host': true,
         'starts_at': '2026-11-08T10:00:00', 'ends_at': '2026-11-08T11:00:00', 'app_link': 'https://alfheemacademy.com/s/meeting/5',
         'org': {'id': 1, 'name_ar': 'جامعة', 'name_en': 'Uni'},
         'guest_link': {'url': 'https://alfheemacademy.com/live/tok', 'has_pin': true, 'guests_joined': 2, 'link_status': 'active'}},
        {'id': 'session:3', 'kind': 'session', 'ref_id': 3, 'title': 'Live 2026-11-09', 'title_auto': true,
         'subtitle': 'Algebra', 'course_id': 12, 'status': 'scheduled', 'recurring': true, 'starts_at': '2026-11-09T08:00:00'},
        {'id': 'meeting:6', 'kind': 'meeting', 'ref_id': 6, 'title': 'Old', 'status': 'ended', 'is_host': true,
         'guest_link': {'url': 'https://alfheemacademy.com/live/old', 'link_status': 'expired'}},
        {'kind': 'other', 'ref_id': 1},
        {'kind': 'meeting', 'ref_id': 0},
      ],
    };

    test('parses the payload (naive UTC, localised auto titles, guest links, unknown rows dropped)', () {
      final d = MeetingLinksData.fromJson(payload);
      expect(d.items.map((i) => i.key).toList(), ['meeting:5', 'session:3', 'meeting:6']);
      final m = d.items[0];
      expect(m.status, MeetingLinkStatus.live);
      expect(m.startsAt, DateTime.utc(2026, 11, 8, 10));
      expect(m.orgName, 'Uni');
      expect(m.guest!.hasPin, isTrue);
      expect(m.guest!.guestsJoined, 2);
      expect(m.guest!.active, isTrue);
      expect(m.link, const AppLink.meeting(5));
      final s = d.items[1];
      expect(s.title, 'Live session');
      expect(s.recurring, isTrue);
      expect(s.courseId, 12);
      expect(s.link, const AppLink.session(3));
      expect(d.items[2].guest!.active, isFalse);
      AppConfig.lang = 'ar';
      expect(MeetingLinksData.fromJson(payload).items[1].title, 'حصة مباشرة');
      expect(MeetingLinksData.fromJson(payload).items[0].orgName, 'جامعة');
    });

    test('filters and search', () {
      final items = MeetingLinksData.fromJson(payload).items;
      List<String> keys(MeetingLinksFilter f, [String q = '']) => [for (final i in filterMeetingLinks(items, f, q)) i.key];
      expect(keys(MeetingLinksFilter.all), ['meeting:5', 'session:3', 'meeting:6']);
      expect(keys(MeetingLinksFilter.live), ['meeting:5']);
      expect(keys(MeetingLinksFilter.upcoming), ['session:3']);
      expect(keys(MeetingLinksFilter.past), ['meeting:6']);
      expect(keys(MeetingLinksFilter.hosting), ['meeting:5', 'meeting:6']);
      expect(keys(MeetingLinksFilter.guestLinks), ['meeting:5', 'meeting:6']);
      expect(keys(MeetingLinksFilter.all, 'algeb'), ['session:3']);
      expect(keys(MeetingLinksFilter.all, 'UNI'), ['meeting:5']);
      expect(keys(MeetingLinksFilter.live, 'algebra'), isEmpty);
    });
  });
}
