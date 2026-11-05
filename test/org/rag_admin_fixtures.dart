// Server replies of the RAG admin additions (FRONT_CONTRACTS "Feedback review", "Cache"), shared by the rag_admin_* tests.

Map<String, dynamic> feedbackCluster(String key, {String scope = 'app', Map<String, dynamic>? verified, int dislikes = 3}) => {
      'key': key,
      'scope': scope,
      'org_id': scope == 'org' ? 5 : null,
      'course_id': null,
      'question': 'How do I change my password?',
      'dislikes': dislikes,
      'likes': 1,
      'questions': ['How do I change my password?', 'forgot password how to reset', 'change pwd'],
      'last_at': '2026-11-03T09:30:00Z',
      'query_id': 9,
      'answer': {
        'text': 'Open Settings, then Security.',
        'found': true,
        'generator': 'extractive',
        'citations': [
          {'title': 'Terms and Conditions', 'section': 'Account', 'document_id': 7, 'page_from': 3},
        ],
      },
      'comments': [
        {'text': 'It does not say where the button is', 'at': '2026-11-03T09:31:00Z'},
      ],
      'verified': verified,
    };

Map<String, dynamic> feedbackPage(List<Map<String, dynamic>> items, {int total = -1, int offset = 0}) => {
      'items': items,
      'total': total < 0 ? items.length : total,
      'limit': 20,
      'offset': offset,
      'days': 30,
      'min_dislikes': 1,
      'threshold': 0.86,
      'rated': {'unhelpful': 7, 'helpful': 12},
    };

Map<String, dynamic> cacheStatsJson() => {
      'entries': 1240,
      'bytes': 5242880,
      'hits': 900,
      'semantic_entries': 310,
      'hit_rate': 0.42,
      'per_org': [
        {'org_id': null, 'entries': 800, 'bytes': 3000000, 'hits': 500},
        {'org_id': 5, 'entries': 300, 'bytes': 1500000, 'hits': 300},
      ],
      'env_enabled': true,
      'settings': {'cache.enabled': true, 'cache.semantic': true, 'cache.max_entries': 20000, 'cache.org_max_entries': 0},
      'semantic_min': 0.95,
      'max_age_days': 30,
    };
