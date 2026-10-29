// live_room_ended.dart — what the room says when LiveKit closed it for a reason other than "you left" or "the
// session ended" (D9, liveDisconnectAction in live_room_rules.dart):
//
//   lost         the connection dropped — "Rejoin" runs the pre-join page's join again (a fresh token, then
//                connect) with the same microphone / camera choices; "Close" leaves.
//   removed      the host removed this person.
//   otherDevice  the same account joined from another device: no Rejoin (the two devices would push each other
//                out in turn).
//
// LiveRoomEndedCard takes plain values (test/ui/live_room_ended_layout_test.dart); room.dart shows it in a
// Dialog and reads the answer: true = Rejoin.

import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/display/app_fonts.dart';

import '../../../../admin/admin_common.dart' show t;
import 'live_palette.dart';

enum LiveEndedKind { lost, removed, otherDevice }

class LiveRoomEndedCard extends StatelessWidget {
  const LiveRoomEndedCard({super.key, required this.kind, this.onRejoin, required this.onClose});

  final LiveEndedKind kind;

  /// Null hides Rejoin (always for [LiveEndedKind.removed] / [LiveEndedKind.otherDevice]; for a lost connection
  /// when the room was not opened from a pre-join page that can join again).
  final VoidCallback? onRejoin;
  final VoidCallback onClose;

  String get _title => switch (kind) {
        LiveEndedKind.lost => t('انقطع الاتصال', 'Connection lost'),
        LiveEndedKind.removed => t('أخرجك المضيف من الجلسة', 'You were removed by the host'),
        LiveEndedKind.otherDevice => t('دخلت بهذا الحساب من جهاز آخر', 'This account joined from another device'),
      };

  String get _body => switch (kind) {
        LiveEndedKind.lost => onRejoin != null
            ? t('انقطع اتصالك بالجلسة المباشرة. اضغط «إعادة الانضمام» للعودة بنفس إعدادات الميكروفون والكاميرا.',
                'Your connection to the live session dropped. Tap Rejoin to come back with the same microphone and camera settings.')
            : t('لم نتمكن من إبقائك في الجلسة. تحقق من الإنترنت وادخل مجدداً.',
                "We couldn't keep you in the session. Check your internet and join again."),
        LiveEndedKind.removed => t('أخرجك المضيف من هذه الجلسة المباشرة. تواصل معه إن كنت تظن أن هذا خطأ.',
            'The host removed you from this live session. Contact them if you think this is a mistake.'),
        LiveEndedKind.otherDevice => t(
            'يمكن للحساب الواحد أن يكون في الغرفة من جهاز واحد فقط. أكمل من الجهاز الآخر، أو اخرج منه ثم ادخل من هنا.',
            'One account can be in the room from one device at a time. Carry on on the other device, or leave it there and join again here.'),
      };

  IconData get _icon => switch (kind) {
        LiveEndedKind.lost => Icons.wifi_off_rounded,
        LiveEndedKind.removed => Icons.person_remove_rounded,
        LiveEndedKind.otherDevice => Icons.devices_other_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final tone = kind == LiveEndedKind.lost ? LivePalette.accent : LivePalette.danger;
    final rejoin = kind == LiveEndedKind.lost ? onRejoin : null;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: LivePalette.surfaceHi,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: LivePalette.glassBorder),
        boxShadow: [BoxShadow(color: LivePalette.shade(0.6), blurRadius: 20)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: tone.withValues(alpha: 0.12),
            border: Border.all(color: tone.withValues(alpha: 0.4), width: 2),
          ),
          child: Icon(_icon, color: tone, size: 34),
        ),
        const SizedBox(height: 16),
        Text(_title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: AppFonts.family, color: LivePalette.textHigh, fontWeight: FontWeight.w800, fontSize: 20)),
        const SizedBox(height: 8),
        Text(_body,
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: AppFonts.family, color: LivePalette.textMid, height: 1.5)),
        const SizedBox(height: 24),
        if (rejoin != null) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('live_room.rejoin'),
              style: FilledButton.styleFrom(
                backgroundColor: LivePalette.accent,
                minimumSize: const Size(48, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: rejoin,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t('إعادة الانضمام', 'Rejoin'),
                  style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: rejoin != null
              ? TextButton(
                  key: const ValueKey('live_room.ended_close'),
                  style: TextButton.styleFrom(foregroundColor: LivePalette.textHigh, minimumSize: const Size(48, 48)),
                  onPressed: onClose,
                  child: Text(t('إغلاق', 'Close'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w700)),
                )
              : FilledButton(
                  key: const ValueKey('live_room.ended_close'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tone,
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: onClose,
                  child: Text(t('حسناً', 'OK'), style: TextStyle(fontFamily: AppFonts.family, fontWeight: FontWeight.w800)),
                ),
        ),
      ]),
    );
  }
}
