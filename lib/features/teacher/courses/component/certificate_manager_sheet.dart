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

import 'package:flutter/material.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../../config/theme/theme_config_provider.dart';
import '../../../../config/app_config.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'certificate_manager_provider.dart';

/// Call this to open the manager. `certificateId`/`certificateTitle` come
/// from the course's CourseCertificate list; `templateUrl` may be null.
Future<void> showCertificateManagerSheet(
    BuildContext context, {
      required int courseId,
      required int certificateId,
      required String certificateTitle,
      String? templateUrl,
    }) {
  final isWide = MediaQuery.of(context).size.width > 760;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => ChangeNotifierProvider(
      create: (_) => CertificateManagerProvider(),
      child: _CertificateManagerBody(
        courseId: courseId,
        certificateId: certificateId,
        certificateTitle: certificateTitle,
        initialTemplateUrl: templateUrl,
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
  final bool isWide;

  const _CertificateManagerBody({
    required this.courseId,
    required this.certificateId,
    required this.certificateTitle,
    required this.initialTemplateUrl,
    required this.isWide,
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

  Future<void> _issueAll() async {
    final provider = context.read<CertificateManagerProvider>();
    final count = await provider.issueAll(widget.certificateId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${'certificates_sent_count'.tr} $count',
          style: const TextStyle(fontFamily: 'bahji', color: Colors.white),
        ),
        backgroundColor: context.colors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _Content(
      certificateId: widget.certificateId,
      certificateTitle: widget.certificateTitle,
      templateUrl: _templateUrl,
      templateLoading: _templateLoading,
      isWide: widget.isWide,
      onPickTemplate: _pickTemplate,
      onRemoveTemplate: _removeTemplate,
      onIssueAll: _issueAll,
    );

    if (widget.isWide) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.cardBg,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 40),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
          ),
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.96,
      minChildSize: 0.6,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.colors.cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
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

  const _Content({
    required this.certificateId,
    required this.certificateTitle,
    required this.templateUrl,
    required this.templateLoading,
    required this.isWide,
    required this.onPickTemplate,
    required this.onRemoveTemplate,
    required this.onIssueAll,
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
              VerticalDivider(width: 1, color: Colors.black.withValues(alpha: 0.06)),
              Expanded(child: studentsPane),
            ],
          )
              : Column(
            children: [
              templatePane,
              Divider(height: 1, color: Colors.black.withValues(alpha: 0.06)),
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
    padding: const EdgeInsets.fromLTRB(20, 18, 12, 14),
    decoration: BoxDecoration(gradient: context.colors.primaryGradient),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'certificate_manager_title'.tr,
                style: const TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'tajawal',
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.close_rounded, color: Colors.white),
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

  const _TemplatePane({
    required this.certificateTitle,
    required this.templateUrl,
    required this.isLoading,
    required this.onPick,
    required this.onRemove,
    required this.onIssueAll,
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
              fontFamily: 'bahji',
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
                gradient: templateUrl == null
                    ? const LinearGradient(
                  colors: [Color(0xFFFDF8EF), Color(0xFFF3E9D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: isLoading
                  ? const Center(child: AppLoadingIndicator())
                  : templateUrl != null
                  ? Image.network(templateUrl!, fit: BoxFit.cover)
                  : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        size: 28, color: Color(0xFFC49A47)),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'certificate_premium_template_hint'.tr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: 'tajawal',
                          fontSize: 11,
                          color: Color(0xFF8A6D2E),
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
                    style: const TextStyle(fontFamily: 'tajawal', fontSize: 12),
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
          const SizedBox(height: 18),
          Divider(color: Colors.black.withValues(alpha: 0.06)),
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
                    const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'send_to_all_students_btn'.tr,
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
      return const Center(child: AppLoadingIndicator());
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
      separatorBuilder: (_, __) => const SizedBox(height: 8),
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
                      style: const TextStyle(
                        fontFamily: 'tajawal',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${s.progressPercentage.toStringAsFixed(0)}% ${'complete_label'.tr}',
                      style: TextStyle(
                        fontFamily: 'tajawal',
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
                          fontFamily: 'tajawal',
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
                        const Icon(Icons.send_rounded, size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'send_btn'.tr,
                          style: const TextStyle(
                            fontFamily: 'tajawal',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
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