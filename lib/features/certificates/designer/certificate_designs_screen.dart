// features/certificates/designer/certificate_designs_screen.dart
//
// Library of certificate designs the user can use:
//   • their own designs (individual teachers),
//   • their organization's designs (university / faculty admins, admin assistants, teachers, TAs).
// Each card shows the languages it issues in and whether it is THE default (used for every course without a design
// of its own); its menu duplicates a design or makes it the default (one default per owner / organization).
//
// Open it from the admin / organization dashboard (pass orgId) or from a course certificate
// (pass certificateId → every card gets a "Use" button that attaches the design to that certificate).
//
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => CertificateDesignsScreen(orgId: org.id)));

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/core/base_provider.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_design_models.dart';
import 'package:flutter_education_app/features/certificates/studio/cert_engine_studio.dart' show openCertificateStudio;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart'
    show AppAreaScope, AppButton, AppCard, AppEmpty, AppElevation, AppHero, AppHeroStat, AppListSkeleton, AppType, AppSpace,
        AppRadius, AppIconSize, AppBorder, AppTouch, appInk;
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppReveal, AppTilt;
import 'package:flutter_education_app/features/admin/admin_common.dart' show ErrorRetry;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_flow.dart' show openCertIssueFlow;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_history.dart' show CertIssueHistoryPage;
import 'package:flutter_education_app/features/certificates/issue/cert_issue_lists.dart' show CertSavedListsPage;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_logic.dart' show kCertVerifyFeature;
import 'package:flutter_education_app/features/certificates/issue/cert_verify_page.dart' show openCertVerify;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/features/profile/teacher/t2_frame.dart';

class CertificateDesignsProvider extends BaseProvider {
  final ApiClient _api;

  CertificateDesignsProvider({ApiClient? api}) : _api = api ?? ApiClient();

  List<CertDesign> items = [];
  bool loading = false;
  final Set<int> busyIds = {};

  Future<void> load({int? orgId}) async {
    loading = true;
    notifyListeners();
    final r = await run(() => _api.get(
          '/api/v1/certificate-designs',
          queryParams: {'org_id': ?orgId},
        ));
    if (r is List) {
      items = r.whereType<Map<String, dynamic>>().map(CertDesign.fromJson).toList();
    }
    loading = false;
    notifyListeners();
  }

  Future<bool> delete(int id) async {
    busyIds.add(id);
    notifyListeners();
    await run(() => _api.delete('/api/v1/certificate-designs/$id'));
    final ok = state == ProviderState.success;
    busyIds.remove(id);
    if (ok) items.removeWhere((d) => d.id == id);
    notifyListeners();
    return ok;
  }

  /// A full copy of [id] (my own, editable), added at the top.
  Future<CertDesign?> duplicate(int id) async {
    busyIds.add(id);
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificate-designs/$id/duplicate'));
    busyIds.remove(id);
    CertDesign? copy;
    if (r is Map<String, dynamic>) {
      copy = CertDesign.fromJson(r);
      items.insert(0, copy);
    }
    notifyListeners();
    return copy;
  }

  /// Makes [d] THE default of its scope (used for every course without its own design). The server clears the
  /// previous default of the same owner / organization; the list follows.
  Future<bool> setDefault(CertDesign d) async {
    busyIds.add(d.id);
    notifyListeners();
    final courses = (d.extra['course_ids'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ?? const <int>[];
    final r = await run(() => _api.put('/api/v1/certificate-designs/${d.id}/assignment',
        body: {'apply_all': true, 'course_ids': courses}));
    busyIds.remove(d.id);
    final ok = r is Map<String, dynamic>;
    if (ok) {
      items = [
        for (final x in items)
          x.id == d.id
              ? CertDesign.fromJson({...x.toJson(), 'apply_all': true})
              : (certSameDefaultScope(x, d) ? CertDesign.fromJson({...x.toJson(), 'apply_all': false}) : x),
      ];
    }
    notifyListeners();
    return ok;
  }

  Future<bool> attach(int certificateId, int designId) async {
    busyIds.add(designId);
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificates/$certificateId/design', body: {'design_id': designId}));
    busyIds.remove(designId);
    notifyListeners();
    return r is Map<String, dynamic>;
  }
}

/// Whether [a] and [b] share one default (the same organization, or the same owner's personal designs).
bool certSameDefaultScope(CertDesign a, CertDesign b) =>
    a.orgId != null ? a.orgId == b.orgId : (b.orgId == null && a.ownerId == b.ownerId);

/// THE default design of its scope (`apply_all`).
bool certIsDefault(CertDesign d) => d.extra['apply_all'] == true;

class CertificateDesignsScreen extends StatelessWidget {
  final int? orgId;
  final int? certificateId;

  const CertificateDesignsScreen({super.key, this.orgId, this.certificateId});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => CertificateDesignsProvider()..load(orgId: orgId),
        child: _View(orgId: orgId, certificateId: certificateId),
      );
}

class _View extends StatelessWidget {
  final int? orgId;
  final int? certificateId;

  const _View({this.orgId, this.certificateId});

  Future<void> _open(BuildContext context, {int? designId}) async {
    final p = context.read<CertificateDesignsProvider>();
    await openCertificateStudio(context, designId: designId, certificateId: certificateId, orgId: orgId);
    await p.load(orgId: orgId); // pick up what was created / renamed
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignsProvider>();
    final standalone = certificateId == null;
    final def = p.items.where(certIsDefault).firstOrNull ?? p.items.firstOrNull;

    final Widget designs;
    if (p.loading && p.items.isEmpty) {
      designs = const AppListSkeleton(withAvatar: false);
    } else if (p.hasError && p.items.isEmpty) {
      // A failed first load used to show "no designs yet" — say it failed and offer a retry instead.
      designs = ErrorRetry(message: p.errorMessage ?? 'pl_designs_load_failed'.tr, onRetry: () => p.load(orgId: orgId));
    } else if (p.items.isEmpty) {
      designs = AppEmpty(
        icon: Icons.workspace_premium_outlined,
        title: 'cert_no_designs'.tr,
        actionLabel: 'cert_new_design'.tr,
        onAction: () => _open(context),
      );
    } else {
      designs = T2TileGrid(
        maxColumns: 4,
        minTile: 240,
        children: [
          for (var i = 0; i < p.items.length; i++)
            // the page's one orchestrated entrance: the first cards rise in once
            AppReveal(
              index: i,
              group: 'cert.designs',
              child: _DesignCard(
                design: p.items[i],
                certificateId: certificateId,
                orgId: orgId,
                onOpen: () => _open(context, designId: p.items[i].id),
              ),
            ),
        ],
      );
    }

    // the shortcuts of the reference: issue, the history, the saved lists, verify (standalone issuing only)
    final shortcuts = <Widget>[
      if (def != null)
        ParentComponent(
          featureKey: 'certificates.standalone',
          child: T2InsightTile(
            icon: Icons.send_outlined,
            title: 'ci_issue_action'.tr,
            subtitle: 't2_certd_issue_sub'.tr,
            onTap: () => openCertIssueFlow(context, designId: def.id, designName: def.name, orgId: orgId),
          ),
        ),
      ParentComponent(
        featureKey: 'certificates.standalone',
        child: T2InsightTile(
          icon: Icons.history_rounded,
          tone: context.colors.kit.primaryTone,
          title: 'ci_history'.tr,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CertIssueHistoryPage(orgId: orgId))),
        ),
      ),
      ParentComponent(
        featureKey: 'certificates.standalone',
        child: T2InsightTile(
          icon: Icons.groups_2_outlined,
          tone: context.colors.kit.ok,
          title: 'ci_saved_lists'.tr,
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CertSavedListsPage(orgId: orgId))),
        ),
      ),
      ParentComponent(
        featureKey: kCertVerifyFeature,
        child: T2InsightTile(
          icon: Icons.shield_outlined,
          tone: context.colors.kit.warn,
          title: 'cv_entry_title'.tr,
          subtitle: 't2_certd_verify_sub'.tr,
          onTap: () => openCertVerify(context),
        ),
      ),
    ];

    return T2HeroPage(
      title: 'cert_designs_title'.tr,
      onRefresh: () => p.load(orgId: orgId),
      hero: AppHero(
        kicker: 't2_cert_kicker'.tr,
        title: 't2_certd_title'.tr,
        stats: p.items.isEmpty ? const [] : [AppHeroStat(value: '${p.items.length}', label: 't2_certd_stat'.tr)],
        actions: [
          if (standalone && def != null)
            ParentComponent(
              featureKey: 'certificates.standalone',
              child: AppButton.hot(
                label: 't2_certd_issue'.tr,
                icon: Icons.workspace_premium_outlined,
                onPressed: () => openCertIssueFlow(context, designId: def.id, designName: def.name, orgId: orgId),
              ),
            ),
          AppButton.secondary(label: 'cert_new_design'.tr, icon: Icons.add_rounded, onPressed: () => _open(context)),
        ],
      ),
      children: [
        if (standalone) T2TileGrid(maxColumns: 4, minTile: 200, children: shortcuts),
        AppCard(title: 't2_certd_mine'.tr, child: designs),
      ],
    );
  }
}

class _DesignCard extends StatelessWidget {
  final CertDesign design;
  final int? certificateId;
  final int? orgId;
  final VoidCallback onOpen;

  const _DesignCard({required this.design, required this.certificateId, required this.onOpen, this.orgId});

  /// The preview mat's height (the sheet is fitted inside it).
  static const double _previewH = 168;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignsProvider>();
    final c = context.colors;
    final busy = p.busyIds.contains(design.id);

    // a paper card on a warm hairline; the design sits on an input-well mat like a printed sheet on a desk, the one
    // thing that floats (and tilts a little under the pointer)
    final set = AppAreaScope.of(context);
    final isDefault = certIsDefault(design);
    return Container(
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        border: Border.all(
          color: isDefault ? Color.lerp(set.tint, set.a, .35)! : c.kit.line,
          width: isDefault ? AppBorder.focus : AppBorder.strong,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: _previewH,
          child: InkWell(
            onTap: onOpen,
            child: Container(
              color: c.kit.well,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(AppSpace.md),
              child: AppTilt.subtle(
                child: AspectRatio(
                  aspectRatio: design.logicalW / design.logicalH,
                  child: Container(
                    decoration: BoxDecoration(color: c.cardBg, boxShadow: AppElevation.of(context, 2)),
                    child: design.backgroundUrl == null
                        ? Icon(Icons.workspace_premium_outlined, color: c.textLight, size: AppIconSize.xl)
                        : Image.network(design.backgroundUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.textLight)),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.sm, AppSpace.xxs, AppSpace.xxs),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(design.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.tileTitle(context)),
                Text(
                  '${design.orgId != null ? 'cert_scope_org'.tr : 'cert_scope_personal'.tr} · ${'cert_orientation_${design.orientation}'.tr}',
                  style: AppType.meta(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpace.xs),
                Wrap(spacing: AppSpace.xxs, runSpacing: AppSpace.xxs, children: [
                  if (isDefault) _Chip(label: 'cert_default_badge'.tr, icon: Icons.star_rounded, strong: true),
                  for (final l in design.langs) _Chip(label: l == 'ar' ? 'certd_lang_ar'.tr : 'certd_lang_en'.tr),
                ]),
              ]),
            ),
            if (busy)
              const SizedBox(
                width: AppTouch.min,
                height: AppTouch.min,
                child: Center(child: SizedBox(width: AppIconSize.md, height: AppIconSize.md, child: AppLoadingIndicator())),
              )
            else if (design.canEdit)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    onOpen();
                  } else if (v == 'assign') {
                    await showDesignAssignment(context, design.id);
                  } else if (v == 'duplicate') {
                    final copy = await context.read<CertificateDesignsProvider>().duplicate(design.id);
                    showAppNotice((copy != null ? 'cert_duplicated' : 'certificate_action_failed').tr, error: copy == null);
                  } else if (v == 'default') {
                    final ok = await context.read<CertificateDesignsProvider>().setDefault(design);
                    showAppNotice((ok ? 'cert_default_set' : 'certificate_action_failed').tr, error: !ok);
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('cert_delete_design_title'.tr),
                        content: Text('cert_delete_design_body'.tr),
                        actions: [
                          AppButton.ghost(label: 'cancel'.tr, onPressed: () => Navigator.pop(ctx, false)),
                          AppButton.danger(label: 'delete'.tr, onPressed: () => Navigator.pop(ctx, true)),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) await context.read<CertificateDesignsProvider>().delete(design.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('cert_edit_design'.tr)),
                  PopupMenuItem(value: 'duplicate', child: Text('cert_duplicate_design'.tr)),
                  if (!certIsDefault(design)) PopupMenuItem(value: 'default', child: Text('cert_set_default'.tr)),
                  PopupMenuItem(value: 'assign', child: Text('cert_use_for_courses'.tr)),
                  PopupMenuItem(value: 'delete', child: Text('delete'.tr)),
                ],
              ),
          ]),
        ),
        // Issue certificates from this design: to a course's students or standalone (a list / a sheet)
        if (certificateId == null)
          ParentComponent(
            featureKey: 'certificates.standalone',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.sm),
              child: AppButton.secondary(
                expand: true,
                icon: Icons.workspace_premium_outlined,
                label: 'ci_issue_action'.tr,
                onPressed: busy
                    ? null
                    : () => openCertIssueFlow(context, designId: design.id, designName: design.name, orgId: orgId),
              ),
            ),
          ),
        if (certificateId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.sm, 0, AppSpace.sm, AppSpace.sm),
            child: AppButton.primary(
              expand: true,
              icon: Icons.check_rounded,
              label: 'cert_use_design'.tr,
              onPressed: busy
                  ? null
                  : () async {
                      final ok = await context.read<CertificateDesignsProvider>().attach(certificateId!, design.id);
                      if (!context.mounted) return;
                      // the notice's tone follows the result (it always showed as an error before)
                      showAppNotice((ok ? 'cert_design_in_use' : 'certificate_action_failed').tr, error: !ok);
                    },
            ),
          ),
      ]),
    );
  }
}


/// "Use this design for": all my courses, or chosen courses. When a certificate is issued without its own design,
/// the course's assigned design is used — otherwise the automatic premium landscape certificate.
Future<void> showDesignAssignment(BuildContext context, int designId) async {
  final api = ApiClient();
  List<Map<String, dynamic>> courses = const [];
  bool all = false;
  final picked = <int>{};
  try {
    final r = await api.get('/api/v1/certificate-designs/$designId/assignable-courses');
    courses = [for (final x in (r as Map)['items'] as List) Map<String, dynamic>.from(x as Map)];
    final d = await api.get('/api/v1/certificate-designs/$designId');
    all = (d as Map)['apply_all'] == true;
    picked.addAll(((d['course_ids'] as List?) ?? const []).map((e) => (e as num).toInt()));
  } catch (_) {}
  if (!context.mounted) return;
  await showAppModalSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final c = ctx.colors;
      return Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('cert_use_for_courses'.tr, style: AppType.pageTitle(ctx)),
          const SizedBox(height: AppSpace.xxs),
          Text('cert_use_for_courses_hint'.tr, style: AppType.meta(ctx)),
          AppSwitchTile(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            value: all,
            onChanged: (v) => set(() => all = v),
            title: 'cert_all_my_courses'.tr,
          ),
          if (!all)
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final co in courses)
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: picked.contains(co['id']),
                      onChanged: (on) => set(() => on == true ? picked.add(co['id'] as int) : picked.remove(co['id'])),
                      activeColor: c.primary,
                      title: Text('${co['title']}', style: AppType.row(ctx)),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: AppSpace.md),
          AppButton.primary(
            expand: true,
            label: 'save'.tr,
            onPressed: () async {
              try {
                await api.put('/api/v1/certificate-designs/$designId/assignment', body: {'apply_all': all, 'course_ids': picked.toList()});
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (_) {}
            },
          ),
        ]),
      );
    }),
  );
}

/// A small label on a design card (a language, "Default").
class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.strong = false});
  final String label;
  final IconData? icon;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ink = strong ? appInk(context, c.primary) : c.textMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs, vertical: AppSpace.xxs / 2),
      decoration: BoxDecoration(
        color: strong ? c.primaryTint : c.inputBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: AppIconSize.xs, color: ink), const SizedBox(width: AppSpace.xxs)],
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppType.overline(context).copyWith(color: strong ? ink : c.textDark)),
        ),
      ]),
    );
  }
}
