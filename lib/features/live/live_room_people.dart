// lib/features/live/live_room_people.dart
//
// WP1 (D-1950): the HOST's roster of a live room. A student's (and a guest's) LiveKit token is hidden, so the host's
// LiveKit participant list no longer holds them; `GET /api/v1/live/{kind}/{id}/people` does, with real names, the
// raised hands and who is on stage, and `POST …/participants/{identity}/stage {on}` brings a person on stage / takes
// them off (docs/redesign/api/privacy.md). Pure logic (parsing, counts, optimistic stage flip) so it is unit-tested
// without a Room (test/ui/t1_live_people_test.dart); the room's participants panel draws from it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/features/live/live_controls_api.dart';

/// One row of `GET …/people`.
@immutable
class LiveRoomPerson {
  const LiveRoomPerson({
    required this.identity,
    required this.name,
    this.userId,
    this.imageUrl,
    this.guest = false,
    this.companion = false,
    this.host = false,
    this.private = false,
    this.onStage = false,
    this.handRaised = false,
  });

  final String identity;
  final String name;
  final int? userId;
  final String? imageUrl;
  final bool guest, companion, host;

  /// Hidden from everyone but the hosts (until brought on stage).
  final bool private;
  final bool onStage;
  final bool handRaised;

  /// A student or a guest the host may bring on stage: never a host, never a companion phone.
  bool get canStage => !host && !companion && (private || onStage);

  /// Null when the row has no identity.
  static LiveRoomPerson? fromJson(Map<String, dynamic> j) {
    final id = '${j['identity'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final name = '${j['name'] ?? ''}'.trim();
    final image = '${j['image_url'] ?? ''}'.trim();
    return LiveRoomPerson(
      identity: id,
      name: name.isEmpty ? id : name,
      userId: j['user_id'] is num ? (j['user_id'] as num).toInt() : int.tryParse('${j['user_id'] ?? ''}'),
      imageUrl: image.isEmpty ? null : image,
      guest: j['guest'] == true,
      companion: j['companion'] == true,
      host: j['host'] == true,
      private: j['private'] == true,
      onStage: j['on_stage'] == true,
      handRaised: j['hand_raised'] == true,
    );
  }

  LiveRoomPerson copyWith({bool? onStage, bool? handRaised}) => LiveRoomPerson(
        identity: identity,
        name: name,
        userId: userId,
        imageUrl: imageUrl,
        guest: guest,
        companion: companion,
        host: host,
        private: private,
        onStage: onStage ?? this.onStage,
        handRaised: handRaised ?? this.handRaised,
      );
}

/// The roster the host's panel draws. [fetch] / [stage] default to [LiveControlsApi]; tests pass fakes.
class LivePeopleController extends ChangeNotifier {
  LivePeopleController({
    LiveControlsApi? api,
    Future<List<Map<String, dynamic>>> Function()? fetch,
    Future<bool> Function(String identity, bool on)? stage,
  })  : _fetch = fetch ?? (api ?? (throw ArgumentError('api or fetch'))).people,
        _stage = stage ?? (api ?? (throw ArgumentError('api or stage'))).stage;

  final Future<List<Map<String, dynamic>>> Function() _fetch;
  final Future<bool> Function(String identity, bool on) _stage;

  List<LiveRoomPerson> _items = const [];
  bool _loaded = false;
  bool _busy = false;
  bool _disposed = false;
  final Set<String> _staging = {};

  List<LiveRoomPerson> get items => _items;

  /// A first answer arrived (an older server without the route never gets here: the roster stays empty).
  bool get loaded => _loaded;
  bool get loading => _busy;

  /// Identities whose stage call is in flight.
  Set<String> get staging => Set.unmodifiable(_staging);

  LiveRoomPerson? byIdentity(String identity) {
    for (final p in _items) {
      if (p.identity == identity) return p;
    }
    return null;
  }

  /// A signed-in student's row: the identity the server mints is `student_<id>`, the row carries the user id too.
  LiveRoomPerson? byUserId(int id) {
    for (final p in _items) {
      if (p.userId == id && !p.guest && !p.companion) return p;
    }
    return null;
  }

  /// Students in the room now (not hosts, guests or companion phones).
  int get studentsPresent => _items.where((p) => !p.host && !p.guest && !p.companion).length;
  int get guestsPresent => _items.where((p) => p.guest && !p.companion).length;
  int get handsUp => _items.where((p) => p.handRaised).length;

  /// Replaces the roster from the server. Silent on failure: the panel keeps what it had.
  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final rows = await _fetch();
      _items = [
        for (final r in rows)
          ?LiveRoomPerson.fromJson(r),
      ];
      _loaded = true;
    } catch (_) {
      // keep the last roster
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Brings [identity] on stage / takes them off. The row flips at once and goes back when the call fails;
  /// returns whether the server applied it (null = a call for that person was already running).
  Future<bool?> setStage(String identity, bool on) async {
    if (_staging.contains(identity)) return null;
    final before = byIdentity(identity);
    if (before == null) return false;
    _staging.add(identity);
    _replace(before.copyWith(onStage: on));
    _notify();
    try {
      final applied = await _stage(identity, on);
      _replace(before.copyWith(onStage: applied));
      return applied == on;
    } on ApiException {
      _replace(before);
      rethrow;
    } catch (_) {
      _replace(before);
      return false;
    } finally {
      _staging.remove(identity);
      _notify();
    }
  }

  /// A hand raised / lowered by a data message, before the next refresh.
  void markHand(String identity, bool raised) {
    final p = byIdentity(identity);
    if (p == null || p.handRaised == raised) return;
    _replace(p.copyWith(handRaised: raised));
    _notify();
  }

  void _replace(LiveRoomPerson p) {
    _items = [for (final i in _items) i.identity == p.identity ? p : i];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// A `nb.hand` / `nb.ask` data message from the server (topics in privacy.md): `{type, identity, raised | text, name}`.
/// Null when it is neither.
@immutable
class LiveServerSignal {
  const LiveServerSignal.hand({required this.identity, required this.name, required this.raised})
      : text = null,
        at = null;
  const LiveServerSignal.ask({required this.identity, required this.name, required String this.text, this.at})
      : raised = null;

  final String identity;
  final String name;
  final bool? raised;
  final String? text;
  final int? at;

  bool get isHand => raised != null;
}

/// Topic names of the server's host-only messages.
const String kLiveServerHandTopic = 'nb.hand';
const String kLiveServerAskTopic = 'nb.ask';

LiveServerSignal? parseLiveServerSignal(Map<dynamic, dynamic> m) {
  final identity = '${m['identity'] ?? ''}'.trim();
  if (identity.isEmpty) return null;
  final name = '${m['name'] ?? ''}'.trim();
  switch ('${m['type'] ?? ''}') {
    case 'hand':
      return LiveServerSignal.hand(identity: identity, name: name.isEmpty ? identity : name, raised: m['raised'] == true);
    case 'ask':
      final text = '${m['text'] ?? ''}'.trim();
      if (text.isEmpty) return null;
      return LiveServerSignal.ask(
        identity: identity,
        name: name.isEmpty ? identity : name,
        text: text,
        at: m['at'] is num ? (m['at'] as num).toInt() : null,
      );
  }
  return null;
}
