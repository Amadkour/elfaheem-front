// lib/features/booking/booking_mine_card.dart
//
// "حجزك": the student's booking of this subject on the subject page (GET /booking/me?subject_id=). One line of
// state, the time when it is fixed, and the one action the state asks for (pay a held seat, an offered seat or a
// fixed proposal). Never a waiting-list position (privacy).
library;

import 'package:flutter/material.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/app_digits.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/booking/booking_models.dart';
import 'package:flutter_education_app/features/booking/booking_parts.dart';

/// The bookings worth a card: the newest one still the student's.
BkBooking? bkShownBooking(List<BkBooking> mine) => mine.where((b) => b.live).firstOrNull;

class BkMineCard extends StatelessWidget {
  const BkMineCard({super.key, required this.booking, this.onPay, this.busy = false});

  final BkBooking booking;
  final VoidCallback? onPay;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kit = c.kit;
    final b = booking;
    final hold = b.holdUntil == null ? '' : appDigits('${AppTime.date(b.holdUntil!, pattern: 'EEEE d MMMM')}$bkComma${AppTime.time(b.holdUntil!)}');
    final (String line, KitTone tone, IconData icon) = switch (b.status) {
      'active' => ('bk_mine_active'.tr, kit.ok, Icons.event_available_rounded),
      'pending_payment' => (bkFill('bk_mine_pending', {'time': hold}), kit.warmTone, Icons.hourglass_bottom_rounded),
      'offered' => (bkFill('bk_mine_offered', {'time': hold}), kit.warmTone, Icons.event_seat_outlined),
      'scheduled' => (bkFill('bk_mine_scheduled', {'time': hold}), kit.warmTone, Icons.event_available_rounded),
      'proposed' => ('bk_mine_proposed'.tr, kit.primaryTone, Icons.schedule_send_outlined),
      'waitlisted' => ('bk_seats_notified'.tr, kit.primaryTone, Icons.notifications_none_rounded),
      'notify' => ('bk_other_time_done'.tr, kit.primaryTone, Icons.notifications_none_rounded),
      _ => ('bk_mine_title'.tr, kit.primaryTone, Icons.event_note_rounded),
    };
    final when = b.nextClassAt != null
        ? '${AppTime.date(b.nextClassAt!, pattern: 'EEEE d MMMM')}$bkComma${bkTimeRange(b.nextClassAt!, b.classMinutes)}'
        : (b.group != null && b.group!.times.isNotEmpty
            ? '${bkDaysOf(b.group!.times)}$bkComma${bkTimeRange(b.group!.times.first, b.classMinutes)}'
            : null);
    final what = [
      b.kind == 'group' && b.group != null ? bkGroupName(b.group!.label) : (b.kind == 'individual' ? 'bk_kind_individual_short'.tr : null),
      b.mode == 'in_person' ? 'bk_mode_in_person'.tr : 'bk_mode_remote'.tr,
      b.teacher?.name,
    ].whereType<String>().where((s) => s.isNotEmpty).join(bkComma);
    return AppCard(
      variant: AppCardVariant.tint,
      tone: tone,
      title: 'bk_mine_title'.tr,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppIconBox(icon: icon, tone: tone),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line, style: AppType.bodyStrong(context)),
              if (when != null) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(appDigits(when), style: AppType.body(context).copyWith(color: c.textMedium)),
              ],
              if (what.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xxs),
                Text(what, style: AppType.meta(context)),
              ],
            ]),
          ),
        ]),
        if (b.payable && onPay != null) ...[
          const SizedBox(height: AppSpace.md),
          AppButton.hot(
            label: b.price == null ? 'bk_pay_now'.tr : bkFill('bk_pay_now_price', {'price': bkMoney(b.price!, b.currency)}),
            trailingIcon: Icons.arrow_forward_rounded,
            busy: busy,
            expand: true,
            onPressed: onPay,
          ),
        ],
      ]),
    );
  }
}
