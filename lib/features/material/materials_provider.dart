/// ─────────────────────────────────────────────────────────────────────────────
/// materials_provider.dart
/// POST   /api/v1/materials                         — upload file (multipart)
/// GET    /api/v1/modules/{module_id}/materials     — list materials
/// DELETE /api/v1/materials/{material_id}           — delete material
///
/// Supported file types: PDF, video, image, Word, Excel, PPT
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'dart:io';
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class MaterialModel {
  final int     id;
  final String  name;
  final String? description;
  final int     moduleId;
  final String? fileUrl;
  final String? fileType;
  final int?    fileSize;

  const MaterialModel({
    required this.id,
    required this.name,
    required this.moduleId,
    this.description,
    this.fileUrl,
    this.fileType,
    this.fileSize,
  });

  factory MaterialModel.fromJson(Map<String, dynamic> j) => MaterialModel(
        id:          j['id']          as int,
        name:        j['name']        as String,
        description: j['description'] as String?,
        moduleId:    j['module_id']   as int,
        fileUrl:     j['file_url']    as String?,
        fileType:    j['file_type']   as String?,
        fileSize:    j['file_size']   as int?,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class MaterialsProvider extends BaseProvider {
  final ApiClient _api;

  MaterialsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────
  List<MaterialModel> _materials = [];
  double              _uploadProgress = 0.0;

  List<MaterialModel> get materials       => List.unmodifiable(_materials);
  double              get uploadProgress  => _uploadProgress;

  // ── Fetch ─────────────────────────────────────────────────────────────────────

  Future<void> fetchMaterials(int moduleId) async {
    final result = await run(
      () => _api.get('/api/v1/modules/$moduleId/materials', auth: false),
    );
    if (result is List) {
      _materials = result
          .map((e) => MaterialModel.fromJson(e as Map<String, dynamic>))
          .toList();
      notifyListeners();
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────────

  /// Upload a file to [moduleId].
  /// [file] is the local [File] to upload.
  Future<MaterialModel?> uploadMaterial({
    required int    moduleId,
    required String name,
    required File   file,
    String? description,
  }) async {
    _uploadProgress = 0.0;
    notifyListeners();

    final result = await run(() => _api.uploadFile(
          '/api/v1/materials',
          file: file,
          fields: {
            'module_id': moduleId.toString(),
            'name':      name,
            if (description != null) 'description': description,
          },
        ));

    _uploadProgress = 1.0;
    notifyListeners();

    if (result is Map<String, dynamic>) {
      final created = MaterialModel.fromJson(result);
      _materials    = [..._materials, created];
      notifyListeners();
      return created;
    }
    return null;
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  Future<bool> deleteMaterial(int materialId) async {
    await run(() => _api.delete('/api/v1/materials/$materialId'));
    if (state == ProviderState.success) {
      _materials = _materials.where((m) => m.id != materialId).toList();
      notifyListeners();
      return true;
    }
    return false;
  }
}
