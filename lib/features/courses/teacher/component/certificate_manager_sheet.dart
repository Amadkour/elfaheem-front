// components/certificate_manager_sheet.dart
//
// Premium certificate manager — opened from the certificate row in
// CourseDetailsSection. Lets the teacher:
//   • upload a background template image for the certificate (or leave it
//     blank to use the generated "premium" template server-side)
//   • send the certificate to one student, or all actively-enrolled
//     students, by email (POST /certificates/{id}/issue[-all])
//
// Responsive: on wide (web) viewports it renders as a centered dialog card
// with the template preview and student list side-by-side; on narrow
// (mobile) viewports it renders as a full-height draggable bottom sheet
// with the same content stacked vertically.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_education_app/design/app_side_sheet.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/core/api_client.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/features/courses/teacher/component/certificate_manager_provider.dart';
import 'package:flutter_education_app/features/certificates/designer/certificate_designer_screen.dart';
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_kit.dart' show AppListSkeleton;
import 'package:flutter_education_app/core/display/app_fonts.dart';

/// Call this to open the manager. `certificateId`/`certificateTitle` come
/// from the course's CourseCertificate list; `templateUrl` may be null.
Future<void> showCertificateManagerSheet(
    BuildContext context, {
      required int courseId,
      required int certificateId,
      required String certificateTitle,
      String? templateUrl,
      int? orgId, // set when the course belongs to an organization (designs of the org are offered)
    }) {
  // the two-pane layout needs the wide panel; below that the template sits above the students
  final isWide = MediaQuery.sizeOf(context).width >= 1000;

  return showAppSideSheet<void>(
    context, mode: AppSheetMode.side,
    width: isWide ? 860 : 520,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => CertificateManagerProvider(),
      child: _CertificateManagerBody(
        courseId: courseId,
        certificateId: certificateId,
        certificateTitle: certificateTitle,
        initialTemplateUrl: templateUrl,
        orgId: orgId,
        isWide: isWide,
      ),
    ),
  );
}

class _CertificateManagerBody extends StatefulWidget {
  final int courseId;
  final int certificateId;
  final String certificateTitle;
  final String? initialTemplateUrl;
  final int? orgId;
  final bool isWide;

  const _CertificateManagerBody({
    required this.courseId,
    required this.certificateId,
    required this.certificateTitle,
    required this.initialTemplateUrl,
    required this.isWide,
    this.orgId,
  });

  @override
  State<_CertificateManagerBody> createState() => _CertificateManagerBodyState();
}

class _CertificateManagerBodyState extends State<_CertificateManagerBody> {
  String? _templateUrl;
  bool _templateLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDesign();
    _templateUrl = widget.initialTemplateUrl;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CertificateManagerProvider>().load(widget.courseId, widget.certificateId);
    });
  }

  Future<void> _pickTemplate() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null) return;
    setState(() => _templateLoading = true);
    final url = await context.read<CertificateManagerProvider>().uploadTemplate(
      widget.certificateId,
      file,
    );
    setState(() {
      _templateLoading = false;
      if (url != null) _templateUrl = url;
    });
  }

  Future<void> _removeTemplate() async {
    setState(() => _templateLoading = true);
    final ok = await context.read<CertificateManagerProvider>().removeTemplate(widget.certificateId);
    setState(() {
      _templateLoading = false;
      if (ok) _templateUrl = null;
    });
  }

  /// Opens the certificate designer for this certificate (new design wizard if none is attached yet).
  Future<void> _openDesigner() async {
    await openCertificateDesigner(context, certificateId: widget.certificateId, orgId: widget.orgId);
    await _loadDesign();   // show the design that is now attached
  }

  /// The design attached to this certificate (null = the default / uploaded template is used).
  Map<String, dynamic>? _design;

  Future<void> _loadDesign() async {
    try {
      final r = await ApiClient().get('/api/v1/certificates/${widget.certificateId}/design');
      if (mounted) setState(() => _design = r is Map ? Map<String, dynamic>.from(r) : null);
    } catch (_) {}
  }

  Future<void> _removeDesign() async {
    try {
      await ApiClient().put('/api/v1/certificates/${widget.certificateId}/design', body: {'design_id': null});
      if (mounted) setState(() => _design = null);
    } catch (_) {}
  }

  /// Pick one of the saved designs (own / organization) for this certificate.
  Future<void> _openDesignLibrary() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => deferredCertificateDesigns(orgId: widget.orgId, certificateId: widget.certificateId),
    ));
    await _loadDesign();
  }

  Future<void> _issueAll() async {
    final provider = context.read<CertificateManagerProvider>();
    final count = await provider.issueAll(widget.certificateId);
    if (!mounted) return;
    showAppNotice('${'certificates_sent_count'.tr} $count');
  }

  @override
  Widget build(BuildContext context) {
    return _Content(
      certificateId: widget.certificateId,
      certificateTitle: widget.certificateTitle,
      templateUrl: _templateUrl,
      templateLoading: _templateLoading,
      isWide: widget.isWide,
      onPickTemplate: _pickTemplate,
      onRemoveTemplate: _removeTemplate,
      onIssueAll: _issueAll,
      onOpenDesigner: _openDesigner,
      onOpenDesignLibrary: _openDesignLibrary,
      designName: _design?['name'] as String?,
      onRemoveDesign: _design == null ? null : _removeDesign,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared content — laid out as a row on wide screens, a column on mobile.
// ─────────────────────────────────────────────────────────────────────────────

class _Content extends StatelessWidget {
  final int certificateId;
  final String certificateTitle;
  final String? templateUrl;
  final bool templateLoading;
  final bool isWide;
  final VoidCallback onPickTemplate;
  final VoidCallback onRemoveTemplate;
  final VoidCallback onIssueAll;
  final VoidCallback onOpenDesigner;
  final String? designName;            // design in use (null → default template)
  final VoidCallback? onRemoveDesign;
  final VoidCallback onOpenDesignLibrary;

  const _Content({
    required this.certificateId,
    required this.certificateTitle,
    required this.templateUrl,
    required this.templateLoading,
    required this.isWide,
    required this.onPickTemplate,
    required this.onRemoveTemplate,
    required this.onIssueAll,
    required this.onOpenDesigner,
    this.designName,
    this.onRemoveDesign,
    required this.onOpenDesignLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final templatePane = ParentComponent(
        featureKey: 'certificates.template',
        child: _TemplatePane(
          certificateTitle: certificateTitle,
          templateUrl: templateUrl,
          isLoading: templateLoading,
          onPick: onPickTemplate,
          onRemove: onRemoveTemplate,
          onIssueAll: onIssueAll,
          onOpenDesigner: onOpenDesigner,
          designName: designName,
          onRemoveDesign: onRemoveDesign,
          onOpenDesignLibrary: onOpenDesignLibrary,
        ));
    final studentsPane = ParentComponent(
      featureKey: 'certificates.students',
      child: _StudentsPane(certificateId: certificateId),
    );

    return Column(
      children: [
        _Header(title: certificateTitle),
        Expanded(
          child: isWide
              ? Row(
            children: [
              SizedBox(width: 320, child: templatePane),
              VerticalDivider(width: 1, color: context.colors.heroShade.withValues(alpha: 0.06)),
              Expanded(child: studentsPane),
            ],
          )
              : Column(
            children: [
              templatePane,
              Divider(height: 1, color: context.colors.heroShade.withValues(alpha: 0.06)),
              Expanded(child: studentsPane),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header({required this.title});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 12, 14),
    decoration: BoxDecoration(gradient: context.colors.primaryGradient),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.colors.onHero.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.workspace_premium_rounded, color: context.colors.onHero, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'certificate_manager_title'.tr,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 12,
                  color: context.colors.onHeroMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 16,
                  color: context.colors.onHero,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'close'.tr,
          onPressed: () => Navigator.maybePop(context),
          icon: Icon(Icons.close_rounded, color: context.colors.onHero),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Template pane
// ─────────────────────────────────────────────────────────────────────────────

class _TemplatePane extends StatelessWidget {
  final String certificateTitle;
  final String? templateUrl;
  final bool isLoading;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback onIssueAll;
  final VoidCallback onOpenDesigner;
  final String? designName;            // design in use (null → default template)
  final VoidCallback? onRemoveDesign;
  final VoidCallback onOpenDesignLibrary;

  const _TemplatePane({
    required this.certificateTitle,
    required this.templateUrl,
    required this.isLoading,
    required this.onPick,
    required this.onRemove,
    required this.onIssueAll,
    required this.onOpenDesigner,
    this.designName,
    this.onRemoveDesign,
    required this.onOpenDesignLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CertificateManagerProvider>();
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'certificate_template_label'.tr,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textMedium,
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1.41, // A4 landscape-ish preview
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.divider, width: 1.2),
                color: templateUrl == null ? context.colors.accentTint : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: isLoading
                  ? const Center(child: AppLoadingIndicator())
                  : templateUrl != null
                  ? Image.network(templateUrl!, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: Icon(Icons.image_not_supported_outlined, color: context.colors.textLight)))
                  : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 28, color: context.colors.accent2),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'certificate_premium_template_hint'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          color: context.colors.heroEnd(context.colors.accent2, 0.45),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isLoading ? null : onPick,
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: Text(
                    templateUrl == null
                        ? 'upload_template_btn'.tr
                        : 'change_template_btn'.tr,
                    style: TextStyle(fontFamily: AppFonts.family, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.primary,
                    side: BorderSide(color: context.colors.primary.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (templateUrl != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isLoading ? null : onRemove,
                  icon: Icon(Icons.delete_outline_rounded, color: context.colors.danger),
                  tooltip: 'remove_template_btn'.tr,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Certificate designer: draft from the app theme + logo + signature, or your own template;
          // move / add / delete fields, fonts, sizes, colours, portrait or landscape.
          // Which design do students receive? Always visible — and changeable.
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
            decoration: BoxDecoration(
              color: (designName == null ? context.colors.textLight : context.colors.success).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: designName == null ? context.colors.divider : context.colors.success.withValues(alpha: 0.35)),
            ),
            child: Row(children: [
              Icon(designName == null ? Icons.description_outlined : Icons.verified_rounded,
                  size: 18, color: designName == null ? context.colors.textMedium : context.colors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  designName == null ? 'cert_default_template'.tr : '${'cert_current_design'.tr}: $designName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: AppFonts.family, fontSize: 12.5, fontWeight: FontWeight.w700, color: context.colors.textDark),
                ),
              ),
              if (onRemoveDesign != null)
                TextButton(
                  onPressed: onRemoveDesign,
                  child: Text('cert_remove_design'.tr,
                      style: TextStyle(fontFamily: AppFonts.family, fontSize: 12, color: context.colors.danger)),
                ),
            ]),
          ),
          ElevatedButton.icon(
            onPressed: onOpenDesigner,
            icon: const Icon(Icons.design_services_rounded, size: 16),
            label: Text((designName == null ? 'cert_design_certificate_btn' : 'cert_edit_design_btn').tr,
                style: TextStyle(fontFamily: AppFonts.family, fontSize: 12)),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
          ),
          TextButton.icon(
            onPressed: onOpenDesignLibrary,
            icon: const Icon(Icons.collections_bookmark_outlined, size: 16),
            label: Text('cert_choose_saved_design_btn'.tr, style: TextStyle(fontFamily: AppFonts.family, fontSize: 12)),
          ),
          const SizedBox(height: 18),
          Divider(color: context.colors.heroShade.withValues(alpha: 0.06)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: provider.issuingAll ? null : onIssueAll,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: context.colors.accentGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: context.colors.primaryShadow,
              ),
              child: Center(
                child: provider.issuingAll
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: AppLoadingIndicator(),
                )
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.send_rounded, size: 16, color: context.colors.onHero),
                    const SizedBox(width: 8),
                    Text(
                      'send_to_all_students_btn'.tr,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: context.colors.onHero,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Students pane
// ─────────────────────────────────────────────────────────────────────────────

class _StudentsPane extends StatelessWidget {
  final int certificateId;

  const _StudentsPane({required this.certificateId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CertificateManagerProvider>();

    if (provider.loadingStudents) {
      return const AppListSkeleton(items: 4);
    }

    if (provider.students.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline_rounded, size: 40, color: context.colors.textLight),
              const SizedBox(height: 12),
              Text(
                'no_enrolled_students_yet'.tr,
                style: context.colors.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: provider.students.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = provider.students[i];
        final issued = provider.isIssued(s.id);
        final sending = provider.issuingStudentId == s.id;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.colors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.colors.divider, width: 1),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: context.colors.primary.withValues(alpha: 0.12),
                backgroundImage: (s.imageUrl != null && s.imageUrl!.isNotEmpty)
                    ? NetworkImage(s.imageUrl!)
                    : null,
                child: (s.imageUrl == null || s.imageUrl!.isEmpty)
                    ? Text(
                  s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: context.colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.name,
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${s.progressPercentage.toStringAsFixed(0)}% ${'complete_label'.tr}',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize: 11,
                        color: context.colors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
              if (sending)
                const SizedBox(width: 18, height: 18, child: AppLoadingIndicator())
              else if (issued)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.colors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: context.colors.success),
                      const SizedBox(width: 4),
                      Text(
                        'certificate_sent_label'.tr,
                        style: TextStyle(
                          fontFamily: AppFonts.family,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.colors.success,
                        ),
                      ),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: () => provider.issueOne(certificateId, s.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: context.colors.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.send_rounded, size: 13, color: context.colors.onHero),
                        const SizedBox(width: 4),
                        Text(
                          'send_btn'.tr,
                          style: TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: context.colors.onHero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}