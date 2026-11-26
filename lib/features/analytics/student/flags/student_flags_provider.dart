// features/analytics/student/flags/student_flags_provider.dart
import 'package:flutter_education_app/core/api_error_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/analytics/student/flags/student_flags_api.dart';

/// Backs the per-course "Review bank" / "Read flags" screen.
class StudentFlagsProvider extends ChangeNotifier {
  final StudentFlagsApi _api;
  /// Null: every course (the Exams area's Review page).
  final int? courseId;

  StudentFlagsProvider({this.courseId, StudentFlagsApi? api})
      : _api = api ?? StudentFlagsApi();

  bool loading = false;
  String? error;
  FlagSettings settings = const FlagSettings();
  List<FlaggedQuestion> review = [];
  List<FlaggedQuestion> read = [];
  double readTotalScore = 0;
  int readTotalWrong = 0;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final r = await Future.wait([
        _api.fetchReview(courseId: courseId),
        _api.fetchRead(courseId: courseId),
      ]);
      final rv = r[0] as ReviewBank;
      final rd = r[1] as ReadBank;
      settings = rv.settings;
      review = rv.items;
      read = rd.items;
      readTotalScore = rd.totalScore;
      readTotalWrong = rd.totalWrong;
    } on ApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = apiErrorText(ApiException.from(e));
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> removeReview(FlaggedQuestion q) async {
    try {
      await _api.removeReview(q.questionId);
      review = review.where((e) => e.questionId != q.questionId).toList();
      notifyListeners();
    } catch (_) {/* keep the item; the user can retry */}
  }
}
