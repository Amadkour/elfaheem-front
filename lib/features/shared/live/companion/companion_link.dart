// lib/features/shared/live/companion/companion_link.dart
//
// The person's side of a companion phone (D-520): asks for the phone, watches it arrive and leave in the LiveKit
// room, and hands this device's microphone, camera and sound over and back (`CompanionHandover`). RoomPage owns one and
// feeds it the room's events; the sheet (companion_sheet.dart) and the bar read it.
library;

import 'dart:async';
import 'dart:developer' show log;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../core/api_client.dart' show ApiException;
import '../../../../core/live/event_wait.dart';
import '../../../../utils/live_events.dart';
import '../../../admin/admin_common.dart' show t;
import '../live_room.dart' show LiveRoomRef;
import 'companion_core.dart';
import 'companion_platform.dart' as platform;

/// What RoomPage lends the link: this device's mic and camera, and the way to say something on screen.
abstract class CompanionHost {
  bool get webMicOn;
  bool get webCamOn;
  Future<void> setWebMic(bool on);
  Future<void> setWebCam(bool on);
  void companionNotice(String text, {bool error = false});
}

enum CompanionStage { idle, ringing, connecting, active }

class CompanionLink extends ChangeNotifier {
  CompanionLink({required this.room, required this.ref, required this.host, CompanionApi? api})
      : _api = api ?? CompanionApi();

  final Room room;
  final LiveRoomRef ref;
  final CompanionHost host;
  final CompanionApi _api;

  CompanionStage stage = CompanionStage.idle;
  CompanionRequest? request;
  Set<CompanionSource> wanted = const {CompanionSource.camera};
  String? error;

  /// The QR link's secret of the running request.
  String? secret;
  bool noPhoneToPush = false;
  bool busy = false;

  bool _disposed = false;
  bool _endedByPerson = false;
  EventsListener<RoomEvent>? _listener;
  StreamSubscription<LiveEvent>? _events;
  EventOrPoll? _wait;
  final CompanionHandover _handover = CompanionHandover();

  String? get _myIdentity => room.localParticipant?.identity;

  RemoteParticipant? get phone {
    final me = _myIdentity;
    if (me == null) return null;
    final id = companionIdentityFor(me);
    return room.remoteParticipants.values.firstWhereOrNull((p) => p.identity == id);
  }

  bool get phoneConnected => phone != null;

  TrackPublication? _pub(Participant? p, TrackSource source, {required bool audio}) {
    if (p == null) return null;
    final Iterable<TrackPublication> pubs = audio ? p.audioTrackPublications : p.videoTrackPublications;
    return pubs.firstWhereOrNull((t) => t.source == source);
  }

  bool get phoneIsMic => _pub(phone, TrackSource.microphone, audio: true) != null;
  bool get phoneIsCamera => _pub(phone, TrackSource.camera, audio: false) != null;
  bool get phoneIsSpeaker => phoneConnected && (request?.sources.contains(CompanionSource.speaker) ?? false);

  /// The phone's mic / camera are on (the person may have muted them on the phone).
  bool get phoneMicOn => _pub(phone, TrackSource.microphone, audio: true)?.muted == false;
  bool get phoneCamOn => _pub(phone, TrackSource.camera, audio: false)?.muted == false;

  /// The phone's camera as a track of this device (the self-view); null while it shows no picture.
  VideoTrack? get phoneVideo {
    final t = _pub(phone, TrackSource.camera, audio: false);
    final track = t?.track;
    return t != null && !t.muted && track is VideoTrack ? track : null;
  }

  void start() {
    _listener = room.createListener()
      ..on<ParticipantConnectedEvent>((e) => _onParticipant(e.participant))
      ..on<ParticipantDisconnectedEvent>((e) => _onParticipantGone(e.participant))
      ..on<TrackPublishedEvent>((e) => _changed(e.participant))
      ..on<TrackUnpublishedEvent>((e) => _changed(e.participant))
      ..on<TrackSubscribedEvent>((e) {
        _changed(e.participant);
        _applyPlayback();
      })
      ..on<TrackMutedEvent>((e) => _changed(e.participant))
      ..on<TrackUnmutedEvent>((e) => _changed(e.participant));
    _events = LiveEvents.instance.listen({LiveEvents.liveCompanionState}, _onServerEvent);
    unawaited(_restore());
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_listener?.dispose());
    _events?.cancel();
    _wait?.stop();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// The page came back (a reload of the room, the sheet reopened): pick up what the server still holds.
  Future<void> _restore() async {
    try {
      final r = await _api.current(ref);
      if (r == null || _disposed) return;
      request = r;
      wanted = r.sources.isEmpty ? wanted : r.sources;
      stage = r.pending ? CompanionStage.ringing : CompanionStage.connecting;
      if (r.pending) _startWait();
      _sync();
    } catch (e) {
      log('[LIVE] companion restore: $e');
    }
  }

  void _changed(Participant p) {
    if (p.identity != phone?.identity) return;
    _sync();
  }

  void _onParticipant(RemoteParticipant p) {
    if (p.identity != companionIdentityFor(_myIdentity ?? '')) return;
    _stopWait();
    stage = CompanionStage.active;
    error = null;
    _sync();
    _applyPlayback();
    _notify();
    host.companionNotice(t('هاتفك متصل', 'Your phone is connected'));
  }

  /// The phone left the room. A phone that was active and left on its own (battery, network, killed) is a drop: this
  /// device takes everything back and says so. Ended by the person, or by the room, says less.
  void _onParticipantGone(RemoteParticipant p) {
    if (p.identity != companionIdentityFor(_myIdentity ?? '')) return;
    final wasActive = stage == CompanionStage.active || stage == CompanionStage.connecting;
    final endedOnPurpose = _endedByPerson;
    _endedByPerson = false;
    final id = request?.id;
    _clearRun();
    _sync();
    if (wasActive && !endedOnPurpose) {
      host.companionNotice(
          t('انقطع هاتفك. عاد الميكروفون والكاميرا إلى هذا الجهاز.',
              'Your phone disconnected. This device is back on its own microphone and camera.'),
          error: true);
      if (id != null) unawaited(_api.end(id, reason: 'phone_left').then((_) {}, onError: (_) {}));
    }
  }

  void _clearRun() {
    _stopWait();
    request = null;
    secret = null;
    noPhoneToPush = false;
    stage = CompanionStage.idle;
    _notify();
  }

  void _onServerEvent(LiveEvent e) {
    final r = request;
    if (r == null || '${e.data['id']}' != '${r.id}') return;
    final status = CompanionStatus.parse(e.data['status']);
    if (status == CompanionStatus.active) {
      final sources = CompanionSource.parseAll(e.data['sources']);
      if (sources.isNotEmpty) request = _withSources(r, sources);
      if (stage == CompanionStage.ringing) stage = CompanionStage.connecting;
      _sync();
      _notify();
    } else if (status != CompanionStatus.pending && status != CompanionStatus.none) {
      _serverEnded(status, '${e.data['reason'] ?? ''}');
    }
  }

  CompanionRequest _withSources(CompanionRequest r, Set<CompanionSource> s) => CompanionRequest(
      id: r.id,
      status: r.status,
      kind: r.kind,
      refId: r.refId,
      sources: s,
      title: r.title,
      originLabel: r.originLabel,
      expiresIn: r.expiresIn,
      primaryIdentity: r.primaryIdentity);

  void _serverEnded(CompanionStatus status, String reason) {
    final wasRinging = stage == CompanionStage.ringing || stage == CompanionStage.connecting;
    if (!wasRinging) return; // an active phone reports its own leaving through the room
    _clearRun();
    if (status == CompanionStatus.declined) {
      host.companionNotice(t('رفضت الطلب من هاتفك.', 'You declined on your phone.'));
    } else if (status == CompanionStatus.expired) {
      error = t('لم يصل هاتفك في الوقت المحدد. أعد المحاولة أو امسح رمز الاستجابة.',
          'Your phone did not answer in time. Try again or scan the QR code.');
      _notify();
    }
  }

  void _sync() {
    final me = room.localParticipant;
    if (me == null || _disposed) return;
    final actions = _handover.sync(
      phoneHasMic: phoneIsMic,
      phoneHasCam: phoneIsCamera,
      phoneSpeaker: phoneIsSpeaker,
      webMicOn: host.webMicOn,
      webCamOn: host.webCamOn,
    );
    if (actions.webMic != null) {
      unawaited(host.setWebMic(actions.webMic!).catchError((Object e) => log('[LIVE] companion mic: $e')));
    }
    if (actions.webCam != null) {
      unawaited(host.setWebCam(actions.webCam!).catchError((Object e) => log('[LIVE] companion cam: $e')));
    }
    if (actions.roomAudioMuted != null) _applyPlayback();
    _notify();
  }

  /// This device plays the room unless the phone is the speaker; it never plays its own phone's mic.
  void _applyPlayback() {
    if (_disposed) return;
    final speakerOnPhone = phoneIsSpeaker;
    final myPhone = phone?.identity;
    for (final p in room.remoteParticipants.values) {
      for (final pub in p.audioTrackPublications) {
        final track = pub.track;
        if (track is! RemoteAudioTrack) continue;
        platform.companionSetPlayback(track.getCid(), track.mediaStreamTrack,
            muted: speakerOnPhone || p.identity == myPhone);
      }
    }
  }

  // ── actions ─────────────────────────────────────────────────────────────────────────────────────────────

  Future<void> _call(Future<void> Function() fn) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await fn();
    } on ApiException catch (e) {
      error = (e.code != null ? companionErrorText(e.code!) : null) ?? e.message;
    } catch (e) {
      error = t('تعذّر ذلك. حاول مرة أخرى.', 'That did not work. Try again.');
      log('[LIVE] companion: $e');
    } finally {
      busy = false;
      _notify();
    }
  }

  void setWanted(Set<CompanionSource> s) {
    wanted = s;
    _notify();
  }

  /// Ring the phone with [wanted].
  Future<void> ask() => _call(() async {
        final r = await _api.ask(ref, wanted, originLabel: platform.companionOriginLabel());
        request = r;
        secret = r.secret;
        noPhoneToPush = !r.pushed;
        stage = CompanionStage.ringing;
        _startWait();
      });

  void _startWait() {
    _stopWait();
    final w = EventOrPoll(
      poll: _poll,
      every: const Duration(seconds: 5),
      names: const {LiveEvents.liveCompanionState},
    );
    _wait = w;
    w.start();
  }

  void _stopWait() {
    _wait?.stop();
    _wait = null;
  }

  Future<void> _poll() async {
    final r = await _api.current(ref);
    if (_disposed) return;
    if (r == null) {
      // No pending or active row: the server ended it (expired, declined, cancelled) and the event was lost.
      if (stage == CompanionStage.ringing) {
        _clearRun();
        error = t('انتهى الطلب.', 'The request ended.');
        _notify();
      }
      return;
    }
    request = _withSources(r, r.sources);
    if (r.active && stage == CompanionStage.ringing) stage = CompanionStage.connecting;
    _notify();
  }

  /// Cancel while it rings.
  Future<void> cancel() => _call(() async {
        final id = request?.id;
        _clearRun();
        if (id != null) await _api.end(id, reason: 'cancelled');
      });

  /// Stop using the phone; it leaves the room, this device takes everything back.
  Future<void> stop() => _call(() async {
        final id = request?.id;
        if (id == null) return;
        _endedByPerson = true;
        _send({'t': 'bye'});
        await _api.end(id, reason: 'web');
      });

  /// Change what the running phone provides. The server's rights change first, then the phone is told.
  Future<void> setSources(Set<CompanionSource> s) => _call(() async {
        final r = request;
        wanted = s;
        if (r == null) return;
        final updated = await _api.setSources(r.id, s);
        request = _withSources(updated, updated.sources);
        _send({
          't': 'sources',
          'sources': [for (final x in updated.sources) x.wire]
        });
        _sync();
      });

  void _send(Map<String, Object?> m) {
    final me = room.localParticipant;
    final to = phone?.identity;
    if (me == null || to == null) return;
    unawaited(me
        .publishData(companionPacket(m), reliable: true, destinationIdentities: [to], topic: kCompanionTopic)
        .catchError((Object e) => log('[LIVE] companion send: $e')));
  }

  /// The bar's mic / camera while the phone provides it: the same taps reach the phone.
  void setPhoneMic(bool on) => _send({'t': 'set', 'mic': on});
  void setPhoneCam(bool on) => _send({'t': 'set', 'cam': on});
  void flipPhoneCamera() => _send({'t': 'set', 'flip': true});

  /// The room is closing on this side: end the phone first.
  Future<void> shutdown() async {
    final id = request?.id;
    _send({'t': 'bye'});
    if (id != null && stage != CompanionStage.idle) {
      await _api.end(id, reason: 'web').timeout(const Duration(seconds: 4), onTimeout: () {});
    }
  }
}

/// Bilingual text for the server's codes.
String? companionErrorText(String code) => switch (code) {
      'not_in_room' => t('انضم إلى الجلسة أولًا.', 'Join the session first.'),
      'same_device' => t('افتح الطلب من هاتفك، لا من هذا الجهاز.', 'Open this on your phone, not on this device.'),
      'companion_expired' => t('انتهت مهلة الطلب.', 'The request expired.'),
      'companion_not_pending' => t('تمت الإجابة على هذا الطلب.', 'This request was already answered.'),
      'participant_removed' => t('أزالك المضيف من هذه الغرفة.', 'The host removed you from this room.'),
      'source_not_allowed' => t('المضيف لم يسمح بهذا الجهاز الآن.', 'The host has not allowed this device right now.'),
      'not_your_request' => t('هذا الطلب ليس لحسابك.', 'This request is not for your account.'),
      'feature_disabled' => t('هذه الميزة متوقفة حاليًا.', 'This feature is switched off right now.'),
      'live_not_started' => t('انتهت هذه الجلسة.', 'This session has ended.'),
      _ => null,
    };
