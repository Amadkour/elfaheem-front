// lib/features/attendance/attendance_qr_card.dart
//
// The open attendance as a QR (Tea1Class.dc.html?screen=attqr), from plain values: "Scan to check in, <lesson>" with
// the open tag, the QR of the window's rotating code in a deep frame, two chips (the code renews in N s, time left)
// and one quiet line about offline students. The QR carries the same 6-digit code the screen view shows, so a student
// can also type it. Dark modules on the light hero ink in both modes: a scanner needs the contrast.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/attendance/attendance_strings.dart';
import 'package:flutter_education_app/features/attendance/attendance_ui.dart' show AttLiveDot;
import 'package:qr_flutter/qr_flutter.dart';

class AttQrCard extends StatelessWidget {
  const AttQrCard({
    super.key,
    required this.code,
    required this.secondsLeft,
    required this.registrationLeft,
    this.lesson,
    this.open = true,
    this.size,
  });

  /// The 6 digits the QR carries.
  final String code;

  /// Until the code changes, and until registration closes.
  final int secondsLeft;
  final Duration registrationLeft;
  final String? lesson;

  /// False once registration closed: the QR is drawn faded and the tag says so.
  final bool open;

  /// The QR's side; the card's width decides when null.
  final double? size;

  static String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              lesson == null || lesson!.isEmpty ? attT('t1_cl_scan_plain') : attT('t1_cl_scan_title', args: {'lesson': lesson!}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.section(context),
            ),
          ),
          AppSpace.gapXs,
          if (open) AttLiveDot(color: c.danger),
          Flexible(
            child: Text(attT(open ? 't1_cl_open_tag' : 'att_t_closed'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(context).copyWith(color: appInk(context, open ? c.danger : c.textMedium), fontWeight: FontWeight.w600)),
          ),
        ]),
        AppSpace.gapMd,
        LayoutBuilder(builder: (context, box) {
          final side = size ?? (box.maxWidth.isFinite ? (box.maxWidth - AppSpace.xl).clamp(AppTouch.primary * 3, AppTouch.primary * 6) : AppTouch.primary * 5);
          return Center(
            child: Semantics(
              label: attT('att_code_hint'),
              value: code,
              excludeSemantics: true,
              child: Opacity(
                opacity: open ? 1 : 0.35,
                child: Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(color: c.heroShade, borderRadius: BorderRadius.circular(AppRadius.sheet)),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpace.sm),
                    decoration: BoxDecoration(color: c.onHero, borderRadius: AppRadius.cardAll),
                    child: QrImageView(
                      data: code,
                      size: side,
                      padding: EdgeInsets.zero,
                      backgroundColor: c.onHero,
                      eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: c.heroShade),
                      dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: c.heroShade),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
        AppSpace.gapSm,
        Wrap(alignment: WrapAlignment.center, spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: [
          if (open) AppTag(attT('t1_cl_qr_renews', args: {'n': '$secondsLeft'}), c.primary, icon: Icons.autorenew_rounded),
          if (open) AppTag(attT('t1_cl_left', args: {'t': _mmss(registrationLeft)}), c.textMedium, icon: Icons.timer_outlined),
        ]),
        AppSpace.gapSm,
        AppBanner(icon: Icons.wifi_off_rounded, color: c.accent3, text: attT('t1_cl_offline_note')),
      ]),
    );
  }
}
