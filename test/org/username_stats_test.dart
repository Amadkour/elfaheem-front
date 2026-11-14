// Username rollout numbers (D-076, lib/features/admin/admin_username_stats.dart): the payload parser (every key
// optional, odd types tolerated) and the trend folding.
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/admin/admin_username_stats.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> payload() => {
      'days': 7,
      'since': '2026-10-22',
      'until': '2026-10-28',
      'snapshot': {'users_total': 200, 'with_username': 150, 'confirmed': 90, 'unconfirmed_pending': 60, 'without': 50},
      'flows': {'kept': 5, 'changed': 3, 'removed': 2, 'set_at_signup': 7, 'set_later': 1, 'admin_set': 4,
        'admin_cleared': 1, 'profile_changed': 0, 'profile_removed': 0, 'backfilled': 0},
      'daily': [
        for (var i = 0; i < 7; i++)
          {
            'date': '2026-10-${22 + i}',
            'events': {'confirmed_kept': i, 'chosen_at_signup': 1, 'set_in_profile': i == 6 ? 2 : 0},
            'logins': {'email': 10, 'username': i},
          }
      ],
      'logins_by_kind': {'email': 70, 'phone': 5, 'username': 21, 'id': 3, 'google': 1},
      'prompt_conversion': 0.1429,
    };

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parses the full payload', () {
    final s = UsernameStats.fromJson(payload());
    expect(s.days, 7);
    expect([s.usersTotal, s.withUsername, s.confirmed, s.pending, s.without], [200, 150, 90, 60, 50]);
    expect(s.answered, 10);
    expect(s.flow('admin_set'), 4);
    expect(s.login('username'), 21);
    expect(s.loginsTotal, 100);
    expect(s.promptConversion, closeTo(0.1429, 1e-9));
    expect(s.usernameShare, 0.75);
    expect(s.daily.length, 7);
    expect(s.daily.last.date, '2026-10-28');
    expect(s.daily.last.answered, 6);
    expect(s.daily.last.newNames, 3);
    expect(s.daily.last.usernameLogins, 6);
  });

  test('missing keys read as zeros (an older or partial server)', () {
    final s = UsernameStats.fromJson(const {});
    expect(s.days, 30);
    expect([s.usersTotal, s.withUsername, s.confirmed, s.pending, s.without], [0, 0, 0, 0, 0]);
    expect(s.flows, isEmpty);
    expect(s.flow('kept'), 0);
    expect(s.loginsTotal, 0);
    expect(s.daily, isEmpty);
    expect(s.promptConversion, isNull);
    expect(s.usernameShare, 0);
  });

  test('odd types are tolerated', () {
    final s = UsernameStats.fromJson({
      'days': '30',
      'snapshot': {'users_total': '12', 'with_username': 4.0, 'confirmed': null},
      'flows': 'not a map',
      'daily': [
        'junk',
        {'date': '2026-10-01'},
        {'date': '2026-10-02', 'events': {'confirmed_changed': '2'}, 'logins': null},
      ],
      'logins_by_kind': {'email': '3'},
      'prompt_conversion': 1.7,
    });
    expect(s.days, 30);
    expect(s.usersTotal, 12);
    expect(s.withUsername, 4);
    expect(s.confirmed, 0);
    expect(s.flows, isEmpty);
    expect(s.daily.length, 2);
    expect(s.daily.first.answered, 0);
    expect(s.daily.last.answered, 2);
    expect(s.login('email'), 3);
    expect(s.promptConversion, 1.0);
  });

  test('the trend folds the days into at most 10 bars', () {
    List<UsernameStatsDay> days(int n) => [
          for (var i = 0; i < n; i++)
            UsernameStatsDay(date: 'd$i', events: const {'confirmed_kept': 1, 'set_in_profile': 1}, logins: {'username': i}),
        ];
    expect(usernameTrend(const []), isEmpty);

    final week = usernameTrend(days(7));
    expect(week.length, 7);
    expect(week.first.firstDate, 'd0');
    expect(week.last.usernameLogins, 6);

    final month = usernameTrend(days(30));
    expect(month.length, 10);
    expect(month.first.firstDate, 'd0');
    expect(month[1].firstDate, 'd3');
    expect(month.first.answered, 3);
    expect(month.first.newNames, 3);
    expect(month.first.usernameLogins, 0 + 1 + 2);

    final quarter = usernameTrend(days(90));
    expect(quarter.length, 10);
    expect(quarter.fold<int>(0, (a, b) => a + b.answered), 90);

    final odd = usernameTrend(days(31));
    expect(odd.length, 8); // 4 days a bar, the last one shorter
    expect(odd.last.answered, 3);
  });

  test('day labels', () {
    expect(usernameDayLabel('2026-10-28'), '28 Oct');
    expect(usernameDayLabel('nonsense'), 'nonsense');
  });
}
