// lib/features/live/live_participant_controls.dart
//
// The UI of the host's ("teacher") controls in a live room (live hardening L2). Pure parts and the API are in
// live_controls_api.dart; how the room plugs these in: docs/live/teacher_controls_wiring.md. The presentational
// widgets take plain values + callbacks so the layout harness can pump them (test/ui/live_participant_controls_
// layout_test.dart):
//
//   LiveHostControlsController   ChangeNotifier the host's room creates once: runs every action through
//                                LiveControlsApi, keeps what is in flight (per participant, mute all, lock, end),
//                                the lock state, and tells the result with showAppNotice (bilingual error text from
//                                liveControlsError).
//   LiveParticipantActionsBody   the per-participant sheet: avatar, name, what they publish now, one 56 px row per
//                                action (mute mic · allow mic · stop camera · stop share · allow / revoke screen
//                                share · allow / revoke drawing · remove), the row in flight shows a spinner.
//   showLiveParticipantControls  opens it (showAppSheet), confirms Remove (appConfirm), closes on success.
//   LiveParticipantControlsButton the ⋮ of a participant row in the room's panel (48 px, labelled).
//   LiveHostControlsBar          the participants panel's host strip on the dark room backdrop (LivePalette):
//                                Mute all · End for everyone · the Lock room toggle with its state.
//   LiveHostControlsHeader       the bar wired to the controller (confirms End for everyone).
//
// Kill switches: everything but the lock under `live.teacher_controls`, the lock under `live.room_lock`
// (ParentComponent). Strings: t(ar, en) like the other live files (no translation.json edits).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/room/widgets/live_palette.dart';
import 'package:flutter_education_app/features/live/live_controls_api.dart';
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_room_words.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// Sends the annotation permission packet to one participant (the annotation layer owns its format).
typedef LiveDrawingPermissionSender = Future<void> Function(String identity, bool allow);

/// How a result is told; tests pass their own.
typedef LiveControlsNotice = void Function(String message, {bool error});

void _appNotice(String message, {bool error = false}) => showAppNotice(message, error: error);

// ─────────────────────────────────────────────────────────────────────────────
// Controller
// ─────────────────────────────────────────────────────────────────────────────

/// One room's host controls. The room creates it for a host (`widget.host && !widget.isGuest`), calls [loadLock]
/// once connected, and disposes it with the room.
class LiveHostControlsController extends ChangeNotifier {
  LiveHostControlsController(this.ref, {LiveControlsApi? api, LiveControlsNotice? notice, this.onDrawingChanged})
      : api = api ?? LiveControlsApi(ref),
        _notice = notice ?? _appNotice;

  final LiveRoomRef ref;
  final LiveControlsApi api;
  final LiveControlsNotice _notice;

  /// Sends the annotation permission packet; null → the drawing toggle only changes `can_publish_data`.
  LiveDrawingPermissionSender? onDrawingChanged;

  /// One share at a time (live_share_arbiter.dart): "Stop screen share" goes through the room, which asks the
  /// presenter's app to stop (a clean stop, their notice) and keeps the server mute as the fallback. Null → the
  /// server mute alone.
  Future<void> Function(LiveControlTarget target)? stopScreenShare;

  /// After "Revoke screen share" succeeded: the room forgets a temporary grant for that person.
  void Function(String identity)? onScreenShareRevoked;

  /// Told right before end-for-all is sent (true) and again when it failed (false): the room publishes its
  /// "ending for everyone" packet (live_end_signal.dart), so the participants the server removes read "the host
  /// ended the session" rather than "you were removed". Its errors never stop the end.
  Future<void> Function(bool ending)? onEndForAllPhase;

  Future<void> _endPhase(bool ending) async {
    try {
      await onEndForAllPhase?.call(ending);
    } catch (_) {
      // The packet is a nicety: the end goes on without it.
    }
  }

  final Map<String, LiveHostAction> _busy = {};
  bool _muteAllBusy = false;
  bool _lockBusy = false;
  bool _endBusy = false;
  LiveLockState? _lock;
  bool _lockSupported = true;
  bool _disposed = false;

  /// The action in flight for [identity], if any.
  LiveHostAction? busyFor(String identity) => _busy[identity];

  bool get muteAllBusy => _muteAllBusy;
  bool get lockBusy => _lockBusy;
  bool get endBusy => _endBusy;

  /// Null until [loadLock] answered.
  bool? get locked => _lock?.locked;
  LiveLockState? get lockState => _lock;

  /// False when the server has no lock route (an older server's bare 404 / 405): the toggle is hidden.
  bool get lockSupported => _lockSupported;

  /// Anything in flight that should disable the other room-wide buttons.
  bool get roomBusy => _muteAllBusy || _lockBusy || _endBusy;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  static bool _missingRoute(Object e) {
    final ex = ApiException.from(e);
    return (ex.statusCode == 404 || ex.statusCode == 405) && (ex.code == null || ex.code!.isEmpty);
  }

  /// Reads the lock once (silent on failure: the toggle then starts unlocked and the PUT tells the truth).
  Future<void> loadLock() async {
    try {
      _lock = await api.lock();
    } catch (e) {
      if (_missingRoute(e)) _lockSupported = false;
    }
    _changed();
  }

  /// Runs [action] on [target]; true when it succeeded. Remove is NOT confirmed here (the sheet confirms it).
  Future<bool> run(LiveControlTarget target, LiveHostAction action) async {
    final id = target.identity;
    if (_busy.containsKey(id)) return false;
    _busy[id] = action;
    _changed();
    try {
      final source = liveMuteSourceFor(action);
      if (action == LiveHostAction.stopScreenShare && stopScreenShare != null) {
        await stopScreenShare!(target);
      } else if (source != null) {
        await api.mute(id, source: source);
      } else if (action == LiveHostAction.remove) {
        await api.remove(id);
      } else if (action == LiveHostAction.allowDrawing || action == LiveHostAction.revokeDrawing) {
        final perms = livePermissionsFor(action, target.permissions);
        if (perms != null) await api.setPermissions(id, perms);
        await onDrawingChanged?.call(id, action == LiveHostAction.allowDrawing);
      } else {
        final perms = livePermissionsFor(action, target.permissions);
        if (perms != null) await api.setPermissions(id, perms);
        if (action == LiveHostAction.revokeScreenShare) onScreenShareRevoked?.call(id);
      }
      _notice(liveHostActionDone(action, target.displayName));
      return true;
    } catch (e) {
      _notice(liveControlsError(e), error: true);
      return false;
    } finally {
      _busy.remove(id);
      _changed();
    }
  }

  /// Mutes everyone but the hosts. Returns how many were muted (null on failure).
  Future<int?> muteAll({bool allowUnmute = true}) async {
    if (_muteAllBusy) return null;
    _muteAllBusy = true;
    _changed();
    try {
      final n = await api.muteAll(allowUnmute: allowUnmute);
      _notice(n == 0
          ? t('الجميع صامتون بالفعل', 'Everyone is already muted')
          : t('تم كتم $n من المشاركين', '$n participants muted'));
      return n;
    } catch (e) {
      _notice(liveControlsError(e), error: true);
      return null;
    } finally {
      _muteAllBusy = false;
      _changed();
    }
  }

  /// Locks / unlocks the room; true when the server agreed.
  Future<bool> setLocked(bool locked) async {
    if (_lockBusy) return false;
    _lockBusy = true;
    _changed();
    try {
      _lock = await api.setLock(locked);
      _notice(_lock!.locked
          ? t('تم قفل الغرفة: لن ينضم أحد جديد', 'Room locked: nobody new can join')
          : t('تم فتح الغرفة', 'Room unlocked'));
      return true;
    } catch (e) {
      if (_missingRoute(e)) _lockSupported = false;
      _notice(liveControlsError(e), error: true);
      return false;
    } finally {
      _lockBusy = false;
      _changed();
    }
  }

  /// Ends the room for everyone (NOT confirmed here). True when the server ended it.
  Future<bool> endForAll() async {
    if (_endBusy) return false;
    _endBusy = true;
    _changed();
    try {
      await _endPhase(true);
      await api.endForAll();
      _notice(liveT(null,
          ar: 'انتهت الجلسة للجميع',
          en: 'The room was ended for everyone',
          meetingAr: 'انتهى الاجتماع للجميع',
          meetingEn: 'The meeting was ended for everyone'));
      return true;
    } catch (e) {
      await _endPhase(false);
      _notice(liveControlsError(e), error: true);
      return false;
    } finally {
      _endBusy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Per-participant sheet
// ─────────────────────────────────────────────────────────────────────────────

IconData liveHostActionIcon(LiveHostAction a) => switch (a) {
      LiveHostAction.muteMic => Icons.mic_off_rounded,
      LiveHostAction.allowMic => Icons.record_voice_over_rounded,
      LiveHostAction.stopCamera => Icons.videocam_off_rounded,
      LiveHostAction.stopScreenShare => Icons.stop_screen_share_rounded,
      LiveHostAction.allowScreenShare => Icons.screen_share_rounded,
      LiveHostAction.revokeScreenShare => Icons.stop_screen_share_outlined,
      LiveHostAction.allowDrawing => Icons.draw_rounded,
      LiveHostAction.revokeDrawing => Icons.edit_off_rounded,
      LiveHostAction.remove => Icons.person_remove_rounded,
    };

/// The per-participant sheet (plain values). [busy]: the action in flight (its row spins, every row is disabled);
/// [disabled] + [note]: nothing can be done right now (e.g. the room is not live) and why.
class LiveParticipantActionsBody extends StatelessWidget {
  const LiveParticipantActionsBody({
    super.key,
    required this.target,
    required this.actions,
    required this.onAction,
    this.busy,
    this.disabled = false,
    this.note,
  });

  final LiveControlTarget target;
  final List<LiveHostAction> actions;
  final ValueChanged<LiveHostAction> onAction;
  final LiveHostAction? busy;
  final bool disabled;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = target.displayName;
    final p = target.permissions;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppSheetHeader(t('إدارة المشارك', 'Participant controls')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              AppAvatar(name: name, url: target.imageUrl, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: appText(15, w: FontWeight.w700, c: c.textDark)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (target.isGuest) AppBadgePill(t('زائر', 'Guest'), icon: Icons.link_rounded, color: c.warning),
                    AppBadgePill(
                      target.micOn ? t('الميكروفون يعمل', 'Mic on') : t('الميكروفون مغلق', 'Mic off'),
                      icon: target.micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      color: target.micOn ? c.success : c.textLight,
                    ),
                    AppBadgePill(
                      target.cameraOn ? t('الكاميرا تعمل', 'Camera on') : t('الكاميرا مغلقة', 'Camera off'),
                      icon: target.cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      color: target.cameraOn ? c.success : c.textLight,
                    ),
                    if (target.screenSharing)
                      AppBadgePill(t('يشارك الشاشة', 'Sharing screen'), icon: Icons.screen_share_rounded, color: c.primary)
                    else if (p.mayShareScreen)
                      AppBadgePill(t('مسموح بالمشاركة', 'May share'), icon: Icons.screen_share_outlined, color: c.primary),
                    if (target.drawingAllowed && p.canPublishData)
                      AppBadgePill(t('مسموح بالرسم', 'May draw'), icon: Icons.draw_rounded, color: c.primary),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            if (note != null && note!.isNotEmpty) ...[
              AppBanner(key: const ValueKey('live_controls.note'), icon: Icons.info_outline_rounded, text: note!, color: c.textMedium),
              const SizedBox(height: 8),
            ],
            if (actions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t('لا توجد إجراءات متاحة لهذا المشارك.', 'Nothing can be done for this participant.'),
                  style: appText(13, c: c.textLight),
                ),
              )
            else
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.divider),
                LiveHostActionRow(
                  key: ValueKey('live_controls.action.${actions[i].name}'),
                  action: actions[i],
                  busy: busy == actions[i],
                  enabled: !disabled && busy == null,
                  onTap: () => onAction(actions[i]),
                ),
              ],
          ]),
        ),
      ),
    ]);
  }
}

/// One action row: icon, label, 56 px tall, a spinner while it runs; Remove in the danger colour.
class LiveHostActionRow extends StatelessWidget {
  const LiveHostActionRow({super.key, required this.action, required this.onTap, this.busy = false, this.enabled = true});

  final LiveHostAction action;
  final VoidCallback onTap;
  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final danger = liveHostActionIsDestructive(action);
    final col = danger ? c.danger : c.textDark;
    final label = liveHostActionLabel(action);
    final active = enabled && !busy;
    return Semantics(
      button: true,
      enabled: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Opacity(
            opacity: active || busy ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: (danger ? c.danger : c.primary).withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(liveHostActionIcon(action), size: 20, color: danger ? c.danger : c.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: appText(14, w: FontWeight.w600, c: col))),
                if (busy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the host's sheet for [target]. Remove is confirmed first; the sheet closes once an action succeeded and
/// stays open (with the error notice) when it failed.
Future<void> showLiveParticipantControls(
  BuildContext context, {
  required LiveHostControlsController controller,
  required LiveControlTarget target,
  bool viewerIsHost = true,
  bool drawingAvailable = false,
  String? note,
}) =>
    showAppSheet<void>(
      context,
      (_) => _LiveParticipantControlsSheet(
        controller: controller,
        target: target,
        actions: liveHostActionsFor(target, viewerIsHost: viewerIsHost, drawingAvailable: drawingAvailable),
        note: note,
      ),
    );

class _LiveParticipantControlsSheet extends StatelessWidget {
  const _LiveParticipantControlsSheet({required this.controller, required this.target, required this.actions, this.note});

  final LiveHostControlsController controller;
  final LiveControlTarget target;
  final List<LiveHostAction> actions;
  final String? note;

  Future<void> _onAction(BuildContext context, LiveHostAction a) async {
    if (liveHostActionIsDestructive(a)) {
      final ok = await appConfirm(context,
          message: liveHostActionConfirm(a, target.displayName), danger: true, confirmLabel: liveHostActionLabel(a));
      if (!ok || !context.mounted) return;
    }
    final done = await controller.run(target, a);
    if (done && context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => ParentComponent(
        featureKey: kLiveTeacherControlsFeatureKey,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => LiveParticipantActionsBody(
            target: target,
            actions: actions,
            busy: controller.busyFor(target.identity),
            note: note,
            onAction: (a) => unawaited(_onAction(context, a)),
          ),
        ),
      );
}

/// The ⋮ of one participant row in the room's panel (on the dark backdrop): 48 px, labelled with the name, a
/// spinner while an action on that participant runs.
class LiveParticipantControlsButton extends StatelessWidget {
  const LiveParticipantControlsButton({super.key, required this.name, required this.onPressed, this.busy = false});

  final String name;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final label = t('إدارة $name', 'Controls for $name');
    if (busy) {
      return Semantics(
        label: label,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LivePalette.textMid))),
        ),
      );
    }
    return ParentComponent(
      featureKey: kLiveTeacherControlsFeatureKey,
      child: IconButton(
        tooltip: label,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
        icon: const Icon(Icons.more_vert_rounded, size: 20, color: LivePalette.textMid),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Host bar (participants panel)
// ─────────────────────────────────────────────────────────────────────────────

/// The participants panel's host strip, drawn on the dark room backdrop (LivePalette, derived from the app theme).
/// [locked] null = not known yet (the toggle shows unlocked and stays usable). [onLockChanged] null hides the lock
/// row (no route on an older server); [onEndForAll] null hides End for everyone. [enabled] false disables all.
class LiveHostControlsBar extends StatelessWidget {
  const LiveHostControlsBar({
    super.key,
    required this.onMuteAll,
    this.onLockChanged,
    this.onEndForAll,
    this.locked,
    this.muteAllBusy = false,
    this.lockBusy = false,
    this.endBusy = false,
    this.enabled = true,
  });

  final VoidCallback onMuteAll;
  final ValueChanged<bool>? onLockChanged;
  final VoidCallback? onEndForAll;
  final bool? locked;
  final bool muteAllBusy;
  final bool lockBusy;
  final bool endBusy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final anyBusy = muteAllBusy || lockBusy || endBusy;
    final isLocked = locked ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: LivePalette.hairline))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        ParentComponent(
          featureKey: kLiveTeacherControlsFeatureKey,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            _LiveBarButton(
              key: const ValueKey('live_controls.mute_all'),
              icon: Icons.mic_off_rounded,
              label: t('كتم الجميع', 'Mute all'),
              color: LivePalette.warning,
              busy: muteAllBusy,
              onTap: enabled && !anyBusy ? onMuteAll : null,
            ),
            if (onEndForAll != null)
              _LiveBarButton(
                key: const ValueKey('live_controls.end_for_all'),
                icon: Icons.call_end_rounded,
                label: t('إنهاء للجميع', 'End for everyone'),
                color: LivePalette.danger,
                busy: endBusy,
                onTap: enabled && !anyBusy ? onEndForAll : null,
              ),
          ]),
        ),
        if (onLockChanged != null)
          ParentComponent(
            featureKey: kLiveRoomLockFeatureKey,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _LiveLockRow(
                locked: isLocked,
                busy: lockBusy,
                onChanged: enabled && !(muteAllBusy || endBusy) && !lockBusy ? onLockChanged : null,
              ),
            ),
          ),
      ]),
    );
  }
}

class _LiveBarButton extends StatelessWidget {
  const _LiveBarButton({super.key, required this.icon, required this.label, required this.color, required this.onTap, this.busy = false});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Opacity(
            opacity: on || busy ? 1 : 0.5,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (busy)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: color))
                else
                  Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w700, color: LivePalette.textHigh)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveLockRow extends StatelessWidget {
  const _LiveLockRow({required this.locked, required this.onChanged, this.busy = false});

  final bool locked;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final title = t('قفل الغرفة', 'Lock room');
    final sub = locked
        ? t('مقفلة: لا ينضم أحد جديد', 'Locked: nobody new can join')
        : t('مفتوحة: يمكن للمدعوين الانضمام', 'Open: invited people can join');
    final col = locked ? LivePalette.warning : LivePalette.textMid;
    return Semantics(
      key: const ValueKey('live_controls.lock'),
      toggled: locked,
      enabled: onChanged != null,
      label: '$title. $sub',
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged!(!locked),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!locked),
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(children: [
                Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: col),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w700, color: LivePalette.textHigh)),
                    Text(sub,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: AppFonts.family, fontSize: 11, color: col)),
                  ]),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const SizedBox(
                      width: AppSwitch.width,
                      child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: LivePalette.textMid))))
                else
                  AppSwitch(value: locked, onChanged: onChanged, activeColor: LivePalette.warning),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The host bar wired to [controller]: Mute all, Lock room, End for everyone (confirmed). [onEnded] runs after the
/// server ended the room (the room then leaves as the host does after End). [showEndForAll] false hides it (e.g.
/// the room keeps its own End button only).
class LiveHostControlsHeader extends StatelessWidget {
  const LiveHostControlsHeader({super.key, required this.controller, this.onEnded, this.showEndForAll = true});

  final LiveHostControlsController controller;
  final VoidCallback? onEnded;
  final bool showEndForAll;

  Future<void> _end(BuildContext context) async {
    final ok = await appConfirm(context,
        message: t('إنهاء الغرفة للجميع؟ سيخرج كل المشاركين فوراً.', 'End the room for everyone? Every participant leaves at once.'),
        danger: true,
        confirmLabel: t('إنهاء للجميع', 'End for everyone'));
    if (!ok) return;
    if (await controller.endForAll()) onEnded?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => LiveHostControlsBar(
          locked: controller.locked,
          muteAllBusy: controller.muteAllBusy,
          lockBusy: controller.lockBusy,
          endBusy: controller.endBusy,
          onMuteAll: () => unawaited(controller.muteAll()),
          onLockChanged: controller.lockSupported ? (v) => unawaited(controller.setLocked(v)) : null,
          onEndForAll: showEndForAll ? () => unawaited(_end(context)) : null,
        ),
      );
}
