// features/certificates/certificate_requests_screen.dart
//
// Teacher inbox: approve → the student gets the certificate automatically
// (email + in-app notification); reject → the student is notified.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/certificates/certificate_requests_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart' show deferredCertificateDesigns;
import 'package:flutter_education_app/features/analytics/analytics_summary.dart' show anStudentsWord;
import 'package:flutter_education_app/features/analytics/analytics_ui.dart' show anFmt;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_history.dart' show CertIssueHistoryPage;
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/core/entities/entity_ref.dart';
import 'package:flutter_education_app/design/master_detail/entity_chip.dart';
import 'package:flutter_education_app/design/master_detail/entity_panel_controller.dart';
import 'package:flutter_education_app/design/master_detail/master_detail_scaffold.dart';

class CertificateRequestsScreen extends StatelessWidget {
  const CertificateRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => CertificateRequestsProvider()..load(),
        child: const _View(),
      );
}

/// A request names a student of my course and that course: both open their connected detail in the shared panel
/// (D-290), the approve / reject buttons stay on the card.
class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _panel = EntityPanelController(rowKind: EntityKind.student);

  @override
  void dispose() {
    _panel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateRequestsProvider>();
    _panel.siblings = [
      for (final i in p.items) EntityRef(EntityKind.student, i.studentId, label: i.studentName, imageUrl: i.studentImageUrl),
    ];

    return Scaffold(
      appBar: AppHeader(title: 'certificate_requests'.tr),
      body: SafeArea(
        child: MasterDetailScaffold(
          controller: _panel,
          rootLabel: 'certificate_requests'.tr,
          list: T2Scope(
            child: CertificateRequestsBody(
              loading: p.loading,
              error: p.hasError ? (p.errorMessage ?? 'pl_requests_load_failed'.tr) : null,
              count: p.items.length,
              onRefresh: p.load,
              onDesigns: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => deferredCertificateDesigns())),
              onHistory: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CertIssueHistoryPage())),
              // the list's one orchestrated entrance: the first cards rise in once
              itemBuilder: (_, i) => AppReveal(index: i, group: 'cert.requests', child: _RequestCard(item: p.items[i])),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page body from plain values (loading · error · empty · list), so the layout harness can pump it: the
/// certificates hero ("3 students are waiting for their certificate", the count, the designs and the history), then
/// the requests riding up over it and one line on what approving does.
class CertificateRequestsBody extends StatelessWidget {
  const CertificateRequestsBody({
    super.key,
    required this.loading,
    required this.error,
    required this.count,
    required this.onRefresh,
    required this.itemBuilder,
    this.onDesigns,
    this.onHistory,
  });

  final bool loading;
  final String? error;
  final int count;
  final Future<void> Function() onRefresh;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onDesigns, onHistory;

  @override
  Widget build(BuildContext context) {
    final List<Widget> body;
    if (loading && count == 0) {
      body = [const AppListSkeleton()];
    } else if (error != null && count == 0) {
      // A failed first load used to show "no requests" — say it failed and offer a retry instead.
      body = [AppCard(child: ErrorRetry(message: error!, onRetry: () => onRefresh()))];
    } else if (count == 0) {
      body = [AppCard(child: AppEmpty(icon: Icons.mark_email_read_outlined, title: 'no_certificate_requests'.tr))];
    } else {
      body = [
        for (var i = 0; i < count; i++) Builder(builder: (context) => itemBuilder(context, i)),
        const _ApproveNote(),
      ];
    }
    final hero = AppHero(
      kicker: 't2_cert_kicker'.tr,
      title: count > 0 ? anFmt('t2_cert_waiting', {'students': anStudentsWord(count)}) : 'certificate_requests'.tr,
      subtitle: 't2_cert_sub'.tr,
      stats: count > 0 ? [AppHeroStat(value: '$count', label: 't2_cert_stat_waiting'.tr)] : const [],
      actions: [
        if (onDesigns != null)
          ParentComponent(
            featureKey: 'profile.certificate_designs',
            child: AppButton.secondary(label: 't2_cert_designs'.tr, icon: Icons.image_outlined, onPressed: onDesigns),
          ),
        if (onHistory != null)
          AppButton.secondary(label: 't2_cert_history'.tr, icon: Icons.history_rounded, onPressed: onHistory),
      ],
    );
    return AppRefresh(
      onRefresh: onRefresh,
      child: T2HeroScroll(width: AppWidth.reading, hero: hero, children: body),
    );
  }
}

/// "When you approve, the certificate reaches the student by email and in the app, and joins the log."
class _ApproveNote extends StatelessWidget {
  const _ApproveNote();

  @override
  Widget build(BuildContext context) {
    final t = context.colors.kit.primaryTone;
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(color: t.tint, borderRadius: BorderRadius.circular(AppRadius.tile)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: AppIconSize.md, color: t.ink),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text('t2_cert_note'.tr, style: AppType.label(context).copyWith(color: t.ink))),
      ]),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final CertificateRequestItem item;

  const _RequestCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    final p = context.read<CertificateRequestsProvider>();
    final busy = context.watch<CertificateRequestsProvider>().busyIds.contains(item.requestId);

    // the notice's tone follows the result (it always showed as an error before)
    void toast(String m, {bool error = false}) => showAppNotice(m, error: error);
    final done = item.progress >= 100;

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AppProgressRing(
            value: item.progress / 100,
            size: AppDashSize.avatarSm,
            tone: done ? c.kit.ok : c.kit.warn,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.studentName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
              if (item.createdAt != null)
                Text(anFmt('t2_cert_asked', {'date': AppTime.date(item.createdAt!)}), style: AppType.meta(context)),
              const SizedBox(height: AppSpace.xxs / 2),
              Row(children: [
                Icon(Icons.workspace_premium_rounded, size: AppIconSize.sm, color: c.textLight),
                const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: Text(item.certificateTitle, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: AppSpace.xs),
              Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, children: [
                EntityChip(
                    key: ValueKey('md.cert_request.student.${item.requestId}'),
                    EntityRef(EntityKind.student, item.studentId, label: item.studentName, imageUrl: item.studentImageUrl)),
                EntityChip(EntityRef(EntityKind.course, item.courseId, label: item.courseName(ar))),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        if ((item.note ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpace.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs),
            decoration: BoxDecoration(
              color: c.kit.well,
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(color: c.kit.line, width: AppBorder.strong),
            ),
            child: Text('“${item.note}”', style: AppType.body(context).copyWith(color: c.textDark)),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        // a phone stacks the two actions (approve first) so neither label is cut; a wider card puts them side by side
        LayoutBuilder(builder: (context, box) {
          final reject = AppButton.danger(
              dangerOutline: true,
              expand: true,
              icon: Icons.close_rounded,
              label: 'reject'.tr,
              onPressed: busy
                  ? null
                  : () async {
                      final reason = await _askReason(context);
                      if (reason == null) return;
                      final ok = await p.reject(item.requestId, reason: reason);
                      toast(ok ? 'certificate_request_rejected'.tr : 'certificate_action_failed'.tr, error: !ok);
                    },
            );
          final approve = AppButton.primary(
              expand: true,
              busy: busy,
              icon: Icons.send_rounded,
              label: 'approve_and_send'.tr,
              onPressed: () async {
                final ok = await p.approve(item.requestId);
                toast(ok ? 'certificate_request_approved'.tr : 'certificate_action_failed'.tr, error: !ok);
              },
            );
          if (box.maxWidth < 420) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [approve, const SizedBox(height: AppSpace.xs), reject]);
          }
          return Row(children: [Expanded(child: reject), const SizedBox(width: AppSpace.xs), Expanded(child: approve)]);
        }),
      ]),
    );
  }

  /// Returns the (possibly empty) reason, or null when the dialog was cancelled.
  Future<String?> _askReason(BuildContext context) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('reject_certificate_request'.tr),
        content: TextField(
          controller: controller,
          maxLines: 3,
          maxLength: 500,
          style: appFieldTextStyle(ctx),
          decoration: appFieldDecoration(ctx, hint: 'rejection_reason_optional'.tr),
        ),
        actions: [
          AppButton.ghost(label: 'cancel'.tr, onPressed: () => Navigator.pop(ctx, false)),
          AppButton.danger(label: 'reject'.tr, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    final text = controller.text;
    controller.dispose();
    return ok == true ? text : null;
  }
}
