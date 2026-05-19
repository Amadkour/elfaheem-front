// ─────────────────────────────────────────────────────────────────────────────
// features/shared/complaints/complaint_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';

import 'complaint_model.dart';

class ComplaintProvider extends BaseProvider {
  ComplaintProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  // ── State ─────────────────────────────────────────────────────────────────
  List<ComplaintModel> _complaints = [];
  ComplaintModel? _selected;
  ComplaintStats _stats = const ComplaintStats();

  bool isLoadingList  = false;
  bool isLoadingDetail = false;
  bool isSending      = false;
  String? errorMsg;

  int _page       = 1;
  int _totalPages = 1;
  bool get hasMore => _page < _totalPages;

  ComplaintStatus? _statusFilter;
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
        // Update item in list if present
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

  // ── Create ────────────────────────────────────────────────────────────────
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
      final body = <String, dynamic>{
        'title': title,
        'description': description,
        'category': category.toJson(),
        'priority': priority.toJson(),
        if (courseId != null) 'course_id': courseId,
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

  // ── Reply ─────────────────────────────────────────────────────────────────
  Future<ComplaintReply?> addReply({
    required int complaintId,
    required String message,
    List<String> attachmentUrls = const [],
  }) async {
    isSending = true;
    notifyListeners();

    try {
      final res = await _api.post(
        '/api/v1/complaints/$complaintId/replies',
        body: {'message': message, 'attachment_urls': attachmentUrls},
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
