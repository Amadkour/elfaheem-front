// lib/features/live/meeting_info_sheet.dart
//
// The room's (i) sheet (docs/backend/live-rooms-spec.md §11): what this room is and how it runs, for everyone in
// it — title, kind, host, scheduled time, how long you have been in, participants, your role, the recording state,
// the free time left; and for the host the share link with Copy and the admission rules.
//
//   MeetingInfo          plain values (built by room.dart every second while the sheet is open).
//   MeetingInfoSheet     the layout (plain values; test/ui/meeting_info_layout_test.dart).
//   showMeetingInfoSheet opens it over the room: a 1 s ticker re-reads the room's snapshot, and for the host the
//                        policy (link + admission) is fetched once through LiveRoomApi.
//
// Part 3 (spec §16): "Live for" counts from the room's real start (`live_started_at` → RoomPage.liveStartedAt →
// MeetingInfo.liveFor, meetingLiveFor) and falls back to the person's own time in the room when it is unknown.
//
// Strings: t(ar, en). Times: AppTime.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppOdometer;
import 'package:flutter_education_app/features/admin/admin_common.dart' show t;
import 'package:flutter_education_app/features/live/live_lobby_sheets.dart' show copyLiveLink;
import 'package:flutter_education_app/features/live/live_room.dart';
import 'package:flutter_education_app/features/live/live_time_limit.dart' show LiveTimeLimit;

/// Who you are in this room.
enum LiveRoomRole { host, member, guest }

/// What the room's recorder is doing.
enum LiveInfoRecording { off, recording, paused, server }

/// How long the room has been live at [nowUtc], from its real start [liveStartedAt] (the server's
/// `live_started_at`); never less than [own] (the person's own time in it — a device clock behind the server's would
/// otherwise show less, or a negative). Null when the start is unknown: the sheet then shows [own].
Duration? meetingLiveFor(DateTime? liveStartedAt, DateTime nowUtc, {Duration own = Duration.zero}) {
  if (liveStartedAt == null) return null;
  final d = nowUtc.toUtc().difference(liveStartedAt.toUtc());
  return d < own ? own : d;
}

class MeetingInfo {
  const MeetingInfo({
    required this.title,
    required this.isMeeting,
    required this.role,
    this.hostName,
    this.startsAt,
    this.elapsed = Duration.zero,
    this.liveFor,
    this.participants = 1,
    this.recording = LiveInfoRecording.off,
    this.freeLeft,
    this.linkUrl,
    this.linkLoading = false,
    this.linkDirect = false,
    this.admission,
    this.guestAdmission,
  });

  final String title;
  final bool isMeeting;
  final LiveRoomRole role;
  final String? hostName;

  /// Scheduled start (UTC), meetings.
  final DateTime? startsAt;

  /// Time spent in the room so far.
  final Duration elapsed;

  /// How long the room has been live (from `live_started_at`, [meetingLiveFor]); null = unknown → [elapsed].
  final Duration? liveFor;
  final int participants;
  final LiveInfoRecording recording;

  /// Free time left (a student's meeting); null = no limit (or the owner subscribed).
  final Duration? freeLeft;

  // ── Host only ──────────────────────────────────────────────────────────────
  final String? linkUrl;
  final bool linkLoading;
  final bool linkDirect;
  final LiveAdmission? admission;
  final LiveGuestAdmission? guestAdmission;

  bool get isHost => role == LiveRoomRole.host;

  /// The same snapshot with the host's fetched data (policy / link) laid over it.
  MeetingInfo withHostData({
    String? linkUrl,
    bool linkLoading = false,
    bool linkDirect = false,
    LiveAdmission? admission,
    LiveGuestAdmission? guestAdmission,
  }) =>
      MeetingInfo(
        title: title,
        isMeeting: isMeeting,
        role: role,
        hostName: hostName,
        startsAt: startsAt,
        elapsed: elapsed,
        liveFor: liveFor,
        participants: participants,
        recording: recording,
        freeLeft: freeLeft,
        linkUrl: linkUrl,
        linkLoading: linkLoading,
        linkDirect: linkDirect,
        admission: admission,
        guestAdmission: guestAdmission,
      );
}

/// Opens the info sheet over the room. [snapshot] is read every second (elapsed time, participants, recording,
/// free time); for the host the policy is fetched once ([api] defaults to `LiveRoomApi(ref)`).
Future<void> showMeetingInfoSheet(
  BuildContext context, {
  required LiveRoomRef ref,
  required MeetingInfo Function() snapshot,
  LiveRoomApi? api,
}) =>
    showAppSheet<void>(context, (_) => _MeetingInfoLive(ref: ref, snapshot: snapshot, api: api));

class _MeetingInfoLive extends StatefulWidget {
  const _MeetingInfoLive({required this.ref, required this.snapshot, this.api});

  final LiveRoomRef ref;
  final MeetingInfo Function() snapshot;
  final LiveRoomApi? api;

  @override
  State<_MeetingInfoLive> createState() => _MeetingInfoLiveState();
}

class _MeetingInfoLiveState extends State<_MeetingInfoLive> {
  late final LiveRoomApi _api = widget.api ?? LiveRoomApi(widget.ref);
  Timer? _tick;
  bool _loading = false;
  LiveLink? _link;
  LiveAdmission? _admission;
  LiveGuestAdmission? _guestAdmission;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.snapshot().isHost) unawaited(_loadHost());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _loadHost() async {
    setState(() => _loading = true);
    try {
      final p = await _api.policy();
      _link = p.link;
      _admission = p.admission;
      _guestAdmission = p.guestAdmission;
    } catch (_) {
      // An older server without the policy route: the link alone.
      try {
        _link = await _api.link();
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot();
    final info = s.isHost
        ? s.withHostData(
            linkUrl: _link?.url,
            linkLoading: _loading,
            linkDirect: _link?.direct ?? false,
            admission: _admission,
            guestAdmission: _guestAdmission,
          )
        : s;
    return MeetingInfoSheet(info: info, onCopyLink: info.linkUrl == null ? null : () => copyLiveLink(info.linkUrl!));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Layout
// ─────────────────────────────────────────────────────────────────────────────

class MeetingInfoSheet extends StatelessWidget {
  const MeetingInfoSheet({super.key, required this.info, this.onCopyLink});

  final MeetingInfo info;

  /// Host: copies the share link (null hides the button).
  final VoidCallback? onCopyLink;

  static String _elapsed(Duration d) => LiveTimeLimit.format(d);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = info;
    final kind = i.isMeeting ? t('اجتماع', 'Meeting') : t('بث مباشر لمقرر', 'Course live session');
    final role = switch (i.role) {
      LiveRoomRole.host => t('المضيف', 'Host'),
      LiveRoomRole.member => t('مشارك', 'Participant'),
      LiveRoomRole.guest => t('زائر', 'Guest'),
    };
    final rec = switch (i.recording) {
      LiveInfoRecording.off => t('لا يُسجَّل', 'Not recorded'),
      LiveInfoRecording.recording => t('يُسجَّل الآن', 'Recording now'),
      LiveInfoRecording.paused => t('التسجيل متوقف مؤقتاً', 'Recording paused'),
      LiveInfoRecording.server => t('يُسجَّل', 'Being recorded'),
    };
    final title = i.title.trim().isEmpty ? kind : i.title.trim();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AppSheetHeader(tone: AppTone.info, icon: Icons.info_outline_rounded, t('عن الغرفة', 'About this room')),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.lg),
          child: Column(key: const ValueKey('meeting_info'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text(title, style: AppType.headline(context))),
            const SizedBox(height: AppSpace.xs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
              AppStatusBadge(label: kind, tone: AppTone.brand, icon: i.isMeeting ? Icons.groups_rounded : Icons.cast_for_education_rounded),
              AppStatusBadge(label: role, tone: i.isHost ? AppTone.success : AppTone.neutral, icon: Icons.badge_rounded),
              if (i.recording != LiveInfoRecording.off)
                AppStatusBadge(label: rec, tone: AppTone.danger, dot: i.recording != LiveInfoRecording.paused),
            ]),
            const SizedBox(height: AppSpace.md),
            // the sheet's one block: the room right now, as two key figures (how long it has been live, who is in it)
            _NowBlock(
              liveFor: _elapsed(i.liveFor ?? i.elapsed),
              participants: i.participants,
            ),
            const SizedBox(height: AppSpace.xs),
            if ((i.hostName ?? '').trim().isNotEmpty)
              _InfoLine(icon: Icons.person_rounded, label: t('المضيف', 'Host'), value: i.hostName!.trim()),
            if (i.startsAt != null)
              _InfoLine(icon: Icons.event_rounded, label: t('الموعد', 'Scheduled'), value: AppTime.dateTime(i.startsAt!)),
            if (i.liveFor != null)
              _InfoLine(
                key: const ValueKey('meeting_info.elapsed'),
                icon: Icons.schedule_rounded,
                label: t('مدة وجودك في الغرفة', 'Your time in the room'),
                value: _elapsed(i.elapsed),
                ltrValue: true,
              ),
            _InfoLine(icon: Icons.fiber_manual_record_rounded, label: t('التسجيل', 'Recording'), value: rec),
            if (i.freeLeft != null)
              _InfoLine(
                key: const ValueKey('meeting_info.free_left'),
                icon: Icons.hourglass_bottom_rounded,
                label: t('الوقت المجاني المتبقي', 'Free time left'),
                value: i.freeLeft == Duration.zero ? t('انتهى', 'Over') : _elapsed(i.freeLeft!),
                ltrValue: i.freeLeft != Duration.zero,
                color: i.freeLeft! <= const Duration(minutes: 3) ? c.warning : null,
              ),
            if (i.isHost) ...[
              // an editorial section: more air above the heading than below it, no rule
              Padding(
                padding: AppSpace.sectionHead,
                child: Semantics(header: true, child: Text(t('للمضيف', 'For the host'), style: AppType.section(context))),
              ),
              if (i.linkLoading)
                const SizedBox(height: AppSpace.xxxl, child: AppListSkeleton(items: 1, withAvatar: false, padding: EdgeInsets.zero))
              else if (i.linkUrl == null)
                _InfoLine(
                  icon: Icons.link_off_rounded,
                  label: t('رابط المشاركة', 'Share link'),
                  value: t('لا يوجد رابط بعد — أنشئه من غرفة الانتظار.', 'No link yet — create one from the lobby.'),
                )
              else ...[
                _InfoLine(
                  key: const ValueKey('meeting_info.link'),
                  icon: Icons.link_rounded,
                  label: i.linkDirect ? t('رابط المشاركة (دخول مباشر)', 'Share link (direct entry)') : t('رابط المشاركة', 'Share link'),
                  value: i.linkUrl!,
                  ltrValue: true,
                ),
                if (onCopyLink != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: _InfoLine.indent, bottom: AppSpace.xs),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton.secondary(
                        key: const ValueKey('meeting_info.copy_link'),
                        icon: Icons.copy_rounded,
                        label: t('نسخ الرابط', 'Copy link'),
                        size: AppButtonSize.sm,
                        onPressed: onCopyLink,
                      ),
                    ),
                  ),
              ],
              if (i.admission != null)
                _InfoLine(
                  key: const ValueKey('meeting_info.admission'),
                  icon: Icons.how_to_reg_rounded,
                  label: t('الأعضاء', 'Members'),
                  value: i.admission == LiveAdmission.approve
                      ? t('ينتظرون موافقتك', 'Wait for your approval')
                      : t('يدخلون مباشرة', 'Come straight in'),
                ),
              if (i.guestAdmission != null)
                _InfoLine(
                  key: const ValueKey('meeting_info.guest_admission'),
                  icon: Icons.door_front_door_outlined,
                  label: t('الزوار', 'Guests'),
                  value: i.linkDirect || i.guestAdmission == LiveGuestAdmission.auto
                      ? t('يدخلون مباشرة', 'Come straight in')
                      : t('ينتظرون موافقتك', 'Wait for your approval'),
                ),
            ],
          ]),
        ),
      ),
    ]);
  }
}

/// The room right now: how long it has been live and how many are in it, as the sheet's two key figures on a sky
/// block (information). The clock is plain text (it ticks every second); the head count rolls when it changes.
class _NowBlock extends StatelessWidget {
  const _NowBlock({required this.liveFor, required this.participants});

  final String liveFor;
  final int participants;

  @override
  Widget build(BuildContext context) {
    final bc = AppBlockColors.of(context, AppBlockTone.sky);
    final figure = AppType.figureLarge(context).copyWith(color: bc.ink);
    Widget cell({required IconData icon, required String label, required Widget value}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(icon, size: AppIconSize.xs, color: bc.muted),
              const SizedBox(width: AppSpace.xxs),
              Flexible(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: bc.muted)),
              ),
            ]),
            const SizedBox(height: AppSpace.xxs),
            FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: value),
          ],
        );
    return AppBlock(
      tone: AppBlockTone.sky,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(children: [
        Expanded(
          child: cell(
            icon: Icons.sensors_rounded,
            label: t('مدة البث', 'Live for'),
            value: Text(liveFor, key: const ValueKey('meeting_info.live_for'), textDirection: TextDirection.ltr, style: figure),
          ),
        ),
        Container(
          width: AppBorder.hairline,
          height: AppSpace.xxl,
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          color: bc.faint,
        ),
        Expanded(
          child: cell(
            icon: Icons.people_alt_rounded,
            label: t('المشاركون الآن', 'Participants now'),
            value: KeyedSubtree(
              key: const ValueKey('meeting_info.participants'),
              child: AppOdometer('$participants', style: figure, textDirection: TextDirection.ltr),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Icon · label over value.
class _InfoLine extends StatelessWidget {
  const _InfoLine({super.key, required this.icon, required this.label, required this.value, this.ltrValue = false, this.color});

  final IconData icon;
  final String label;
  final String value;
  final bool ltrValue;
  final Color? color;

  /// The icon tile and the gap after it: what a follow-up action under a line indents by.
  static const double _tile = AppSpace.xl;
  static const double indent = _tile + AppSpace.sm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.primary;
    final ink = appInk(context, tone);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: _tile,
          height: _tile,
          decoration: BoxDecoration(color: tone.withValues(alpha: 0.10), borderRadius: AppRadius.chipAll),
          child: Icon(icon, size: AppIconSize.sm, color: ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.meta(context)),
            const SizedBox(height: AppSpace.xxs / 2),
            Text(
              value,
              textDirection: ltrValue ? TextDirection.ltr : null,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong(context).copyWith(color: color == null ? null : ink, height: 1.35),
            ),
          ]),
        ),
      ]),
    );
  }
}
