/// features/teacher/device_requests/teacher_device_requests_screen.dart
/// Teacher reviews device-switch requests: buttons or drag the card
/// (approve one way, reject the other).
///
/// Open from the teacher dashboard:
///   Navigator.push(context, MaterialPageRoute(builder: (_) => const TeacherDeviceRequestsScreen()));
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:provider/provider.dart';
import 'package:flutter_education_app/utils/widget/swipe_request_card.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../utils/widget/app_bar.dart';
import '../../../../utils/widget/base_page.dart';
import 'teacher_device_requests_provider.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/app_tokens.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/app_refresh.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/design/app_notice.dart';

class TeacherDeviceRequestsScreen extends StatefulWidget {
  const TeacherDeviceRequestsScreen({super.key});

  @override
  State<TeacherDeviceRequestsScreen> createState() =>
      _TeacherDeviceRequestsScreenState();
}

class _TeacherDeviceRequestsScreenState
    extends State<TeacherDeviceRequestsScreen> {
  @override
  void initState() {
    super.initState();
    // Shared singleton provider: loads only if the dashboard hasn't already.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TeacherDeviceRequestsProvider>().ensureLoaded();
    });
  }

  @override
  Widget build(BuildContext context) => const _View();
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<TeacherDeviceRequestsProvider>();
    final c = context.colors;
    // Not loaded yet: loader, or error + retry if the first load failed.
    final failedFirstLoad =
        !p.hasLoaded && !p.isLoading && p.errorMessage != null;

    return BasePage(
      key: const ValueKey('device_requests'),
      useWebCard: true,
      maxWith: 1100,
      appBar: ScreenAppBar(title: 'device_switch_requests'.tr),
      child: !p.hasLoaded && !failedFirstLoad
          ? const AppListSkeleton()
          : AppRefresh(
        onRefresh: p.load,
        child: failedFirstLoad
            ? RequestStateView(
          icon: Icons.error_outline_rounded,
          color: c.danger,
          message: p.errorMessage ?? 'failed_to_load'.tr,
          actionLabel: 'retry'.tr,
          onAction: p.load,
        )
            : p.items.isEmpty
            ? RequestStateView(
          icon: Icons.phonelink_rounded,
          message: 'no_pending_requests'.tr,
        )
            : ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          // +1: the hint banner is the first row.
          itemCount: p.items.length + 1,
          itemBuilder: (_, i) {
            if (i == 0) return SwipeHintBanner(key: const ValueKey('device_requests.hint'), count: p.items.length);
            final item = p.items[i - 1];
            return _Card(key: ValueKey(item.id), item: item);
          },
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final DeviceSwitchItem item;

  const _Card({super.key, required this.item});

  static List<String> get _quickReasons => [
    'device_reason_monthly_limit'.tr,
    'device_reason_unknown_device'.tr,
  ];

  Future<bool> _approve(BuildContext context) async {
    final p = context.read<TeacherDeviceRequestsProvider>();

    final ok = await p.approve(item.id);
    showAppNotice(
      ok ? 'device_request_approved'.tr : (p.errorMessage ?? 'device_approve_failed'.tr),
      error: !ok,
    );
    return ok;
  }

  Future<bool> _reject(BuildContext context) async {
    final p = context.read<TeacherDeviceRequestsProvider>();

    final reason = await showReasonDialog(
      context,
      title: 'rejection_reason_title'.tr,
      hint: 'optional'.tr,
      requireReason: false,
      quickReasons: _quickReasons,
    );
    if (reason == null) return false; // cancelled → card springs back

    final ok = await p.reject(item.id, reason);
    showAppNotice(
      ok ? 'request_rejected'.tr : (p.errorMessage ?? 'request_reject_failed'.tr),
      error: !ok,
    );
    return ok;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final warn = context.colors.warning;

    return SwipeRequestCard(
      itemId: item.id,
      approveLabel: 'request_approve'.tr,
      onApprove: () => _approve(context),
      onReject: () => _reject(context),
      onRemoved: () =>
          context.read<TeacherDeviceRequestsProvider>().removeItem(item.id),
      builder: (context, ctl) => RequestCardShell(
        busy: ctl.busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: student + course chip ──
            Row(
              children: [
                RequestAvatar(name: item.studentName),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: c.label.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      // the student and the course open their detail where the server allows it (D-290)
                      if (item.studentId != null || item.courseId != null)
                        Wrap(spacing: AppSpace.xs, children: [
                          if (item.studentId != null)
                            EntityGuardedChip(EntityRef(EntityKind.student, item.studentId!, label: item.studentName)),
                          if (item.courseId != null)
                            EntityGuardedChip(EntityRef(EntityKind.course, item.courseId!, label: item.courseName ?? '')),
                        ])
                      else if (item.courseName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.courseName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: c.caption,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Request details ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.primary.withValues(alpha: 0.12)),
              ),
              child: Column(
                children: [
                  RequestInfoRow(
                    icon: Icons.phone_iphone_rounded,
                    label: 'new_device'.tr,
                    value: item.newDeviceName ?? 'unknown_value'.tr,
                  ),
                  if (item.studentPhone?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 10),
                    RequestInfoRow(
                      icon: Icons.phone_outlined,
                      label: 'student_phone_label'.tr,
                      value: item.studentPhone!,
                      copyable: true,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Monthly-limit note ──
            Container(
              key: const ValueKey('device_requests.limit_note'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: warn.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: warn.withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'device_monthly_limit_note'.tr,
                      style: c.caption,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            RequestActionButtons(key: const ValueKey('device_requests.actions'), ctl: ctl, approveLabel: 'request_approve'.tr),
          ],
        ),
      ),
    );
  }
}