import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';

class EnrolledStudent {
  final int id;
  final String name;
  final String gmail;
  final String? imageUrl;
  final String enrolledAt;
  final String status;
  final double progressPercentage;

  const EnrolledStudent({
    required this.id,
    required this.name,
    required this.gmail,
    this.imageUrl,
    required this.enrolledAt,
    required this.status,
    required this.progressPercentage,
  });

  factory EnrolledStudent.fromJson(Map<String, dynamic> j) => EnrolledStudent(
    id: j['id'] as int,
    name: j['name'] as String,
    gmail: j['gmail'] as String,
    imageUrl: j['image_url'] as String?,
    enrolledAt: j['enrolled_at'] as String,
    status: j['status'] as String,
    progressPercentage:
    (j['progress_percentage'] as num?)?.toDouble() ?? 0.0,
  );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class EnrolledStudentsProvider extends BaseProvider {
  final ApiClient _api;

  EnrolledStudentsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<EnrolledStudent> _all = [];
  String _query = '';

  List<EnrolledStudent> get students {
    if (_query.isEmpty) return List.unmodifiable(_all);
    final q = _query.toLowerCase();
    return _all
        .where((s) =>
    s.name.toLowerCase().contains(q) ||
        s.gmail.toLowerCase().contains(q))
        .toList();
  }

  int get totalCount => _all.length;

  double get avgProgress => _all.isEmpty
      ? 0
      : _all.map((s) => s.progressPercentage).reduce((a, b) => a + b) /
      _all.length;

  int get completedCount =>
      _all.where((s) => s.progressPercentage >= 100).length;

  void setQuery(String q) {
    _query = q;
    notifyListeners();
  }

  Future<void> fetch(int courseId) async {
    final result =
    await run(() => _api.get('/api/v1/courses/$courseId/students'));
    if (result is List) {
      _all = result
          .map((e) => EnrolledStudent.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.progressPercentage.compareTo(a.progressPercentage));
      notifyListeners();
    }
  }
}