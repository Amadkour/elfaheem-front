// The workspace's Alerts / Pinned / Profile tabs (F4, docs/teacher-org/PLAN.md): the pure helpers and the
// plain-value parts through the layout harness (320 × 640 and 1400 × 900, ar / en, text scale 1.3).
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/app_time.dart';
import 'package:flutter_education_app/features/org/org_page_kit.dart' show OrgMenuItem;
import 'package:flutter_education_app/features/org/workspace/ws_alerts.dart';
import 'package:flutter_education_app/features/org/workspace/ws_models.dart';
import 'package:flutter_education_app/features/org/workspace/ws_pinned.dart';
import 'package:flutter_education_app/features/org/workspace/ws_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';

const _dept = WsAlertSource(type: 'department', id: 3, nameAr: 'قسم الرياضيات التطبيقية والإحصاء', nameEn: 'Applied Mathematics and Statistics');
const _org = WsAlertSource(type: 'organization');

WsAlert _a(String key, {WsAlertSource source = _dept, WsSeverity sev = WsSeverity.medium, DateTime? at, bool read = false, String? person}) => WsAlert(
      key: key,
      source: source,
      severity: sev,
      titleAr: 'طلب انضمام ينتظر الموافقة منذ ثلاثة أيام في القسم',
      titleEn: 'A join request has been waiting for approval for three days in the department',
      subtitleAr: 'راجع الطلب قبل نهاية الأسبوع',
      subtitleEn: 'Review the request before the end of the week',
      personId: person == null ? null : 7,
      personName: person,
      deptId: 3,
      at: at,
      read: read,
    );

void main() {
  setUp(() => AppConfig.lang = 'en');

  group('helpers', () {
    test('wsSnoozeUntil: an hour, tomorrow 8:00 and a week later 8:00 on the effective clock', () {
      final now = DateTime.utc(2026, 11, 18, 14, 30);
      expect(wsSnoozeUntil(WsSnooze.hour, nowUtc: now), DateTime.utc(2026, 11, 18, 15, 30));
      final tomorrow = AppTime.toZone(wsSnoozeUntil(WsSnooze.tomorrow, nowUtc: now));
      final today = AppTime.toZone(now);
      expect(tomorrow.hour, wsSnoozeMorningHour);
      expect(DateTime(tomorrow.year, tomorrow.month, tomorrow.day).difference(DateTime(today.year, today.month, today.day)).inDays, 1);
      final week = AppTime.toZone(wsSnoozeUntil(WsSnooze.nextWeek, nowUtc: now));
      expect(week.hour, wsSnoozeMorningHour);
      expect(DateTime(week.year, week.month, week.day).difference(DateTime(today.year, today.month, today.day)).inDays, 7);
      expect(wsSnoozeUntil(WsSnooze.tomorrow, nowUtc: now).isUtc, isTrue);
    });

    test('wsFilterAlerts keeps everything with no filter, and ANDs source with severity', () {
      final l = [_a('1', sev: WsSeverity.high), _a('2', source: _org, sev: WsSeverity.high), _a('3', sev: WsSeverity.low)];
      expect(wsFilterAlerts(l).length, 3);
      expect(wsFilterAlerts(l, sources: {_dept.key}).map((a) => a.key).toList(), ['1', '3']);
      expect(wsFilterAlerts(l, severities: {WsSeverity.high}).map((a) => a.key).toList(), ['1', '2']);
      expect(wsFilterAlerts(l, sources: {_org.key}, severities: {WsSeverity.low}), isEmpty);
    });

    test('wsNewestFirst: newest first, undated rows last by severity', () {
      final l = [
        _a('old', at: DateTime(2026, 1, 1)),
        _a('low', sev: WsSeverity.low),
        _a('new', at: DateTime(2026, 5, 1)),
        _a('high', sev: WsSeverity.high),
      ];
      expect(wsNewestFirst(l).map((a) => a.key).toList(), ['new', 'old', 'high', 'low']);
    });

    test('pins: tab key, search', () {
      expect(wsPinTabKey(const WsPin('tab', 'management')), 'ws_management');
      expect(wsPinTabKey(const WsPin('tab', 'ws_alerts')), 'ws_alerts');
      final pins = [const WsPin('unit', '1', labelEn: 'Physics'), const WsPin('unit', '2', labelEn: 'Chemistry')];
      String label(WsPin p) => wsPinLabel(p, null);
      expect(wsSearchPins(pins, '', label).length, 2);
      expect(wsSearchPins(pins, 'chem', label).single.ref, '2');
      expect(label(const WsPin('tab', 'membership')), 'Membership');
    });
  });

  group('layout', () {
    final now = DateTime(2026, 11, 18, 12);
    final actions = [OrgMenuItem(icon: Icons.archive_outlined, label: 'Archive', onTap: () {})];

    testWidgets('alert row', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(children: [
          WsAlertRow(alert: _a('1', person: 'Abdelrahman Mohamed Abdelaziz El-Sayed', at: now.subtract(const Duration(hours: 3))), now: now, actions: actions),
          WsAlertRow(alert: _a('2', sev: WsSeverity.high, read: true), now: now, actions: actions, onTap: () {}),
        ]),
      );
    });

    testWidgets('alert group card, open and closed', (tester) async {
      final g = WsAlertGroup(_dept, [_a('1', person: 'Sara Ali', at: now), _a('2', sev: WsSeverity.high), _a('3', read: true)]);
      await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: [
          WsAlertGroupCard(group: g, open: true, onToggle: () {}, onMarkAllRead: () {}, children: [
            for (final a in g.alerts) WsAlertRow(alert: a, now: now, actions: actions),
          ]),
          WsAlertGroupCard(group: WsAlertGroup(_org, [_a('4', source: _org)]), open: false, onToggle: () {}, children: const []),
        ]),
      );
    });

    testWidgets('pin strip with 14 pins', (tester) async {
      final pins = [
        for (var i = 0; i < 14; i++) WsPin(i.isEven ? 'unit' : 'box', '$i', labelAr: 'وحدة رقم $i ذات اسم طويل', labelEn: 'Unit number $i with a long name'),
      ];
      await expectNoLayoutErrors(
        tester,
        () => Column(children: [
          WsPinStrip(pins: pins, selectedId: pins[2].id, labelOf: (p) => p.label, onSelect: (_) {}, onUnpin: (_) {}, onAll: () {}),
        ]),
        act: (tester) async => expect(find.byKey(const ValueKey('ws-pin-all'), skipOffstage: false), findsOneWidget),
      );
    });

    testWidgets('profile header', (tester) async {
      await expectNoLayoutErrors(
        tester,
        () => ListView(padding: const EdgeInsets.all(16), children: const [
          WsProfileHeader(
            name: 'Abdelrahman Mohamed Abdelaziz El-Sayed',
            role: 'Teaching assistant · Faculty of Engineering, Cairo University',
            email: 'abdelrahman.mohamed.long.address@example.com',
            username: 'abdelrahman_m',
            managed: 3,
            memberOf: 12,
            unread: 128,
          ),
        ]),
      );
    });
  });
}
