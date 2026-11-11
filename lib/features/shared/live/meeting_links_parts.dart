// lib/features/shared/live/meeting_links_parts.dart — the plain-values pieces of the meeting links page (D-307):
//
//   MeetingLinkCard        one room: status, kind, time, course / host, Join / Open, Copy · Share · QR, and the
//                          host's guest link (expired once the room ended)
//   MeetingLinksSummary    Live now · Upcoming · Guest links, each a tap on its filter
//   MeetingLinksFilterBar  the filter chips (one line, scrolls sideways on a phone)
//   meetingLinkDayLabel    "Today" · "Tomorrow" · "Mon 10 Nov" (the platform / organization timezone, AppTime)
//
// No provider, no API: test/ui/meeting_links_layout_test.dart lays them out at 320 and 1400 px, ar / en, text × 1.3.
library;

import 'package:flutter/material.dart';

import '../../../config/theme/theme_config_provider.dart';
import '../../../core/plural.dart';
import '../../../design/app_kit.dart';
import '../../../design/app_motion_kit.dart' show AppCountUp;
import '../../admin/admin_common.dart' show t;
import 'meeting_links.dart';

/// "Today" / "Tomorrow" / "Mon 10 Nov" for a UTC instant, against [now] (UTC).
String meetingLinkDayLabel(DateTime utc, DateTime now) {
  final d = AppTime.toZone(utc), n = AppTime.toZone(now);
  final day = DateTime(d.year, d.month, d.day), today = DateTime(n.year, n.month, n.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return t('اليوم', 'Today');
  if (diff == 1) return t('غداً', 'Tomorrow');
  if (diff == -1) return t('أمس', 'Yesterday');
  return AppTime.date(utc, pattern: 'EEEE d MMM');
}

/// "10:00 – 11:00" (or the start alone).
String meetingLinkTimeRange(MeetingLinkItem i) {
  final s = i.startsAt, e = i.endsAt;
  if (s == null) return '';
  return e == null ? AppTime.time(s) : '${AppTime.time(s)} – ${AppTime.time(e)}';
}

/// "in 40 min" / "in 3 h" for a room that has not started; null otherwise (or more than a day away).
String? meetingLinkStartsIn(MeetingLinkItem i, DateTime now) {
  final s = i.startsAt;
  if (i.status != MeetingLinkStatus.scheduled || s == null) return null;
  final mins = s.difference(now).inMinutes;
  if (mins <= 0 || mins > 24 * 60) return null;
  final h = mins ~/ 60, m = mins % 60;
  final d = h == 0 ? t('$m د', '$m min') : (m == 0 ? t('$h س', '$h h') : t('$h س $m د', '$h h $m min'));
  return t('بعد $d', 'in $d');
}

class MeetingLinkCard extends StatelessWidget {
  const MeetingLinkCard({
    super.key,
    required this.item,
    required this.now,
    required this.onOpen,
    required this.onCopy,
    required this.onShare,
    this.onJoin,
    this.onCopyGuest,
    this.onShareGuest,
    this.showDay = false,
  });

  final MeetingLinkItem item;
  final DateTime now;
  final VoidCallback onOpen, onCopy, onShare;

  /// Into the room (its pre-join page); null hides the button (a session I host opens in its course instead).
  final VoidCallback? onJoin;
  final VoidCallback? onCopyGuest, onShareGuest;

  /// Write the day in the time line (the "Live now" group, which is not under a day heading).
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final i = item;
    final live = i.status == MeetingLinkStatus.live, ended = i.status == MeetingLinkStatus.ended;
    final tone = live ? AppTone.danger : (ended ? AppTone.neutral : AppTone.info);
    final ink = appToneInk(context, tone);
    final startsIn = meetingLinkStartsIn(i, now);
    final when = [
      if (showDay && i.startsAt != null) meetingLinkDayLabel(i.startsAt!, now),
      meetingLinkTimeRange(i),
    ].where((s) => s.isNotEmpty).join(' · ');
    final who = [
      ?i.subtitle,
      ?i.orgName,
    ].join(' · ');
    final statusLabel = live
        ? t('مباشر الآن', 'Live now')
        : ended
            ? t('انتهى', 'Ended')
            : (startsIn ?? t('مجدول', 'Scheduled'));
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: AppSpace.xxl - AppSpace.xxs,
            height: AppSpace.xxl - AppSpace.xxs,
            decoration: BoxDecoration(color: appToneTint(context, tone), borderRadius: AppRadius.controlAll),
            child: Icon(i.isMeeting ? Icons.groups_rounded : Icons.live_tv_rounded, color: ink, size: AppIconSize.md),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              if (when.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(when, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
              ],
              if (who.isNotEmpty)
                Text(who, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.sm),
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          AppStatusBadge(label: statusLabel, tone: tone, dot: live, dense: true),
          AppStatusBadge(
            label: i.isMeeting ? t('اجتماع', 'Meeting') : t('حصة كورس', 'Course session'),
            tone: AppTone.neutral,
            dense: true,
          ),
          if (i.isHost) AppStatusBadge(label: t('أنت المضيف', 'You host'), tone: AppTone.brand, dense: true),
          if (i.recurring) AppStatusBadge(label: t('أسبوعي', 'Weekly'), tone: AppTone.neutral, icon: Icons.repeat_rounded, dense: true),
          if (i.myStatus == 'pending') AppStatusBadge(label: t('بانتظار ردّك', 'Awaiting your answer'), tone: AppTone.warning, dense: true),
        ]),
        if (i.guest != null) ...[
          const SizedBox(height: AppSpace.sm),
          _GuestLinkRow(link: i.guest!, onCopy: onCopyGuest, onShare: onShareGuest),
        ],
        const SizedBox(height: AppSpace.sm),
        Row(children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: onJoin != null && !ended
                  ? AppButton.primary(
                      key: ValueKey('links.join.${i.key}'),
                      label: live ? t('انضم الآن', 'Join now') : t('انضم', 'Join'),
                      icon: Icons.videocam_rounded,
                      size: AppButtonSize.sm,
                      onPressed: onJoin,
                    )
                  : AppButton.secondary(
                      key: ValueKey('links.open.${i.key}'),
                      label: i.isMeeting ? t('التفاصيل', 'Details') : t('فتح الكورس', 'Open course'),
                      icon: i.isMeeting ? Icons.event_note_rounded : Icons.school_rounded,
                      size: AppButtonSize.sm,
                      onPressed: onOpen,
                    ),
            ),
          ),
          IconButton(
            key: ValueKey('links.copy.${i.key}'),
            tooltip: t('نسخ الرابط', 'Copy link'),
            onPressed: onCopy,
            icon: Icon(Icons.copy_rounded, color: c.textMedium, size: AppIconSize.md),
          ),
          IconButton(
            key: ValueKey('links.share.${i.key}'),
            tooltip: t('مشاركة · رمز QR', 'Share · QR code'),
            onPressed: onShare,
            icon: Icon(Icons.ios_share_rounded, color: c.textMedium, size: AppIconSize.md),
          ),
        ]),
      ]),
    );
  }
}

class _GuestLinkRow extends StatelessWidget {
  const _GuestLinkRow({required this.link, this.onCopy, this.onShare});
  final MeetingGuestLink link;
  final VoidCallback? onCopy, onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final active = link.active;
    final ink = active ? appInk(context, c.primary) : c.textLight;
    final facts = [
      active ? t('رابط الضيوف', 'Guest link') : t('رابط الضيوف منتهٍ', 'Guest link expired'),
      if (link.hasPin) t('برمز PIN', 'PIN'),
      if (link.direct) t('دخول مباشر', 'Direct entry'),
      if (link.guestsJoined > 0)
        countText(link.guestsJoined,
            ar1: 'ضيف واحد', ar2: 'ضيفان', arFew: '{n} ضيوف', arMany: '{n} ضيفاً', en1: '1 guest', en: '{n} guests'),
    ];
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.sm, AppSpace.xxs, AppSpace.xxs, AppSpace.xxs),
      decoration: BoxDecoration(
        color: active ? c.primary.withValues(alpha: 0.06) : c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(children: [
        Icon(active ? Icons.public_rounded : Icons.link_off_rounded, size: AppIconSize.sm, color: ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(facts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(context).copyWith(color: ink)),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(link.url.replaceFirst(RegExp(r'^https?://'), ''), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppType.meta(context)),
            ),
          ]),
        ),
        if (active) ...[
          IconButton(
            tooltip: t('نسخ رابط الضيوف', 'Copy the guest link'),
            onPressed: onCopy,
            icon: Icon(Icons.copy_rounded, size: AppIconSize.sm, color: ink),
          ),
          IconButton(
            tooltip: t('مشاركة رابط الضيوف', 'Share the guest link'),
            onPressed: onShare,
            icon: Icon(Icons.qr_code_2_rounded, size: AppIconSize.sm, color: ink),
          ),
        ],
      ]),
    );
  }
}

/// Live now · Upcoming · Guest links: three figures, each opens its filter. While a room is live its tile is the
/// page's one tinted block (sky, the schedule's tone); the others stay paper. The figures count up once.
class MeetingLinksSummary extends StatelessWidget {
  const MeetingLinksSummary({super.key, required this.live, required this.upcoming, required this.guestLinks, required this.onFilter});
  final int live, upcoming, guestLinks;
  final ValueChanged<MeetingLinksFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int n, IconData icon, AppTone tone, MeetingLinksFilter f) {
      final lead = f == MeetingLinksFilter.live && n > 0;
      final bc = lead ? AppBlockColors.of(context, AppBlockTone.sky) : null;
      final iconInk = bc == null ? appToneInk(context, tone) : bc.accentInk(appToneColor(context, tone));
      // the figure beside its icon, the label under both on the card's full width (fits a 320 px phone)
      final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: AppIconSize.md, color: iconInk),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: AppCountUp(
              '$n',
              memoryKey: 'links.summary.${f.name}',
              style: AppType.figure(context).copyWith(color: bc?.ink),
            ),
          ),
        ]),
        const SizedBox(height: AppSpace.xxs),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.meta(context).copyWith(color: bc?.muted)),
      ]);
      const pad = EdgeInsets.all(AppSpace.sm);
      return Expanded(
        child: lead
            ? AppBlock(tone: AppBlockTone.sky, padding: pad, onTap: () => onFilter(f), semanticLabel: '$label: $n', child: body)
            : AppCard(padding: pad, onTap: () => onFilter(f), child: body),
      );
    }

    return Row(children: [
      tile(t('مباشر الآن', 'Live now'), live, Icons.sensors_rounded, AppTone.danger, MeetingLinksFilter.live),
      const SizedBox(width: AppSpace.xs),
      tile(t('القادمة', 'Upcoming'), upcoming, Icons.event_rounded, AppTone.info, MeetingLinksFilter.upcoming),
      const SizedBox(width: AppSpace.xs),
      tile(t('روابط الضيوف', 'Guest links'), guestLinks, Icons.public_rounded, AppTone.brand, MeetingLinksFilter.guestLinks),
    ]);
  }
}

String meetingLinksFilterLabel(MeetingLinksFilter f) => switch (f) {
      MeetingLinksFilter.all => t('الكل', 'All'),
      MeetingLinksFilter.live => t('مباشر الآن', 'Live now'),
      MeetingLinksFilter.upcoming => t('القادمة', 'Upcoming'),
      MeetingLinksFilter.hosting => t('أستضيفها', 'I host'),
      MeetingLinksFilter.guestLinks => t('روابط الضيوف', 'Guest links'),
      MeetingLinksFilter.past => t('السابقة', 'Past'),
    };

class MeetingLinksFilterBar extends StatelessWidget {
  const MeetingLinksFilterBar({super.key, required this.value, required this.onChanged, this.counts = const {}});
  final MeetingLinksFilter value;
  final ValueChanged<MeetingLinksFilter> onChanged;
  final Map<MeetingLinksFilter, int> counts;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in MeetingLinksFilter.values) ...[
            AppChoiceChip(
              key: ValueKey('links.filter.${f.name}'),
              label: counts[f] == null || f == MeetingLinksFilter.all
                  ? meetingLinksFilterLabel(f)
                  : '${meetingLinksFilterLabel(f)} · ${counts[f]}',
              selected: f == value,
              onTap: () => onChanged(f),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ]),
      );
}
