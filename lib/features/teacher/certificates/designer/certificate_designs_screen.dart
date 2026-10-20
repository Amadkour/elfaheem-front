// features/teacher/certificates/designer/certificate_designs_screen.dart
//
// Library of certificate designs the user can use:
//   • their own designs (individual teachers),
//   • their organization's designs (university / faculty admins, admin assistants, teachers, TAs).
//
// Open it from the admin / organization dashboard (pass orgId) or from a course certificate
// (pass certificateId → every card gets a "Use" button that attaches the design to that certificate).
//
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => CertificateDesignsScreen(orgId: org.id)));

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:provider/provider.dart';

import '../../../../config/app_config.dart';
import '../../../../config/theme/theme_config_provider.dart';
import '../../../../core/api_client.dart';
import '../../../../core/base_provider.dart';
import 'certificate_design_models.dart';
import 'certificate_designer_screen.dart';

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
          queryParams: {if (orgId != null) 'org_id': orgId},
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

  Future<bool> attach(int certificateId, int designId) async {
    busyIds.add(designId);
    notifyListeners();
    final r = await run(() => _api.post('/api/v1/certificates/$certificateId/design', body: {'design_id': designId}));
    busyIds.remove(designId);
    notifyListeners();
    return r is Map<String, dynamic>;
  }
}

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
    await openCertificateDesigner(context, designId: designId, certificateId: certificateId, orgId: orgId);
    await p.load(orgId: orgId); // pick up what was created / renamed
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignsProvider>();
    final c = context.colors;

    Widget body;
    if (p.loading && p.items.isEmpty) {
      body = const Center(child: AppLoadingIndicator());
    } else if (p.items.isEmpty) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium_outlined, size: 52, color: c.textLight),
          const SizedBox(height: 12),
          Text('cert_no_designs'.tr, style: c.body),
        ]),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: () => p.load(orgId: orgId),
        child: GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 340,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
          ),
          itemCount: p.items.length,
          itemBuilder: (_, i) => _DesignCard(
            design: p.items[i],
            certificateId: certificateId,
            onOpen: () => _open(context, designId: p.items[i].id),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('cert_designs_title'.tr, style: c.h2.copyWith(fontSize: 16)), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('cert_new_design'.tr),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _DesignCard extends StatelessWidget {
  final CertDesign design;
  final int? certificateId;
  final VoidCallback onOpen;

  const _DesignCard({required this.design, required this.certificateId, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CertificateDesignsProvider>();
    final c = context.colors;
    final busy = p.busyIds.contains(design.id);

    return Container(
      decoration: BoxDecoration(color: c.cardBg, borderRadius: BorderRadius.circular(c.radiusMedium), boxShadow: c.cardShadow),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Container(
              color: Colors.grey.shade200,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              child: AspectRatio(
                aspectRatio: design.logicalW / design.logicalH,
                child: Container(
                  decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 6)]),
                  child: design.backgroundUrl == null
                      ? Icon(Icons.workspace_premium_outlined, color: c.textLight)
                      : Image.network(design.backgroundUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(design.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'tajawal', fontWeight: FontWeight.w800, fontSize: 13)),
                Text(
                  '${design.orgId != null ? 'cert_scope_org'.tr : 'cert_scope_personal'.tr} · ${'cert_orientation_${design.orientation}'.tr}',
                  style: c.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ]),
            ),
            if (busy)
              const SizedBox(width: 22, height: 22, child: AppLoadingIndicator())
            else if (design.canEdit)
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') {
                    onOpen();
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('cert_delete_design_title'.tr),
                        content: Text('cert_delete_design_body'.tr),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr)),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('delete'.tr)),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) await context.read<CertificateDesignsProvider>().delete(design.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'edit', child: Text('cert_edit_design'.tr)),
                  PopupMenuItem(value: 'delete', child: Text('delete'.tr)),
                ],
              ),
          ]),
        ),
        if (certificateId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final ok = await context.read<CertificateDesignsProvider>().attach(certificateId!, design.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text((ok ? 'cert_design_in_use' : 'certificate_action_failed').tr,
                              style: const TextStyle(fontFamily: 'bahji', color: Colors.white)),
                          backgroundColor: ok ? c.success : c.danger,
                          behavior: SnackBarBehavior.floating,
                        ));
                      },
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text('cert_use_design'.tr),
              ),
            ),
          ),
      ]),
    );
  }
}
