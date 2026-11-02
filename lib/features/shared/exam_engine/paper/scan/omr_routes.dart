// Where the scanner's "Review" and "Results" entries lead: `OmrReviewPage(examId:)` and `OmrResultsPage(examId:)`
// (paper/review/). Kept as a small registry so a test can swap a page out; it points at the real pages by default.
library;

import 'package:flutter/material.dart';

import '../review/omr_results_page.dart';
import '../review/omr_review_page.dart';

typedef OmrExamPageBuilder = Widget Function(BuildContext context, int examId);

abstract final class OmrRoutes {
  static OmrExamPageBuilder? review = (_, id) => OmrReviewPage(examId: id);
  static OmrExamPageBuilder? results = (_, id) => OmrResultsPage(examId: id);
}

void registerOmrPages({OmrExamPageBuilder? review, OmrExamPageBuilder? results}) {
  if (review != null) OmrRoutes.review = review;
  if (results != null) OmrRoutes.results = results;
}

/// Pushes the review page of [examId]; false when it is not wired.
Future<bool> openOmrReview(BuildContext context, int examId) => _open(context, OmrRoutes.review, examId);

/// Pushes the results page of [examId]; false when it is not wired.
Future<bool> openOmrResults(BuildContext context, int examId) => _open(context, OmrRoutes.results, examId);

Future<bool> _open(BuildContext context, OmrExamPageBuilder? b, int examId) async {
  if (b == null) return false;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (c) => b(c, examId)));
  return true;
}
