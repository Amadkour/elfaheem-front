import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/services/storage_service.dart';
import '../config/storage_service.dart';
import '../models/course.dart';
import '../services/api_service.dart';

class CourseProvider with ChangeNotifier {
  ApiService? _apiService;

  List<Course> _courses = [];
  List<Course> _myCourses = [];
  bool _isLoading = false;
  String? _errorMessage;

  CourseProvider(this._apiService) {
    if (_apiService == null) {
      getApiService();
    }
  }
 getApiService() async {
   StorageService storageService=await StorageService.getInstance();
   _apiService=ApiService(storageService );
 }
  // Getters
  List<Course> get courses => _courses;
  List<Course> get myCourses => _myCourses;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Fetch all courses
  Future<void> fetchCourses({int skip = 0, int limit = 20}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService!.getCourses(skip: skip, limit: limit);
      _courses = response.map((json) => Course.fromJson(json)).toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load courses: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch user's enrolled courses
  Future<void> fetchMyCourses() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService!.getMyCourses();
      _myCourses = response.map((json) => Course.fromJson(json)).toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to load your courses: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get course by ID
  Future<Course?> getCourse(int courseId) async {
    try {
      final response = await _apiService!.getCourse(courseId);
      return Course.fromJson(response);
    } catch (e) {
      _errorMessage = 'Failed to load course: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  /// Create new course (instructor only)
  Future<Course?> createCourse({
    required String title,
    required String description,
    required double price,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiService!.createCourse(
        title: title,
        description: description,
        price: price,
      );
      final course = Course.fromJson(response);
      _courses.insert(0, course);
      _isLoading = false;
      notifyListeners();
      return course;
    } catch (e) {
      _errorMessage = 'Failed to create course: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Enroll in a course
  Future<bool> enrollCourse(int courseId,userId) async {
    try {
      await _apiService!.enrollCourse(courseId,userId);
      await fetchMyCourses();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to enroll: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Check if user is enrolled in course
  bool isEnrolled(int courseId) {
    return _myCourses.any((course) => course.id == courseId);
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
