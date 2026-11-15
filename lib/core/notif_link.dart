// lib/core/notif_link.dart
//
// UX v3 phase 2: where a notification / a push / an "action inbox" row points, and what it asks of me.
//
//   NotifLink.fromRow(row)        a notification row: `{action, link: {module, id, org_id?, focus?, reason_ar,
//                                 reason_en, note?, fields?}}`; null for an old row (neither key)
//   NotifLink.fromTarget(answer)  GET /notifications/{id}/target: the same keys at the top or under `link`, or
//                                 `{stale: true, stale_reason_ar, stale_reason_en, fallback: {module}}`
//   NotifLink.fromPush(data)      FCM data (strings): notification_id, action, module, id, org_id, reason_ar, reason_en
//   NotifLink.fromAttentionTarget(target)   a /me/attention row's `target: {module, id, org_id}`
//   notifLinkDestination(link)    the pure routing decision AppNavigator.openLink follows (tested)
//
// Pure Dart (no widgets): the banner that draws it is lib/design/action_banner.dart.
library;

import 'package:flutter_education_app/config/app_config.dart';

/// What the item asks of me. [none] = an older server named no action.
enum NotifAction { edit, confirm, vote, reply, review, fill, approve, view, none }

NotifAction notifActionOf(Object? v) => switch ('${v ?? ''}'.trim().toLowerCase()) {
      'edit' => NotifAction.edit,
      'confirm' => NotifAction.confirm,
      'vote' => NotifAction.vote,
      'reply' => NotifAction.reply,
      'review' => NotifAction.review,
      'fill' => NotifAction.fill,
      'approve' => NotifAction.approve,
      'view' => NotifAction.view,
      _ => NotifAction.none,
    };

String _pick(String? ar, String? en) {
  final a = (ar ?? '').trim(), e = (en ?? '').trim();
  return AppConfig.lang == 'ar' ? (a.isNotEmpty ? a : e) : (e.isNotEmpty ? e : a);
}

String? _str(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

int? _int(Object? v) => v == null ? null : int.tryParse('$v'.trim());

Map<String, dynamic> _map(Object? v) => v is Map ? v.map((k, x) => MapEntry('$k', x)) : const {};

/// One field the reviewer asks me to change: its form key and its label (Arabic / English; the key when none).
class NotifField {
  const NotifField(this.key, {this.labelAr, this.labelEn});

  final String key;
  final String? labelAr, labelEn;

  String get label {
    final l = _pick(labelAr, labelEn);
    return l.isEmpty ? key : l;
  }

  /// A plain string (`"title"`) or `{name | field | key, label_ar | label, label_en}`.
  static NotifField? parse(Object? v) {
    if (v is Map) {
      final m = _map(v);
      final k = _str(m['name'] ?? m['field'] ?? m['key']);
      if (k == null) return null;
      return NotifField(k, labelAr: _str(m['label_ar'] ?? m['label']), labelEn: _str(m['label_en']));
    }
    final k = _str(v);
    return k == null ? null : NotifField(k);
  }
}

class NotifLink {
  const NotifLink({
    this.action = NotifAction.none,
    this.module,
    this.id,
    this.orgId,
    this.focus,
    this.reasonAr,
    this.reasonEn,
    this.note,
    this.fields = const [],
    this.rejected = false,
    this.stale = false,
    this.staleReasonAr,
    this.staleReasonEn,
    this.fallbackModule,
    this.notificationId,
  });

  final NotifAction action;
  final String? module;
  final int? id, orgId;

  /// The part of the screen to scroll to: `decision` · `vote` · `comments` · `fields` (server words; others ignored).
  final String? focus;
  final String? reasonAr, reasonEn;

  /// The reviewer's note (shown under the reason, quoted).
  final String? note;
  final List<NotifField> fields;

  /// The item came back rejected (`outcome: rejected` / `rejected: true`): the banner reads "Rejected: see why".
  final bool rejected;

  /// The target was already handled or no longer exists (only from the target answer).
  final bool stale;
  final String? staleReasonAr, staleReasonEn;

  /// Where the stale view's button goes (`fallback.module`).
  final String? fallbackModule;

  /// The notification the push carried (a push tap marks it read through the target GET).
  final String? notificationId;

  /// The reason in the current language ('' when the server sent none).
  String get reason => _pick(reasonAr, reasonEn);
  String get staleReason => _pick(staleReasonAr, staleReasonEn);

  bool get hasAction => action != NotifAction.none;

  static NotifLink _build(Map<String, dynamic> top, Map<String, dynamic> link, {String? notificationId}) {
    Object? v(String k) => link[k] ?? top[k];
    final fields = <NotifField>[
      for (final f in (v('fields') is List ? v('fields') as List : const [])) ?NotifField.parse(f),
    ];
    final fallback = _map(top['fallback']);
    return NotifLink(
      action: notifActionOf(top['action'] ?? link['action']),
      module: _str(v('module')),
      id: _int(link['id'] ?? top['id'] ?? top['target_id']),
      orgId: _int(v('org_id')),
      focus: _str(v('focus')),
      reasonAr: _str(v('reason_ar')),
      reasonEn: _str(v('reason_en')),
      note: _str(v('note')),
      fields: fields,
      rejected: v('rejected') == true || '${v('outcome') ?? ''}' == 'rejected',
      stale: top['stale'] == true || link['stale'] == true,
      staleReasonAr: _str(top['stale_reason_ar'] ?? link['stale_reason_ar']),
      staleReasonEn: _str(top['stale_reason_en'] ?? link['stale_reason_en']),
      fallbackModule: _str(fallback['module']),
      notificationId: notificationId,
    );
  }

  /// A notification row; null when the row carries neither `action` nor `link` (an older server).
  static NotifLink? fromRow(Map row) {
    final m = _map(row);
    final link = _map(m['link']);
    if (link.isEmpty && _str(m['action']) == null) return null;
    return _build({'action': m['action']}, link);
  }

  /// The target answer; null when it names no action, no link and is not stale (the old routing applies).
  static NotifLink? fromTarget(Map answer) {
    final m = _map(answer);
    final link = _map(m['link']);
    if (link.isEmpty && _str(m['action']) == null && m['stale'] != true) return null;
    return _build(m, link);
  }

  /// FCM data; null when it names no action and no notification (an older server's push).
  static NotifLink? fromPush(Map data) {
    final m = _map(data);
    final nid = _str(m['notification_id']);
    if (nid == null && _str(m['action']) == null) return null;
    return _build(m, const {}, notificationId: nid);
  }

  /// A /me/attention row's `target` (on the row or inside its `action`); null without a module.
  static NotifLink? fromAttentionTarget(Object? target) {
    final m = _map(target);
    if (_str(m['module']) == null) return null;
    return _build(m, const {});
  }

  /// An action inbox row (`{action, module, id, org_id, reason_ar, reason_en}`).
  static NotifLink fromInboxRow(Map row) => _build(_map(row), const {});
}

/// Where [notifLinkDestination] sends a link.
enum NotifDestination { stale, actionInbox, govItem, govSession, govDelegation, govAssignment, module }

/// The routing decision for a link (AppNavigator.openLink follows it).
NotifDestination notifLinkDestination(NotifLink l) {
  if (l.stale) return NotifDestination.stale;
  return switch (l.module) {
    'action_inbox' => NotifDestination.actionInbox,
    'org_work' when l.id != null => NotifDestination.govItem,
    'org_council' when l.id != null => NotifDestination.govSession,
    'org_delegation' when l.id != null => NotifDestination.govDelegation,
    'org_form_assignment' when l.id != null => NotifDestination.govAssignment,
    _ => NotifDestination.module,
  };
}
