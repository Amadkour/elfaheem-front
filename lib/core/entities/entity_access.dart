// lib/core/entities/entity_access.dart — may this viewer open that entity? (D-290, phase 7)
//
//   EntityAccess.instance.known(ref)    true / false from the cache, null when not asked yet
//   await EntityAccess.instance.check(ref)   the answer; every ref asked in the same frame shares ONE request
//                                       (`POST /api/v1/entities/access`, at most 100 refs a request)
//
// Asked only for mentions that are not the viewer's by construction (a name in a request or a report): a sub-list's
// rows are in scope already. A failed request answers false and is not remembered, so the next screen asks again.
library;

import 'dart:async';

import 'entities_api.dart';
import 'entity_ref.dart';

class EntityAccess {
  EntityAccess._();
  static final EntityAccess instance = EntityAccess._();

  static const Duration maxAge = Duration(minutes: 5);
  static const int batch = 100;

  /// Instead of the API (tests).
  Future<Set<String>> Function(List<String> tokens)? debugAsk;

  final _known = <String, (DateTime, bool)>{};
  final _waiting = <String, Completer<bool>>{};
  Timer? _flush;

  bool? known(EntityRef ref) {
    final hit = _known[ref.toToken()];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.$1) > maxAge) return null;
    return hit.$2;
  }

  Future<bool> check(EntityRef ref) {
    final hit = known(ref);
    if (hit != null) return Future.value(hit);
    final token = ref.toToken();
    final waiting = _waiting[token];
    if (waiting != null) return waiting.future;
    final c = Completer<bool>();
    _waiting[token] = c;
    _flush ??= Timer(Duration.zero, _send);
    return c.future;
  }

  Future<void> _send() async {
    _flush = null;
    final tokens = _waiting.keys.take(batch).toList();
    final asked = {for (final t in tokens) t: _waiting.remove(t)!};
    if (_waiting.isNotEmpty) _flush = Timer(Duration.zero, _send);
    try {
      final ask = debugAsk ?? EntitiesApi.instance.allowed;
      final allowed = await ask(tokens);
      final now = DateTime.now();
      asked.forEach((t, c) {
        final v = allowed.contains(t);
        _known[t] = (now, v);
        c.complete(v);
      });
    } catch (_) {
      asked.forEach((_, c) => c.complete(false));
    }
  }

  /// Forgets everything (the account changed).
  void clear() => _known.clear();
}
