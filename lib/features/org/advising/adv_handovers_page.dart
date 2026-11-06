// lib/features/org/advising/adv_handovers_page.dart — handovers (Phase 3, docs/advising/PHASE3.md "Handovers"): when
// a student changes advisor, the new advisor gets a summary of the case (open flags, active plans, open requests,
// notes, the last meetings) and acknowledges it. An advisor sees theirs; the director sees every handover.
//
//   AdvHandoversView   the list (plain values)      AdvHandoverCard   one handover
//   AdvHandoversPage   loads `GET …/handovers`, acknowledges with `POST …/handovers/{id}/ack`
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/plural.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/auth/auth_provider.dart' show MyAuthProvider;
import 'package:provider/provider.dart';

import '../../admin/admin_common.dart' show t;
import '../org_page_header.dart' show OrgPageRefresh, OrgPushedPage;
import '../org_page_kit.dart';
import '../org_v3.dart' show orgCall, orgErrorText;
import 'adv_api.dart';
import 'adv_models.dart';
import 'adv_parts.dart';

class AdvHandoverCard extends StatelessWidget {
  const AdvHandoverCard({super.key, required this.handover, this.onAck, this.busy = false});
  final AdvHandover handover;

  /// Shown to the receiving advisor while the handover is pending.
  final VoidCallback? onAck;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = handover;
    final sum = h.summary;
    final from = h.from;
    final route = from == null ? t('إلى ${h.to.shown}', 'To ${h.to.shown}') : t('من ${from.shown} إلى ${h.to.shown}', 'From ${from.shown} to ${h.to.shown}');
    final facts = <(IconData, String, bool)>[
      (Icons.flag_outlined, countText(sum.flagsOpen, ar0: 'لا تنبيهات مفتوحة', ar1: 'تنبيه مفتوح', ar2: 'تنبيهان مفتوحان', arFew: '${sum.flagsOpen} تنبيهات مفتوحة',
          arMany: '${sum.flagsOpen} تنبيهاً مفتوحاً', en0: 'No open flags', en1: '1 open flag', en: '${sum.flagsOpen} open flags'), sum.flagsOpen > 0),
      (Icons.route_outlined, countText(sum.plansActive, ar0: 'لا خطط نشطة', ar1: 'خطة نشطة', ar2: 'خطتان نشطتان', arFew: '${sum.plansActive} خطط نشطة',
          arMany: '${sum.plansActive} خطة نشطة', en0: 'No active plans', en1: '1 active plan', en: '${sum.plansActive} active plans'), sum.plansActive > 0),
      (Icons.assignment_outlined, countText(sum.requestsOpen, ar0: 'لا طلبات مفتوحة', ar1: 'طلب مفتوح', ar2: 'طلبان مفتوحان', arFew: '${sum.requestsOpen} طلبات مفتوحة',
          arMany: '${sum.requestsOpen} طلباً مفتوحاً', en0: 'No open requests', en1: '1 open request', en: '${sum.requestsOpen} open requests'), sum.requestsOpen > 0),
      (Icons.sticky_note_2_outlined, countText(sum.notes, ar0: 'لا ملاحظات', ar1: 'ملاحظة واحدة', ar2: 'ملاحظتان', arFew: '${sum.notes} ملاحظات',
          arMany: '${sum.notes} ملاحظة', en0: 'No notes', en1: '1 note', en: '${sum.notes} notes'), sum.notes > 0),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: AppCard(
        padding: AppSpace.card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, box) {
            final pill = h.pending
                ? AppBadgePill(t('بانتظار الاستلام', 'Pending'), color: c.warning, icon: Icons.hourglass_top_rounded)
                : AppBadgePill(t('استُلم', 'Received'), color: c.success, icon: Icons.check_rounded);
            // the pill at the end when there is room, else under the date
            final atEnd = box.maxWidth >= 360 * MediaQuery.textScalerOf(context).scale(1);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(child: AppAvatar(name: h.studentShown, size: 40)),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.studentShown, style: AppType.row(context).copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(route, style: AppType.meta(context), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (h.createdAt != null) Text(advDate(h.createdAt), style: AppType.meta(context)),
                  if (!atEnd) ...[const SizedBox(height: AppSpace.xxs), pill],
                ]),
              ),
              if (atEnd) ...[const SizedBox(width: AppSpace.xs), pill],
            ]);
          }),
          if (h.reason != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(advHandoverReasonLabel(h.reason!), style: AppType.body(context)),
          ],
          if (h.note != null) ...[
            const SizedBox(height: AppSpace.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ExcludeSemantics(child: Icon(Icons.format_quote_rounded, size: AppIconSize.md, color: c.primary)),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(h.note!,
                    textDirection: advTextDirection(h.note!), style: AppType.body(context).copyWith(color: c.textDark)),
              ),
            ]),
          ],
          const SizedBox(height: AppSpace.sm),
          Container(
            padding: const EdgeInsets.all(AppSpace.sm),
            decoration: BoxDecoration(color: c.inputBg, borderRadius: AppRadius.chipAll),
            child: sum.empty
                ? Row(children: [
                    Icon(Icons.inbox_outlined, size: AppIconSize.md, color: c.textMedium),
                    const SizedBox(width: AppSpace.xs),
                    Expanded(child: Text(t('لا سجلات إرشاد لهذا الطالب بعد.', 'No advising records for this student yet.'), style: AppType.meta(context))),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Wrap(spacing: AppSpace.md, runSpacing: AppSpace.xs, children: [
                      for (final (icon, text, on) in facts)
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(icon, size: AppIconSize.sm, color: on ? c.primary : c.textLight),
                          const SizedBox(width: AppSpace.xxs),
                          Flexible(child: Text(text, style: AppType.meta(context).copyWith(color: on ? c.textDark : null))),
                        ]),
                    ]),
                    if (sum.lastMeetings.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        t('آخر اللقاءات: ', 'Last meetings: ') +
                            [for (final (at, mode) in sum.lastMeetings) [if (at != null) advDate(at), if (mode.isNotEmpty) advMeetingModeLabel(mode)].join(' · ')].join(t('، ', ', ')),
                        style: AppType.meta(context),
                      ),
                    ],
                  ]),
          ),
          if (h.pending && onAck != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, AppTouch.min), shape: RoundedRectangleBorder(borderRadius: AppRadius.chipAll)),
                onPressed: busy ? null : onAck,
                icon: const Icon(Icons.done_rounded, size: AppIconSize.md),
                label: Text(t('استلمت الملف', 'Acknowledge')),
              ),
            ),
          ] else if (!h.pending && h.acknowledgedAt != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(t('استُلم ${advDate(h.acknowledgedAt)}', 'Received ${advDate(h.acknowledgedAt)}'), style: AppType.meta(context)),
          ],
        ]),
      ),
    );
  }
}

class AdvHandoversView extends StatelessWidget {
  const AdvHandoversView({
    super.key,
    required this.load,
    this.page,
    this.pendingOnly = true,
    this.me,
    this.acking = const {},
    this.errorText,
    this.onRetry,
    this.onPending,
    this.onPage,
    this.onAck,
  });

  final AdvLoad load;
  final AdvPage<AdvHandover>? page;
  final bool pendingOnly;

  /// My user id: Acknowledge is offered on handovers to me.
  final int? me;

  /// Handovers being acknowledged right now.
  final Set<int> acking;
  final String? errorText;
  final VoidCallback? onRetry;
  final ValueChanged<bool>? onPending;
  final ValueChanged<int>? onPage;
  final ValueChanged<AdvHandover>? onAck;

  @override
  Widget build(BuildContext context) {
    final p = page;
    Widget body;
    if (load != AdvLoad.ready || p == null) {
      body = AdvLoadState(state: load == AdvLoad.ready ? AdvLoad.loading : load, errorText: errorText, onRetry: onRetry, items: 3);
    } else if (p.items.isEmpty) {
      body = AppEmpty(
        icon: Icons.handshake_outlined,
        title: pendingOnly ? t('لا ملفات بانتظارك', 'Nothing waiting for you') : t('لا ملفات تسليم بعد', 'No handovers yet'),
        message: t('عندما ينتقل طالب إلى مرشد جديد، يصله ملخص حالته هنا.', 'When a student moves to a new advisor, a summary of their case arrives here.'),
      );
    } else {
      body = AdvPageFrame(children: [
        for (final h in p.items)
          AdvHandoverCard(
            handover: h,
            busy: acking.contains(h.id),
            onAck: onAck != null && me != null && h.to.userId == me ? () => onAck!(h) : null,
          ),
        if (p.pages > 1 && onPage != null) ...[
          const SizedBox(height: AppSpace.sm),
          AppPagination(page: p.page, pageCount: p.pages, total: p.total, pageSize: p.size, onPage: onPage!),
        ],
      ]);
    }
    return OrgPageBody(
      filter: onPending == null
          ? null
          : OrgFilterButton<bool>(
              value: pendingOnly,
              defaultValue: false,
              label: t('الحالة', 'Status'),
              options: {
                true: p != null && p.facets.containsKey('pending') ? '${t('بانتظار الاستلام', 'Pending')} · ${p.facet('pending')}' : t('بانتظار الاستلام', 'Pending'),
                false: t('الكل', 'All'),
              },
              onChanged: onPending!,
            ),
      child: body,
    );
  }
}

class AdvHandoversPage extends StatelessWidget {
  const AdvHandoversPage({super.key, required this.orgId, required this.manage});
  final int orgId;

  /// The director sees every handover; an advisor theirs.
  final bool manage;

  @override
  Widget build(BuildContext context) => OrgPushedPage(
        title: t('ملفات التسليم', 'Handovers'),
        helpPageId: 'org.advising',
        maxWidth: 1000,
        child: _AdvHandoversBody(orgId: orgId, manage: manage),
      );
}

class _AdvHandoversBody extends StatefulWidget {
  const _AdvHandoversBody({required this.orgId, required this.manage});
  final int orgId;
  final bool manage;

  @override
  State<_AdvHandoversBody> createState() => _AdvHandoversBodyState();
}

class _AdvHandoversBodyState extends State<_AdvHandoversBody> {
  late final AdvApi _api = AdvApi(widget.orgId);
  OrgPageRefresh? _refresh;
  AdvPage<AdvHandover>? _page;
  AdvLoad _load = AdvLoad.loading;
  String? _error;
  bool _pending = true;
  int _pageNo = 1;
  int _seq = 0;
  final Set<int> _acking = {};

  int? get _me {
    try {
      return Provider.of<MyAuthProvider>(context, listen: false).currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh = OrgPageRefresh.register(context, _reload);
    _reload();
  }

  @override
  void dispose() {
    _refresh?.unregister(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    final r = await orgCall(() => _api.handovers(mine: !widget.manage, pending: _pending, page: _pageNo), quiet: true);
    if (!mounted || seq != _seq) return;
    setState(() {
      if (r.ok) {
        _page = r.data as AdvPage<AdvHandover>;
        _load = AdvLoad.ready;
      } else {
        _load = r.endpointMissing ? AdvLoad.missing : AdvLoad.failed;
        _error = orgErrorText(r.error!);
      }
    });
    if (r.ok && mounted) OrgPageRefresh.reportUpdated(context);
  }

  void _query({bool? pending, int page = 1}) {
    setState(() {
      _pending = pending ?? _pending;
      _pageNo = page;
      _load = AdvLoad.loading;
    });
    _reload();
  }

  Future<void> _ack(AdvHandover h) async {
    setState(() => _acking.add(h.id));
    final r = await orgCall(() => _api.acknowledge(h.id), ok: t('استُلم ملف ${h.studentShown}', 'Handover of ${h.studentShown} acknowledged'));
    if (!mounted) return;
    setState(() {
      _acking.remove(h.id);
      final p = _page;
      if (r.ok && p != null) {
        final done = r.data as AdvHandover;
        // pending only: it leaves the list; all: it shows as received
        final items = _pending ? [for (final x in p.items) if (x.id != h.id) x] : [for (final x in p.items) x.id == h.id ? done : x];
        _page = AdvPage(items: items, total: _pending ? p.total - 1 : p.total, page: p.page, size: p.size, pages: p.pages, facets: p.facets);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AdvHandoversView(
        load: _load,
        page: _page,
        pendingOnly: _pending,
        me: _me,
        acking: _acking,
        errorText: _error,
        onRetry: () => _query(),
        onPending: (v) => _query(pending: v),
        onPage: (p) => _query(page: p),
        onAck: _ack,
      );
}
