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
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';

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
    final failedFirstLoad = !p.hasLoaded && !p.isLoading && p.errorMessage != null;
    final title = 'device_switch_requests'.tr;

    final List<Widget> body;
    if (!p.hasLoaded && !failedFirstLoad) {
      body = [const AppListSkeleton()];
    } else if (failedFirstLoad) {
      body = [
        AppCard(
          child: RequestStateView(
            icon: Icons.error_outline_rounded,
            color: c.danger,
            message: p.errorMessage ?? 'failed_to_load'.tr,
            actionLabel: 'retry'.tr,
            onAction: p.load,
          ),
        ),
      ];
    } else {
      body = [
        // the one rule of the page, once, above the requests (it was repeated on every card)
        _LimitNote(key: const ValueKey('device_requests.limit_note')),
        if (p.items.isEmpty)
          AppCard(child: AppEmpty(icon: Icons.phonelink_rounded, title: 'no_pending_requests'.tr))
        else ...[
          SwipeHintBanner(key: const ValueKey('device_requests.hint'), count: p.items.length),
          for (final item in p.items) _Card(key: ValueKey(item.id), item: item),
        ],
      ];
    }

    return T2HeroPage(
      pageKey: const ValueKey('device_requests'),
      title: title,
      width: AppWidth.reading,
      onRefresh: p.load,
      hero: AppHero(
        title: title,
        stats: p.hasLoaded ? [AppHeroStat(value: '${p.pendingCount}', label: 't2_dev_waiting'.tr)] : const [],
      ),
      children: body,
    );
  }
}

/// "You can approve one request per student a month": the info tint (the reference's lilac note).
class _LimitNote extends StatelessWidget {
  const _LimitNote({super.key});

  @override
  Widget build(BuildContext context) {
    final set = AppAreaScope.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: set.tint,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(color: Color.lerp(set.tint, set.a, .3)!, width: AppBorder.strong),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: set.ink),
        const SizedBox(width: AppSpace.sm),
        Expanded(child: Text('device_monthly_limit_note'.tr, style: AppType.body(context).copyWith(color: set.ink))),
      ]),
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
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong(context),
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
                        const SizedBox(height: AppSpace.xxs / 2),
                        Text(
                          item.courseName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.meta(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),

            // ── Request details: an inset well (the input tone), no tinted wash ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.sm),
              decoration: BoxDecoration(
                color: c.kit.well,
                borderRadius: BorderRadius.circular(AppRadius.tile),
                border: Border.all(color: c.kit.line, width: AppBorder.strong),
              ),
              child: Column(
                children: [
                  RequestInfoRow(
                    icon: Icons.phone_iphone_rounded,
                    label: 'new_device'.tr,
                    value: item.newDeviceName ?? 'unknown_value'.tr,
                  ),
                  if (item.studentPhone?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpace.xs),
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
            const SizedBox(height: AppSpace.xs),

            RequestActionButtons(key: const ValueKey('device_requests.actions'), ctl: ctl, approveLabel: 'request_approve'.tr),
          ],
        ),
      ),
    );
  }
}