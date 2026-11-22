// A course's online meetings on the teacher's Sessions tab (D-1720 – D-1726): the two actions (Meet now ·
// Repeating meeting, each hidden by its kill switch), the series card's guest link row (owner + online only), the
// link's wire (the series routes, the same model as a meeting's link) and the guest page between two dates of a
// repeating meeting. Laid out at 320x640 and 1400x900, ar + en, textScaler 1.3.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/courses/course_space/course_series_block.dart';
import 'package:flutter_education_app/features/courses/course_space/course_sessions.dart';
import 'package:flutter_education_app/features/guest/guest_live_api.dart';
import 'package:flutter_education_app/features/guest/guest_live_page.dart';
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

const _url = 'https://alfheemacademy.com/live/3f9a1c2e7b8d4f6a9c0e1b2d3f4a5c6e';

Map<String, dynamic> _series({bool owner = true, String mode = 'online', bool link = true}) => {
      'items': [
        {
          'id': 7,
          'title': 'حلقة الأسئلة الأسبوعية لطلاب المستوى الثاني مع مراجعة شاملة',
          'mode': mode,
          'is_owner': owner,
          'rule': {'freq': 'weekly', 'interval': 1, 'weekdays': [6], 'start_date': '2026-11-22', 'start_time': '10:00', 'end_time': '11:00', 'tz': 'UTC'},
          'upcoming': [
            {'occurrence_date': '2026-11-22', 'starts_at': '2026-11-22T10:00:00', 'ends_at': '2026-11-22T11:00:00', 'cancelled': false},
          ],
          if (owner) 'guest_link': link ? {'url': _url, 'token': 'abc', 'can_publish': true, 'series_id': 7, 'direct': false} : null,
        },
      ],
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('CourseMeetingActions', () {
    testWidgets('both actions; a null callback hides its button; both null draw nothing', (tester) async {
      var now = 0, repeat = 0;
      await tester.pumpWidget(layoutHost(CourseMeetingActions(onMeetNow: () => now++, onRepeating: () => repeat++)));
      await tester.tap(find.byKey(const ValueKey('course_sessions.meet_now')));
      await tester.tap(find.byKey(const ValueKey('course_sessions.repeating_meeting')));
      expect((now, repeat), (1, 1));

      await tester.pumpWidget(layoutHost(CourseMeetingActions(onMeetNow: null, onRepeating: () {})));
      expect(find.byKey(const ValueKey('course_sessions.meet_now')), findsNothing);
      expect(find.byKey(const ValueKey('course_sessions.repeating_meeting')), findsOneWidget);

      await tester.pumpWidget(layoutHost(const CourseMeetingActions(onMeetNow: null, onRepeating: null)));
      expect(find.byKey(const ValueKey('course_sessions.meetings')), findsNothing);
    });

    testWidgets('no layout errors', (tester) async {
      await expectNoLayoutErrors(tester, () => CourseMeetingActions(onMeetNow: () {}, onRepeating: () {}));
      await expectNoLayoutErrors(tester, () => CourseMeetingActions(onMeetNow: () {}, onRepeating: () {}, starting: true));
    });
  });

  group('the series guest link on the course block', () {
    test('guest_link parses into the meeting link model with its series', () {
      final s = CourseSeriesItem.listFrom(_series()).single;
      expect(s.guestLink?.url, _url);
      expect(s.guestLink?.seriesId, 7);
      expect(s.canShareLink, isTrue);
      expect(CourseSeriesItem.listFrom(_series(link: false)).single.guestLink, isNull);
      expect(CourseSeriesItem.listFrom(_series(owner: false)).single.canShareLink, isFalse);
      expect(CourseSeriesItem.listFrom(_series(mode: 'offline')).single.canShareLink, isFalse);
    });

    testWidgets('owner of an online series: Copy guest link + Link options', (tester) async {
      CourseSeriesItem? copied, options;
      Widget block(Map<String, dynamic> a) => layoutHost(SingleChildScrollView(
          child: CourseSeriesBlock(items: CourseSeriesItem.listFrom(a), onCopyLink: (s) => copied = s, onLinkOptions: (s) => options = s)));
      await tester.pumpWidget(block(_series()));
      await tester.tap(find.byKey(const ValueKey('course_series.7.copy_link')));
      await tester.tap(find.byKey(const ValueKey('course_series.7.link_options')));
      expect((copied?.id, options?.id), (7, 7));

      await tester.pumpWidget(block(_series(owner: false))); // a student sees the dates only
      expect(find.byKey(const ValueKey('course_series.7.copy_link')), findsNothing);
      await tester.pumpWidget(block(_series(mode: 'offline'))); // in person: nothing to link to
      expect(find.byKey(const ValueKey('course_series.7.copy_link')), findsNothing);
    });

    testWidgets('no layout errors', (tester) async {
      await expectNoLayoutErrors(
          tester,
          () => SingleChildScrollView(
              child: CourseSeriesBlock(items: CourseSeriesItem.listFrom(_series()), onDate: (_, _) {}, onCopyLink: (_) {}, onLinkOptions: (_) {})));
    });
  });

  group('the share sheet of a series link', () {
    Widget body(LiveLink l) {
      final max = TextEditingController(), pin = TextEditingController();
      return ShareLinkBody(
        loading: false,
        busy: false,
        error: null,
        link: l,
        canPublish: l.canPublish,
        maxGuestsController: max,
        pinController: pin,
        editing: false,
        showQr: false,
        onRetry: () {},
        onCanPublishChanged: (_) {},
        onCreate: () {},
        onCopy: () {},
        onShare: () {},
        onToggleQr: () {},
        onToggleSettings: () {},
        onSaveSettings: () {},
        onRevoke: () {},
      );
    }

    testWidgets('says the link is the same for every date; a plain meeting link does not', (tester) async {
      await tester.pumpWidget(layoutHost(body(LiveLink.fromJson({'url': _url, 'token': 'abc', 'series_id': 7}))));
      expect(find.byKey(const ValueKey('share_link.series')), findsOneWidget);
      await tester.pumpWidget(layoutHost(body(LiveLink.fromJson({'url': _url, 'token': 'abc'}))));
      expect(find.byKey(const ValueKey('share_link.series')), findsNothing);
    });

    testWidgets('no layout errors', (tester) async {
      await expectNoLayoutErrors(tester, () => body(LiveLink.fromJson({'url': _url, 'token': 'abc', 'series_id': 7, 'has_pin': true})));
    });
  });

  group('the guest page of a repeating meeting', () {
    // the server's answer between two dates (back features/home/calendar_series_link.public_info)
    final between = GuestLiveInfo.fromJson({
      'kind': 'meeting',
      'title': 'Weekly Q&A',
      'host_name': 'Dr. Ahmed Hamdy Madkour',
      'starts_at': '2026-11-29T10:00:00',
      'ends_at': '2026-11-29T11:00:00',
      'opens_at': '2026-11-29T09:45:00',
      'guest_admission': 'approve',
      'auto_join': false,
      'signed_in_join': true,
      'is_live': false,
      'can_publish': true,
      'guests_joined': 0,
      'max_guests': null,
      'requires_pin': false,
      'meeting_id': null,
      'recording_enabled': false,
      'recurring': true,
      'series_id': 7,
      'occurrence_date': '2026-11-29',
    });

    Widget page(GuestLiveInfo info) {
      final name = TextEditingController();
      return GuestLiveContent(loading: false, info: info, error: null, joining: false, nameController: name, onJoin: () {}, onRetry: () {});
    }

    test('between dates: a meeting that is not live, with the next start', () {
      expect((between.recurring, between.isLive, between.isMeeting, between.meetingId), (true, false, true, null));
      expect(between.startsAt, isNotNull);
    });

    testWidgets('shows the next date instead of an error, join waits', (tester) async {
      await tester.pumpWidget(layoutHost(page(between)));
      expect(find.byKey(const ValueKey('guest_live.recurring')), findsOneWidget);
      expect(find.byKey(const ValueKey('guest_live.waiting_banner')), findsOneWidget);
      expect(find.byKey(const ValueKey('guest_live.error')), findsNothing);
      // the banner is the repeating one (translations are not loaded here: the key stands for its text)
      expect(find.textContaining('guest_live_recurring_next'), findsOneWidget);
    });

    testWidgets('no layout errors', (tester) async {
      await expectNoLayoutErrors(tester, () => page(between));
    });
  });
}
