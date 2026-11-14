// ─────────────────────────────────────────────────────────────────────────────
// features/auth/teacher_documents/teacher_document_provider.dart
// ─────────────────────────────────────────────────────────────────────────────

import 'teacher_onboarding_token.dart';
import 'dart:developer';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'teacher_document_model.dart';

// File extensions accepted for a document: any common image format or PDF.
const List<String> kDocumentAllowedExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'pdf',
];

class TeacherDocumentProvider extends BaseProvider {
  TeacherDocumentProvider({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;
  final _picker = ImagePicker();

  // ── State ─────────────────────────────────────────────────────────────────
  TeacherDocumentsOverview? _overview;

  TeacherDocumentsOverview? get overview => _overview;

  bool isLoadingOverview = false;
  bool isLoadingTypes = false;

  // Per-slot upload tracking: typeId (or -1 for custom index) → loading flag
  final Map<String, bool> _uploading = {};

  bool isUploadingFor(String key) => _uploading[key] ?? false;

  // Custom document form state — keyed by a local UUID string
  final List<_CustomDocEntry> _customEntries = [];

  List<_CustomDocEntry> get customEntries => List.unmodifiable(_customEntries);

  // Public documents (for profile page — approved-only)
  List<TeacherDocumentModel> _publicDocs = [];

  List<TeacherDocumentModel> get publicDocs => List.unmodifiable(_publicDocs);
  bool isLoadingPublic = false;

  // Last error message (upload rejected, finalize blocked, etc.)
  @override
  String? errorMessage;

  bool isFinalizing = false;
  bool isFinalized = false;

  // ── Load teacher's own overview ──────────────────────────────────────────
  // POST /teacher-documents/overview {email}. The server identifies the teacher from the onboarding token
  // (`X-Onboarding-Token`, during registration) or the access token (a logged-in teacher); `email` must be that
  // same account (403 onboarding_user_mismatch otherwise). Not POST /teacher-documents: that one creates a document.
  Future<void> loadOverview(String email) async {
    isLoadingOverview = true;
    notifyListeners();

    try {
      final res = await _api.post(
        '/api/v1/auth/teacher-documents/overview',
        body: {'email': email},
        headers: TeacherOnboardingToken.headers,
      );
      if (res != null && res is Map) {
        _overview = TeacherDocumentsOverview.fromJson(
          res as Map<String, dynamic>,
        );
      }
    } catch (e) {
      log('loadOverview ❌ $e');
    } finally {
      isLoadingOverview = false;
      notifyListeners();
    }
  }

  // ── Load public docs (profile page) ──────────────────────────────────────
  Future<void> loadPublicDocuments(int teacherUserId) async {
    isLoadingPublic = true;
    notifyListeners();
    try {
      final res = await _api.get(
        '/api/v1/auth/teacher-documents/$teacherUserId/public',
      );
      if (res != null && res is List) {
        _publicDocs = (res)
            .map(
              (e) => TeacherDocumentModel.fromJson(e as Map<String, dynamic>),
        )
            .toList();
      }
    } catch (e) {
      log('loadPublicDocuments ❌ $e');
    } finally {
      isLoadingPublic = false;
      notifyListeners();
    }
  }

  // ── Shared: upload raw bytes, then attach the returned file_url ───────────
  // Step 1: POST .../upload-attachment (multipart) -> {file_url, ...}
  // Step 2: POST .../                  (JSON)      -> creates/replaces the doc row
  // Mirrors ComplaintProvider._uploadOne + createComplaint's attachment_urls
  // pattern, so both features go through the same upload-then-attach shape.
  Future<bool> _uploadThenAttach({
    required String key,
    required String fileName,
    required String email,
    String? filePath,
    Uint8List? fileBytes,
    int? requiredTypeId,
    String? customTitle,
  }) async {
    _uploading[key] = true;
    errorMessage = null;
    notifyListeners();
    try {
      final uploadRes = await _api.postMultipart(
        '/api/v1/auth/teacher-documents/upload-attachment/$email',
        fields: {},
        fileField: 'file',
        fileName: fileName,
        filePath: filePath,
        fileBytes: fileBytes,
        headers: TeacherOnboardingToken.headers,
      );
      if (uploadRes == null || uploadRes is! Map) return false;

      final res = await _api.post(
        '/api/v1/auth/teacher-documents',
        body: {
      'email': email,
      'file_url': uploadRes['file_url'],
      'file_name': uploadRes['file_name'],
      'file_type': uploadRes['file_type'],
      'file_size': uploadRes['file_size'],
      'required_document_type_id': ?requiredTypeId,
      'custom_title': ?customTitle,
      },
        headers: TeacherOnboardingToken.headers,
      );
      if (res == null) return false;

      await loadOverview(email);
      return true;
    } catch (e) {
      errorMessage = ApiException.from(e).message;
      log('_uploadThenAttach ❌ $e');
      return false;
    } finally {
      _uploading[key] = false;
      notifyListeners();
    }
  }

  // ── Pick & upload for a predefined requirement — quick camera/gallery photo ─
  Future<void> pickAndUploadRequired({
    required int requiredTypeId,
    required ImageSource source,
    required String email,
  }) async {
    XFile? file;

    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage(imageQuality: 90, limit: 1);
      file = files.isNotEmpty ? files.first : null;
    } else {
      file = await _picker.pickImage(source: source, imageQuality: 90);
    }
    if (file == null) return;

    // file.path is a blob URL on web — dart:io's File can't stream from it
    // (that's the "Unsupported operation: _Namespace" crash). Always read
    // bytes too so postMultipart has a working fallback on web.
    final bytes = await file.readAsBytes();

    await _uploadThenAttach(
      key: 'req_$requiredTypeId',
      fileName: file.name,
      filePath: file.path,
      fileBytes: bytes,
      requiredTypeId: requiredTypeId,
      email: email,
    );
  }

  // ── Pick & upload for a predefined requirement — any image OR a PDF ────────
  // Uses file_picker so the teacher can browse their files, not just the
  // camera roll — needed for scanned PDFs (IDs, certificates, etc.).
  Future<void> pickAndUploadRequiredFile(
      int requiredTypeId, {
        required String email,
      }) async {
    // file_picker v12+: pickFile() returns PlatformFile? (null if cancelled).
    // The old `withData` flag is gone — bytes are read via readAsBytes().
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kDocumentAllowedExtensions,
    );
    if (f == null) return;

    final bytes = await f.readAsBytes(); // works on web and mobile

    await _uploadThenAttach(
      key: 'req_$requiredTypeId',
      fileName: f.name,
      filePath: kIsWeb ? null : f.path, // no real file path on web
      fileBytes: bytes,
      requiredTypeId: requiredTypeId,
      email: email,
    );
  }

  // ── Custom document entries (local form rows) ─────────────────────────────
  void addCustomEntry() {
    _customEntries.add(_CustomDocEntry());
    notifyListeners();
  }

  void removeCustomEntry(int index) {
    if (index < 0 || index >= _customEntries.length) return;
    _customEntries.removeAt(index);
    notifyListeners();
  }

  void setCustomEntryTitle(int index, String title) {
    if (index < 0 || index >= _customEntries.length) return;
    _customEntries[index].title = title;
    notifyListeners();
  }

  // ── Custom document: quick camera/gallery photo ─────────────────────────
  Future<void> pickAndUploadCustom(
      int entryIndex, {
        required String email,
      }) async {
    if (entryIndex < 0 || entryIndex >= _customEntries.length) return;
    final entry = _customEntries[entryIndex];
    if (entry.title.trim().isEmpty) return; // guard: title must be set first

    final files = await _picker.pickMultiImage(imageQuality: 90, limit: 1);
    if (files.isEmpty) return;
    final file = files.first;

    // Same web-safety fix as pickAndUploadRequired — always have bytes ready.
    final bytes = await file.readAsBytes();

    final ok = await _uploadThenAttach(
      key: 'custom_$entryIndex',
      fileName: file.name,
      filePath: file.path,
      fileBytes: bytes,
      customTitle: entry.title.trim(),
      email: email,
    );
    if (ok) _customEntries.removeAt(entryIndex);
  }

  // ── Custom document: any image OR a PDF, via file_picker ──────────────────
  Future<void> pickAndUploadCustomFile(
      int entryIndex, {
        required String email,
      }) async {
    if (entryIndex < 0 || entryIndex >= _customEntries.length) return;
    final entry = _customEntries[entryIndex];
    if (entry.title.trim().isEmpty) return; // guard: title must be set first

    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: kDocumentAllowedExtensions,
    );
    if (f == null) return;

    final bytes = await f.readAsBytes();

    final ok = await _uploadThenAttach(
      key: 'custom_$entryIndex',
      fileName: f.name,
      filePath: kIsWeb ? null : f.path,
      fileBytes: bytes,
      customTitle: entry.title.trim(),
      email: email,
    );
    if (ok) _customEntries.removeAt(entryIndex);
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<bool> deleteDocument(int documentId, {required String email}) async {
    try {
      await _api.delete('/api/v1/auth/teacher-documents/$documentId', headers: TeacherOnboardingToken.headers);
      await loadOverview(email);
      return true;
    } catch (e) {
      log('deleteDocument ❌ $e');
      return false;
    }
  }

  void clearCustomEntries() {
    _customEntries.clear();
    notifyListeners();
  }

  // ── Finalize registration (require ALL required docs to be uploaded) ──────
  Future<bool> finalizeRegistration({required String email}) async {
    isFinalizing = true;
    isFinalized = false;
    errorMessage = null;
    notifyListeners();
    try {
      final res = await _api.post(
        '/api/v1/auth/teacher-documents/finalize',
        body: {'email': email},
        headers: TeacherOnboardingToken.headers,
      );
      if (res != null && res is Map) {
        _overview = TeacherDocumentsOverview.fromJson(
          res as Map<String, dynamic>,
        );
        isFinalized = true;
        TeacherOnboardingToken.clear(); // onboarding is over: the token has no further use
        return true;
      }
      return false;
    } catch (e) {
      errorMessage = ApiException.from(e).message;
      log('finalizeRegistration ❌ $e');
      await loadOverview(email); // refresh so the UI shows what's still missing
      return false;
    } finally {
      isFinalizing = false;
      notifyListeners();
    }
  }
}

// ── Local form model for an in-progress custom document entry ────────────────
class _CustomDocEntry {
  String title = '';
// Could extend with a picked XFile preview, but we upload immediately on pick.
}