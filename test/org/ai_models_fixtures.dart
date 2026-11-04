// Hand-built replies of the model hub in the per-task shape (FRONT_CONTRACTS "Models"), shared by the ai_models_* tests.

Map<String, dynamic> aiModelRow(int id, String ref, {String status = 'ready', List<String> roles = const ['generation.chat', 'generation.exam', 'grading'], Map<String, dynamic>? extra}) => {
      'id': id,
      'role': 'generation',
      'name': ref.split(':').last,
      'version': '4b',
      'ref': ref,
      'provider': 'ollama',
      'source': 'ollama',
      'status': status,
      'size_bytes': 2500000000,
      'disk_bytes': status == 'not_downloaded' ? 0 : 2500000000,
      'ram_mb': 3200,
      'deletable': true,
      'roles': roles,
      'used_in': {
        if (status == 'active') 'generation.chat': ['active'],
      },
      'accuracy': {
        'generation.chat': {'metric': 'pass_rate', 'score': 0.82, 'n': 40, 'dataset': 'chat-ar-40', 'details': {}, 'at': '2026-11-03T10:00:00'},
      },
      'speed': {'value': 18.4, 'unit': 'tok/s', 'ttft_ms': 640, 'load_ms': 2000, 'rss_mb': 3100, 'at': '2026-11-03T10:00:00', 'ok': true},
      'context': 8192,
      'params_b': 4.0,
      'recommended_for': ['generation.chat'],
      ...?extra,
    };

Map<String, dynamic> aiRoleRow(String role, String? task, List<Map<String, dynamic>> models, {int? activeId, String? recommended, Map<String, dynamic>? pending}) => {
      'role': role,
      'task': task,
      'active': activeId == null ? null : 'ollama:qwen3:4b',
      'active_id': activeId,
      'previous': null,
      'previous_id': null,
      'fallback': null,
      'fallback_id': null,
      'pending': pending,
      'limits': {'threads': 2, 'max_concurrency': 1, 'priority': 'interactive', 'idle_unload_s': 0, 'ram_mb': 0},
      'recommended': recommended,
      'models': models,
    };

/// The hub with the three task roles (chat serves model 1, exam and grading have none yet) + a supporting role.
Map<String, dynamic> aiTaskOverview({int? chatActive = 1, Map<String, dynamic>? examPending}) {
  final a = aiModelRow(1, 'ollama:qwen3:4b', status: 'active');
  final b = aiModelRow(2, 'ollama:qwen3:14b-q4_K_M', status: 'not_downloaded', extra: {'ram_mb': 11000, 'accuracy': {}, 'speed': null});
  return {
    'roles': [
      aiRoleRow('embedding', null, [
        {...aiModelRow(9, 'bge-m3', extra: {'roles': ['embedding']}), 'role': 'embedding', 'accuracy': {}, 'speed': null},
      ], activeId: 9),
      aiRoleRow('generation.chat', 'chat', [a, b], activeId: chatActive, recommended: 'ollama:qwen3:4b'),
      aiRoleRow('generation.exam', 'exam', [a, b], recommended: 'ollama:qwen3:14b-q4_K_M', pending: examPending),
      aiRoleRow('grading', 'grading', [a, b]),
    ],
  };
}
