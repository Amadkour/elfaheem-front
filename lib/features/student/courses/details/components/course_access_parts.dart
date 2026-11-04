// The course page's answer to "what does this student's access look like": the renewal / payment-review / support
// states of the bottom bar and side card, and the calm banner that warns of an ending plan. Plain values in, no
// provider read, so the layout harness can test them (test/access/course_access_layout_test.dart).
library;

import 'package:flutter/material.dart';

import '../../../../../config/app_config.dart';
import '../../../../../config/theme/theme_config_provider.dart';
import '../../../../../core/app_time.dart';
import '../../../../../core/course_access.dart';
import '../../../../../core/display/app_fonts.dart';
import '../../../../../core/plural.dart';
import '../../../../../design/app_kit.dart' show AppBanner;

/// "Plan ended on 4 Nov 2026" under the Renew button; null when the end date is unknown.
String? renewSubtitle(CourseAccess? access) {
  final end = access?.expiresAt;
  if (end == null) return null;
  return 'course_renew_ended_on'.tr.replaceAll('{date}', AppTime.date(end));
}

/// The text of the banner on the course page, or null when there is nothing to warn about.
/// Within 7 days of the end → "ends on DATE (in N days)"; after it ended → "has ended".
String? accessBannerText(CourseAccess? access) {
  if (access == null) return null;
  if (access.isExpired) return 'course_expired_banner'.tr;
  if (!access.expiringSoon) return null;
  final end = access.expiresAt!;
  final n = access.daysLeft ?? 0;
  final days = n <= 0
      ? 'course_days_today'.tr
      : countText(n, ar1: 'يوم واحد', ar2: 'يومان', arFew: '$n أيام', arMany: '$n يوماً', en1: 'in 1 day', en: 'in $n days');
  return 'course_expiring_banner'.tr.replaceAll('{date}', AppTime.date(end)).replaceAll('{days}', days);
}

/// The banner itself (warning colour while the plan runs, danger once it ended).
class CourseAccessBanner extends StatelessWidget {
  const CourseAccessBanner({super.key, required this.access});

  final CourseAccess? access;

  @override
  Widget build(BuildContext context) {
    final text = accessBannerText(access);
    if (text == null) return const SizedBox.shrink();
    final c = context.colors;
    final ended = access!.isExpired;
    return AppBanner(
      icon: ended ? Icons.event_busy_rounded : Icons.schedule_rounded,
      text: text,
      color: ended ? c.danger : c.warning,
    );
  }
}

/// A calm notice in the buy bar / card where the buy button would be: payment under review, or "contact support".
class CourseAccessNote extends StatelessWidget {
  const CourseAccessNote({super.key, required this.mode, required this.access});

  final EnrollBarMode mode;
  final CourseAccess? access;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pending = mode == EnrollBarMode.pending;
    final title = pending ? 'course_pay_review_title'.tr : (access == null ? '' : accessReasonText(access!));
    final hint = pending ? 'course_pay_review_hint'.tr : null;
    final color = pending ? c.warning : c.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(pending ? Icons.hourglass_top_rounded : Icons.support_agent_rounded, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 13, fontWeight: FontWeight.w600, color: c.textDark, height: 1.4),
                ),
                if (hint != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(hint, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: c.textMedium, height: 1.4)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
