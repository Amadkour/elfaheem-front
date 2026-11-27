// lib/features/admin/approvals/admin_approvals_inbox.dart
//
// The requests inbox (redesign A1, the reference's AdmApprovals inbox): every queue that waits for an admin's
// decision in ONE list, oldest first, filtered by kind, searched by name. A row opens the page that decides it (the
// account approvals, the transfer review with its receipt, the device requests, the certificate requests, the
// parent link requests), and the inbox reloads when that page closes.
//
// Sources (each one on its own; a queue that fails or is switched off is left out, never the whole page):
//   GET /api/v1/admin/accounts/pending?status=pending              new accounts (teachers, parents)
//   TeacherTransfersProvider (GET /api/v1/payments/transfers/pending)   bank transfers and InstaPay receipts
//   TeacherDeviceRequestsProvider (GET /api/v1/devices/teacher/switch-requests)   device changes (all, for admins)
//   GET /api/v1/teacher/certificate-requests?status=pending         certificates (all, for admins)
//   GET /api/v1/admin/parent-link/requests?status=pending           parent ⇄ student links
//
//   GET /api/v1/admin/publish-queue?status=pending_review          courses waiting to be published (governance.md §1,
//                                                                   kill switch admin.publish_queue)
library;

import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/plural.dart' show countText;
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/features/certificates/certificate_requests_screen.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_provider.dart';
import 'package:flutter_education_app/features/payments/enrollment_request/teacher_transfers_screen.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_provider.dart';
import 'package:flutter_education_app/features/profile/teacher/switch_device_requests/teacher_device_requests_screen.dart';
import 'package:provider/provider.dart';

import '../adm_kit.dart';
import '../admin_account_approval.dart' show AdminPendingAccountsPage;
import '../admin_parent_requests_page.dart' show AdminParentRequestsPage;
import '../governance/gov_api.dart' show GovApi, kPublishQueueKey;
import '../governance/publish_queue_page.dart' show AdminPublishQueuePage;
import '../sup/sup_kit.dart';

/// The kinds of request the inbox gathers.
enum AdmRequestKind { account, transfer, device, certificate, parentLink, course }

/// One request of the inbox (plain values, so the list is testable without a server).
class AdmRequest {
  const AdmRequest({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.at,
    this.amount,
  });

  final AdmRequestKind kind;
  final String title;
  final String subtitle;
  final DateTime? at;

  /// Already formatted ("450 SAR"), transfers only.
  final String? amount;

  /// Older than three days: the tag on the row and the hero's figure.
  bool isOld(DateTime now) => at != null && now.difference(at!).inDays >= 3;
}

String admRequestKindLabel(AdmRequestKind k) => switch (k) {
      AdmRequestKind.account => 'a1_kind_account'.tr,
      AdmRequestKind.transfer => 'a1_kind_transfer'.tr,
      AdmRequestKind.device => 'a1_kind_device'.tr,
      AdmRequestKind.certificate => 'a1_kind_certificate'.tr,
      AdmRequestKind.parentLink => 'a1_kind_parent_link'.tr,
      AdmRequestKind.course => 'ow_kind_course'.tr,
    };

IconData admRequestKindIcon(AdmRequestKind k) => switch (k) {
      AdmRequestKind.account => Icons.person_add_alt_rounded,
      AdmRequestKind.transfer => Icons.receipt_long_rounded,
      AdmRequestKind.device => Icons.phonelink_setup_rounded,
      AdmRequestKind.certificate => Icons.workspace_premium_rounded,
      AdmRequestKind.parentLink => Icons.link_rounded,
      AdmRequestKind.course => Icons.menu_book_rounded,
    };

KitTone admRequestKindTone(BuildContext context, AdmRequestKind k) {
  final kit = context.colors.kit;
  return switch (k) {
    AdmRequestKind.account => kit.warmTone,
    AdmRequestKind.transfer => kit.accent(AppAccent.sky),
    AdmRequestKind.device => kit.accent(AppAccent.grape),
    AdmRequestKind.certificate => kit.ok,
    AdmRequestKind.parentLink => kit.accent(AppAccent.pink),
    AdmRequestKind.course => kit.accent(AppAccent.mint),
  };
}

/// "2 days ago" / "قبل يومين": the age of a request.
String admAgeText(DateTime? at, DateTime now) {
  if (at == null) return '';
  final d = now.difference(at);
  if (d.inDays >= 1) {
    return countText(d.inDays, ar1: 'قبل يوم', ar2: 'قبل يومين', arFew: 'قبل {n} أيام', arMany: 'قبل {n} يوم', en1: '1 day ago', en: '{n} days ago');
  }
  if (d.inHours >= 1) {
    return countText(d.inHours,
        ar1: 'قبل ساعة', ar2: 'قبل ساعتين', arFew: 'قبل {n} ساعات', arMany: 'قبل {n} ساعة', en1: '1 hour ago', en: '{n} hours ago');
  }
  return 'a1_just_now'.tr;
}

class AdminApprovalsInboxPage extends StatefulWidget {
  const AdminApprovalsInboxPage({super.key});

  @override
  State<AdminApprovalsInboxPage> createState() => _AdminApprovalsInboxPageState();
}

class _AdminApprovalsInboxPageState extends State<AdminApprovalsInboxPage> {
  List<AdmRequest> _accounts = const [], _certs = const [], _links = const [], _courses = const [];
  bool _loading = true;
  AdmRequestKind? _kind;
  String _q = '';
  bool _oldestFirst = true;

  @override
  void initState() {
    super.initState();
    // the shared queues notify while they load: never during this page's first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  static List<Map<String, dynamic>> _maps(dynamic v) {
    final list = v is Map ? v['items'] : v;
    if (list is! List) return const [];
    return [for (final e in list) if (e is Map) Map<String, dynamic>.from(e)];
  }

  static DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toUtc();

  Future<List<AdmRequest>> _try(Future<List<AdmRequest>> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _load() async {
    final api = ApiClient.instance;
    final transfers = context.read<TeacherTransfersProvider>();
    final devices = context.read<TeacherDeviceRequestsProvider>();
    final off = AppConfig.disableList;
    final results = await Future.wait([
      _try(() async => [
            for (final u in _maps(await api.get('/api/v1/admin/accounts/pending', queryParams: {'status': 'pending'})))
              AdmRequest(
                kind: AdmRequestKind.account,
                title: '${u['name'] ?? '#${u['id']}'}',
                subtitle: [_roleText('${u['role'] ?? ''}'), u['gmail'] ?? u['phone'] ?? ''].where((x) => '$x'.isNotEmpty).join('، '),
                at: _date(u['created_at']),
              ),
          ]),
      if (!off.contains('profile.certificate_requests'))
        _try(() async => [
              for (final r in _maps(await api.get('/api/v1/teacher/certificate-requests', queryParams: {'status': 'pending'})))
                AdmRequest(
                  kind: AdmRequestKind.certificate,
                  title: '${r['student_name'] ?? ''}',
                  subtitle: '${r['certificate_title'] ?? ''}',
                  at: _date(r['created_at']),
                ),
            ])
      else
        Future.value(const <AdmRequest>[]),
      _try(() async => [
            for (final r in _maps(await api.get('/api/v1/admin/parent-link/requests',
                queryParams: {'status': 'pending', 'page': 1, 'size': 20})))
              AdmRequest(
                kind: AdmRequestKind.parentLink,
                title: '${r['parent_name'] ?? ''} ← ${r['student_name'] ?? ''}',
                subtitle: 'pl_mode_${r['mode']}'.tr,
                at: _date(r['created_at']),
              ),
          ]),
      if (!off.contains('profile.enrollment_request')) _try(() async {
        await transfers.load();
        return const <AdmRequest>[];
      }) else Future.value(const <AdmRequest>[]),
      _try(() async {
        await devices.load();
        return const <AdmRequest>[];
      }),
      if (!off.contains(kPublishQueueKey))
        _try(() async => [
              for (final c in (await GovApi(api).queue(size: 50)).items)
                AdmRequest(kind: AdmRequestKind.course, title: c.name, subtitle: c.teacherName, at: c.submittedAt),
            ])
      else
        Future.value(const <AdmRequest>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _accounts = results[0];
      _certs = results[1];
      _links = results[2];
      _courses = results[5];
      _loading = false;
    });
  }

  String _roleText(String role) => switch (role) {
        'parent' => 'a1_role_parent'.tr,
        'student' => 'a1_role_student'.tr,
        _ => 'a1_role_teacher'.tr,
      };

  List<AdmRequest> _all(BuildContext context) {
    final transfers = context.watch<TeacherTransfersProvider>().items;
    final devices = context.watch<TeacherDeviceRequestsProvider>().items;
    return [
      ..._accounts,
      if (!AppConfig.disableList.contains('profile.enrollment_request'))
        for (final t in transfers)
          AdmRequest(
            kind: AdmRequestKind.transfer,
            title: '${t.studentName}، ${t.courseName}',
            subtitle: [t.senderName, t.transferReference ?? ''].where((x) => x.isNotEmpty).join('، '),
            at: t.submittedAt.toUtc(),
            amount: '${appCompactNumber(t.amount)} ${t.currency}',
          ),
      for (final d in devices)
        AdmRequest(
          kind: AdmRequestKind.device,
          title: d.studentName,
          subtitle: [d.courseName ?? '', d.newDeviceName ?? ''].where((x) => x.isNotEmpty).join('، '),
          at: _date(d.createdAt),
        ),
      ..._certs,
      ..._links,
      ..._courses,
    ];
  }

  Future<void> _open(AdmRequestKind k) async {
    final Widget page = switch (k) {
      AdmRequestKind.account => const AdminPendingAccountsPage(),
      AdmRequestKind.transfer => const TeacherTransfersScreen(),
      AdmRequestKind.device => const TeacherDeviceRequestsScreen(),
      AdmRequestKind.certificate => const CertificateRequestsScreen(),
      AdmRequestKind.parentLink => const AdminParentRequestsPage(),
      AdmRequestKind.course => const AdminPublishQueuePage(),
    };
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final all = _all(context);
    final counts = <AdmRequestKind, int>{for (final k in AdmRequestKind.values) k: all.where((r) => r.kind == k).length};
    final words = _q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final shown = [
      for (final r in all)
        if ((_kind == null || r.kind == _kind) && words.every('${r.title} ${r.subtitle}'.toLowerCase().contains)) r,
    ]..sort((a, b) {
        final x = a.at ?? now, y = b.at ?? now;
        return _oldestFirst ? x.compareTo(y) : y.compareTo(x);
      });
    final old = all.where((r) => r.isOld(now)).length;

    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        AppChip(
          label: 'a1_all'.tr,
          count: all.length,
          icon: Icons.inbox_rounded,
          selected: _kind == null,
          onTap: () => setState(() => _kind = null),
        ),
        for (final k in AdmRequestKind.values)
          if (counts[k]! > 0) ...[
            const SizedBox(width: AppSpace.xs),
            AppChip(
              label: admRequestKindLabel(k),
              count: counts[k],
              icon: admRequestKindIcon(k),
              selected: _kind == k,
              onTap: () => setState(() => _kind = _kind == k ? null : k),
            ),
          ],
      ]),
    );

    final list = <Widget>[
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          chips,
          AppSpace.gapSm,
          LayoutBuilder(builder: (context, box) {
            final search = AppSearchField(hint: 'a1_inbox_search'.tr, onChanged: (v) => setState(() => _q = v));
            final sort = AppButton.secondary(
              label: _oldestFirst ? 'a1_oldest_first'.tr : 'a1_newest_first'.tr,
              icon: Icons.swap_vert_rounded,
              size: AppButtonSize.sm,
              onPressed: () => setState(() => _oldestFirst = !_oldestFirst),
            );
            // the sort goes under the search on a narrow card
            if (box.maxWidth < AppWidth.form.max * .6) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                search,
                AppSpace.gapXs,
                Align(alignment: AlignmentDirectional.centerEnd, child: sort),
              ]);
            }
            return Row(children: [Expanded(child: search), AppSpace.gapSm, sort]);
          }),
          AppSpace.gapMd,
          if (_loading && all.isEmpty)
            const AppListSkeleton()
          else if (shown.isEmpty)
            AppEmpty(icon: Icons.inbox_outlined, title: 'a1_inbox_empty'.tr, message: 'a1_inbox_empty_d'.tr)
          else
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) AppSpace.gapSm,
              AdmQueueRow(
                icon: admRequestKindIcon(shown[i].kind),
                tone: admRequestKindTone(context, shown[i].kind),
                title: shown[i].title,
                subtitle: [admRequestKindLabel(shown[i].kind), if (shown[i].subtitle.isNotEmpty) shown[i].subtitle].join('، '),
                tag: shown[i].isOld(now) ? 'a1_older_3d'.tr : (shown[i].amount ?? admAgeText(shown[i].at, now)),
                tagTone: shown[i].isOld(now) ? AppTone.danger : AppTone.neutral,
                review: MediaQuery.sizeOf(context).width >= AppWidth.form.max,
                onTap: () => _open(shown[i].kind),
              ),
            ],
        ]),
      ),
    ];

    return SupPage(
      role: admRole(context),
      title: 'a1_group_approvals'.tr,
      kicker: 'a1_group_approvals'.tr,
      headline: all.isEmpty && !_loading
          ? 'a1_home_clear'.tr
          : countText(all.length,
              ar1: 'طلب واحد ينتظر قرارك',
              ar2: 'طلبين ينتظرون قرارك',
              arFew: '{n} طلبات تنتظر قرارك',
              arMany: '{n} طلب ينتظر قرارك',
              en1: 'One request waits for your decision',
              en: '{n} requests wait for your decision'),
      line: 'a1_hub_approvals_line'.tr,
      onRefresh: _load,
      helpPageId: 'admin.users',
      stats: [
        AppHeroStat(value: '${all.length}', label: 'a1_waiting_decision'.tr),
        AppHeroStat(value: '$old', label: 'a1_older_3d'.tr),
      ],
      width: AppWidth.content,
      body: ListView(padding: SupPage.bodyPadding(context), children: list),
    );
  }
}
