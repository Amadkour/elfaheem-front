/// ─────────────────────────────────────────────────────────────────────────────
/// modules_provider.dart
/// GET    /api/v1/courses/{course_id}/modules   — list modules for a course
/// POST   /api/v1/modules                        — create module
/// PUT    /api/v1/modules/{module_id}            — update module
/// DELETE /api/v1/modules/{module_id}            — delete module
/// ─────────────────────────────────────────────────────────────────────────────
library;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class ModuleModel {
  final int     id;
  final String  name;
  final String? description;
  final String? type; // 'live' | 'recorded'
  final int     courseId;
  final int     order;

  const ModuleModel({
    required this.id,
    required this.name,
    required this.courseId,
    required this.order,
    this.description,
    this.type,
  });

  factory ModuleModel.fromJson(Map<String, dynamic> j) => ModuleModel(
        id:          j['id']          as int,
        name:        j['name']        as String,
        description: j['description'] as String?,
        type:        j['type']        as String?,
        courseId:    j['course_id']   as int,
        order:       j['order']       as int? ?? 0,
      );
}

// ── Provider ──────────────────────────────────────────────────────────────────

class ModulesProvider extends BaseProvider {
  final ApiClient _api;

  ModulesProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── State ────────────────────────────────────────────────────────────────────
  List<ModuleModel> _modules  = [];
  int?              _courseId;

  List<ModuleModel> get modules  => List.unmodifiable(_modules);
  int?              get courseId => _courseId;

  // ── Fetch ─────────────────────────────────────────────────────────────────────

  Future<void> fetchModules(int courseId) async {
    _courseId = courseId;
    final result = await run(
      () => _api.get('/api/v1/courses/$courseId/modules', auth: false),
    );
    if (result is List) {
      _modules = result
          .map((e) => ModuleModel.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
    }
  }

  // ── Create ────────────────────────────────────────────────────────────────────

  /// [type] = 'live' | 'recorded'
  Future<ModuleModel?> createModule({
    required String name,
    required int    courseId,
    String? description,
    String? type,
    int     order = 0,
  }) async {
    final result = await run(() => _api.post(
          '/api/v1/modules',
          body: {
            'name':      name,
            'course_id': courseId,
            'order':     order,
            if (description != null) 'description': description,
            if (type        != null) 'type':        type,
          },
        ));

    if (result is Map<String, dynamic>) {
      final created = ModuleModel.fromJson(result);
      _modules      = [..._modules, created]
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return created;
    }
    return null;
  }

  // ── Update ────────────────────────────────────────────────────────────────────

  Future<ModuleModel?> updateModule(
    int moduleId, {
    String? name,
    String? description,
    String? type,
    int?    order,
  }) async {
    final result = await run(() => _api.put(
          '/api/v1/modules/$moduleId',
          body: {
            if (name        != null) 'name':        name,
            if (description != null) 'description': description,
            if (type        != null) 'type':        type,
            if (order       != null) 'order':       order,
          },
        ));

    if (result is Map<String, dynamic>) {
      final updated = ModuleModel.fromJson(result);
      _modules      = _modules
          .map((m) => m.id == moduleId ? updated : m)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      notifyListeners();
      return updated;
    }
    return null;
  }

  // ── Delete ────────────────────────────────────────────────────────────────────

  Future<bool> deleteModule(int moduleId) async {
    await run(() => _api.delete('/api/v1/modules/$moduleId'));
    if (state == ProviderState.success) {
      _modules = _modules.where((m) => m.id != moduleId).toList();
      notifyListeners();
      return true;
    }
    return false;
  }
}
