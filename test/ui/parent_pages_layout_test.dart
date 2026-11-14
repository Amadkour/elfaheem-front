// The parent's Children and Alerts tabs and the report's KPI tile (Warm Editorial, D-610 – D-629) at 320x640 and
// 1400x900, Arabic + English, textScaler 1.3, over FakeApi with long names, big counts and long deltas.
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/parent/parent_alerts_page.dart';
import 'package:flutter_education_app/features/parent/parent_children_page.dart';
import 'package:flutter_education_app/features/parent/parent_link_providers.dart';
import 'package:flutter_education_app/features/parent/parent_report_widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/fake_api.dart';
import 'layout_harness.dart';

const _longAr = 'إدارة شؤون الطلاب والدراسات العليا والبحث العلمي بكلية الهندسة';
const _longEn = 'Office of Student Affairs, Graduate Studies and Scientific Research';

String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, dynamic> _profile(int id) => {
      'student': {'id': id, 'name': 'x'},
      'overall': {'progress': 64, 'attendance': 41, 'exam_avg': 38},
      'courses': [
        for (var i = 0; i < 3; i++)
          {
            'course': {'id': i + 1, 'title': _longEn},
            'progress': 45,
            'attendance': {'rate': 40, 'attended': 4, 'held': 10},
            'exams': {'avg': 30},
            'columns': [],
          },
      ],
    };

Map<String, dynamic> _alert(String key, String prio, int child, String type) => {
      'key': key,
      'type': type,
      'priority': prio,
      'unread': prio != 'medium',
      'status': prio == 'medium' ? 'read' : 'unread',
      'at': _iso(DateTime.now().subtract(const Duration(hours: 30))),
      'child': {'id': child, 'name': '$_longAr $_longEn'},
      'params': {'pct': 48, 'exam': _longEn, 'course_ar': _longAr, 'course_en': _longEn, 'title': _longEn, 'days': 12},
    };

FakeApi _api() => FakeApi({
      'GET /api/v1/parent/children': (_) => [
            {'id': 7, 'name': '$_longAr $_longEn', 'linked_at': '2026-09-01T10:00:00Z'},
            {'id': 8, 'name': 'Sara', 'linked_at': '2026-09-01T10:00:00Z'},
          ],
      'GET /api/v1/parent/children/7/profile': (_) => _profile(7),
      'GET /api/v1/parent/children/8/profile': (_) => _profile(8),
      'GET /api/v1/parent/link/config': (_) => {'mode': 'easy'},
      'GET /api/v1/parent/link/requests': (_) => [],
      'GET /api/v1/parent/alerts': (_) => {
            'items': [
              _alert('a1', 'high', 7, 'failed_exam'),
              _alert('a2', 'medium', 7, 'missing_homework'),
              _alert('a3', 'low', 8, 'inactive'),
              for (var i = 0; i < 6; i++) _alert('b$i', 'high', 8, 'score_drop'),
            ],
          },
    });

Widget _tab(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ParentLinkProvider()..loadAll()),
        ChangeNotifierProvider(create: (_) => ParentAlertsProvider()..load()),
      ],
      child: child,
    );

void main() {
  setUp(() {
    AppConfig.disableList = [];
    mockRequestPlugins();
  });

  testWidgets('children tab: child blocks with rings and badges', (tester) async {
    final api = _api()..install();
    addTearDown(api.uninstall);
    await expectNoLayoutErrors(tester, () => _tab(ParentChildrenPage(onOpenLinkTab: () {})), frames: 8);
  });

  testWidgets('alerts tab: priority tiles, sort tabs, cards in both orders', (tester) async {
    final api = _api()..install();
    addTearDown(api.uninstall);
    await expectNoLayoutErrors(tester, () => _tab(const ParentAlertsPage()), frames: 8);
    await expectNoLayoutErrors(
      tester,
      () => _tab(const ParentAlertsPage()),
      frames: 8,
      act: (t) async {
        final newest = find.text('pl_sort_date'.tr);
        if (newest.evaluate().isNotEmpty) await t.tap(newest.first);
      },
    );
  });

  testWidgets('report KPI tile: a long delta chip shrinks instead of clipping', (tester) async {
    await expectNoLayoutErrors(
      tester,
      () => SingleChildScrollView(
        child: SizedBox(
          width: 150,
          child: PlKpi(
            icon: Icons.timer_rounded,
            label: '$_longAr $_longEn',
            value: '1234h 59min',
            sub: _longEn,
            delta: 123456,
            deltaSuffix: '%',
          ),
        ),
      ),
    );
  });
}
