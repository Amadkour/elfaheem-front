// lib/features/org/advising/adv_comm_parts.dart — the pieces the Phase 5 advising screens share (docs/advising/
// PHASE5.md): appointments, conversations, the hub and the availability editor.
//
//   advCommErrorText    advErrorText + the numbers / conflicts the Phase 5 errors carry
//   AdvCommScaffold     OrgPushedPage for staff of the organization, the screen's own app bar for a student
//   AdvApptStatusPill · AdvThreadStatusPill · AdvModeChips · AdvDateStrip · AdvSlotPicker · AdvAttachmentChip
//   AdvInfoLine         an icon + a calm line ("Next free: Mon 9 Nov · 10:00 AM")
//   advShareIcs · advOpenAttachment · advPickAttachment · advJoinAppointment   the actions that touch files / rooms
// Everything takes plain values except the four action functions.
library;


import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart' show ApiException;
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/calendar/calendar_api.dart' show RemoteCalendarApi;
import 'package:flutter_education_app/features/calendar/calendar_meeting.dart' show showMeetingSheet;
import 'package:flutter_education_app/utils/widget/app_bar.dart';
import 'package:flutter_education_app/utils/widget/base_page.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_education_app/core/share/external_link.dart';

import '../../admin/admin_common.dart' show asInt, asMap, t;
import '../governance/gov_request_parts.dart' show govAttachmentExtensions;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage, orgUsesDashboardHeader;
import '../org_ui.dart' show orgPickAndUpload;
import '../org_v3.dart' show orgCall;
import 'adv_appt_models.dart';
import 'adv_comm_api.dart';
import 'adv_parts.dart' show advErrorText;

// ═════════════════════════════════════════════════════════════════════════════
//  Errors
// ═════════════════════════════════════════════════════════════════════════════

/// [advErrorText] plus what some Phase 5 errors carry: the booking limit, the largest file, the student's clashes.
String advCommErrorText(ApiException e) {
  final d = asMap(ApiException.asMap(e.body)?['detail']);
  switch (e.code) {
    case 'advising_booking_limit':
      final n = asInt(d['limit']);
      if (n > 0) {
        return countText(n,
            ar1: 'لديك موعد قادم بالفعل — الحد موعد واحد في الوقت نفسه. ألغه أو انتظر حتى ينتهي',
            ar2: 'لديك موعدان قادمان — وهو الحد المسموح. ألغِ أحدهما أو انتظر حتى ينتهي',
            arFew: 'لديك $n مواعيد قادمة — وهو الحد المسموح. ألغِ أحدها أو انتظر حتى ينتهي',
            arMany: 'لديك $n موعداً قادماً — وهو الحد المسموح. ألغِ أحدها أو انتظر حتى ينتهي',
            en1: 'You already have an upcoming appointment — one at a time is the limit. Cancel it or wait until it has taken place',
            en: 'You already have $n upcoming appointments — that is the limit. Cancel one or wait until it has taken place');
      }
    case 'advising_file_too_large':
      final max = asInt(d['max_bytes']);
      if (max > 0) {
        final mb = (max / (1024 * 1024)).toStringAsFixed(max % (1024 * 1024) == 0 ? 0 : 1);
        return t('الملف أكبر من $mb ميغابايت', 'The file is larger than $mb MB');
      }
    case 'advising_student_busy':
      final spans = AdvBusySpan.listOf(d);
      if (spans.isNotEmpty) {
        final s = spans.first;
        return t('لدى الطالب ${s.sourceLabel} من ${AppTime.time(s.startsAt)} إلى ${AppTime.time(s.endsAt)}',
            'The student has ${s.sourceLabel.toLowerCase()} from ${AppTime.time(s.startsAt)} to ${AppTime.time(s.endsAt)}');
      }
  }
  return advErrorText(e);
}

// ═════════════════════════════════════════════════════════════════════════════
//  Page frame
// ═════════════════════════════════════════════════════════════════════════════

/// A Phase 5 page: the organization dashboard's header for its staff (OrgPushedPage), the screen's own app bar for
/// a student, a member page or a deep link opened before the session knew the organization.
class AdvCommScaffold extends StatelessWidget {
  const AdvCommScaffold({super.key, required this.orgId, required this.title, required this.child, this.subtitle, this.maxWidth = 960, this.refresh});
  final int orgId;
  final String title;
  final String? subtitle;
  final Widget child;
  final double maxWidth;
  final OrgPageRefresh? refresh;

  @override
  Widget build(BuildContext context) {
    if (orgUsesDashboardHeader(context, orgId)) {
      return OrgPushedPage(title: title, subtitle: subtitle, helpPageId: 'org.advising', maxWidth: maxWidth, refresh: refresh, child: child);
    }
    return BasePage(useWebCard: true, maxWith: maxWidth, appBar: ScreenAppBar(title: title, helpPageId: 'org.advising'), child: child);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Pills, lines, chips
// ═════════════════════════════════════════════════════════════════════════════

IconData advModeIcon(String? mode) => switch (mode) {
      'video' => Icons.videocam_rounded,
      'phone' => Icons.call_rounded,
      'chat' => Icons.chat_bubble_outline_rounded,
      _ => Icons.meeting_room_outlined,
    };

Color advApptStatusColor(BuildContext context, String s) {
  final c = context.colors;
  return switch (s) {
    'completed' => c.success,
    'no_show' => c.danger,
    'cancelled' => c.textMedium,
    _ => c.primary,
  };
}

class AdvApptStatusPill extends StatelessWidget {
  const AdvApptStatusPill({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        advApptStatusLabel(status),
        color: advApptStatusColor(context, status),
        icon: switch (status) {
          'completed' => Icons.check_circle_rounded,
          'no_show' => Icons.person_off_rounded,
          'cancelled' => Icons.event_busy_rounded,
          _ => Icons.event_available_rounded,
        },
      );
}

Color advThreadStatusColor(BuildContext context, String s, {bool overdue = false}) {
  final c = context.colors;
  if (overdue) return c.danger;
  return switch (s) {
    'open' => c.warning,
    'answered' => c.success,
    'escalated' => c.danger,
    _ => c.textMedium,
  };
}

class AdvThreadStatusPill extends StatelessWidget {
  const AdvThreadStatusPill({super.key, required this.status, this.overdue = false, this.staff = true});
  final String status;
  final bool overdue;

  /// The staff side reads `open` as "Waiting for your reply".
  final bool staff;

  @override
  Widget build(BuildContext context) => AppBadgePill(
        overdue ? t('متأخرة', 'Overdue') : (status == 'open' && staff ? t('بانتظار ردّك', 'Needs your reply') : advThreadStatusLabel(status)),
        color: advThreadStatusColor(context, status, overdue: overdue),
        icon: overdue
            ? Icons.alarm_rounded
            : switch (status) {
                'answered' => Icons.mark_chat_read_outlined,
                'closed' => Icons.lock_outline_rounded,
                'escalated' => Icons.north_rounded,
                _ => Icons.mark_chat_unread_outlined,
              },
      );
}

/// An icon and one calm line under a title.
class AdvInfoLine extends StatelessWidget {
  const AdvInfoLine({super.key, required this.icon, required this.text, this.color, this.maxLines = 2, this.typed = false});
  final IconData icon;
  final String text;
  final Color? color;
  final int maxLines;

  /// Text someone typed (an office, a contact note): laid out in its own direction.
  final bool typed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ExcludeSemantics(child: Icon(icon, size: AppIconSize.sm, color: color == null ? c.textMedium : appInk(context, color!))),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            textDirection: typed ? _dir(text) : null,
            style: AppType.meta(context).copyWith(color: color == null ? null : appInk(context, color!)),
          ),
        ),
      ]),
    );
  }

  static TextDirection? _dir(String s) {
    for (final r in s.runes) {
      if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFDFF) || (r >= 0xFE70 && r <= 0xFEFF)) return TextDirection.rtl;
      if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return TextDirection.ltr;
    }
    return null;
  }
}

/// The ways to meet, as choice chips ([modes] = what may be chosen).
class AdvModeChips extends StatelessWidget {
  const AdvModeChips({super.key, required this.modes, required this.selected, required this.onChanged, this.multi = false, this.selection = const []});
  final List<String> modes;

  /// Single choice: the chosen mode.
  final String? selected;

  /// Multiple choice ([multi]): the chosen modes.
  final List<String> selection;
  final bool multi;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
        for (final m in modes)
          AppChoiceChip(
            label: advMeetingModeLabelShort(m),
            icon: advModeIcon(m),
            selected: multi ? selection.contains(m) : m == selected,
            onTap: onChanged == null ? () {} : () => onChanged!(m),
          ),
      ]);
}

String advMeetingModeLabelShort(String m) => switch (m) {
      'in_person' => t('حضوري', 'In person'),
      'video' => t('مرئي', 'Video'),
      'phone' => t('هاتفي', 'Phone'),
      'chat' => t('محادثة', 'Chat'),
      _ => m,
    };

/// A row of days to pick from; each day shows how many free times it has ([counts]; 0 = none, drawn muted).
class AdvDateStrip extends StatelessWidget {
  const AdvDateStrip({super.key, required this.days, required this.selected, required this.counts, required this.onSelect, this.onPrev, this.onNext});
  final List<DateTime> days;
  final DateTime? selected;

  /// day key → free times that day.
  final Map<String, int> counts;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback? onPrev, onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = selected == null ? null : advDayKey(selected!);
    Widget arrow(IconData icon, String tip, VoidCallback? on) => IconButton(
          tooltip: tip,
          onPressed: on,
          constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
          icon: Icon(icon, size: AppIconSize.md),
        );
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    return Row(children: [
      arrow(Icons.chevron_left_rounded, t('الأيام السابقة', 'Earlier days'), onPrev),
      Expanded(
        child: SizedBox(
          height: 76 * scale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpace.xs),
            itemBuilder: (context, i) {
              final d = days[i];
              final k = advDayKey(d);
              final n = counts[k] ?? 0;
              final on = k == sel;
              final ink = on ? c.primary : (n == 0 ? c.textLight : c.textDark);
              return Semantics(
                selected: on,
                button: true,
                label: '${advDayLabel(d, pattern: 'EEEE d MMMM')}, ${n == 0 ? t('لا مواعيد متاحة', 'no free times') : countText(n, ar1: 'موعد متاح', ar2: 'موعدان متاحان', arFew: '$n مواعيد متاحة', arMany: '$n موعداً متاحاً', en1: '1 free time', en: '$n free times')}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: AppRadius.chipAll,
                  onTap: () => onSelect(d),
                  child: AnimatedContainer(
                    duration: AppMotion.of(context).fast,
                    width: 58 * scale,
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    decoration: BoxDecoration(
                      color: on ? c.primary.withValues(alpha: c.isDark ? 0.22 : 0.10) : c.cardBg,
                      borderRadius: AppRadius.chipAll,
                      border: Border.all(color: on ? c.primary : c.divider, width: on ? AppBorder.strong : AppBorder.hairline),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(advDayLabel(d, pattern: 'EEE'), maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: AppType.meta(context).copyWith(color: on ? appInk(context, c.primary) : null)),
                      Text('${d.day}', style: AppType.section(context).copyWith(color: on ? appInk(context, c.primary) : ink, fontFeatures: const [FontFeature.tabularFigures()])),
                      Container(
                        width: AppSpace.xs - 2,
                        height: AppSpace.xs - 2,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: n > 0 ? c.success : Colors.transparent),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      arrow(Icons.chevron_right_rounded, t('أيام لاحقة', 'Later days'), onNext),
    ]);
  }
}

/// The free times of one day as tappable chips (the organization's wall clock).
class AdvSlotPicker extends StatelessWidget {
  const AdvSlotPicker({super.key, required this.slots, required this.selected, required this.onSelect});
  final List<AdvSlot> slots;
  final AdvSlot? selected;
  final ValueChanged<AdvSlot> onSelect;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
        child: Row(children: [
          ExcludeSemantics(child: Icon(Icons.event_busy_rounded, size: AppIconSize.md, color: context.colors.textLight)),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(t('لا مواعيد متاحة في هذا اليوم — اختر يوماً آخر', 'No free times on this day — pick another day'), style: AppType.body(context))),
        ]),
      );
    }
    return Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
      for (final s in slots)
        AppChoiceChip(
          label: AppTime.time(s.startsAt),
          selected: selected != null && selected!.startsAt == s.startsAt,
          onTap: () => onSelect(s),
        ),
    ]);
  }
}

/// One attachment: name and size; tap opens it, [onRemove] adds an ×.
class AdvAttachmentChip extends StatelessWidget {
  const AdvAttachmentChip({super.key, required this.attachment, this.onOpen, this.onRemove, this.onDark = false});
  final AdvAttachment attachment;
  final VoidCallback? onOpen, onRemove;

  /// Drawn on a tinted bubble.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = attachment;
    final size = fileSizeLabel(a.size);
    return Semantics(
      button: onOpen != null,
      label: [t('مرفق', 'Attachment'), a.shown, if (size.isNotEmpty) size].join(', '),
      excludeSemantics: true,
      child: Material(
        color: c.cardBg,
        borderRadius: AppRadius.chipAll,
        child: InkWell(
          borderRadius: AppRadius.chipAll,
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTouch.min, maxWidth: 280),
            padding: const EdgeInsetsDirectional.only(start: AppSpace.sm, end: AppSpace.xxs),
            decoration: BoxDecoration(borderRadius: AppRadius.chipAll, border: Border.all(color: c.divider)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(a.isImage ? Icons.image_outlined : (a.isPdf ? Icons.picture_as_pdf_outlined : Icons.insert_drive_file_outlined), size: AppIconSize.md, color: c.primary),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.shown, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600)),
                  if (size.isNotEmpty) Text(size, textDirection: TextDirection.ltr, style: AppType.meta(context)),
                ]),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: t('إزالة المرفق', 'Remove the attachment'),
                  onPressed: onRemove,
                  constraints: const BoxConstraints(minWidth: AppTouch.min, minHeight: AppTouch.min),
                  icon: Icon(Icons.close_rounded, size: AppIconSize.sm, color: c.textMedium),
                )
              else
                const SizedBox(width: AppSpace.xs),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A count badge (unread messages) next to a title: the kit's bubble with a spoken label.
class AdvCountDot extends StatelessWidget {
  const AdvCountDot({super.key, required this.count, this.tone = AppTone.brand});
  final int count;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => AppCountBadge(
        count: count,
        tone: tone,
        semanticLabel: countText(count, ar1: 'رسالة غير مقروءة', ar2: 'رسالتان غير مقروءتين', arFew: '$count رسائل غير مقروءة', arMany: '$count رسالة غير مقروءة', en1: '1 unread message', en: '$count unread messages'),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Actions that touch files and rooms
// ═════════════════════════════════════════════════════════════════════════════

/// "Add to calendar": the appointment's .ics — downloaded on the web and desktops, the share sheet on phones (the
/// device calendar is one of its targets).
Future<void> advShareIcs(AdvCommApi api, AdvAppointment a) async {
  final r = await orgCall(() => api.ics(a.id), quiet: true);
  if (!r.ok) {
    showAppNotice(advCommErrorText(r.error!), error: true);
    return;
  }
  final bytes = r.data as Uint8List;
  final name = 'advising-${a.id}';
  final phone = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  try {
    if (phone) {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'text/calendar', name: '$name.ics')],
        fileNameOverrides: ['$name.ics'],
        subject: t('موعد إرشاد أكاديمي', 'Academic advising appointment'),
      ));
    } else {
      await FileSaver.instance.saveFile(name: name, bytes: bytes, fileExtension: 'ics', mimeType: MimeType.text);
      showAppNotice(t('حُفظ ملف الموعد — افتحه ليُضاف إلى تقويمك', 'Appointment file saved — open it to add it to your calendar'));
    }
  } catch (_) {
    showAppNotice(t('تعذّر إنشاء ملف التقويم', 'Could not create the calendar file'), error: true);
  }
}

/// Opens an attachment: images in an in-app preview, anything else in the browser / the system viewer.
Future<void> advOpenAttachment(BuildContext context, AdvCommApi api, AdvAttachment a) async {
  final r = await orgCall(() => api.attachmentLink(a.id), quiet: true);
  if (!r.ok) {
    showAppNotice(advCommErrorText(r.error!), error: true);
    return;
  }
  final url = r.data as String;
  if (url.isEmpty) {
    showAppNotice(t('تعذّر فتح الملف الآن — أعد المحاولة بعد قليل', 'The file cannot be opened right now — try again shortly'), error: true);
    return;
  }
  if (a.isImage && context.mounted) {
    await showDialog<void>(context: context, builder: (_) => AdvImagePreview(name: a.shown, url: url));
    return;
  }
  await openExternalLink(url, failText: t('تعذّر فتح الملف', 'Could not open the file'));
}

class AdvImagePreview extends StatelessWidget {
  const AdvImagePreview({super.key, required this.name, required this.url});
  final String name, url;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpace.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
            child: Row(children: [
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: AppType.bodyStrong(context))),
              IconButton(
                tooltip: t('فتح في المتصفح', 'Open in the browser'),
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => openExternalLink(url),
              ),
              IconButton(tooltip: t('إغلاق', 'Close'), icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          Flexible(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Text(t('تعذّرت المعاينة — افتح الملف في المتصفح', 'The preview failed — open the file in the browser'), textAlign: TextAlign.center, style: AppType.body(context).copyWith(color: c.textMedium)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Picks a file and uploads it as an unsent attachment; null when cancelled or refused (told). Never throws.
Future<AdvAttachment?> advPickAttachment(AdvCommApi api) async {
  Map<String, dynamic>? f;
  try {
    f = await orgPickAndUpload(api.uploadPath, extensions: govAttachmentExtensions, errorText: advCommErrorText);
  } catch (_) {
    showAppNotice(t('تعذّر رفع الملف', 'Could not upload the file'), error: true);
    return null;
  }
  if (f == null) return null;
  final a = AdvAttachment.fromJson(f);
  if (a.id == 0) {
    showAppNotice(t('تعذّر رفع الملف', 'Could not upload the file'), error: true);
    return null;
  }
  showAppNotice(t('أُرفق الملف', 'File attached'));
  return a;
}

/// Join a video appointment: the advisor's own https link, else the platform's meeting (the calendar's Join flow).
Future<void> advJoinAppointment(BuildContext context, AdvAppointment a) async {
  if (a.hasLink) {
    await openExternalLink(a.videoLink, failText: t('تعذّر فتح رابط الاجتماع', 'Could not open the meeting link'));
    return;
  }
  final id = a.meetingId;
  if (id == null) {
    showAppNotice(t('لا رابط لهذا الاجتماع بعد — تواصل مع المرشد', 'This meeting has no link yet — contact the advisor'), error: true);
    return;
  }
  await showMeetingSheet(context, api: const RemoteCalendarApi(), meetingId: id);
}
