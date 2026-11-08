// lib/features/shared/live/live_host_handover.dart
//
// End or leave a meeting, and hand the host controls over before leaving (D-310). Meetings only: a course session
// keeps its own End flow.
//
//   LiveEndChoice / LiveEndChoiceBody / showLiveEndChoiceSheet
//       the host's End: two large choices, "End meeting for everyone" (danger; says the recording is saved) and
//       "Leave meeting" (the others stay), plus Cancel. Plain values; test/ui/live_host_handover_layout_test.dart.
//   LiveHandoverCandidate / liveHandoverCandidates / LiveHandoverBody / showLiveHandoverSheet
//       after Leave, while someone signed in is still in the room: "Give someone host controls for this meeting?" —
//       pick a person → Make host and leave; "No, just leave" leaves without handing over; closing the sheet stays.
//   MeetingHostApi
//       POST /api/v1/live/meeting/{id}/host {user_id} (the current host only) · GET the same path (who hosts now).
//   kLiveHostTopic / liveHostPacket / liveHostFromPacket
//       the leaving host's LiveKit data message (topic `host`): a HINT that the room has a new host. The new host's
//       room confirms it with GET …/host before it takes the controls; the server's `live_host_changed` event
//       (LiveEvents.liveHostChanged) says the same. Only the server decides who may act as host.
//
// "Host for this meeting only": the server stores an acting host on the meeting's room; the person's role and the
// meeting's owner never change, and it ends when the room closes. Kill switch `live.host_handover` (the Leave choice
// then just leaves). Strings: t(ar, en).
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/theme/theme_config_provider.dart';
import '../../../core/api_client.dart';
import '../../../design/app_icons.dart';
import '../../../design/app_kit.dart';
import '../../admin/admin_common.dart' show t;
import '../../teacher/sessions/live/widgets/live_avatar.dart';

const String kLiveHostHandoverFeatureKey = 'live.host_handover';

// ── what the host chose ─────────────────────────────────────────────────────────────────────────────────────────

enum LiveEndChoice { endForAll, leave }

/// The End sheet's body (plain values). [onChoose] gets the choice; [onCancel] closes it.
class LiveEndChoiceBody extends StatelessWidget {
  const LiveEndChoiceBody({
    super.key,
    required this.onChoose,
    required this.onCancel,
    this.recording = false,
    this.canEndForAll = true,
    this.others = 0,
  });

  final ValueChanged<LiveEndChoice> onChoose;
  final VoidCallback onCancel;

  /// A recording is running on this device: ending says it is saved.
  final bool recording;

  /// End for everyone is offered (the host controls are on).
  final bool canEndForAll;

  /// How many other people are in the room.
  final int others;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final endLine = recording
        ? t('يخرج الجميع الآن، ويُحفظ التسجيل.', 'Everyone leaves now. The recording is saved.')
        : t('يخرج الجميع الآن ويُغلق الاجتماع.', 'Everyone leaves now and the meeting closes.');
    final leaveLine = others > 0
        ? t('يستمر الاجتماع للآخرين، ويمكنك تسليم إدارته لأحدهم.',
            'The meeting goes on for the others. You can hand the host controls to someone.')
        : t('يبقى الاجتماع مفتوحًا، ويمكنك العودة إليه.', 'The meeting stays open. You can come back to it.');
    return AppSheetContent(
      title: t('إنهاء الاجتماع أم مغادرته؟', 'End or leave the meeting?'),
      children: [
        if (canEndForAll) ...[
          _ChoiceCard(
            key: const ValueKey('live_end.end_all'),
            icon: Icons.call_end_rounded,
            tone: c.danger,
            tint: c.dangerTint,
            title: t('إنهاء الاجتماع للجميع', 'End meeting for everyone'),
            subtitle: endLine,
            onTap: () => onChoose(LiveEndChoice.endForAll),
          ),
          const SizedBox(height: AppSpace.sm),
        ],
        _ChoiceCard(
          key: const ValueKey('live_end.leave'),
          icon: DirIcons.logout,
          tone: c.primary,
          tint: c.primaryTint,
          title: t('مغادرة الاجتماع', 'Leave meeting'),
          subtitle: leaveLine,
          onTap: () => onChoose(LiveEndChoice.leave),
        ),
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          height: AppTouch.min,
          child: TextButton(
            key: const ValueKey('live_end.cancel'),
            onPressed: onCancel,
            child: Text(t('إلغاء', 'Cancel'), style: AppType.bodyStrong(context).copyWith(color: c.textMedium)),
          ),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.tone,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color tone;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: tone.withValues(alpha: 0.45), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary + AppSpace.md),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(children: [
                Container(
                  width: AppTouch.min,
                  height: AppTouch.min,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  child: Icon(icon, color: tone, size: 24),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, style: AppType.bodyStrong(context).copyWith(color: tone)),
                    const SizedBox(height: AppSpace.xxs),
                    Text(subtitle, style: AppType.meta(context)),
                  ]),
                ),
                const SizedBox(width: AppSpace.xs),
                Icon(Icons.chevron_right_rounded, color: c.textLight),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The host's End sheet. Null = cancelled (stay in the room).
Future<LiveEndChoice?> showLiveEndChoiceSheet(BuildContext context,
        {bool recording = false, bool canEndForAll = true, int others = 0}) =>
    showAppSheet<LiveEndChoice>(
      context,
      (ctx) => LiveEndChoiceBody(
        recording: recording,
        canEndForAll: canEndForAll,
        others: others,
        onChoose: (v) => Navigator.pop(ctx, v),
        onCancel: () => Navigator.pop(ctx),
      ),
    );

// ── handing the host controls over ──────────────────────────────────────────────────────────────────────────────

/// A signed-in person in the room who may take the host controls.
class LiveHandoverCandidate {
  const LiveHandoverCandidate({required this.userId, required this.identity, required this.name, this.imageUrl});

  final int userId;

  /// The LiveKit identity (`meet_<userId>`).
  final String identity;
  final String name;
  final String? imageUrl;
}

/// The user id of a meeting member's LiveKit identity (`meet_<id>`); null for a guest or anything else.
int? liveMeetingUserId(String identity) {
  const prefix = 'meet_';
  if (!identity.startsWith(prefix)) return null;
  return int.tryParse(identity.substring(prefix.length));
}

/// Who may take over: every remote participant with a meeting member identity (never a guest, never me), once
/// each, sorted by name. [people] = (identity, name, imageUrl) of the remote participants.
List<LiveHandoverCandidate> liveHandoverCandidates(
  Iterable<({String identity, String name, String? imageUrl})> people, {
  required String localIdentity,
}) {
  final seen = <int>{};
  final out = <LiveHandoverCandidate>[];
  for (final p in people) {
    final id = liveMeetingUserId(p.identity);
    if (id == null || p.identity == localIdentity || !seen.add(id)) continue;
    final name = p.name.trim().isEmpty ? '#$id' : p.name.trim();
    out.add(LiveHandoverCandidate(userId: id, identity: p.identity, name: name, imageUrl: p.imageUrl));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// What the person decided after Leave. Null (the sheet closed) = stay in the room.
class LiveHandoverOutcome {
  const LiveHandoverOutcome.handedTo(int this.userId);
  const LiveHandoverOutcome.justLeave() : userId = null;

  /// Who now hosts; null = left without handing over.
  final int? userId;
}

/// The handover sheet's body (plain values).
class LiveHandoverBody extends StatelessWidget {
  const LiveHandoverBody({
    super.key,
    required this.people,
    required this.onSelect,
    required this.onConfirm,
    required this.onJustLeave,
    this.selectedId,
    this.busy = false,
    this.error,
  });

  final List<LiveHandoverCandidate> people;
  final int? selectedId;
  final ValueChanged<int> onSelect;

  /// Make the selected person host, then leave (disabled until someone is picked).
  final VoidCallback onConfirm;
  final VoidCallback onJustLeave;

  /// The handover is being sent.
  final bool busy;

  /// Why the last handover failed (shown above the buttons).
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final picked = selectedId != null && people.any((p) => p.userId == selectedId);
    return AppSheetContent(
      title: t('تسليم إدارة الاجتماع لشخص آخر؟', 'Give someone host controls?'),
      children: [
        Text(
          t('لهذا الاجتماع فقط: يستطيع قبول المنتظرين وإدارة المشاركين والتسجيل وإنهاء الاجتماع. لا يتغيّر شيء في حسابه.',
              'For this meeting only: they can admit people, manage participants, record and end the meeting. '
                  'Nothing changes on their account.'),
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.md),
        for (final p in people) ...[
          _PersonTile(
            key: ValueKey('live_handover.person.${p.userId}'),
            person: p,
            selected: p.userId == selectedId,
            onTap: busy ? null : () => onSelect(p.userId),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpace.xs),
          AppBanner(icon: Icons.error_outline_rounded, text: error!, color: c.danger),
        ],
        const SizedBox(height: AppSpace.md),
        SizedBox(
          height: AppTouch.primary,
          child: FilledButton.icon(
            key: const ValueKey('live_handover.confirm'),
            onPressed: picked && !busy ? onConfirm : null,
            icon: busy
                ? SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.onHero))
                : const Icon(Icons.admin_panel_settings_rounded),
            label: Text(t('اجعله المضيف وغادر', 'Make host and leave'), maxLines: 2, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        SizedBox(
          height: AppTouch.min,
          child: TextButton(
            key: const ValueKey('live_handover.just_leave'),
            onPressed: busy ? null : onJustLeave,
            child: Text(t('لا، غادر فقط', 'No, just leave'), style: AppType.bodyStrong(context).copyWith(color: c.textMedium)),
          ),
        ),
      ],
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({super.key, required this.person, required this.selected, required this.onTap});

  final LiveHandoverCandidate person;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      label: person.name,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.primaryTint : c.cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: selected ? c.primary : c.divider, width: selected ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTouch.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
              child: Row(children: [
                LiveAvatar(name: person.name, imageUrl: person.imageUrl, size: 40, ring: false, shadow: false),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(person.name,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(context)),
                ),
                const SizedBox(width: AppSpace.xs),
                Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    color: selected ? c.primary : c.textLight),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// After Leave: pick someone to host, or just leave. [handOver] sends the handover (true = done; on false the
/// sheet stays open with [errorText]). Null = the sheet was closed (stay in the room).
Future<LiveHandoverOutcome?> showLiveHandoverSheet(
  BuildContext context, {
  required List<LiveHandoverCandidate> people,
  required Future<String?> Function(LiveHandoverCandidate person) handOver,
}) =>
    showAppSheet<LiveHandoverOutcome>(context, (_) => _HandoverSheet(people: people, handOver: handOver));

class _HandoverSheet extends StatefulWidget {
  const _HandoverSheet({required this.people, required this.handOver});

  final List<LiveHandoverCandidate> people;

  /// Null = handed over; else the error text.
  final Future<String?> Function(LiveHandoverCandidate person) handOver;

  @override
  State<_HandoverSheet> createState() => _HandoverSheetState();
}

class _HandoverSheetState extends State<_HandoverSheet> {
  int? _selected;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.people.length == 1) _selected = widget.people.first.userId; // one person: already picked
  }

  Future<void> _confirm() async {
    final id = _selected;
    final person = widget.people.where((p) => p.userId == id).firstOrNull;
    if (person == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.handOver(person);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, LiveHandoverOutcome.handedTo(person.userId));
    } else {
      setState(() {
        _busy = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => LiveHandoverBody(
        people: widget.people,
        selectedId: _selected,
        busy: _busy,
        error: _error,
        onSelect: (id) => setState(() {
          _selected = id;
          _error = null;
        }),
        onConfirm: _confirm,
        onJustLeave: () => Navigator.pop(context, const LiveHandoverOutcome.justLeave()),
      );
}

/// The handover is switched on (kill switch `live.host_handover`).
bool get liveHostHandoverOn => !AppConfig.disableList.contains(kLiveHostHandoverFeatureKey);

/// The error text of a failed handover.
String liveHandoverErrorText(Object e) {
  final err = ApiException.from(e);
  return switch (err.code) {
    'target_not_in_room' => t('لم يعد هذا الشخص في الاجتماع. اختر شخصًا آخر.',
        'This person is no longer in the meeting. Pick someone else.'),
    'not_host' => t('لم تعد مضيف هذا الاجتماع.', 'You are no longer the host of this meeting.'),
    _ => err.message,
  };
}

// ── the API ─────────────────────────────────────────────────────────────────────────────────────────────────────

/// Who hosts a meeting's room now.
class MeetingHostState {
  const MeetingHostState({required this.hostId, required this.ownerId, this.acting = false, this.isHost = false});

  factory MeetingHostState.fromJson(Map<String, dynamic> j) => MeetingHostState(
        hostId: int.tryParse('${j['host_id'] ?? ''}') ?? 0,
        ownerId: int.tryParse('${j['owner_id'] ?? ''}') ?? 0,
        acting: j['acting'] == true,
        isHost: j['is_host'] == true,
      );

  final int hostId;
  final int ownerId;

  /// Someone other than the owner hosts (a handover).
  final bool acting;

  /// The caller hosts.
  final bool isHost;
}

class MeetingHostApi {
  MeetingHostApi(this.meetingId, {ApiClient? api}) : _api = api ?? ApiClient();

  final int meetingId;
  final ApiClient _api;

  static String hostPath(int meetingId) => '/api/v1/live/meeting/$meetingId/host';

  static Map<String, dynamic> handOverBody(int userId) => {'user_id': userId};

  Future<MeetingHostState> handOver(int userId) async =>
      MeetingHostState.fromJson(_map(await _api.post(hostPath(meetingId), body: handOverBody(userId))));

  Future<MeetingHostState> current() async => MeetingHostState.fromJson(_map(await _api.get(hostPath(meetingId))));

  static Map<String, dynamic> _map(dynamic r) {
    final d = r is Map && r['data'] is Map ? r['data'] : r;
    return d is Map ? Map<String, dynamic>.from(d) : const {};
  }
}

// ── the room's data message ─────────────────────────────────────────────────────────────────────────────────────

const String kLiveHostTopic = 'host';

/// "The host is now [hostIdentity]" — sent by the leaving host right after the server accepted the handover.
List<int> liveHostPacket(String hostIdentity) => utf8.encode(jsonEncode({'v': 1, 't': 'host', 'host': hostIdentity}));

/// The new host's identity from a `host` packet; null for anything else (an unknown version is still read).
String? liveHostFromPacket(List<int> bytes) {
  try {
    final j = jsonDecode(utf8.decode(bytes));
    if (j is! Map || j['t'] != 'host') return null;
    final h = '${j['host'] ?? ''}';
    return h.isEmpty ? null : h;
  } catch (_) {
    return null;
  }
}
