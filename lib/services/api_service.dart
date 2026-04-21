/// Main API service for making HTTP requests to backend.
/// Handles authentication, error handling, and request/response processing.
library;

import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../config/storage_service.dart';

class ApiService {
  late Dio _dio;
  final StorageService _storage;

  ApiService(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiV1,
      connectTimeout: const Duration(milliseconds: AppConfig.connectionTimeout),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Add interceptor for authentication
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = _storage.accessToken;
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) {
        // Handle errors globally
        return handler.next(error);
      },
    ));
    _dio.interceptors
        .add(LogInterceptor(requestBody: true, responseBody: true));
  }

  // ========== Authentication ==========

  /// Login user
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post(
      '/auth/login',
      data: json.encode({'email': username, 'password': password}),
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data;
  }

  /// Register new user
  Future<Map<String, dynamic>> register({
    required String email,
    required String phone,
    required String dob,
    required String password,
    String? fullName,
    String role = 'student',
  }) async {
    final response = await _dio.post(
      '/auth/register',
      data: {
        'email': email,
        'phone': phone,
        'dob': dob,
        'password': password,
        'country': 'sar',
        'name': fullName,
        'role': role,
      },
    );
    return response.data;
  }

  /// Register new teacher
  Future<Map<String, dynamic>> registerTeacher({
    required String experience,
    required String specialization,
    required String paymentType,
    required String teachingType,
  }) async {
    final response = await _dio.post(
      '/auth/register_teacher',
      data: {
        'experience': experience,
        'specialization': specialization,
        'payment_type': paymentType,
        'teaching_type': teachingType,
      },
    );
    return response.data;
  }

  /// Get current user information
  Future<Map<String, dynamic>> getCurrentUser() async {
    final response = await _dio.get(
      '/auth/me',
      options: Options(contentType: Headers.jsonContentType),
    );
    return response.data;
  }

  // ========== Courses ==========

  /// Get list of courses
  Future<List<dynamic>> getCourses({int skip = 0, int limit = 20}) async {
    final response = await _dio.get(
      '/courses',
      queryParameters: {'skip': skip, 'limit': limit},
    );
    return response.data as List<dynamic>;
  }

  /// Get course by ID
  Future<Map<String, dynamic>> getCourse(int courseId) async {
    final response = await _dio.get('/courses/$courseId');
    return response.data;
  }

  /// Create new course (instructor only)
  Future<Map<String, dynamic>> createCourse({
    required String title,
    required String description,
    required double price,
  }) async {
    final response = await _dio.post(
      '/courses',
      data: {
        'name': title,
        'description': description,
        'fees': price,
      },
    );
    return response.data;
  }

  /// Enroll in course
  Future<void> enrollCourse(int courseId, int userId) async {
    await _dio.post('/courses/enroll',
        data: {'course_id': courseId, 'user_id': userId});
  }

  /// Get user's enrolled courses
  Future<List<dynamic>> getMyCourses() async {
    final response = await _dio.get('/courses/my-courses');
    return response.data as List<dynamic>;
  }

  // ========== Modules ==========

  /// Get modules for a course
  Future<List<dynamic>> getModules(int courseId) async {
    final response =
        await _dio.get('/modules', queryParameters: {'course_id': courseId});
    return response.data as List<dynamic>;
  }

  /// Create new module (instructor only)
  Future<Map<String, dynamic>> createModule({
    required int courseId,
    required String title,
    String? description,
    int order = 0,
  }) async {
    final response = await _dio.post(
      '/modules',
      data: {
        'course_id': courseId,
        'title': title,
        'description': description,
        'order': order,
      },
    );
    return response.data;
  }

  /// Update module (instructor only)
  Future<Map<String, dynamic>> updateModule({
    required int moduleId,
    String? title,
    String? description,
    int? order,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (order != null) data['order'] = order;

    final response = await _dio.put('/modules/$moduleId', data: data);
    return response.data;
  }

  /// Delete module (instructor only)
  Future<void> deleteModule(int moduleId) async {
    await _dio.delete('/modules/$moduleId');
  }

  // ========== Lessons ==========

  /// Get lessons for a module
  Future<List<dynamic>> getLessons(int courseId) async {
    final response = await _dio.get(
      '/lessons',
      queryParameters: {
        'course_id': courseId,
      },
    );
    return response.data as List<dynamic>;
  }

  /// Get lesson by ID
  Future<Map<String, dynamic>> getLesson(int lessonId) async {
    final response = await _dio.get('/lessons/$lessonId');
    return response.data;
  }

  /// Create new lesson (instructor only)
  Future<Map<String, dynamic>> createLesson({
    required int courseId,
    int? moduleId,
    required String title,
    String? description,
    int order = 0,
  }) async {
    final response = await _dio.post(
      '/lessons',
      data: {
        'course_id': courseId,
        'module_id': moduleId,
        'title': title,
        'description': description ?? '',
        'order': order,
      },
    );
    return response.data;
  }

  /// Upload video or file for lesson (supports videos, PDFs, documents)
  Future<Map<String, dynamic>> uploadVideo(
    int lessonId,
    String filePath, {
    Function(int, int)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });

    final response = await _dio.post(
      '/lessons/$lessonId/upload-video',
      data: formData,
      onSendProgress: onProgress,
    );
    return response.data;
  }

  /// Update lesson (instructor only)
  Future<Map<String, dynamic>> updateLesson({
    required int lessonId,
    String? title,
    String? description,
    int? order,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (order != null) data['order'] = order;

    final response = await _dio.put('/lessons/$lessonId', data: data);
    return response.data;
  }

  /// Delete lesson (instructor only)
  Future<void> deleteLesson(int lessonId) async {
    await _dio.delete('/lessons/$lessonId');
  }

  // ========== Video Progress ==========

  /// Update video watch progress
  Future<Map<String, dynamic>> updateVideoProgress(
    int lessonId,
    int watchedDuration,
    bool completed,
  ) async {
    final response = await _dio.post(
      '/lessons/$lessonId/progress',
      data: {
        'watched_duration': watchedDuration,
        'completed': completed,
      },
    );
    return response.data;
  }

  /// Get video progress
  Future<Map<String, dynamic>?> getVideoProgress(int lessonId) async {
    try {
      final response = await _dio.get('/lessons/$lessonId/progress');
      return response.data;
    } catch (e) {
      return null; // No progress found
    }
  }

  // ========== Live Sessions ==========

  /// Get live sessions for a course
  Future<List<dynamic>> getLiveSessions(
    int courseId, {
    bool includePast = false,
  }) async {
    final response = await _dio.get(
      '/live-sessions',
      queryParameters: {
        'include_past': includePast,
        'course_id': courseId,
      },
    );
    return response.data as List<dynamic>;
  }

  /// Get live session by ID
  Future<Map<String, dynamic>> getLiveSession(int sessionId) async {
    final response = await _dio.get('/live-sessions/$sessionId');
    return response.data;
  }

  /// Create new live session (instructor only)
  /// Supports both Zoom and Google Meet platforms
  Future<Map<String, dynamic>> createLiveSession({
    required int courseId,
    required String title,
    String? description,
    required String platform, // 'zoom' or 'google_meet'
    required DateTime scheduledAt,
    int duration = 60,
  }) async {
    final response = await _dio.post(
      '/live-sessions',
      data: {
        'course_id': courseId,
        'title': title,
        'description': description,
        'platform': platform,
        'scheduled_at': scheduledAt.toIso8601String(),
        'duration': duration,
      },
    );
    return response.data;
  }

  /// Start live session (instructor only)
  Future<Map<String, dynamic>> startLiveSession(int sessionId) async {
    final response = await _dio.post('/live-sessions/$sessionId/start');
    return response.data;
  }

  /// Join live session
  Future<dynamic> joinLiveSession(int sessionId) async {
    final response = await _dio.post('/live-sessions/$sessionId/join');
    log("==============================");
    log(response.data.toString());
    log("==============================");
    return response.data;
  }

  /// Leave live session
  Future<void> leaveLiveSession(int sessionId, int watchDuration) async {
    await _dio.post(
      '/live-sessions/$sessionId/leave',
      data: {'watch_duration': watchDuration},
    );
  }

  /// End live session (instructor only)
  Future<Map<String, dynamic>> endLiveSession(int sessionId) async {
    final response = await _dio.post('/live-sessions/$sessionId/end');
    return response.data;
  }

  /// Update live session (instructor only)
  Future<Map<String, dynamic>> updateLiveSession({
    required int sessionId,
    String? title,
    String? description,
    DateTime? scheduledAt,
    int? duration,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (scheduledAt != null) {
      data['scheduled_at'] = scheduledAt.toIso8601String();
    }
    if (duration != null) data['duration'] = duration;

    final response = await _dio.put('/live-sessions/$sessionId', data: data);
    return response.data;
  }

  /// Delete live session (instructor only)
  Future<void> deleteLiveSession(int sessionId) async {
    await _dio.delete('/live-sessions/$sessionId');
  }

  // ========== Assignments ==========

  /// Get assignments for a course
  Future<List<dynamic>> getAssignments(int courseId) async {
    final response = await _dio.get(
      '/assignments',
      queryParameters: {'course_id': courseId},
    );
    return response.data as List<dynamic>;
  }

  /// Get assignment by ID
  Future<Map<String, dynamic>> getAssignment(int assignmentId) async {
    final response = await _dio.get('/assignments/$assignmentId');
    return response.data;
  }

  /// Submit assignment
  Future<Map<String, dynamic>> submitAssignment({
    required int assignmentId,
    required String filePath,
    String? comments,
    Function(int, int)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
      if (comments != null) 'comments': comments,
    });

    final response = await _dio.post(
      '/assignments/$assignmentId/submit',
      data: formData,
      onSendProgress: onProgress,
    );
    return response.data;
  }

  // ========== Quizzes ==========

  /// Get quizzes for a course
  Future<List<dynamic>> getQuizzes(int courseId) async {
    final response = await _dio.get(
      '/quizzes',
      queryParameters: {'course_id': courseId},
    );
    return response.data as List<dynamic>;
  }

  /// Get quiz by ID
  Future<Map<String, dynamic>> getQuiz(int quizId) async {
    final response = await _dio.get('/quizzes/$quizId');
    return response.data;
  }

  /// Submit quiz answers
  Future<Map<String, dynamic>> submitQuiz({
    required int quizId,
    required Map<String, dynamic> answers,
  }) async {
    final response = await _dio.post(
      '/quizzes/$quizId/submit',
      data: answers,
    );
    return response.data;
  }

  // ========== Notifications ==========

  /// Get user notifications
  Future<List<dynamic>> getNotifications({
    bool unreadOnly = false,
    int skip = 0,
    int limit = 20,
  }) async {
    final response = await _dio.get(
      '/notifications',
      queryParameters: {
        'unread_only': unreadOnly,
        'skip': skip,
        'limit': limit,
      },
    );
    return response.data as List<dynamic>;
  }

  /// Mark notification as read
  Future<void> markNotificationRead(int notificationId) async {
    await _dio.put('/notifications/$notificationId/read');
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsRead() async {
    await _dio.put('/notifications/read-all');
  }

  // ========== File Downloads ==========

  /// Download file from URL
  Future<void> downloadFile({
    required String url,
    required String savePath,
    Function(int, int)? onProgress,
  }) async {
    await _dio.download(
      url,
      savePath,
      onReceiveProgress: onProgress,
    );
  }
}
