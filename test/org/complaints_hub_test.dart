// The pure rules of the profile's Complaints page (D-086): parsing both sources into one row, the two orders,
// filters / search / counts, the SLA chip, the quick actions and the labels.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/profile/compalints/complaint_model.dart';
import 'package:flutter_education_app/features/profile/compalints/complaints_hub_model.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 28, 7);

HubRow _row(
  int id, {
  HubSource source = HubSource.org,
  HubStatus status = HubStatus.open,
  String priority = 'medium',
  Duration age = const Duration(hours: 1),
  Duration? updatedAgo,
  DateTime? due,
  bool unread = false,
  bool mine = false,
  bool canAct = true,
  String title = 'Complaint',
}) =>
    HubRow(
      source: source,
      id: id,
      title: title,
      status: status,
      priority: priority,
      createdAt: _now.subtract(age),
      updatedAt: _now.subtract(updatedAgo ?? age),
      dueAt: due,
      unread: unread,
      mine: mine,
      canAct: canAct,
    );

void main() {
  setUpAll(() {
    translation = jsonDecode(File('assets/translation.json').readAsStringSync()) as Map<String, dynamic>;
  });
  setUp(() => AppConfig.lang = 'en');

  group('parsing', () {
    test('a platform complaint: mine vs to resolve', () {
      final j = {
        'id': 41, 'user_id': 7, 'user_name': 'Mariam', 'title': 'Video stops', 'description': 'At minute 12',
        'category': 'course_content', 'priority': 'high', 'status': 'in_progress', 'is_read_by_admin': false,
        'is_read_by_user': false, 'created_at': '2026-10-27T07:00:00', 'updated_at': '2026-10-28T06:00:00',
        'replies_count': 2, 'target_type': 'course', 'target_label': 'Python', 'course_title': 'Python',
        'attachments': [
          {'id': 1, 'file_url': 'https://x/a.png', 'uploaded_at': '2026-10-27T07:00:00'},
        ],
      };
      final m = ComplaintModel.fromJson(j);
      final mine = HubRow.fromPlatform(m, mine: true);
      expect(mine.source, HubSource.platform);
      expect(mine.status, HubStatus.inProgress);
      expect(mine.unread, isTrue); // is_read_by_user false
      expect(mine.about, 'Python');
      expect(mine.sender, isNull);
      expect(mine.canAct, isFalse);
      expect(mine.attachments, 1);
      expect(mine.updatedAt, DateTime.utc(2026, 10, 28, 6));
      final other = HubRow.fromPlatform(m, mine: false);
      expect(other.sender, 'Mariam');
      expect(other.unread, isTrue); // is_read_by_admin false
      expect(other.canAct, isTrue);
    });

    test('an organization complaint: names, reply-by, anonymous sender, can_act', () {
      final j = {
        'id': 11, 'ref': 'C-000011', 'org_id': 3, 'subject': 'Grade missing', 'body': 'Databases', 'status': 'waiting',
        'priority': 'urgent', 'due_at': '2026-10-28T04:00:00', 'unread': true, 'created_at': '2026-10-27T04:00:00',
        'updated_at': null, 'is_anonymous': true, 'user': {'id': null, 'name': 'hidden'},
        'department': {'id': 2, 'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs'},
        'org': {'id': 3, 'name_ar': 'جامعة القاهرة', 'name_en': 'Cairo University'}, 'can_act': true,
        'attachments': [{'name': 'a.pdf', 'url': 'u'}],
      };
      final r = HubRow.fromOrg(j, mine: false);
      expect(r.status, HubStatus.waiting);
      expect(r.dueAt, DateTime.utc(2026, 10, 28, 4));
      expect(r.updatedAt, r.createdAt); // falls back to created_at
      expect(r.anonymous, isTrue);
      expect(r.sender, isNull);
      expect(r.canAct, isTrue);
      expect(r.org!.text, 'Cairo University');
      expect(r.department!.text, 'Student Affairs');
      AppConfig.lang = 'ar';
      expect(r.org!.text, 'جامعة القاهرة');
      expect(r.attachments, 1);
    });

    test('my organization complaint: the org name comes from my organizations when the row has only org_id', () {
      final r = HubRow.fromOrg(
        {'id': 5, 'org_id': 9, 'subject': 'AC', 'status': 'closed', 'created_at': '2026-10-01T00:00:00', 'can_act': true},
        mine: true,
        orgNames: {9: const HubName('', 'Nile Institute')},
      );
      expect(r.org!.text, 'Nile Institute');
      expect(r.canAct, isFalse); // never on my own complaint
      expect(r.status.active, isFalse);
    });

    test('status wire names round-trip', () {
      for (final s in HubStatus.values) {
        expect(HubStatus.parse(s.wire), s);
      }
      expect(HubStatus.parse('garbage'), HubStatus.open);
    });
  });

  group('order', () {
    test('my complaints: unread first, then the latest change', () {
      final rows = sortMine([
        _row(1, updatedAgo: const Duration(minutes: 5)),
        _row(2, updatedAgo: const Duration(days: 2), unread: true),
        _row(3, updatedAgo: const Duration(hours: 1)),
      ]);
      expect(rows.map((r) => r.id).toList(), [2, 1, 3]);
    });

    test('to resolve: overdue, nearest reply-by, priority; finished last', () {
      final rows = sortToResolve([
        _row(1, due: _now.add(const Duration(hours: 30))),
        _row(2, status: HubStatus.resolved, updatedAgo: const Duration(minutes: 1)),
        _row(3, due: _now.subtract(const Duration(hours: 2))), // overdue
        _row(4, due: _now.add(const Duration(hours: 5))),
        // a platform complaint: urgent, created 20 h ago → its usual window (24 h) ends in 4 h
        _row(5, source: HubSource.platform, priority: 'urgent', age: const Duration(hours: 20)),
        _row(6, status: HubStatus.closed, updatedAgo: const Duration(days: 3)),
      ], _now);
      expect(rows.map((r) => r.id).toList(), [3, 5, 4, 1, 2, 6]);
    });

    test('same reply-by: priority, then unread, then the oldest', () {
      final due = _now.add(const Duration(hours: 10));
      final rows = sortToResolve([
        _row(1, due: due, priority: 'low'),
        _row(2, due: due, priority: 'high', age: const Duration(hours: 1)),
        _row(3, due: due, priority: 'high', age: const Duration(hours: 3)),
        _row(4, due: due, priority: 'high', unread: true),
      ], _now);
      expect(rows.map((r) => r.id).toList(), [4, 3, 2, 1]);
    });

    test('merge drops duplicates by source and id', () {
      final a = [_row(1), _row(2, source: HubSource.platform)];
      final b = [_row(1), _row(1, source: HubSource.platform)];
      expect(mergeRows(a, b).map((r) => r.key).toList(), ['org:1', 'platform:2', 'platform:1']);
    });
  });

  group('filters', () {
    final rows = [
      _row(1, status: HubStatus.open, unread: true, title: 'Grade missing'),
      _row(2, status: HubStatus.inProgress, due: _now.subtract(const Duration(hours: 1))),
      _row(3, status: HubStatus.waiting),
      _row(4, status: HubStatus.resolved, unread: true),
      _row(5, status: HubStatus.closed),
    ];

    test('each chip', () {
      final c = filterCounts(rows, HubFilter.values, _now);
      expect(c[HubFilter.all], 5);
      expect(c[HubFilter.open], 1);
      expect(c[HubFilter.inProgress], 2); // waiting counts as in progress
      expect(c[HubFilter.resolved], 1);
      expect(c[HubFilter.closed], 1);
      expect(c[HubFilter.active], 3);
      expect(c[HubFilter.overdue], 1);
      expect(c[HubFilter.unread], 1); // a finished unread row does not need me
    });

    test('search covers title, reference, sender, organization and department', () {
      final r = HubRow.fromOrg({
        'id': 1, 'ref': 'C-000042', 'org_id': 3, 'subject': 'Hall too hot', 'body': 'AC broken', 'status': 'open',
        'created_at': '2026-10-27T00:00:00', 'user': {'id': 4, 'name': 'Sara Mahmoud'},
        'department': {'name_ar': 'شؤون الطلاب', 'name_en': 'Student Affairs'},
        'org': {'name_ar': 'جامعة القاهرة', 'name_en': 'Cairo University'},
      }, mine: false);
      for (final q in ['hall', 'c-000042', 'sara', 'cairo', 'شؤون', 'ac broken', '  ']) {
        expect(matchesQuery(r, q), isTrue, reason: q);
      }
      expect(matchesQuery(r, 'payment'), isFalse);
    });

    test('visible rows apply filter + search + the segment order', () {
      final v = visibleRows(rows, HubSegment.toResolve, HubFilter.active, '', _now);
      expect(v.first.id, 2); // the overdue one
      expect(visibleRows(rows, HubSegment.mine, HubFilter.all, 'grade', _now).map((r) => r.id), [1]);
    });

    test('badges and who sees "To resolve"', () {
      expect(toResolveBadge(rows), 3);
      expect(mineBadge(rows), 2);
      expect(defaultFilter(HubSegment.mine), HubFilter.all);
      expect(defaultFilter(HubSegment.toResolve), HubFilter.active);
      expect(offersToResolve(role: 'student', hasRows: false), isFalse);
      expect(offersToResolve(role: 'parent', hasRows: false), isFalse);
      expect(offersToResolve(role: 'student', hasRows: true), isTrue);
      expect(offersToResolve(role: 'teacher', hasRows: false), isTrue);
      expect(offersToResolve(role: 'org-staff', hasRows: false), isTrue);
    });
  });

  group('SLA, actions, labels', () {
    test('reply-by of an open complaint only', () {
      final late = slaOf(_row(1, due: _now.subtract(const Duration(hours: 3))), _now)!;
      expect(late.overdue, isTrue);
      expect(late.span, const Duration(hours: 3));
      final soon = slaOf(_row(2, due: _now.add(const Duration(hours: 5))), _now)!;
      expect((soon.overdue, soon.soon), (false, true));
      expect(slaOf(_row(3, due: _now.add(const Duration(hours: 30))), _now)!.soon, isFalse);
      expect(slaOf(_row(4), _now), isNull); // no reply-by (platform)
      expect(slaOf(_row(5, status: HubStatus.resolved, due: _now), _now), isNull);
      expect(isOverdue(_row(6, status: HubStatus.closed, due: _now.subtract(const Duration(days: 1))), _now), isFalse);
    });

    test('quick actions follow the status and the right to act', () {
      expect(quickActionsFor(_row(1)), [HubAction.reply, HubAction.start, HubAction.resolve]);
      expect(quickActionsFor(_row(2, status: HubStatus.inProgress)), [HubAction.reply, HubAction.resolve]);
      expect(quickActionsFor(_row(3, status: HubStatus.waiting)), [HubAction.reply, HubAction.resolve]);
      expect(quickActionsFor(_row(4, status: HubStatus.resolved)), isEmpty);
      expect(quickActionsFor(_row(5, canAct: false)), isEmpty);
      expect(quickActionsFor(_row(6, mine: true)), isEmpty);
      expect(statusAfter(HubAction.start), HubStatus.inProgress);
      expect(statusAfter(HubAction.resolve), HubStatus.resolved);
      expect(statusAfter(HubAction.reply), isNull);
    });

    test('span and "ago" labels in both languages', () {
      expect(spanLabel(const Duration(minutes: 0)), '1 min');
      expect(spanLabel(const Duration(minutes: 45)), '45 min');
      expect(spanLabel(const Duration(hours: 5)), '5 h');
      expect(spanLabel(const Duration(days: 3)), '3 d');
      expect(agoLabel(_now.subtract(const Duration(seconds: 20)), _now), 'just now');
      expect(agoLabel(_now.subtract(const Duration(minutes: 12)), _now), '12 min ago');
      expect(agoLabel(_now.subtract(const Duration(hours: 5)), _now), '5 h ago');
      expect(agoLabel(_now.subtract(const Duration(days: 3)), _now), '3 d ago');
      expect(agoLabel(_now.subtract(const Duration(days: 9)), _now), isNull);
      AppConfig.lang = 'ar';
      expect(spanLabel(const Duration(hours: 5)), '5 س');
      expect(agoLabel(_now.subtract(const Duration(minutes: 12)), _now), 'منذ 12 د');
    });

    test('SLA hours and priority ranks match the server', () {
      expect([for (final p in ['urgent', 'high', 'medium', 'low']) slaHours(p)], [24, 48, 72, 120]);
      expect(priorityRank('urgent') < priorityRank('high'), isTrue);
      expect(priorityRank('unknown'), priorityRank('low'));
    });
  });
}
