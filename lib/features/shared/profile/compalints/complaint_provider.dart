// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaint_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'complaint_model.dart';

// ── Pending attachment (before upload) ────────────────────────────────────────

class PendingAttachment {
  final XFile file;
  final String localPreviewUrl; // file.path on mobile, blob URL on web

  PendingAttachment({required this.file, required this.localPreviewUrl});
}

// ─────────────────────────────────────────────────────────────────────────────

class ComplaintProvider extends BaseProvider {
  ComplaintProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  // ── Unread badge ──────────────────────────────────────────────────────────
  // Number of complaints that need THIS user's attention (server-side rule:
  // staff → new complaints / follow-ups they have not opened; student →
  // complaints with an unopened reply). Drives the dashboard / tile badges.
  int _count = 0;

  int get count => _count;

  bool _disposed = false;
  int _listRequestId = 0; // lets a newer list request supersede an older one

  @override
  void notifyListeners() {
    if (_disposed) return; // late network replies after the owner was disposed
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Cheap call (single COUNT on the server) — safe to fire-and-forget.
  Future<void> refreshCount() async {
    try {
      final res = await _api.get('/api/v1/complaints/unread-count');
      if (_disposed || res is! Map) return;
      final n = (res['count'] as num?)?.toInt() ?? 0;
      if (n != _count) {
        _count = n;
        notifyListeners();
      }
    } catch (e) {
      log('refreshCount ❌ $e'); // keep the last known number
    }
  }

  // ── State ─────────────────────────────────────────────────────────────────
  List<ComplaintModel> _complaints = [];
  ComplaintModel? _selected;
  ComplaintStats _stats = const ComplaintStats();

  bool isLoadingList = false;
  bool isLoadingDetail = false;
  bool isSending = false;
  bool isUploadingImage = false;
  String? errorMsg;

  // ── Pending attachments (form / reply) ─────────────────────────────────────
  final List<PendingAttachment> _pendingAttachments = [];
  final List<PendingAttachment> _pendingReplyAttachments = [];

  List<PendingAttachment> get pendingAttachments =>
      List.unmodifiable(_pendingAttachments);

  List<PendingAttachment> get pendingReplyAttachments =>
      List.unmodifiable(_pendingReplyAttachments);

  // ── Pagination / filter state ─────────────────────────────────────────────
  // _page = the NEXT page to request (1 after a reset, 2 once page 1 is in …).
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  /// Next page still exists. (`<` skipped the last page: after page N of N the
  /// next page is N+1, which is > N, so `<=` is the right test.)
  bool get hasMore => _page <= _totalPages;

  /// Total rows for the current filters — drives the "Showing X of Y" card.
  int get total => _total;

  /// A page is being APPENDED (first load / reset shows the big spinner instead).
  bool get loadingMore => isLoadingList && _complaints.isNotEmpty;

  ComplaintStatus? _statusFilter;
  ComplaintCategory? _categoryFilter;
  String _search = '';

  // ── Getters ───────────────────────────────────────────────────────────────
  List<ComplaintModel> get complaints => List.unmodifiable(_complaints);

  ComplaintModel? get selected => _selected;

  ComplaintStats get stats => _stats;

  ComplaintStatus? get statusFilter => _statusFilter;

  ComplaintCategory? get categoryFilter => _categoryFilter;

  String get search => _search;

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
    _statusFilter = null;
    _categoryFilter = null;
    _search = '';
    loadComplaints(reset: true);
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  Image picking  (for new complaint form)
  // ══════════════════════════════════════════════════════════════════════════

  static const int _maxImages = 4;
  final _picker = ImagePicker();

  static const List<String> _allowedAttachmentExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
  ];

  /// Converts a file_picker result into a PendingAttachment, working both
  /// on platforms with a real file path and on web (bytes only).
  Future<PendingAttachment?> _pendingFromPlatformFile(PlatformFile f) async {
    // No real file path on web — only read `path` on mobile / desktop.
    final path = kIsWeb ? null : f.path;
    if (path != null) {
      final file = XFile(path, name: f.name);
      return PendingAttachment(file: file, localPreviewUrl: path);
    }
    try {
      // file_picker v12+: bytes come from readAsBytes(), not `withData`.
      final bytes = await f.readAsBytes();
      final file = XFile.fromData(bytes, name: f.name);
      return PendingAttachment(file: file, localPreviewUrl: f.name);
    } catch (_) {
      return null;
    }
  }

  Future<void> pickComplaintImages() async {
    if (_pendingAttachments.length >= _maxImages) return;
    final remaining = _maxImages - _pendingAttachments.length;
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      limit: remaining,
    );
    for (final f in files) {
      _pendingAttachments.add(
        PendingAttachment(file: f, localPreviewUrl: f.path),
      );
    }
    notifyListeners();
  }

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

  /// Browse the device for any image OR a PDF (scanned evidence, receipts,
  /// invoices, etc.) — not limited to the camera roll like the pickers above.
  Future<void> pickComplaintFile() async {
    if (_pendingAttachments.length >= _maxImages) return;
    // file_picker v12+: pickFiles() returns a List (empty if cancelled) and
    // already allows multiple selection.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedAttachmentExtensions,
    );
    if (files.isEmpty) return;

    final remaining = _maxImages - _pendingAttachments.length;
    for (final f in files.take(remaining)) {
      final pending = await _pendingFromPlatformFile(f);
      if (pending != null) _pendingAttachments.add(pending);
    }
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
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      limit: remaining,
    );
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

  /// Same as pickComplaintFile() but for a reply — any image or a PDF.
  Future<void> pickReplyFile() async {
    if (_pendingReplyAttachments.length >= _maxImages) return;
    // file_picker v12+: pickFiles() returns a List (empty if cancelled) and
    // already allows multiple selection.
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedAttachmentExtensions,
    );
    if (files.isEmpty) return;

    final remaining = _maxImages - _pendingReplyAttachments.length;
    for (final f in files.take(remaining)) {
      final pending = await _pendingFromPlatformFile(f);
      if (pending != null) _pendingReplyAttachments.add(pending);
    }
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

  // ══════════════════════════════════════════════════════════════════════════
  //  Upload helpers — use postMultipart (consistent with teacher docs pattern)
  // ══════════════════════════════════════════════════════════════════════════

  Future<Map?> _uploadOne(PendingAttachment pending) async {
    try {
      final bytes = await pending.file.readAsBytes();

      final res = await _api.postMultipart(
        '/api/v1/complaints/upload-attachment',
        fields: {},
        fileField: 'file',
        fileName: pending.file.name,
        fileBytes: bytes,
      );
      if (res != null && res is Map && res['file_url'] != null) {
        return res;
      }
      log('_uploadOne ❌ unexpected response: $res');
    } catch (e) {
      log('_uploadOne ❌ $e');
    }
    return null;
  }

  Future<List<Map>> _uploadAll(List<PendingAttachment> pending) async {
    if (pending.isEmpty) return [];
    isUploadingImage = true;
    notifyListeners();
    final urls = <Map>[];
    try {
      for (final item in pending) {
        final url = await _uploadOne(item);
        if (url != null) urls.add(url);
      }
    } finally {
      isUploadingImage = false;
      notifyListeners();
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
      _totalPages = 1;
      _total = 0;
      _complaints = [];
    } else if (isLoadingList || !hasMore) {
      // Paging: don't start a second request, and stop once the last page is in
      // (the scroll listener used to re-request page N+1 forever).
      return;
    }
    // A reset must win over a request that is still in flight (typing in the
    // search box / changing a filter). The old guard dropped the new request
    // and left the list empty.
    final requestId = ++_listRequestId;
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
      if (requestId != _listRequestId) return; // superseded by a newer request
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
        _page = (res['page'] ?? 1) + 1;
        // Use the server total when it sends one, otherwise estimate from pages.
        _total = (res['total'] as num?)?.toInt() ??
            (hasMore ? _totalPages * 20 : _complaints.length);
      }
    } catch (e) {
      if (requestId == _listRequestId) errorMsg = e.toString();
      log('loadComplaints ❌ $e');
    } finally {
      if (requestId == _listRequestId) {
        isLoadingList = false;
        notifyListeners();
      }
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
        refreshCount(); // opening it marks it read on the server → badge goes down
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
        _count = _stats.unreadAdmin; // role-aware on the server
        notifyListeners();
      }
    } catch (e) {
      log('loadStats ❌ $e');
    }
  }

  // ── Create (uploads images first, then sends all data) ────────────────────
  Future<ComplaintModel?> createComplaint({
    required String title,
    required String description,
    required ComplaintCategory category,
    required ComplaintPriority priority,
    String? courseId,
    String? suggestedSolution, // ← NEW  optional param
    String? targetType,          // general · course · teacher · student · staff · department
    int? targetId,
    String? targetLabel,
  }) async {
    isSending = true;
    notifyListeners();

    try {
      final attachmentUrls = await _uploadAll(_pendingAttachments);
      if (attachmentUrls.length != _pendingAttachments.length) {
        // Some files failed to upload — don't silently send the complaint
        // without them. Keep the picked files so the user can just retry.
        errorMsg = 'upload_failed'; // translation key
        return null;
      }

      // Trim the suggestion; send null if blank so the backend stores NULL.
      final trimmedSuggestion = suggestedSolution?.trim();

      final body = <String, dynamic>{
    'title': title,
    'description': description,
    'category': category.toJson(),
    'priority': priority.toJson(),
    'course_id': ?(courseId == null ? null : int.tryParse(courseId)),
    'target_type': ?targetType,
    'target_id': ?targetId,
    'target_label': ?targetLabel,
    if (attachmentUrls.isNotEmpty) 'attachment_urls': attachmentUrls,
    if (trimmedSuggestion != null && trimmedSuggestion.isNotEmpty)
    'suggested_solution': trimmedSuggestion, // ← NEW
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

  // ── Reply (uploads images first) ──────────────────────────────────────────
  Future<ComplaintReply?> addReply({
    required int complaintId,
    required String message,
    List<String> attachmentUrls = const [],
  }) async {
    isSending = true;
    notifyListeners();

    try {
      final uploadedUrls = await _uploadAll(_pendingReplyAttachments);
      if (uploadedUrls.length != _pendingReplyAttachments.length) {
        errorMsg = 'upload_failed'; // translation key
        return null; // keep staged files for a retry
      }
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
            suggestedSolution: _selected!.suggestedSolution,
            // preserve
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
        await loadDetail(complaintId); // also refreshes the badge
        return true;
      }
    } catch (e) {
      log('updateStatus ❌ $e');
    }
    return false;
  }

  // ── Swipe actions (resolve / close from the list) ─────────────────────────
  //
  // Two steps so the swipe card can play its exit animation BEFORE the list
  // changes: [changeStatusSilently] only calls the API; [applyStatus] updates
  // the list once the card has left the screen.

  Future<bool> changeStatusSilently(int id, ComplaintStatus s) async {
    try {
      final res = await _api.put(
        '/api/v1/complaints/$id',
        body: {'status': s.toJson()},
      );
      return res != null;
    } catch (e) {
      log('changeStatusSilently ❌ $e');
      return false;
    }
  }

  /// Reflect a status change locally: drop the item when it no longer matches
  /// the active status filter, otherwise update it in place. Then re-sync the
  /// stats banner and the unread badge.
  void applyStatus(int id, ComplaintStatus s) {
    final idx = _complaints.indexWhere((c) => c.id == id);
    if (idx != -1) {
      if (_statusFilter != null && _statusFilter != s) {
        _complaints.removeAt(idx);
      } else {
        _complaints[idx] = _withStatus(_complaints[idx], s);
      }
    }
    if (_selected?.id == id) _selected = _withStatus(_selected!, s);
    notifyListeners();
    loadStats(); // also refreshes the badge (stats carries the unread number)
  }

  ComplaintModel _withStatus(ComplaintModel m, ComplaintStatus s) =>
      ComplaintModel(
        id: m.id,
        userId: m.userId,
        userName: m.userName,
        userImage: m.userImage,
        courseId: m.courseId,
        courseTitle: m.courseTitle,
        title: m.title,
        description: m.description,
        suggestedSolution: m.suggestedSolution,
        category: m.category,
        priority: m.priority,
        status: s,
        isReadByAdmin: true, // whoever acted on it has seen it
        isReadByUser: m.isReadByUser,
        createdAt: m.createdAt,
        updatedAt: DateTime.now(),
        resolvedAt: s == ComplaintStatus.resolved ? DateTime.now() : m.resolvedAt,
        repliesCount: m.repliesCount,
        replies: m.replies,
        attachments: m.attachments,
      );

  void clearSelected() {
    _selected = null;
    notifyListeners();
  }
}