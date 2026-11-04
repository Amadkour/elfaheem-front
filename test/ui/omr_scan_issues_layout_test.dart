import 'package:flutter/material.dart';
import 'package:flutter_education_app/features/shared/exam_engine/paper/scan/omr_scan_issues.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_harness.dart';

void main() {
  testWidgets('scan issues card has no layout errors', (tester) async {
    final issues = OmrScanIssues.fromJson({
      'items': [
        for (final c in kOmrIssueCodes)
          {'code': c, 'page_id': 1, 'label': 'Paper 12', 'message': 'ورقة غير واضحة جدًا ويجب تصويرها مرة أخرى', 'message_en': 'This paper is too blurry to read, please take it again', 'review_item_id': c == 'unknown_student' ? 5 : null},
      ],
    });
    await expectNoLayoutErrors(tester, () => SingleChildScrollView(child: OmrIssuesCard(issues: issues, onOpen: (_) {}, onReplace: (_) {})));
  });
}
