// lib/design/action_banner.dart
//
// UX v3 phase 2: what an opened notification asks of me, at the top of the screen it opened.
//
//   ActionBanner(action: NotifAction.edit, reason: '…', note: '…', fields: ['Title', 'Due date'],
//       actionLabel: 'Edit now', onAction: _edit)
//     plain values: the action's icon + label ("Needs your edit" …), the reason, the reviewer's note (quoted), a chip
//     per field to change, one primary button
//   ActionBanner.of(link, onAction: …)   the same from a NotifLink
//   StaleLinkView(gone: false, reason: '…', onFallback: …)   "already handled" / "no longer exists" + a button
//   StaleLinkPage(…)                     the same as a whole page (AppNavigator pushes it)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';

import '../core/notif_link.dart';
import '../utils/widget/app_bar.dart' show ScreenAppBar;
import '../utils/widget/base_page.dart' show BasePage;
import 'app_buttons.dart';
import 'app_kit.dart' show AppBadgePill, AppEmpty;
import 'app_tokens.dart';

String _tx(String ar, String en) => AppConfig.lang == 'ar' ? ar : en;

/// The banner's headline for [a]; [rejected] reads "Rejected: see why" for an edit / a view.
String notifActionLabel(NotifAction a, {bool rejected = false}) {
  if (rejected && (a == NotifAction.edit || a == NotifAction.view || a == NotifAction.none)) {
    return _tx('مرفوض: اطّلع على السبب', 'Rejected: see why');
  }
  return switch (a) {
    NotifAction.edit => _tx('يحتاج تعديلك', 'Needs your edit'),
    NotifAction.confirm => _tx('بانتظار تأكيدك', 'Awaiting your confirmation'),
    NotifAction.vote => _tx('مطلوب تصويتك', 'Vote required'),
    NotifAction.reply => _tx('مطلوب ردّك', 'Reply needed'),
    NotifAction.review => _tx('طلب جديد', 'New request'),
    NotifAction.fill => _tx('املأ النموذج', 'Fill the form'),
    NotifAction.approve => _tx('بانتظار اعتمادك', 'Awaiting your approval'),
    NotifAction.view || NotifAction.none => _tx('للاطلاع', 'For your information'),
  };
}

/// The banner's button label for [a] (the caller may pass its own).
String notifActionButton(NotifAction a) => switch (a) {
      NotifAction.edit => _tx('عدّل الآن', 'Edit now'),
      NotifAction.confirm => _tx('تأكيد', 'Confirm'),
      NotifAction.vote => _tx('إلى التصويت', 'Go to the vote'),
      NotifAction.reply => _tx('اكتب ردّك', 'Write a reply'),
      NotifAction.review => _tx('راجع الطلب', 'Review it'),
      NotifAction.fill => _tx('املأ النموذج', 'Fill the form'),
      NotifAction.approve => _tx('اتخذ القرار', 'Decide'),
      NotifAction.view || NotifAction.none => _tx('عرض', 'View'),
    };

IconData notifActionIcon(NotifAction a, {bool rejected = false}) {
  if (rejected) return Icons.report_rounded;
  return switch (a) {
    NotifAction.edit => Icons.edit_note_rounded,
    NotifAction.confirm => Icons.task_alt_rounded,
    NotifAction.vote => Icons.how_to_vote_rounded,
    NotifAction.reply => Icons.reply_rounded,
    NotifAction.review => Icons.mark_email_unread_rounded,
    NotifAction.fill => Icons.assignment_rounded,
    NotifAction.approve => Icons.gavel_rounded,
    NotifAction.view || NotifAction.none => Icons.info_outline_rounded,
  };
}

class ActionBanner extends StatelessWidget {
  const ActionBanner({
    super.key,
    required this.action,
    this.rejected = false,
    this.reason = '',
    this.note,
    this.fields = const [],
    this.actionLabel,
    this.onAction,
    this.busy = false,
  });

  /// From a link (the button is the caller's).
  factory ActionBanner.of(NotifLink l, {Key? key, String? actionLabel, VoidCallback? onAction, bool busy = false}) => ActionBanner(
        key: key,
        action: l.action,
        rejected: l.rejected,
        reason: l.reason,
        note: l.note,
        fields: [for (final f in l.fields) f.label],
        actionLabel: actionLabel,
        onAction: onAction,
        busy: busy,
      );

  final NotifAction action;
  final bool rejected, busy;
  final String reason;
  final String? note;

  /// The labels of the fields to change (a chip each).
  final List<String> fields;

  /// The one primary button ([notifActionButton] when [actionLabel] is null); hidden without [onAction].
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = rejected ? c.danger : (action == NotifAction.edit || action == NotifAction.vote ? c.warning : c.primary);
    final label = notifActionLabel(action, rejected: rejected);
    final note = (this.note ?? '').trim();
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: Container(
        key: const ValueKey('action_banner'),
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpace.sm),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.08),
          borderRadius: AppRadius.cardAll,
          border: Border.all(color: tone.withValues(alpha: 0.35), width: AppBorder.hairline),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(notifActionIcon(action, rejected: rejected), color: tone, size: AppIconSize.md),
            AppSpace.gapXs,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: AppType.bodyStrong(context).copyWith(color: c.textDark)),
                if (reason.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpace.xxs),
                  Text(reason, style: AppType.body(context).copyWith(color: c.textDark)),
                ],
              ]),
            ),
          ]),
          if (note.isNotEmpty) ...[
            AppSpace.gapXs,
            Container(
              key: const ValueKey('action_banner_note'),
              width: double.infinity,
              padding: const EdgeInsetsDirectional.only(start: AppSpace.xs),
              decoration: BoxDecoration(border: BorderDirectional(start: BorderSide(color: tone, width: AppBorder.focus))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_tx('ملاحظة المراجِع', "The reviewer's note"), style: AppType.meta(context).copyWith(color: c.textMedium)),
                Text(note, style: AppType.body(context).copyWith(color: c.textDark)),
              ]),
            ),
          ],
          if (fields.isNotEmpty) ...[
            AppSpace.gapXs,
            Text(_tx('غيّر هذه الحقول:', 'Change these fields:'), style: AppType.meta(context).copyWith(color: c.textMedium)),
            const SizedBox(height: AppSpace.xxs),
            Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
              for (final f in fields) AppBadgePill(f, color: tone, icon: Icons.edit_rounded),
            ]),
          ],
          if (onAction != null) ...[
            AppSpace.gapXs,
            AppButton.primary(
              key: const ValueKey('action_banner_go'),
              size: AppButtonSize.sm,
              icon: notifActionIcon(action),
              label: actionLabel ?? notifActionButton(action),
              busy: busy,
              onPressed: busy ? null : onAction,
            ),
          ],
        ]),
      ),
    );
  }
}

/// The target is gone ([gone]) or already handled: the server's [reason], then one button to where it is now.
class StaleLinkView extends StatelessWidget {
  const StaleLinkView({super.key, this.gone = false, this.reason = '', this.fallbackLabel, this.onFallback});

  final bool gone;
  final String reason;
  final String? fallbackLabel;
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) => AppEmpty(
        key: const ValueKey('stale_link'),
        icon: gone ? Icons.search_off_rounded : Icons.task_alt_rounded,
        title: gone ? _tx('هذا العنصر لم يعد موجوداً', 'This item no longer exists') : _tx('تمت معالجة هذا العنصر بالفعل', 'This item was already handled'),
        message: reason.trim().isEmpty ? _tx('لا شيء مطلوب منك هنا الآن.', 'Nothing is waiting for you here now.') : reason,
        actionLabel: onFallback == null ? null : (fallbackLabel ?? _tx('إلى القائمة', 'Go to the list')),
        onAction: onFallback,
      );
}

/// [StaleLinkView] as a page of its own (a notification tap / push whose target is gone or handled).
class StaleLinkPage extends StatelessWidget {
  const StaleLinkPage({super.key, this.gone = false, this.reason = '', this.fallbackLabel, this.onFallback});

  final bool gone;
  final String reason;
  final String? fallbackLabel;
  final VoidCallback? onFallback;

  @override
  Widget build(BuildContext context) => BasePage(
        useWebCard: true,
        width: AppWidth.reading,
        appBar: ScreenAppBar(title: _tx('الإشعار', 'Notification')),
        child: StaleLinkView(gone: gone, reason: reason, fallbackLabel: fallbackLabel, onFallback: onFallback),
      );
}
