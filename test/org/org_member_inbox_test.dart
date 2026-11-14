// Member dashboard: inbox priority order, urgency, countdowns and the Organization/Individual switch rules.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_mode.dart';
import 'package:flutter_education_app/features/messaging/inbox/unified_inbox.dart';
import 'package:flutter_test/flutter_test.dart';

String iso(DateTime d) => d.toUtc().toIso8601String().replaceAll('Z', ''); // the server sends naive UTC

InboxItem item(String key, {DateTime? due, DateTime? created, bool mandatory = false, String kind = 'form', String segment = 'todo'}) =>
    InboxItem({
      'key': key,
      'kind': kind,
      'segment': segment,
      'title': key,
      'due_at': due == null ? null : iso(due),
      'created_at': created == null ? null : iso(created),
      'mandatory': mandatory,
    });

void main() {
  final now = DateTime.now();

  test('order: overdue → due soon → new → rest; required first; nearest deadline; newest', () {
    final items = [
      item('old', created: now.subtract(const Duration(days: 20))),
      item('new', created: now.subtract(const Duration(hours: 2))),
      item('soon_late', due: now.add(const Duration(hours: 60))),
      item('soon_early', due: now.add(const Duration(hours: 5))),
      item('soon_required', due: now.add(const Duration(hours: 70)), mandatory: true),
      item('overdue', due: now.subtract(const Duration(hours: 1))),
      item('far', due: now.add(const Duration(days: 10)), created: now.subtract(const Duration(days: 9))),
    ];
    expect(sortInbox(items, now).map((x) => x.key).toList(),
        ['overdue', 'soon_required', 'soon_early', 'soon_late', 'new', 'far', 'old']);
  });

  test('urgency and countdown', () {
    expect(inboxUrgency(item('a', due: now.subtract(const Duration(minutes: 5))), now), 'overdue');
    expect(inboxUrgency(item('b', due: now.add(const Duration(hours: 10))), now), 'due_soon');
    expect(inboxUrgency(item('c', created: now.subtract(const Duration(hours: 1))), now), 'new');
    expect(inboxUrgency(item('d'), now), 'normal');
    // an offer that ended is never an alarm
    expect(inboxUrgency(item('ad', kind: 'ad', segment: 'offers', due: now.subtract(const Duration(hours: 1))), now), 'normal');
    expect(inboxCountdown(item('e'), now), isNull);
    // (translations aren't loaded in unit tests: the keys tell which sentence was chosen)
    expect(inboxCountdown(item('f', due: now.add(const Duration(hours: 5, minutes: 10))), now), 'inbox_due_in');
    expect(inboxCountdown(item('g', due: now.subtract(const Duration(days: 3, hours: 1))), now), 'inbox_overdue_by');
    expect(inboxCountdown(item('h', kind: 'ad', due: now.subtract(const Duration(hours: 1))), now), isNull);
  });

  test('the switch only exists with a live organization and the org master switch on', () {
    final ctl = AppModeController.instance;
    ctl.debugSet({'items': []}, mode: AppMode.organization);
    expect(ctl.available, isFalse);
    expect(ctl.mode, AppMode.individual);

    ctl.debugSet({
      'items': [
        {'organization': {'id': 7, 'status': 'pending'}, 'roles': [], 'manage': {'is_admin': true}},
        {'organization': {'id': 9, 'status': 'approved'}, 'roles': ['student'], 'manage': null, 'todo': {'total': 2}, 'approvals': {'total': 1}},
      ],
      'default_org_id': 9,
      'pending_total': 3,
    }, mode: AppMode.organization);
    expect(ctl.available, isTrue);
    expect(ctl.isOrg, isTrue);
    expect(ctl.currentOrgId, 9); // a pending organization is never opened in Organization mode
    expect(AppModeController.pendingOf(ctl.current!), 3);


    AppConfig.orgsEnabled = false;
    expect(ctl.available, isFalse);
    expect(ctl.mode, AppMode.individual);
    AppConfig.orgsEnabled = true;
  });
}
