import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// API Service for lesson management
class LessonApiService {
  final String baseUrl;
  final String? authToken;

  LessonApiService({
    required this.baseUrl,
    this.authToken,
  });

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  /// Create a new lesson
  Future<LessonCreateResponse> createLesson({
    required int moduleId,
    required String title,
    String? description,
    int order = 0,
  }) async {
    final url = Uri.parse('$baseUrl/lessons');

    final request = http.MultipartRequest('POST', url);

    // Add authentication header
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }

    // Add form fields
    request.fields['module_id'] = moduleId.toString();
    request.fields['title'] = title;
    if (description != null && description.isNotEmpty) {
      request.fields['description'] = description;
    }
    request.fields['order'] = order.toString();

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 201) {
      final data = json.decode(responseBody);
      return LessonCreateResponse.fromJson(data);
    } else {
      throw LessonApiException(
        statusCode: response.statusCode,
        message: responseBody,
      );
    }
  }

  /// Upload video or file for a lesson
  Future<VideoUploadResponse> uploadVideo({
    required int lessonId,
    required File file,
    required String fileName,
    Function(double)? onProgress,
  }) async {
    final url = Uri.parse('$baseUrl/lessons/$lessonId/upload-video');

    final request = http.MultipartRequest('POST', url);

    // Add authentication header
    if (authToken != null) {
      request.headers['Authorization'] = 'Bearer $authToken';
    }

    // Add file
    final fileStream = http.ByteStream(file.openRead());
    final fileLength = await file.length();

    request.files.add(
      http.MultipartFile(
        'file',
        fileStream,
        fileLength,
        filename: fileName,
      ),
    );

    // Send request
    final streamedResponse = await request.send();

    // Track progress if callback provided
    if (onProgress != null) {
      int bytesReceived = 0;
      streamedResponse.stream.listen(
            (chunk) {
          bytesReceived += chunk.length;
          onProgress(bytesReceived / fileLength);
        },
      );
    }

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return VideoUploadResponse.fromJson(data);
    } else {
      throw LessonApiException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }

  /// Get lesson details
  Future<LessonResponse> getLesson(int lessonId) async {
    final url = Uri.parse('$baseUrl/lessons/$lessonId');

    final response = await http.get(url, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return LessonResponse.fromJson(data);
    } else {
      throw LessonApiException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }

  /// Update video progress
  Future<VideoProgressResponse> updateProgress({
    required int lessonId,
    required int watchedDuration,
    required bool completed,
  }) async {
    final url = Uri.parse('$baseUrl/lessons/$lessonId/progress');

    final response = await http.post(
      url,
      headers: _headers,
      body: json.encode({
        'watched_duration': watchedDuration,
        'completed': completed,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return VideoProgressResponse.fromJson(data);
    } else {
      throw LessonApiException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }

  /// Get video progress
  Future<VideoProgressResponse> getProgress(int lessonId) async {
    final url = Uri.parse('$baseUrl/lessons/$lessonId/progress');

    final response = await http.get(url, headers: _headers);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return VideoProgressResponse.fromJson(data);
    } else if (response.statusCode == 404) {
      // No progress found, return default
      return VideoProgressResponse(
        id: 0,
        userId: 0,
        lessonId: lessonId,
        watchedDuration: 0,
        completed: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } else {
      throw LessonApiException(
        statusCode: response.statusCode,
        message: response.body,
      );
    }
  }
}

// Models

class LessonCreateResponse {
  final int id;
  final String title;
  final String? description;
  final int moduleId;
  final int order;
  final String? videoUrl;
  final String? videoKey;
  final int? fileSize;
  final DateTime createdAt;
  final DateTime updatedAt;

  LessonCreateResponse({
    required this.id,
    required this.title,
    this.description,
    required this.moduleId,
    required this.order,
    this.videoUrl,
    this.videoKey,
    this.fileSize,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LessonCreateResponse.fromJson(Map<String, dynamic> json) {
    return LessonCreateResponse(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      moduleId: json['module_id'],
      order: json['order'],
      videoUrl: json['video_url'],
      videoKey: json['video_key'],
      fileSize: json['file_size'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class VideoUploadResponse {
  final String message;
  final String videoUrl;
  final int fileSize;

  VideoUploadResponse({
    required this.message,
    required this.videoUrl,
    required this.fileSize,
  });

  factory VideoUploadResponse.fromJson(Map<String, dynamic> json) {
    return VideoUploadResponse(
      message: json['message'],
      videoUrl: json['video_url'],
      fileSize: json['file_size'],
    );
  }
}

class LessonResponse {
  final int id;
  final String title;
  final String? description;
  final int moduleId;
  final int order;
  final String? videoUrl;
  final String? videoKey;
  final int? fileSize;
  final DateTime createdAt;
  final DateTime updatedAt;

  LessonResponse({
    required this.id,
    required this.title,
    this.description,
    required this.moduleId,
    required this.order,
    this.videoUrl,
    this.videoKey,
    this.fileSize,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LessonResponse.fromJson(Map<String, dynamic> json) {
    return LessonResponse(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      moduleId: json['module_id'],
      order: json['order'],
      videoUrl: json['video_url'],
      videoKey: json['video_key'],
      fileSize: json['file_size'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class VideoProgressResponse {
  final int id;
  final int userId;
  final int lessonId;
  final int watchedDuration;
  final bool completed;
  final DateTime createdAt;
  final DateTime updatedAt;

  VideoProgressResponse({
    required this.id,
    required this.userId,
    required this.lessonId,
    required this.watchedDuration,
    required this.completed,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VideoProgressResponse.fromJson(Map<String, dynamic> json) {
    return VideoProgressResponse(
      id: json['id'],
      userId: json['user_id'],
      lessonId: json['lesson_id'],
      watchedDuration: json['watched_duration'],
      completed: json['completed'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class LessonApiException implements Exception {
  final int statusCode;
  final String message;

  LessonApiException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() => 'LessonApiException: $statusCode - $message';
}