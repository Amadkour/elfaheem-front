// Where the scanner's "Review" and "Results" entries lead. The two pages are built by another agent of the OMR job
// (`OmrReviewPage(examId:)` in paper/review/omr_review_page.dart, `OmrResultsPage(examId:)` in
// paper/review/omr_results_page.dart) and do not exist in this branch, so they are reached through this tiny
// registry instead of an import.
//
// TODO(omr): the lead wires them once at merge, e.g. at the top of the review page file or in main.dart:
//   registerOmrPages(review: (_, id) => OmrReviewPage(examId: id), results: (_, id) => OmrResultsPage(examId: id));
// Until then the entries say "Available soon" and lead nowhere (they are not dead ends: nothing can be tapped).
library;

import 'package:flutter/material.dart';

typedef OmrExamPageBuilder = Widget Function(BuildContext context, int examId);

abstract final class OmrRoutes {
  static OmrExamPageBuilder? review;
  static OmrExamPageBuilder? results;
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
