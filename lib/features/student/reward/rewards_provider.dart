/// ─────────────────────────────────────────────────────────────────────────────
/// rewards_provider.dart
/// Manages the Rewards / Achievements screen state.
///
/// Data is currently derived from the local enrolled-courses list and a
/// static leaderboard stub; replace the stubs with real API calls when
/// the backend exposes a rewards endpoint.
/// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../models.dart';
// ── Achievement Model ─────────────────────────────────────────────────────────

class AchievementModel {
  final String title;
  final bool   earned;

  const AchievementModel({required this.title, required this.earned});
}

// ── Leaderboard Entry ─────────────────────────────────────────────────────────

class LeaderboardEntry {
  final String name;
  final int    points;
  final int    rank;

  const LeaderboardEntry({
    required this.name,
    required this.points,
    required this.rank,
  });
}

// ── RewardsProvider ───────────────────────────────────────────────────────────

class RewardsProvider extends ChangeNotifier {
  RewardsProvider(){
    _enrolledCourses=[];
  }

  late List<CourseModel> _enrolledCourses;
  bool _showDetail = false;

  // ── Getters ──────────────────────────────────────────────────────────────────

  List<CourseModel> get enrolledCourses => _enrolledCourses;
  bool              get showDetail      => _showDetail;

  /// Total points: 100 per completed course + 50 per in-progress.
  int get totalPoints {
    int pts = 0;
    for (final c in _enrolledCourses) {
      if (c.progress >= 1.0) pts += 100;
      else if (c.progress > 0) pts += 50;
    }
    return pts;
  }

  List<AchievementModel> get achievements => [
        AchievementModel(
          title:  'أعلى درجة في الاختبارات',
          earned: _enrolledCourses.any((c) => c.progress >= 1.0),
        ),
        AchievementModel(
          title:  'أسرع في إكمال الدورة',
          earned: _enrolledCourses.length >= 2,
        ),
        AchievementModel(
          title:  'درجة كاملة في الواجبات',
          earned: _enrolledCourses.any((c) => c.progress >= 0.8),
        ),
        AchievementModel(
          title:  'نشط في المناقشات',
          earned: _enrolledCourses.isNotEmpty,
        ),
      ];

  List<AchievementModel> get tips => const [
        AchievementModel(title: 'سلّم الواجبات مبكراً',  earned: false),
        AchievementModel(title: 'احصل على نقاط إضافية', earned: false),
      ];

  // Stub leaderboard — replace with API call
  List<LeaderboardEntry> get leaderboard => const [
        LeaderboardEntry(name: 'أحمد محمد', points: 985, rank: 1),
        LeaderboardEntry(name: 'سارة علي',  points: 870, rank: 2),
        LeaderboardEntry(name: 'عمر حسن',   points: 760, rank: 3),
      ];

  // ── Navigation within the rewards tab ────────────────────────────────────────

  void openDetail() {
    _showDetail = true;
    notifyListeners();
  }

  void closeDetail() {
    _showDetail = false;
    notifyListeners();
  }
}
