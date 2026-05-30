/// ─────────────────────────────────────────────────────────────────────────────
/// notifications_provider.dart
/// Manages state for the Notifications screen.
///
/// API endpoints:
///   GET /api/v1/notifications                        — fetch paginated list
///   PUT /api/v1/notifications/{notification_id}/read — mark single as read
///
/// Screen contract (must match notifications_screen.dart exactly):
///   • todayNotifs     → List used by _NotifGroup(group: NotifGroup.today)
///   • yesterdayNotifs → List used by _NotifGroup(group: NotifGroup.yesterday)
///   • markAsRead(id)  → called on tile tap
///   • markGroupAsRead(group) → called by "تحديد الكل كمقروء"
///
/// NotificationModel fields the screen reads:
///   id, title, body, iconAsset, isRead
/// ─────────────────────────────────────────────────────────────────────────────
library;

import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';
import 'notification_service.dart';

// ── NotifGroup ────────────────────────────────────────────────────────────────

/// Time-bucket used by the screen to split notifications into sections.
/// The screen imports this enum directly from this file.
enum NotifGroup {
  today, // "اليوم"
  yesterday, // "الأمس"
}

// ── NotificationModel ─────────────────────────────────────────────────────────

class NotificationModel {
  final String id;
  final String title;
  final String body;

  /// Icon asset key — read by `_buildIcon()` in the screen:
  ///   'payment' → credit card icon
  ///   'badge'   → premium badge icon
  ///   'new'     → pink NEW badge
  ///   ''        → default bell icon
  final String iconAsset;
  final NotifGroup group;
  bool isRead;
  final int sourceId;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.group,
    this.iconAsset = '',
    this.isRead = false,
    required this.sourceId,
  });

  // ── fromJson ────────────────────────────────────────────────────────────────

  /// Converts the API JSON response into a [NotificationModel].
  ///
  /// Group derivation:
  ///   today's date  → [NotifGroup.today]
  ///   yesterday     → [NotifGroup.yesterday]
  ///   older         → bucketed into [NotifGroup.yesterday]
  ///                   (screen only shows two sections)
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    // ── Derive group from created_at ──────────────────────────────────────────
    final raw = json['created_at'] as String?;
    final createdAt =
        raw != null ? DateTime.tryParse(raw) ?? DateTime.now() : DateTime.now();

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final createdDay = DateTime(createdAt.year, createdAt.month, createdAt.day);

    final dayDiff = todayMidnight.difference(createdDay).inDays;
    final group = dayDiff == 0 ? NotifGroup.today : NotifGroup.yesterday;

    // ── Derive iconAsset from API type field ──────────────────────────────────
    final type = (json['related_type'] as String? ?? '').toLowerCase();
    final iconAsset = _resolveIconAsset(type);

    return NotificationModel(
      id: json['id'].toString(),
      sourceId: json['related_id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      body: json['message'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      iconAsset: iconAsset,
      group: group,
    );
  }

  /// Maps API `type` string → icon asset key expected by the screen.
  static String _resolveIconAsset(String type) {
    if (type.contains('payment') || type.contains('pay')) return 'payment';
    if (type.contains('badge') ||
        type.contains('certificate') ||
        type.contains('premium')) {
      return 'badge';
    }
    if (type.contains('new') ||
        type.contains('enroll') ||
        type.contains('session') ||
        type.contains('join')) {
      return 'new';
    }
    return ''; // default → bell icon
  }

  // ── Immutable copy ──────────────────────────────────────────────────────────

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        title: title,
        body: body,
        group: group,
        iconAsset: iconAsset,
        isRead: isRead ?? this.isRead,
        sourceId: sourceId,
      );
}

// ── NotificationsProvider ─────────────────────────────────────────────────────

class NotificationsProvider extends BaseProvider {
  final ApiClient _api;

  NotificationsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  // ── Internal state ───────────────────────────────────────────────────────────

  final List<NotificationModel> _all = [];

  int _skip = 0;
  bool _hasMore = true;

  /// Larger page to ensure both "today" and "yesterday" buckets fill up
  /// in a single fetch.
  static const int _pageSize = 30;

  // ── Getters — consumed directly by the screen ─────────────────────────────────

  /// Notifications belonging to [NotifGroup.today].
  List<NotificationModel> get todayNotifs =>
      _all.where((n) => n.group == NotifGroup.today).toList();

  List<NotificationModel> get allNotifs => _all;

  /// Notifications belonging to [NotifGroup.yesterday].
  List<NotificationModel> get yesterdayNotifs =>
      _all.where((n) => n.group == NotifGroup.yesterday).toList();

  /// Total unread count — used for badge dots in app shell.
  int get unreadCount => _all.where((n) => !n.isRead).length;

  bool get hasMore => _hasMore;

  // ── Fetch ─────────────────────────────────────────────────────────────────────

  /// Load the first page. Clears any existing data.
  Future<void> fetchNotifications({bool unreadOnly = false}) async {
    _skip = 0;
    _hasMore = true;
    _all.clear();
    notifyListeners();
    await _loadPage(unreadOnly: unreadOnly);
  }

  /// Append the next page (infinite scroll).
  Future<void> loadMore({bool unreadOnly = false}) async {
    if (!_hasMore || isLoading) return;
    await _loadPage(unreadOnly: unreadOnly);
  }

  Future<void> _loadPage({bool unreadOnly = false}) async {
    dynamic result = await run(() => _api.get(
          '/api/v1/notifications',
          queryParams: {
            'skip': 0,
            'limit': 20,
            'unread_only': unreadOnly,
          },
        ));
    if (result is Map<dynamic, dynamic> &&
        result.containsKey('items') &&
        result['items'] is List) {
      result = result['items'];
      List<NotificationModel> page = result
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .cast<NotificationModel>()
          .toList();
      print('page length is: ${page.length}');
      _all.addAll(page);
      _skip += page.length;
      _hasMore = page.length == _pageSize;
      notifyListeners();
      for (final notif in page) {
        if (!notif.isRead) {
          await NotificationService.instance.show(
            id: notif.id.hashCode,
            title: notif.title,
            body: notif.body,
          );
        }
      }
    }
  }

  // ── markAsRead — tile tap ─────────────────────────────────────────────────────

  /// Optimistically marks a single notification as read, then calls the API.
  /// Rolls back if the API call fails.
  Future<bool> markAsRead(String id) async {
    // Optimistic update for instant feedback
    _updateLocal(id, true);

    final result = await run(
      () => _api.put('/api/v1/notifications/$id/read'),
    );

    if (result == null && hasError) {
      _updateLocal(id, false); // rollback
      return false;
    }
    return true;
  }

  // ── markGroupAsRead — "تحديد الكل كمقروء" ────────────────────────────────────

  /// Marks all unread notifications in [group] as read.
  /// Fires all API calls concurrently for speed.
  /// Called by the screen's group header action.
  Future<void> markGroupAsRead(NotifGroup group) async {
    final unread = _all.where((n) => n.group == group && !n.isRead).toList();

    if (unread.isEmpty) return;

    // Optimistic UI update first
    for (final n in unread) {
      _updateLocal(n.id, true);
    }

    // Fire all concurrently — no rollback on partial failure for UX stability
    await Future.wait(
      unread.map((n) => _api
          .put('/api/v1/notifications/${n.id}/read')
          .catchError((_) => null)),
    );
  }

  // ── markAllAsRead — used by app shell nav badge ───────────────────────────────

  Future<void> markAllAsRead() async {
    final unread = _all.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;

    for (final n in unread) {
      _updateLocal(n.id, true);
    }

    await Future.wait(
      unread.map((n) => _api
          .put('/api/v1/notifications/${n.id}/read')
          .catchError((_) => null)),
    );
  }

  // ── Private helper ────────────────────────────────────────────────────────────

  void _updateLocal(String id, bool isRead) {
    final idx = _all.indexWhere((n) => n.id == id);
    if (idx != -1) {
      _all[idx] = _all[idx].copyWith(isRead: isRead);
      notifyListeners();
    }
  }
}
