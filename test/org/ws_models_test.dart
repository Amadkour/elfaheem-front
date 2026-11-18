// The teacher workspace's pure logic (lib/features/org/workspace/ws_models.dart, D-1150 – D-1158).
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/org/workspace/ws_models.dart';
import 'package:flutter_test/flutter_test.dart';

WsAlert _a(String key, {String src = 'dept', int? id = 1, String sev = 'medium', bool read = false, String at = '2026-11-10T10:00:00'}) =>
    WsAlert.fromJson({
      'key': key,
      'source': {'type': src, 'id': id, 'name_ar': 'قسم $id', 'name_en': 'Unit $id'},
      'severity': sev,
      'read': read,
      'created_at': at,
    });

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('WsHome', () {
    test('parses units, roles, stats and weeks', () {
      final h = WsHome.fromJson({
        'managed': [
          {'id': 3, 'name_ar': 'الرياضيات', 'name_en': 'Maths', 'people': 40, 'team': 4, 'role': 'head'},
        ],
        'member_of': [
          {'id': 7, 'name_ar': 'العلوم', 'name_en': '', 'role': 'member'},
        ],
        'stats': {'alerts_active': 5, 'alerts_high': 2, 'next_session': null},
        'weeks': {'people': [1, 2, 3]},
      });
      expect(h.managed.single.manages, isTrue);
      expect(h.managed.single.role, WsUnitRole.head);
      expect(h.memberOf.single.manages, isFalse);
      expect(h.memberOf.single.name, 'العلوم');           // English empty → Arabic
      expect(h.unit(7)?.id, 7);
      expect(h.stats.alertsHigh, 2);
      expect(h.stats.nextSession, isNull);
      expect(h.weeks['people'], [1, 2, 3]);
      AppConfig.lang = 'ar';
      expect(h.managed.single.name, 'الرياضيات');
    });
  });

  group('alerts', () {
    test('groups by source: worst severity first, unread rows first inside', () {
      final groups = wsGroupAlerts([
        _a('a', id: 1, sev: 'low'),
        _a('b', id: 2, sev: 'high', read: true),
        _a('c', id: 2, sev: 'low'),
        _a('d', src: 'organization', id: null, sev: 'low'),
      ]);
      expect(groups.map((g) => g.source.key), ['dept:2', 'dept:1', 'organization:0']);
      expect(groups.first.alerts.map((a) => a.key), ['c', 'b']);   // unread before read
      expect(groups.first.worst, WsSeverity.high);
      expect(groups.first.unread, 1);
    });

    test('a tie puts the organization group last', () {
      final groups = wsGroupAlerts([
        _a('o', src: 'organization', id: null),
        _a('u', id: 4),
      ]);
      expect(groups.last.source.type, 'organization');
    });

    test('opens the person only when the alert names a person in a unit', () {
      final a = WsAlert.fromJson({'key': 'k', 'person': {'id': 9, 'name': 'Sara'}, 'dept_id': 3});
      expect(a.opensPerson, isTrue);
      expect(WsAlert.fromJson({'key': 'k', 'person': {'id': 9}}).opensPerson, isFalse);
      expect(a.copyWith(read: true).read, isTrue);
    });
  });

  group('people filter', () {
    test('query sends kinds comma-separated and the sort as the server spells it', () {
      final f = WsPeopleFilter(q: ' ali ', kinds: {WsPersonKind.team, WsPersonKind.head}, joinedFrom: DateTime(2026, 1, 5), sort: WsSort.newest);
      expect(f.query(page: 2), {
        'q': 'ali',
        'kind': 'head,team',
        'joined_from': '2026-01-05',
        'sort': '-joined',
        'page': '2',
        'size': '30',
      });
      expect(f.chipCount, 3);
      expect(f.without(kind: WsPersonKind.team).kinds, {WsPersonKind.head});
      expect(f.without().joinedFrom, isNull);
    });

    test('round-trips through JSON (saved filters)', () {
      final f = WsPeopleFilter(kinds: {WsPersonKind.member}, joinedTo: DateTime(2026, 3, 1), sort: WsSort.oldest);
      final g = WsPeopleFilter.fromJson(f.toJson());
      expect(g.kinds, f.kinds);
      expect(g.joinedTo, DateTime(2026, 3, 1));
      expect(g.sort, WsSort.oldest);
      expect(const WsPeopleFilter().isEmpty, isTrue);
    });
  });

  group('prefs + pins', () {
    test('toggle, move and drop pins of units I left', () {
      var p = const WsPrefs();
      const a = WsPin('unit', '3'), b = WsPin('box', 'alerts'), c = WsPin('tab', 'ws_alerts');
      p = p.togglePin(a).togglePin(b).togglePin(c);
      expect(p.pins, [a, b, c]);
      p = p.movePin(0, 3);                                   // first → last
      expect(p.pins, [b, c, a]);
      p = p.togglePin(b);
      expect(p.pins, [c, a]);
      expect(wsLivePins(p.pins, {7}), [c]);                  // unit 3 is gone
    });

    test('main unit opens when still listed, else the first', () {
      const p = WsPrefs(mainUnit: {'management': 5});
      expect(p.openUnit('management', [2, 5]), 5);
      expect(p.openUnit('management', [2]), 2);
      expect(p.openUnit('membership', const []), isNull);
    });

    test('round-trips through JSON and ignores junk', () {
      final p = const WsPrefs(display: {'management': WsDisplay.tabs}, mainUnit: {'membership': 4}, focus: true, alertView: WsAlertView.expanded)
          .togglePin(const WsPin('unit', '4', labelAr: 'أ', labelEn: 'A'));
      final q = WsPrefs.fromJson({
        ...p.toJson(),
        'pins': [...(p.toJson()['pins'] as List), {'kind': 'nope', 'ref': 'x'}, 'junk'],
      });
      expect(q.displayOf('management'), WsDisplay.tabs);
      expect(q.displayOf('membership'), WsDisplay.boxes);
      expect(q.mainUnit, {'membership': 4});
      expect(q.focus, isTrue);
      expect(q.alertView, WsAlertView.expanded);
      expect(q.pins.single.label, 'A');
    });
  });

  test('history groups by local day, newest first', () {
    final rows = [
      WsHistoryRow.fromJson({'id': 1, 'created_at': '2026-11-01T08:00:00'}),
      WsHistoryRow.fromJson({'id': 2, 'created_at': '2026-11-03T08:00:00', 'actor': null}),
      WsHistoryRow.fromJson({'id': 3, 'created_at': '2026-11-03T09:00:00', 'actor': {'id': 5, 'name': 'Omar'}}),
    ];
    final days = wsHistoryByDay(rows);
    expect(days.length, 2);
    expect(days.first.$2.map((r) => r.id), [3, 2]);
    expect(days.first.$2.first.actorName, 'Omar');
    expect(days.first.$2.last.actorId, isNull);
  });
}
