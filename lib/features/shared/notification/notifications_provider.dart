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
///   • markAllAsRead()  → the page's one "Mark all read" (PUT /read-all, N12)
///   • unreadCount      → the server's whole `unread` count (N11)
///
/// NotificationModel fields the screen reads:
///   id, title, body, iconAsset, isRead
/// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter_education_app/core/entities/entity_models.dart';
import '../../../core/api_client.dart';
import '../../../core/base_provider.dart';

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

  /// Raw `related_type` from the API (course / session / exam / payment / profile …).
  final String relatedType;

  /// Raw notification `type` from the API (session_started / recording_ready / payment_success …).
  final String type;

  /// The course and teacher this notification is about (D-290): chips, a link only when the viewer has access.
  final List<EntityMention> entities;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.group,
    this.iconAsset = '',
    this.isRead = false,
    required this.sourceId,
    this.relatedType = '',
    this.type = '',
    this.entities = const [],
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
      relatedType: type,
      type: (json['type'] as String? ?? '').toLowerCase(),
      entities: EntityMention.listFrom(json['entities']),
    );
  }

  /// Maps API `type` string → icon asset key expected by the screen.
  static String _resolveIconAsset(String type) {
    if (type == 'message' || type == 'profile' || type == 'notifications') return '';
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
    relatedType: relatedType,
    type: type,
    entities: entities,
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

  /// The server's whole unread count (`unread` on GET /notifications, N11), kept in step with local marks;
  /// null on an older server, which then falls back to the loaded page's count.
  int? _serverUnread;

  /// Larger page to ensure both "today" and "yesterday" buckets fill up
  /// in a single fetch.
  static const int _pageSize = 30; // sent as `limit`; hasMore = (page.length == _pageSize)

  // ── Getters — consumed directly by the screen ─────────────────────────────────

  /// Notifications belonging to [NotifGroup.today].
  List<NotificationModel> get todayNotifs =>
      _all.where((n) => n.group == NotifGroup.today).toList();

  List<NotificationModel> get allNotifs => _all;

  /// Notifications belonging to [NotifGroup.yesterday].
  List<NotificationModel> get yesterdayNotifs =>
      _all.where((n) => n.group == NotifGroup.yesterday).toList();

  /// Total unread count — the bell badge. The server's whole count when it sends one (the page holds at most
  /// [_pageSize] rows, so counting it said 30 where the attention feed said 31), else the loaded rows'.
  int get unreadCount => _serverUnread ?? _all.where((n) => !n.isRead).length;

  bool get hasMore => _hasMore;

  // ── Fetch ─────────────────────────────────────────────────────────────────────

  /// Load the first page. Clears any existing data.
  Future<void> fetchNotifications({bool unreadOnly = false}) async {
    _skip = 0;
    _hasMore = true;
    _serverUnread = null;
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
        'skip': _skip,
        'limit': _pageSize,
        'unread_only': unreadOnly,
      },
    ));
    if (result is Map<dynamic, dynamic> &&
        result.containsKey('items') &&
        result['items'] is List) {
      final unread = result['unread'];
      if (unread is int) _serverUnread = unread;
      result = result['items'];
      List<NotificationModel> page = result
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .cast<NotificationModel>()
          .toList();
      _all.addAll(page);
      _skip += page.length;
      _hasMore = page.length == _pageSize;
      notifyListeners();

      // NOTE: This used to loop over every unread item in the fetched page
      // and call NotificationService.instance.show() for each one. That was
      // the cause of two bugs:
      //   1. Every unread notification got re-shown as a local push EVERY
      //      TIME this screen was opened, not just once when it originally
      //      arrived — hence "20 notifications at once".
      //   2. It made it *look* like notifications only worked when opening
      //      this screen, when in reality real-time push (FCM foreground/
      //      background handlers, registered globally in main.dart at app
      //      startup) already works on any screen and doesn't need this.
      //
      // Fetching a list of notifications is a read operation, not a "new
      // event" — it should never trigger a local notification. Real-time
      // "new notification" alerts are already handled by
      // NotificationService's FCM listeners (see notification_service.dart),
      // which fire regardless of which screen is currently open.
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

  /// Marks every notification read — the loaded rows and the ones on later pages — with ONE call
  /// (`PUT /read-all`), optimistically. The page's single "Mark all read" (N12) uses it.
  Future<void> markAllAsRead() async {
    if (unreadCount == 0) return;
    for (final n in _all.where((n) => !n.isRead).toList()) {
      _updateLocal(n.id, true);
    }
    if (_serverUnread != null) {
      _serverUnread = 0;
      notifyListeners();
    }
    try {
      await _api.put('/api/v1/notifications/read-all');
    } catch (_) {
      // Kept read on screen; the next fetch tells the truth.
    }
  }

  // ── Private helper ────────────────────────────────────────────────────────────

  void _updateLocal(String id, bool isRead) {
    final idx = _all.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final was = _all[idx].isRead;
      if (_serverUnread != null && was != isRead) {
        _serverUnread = (_serverUnread! + (isRead ? -1 : 1)).clamp(0, 1 << 30);
      }
      _all[idx] = _all[idx].copyWith(isRead: isRead);
      notifyListeners();
    }
  }
}
