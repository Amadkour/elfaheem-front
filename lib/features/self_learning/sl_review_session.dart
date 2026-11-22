// lib/features/self_learning/sl_review_session.dart — the review round's state (D-1605): answer → feedback → next.
// The verdict is the device's own (the item carries the right option), so the feedback shows on the tap; the answer
// is then sent once with its `client_id` (kept in the outbox when offline). The server's explanation replaces the
// item's when it differs; a refused answer keeps the feedback and shows the refusal under it.
library;

import 'package:flutter/foundation.dart';

import 'sl_api.dart';
import 'sl_models.dart';

enum SlReviewPhase { answering, feedback, done }

/// Sends one answer (the API's [SlApi.review], faked in tests).
typedef SlSubmit = Future<SlReviewResult> Function(int itemId, int choice, String clientId);

class SlReviewSession extends ChangeNotifier {
  SlReviewSession({required List<SlItem> items, required SlSubmit submit, String Function()? clientId})
      : items = [for (final i in items) if (i.question?.valid == true) i],
        _submit = submit,
        _clientId = clientId ?? slClientId;

  final List<SlItem> items;
  final SlSubmit _submit;
  final String Function() _clientId;

  int _index = 0;
  int? _picked;
  bool? _right;
  String _explanation = '';
  bool _sending = false;
  bool _queued = false;
  String? _error;
  int _rightCount = 0;
  int _queuedCount = 0;

  int get index => _index;
  int get total => items.length;
  SlItem? get current => _index < items.length ? items[_index] : null;
  int? get picked => _picked;
  bool? get right => _right;
  String get explanation => _explanation;
  bool get sending => _sending;

  /// The current answer was kept on the device (no connection).
  bool get queued => _queued;
  String? get error => _error;
  int get rightCount => _rightCount;
  int get queuedCount => _queuedCount;

  SlReviewPhase get phase =>
      current == null ? SlReviewPhase.done : (_right == null ? SlReviewPhase.answering : SlReviewPhase.feedback);

  /// Picks [choice] for the current question: graded at once, then sent.
  Future<void> answer(int choice) async {
    final item = current;
    final q = item?.question;
    if (item == null || q == null || _right != null) return;
    _picked = choice;
    _right = choice == q.answer;
    _explanation = q.explanation;
    if (_right!) _rightCount++;
    _sending = true;
    _error = null;
    notifyListeners();
    final at = _index;
    try {
      final r = await _submit(item.id, choice, _clientId());
      if (at != _index) return;
      if (r.queued) {
        _queued = true;
        _queuedCount++;
      } else if (r.explanation.trim().isNotEmpty) {
        _explanation = r.explanation;
      }
    } catch (e) {
      if (at != _index) return;
      _error = slErrorText(e);
    } finally {
      if (at == _index) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  /// The next question (or the end).
  void next() {
    if (_right == null) return;
    _index++;
    _picked = null;
    _right = null;
    _explanation = '';
    _sending = false;
    _queued = false;
    _error = null;
    notifyListeners();
  }
}
