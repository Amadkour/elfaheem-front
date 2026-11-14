// lib/features/home/teacher/todo/teacher_todo_api.dart — the to-do list's calls (D-303).
//
//   GET  /api/v1/me/todo?scope=&org_id=       the core's list (states applied, hidden items, the states map)
//   GET  /api/v1/exam/me/todo                  the Exam Engine's review queues (same item shape), merged here
//   POST /api/v1/me/todo/state {key, action, fp, days?}   done · snooze · dismiss · restore
//
// The engine's half never fails the page: a missing route (an older engine) or an error leaves it out.
library;

import 'package:flutter/foundation.dart' show VoidCallback;

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/attention/attention_service.dart' show AttentionService;
import 'package:flutter_education_app/core/home/me_home.dart' show MeHomeService;
import 'package:flutter_education_app/design/app_notice.dart' show showAppNotice;
import 'package:flutter_education_app/features/home/teacher/todo/teacher_todo_models.dart';

class TeacherTodoApi {
  TeacherTodoApi({ApiClient? api}) : _api = api ?? ApiClient();
  final ApiClient _api;

  static const corePath = '/api/v1/me/todo';
  static const enginePath = '/api/v1/exam/me/todo';
  static const statePath = '/api/v1/me/todo/state';

  /// The whole list for the mode's side (Individual → personal courses, Organization → that organization's).
  Future<TodoList> load({Map<String, dynamic>? scope}) async {
    final core = _api.get(corePath, queryParams: scope ?? MeHomeService.scopeQuery());
    final engine = _engine();
    final r = await core;
    final list = TodoList.fromJson(r is Map ? r : const {});
    if (!list.enabled) return list;
    return mergeTodo(list, await engine);
  }

  Future<List<TodoItem>> _engine() async {
    try {
      final r = await _api.get(enginePath);
      final items = r is Map ? r['items'] : null;
      return [for (final x in items is List ? items : const []) ?TodoItem.fromJson(x)];
    } catch (_) {
      return const [];
    }
  }

  /// [action]: done · snooze ([days]) · dismiss · restore.
  Future<void> setState(TodoItem item, String action, {int? days}) =>
      _api.post(statePath, body: {'key': item.key, 'action': action, 'fp': item.fp, 'days': ?days});
}

/// Sends a to-do state change, refreshes the badge and says so (with Undo). Shared by the page and the home card.
/// Returns false when the server refused it (the caller puts the item back).
Future<bool> sendTodoChoice(TodoItem item, TodoMenu choice, {TeacherTodoApi? api, VoidCallback? onUndone}) async {
  final a = api ?? TeacherTodoApi();
  final (action, days) = switch (choice) {
    TodoMenu.done => ('done', null),
    TodoMenu.snooze1 => ('snooze', 1),
    TodoMenu.snooze3 => ('snooze', 3),
    TodoMenu.snooze7 => ('snooze', 7),
    TodoMenu.dismiss => ('dismiss', null),
  };
  try {
    await a.setState(item, action, days: days);
  } catch (e) {
    showAppNotice(ApiException.from(e).message, error: true);
    return false;
  }
  AttentionService.instance.refresh();
  showAppNotice(
    switch (choice) {
      TodoMenu.done => 'todo_toast_done'.tr,
      TodoMenu.dismiss => 'todo_toast_dismissed'.tr,
      _ => 'todo_toast_snoozed'.tr,
    },
    actionLabel: 'todo_undo'.tr,
    onAction: () async {
      try {
        await a.setState(item, 'restore');
        AttentionService.instance.refresh();
        onUndone?.call();
      } catch (e) {
        showAppNotice(ApiException.from(e).message, error: true);
      }
    },
  );
  return true;
}
