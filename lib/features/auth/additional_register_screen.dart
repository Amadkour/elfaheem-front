// ─────────────────────────────────────────────────────────────────────────────
// features/auth/additional_register_screen.dart
// Teacher registration — Step 3: profile details + required documents
// ─────────────────────────────────────────────────────────────────────────────
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/features/auth/teacher_document_model.dart';
import 'package:flutter_education_app/features/auth/teacher_document_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import '../../utils/widget/primary_button.dart';
import 'auth_provider.dart';
import 'auth_shell.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';

class AdditionalRegisterScreen extends StatefulWidget {
  const AdditionalRegisterScreen({super.key, required this.email});

  final String email;

  @override
  State<AdditionalRegisterScreen> createState() =>
      _AdditionalRegisterScreenState();
}

class _AdditionalRegisterScreenState extends State<AdditionalRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _yearCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _payCtrl = ExpansibleController();
  final _specCtrl = ExpansibleController();
  final _teachCtrl = ExpansibleController();

  // Document uploads need an existing TeacherProfile server-side, which is
  // only created once step 1 (profile fields) is submitted. So this screen
  // runs in two phases even though it's a single scrollable page:
  //   phase 1: profile fields  -> completeTeacherProfile()
  //   phase 2: required + custom docs -> finalizeRegistration()
  bool _profileSubmitted = false;

  @override
  void dispose() {
    _yearCtrl.dispose();
    _bioCtrl.dispose();
    _payCtrl.dispose();
    _specCtrl.dispose();
    _teachCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitProfile({required String email}) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<MyAuthProvider>();
    final docProvider = context.read<TeacherDocumentProvider>();

    final success = await auth.completeTeacherProfile(
      experienceYears: int.parse(_yearCtrl.text.trim()),
      email: widget.email,
      bio: _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
    );

    if (!mounted) return;
    if (success) {
      setState(() => _profileSubmitted = true);
      // Profile now exists server-side, so the document endpoints will work.
      await docProvider.loadOverview(email);
    } else {
      Helpers.showMessage(
        auth.errorMessage ?? 'registration_failed'.tr,
        isError: true,
      );
    }
  }

  Future<void> _finishRegistration({required String email}) async {
    final docProvider = context.read<TeacherDocumentProvider>();
    final overview = docProvider.overview;

    // Hard block — no "skip for now". Required documents must be uploaded.
    if (overview != null && !overview.allRequiredFulfilled) {
      Helpers.showMessage('missing_docs_body'.tr, isError: true);
      return;
    }

    final ok = await docProvider.finalizeRegistration(email: email);
    if (!mounted) return;
    if (ok) {
      docProvider.clearCustomEntries();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (r) => false,
      );
    } else {
      // finalizeRegistration() already refreshed the overview, and its
      // errorMessage carries the server's "Missing required documents: ..."
      // detail when that's the cause.
      Helpers.showMessage(
        docProvider.errorMessage ?? 'registration_failed'.tr,
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MyAuthProvider, TeacherDocumentProvider>(
      builder: (context, auth, docs, _) {
        return AuthScaffold(
          title: 'register'.tr,
          pageKey: const ValueKey('additional_register'),
          maxWidth: 680,
          builder: (context, isWide) => _buildForm(auth, docs),
        );
      },
    );
  }

  Widget _buildForm(MyAuthProvider auth, TeacherDocumentProvider docs) {
    final c = context.colors;
    return Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProgressBar(currentStep: 2, totalSteps: 3),
            const SizedBox(height: 22),
            AuthHeader(
              title: 'complete_profile'.tr,
              subtitle: 'additional_registration_welcome'.tr,
            ),
            const SizedBox(height: 24),

            // ── Profile fields ──────────────────────────────────────────────
            IgnorePointer(
              ignoring: _profileSubmitted,
              child: Opacity(
                opacity: _profileSubmitted ? 0.5 : 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ParentComponent(featureKey: 'additional_register.experience', child: IconTextField(
                      controller: _yearCtrl,
                      label: 'experience'.tr,
                      icon: Icons.schedule_rounded,
                      keyboard: TextInputType.number,
                      // validator: (v) =>
                      // (v == null || v.isEmpty) ? 'field_required'.tr : null,
                    )),
                    const SizedBox(height: 20),

                    ParentComponent(featureKey: 'additional_register.specialization', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'specialization'.tr),
                      const SizedBox(height: 8),
                      auth.isLoading
                          ? const Center(
                        child: AppLoadingIndicator(),
                      )
                          : StyledDropdown(
                        icon: Icons.science_outlined,
                        label: 'specialization'.tr,
                        controller: _specCtrl,
                        initValue: auth.selectedSpecialization,
                        options: auth.specializations,
                        onChange: (i) =>
                            auth.onChangeSpecialization(i, _specCtrl),
                      ),
                      const SizedBox(height: 20)])),

                    ParentComponent(featureKey: 'additional_register.payment_method', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'payment_method'.tr),
                      const SizedBox(height: 8),
                      StyledDropdown(
                        icon: Icons.credit_card_outlined,
                        label: 'payment_method'.tr,
                        controller: _payCtrl,
                        initValue: auth.selectedPaymentType,
                        options: auth.paymentTypes,
                        onChange: (i) => auth.onChangePaymentMethod(i, _payCtrl),
                      ),
                      const SizedBox(height: 20)])),

                    ParentComponent(featureKey: 'additional_register.teaching_style', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'teaching_style'.tr),
                      const SizedBox(height: 8),
                      StyledDropdown(
                        icon: Icons.cast_for_education_outlined,
                        label: 'teaching_style'.tr,
                        controller: _teachCtrl,
                        initValue: auth.selectedTeachingType,
                        options: auth.teachingTypes,
                        onChange: (i) => auth.onChangeTeachingType(i, _teachCtrl),
                      ),
                      const SizedBox(height: 20)])),

                    ParentComponent(featureKey: 'additional_register.bio', child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [SectionLabel(label: 'bio_label'.tr),
                      const SizedBox(height: 8),
                      IconTextField(
                        controller: _bioCtrl,
                        label: 'bio_optional_hint'.tr,
                        icon: Icons.info_outline_rounded,
                      )])),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Documents section ─────────────────────────────────────────────
            // Only reachable once the profile row exists server-side, since
            // the upload endpoints 400 otherwise ("Complete your teacher
            // profile first").
            if (_profileSubmitted) ...[
              ParentComponent(featureKey: 'additional_register.documents', child: _DocumentsSection(provider: docs, email: widget.email)),
              const SizedBox(height: 32),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.inputBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 16,
                      color: c.textLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'finish_profile_to_unlock_docs'.tr,
                        style: c.caption.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],

            // ── Submit ──────────────────────────────────────────────────────
            PrimaryButton(
              isLoading: _profileSubmitted
                  ? docs.isFinalized
                  : auth.isLoadingAdditionalRegistration,
              label: _profileSubmitted
                  ? 'finish_registration'.tr
                  : 'continue'.tr,
              icon: _profileSubmitted
                  ? Icons.check_circle_outline_rounded
                  : Icons.arrow_forward_rounded,
              onPressed: _profileSubmitted
                  ? () => _finishRegistration(email: widget.email)
                  : () => _submitProfile(email: widget.email),
            ),
          ],
        ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  Documents Section
// ══════════════════════════════════════════════════════════════════════════════

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({required this.provider, required this.email});

  final String email;
  final TeacherDocumentProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overview = provider.overview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────────
        Row(
          children: [
            Container(
              width: 3,
              height: 20,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.folder_open_outlined, color: c.primary, size: 18),
            const SizedBox(width: 8),
            Text('required_documents'.tr, style: c.h3),
            const Spacer(),
            if (overview != null) ...[
              Text(
                '${overview.fulfilledRequiredCount}/${overview.requiredCount}',
                style: TextStyle(
                  fontFamily: 'bahji',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: overview.allRequiredFulfilled ? c.success : c.primary,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                overview.allRequiredFulfilled
                    ? Icons.check_circle_rounded
                    : Icons.pending_outlined,
                size: 16,
                color: overview.allRequiredFulfilled ? c.success : c.primary,
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'documents_section_hint'.tr,
          style: c.caption.copyWith(color: c.textLight),
        ),
        const SizedBox(height: 16),

        // ── Loading ───────────────────────────────────────────────────────────
        if (provider.isLoadingOverview)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: AppLoadingIndicator(),
            ),
          )
        // ── Predefined requirement rows ───────────────────────────────────────
        else if (overview != null) ...[
          ...overview.requirements.map(
                (req) => _RequirementRow(
              requirement: req,
              provider: provider,
              email: email,
            ),
          ),

          // ── Custom documents already uploaded ─────────────────────────────
          if (overview.customDocuments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...overview.customDocuments.map(
                  (doc) => _UploadedCustomDocRow(
                doc: doc,
                provider: provider,
                email: email,
              ),
            ),
          ],

          // ── In-progress custom entry forms ────────────────────────────────
          ...provider.customEntries.asMap().entries.map(
                (e) => _CustomDocEntryRow(
              index: e.key,
              provider: provider,
              email: email,
            ),
          ),

          // ── Add another document button ────────────────────────────────────
          const SizedBox(height: 12),
          ParentComponent(featureKey: 'additional_register.add_document', child: _AddAnotherButton(provider: provider)),
        ],
      ],
    );
  }
}

// ── Single predefined requirement row ────────────────────────────────────────

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({
    required this.requirement,
    required this.provider,
    required this.email,
  });

  final DocumentRequirementStatus requirement;
  final TeacherDocumentProvider provider;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = requirement.document;
    final fulfilled = requirement.isFulfilled;
    final uploading = provider.isUploadingFor('req_${requirement.typeId}');

    final statusColor = doc == null
        ? c.textLight
        : doc.isApproved
        ? c.success
        : doc.isRejected
        ? c.danger
        : c.primary;

    final statusIcon = doc == null
        ? Icons.upload_file_outlined
        : doc.isApproved
        ? Icons.check_circle_rounded
        : doc.isRejected
        ? Icons.cancel_rounded
        : Icons.access_time_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fulfilled
              ? statusColor.withValues(alpha: 0.35)
              : requirement.isRequired
              ? c.primary.withValues(alpha: 0.25)
              : c.divider,
          width: 1.5,
        ),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Main row ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Icon bubble
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (fulfilled ? statusColor : c.primary).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _materialIcon(requirement.iconName),
                    size: 20,
                    color: fulfilled ? statusColor : c.primary,
                  ),
                ),
                const SizedBox(width: 12),

                // Title + status
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              requirement.title,
                              style: c.bodyBold.copyWith(fontSize: 13),
                            ),
                          ),
                          if (requirement.isRequired)
                            Container(
                              margin: const EdgeInsetsDirectional.only(start: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: c.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                'required'.tr,
                                style: TextStyle(
                                  fontFamily: 'bahji',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: c.danger,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (requirement.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          requirement.description!,
                          style: c.caption.copyWith(fontSize: 11),
                        ),
                      ],
                      if (doc != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              _statusLabel(doc.status, context),
                              style: TextStyle(
                                fontFamily: 'bahji',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Action button
                const SizedBox(width: 8),
                uploading
                    ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: AppLoadingIndicator(),
                )
                    : _UploadButton(
                  fulfilled: fulfilled,
                  onPick: (src) => provider.pickAndUploadRequired(
                    requiredTypeId: requirement.typeId,
                    source: src,
                    email: email,
                  ),
                  onPickFile: () => provider.pickAndUploadRequiredFile(
                    requirement.typeId,
                    email: email,
                  ),
                  onDelete: doc != null
                      ? () =>
                      provider.deleteDocument(doc.id, email: email)
                      : null,
                ),
              ],
            ),
          ),

          // ── Thumbnail preview ────────────────────────────────────────────────
          if (doc != null && doc.isImage) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _DocThumbnail(url: doc.fileUrl, fileType: doc.fileType),
            ),
          ],
          if (doc != null && doc.isPdf) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _PdfChip(fileName: doc.fileName ?? 'document.pdf'),
            ),
          ],

          // ── Rejection reason ─────────────────────────────────────────────────
          if (doc?.isRejected == true && doc?.rejectionReason != null)
            Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: context.colors.danger,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      doc!.rejectionReason!,
                      style: TextStyle(
                        fontFamily: 'bahji',
                        fontSize: 11,
                        color: context.colors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(String status, BuildContext ctx) => switch (status) {
    'approved' => 'doc_approved'.tr,
    'rejected' => 'doc_rejected'.tr,
    _ => 'doc_pending'.tr,
  };
}

// ── Upload button (pick / replace / delete) ───────────────────────────────────

class _UploadButton extends StatelessWidget {
  const _UploadButton({
    required this.fulfilled,
    required this.onPick,
    required this.onPickFile,
    this.onDelete,
  });

  final bool fulfilled;
  final void Function(ImageSource) onPick;
  final VoidCallback onPickFile;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Upload / Replace
        GestureDetector(
          onTap: () => _showPicker(context),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: fulfilled ? c.primaryTint : c.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              fulfilled ? Icons.refresh_rounded : Icons.cloud_upload_outlined,
              size: 18,
              color: fulfilled ? c.primary : context.colors.onHero,
            ),
          ),
        ),

        // Delete
        if (onDelete != null) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: c.danger,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _showPicker(BuildContext context) {
    final c = context.colors;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gallery/camera don't make sense as separate concepts on
              // web — the browser file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: _iconBubble(
                    Icons.photo_library_outlined,
                    c.primary,
                    c.primaryTint,
                  ),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onPick(ImageSource.gallery);
                  },
                ),
              if (!kIsWeb)
                ListTile(
                  leading: _iconBubble(
                    Icons.camera_alt_outlined,
                    c.accent,
                    c.accentTint,
                  ),
                  title: Text(
                    'take_photo'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    onPick(ImageSource.camera);
                  },
                ),
              ListTile(
                leading: _iconBubble(
                  Icons.folder_open_outlined,
                  c.textLight,
                  c.inputBg,
                ),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onPickFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBubble(IconData icon, Color fg, Color bg) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: fg),
  );
}

// ── Already-uploaded custom doc row (from overview.customDocuments) ───────────

class _UploadedCustomDocRow extends StatelessWidget {
  const _UploadedCustomDocRow({
    required this.doc,
    required this.provider,
    required this.email,
  });

  final String email;
  final TeacherDocumentModel doc;
  final TeacherDocumentProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.accentTint, width: 1.5),
        boxShadow: c.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.accentTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.insert_drive_file_outlined,
              size: 20,
              color: c.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.title, style: c.bodyBold.copyWith(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  doc.isPdf ? 'pdf_doc'.tr : 'image_doc'.tr,
                  style: c.caption.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          if (doc.isImage)
            _DocThumbnail(url: doc.fileUrl, fileType: doc.fileType, size: 48),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => provider.deleteDocument(doc.id, email: email),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                size: 16,
                color: c.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── In-progress custom document form row ──────────────────────────────────────

class _CustomDocEntryRow extends StatelessWidget {
  const _CustomDocEntryRow({
    required this.index,
    required this.provider,
    required this.email,
  });

  final int index;
  final TeacherDocumentProvider provider;
  final String email;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final uploading = provider.isUploadingFor('custom_$index');
    final entry = provider.customEntries[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: c.accent.withValues(alpha: 0.35),
          width: 1.5,
          style: BorderStyle.solid,
        ),
        boxShadow: c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c.accentTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.post_add_outlined, size: 15, color: c.accent),
              ),
              const SizedBox(width: 8),
              Text(
                'additional_document'.tr,
                style: c.bodyBold.copyWith(fontSize: 13),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => provider.removeCustomEntry(index),
                child: Icon(Icons.close_rounded, size: 18, color: c.textLight),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title input
          Container(
            decoration: BoxDecoration(
              color: c.inputBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.divider),
            ),
            child: TextField(
              onChanged: (v) => provider.setCustomEntryTitle(index, v),
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                color: c.textDark,
              ),
              decoration: InputDecoration(
                hintText: 'document_title_hint'.tr,
                hintStyle: TextStyle(
                  fontFamily: 'bahji',
                  color: c.textLight,
                  fontSize: 13,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: InputBorder.none,
                prefixIcon: Icon(
                  Icons.label_outline_rounded,
                  size: 16,
                  color: c.textLight,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Upload button — active only when title typed
          AnimatedOpacity(
            opacity: entry.title.trim().isNotEmpty ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: entry.title.trim().isEmpty
                  ? null
                  : () => _showPicker(context, email: email),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  gradient: entry.title.trim().isNotEmpty
                      ? c.primaryGradient
                      : LinearGradient(colors: [c.divider, c.divider]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: uploading
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: AppLoadingIndicator(),
                  )
                      : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.upload_file_outlined,
                        size: 16,
                        color: context.colors.onHero,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'upload_document'.tr,
                        style: TextStyle(
                          fontFamily: 'bahji',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.colors.onHero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context, {required String email}) {
    final c = context.colors;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      backgroundColor: c.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: c.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Gallery doesn't make sense as a separate concept on web —
              // the browser file picker (below) already covers it.
              if (!kIsWeb)
                ListTile(
                  leading: Icon(Icons.photo_library_outlined, color: c.primary),
                  title: Text(
                    'pick_from_gallery'.tr,
                    style: TextStyle(
                      fontFamily: 'bahji',
                      fontWeight: FontWeight.w600,
                      color: c.textDark,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    provider.pickAndUploadCustom(index, email: email);
                  },
                ),
              ListTile(
                leading: Icon(Icons.folder_open_outlined, color: c.textLight),
                title: Text(
                  'browse_file_pdf_or_image'.tr,
                  style: TextStyle(
                    fontFamily: 'bahji',
                    fontWeight: FontWeight.w600,
                    color: c.textDark,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  provider.pickAndUploadCustomFile(index, email: email);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── + Add another document button ─────────────────────────────────────────────

class _AddAnotherButton extends StatelessWidget {
  const _AddAnotherButton({required this.provider});

  final TeacherDocumentProvider provider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: provider.addCustomEntry,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.primaryTint,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: c.primary.withValues(alpha: 0.3),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add_rounded, size: 16, color: c.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'add_another_document'.tr,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable thumbnail widget ─────────────────────────────────────────────────

class _DocThumbnail extends StatelessWidget {
  const _DocThumbnail({
    required this.url,
    required this.fileType,
    this.size = 72,
  });

  final String url;
  final String fileType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (fileType == 'pdf') return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _fullscreen(context),
      child: Hero(
        tag: url,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: size,
              height: size,
              color: c.inputBg,
              child: Icon(Icons.broken_image_outlined, color: c.textLight),
            ),
          ),
        ),
      ),
    );
  }

  void _fullscreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: context.colors.heroShade,
          appBar: AppBar(
            backgroundColor: context.colors.heroShade,
            iconTheme: IconThemeData(color: context.colors.onHero),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Hero(tag: url, child: Image.network(url)),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfChip extends StatelessWidget {
  const _PdfChip({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.picture_as_pdf_rounded, size: 16, color: c.danger),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              fileName,
              style: TextStyle(
                fontFamily: 'bahji',
                fontSize: 12,
                color: c.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Icon token → MaterialIconData mapper ─────────────────────────────────────

IconData _materialIcon(String token) => switch (token) {
  'description' => Icons.description_outlined,
  'badge' => Icons.badge_outlined,
  'school' => Icons.school_outlined,
  'account_balance' => Icons.account_balance_outlined,
  'work' => Icons.work_outline_rounded,
  'credit_card' => Icons.credit_card_outlined,
  'fingerprint' => Icons.fingerprint_rounded,
  'home' => Icons.home_outlined,
  'star' => Icons.star_outline_rounded,
  'verified' => Icons.verified_outlined,
  _ => Icons.insert_drive_file_outlined,
};
