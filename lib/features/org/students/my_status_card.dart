// lib/features/org/students/my_status_card.dart — the student's own status in an organization (student lifecycle
// contract §6.5, help id `me.status`).
//
//   MyStatusCard(orgId:, api:)   loads GET /api/v1/org/public/{org}/my-status and draws MyStatusView; draws nothing
//                                while loading, on any error, with the kill switch `org.students.status` off, or when
//                                the institution shows the student nothing (`student_sees`)
//   MyStatusCard.fromHome(orgId:, data:)   the same card from the `my_status[]` entry of GET /me/home
//                                (MeHome.myStatusOf): never a request of its own; null data = nothing drawn
//   MyStatusView(status:, onRequests:)   plain values (onRequests: the "My requests" pill → MyRequestsPage): enrolment · standing · the flags the student may see · the last change
//                                with its reason and decision number. Staff-only flags never reach it (MyStatus drops
//                                them again), and nothing here names a staff-only flag.
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/design/app_kit.dart';

import '../../admin/admin_common.dart' show t;
import 'my_requests.dart' show openMyRequests;
import 'student_status_models.dart';
import 'students_api.dart';
import 'students_models.dart';

/// The help page of the card (§12).
const kMyStatusHelpId = 'me.status';

class MyStatusCard extends StatefulWidget {
  const MyStatusCard({super.key, required this.orgId, this.api, this.padding = EdgeInsets.zero})
      : fromHome = false,
        data = null;

  /// From the home payload ([data] = `MeHome.myStatusOf(orgId)`): no request at all.
  const MyStatusCard.fromHome({super.key, required this.orgId, required this.data, this.padding = EdgeInsets.zero})
      : fromHome = true,
        api = null;
  final int orgId;

  /// The card reads [data] and never loads.
  final bool fromHome;
  final Map<String, dynamic>? data;

  /// Around the card only while it is drawn (no empty gap when there is nothing to show).
  final EdgeInsetsGeometry padding;

  /// For tests.
  final StudentsApi? api;

  @override
  State<MyStatusCard> createState() => _MyStatusCardState();
}

class _MyStatusCardState extends State<MyStatusCard> {
  MyStatus? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MyStatusCard old) {
    super.didUpdateWidget(old);
    if (widget.fromHome) {
      if (old.data != widget.data) _load();
      return;
    }
    if (old.orgId != widget.orgId) {
      _status = null;
      _load();
    }
  }

  Future<void> _load() async {
    if (AppConfig.disableList.contains(kStudentsStatusKey)) return;
    if (widget.fromHome) {
      final d = widget.data;
      if (mounted) setState(() => _status = d == null ? null : MyStatus.fromJson(d));
      return;
    }
    final r = await (widget.api ?? StudentsApi(widget.orgId)).myStatus();
    if (!mounted || !r.ok) return;
    setState(() => _status = MyStatus.fromJson(r.map));
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || s.isEmpty || AppConfig.disableList.contains(kStudentsStatusKey)) return const SizedBox.shrink();
    return Padding(padding: widget.padding, child: MyStatusView(status: s, onRequests: () => openMyRequests(context, widget.orgId)));
  }
}

/// The card over plain values (the layout harness pumps it).
class MyStatusView extends StatelessWidget {
  const MyStatusView({super.key, required this.status, this.onRequests});
  final MyStatus status;

  /// "My requests": ask for a change in the studies and follow the answers (MyRequestsPage); null = no pill.
  final VoidCallback? onRequests;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = status;
    final enrol = s.enrolStatus;
    final standing = s.acadStanding;
    final until = s.enrolUntil;
    final last = s.last;
    final flags = [for (final f in s.flags) if (!staffOnlyFlags.contains(f)) f];
    final enrolChip = enrol == null ? null : StudentChip('enrolment', enrol);
    return AppCard(
      key: const ValueKey('me.status.card'),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: AppIconSize.xl,
            height: AppIconSize.xl,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: appTintOn(context, c.primary)),
            child: Icon(Icons.badge_outlined, size: AppIconSize.md, color: appToneInk(context, AppTone.brand)),
          ),
          AppSpace.gapSm,
          Expanded(
            child: Semantics(
              header: true,
              child: Text(t('حالتي الدراسية', 'My study status'), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
          ),
        ]),
        AppSpace.gapSm,
        Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xxs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (enrolChip != null) AppStatusBadge(label: enrolChip.label, tone: enrolChip.tone, dot: true),
          if (standing != null) AppStatusBadge(label: standingLabel(standing), tone: chipTone(StudentChip('standing', standing))),
          for (final f in flags) AppStatusBadge(label: flagLabel(f), tone: flagTone(f), dense: true),
        ]),
        if (until != null && enrol != null && enrolPaused.contains(enrol)) ...[
          AppSpace.gapXs,
          Text(t('يعود قيدك في ${AppTime.wall(until)}', 'Your enrolment resumes on ${AppTime.wall(until)}'), style: AppType.body(context)),
        ],
        if (s.allWell && last == null) ...[
          AppSpace.gapXs,
          Text(t('قيدك سارٍ ولا يوجد ما يحتاج انتباهك.', 'Your enrolment is in force and nothing needs your attention.'),
              style: AppType.meta(context)),
        ],
        if (last != null) ...[
          AppSpace.gapSm,
          Divider(height: AppSpace.sm, color: c.divider),
          AppSpace.gapXs,
          Text(t('آخر تغيير', 'Last change'), style: AppType.meta(context)),
          const SizedBox(height: AppSpace.xxs),
          Text(last.title, style: AppType.bodyStrong(context)),
          if (last.reason != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(last.reason!, style: AppType.body(context)),
          ],
          if (last.decisionNo != null || last.at != null) ...[
            const SizedBox(height: AppSpace.xxs),
            Text(
              [
                if (last.decisionNo != null) t('قرار رقم ${last.decisionNo}', 'Decision no. ${last.decisionNo}'),
                if (last.at != null) AppTime.date(last.at!),
              ].join(' · '),
              style: AppType.meta(context),
            ),
          ],
        ],
        if (onRequests != null) ...[
          AppSpace.gapSm,
          AppPill(key: const ValueKey('me.status.requests'), label: t('طلباتي', 'My requests'), icon: Icons.assignment_rounded, onTap: onRequests),
        ],
      ]),
    );
  }
}
