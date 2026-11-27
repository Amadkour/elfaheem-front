// features/courses/teacher/wizard/form_parts.dart — the small pieces of the course form (cover, group card, labeled
// field, type selector, collapsible section, footer, status card, certificate link), moved out of
// course_form_screen.dart unchanged.
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_education_app/config/app_config.dart';
import 'package:flutter_education_app/config/theme/theme_config_provider.dart';
import 'package:flutter_education_app/core/routing/deferred_screens.dart';
import 'package:flutter_education_app/design/app_image_cropper.dart';
import 'package:flutter_education_app/design/app_kit.dart';
import 'package:flutter_education_app/design/app_motion_kit.dart' show AppEase;
import 'package:flutter_education_app/design/app_notice.dart';
import 'package:flutter_education_app/design/app_switch.dart';
import 'package:flutter_education_app/features/courses/teacher/course_form_provider.dart';
import 'package:flutter_education_app/features/home/teacher/teacher_models.dart';
import 'package:flutter_education_app/utils/widget/app_loading_indicator.dart';
import 'package:flutter_education_app/utils/widget/editable_image.dart';
import 'package:flutter_education_app/utils/widget/parent_component.dart';
import 'package:flutter_education_app/utils/widget/text_field.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// The course's cover at the top of the form.
class CfCoverPicker extends StatelessWidget {
  final Uint8List? logoBytes;
  final XFile? logoFile;
  final String? imageUrl;
  final Future<void> Function(XFile file) onChange;
  final Future<void> Function()? onRemove;

  const CfCoverPicker({
    required this.logoBytes,
    required this.imageUrl,
    this.logoFile,
    required this.onChange,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: EditableImage(
        onChange: onChange,
        imageUrl: imageUrl,
        imageByte: logoBytes,
        imageFile: logoFile,
        size: context.height / 6,
        onRemove: onRemove,
        removeMessage: 'cover_remove_confirm'.tr,
      ),
    ),
  );
}
/// A group of the form on paper (the card surface on a warm hairline, no shadow): a quiet glyph and the group's name
/// in the editorial section face, then its fields.
class CfFormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const CfFormCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.cardBg,
      borderRadius: AppRadius.cardAll,
      border: Border.all(color: context.colors.divider, width: AppBorder.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
          child: CfGroupTitle(icon: icon, title: title),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}

/// A form group's heading: a quiet glyph in the medium ink and the name in the editorial section face.
class CfGroupTitle extends StatelessWidget {
  const CfGroupTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: AppSpace.xxs),
        child: Icon(icon, size: AppIconSize.md, color: context.colors.textMedium),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.section(context)),
            ),
            if (subtitle != null && subtitle!.isNotEmpty)
              Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.meta(context)),
          ],
        ),
      ),
    ],
  );
}
class EditCertificateTemplateCard extends StatefulWidget {
  final TeacherCourse course;

  const EditCertificateTemplateCard({required this.course});

  @override
  State<EditCertificateTemplateCard> createState() =>
      EditCertificateTemplateCardState();
}

class EditCertificateTemplateCardState
    extends State<EditCertificateTemplateCard> {
  late final TextEditingController _titleCtrl;
  String? _templateUrl;
  Uint8List? _pickedBytes;
  bool _uploading = false;

  CourseCertificate? get _existingCert => widget.course.certificates.isNotEmpty
      ? widget.course.certificates.first
      : null;

  @override
  void initState() {
    super.initState();
    _templateUrl = _existingCert?.templateUrl;
    _titleCtrl = TextEditingController(
      text: _existingCert?.title ?? 'default_certificate_title'.tr,
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    final img = await cropImageWithName(context, await file.readAsBytes(), file.name, allowBackground: false); // a certificate page, not a photo
    if (img == null) return;
    final bytes = img.bytes;
    setState(() {
      _pickedBytes = bytes;
      _uploading = true;
    });

    final provider = context.read<CourseFormProvider>();
    final url = await provider.updateCertificateTemplate(
      courseId: widget.course.id,
      existingCertificateId: _existingCert?.id,
      title: _titleCtrl.text.trim().isEmpty
          ? 'default_certificate_title'.tr
          : _titleCtrl.text.trim(),
      // what the person cropped and saw in the preview, not the file they first picked
      file: XFile.fromData(bytes, name: img.name, path: img.name),
    );

    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (url != null) {
        _templateUrl = url;
      } else {
        _pickedBytes = null;
      }
    });

    if (url == null && mounted) {
      showAppNotice('certificate_template_upload_failed'.tr, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = _existingCert != null;

    return CfFormCard(
      icon: Icons.workspace_premium_rounded,
      title: 'certificate_template_card_title'.tr,
      children: [
        Text(
          hasExisting
              ? 'certificate_template_card_hint_edit'.tr
              : 'certificate_template_card_hint'.tr,
          style: AppType.meta(context),
        ),
        const SizedBox(height: AppSpace.md),
        if (hasExisting)
          CfLabeledField(
            label: 'certificate_title_label'.tr,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: AppRadius.controlAll,
                border: Border.all(color: context.colors.divider, width: AppBorder.strong),
              ),
              child: Text(_existingCert!.title, style: AppType.bodyStrong(context)),
            ),
          )
        else
          CfLabeledField(
            label: 'certificate_title_label'.tr,
            child: MyTextField(
              controller: _titleCtrl,
              label: 'certificate_title_label'.tr,
            ),
          ),
        const SizedBox(height: AppSpace.md),
        // a real button (keyboard, screen reader), not a bare GestureDetector
        Semantics(
          button: true,
          label: (_templateUrl != null || _pickedBytes != null) ? 'change_template_btn'.tr : 'upload_template_btn'.tr,
          child: Material(
            color: context.colors.background,
            borderRadius: AppRadius.cardAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _uploading ? null : _pick,
              child: AspectRatio(
                aspectRatio: 1.6,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.cardAll,
                    border: Border.all(color: context.colors.divider, width: AppBorder.strong),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _uploading
                      ? const Center(child: AppLoadingIndicator())
                      : _pickedBytes != null
                          ? Image.memory(_pickedBytes!, fit: BoxFit.cover, excludeFromSemantics: true)
                          : _templateUrl != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.network(_templateUrl!, fit: BoxFit.cover, excludeFromSemantics: true,
                                        // a dead link shows the calm well, not Flutter's broken-image glyph
                                        errorBuilder: (_, _, _) => Center(child: Icon(Icons.image_not_supported_outlined, color: context.colors.textLight))),
                                    // the corner that reads first in either direction (was a fixed right: in RTL too)
                                    PositionedDirectional(
                                      bottom: AppSpace.xs,
                                      end: AppSpace.xs,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xxs),
                                        decoration: BoxDecoration(
                                          color: context.colors.textMedium,
                                          borderRadius: BorderRadius.circular(AppRadius.pill),
                                        ),
                                        child: Text(
                                          'change_template_btn'.tr,
                                          style: AppType.meta(context).copyWith(fontWeight: FontWeight.w700, color: context.colors.onHero),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add_photo_alternate_rounded, size: AppIconSize.xl - 4, color: context.colors.textLight),
                                      const SizedBox(height: AppSpace.xs),
                                      Text('upload_template_btn'.tr, style: AppType.label(context).copyWith(fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
/// A field with the kit's label above its well.
class CfLabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const CfLabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppFieldLabel(label),
      child,
    ],
  );
}
class CfCourseTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const CfCourseTypeSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => ParentComponent(
    featureKey: 'course_form.course_type',
    child: _buildContent(context),
  );

  /// One choice: solid emerald when chosen (the on-hero ink), a quiet well otherwise.
  Widget _choice(BuildContext context, String value, IconData icon, String label) {
    final c = context.colors;
    final on = selected == value;
    final motion = AppMotion.of(context);
    return Semantics(
      button: true,
      selected: on,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: AppEase.out,
        decoration: BoxDecoration(
          color: on ? c.primary : c.inputBg,
          borderRadius: AppRadius.controlAll,
          border: Border.all(color: on ? c.primary : c.divider, width: AppBorder.hairline),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.controlAll,
            onTap: () => onChanged(value),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTouch.primary),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm, horizontal: AppSpace.xxs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: AppIconSize.md, color: on ? c.onHero : c.textMedium),
                    const SizedBox(height: AppSpace.xxs),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: on ? c.onHero : c.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final items = <(String, IconData, String)>[
      ('live', Icons.sensors_rounded, 'cf_type_live'.tr),
      ('recorded', Icons.play_circle_outline_rounded, 'cf_type_recorded'.tr),
      ('both', Icons.all_inclusive_rounded, 'cf_type_both'.tr),
    ];
    final hint = switch (selected) {
      'live' => 'cf_hint_live'.tr,
      'both' => 'cf_hint_both'.tr,
      _ => 'cf_hint_recorded'.tr,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final (i, (value, icon, label)) in items.indexed) ...[
              if (i > 0) const SizedBox(width: AppSpace.xs),
              Expanded(child: _choice(context, value, icon, label)),
            ],
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(hint, style: AppType.meta(context)),
      ],
    );
  }
}
class CfCollapsibleSection extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const CfCollapsibleSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = AppMotion.of(context);
    return Material(
      color: c.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardAll,
        side: BorderSide(color: c.divider, width: AppBorder.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppTouch.primary),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(AppSpace.md, AppSpace.md, AppSpace.sm, AppSpace.md),
                  child: Row(
                    children: [
                      Expanded(child: CfGroupTitle(icon: icon, title: title, subtitle: subtitle)),
                      const SizedBox(width: AppSpace.xs),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: motion.base,
                        curve: AppEase.out,
                        child: Icon(Icons.keyboard_arrow_down_rounded, color: c.textMedium, size: AppIconSize.lg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // children stay mounted while folded, so their validators still run
          AnimatedSize(
            duration: motion.slow,
            curve: AppEase.out,
            alignment: Alignment.topCenter,
            child: Visibility(
              visible: expanded,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.md, 0, AppSpace.md, AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class CfStickyFooter extends StatelessWidget {
  final bool isEdit;
  final bool canSave;
  final bool isLoading;

  /// Edit mode: save edits. Create mode: publish immediately.
  final VoidCallback onSave;

  /// Create mode only: save the new course as a draft.
  final VoidCallback? onSaveDraft;

  final TeacherCourse? course;

  const CfStickyFooter({
    required this.isEdit,
    required this.canSave,
    required this.isLoading,
    required this.onSave,
    this.onSaveDraft,
    required this.course,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bottom = MediaQuery.of(context).padding.bottom;
    final showDraftBtn = !isEdit && onSaveDraft != null;
    final ready = canSave && !isLoading;

    // the bar sits on paper under a warm hairline (it is part of the page, not a floating layer)
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.sm + bottom),
      decoration: BoxDecoration(
        color: c.cardBg,
        border: Border(top: BorderSide(color: c.divider, width: AppBorder.hairline)),
      ),
      child: Row(
        children: [
          // Save as draft (create mode only)
          if (showDraftBtn) ...[
            Expanded(
              flex: 2,
              child: AppButton.secondary(
                label: 'save_as_draft_btn'.tr,
                size: AppButtonSize.lg,
                expand: true,
                onPressed: ready ? onSaveDraft : null,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
          ],

          // Primary save/publish button: while it cannot save it says why (the wider of the two)
          Expanded(
            flex: 3,
            child: AppButton.primary(
              label: canSave
                  ? (isEdit
                      ? 'btn_save_edits'.tr
                      : (showDraftBtn ? 'publish_course_btn'.tr : 'create_course_btn'.tr))
                  : (isEdit ? 'no_changes_to_save'.tr : 'enter_course_title_first'.tr),
              size: AppButtonSize.lg,
              expand: true,
              busy: isLoading,
              onPressed: ready ? onSave : null,
            ),
          ),
        ],
      ),
    );
  }
}
class CfStatusCard extends StatelessWidget {
  final bool isPublished;
  final bool isLoading;
  final VoidCallback onToggle;

  const CfStatusCard({
    required this.isPublished,
    required this.isLoading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CfFormCard(
      icon: Icons.visibility_rounded,
      title: 'course_status_title'.tr,
      children: [
        Row(
          children: [
            Flexible(
              child: AppStatusBadge(
                label: isPublished ? 'status_published'.tr : 'status_draft'.tr,
                tone: isPublished ? AppTone.success : AppTone.warning,
                dot: true,
              ),
            ),
            const Spacer(),
            if (isLoading)
              AppLoadingIndicator()
            else
              AppSwitch(
                value: isPublished,
                semanticLabel: 'status_published'.tr,
                onChanged: (_) => onToggle(),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          isPublished
              ? 'course_status_published_hint'.tr
              : 'course_status_draft_hint'.tr,
          style: AppType.meta(context),
        ),
      ],
    );
  }
}
class CfCertificateDesignsLink extends StatelessWidget {
  const CfCertificateDesignsLink();

  @override
  Widget build(BuildContext context) {
    return AppBlock(
      tone: AppBlockTone.gold,
      padding: AppSpace.card,
      semanticLabel: 'cert_designs_link_title'.tr,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => deferredCertificateDesigns())),
      child: Builder(builder: (context) {
        final b = AppBlock.colorsOf(context);
        return Row(children: [
          Container(
            width: AppTouch.min - AppSpace.xxs,
            height: AppTouch.min - AppSpace.xxs,
            decoration: BoxDecoration(color: Color.lerp(b.surface, b.ink, 0.06), borderRadius: AppRadius.chipAll),
            child: Icon(Icons.workspace_premium_rounded, color: b.accentInk(context.colors.accent2), size: AppIconSize.lg),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('cert_designs_link_title'.tr, style: AppType.bodyStrong(context).copyWith(color: b.ink)),
              Text('cert_designs_link_sub'.tr, style: AppType.meta(context).copyWith(color: b.muted)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: b.muted),
        ]);
      }),
    );
  }
}
