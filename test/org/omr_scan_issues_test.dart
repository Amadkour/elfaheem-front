import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_batch_notice.dart';
import 'package:flutter_education_app/features/exams/paper/scan/omr_scan_issues.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/layout_harness.dart';


const _json = {
  'items': [
    {'code': 'unreadable_page', 'page_id': 7, 'batch_id': 3, 'label': '7', 'message': 'الصفحة 7 غير واضحة', 'message_en': 'Page 7 is blurry'},
    {'code': 'duplicate_scan', 'page_id': 8, 'batch_id': 3, 'label': '8', 'message': 'مكررة', 'message_en': 'Duplicate'},
    {'code': 'unknown_student', 'page_id': 9, 'batch_id': 3, 'label': '9', 'message': '', 'message_en': 'No such student', 'review_item_id': 41},
    {'code': 'unreadable_page', 'page_id': 10, 'batch_id': 3, 'label': '10', 'message': 'x', 'message_en': 'y'},
    {'code': 'something_new', 'page_id': 11},
  ],
  'counts': {},
};

void main() {
  setUp(() => AppConfig.lang = 'en');

  test('parses, groups by code in the known order, unknown codes last', () {
    final i = OmrScanIssues.fromJson(Map<String, dynamic>.from(_json));
    expect(i.items.length, 5);
    expect([for (final (c, _) in i.groups) c], ['unreadable_page', 'duplicate_scan', 'unknown_student', 'something_new']);
    expect(i.groups.first.$2.length, 2);
    expect(i.items[2].reviewItemId, 41);
    expect(i.items[0].canReplace, isTrue);
    expect(i.items[2].canReplace, isFalse);
  });

  test('an older server (no items) gives an empty list', () {
    expect(OmrScanIssues.fromJson(const {}).isEmpty, isTrue);
  });

  test('text follows the language', () {
    final i = OmrScanIssue.fromJson(Map<String, dynamic>.from((_json['items']! as List).first as Map));
    expect(i.text, 'Page 7 is blurry');
    AppConfig.lang = 'ar';
    expect(i.text, 'الصفحة 7 غير واضحة');
  });

  test('batch done sentence', () {
    expect(omrBatchDoneText(12, 3), 'Grading finished: 12 graded, 3 to review');
  });

  testWidgets('card shows counts and the right action per item', (tester) async {
    final opened = <int?>[], replaced = <int?>[];
    await tester.pumpWidget(layoutHost(SingleChildScrollView(
        child: OmrIssuesCard(
            issues: OmrScanIssues.fromJson(Map<String, dynamic>.from(_json)), onOpen: (i) => opened.add(i.reviewItemId), onReplace: (i) => replaced.add(i.pageId)))));
    expect(find.text('Unreadable page (2)'), findsOneWidget);
    expect(find.text('Unknown student (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('omr.issue.open.41')));
    await tester.tap(find.byKey(const ValueKey('omr.issue.replace.7')));
    expect(opened, [41]);
    expect(replaced, [7]);
    expect(find.byKey(const ValueKey('omr.issue.replace.8')), findsNothing);
  });
}
