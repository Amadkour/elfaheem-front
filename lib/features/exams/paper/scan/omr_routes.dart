// Where the scanner's "Review" and "Results" entries lead: `OmrReviewPage(examId:)` and `OmrResultsPage(examId:)`
// (paper/review/). Kept as a small registry so a test can swap a page out; it points at the real pages by default.
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/features/exams/paper/review/omr_results_page.dart';
import 'package:flutter_education_app/features/exams/paper/review/omr_review_page.dart';

export 'package:flutter_education_app/features/exams/paper/review/omr_review_page.dart' show OmrReviewFocus;

typedef OmrExamPageBuilder = Widget Function(BuildContext context, int examId);

/// The review page opened on one student's answer ("Review it on the paper image" in Review marking).
typedef OmrFocusedReviewBuilder = Widget Function(BuildContext context, int examId, OmrReviewFocus focus);

Widget _reviewPage(BuildContext _, int id) => OmrReviewPage(examId: id);

abstract final class OmrRoutes {
  static OmrExamPageBuilder? review = _reviewPage;
  static OmrExamPageBuilder? results = (_, id) => OmrResultsPage(examId: id);

  /// [review] opened on one answer. Null: the real page on that answer while [review] is the real page, else
  /// [review] as it is (a swapped-in review page knows nothing of the focus).
  static OmrFocusedReviewBuilder? reviewAt;
}

void registerOmrPages({OmrExamPageBuilder? review, OmrExamPageBuilder? results, OmrFocusedReviewBuilder? reviewAt}) {
  if (review != null) OmrRoutes.review = review;
  if (results != null) OmrRoutes.results = results;
  if (reviewAt != null) OmrRoutes.reviewAt = reviewAt;
}

/// Pushes the review page of [examId], on [focus]'s item when given; false when it is not wired.
Future<bool> openOmrReview(BuildContext context, int examId, {OmrReviewFocus? focus}) {
  final at = OmrRoutes.reviewAt ??
      (identical(OmrRoutes.review, _reviewPage) ? (BuildContext _, int id, OmrReviewFocus f) => OmrReviewPage(examId: id, focus: f) : null);
  if (focus != null && at != null && OmrRoutes.review != null) {
    return _open(context, (c, id) => at(c, id, focus), examId);
  }
  return _open(context, OmrRoutes.review, examId);
}

/// Pushes the results page of [examId]; false when it is not wired.
Future<bool> openOmrResults(BuildContext context, int examId) => _open(context, OmrRoutes.results, examId);

Future<bool> _open(BuildContext context, OmrExamPageBuilder? b, int examId) async {
  if (b == null) return false;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (c) => b(c, examId)));
  return true;
}
