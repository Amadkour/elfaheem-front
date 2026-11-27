// lib/features/admin/governance/publish_queue_page.dart
//
// The course publish-review queue (docs/redesign/api/governance.md §1): courses teachers sent for publishing while
// the platform's "Review before publishing" is on. Three tabs (Waiting, Approved, Rejected); a waiting course is
// approved (it goes live) or rejected with a reason the teacher receives. The super admin turns the review on or off
// from the card on top. The list reloads on the `course_review` live event. Kill switch `admin.publish_queue`.
//
// PublishQueueCard is the plain-values row (tested by the layout harness).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:flutter_education_app/utils/live_events.dart';
import 'package:provider/provider.dart';

import '../adm_kit.dart' show admRole;
import '../approvals/admin_approvals_inbox.dart' show admAgeText;
import '../cfg_common.dart';
import '../sup/sup_kit.dart';
import 'gov_api.dart';

/// True when the signed-in person is the super admin (no provider above, e.g. a preview: false).
bool govIsSuper(BuildContext context) {
  try {
    return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.role == 'super-admin';
  } catch (_) {
    return false;
  }
}

/// Asks for the reason of a rejection; null when cancelled.
Future<String?> askRejectReason(BuildContext context, String courseName) async {
  final note = TextEditingController();
  String? error;
  final ok = await showAppSheet<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppSheetHeader('${'ow_pq_reject_title'.tr} «$courseName»', tone: AppTone.danger),
          AppField(
            key: const ValueKey('publish_queue.reason'),
            controller: note,
            label: 'ow_pq_reason'.tr,
            helper: 'ow_pq_reason_d'.tr,
            errorText: error,
            maxLines: 3,
            maxLength: 500,
            required: true,
          ),
          AppSpace.gapSm,
          AppButton.danger(
            label: 'ow_pq_reject'.tr,
            icon: Icons.block_rounded,
            onPressed: () {
              if (note.text.trim().length < 3) {
                setSheet(() => error = 'ow_pq_reason_short'.tr);
                return;
              }
              Navigator.pop(ctx, true);
            },
          ),
        ]),
      ),
    ),
  );
  final text = note.text.trim();
  WidgetsBinding.instance.addPostFrameCallback((_) => note.dispose());
  return ok == true ? text : null;
}

/// One course of the queue: cover glyph, name, teacher, age, the reason when rejected, and the two decisions while
/// it waits.
class PublishQueueCard extends StatelessWidget {
  const PublishQueueCard({
    super.key,
    required this.item,
    required this.now,
    this.onApprove,
    this.onReject,
    this.busy = false,
  });

  final PublishItem item;
  final DateTime now;
  final VoidCallback? onApprove, onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final pending = item.status == 'pending_review';
    final rejected = item.status == 'rejected';
    final at = pending ? item.submittedAt : item.decidedAt;
    final reason = (item.reason ?? '').trim();
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        AppTile(
          icon: Icons.menu_book_rounded,
          tone: pending ? context.colors.kit.warmTone : (rejected ? context.colors.kit.error : context.colors.kit.ok),
          title: item.name,
          subtitle: [if (item.teacherName.isNotEmpty) item.teacherName, if (at != null) admAgeText(at, now)].join('، '),
          trailing: AppStatusBadge(
            label: 'ow_pq_status_${item.status}'.tr,
            tone: pending ? AppTone.warning : (rejected ? AppTone.danger : AppTone.success),
            dense: true,
          ),
        ),
        if (rejected && reason.isNotEmpty) ...[
          AppSpace.gapXs,
          Text('${'ow_pq_reason_label'.tr}: $reason', style: AppType.meta(context), maxLines: 4, overflow: TextOverflow.ellipsis),
        ],
        if (pending && (onApprove != null || onReject != null)) ...[
          AppSpace.gapSm,
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, alignment: WrapAlignment.end, children: [
            if (onReject != null)
              AppButton.secondary(
                  label: 'ow_pq_reject'.tr, icon: Icons.block_rounded, size: AppButtonSize.sm, onPressed: busy ? null : onReject),
            if (onApprove != null)
              AppButton.primary(
                  label: 'ow_pq_approve'.tr,
                  icon: Icons.check_rounded,
                  size: AppButtonSize.sm,
                  busy: busy,
                  onPressed: busy ? null : onApprove),
          ]),
        ],
      ]),
    );
  }
}

class AdminPublishQueuePage extends StatefulWidget {
  const AdminPublishQueuePage({super.key});

  @override
  State<AdminPublishQueuePage> createState() => _AdminPublishQueuePageState();
}

class _AdminPublishQueuePageState extends State<AdminPublishQueuePage> {
  static const _statuses = ['pending_review', 'approved', 'rejected'];
  final _api = GovApi();
  int _tab = 0;
  PublishPage? _page;
  Object? _error;
  bool? _required;
  bool _savingSetting = false;
  int? _busyId;
  StreamSubscription<LiveEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = LiveEvents.instance.listen({kCourseReviewEvent}, (_) => _load());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await _api.queue(status: _statuses[_tab], size: 100);
      if (!mounted) return;
      setState(() {
        _page = p;
        _required = p.requireReview;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_page == null) {
        setState(() => _error = e);
      } else {
        showAppNotice(cfgErrorMessage(e), error: true);
      }
    }
  }

  Future<void> _setRequired(bool on) async {
    setState(() => _savingSetting = true);
    try {
      final v = await _api.setRequireReview(on);
      if (!mounted) return;
      setState(() => _required = v);
      showAppNotice(v ? 'ow_pq_on_notice'.tr : 'ow_pq_off_notice'.tr);
    } catch (e) {
      showAppNotice(cfgErrorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _savingSetting = false);
    }
  }

  Future<void> _decide(PublishItem it, bool approve) async {
    String? reason;
    if (!approve) {
      reason = await askRejectReason(context, it.name);
      if (reason == null || !mounted) return;
    }
    setState(() => _busyId = it.courseId);
    try {
      if (approve) {
        await _api.approve(it.courseId);
      } else {
        await _api.reject(it.courseId, reason!);
      }
      showAppNotice(approve ? 'ow_pq_approved_notice'.tr : 'ow_pq_rejected_notice'.tr);
      unawaited(AttentionService.instance.refresh());
      await _load();
    } catch (e) {
      showAppNotice(e is ApiException ? ApiException.from(e).message : cfgErrorMessage(e), error: true);
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _page;
    final now = DateTime.now().toUtc();
    final isSuper = govIsSuper(context);
    final waiting = _tab == 0 ? (p?.total ?? 0) : null;
    final children = <Widget>[
      if (isSuper && _required != null) ...[
        SupCard(
          title: 'ow_pq_setting'.tr,
          icon: Icons.fact_check_rounded,
          child: AppSwitchTile(
            key: const ValueKey('publish_queue.require'),
            title: 'ow_pq_require'.tr,
            subtitle: 'ow_pq_require_d'.tr,
            value: _required!,
            onChanged: _savingSetting ? null : _setRequired,
          ),
        ),
        AppSpace.gapMd,
      ],
      if (_required == false && _tab == 0) ...[
        AppCard(child: Text('ow_pq_off_line'.tr, style: AppType.meta(context))),
        AppSpace.gapMd,
      ],
      if (p == null)
        const AppListSkeleton(withAvatar: false)
      else if (p.items.isEmpty)
        AppEmpty(icon: Icons.fact_check_outlined, title: 'ow_pq_empty'.tr, message: 'ow_pq_empty_d'.tr)
      else
        for (var i = 0; i < p.items.length; i++) ...[
          if (i > 0) AppSpace.gapSm,
          PublishQueueCard(
            item: p.items[i],
            now: now,
            busy: _busyId == p.items[i].courseId,
            onApprove: () => _decide(p.items[i], true),
            onReject: () => _decide(p.items[i], false),
          ),
        ],
    ];
    return SupPage(
      pageKey: const ValueKey(kPublishQueueKey),
      role: admRole(context),
      title: 'ow_pq_title'.tr,
      kicker: 'ow_gov_kicker'.tr,
      headline: waiting == null
          ? 'ow_pq_head'.tr
          : waiting == 0
              ? 'ow_pq_head_clear'.tr
              : countText(waiting,
                  ar1: 'دورة واحدة تنتظر المراجعة',
                  ar2: 'دورتان تنتظران المراجعة',
                  arFew: '{n} دورات تنتظر المراجعة',
                  arMany: '{n} دورة تنتظر المراجعة',
                  en1: 'One course waits for review',
                  en: '{n} courses wait for review'),
      line: 'ow_pq_line'.tr,
      tabs: [
        AppTabItem('ow_pq_tab_waiting'.tr, count: waiting),
        AppTabItem('ow_pq_tab_approved'.tr),
        AppTabItem('ow_pq_tab_rejected'.tr),
      ],
      tab: _tab,
      onTab: (i) {
        if (i == _tab) return;
        setState(() {
          _tab = i;
          _page = null;
        });
        _load();
      },
      onRefresh: _load,
      helpPageId: 'admin.users',
      width: AppWidth.content,
      body: _error != null && p == null
          ? cfgErrorState(_error, onRetry: _load)
          : ListView(padding: SupPage.bodyPadding(context), children: children),
    );
  }
}
