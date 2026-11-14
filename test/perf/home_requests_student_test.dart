// Student home: HTTP requests on first open, duplicates, waterfall depth, pull-to-refresh — within the budget
// (home_requests_harness.dart). Its own file = its own isolate (fresh app singletons).
import 'package:flutter_education_app/features/home/student/dashboard/dashboard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_requests_harness.dart';

void main() {
  testWidgets('Student home: requests on open and on pull-to-refresh stay within the budget', (tester) async {
    expectWithinBudget(await measureHome(tester, 'student', const DashboardScreen()));
  });
}
