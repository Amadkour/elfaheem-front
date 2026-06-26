// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaint_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import 'complaint_model.dart';

// ── Pending attachment (before upload) ────────────────────────────────────────

class PendingAttachment {
  final XFile file;
  final String localPreviewUrl; // file.path on mobile, object-URL on web

  PendingAttachment({required this.file, required this.localPreviewUrl});
}

// ── Upload result ──────────────────────────────────────────────────────────────

class _UploadResult {
  final String fileUrl;
  final String fileName;
  final String fileType;
  final int fileSize;

  _UploadResult({
    required this.fileUrl,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
  });

  factory _UploadResult.fromJson(Map<String, dynamic> j) => _UploadResult(
    fileUrl: j['file_url'] as String,
    fileName: j['file_name'] as String,
    fileType: j['file_type'] as String,
    fileSize: j['file_size'] as int,
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class ComplaintProvider extends BaseProvider {
  ComplaintProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  // ── State ─────────────────────────────────────────────────────────────────
  List<ComplaintModel> _complaints = [];
  ComplaintModel? _selected;
  ComplaintStats _stats = const ComplaintStats();

  bool isLoadingList    = false;
  bool isLoadingDetail  = false;
  bool isSending        = false;
  bool isUploadingImage = false;
  String? errorMsg;

  // ── Pending attachments (form/reply) ──────────────────────────────────────
  final List<PendingAttachment> _pendingAttachments = [];
  final List<PendingAttachment> _pendingReplyAttachments = [];

  List<PendingAttachment> get pendingAttachments =>
      List.unmodifiable(_pendingAttachments);
  List<PendingAttachment> get pendingReplyAttachments =>
      List.unmodifiable(_pendingReplyAttachments);

  // ── Pagination / filter state ─────────────────────────────────────────────
  int _page       = 1;
  int _totalPages = 1;
  bool get hasMore => _page < _totalPages;

  ComplaintStatus?   _statusFilter;
  ComplaintCategory? _categoryFilter;
  String _search = '';

  // ── Getters ───────────────────────────────────────────────────────────────
  List<ComplaintModel> get complaints => List.unmodifiable(_complaints);
  ComplaintModel?      get selected   => _selected;
  ComplaintStats       get stats      => _stats;

  ComplaintStatus?   get statusFilter   => _statusFilter;
  ComplaintCategory? get categoryFilter => _categoryFilter;
  String             get search         => _search;

  // ── Filter helpers ────────────────────────────────────────────────────────
  void setStatusFilter(ComplaintStatus? v) {
    _statusFilter = v;
    loadComplaints(reset: true);
  }

  void setCategoryFilter(ComplaintCategory? v) {
    _categoryFilter = v;
    loadComplaints(reset: true);
  }

  void setSearch(String v) {
    _search = v;
    loadComplaints(reset: true);
  }

  void clearFilters() {
    _statusFilter   = null;
    _categoryFilter = null;
    _search         = '';
    loadComplaints(reset: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Image picking & uploading
  // ══════════════════════════════════════════════════════════════════════════

  static const int _maxImages = 4;
  final _picker = ImagePicker();

  /// Pick image(s) from gallery for the NEW COMPLAINT form.
  Future<void> pickComplaintImages() async {
    if (_pendingAttachments.length >= _maxImages) return;
    final remaining = _maxImages - _pendingAttachments.length;
    final files = await _picker.pickMultiImage(imageQuality: 85, limit: remaining);
    for (final f in files) {
      _pendingAttachments.add(
        PendingAttachment(file: f, localPreviewUrl: f.path),
      );
    }
    notifyListeners();
  }

  /// Pick a single image from camera for the NEW COMPLAINT form.
  Future<void> pickComplaintImageFromCamera() async {
    if (_pendingAttachments.length >= _maxImages) return;
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (f == null) return;
    _pendingAttachments.add(
      PendingAttachment(file: f, localPreviewUrl: f.path),
    );
    notifyListeners();
  }

  void removeComplaintImage(int index) {
    if (index < 0 || index >= _pendingAttachments.length) return;
    _pendingAttachments.removeAt(index);
    notifyListeners();
  }

  void clearComplaintImages() {
    _pendingAttachments.clear();
    notifyListeners();
  }

  // ── Reply images ──────────────────────────────────────────────────────────

  Future<void> pickReplyImage() async {
    if (_pendingReplyAttachments.length >= _maxImages) return;
    final remaining = _maxImages - _pendingReplyAttachments.length;
    final files = await _picker.pickMultiImage(imageQuality: 85, limit: remaining);
    for (final f in files) {
      _pendingReplyAttachments.add(
        PendingAttachment(file: f, localPreviewUrl: f.path),
      );
    }
    notifyListeners();
  }

  Future<void> pickReplyImageFromCamera() async {
    if (_pendingReplyAttachments.length >= _maxImages) return;
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (f == null) return;
    _pendingReplyAttachments.add(
      PendingAttachment(file: f, localPreviewUrl: f.path),
    );
    notifyListeners();
  }

  void removeReplyImage(int index) {
    if (index < 0 || index >= _pendingReplyAttachments.length) return;
    _pendingReplyAttachments.removeAt(index);
    notifyListeners();
  }

  void clearReplyImages() {
    _pendingReplyAttachments.clear();
    notifyListeners();
  }

  // ── Core upload helper ────────────────────────────────────────────────────

  Future<_UploadResult?> _uploadSingle(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final mime  = lookupMimeType(xfile.name, headerBytes: bytes) ?? 'image/jpeg';
      final parts = mime.split('/');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${_api.baseUrl}/api/v1/complaints/upload-attachment'),
      );
      request.headers.addAll(await _api.authHeaders());
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: xfile.name,
          contentType: MediaType(parts[0], parts[1]),
        ),
      );

      final streamed = await request.send();
      final body     = await streamed.stream.bytesToString();

      if (streamed.statusCode == 201) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        return _UploadResult.fromJson(json);
      } else {
        log('_uploadSingle ❌ ${streamed.statusCode}: $body');
      }
    } catch (e) {
      log('_uploadSingle exception ❌ $e');
    }
    return null;
  }

  /// Upload all pending complaint attachments and return their URLs.
  Future<List<String>> _uploadPendingComplaintImages() async {
    final urls = <String>[];
    for (final pending in _pendingAttachments) {
      final result = await _uploadSingle(pending.file);
      if (result != null) urls.add(result.fileUrl);
    }
    return urls;
  }

  /// Upload all pending reply attachments and return their URLs.
  Future<List<String>> _uploadPendingReplyImages() async {
    final urls = <String>[];
    for (final pending in _pendingReplyAttachments) {
      final result = await _uploadSingle(pending.file);
      if (result != null) urls.add(result.fileUrl);
    }
    return urls;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  CRUD
  // ══════════════════════════════════════════════════════════════════════════

  // ── Load list ─────────────────────────────────────────────────────────────
  Future<void> loadComplaints({bool reset = false}) async {
    if (reset) {
      _page = 1;
      _complaints = [];
    }

    if (isLoadingList) return;
    isLoadingList = true;
    errorMsg = null;
    notifyListeners();

    try {
      final params = <String, dynamic>{
        'page': _page,
        'per_page': 20,
        if (_statusFilter != null) 'status': _statusFilter!.toJson(),
        if (_categoryFilter != null) 'category': _categoryFilter!.toJson(),
        if (_search.isNotEmpty) 'search': _search,
      };

      final res = await _api.get('/api/v1/complaints', queryParams: params);

      if (res != null && res is Map) {
        final items = (res['items'] as List? ?? [])
            .map((j) => ComplaintModel.fromJson(j as Map<String, dynamic>))
            .toList();

        if (reset) {
          _complaints = items;
        } else {
          _complaints = [..._complaints, ...items];
        }
        _totalPages = res['pages'] ?? 1;
        _page       = (res['page'] ?? 1) + 1;
      }
    } catch (e) {
      errorMsg = e.toString();
      log('loadComplaints ❌ $e');
    } finally {
      isLoadingList = false;
      notifyListeners();
    }
  }

  // ── Load detail ───────────────────────────────────────────────────────────
  Future<void> loadDetail(int id) async {
    isLoadingDetail = true;
    _selected = null;
    notifyListeners();

    try {
      final res = await _api.get('/api/v1/complaints/$id');
      if (res != null && res is Map) {
        _selected = ComplaintModel.fromJson(res as Map<String, dynamic>);
        final idx = _complaints.indexWhere((c) => c.id == id);
        if (idx != -1) _complaints[idx] = _selected!;
      }
    } catch (e) {
      log('loadDetail ❌ $e');
    } finally {
      isLoadingDetail = false;
      notifyListeners();
    }
  }

  // ── Load stats ────────────────────────────────────────────────────────────
  Future<void> loadStats() async {
    try {
      final res = await _api.get('/api/v1/complaints/stats');
      if (res != null && res is Map) {
        _stats = ComplaintStats.fromJson(res as Map<String, dynamic>);
        notifyListeners();
      }
    } catch (e) {
      log('loadStats ❌ $e');
    }
  }

  // ── Create (with optional image attachments) ──────────────────────────────
  Future<ComplaintModel?> createComplaint({
    required String title,
    required String description,
    required ComplaintCategory category,
    required ComplaintPriority priority,
    String? courseId,
  }) async {
    isSending = true;
    notifyListeners();

    try {
      // 1. Upload any pending images first
      final attachmentUrls = await _uploadPendingComplaintImages();

      // 2. Create complaint
      final body = <String, dynamic>{
        'title': title,
        'description': description,
        'category': category.toJson(),
        'priority': priority.toJson(),
        if (courseId != null) 'course_id': courseId,
        if (attachmentUrls.isNotEmpty) 'attachment_urls': attachmentUrls,
      };

      final res = await _api.post('/api/v1/complaints', body: body);
      if (res != null && res is Map) {
        final complaint = ComplaintModel.fromJson(res as Map<String, dynamic>);
        _complaints.insert(0, complaint);
        _stats = ComplaintStats(
          total: _stats.total + 1,
          open: _stats.open + 1,
          inProgress: _stats.inProgress,
          resolved: _stats.resolved,
          closed: _stats.closed,
          unreadAdmin: _stats.unreadAdmin + 1,
        );
        _pendingAttachments.clear();
        isSending = false;
        notifyListeners();
        return complaint;
      }
    } catch (e) {
      log('createComplaint ❌ $e');
    } finally {
      isSending = false;
      notifyListeners();
    }
    return null;
  }

  // ── Reply (with optional image attachments) ───────────────────────────────
  Future<ComplaintReply?> addReply({
    required int complaintId,
    required String message,
    List<String> attachmentUrls = const [],
  }) async {
    isSending = true;
    notifyListeners();

    try {
      // Upload any pending reply images
      final uploadedUrls = await _uploadPendingReplyImages();
      final allUrls = [...attachmentUrls, ...uploadedUrls];

      final res = await _api.post(
        '/api/v1/complaints/$complaintId/replies',
        body: {'message': message, 'attachment_urls': allUrls},
      );

      if (res != null && res is Map) {
        final reply = ComplaintReply.fromJson(res as Map<String, dynamic>);
        if (_selected?.id == complaintId) {
          _selected = ComplaintModel(
            id: _selected!.id,
            userId: _selected!.userId,
            userName: _selected!.userName,
            userImage: _selected!.userImage,
            courseId: _selected!.courseId,
            courseTitle: _selected!.courseTitle,
            title: _selected!.title,
            description: _selected!.description,
            category: _selected!.category,
            priority: _selected!.priority,
            status: _selected!.status,
            isReadByAdmin: _selected!.isReadByAdmin,
            isReadByUser: _selected!.isReadByUser,
            createdAt: _selected!.createdAt,
            updatedAt: DateTime.now(),
            resolvedAt: _selected!.resolvedAt,
            repliesCount: _selected!.repliesCount + 1,
            replies: [..._selected!.replies, reply],
            attachments: _selected!.attachments,
          );
        }
        _pendingReplyAttachments.clear();
        isSending = false;
        notifyListeners();
        return reply;
      }
    } catch (e) {
      log('addReply ❌ $e');
    } finally {
      isSending = false;
      notifyListeners();
    }
    return null;
  }

  // ── Update status (admin / teacher) ───────────────────────────────────────
  Future<bool> updateStatus(int complaintId, ComplaintStatus newStatus) async {
    try {
      final res = await _api.put(
        '/api/v1/complaints/$complaintId',
        body: {'status': newStatus.toJson()},
      );
      if (res != null) {
        await loadDetail(complaintId);
        return true;
      }
    } catch (e) {
      log('updateStatus ❌ $e');
    }
    return false;
  }

  void clearSelected() {
    _selected = null;
    notifyListeners();
  }
}